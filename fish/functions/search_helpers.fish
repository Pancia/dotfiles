# Search and navigation helpers
function gitroot --description 'Get git repository root' --wraps 'git rev-parse'
    git rev-parse --show-toplevel $argv
end

function _gitignore_to_regex --description 'Convert gitignore to regex'
    cat .gitignore .ignore ~/.ignore ~/dotfiles/git/gitignore_global 2> /dev/null; or echo ''
    | sed '/^[#;"]/d' \
    | sed 's#^/##' \
    | tr '\n' '|' \
    | sed 's/\|*$//'
end

function tree --description 'Tree with gitignore filtering' --wraps tree
    command tree -I (_gitignore_to_regex) $argv
end

function search --description 'Interactive search with peco' --wraps peco
    peco $argv
end
