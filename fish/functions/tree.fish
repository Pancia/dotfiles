function _gitignore_to_regex --description 'Convert gitignore to regex'
    cat .gitignore .ignore ~/.ignore ~/dotfiles/git/gitignore_global 2>/dev/null |
        string match -v -r '^[#;"]|^$' |
        string replace -r '^/' '' |
        string join '|'
end

function tree --description 'Tree with gitignore filtering' --wraps tree
    command tree -I (_gitignore_to_regex) $argv
end
