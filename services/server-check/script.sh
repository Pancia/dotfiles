#!/usr/bin/env bash
# Daily check of the Vultr server. Silent when healthy; at most one notification.
# Clicking the notification opens show.sh in iTerm: the last results and what to do.
#
# A once-a-day check is deliberate: the server once sat dead for weeks unnoticed,
# and a day's delay is fine. Checking more often only adds noise.
#
# SERVER_CHECK_HOST and SERVER_CHECK_URL override the targets for testing.
# SERVER_CHECK_DRY=1 prints the alert instead of sending it.
# SERVER_CHECK_STATE, when set (even empty), replaces the server's SSH answer and
# skips the internet check, so tests need no network. Empty means unreachable.
# SERVER_CHECK_RETRY_DELAY sets the wait before the one retry (default 120 s).
# Tests: cmds test server-check

host="${SERVER_CHECK_HOST:-musicread@anthonydambrosio.me}"
url="${SERVER_CHECK_URL:-https://hs.anthonydambrosio.me/health}"
notifier=/opt/homebrew/bin/terminal-notifier

run_checks() {
    problems=()

    # curl verifies the certificate, so this also catches a failed renewal.
    if ! /usr/bin/curl -fsS -m 20 "$url" 2>/dev/null | /usr/bin/grep -q pass; then
        problems+=("Headscale or its certificate")
    fi

    local state
    if [ -n "${SERVER_CHECK_STATE+x}" ]; then
        state=$SERVER_CHECK_STATE
    else
        # This key has no passphrase, so the check works before anyone has logged in.
        # The server limits it to running /usr/local/bin/server-health, whatever is asked.
        # The time limit covers a server that accepts the connection and then stalls.
        state=$(/opt/homebrew/bin/timeout 90 /usr/bin/ssh -i "$HOME/.ssh/server_check" \
            -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=20 \
            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$host" </dev/null 2>/dev/null)
    fi

    # The words reachable, musicdisk, navidrome and unlocked are a contract with
    # /usr/local/bin/server-health on the server, which is not in this repo. Change
    # both sides together. -w, so that "unreachable" does not count as "reachable".
    if ! grep -qw reachable <<<"$state"; then
        problems+=("SSH: server unreachable")
        return
    fi
    if ! grep -qw musicdisk <<<"$state"; then
        problems+=("music disk not mounted")
    elif ! grep -qw navidrome <<<"$state"; then
        problems+=("Navidrome is not answering")
    fi
    # Locked is the safe, normal state: nothing automatic needs /mnt any more (the AKR
    # backup goes encrypted to the root disk since 2026-11-12). Unlocked means private
    # files are readable on the server, so it is unlocked that gets the warning --
    # usually a reminder that remote-sync finished and the disk was left open.
    if grep -qw unlocked <<<"$state"; then
        problems+=("encrypted disk is unlocked: lock it with unmnt when done")
    fi
}

# Without internet here, every check would fail and blame the server.
# A faked state needs no network, so the test skips this.
if [ -z "${SERVER_CHECK_STATE+x}" ] && ! /usr/bin/nc -z -G 10 1.1.1.1 443 2>/dev/null; then
    echo "$(date): no internet on this Mac; skipped"
    exit 0
fi

run_checks
if [ "${#problems[@]}" -gt 0 ]; then
    # One retry, so a passing network problem stays silent.
    /bin/sleep "${SERVER_CHECK_RETRY_DELAY:-120}"
    run_checks
fi

if [ "${#problems[@]}" -eq 0 ]; then
    echo "$(date): ok"
    exit 0
fi

message=$(IFS=';'; echo "${problems[*]}" | /usr/bin/sed 's/;/; /g')
echo "$(date): PROBLEM: $message"
if [ -n "${SERVER_CHECK_DRY:-}" ]; then
    echo "would notify: $message"
else
    # A click opens an iTerm window that only shows the result and what to do.
    show="$(cd "$(dirname "$0")" && pwd)/show.sh"
    "$notifier" -title "Vultr server" -message "$message" \
        -execute "/usr/bin/osascript -e 'tell application \"iTerm\" to create window with default profile command \"/bin/bash $show\"'"
fi
