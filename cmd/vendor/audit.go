package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// scanFinding records a single pattern match during static analysis.
type scanFinding struct {
	File     string
	Line     int
	Category string
	Pattern  string
	Content  string
}

// securityPatterns maps category names to lists of patterns to scan for.
// Organized by language/runtime.
var securityPatterns = []struct {
	Category string
	Pattern  string
}{
	// Rust - Network
	{"Network", "reqwest"},
	{"Network", "hyper"},
	{"Network", "std::net"},
	{"Network", "tokio::net"},
	// Rust - Filesystem
	{"Filesystem", "std::fs"},
	{"Filesystem", "dirs"},
	{"Filesystem", "home_dir"},
	// Rust - Environment
	{"Environment", "std::env::var"},
	{"Environment", "env!"},
	// Rust - Process
	{"Process", "std::process::Command"},
	// Go - Network
	{"Network", "net/http"},
	{"Network", "net.Dial"},
	// Go - Filesystem
	{"Filesystem", "os.Open"},
	{"Filesystem", "os.Create"},
	{"Filesystem", "os.ReadFile"},
	{"Filesystem", "os.WriteFile"},
	// Go - Environment
	{"Environment", "os.Getenv"},
	// Go - Process
	{"Process", "exec.Command"},
	// General
	{"Process", "eval("},
	{"Process", "subprocess"},
	{"Process", "system("},
	{"Process", "popen"},
}

type streamEvent struct {
	Type    string         `json:"type"`
	Message *streamMessage `json:"message,omitempty"`
	Result  string         `json:"result,omitempty"`
}

type streamMessage struct {
	Content []contentBlock `json:"content"`
}

type contentBlock struct {
	Type  string          `json:"type"`
	Text  string          `json:"text,omitempty"`
	Name  string          `json:"name,omitempty"`
	Input json.RawMessage `json:"input,omitempty"`
}

type auditReview struct {
	ToolCalls []string // human-readable log lines
	Text      string   // final assessment
}

func formatToolCall(name string, rawInput json.RawMessage) string {
	var input map[string]interface{}
	json.Unmarshal(rawInput, &input)
	switch name {
	case "Read":
		return fmt.Sprintf("Read %s", input["file_path"])
	case "Grep":
		s := fmt.Sprintf("Grep %q", input["pattern"])
		if p, ok := input["path"]; ok {
			s += fmt.Sprintf(" in %s", p)
		}
		return s
	case "Glob":
		return fmt.Sprintf("Glob %s", input["pattern"])
	case "Bash":
		cmd := fmt.Sprintf("%s", input["command"])
		if len(cmd) > 60 {
			cmd = cmd[:60] + "..."
		}
		return fmt.Sprintf("Bash %s", cmd)
	default:
		return name
	}
}

