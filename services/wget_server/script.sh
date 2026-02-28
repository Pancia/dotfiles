#!/opt/homebrew/bin/fish

set WGET_SERVER_DIR "$HOME/Library/CloudStorage/ProtonDrive-adambrosio@pm.me-folder/copyparty"

echo (date)": Starting wget_server..."
cd "$WGET_SERVER_DIR"
/opt/homebrew/bin/uv run --with setproctitle proc-label wget-server python wget_server.py
