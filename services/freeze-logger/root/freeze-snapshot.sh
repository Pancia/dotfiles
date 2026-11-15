#!/bin/bash
# freeze-snapshot — runs as root (LaunchDaemon). When listing processes hangs,
# flush the disks and play a warning sound, so you know the machine has hit the
# known freeze and that data is on disk before you hold the power button.
#
# The freeze: one process deadlocks on itself in the middle of exec, and every
# caller that touches its pid (ps, iTerm2, runningboardd, then WindowServer)
# waits for ever. The panic report from the power-button reset already holds
# the cause, to the millisecond. See .cc/reports/REPORT-mac-freezes-2026-11.md
# and REVIEW-freeze-options.md.
#
# It no longer saves a tailspin trace: that cost 256 MB of wired RAM, held only
# 4-8 s of history, and saving would likely hang on the stuck pid too.
#
# Installed copy: /usr/local/sbin/freeze-snapshot (root-owned, so a user-level
# process cannot change what root runs). Edit this file, then re-run install.sh.
# Output: /Library/Logs/freeze-snapshot/watch.log
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

OUT=/Library/Logs/freeze-snapshot
INTERVAL=5   # seconds between checks
WAIT=5       # seconds a listing may take before it counts as hung
SOUND=/System/Library/Sounds/Sosumi.aiff
ALERTS=3     # times the sound plays per hang

# root:admin 750 — your admin account can read the log, other accounts cannot.
mkdir -p "$OUT"
chown root:admin "$OUT"
chmod 750 "$OUT"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S %Z') $*" >>"$OUT/watch.log"; }

# True while pid $1 is a running job of this shell. Unlike `kill -0`, this
# cannot be fooled by another process reusing the pid (root may signal any pid).
running() { jobs -rp | grep -qx "$1"; }

# Wait up to $2 seconds for job $1. Return 0 if it ended.
ended_within() {
    local i
    for ((i = 0; i < $2; i++)); do
        running "$1" || return 0
        sleep 1
    done
    return 1
}

on_hang() {
    log "process listing hung for ${WAIT}s: flushing disks and sounding the alarm"
    # Both in the background with a limit: if either hangs too, the loop goes on.
    sync &
    local s=$! i
    ended_within "$s" 30 && log "sync done" || log "sync still running after 30s"
    for ((i = 0; i < ALERTS; i++)); do
        afplay "$SOUND" >/dev/null 2>&1 &
        ended_within $! 10 || log "afplay still running after 10s"
        sleep 2
    done
}

log "watching: checks every ${INTERVAL}s"

stuck=""   # pid of a listing that has not returned
while true; do
    if [ -n "$stuck" ]; then
        # Start no new listing while one is stuck: it would only pile up.
        if ! running "$stuck"; then
            wait "$stuck" 2>/dev/null
            log "process listing returned again"
            stuck=""
        fi
    else
        ps -Ao pid= >/dev/null 2>&1 &
        p=$!
        if ended_within "$p" "$WAIT"; then
            wait "$p"
        else
            stuck=$p
            on_hang
        fi
    fi
    sleep "$INTERVAL"
done