func cmdAudit(args []string) {
	fs := flag.NewFlagSet("audit", flag.ExitOnError)
	noClaude := fs.Bool("no-claude", false, "Skip AI review phase")
	fs.Parse(args)

	if fs.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "Usage: vendor audit <name> [--no-claude]\n")
		os.Exit(1)
	}
	name := fs.Arg(0)

	root, err := findDotfilesRoot()
	if err != nil {
		fatal(err)
	}

	manifest, err := LoadManifest(root)
	if err != nil {
		fatalf("failed to load manifest: %v", err)
	}

	entry, ok := manifest[name]
	if !ok {
		fatalf("unknown dependency: %s", name)
	}

	vendorDir := filepath.Join(root, "vendor", name)
	if _, err := os.Stat(vendorDir); os.IsNotExist(err) {
		fatalf("vendor/%s does not exist", name)
	}

	// ── Header ───────────────────────────────────────────────────────

	fmt.Printf("=== Vendor Audit: %s ===\n", name)
	fmt.Printf("Repository: %s\n", entry.Repo)
	fmt.Printf("Pinned: %s (ref: %s)\n", shortHash(entry.PinnedCommit), entry.Ref)
	fmt.Printf("Reviewed: %s by %s\n", entry.LastReviewed, entry.ReviewedBy)
	fmt.Println()

	// ── Phase 1: Static scan ──────────────────────────────────────────

	fmt.Println("Running static analysis...")
	findings := staticScan(vendorDir, entry.Audit)

	fmt.Println("--- Static Analysis ---")
	if len(findings) == 0 {
		fmt.Println("No security-relevant patterns found.")
	} else {
		for _, f := range findings {
			fmt.Printf("[%s] %s:%d - %s\n", f.Category, f.File, f.Line, f.Pattern)
			fmt.Printf("  > %s\n", f.Content)
		}
	}
	fmt.Println()

	directDeps, transitiveDeps := countDeps(vendorDir)
	if directDeps > 0 || transitiveDeps > 0 {
		fmt.Printf("Dependencies: %d direct, %d transitive\n", directDeps, transitiveDeps)
		fmt.Println()
	}

	cargoAuditOutput := runCargoAudit(vendorDir)
	fmt.Println("--- Cargo Audit ---")
	fmt.Println(cargoAuditOutput)
	fmt.Println()

	// ── Phase 2: Claude review ────────────────────────────────────────

	auditSummary := formatAuditSummary(name, entry, findings, directDeps, transitiveDeps, cargoAuditOutput)
	review := auditReview{Text: "skipped (--no-claude)"}
	if *noClaude {
		fmt.Println("Skipping AI review (--no-claude)")
	} else {
		fmt.Println("Running AI review...")
		fmt.Println("--- AI Review ---")
		review = runClaudeReview(root, vendorDir, auditSummary, true)
		fmt.Println()
	}

	// ── Save report ──────────────────────────────────────────────────

	report := buildReport(name, entry, findings, directDeps, transitiveDeps, cargoAuditOutput, review)

	auditsDir := filepath.Join(vendorDir, ".audits")
	if err := os.MkdirAll(auditsDir, 0755); err != nil {
		fatalf("failed to create .audits directory: %v", err)
	}

	timestamp := time.Now().Format("2006-01-02T15-04-05")
	reportFile := timestamp + ".txt"
	reportPath := filepath.Join(auditsDir, reportFile)
	if err := os.WriteFile(reportPath, []byte(report), 0644); err != nil {
		fatalf("failed to write audit report: %v", err)
	}

	latestLink := filepath.Join(auditsDir, "latest")
	os.Remove(latestLink) // remove old symlink if exists
	if err := os.Symlink(reportFile, latestLink); err != nil {
		fmt.Fprintf(os.Stderr, "warning: could not create latest symlink: %v\n", err)
	}

	fmt.Printf("Report saved to vendor/%s/.audits/%s\n", name, reportFile)
}

// staticScan walks the vendor directory searching for security-relevant patterns.
func staticScan(vendorDir string, audit AuditConfig) []scanFinding {
	var findings []scanFinding

	filepath.Walk(vendorDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			if info.Name() == ".git" {
				return filepath.SkipDir
			}
			return nil
		}

		relPath, _ := filepath.Rel(vendorDir, path)

		if !matchesAny(relPath, audit.WatchPatterns) {
			return nil
		}
		if matchesAny(relPath, audit.IgnorePatterns) {
			return nil
		}

		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()

		scanner := bufio.NewScanner(f)
		lineNum := 0
		for scanner.Scan() {
			lineNum++
			line := scanner.Text()
			for _, sp := range securityPatterns {
				if strings.Contains(line, sp.Pattern) {
					findings = append(findings, scanFinding{
						File:     relPath,
						Line:     lineNum,
						Category: sp.Category,
						Pattern:  sp.Pattern,
						Content:  strings.TrimSpace(line),
					})
				}
			}
		}
		return nil
	})

	return findings
}

// matchesAny returns true if relPath matches any of the given glob patterns.
// Patterns are matched against the full relative path and also against just
// the file name, to handle patterns like "*.rs".
func matchesAny(relPath string, patterns []string) bool {
	if len(patterns) == 0 {
		return false
	}
	baseName := filepath.Base(relPath)
	for _, pattern := range patterns {
		if matched, _ := filepath.Match(pattern, relPath); matched {
			return true
		}
		if matched, _ := filepath.Match(pattern, baseName); matched {
			return true
		}
	}
	return false
}

