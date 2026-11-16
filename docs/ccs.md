# Crashed session titles (ccs)

Every `claude` started through the wrapper registers an entry in
`$XDG_STATE_HOME/claude-sessions/open/`. A clean exit deletes it, so an entry whose
process is gone marks a crash. Resuming one moves it to `archive/`, which `ccs old` lists.

**A clean exit is proved by `SessionEnd`, not by claude returning.** `ccs-title-hook --end`
sets `.ended` (not for `/clear` or `/resume`, which keep the process), and the wrapper's
`_ccs_open_finish` deletes only an ended entry or one with no session id. The id match is not
enough to set it: a nested `claude -p --resume $CLAUDE_SESSION_ID` ends with the parent's id,
so `--end` also requires `_ccs_is_top_claude` (`lib/bash/ccs-hook-lib.sh`, shared with
ccsave-hook). A claude killed under a live shell (OOM, segfault) returns too, and used to lose
its entry; now the entry is kept and marked `.claude_exited`, which `_ccs_open_scan` lists as
crashed even though its pid (the shell) is alive. Ctrl-Z also returns: fish carries on with
the wrapper function when its job stops. The wrapper spots the new stopped job (`jobs -p`
before and after) and skips the review and finalize; `_ccs_open_scan` retires the entry through
`_ccs_open_finalize` once SessionEnd has marked it. `.cwd` is the registered key (the parent repo
for a worktree) and no hook writes it: the hook payload's cwd drifts into worktrees and
subfolders, and writing it hid entries from `ccs list` at the root. The wrapper finds the
transcript by id (`_ccs_session_jsonl`) instead. `ccs resume` archives only after the
transcript is in place. With no recorded `transcript_path` it restores to the folder the
nightly copy sits in, else the folder of the entry's cwd (Claude Code turns every
non-alphanumeric character into `-`, and hashes paths over 200 characters). It takes the
newest of the local copy, the nightly copy and a `ccsave` copy: the local one is throttled, so
after a crash the nightly one can hold more. Tests:
`tests/fish/test_ccs_session_safety.py`, `tests/hooks/test_ccs_title_hook.py`.

**Off-Mac copy:** `services/cc-transcript-backup` zstd-copies every transcript under
`~/.claude/projects`, plus `history.jsonl` and the ccs entries, to `~/Cloud/claude-transcripts/`
nightly at 3:30. It adds and updates, **never deletes**, so a chat outlives Claude Code's
one-year `cleanupPeriodDays`. Copies keep the original's mtime, read **before** compressing
(a live session can append during zstd), and compare whole seconds: zstd drops sub-second
time, so `-nt` re-copied everything each night. `ccs-state/` gets the entries and the hook's
local copies, which hold the only copy of chats pruned before this job existed.

`ccs list` shows crashed sessions with real titles, not just `crashed <date>`. A crash is
usually power loss, so nothing can run afterwards — the title has to already be on disk:

- Claude Code writes its own title into the transcript (`{"type":"ai-title","aiTitle":...}`,
  refreshed as the session drifts). `_ccs_open_scan` reads the last one.
- `bin/ccs-title-hook` (a `Stop` hook) copies it into the session's entry file each turn, so
  it outlives the transcript. It also keeps a local zstd copy, for **every** session, entry
  or not (plain `claude`, the desktop app, IDE), and unthrottled at `SessionEnd`, in
  `$XDG_STATE_HOME/claude-sessions/transcripts/` — deliberately *not* `~/Cloud`, which is a
  ProtonDrive symlink. That copy is throttled to one write per 10 minutes, so it can lag the
  live transcript by up to that much. `ccs resume` puts it back via
  `_ccs_restore_transcript` before resuming, since `--resume` needs the real file in
  `~/.claude/projects/`.
- `bin/ccsave-hook` (a `SessionStart` hook) stamps the real `session_id` into the entry,
  **write-once** — except on `/clear` and compaction (`.source`), which start a new session
  id in the same terminal and so must be followed, or ccs would keep pointing at the
  pre-`/clear` conversation. A rotation clears the recorded title too. It also follows
  `/resume` (`source=resume`), but only when the wrapper's pid is the hook's grandparent
  or great-grandparent, because a nested `claude -p --resume` reports the same source.
  Without that, an entry stays on the empty pre-`/resume` id and its real conversation
  looks lost. Tests: `tests/hooks/test_ccsave_hook.py`.
- Both hooks gate on identity, because `CCS_ENTRY_FILE` is inherited by every descendant and
  `claude -p` runs hooks too: without it a nested helper session would overwrite the parent's
  id or title. A nested session always reports `source=startup`, never `clear`.
- `ccs rename` on a crashed session sets `.title_manual`, which stops the hook overwriting it.
- The wrapper exports `CCS_ENTRY_FILE`; if it's unset, both hooks skip the entry (the
  transcript copy still runs). `ccsave` keys its save on the entry's `.cwd`, not the
  current folder, and finds the transcript by id.

**Known limitation:** if you quit a session in the millisecond window while its `Stop` hook is
mid-write, the hook can recreate the entry that `_ccs_open_finalize` just deleted, leaving a
phantom `crashed` row in `ccs list`. Delete the entry from
`$XDG_STATE_HOME/claude-sessions/open/` by hand. Every fix considered (tombstone files, pid
checks) introduced a worse failure mode than the one it closed.
