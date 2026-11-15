# Review: roleplay vote ids (roleplay-roll, rolevote.lua, tests, CLAUDE.md)

Date: 2026-11-15
Scope: uncommitted changes to `roleplay/bin/roleplay-roll`,
`roleplay/tests/test_roleplay_roll.py`, `lib/lua/seeds/rolevote.lua` (new),
`lib/lua/hammerspoon.lua` (one `engage` line), `rcs/claude-user-claude.md`
(the "Format" section).

Baseline: `cmds test roleplay` passes, 86 tests. No correctness bug that breaks
the main path was found. The findings below are ranked most severe first.

How things were checked:
- The hook was run directly, about 4,600 times, under `/bin/bash` 3.2 (what the
  tests use, because their PATH is `/usr/bin:/bin`) and `/opt/local/bin/bash`
  5.3 (first on the real PATH, so what Claude Code runs).
- `rolevote.lua` was loaded in plain `lua5.4` with a stub `hs` table. Its two
  URL handlers were called directly, with scratch `votes`/`rolls` paths. No
  `hammerspoon://` URL was opened.
- Scratch files: `/private/tmp/claude-501/-Users-anthony-dotfiles/80e88030-4264-48cb-bb9e-70114583fa20/scratchpad/rv/`
  (`sample.sh`, `lua_harness.lua`, mutated copies `mut-nodiv`, `mut-colon`, `lean-roll`).

Side effect of this review: one mutation run wrote a single line to the real
`~/.local/state/roleplay/rolls.tsv`, because the shell's `XDG_STATE_HOME` points
at the real state dir. The line is `2026-11-15 14:27:18  63q5  Hermes  MYTH`. It
is harmless: no vote can reference it. It was left in place, because the brief
says to edit nothing but this report. Delete it by hand if you want a clean log.

---

## 1. A vote with an unknown id is recorded as if it worked (medium)

`rolevote.lua`, `r` handler. If `lookup(id)` finds nothing, the handler still
appends a row with an empty name. The alert then reads `+ character zzzz`. It
looks like a normal success, so the user cannot tell the vote is orphaned.

When this happens:
- The model copies the example id `k3f2` from CLAUDE.md, or writes a wrong id.
- The roll log could not be written. That failure is silent on purpose (the hook
  fails open), but the hook still puts the id into the tag. So the model still
  emits links, and every vote on that roll is orphaned.
- `XDG_STATE_HOME` is set to anything other than `~/.local/state` in the hook's
  environment. The bash side honours it. The Lua side hard-codes
  `$HOME/.local/state/roleplay`. Today the two agree: fish sets it to that value,
  and the unset default is the same path.

Confirmed by running. Harness output:
`r v=zzzz1 -> + character zzzz` and the row
`…  zzzz  opener  up  character  (empty)  (empty)`.

Fix: when `lookup` returns nil, show a distinct alert, for example
"rolevote: unknown id zzzz (logged)". Still write the row, or write it to a
separate file, so a later roll-log repair can match it. Also consider having the
hook leave ` || vote id:` out of the tag when the log write fails. The
"no vote id → no links" rule in CLAUDE.md then does the right thing.

## 2. Two test gaps let real breakage pass (medium)

a) **"Empty disables logging" is never tested.** Every hook-mode test goes
through `run()`, which always sets `ROLEPLAY_ROLL_LOG`. (`_roll()` bypasses
`run()`, but only with `--plain`, which never logs.) No test runs hook mode with
it empty and then checks that no file appears. A mutation from
`${ROLEPLAY_ROLL_LOG-…}` to `${ROLEPLAY_ROLL_LOG:-…}` makes the empty value fall
through to the default path.

- Confirmed by running: the mutated copy `mut-colon`, run with
  `ROLEPLAY_ROLL_LOG=` empty, wrote a row to the default log. In my shell that
  path came from the inherited `XDG_STATE_HOME`, which is the real state dir.
  This is the side effect noted above.
- From reading the tests, not run: the suite would still pass under this
  mutation. Each hook-mode test would then write to the real
  `$HOME/.local/state/roleplay/rolls.tsv`. The reason is that `run()` passes the
  real `HOME` and no `XDG_STATE_HOME`. I did not run the suite against the
  mutant, because it would write to the real log.
Fix: in `run()`, set `HOME` and `XDG_STATE_HOME` to a `tmp_path`. Add one test
that runs hook mode with `log=""` and asserts that the state dir is still empty.
Add one test with `ROLEPLAY_ROLL_LOG` unset and `XDG_STATE_HOME=tmp`, asserting
that `tmp/roleplay/rolls.tsv` gets the row. Nothing tests that default branch
today.

