#!/usr/bin/env bash
# Opened in an iTerm window when a claude-watchdog notification is clicked.
# It shows one incident: what the verdict means, what the process is, and
# whether it is still running. Then it leaves an interactive fish shell.
# It changes nothing and signals nothing.
#
# Usage: show.sh <incident-dir>   (no argument: the newest incident)
#
# The verdict names below must stay in step with bin/claude-watchdog.

incidents="${XDG_STATE_HOME:-$HOME/.local/state}/claude-watchdog/incidents"
dir=${1:-$(ls -td "$incidents"/*/ 2>/dev/null | head -n 1)}
dir=${dir%/}
bold=$'\e[1m' red=$'\e[1;31m' green=$'\e[1;32m' yellow=$'\e[1;33m' reset=$'\e[0m'

echo "${bold}claude-watchdog incident${reset}"
echo

if [ -z "$dir" ] || [ ! -f "$dir/summary.txt" ]; then
    echo "No incident to show. Looked for: ${dir:-$incidents/*}"
    echo
    exec /opt/homebrew/bin/fish -l
fi

verdict=$(awk -F': *' '/^verdict:/ {print $2}' "$dir/summary.txt")
pid=$(awk -F': *' '/^pid:/ {print $2}' "$dir/summary.txt")

case "$verdict" in
    ORPHAN-IDLE)
        echo "${yellow}An idle Claude process has no parent${reset}"
        echo "  The program that started it has exited, and it has used almost no CPU"
        echo "  for at least 30 minutes. This is usually harmless, for example"
        echo "  Claude Code's own background helper ('claude daemon run')."
        ;;
    ORPHAN-CANDIDATE)
        echo "${red}A Claude process with no parent is growing${reset}"
        echo "  The program that started it has exited, and its memory and CPU"
        echo "  stayed high and kept rising for the whole sample window."
        ;;
    CANDIDATE)
        echo "${red}A headless Claude process is growing${reset}"
        echo "  Its memory and CPU stayed high and kept rising for the whole"
        echo "  sample window. This is the runaway pattern the watchdog exists for."
        ;;
    *)
        echo "${yellow}Verdict: ${verdict:-unknown}${reset}"
        ;;
esac
echo "  The watchdog did not stop it. It only records and notifies."
echo

echo "${bold}The process${reset}"
# Cut the command line short: it can carry hundreds of flags.
awk 'NR == 2 { $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""; sub(/^ +/, "");
               print "  " substr($0, 1, 300) (length($0) > 300 ? " ..." : "") }' \
    "$dir/proc.txt"
if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "  ${yellow}Still running${reset} as pid $pid ($(ps -o etime= -p "$pid" | tr -d ' ') old)."
    echo "  To stop it:  kill $pid"
else
    echo "  ${green}No longer running.${reset}"
fi
echo

echo "${bold}Summary${reset}"
sed 's/^/  /' "$dir/summary.txt"
echo

cat <<EOF
More information:
  This incident:  $dir
  Watchdog log:   ~/.log/services/claude-watchdog.log
  How it works:   ~/dotfiles/docs/claude-watchdog.md

EOF

# Stay open in an interactive shell, so you can act on what is shown.
exec /opt/homebrew/bin/fish -l
