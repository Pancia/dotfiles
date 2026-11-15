# Review: five retro proposals from the freeze session

Date: 2026-11-15. Scope: proposals 1 to 5 of the freeze-session retrospective.
The review itself changed nothing in the project. The item-1 prototype and its
scenario tests ran in a throwaway copy.

**Update, same day:** all five revised fixes, and the marker-doc fix, are now
implemented. The prototype is `bash_overwrites` in `lib/python/ccjj.py`. Its
scenario tests are the `test_overwrite_*`, `test_cannot_place_with_peer_*` and
`test_shared_path_note_*` tests in `tests/lib/python/test_ccjj.py`. The
`.cc/misc/retro-freeze-session/` copies named below were removed.

| # | Proposal | Verdict |
|---|---|---|
| 1 | Warn at once when Bash changes a file with this session's records | **Changed**: yes, but with a disk-vs-newest-record test, and as `additionalContext` |
| 2 | Reword `services/*/*.plist` to "any depth" | **Changed**: fix the code to one level (`-maxdepth 2`) instead; then the docs are true |
| 3 | Brief line "edit only with Edit or Write" | **Changed**: one sentence in the existing rule first; the brief line is optional |
| 4 | "Test a script by its path" | **Changed**: broaden to "test the exact command", put it beside the CHECKED rule |
| 5 | Mark an untested-hypothesis fix as an experiment with a prediction | **Confirmed**, reuse the 🔮 mark |

## 1. ccjj warning when Bash changes a file you also Edited

**Diagnosis: true, with one correction.** Nothing warns at Bash time.
`cmd_bash_window` writes a `.win` file and prints nothing. No gated or disabled
warning exists. But the commit-time message is already good: the "cannot place
your edit" error in `anchored_replace` says "Most often this means YOU also
changed ... through Bash" and names `ccjj claim`. So the gap is *timing*, plus one
wrong hint, not a missing diagnosis.

**What happens today (each reproduced in a scratch repo, `test_proto_warn.py`
tests H, J and K, which pass on the unpatched code):**

- Edit, then sed, then a later Edit that anchors on the sed text: `build()` dies
  in `anchored_replace` before the exit-5 check runs. The whole commit stops,
  including unrelated paths (test H). That is the session's failure.
- Edit, then sed, with no later Edit: exit 5 stops the commit and offers
  `ccjj claim f.txt`. That route already works (test J).
- A peer also has records on the path (the CLAUDE.md case): `claim` refuses with
  exit 1. Without a later Edit, the commit then takes your Edit hunks, exits 0, and
  leaves the sed in the working copy with a note that it "can still be claimed"
  (test K). With a later Edit, the die message says "`ccjj claim` replaces your
  records". Both hints are wrong for this case: `claim` refuses, and `claim --force`
  would take the peer's hunks. Both messages should say "undo and redo with Edit"
  when `peer_record_paths` names the path. That is a cheap fix in its own right, and
  it runs only on the error path.

**The naive rule mis-fires.** "Window changed a path that has my records" fires on
the session's *own* Edits, because a window spans everything between two Bash
calls. It also fires on a peer's Edit inside the window.

**Revised rule (prototyped in `bash_overwrites.patch.txt`; tests A to I pass):**
warn for a path when

1. this Bash call's window changed it, and
2. this session has Edit/Write records for it, and
3. the file on disk differs from what the *newest* record on that path, from any
   session, left (`_record_result`, which already exists).

Condition 3 makes it silent on own Edits (A) and on a peer's Edit inside the window
(C). It warns once per Bash change, not on every later call (B). It is silent after
`ccjj claim` (E). It tells the agent to undo and redo with Edit when a peer has
records (F), and offers `claim` otherwise.

**Surfacing.** The hooks docs (code.claude.com/docs/en/hooks, read in part) name
UserPromptSubmit, UserPromptExpansion, SessionStart and PostModelSwitch as the
events whose plain stdout reaches the model. PostToolUse is not on that list, so
plain stdout most likely does not reach it. That is an inference: the PostToolUse
section itself does not say. The field table says `systemMessage` is "shown to the
user". The PostToolUse section does confirm `additionalContext` ("added to Claude's
context alongside the tool result"). Use
`{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ...}}`
on stdout, exit 0. `bin/rcs-sync --hook` already does exactly this
in the same hook slot. Exit 2 would also reach the model, but it breaks the gate's
"always exit 0" rule, so do not use it.

**Cost.** Measured end to end on a 40-file scratch repo, median of 8:

