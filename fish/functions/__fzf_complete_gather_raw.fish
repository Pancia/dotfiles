function __fzf_complete_gather_raw
    set -l anchor $_fzf_complete_fd_anchor
    set -l prefix $_fzf_complete_fd_prefix
    set -l depth $_fzf_complete_fd_depth

    set -l anchor_clean (string replace -r '/$' '' -- $anchor)
    test -z "$anchor_clean"; and set anchor_clean /

    __fzf_complete_log "gather: fd start anchor=$anchor_clean depth=$depth"
    fd --type d --type f --type l --hidden --follow --max-depth $depth . "$anchor_clean" 2>/dev/null | while read -l p
        set -l rel (string replace -- "$anchor_clean/" '' $p)
        if string match -q '*/' -- $p
            printf '%s\tdirectory\n' "$prefix$rel"
        else
            printf '%s\tfile\n' "$prefix$rel"
        end
    end
    __fzf_complete_log "gather: fd done"
end
