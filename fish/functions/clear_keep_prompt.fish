function clear_keep_prompt --description 'Clear screen and scrollback but keep tide prompt visible'
    # Clear scrollback buffer (works in most terminals including iTerm2)
    printf '\e[3J'
    # Clear the screen
    printf '\e[2J'
    # Move cursor to top
    printf '\e[H'
    # iTerm2-specific: also clear their scrollback
    printf '\e]1337;ClearScrollback\a'
    # Repaint the current prompt
    commandline -f repaint
end
