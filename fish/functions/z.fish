# Quick directory navigation (relies on chpwd.fish)
function z --description 'Jump to frequently used directory'
    set -l search (cat ~/.config/dir_history | search --select-1 --query "$argv")
    test -n "$search"; and cd $search
end
