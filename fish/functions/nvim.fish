function nvim --description 'Neovim wrapper with session restart support' --wraps nvim
    set -l restart_flag ~/.local/share/nvim/restart

    set -l session_file ~/.local/share/nvim/session.vim

    # This pane's nvim session folder for `revive` (docs/revive.md). Set for
    # the child only, never exported: git's editor, `cmds` and nested shells
    # must not claim the pane. Empty outside a journaling shell, which turns
    # nvim/lua/revive_session.lua off.
    set -l revive_dir
    if test -n "$__revive_rec"
        set revive_dir (string replace -r '\.rec$' .nvim -- $__revive_rec)
    end

    REVIVE_NVIM_DIR=$revive_dir command nvim $argv

    while test -f "$restart_flag"
        rm "$restart_flag"
        if test -f "$session_file"
            REVIVE_NVIM_DIR=$revive_dir command nvim -S "$session_file"
        else
            echo "No session file found at $session_file"
            break
        end
    end
end
