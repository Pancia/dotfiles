function __fzf_complete_gather_raw
    set -l anchor $_fzf_complete_fd_anchor
    set -l prefix $_fzf_complete_fd_prefix
    set -l depth $_fzf_complete_fd_depth

    set -l anchor_clean (string replace -r '/$' '' -- $anchor)
    test -z "$anchor_clean"; and set anchor_clean /

    __fzf_complete_log "gather: fd start anchor=$anchor_clean depth=$depth"
    set -l strip "$anchor_clean/"
    test "$anchor_clean" = /; and set strip /
    fd --type d --type f --type l --hidden --follow --max-depth $depth . "$anchor_clean" 2>/dev/null \
        | awk -v p="$prefix" -v s="$strip" '
            BEGIN { slen = length(s) }
            {
                if (substr($0, 1, slen) == s) $0 = substr($0, slen + 1)
                if (substr($0, length($0), 1) == "/") print p $0 "\tdirectory"
                else print p $0 "\tfile"
            }'
    __fzf_complete_log "gather: fd done"
end
