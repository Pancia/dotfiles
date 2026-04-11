function _fzf_complete
#  set --local _DEBUG_PIPE tee -a DEBUG_COMPLETE.txt ## DEBUG

  __fzf_complete_log "====== _fzf_complete start ======"

  #### We're exporting some vars for the __fzf_complete_reload function

  set --local current_token (commandline --current-token)
  __fzf_complete_log "current_token=$current_token"
  set --local --export preceding_tokens (commandline --current-process --cut-at-cursor --tokenize)
  __fzf_complete_log "got preceding_tokens"
  set --local all_tokens (commandline --current-process --tokenize)
  __fzf_complete_log "got all_tokens"

  set --local token_pos (math (commandline --cursor) - (commandline --cursor --current-token))
  __fzf_complete_log "got token_pos=$token_pos"

  # Tide's fish_prompt hangs re-entrantly inside a key binding; skip it.
  # This value just controls fzf popup horizontal alignment (cosmetic).
  set --local fish_prompt_offset 2
  __fzf_complete_log "fish_prompt_offset=$fish_prompt_offset (hardcoded)"
  set --local token_pos_on_screen (math "($token_pos + $fish_prompt_offset) % $COLUMNS")

  set --local min_prompt_size 40
  set --local max_prompt_offset (math "$COLUMNS - $min_prompt_size")

  set --local fzf_offset (math "min($token_pos_on_screen - 3, $max_prompt_offset)")

  if test (math $token_pos_on_screen + (string length -- $current_token)) -gt $COLUMNS
    set fzf_offset 0
  end
  __fzf_complete_log "fzf_offset=$fzf_offset (before fzf_args)"

  ## If we reload on change here, we lose the ability to fuzzy-search the
  ## description text and it's also quite slow.
  ##
  ## If we reload on deletion, we can easily lose state – we're fuzzy searching an
  ## arg description, make a typo, delete, suddenly we have different completions
  ## available. Plus there's a lot of dealing with edge cases like -options and
  ## $vars, etc.
  ##
  ## It looks like the most solid option is to only reload manually, otherwise do
  ## fuzzy-search only. It's solid, reliable, no edge cases and it's the default
  ## fish completion search behaviour. Unless we encounter a _very_ good reason to
  ## change that down the road, we're gonna stick with it for now.

  set --local fzf_args \
    --height 11 \
    -i \
    --border=none \
    --margin 0,0,0,$fzf_offset \
    --no-info \
    --reverse \
    --cycle \
    --tiebreak=begin \
    --query (string unescape -- $current_token) \
    --bind backward-eof:abort \
    --bind "ctrl-r:reload(__fzf_complete_reload {q})" \
    --bind "ctrl-w:backward-kill-word" \
