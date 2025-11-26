function fish_user_key_bindings
    # Fuzzy tab completion using fzf (disabled - too slow)
    # Tab - primary completion trigger
    # bind \t _fzf_complete

    # Ctrl+S - fzfm leader key
    # Press Ctrl+S to show menu, then press a letter (Space, s, f, r, g, d, a, q)
    # Press Ctrl+S Space for quick default file search
    bind \cs fzfm_leader
end
