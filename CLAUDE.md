# Dotfiles

Personal development environment for macOS. Focused on automation, productivity, and multi-tool integration.

## VCS

This is a **jj (Jujutsu) repository**. Use `jj` rather than `git` for inspection
(`jj st`, `jj log`, `jj diff`) and history editing (`describe`, `squash`, `split`,
`new`). See the global CLAUDE.md for jj workflow details.

**To commit, use `/cc:commit`** (or `g run ci`) rather than a raw `jj commit`.
Both detect the VCS themselves and route to `commit-mine` when another live
session shares this working copy, so they stay correct where a hardcoded rule
would not — which is why this section no longer says "use jj for *all* VCS
operations". The global CLAUDE.md carries the one exception, for git worktrees of
a jj repo; it cannot arise here, because `cc-worktree` refuses this checkout by
name (see [docs/cc-worktree.md](docs/cc-worktree.md)).

**jj config**: `rcs/jj-config.toml` → `~/.config/jj/config.toml` (managed via MANIFEST).

## External Sources

Some configuration here glues into external projects. When debugging, check the source repo, not just the dotfiles copy:

| Concern | Source |
|---------|--------|
| `fzfm` (fuzzy leader menu — `j`, `d`, `q`, `z`, `Ctrl+S`, `__fzfm_*` functions) | `~/projects/tooling/fzfm/` |

## Repository Structure

```
dotfiles/
├── fish/           # Fish shell configuration (primary shell)
├── nvim/           # Neovim configuration (Lua + Vimscript)
├── lib/lua/        # Hammerspoon configuration (macOS automation)
├── rcs/            # Config files managed via rcs/MANIFEST symlinks
├── bin/            # CLI utilities (50+ scripts)
├── services/       # Background LaunchAgent services
├── vpc/            # VPC workspace definitions
├── zsh/            # Zsh configuration (legacy, deprecated)
├── lib/            # Language-specific libraries (ruby, python, etc.)
├── misc/           # Miscellaneous tools and data
├── wiki/           # Personal wiki/knowledge base
├── ai/             # AI prompts and templates
├── vendor/         # Vendored dependencies (MANIFEST.json tracked, clones gitignored)
├── cmd/vendor/     # Vendor CLI source (Go)
├── public/         # Static HTML pages and redirect utilities
├── install         # Installation script
└── Brewfile        # Homebrew packages
```

## LaunchAgent Services

Use the `service` CLI (not `launchctl` directly) for managing LaunchAgents:
```bash
service list              # List all services
service status            # Status of all services
service start <name>      # Start a service
service stop <name>       # Stop a service
service restart <name>    # Restart a service
service log <name>        # Show logs for a service
service create            # Create a new service
service edit <name>       # Edit a service's script and plist
```

### Available Services

| Service | Schedule | Purpose |
|---------|----------|---------|
| `ziplog` | Thursday 12:00 | Compress monitor logs >6 days old, archive by month, backup to `~/Cloud/_inbox/monitor/minimac/` |
| `disk-snapshot` | Sun & Wed 3:00 | Create disk usage snapshot to `~/.local/share/disk-snapshots/` |
| `claude-watchdog` | Every 60s | Watch for a headless `claude` growing without bound. **Observe-only (phase 2): records, bundles forensics, notifies — cannot kill.** See [docs/claude-watchdog.md](docs/claude-watchdog.md) |
| `bookmark-manager` | Daily 2:00 | Sync browser bookmarks |
| `music-backup` | Daily 3:00 | Backup music library via `music backup` |
| `sanctuary` | On demand | Rotate encrypted backup directories |
| `copyparty` | Startup | Media server for file sharing |

See `service list` for all installed services. `bin/ziplog` can also be run manually with `ziplog --yes` (skips confirmation prompt).

## Key Patterns

### RC Metadata System
Files in `rcs/` are managed via `rcs/MANIFEST` using `source -> destination` format:
```
tmux.conf -> $HOME/.tmux.conf
ghostty.config -> $HOME/.config/ghostty/config
```
The `_ENSURE_RCS()` function in `fish/config.fish` parses the MANIFEST and creates symlinks from `~/dotfiles/rcs/file` to the destination. It runs automatically in the background on every Fish shell startup (`_ENSURE_RCS &`). Some `rcs/` files have vestigial `#<[...]>` inline headers that are no longer parsed. Directories are symlinked; files are hard linked.

### Seed Architecture (Hammerspoon)
Hammerspoon modules in `lib/lua/seeds/` follow a standard interface:
- `start(config)` - Initialize the seed
- `stop()` - Clean up resources
- `engage()` wrapper provides error handling via pcall
- **Never call `hs.reload()` programmatically** - ask the user to reload with `Cmd+Ctrl+R`

### Monitor Seed (Activity Logger)
The `monitor` seed (`lib/lua/seeds/monitor.lua`) logs the focused window every 20 seconds to `~/.local/share/monitor/YYYY_MM_DD.log.json`. Each entry is a JSON object with `timestamp`, `focused` (app name + window title), and `active` (whether keyboard/mouse input occurred since last entry). Repeated same-window entries get a `noChange: true` flag. The file is append-only comma-separated JSON objects (not a JSON array).

