function __fzf_complete_navigate
    __fzf_complete_state_read
    set -l line "$argv"
    __fzf_complete_log "navigate line=$line anchor_in=$_fzf_complete_fd_anchor"
    set -l path (echo -- $line | choose 0 -f '\s{2,}|\t')
    set -l kind (echo -- $line | choose 1 -f '\s{2,}|\t')
    __fzf_complete_log "navigate path=$path kind=$kind"

    if test "$kind" = directory
        set -l expanded (string replace -r '^~' "$HOME" -- $path)
        set -l resolved (string replace -r '/$' '' -- $expanded)
        if test -d "$resolved"
            set -gx _fzf_complete_fd_anchor $resolved
            set -gx _fzf_complete_fd_prefix $path
            __fzf_complete_state_write
            __fzf_complete_log "navigate anchor updated -> $resolved"
        end
    end

    __fzf_complete_gather_raw | eval $column_format_cmd
    __fzf_complete_log "navigate done"
end
