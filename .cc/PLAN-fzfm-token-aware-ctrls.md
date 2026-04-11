# Token-aware fzfm Ctrl+S handler

**Status:** Partial / buggy in edge cases. On jj bookmark `fzfm-wip` (commit `735128df`). **May be superseded** by talking with George (upstream fzfm creator) — it's possible the "broken" behavior I'm patching around is actually misconfiguration or misuse on my end, and upstream has a proper solution.

## Context

`Ctrl+S` was bound to `fzfm_leader` (a which-key menu I never use). The real itch: typing `ls ~/Cloud/<Ctrl+S>` would run fzfm list modes against `pwd` instead of `~/Cloud/`, because fzfm's token-capture block (in `~/projects/tooling/fzfm/functions/__fzfm_search.fish` lines 114-124) passes the current token to fzf as `--query`, while the list commands (`fzfm_list_cmd_{all,inside,flat_*}`) still scan `.`/pwd. `j`/`jump_frecent` hides the bug because its list is universe-wide so query filtering happens to land on the right entries.

Intent: repurpose Ctrl+S as a **token-aware fzfm search** that routes fzfm at the directory the user is typing into, while keeping fzfm's full nested fuzzy experience (preview, alt-key mode switching, `__fzfm_select` token-replace).

## What's on the bookmark

Branch: `fzfm-wip` (735128df: "fzfm: token-aware search binding")

- **New:** `fish/functions/fzfm_search_token.fish` — wrapper that:
  1. Reads current cmdline token
  2. Unescapes, tilde-expands, optionally `$VAR`-expands (strict regex guard against `$(...)` / backticks)
  3. Classifies into `base_dir` + `query_part`:
     - empty → `$fzfm_search_token_root` if set, else pwd (no cd)
     - existing dir → base = token
     - contains `/` with existing parent → base = dirname, query = basename
     - otherwise → pwd + token as query
  4. `cd`s into `base_dir`, clears the token, calls `__fzfm_search all $query_part`
  5. Restores pwd only if fzfm didn't intentionally move us (`test (pwd) = $base_dir`)
- **Edited:** `fish/functions/fish_user_key_bindings.fish` — `bind \cs fzfm_leader` → `bind \cs fzfm_search_token`
- `fzfm_leader.fish` left as dead code

Approved plan lives at `~/.claude/plans/wondrous-seeking-valiant.md` with full design, verification steps, and known limitations.

## Validation done

Non-interactive only (fish `commandline` doesn't work outside an interactive TTY):

- Syntax-check of both fish files: clean
- 10/10 classification cases pass (empty, `~/Cloud/`, `~/dotfiles`, `~/dotfiles/fi`, plain name, non-existent parent, `$HOME/dotfiles/`, `$BOGUS_VAR/x`, `$(rm -rf /)`, empty+override)
- `$(rm -rf /)` safely kept literal (strict regex blocks eval)
- `cd`+restore logic verified in all 3 pwd-state scenarios: no-push, push+noop-restore, push+jump-no-restore

## Known edge cases / bugs (not fixed)

1. **Tilde compression lost on insert.** `__fzfm_select` inserts absolute paths (`/Users/anthony/Cloud/foo.txt`) — the `~/Cloud/` prefix the user typed doesn't get reused.
2. **Partial-path with non-existent parent silently degrades** to a pwd search with the full literal as query. Surprising but not broken.
3. **`all` mode on large roots** (`$HOME`, Cloud) has noticeable first-paint latency because `fd --no-ignore --hidden --max-depth 10` streams thousands of entries. Works, just sluggish.
4. **`$BOGUS_VAR/x` silently collapses to empty** then falls through to the empty-token branch. Not ideal; should probably be kept as literal query instead.
5. **`eval echo` expansion trust.** Restricted by regex to simple `$VAR`/`$VAR/path` forms, but still executes in the shell's own env. Fine for personal use, not for anything shared.
6. **Not tested interactively.** The full round-trip — fzf actually launching, preview running under pushed pwd, alt-key mode switching, `__fzfm_select` replacing the cleared token — has only been validated in theory. Real user testing pending.
7. **`(pwd) = $base_dir` restore guard is a heuristic.** If fzfm jump mode happens to land on `base_dir`, we'd incorrectly restore to `saved_pwd`. Unlikely in practice.

## Why this might get thrown away

George (fzfm creator at `~/projects/tooling/fzfm/`) likely has opinions about:

- Whether fzfm already supports token-as-root through some configuration path I missed (I grepped the source and didn't find one, but I may have been looking for the wrong thing)
- Whether my cmdline usage pattern (`cat ~/Cloud/<Ctrl+S>`) is how fzfm is *meant* to be driven at all, or whether there's a different intended entry point
- Whether patching around the issue with a dotfiles-side wrapper is the right call or whether the fix belongs upstream in `__fzfm_search.fish`'s token block
- Whether `_fzf_complete` (fish native `complete --do-complete` → fzf) was the intended handler for this use case instead of fzfm list modes

**If George has a cleaner answer, revert this branch and adopt that instead.** The wrapper is self-contained (one new file, one binding edit), so revert is trivial: `jj abandon fzfm-wip` or delete the new file and restore the binding line.

## Files touched

- `fish/functions/fzfm_search_token.fish` (new)
- `fish/functions/fish_user_key_bindings.fish` (1 binding + comment)

## Not landed yet

- Not merged into master. Bookmark `fzfm-wip` sits ahead of master at 735128df.
- No `fzfm_search_token_root` export added to `fish/conf.d/` — left for me to set when/if I actually want a non-pwd default.

## Next steps (if continuing without George's input)

1. Dogfood interactively for a week. Note which edge cases bite.
2. Fix #4 (`$BOGUS_VAR/x` collapse) — trivial: only overwrite token on non-empty expansion.
3. Decide on #1 (tilde compression) — would need post-processing `__fzfm_select`'s output or a new insert path.
4. Consider switching default mode from `all` to `inside` or `flat_alphabetical` if #3 (latency) is annoying.

## Next steps (if talking to George)

1. Describe the `cat ~/Cloud/<Ctrl+S>` use case.
2. Ask: does fzfm intend to treat a path token as a listing root? If yes, how.
3. Ask: is `_fzf_complete` the right entry point for this, or is it `__fzfm_search`?
4. Ask: would he accept an upstream PR to `__fzfm_search.fish`'s token block that honors a `test -d` check before falling through to `--query`?
