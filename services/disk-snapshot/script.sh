#!/usr/bin/env bash
set -euo pipefail

DIR="$HOME/.local/share/disk-snapshots"
mkdir -p "$DIR"
OUT="$DIR/$(date +%Y-%m-%d).txt"

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

scan "/" du -d 1 -k / > "$OUT"
scan "~" du -d 1 -k "$HOME" >> "$OUT"
scan "~/Library" du -d 1 -k "$HOME/Library" >> "$OUT"
scan "~/Library/Caches" du -d 1 -k "$HOME/Library/Caches" >> "$OUT"
scan "~/.cache" du -d 1 -k "$HOME/.cache" >> "$OUT"
scan "~/.local" du -d 2 -k "$HOME/.local" >> "$OUT"
scan "~/AndroidStudioProjects" du -d 1 -k "$HOME/AndroidStudioProjects" >> "$OUT"

log "Scanning ~/projects (git repos) ..."
{
    echo "=== ~/projects (git repos) ==="
    find "$HOME/projects" -maxdepth 3 -name .git -type d 2>/dev/null | while read -r d; do
        du -sk "$(dirname "$d")" 2>/dev/null || true
    done | sort -t$'\t' -k2
    echo ""
} >> "$OUT"

lines=$(wc -l < "$OUT")
size=$(du -h "$OUT" | cut -f1)
log "Snapshot saved to $OUT ($lines lines, $size)"
