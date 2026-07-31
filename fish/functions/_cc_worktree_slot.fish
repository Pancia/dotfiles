function _cc_worktree_slot --description 'Slot name (w-NN) for a cc worktree path, empty if not in one'
    # The counterpart of _cc_worktree_key: that one strips the slot out of a
    # path, this one is the slot it stripped. Recorded in the ccs entry so a
    # later `--resume` can be sent back to the SAME directory -- Claude Code
    # keys transcripts by mangled cwd, so a session that ran in w-03 cannot be
    # resumed anywhere else.
    #
    # Pure fish, no subprocess (`cc-worktree current` does the same thing for
    # callers that are not fish), because this runs on every registration.
    set -l p $argv[1]
    test -n "$p"; or set p $PWD
    set -l m (string match -r '/\.claude/worktrees/(w-[0-9]+)(?:/|$)' -- $p)
    if test (count $m) -ge 2
        printf '%s\n' $m[2]
    end
end