b) **`test_vote_ids_differ_between_rolls` cannot tell a 4-character id from a
1-character one.** It asks for more than 5 distinct ids in 10 rolls. A mutation
that drops `n=$(( n / 36 ))` gives ids like `aaaa`, `2222`, `wwww`: 36 possible
values instead of 1,679,616. Confirmed by running `mut-nodiv` directly: one
sample of 10 rolls gave 7 distinct ids, which meets the test's threshold. With
36 values, 10 rolls give about 8.8 distinct ids on average, so the test passes
nearly always. I did not run the suite against the mutant.
Fix: assert on the shape, not only the spread. For example, over about 50
rolls, require more than 10 distinct values at each of the 4 positions, or
require that at least one id has 2 or more different characters. A seeded check
does not work, because the id ignores `ROLEPLAY_SEED` (see 7).

c) **No tests for `rolevote.lua`.** Its parsing, slot table and lookup are pure
Lua, and they run under plain `lua5.4` with a five-line `hs` stub (see
`lua_harness.lua` in the scratch dir). No component in `lib/python/run_tests.py`
covers it. Suggested: a small pytest that runs `lua5.4` on a harness like that
one and checks the rows in `votes.tsv`.

## 3. Added hook latency: about 7 ms per prompt, about 4 ms avoidable (low-medium)

Measured over 100 runs each, against the real roster:

| bash | before | after | after, without `dirname`/`mkdir` forks |
|---|---|---|---|
| 3.2 (`/bin/bash`) | 12.4 ms | 19.4 ms | 15.3 ms |
| 5.3 (`/opt/local/bin/bash`, real PATH) | 15.6 ms | 22.3 ms | 18.2 ms |

The new code forks `dirname` (plus a subshell), `mkdir` and `date` on every
prompt. Replace `"$(dirname -- "$log")"` with `"${log%/*}"`, and guard the mkdir
with `[ -d "${log%/*}" ] || mkdir -p …`. That saves about 4 ms, as measured in
`lean-roll`. `date` is the remaining fork. bash 3.2 has no `printf '%(…)T'`, and
BSD awk has no `strftime`, so I found no clean way to remove it. Keeping it is
reasonable.

Caveat: `${log%/*}` gives the wrong answer for a bare filename with no slash.
Guard it with `case $log in */*)`.

## 4. `rate` rows have 6 columns when `line` is missing (low)

`append({…, name, params.line})`: when `params.line` is nil, it is the last
element. So the table has 6 entries, and `ipairs` and `table.concat` write 6
fields. The header comment promises 7. Confirmed: the harness row for
`rate?vote=up&kind=character&name=Holo` has 6 tab-separated fields. Any reader
that splits on tabs and indexes field 7 gets nothing or an error.
Fix: `params.line or ""`.

## 5. The header comment calls column 3 "slot", but it stores place (low)

`votes.tsv` column 3 holds `opener`/`closer`, not the slot digit 1–8. Confirmed
in the harness output. Rename it in the comment to `place`, or store the digit.

## 6. Id reuse grows over time, and votes do not record which roll they mean (low)

Collision maths: 4 base-36 characters give 1,679,616 ids. At about 100 prompts a
day, a year is about 36,500 rolls, which gives about 400 pairs of rolls that
share an id. About 2 % of ids are then shared. "Newest match wins" picks the
wrong roll only if a later roll reused the id before the vote was cast. That is
rare, because votes come soon after the roll.

The documented recovery is "search the transcripts for `r?v=<id>`". That gets
ambiguous for shared ids. `votes.tsv` does not record the roll's time, so the
ambiguity cannot be resolved later.
Fix (cheap): have `lookup` also return the roll's timestamp, and write it into
the vote row. A 5th character would cut collisions 36-fold, at the cost of
about 1 token per link.

Distribution, confirmed by running 2,000 rolls per bash:
- bash 3.2: 2,000 unique ids.
- bash 5.3: 1,999 unique ids. One collision, which matches the expected 1.2.
- Every position used all 36 characters. Bucket counts ran 33–75 against an
  expected 55.6, which is normal spread.
- Modulo bias from `2^30 % 36^4` is 0.16 %, which is negligible.

## 7. `ROLEPLAY_SEED` no longer makes hook output reproducible (low)