### Auto-Loading (Fish)
- `conf.d/*.fish` - Sourced on shell startup
- `functions/*.fish` - Lazy-loaded on first call
- Fisher plugins auto-installed on missing

### Fisher Plugin Manager
`conf.d/fisher-wrap.fish` shadows the `fisher` command at shell startup to preserve local patches:
- `fisher update` is transparently intercepted and routed through `fisher-up`, which runs the real update then restores any tracked files in `fish/functions/` (e.g. `_tide_pwd.fish`) from the `master` baseline
- All other `fisher` subcommands pass through unchanged
- This preserves bug fixes and customizations to plugin files without manual re-patching after updates

### Fish Shell Gotchas
**REQUIRED: Run `/fish` before writing or modifying ANY `.fish` file.** Fish syntax differs from bash/zsh in subtle ways that cause bugs. Do not skip this step.

Common pitfalls when writing Fish functions:

| Gotcha | Wrong | Right |
|--------|-------|-------|
| **Escape sequences** | `"text\twith\ttabs"` (literal `\t`) | `printf '%s\t%s' "$a" "$b"` |
| **Variable scoping** | `set -l var` inside if/for block | Declare at function level, assign inside block |
| **List vs string** | `"$list"` joins with spaces | `$list` keeps elements separate |
| **Multi-line output** | `printf '%s\n' "$list"` (one line) | `printf '%s\n' $list` (many lines) |
| **Piping to functions** | `cmd | my_func` with `cat`/`string collect` | Write to temp file, pass as argument |

**Variable scoping example:**
```fish
# WRONG - $msg not visible outside if block
if test $big
    set -l msg (generate_message)
end
echo $msg  # empty!

# RIGHT - declare first, assign inside
set -l msg
if test $big
    set msg (generate_message)
end
echo $msg  # works
```

### Concurrent Claude sessions — which tool

Two tools, one decision. They solve the same problem from opposite ends and the
right one depends on whether the repo can be *copied*:

| Situation | Tool | Why |
|---|---|---|
| **This repo** (`~/dotfiles`) | `ccjj` / `commit-mine` — [docs/cc-jj-sessions.md](docs/cc-jj-sessions.md) | It cannot be isolated: about half its tracked files load by absolute path from `~/dotfiles` (all 35 `rcs/MANIFEST` entries are hardlinks, `~/.config/fish/functions` is a symlink into the checkout), so a second checkout can author changes it cannot run. The working copy has to stay shared, so the *commit* is what gets split. |
| **Any other repo** | `cc-worktree on`, then Claude Code's own `--worktree` — [docs/cc-worktree.md](docs/cc-worktree.md) | Nothing stops a second checkout, so each session gets its own and the collision never happens. `cc-worktree on` once per checkout; `cc` then passes `--worktree` for you, and `cc --no-worktree` opts out for one run. Refuses in `~/dotfiles` by name. |

**Setup, in full:** `ccjj` needs nothing — its hooks are registered and the
routing decides for itself. `cc-worktree` needs `cc-worktree on` once per
checkout, permanent. Optionally `ccjj bash-windows on` once per checkout (already
on here) to make Bash-made changes recoverable rather than merely reported.

**Inside a worktree of a jj repo, use `git`, not `jj`.** Claude Code's
`--worktree` creates a *git* worktree, which has no `.jj` of its own — so `jj`
there walks up and resolves to the **parent** repo. `jj commit` in a worktree
commits the parent's working copy, very likely a peer session's in-flight work,
while leaving your own changes uncommitted. Commit with git instead: the parent
picks the branch up as a jj bookmark of the same name automatically, so nothing
is stranded. `bin/cc-worktree-nudge` injects this warning on every prompt when it
detects the situation, because the repo's own tracked CLAUDE.md *is* loaded in
the worktree and says the opposite.

### Session-scoped jj commits (`commit-mine`)

When two Claude sessions share this working copy, **`jj commit` captures the other
session's half-written files too** — jj snapshots the whole working copy on every
command. Commit with `commit-mine -m "msg"` instead: it replays only *this*
session's recorded edits onto `@-` and commits that, so the other session's work
stays untouched and on disk. It splits a file both sessions edited, not just
disjoint files.

- A `PostToolUse` hook on `Edit|Write` (`ccjj record-edit`, registered in
  `rcs/claude-settings.json`) journals each edit with the file's pre-edit content;
  that is what lets the replay position an edit by context instead of by
  first-occurrence matching. Subagents share the parent's session id, so `Task`
  work is included.
- **Bash blind spot:** `rm`/`mv`/`sed -i`/`>` are journaled nowhere by the
  Edit/Write hook. Declare deletions and renames with `--also <path>` (safe only
  for whole-path changes, never for content). `ccjj audit` lists working-copy
  changes no session claims — run it when something seems to have gone
  uncommitted.
- **Bash content changes, in an opted-in checkout** (`ccjj bash-windows on`): a
  `PostToolUse` hook records the working-copy commit ids either side of each Bash
  call, `ccjj audit` annotates unclaimed paths with what covers them, and
  `ccjj claim <path>` prints the diff and turns it into an ordinary record.
  Deliberately an **offer, not an attribution** — a window's delta is a
  whole-copy diff, so it carries every write that landed inside it, including
  another session's `Edit` and the 103 tracked files hardlinked outside this
  repo. Reading the diff is the only detector that works.
