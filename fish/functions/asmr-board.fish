function asmr-board
    set -l dir ~/projects/asmr-board
    set -l tab_cmd "cd $dir && cc"

    switch $TERM_PROGRAM
        case Apple_Terminal
            osascript -e "
                tell application \"Terminal\"
                    activate
                    tell application \"System Events\" to keystroke \"t\" using command down
                    delay 0.3
                    do script \"$tab_cmd\" in front window
                end tell
            "
        case 'iTerm.app'
            osascript -e "
                tell application \"iTerm\"
                    tell current window
                        create tab with default profile
                        tell current session
                            write text \"$tab_cmd\"
                        end tell
                    end tell
                end tell
            "
        case ghostty
            osascript -e "
                tell application \"Ghostty\"
                    activate
                    tell application \"System Events\" to keystroke \"t\" using command down
                    delay 0.3
                    tell application \"System Events\"
                        keystroke \"$tab_cmd\"
                        key code 36
                    end tell
                end tell
            "
        case '*'
            echo "Unsupported terminal: $TERM_PROGRAM"
    end

    cd $dir && cmds start
end