The vote id comes from `$RANDOM` after the seed is fixed, so it changes on every
run even with `ROLEPLAY_SEED` set. The header says the seed makes "a roll
reproducible". That is still true for the character, but not for the full hook
output. Either document this, or derive the id from the seed when it is set.
That would also allow a seeded test for 2b.

## 8. A tab inside a roster field breaks the log row (low; mostly older code)

A tab inside a name or universe gives the meta line more than one tab. The log
row then has 5 or more fields, and the Lua pattern `^([^\t]*)\t…\t([^\t]*)$` no
longer matches. So the lookup misses (see finding 1). The same input already
made the hook's JSON invalid before this change, because `sed` escapes only `\`
and `"`, so a raw tab reaches the string. Confirmed with a scratch roster: the
new script gives `JSONDecodeError: Invalid control character` and a 6-field log
row. The old script (`@-`) gives the same JSON error. The real
roster has no tabs. `--check` could flag a tab or CR inside a field, which would
cover both problems.

## 9. Fail-open review: no violations found

- Every new failure path is inside `{ … } >/dev/null 2>&1 || true`, or exits 0
  through `[ -n "$line" ] || exit 0`.
- The command substitutions inside the group inherit its redirections.
- `set -u` is safe: `HOME`, `XDG_STATE_HOME` and `ROLEPLAY_ROLL_LOG` all have
  default-safe expansions.
- No apostrophes were added inside `awk_prog`. The new `printf` there is BSD-awk
  safe.
- 200 hook runs on the real roster all produced valid JSON. The vote id is
  `[0-9a-z]` only, so it needs no escaping.
- The unwritable-log test covers the case where the parent path is a file.

One theoretical hang remains. If `ROLEPLAY_ROLL_LOG` is a FIFO with no reader,
or a path on a stalled network mount, `>>` blocks until Claude Code's hook
timeout, on every prompt. It is not realistic today, and not worth code.

## 10. CLAUDE.md instructions: clear, with three small risks

`rcs/claude-user-claude.md` is hardlinked to `~/.claude/CLAUDE.md` (same inode),
so the change is live now.

- Only the opener has a worked example. The 5–8 rule for the closer is stated
  once, in prose. A model that copies the opener line into the closer will reuse
  1–4. Those clicks are then recorded as `opener`, which skews any opener vs.
  closer comparison silently. Suggest adding a one-line closer example
  (`…v=k3f25 … v=k3f28`).
- The "Selection" example tag still shows no ` || vote id: …` suffix. So the
  model has to infer where "the roll tag's vote id" is. Suggest adding the
  suffix to that example, for example `… detective instincts || vote id: k3f2]`.
- The example id `k3f2` can be copied literally. It is labelled well ("With the
  roll's vote id `k3f2`"). Finding 1 decides whether such a mistake is visible.
- Cost: the 8 links add about 240 characters, roughly 80–100 output tokens, to
  every reply. The closer's 4 links vote on the same character and universe as
  the opener's. They only tell which line was liked, and the line is not stored.
  If opener vs. closer is not needed, drop them to halve the cost.

Not verified: that Claude Code renders `[ + ](hammerspoon://…)` as a clickable
OSC 8 link in iTerm2, rather than printing the URL. The existing `votes.tsv`
(184 bytes) suggests it has worked at least once.

Test file coverage of this review: I read the diff, the `run()` helper, lines
100–180, and lines 560–676. I grepped the rest for hook-mode and seeded tests.
All seeded tests use `--plain`, and no hook-mode test pins the full
`additionalContext`. So the random id does not destabilise the existing tests.

## Minor notes (no action needed)

- `append` runs `os.execute("mkdir -p …")` on every vote. That is a synchronous
  shell spawn on the Hammerspoon main thread. `hs.fs.mkdir`, or nothing at all,
  would do: the hook already creates the directory. The quoting
  (`gsub("'", "'\\''")`, truncated to one value inside `..`) is correct.
- Any page or app can open `hammerspoon://r?v=…`. The worst outcome is a junk
  row in `votes.tsv`, and `clean()` stops tab or newline injection. Acceptable.
- `obj:stop()` unbinding with `nil` matches `hs.urlevent.bind`'s documented
  removal form.
- Lua slot parsing was confirmed by running. `ab121` gives opener/character/up.
  `ab124` gives opener/universe/down. `cd345` gives closer/character/up. `cd348`
  gives closer/universe/down. `ab129`, `ab120`, `AB121`, `ab1`, `nil` and
  `ab12 1` are all rejected. A repeated id resolves to the newest roll
  (Togusa, not Holo).
