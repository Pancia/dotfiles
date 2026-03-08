# Spec: Vendored Dependencies System

**Date**: 2026-03-08
**Status**: draft

## Overview

A Go CLI tool (`bin/vendor`) that manages external project dependencies with a review-gated update workflow. Dependencies are cloned locally, built from source, and pinned to reviewed commits. This provides visibility, control, and auditability for tools that sit in sensitive paths (e.g., LLM proxies that see source code and API keys). The first target dependency is `rtk-ai/rtk`, a Rust CLI proxy for LLM token reduction.

## Requirements

1. **Directory structure**: `vendor/` directory at dotfiles root containing `MANIFEST.json` (committed) and cloned repos (gitignored via `vendor/*/` pattern in `.gitignore`).

2. **Go CLI binary** at `cmd/vendor/main.go` (compiled to `bin/vendor`) with these subcommands:
   - `vendor add <name> <repo-url> [--ref <tag>]` — Clone repo into `vendor/<name>/`, record in MANIFEST.json, print source stats.
   - `vendor update <name> [--ref <tag>]` — Fetch upstream, show filtered diff, write `.review-pending` marker. Does NOT update `pinned_commit` until approved. Reverts on abort.
   - `vendor check` — Fetch all deps, print table of `name | pinned | latest | behind_by`. `--quiet` flag suppresses output unless updates exist.
   - `vendor audit <name>` — Scan source for network/fs/env/process patterns, count dependencies, run `cargo audit` for Rust projects, output summary report to stdout and optionally to `vendor/<name>/.audit-report`.
   - `vendor build <name>` — Run the `install` command from MANIFEST.json in the clone directory.
   - `vendor install <name>` — Build + create symlink from `link_binary` to `link_to` path.
   - `vendor list` — Show all vendored deps with pinned ref, review date, and link status.
   - `vendor diff <name>` — Show diff between `pinned_commit` and latest upstream (or specified ref).
   - `vendor approve <name>` — Update `pinned_commit` and `last_reviewed` in MANIFEST.json, remove `.review-pending` marker.

3. **MANIFEST.json format** per the sketch: each entry keyed by name with fields `repo`, `ref`, `pinned_commit`, `last_reviewed`, `reviewed_by`, `install`, `link_binary`, `link_to`, `notes`, and `audit` (with `watch_patterns` and `ignore_patterns`).

4. **Review-gated updates**: `vendor update` shows a diff filtered by `watch_patterns`, opens in `$PAGER` (or `$EDITOR`), and writes a `.review-pending` file. The manifest is only updated after explicit `vendor approve`. If the user aborts, the clone reverts to `pinned_commit`.

5. **Audit command**: Pattern-based scan for security-relevant code across languages, starting with Rust:
   - Network: `reqwest`, `hyper`, `std::net`, `tokio::net`
   - Filesystem: `std::fs`, `dirs`, `home_dir`
   - Environment: `std::env::var`, `env!`
   - Process: `std::process::Command`
   - Run `cargo audit` when available for CVE checks
   - Report saved to `vendor/<name>/.audit-report`

6. **Build from source only**: No pre-built binary downloads. The `install` field in MANIFEST.json contains the build command (e.g., `cargo build --release`).

7. **macOS ARM only**: No cross-compilation support needed.

8. **Install script integration**: Add `task_vendor` to `install` that runs `vendor install` for all MANIFEST entries. Add to `task_all` call chain. Add `vendor` to the `main()` case statement.

9. **Fish startup check**: `fish/conf.d/vendor_check.fish` runs `vendor check --quiet` weekly (cached timestamp in `~/dotfiles/cache/vendor-last-check`), backgrounded.

10. **Binary linking**: Symlink built binaries to `~/.local/bin/` (already on PATH per `fish/conf.d/path.fish`).

11. **Gitignore**: Add `vendor/*/` to `.gitignore` so cloned repos are excluded but `vendor/MANIFEST.json` is committed.

## Acceptance Criteria

- [ ] `go build` in `cmd/vendor/` produces a working binary
- [ ] `vendor add rtk https://github.com/rtk-ai/rtk.git --ref v0.4.2` clones the repo, creates a MANIFEST.json entry, prints source stats
- [ ] `vendor list` shows the added dependency with pinned ref and review date
- [ ] `vendor audit rtk` produces a report listing flagged patterns and dependency counts
- [ ] `vendor build rtk` runs `cargo build --release` successfully in the clone
- [ ] `vendor install rtk` builds and symlinks `target/release/rtk` to `~/.local/bin/rtk`
- [ ] `vendor check` shows whether upstream has newer commits/tags
- [ ] `vendor update rtk --ref <new-tag>` shows diff, creates `.review-pending`, does NOT update `pinned_commit`
- [ ] `vendor approve rtk` updates `pinned_commit`, `last_reviewed`, removes `.review-pending`
- [ ] Aborting `vendor update` reverts the clone to the pinned commit
- [ ] `vendor diff rtk` shows diff between pinned and latest upstream
- [ ] `vendor/*/` is in `.gitignore`; `vendor/MANIFEST.json` is tracked
- [ ] `./install vendor` runs `task_vendor` successfully
- [ ] `fish/conf.d/vendor_check.fish` runs check weekly in background, only prints when updates exist
- [ ] The compiled `vendor` binary runs on macOS ARM without runtime dependencies

