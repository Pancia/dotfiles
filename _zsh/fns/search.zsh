function gitroot { git rev-parse --show-toplevel "$@" }
function _gitignore_to_regex {
    (command cat .gitignore .ignore ~/.ignore ~/dotfiles/git/gitignore_global 2> /dev/null || echo '') \
        | sed '/^[#;"]/d' \
        | sed 's#^/##' \
        | tr '\n' '|' \
        | sed 's/\|*$//'
}
function tree { command tree -I "$(_gitignore_to_regex)" "$@" }

function search { peco "$@" }
