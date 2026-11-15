#!/usr/bin/env bash
# Records memory, swap, load and the largest processes every 30 seconds, so a
# machine freeze leaves a record of the minutes before it. A crash report is
# taken after the freeze, when the applications have already died.
#
# Output: ~/.local/share/freeze-logger/YYYY-MM-DD.log, kept for 14 days.
# `script.sh --once` writes one sample to stdout and exits.
set -u

DIR="$HOME/.local/share/freeze-logger"
INTERVAL=30
KEEP_DAYS=14

# True while pid $1 is a running job of this shell. Unlike `kill -0`, a reused
# pid cannot fool it.
running() { jobs -rp | /usr/bin/grep -qx "$1"; }

sample() {
    echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "load: $(/usr/sbin/sysctl -n vm.loadavg)"
    echo "memory: $(/usr/bin/memory_pressure -Q 2>/dev/null | /usr/bin/tail -1)"
    echo "swap: $(/usr/sbin/sysctl -n vm.swapusage)"
    /usr/bin/vm_stat | /usr/bin/grep -E 'Pages (free|active|wired down|occupied by compressor)|Swapouts' \
        | /usr/bin/sed -E 's/  +/ /g'
    # A machine freeze jams every process listing in the kernel, and a jammed
    # `ps` cannot be killed. So start no new one while the last is stuck, and
    # give each one PS_WAIT seconds. The root freeze-snapshot daemon saves the
    # kernel trace (root/install.sh).
    if [ -n "$PS_STUCK" ]; then
        if running "$PS_STUCK"; then
            echo "HUNG: process listing (pid $PS_STUCK) still stuck since $PS_STUCK_AT"
            return
        fi
        echo "RECOVERED: process listing returned"
        PS_STUCK=""
    fi
    /bin/ps -Ao rss=,%cpu=,comm= >"$PS_TMP" &
    local p=$! i
    for ((i = 0; i < PS_WAIT; i++)); do
        running "$p" || break
        /bin/sleep 1
    done
    if running "$p"; then
        PS_STUCK=$p
        PS_STUCK_AT=$(date '+%H:%M:%S') # when the hang was noticed
        echo "HUNG: process listing did not return in ${PS_WAIT}s"
        return
    fi
    wait "$p"
    echo "counts: claude=$(/usr/bin/grep -c 'claude' "$PS_TMP") go=$(/usr/bin/grep -cE '/go$|/compile$|/link$|\.test$' "$PS_TMP") alt=$(/usr/bin/grep -cE '[/ ]alt(-[0-9a-f]+)?$' "$PS_TMP") tmux=$(/usr/bin/grep -c 'tmux' "$PS_TMP") total=$(/usr/bin/wc -l <"$PS_TMP" | /usr/bin/tr -d ' ')"
    echo "top memory (MB, cpu%, name):"
    /usr/bin/sort -rn "$PS_TMP" | /usr/bin/head -8 \
        | /usr/bin/awk '{ n=$3; sub(".*/","",n); printf "  %6d %6s %s\n", $1/1024, $2, n }'
    echo "top cpu (cpu%, MB, name):"
    /usr/bin/sort -k2 -rn "$PS_TMP" | /usr/bin/head -5 \
        | /usr/bin/awk '{ n=$3; sub(".*/","",n); printf "  %6s %6d %s\n", $2, $1/1024, n }'
}

PS_WAIT=10
PS_STUCK=""
PS_STUCK_AT=""
PS_TMP="$(/usr/bin/mktemp -t freeze-logger)"
trap '/bin/rm -f "$PS_TMP"' EXIT

if [ "${1:-}" = "--once" ]; then
    sample
    exit 0
fi

trap '/bin/rm -f "$PS_TMP"; exit 0' TERM INT

/bin/mkdir -p "$DIR"
echo "freeze-logger started: samples every ${INTERVAL}s in $DIR"

while true; do
    sample >>"$DIR/$(date +%Y-%m-%d).log" 2>&1
    /usr/bin/find "$DIR" -name '*.log' -mtime +"$KEEP_DAYS" -delete 2>/dev/null
    sleep "$INTERVAL" &
    wait $!
done
