function __fzf_complete_state_read
    set -q _fzf_complete_state_file; or return
    test -f "$_fzf_complete_state_file"; or return
    set -l parts (string split \t -- (cat $_fzf_complete_state_file))
    set -gx _fzf_complete_fd_anchor $parts[1]
    set -gx _fzf_complete_fd_prefix $parts[2]
    set -gx _fzf_complete_fd_depth $parts[3]
end
