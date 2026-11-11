# Review: three retro fixes (ccjj claim hint, Edit-over-Bash rule, disk snapshot dir)

Date: 2026-11-10. Method: read the code, then ran behaviour tests on copies in a
scratch folder. Nothing in the repo was changed except this file.

## Item 1 — `ccjj claim` hides the `--force` hint above the diff

**Verdict: confirmed, widened to a second refusal.**

Diagnosis is true. Captured output of the current code (claim refused for a
window-only peer): the reason and both hints come first, the unified diff comes
last, so the last line is a diff line (`+p-changed`). `tail -1` shows nothing
useful.

One nuance: `die()` writes to stderr. `cmd | tail -1` without `2>&1` only tails
stdout, so the agent must have merged stderr. The fix still holds; it only matters
for merged output or a human reading the bottom of the terminal.

Same shape elsewhere: `also_refusal()` (the `commit-mine --also` refusal, around
line 2134) ends with "What would be committed:" and then the diff. Fix both.

Nothing parses the layout. Tests use substring checks only (`"under your name"`,
`"may not have touched"`, `"A-PERL"`, `"Bash span only: S2 (live)"`,
`"commit-mine --no-claim"`). `commit-mine` is a plain `exec`. No hook reads this
text. `die()` order matters only in that it prints one message; printing the diff
with `print(..., file=sys.stderr)` before `die()` keeps the exit code.

Tested in a copy: diff first, then the reason, then one combined last line.
The whole ccjj suite passes on the patched copy (191 passed, 1 xfailed). The
last line is now:

    If all of the diff above is yours: `ccjj claim --force peer.txt`. If not: `commit-mine --no-claim`.

Revised fix:

- Claim: print a one-line header, then the diff, to stderr. Then `die()` with the
  reason, and end with ONE line that holds both next steps and the exact command.
  Two hint lines defeat `tail -1`, which is why the current second hint is not enough.
- Change "the diff below" to "the diff above".
- Quote the path in the hint (`shlex.quote`), and keep `--session` in it when the
  call had one.
- `also_refusal()`: move the diff up, after the rows, and put the `--force` text
  last on one line. In the tested copy its last line was still
  "another session has records on.", which is not actionable on its own.
- Do not repeat the hint above and below the diff. It is two copies of one text
  for no gain once the order is right.

## Item 2 — CLAUDE.md: use Edit, not Bash scripts, in a shared jj repo

**Verdict: changed (wider trigger, different wording).**

The claim is true. `ccjj record-edit` (PostToolUse on Edit/Write) records every
successful edit in any jj repo, without opt-in. `commit-mine` replays records hunk
by hunk. For a path in `mine`, commit does not consult peers' Bash windows at all,
so an ended peer's overlapping span does not block it. The one stop that remains:
if the file on disk differs from what the records rebuild (other unrecorded
changes in the same file) and this session's own window covers it, commit exits 5
and asks for a claim. That is rare and correct.

The trigger is wrong. The proposed sentence keys on "the ccjj nudge reports other
live sessions". The nudge only counts LIVE sessions (`session_is_live`). In this
incident the blocker was an ENDED session, which the nudge never mentions. A
session that starts after the edit is also missed. Edit/Write costs nothing in a
repo with no peers, so no condition is needed beyond "jj repo".

No contradiction inside the file. It does narrow the harness default that invites
`sed`/heredoc edits, and that is the point. `~/.claude/CLAUDE.md` is a hard link
to `rcs/claude-user-claude.md` (same inode, link count 2).

Revised fix: after "Bash edits are allowed." on line 162, add:

    In a jj repo, make edits with Edit or Write, not Bash scripts.
    Those hooks record the edit, so `commit-mine` takes it with no claim.
    Use Bash only for large mechanical edits, and claim them as below.

## Item 3 — disk-cleanup: allow a snapshot folder override

**Verdict: rejected as unneeded; if done anyway, do it in all three scripts.**

Faking `HOME` already works for report tests. Tested: a copy of `disk-cleanup`
with `HOME=<fake>` and two fixture snapshots gave a correct report (top list,
baseline, growth from `disk-snapshot-diff`) with `--no-ai`.

Traps found with HOME-faking:

- `REPORT_DIR` uses `XDG_CACHE_HOME`, which is set in the real environment, so a
  fake-HOME run writes its report into the real cache. Set `XDG_CACHE_HOME` too.
- `--scan` dies loudly, because `SCAN_SCRIPT` is `$HOME/dotfiles/...`. This is a
  clear failure, not a silent one.
- Fixture paths must use the fake HOME, because section roots expand `~` with
  `$HOME`.

`disk-snapshot-diff` also hardcodes `SNAP_DIR`, but `disk-cleanup` passes it full
paths, so only its standalone date-stem use reads that folder. The launchd plist
needs nothing.

The partial-override trap is real. If only `disk-cleanup` honours a variable,
`--scan` writes to the real folder and the report reads the fake one. The report
then shows an old snapshot with no error. Also, the notes file lives in the
snapshot folder, so it moves with an override.

Revised fix: none required. If wanted, use one line in each of the three scripts,
`${DISK_SNAPSHOT_DIR:-$HOME/.local/share/disk-snapshots}`. The repo already uses
this pattern (`SHADOW_PCAP_DIR`, `CW_STATE_DIR`, `RCS_STATE_DIR`). A smaller and
more useful change is to find `SCAN_SCRIPT` and `DIFF_BIN` from the script's own
folder instead of `$HOME/dotfiles`. Then a test of a copy uses its sibling copies,
and a fake HOME no longer breaks `--scan`.
