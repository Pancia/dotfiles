# Fish functions: un-ignore first-party code, then move fisher out of the repo

**Two phases, deliberately separable.** Phase 1 is a live bug — twelve
first-party functions are ignored and a fresh clone gets a broken `d`, `q` and
`ytdl`. Phase 2 removes the cause: `~/.config/fish/functions` is a symlink into
this checkout, so `fisher` installs *into the repo*, which is why the ignore
block and its twelve hand-maintained negations exist at all.

Phase 1 stands alone and should land first. Phase 2 deletes the ignore block
entirely, along with `fisher-wrap.fish` and `fisher-up.fish`.

## The problem in one paragraph

`.gitignore:15` is `fish/functions/_*`, because fisher writes plugin internals
(`_tide_*`, `__fzfm_*`, `_fzf_*`) into that directory. Every first-party
`_`-prefixed function therefore needs a `!` negation line, added by hand. The
convention has silently failed twelve times: the file works locally and is
absent from a clone. `conf.d/` and `completions/` do not have this problem —
they are *real* directories populated with hard links, so plugin files there sit
outside the repo and VCS never sees them. `functions/` is the only wholesale
directory symlink, and that single decision produced the entire ignore block.

## Facts this plan is built on

Measured on this machine, fish 4.1.2, fisher 4.4. Do not re-derive.

| Fact | Consequence |
|---|---|
| A leading `_` hides a function from `functions` (needs `-a`) and from command completion unless you type the `_` | The prefix is load-bearing *in fish*. Renaming away from `_` is not an option; only the VCS side can move. |
| Autoload requires `filename == function name`, exactly | You cannot rename the file without renaming the function and every callsite. |
| `$fish_function_path` is scanned **in order**, first match wins — verified with two dirs holding the same function name | A repo copy earlier on the path permanently shadows a plugin copy. This is what replaces `fisher-up`. |
| A function in a subdir added to `$fish_function_path` autoloads normally | Only relevant to rejected option B; recorded so it is not re-tested. |
| gitignore `*` does not cross `/`, so `fish/functions/_*` never matches a subdirectory | Same. |
| `~/.config/fish/functions` is a **symlink** to `~/dotfiles/fish/functions`; `conf.d/` and `completions/` are real dirs with hard-linked repo files | Only `functions/` is exposed to fisher. This is the whole bug. |
| Exactly two tracked files under `fish/functions/` are plugin-owned: `_tide_pwd.fish` and `trash.scpt` | `fisher-up` guards two files, not twelve. |
| `_tide_pwd.fish` is a real patch — one commit, *"Fix tide _tide_pwd error + add fisher update wrapper"* | Must survive Phase 2, as a shadow. |
| `trash.scpt` is **byte-identical** to fzfm upstream — tracked only because no ignore rule names it | Not a patch. `fisher-up` would silently revert a future fzfm change to it. Delete it in Phase 2. |
| Fisher records every installed file per plugin in `_fisher_<plugin>_files` universal vars, with a literal `~` | The only reliable inventory of plugin-owned files. 128 files across 5 plugins. |
| `fisher.fish:2` — `set --query fisher_path || set --local fisher_path $__fish_config_dir` | `$fisher_path` is supported; Phase 2 is a supported configuration, not a hack. |
| Fisher installs with `cp -RLf` into `$fisher_path/{functions,themes,conf.d,completions}` | It cannot be pointed at different roots per subdir. Phase 2 moves all four or none. |
| `share/config.fish:245` sources `$__fish_config_dir/conf.d/*.fish` — glob-sorted **per directory**, no global sort | Fisher's conf.d snippets must be sourced from one of our own snippets, at a filename that reproduces the current relative order. |
| Effective conf.d order today: `0_my_fzfm_settings`, `00_xdg`, `_tide_init`, then alphabetical (`done`, `fisher-wrap`, `fzf`, `fzfm`, `fzfm_keybindings`, … `nvm`, … `tide_dashboard`) | `0_my_fzfm_settings` must keep running before `fzfm`; `tide_dashboard` after `_tide_init`. |

## Phase 1 — un-ignore the twelve first-party functions

Independent of Phase 2 and worth landing on its own. Verified against fisher's
manifests and the fzfm source tree: no plugin owns any of these.

