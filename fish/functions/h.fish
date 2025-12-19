function h --description 'Show type, location, and definition of a command'
    if test (count $argv) -eq 0
        echo "Usage: h <command>"
        return 1
    end

    set -l cmd $argv[1]

    # For functions, show source file and definition
    if functions -q $cmd
        set -l src (functions --details $cmd)
        if test "$src" != "n/a"
            set_color yellow
            echo "Source: $src"
            set_color normal
            echo
        end
        functions $cmd
    # For builtins
    else if contains $cmd (builtin --names)
        set_color cyan
        echo "$cmd is a builtin"
        set_color normal
    # For external commands
    else if command -v $cmd >/dev/null
        set -l path (command -v $cmd)
        set_color yellow
        echo "Path: $path"
        set_color normal
        file $path
        # If it's a script, show the first lines
        if file $path | grep -q "text"
            echo
            head -n 15 $path
        end
    else
        echo "h: '$cmd' not found"
        return 1
    end
end
