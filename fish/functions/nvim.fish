function nvim --description 'Neovim wrapper with session restart support' --wraps nvim
    set -l restart_flag ~/.local/share/nvim/restart

    set -l session_file ~/.local/share/nvim/session.vim

    command nvim $argv

    while test -f "$restart_flag"
        rm "$restart_flag"
        if test -f "$session_file"
            command nvim -S "$session_file"
        else
            echo "No session file found at $session_file"
            break
        end
    end
end
