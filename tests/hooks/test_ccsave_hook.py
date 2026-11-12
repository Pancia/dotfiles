#!/usr/bin/env python3
"""Tests for bin/ccsave-hook, which stamps the session id into a ccs entry.

The entry records the wrapper's pid. A real session runs
wrapper -> claude -> hook. A nested helper runs
wrapper -> claude -> shell -> nested claude -> hook, and inherits
CCS_ENTRY_FILE. The hook must follow /resume in the first case only.
"""

import json
import os
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).parent.parent.parent
HOOK = DOTFILES / "bin" / "ccsave-hook"

# Each script ends in `; true`, so bash cannot exec its last command and drop a
# process level. The wrapper writes the entry with its own pid and start time.
SCRIPTS = {
    "wrapper.sh": r"""
jq -n --argjson pid $$ --arg l "$(ps -o lstart= -p $$ | sed 's/^ *//; s/ *$//')" \
  --arg sid "$OLD_SID" '{pid:$pid, pid_lstart:$l, session_id:$sid, title:"old"}' \
  > "$CCS_ENTRY_FILE"
bash "$D/$FIRST"; true
""",
    # A claude that runs its hook directly.
    "claude.sh": '"$HOOK" < "$INPUT"; true\n',
    # A claude that runs its hook through `sh -c`.
    "claude_sh.sh": 'sh -c \'"$HOOK" < "$INPUT"; true\'; true\n',
    # A claude whose Bash tool starts a nested claude.
    "claude_nested.sh": 'bash -c \'bash "$D/claude.sh"; true\'; true\n',
}


def run(tmp_path, source, first, old_sid="old-id"):
    for name, body in SCRIPTS.items():
        (tmp_path / name).write_text(body)
    entry = tmp_path / "entry.json"
    inp = tmp_path / "input.json"
    inp.write_text(json.dumps({"session_id": "new-id", "source": source, "cwd": "/x"}))
    env = dict(
        os.environ,
        CCS_ENTRY_FILE=str(entry),
        INPUT=str(inp),
        HOOK=str(HOOK),
        OLD_SID=old_sid,
        D=str(tmp_path),
        FIRST=first,
    )
    env.pop("CLAUDE_ENV_FILE", None)
    r = subprocess.run(
        ["bash", str(tmp_path / "wrapper.sh")], env=env, capture_output=True, text=True
    )
    assert r.returncode == 0, r.stderr
    assert r.stdout == ""
    return json.loads(entry.read_text())


def test_resume_in_top_session_follows_new_id(tmp_path):
    e = run(tmp_path, "resume", "claude.sh")
    assert e["session_id"] == "new-id"
    assert e["title"] == ""


def test_resume_through_sh_c_still_counts_as_top(tmp_path):
    e = run(tmp_path, "resume", "claude_sh.sh")
    assert e["session_id"] == "new-id"


def test_resume_from_nested_session_is_ignored(tmp_path):
    e = run(tmp_path, "resume", "claude_nested.sh")
    assert e["session_id"] == "old-id"
    assert e["title"] == "old"


def test_startup_never_overwrites_a_stamped_entry(tmp_path):
    e = run(tmp_path, "startup", "claude.sh")
    assert e["session_id"] == "old-id"


def test_clear_still_follows(tmp_path):
    e = run(tmp_path, "clear", "claude.sh")
    assert e["session_id"] == "new-id"


def test_empty_entry_is_stamped(tmp_path):
    e = run(tmp_path, "startup", "claude.sh", old_sid="")
    assert e["session_id"] == "new-id"
