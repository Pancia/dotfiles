#!/usr/bin/env bash
set -uo pipefail

# The watchdog's own watchdog — the same mechanism claude-p applies to claude,
# applied here. If `lsof` or `sample` hangs on a pathological process, this run
# dies at 55 s and launchd starts a clean one at the next minute. 55 rather than
# 60 so a run can never overlap the next StartInterval tick.
#
# Absolute path: launchd gives us a minimal PATH, and this must be GNU timeout
# (it signals the whole process group), not a shell builtin.
exec /opt/homebrew/bin/timeout -k 5 55 "$HOME/dotfiles/bin/claude-watchdog"
