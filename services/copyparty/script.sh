#!/opt/homebrew/bin/fish

set COPYPARTY_DIR "$HOME/ProtonDrive/copyparty"

echo (date)": Starting copyparty service..."
cd "$COPYPARTY_DIR"
uv run --with setproctitle proc-label copyparty /opt/homebrew/bin/copyparty -c copyparty.conf
