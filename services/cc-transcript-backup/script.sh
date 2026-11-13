#!/usr/bin/env bash
# Nightly copy of every Claude Code transcript to ProtonDrive, so chats survive
# the loss of this Mac's disk and Claude Code's own one-year cleanup
# (cleanupPeriodDays in rcs/claude-settings.json).
#
# - Adds and updates only. It never deletes: a transcript that Claude Code
#   prunes locally stays here, which is the point.
# - A file is copied again only when the original is newer than the copy.
# - Each copy is zstd-compressed (about 1/5 of the size), written to a temp
#   name and then renamed, so a killed run never leaves a broken copy.
#
# CC_BACKUP_SRC and CC_BACKUP_DST override the folders for testing.
# Restore one: zstd -d <copy>.jsonl.zst -o ~/.claude/projects/<folder>/<id>.jsonl
# (`ccs resume` does this itself when the local transcript is gone.)

set -u
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

src="${CC_BACKUP_SRC:-$HOME/.claude}"
dst="${CC_BACKUP_DST:-$HOME/Cloud/claude-transcripts}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-sessions"

# ~/Cloud is a symlink into ProtonDrive's File Provider folder. If ProtonDrive
# is not set up, do not create a plain folder in its place.
parent=$(dirname "$dst")
if [ ! -d "$parent" ]; then
    echo "backup folder's parent $parent is missing; is ProtonDrive running?"
    exit 1
fi

copy_zst() {  # copy_zst <source> <dest.zst>
    local in=$1 out=$2 m
    # Whole seconds, and the copy takes the original's mtime: `-nt` compares
    # below a second, and zstd keeps only whole seconds, so every file looked
    # newer than its copy and was copied again each night.
    m=$(stat -f %m "$in") || return 2
    if [ -f "$out" ] && [ "$m" -le "$(stat -f %m "$out")" ]; then
        return 1
    fi
    mkdir -p "$(dirname "$out")" || return 2
    if zstd -qf "$in" -o "$out.tmp.$$" 2>/dev/null; then
        # The mtime read BEFORE compressing. A live session can append while
        # zstd runs; stamping the copy with the later mtime would mark lines it
        # does not hold as copied, and if that was the last write, for good.
        touch -t "$(date -r "$m" +%Y%m%d%H%M.%S)" "$out.tmp.$$"
        mv "$out.tmp.$$" "$out" && return 0
    fi
    rm -f "$out.tmp.$$"
    return 2
}

copied=0 skipped=0 failed=0
while IFS= read -r -d '' f; do
    rel=${f#"$src/projects/"}
    copy_zst "$f" "$dst/projects/$rel.zst"
    case $? in
        0) copied=$((copied + 1)) ;;
        1) skipped=$((skipped + 1)) ;;
        *) failed=$((failed + 1)); echo "failed: $f" ;;
    esac
done < <(find "$src/projects" -type f -name '*.jsonl' -print0 2>/dev/null)

# Prompt history; the ccs records that say which pane ran which session and
# its title; and the hook's local transcript copies, which for a session Claude
# Code pruned before this job existed are the only copy. rsync without
# --delete, like everything here. Half-written `*.tmp.<pid>` files are left out.
[ -f "$src/history.jsonl" ] && copy_zst "$src/history.jsonl" "$dst/history.jsonl.zst"
if [ -d "$state" ]; then
    mkdir -p "$dst/ccs-state"
    for d in open archive transcripts; do
        [ -d "$state/$d" ] || continue
        rsync -a --exclude '*.tmp.*' "$state/$d" "$dst/ccs-state/" \
            || { failed=$((failed + 1)); echo "failed: rsync $d"; }
    done
fi

echo "copied $copied, unchanged $skipped, failed $failed"
[ "$failed" -eq 0 ]
