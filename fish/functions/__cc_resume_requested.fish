function __cc_resume_requested --description 'True if argv asks to resume or continue a session'
    # The wrapper's guard against adding --worktree to a resume: Claude Code
    # already returns a resumed session to the worktree it ran in, so appending
    # the flag would strand it in a fresh empty one instead.
    #
    # This used to have a sibling, __cc_resume_id, which extracted the session id
    # so the old hand-rolled code could look up which slot to reuse. Claude Code
    # resolves that itself now -- `claude --resume <id>` from the parent reaches
    # a worktree session -- so only the yes/no question is left.
    for a in $argv
        switch $a
            case -r --resume '--resume=*' -c --continue '--continue=*'
                return 0
        end
    end
    return 1
end
