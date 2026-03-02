function gd --description 'git diff --color-words, including untracked files'
    git diff --color-words $argv
    for f in (git ls-files --others --exclude-standard)
        git diff --color-words --no-index /dev/null $f 2>/dev/null
    end
end
