# relies on chpwd.zsh
function z() {
    local search=`cat ~/.config/dir_history | search --select-1 --query "${@:- }"`
    [[ -n $search ]] && cd $search
}
