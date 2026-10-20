#!/usr/bin/env bash
# Rotates every Inari-family log. Each runs even if another fails; the first
# failure's status is kept (service-wrapper pipes through ts, so check archive
# mtimes rather than the exit status — see tools/inari/CLAUDE.md).
set -uo pipefail

rc=0
~/dotfiles/bin/rotate-inari-log inari    || rc=$?
~/dotfiles/bin/rotate-inari-log inari-cc || { s=$?; [ "$rc" -eq 0 ] && rc=$s; }
exit "$rc"
