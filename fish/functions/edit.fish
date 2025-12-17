function edit --description 'Edit a command defined in dotfiles'
    set -l path (type -p $argv[1] 2>/dev/null)
    if test -z "$path"
        echo "edit: '$argv[1]' not found"
        return 1
    end

    set -l real_path (realpath "$path" 2>/dev/null)

    type $argv[1]
    echo
    if not string match -q "$HOME/dotfiles/*" "$real_path"
        echo "warning: not in dotfiles"
    end
    read -P "edit $real_path? "; or return 1

    $EDITOR "$real_path"
end
