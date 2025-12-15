function v
    set -l file (fd --type f --follow --hidden | \
        fzf --tac --no-sort \
            --preview='bat --style=numbers --color=always {} 2>/dev/null || cat {}' \
            --preview-window=right:50%)
    if test -n "$file"
        nvim "$file"
    end
end
