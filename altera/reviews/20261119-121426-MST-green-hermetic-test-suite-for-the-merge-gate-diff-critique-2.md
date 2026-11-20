Summary: Revision 2 handles the diff critique's MINOR findings mostly correctly against master. It removes row PRIVACY cleanly and narrows nothing else. All 13 JSON blocks parse as strict JSON, and every acceptance check title matches exactly one done-check title. The deps form no cycle. I found no BLOCKING problem. One check may break depending on the regex engine, and I could not confirm which engine runs the done checks. The rest are MINOR fixes to wording and ordering. File paths below use `spec.md` for `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md` at b86ca0f8. The spec quotes no personal birth details.

These points check out against master:
- **Line reference:** `_build_chart` runs from line 181 to line 203 of `bin/astro-zr-helper` (spec.md:23).
- **Roleplay test (spec.md:152):** `_roll(path)` runs any script path, so a stub works. The test now compares HOME with the test's own `tmp_path`, so it fails until R9.1 is done. `_roll` will need a home parameter.
- **SVC-EXIT order:** ISOLATE now waits for SVC-EXIT (spec.md:307, 318).
- **AC5:** reworded to "written classification" in both the prose and the JSON (spec.md:192, 212).
- **AC1:** no longer contradicts anything, because AC18 is gone.
- **REST-B:** R10.1 keeps it out of `tests/bin/astro/` and `test_revive.py`, and lets it touch `run_tests.py` for the opt-out only, after REST-A (spec.md:159, 320).
- **Interim notice:** R12.3 now removes it (spec.md:179).
- **GATE-RUN:** now waits for REVIVE (spec.md:316).
- **PRIVACY removal:** the requirement list, its done check, AC18, its acceptance line, its dep on CANARY and its table row are all gone. "PRIVACY" now appears only in the note at spec.md:19 and spec.md:184. The removed item moved to Out of Scope (spec.md:428) and Open Question 5 (spec.md:436).
- **Nothing else narrowed:** the CANARY allowlist rule and AC5 changed only as the critique asked.
- **Lua regex:** it matches `15 passed` and rejects `1 passed, 14 skipped`. It also rejects `20 passed, 5 skipped` and `115 passed`. With lua5.4 installed, master collects 25 lua tests (15 functions; three are parametrized into 7, 4 and 2 cases). 25 is inside the 10–29 window.
- **Deps:** no cycle. Every row reaches GATE-RUN.
- **File owners:** `run_tests.py` goes ISOLATE, REST-A, REST-B, TIMING. `docs/testing.md` goes ISOLATE, REST-A, REST-B, TIMING, CANARY, then GATE-RUN. `CLAUDE.md` goes ISOLATE, then CANARY. `tests/svc/test_svc.py` goes SVC-KEYS, then SVC-EXIT. The deps enforce each order.

- MINOR (not verified): The lua check uses a negative lookahead, `(?![^\n]*skipped)` (spec.md:386). It is the only lookahead in any check. Go RE2 and Rust regex cannot compile it. I found no doc in `altera/` that names the engine for `stdout_matches`, and I could not reach the `alt` source. If the engine is RE2-style, use a pattern with no lookahead, for example `\b[12][0-9] passed(, \d+ warnings?)? in `. pytest prints `skipped` between the passed count and `in`, so a skip still fails this pattern.
- MINOR: REVIVE has no order against ISOLATE (spec.md:304, 307, 318). Rev 2 made ISOLATE wait for SVC-EXIT because the runner then strips `TMUX`. The same reason holds for REVIVE:
  - After ISOLATE, R1.3 (spec.md:53) cannot reproduce the failure.
  - The existing-test half of the REVIVE check (spec.md:327) then passes without the fix.
  - Fix: make ISOLATE depend on REVIVE as well.
- MINOR: The Order paragraph is stale (spec.md:243). It says REVIVE and SVC-KEYS land first and ISOLATE comes next. It omits SVC-EXIT, which now also lands before ISOLATE. It also says each check fails before its fix whatever the gate's environment is. That is false for REVIVE after ISOLATE (see above).
- MINOR: The CANARY allowlist rule contradicts itself.
  - spec.md:174 still says "An allowlist keyed by file and pattern". spec.md:178 says exact stripped line text, "not by pattern". Change line 174.
  - The starting list keeps three entries that the scan never sees: `test_cc_worktree_wrapper.py` lines 81 and 89, and `test_llm_output.py` line 709. On master all three are `#` comment lines, and the scan skips those (spec.md:175, 177).
- MINOR: CANARY has no dep on FISH (spec.md:311, 315). The allowlist now pins exact line text in `tests/fish/test_cc_worktree_wrapper.py` and `tests/fish/test_trash.py`, which FISH owns.
  - The PATH rule in R8.3 and R4.2 may lead FISH to change the hand-written PATH guards at `test_trash.py:22-29`, or to add a docstring that names `~/dotfiles`.
  - Either change fails CANARY's scan after both rows merge, although CANARY's own check already passed.
  - Fix: add FISH to CANARY's deps.
- MINOR: REST-B's table row was not narrowed (spec.md:313). It still lists all of `tests/bin/` and `tests/lib/python/`. It also omits `lib/python/run_tests.py (opt-out only)`, which R10.1 and spec.md:320 now give it. REST-A's row (spec.md:312) shows how to write that.
- MINOR: R12.3 is only partly connected (spec.md:179).
  - Documentation Updates (spec.md:228-239) does not list the notice removal or CANARY's `CLAUDE.md` edit.
  - The one-owner sentence (spec.md:320) does not name `CLAUDE.md`, although the deps already put ISOLATE before CANARY.
  - No check confirms the notice is gone.
  - R12.3 comes before R12.2.
- MINOR: No successor spec tracks the PRIVACY work on master. Only `altera/sitrep.md` Q32 tracks it, and that entry is stale. It still says "Recommend moving it to its own spec" and "(rev 2, uncommitted)", although this commit made the move. Q31 also stays listed as open, although master 1f52612e landed 148b8ceb. Update Q32 to point at the planned spec, and close Q31.
- MINOR: The cost estimate is a little high (spec.md:298). The 12 worker missions sum to 375 minutes, which is about 6.25 hours, not about 6.5.
- MINOR: AC5's prose says "with the runs behind it" (spec.md:192). The "finding written" check (spec.md:342) reads only the report's first line, so nothing checks that part. Either drop the phrase or add a check for it.
