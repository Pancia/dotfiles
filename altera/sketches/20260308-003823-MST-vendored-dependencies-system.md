Now I have a good understanding of the codebase. Let me produce the sketch.

# Sketch: Vendored Dependencies System

**Date**: 2026-03-08
**Status**: exploring

## Motivation

External tools that sit in the critical path of development workflows (like `rtk-ai/rtk`, a Rust CLI proxy for LLM token reduction) need to be trusted. These tools see sensitive data — source code, API keys in environment, conversation transcripts — but are maintained by third parties. Vendoring them locally with a gated review process provides:

1. **Visibility** — full source is local, auditable, diffable
2. **Control** — updates only land after human review
3. **Reproducibility** — pinned versions, no surprise upstream changes
4. **Auditability** — review history is tracked in dotfiles git log

## Design

### 1. Directory Structure

```
dotfiles/
├── vendor/                    # All vendored dependencies
│   ├── MANIFEST.toml          # Registry of all vendored deps
│   ├── rtk/                   # Cloned repo (gitignored)
│   │   └── ...                # Full source tree
│   └── <future-dep>/
├── bin/vendor                 # CLI tool for managing vendored deps
└── .gitignore                 # Add: vendor/*/  (repos themselves are gitignored)
```

**Why not git submodules?** Submodules track a specific commit but `git submodule update` pulls it automatically without review. The existing submodules (`antigen`, `spacehammer`) are trusted community tools. For untrusted dependencies, we want an explicit human gate. A manifest + shallow clones gives full control without submodule complexity.

**Why gitignore the cloned repos?** The vendored source can be large (Rust projects with `target/`, etc). The MANIFEST tracks the pinned commit hash — the clone is reproducible from that. Only the manifest and audit artifacts are committed.

### 2. Manifest Format (`vendor/MANIFEST.toml`)

```toml
[rtk]
repo = "https://github.com/rtk-ai/rtk.git"
ref = "v0.4.2"                          # Tag, branch, or commit SHA
pinned_commit = "abc123def456..."        # Exact commit SHA after clone
last_reviewed = "2026-03-08"
reviewed_by = "anthony"
install = "cargo build --release"
link_binary = "target/release/rtk"      # Relative path to built binary
link_to = "$HOME/.local/bin/rtk"        # Where to symlink/copy the binary
notes = "LLM token reduction proxy. Sits in AI tool path."

# Optional: files/patterns to flag in review
[rtk.audit]
watch_patterns = [
    "**/*.rs",                          # All Rust source
    "Cargo.toml", "Cargo.lock",         # Dependency changes
    "build.rs",                         # Build scripts
]
ignore_patterns = [
    "docs/**", "*.md", "LICENSE",
]
```

### 3. CLI Tool (`bin/vendor`)

A Fish script (consistent with the rest of dotfiles) with these subcommands:

```
vendor add <name> <repo-url> [--ref <tag>]   # Clone and register
vendor update <name> [--ref <tag>]           # Fetch upstream, show diff, gate on review
vendor check                                 # Check all deps for upstream updates
vendor audit <name>                          # Run security review on current source
vendor build <name>                          # Build from source per manifest instructions
vendor install <name>                        # Build + link binary to PATH
vendor list                                  # Show all vendored deps with status
vendor diff <name>                           # Show diff between pinned and latest upstream
vendor approve <name>                        # Mark current version as reviewed, update manifest
```

### 4. Core Workflows

**Initial add (`vendor add rtk https://github.com/rtk-ai/rtk.git --ref v0.4.2`):**
1. Clone into `vendor/rtk/` at the specified ref
2. Record entry in `MANIFEST.toml`
3. Print source stats (file count, languages, dependency count)
4. Prompt: "Run `vendor audit rtk` to review before building"

**Check for updates (`vendor check`):**
1. For each entry in MANIFEST, `git fetch` in the clone
2. Compare `pinned_commit` against `origin/main` and latest tags
3. Print table: `name | pinned | latest | behind_by`
4. No automatic updates — just informational

**Update with review gate (`vendor update rtk --ref v0.5.0`):**
1. `git fetch` and checkout the new ref
2. Generate diff from `pinned_commit` to new ref
3. Filter diff through `watch_patterns` to highlight security-relevant changes
4. Write diff summary to `vendor/rtk/.review-pending`
5. Open diff in `$EDITOR` or `$PAGER`
6. **Do not update `pinned_commit` in manifest** until `vendor approve rtk`
7. If user aborts, `git checkout` back to pinned commit

