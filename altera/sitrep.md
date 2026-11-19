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
- Until altera/ is private: keep security work out of Altera; check altera/ changes before each push.
