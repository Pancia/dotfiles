#!/usr/bin/env python3

import iterm2
import AppKit
import sys
import json

directory = sys.argv[1]
tabs = json.loads(sys.argv[2])

AppKit.NSWorkspace.sharedWorkspace().launchApplication_("iterm")

async def main(connection):
    app = await iterm2.async_get_app(connection)
    await app.async_activate()
    window = await iterm2.Window.async_create(connection, command=f"/bin/zsh")
    await window.current_tab.current_session.async_send_text(f"cd {directory} && {tabs[0]}\n")
    for t in tabs[1:]:
        tab = await window.async_create_tab()
        await tab.current_session.async_send_text(f"cd {directory} && {t}\n")
    #await tab.current_session.async_split_pane(vertical=True)

iterm2.run_until_complete(main, True)
