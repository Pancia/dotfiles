#!/usr/bin/env python3
"""Tests for bin/ccs-title-hook (Stop, and SessionEnd as `--end`).

The backup must run for every session, whatever the entry says. The entry is
written only by the session stamped in it. `--end` marks a clean end, except
for /clear and /resume, which keep the process and move the entry on.
"""

import json
import os
import subprocess
import time
from pathlib import Path

HOOK = Path(__file__).parent.parent.parent / "bin" / "ccs-title-hook"


def lstart(pid):
    return subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                          capture_output=True, text=True).stdout.strip()


def setup(tmp_path, stamped="sid-1", transcript_lines=None):
    state = tmp_path / "state"
    transcript = tmp_path / "proj" / "sid-1.jsonl"
    transcript.parent.mkdir(parents=True)
    lines = transcript_lines or [{"type": "ai-title", "aiTitle": "A title"}]
    transcript.write_text("".join(json.dumps(l, separators=(",", ":")) + "\n" for l in lines))
    entry = None
    if stamped is not None:
        entry = tmp_path / "entry.json"
        # The hook runs as a child of this test process, so this test's parent
        # plays the wrapper: it is the hook's grandparent, as in a real session.
        entry.write_text(json.dumps({"session_id": stamped, "cwd": "/repo",
                                     "pid": os.getppid(), "pid_lstart": lstart(os.getppid())}))
    return state, transcript, entry


def run(state, transcript, entry, *args, sid="sid-1", reason=None):
    payload = {"session_id": sid, "transcript_path": str(transcript)}
    if reason:
        payload["reason"] = reason
    env = dict(os.environ, XDG_STATE_HOME=str(state))
    env.pop("CCS_ENTRY_FILE", None)
    if entry is not None:
        env["CCS_ENTRY_FILE"] = str(entry)
    r = subprocess.run([str(HOOK), *args], input=json.dumps(payload), env=env,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert r.stdout == ""


def backup(state, sid="sid-1"):
    return state / "claude-sessions" / "transcripts" / f"{sid}.jsonl.zst"


def test_a_session_with_no_entry_is_still_backed_up(tmp_path):
    """Plain `claude`, the desktop app and IDE sessions have no ccs entry."""
    state, transcript, _ = setup(tmp_path, stamped=None)
    run(state, transcript, None)
    assert backup(state).is_file()


def test_a_session_with_no_title_is_still_backed_up(tmp_path):
    state, transcript, entry = setup(tmp_path, transcript_lines=[{"type": "user"}])
    run(state, transcript, entry)
    assert backup(state).is_file()
    e = json.loads(entry.read_text())
    assert "title" not in e
    assert e["transcript_path"] == str(transcript), "resume needs it to restore"


def test_stop_writes_the_title_for_the_stamped_session_only(tmp_path):
    state, transcript, entry = setup(tmp_path, stamped="other")
    run(state, transcript, entry)
    assert "title" not in json.loads(entry.read_text())
    entry.write_text(json.dumps({"session_id": "sid-1"}))
    run(state, transcript, entry)
    assert json.loads(entry.read_text())["title"] == "A title"


def test_stop_is_throttled_but_end_is_not(tmp_path):
    state, transcript, entry = setup(tmp_path)
    run(state, transcript, entry)
    b = backup(state)
    old = time.time() - 60
    os.utime(b, (old, old))
    run(state, transcript, entry)
    assert b.stat().st_mtime < old + 1, "Stop within 10 minutes must not copy again"
    run(state, transcript, entry, "--end", reason="prompt_input_exit")
    assert b.stat().st_mtime > old + 30, "SessionEnd must take the last minutes"


def test_end_marks_the_entry_ended(tmp_path):
    state, transcript, entry = setup(tmp_path)
    run(state, transcript, entry, "--end", reason="prompt_input_exit")
    assert json.loads(entry.read_text())["ended"] is True


def test_clear_and_resume_do_not_mark_the_entry_ended(tmp_path):
    for reason in ("clear", "resume"):
        state, transcript, entry = setup(tmp_path / reason)
        run(state, transcript, entry, "--end", reason=reason)
        assert "ended" not in json.loads(entry.read_text()), reason


def test_a_nested_session_ending_does_not_mark_the_parent(tmp_path):
    state, transcript, entry = setup(tmp_path, stamped="parent")
    run(state, transcript, entry, "--end", reason="other")
    assert "ended" not in json.loads(entry.read_text())


def test_a_nested_session_resuming_the_parent_id_does_not_mark_it(tmp_path):
    """`claude -p --resume $CLAUDE_SESSION_ID` ends with the parent's own id.
    Marking the parent ended let `ccs list` delete a live session's entry."""
    state, transcript, entry = setup(tmp_path)
    e = json.loads(entry.read_text())
    e["pid"] = 1  # the wrapper is not within two steps of this hook
    entry.write_text(json.dumps(e))
    run(state, transcript, entry, "--end", reason="other")
    assert "ended" not in json.loads(entry.read_text())
