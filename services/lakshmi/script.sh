#!/opt/homebrew/bin/fish

echo (date)": Starting lakshmi content server on port 8420..."
cd ~/projects/lakshmi/public
proc-label lakshmi python3 -m http.server 8420