// countDeps parses Cargo.toml and Cargo.lock to count dependencies.
// Returns (direct, transitive). Returns (0, 0) if files don't exist.
func countDeps(vendorDir string) (int, int) {
	direct := countCargoTomlDeps(filepath.Join(vendorDir, "Cargo.toml"))
	transitive := countCargoLockPackages(filepath.Join(vendorDir, "Cargo.lock"))
	return direct, transitive
}

// countCargoTomlDeps counts entries under [dependencies] in Cargo.toml.
func countCargoTomlDeps(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()

	count := 0
	inDeps := false
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "[") {
			inDeps = line == "[dependencies]"
			continue
		}
		if inDeps && line != "" && !strings.HasPrefix(line, "#") {
			if strings.Contains(line, "=") {
				count++
			}
		}
	}
	return count
}

// countCargoLockPackages counts [[package]] entries in Cargo.lock.
func countCargoLockPackages(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()

	count := 0
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) == "[[package]]" {
			count++
		}
	}
	return count
}

// runCargoAudit runs `cargo audit` if cargo is on PATH and Cargo.toml exists.
func runCargoAudit(vendorDir string) string {
	if !fileExists(filepath.Join(vendorDir, "Cargo.toml")) {
		return "skipped (no Cargo.toml)"
	}
	cargoPath, err := exec.LookPath("cargo")
	if err != nil {
		return "skipped (cargo not found)"
	}
	// Check if cargo-audit subcommand is available.
	cmd := exec.Command(cargoPath, "audit")
	cmd.Dir = vendorDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		// cargo audit may exit non-zero if vulnerabilities found; still show output.
		if len(out) > 0 {
			return strings.TrimSpace(string(out))
		}
		return fmt.Sprintf("error: %v", err)
	}
	return strings.TrimSpace(string(out))
}

// formatAuditSummary creates a text summary of Phase 1 findings for Claude.
func formatAuditSummary(name string, entry ManifestEntry, findings []scanFinding, direct, transitive int, cargoAudit string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Dependency: %s\n", name)
	fmt.Fprintf(&b, "Repository: %s\n", entry.Repo)
	fmt.Fprintf(&b, "Pinned commit: %s (ref: %s)\n\n", entry.PinnedCommit, entry.Ref)

	fmt.Fprintf(&b, "Static Analysis Findings (%d total):\n\n", len(findings))
	for _, f := range findings {
		fmt.Fprintf(&b, "[%s] %s:%d - %s\n", f.Category, f.File, f.Line, f.Pattern)
		fmt.Fprintf(&b, "  > %s\n\n", f.Content)
	}

	if direct > 0 || transitive > 0 {
		fmt.Fprintf(&b, "Dependencies: %d direct, %d transitive\n\n", direct, transitive)
	}

	fmt.Fprintf(&b, "Cargo Audit:\n%s\n", cargoAudit)
	return b.String()
}