| Bash call | today | prototype |
|---|---|---|
| changed nothing | 68 ms | 68 ms |
| changed a file, session has records | 108 ms | 128 ms |
| changed a file, session has no records | no extra jj process (test I) | no extra jj process (test I) |

The extra cost is one read-only `jj diff --ignore-working-copy` (about 20 ms) on
calls that changed the working copy, and only when the session has records. The
existing one-jj-process test still passes, because it has no records. The full ccjj
suite passes on the prototype copy (207 passed, 1 xfailed).

**A worse defect in the same code: the contention gate is stuck open.**
`.jj/ccjj-contended` in this checkout was created on 2026-07-31 00:33 and has never
been removed (birth time equals mtime). Only `retire-all` and `bash-windows off`
remove it. The `cmd_nudge` comment says "Clearing belongs where the whole picture
is known (prune / retire-all)", but `cmd_prune` never touches it. `retire-all` runs
only after a whole-copy `ai_jj_commit`, and none has cleared it in 3.5 months. So
gate 2 of `bin/ccjj-bash-window` is in effect always open here. Python and a jj
snapshot run on every Bash call in `~/dotfiles`. On the 40-file scratch repo that
cost about 70 ms when nothing changed and about 110 ms when something did; the real
4,000-file repo was not timed end to end. The doc's "~78% of active minutes"
saving does not happen in practice.

This interacts with the new warning, which runs only behind that gate. If the
marker is cleared when a session is alone, a Bash change made then gets no window
and no warning. That costs nothing at commit time while the session stays alone
(the whole-copy commit takes it), but a peer that arrives later turns it into the
test-D case: the sed is left behind. **Recommendation: leave the marker as it is,
and correct the `cmd_nudge` comment and the cost section of
`docs/cc-jj-sessions.md`** to say the marker is cleared only by `retire-all` and
`bash-windows off`. An always-open gate keeps every window claimable and keeps the
warning working; the price is the per-call cost above.

**Known gaps of the warning (state them in the doc):**

- The first Bash call of a session only sets a baseline. A sed in that call gets no
  warning, and the commit then takes the Edits and leaves the sed behind, exit 0,
  with only the "claimed by no session" note (test D).
- A held lockdir skips the window. The warning arrives one call late, not never.
- If a peer Edits the file *after* your sed and inside the same window, condition 3
  sees the peer's result on disk and stays silent.
- The "claimed by no session" note prints "`ccjj bash-windows on` makes Bash-made
  changes recoverable" whenever no window covers the path, even when windows are
  already on (seen in test D). Minor, but it misleads.

**Smaller alternative considered.** The Edit hook (`cmd_record_edit`) could compare
each new record's `original` with the result of this session's previous record on
the path. It needs no jj call and works uncontended. But it fires one step late, at
the next Edit, and misses the "Bash change last" case. The Bash-hook version is
better. The die-message fix above is worth doing whichever is chosen.

## 2. `_ENSURE_SERVICES` depth

**Diagnosis: true.** `fish/config.fish` runs
`find $HOME/dotfiles/services -type f -name '*.plist'`, which has no depth limit.
CLAUDE.md says `services/*/*.plist` in two places: the LaunchAgent bullet (about
line 69) and the music-backup bullet (about line 431). The comment in
`services/freeze-logger/root/org.pancia.freeze-snapshot.plist.in` already says
`services/**/*.plist` correctly. `docs/services.md` makes no depth claim.

**Nothing relies on depth.** All 24 installed plists sit one level down.
`find -maxdepth 2` gives the identical set. The rest of the tooling assumes one
level: `bin/service` builds `services/<name>/<label>.plist`, and `rcs-sync` pairs
the same layout. So a deeper plist would be loaded by fish but be invisible to
`service`. The only deeper plist-like file is the root LaunchDaemon, which had to use
`.plist.in` to dodge exactly this.

**Revised fix:** add `-maxdepth 2` to that `find` and keep `-type f`. Then the
CLAUDE.md wording is true as written, and a future root plist in a subfolder cannot
be loaded as a user agent by accident. Update the `.plist.in` comment to match, and
keep the `.plist.in` name as a second guard. Keep `-type f`: it is load-bearing.
`services/inari-wake-morning/org.pancia.inari-wake-morning.plist` is a symlink to the
`services/inari/` copy, and `-type f` is what keeps it out. A switch to a fish glob
would bring it back in. If you prefer docs only, write "any `*.plist` file under
`services/`, at any depth (symlinks are skipped)".

