# Plan: Altera review workflow and docs for dotfiles (2026-11-19)

Status: proposal, nothing applied. Decisions are Q15–Q20 in the liaison session.

## Goal

Give dotfiles the same review gates that Altera's own repo uses (`~/projects/altera/altera/workflows/altera-dev.json`), adapted to this repo, and make the project docs fit what an Altera worker actually loads.

## What exists today

- `altera/workflows/default.json` has no hooks. Specs and missions run with no critique and no merge review.
- `altera/workflows/dotmod-vendor-go.json` is a March leftover for the vendor CLI.
- `altera/config.json` still has `source_guard.protected_prefixes: [internal/, cmd/]` and Go-only sandbox domains, copied from Altera's defaults. The sandbox is off, so the domains do nothing.
- The merge gate is off (Q6 pending).
- master is 35 commits behind the main checkout. Critiques and writers read `git show master:`, and workers branch from master.
- CLAUDE.md never mentions Altera. It tells every session to use `jj`, `/cc:commit`, `cmds test` and the `/fish` skill. A worker is denied `jj`, `g`, `commit-mine` and `ccjj`. `cmds test` tests `~/dotfiles`, not the worker's tree. With `agent_user_config: skip`, a worker loads no user CLAUDE.md, hooks or user skills, so it never sees the no-`rm` rule or `/fish`.

## Step 0 (operator): move master

Move master to the current main-checkout commit before any spec, so every critique checks real code: `jj bookmark set master -r 1898647d` (then push only master: `jj git push -b master`).

## Step 1: new workflow `dotfiles-dev` (default_workflow)

Three gated agent hooks, ported from `altera-dev`:

| Hook | When | Checks | Timeout |
|---|---|---|---|
| spec critique (`pre_spec_approve`) | before you approve a spec | claims against master; mission size; one done check per mission; overlap; live-file and privacy risks; docs section present | 30m |
| mission critique (`pre_task_assign`) | before a worker starts | brief against master; done check; scope; deps; live-file risks | 10m |
| merge review (`pre_task_merge`) | before a change merges | diff against brief; regressions; lost work; docs updated; nothing private added | 20m |

Prompts live in `altera/prompts/dotfiles-dev/`: `checklist.md`, `merge-review.md`, `spec-writer.md`, `mission-writer.md`, loaded as `writers` like Altera's.

Changes from Altera's versions:
- Drop Go-only parts: `HermeticMain`, `make test`, `go test`, `test` done checks (Go-only; use `command`), the `internal/`/`cmd/` path filter, `TestScenarios` rules.
- Keep `alt heavy run`, `alt exhibit` and the cost estimate (`.alt/usage/costs.jsonl` exists here).
- Add dotfiles checklist items:
  1. **Live files.** A change under `rcs/` (hardlinked into live config), `services/*/*.plist` (loaded at the next fish start), `fish/functions/` (symlinked live), `lib/lua/seeds/` (Hammerspoon) or `~/.claude` settings goes live as soon as it reaches the main checkout. The brief must say so and say how to check it.
  2. **Public repo.** No secret, private path content, transcript quote or personal detail in code, specs, reviews or worklogs. Private material goes to `.cc/private/` or the work-config vault.
  3. **Tests.** Run with `uv run lib/python/run_tests.py <component>`, never `cmds test`. A new test tree is registered in `COMPONENTS` (`lib/python/run_tests.py`). No test touches the real `HOME`, live `~/.config`, `~/Library/LaunchAgents` or a live service.
  4. **Fish.** A `.fish` change follows the gotchas in CLAUDE.md and passes `fish -n`.
  5. **No `rm`.** Use `trash`.
  6. **Docs.** A change that alters behaviour updates CLAUDE.md or the matching `docs/` file in the same mission. This is the hook that keeps docs current.
- `done_check.required: true`.
- `autofix`: off. Altera's docs say the automatic writer is not launched yet.

Cost: each spec adds one critique run; each mission adds two (critique and review). Hook agents are not sandboxed and do not take worker slots (`max_hook_agents`, default 2).

## Step 2: docs hooked into Altera

- Add an "Altera workers" section to CLAUDE.md: use `git`, not `jj`; test with `uv run lib/python/run_tests.py`; no `rm`; never push; `altera/` files are public. A worker loads the project CLAUDE.md, so this is where it learns the rules it would otherwise get from the user files.
- Add a short "Altera" section for interactive sessions: what `altera/` holds, the liaison, review landing, push only master.
- Set `context` in the workflow: `sketch` and `spec` get `CLAUDE.md` and `docs/testing.md`.
- First spec through the new gates: a docs audit of CLAUDE.md and `docs/` against the code, with fixes as missions. This also tests the workflow.

## Step 3: cleanup

- Remove `source_guard` (`internal/`, `cmd/` are wrong here; dotfiles code is everywhere).
- Retire `dotmod-vendor-go.json`.
- Trim the March content from `altera/sitrep.md`.

## Open decisions

- Findings files are committed under `altera/reviews/` and pushed, as Q12 (Altera files private) has no fix yet.
- Who writes the workflow and prompts: the liaison, shown to the operator before activating, or a spec and missions.
- Merge gate command (Q6): to be checked from a clean copy of master, not from `~/dotfiles`.
