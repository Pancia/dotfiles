#!/bin/bash
# Claude Code hook to protect RCS hardlinks managed by _ENSURE_RCS.
# Usage: ensure-rcs.sh pre|post
# Pre:  blocks edits to MANIFEST destination files, redirects to source.
# Post: re-establishes hardlinks after editing a MANIFEST source file.

MODE="$1"
MANIFEST="$HOME/dotfiles/rcs/MANIFEST"

# Extract file_path from stdin JSON without jq
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$MANIFEST" ] && exit 0

if [ "$MODE" = "post" ]; then
    # Quick prefix check — skip MANIFEST parsing for unrelated files
    [[ "$FILE_PATH" != "$HOME/dotfiles/rcs/"* ]] && exit 0
    fish -c '_ENSURE_RCS' 2>/dev/null
    exit 0
fi

if [ "$MODE" = "pre" ]; then
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
        # Expand $HOME
        dst="${dst//\$HOME/$HOME}"

        if [ "$FILE_PATH" = "$dst" ]; then
            # Resolve source path
            if [[ "$src" == /* ]] || [[ "$src" == '$HOME'* ]]; then
                src="${src//\$HOME/$HOME}"
            else
                src="$HOME/dotfiles/rcs/$src"
            fi
            echo "Blocked: $FILE_PATH is hardlinked from $src via rcs/MANIFEST. Edit the source file instead." >&2
            exit 2
        fi
    done < "$MANIFEST"
fi

exit 0
