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
ERR="${OUT}.err"
DENIED="${OUT}.denied"
trap 'rm -f "$TMP" "$ERR" "$DENIED"' EXIT
: > "$DENIED"

log() { echo "$*" >&2; }

log "Starting disk snapshot -> $OUT"

# Run without Full Disk Access (the usual case under launchd), du cannot open
# protected folders. It prints an error and counts them as almost nothing, so
# a full folder looks empty. Each listed folder that hid an error is recorded
# and written to the "could not read" section at the end.
#   denied_entries ROOT DEPTH < du-stderr
denied_entries() {
    local root="${1%/}" depth="$2" p rel
    sed -nE 's/^du: (.*): (Operation not permitted|Permission denied)$/\1/p' |
    while IFS= read -r p; do
        rel="${p#"$root"/}"
        if [ "$p" = "${root:-/}" ] || [ "$rel" = "$p" ] || [ "$depth" -eq 0 ]; then
            printf '%s\n' "${root:-/}"
        else
            printf '%s/%s\n' "$root" "$(printf '%s' "$rel" | cut -d/ -f1-"$depth")"
        fi
    done
}

# scan HEADER COMMAND... — the last argument is the folder, and -d N its depth.
scan() {
    local header="$1"
    shift
    local root="${!#}" depth=0 prev="" arg
    for arg in "$@"; do
        [ "$prev" = "-d" ] && depth="$arg"
        prev="$arg"
    done
    log "Scanning $header ..."
    echo "=== $header ==="
    "$@" 2>"$ERR" | sort -t$'\t' -k2 || true
    echo ""
    denied_entries "$root" "$depth" < "$ERR" >> "$DENIED" || true
    log "Done scanning $header"
}

# A network mount looks like a folder, so du would walk it (slowly) and count
# the remote files as local disk. Two guards, because the music mount service
# also starts at login and can come up while this scan is running:
# - du -x stays on the starting volume, so it skips a mount whenever it
#   appears. It cannot be used for "/", where it stops at every firmlink.
# - -I skips each mounted folder by name at any depth. That is the only form
#   that works for "/". The list is read again before each du call.
du_skip=()
refresh_mount_skips() {
    du_skip=()
    local mount_point
    while IFS= read -r mount_point; do
        [ -n "$mount_point" ] && du_skip+=(-I "$(basename "$mount_point")")
    done < <(/sbin/mount | sed -nE 's/^.* on (.*) \((nfs|smbfs|afpfs|webdav|macfuse|osxfuse)[, ].*$/\1/p')
}

# The expansion guards an empty array: this can run under bash 3.2, where a
# bare "${du_skip[@]}" is an unbound-variable error with set -u.
local_du() { refresh_mount_skips; du -x ${du_skip[@]+"${du_skip[@]}"} "$@"; }
root_du() { refresh_mount_skips; du ${du_skip[@]+"${du_skip[@]}"} "$@"; }

# Recorded at scan time so the report can compare it with what this scan could
# read. A live df would drift from the snapshot. Readers ignore lines before
# the first section header.
df_target=/
[ -d /System/Volumes/Data ] && df_target=/System/Volumes/Data
printf '# data_volume_used_kb %s\n\n' "$(/bin/df -k "$df_target" | awk 'END {print $3}')" > "$TMP"

scan "/" root_du -d 1 -k / >> "$TMP"
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

# One path per line, no size. Readers that expect "size<TAB>path" skip these.
{
    echo "=== could not read ==="
    sort -u "$DENIED"
    echo ""
} >> "$TMP"

mv "$TMP" "$OUT"

lines=$(wc -l < "$OUT")
size=$(du -h "$OUT" | cut -f1)
log "Snapshot saved to $OUT ($lines lines, $size)"
