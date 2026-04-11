function __fzf_complete_reload
  __fzf_complete_state_read
  __fzf_complete_log "reload start argv=$argv anchor_in=$_fzf_complete_fd_anchor"
  if test -n "$_fzf_complete_fd_anchor"
    # Recompute anchor from the live fzf query so editing the path navigates
    set -l query $argv
    if test -n "$query"
      set -l anchor_raw (string replace -r '[^/]*$' '' -- $query)
      set -l expanded (string replace -r '^~' "$HOME" -- $anchor_raw)
      if test -d "$expanded"
        set -gx _fzf_complete_fd_anchor $expanded
        set -gx _fzf_complete_fd_prefix $anchor_raw
        __fzf_complete_state_write
        __fzf_complete_log "reload anchor updated -> $expanded"
      end
    end
    __fzf_complete_gather_raw | eval $column_format_cmd
    __fzf_complete_log "reload done"
    return
  end
  string match --quiet --regex -- '^(?<tilde_prefix>~/)?(?<completion_rest>.*)$' "$argv"
  set --local escaped_query "$tilde_prefix$(string escape -- $completion_rest)"
  complete --do-complete "$preceding_tokens $escaped_query" | eval $column_format_cmd
end
