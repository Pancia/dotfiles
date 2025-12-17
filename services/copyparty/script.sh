#!/opt/homebrew/bin/fish

set COPYPARTY_DIR "$HOME/ProtonDrive/copyparty"

echo (date)": Starting copyparty service..."
cd "$COPYPARTY_DIR"
/opt/homebrew/bin/copyparty -c copyparty.conf
