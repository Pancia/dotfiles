#!/bin/bash
# Claude Code hook to snapshot jj repos before edits and on session stop.
# Usage: jj-snapshot.sh [pre|stop]
# pre:  extracts file_path from stdin, snapshots its jj repo
# stop: extracts cwd from stdin, snapshots its jj repo

MODE="${1:-pre}"
INPUT=$(cat)

if [ "$MODE" = "stop" ]; then
    TARGET=$(echo "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//;s/"$//')
else
    TARGET=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

[ -z "$TARGET" ] && exit 0

# If it's a file, get its directory
if [ -f "$TARGET" ]; then
    TARGET=$(dirname "$TARGET")
fi

# Walk up to find a .jj directory
while [ "$TARGET" != "/" ]; do
    if [ -d "$TARGET/.jj" ]; then
        jj util snapshot -R "$TARGET" 2>/dev/null
        exit 0
    fi
    TARGET=$(dirname "$TARGET")
done

exit 0
