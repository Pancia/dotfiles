#!/usr/bin/env python3
"""Tests for bin/ccsave: where a manual save and its backup land.

A save keyed on the current folder landed where `ccs list` at the repo root
never looks, and a transcript path built with `tr '/' '-'` missed any folder
with a dot in it, so those sessions got no Cloud backup.
"""

import json
import os
import subprocess
from pathlib import Path

CCSAVE = Path(__file__).parent.parent.parent / "bin" / "ccsave"


def run(tmp_path, cwd, entry_sid="sx"):
    home = tmp_path / "home"
    proj = home / ".claude" / "projects" / "-Users-a--claude-worktrees-x"
    proj.mkdir(parents=True, exist_ok=True)
    (proj / "sx.jsonl").write_text('{"x":1}\n')
    (home / "Cloud").mkdir(exist_ok=True)
    entry = tmp_path / "entry.json"
    entry.write_text(json.dumps({"session_id": entry_sid, "cwd": "/repo/key"}))
    cwd.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, HOME=str(home), CLAUDE_SESSION_ID="sx",
               CCS_ENTRY_FILE=str(entry))
    r = subprocess.run([str(CCSAVE), "a title"], cwd=str(cwd), env=env,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return home / "Cloud" / "cc-sessions"


def test_the_save_is_keyed_on_the_launch_folder_not_the_current_one(tmp_path):
    root = run(tmp_path, tmp_path / "some" / "subfolder")
    saved = json.loads((root / "repo" / "key" / "sessions.json").read_text())
    assert [s["id"] for s in saved] == ["sx"]
    assert (root / "repo" / "key" / "session-backups" / "sx.jsonl.zst").is_file(), \
        "found by id even though its folder name has a doubled dash"


def test_an_entry_of_another_session_is_not_used_as_the_key(tmp_path):
    cwd = tmp_path / "here"
    root = run(tmp_path, cwd, entry_sid="someone-else")
    assert not (root / "repo").exists()
    assert (root / str(cwd).lstrip("/") / "sessions.json").is_file()
