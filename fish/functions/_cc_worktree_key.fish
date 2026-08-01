function _cc_worktree_key --description 'Session key: parent repo path for a cc worktree, else pwd'
    # Maps <repo>/.claude/worktrees/<name>[/sub] back to <repo>[/sub], so every
    # ccs record for an isolated session files under the repo the human thinks
    # in. Without it `ccs list` at the repo root shows nothing, and ~/Cloud grows
    # one cc-sessions tree per worktree, forever.
    #
    # The name pattern is any single path segment, not the old `w-NN`. Claude
    # Code's native --worktree generates names like `warm-discovering-metcalfe`,
    # so the narrower regex stopped matching entirely and every isolated session
    # filed under its worktree path instead of the repo -- the exact failure
    # this function exists to prevent. Filing under the parent is right because
    # `claude --resume <id>` run from the parent reaches a worktree session on
    # its own (verified), so ccs never needs to cd into the worktree.
    set -l p $argv[1]
    # $PWD (logical), NOT `pwd -P`: every ccs site this replaces uses logical
    # pwd, and /tmp -> /private/tmp and ~/Cloud (a ProtonDrive symlink) diverge,
    # which would silently orphan every entry recorded before this landed.
    test -n "$p"; or set p $PWD
    set -l m (string match -r '^(.*)/\.claude/worktrees/[^/]+(/.*)?$' -- $p)
    # When group 2 does not participate fish emits NO element for it, so `count`
    # is 2 rather than 3 and $m[3] expands to nothing -- which printf handles as
    # a single argument. -ge 2 is therefore the right test, not -eq 3.
    if test (count $m) -ge 2
        printf '%s%s\n' $m[2] $m[3]
    else
        printf '%s\n' $p
    end
end