#    --bind "tab:down" \
#    --bind "btab:up" \
#    --bind "ctrl-w:unix-word-rubout+reload($reload_cmd)" \
#    --multi \
#    --bind "change:reload($reload_cmd)" \
#    --bind "bspace:backward-delete-char+reload($reload_cmd)" \
#    --bind "ctrl-d:delete-char+reload($reload_cmd)" \
#    --bind "alt-d:kill-word+reload($reload_cmd)" \
#    --bind "ctrl-u:unix-line-discard+reload($reload_cmd)" \
#    --bind "ctrl-k:kill-line+reload($reload_cmd)" \
#    --bind "del:delete-char+reload($reload_cmd)" \

  __fzf_complete_log "fzf_args built"
  set --local token_trailing_space " "
  if test (count $all_tokens) -gt (math (count $preceding_tokens) + 1) || test -z "$current_token"
    set token_trailing_space ""
  end

  set --local column_select_cmd "choose 0 -f '\s{2,}|\\t'"
  set --local set_cursor_cmd 'commandline --cursor (math (commandline --cursor) + 1 - (string length -- $token_trailing_space))'
  set --local --export column_format_cmd "/opt/homebrew/opt/util-linux/bin/column --table --table-columns-limit 2 --separator $(printf '\\\\t')"

  #### Path-like token? Use fd instead of fish's 1-level completion.
  set --local --export _fzf_complete_fd_anchor ""
  set --local --export _fzf_complete_fd_prefix ""
  set --local --export _fzf_complete_fd_depth 3

  if string match -qr '/' -- $current_token
    set --local anchor_raw (string replace -r '[^/]*$' '' -- $current_token)
    set --local expanded (string replace -r '^~' "$HOME" -- $anchor_raw)
    __fzf_complete_log "path detect anchor_raw=$anchor_raw expanded=$expanded"
    if test -d "$expanded"
      set _fzf_complete_fd_anchor $expanded
      set _fzf_complete_fd_prefix $anchor_raw
      # Persist state across fzf reload subshells via a tempfile
      set --global --export _fzf_complete_state_file (mktemp /tmp/fzf_complete_state.XXXXXX)
      __fzf_complete_state_write
      __fzf_complete_log "state_file=$_fzf_complete_state_file"
      # Live reload as query changes, so edits that shift the anchor refresh results
      set --append fzf_args --bind 'change:reload(fish -c "__fzf_complete_reload {q}")'
      # Tab dives into a directory: navigate updates state+prefix, then we set the
      # query to the new prefix, which triggers change:reload to refetch the list.
      set --append fzf_args --bind 'tab:transform-query(fish -c "__fzf_complete_navigate {} > /dev/null; echo -n \$_fzf_complete_fd_prefix")'
    end
  end

  # Non-path mode still needs tab to accept (fzf's default for tab in single-mode is no-op)
  if test -z "$_fzf_complete_fd_anchor"
    set --append fzf_args --bind "tab:accept-non-empty"
  end

  set --local fish_completions
  if test -n "$_fzf_complete_fd_anchor"
    __fzf_complete_log "mode=path anchor=$_fzf_complete_fd_anchor depth=$_fzf_complete_fd_depth"
    set fish_completions (__fzf_complete_gather_raw)
  else
    __fzf_complete_log "mode=fish preceding_tokens=$preceding_tokens"
    set fish_completions (complete --do-complete="$preceding_tokens $current_token")
  end
  __fzf_complete_log "completions count="(count $fish_completions)

  set --local abbreviation_regex '^\S+\s+Abbreviation: .+'

  if test (count $fish_completions) -eq 0
    return
  else if test (count $fish_completions) -eq 1
    string match --quiet --regex -- "$abbreviation_regex" "$fish_completions[1]" && set token_trailing_space ""
    string match --quiet --regex -- '^(?<tilde_prefix>~/)?(?<completion_rest>.*)$' "$(echo -- $fish_completions[1] | eval $column_select_cmd)"
    string match --quiet -- '*/' "$completion_rest" && set token_trailing_space ""

    commandline --current-token --replace -- \
    "$tilde_prefix$(string escape -- $completion_rest)$token_trailing_space"

    eval $set_cursor_cmd
    commandline --function repaint
    return
  else
    __fzf_complete_log "fzf launch SHELL=$SHELL"
    __fzf_complete_log "fzf_args=$fzf_args"
    set --local fzf_completion_raw (__fzfm_println $fish_completions | eval $column_format_cmd | fzf $fzf_args)
    __fzf_complete_log "fzf exit"
    if set -q _fzf_complete_state_file
      rm -f $_fzf_complete_state_file
      set -e _fzf_complete_state_file
    end
    string match --quiet --regex -- "$abbreviation_regex" "$fzf_completion_raw" && set token_trailing_space ""
    set --local fzf_completion (echo -- $fzf_completion_raw | eval $column_select_cmd)

    if not test -z "$fzf_completion"
      string match --quiet -- '*/' "$fzf_completion" && set token_trailing_space ""
      string match --quiet --regex -- '^(?<tilde_prefix>~/)?(?<completion_rest>.*)$' "$fzf_completion"

      commandline --current-token --replace -- \
      "$tilde_prefix$(string escape -- $completion_rest)$token_trailing_space"

      eval $set_cursor_cmd
    end
    commandline --function repaint
  end
end
