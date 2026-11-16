# Dotfiles

Personal development environment for macOS. Focused on automation, productivity, and multi-tool integration.

## Dated reminders

Compare each date with today's date: the `[now: …]` line a `UserPromptSubmit`
hook adds to every prompt (`rcs/claude-settings.json`). When one has come, put
it under **Needs you** in your first reply, then delete the entry once it is
dealt with.

- **On or after 2026-11-22:** check the roleplay-bookends mod's debug log,
  `~/.local/state/roleplay/mod-debug.log`, since 2026-11-15, for lines with
  `error`, `aborted`, `api-error`, `empty reply`, `refused` or `who=none`
  (a healthy write ends in `ok`). If it is clean, offer to set `DEBUG = false` in
  `ai/mods/roleplay-bookends/hooks/register.tsx`, which stops the log.

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

## LaunchAgent Services

Use the `service` CLI (not `launchctl` directly) for managing LaunchAgents; `service --help` lists its subcommands (`reload`, `wait`, `create`, `edit` among them).

- A new or changed `services/*/*.plist` is installed and loaded at the next fish start of any kind, including `fish -c` and fish scripts such as `trash` (`_ENSURE_SERVICES` in `fish/config.fish`). A RunAtLoad or KeepAlive job starts then. Rename a plist to `*.plist.disabled` to keep it out.
- `launchctl load` ignores a job that is already loaded, so an edit to a loaded plist needs `service reload <name>`. `service restart <name>` also applies it, but then runs the job at once; for a scheduled job that is an extra run. Both stop a run in progress.

### Available Services

| Service | Schedule | Purpose |
|---------|----------|---------|
| `ziplog` | Thursday 12:00 | Compress monitor logs >6 days old, archive by month, backup to `~/Cloud/_inbox/monitor/minimac/` |
| `disk-snapshot` | Sun & Wed 3:00 | Create disk usage snapshot to `~/.local/share/disk-snapshots/` |
| `claude-watchdog` | Every 60s | Watch for a headless `claude` growing without bound. **Observe-only (phase 2): records, bundles forensics, notifies — cannot kill.** See [docs/claude-watchdog.md](docs/claude-watchdog.md) |
| `bookmark-manager` | Daily 2:00 | Sync browser bookmarks |
| `music-backup` | **Off** | `music backup`; its source drive is dead. See "Music streaming" below |
| `sanctuary` | On demand | Rotate encrypted backup directories |
| `copyparty` | Startup | Media server for file sharing |
| `music-mount` | Startup | Read-only `rclone nfsmount` of the server's music at `~/Music/music-server`, for cmus. See "Music streaming" below |
| `cc-transcript-backup` | Daily 3:30 | Copy every Claude Code transcript, zstd-compressed, to `~/Cloud/claude-transcripts/` (ProtonDrive). Adds and updates only, never deletes. See "Crashed Session Titles (ccs)" |
| `freeze-logger` | **Off** (`*.plist.disabled`) | The Nov 2026 freezes are explained and mitigated: see [docs/mac-freezes.md](docs/mac-freezes.md). When on: record load, memory and top processes to `~/.local/share/freeze-logger/`, so a machine freeze leaves the minutes before it. A `ps` that takes over 10s is logged as `HUNG:` and not retried, because a freeze jams every process listing in the kernel. Its root partner `freeze-snapshot` (`services/freeze-logger/root/`, a LaunchDaemon installed with `sudo .../install.sh`, not by `_ENSURE_SERVICES`) flushes the disks and plays a warning sound on such a hang (log in `/Library/Logs/freeze-snapshot/`). It saves no trace: the power-button panic report already names the stuck process. Findings: [.cc/reports/REPORT-mac-freezes-2026-11.md](.cc/reports/REPORT-mac-freezes-2026-11.md) |
| `server-check` | Daily 9:00 | Check the Vultr server: Headscale and its certificate, SSH, Navidrome, and warn if the encrypted disk is left **unlocked**. Silent when healthy; at most one macOS notification, and a click opens `show.sh` in iTerm (shows only, runs nothing). `SERVER_CHECK_DRY=1 services/server-check/script.sh` runs it for real without notifying; `cmds test server-check` fakes the server's answer (`SERVER_CHECK_STATE`) and needs no network |