```
__d.fish              __d_bookmarks.fish     __q.fish        __q_registers.fish
__ytdl_id.fish        __ytdl_id_async.fish   __ytdl_dl.fish  __yt_lookup.fish
__edit_id.fish        __fix_marked_music.fish
_cc_config_preview.fish  _fzfm_show_help.fish
```

1. Add twelve `!fish/functions/<name>` lines to the existing negation block in
   `.gitignore`, grouped with a comment saying they are first-party and were
   found missing on 2026-07-31.
2. `git check-ignore -v` each one; all twelve must return rc 1.
3. Commit with `commit-mine` — another session is live in this working copy.

If Phase 2 lands, this block is deleted along with the rest. That is fine: the
files stay tracked, which is the entire point.

### Related, same failure class — do not fix here

Three first-party **conf.d** files exist only in `~/.config/fish/conf.d/` and
are absent from the repo: `keychain.fish`, `youtube_enhancer.fish`,
`0_my_fzfm_settings.fish`. Not ignored — never authored in the repo, and
`_ENSURE_CONF_D` only copies repo → live, never back. Same fresh-clone loss,
different mechanism. Note that `0_my_fzfm_settings.fish` duplicates the repo's
`my_fzfm_settings.fish` at an earlier sort position, so reconciling it is a
behaviour change, not a move. Separate task.

## Phase 2 — move fisher out via `$fisher_path`

End state: `fish/functions/` contains only first-party code, the entire `_*`
ignore block and every negation is deleted, and `fisher-wrap.fish` +
`fisher-up.fish` are gone. The `~/.config/fish/functions` symlink **stays** — so
the reasoning in CLAUDE.md about why `~/dotfiles` cannot use `cc-worktree` is
unaffected.

### Sequencing hazard, read first

`fisher update` **rewrites** the `_fisher_*_files` universal vars to the new
paths. That inventory is the only record of which of the ~128 files in
`fish/functions/` belong to plugins. **Capture it to a file before step 3**, or
the purge in step 5 has no source of truth and must be reconstructed by hand.

```fish
fish -c 'for v in (set -n | string match "_fisher_*_files")
    for f in $$v; echo $f; end
end' > /tmp/fisher-inventory.txt
```

### Steps

1. **Capture the inventory** (above). Also record `functions --details _tide_pwd`
   and a screenshot-equivalent of the prompt, for the step 8 comparison.