- **`claude-p` disables hooks** (`--safe-mode`), so a headless agent produces no
  journal at all unless `CLAUDE_P_SAFE=0`.
- **You do not have to remember.** `g run ci` / `ai_jj_commit` / `/cc:commit` call
  `ccjj should-scope` and route to `commit-mine` themselves when another live
  session is here; otherwise they commit the whole working copy as before.
- A `UserPromptSubmit` hook injects a one-line reminder when another **live**
  session is working in this repo — so "commit stuff" gets steered without you
  invoking anything. Liveness is owner pid + start time, with a 12h staleness
  fallback; `ccjj prune` retires orphaned journals, `ccjj disown <sid>` by hand.

Exit `4` means locked or the base moved — retry, it is not an error. Full
mechanism, and why each guard exists, in [docs/cc-jj-sessions.md](docs/cc-jj-sessions.md).

### Crashed Session Titles (ccs)

`ccs list` shows crashed sessions with real titles, not just `crashed <date>`. A crash is
usually power loss, so nothing can run afterwards — the title has to already be on disk:

- Claude Code writes its own title into the transcript (`{"type":"ai-title","aiTitle":...}`,
  refreshed as the session drifts). `_ccs_open_scan` reads the last one.
- `bin/ccs-title-hook` (a `Stop` hook) copies it into the session's entry file each turn, so
  it outlives the transcript. It also keeps a local zstd copy in
  `$XDG_STATE_HOME/claude-sessions/transcripts/` — deliberately *not* `~/Cloud`, which is a
  ProtonDrive symlink. That copy is throttled to one write per 10 minutes, so it can lag the
  live transcript by up to that much. `ccs resume` puts it back via
  `_ccs_restore_transcript` before resuming, since `--resume` needs the real file in
  `~/.claude/projects/`.
- `bin/ccsave-hook` (a `SessionStart` hook) stamps the real `session_id` into the entry,
  **write-once** — except on `/clear` and compaction (`.source`), which start a new session
  id in the same terminal and so must be followed, or ccs would keep pointing at the
  pre-`/clear` conversation. A rotation clears the recorded title too.
- Both hooks gate on identity, because `CCS_ENTRY_FILE` is inherited by every descendant and
  `claude -p` runs hooks too: without it a nested helper session would overwrite the parent's
  id or title. A nested session always reports `source=startup`, never `clear`.
- `ccs rename` on a crashed session sets `.title_manual`, which stops the hook overwriting it.
- The wrapper exports `CCS_ENTRY_FILE`; if it's unset, both hooks no-op silently.

**Known limitation:** if you quit a session in the millisecond window while its `Stop` hook is
mid-write, the hook can recreate the entry that `_ccs_open_finalize` just deleted, leaving a
phantom `crashed` row in `ccs list`. Delete the entry from
`$XDG_STATE_HOME/claude-sessions/open/` by hand. Every fix considered (tombstone files, pid
checks) introduced a worse failure mode than the one it closed.

### Session Review
After each interactive Claude Code session, a background Haiku process reviews the session transcript and suggests CLAUDE.md updates. Results are written to `.cc/pending-updates-<timestamp>-<session-id>.md`.

**How it works:**
1. `bin/cc-session-summary` — extracts review-optimized session summary (human messages, file paths, tool use) with 150k char budget
2. `fish/functions/cc-session-review.fish` — sends summary + current CLAUDE.md to Haiku, writes suggestions
3. Triggered automatically by `fish/functions/my-claude-code-wrapper.fish` after `claude` exits (non-interactive invocations skipped)

**Viewing suggestions:** Pending updates appear in `chpwd` output when you cd into a project with pending files (golden/orange highlight). Use `/cc:pending-updates` to automatically find, review, apply, and clean up pending update files in the current directory. Alternatively, manually review files and delete them after applying edits.

### Claude Code Project Artifacts

Files in `.cc/` are Claude Code session artifacts:
- `pending-updates-<ts>-<id>.md` — suggested CLAUDE.md edits from session reviews
- `PLAN-*.md` — session plans and design documents

Tracked in git via `!.cc` in `gitignore_global`.

## Quick Reference

### Installation
```bash
cd ~/dotfiles
./install all    # Run all setup tasks
./install brew   # Just Homebrew packages
./install nvim   # Just Neovim setup
```

### XDG Base Directories

The project uses XDG Base Directory Specification for tool configuration and caches. Environment variables are set in `fish/conf.d/00_xdg.fish` (loaded first, alphabetically):

| Variable | Value | Used By |
|----------|-------|---------|
| `XDG_CONFIG_HOME` | `~/.config` | git, tmux, docker, aws, etc. |
| `XDG_DATA_HOME` | `~/.local/share` | cargo, bundle, gem, hex, etc. |
| `XDG_STATE_HOME` | `~/.local/state` | history files, cache, logs |
| `XDG_CACHE_HOME` | `~/.cache` | npm, maven, gradle, gitlibs, deps.clj |