See `service list` for all installed services. `bin/ziplog` can also be run manually with `ziplog --yes` (skips confirmation prompt).

## Key Patterns

### RC Metadata System
Files in `rcs/` are managed via `rcs/MANIFEST` using `source -> destination` format:
```
tmux.conf -> $HOME/.tmux.conf
ghostty.config -> $HOME/.config/ghostty/config
```
`bin/rcs-sync` parses the MANIFEST; directories are symlinked, files are hard linked. Some `rcs/` files have vestigial `#<[...]>` inline headers that are no longer parsed.

**A hardlink splits whenever either side is replaced rather than written in place** — `sed -i`, the Edit tool, any jj checkout/restore/rebase on the repo side, or an app saving by atomic rename on the live side (Claude Code does, for `/effort` and `/permissions`). The old rule, "repo always wins", silently reverted those app saves. `rcs-sync` instead keeps a per-pair record of the source's content at last sync (`$XDG_STATE_HOME/rcs-sync/records/`) and resolves a split by which side still matches it: both equal → relink; live copy unchanged → repo wins; repo unchanged → **the live copy is copied into the repo** (shows up in `jj diff`); both changed or no record → touch nothing and report a CONFLICT.

It runs from three places: interactive fish startup (a real background process — fish cannot background a *function*, so the old `_ENSURE_RCS &` blocked every `fish -c` for ~280ms), the `ensure-rcs` Edit/Write hook, and a `PostToolUse` Bash hook (`rcs-sync --hook`, ~40ms when nothing split) that reports anything it resolved back into the Claude session. `_ENSURE_RCS` remains as a thin fish wrapper. Tests: `tests/hooks/test_rcs_sync.py`.

**Service plists are resolved the same way.** Each installed `~/Library/LaunchAgents/org.pancia.<name>.plist` pairs with `services/<name>/org.pancia.<name>.plist` (the layout `bin/service` uses), so a `sed -i` on either side is repaired or adopted and reported, with a reminder to `service restart <name>`. A plist that is not installed is left alone. The `ensure-rcs` pre hook blocks Edit/Write on MANIFEST destinations and LaunchAgent plists after resolving symlinks and letter case, so `~/.Config/...` or `~/...` spellings are caught too.

### JS dependency hygiene (pnpm + npm)

Two configs, one policy, covering **different populations**. Both are `rcs/`
entries, so both are tracked and follow a fresh machine.

| File | Covers | Setting |
|---|---|---|
| `rcs/pnpm-config.yaml` → `~/.config/pnpm/config.yaml` | **new** projects | `minimumReleaseAge: 20160` — refuse any version published less than 14 days ago |
| `rcs/npmrc` → `~/.npmrc` | the 17 existing npm/yarn projects | `ignore-scripts=true` — block dependency install hooks |

**pnpm is for new projects only** — nothing was ported. That is exactly why the
npm side exists: pnpm's defaults protect only projects that *use* pnpm, and
`~/projects` is still npm/yarn. `brew 'pnpm'` is in the Brewfile.

Two escape hatches, both needed in practice:

- `npm rebuild <pkg> --ignore-scripts=false` — **the flag is required.**
  `npm rebuild <pkg>` alone honours `ignore-scripts` and does nothing while
  printing *"rebuilt dependencies successfully"*. `work/filament` needs this;
  its `preinstall` is the only real lifecycle hook across `~/projects`.
- `minimumReleaseAgeExclude:` in a project's `pnpm-workspace.yaml`, to exempt a
  package needing an urgent fix. Does **not** cascade to transitive deps.

The reasoning — why 14 days rather than more, why npm expunging malicious
versions makes this prevention rather than delay, what it costs, and three
silent-failure traps each found by experiment — lives in the comments of those
two files. Read them before changing either setting.

