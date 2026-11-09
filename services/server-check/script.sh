#!/usr/bin/env bash
# Daily check of the Vultr server. Silent when healthy; at most one notification.
#
# A once-a-day check is deliberate: the server once sat dead for weeks unnoticed,
# and a day's delay is fine. Checking more often only adds noise.
#
# SERVER_CHECK_HOST and SERVER_CHECK_URL override the targets for testing.
# SERVER_CHECK_DRY=1 prints the alert instead of sending it.

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
    # This key has no passphrase, so the check works before anyone has logged in.
    # The server limits it to running /usr/local/bin/server-health, whatever is asked.
    # The time limit covers a server that accepts the connection and then stalls.
    state=$(/opt/homebrew/bin/timeout 90 /usr/bin/ssh -i "$HOME/.ssh/server_check" \
        -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=20 \
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$host" </dev/null 2>/dev/null)

    if ! grep -q reachable <<<"$state"; then
        problems+=("SSH: server unreachable")
        return
    fi
    if ! grep -q unlocked <<<"$state"; then
        problems+=("disk locked: run bin/mnt on the server")
    elif ! grep -q navidrome <<<"$state"; then
        problems+=("Navidrome is not answering")
    fi
}

# Without internet here, every check would fail and blame the server.
if ! /usr/bin/nc -z -G 10 1.1.1.1 443 2>/dev/null; then
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
    "$notifier" -title "Vultr server" -message "$message"
fi
