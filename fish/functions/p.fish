function p --description "Jump to git project"
    # `p you<TAB>` completes to a whole project path; go there rather than
    # feeding it to fzf as a query. See __jump_direct.
    if __jump_direct $argv
        __fzfm_save_pwd_history
        return
    end

    # Accept immediately when the query matches exactly one project, so
    # `p youtube-enh` lands without drawing a picker you'd only press Enter on.
    # Startup-only: narrowing to one row while typing *inside* the picker still
    # takes an Enter. No --exit-0, so a query that matches nothing still opens
    # the picker to be edited rather than silently doing nothing.
    #
    # FZF_OPTS_OVERRIDE is __fzfm_search's own knob for this. It must be
    # exported — a plain `set -l` is not visible to a called function — and
    # local-exported keeps it scoped to this call instead of leaking globally.
    set -lx FZF_OPTS_OVERRIDE $FZF_OPTS_OVERRIDE --select-1

    __fzfm_search jump_projects $argv
end
