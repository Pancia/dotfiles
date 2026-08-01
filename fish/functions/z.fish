# Quick directory navigation (relies on chpwd.fish)
function z --description 'Jump to frequently used directory'
    # Tab completion here is fish's default (directories), so it hands back an
    # exact path. peco's --select-1 does not help: it fires only when the
    # *input* is a single item, not when the query narrows to one. See
    # __jump_direct.
    __jump_direct $argv
    and return

    # chpwd records every directory visited and never checks back, so the file
    # refills with deleted worktrees and pytest temp dirs. Filter at read time
    # so the picker only ever offers somewhere you can actually land.
    # Absolute-only: a bare entry would otherwise resolve against the current
    # directory and appear to exist from some cwds but not others.
    set -l dirs
    for path in (cat ~/.config/dir_history)
        string match --quiet -- '/*' $path
        and test -d $path
        and set -a dirs $path
    end
    test (count $dirs) -gt 0
    or return 1

    # printf with the list unquoted — one entry per line. "$dirs" would join
    # them onto a single line, which is the bug that broke this file.
    set -l search (printf '%s\n' $dirs | search --select-1 --query "$argv")
    test -n "$search"; and cd $search
end
