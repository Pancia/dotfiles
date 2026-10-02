#!/usr/bin/env bash
set -uo pipefail

# The out-of-process kiosk watchdog (m-067). The binary ships inside the installed app, so
# every `just install` replaces it together with the app whose kiosk files it reads.
guard="$HOME/Applications/Sanctuary.app/Contents/MacOS/sanctuary-guard"

if [ ! -x "$guard" ]; then
    echo "sanctuary-guard: $guard is missing; run 'just install' in the Sanctuary checkout"
    # Back off, or KeepAlive respawns this every ThrottleInterval (10 s) and floods the log.
    sleep 60
    exit 1
fi

exec "$guard" run
