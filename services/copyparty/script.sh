#!/usr/bin/env zsh

COPYPARTY_DIR="${HOME}/ProtonDrive/copyparty"
WGET_SERVER_DIR="${HOME}/Library/CloudStorage/ProtonDrive-adambrosio@pm.me-folder/copyparty"

# Cleanup function to stop wget_server when script exits
cleanup() {
    if [ ! -z "$WGET_PID" ]; then
        echo "$(date): Stopping wget_server (PID: $WGET_PID)..."
        kill $WGET_PID 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

# Start wget_server using venv Python directly (no activation needed)
echo "$(date): Starting wget_server..."
cd "$WGET_SERVER_DIR"
venv/bin/python wget_server.py &
WGET_PID=$!
echo "$(date): wget_server started (PID: $WGET_PID)"

# Start copyparty in foreground
echo "$(date): Starting copyparty service..."
cd "$COPYPARTY_DIR"
copyparty -c copyparty.conf

# cleanup() will be called automatically on exit
