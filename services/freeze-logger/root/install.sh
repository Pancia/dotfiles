#!/bin/bash
# Install or remove the root freeze-snapshot daemon.
#
#   sudo services/freeze-logger/root/install.sh            # install or update
#   sudo services/freeze-logger/root/install.sh --uninstall
#
# Install copies the script to /usr/local/sbin as root-owned, so nothing your
# user account runs can change what root runs. It shows what will run as root
# and asks first, because this checkout is shared with other sessions.
# It also puts tailspin back to the macOS default (all settings reset, off),
# which frees the 256 MB of wired RAM an earlier version gave it.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

LABEL=org.pancia.freeze-snapshot
BIN=/usr/local/sbin/freeze-snapshot
PLIST=/Library/LaunchDaemons/$LABEL.plist
OUT=/Library/Logs/freeze-snapshot
here=$(cd "$(dirname "$0")" && pwd)

stop_daemon() {
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    # bootout returns before the job is gone; bootstrap fails until it is.
    local i
    for ((i = 0; i < 20; i++)); do
        launchctl print "system/$LABEL" >/dev/null 2>&1 || return 0
        sleep 0.5
    done
    echo "warning: $LABEL still loaded after 10s" >&2
}

if [ "${1:-}" = "--uninstall" ]; then
    stop_daemon
    rm -f "$PLIST" "$BIN"
    echo "removed $LABEL (logs kept in $OUT)"
    exit 0
fi

src="$here/freeze-snapshot.sh"
echo "will run as root: $src"
echo "sha256: $(shasum -a 256 "$src" | cut -d' ' -f1)"
if [ -f "$BIN" ]; then
    if cmp -s "$BIN" "$src"; then
        echo "(same as the installed copy)"
    else
        echo "--- changes from the installed copy:"
        diff -u "$BIN" "$src" || true
    fi
else
    echo "--- new install; full script:"
    cat "$src"
fi
if [ -t 0 ]; then
    read -r -p "Install this as root? [y/N] " ok
    [ "$ok" = y ] || [ "$ok" = Y ] || { echo "not installed"; exit 1; }
fi

stop_daemon
install -d -o root -g wheel -m 755 /usr/local/sbin
install -d -o root -g admin -m 750 "$OUT"
install -o root -g wheel -m 755 "$src" "$BIN"
install -o root -g wheel -m 644 "$here/$LABEL.plist.in" "$PLIST"
plutil -lint "$PLIST" >/dev/null

# The daemon no longer saves traces. tailspin was off before it was installed.
tailspin reset
if tailspin info 2>&1 | grep -m1 -E '^tailspin has been (enabled|disabled)' | grep -q enabled; then
    tailspin disable
fi
rm -f "$OUT"/test-install.tailspin

launchctl bootstrap system "$PLIST"
sleep 2
launchctl print "system/$LABEL" | grep -E '^\s*(state|pid) =' || true
tail -3 "$OUT/watch.log" || true

echo "playing the warning sound once, as root ..."
afplay /System/Library/Sounds/Sosumi.aiff || echo "afplay FAILED" >&2
