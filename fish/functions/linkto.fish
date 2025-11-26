function linkto --description 'Create symlinks with intuitive syntax: linkto [options] source target (creates link at source pointing to target)'
    # linkto -s source target
    # calls: ln -s target source
    # Result: source is a link pointing to target

    if test (count $argv) -lt 2
        echo "Error: linkto requires at least 2 arguments" >&2
        echo "Usage: linkto [ln-options] source target" >&2
        echo "Creates a link at 'source' pointing to 'target'" >&2
        return 1
    end

    # Get the last two arguments (source and target)
    set -l target $argv[-1]
    set -l source $argv[-2]

    # Get all options (everything except the last two arguments)
    set -l opts
    if test (count $argv) -gt 2
        set opts $argv[1..(math (count $argv) - 2)]
    end

    # Call ln with swapped order: ln [opts] target source
    command ln $opts $target $source
end
