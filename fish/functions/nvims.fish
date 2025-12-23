function nvims --description 'Open nvim with saved session'
    set -l session_file ~/.local/share/nvim/session.vim
    if test -f "$session_file"
        command nvim -S "$session_file" $argv
    else
        echo "No session file found at $session_file"
        echo "Use :SessionSave or :SessionRestart in nvim to create one"
    end
end
