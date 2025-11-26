function fish_user_key_bindings
    # Fuzzy tab completion using fzf (disabled - too slow)
    # Tab - primary completion trigger
    # bind \t _fzf_complete

    # Ctrl+S - fzfm leader key
    # Press Ctrl+S, then a letter (f, r, g, d, a)
    bind \cs _fzfm_leader
end
