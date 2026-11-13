#!/usr/bin/env bash
# Tuesday and Friday: run the vault's media-sync (YouTube channels and Pinterest
# into ProtonDrive). The sources are in ~/AKR/tools/media-sync/sources.toml.
#
#   start    macOS notification
#   success  macOS notification + Inari Telegram message with the counts
#   failure  macOS notification; a click opens Claude Code in the vault with the
#            log. The Claude Code Telegram bot gets the same prompt to send back.
#
# MEDIA_SYNC_CMD overrides the command, for testing (e.g. MEDIA_SYNC_CMD=false).
# MEDIA_SYNC_DRY=1 prints the notifications and messages instead of sending them.

set -u
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

akr="$HOME/Vaults/the-akashic-records"
cmd="${MEDIA_SYNC_CMD:-$akr/scripts/media-sync}"
env_file="$akr/tools/inari/.env"
state="${XDG_STATE_HOME:-$HOME/.local/state}/media-sync"
notifier=/opt/homebrew/bin/terminal-notifier
dry="${MEDIA_SYNC_DRY:-}"

mkdir -p "$state/runs"
runlog="$state/runs/$(date +%Y-%m-%d_%H%M%S).log"
prompt_file="$state/fix-prompt.md"

notify() { # title message [command to run on click]
    if [ -n "$dry" ]; then echo "would notify: $1 — $2 ${3:+(click: $3)}"; return; fi
    if [ -n "${3:-}" ]; then
        # No -group: a failure must stay on screen, not be replaced by a later notice.
        # It clears the "Started" notice instead.
        "$notifier" -remove media-sync >/dev/null
        "$notifier" -title "$1" -message "$2" -execute "$3"
    else
        "$notifier" -title "$1" -message "$2" -group media-sync
    fi
}

telegram() { # token-variable-name html-text
    if [ -n "$dry" ]; then echo "would send ($1): $2"; return; fi
    local token chat
    token=$(/usr/bin/grep -E "^$1=" "$env_file" 2>/dev/null | /usr/bin/cut -d= -f2- | /usr/bin/tr -d "\"' ")
    chat=$(/usr/bin/grep -E '^TELEGRAM_CHAT_ID=' "$env_file" 2>/dev/null | /usr/bin/cut -d= -f2- | /usr/bin/tr -d "\"' ")
    if [ -z "$token" ] || [ -z "$chat" ]; then
        echo "telegram: $1 or TELEGRAM_CHAT_ID missing from $env_file"
        return 1
    fi
    /usr/bin/curl -fsS -m 30 "https://api.telegram.org/bot$token/sendMessage" \
        --data-urlencode "chat_id=$chat" --data-urlencode "text=$2" \
        --data-urlencode "parse_mode=HTML" -o /dev/null \
        || echo "telegram: send with $1 failed"
}

html_escape() { /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

if [ -n "$dry" ]; then
    echo "would notify: Media sync — Started (click: tail -f $runlog)"
else
    # In the group, so the end notice replaces it. A click follows the live log.
    "$notifier" -title "Media sync" -message "Started — click to watch" -group media-sync \
        -execute "$HOME/dotfiles/bin/open-iterm-with tail -n +1 -f $runlog"
fi
echo "start: $cmd (log $runlog)"

"$cmd" >"$runlog" 2>&1
rc=$?

# media-sync's own status lines, without the timestamp and the final "done".
summary=$(/usr/bin/grep -E '^\[[0-9-]+ [0-9:]+\] ' "$runlog" | /usr/bin/sed 's/^\[[^]]*\] //' \
    | /usr/bin/grep -vE '^done$|: start \(' )
echo "$summary"
echo "exit $rc"

if [ "$rc" -eq 75 ]; then
    notify "Media sync" "Skipped: another run is still going"
    exit 0
fi

if [ "$rc" -eq 0 ]; then
    short=$(echo "$summary" | /usr/bin/sed 's/: ok, /: /; s/ new file(s)/ new/' | /usr/bin/paste -sd ',' - | /usr/bin/sed 's/,/, /g')
    notify "Media sync done" "${short:-nothing to do}"
    telegram TELEGRAM_BOT_TOKEN "📥 <b>Media sync done</b>
$(echo "$summary" | html_escape)"
    exit 0
fi

# Failure: leave a prompt that Claude Code can start from, on either device.
cat >"$prompt_file" <<EOF
The scheduled media-sync run failed on $(date '+%a %Y-%m-%d %H:%M') (exit $rc).

- Full log: $runlog
- Script: ~/AKR/scripts/media-sync
- Sources: ~/AKR/tools/media-sync/sources.toml
- Schedule and notifications: ~/dotfiles/services/media-sync/script.sh
- Earlier runs: $state/runs/

Status lines from the run:
$summary

Read the log, find the cause and tell me. Propose a fix before you change anything.
Common causes: ProtonDrive not running, an outdated yt-dlp (brew upgrade yt-dlp),
a deleted or members-only video, or a changed channel URL.
EOF

failed=$(echo "$summary" | /usr/bin/grep -E 'FAILED' | /usr/bin/head -3 | /usr/bin/paste -sd ';' - | /usr/bin/sed 's/;/; /g')
notify "Media sync FAILED" "${failed:-exit $rc} — click to open Claude" \
    "$HOME/dotfiles/bin/open-iterm-with cd ~/AKR\\; and claude \\(cat $prompt_file \\| string collect\\)"
telegram CLAUDE_CODE_BOT_TOKEN "❌ <b>Media sync failed</b> (exit $rc)
$(echo "${failed:-see log}" | html_escape)

Send me this to look into it:
<code>Read $prompt_file and do what it says.</code>"
exit 1
