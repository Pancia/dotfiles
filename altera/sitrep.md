# Sitrep

## Session Goal

First Altera session on dotfiles repo. Ingest existing PLAN files as sketches, design and implement a vendored dependencies system.

## In Progress

- **Vendor CLI**: m-001 and m-002 merged to master. m-003 (audit) and m-004 (build/install) completed by workers but stalled at resolver stage — work lives on `alt/resolve-m-003` and `alt/resolve-m-004` branches. Need manual merge to master.
- **Resolver worktrees** still exist at `.alt/worktrees/resolver-01` and `resolver-02` — daemon thinks resolvers are dead/critical.

## Decisions

- **default_branch** was `main` (wrong), fixed to `master` — caused repeated merge failures and a config persistence issue (required two `alt config set` calls)
- **Vendor CLI**: Go binary, MANIFEST.json, source-only builds, Claude-powered auditing as default, macOS ARM only
- **Sketches**: 10 total (9 PLAN files + vendored deps), all in `altera/sketches/` with proper structure
- **Spec approved**: `altera/specs/20260308-005905-MST-vendored-dependencies-system.md`

## Open Bugs

- **Merge silently drops work**: When `default_branch` is wrong, merge retries mark tasks `done` with no commits on target branch. Filed: `~/projects/altera/bug-reports/20260308-merge-loses-work-on-default-branch-mismatch.md`
- **Config persistence**: `alt config set default_branch master` reported success but didn't persist on first call. Required second invocation.
- **Workflow dir deleted**: `altera/workflows/` was cleaned up (possibly by worktree cleanup). Had to recreate `default.json`.

## Notes

- Stale resolver alert (m-3653f4) for resolver-01 — can ack after resolving the merge branches
- Session JSONL transcripts for all workers preserved at `~/.claude/projects/-Users-anthony-dotfiles--alt-worktrees-w-0{1,2,3,4}/`