**Audit (`vendor audit rtk`):**
1. Count and list all dependencies (`Cargo.toml` deps, transitive via `Cargo.lock`)
2. Flag network-accessing code patterns: `reqwest`, `hyper`, `std::net`, `tokio::net`
3. Flag filesystem access patterns: `std::fs`, `dirs`, `home_dir`
4. Flag environment variable access: `std::env::var`, `env!`
5. Flag process spawning: `std::process::Command`
6. For Rust: run `cargo audit` if available (checks for known CVEs in deps)
7. Output a summary report; optionally save to `vendor/rtk/.audit-report`

### 5. Integration with Install System

Add a new task to `install`:

```bash
task_vendor () {
    if command -v cargo &>/dev/null; then
        fish -c "vendor install rtk"
    else
        echo "Skipping vendor deps (cargo not found)"
    fi
}
```

And add `task_vendor` to `task_all`.

### 6. Integration with Existing Patterns

- **Binary linking** follows the same pattern as Homebrew binaries — symlink into a PATH directory (`$HOME/.local/bin/` or `$HOME/Developer/bin/`)
- **MANIFEST.toml** is committed to dotfiles (like `rcs/MANIFEST`), providing the reproducible record
- **Cloned repos** are gitignored (like `__pycache__`, `tmp/`, `cache/`)
- **LaunchAgent for update checks** (optional, future): a periodic service in `services/vendor-check/` that runs `vendor check` and sends a notification via Hammerspoon if updates are available

### 7. Notification of Available Updates

Two approaches, simplest first:

**A. Fish shell startup hook** (recommended to start):
Add to `fish/conf.d/`:
```fish
# Check weekly for vendor updates (cached timestamp)
if test -f ~/dotfiles/vendor/MANIFEST.toml
    set -l last_check_file ~/dotfiles/cache/vendor-last-check
    set -l now (date +%s)
    set -l threshold 604800  # 7 days
    if not test -f $last_check_file; or test (math $now - (cat $last_check_file)) -gt $threshold
        echo $now > $last_check_file
        vendor check --quiet &  # background, only prints if updates available
    end
end
```

**B. LaunchAgent** (if more visibility needed later): `services/vendor-check/` with weekly schedule, logs to `~/.log/services/vendor-check.log`.

### 8. File Listing

New files to create:
- `bin/vendor` — Main CLI (Fish script, ~200 lines)
- `vendor/MANIFEST.toml` — Dependency registry (committed)
- `vendor/.gitkeep` — Ensure directory exists
- `fish/conf.d/vendor-check.fish` — Optional startup check
- Add `vendor/*/` to `.gitignore`

Modified files:
- `install` — Add `task_vendor`
- `.gitignore` — Add vendor repo exclusion

## Open Questions

1. **TOML parsing in Fish?** Fish has no native TOML parser. Options: (a) use a simple line-based format instead (like rcs/MANIFEST), (b) write a minimal parser in Fish using `string match`, (c) use Python/Ruby for manifest parsing. Given the dotfiles already use Ruby (`bin/service`, `Gemfile`), a Ruby-based manifest parser is pragmatic. Alternatively, a simpler `KEY=VALUE` format per-section would avoid the dependency entirely.

2. **Build from source vs pre-built binaries?** For `rtk` specifically, building from source (`cargo build --release`) is the most trustworthy path but requires a Rust toolchain. Should the system also support downloading pre-built release binaries (with checksum verification) as a fallback?

3. **Sandboxing the built binary?** Once `rtk` is built from reviewed source, should it also run under a macOS sandbox profile (using the existing `macos-sandboxing` skill/patterns)? This would provide defense-in-depth: even if a future review misses something, the sandbox limits blast radius. This could be a separate follow-up.

4. **Audit depth for Rust transitive deps?** `cargo audit` checks for known CVEs, but the full dependency tree of a Rust project can be hundreds of crates. Should the audit also flag new transitive dependencies added between versions, or is CVE checking sufficient?

5. **Multiple architectures?** Is this only for the local macOS ARM machine, or should the manifest support cross-compilation targets?

## Related

- `rcs/MANIFEST` — Existing manifest pattern for dotfiles symlinks
- `.gitmodules` — Existing git submodules (antigen, spacehammer) for trusted deps
- `install` — Installation system that would run vendor builds
- `bin/service` — LaunchAgent manager pattern for potential update-check service
- `services/` — Existing service infrastructure
- `macos-sandboxing` skill — Potential follow-up for sandboxing built binaries
