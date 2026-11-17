#!/usr/bin/env bash
# Side-by-side readability test for the blue colors in `alt tui` on a transparent iTerm.
# Green, yellow, red, magenta and orange stay at their current values in every row.
# Prints only. Changes no config. Run it in the same iTerm window as the TUI.

fg() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
bg() { printf '\033[48;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
B=$'\033[1m'
R=$'\033[0m'

# args: "fg" or "fg/bg"
style() {
  local out; out=$(fg "${1%%/*}")
  [[ $1 == */* ]] && out+=$(bg "${1##*/}")
  printf '%s' "$out"
}

# args: label title-style time-color cyan-style
row() {
  local label=$1 title cyan time
  title=$(style "$2"); time=$(fg "$3"); cyan=$(style "$4")
  printf '\n%s\n' "$label"
  printf '%s%s %s %s\n' "$B" "$title" "RECENT EVENTS" "$R"
  printf '  %s12:20:41%s  %s %s %s\n' "$time" "$R" "$cyan" "daemon_tick_reactive" "$R"
  printf '  %s12:20:12%s  %s %s %s\n' "$time" "$R" "$(fg '#9ece6a')" "task_merged" "$R"
  printf '  %s12:19:58%s  %s %s %s\n' "$time" "$R" "$(fg '#e0af68')" "worker_waiting" "$R"
  printf '  %s12:19:40%s  %s %s %s\n' "$time" "$R" "$(fg '#f7768e')" "worker_failed" "$R"
  printf '  %s12:19:21%s  %s %s %s\n' "$time" "$R" "$(fg '#bb9af7')" "mission_created" "$R"
}

row "A. Current"                    '#7aa2f7'         '#565f89' '#7dcfff'
row "D. Deeper blue text"           '#1d4ed8'         '#3b4466' '#0369a1'
row "E. Dark background on blues"   '#7aa2f7/#1a1b26' '#3b4466' '#7dcfff/#1a1b26'
row "F. White text on blue"         '#ffffff/#1d4ed8' '#3b4466' '#ffffff/#0369a1'
echo
