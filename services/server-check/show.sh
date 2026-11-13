#!/usr/bin/env bash
# Opened in an iTerm window when the server-check notification is clicked.
# It shows the latest result and help for only the problems in it, then leaves
# an interactive fish shell. It runs nothing on the server.
#
# The match strings below must stay in step with the messages in script.sh.

log="$HOME/.log/services/server-check.log"
bold=$'\e[1m' red=$'\e[1;31m' green=$'\e[1;32m' yellow=$'\e[1;33m' reset=$'\e[0m'

echo "${bold}Vultr server check${reset}"
echo

latest=$(tail -n 1 "$log" 2>/dev/null)
if [ -z "$latest" ]; then
    echo "No result yet: there is no log at $log"
elif [[ "$latest" == *": ok" ]]; then
    echo "${green}Latest result: no problems${reset}"
    echo "  $latest"
    echo
elif [[ "$latest" != *PROBLEM:* ]]; then
    # "no internet; skipped", or an error message: the check did not finish.
    echo "${yellow}Latest result: the check did not finish${reset}"
    echo "  $latest"
    echo "  Look at the full log below."
    echo
else
    echo "${red}Latest result: problems found${reset}"
    echo "  $latest"
    echo

    if [[ "$latest" == *"encrypted disk is unlocked"* ]]; then
        cat <<'EOF'
Encrypted disk is unlocked
    /mnt stays readable until it is locked again. Lock it when you are done:
      ssh anthony@anthonydambrosio.me
      ~/bin/unmnt

EOF
    fi
    if [[ "$latest" == *"music disk not mounted"* || "$latest" == *"Navidrome is not answering"* ]]; then
        cat <<'EOF'
Music is down
    Look at the server:
      ssh anthony@anthonydambrosio.me
      mount; rcctl check navidrome

EOF
    fi
    if [[ "$latest" == *"SSH: server unreachable"* || "$latest" == *"Headscale or its certificate"* ]]; then
        cat <<'EOF'
Server or Headscale unreachable
    The server or its network is down, or the certificate expired.
    Look at the Vultr console in a browser.

EOF
    fi
fi

cat <<EOF
More information:
  Full log:      $log
  Run it again:  SERVER_CHECK_DRY=1 ~/dotfiles/services/server-check/script.sh
  Server notes:  ~/dotfiles/remote/anthonydambrosio.me/README.md

EOF

# Stay open in an interactive shell, so you can act on what is shown.
exec /opt/homebrew/bin/fish -l
