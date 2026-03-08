#!/usr/bin/env python3.11
# pyright: reportAttributeAccessIssue=false, reportPrivateImportUsage=false, reportOptionalMemberAccess=false

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
    """Parse a pane definition into (cmd, vertical, size, title).

    Pane can be:
      - "command"                           -> (cmd, True, None, None)
      - {"cmd": "command"}                  -> (cmd, True, None, None)
      - {"cmd": "command", "size": 50}      -> (cmd, True, 50, None)
      - {"cmd": "command", "vertical": false, "size": 70, "title": "Logs"}
    """
    if isinstance(pane, str):
        return pane, True, None, None
    return pane["cmd"], pane.get("vertical", True), pane.get("size"), pane.get("title")


def _pane_command(directory, cmd, title=None):
    """Build the shell command string for a pane, with optional title env var."""
    prefix = f"set -gx VPC_PANE_TITLE '{title}'\n" if title else ""
    return f"{prefix}cd {directory} && {cmd}\n"


async def _set_pane_badge(session, title):
    """Set the iTerm2 badge text for a session via the profile API."""
    profile = iterm2.LocalWriteOnlyProfile()
    profile.set_badge_text(title)
    await session.async_set_profile_properties(profile)


async def setup_tab(window, tab, directory, tab_data):
    """Set up a tab with optional split panes.

    tab_data can be:
      - "command"                              -> single pane
      - ["cmd1", "cmd2"]                       -> vertical splits, equal size
      - [{"cmd": ..., "size": 50}, "cmd2"]     -> splits with sizing
      - {"title": "Name", "cmd": "command"}    -> single pane with tab title
      - {"title": "Name", "panes": [...]}      -> split panes with tab title
    """
    tab_title = None

    # Dict form: extract title, then normalize to string or list
    if isinstance(tab_data, dict):
        tab_title = tab_data.get("title")
        if "panes" in tab_data:
            tab_data = tab_data["panes"]
        else:
            tab_data = tab_data.get("cmd", "")

    if tab_title:
        await tab.async_set_title(tab_title)

    if isinstance(tab_data, str):
        await tab.current_session.async_send_text(_pane_command(directory, tab_data))
        return

    panes = [parse_pane(p) for p in tab_data]
    first_cmd, _, _, first_title = panes[0]

    # First pane uses the existing session
    first_session = tab.current_session
    if first_title:
        await _set_pane_badge(first_session, first_title)
    await first_session.async_send_text(_pane_command(directory, first_cmd, first_title))

    # Create remaining panes by splitting the previous session
    prev_session = first_session
    sessions = [first_session]
    for cmd, vertical, _, pane_title in panes[1:]:
        await asyncio.sleep(0.3)
        new_session = await prev_session.async_split_pane(vertical=vertical)
        if pane_title:
            await _set_pane_badge(new_session, pane_title)
        await new_session.async_send_text(_pane_command(directory, cmd, pane_title))
        sessions.append(new_session)
        prev_session = new_session

    # Apply preferred sizes if any pane specifies a size (percentage)
    has_sizes = any(p[2] is not None for p in panes)
    if has_sizes:
        # Get total grid cells across all panes in the split direction
        total_cols = sum(s.grid_size.width for s in sessions)
        total_rows = sum(s.grid_size.height for s in sessions)
        for session, (_, vertical, size_pct, _) in zip(sessions, panes):
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
