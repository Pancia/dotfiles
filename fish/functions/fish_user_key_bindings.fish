function fish_user_key_bindings
    # Ctrl+S - fzfm leader key
    # Press Ctrl+S to show menu, then press a letter (Space, s, f, r, g, d, a, q)
    # Press Ctrl+S Space for quick default file search
    bind \cs fzfm_leader

    # Ctrl+Z - fancy ctrl-z (fg or jobs, or push-line + clear-screen)
    bind \cz fancy_ctrl_z

    # Override fzfm's ctrl-j binding with alt-j to avoid conflict with newline
    bind \ej '__fzfm_search jump_frecent'
    bind \e\cJ '__fzfm_search jump_frecent_aux'
    # Unbind ctrl-j so it acts as normal newline
    bind \cj execute

    # Tab - fzf completion for p and d commands, normal completion otherwise
    bind \t __fzf_complete_cmd
end