### Seed Architecture (Hammerspoon)
Hammerspoon modules in `lib/lua/seeds/` follow a standard interface:
- `start(config)` - Initialize the seed
- `stop()` - Clean up resources
- `engage()` wrapper provides error handling via pcall
- **Never call `hs.reload()` programmatically** - ask the user to reload with `Cmd+Ctrl+R`
- `Cmd+Ctrl+R` is a **soft reload** (`softReload` in `lib/lua/hammerspoon.lua`): it stops the seeds in the `seeds` table and clears only the modules in `seedModules`, then re-runs `hammerspoon.lua`. **Add a new seed to both lists**, or `require` keeps returning its old cached code. `Cmd+Ctrl+Shift+R` is the hard reload.
- To load a new seed without asking for a reload: `timeout 15 hs -c 'package.loaded["seeds.X"]=nil; require("seeds.X"):start({})' </dev/null`. Use this only for a seed that is not loaded yet, or one whose `start()` only binds `hs.urlevent` (copylink, rolevote); any other seed's second `start()` duplicates its timers, eventtaps, hotkeys or menubars, and `{}` drops the config `hammerspoon.lua` passes. **Always redirect stdin from `/dev/null`:** in the Bash tool stdin is a socket that never closes, and `hs` reads it after running the command, so without the redirect it hangs after it has already run (a retry then runs `start()` twice). `timeout` is only a backstop; `hs -t` does not bound this wait.

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

**A git repo that is not opted in** has neither, so two sessions can share its
checkout. `bin/cc-peers` lists the other live sessions there (from Claude Code's
`~/.claude/sessions/<pid>.json`, live by process id) and the files each one wrote
(from its transcript). `vcs-status-for-ai` prints that as a `### PEERS` section,
and `/cc:commit` then scopes the commit and messages any peer whose files it
committed. Tests: `tests/bin/cc-peers/test_cc_peers.py`.

### Session-scoped jj commits (`commit-mine`)

When two Claude sessions share this working copy, **`jj commit` captures the other
session's half-written files too**. Commit with `commit-mine -m "msg"` instead: it replays
only *this* session's recorded Edit/Write edits onto `@-`, and splits a file both sessions
edited. `g run ci`, `ai_jj_commit` and `/cc:commit` route to it on their own when another
live session is here.

- **Bash blind spot:** `rm`/`mv`/`sed -i`/`>` are not journaled. Declare deletions and
  renames with `--also <path>` (whole-path changes only, never content). For a Bash
  content change, `ccjj claim <path>` prints the diff and records it; read the diff first,
  because it can carry another session's writes. `ccjj audit` lists changes no session
  claims.
- **`claude-p` disables hooks** (`--safe-mode`), so a headless agent produces no journal
  at all unless `CLAUDE_P_SAFE=0`.
- Exit `4` means locked or the base moved — retry, it is not an error.

Full mechanism (the journal, Bash windows, liveness, `prune`/`disown`) and why each guard
exists: [docs/cc-jj-sessions.md](docs/cc-jj-sessions.md).

### Crashed Session Titles (ccs)

**REQUIRED: read [docs/ccs.md](docs/ccs.md) before editing `fish/functions/ccs.fish`,
`fish/functions/my-claude-code-wrapper.fish`, `bin/ccs-title-hook`, `bin/ccsave-hook`,
`lib/bash/ccs-hook-lib.sh` or `services/cc-transcript-backup/`.** They share invariants
that look removable and are not: a clean exit is proved by `SessionEnd`, no hook writes
`.cwd`, both hooks gate on identity, and `ccs resume` archives only after the transcript is
in place. Fixes already tried and rejected are listed there too. A script that starts an
interactive session runs `my-claude-code-wrapper` by name. Bare `claude` is the binary, and
`cc` is an abbreviation that expands only when typed; in a non-interactive fish it is the C
compiler. From bash or Python, go through fish: `fish -c 'my-claude-code-wrapper …'`, as
`bin/disk-cleanup` does. Otherwise the session gets no ccs entry, no review and no worktree.

