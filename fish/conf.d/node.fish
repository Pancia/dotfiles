# Node.js configuration
set -gx NODE_OPTIONS --max_old_space_size=8192

# Put the nearest node_modules/.bin (this folder or a parent) first on PATH,
# and only while you are inside that project. Session-scoped: nothing is saved.
#
# This replaced `fish_add_path --prepend ./node_modules/.bin`, which resolved
# the relative path against the folder the shell started in and saved it in
# universal fish_user_paths. Every project a shell ever started in then stayed
# first on PATH in every shell, for good, so `tsc` anywhere ran one project's copy.
function __node_bin_path --on-variable PWD --description 'Keep the nearest node_modules/.bin on PATH'
    set -l want
    set -l dir $PWD
    while true
        if test -d "$dir/node_modules/.bin"
            set want "$dir/node_modules/.bin"
            break
        end
        test "$dir" = /; and break
        set dir (path dirname -- $dir)
    end
    if set -q __node_bin_current; and test "$__node_bin_current" = "$want"
        return
    end
    if set -q __node_bin_current
        set -l i (contains -i -- $__node_bin_current $PATH)
        and set -e PATH[$i]
        set -e __node_bin_current
    end
    if test -n "$want"
        set -g __node_bin_current $want
        set -gx PATH $want $PATH
    end
end
__node_bin_path
