function __jump_direct --description 'cd straight to an argument that is already a directory; return 1 if it is not one'
    # Every jump command (p, j, z) takes its argument as a *fuzzy query* for a
    # picker. But their completions hand back whole paths, so tab-completing
    # leaves an exact directory on the line — which the picker then narrows to a
    # single row and waits for a second Enter on. Short-circuit that case.
    #
    # Callers keep their own post-cd bookkeeping (fzfm's history entry, etc.),
    # so this only does the test and the cd.
    test (count $argv) -eq 1
    or return 1

    set -l target (string replace --regex -- '^~/' $HOME/ $argv[1])

    # Requiring a slash keeps bare fuzzy words going to the picker, and stops
    # `.` / `..` being silently swallowed as a no-op jump.
    string match --quiet -- '*/*' $target
    or return 1

    test -d $target
    or return 1

    cd $target
end