### Session Review
After each interactive Claude Code session, a background Haiku process reviews the session transcript and suggests CLAUDE.md updates. Results are written to `.cc/pending-updates-<timestamp>-<session-id>.md`.

**How it works:**
1. `bin/cc-session-summary` — extracts review-optimized session summary (human messages, file paths, tool use) with 150k char budget
2. `fish/functions/cc-session-review.fish` — sends summary + current CLAUDE.md to Haiku, writes suggestions
3. Triggered automatically by `fish/functions/my-claude-code-wrapper.fish` after `claude` exits (non-interactive invocations skipped)

**Viewing suggestions:** Pending updates appear in `chpwd` output when you cd into a project with pending files (golden/orange highlight). Use `/cc:pending-updates` to automatically find, review, apply, and clean up pending update files in the current directory. Alternatively, manually review files and delete them after applying edits.

### Private per-project config: the work-config vault

**This repo is public.** Private per-project config (work `cmds.rb`, `svc.conf`) lives in
`~/Vaults/work-config/fs-config/<absolute project path>/`; `cmds init` puts anything under
`~/projects/work/` there. Commit in the vault after any change — that is the only backup.
Details: [docs/work-config-vault.md](docs/work-config-vault.md).

### Music streaming (Navidrome + cmus mount)

The **`music-server` skill** (`ai/skills/music-server/SKILL.md`) holds the full notes: the
Vultr server and its two disks, Navidrome, `music push`, the `music-mount` rclone mount,
`bin/cmus-add-new` and scripting cmus. Load it before touching any of those. Rules that
must hold even without it:

- `q remote-sync` (`~/AKR/scripts/remote-sync`) must never get `--delete` back: its old `Music/MyMusic` source is empty.
- Find server disks by DUID, never by `sdN`. A script that writes to `/mnt` must first run `/usr/local/bin/crypt-mounted`; one that writes to `/music` checks `mount | grep -q ' on /music '`. Unmounted, either path is a plain folder on the root disk.
- `/mnt` is encrypted and locks on every restart; only the user unlocks it (`~/bin/mnt`). Auto-unlocking was rejected. The age private key is `~/.config/age/akr-backup.key` and Proton Pass, never the server.
- `/music` stays `noauto` in `/etc/fstab` and is mounted by `/etc/rc.local`: a normal fstab entry that fails fsck drops the boot to single-user mode.
- Any new folder under `/mnt` that holds private data needs group `wheel` and mode 750 or 700; the default 755 is readable by `musicread`.
- `$MUSIC_LIBRARY` must never point at the read-only mount (`$MUSIC_PLAYBACK`).

### Claude Code Project Artifacts

`.cc/` follows the global layout (`plans/`, `reports/`, `scripts/`, `misc/`, `private/`).
`chpwd` and the dashboard list plans from both `.cc/plans/` and the top of `.cc/`.
**This repo is public, so everything in `.cc/` except `.cc/private/` is published on the
next push.**

### Live Transcribe and whisper-serverd

Full notes (build and signing, logs, history, the warm whisper server):
[docs/live-transcribe.md](docs/live-transcribe.md). Test rules:

- Check `pgrep -f LiveTranscribe.app/Contents/MacOS/` first. A test run shares the warm whisper server and slows a live session.
- Use BlackHole as the mic and an `--output-dir` in the scratchpad: the default output, `~/transcripts`, is the real `~/Cloud/transcripts` folder. Never pass `--save-audio`. `.cc/scripts/live-transcribe-tail-repro.sh` does this.

## Quick Reference

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

Hermes is a which-key app launcher; commands live in `rcs/hermes-commands.json`. Command types, submenus, generators, comments and reloading: [docs/hermes.md](docs/hermes.md).

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

