#!/usr/bin/env python3.11

import iterm2
import AppKit
import sys
import json
import asyncio

print("[iterm.py/debug]: args:", sys.argv)
directory = sys.argv[1]
tabs = json.loads(sys.argv[2])

# Parse --frame x,y,w,h or --maximize
target_frame = None
for i, arg in enumerate(sys.argv):
    if arg == "--frame" and i + 1 < len(sys.argv):
        parts = sys.argv[i + 1].split(",")
        target_frame = tuple(int(p) for p in parts)
    elif arg == "--maximize":
        screen = AppKit.NSScreen.mainScreen()
        visible = screen.visibleFrame()
        target_frame = (int(visible.origin.x), int(visible.origin.y),
                        int(visible.size.width), int(visible.size.height))

print("[iterm.py/debug]: dir & tabs", directory, tabs, "frame:", target_frame)

AppKit.NSWorkspace.sharedWorkspace().launchApplication_("iterm")


def parse_pane(pane):
    """Parse a pane definition into (cmd, vertical, size).

    Pane can be:
      - "command"                           -> (cmd, True, None)
      - {"cmd": "command"}                  -> (cmd, True, None)
      - {"cmd": "command", "size": 50}      -> (cmd, True, 50)
      - {"cmd": "command", "vertical": false, "size": 70}
    """
    if isinstance(pane, str):
        return pane, True, None
    return pane["cmd"], pane.get("vertical", True), pane.get("size")


async def setup_tab(window, tab, directory, tab_data):
    """Set up a tab with optional split panes.

    tab_data can be:
      - "command"           -> single pane
      - ["cmd1", "cmd2"]    -> vertical splits, equal size
      - [{"cmd": ..., "size": 50}, "cmd2"]  -> splits with sizing
    """
    if isinstance(tab_data, str):
        await tab.current_session.async_send_text(f"cd {directory} && {tab_data}\n")
        return

    panes = [parse_pane(p) for p in tab_data]
    first_cmd, _, _ = panes[0]

    # First pane uses the existing session
    first_session = tab.current_session
    await first_session.async_send_text(f"cd {directory} && {first_cmd}\n")

    # Create remaining panes by splitting the previous session
    prev_session = first_session
    sessions = [first_session]
    for cmd, vertical, _ in panes[1:]:
        await asyncio.sleep(0.3)
        new_session = await prev_session.async_split_pane(vertical=vertical)
        await new_session.async_send_text(f"cd {directory} && {cmd}\n")
        sessions.append(new_session)
        prev_session = new_session

    # Apply preferred sizes if any pane specifies a size (percentage)
    has_sizes = any(p[2] is not None for p in panes)
    if has_sizes:
        # Get total grid cells across all panes in the split direction
        total_cols = sum(s.grid_size.width for s in sessions)
        total_rows = sum(s.grid_size.height for s in sessions)
        for session, (_, vertical, size_pct) in zip(sessions, panes):
            if size_pct is not None:
                if vertical:
                    cols = int(total_cols * size_pct / 100)
                    session.preferred_size = iterm2.util.Size(cols, session.grid_size.height)
                else:
                    rows = int(total_rows * size_pct / 100)
                    session.preferred_size = iterm2.util.Size(session.grid_size.width, rows)
        # Save and restore window frame so layout update doesn't shrink the window
        saved_frame = await window.async_get_frame()
        await tab.async_update_layout()
        await window.async_set_frame(saved_frame)


async def main(connection):
    app = await iterm2.async_get_app(connection)
    print(app)
    await app.async_activate()
    window = await iterm2.Window.async_create(connection)
    await asyncio.sleep(0.5)

    # Set window frame if specified (--frame or --maximize)
    if target_frame:
        x, y, w, h = target_frame
        frame = iterm2.util.Frame(
            iterm2.util.Point(x, y),
            iterm2.util.Size(w, h)
        )
        await window.async_set_frame(frame)
        await asyncio.sleep(0.3)

    # First tab
    await setup_tab(window, window.current_tab, directory, tabs[0])

    # Additional tabs
    for t in tabs[1:]:
        tab = await window.async_create_tab()
        await asyncio.sleep(0.3)
        await setup_tab(window, tab, directory, t)


iterm2.run_until_complete(main, True)
