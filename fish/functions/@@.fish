function @@
    set -l available (string split ' ' -- (cmds list 2>/dev/null))

    if contains main $available
        cmds main $argv
    else if contains start $available
        cmds start $argv
    else
        echo "@@: no 'main' or 'start' command found" >&2
        cmds --help
        return 1
    end
end
