## Thanks to ChatGPT
on run argv
    repeat with i from 1 to count of argv
        set file_path to POSIX file (item i of argv) as alias
        tell application "Finder"
            move file_path to trash
        end tell
    end repeat
end run
