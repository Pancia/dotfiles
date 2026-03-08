package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// GitClone clones a repository into dest. If ref is non-empty the clone is
// restricted to that branch/tag with --depth 1.
func GitClone(url, dest, ref string) error {
	var args []string
	if ref != "" {
		args = []string{"clone", "--depth", "1", "--branch", ref, url, dest}
	} else {
		args = []string{"clone", "--depth", "1", url, dest}
	}
	cmd := exec.Command("git", args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

// GitGetHead returns the full SHA of HEAD in the given repo directory.
func GitGetHead(repoDir string) (string, error) {
	cmd := exec.Command("git", "-C", repoDir, "rev-parse", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// GitFetch runs git fetch in the given repo directory.
func GitFetch(repoDir string) error {
	cmd := exec.Command("git", "-C", repoDir, "fetch")
	return cmd.Run()
}

// GitCheckout checks out the specified ref in the given repo directory.
func GitCheckout(repoDir, ref string) error {
	cmd := exec.Command("git", "-C", repoDir, "checkout", ref)
	return cmd.Run()
}

// GitFetchTags runs git fetch --tags --unshallow (or --depth=2147483647 if
// already unshallowed) to ensure full history and tags are available.
func GitFetchTags(repoDir string) error {
	// Try unshallow first; if the repo is already complete git will error,
	// so fall back to a normal fetch --tags.
	cmd := exec.Command("git", "-C", repoDir, "fetch", "--tags", "--unshallow")
	if err := cmd.Run(); err != nil {
		cmd2 := exec.Command("git", "-C", repoDir, "fetch", "--tags")
		return cmd2.Run()
	}
	return nil
}

// GitDiff returns the diff output between two refs, optionally filtered to
// the given path specs.
func GitDiff(repoDir, from, to string, paths []string) (string, error) {
	args := []string{"-C", repoDir, "diff", from + ".." + to}
	if len(paths) > 0 {
		args = append(args, "--")
		args = append(args, paths...)
	}
	cmd := exec.Command("git", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// GitLatestTag attempts to find the latest tag reachable from origin/HEAD.
// Returns the tag name or an empty string if no tags exist.
func GitLatestTag(repoDir string) string {
	cmd := exec.Command("git", "-C", repoDir, "describe", "--tags", "--abbrev=0", "origin/HEAD")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// GitRevParse resolves a ref to its full SHA.
func GitRevParse(repoDir, ref string) (string, error) {
	cmd := exec.Command("git", "-C", repoDir, "rev-parse", ref)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// GitCommitsBehind returns the number of commits in the range from..to.
func GitCommitsBehind(repoDir, from, to string) (int, error) {
	cmd := exec.Command("git", "-C", repoDir, "rev-list", "--count", from+".."+to)
	out, err := cmd.Output()
	if err != nil {
		return 0, err
	}
	var n int
	_, err = fmt.Sscanf(strings.TrimSpace(string(out)), "%d", &n)
	return n, err
}
