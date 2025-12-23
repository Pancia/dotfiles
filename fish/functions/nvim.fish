function nvim --description 'Neovim wrapper with session restart support' --wraps nvim
    set -l restart_flag ~/.local/share/nvim/restart

    command nvim $argv

    if test -f "$restart_flag"
        rm "$restart_flag"
        nvims
    end
end
