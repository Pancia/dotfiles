package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// AuditConfig holds file-watching patterns for change review.
type AuditConfig struct {
	WatchPatterns  []string `json:"watch_patterns"`
	IgnorePatterns []string `json:"ignore_patterns"`
}

// ManifestEntry describes a single vendored dependency.
type ManifestEntry struct {
	Repo         string      `json:"repo"`
	Ref          string      `json:"ref"`
	PinnedCommit string      `json:"pinned_commit"`
	LastReviewed string      `json:"last_reviewed"`
	ReviewedBy   string      `json:"reviewed_by"`
	Install      string      `json:"install"`
	LinkBinary   string      `json:"link_binary"`
	LinkTo       string      `json:"link_to"`
	Notes        string      `json:"notes"`
	Audit        AuditConfig `json:"audit"`
}

// Manifest maps dependency names to their entries.
type Manifest map[string]ManifestEntry

// manifestPath returns the absolute path to MANIFEST.json.
func manifestPath(dotfilesRoot string) string {
	return filepath.Join(dotfilesRoot, "vendor", "MANIFEST.json")
}

// LoadManifest reads and parses MANIFEST.json. Returns an empty manifest if the
// file does not exist.
func LoadManifest(dotfilesRoot string) (Manifest, error) {
	p := manifestPath(dotfilesRoot)
	data, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			return make(Manifest), nil
		}
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return m, nil
}

// SaveManifest writes the manifest as indented JSON. It creates the vendor/
// directory if it does not already exist.
func SaveManifest(dotfilesRoot string, m Manifest) error {
	dir := filepath.Join(dotfilesRoot, "vendor")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(manifestPath(dotfilesRoot), data, 0644)
}