// runClaudeReview shells out to the claude CLI for AI review.
// When stream is true, tool call summaries are printed to stderr as they happen.
func runClaudeReview(root, vendorDir, auditSummary string, stream bool) auditReview {
	promptPath := filepath.Join(root, "vendor", "audit-prompt.md")
	promptData, err := os.ReadFile(promptPath)
	if err != nil {
		return auditReview{Text: fmt.Sprintf("skipped (cannot read audit-prompt.md: %v)", err)}
	}

	claudePath, err := exec.LookPath("claude")
	if err != nil {
		return auditReview{Text: "skipped (claude not found)"}
	}

	tmpFile, err := os.CreateTemp("", "vendor-audit-*.txt")
	if err != nil {
		return auditReview{Text: fmt.Sprintf("skipped (cannot create temp file: %v)", err)}
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(auditSummary); err != nil {
		tmpFile.Close()
		return auditReview{Text: fmt.Sprintf("skipped (cannot write temp file: %v)", err)}
	}
	tmpFile.Close()

	input, err := os.Open(tmpFile.Name())
	if err != nil {
		return auditReview{Text: fmt.Sprintf("skipped (cannot open temp file: %v)", err)}
	}
	defer input.Close()

	cmd := exec.Command("env", "-u", "CLAUDECODE", claudePath, "-p",
		"--verbose", "--output-format", "stream-json",
		"--allowedTools", "Read,Grep,Glob,Bash(read-only)",
		"--add-dir", vendorDir,
		"--system-prompt", string(promptData))
	cmd.Stdin = input
	cmd.Stderr = os.Stderr

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return auditReview{Text: fmt.Sprintf("error: %v", err)}
	}

	if err := cmd.Start(); err != nil {
		return auditReview{Text: fmt.Sprintf("error: %v", err)}
	}

	var review auditReview
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		var ev streamEvent
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			continue
		}
		switch ev.Type {
		case "assistant":
			if ev.Message == nil {
				continue
			}
			for _, block := range ev.Message.Content {
				if block.Type == "tool_use" {
					summary := formatToolCall(block.Name, block.Input)
					review.ToolCalls = append(review.ToolCalls, summary)
					if stream {
						fmt.Fprintf(os.Stderr, "  → %s\n", summary)
					}
				}
			}
		case "result":
			review.Text = ev.Result
		}
	}

	if err := cmd.Wait(); err != nil {
		if review.Text == "" {
			review.Text = fmt.Sprintf("error: %v", err)
		}
	}

	return review
}

// runClaudeDiffAudit sends a diff to Claude for security review.
// Used by the update command to assess changes before approval.
func runClaudeDiffAudit(root, name, diff string) auditReview {
	summary := fmt.Sprintf("Dependency: %s\nReview the following diff for security-relevant changes:\n\n%s", name, diff)
	vendorDir := filepath.Join(root, "vendor", name)
	return runClaudeReview(root, vendorDir, summary, false)
}

// buildReport constructs the final audit report string.
func buildReport(name string, entry ManifestEntry, findings []scanFinding, direct, transitive int, cargoAudit string, review auditReview) string {
	var b strings.Builder

	fmt.Fprintf(&b, "=== Vendor Audit: %s ===\n", name)
	fmt.Fprintf(&b, "Repository: %s\n", entry.Repo)
	fmt.Fprintf(&b, "Pinned: %s (ref: %s)\n", shortHash(entry.PinnedCommit), entry.Ref)
	fmt.Fprintf(&b, "Reviewed: %s by %s\n", entry.LastReviewed, entry.ReviewedBy)
	fmt.Fprintln(&b)

	fmt.Fprintln(&b, "--- Static Analysis ---")
	if len(findings) == 0 {
		fmt.Fprintln(&b, "No security-relevant patterns found.")
	} else {
		for _, f := range findings {
			fmt.Fprintf(&b, "[%s] %s:%d - %s\n", f.Category, f.File, f.Line, f.Pattern)
			fmt.Fprintf(&b, "  > %s\n", f.Content)
		}
	}
	fmt.Fprintln(&b)

	if direct > 0 || transitive > 0 {
		fmt.Fprintf(&b, "Dependencies: %d direct, %d transitive\n", direct, transitive)
		fmt.Fprintln(&b)
	}

	fmt.Fprintln(&b, "--- Cargo Audit ---")
	fmt.Fprintln(&b, cargoAudit)
	fmt.Fprintln(&b)

	fmt.Fprintln(&b, "--- AI Review ---")
	if len(review.ToolCalls) > 0 {
		fmt.Fprintln(&b, "Investigation:")
		for _, tc := range review.ToolCalls {
			fmt.Fprintf(&b, "  → %s\n", tc)
		}
		fmt.Fprintln(&b)
	}
	fmt.Fprintln(&b, review.Text)
	fmt.Fprintln(&b)

	return b.String()
}