### Shell Commands (Fish)
| Command | Action |
|---------|--------|
| `Ctrl+S` | fzfm leader menu (fuzzy finder) |
| `d` | Directory bookmarks |
| `q` | Command registry |
| `z` | Jump to directory |
| `astro` | Astrological transit tracker |
| `ccpu` | Run claude wrapper with /cc:pending-updates (auto-detects jj/git repo) |
| `ccsave [title]` | Save current Claude Code session to `~/Cloud/cc-sessions/` (autogenerates title if omitted); inside the AKR vault it also writes a readable markdown copy to `claude-chats/` via `akr-chat` |
| `ccs list` / `ccs resume` | List/pick this directory's sessions: saved, running and crashed (titled). Picking a running one switches to its pane. See [docs/ccs.md](docs/ccs.md) |
| `ccs old` / `ccs archive` | List this directory's archived sessions (already resumed, or pruned) |
| `ccs prune [--dry-run]` | Archive crashed entries with no surviving transcript, backup, or saved record |
| `commit-mine -m MSG` | Commit only *this* Claude session's edits when sessions share the working copy; `--diff` to preview, `--also PATH` for a Bash-made delete/rename. See [docs/cc-jj-sessions.md](docs/cc-jj-sessions.md) |
| `ccjj audit` | List working-copy changes no session claims (the Bash blind spot) |
| `cc-worktree on\|status\|off` | Opt a repo in to per-session worktree isolation; `on` once per checkout is the whole setup, and `cc` then passes `--worktree` (`cc --no-worktree` opts out for one run). `.worktreeinclude` skips symlinks, so run your installer in the worktree rather than copying `node_modules`. Refuses in `~/dotfiles`. See [docs/cc-worktree.md](docs/cc-worktree.md) |
| `ccjj bash-windows on\|off\|status` | Opt this checkout into recording Bash windows |
| `ccjj claim PATH` | Accept a Bash-made change as your own, after reading the diff it prints; `-n` to preview |
| `ccjj forget PATH` | Drop this session's journal records for a path, when one of them is wedging a commit — an inconsistent record, or a `Write` for a file you since deleted. Records are **moved**, not unlinked (`<journal>/<sid>/forgotten/`), because the edits they describe then silently stop being committed. `-n` to preview. See [.cc/plans/PLAN-ccjj-journal-fixes.md](.cc/plans/PLAN-ccjj-journal-fixes.md) for the three bugs that motivated it |
| `revive` | What each terminal pane was doing before it died, keyed on the iTerm session GUID. Bare `revive` in a restored pane cds back and resumes its Claude session with its original flags, reopens its nvim files and splits, or offers its command back. `revive ls`, `<n>`, `here`, `go <n>`, `live`, `dismiss --all`. See [docs/revive.md](docs/revive.md) |
| `claude-p [flags] [prompt]` | Guarded `claude -p` — hard timeout in its own process group, `.is_error` checking, and `--safe-mode` by default. Drop-in for text/json/stream-json. See the `headless-claude` skill |
| `plainify [-q QUESTION] < reply` | Rewrite an assistant reply shorter and plainer with Haiku: a word budget by kind of reply plus ASD-STE100 Simplified Technical English. Prompt in `ai/templates/plainify.md`; picked on 2026-11-05 over 12 other approaches on 7 real replies. The `/plainify` mod command (`ai/mods/plainify/`, loaded in every session via `CLAUDE_CODE_PLUGIN_DIRS` in `rcs/claude-settings.json`) calls it on the last reply and shows the result in a pane |
| `llm-output [--json]` | Extract the `<output>` envelope body from an LLM reply on stdin; nonzero exit rather than raw text when there isn't one. See the `headless-claude` skill |
| `site-block [list\|add\|rm\|sync]` | Block domains at the resolver level by rendering `misc/blocked-domains` (tracked) into a marked region of `/etc/hosts`. `add`/`rm` edit the list and re-sync; bare `site-block` shows the list and whether `/etc/hosts` still matches it. Entries get both `0.0.0.0` and `::` so a name can't answer over AAAA, an apex domain also picks up its `www.` form, and the first sync leaves a `/etc/hosts.site-block.bak`. **No wildcards** — `/etc/hosts` can't express one, so a site on wildcard DNS (openfront.io is) only loses the names actually listed; `dnsmasq` with `address=/example.com/0.0.0.0` is the upgrade if that gap matters. `sync` needs sudo |
| `disk-cleanup` | Report on the latest disk snapshot (biggest consumers + growth vs a ~30-day-old baseline), then offer a Claude session to help free space. `--no-ai` report only, `--ai` skip the prompt, `--scan` fresh snapshot first. Hermes: `Cmd+Space` → `x` → `d` |
| `claude-watchdog` | Run the runaway-claude watchdog by hand (read-only at phase 2). `CW_PHASE=1` log only; `CW_RSS_MB=200 CW_CPU_PCT=5 CW_MIN_AGE=5` to force detection. Normally launchd runs it every 60s |
| `roleplay-roll` | Pick the roleplay character for the bookends. Here the `roleplay-bookends` mod (`ai/mods/roleplay-bookends`) calls it and has Sonnet write the lines; it is no longer a `UserPromptSubmit` hook, and the main model writes no bookends. Run as a hook (roleplay/ on its own) it **fails open**: any error prints nothing and exits 0. `--list`, `--check`; `--votes` (the mod's call; never by hand) adds a vote id and writes the roll log the `rolevote` seed reads. Cast in `roleplay/roster.tsv`, deliberately *not* in CLAUDE.md. See [docs/claude-roleplay.md](docs/claude-roleplay.md) |
| `service` | LaunchAgent manager (list/start/stop/restart/log/status) |
| `cmds` / work-config vault | Per-directory commands: public `cmds.rb` in `cmds/<path>/`, private ones in `~/Vaults/work-config/fs-config/<path>/`. Commit in the vault after editing — that is the backup. See [docs/work-config-vault.md](docs/work-config-vault.md) |
| `supervise` / `svc` / `svc-tmux` | Restartable dev services (REPLs, watchers): `supervise <name>` runs one in this pane with keys (`r s c q ?`) and a status bar; `svc` inspects/restarts it from anywhere; `svc-tmux up --wait` is how a script or LLM starts them, in a dedicated `tmux -L svc` server. See `wiki/pages/supervise-svc.md` |
| `tab-organize windows` | List open browser windows with tab counts |
| `tab-organize plan [--window ID]` | Generate AI organization plan (editable before execute) |
| `tab-organize check [plan-file]` | Validate a plan and show what it will do, with tab titles |
| `tab-organize execute <plan-file>` | Apply tab organization commands via browser extension |

### Headless Claude calls (`claude-p`, `llm-output`)

The **`headless-claude` skill** (`ai/skills/headless-claude/SKILL.md`) holds the full notes:
`bin/claude-p`, the `<output>` envelope (`lib/python/llm_output.py`, `bin/llm-output`,
`ai/templates/output_contract*.md`), `--json-schema`, SDK callers, and the tests. Load it
before writing or editing any script or service that calls `claude -p` or the Agent SDK.
Rules that must hold even without it:

- Check `.is_error`, never `.subtype` or the exit code.
- Schema output arrives on `.structured_output` (CLI) or `ResultMessage.structured_output` (SDK) — never re-parse `.result`.
- `llm-output` deliberately has no path that returns the raw text. Do not add one.
- Prefer floating model aliases (`haiku`, `sonnet`); dated ids are the retirement trap.
- SDK callers need `cli_path=shutil.which("claude")`, or `--safe-mode` dies as an unknown option in the SDK's bundled CLI.
- These call bare `claude -p` on purpose, because they kill claude by pid and `claude-p` runs it in a new process group: `services/youtube-transcribe/server.py`, `bin/tab-organize`, AKR's `scripts/score-day.py` and `scripts/invoice-from-worklog.py`. Do not migrate them; they pass `--safe-mode` themselves.
- `cc-session-review`'s `grep -q NO_UPDATES_NEEDED` is left alone on purpose; its false positive fails safe.

### Testing
**Always use `cmds test $argv` from the dotfiles root** — never run `pytest` (or `python -m pytest`) directly. The `cmds` script handles virtual environments and dependencies.

```bash
cmds test                      # Run the full suite
cmds test yt                   # Run youtube-transcribe tests
cmds test yt -v                # Verbose output
cmds test yt --cov             # With coverage report
cmds test yt -k "cache"        # Run tests matching pattern
cmds test bin/ytdl/test_ytdl.py  # Target a specific file
cmds test fish/test_trash.py -k restore  # One file, filtered
cmds test bin                  # Run every bin/* component
cmds test -- -k "cache"        # pytest flags with no component: `--` first
```

File paths are relative to `tests/` (a leading `tests/` is also accepted). Flags
after a component or file pass straight to pytest. A flag in first place is read by
`cmds` itself and fails as an invalid option, so put `--` before it. Do not write
`cmds test fish -- -k foo`: the `--` then reaches pytest, which reads `-k` as a file.

Several targets work: `cmds test fish/test_a.py hooks/test_b.py -k x`. Every argument
before the first flag is a target. A target that does not exist exits 2 and runs nothing.
Before that fix, a second path went to pytest unresolved and the run collected nothing.
Each component runs with its own deps, and the summary covers them all.
`tests/fish/test_fish_syntax.py` runs `fish -n` on every fish file; what it cannot catch is in the fish skill.

**Every test tree must be registered in `COMPONENTS`** (`lib/python/run_tests.py`).
`run_all()` iterates that dict, so a directory under `tests/` that isn't listed is
not "not yet wired up" — it never runs at all, and rots silently. Four trees sat
unregistered for months; when they were finally registered, `tests/hooks` failed
immediately because it still asserted the pre-XDG `~/.tmux.conf` destination.

The component table (aliases, runners, deps) and the aggregate summary: [docs/testing.md](docs/testing.md). The `fish` component takes about 3 min, longer than the Bash tool's 2 min default timeout: run one file when you can, and give a full run a longer timeout.

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

## Other Tools

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
| [docs/revive.md](docs/revive.md) | Per-pane terminal journal: why the iTerm session GUID is the only identity that survives a reboot, the one-record-per-pane store and the rename that makes a ghost, what `fish_exit` buys, and the two gotchas — iTerm's `tab` class shadowing the AppleScript separator, and a zombie answering `ps` |
| [docs/work-config-vault.md](docs/work-config-vault.md) | Private per-project config vault: layout, lookup order for `cmds` and the svc tools, the commit-to-back-up rule, the hook's traps (global hooksPath, ignored `.githooks`), restore |
| [docs/mac-freezes.md](docs/mac-freezes.md) | Nov 2026 hard freezes: a kernel exec self-deadlock triggered by Game Mode (Shadow PC) switching iTerm2's coalition, the fix, how to read a new `forceReset` report, and the diagnostics kept off in `services/freeze-logger/` |
| [docs/claude-watchdog.md](docs/claude-watchdog.md) | Runaway-headless-`claude` watchdog: phases, classification, bundle redaction, tests |
| [docs/claude-roleplay.md](docs/claude-roleplay.md) | Claude Code character roleplay: the external roster, two-stage roll, why the cast is not inlined into CLAUDE.md, and the four symlinks that keep `roleplay/` self-contained. A symlink into `roleplay/docs/` |
| [roleplay/README.md](roleplay/README.md) | Install guide for handing the roleplay system to someone else — written for a stranger, no dotfiles assumed |
| [docs/ccs.md](docs/ccs.md) | Crashed session titles: entries, hooks, transcript copies and restore, and the fixes rejected |
| [docs/live-transcribe.md](docs/live-transcribe.md) | Live Transcribe app and engine, logs, history, and the warm whisper server |
| [docs/hermes.md](docs/hermes.md) | Hermes command types, submenus, generators, reserved keys, reloading |
| [docs/testing.md](docs/testing.md) | Test components, aliases, runners and the aggregate summary |
| skill `music-server` | Music server, Navidrome, the cmus mount and scripting cmus (`ai/skills/music-server/SKILL.md`) |
| skill `headless-claude` | `claude-p`, the `<output>` envelope, `--json-schema`, SDK callers (`ai/skills/headless-claude/SKILL.md`) |
