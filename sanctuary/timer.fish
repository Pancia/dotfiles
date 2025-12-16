#!/usr/bin/env fish

set -l script_dir (path resolve (dirname (status filename)))
echo scriptdir is $script_dir

echo "=== Inbox Journals ==="
bat --paging=never /Users/anthony/Cloud/_inbox/Journals/*
echo

read --prompt-str 'work> ' -c '24' work
read --prompt-str 'short> ' -c '6' short
read --prompt-str 'sessions> ' -c '4' sessions
read --prompt-str 'LABEL> ' LABEL
echo q pymodoro --label "$LABEL" --work $work --short $short --long $work --max-sessions $sessions --notify 0 --confirm
q pymodoro --label "$LABEL" --work $work --short $short --long $work --max-sessions $sessions --notify 0 --confirm

# Return to interactive shell when done
cd $script_dir
exec fish
