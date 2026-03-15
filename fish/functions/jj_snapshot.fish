function jj_snapshot --description "Snapshot jj repo for a given path"
    set -l target $argv[1]
    test -z "$target"; and return 0

    # If it's a file, get its directory
    if test -f "$target"
        set target (path dirname "$target")
    end

    # Walk up to find a .jj directory
    while test "$target" != /
        if test -d "$target/.jj"
            jj util snapshot -R "$target" 2>/dev/null
            return 0
        end
        set target (path dirname "$target")
    end
end
