#!/usr/bin/env python3.11

import iterm2
import AppKit
import sys
import json
import os
import asyncio

print("[iterm.py/debug]: args:", sys.argv)
directory = sys.argv[1]
tabs = json.loads(sys.argv[2])
print("[iterm.py/debug]: dir & tabs", directory, tabs)

AppKit.NSWorkspace.sharedWorkspace().launchApplication_("iterm")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    print(app)
    await app.async_activate()
    window = await iterm2.Window.async_create(connection)
    # Wait for shell to fully initialize before sending commands
    await asyncio.sleep(0.5)
    await window.current_tab.current_session.async_send_text(f"cd {directory} && {tabs[0]}\n")
    for t in tabs[1:]:
        tab = await window.async_create_tab()
        await asyncio.sleep(0.3)
        await tab.current_session.async_send_text(f"cd {directory} && {t}\n")
    #await tab.current_session.async_split_pane(vertical=True)

iterm2.run_until_complete(main, True)
