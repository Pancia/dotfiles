function j --description "Jump to directory (frecent)"
    # Fish's stock completion for `j` replays previous `j` arguments from shell
    # history, so a path typed once comes back as a completion. Go there rather
    # than feeding it to fzf as a query. See __jump_direct.
    if __jump_direct $argv
        __fzfm_save_pwd_history
        return
    end

    # Accept immediately on a unique match — see the note in p.fish.
    set -lx FZF_OPTS_OVERRIDE $FZF_OPTS_OVERRIDE --select-1

    __fzfm_search jump_frecent $argv
end