## Documentation Updates

- `CLAUDE.md` — Add vendor system to Repository Structure and Quick Reference sections
- `install` help text — Add `vendor` to the help output

## Technical Approach

### Go CLI Structure

```
cmd/vendor/
├── main.go          # Entry point, subcommand dispatch
├── manifest.go      # MANIFEST.json read/write/validation
├── clone.go         # Git clone, fetch, checkout operations
├── audit.go         # Pattern scanning and cargo audit integration
├── diff.go          # Diff generation and filtering by watch_patterns
└── go.mod
```

Use `os/exec` for git and cargo commands. Use `encoding/json` for MANIFEST.json. Use `filepath.Glob` for watch/ignore pattern matching. No external Go dependencies — stdlib only.

**Build and install the vendor binary itself**: Add a `Makefile` or build step in `cmd/vendor/` that compiles to `bin/vendor`. The `install` script's `task_vendor` should first check if the binary needs rebuilding (compare `bin/vendor` mtime vs `cmd/vendor/*.go` mtime).

### Subcommand Implementation

**`add`**: `git clone --depth 1 --branch <ref> <url> vendor/<name>`. Parse the clone to count files by extension and list `Cargo.toml` dependencies. Write MANIFEST.json entry.

**`update`**: `git fetch --tags` in the clone. `git diff <pinned_commit>..<new-ref> -- <watch_patterns>` for the security-filtered diff. Write diff to `.review-pending`. Open with `$PAGER` (default `less`). On abort: `git checkout <pinned_commit>`.

**`check`**: For each MANIFEST entry, `git fetch` in the clone, compare `pinned_commit` against `git describe --tags --abbrev=0 origin/HEAD` and `git rev-parse origin/HEAD`. Format as aligned table.

**`audit`**: Use `grep -rn` (or Go equivalent with `bufio.Scanner`) to scan files matching `watch_patterns` for the flagged patterns. For Rust, parse `Cargo.lock` to count transitive deps. Shell out to `cargo audit` if on PATH.

**`approve`**: Read MANIFEST.json, update `pinned_commit` to current HEAD of clone, set `last_reviewed` to today, set `reviewed_by` to `$USER`, write MANIFEST.json, remove `.review-pending`.

### Install Script Integration

Add to `install`:

```bash
task_vendor () {
    # Build the vendor CLI if needed
    if [ cmd/vendor/main.go -nt bin/vendor ] 2>/dev/null; then
        echo "Building vendor CLI..."
        (cd cmd/vendor && go build -o ../../bin/vendor .)
    fi
    if command -v vendor &>/dev/null || [ -x bin/vendor ]; then
        local vendor_cmd="${HOME}/dotfiles/bin/vendor"
        "$vendor_cmd" list --names | while read name; do
            "$vendor_cmd" install "$name"
        done
    else
        echo "Skipping vendor deps (Go not installed)"
    fi
}
```

Add `vendor` to the case statement in `main()` and add `task_vendor` to `task_all`.

### Fish Startup Check

`fish/conf.d/vendor_check.fish`:

```fish
if test -f ~/dotfiles/vendor/MANIFEST.json
    set -l last_check_file ~/dotfiles/cache/vendor-last-check
    set -l now (date +%s)
    set -l threshold 604800
    set -l should_check 0
    if not test -f $last_check_file
        set should_check 1
    else if test (math $now - (cat $last_check_file)) -gt $threshold
        set should_check 1
    end
    if test $should_check -eq 1
        echo $now > $last_check_file
        ~/dotfiles/bin/vendor check --quiet &
    end
end
```

### Gitignore Changes

Append to `.gitignore`:

```
# Vendored dependency clones (MANIFEST.json is tracked)
vendor/*/
```

## Out of Scope

- **Sandboxing built binaries** — Future enhancement using `macos-sandboxing` skill; not part of initial implementation.
- **LaunchAgent for update checks** — The fish startup hook is sufficient initially.
- **Cross-platform support** — macOS ARM only.
- **Non-Rust build systems** — Audit patterns start with Rust; other languages added as dependencies are vendored.
- **Automatic updates** — All updates require human review and explicit approval.
- **Audit report persistence in git** — Reports are written to the gitignored clone directory. Committing them is a future consideration.
- **Dependency graph visualization** — Out of scope for v1.

## Open Questions

1. **Vendor CLI bootstrap**: The vendor binary is built with `go build`, which requires Go on the system. Should Go be added to `Brewfile` if not already present, or should the install script skip gracefully?
2. **Shallow vs full clones**: Shallow clones (`--depth 1`) save space but limit `git log` history for audit. Should `vendor add` default to full clones for better auditability, or keep shallow with a `--full` flag?
3. **Multiple binaries per dep**: The current schema has a single `link_binary`/`link_to` pair. If a vendored project produces multiple binaries, should the schema support a list, or handle it as separate MANIFEST entries?
