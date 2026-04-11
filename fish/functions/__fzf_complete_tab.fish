function __fzf_complete_tab
    set -l line "$argv"
    set -l kind (echo -- $line | choose 1 -f '\s{2,}|\t')
    __fzf_complete_log "tab line=$line kind=$kind"
    if test "$kind" = directory
        __fzf_complete_navigate $line >/dev/null
        echo -n "change-query($_fzf_complete_fd_prefix)"
    else
        echo -n accept
    end
end
