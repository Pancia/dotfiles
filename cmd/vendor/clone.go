package main

import (
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
