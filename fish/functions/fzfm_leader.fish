function fzfm_leader
    # Check if we're already running (prevents recursive/concurrent calls)
    if set -q __fzfm_leader_busy
        # Already running, ignore this call
        return
    end

    # Set busy flag
    set -g __fzfm_leader_busy 1

    # Save current command line
    set -l current_commandline (commandline)

    # Show help menu
    echo
    echo (set_color --bold cyan)"fzfm:"(set_color normal)
    echo "  "(set_color green)"Space"(set_color normal)" - Search files "(set_color --bold)"(default)"(set_color normal)
    echo "  "(set_color green)"j"(set_color normal)" - "(set_color --bold)"J"(set_color normal)"ump to directory"
    echo "  "(set_color green)"s"(set_color normal)" - "(set_color --bold)"S"(set_color normal)"earch files"
    echo "  "(set_color green)"f"(set_color normal)" - Search all "(set_color --bold)"f"(set_color normal)"iles"
    echo "  "(set_color green)"r"(set_color normal)" - "(set_color --bold)"R"(set_color normal)"ecent/frequent files"
    echo "  "(set_color green)"g"(set_color normal)" - "(set_color --bold)"G"(set_color normal)"rep search (search file contents)"
    echo "  "(set_color green)"d"(set_color normal)" - Current "(set_color --bold)"d"(set_color normal)"irectory only"
    echo "  "(set_color green)"a"(set_color normal)" - "(set_color --bold)"A"(set_color normal)"ll files (thorough search)"
    echo "  "(set_color green)"q"(set_color normal)" - "(set_color --bold)"Q"(set_color normal)"uit/cancel"
    echo
    echo -n (set_color cyan)"Choose:"(set_color normal)" "

    # Read single character
    read -n 1 key

    # Clear display
    echo

    # Execute action based on key
    switch $key
        case ' '
            # Space - default file search
            __fzfm_search all
        case j J
            # Jump to directory
            __fzfm_search jump_frecent
        case s S
            # Search files
            __fzfm_search all
        case f F
            # Search all files
            __fzfm_search all
        case r R
            # Recent/frequent files
            __fzfm_search frecent
        case g G
            # Grep search
            __fzfm_search grep_inside
        case d D
            # Inside current directory
            __fzfm_search inside
        case a A
            # All files (more thorough)
            __fzfm_search All
        case q Q ''
            # Cancel (q, Q, Escape, or Ctrl+C)
            # Just return without doing anything
        case '*'
            # Invalid key
            echo (set_color red)"Unknown key: $key"(set_color normal)
            sleep 0.5
    end

    set -e __fzfm_leader_busy  # Clear busy flag
    commandline -f repaint
end