2. **Add `fish/conf.d/01_fisher.fish`.** Name chosen so it sorts after
   `00_xdg.fish` (needs `$XDG_DATA_HOME`) and after `0_my_fzfm_settings.fish`
   (fzfm settings must precede fzfm's own snippet), but before every
   alphabetical snippet — reproducing today's order for `_tide_init` /
   `tide_dashboard` and `fzfm` / `fzfm_keybindings`.

   It must: set `fisher_path`; insert `$fisher_path/functions` into
   `fish_function_path` **immediately after** `$__fish_config_dir/functions`, so
   repo copies shadow plugin copies but plugin copies still beat fish's own
   `share/functions`; do the same for `fish_complete_path`; then source
   `$fisher_path/conf.d/*.fish`.

   Run `/fish` before writing it. Insertion-into-the-middle of a list is the
   part to get right — `set -a` at the end is wrong (fish's own functions would
   win over plugins) and `set -p` at the front is wrong (plugins would win over
   the `_tide_pwd` patch).

3. **Reinstall.** `fisher update` with the new `fisher_path` set. Expect all five
   plugins to re-copy: fzfm (53 files), tide (51), fzf.fish (16), nvm (7),
   done (1).

4. **Restart a shell and check the prompt renders**, before deleting anything.
   This is the step that catches a path-plumbing mistake. If the prompt or
   keybindings are gone, the fault is in `01_fisher.fish`, not in the purge.

5. **Purge the old plugin copies** from `fish/functions/`, driven by
   `/tmp/fisher-inventory.txt`, minus `_tide_pwd.fish` (kept as the shadow).
   Use `trash`, not `rm`. `trash.scpt` goes too — it is identical to upstream and
   fzfm now ships its own copy.

6. **Delete the machinery**: `fish/conf.d/fisher-wrap.fish`,
   `fish/functions/fisher-up.fish`.

7. **Delete the ignore rules**: the whole `fish/functions/_*` block including
   every negation and every explanatory comment, plus the named plugin files
   below it — `fish/functions/tide.fish`, `fish/functions/tide/`,
   `fish/functions/fisher.fish`, `fzf_configure_bindings.fish`, `fzfm.fish`,
   `nvm.fish`, `fish_prompt.fish`, `fish_mode_prompt.fish`,
   `fzfm_fre_prune.clj`.

8. **Verify the shadow.** `functions --details _tide_pwd` must resolve to the
   repo path, not `$fisher_path`. Compare the prompt against step 1.

### Absolute-path references that break

Every one of these hardcodes `~/.config/fish/functions`, which after Phase 2 no
longer contains plugin files. Found by grep; fix each in the same change.

| Site | Problem | Fix |
|---|---|---|
| `fzfm.fish:4` — `command bb $HOME/.config/fish/functions/fzfm_fre_prune.clj` | The `.clj` moves to `$fisher_path/functions/`. **Hard break.** | Fix in the fzfm source repo (`~/projects/tooling/fzfm`), which we own, then reinstall. Do not patch the installed copy. |
| `_fzf_complete.fish:100` — `fish --no-config -C 'set fish_function_path ~/.config/fish/functions $fish_function_path'` | The fast subshell loses every plugin function. | First-party file; add `$fisher_path/functions` to that inner path. |
| `config.fish:145-146` — fisher bootstrap curls `fisher.fish` into `$XDG_CONFIG_HOME/fish/functions/` | Bootstraps back into the repo on a fresh machine. | Point at `$fisher_path/functions/`, creating it first. |
| `__fzfm_trash.fish:4,6` — `osascript $HOME/.config/fish/functions/trash.scpt` | Both lines are **commented out**. No break today. | Note only; if ever re-enabled, it must not use that path. |

### Verification

- `git check-ignore -v fish/functions/_anything.fish` returns rc 1 — nothing
  under `fish/functions/` is ignored any more.
- `jj file list fish/functions` cross-referenced against
  `/tmp/fisher-inventory.txt` yields exactly one intersection: `_tide_pwd.fish`.
- `cmds test fish` passes. `run_tests.py:58` has `"source_path": "fish/functions"`;
  confirm the component still resolves.
- Fresh-clone smoke test in a scratch dir: `d`, `q`, `ytdl`, `ccu` all resolve.
- `fisher update` runs clean with no wrapper, and does not modify anything under
  `~/dotfiles`.

### Rollback

Phase 2 is a config change plus deletions, both recoverable:
`set -e fisher_path`, delete `01_fisher.fish`, `jj restore` the `.gitignore`
block and the two deleted machinery files, `fisher update` to reinstall into the
old location. Purged plugin files are in the trash, and reinstallable regardless.

## Considered and rejected

| Option | Why not |
|---|---|
| **B — `fish/functions/private/` on `$fish_function_path`** | Works, ~1hr, verified. But the top level stays a trap: `fish/functions/_*` must remain because fisher still writes there, so a new `_foo.fish` in the wrong place is still silently ignored. Improves the bookkeeping, does not remove the failure mode. Redundant under Phase 2 — not a stepping stone to it. |
| **C — filename namespace (`_dot_*`) + one negation** | Costs more than B (renames the *function*, so every callsite moves) and buys less. Still a convention someone must remember, with the same silent failure. |
| **E — un-symlink `functions/`, hard-link it like `conf.d/`** | Tempting: `_ENSURE_CONF_D` / `_ENSURE_COMPLETIONS` already do exactly this, every absolute path keeps working, and `ln -f` over a plugin file *is* the patch mechanism for free. Rejected because hard links break when an editor rewrites the inode, and this directory holds 169 files that are edited constantly — the stale-copy failure is silent and daily. `conf.d/` tolerates it because those 25 files are rarely touched. Phase 2 keeps the symlink and edit-in-place. |
| **A — just add the twelve negations and stop** | That is Phase 1. Correct as far as it goes; leaves the treadmill. |

## Open question

Whether the `_tide_pwd.fish` patch is still needed at all. It fixes an error in
tide's generated prompt code and has one commit behind it; tide has released
since. Worth testing the unpatched upstream once before carrying the shadow
forward — if it is fixed upstream, Phase 2 ends with `fish/functions/` holding
no plugin files whatsoever, and the shadow mechanism becomes unused rather than
load-bearing.
