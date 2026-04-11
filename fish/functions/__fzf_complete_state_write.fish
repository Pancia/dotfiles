function __fzf_complete_state_write
    set -q _fzf_complete_state_file; or return
    printf '%s\t%s\t%s' "$_fzf_complete_fd_anchor" "$_fzf_complete_fd_prefix" "$_fzf_complete_fd_depth" > $_fzf_complete_state_file
end