Relocated tool configs:
- **Git**: `~/.config/git/` (replaces `~/.gitconfig`)
- **Tmux**: `~/.config/tmux/` (replaces `~/.tmux.conf`)
- **Cargo**: `~/.local/share/cargo` (replaces `~/.cargo`)
- **Docker**: `~/.config/docker`
- **AWS**: `~/.config/aws`
- **Gradle**: `~/.local/share/gradle` (replaces `~/.gradle`)

Symlinked items (data in `~/.local/`, but still accessible at `~/.`):
- `.flet`, `.dartServer`, `.dart-tool`, `.flutter-devtools` → `~/.local/state/` and `~/.local/share/`
- `.log` → `~/.local/state/log`

### Key Hotkeys (Hammerspoon)
| Hotkey | Action |
|--------|--------|
| `Cmd+Space` | App launcher (Hermes, standalone Swift app) |
| `Cmd+Ctrl+R` | Reload Hammerspoon |
| `Cmd+Ctrl+C` | Hammerspoon console |
| `Cmd+Ctrl+S` | Snippets chooser |
| `Cmd+Ctrl+P` | Clipboard tool |
| `Alt+Tab` | Window switcher (fzf/yabai, all spaces) |
| `F7/F8/F9` | Media controls (cmus) |

### Hermes Commands (`Cmd+Space`)

Hermes is a which-key app launcher. Commands are defined in `rcs/hermes-commands.json`.

**Command types:**
- `"shell command"` — runs and closes
- `{"shell": "command"}` — opens in terminal, closes on exit
- `{"interactive": "command"}` — opens in terminal, stays open when done
- `{"shell:fish": "command"}` — runs via fish shell

**Submenu keys:** Objects with `"_desc": "+name"` create submenus. `"_stay": true` keeps the menu open after running a command (used for music controls).

**Generators:** `"generator:name"` dynamically builds a submenu (snippets, services, vpc).

**Reserved root keys — never assign these in JSON.** They are hardcoded in the Hermes source
(`~/projects/hermes/Sources/Hermes/HermesViewController.swift`) and **silently override** any
JSON entry with the same key — `withBuiltins` merges with the builtin winning, and `keyDown`
intercepts them before the menu is even consulted:

| Key | Reserved for | Scope |
|-----|--------------|-------|
| `a` | `+apps` mode (built-in app switcher) | root only |
| `w` | `+windows` mode (built-in window switcher) | root only |
| `:` | search mode | every level |

Escape / Backspace / Return / arrow keys are also intercepted. A duplicate key fails *silently* —
the entry renders nowhere and nothing is logged — so check `rcs/hermes-commands.json`'s `_note`
block (which lists currently-free root keys) before adding a top-level menu.

The root keyspace is nearly full, so **one-off scripts go in `x` (+utils)** rather than claiming a
root letter. Reserve new root keys for menus that will hold several related entries.

**Comments:** JSON has none, but the parser skips any key beginning with `_`, so a `"_note"` key
holding an array of strings works as a comment block at any level.

**Reloading:** no rebuild needed for config edits — `CommandLoader.load()` re-reads
`~/.config/hermes/commands.json` on every launcher open (background refresh pass), so the first
open after an edit may show the cached menu and the next one is current. `rebuild-hermes`
(`Cmd+Space` → `h` → `r`) is only for Swift source changes.

