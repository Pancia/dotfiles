# FIXME: ccjj refusal after a crash names an ended session with no hint

Found 2026-11-16 in an Altera liaison session that ran across a Mac crash and a power cut.

## What happened

- `commit-mine --also altera/sitrep.md` refused ("Their unfinished work would be committed
  under your message ... Re-run with --force only if all of the diff above is yours").
- The stake was the same liaison's own earlier session (6a0c6887): ended, owner pid gone
  since the crash, 4 Edit records on that file from three days earlier. The crash gave the
  resumed session a new pid, so `same_process_journals` (`lib/python/ccjj.py:491`) did not
  absorb it.
- Eight seconds later a successful commit ran the daily `maybe_prune` (`:3172-3185`), which
  retired 6a0c6887 as orphaned. A later `ccjj who altera/sitrep.md` then said "No session has
  journal records", so the refusal and `who` looked contradictory, and the user was told
  "another session" when none existed any more.

The refusal already names sessions (`also_refusal`, `:2431-2452`; `describe_stakes`,
`:2397-2399`), and `--also` and `who` share `stakes_on` (`:2309-2337`). The gap is missing
detail and a next step.

## Fix

1. In each refusal row, add the owner state and the last record time, for example
   `6a0c6887 (ended; owner process gone; 4 records, last 2026-11-13 18:14)`.
2. For an ended peer whose owner is gone, add one line: "If this was an earlier session of
   yours (resumed after a crash), run `ccjj disown 6a0c6887` and re-run; otherwise use
   --force only if the diff is yours." `disown` already exists.
3. Optional: when `who` finds no stake and a prune ran today, say so ("pruned today at
   10:17").

Source: an Altera retro critique of 2026-11-16 (kept in the Altera checkout's `.cc/reports/`).
