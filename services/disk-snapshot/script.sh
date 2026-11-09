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

# A network mount looks like a folder, so du would walk it (slowly) and count
# the remote files as local disk. -I matches by name at any depth, which is the
# only form that works for the "/" scan: du -x would stop at every firmlink.
du_skip=()
while IFS= read -r mount_point; do
    [ -n "$mount_point" ] && du_skip+=(-I "$(basename "$mount_point")")
done < <(/sbin/mount | sed -nE 's/^.* on (.*) \((nfs|smbfs|afpfs|webdav|macfuse|osxfuse)[, ].*$/\1/p')

# The expansion guards an empty array: this can run under bash 3.2, where a
# bare "${du_skip[@]}" is an unbound-variable error with set -u.
local_du() { du ${du_skip[@]+"${du_skip[@]}"} "$@"; }

# Recorded at scan time so the report can compare it with what this scan could
# read. A live df would drift from the snapshot. Readers ignore lines before
# the first section header.
df_target=/
[ -d /System/Volumes/Data ] && df_target=/System/Volumes/Data
printf '# data_volume_used_kb %s\n\n' "$(/bin/df -k "$df_target" | awk 'END {print $3}')" > "$TMP"

scan "/" local_du -d 1 -k / >> "$TMP"
scan "~" local_du -d 1 -k "$HOME" >> "$TMP"
scan "~/Library" local_du -d 1 -k "$HOME/Library" >> "$TMP"
scan "~/Library/Caches" local_du -d 1 -k "$HOME/Library/Caches" >> "$TMP"
scan "~/Library/CloudStorage" local_du -d 1 -k "$HOME/Library/CloudStorage" >> "$TMP"
scan "~/.cache" local_du -d 1 -k "$HOME/.cache" >> "$TMP"
scan "~/.local" local_du -d 2 -k "$HOME/.local" >> "$TMP"
scan "~/AndroidStudioProjects" local_du -d 1 -k "$HOME/AndroidStudioProjects" >> "$TMP"
[ -d /Volumes/vansuny128 ] && scan "/Volumes/vansuny128" local_du -d 1 -k /Volumes/vansuny128 >> "$TMP"

# Each of these held multiple GB that the sections above could not attribute.
# The protected ones come back empty or too small when launchd runs this
# without Full Disk Access. The report's "unmeasured" line covers that gap.
scan "/Applications" local_du -d 1 -k /Applications >> "$TMP"
[ -d /opt/homebrew ] && scan "/opt/homebrew" local_du -d 1 -k /opt/homebrew >> "$TMP"
[ -d /opt/homebrew/share ] && scan "/opt/homebrew/share" local_du -d 1 -k /opt/homebrew/share >> "$TMP"
scan "~/Library/Application Support" local_du -d 1 -k "$HOME/Library/Application Support" >> "$TMP"
scan "~/Library/Containers" local_du -d 1 -k "$HOME/Library/Containers" >> "$TMP"
scan "~/Library/Group Containers" local_du -d 1 -k "$HOME/Library/Group Containers" >> "$TMP"
scan "~/Documents" local_du -d 1 -k "$HOME/Documents" >> "$TMP"
scan "~/Downloads" local_du -d 1 -k "$HOME/Downloads" >> "$TMP"

# The git-repos section below cannot see a project with no .git.
scan "~/projects" local_du -d 1 -k "$HOME/projects" >> "$TMP"

log "Scanning project build folders ..."
{
    echo "=== project build folders ==="
    find "$HOME/projects" "$HOME/AndroidStudioProjects" -type d \
        \( -name node_modules -o -name .venv -o -name venv -o -name build \
           -o -name target -o -name .gradle -o -name .dart_tool -o -name DerivedData \) \
        -prune -print 2>/dev/null | while IFS= read -r d; do
        local_du -sk "$d" 2>/dev/null || true
    done | sort -t$'\t' -k2
    echo ""
} >> "$TMP"

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