### Shell Commands (Fish)
| Command | Action |
|---------|--------|
| `Ctrl+S` | fzfm leader menu (fuzzy finder) |
| `d` | Directory bookmarks |
| `q` | Command registry |
| `z` | Jump to directory |
| `astro` | Astrological transit tracker |
| `ccpu` | Run claude wrapper with /cc:pending-updates (auto-detects jj/git repo) |
| `ccsave [title]` | Save current Claude Code session to `~/Cloud/cc-sessions/` (autogenerates title if omitted) |
| `ccs list` / `ccs resume` | List/pick sessions, including crashed ones (titled — see below) |
| `ccs prune [--dry-run]` | Archive crashed entries with no surviving transcript, backup, or saved record |
| `commit-mine -m MSG` | Commit only *this* Claude session's edits when sessions share the working copy; `--diff` to preview, `--also PATH` for a Bash-made delete/rename |
| `ccjj audit` | List working-copy changes no session claims (the Bash blind spot) |
| `cc-worktree on\|status\|off` | Opt a repo in to per-session worktree isolation, so two Claude sessions get their own checkouts. **`on` is the whole setup** — once per checkout, permanent; `cc` then appends `--worktree` and Claude Code creates, resumes and removes the worktree itself. `on` also writes a starter `.worktreeinclude` (Claude Code's mechanism for carrying untracked local state across) from what it finds in the repo — small config only, and it *names* `node_modules`/`.venv` as deliberately excluded rather than dropping them silently: `.worktreeinclude` copies and **skips symlinks**, so a copied `node_modules` arrives with no `.bin` and fails as command-not-found. Run your installer in the worktree instead. Inside a worktree of a jj repo, **use `git`** — see above. `cc --no-worktree` opts out for one run. Refuses in `~/dotfiles` — that is what `ccjj` is for. See [docs/cc-worktree.md](docs/cc-worktree.md) |
| `ccjj bash-windows on\|off\|status` | Opt this checkout into recording Bash windows |
| `ccjj claim PATH` | Accept a Bash-made change as your own, after reading the diff it prints; `-n` to preview |
| `claude-p [flags] [prompt]` | Guarded `claude -p` — hard timeout in its own process group, `.is_error` checking, and `--safe-mode` by default. Drop-in for text/json/stream-json. See below |
| `llm-output [--json]` | Extract the `<output>` envelope body from an LLM reply on stdin; nonzero exit rather than raw text when there isn't one. See below |
| `disk-cleanup` | Report on the latest disk snapshot (biggest consumers + growth vs a ~30-day-old baseline), then offer a Claude session to help free space. `--no-ai` report only, `--ai` skip the prompt, `--scan` fresh snapshot first. Hermes: `Cmd+Space` → `x` → `d` |
| `claude-watchdog` | Run the runaway-claude watchdog by hand (read-only at phase 2). `CW_PHASE=1` log only; `CW_RSS_MB=200 CW_CPU_PCT=5 CW_MIN_AGE=5` to force detection. Normally launchd runs it every 60s |
| `service` | LaunchAgent manager (list/start/stop/restart/log/status) |
| `tab-organize windows` | List open browser windows with tab counts |
| `tab-organize plan [--window ID]` | Generate AI organization plan (editable before execute) |
| `tab-organize check [plan-file]` | Validate a plan and show what it will do, with tab titles |
| `tab-organize execute <plan-file>` | Apply tab organization commands via browser extension |

### Headless Claude calls (`claude-p`)

`bin/claude-p` wraps `claude -p` with the three guards it lacks. Use it everywhere a
script or an ad-hoc command needs a headless answer.

```bash
claude-p 'prompt'                                   # -> result text
echo prompt | claude-p --system-prompt "$sys"       # -> result text
claude-p --model haiku --output-format json 'x'     # -> full JSON envelope
claude-p --output-format stream-json --verbose      # -> passthrough stream
CLAUDE_P_TIMEOUT=60 claude-p 'prompt'               # default is 180s
CLAUDE_P_SAFE=0 claude-p 'prompt'                   # keep CLAUDE.md/hooks/MCP
```

Exit `0` ok · `1` claude errored or returned nothing · `124` timed out.

**Variadic flags swallow a positional prompt.** `--tools`, `--allowed-tools`,
`--disallowed-tools`, `--add-dir`, `--mcp-config` and `--betas` are all variadic in
claude's argument parser, so `claude-p --tools '' 'my prompt'` eats the prompt as a
second `--tools` value and dies with *"Input must be provided either through stdin or
as a prompt argument"*. **Prefer the equals form everywhere:** `--tools=''`. Callers
that pass the prompt on stdin escape it by accident.

Three failure modes it closes, all observed in production:

- **A wedged child outliving its caller.** GNU `timeout -k` runs claude in its own
  process group and signals the group. On 2026-07-28 a headless claude sat at ~98%
  CPU past 2.7GB RSS with no output until it was killed by hand; the trigger is
  still unknown (the retired-model theory was tested and disproved — that exits
  rc=1 in ~2s), so a deadline is the defence rather than a fix. Separately, piping
  claude into `head`/`sed -n` does not bound it either: a reader exiting never kills
  the writer. `claude-p` buffers to a file, so a departing reader SIGPIPEs its own
  `cat` instead.
- **Errors that look like answers.** A retired or unavailable `--model` sets
  `is_error: true` while `subtype` still reads `"success"` and text mode just
  prints the warning. **Check `.is_error`, never `.subtype` or the exit code.**
  An *empty* body used to misroute into this branch, which is the one branch that
  never dumps stderr — jq 1.6 reads an empty file as a successful no-op, so both
  `type == "object"` and `.is_error == true` exit 0. A `-s` guard now runs first.
- **LLM chatter where a payload is expected.** `--safe-mode` is passed **by
  default** (`CLAUDE_P_SAFE=0` opts out). It disables CLAUDE.md discovery, hooks,
  skills, plugins, custom commands/agents and MCP config, while leaving auth, model
  selection, built-in tools and permissions normal. Measured on a realistic
  "summarize this diff" prompt: **2/2 leaked roleplay bookends without it, 3/3 clean
  with it.**

Model pins: prefer floating aliases (`haiku`, `sonnet`) or a current id
(`claude-sonnet-5`). Dated ids like `claude-sonnet-4-20250514` are the retirement
trap — they were removed from `ai-chunk-files`, `ai-merge-commit-messages`, and
`bin/ai-commit-msg` on 2026-07-28.

Still calling bare `claude -p` (deliberately, not pending migration):
`services/youtube-transcribe/server.py`, `bin/tab-organize` and AKR's
`scripts/score-day.py` / `scripts/invoice-from-worklog.py` all kill claude by pid,
and `claude-p` runs it under `timeout -k` in a **new process group** — so killing the
`claude-p` pid would orphan both `timeout` and `claude`, exactly the runaway the
wrapper exists to prevent. They pass `--safe-mode` on their own argv instead.
(`~/projects/ereshkigal/bin/import-audio.fish` is a different repo and still unbounded.)

### Constraining headless output

Three layers, cheapest and strongest first. `--safe-mode` kills the *roleplay* leak
but **not generic preamble** — safe-mode runs still volunteer unrequested
alternatives ("Or if you want it more granular:") — so anywhere the output must be
exactly one thing needs a layer on top.

| Layer | Use when | Where |
|---|---|---|
| `--safe-mode` | always | `claude-p` default; hand-added to the direct-subprocess callers above |
| `--json-schema` / SDK `output_format` | the output is data | `ccs autotitle`, `ai-chunk-files`, `ai-commit-msg`, `music ai_import`, AKR `invoice-from-worklog` |
| `<output>` envelope | the output is long prose or markdown | `claude-batch-worker`, `sanctuary` template, `tab-organize`, youtube-transcribe summaries, AKR `score-day` / `reading_engine` / inari chat |

**Schema-constrained output is validated server-side**, so compliance is not a
request the model can decline. The decoded object arrives on `.structured_output`
(CLI JSON envelope) or `ResultMessage.structured_output` (SDK) — never re-parse
`.result`. A **top-level array 400s** (`input_schema.type: Input should be 'object'`),
so wrap it: `{"chunks": [[…]]}`.

**The `<output>` envelope** is `ai/templates/output_contract.md` (canonical text,
includable via the `@<path>` mechanism `bin/ai-commit-msg`'s `load_template()`
implements) plus `lib/python/llm_output.py` and its `bin/llm-output` CLI:

```bash
printf '%s' "$raw" | llm-output          # body on stdout
printf '%s' "$raw" | llm-output --json   # body, validated as JSON
llm-output --contract                    # the contract text, for building a prompt
```

Exit `0` ok · `1` contract unavailable · `2` bad usage · `3` no usable envelope ·
`4` envelope present but empty · `5` bad JSON. **There is deliberately no path that
returns the raw text** — falling back is how chatter became a commit message in the
first place. Shell callers use `--contract` rather than reading the template by path,
so they resolve it the same way Python does and a worktree can't prompt with one
contract while enforcing another.

Matching is **line-anchored**: a tag only counts when it owns its line, which is what
survives the commonest preamble shape, *"I'll put my answer in `<output>` tags:"*
followed by the real envelope. Opens and closes must then **balance**, and the close
is the last line-anchored `</output>` with its partner found by walking back with a
depth counter — so an answer that legitimately quotes a *complete* envelope
(`cc-session-review` feeds the model a CLAUDE.md documenting this contract) comes back
whole, while a lone tag of either kind is rejected.

That symmetry is load-bearing and was a bug for one afternoon. The walk raised on an
unmatched *close* but silently returned the innermost body on an unmatched *open*, so a
reply quoting a bare `<output>` line — which the contract permitted at the time — came
back as a truncated fragment with exit 0. The count check also subsumes the truncation
guard, and has to run *before* the one-line-form fallback: a document cut off at the
token limit whose body contained `<output>PONG</output>` was otherwise silently
replaced by `PONG`. The contract now demands balance in both directions and forbids
anything after the closing tag; the accepted cost is that a stray `</output>` in a
sign-off fails the whole reply rather than being ignored.

**Known limitation, pinned by a test rather than fixed.** A stray line-anchored
`<output>` in the preamble and a stray `</output>` in the postamble *cancel out* in the
count, so the balance check passes and the depth walk latches onto the preamble's open,
over-capturing. Nothing is lost, but the body carries tags and trailing chatter. It is
close to irreducible: the captured region is a locally well-formed nested envelope, so
no local rule separates "outer envelope quoting an inner one" from "narration, real
envelope, narration". Rejecting text outside the outermost envelope fixes it and breaks
every legitimate preamble case. Related: **indenting a lone tag does not escape it** —
both regexes begin `^[ \t]*` — so the contract tells the model to keep a quoted tag
inline in a sentence instead.

Tests live in `tests/lib/python/test_llm_output.py`, under the `lib/python`
component. They are mutation-checked:
30 mutations of the regexes, the balance check, the exit-code constants, the
`--contract` path and the SIGPIPE handling are each killed. Four lessons worth keeping
if you add cases:

- An anchoring test needs an input the *unanchored* regex matches **differently** — a
  mid-line tag with trailing prose pins nothing, because `$` already rejects it.
- A SIGPIPE test needs a body larger than the OS pipe buffer (~64KB), or `print()`
  finishes before the reader exits and `BrokenPipeError` never fires. It also needs
  `${PIPESTATUS[0]}`: `subprocess.run("cli | head -1")` reports *head's* exit code, so
  asserting on it can never fail.
- A test that locates a file **via the value under test** is circular. The
  `CONTRACT_PATH` test copied the module to a temp tree using `CONTRACT_PATH.parents[2]`
  — so the `Path.home()` regression made it copy the real module and pass.
- Whole features can be invisible. `--contract` had no test at all, and printing it to
  stderr instead of stdout would have silently emptied the contract out of every fish
  caller's prompt with the suite green.

**SDK callers need `cli_path`, not just `extra_args`.** The SDK's `_find_cli` returns
its *bundled* CLI unconditionally, and those copies predate `--safe-mode` (2.1.92 in
the system site-packages, **2.1.71** in inari's venv, against 2.1.220 on PATH), so
without it the flag dies as `unknown option '--safe-mode'`:

```python
ClaudeAgentOptions(..., cli_path=shutil.which("claude"), extra_args={"safe-mode": None})
```

SDK MCP servers (`create_sdk_mcp_server`) **survive safe-mode** — they travel over
the control protocol, not MCP *config* — verified by driving `reading_engine`'s
interactive `ask_user` tool through a full pass under safe-mode.

Two callsites stay lenient on purpose: inari's `generate_reply` (a hard failure means
the phone gets nothing, so it strips bookends and warns) and `_emit_narration` (which
forwards intermediate text live, before any `ResultMessage`). `ai_briefing`'s weekly
review and dream consolidation get **safe-mode only, no envelope** — the agent writes
the document itself and `msg.result` there is just a truthiness gate guarding the jj
commit and `_run_backup_hook()`. `cc-session-review`'s `grep -q NO_UPDATES_NEEDED`
is also left alone; its false-positive fails safe.

### Neovim Prefixes
| Prefix | Commands |
|--------|----------|
| `;p` | Plugin management |
| `;s` | LSP commands |
| `;f` | Fuzzy finder (FZF) |
| `;;` | Show all commands |

### Testing
**Always use `cmds test $argv` from the dotfiles root** — never run `pytest` (or `python -m pytest`) directly. The `cmds` script handles virtual environments and dependencies.

```bash
cmds test                      # Run the full suite
cmds test yt                   # Run youtube-transcribe tests
cmds test yt -v                # Verbose output
cmds test yt --cov             # With coverage report
cmds test yt -k "cache"        # Run tests matching pattern
cmds test bin/ytdl/test_ytdl.py  # Target a specific file
cmds test bin                  # Run every bin/* component
```

**Every test tree must be registered in `COMPONENTS`** (`lib/python/run_tests.py`).
`run_all()` iterates that dict, so a directory under `tests/` that isn't listed is
not "not yet wired up" — it never runs at all, and rots silently. Four trees sat
unregistered for months; when they were finally registered, `tests/hooks` failed
immediately because it still asserted the pre-XDG `~/.tmux.conf` destination.

| Component | Alias | Runner | Notes |
|---|---|---|---|
| `services/youtube_transcribe` | `yt` | pytest | needs fastapi/httpx/etc. |
| `lib/python` | `python`, `cjson` | pytest | |
| `bin/astro` | `astro` | pytest | needs kerykeion/pyswisseph |
| `bin/ytdl` | `ytdl` | pytest | stubs yt-dlp via PATH |
| `bin/exocortex-id` | `exocortex` | pytest | |
| `fish` | `trash` | pytest | **pytest, not fishtape** — drives `fish -c` and asserts on output; needs the `fish` binary |
| `hooks` | `ensure-rcs` | pytest | runs `rcs/claude-ensure-rcs-hook.sh` |

`busted` and `fishtape` runners exist in `RUNNERS` but no component uses them.

Each component runs as its own `pytest` subprocess, so the run ends with an
**aggregate summary** naming every component, its counts, and one overall
PASSED/FAILED verdict. Without it the output just ends in the last component's
tally and reads as though nothing else ran — a real reader once saw astro's `107
passed` and concluded the other 300 tests hadn't executed.

`DOTFILES` is derived from `__file__`, not `$HOME/dotfiles`, so a clone or worktree
elsewhere tests itself; the resolved root is printed at the top of every run.

### Claude Code Config (cc-config)

Project-level skill/agent/command configuration via `.cc-config` and `cc-config.json`:

- **`.cc-config`** (local, per-project) — lists groups/skills/agents/commands to enable (one per line)
- **`cc-config.json`** (global registry at `~/dotfiles/ai/`) — defines all available skills, agents, commands, and groups
- **`"default"` key** in cc-config.json — group to auto-sync into `.claude/` when a project lacks `.cc-config`

**Workflow:**
```bash
cc-config              # Show profile and sync status (no args defaults to show)
cc-config init        # Create .cc-config via fzf picker
cc-config edit        # Edit .cc-config with reference comments
cc-config show        # Show what's enabled for current project (+ sync status)
cc-config sync        # Sync based on .cc-config (no args required)
cc-config sync --force # Clear stamp and force re-sync (fixes stale symlinks)
cc-config list        # Show all registered skills/agents/commands
```

The wrapper auto-syncs on `claude` launch: if `.cc-config` exists, uses that; otherwise syncs the `"default"` group from `cc-config.json`. Running `cc-config sync` manually now updates the stamp, keeping it in sync with the wrapper's cache.

## Primary Tools

| Tool | Purpose | Config Location |
|------|---------|-----------------|
| **Fish** | Primary shell | `fish/` |
| **Neovim** | Editor | `nvim/` |
| **Hammerspoon** | macOS automation | `lib/lua/` |
| **Karabiner** | Keyboard customization | `rcs/karabiner.json` |
| **Yabai** | Window tiling | (via VPC workspaces) |
| **Astro** | Astrological transits | `bin/astro`, `~/.local/share/astro/` |
| **uv** | Python package manager & venv tool | `fish/conf.d/uv.fish` |

### Hours Calculation
`lib/python/hours.py` - Parse time entries and calculate hours worked with optional multipliers.

```python
from lib.python.hours import calc_hours
calc_hours([
    "1/29 : 01:00 - 01:50 (ai-mult 2.00) - description",
    "2/3  : 19:40 - 01:00 - no multiplier, defaults to 1x",
])
```

Format: `DATE : HH:MM - HH:MM (ai-mult N.NN) - description`
- Handles overnight spans (e.g. 23:55 - 01:55)
- `(ai-mult ...)` and description are optional

### VPC Workspaces

Virtual Private Context (VPC) workspaces are pre-configured desktop environments launched via Hermes (`Cmd+Space` → `v`).

**Launching:** `Cmd+Space` -> `v` -> pick workspace (e.g. `a` for altera, `f` for festivar)

**Testing from CLI:** `python3 ~/dotfiles/bin/vpc.py ~/dotfiles/vpc/<name>.vpc`

**Creating a new VPC:** Copy `vpc/template.vpc` and edit, or inspect an existing one like `vpc/festivar.vpc`.

**Key files:**
- `vpc/*.vpc` - Workspace definitions (JSON)
- `bin/vpc.py` - Main orchestrator
- `bin/iterm.py` - iTerm2 tab/split launcher (uses iterm2 Python API)
- `bin/kitty.py` - Kitty tab/split launcher

**Yabai note:** Yabai cannot manage iTerm2 windows (empty AX roles). When a VPC has a yabai layout for iTerm, `vpc.py` passes `--maximize` to `iterm.py` which uses the iterm2 API to set the window frame directly.

See [docs/vpc-schema.md](docs/vpc-schema.md) for the full VPC file format specification.

### Website Crawler

`bin/crawl-sitemap` — recursively crawls a website and lists all internal pages. BFS traversal, skips static assets, deduplicates.

```bash
crawl-sitemap <url>              # list all pages
crawl-sitemap <url> -v           # show progress + depth
crawl-sitemap <url> --depth 2    # limit crawl depth
```

### Vendored Dependencies

`bin/vendor` — Go CLI for managing external dependencies built from source with review-gated updates. Dependencies are cloned into `vendor/`, built locally, and symlinked to `~/.local/bin/`.

```bash
vendor add <name> <url> --ref <tag>   # Clone and register a dependency
vendor list                            # Show all vendored deps
vendor build <name>                    # Build from source
vendor install <name>                  # Build + symlink binary
vendor approve <name>                  # Approve current state after review
```

**Key files:**
- `vendor/MANIFEST.json` — Dependency registry (tracked in git)
- `vendor/*/` — Cloned repos (gitignored)
- `cmd/vendor/` — CLI source code (Go, stdlib only)
- `fish/conf.d/vendor_check.fish` — Weekly update check on shell startup

**Install script:** `./install vendor` builds the CLI and runs `vendor install` for all entries.

### Process Labeling

`bin/proc-label` sets custom process names in Activity Monitor using Python's `setproctitle` — the only method that works on macOS (exec -a, Ruby setproctitle, and symlinks only affect `ps`). See [docs/proc-label.md](docs/proc-label.md).

## Detailed Documentation

| Document | Contents |
|----------|----------|
| [docs/fish.md](docs/fish.md) | Fish shell conf.d, functions, fzfm, plugins |
| [docs/neovim.md](docs/neovim.md) | Neovim plugins, LSP, keymaps, settings |
| [docs/hammerspoon.md](docs/hammerspoon.md) | Seeds, hotkeys, VPC system, Spoons |
| [docs/services.md](docs/services.md) | LaunchAgents, VPC workspaces, bin utilities |
| [docs/vpc-schema.md](docs/vpc-schema.md) | VPC file format specification |
| [docs/astro.md](docs/astro.md) | Astrological transit tracker CLI |
| [docs/proc-label.md](docs/proc-label.md) | Process labeling for Activity Monitor |
| [docs/cc-jj-sessions.md](docs/cc-jj-sessions.md) | Session-scoped jj commits for concurrent Claude sessions |
| [docs/cc-worktree.md](docs/cc-worktree.md) | Per-session worktree isolation: the opt-in marker, Claude Code's native `--worktree`, and why `jj` inside one means the parent repo |
| [docs/claude-watchdog.md](docs/claude-watchdog.md) | Runaway-headless-`claude` watchdog: phases, classification, bundle redaction, tests |
| [docs/claude-roleplay.md](docs/claude-roleplay.md) | Claude Code character roleplay (personas + randomizer hook) |

## File Locations

### Entry Points
- Fish: `fish/config.fish` -> `~/.config/fish/config.fish`
- Neovim: `nvim/init.vim` -> `~/.config/nvim/init.vim`
- Hammerspoon: `~/.hammerspoon/init.lua` -> loads `lib/lua/init.lua`

### Important Directories
- Functions: `fish/functions/` (169 files)
- Seeds: `lib/lua/seeds/` (9 modules)
- Utilities: `bin/` (50+ scripts)
- Services: `services/` (6 LaunchAgents)
- Workspaces: `vpc/` (10 VPC definitions)
