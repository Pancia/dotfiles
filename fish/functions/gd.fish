function gd --description 'git diff --color-words, including untracked files'
    set -l tmp (mktemp)
    git diff --color-words $argv >$tmp
    for f in (git ls-files --others --exclude-standard)
        git diff --color-words --no-index /dev/null $f 2>/dev/null >>$tmp
    end
    bat --paging=always --style=plain $tmp
    rm -f $tmp
end
