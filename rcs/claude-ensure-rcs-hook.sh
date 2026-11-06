#!/bin/bash
# Claude Code hook to protect RCS hardlinks managed by _ENSURE_RCS.
# Usage: ensure-rcs.sh pre|post
# Pre:  blocks edits to MANIFEST destination files and managed LaunchAgent
#       plists, redirects to source. Paths are compared after resolving
#       symlinks and letter case, so another spelling of a guarded file is
#       still caught.
# Post: re-establishes hardlinks after editing a MANIFEST source file or a
#       services/ plist.

MODE="$1"
MANIFEST="$HOME/dotfiles/rcs/MANIFEST"

INPUT=$(cat)

# Extract tool_input.file_path from the JSON without jq or a fork. The value
# may hold escaped quotes or backslashes (`we\"ird\\dir`), so match a JSON
# string properly and unescape it. Any other escape (\uXXXX, \n...) is rare
# enough to hand to plutil.
json_file_path() {
    local re='"file_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"' p
    local bs='\' q='"' sl='/' sep=$'\001'
    [[ "$INPUT" =~ $re ]] || return
    p="${BASH_REMATCH[1]}"
    case "$p" in *"$bs"*)
        p="${p//"$bs$bs"/$sep}"; p="${p//"$bs$q"/$q}"; p="${p//"$bs$sl"/$sl}"
        case "$p" in *"$bs"*)
            # plutil prints its errors on stdout, so keep its output only on success.
            p=$(printf '%s' "$INPUT" | plutil -extract tool_input.file_path raw -o - - 2>/dev/null) &&
                printf '%s' "$p"
            return ;;
        esac
        p="${p//"$sep"/$bs}" ;;
    esac
    printf '%s' "$p"
}
FILE_PATH=$(json_file_path)

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$MANIFEST" ] && exit 0

# The path as the filesystem knows it: symlinks resolved and letter case
# corrected (APFS is case-insensitive, so ~/.Config/... names the same file).
# A file that does not exist yet keeps its own name under a resolved parent.
canon_path() {
    local p="$1" d
    [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
    if [ -e "$p" ] && realpath "$p" 2>/dev/null; then return; fi
    if d=$(realpath "${p%/*}" 2>/dev/null); then echo "$d/${p##*/}"; return; fi
    echo "$p"
}

CANON=$(canon_path "$FILE_PATH")
# CANON is resolved, so everything it is compared with must be too: a
# symlinked $HOME or ~/dotfiles would otherwise turn the plist guard off and
# block every MANIFEST source. One realpath call for both.
{ read -r R_HOME; read -r R_DOT; } < <(realpath "$HOME" "$HOME/dotfiles" 2>/dev/null)
R_HOME="${R_HOME:-$HOME}"; R_DOT="${R_DOT:-$HOME/dotfiles}"
# Name comparisons below ignore case, as the filesystem does.
shopt -s nocasematch

if [ "$MODE" = "post" ]; then
    # Quick prefix check — skip rcs-sync for unrelated files. Service plists
    # are hardlinked into ~/Library/LaunchAgents too, and the Edit tool splits
    # that link, so rcs-sync relinks them as well.
    case "$CANON" in
        "$R_DOT/rcs/"*|"$R_DOT/services/"*/org.pancia.*.plist) ;;
        *) exit 0 ;;
    esac
    "$HOME/dotfiles/bin/rcs-sync" --hook </dev/null
    exit 0
fi

if [ "$MODE" = "pre" ]; then
    # Block edits to LaunchAgent plists — edit the source in services/ instead
    if [[ "$CANON" == "$R_HOME/Library/LaunchAgents/org.pancia."*".plist" ]]; then
        full="${CANON##*/}"; full="${full%.plist}"
        source_path="$R_DOT/services/${full#org.pancia.}/$full.plist"
        # The Edit tool refuses to write through a symlink; name the real file.
        [ -L "$source_path" ] && source_path=$(realpath "$source_path" 2>/dev/null)
        if [ -f "$source_path" ]; then
            echo "Blocked: $FILE_PATH is a managed LaunchAgent. Edit the source file at $source_path instead." >&2
        else
            echo "Blocked: $FILE_PATH is a managed LaunchAgent. Edit the source in ~/dotfiles/services/ instead." >&2
        fi
        exit 2
    fi

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        src="${line%% -> *}"
        dst="${line##* -> }"
        # Trim whitespace
        src="${src#"${src%%[![:space:]]*}"}"
        src="${src%"${src##*[![:space:]]}"}"
        dst="${dst#"${dst%%[![:space:]]*}"}"
        dst="${dst%"${dst##*[![:space:]]}"}"
        # Expand $HOME (resolved, to compare with CANON)
        dst="${dst//\$HOME/$R_HOME}"
        if [[ "$src" == /* ]] || [[ "$src" == '$HOME'* ]]; then
            src="${src//\$HOME/$R_HOME}"
        else
            src="$R_DOT/rcs/$src"
        fi

        if [[ "$CANON" == "$dst" ]]; then
            echo "Blocked: $FILE_PATH is hardlinked from $src via rcs/MANIFEST. Edit the source file instead." >&2
            exit 2
        fi
        # An inode match catches spellings the name check misses (a symlinked
        # parent dir) and stray extra hardlinks of a source. A linked source
        # shares the destination's inode, so the source itself is exempt.
        if [ "$CANON" -ef "$dst" ] && [[ "$CANON" != "$src" ]]; then
            echo "Blocked: $FILE_PATH is the same file (hardlink) as $src, an rcs/MANIFEST source. Edit the source file instead." >&2
            exit 2
        fi
    done < "$MANIFEST"
fi

exit 0