**Side finding, not blocking.** `_ENSURE_SERVICES &`, `_ENSURE_CONF_D &` and
`_ENSURE_COMPLETIONS &` do not run in the background. Fish runs a function in the
foreground even with `&` (verified on fish 4.1.2), and the comment above them says
so for rcs-sync. A dry replica of `_ENSURE_SERVICES` takes about 0.12 s, on every
fish start, including each `fish -c` and `trash`. The "(in background)" comment is
wrong for these three.

## 3. Bash edits by subagents

**Diagnosis: partly true.** The rule already exists: "In a jj repo, make edits with
Edit or Write, not Bash scripts" (since 2026-11-10). Agents do load the global
file. This review agent has it in its own context. So the agents most likely broke
a rule that they had read. Two things can weaken it:

- In auto mode the harness adds a message that invites `sed`, heredocs and short
  scripts for "small, mechanical file changes". This agent has that message in its
  own context, later than CLAUDE.md. Whether the freeze session and its agents ran
  in auto mode is not known.
- The rule's own text says "Use Bash only for large mechanical edits", which a
  script that rewrites a report can claim to be.

The parent session broke the same rule (item 1), so a brief line alone fixes only
half the cases. Not checked: which reports the agents changed, and whether each was
made with Write and then changed by Python, or made by Python only. The freeze
reports were all added in commit 5e5e9d09, which does not tell the two apart. For a
file made wholly by Bash, `commit-mine --also` is the documented route, not a fault.
The real fault is a mix: Edit or Write first, then Bash on the same file.

**Revised fix.** Add two sentences to "Edits made through Bash", after "not Bash
scripts.":

> This holds in auto mode too, which suggests `sed` and heredocs. A Bash change
> to a file you changed with Edit or Write needs `ccjj claim` before your next
> Edit to it. If another session also edits that file, undo the change and redo
> it with Edit.

This agrees with the existing "claim them as below" bullet and with the item 1
warning, which offers the same `claim`. It does not forbid the large mechanical
edit that the rule allows.

Optional, and cheap: at the end of the "Subagents:" bullet, add "In a jj repo, the
brief also says: edit files only with Edit or Write." A brief has more weight than a
default that the agent must remember. Item 1's warning backs up both.

## 4. "Test it the way I will run it"

**Diagnosis: true.** `install.sh` is executable now. When the user ran it, it was
not, so `sudo path/install.sh` failed. `bash install.sh` does not need the bit.

**"By its path" is too narrow.** The same class of failure covers the folder it
runs from, `sudo`, and fish versus the zsh that the Bash tool runs. The failure is a
`CHECKED` claim about a command other than the one given to the user. The best home
is the CHECKED paragraph in "Recaps", which already says "Never imply done when
nothing was checked". Add:

> When you give me a command to run, test that exact command first. A script I
> start by its path must be executable. If you cannot run it as I will, such as
> with `sudo`, say so under `UNCHECKED`.

Each sentence is under 20 words. The middle sentence names the failure that
happened, and you can drop it to keep the rule general.

**Mechanical complement (optional).** A test could check that tracked files with a
`#!` line under `bin/` and `services/` have the executable bit. Today four do not:
`bin/claude_to_md.py`, `services/lakshmi/serve.py`, `services/lan-gate/gate.py`
and `services/youtube-transcribe/server.py`. Some of these may be started as
`python3 file`, so such a test needs an allowlist. The value is moderate. The rule is the main fix.

## 5. Hypotheses presented as fixes

**Diagnosis: true.** No rule covers this. 🔮 exists only in "Where next", meaning "a
guess you have not checked". "Give your recommendation if you have one. Do not
invent one." does not cover it either. Reuse 🔮 so the mark keeps one meaning. Add
to "Questions to me", after the run-command paragraph:

> A question can propose a fix for a cause you have not proved. Then mark it 🔮
> and call it an experiment. Say what result you expect, and what a different
> result means.

Example of the effect: **Q7 (App Nap off)** 🔮 experiment. "I expect no freeze for
a week. A freeze means App Nap is not the cause."

## Effort

| Item | Effort |
|---|---|
| 1: warning in `cmd_bash_window`, its tests, a doc paragraph | about 1 hour; the prototype (`bash_overwrites.patch.txt`) and 10 scenario tests exist |
| 1: peer-aware hint in the `anchored_replace` die and the commit note | 20 minutes |
| 1: correct the contended-marker comment and the doc's cost section | 15 minutes |
| 2: `-maxdepth 2` and comment | 5 minutes |
| 3 to 5: three wording edits in `rcs/claude-user-claude.md` | 10 minutes |
