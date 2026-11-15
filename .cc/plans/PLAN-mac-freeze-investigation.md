# Mac freeze investigation plan (rev. 2026-11-15)

> **Status, 2026-11-15: paused.** Step 1 is done (Game Mode off for Shadow).
> All diagnostics are off. Summary and how to resume: docs/mac-freezes.md.

## Suspect

A macOS kernel bug. A process that is mid-`exec` deadlocks on itself when
RunningBoard changes the background flag of iTerm2's whole coalition at the same
moment (into *or* out of background mode). Everything that touches that pid
(ps, iTerm2, runningboardd, then WindowServer) waits for ever.

**Trigger, likely: Game Mode.** Shadow PC's display app declares the games
category, so in full screen macOS turns Game Mode on and RunningBoard moves about
50 processes, iTerm2 included, to the Background role in one sweep. All five
freezes began with Shadow in front; iTerm2 got the Background role only on Shadow
days. Altera's test runs raise the exec rate inside iTerm2's coalition, so they
raise the odds per sweep. Evidence: `.cc/private/freeze-evidence/REVIEW-freeze-plan.md`, kept out of git because it holds app-usage times (supersedes the App Nap
idea in REVIEW-freeze-options.md).

Five freezes, not four: 11-14 12:28 left a reset record but no stackshot. macOS
is on 15.8.3 since 11-14 15:11. Raw evidence is kept in
`.cc/private/freeze-evidence/` (not in git, no backup).

## Steps

1. **Cut the trigger.** In Shadow, Game menu → "Turn Game Mode Off" (or run it
   windowed). Prediction: the RunningBoard log shows no Background role for
   iTerm2 during a Shadow session. Check after the next session.
2. **Judge by exposure, not calendar days.** Baseline ≈ 3% freeze risk per Game
   Mode sweep. Count sweeps from the RunningBoard log (kept ~6 days). About 100
   sweeps with agents running and no freeze is evidence; with Game Mode off there
   should be no sweeps at all, which is checkable at once.
3. **Better logging.** freeze-logger records the priority of one long-lived
   iTerm2-coalition process and the pid delta (fork rate). Not "count of priority
   4": 406 of 783 processes sit there for unrelated reasons.
4. **Confirm each new freeze fast.** A script reads a forceReset report and says
   whether it is the same exec self-deadlock. Copy each new report into the
   evidence folder at once: macOS deletes them within days.
5. **Second line, only if 1 fails:** tmux and Altera under launchd agents. Costly:
   Altera starts its own tmux servers from iTerm2 tabs, revive/ccs key on
   `ITERM_SESSION_ID`, privacy grants move to the tmux binary.
6. **Report to Apple** with the call chain.
