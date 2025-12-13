#!/usr/bin/env python3

import subprocess
import sys
import json
import time
import glob
import os

print("[kitty.py/debug]: args:", sys.argv)
directory = sys.argv[1]
tabs = json.loads(sys.argv[2])
print("[kitty.py/debug]: dir & tabs", directory, tabs)

# Launch Kitty if not running
try:
    # Check if kitty is already running
    result = subprocess.run(
        ['pgrep', '-x', 'kitty'],
        capture_output=True
    )
    is_running = result.returncode == 0

    if not is_running:
        print("[kitty.py/debug]: Launching Kitty...")
        # Launch Kitty with --session=none to prevent default window
        subprocess.run(['open', '-a', 'kitty', '--args', '--session=none'])
        # Give it time to start up
        time.sleep(1.5)
    else:
        print("[kitty.py/debug]: Kitty already running")

    # Find the kitty socket
    sockets = glob.glob('/tmp/kitty-*')
    if not sockets:
        raise RuntimeError("No Kitty socket found in /tmp. Is Kitty running with remote control enabled?")
    socket_path = f"unix:{sockets[0]}"
    print(f"[kitty.py/debug]: Using socket: {socket_path}")

    # Track if we just launched Kitty (will need to close default window)
    close_default_window = not is_running

    # Create new OS window with first tab/command
    print(f"[kitty.py/debug]: Creating window with first tab: {tabs[0]}")
    subprocess.run([
        'kitty', '@', '--to', socket_path, 'launch',
        '--type=os-window',
        '--cwd', directory,
        '--title', 'VPC Workspace',
        'sh', '-c', f'cd {directory} && {tabs[0]}'
    ], check=True)

    # Wait a moment for the window to be created
    time.sleep(0.3)

    # Create additional tabs
    for i, tab_cmd in enumerate(tabs[1:], start=2):
        print(f"[kitty.py/debug]: Creating tab {i}: {tab_cmd}")
        subprocess.run([
            'kitty', '@', '--to', socket_path, 'launch',
            '--type=tab',
            '--cwd', directory,
            'sh', '-c', f'cd {directory} && {tab_cmd}'
        ], check=True)
        time.sleep(0.3)

    # Close the default window if we just launched Kitty
    if close_default_window:
        print("[kitty.py/debug]: Closing default window...")
        # List all windows to find the default one
        result = subprocess.run([
            'kitty', '@', '--to', socket_path, 'ls'
        ], capture_output=True, text=True, check=True)

        windows_data = json.loads(result.stdout)

        # Find the default window (it will be at home directory without our title)
        home_dir = os.environ.get('HOME', '')
        for os_window in windows_data:
            for tab in os_window.get('tabs', []):
                for window in tab.get('windows', []):
                    cwd = window.get('cwd', '')
                    title = window.get('title', '')
                    # Default window is at home and doesn't have our custom title
                    if cwd == home_dir and 'VPC Workspace' not in title:
                        window_id = window.get('id')
                        print(f"[kitty.py/debug]: Found default window (id={window_id}, cwd={cwd})")
                        # Close this window
                        subprocess.run([
                            'kitty', '@', '--to', socket_path, 'close-window',
                            '--match', f'id:{window_id}'
                        ], check=True)
                        print("[kitty.py/debug]: Default window closed")
                        break

    print("[kitty.py/debug]: Kitty setup complete")

except subprocess.CalledProcessError as e:
    print(f"[kitty.py/error]: Command failed: {e}", file=sys.stderr)
    sys.exit(1)
except RuntimeError as e:
    print(f"[kitty.py/error]: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print("[kitty.py/error]: kitty command not found. Make sure Kitty is installed and in PATH", file=sys.stderr)
    print("[kitty.py/error]: You may need to enable remote control in ~/.config/kitty/kitty.conf:", file=sys.stderr)
    print("[kitty.py/error]:   allow_remote_control yes", file=sys.stderr)
    print("[kitty.py/error]:   listen_on unix:/tmp/kitty", file=sys.stderr)
    sys.exit(1)
