#!/usr/bin/env bash
set -euo pipefail

DIR="$HOME/.local/share/disk-snapshots"
mkdir -p "$DIR"
TODAY="$DIR/$(date +%Y-%m-%d)"
OUT="${TODAY}_$(date +%H%M%S).txt"

# Scan into a .partial file and rename only once every section is written. A
# killed scan (power loss, Ctrl-C) used to leave a truncated .txt behind that
# readers could not tell from a complete one — the header for the section it
# died in was already on disk. The suffix keeps it out of the *.txt glob even
# if the trap never runs.
TMP="${OUT}.partial"
trap 'rm -f "$TMP"' EXIT

log() { echo "$*" >&2; }

log "Starting disk snapshot -> $OUT"

scan() {
    local header="$1"
    shift
    log "Scanning $header ..."
    echo "=== $header ==="
    "$@" 2>/dev/null | sort -t$'\t' -k2 || true
    echo ""
    log "Done scanning $header"
}

scan "/" du -d 1 -k / > "$TMP"
scan "~" du -d 1 -k "$HOME" >> "$TMP"
scan "~/Library" du -d 1 -k "$HOME/Library" >> "$TMP"
scan "~/Library/Caches" du -d 1 -k "$HOME/Library/Caches" >> "$TMP"
scan "~/Library/CloudStorage" du -d 1 -k "$HOME/Library/CloudStorage" >> "$TMP"
scan "~/.cache" du -d 1 -k "$HOME/.cache" >> "$TMP"
scan "~/.local" du -d 2 -k "$HOME/.local" >> "$TMP"
scan "~/AndroidStudioProjects" du -d 1 -k "$HOME/AndroidStudioProjects" >> "$TMP"
[ -d /Volumes/vansuny128 ] && scan "/Volumes/vansuny128" du -d 1 -k /Volumes/vansuny128 >> "$TMP"

log "Scanning ~/projects (git repos) ..."
{
    echo "=== ~/projects (git repos) ==="
    find "$HOME/projects" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r d; do
        du -sk "$(dirname "$d")" 2>/dev/null || true
    done | sort -t$'\t' -k2
    echo ""
} >> "$TMP"

mv "$TMP" "$OUT"

lines=$(wc -l < "$OUT")
size=$(du -h "$OUT" | cut -f1)
log "Snapshot saved to $OUT ($lines lines, $size)"
