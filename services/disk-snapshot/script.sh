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
TMPDU="${OUT}.tmpdu"
trap 'rm -f "$TMP" "$ERR" "$DENIED" "$TMPDU"' EXIT
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

# The per-user temp and cache folders. Agents and test runs fill them fast,
# and the "/" scan shows them only inside the one "/private" row.
# - getconf, never $TMPDIR: launchd may leave TMPDIR unset, and set -u aborts.
# - The section header must be the bare path, with no trailing slash (getconf
#   prints one). disk-cleanup takes a section's root from its header and drops
#   that root row; with any other header the root row stays first and the
#   descendant filter then hides every child.
# - Keep getconf's /var spelling. A /private/var spelling would make the
#   report's deepest-only filter drop "/private" from the could-not-read list.
user_tmp="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
user_tmp="${user_tmp%/}"
user_cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
user_cache="${user_cache%/}"

# Cache-folder names are bundle ids and stay the same, so depth 1 compares
# well across snapshots.
if [ -n "$user_cache" ] && [ -d "$user_cache" ]; then
    scan "$user_cache" local_du -d 1 -k "$user_cache" >> "$TMP"
fi

# Temp-folder names mostly end in a random suffix, so the same kind of entry
# never matches from one snapshot to the next, and each one is too small to
# list. Group them by name instead (tmp.* for mktemp, tmp???????? for Python's
# tempfile, prefix-* for "prefix-<digits or random>"). Rows:
#   - each group of 2 or more entries;
#   - each single entry of 100 MB or more (a big live cache must not hide in
#     the remainder);
#   - "(other small)": the rest, so the section always adds up to the total.
# One du run feeds both the rows and the denied list. du exits 1 when it meets
# a folder it cannot open, so the || true is required: under set -e and
# pipefail an unguarded failure ends the script, and the trap then deletes the
# partial file, so no snapshot is written at all.
if [ -n "$user_tmp" ] && [ -d "$user_tmp" ]; then
    log "Scanning $user_tmp (by name) ..."
    { local_du -d 1 -k "$user_tmp" 2>"$ERR" || true; } > "$TMPDU"
    {
        echo "=== $user_tmp (by name) ==="
        awk -F'\t' -v root="$user_tmp" -v big=102400 '
            function randomish(tok,   up, lo, t) {
                if (tok ~ /[0-9]/) return 1
                t = tok; up = gsub(/[A-Z]/, "", t)
                t = tok; lo = gsub(/[a-z]/, "", t)
                return length(tok) >= 8 && up >= 3 && lo >= 2
            }
            function group_key(name,   stem, sep, last, i, found) {
                # Python tempfile: "tmp" plus 8 characters, no separator rule
                # first, because those 8 can include "_".
                if (name ~ /^tmp[a-z0-9_]{8}$/) return "tmp????????"
                stem = name; found = 0
                while (match(stem, /[-._][^-._]+$/)) {
                    last = substr(stem, RSTART + 1)
                    if (!randomish(last)) break
                    sep = substr(stem, RSTART, 1)
                    stem = substr(stem, 1, RSTART - 1)
                    found = 1
                }
                if (!found || stem == "") return name
                return stem sep "*"
            }
            $2 == root || $2 == "" { next }
            {
                name = substr($2, length(root) + 2)
                k = group_key(name)
                n[k]++; kb[k] += $1
            }
            END {
                for (k in n) {
                    if (n[k] >= 2 || kb[k] >= big) printf "%d\t%s/%s\n", kb[k], root, k
                    else rest += kb[k]
                }
                if (rest > 0) printf "%d\t%s/(other small)\n", rest, root
            }' "$TMPDU" | sort -t$'\t' -k2
        echo ""
    } >> "$TMP"
    denied_entries "$user_tmp" 1 < "$ERR" >> "$DENIED" || true
    log "Done scanning $user_tmp"
fi

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
