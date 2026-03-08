package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "add":
		cmdAdd(os.Args[2:])
	case "list":
		cmdList(os.Args[2:])
	case "approve":
		cmdApprove(os.Args[2:])
	case "update":
		cmdUpdate(os.Args[2:])
	case "diff":
		cmdDiff(os.Args[2:])
	case "check":
		cmdCheck(os.Args[2:])
	case "audit":
		cmdAudit(os.Args[2:])
	case "build", "install":
		fmt.Fprintf(os.Stderr, "vendor %s: not implemented yet\n", os.Args[1])
		os.Exit(1)
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage: vendor <command> [arguments]

Commands:
  add       Add a new vendored dependency
  list      List vendored dependencies
  approve   Approve the current state of a dependency
  update    Update a dependency to a new ref
  check     Check for available updates
  audit     Audit a vendored dependency for security concerns
  build     Build a vendored dependency (not implemented)
  install   Install a vendored dependency (not implemented)
  diff      Show diff since last approved commit
`)
}

// findDotfilesRoot locates the dotfiles root directory. It first tries the
// executable path (expects bin/vendor -> root is ../), then falls back to cwd.
func findDotfilesRoot() (string, error) {
	// Try executable path: bin/vendor -> dotfiles root is two levels up from
	// the binary when installed at bin/vendor, but the binary lives in
	// cmd/vendor/ during development. Check for the vendor/ directory as a
	// sibling to confirm we have the right root.
	if exe, err := os.Executable(); err == nil {
		// Resolve symlinks so bin/vendor -> cmd/vendor/vendor works.
		exe, _ = filepath.EvalSymlinks(exe)
		// bin/vendor -> root is parent of bin/
		candidate := filepath.Dir(filepath.Dir(exe))
		if isRoot(candidate) {
			return candidate, nil
		}
		// cmd/vendor/vendor -> root is parent of cmd/vendor/
		candidate = filepath.Dir(filepath.Dir(filepath.Dir(exe)))
		if isRoot(candidate) {
			return candidate, nil
		}
	}

	// Fall back to cwd and walk upward.
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if isRoot(dir) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	// Last resort: just use cwd.
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("cannot determine dotfiles root: %w", err)
	}
	return cwd, nil
}

// isRoot returns true if dir looks like the dotfiles root (contains cmd/vendor/).
func isRoot(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "cmd", "vendor"))
	return err == nil && info.IsDir()
}

// --------------------------------------------------------------------------
// vendor add
// --------------------------------------------------------------------------

func cmdAdd(args []string) {
	fs := flag.NewFlagSet("add", flag.ExitOnError)
	ref := fs.String("ref", "", "Git tag or branch to clone")
	fs.Parse(args)

	if fs.NArg() < 2 {
		fmt.Fprintf(os.Stderr, "Usage: vendor add <name> <repo-url> [--ref <tag>]\n")
		os.Exit(1)
	}
	name := fs.Arg(0)
	repoURL := fs.Arg(1)

	root, err := findDotfilesRoot()
	if err != nil {
		fatal(err)
	}

	dest := filepath.Join(root, "vendor", name)

	// Ensure the target doesn't already exist.
	if _, err := os.Stat(dest); err == nil {
		fatalf("vendor/%s already exists; remove it first to re-add", name)
	}

	// Clone.
	fmt.Printf("Cloning %s into vendor/%s ...\n", repoURL, name)
	if err := GitClone(repoURL, dest, *ref); err != nil {
		fatalf("git clone failed: %v", err)
	}

	// Get HEAD commit.
	head, err := GitGetHead(dest)
	if err != nil {
		fatalf("failed to read HEAD: %v", err)
	}

	// Source stats.
	stats := countFileExtensions(dest)

	// Detect project type for defaults.
	installCmd := ""
	var watchPatterns []string
	if fileExists(filepath.Join(dest, "Cargo.toml")) {
		installCmd = "cargo build --release"
		watchPatterns = []string{"*.rs", "Cargo.toml", "Cargo.lock"}
	} else if fileExists(filepath.Join(dest, "go.mod")) {
		installCmd = "go build ./..."
		watchPatterns = []string{"*.go", "go.mod", "go.sum"}
	} else if fileExists(filepath.Join(dest, "package.json")) {
		installCmd = "npm install && npm run build"
		watchPatterns = []string{"*.js", "*.ts", "package.json", "package-lock.json"}
	} else if fileExists(filepath.Join(dest, "Makefile")) {
		installCmd = "make"
		watchPatterns = []string{"*"}
	}

	refStr := *ref
	if refStr == "" {
		refStr = "HEAD"
	}

	user := os.Getenv("USER")
	today := time.Now().Format("2006-01-02")

	entry := ManifestEntry{
		Repo:         repoURL,
		Ref:          refStr,
		PinnedCommit: head,
		LastReviewed: today,
		ReviewedBy:   user,
		Install:      installCmd,
		LinkBinary:   "",
		LinkTo:       "",
		Notes:        "",
		Audit: AuditConfig{
			WatchPatterns:  watchPatterns,
			IgnorePatterns: []string{"tests/*", "benches/*"},
		},
	}

	manifest, err := LoadManifest(root)
	if err != nil {
		fatalf("failed to load manifest: %v", err)
	}
	manifest[name] = entry
	if err := SaveManifest(root, manifest); err != nil {
		fatalf("failed to save manifest: %v", err)
	}

	// Print summary.
	fmt.Printf("\nAdded %s\n", name)
	fmt.Printf("  repo:   %s\n", repoURL)
	fmt.Printf("  ref:    %s\n", refStr)
	fmt.Printf("  commit: %s\n", shortHash(head))
	if installCmd != "" {
		fmt.Printf("  install: %s\n", installCmd)
	}
	fmt.Printf("\nSource stats:\n")
	printStats(stats)
}

// --------------------------------------------------------------------------
// vendor list
// --------------------------------------------------------------------------

func cmdList(args []string) {
	fs := flag.NewFlagSet("list", flag.ExitOnError)
	namesOnly := fs.Bool("names", false, "Print only dependency names")
	fs.Parse(args)

	root, err := findDotfilesRoot()
	if err != nil {
		fatal(err)
	}

	manifest, err := LoadManifest(root)
	if err != nil {
		fatalf("failed to load manifest: %v", err)
	}

	if len(manifest) == 0 {
		fmt.Println("No vendored dependencies.")
		return
	}

	// Collect sorted names for stable output.
	names := sortedKeys(manifest)

	if *namesOnly {
		for _, name := range names {
			fmt.Println(name)
		}
		return
	}

	// Compute column widths.
	nameW := len("NAME")
	refW := len("REF")
	pinnedW := len("PINNED")
	reviewedW := len("REVIEWED")
	linkW := len("LINK STATUS")

	for _, name := range names {
		e := manifest[name]
		if len(name) > nameW {
			nameW = len(name)
		}
		if len(e.Ref) > refW {
			refW = len(e.Ref)
		}
		h := shortHash(e.PinnedCommit)
		if len(h) > pinnedW {
			pinnedW = len(h)
		}
		if len(e.LastReviewed) > reviewedW {
			reviewedW = len(e.LastReviewed)
		}
	}

	// Header.
	fmt.Printf("%-*s  %-*s  %-*s  %-*s  %-*s\n",
		nameW, "NAME",
		refW, "REF",
		pinnedW, "PINNED",
		reviewedW, "REVIEWED",
		linkW, "LINK STATUS",
	)

	for _, name := range names {
		e := manifest[name]
		linkStatus := linkStatusText(e.LinkTo)
		fmt.Printf("%-*s  %-*s  %-*s  %-*s  %-*s\n",
			nameW, name,
			refW, e.Ref,
			pinnedW, shortHash(e.PinnedCommit),
			reviewedW, e.LastReviewed,
			linkW, linkStatus,
		)
	}
}

// --------------------------------------------------------------------------
// vendor approve
// --------------------------------------------------------------------------

func cmdApprove(args []string) {
	if len(args) < 1 {
		fmt.Fprintf(os.Stderr, "Usage: vendor approve <name>\n")
		os.Exit(1)
	}
	name := args[0]

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

	repoDir := filepath.Join(root, "vendor", name)
	if _, err := os.Stat(repoDir); os.IsNotExist(err) {
		fatalf("vendor/%s does not exist", name)
	}

	head, err := GitGetHead(repoDir)
	if err != nil {
		fatalf("failed to read HEAD of vendor/%s: %v", name, err)
	}

	user := os.Getenv("USER")
	today := time.Now().Format("2006-01-02")

	entry.PinnedCommit = head
	entry.LastReviewed = today
	entry.ReviewedBy = user
	manifest[name] = entry

	if err := SaveManifest(root, manifest); err != nil {
		fatalf("failed to save manifest: %v", err)
	}

	// Remove .review-pending marker if present.
	pending := filepath.Join(repoDir, ".review-pending")
	os.Remove(pending) // ignore error if not present

	fmt.Printf("Approved %s\n", name)
	fmt.Printf("  commit:   %s\n", shortHash(head))
	fmt.Printf("  reviewed: %s by %s\n", today, user)
}

// --------------------------------------------------------------------------
// vendor update
// --------------------------------------------------------------------------

func cmdUpdate(args []string) {
	fs := flag.NewFlagSet("update", flag.ExitOnError)
	ref := fs.String("ref", "", "Git tag or branch to update to")
	abort := fs.Bool("abort", false, "Revert to pinned commit and remove .review-pending")
	fs.Parse(args)

	if fs.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "Usage: vendor update <name> [--ref <tag>] [--abort]\n")
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

	repoDir := filepath.Join(root, "vendor", name)
	if _, err := os.Stat(repoDir); os.IsNotExist(err) {
		fatalf("vendor/%s does not exist", name)
	}

	pendingFile := filepath.Join(repoDir, ".review-pending")

	// Handle --abort: revert to pinned commit and clean up.
	if *abort {
		fmt.Printf("Reverting %s to pinned commit %s ...\n", name, shortHash(entry.PinnedCommit))
		if err := GitCheckout(repoDir, entry.PinnedCommit); err != nil {
			fatalf("failed to checkout pinned commit: %v", err)
		}
		os.Remove(pendingFile)
		fmt.Println("Reverted. Update aborted.")
		return
	}

	// Fetch upstream with tags.
	fmt.Printf("Fetching upstream for %s ...\n", name)
	if err := GitFetchTags(repoDir); err != nil {
		fatalf("git fetch failed: %v", err)
	}

	// Determine target ref.
	targetRef := *ref
	if targetRef == "" {
		if tag := GitLatestTag(repoDir); tag != "" {
			targetRef = tag
			fmt.Printf("Latest tag: %s\n", targetRef)
		} else {
			targetRef = "origin/HEAD"
			fmt.Println("No tags found, using origin/HEAD")
		}
	}

	// Resolve target to a SHA.
	targetSHA, err := GitRevParse(repoDir, targetRef)
	if err != nil {
		fatalf("failed to resolve ref %s: %v", targetRef, err)
	}

	if targetSHA == entry.PinnedCommit {
		fmt.Println("Already up to date.")
		return
	}

	// Build diff with watch_patterns filter.
	diffOutput, err := GitDiff(repoDir, entry.PinnedCommit, targetSHA, entry.Audit.WatchPatterns)
	if err != nil {
		fatalf("git diff failed: %v", err)
	}

	if diffOutput == "" {
		fmt.Println("No changes in watched files.")
		return
	}

	// Write diff to .review-pending.
	if err := os.WriteFile(pendingFile, []byte(diffOutput), 0644); err != nil {
		fatalf("failed to write .review-pending: %v", err)
	}

	// Checkout the new ref.
	if err := GitCheckout(repoDir, targetRef); err != nil {
		fatalf("failed to checkout %s: %v", targetRef, err)
	}

	// Update the ref in manifest (but NOT pinned_commit -- that's what approve does).
	entry.Ref = targetRef
	manifest[name] = entry
	if err := SaveManifest(root, manifest); err != nil {
		fatalf("failed to save manifest: %v", err)
	}

	// Open diff in pager.
	pager := os.Getenv("PAGER")
	if pager == "" {
		pager = "less"
	}
	pagerCmd := exec.Command(pager, pendingFile)
	pagerCmd.Stdin = os.Stdin
	pagerCmd.Stdout = os.Stdout
	pagerCmd.Stderr = os.Stderr
	pagerCmd.Run() // ignore exit code from pager

	fmt.Printf("\nUpdate staged for %s (%s -> %s)\n", name, shortHash(entry.PinnedCommit), shortHash(targetSHA))
	fmt.Printf("  Review the diff: %s\n", pendingFile)
	fmt.Printf("  Approve: vendor approve %s\n", name)
	fmt.Printf("  Abort:   vendor update --abort %s\n", name)
}

// --------------------------------------------------------------------------
// vendor diff
// --------------------------------------------------------------------------

func cmdDiff(args []string) {
	fs := flag.NewFlagSet("diff", flag.ExitOnError)
	ref := fs.String("ref", "", "Git tag or branch to diff against")
	fs.Parse(args)

	if fs.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "Usage: vendor diff <name> [--ref <tag>]\n")
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

	repoDir := filepath.Join(root, "vendor", name)
	if _, err := os.Stat(repoDir); os.IsNotExist(err) {
		fatalf("vendor/%s does not exist", name)
	}

	// Fetch upstream.
	fmt.Fprintf(os.Stderr, "Fetching upstream for %s ...\n", name)
	if err := GitFetchTags(repoDir); err != nil {
		fatalf("git fetch failed: %v", err)
	}

	// Determine target ref.
	targetRef := *ref
	if targetRef == "" {
		if tag := GitLatestTag(repoDir); tag != "" {
			targetRef = tag
		} else {
			targetRef = "origin/HEAD"
		}
	}

	targetSHA, err := GitRevParse(repoDir, targetRef)
	if err != nil {
		fatalf("failed to resolve ref %s: %v", targetRef, err)
	}

	if targetSHA == entry.PinnedCommit {
		fmt.Fprintf(os.Stderr, "No changes (pinned at %s).\n", shortHash(targetSHA))
		return
	}

	diffOutput, err := GitDiff(repoDir, entry.PinnedCommit, targetSHA, entry.Audit.WatchPatterns)
	if err != nil {
		fatalf("git diff failed: %v", err)
	}

	if diffOutput == "" {
		fmt.Fprintf(os.Stderr, "No changes in watched files.\n")
		return
	}

	fmt.Print(diffOutput)
}

// --------------------------------------------------------------------------
// vendor check
// --------------------------------------------------------------------------

func cmdCheck(args []string) {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	quiet := fs.Bool("quiet", false, "Only exit with status; no output unless updates exist")
	fs.Parse(args)

	root, err := findDotfilesRoot()
	if err != nil {
		fatal(err)
	}

	manifest, err := LoadManifest(root)
	if err != nil {
		fatalf("failed to load manifest: %v", err)
	}

	if len(manifest) == 0 {
		fmt.Println("No vendored dependencies.")
		return
	}

	names := sortedKeys(manifest)

	type checkResult struct {
		name     string
		pinned   string
		latest   string
		behind   int
		errMsg   string
	}

	var results []checkResult
	hasUpdates := false

	for _, name := range names {
		entry := manifest[name]
		repoDir := filepath.Join(root, "vendor", name)

		if _, err := os.Stat(repoDir); os.IsNotExist(err) {
			results = append(results, checkResult{name: name, errMsg: "not cloned"})
			continue
		}

		if !*quiet {
			fmt.Fprintf(os.Stderr, "Checking %s ...\n", name)
		}

		if err := GitFetchTags(repoDir); err != nil {
			results = append(results, checkResult{name: name, errMsg: "fetch failed"})
			continue
		}

		// Determine latest ref.
		latestRef := GitLatestTag(repoDir)
		if latestRef == "" {
			latestRef = "origin/HEAD"
		}

		latestSHA, err := GitRevParse(repoDir, latestRef)
		if err != nil {
			results = append(results, checkResult{name: name, errMsg: "resolve failed"})
			continue
		}

		behind := 0
		if latestSHA != entry.PinnedCommit {
			behind, _ = GitCommitsBehind(repoDir, entry.PinnedCommit, latestSHA)
			if behind == 0 {
				// If rev-list returns 0 but SHAs differ, mark as 1 so it shows up.
				behind = 1
			}
			hasUpdates = true
		}

		results = append(results, checkResult{
			name:   name,
			pinned: shortHash(entry.PinnedCommit),
			latest: shortHash(latestSHA),
			behind: behind,
		})
	}

	if *quiet && !hasUpdates {
		return
	}

	if !*quiet {
		fmt.Fprintf(os.Stderr, "\n")
	}

	// Compute column widths.
	nameW := len("NAME")
	pinnedW := len("PINNED")
	latestW := len("LATEST")

	for _, r := range results {
		if len(r.name) > nameW {
			nameW = len(r.name)
		}
		if len(r.pinned) > pinnedW {
			pinnedW = len(r.pinned)
		}
		display := r.latest
		if r.errMsg != "" {
			display = r.errMsg
		}
		if len(display) > latestW {
			latestW = len(display)
		}
	}

	// Header.
	fmt.Printf("%-*s  %-*s  %-*s  %s\n", nameW, "NAME", pinnedW, "PINNED", latestW, "LATEST", "BEHIND")

	for _, r := range results {
		if r.errMsg != "" {
			fmt.Printf("%-*s  %-*s  %-*s  %s\n", nameW, r.name, pinnedW, "?", latestW, r.errMsg, "-")
			continue
		}
		behindStr := "0"
		if r.behind > 0 {
			behindStr = fmt.Sprintf("%d", r.behind)
		}
		fmt.Printf("%-*s  %-*s  %-*s  %s\n", nameW, r.name, pinnedW, r.pinned, latestW, r.latest, behindStr)
	}

	if *quiet && hasUpdates {
		os.Exit(1)
	}
}

// --------------------------------------------------------------------------
// helpers
// --------------------------------------------------------------------------

func fatal(err error) {
	fmt.Fprintf(os.Stderr, "error: %v\n", err)
	os.Exit(1)
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", args...)
	os.Exit(1)
}

func shortHash(h string) string {
	if len(h) > 10 {
		return h[:10]
	}
	return h
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func linkStatusText(linkTo string) string {
	if linkTo == "" {
		return "n/a"
	}
	resolved := linkTo
	if strings.HasPrefix(resolved, "~/") {
		home, _ := os.UserHomeDir()
		resolved = filepath.Join(home, resolved[2:])
	}
	if fileExists(resolved) {
		return "linked"
	}
	return "not linked"
}

// countFileExtensions walks the directory tree and counts files by extension,
// skipping the .git directory.
func countFileExtensions(root string) map[string]int {
	counts := make(map[string]int)
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		// Skip .git directory.
		if info.IsDir() && info.Name() == ".git" {
			return filepath.SkipDir
		}
		if !info.IsDir() {
			ext := filepath.Ext(info.Name())
			if ext == "" {
				ext = "(no ext)"
			}
			counts[ext]++
		}
		return nil
	})
	return counts
}

func printStats(stats map[string]int) {
	keys := sortedMapKeys(stats)
	total := 0
	for _, k := range keys {
		fmt.Printf("  %-16s %d\n", k, stats[k])
		total += stats[k]
	}
	fmt.Printf("  %-16s %d\n", "total", total)
}

// sortedKeys returns the keys of a Manifest in sorted order.
func sortedKeys(m Manifest) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sortStrings(keys)
	return keys
}

// sortedMapKeys returns the keys of a map[string]int in sorted order.
func sortedMapKeys(m map[string]int) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sortStrings(keys)
	return keys
}

// sortStrings sorts a slice of strings in place (insertion sort, no import needed).
func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}
