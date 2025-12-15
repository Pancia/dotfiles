#!/usr/bin/env fish

echo "TODAY is " (date +"%A, %b %d, %Y")
echo
echo "=== Upcoming Calendar Events ==="
set -l script_dir (dirname (status filename))
swift $script_dir/calendar.swift 24
echo
read --prompt-str 'Press Enter to continue... ' -l

set main_md $HOME/TheAkashicRecords/_main.md
set -l temp_file (mktemp)

echo "# Daily Journal - "(date +%Y-%m-%d_%H:%M:%S) > $temp_file
cat journal-template.md >> $temp_file

if test -f $main_md
    cat $main_md >> $temp_file
end

mv $temp_file $main_md

# Open vim at <INSERT> tag and replace it to enter insert mode
nvim "+/<INSERT>" "+normal cc" "+startinsert" $main_md

# Return to interactive shell when vim exits
exec fish
