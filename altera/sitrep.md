# Sitrep

## Session Goal (2026-11-19)

Set up Altera properly in dotfiles: setup review, the same review gates as Altera's own repo, a merge gate, and docs that fit what workers load.

## Done

- Setup applied: privacy public, landing review-manual, checkout-landing warn, scope none, workers 1. Skipped: sandbox, stacks, machine-workers. Retired budget_ceiling removed by the operator.
- m-003/m-004 (March vendor CLI) cancelled: their code was already on master.
- master moved to the main checkout's tip (1898647d) by the operator.
- Feature request filed with Altera for private artifacts (in ~/projects/altera/altera/issues/, uncommitted there).
- Workflow `dotfiles-dev` written (altera/workflows/dotfiles-dev.json, prompts in altera/prompts/dotfiles-dev/), NOT yet default_workflow. Old dotmod-vendor-go workflow trashed.
- Plan: .cc/plans/PLAN-altera-workflow.md.

## Open

- dotfiles-dev approved by the operator (Q24) and set as default_workflow. Hooks read prompts from master, so master must include the commit.
- Q23: first spec = fix the failing tests (astro network, revive, svc) and any test touching the live HOME. Q6: merge gate only after those fixes.
- Merge gate: candidate `alt heavy run --label dotfiles-test -- uv run lib/python/run_tests.py`, merge_gate.mode observe first. Full suite on ~/dotfiles took ~14 min and is red: astro (32 errors, needs network geocoding), revive (1), svc (3). Clean-copy run started.
- Q19: CLAUDE.md worker section + Altera section, then a docs-audit spec through the new gates.
- Q22 done: bulk-ask rule added to rcs/claude-user-claude.md.
- Committed f5db1a2b (workflow, prompts, config, sitrep). Hooks read master, so master must move to it.
- Spec 20261119-121426 (test fixes, 12 missions) approved by the operator (Q27); its four Open Questions accepted as recommended (Q28). Spec critique running via `alt spec approve --wait`.
- Spec rev 2 committed b86ca0f8 (PRIVACY moved out per Q32; diff critique r-004 saved). Rev 2 diff check r-005 running; then `alt recon mission --spec`.
- 148b8ceb (other session's doc commit) approved for landing per Q31.
- 2026-11-20: test-fix missions m-013..m-024 opened (Q33). Privacy spec 20261119-143123 (10 missions + operator HISTORY step; CORE deps m-017, m-024) approved by operator (Q34), critique running. Four other-session commits (reply-links, svc) approved for landing (Q35).
- Privacy spec 20261119-143123 PARKED (Q36): its critique rejected it (tasks leave tests on the old fixtures; SCRUB's word grep cannot pass; 14 MINOR; real cost 40-60 7d points). Revise after the test fixes land and the 7d window resets (Mon 23:00), then `alt hook rerun 20261119-143123-MST-synthetic-sample-chart-for-the-astro-tests`.
- 7d usage was 51% on 2026-11-20 (32% the day before). Both specs together estimate 18-33 7d points.
- Clean-clone gate run: same 36 failures as ~/dotfiles, 16m45s.
- altera/config.json has checkout_landing auto uncommitted (claimed by this session); committing it makes a non-artifact commit the operator must land.

- 2026-11-20 16:57: Altera's external record store (alt 68024bb4) is ready; dotfiles is its first user. Plan from the Altera liaison: restart daemon on 68024bb4 (running 9b1a50c7); drain (no new missions; review group g-001 must be accepted first); operator writes ~/.config/altera/artifacts.json (root ~/Vaults/altera-artifacts, bundle_dir = the vault's backup folder; never in a tracked file); operator runs `alt daemon pause`, `alt artifacts setup`, `alt artifacts migrate` from a plain terminal; commit the printed commit via jj (deletions + altera/config.json only); push; `alt daemon resume`, `alt liaison restart`, `alt sandbox check` (records_read, records_sibling). Undo: `alt artifacts migrate --to repo`. Another session has an uncommitted sketch change (calendar scheduler) that must be committed first.

- PARKED idea (2026-11-20, from a standalone session on the user's behalf): calendar-driven personal scheduler `sched`. Sketch altera/sketches/20261120-142137-MST-calendar-driven-personal-scheduler-sched.md (committed by the liaison). Do not spec or open missions until the user raises it again. Brief .cc/misc/scheduler/recon-brief.md and probes .cc/scripts/sched-ek-*.py belong to that session.

## Open Bugs

- Hammerspoon calendar seed: the trigger key has no occurrence date and expires after 48 h, so a daily tagged event (focus/notify) fires only every third day. Parked with the sched idea (sketch, slice 2).

## Open Questions

Next ID: Q36



## Notes

- Standing permission (Q39, 2026-11-20): when another session's finished commit blocks artifact landing, the liaison approves it with `alt checkout land` without asking, and names the commits in its next reply. Q44 extends this to the liaison's own commits.

- Until altera/ is private: keep security work out of Altera; check altera/ changes before each push.
