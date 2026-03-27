function gd --description 'diff with pager (git or jj)'
    if test -d .jj
        jj diff $argv
    else
        set -l tmp (mktemp)
        git diff --color-words $argv >$tmp
        for f in (git ls-files --others --exclude-standard -- $argv)
            git diff --color-words --no-index /dev/null $f 2>/dev/null >>$tmp
        end
        bat --paging=always --style=plain $tmp
        rm -f $tmp
    end
end
