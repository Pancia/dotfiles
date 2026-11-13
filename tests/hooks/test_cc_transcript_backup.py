#!/usr/bin/env python3
"""Tests for services/cc-transcript-backup/script.sh, the nightly ProtonDrive copy.

The one rule that matters most: it never deletes. Claude Code prunes its own
transcripts after cleanupPeriodDays, and this copy is what outlives that.
"""

import os
import subprocess
import time
from pathlib import Path

SCRIPT = Path(__file__).parent.parent.parent / "services" / "cc-transcript-backup" / "script.sh"


def run(tmp_path):
    env = dict(os.environ, CC_BACKUP_SRC=str(tmp_path / "claude"),
               CC_BACKUP_DST=str(tmp_path / "cloud" / "claude-transcripts"),
               XDG_STATE_HOME=str(tmp_path / "state"))
    r = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
    return r


def unzst(p):
    return subprocess.run(["zstd", "-dc", str(p)], capture_output=True, check=True).stdout


def make(tmp_path):
    proj = tmp_path / "claude" / "projects" / "-Users-x-repo"
    (proj / "s1" / "subagents").mkdir(parents=True)
    (proj / "s1.jsonl").write_text('{"a":1}\n')
    (proj / "s1" / "subagents" / "agent-a.jsonl").write_text('{"b":2}\n')
    (tmp_path / "claude" / "history.jsonl").write_text('{"h":1}\n')
    (tmp_path / "cloud").mkdir()
    return proj


def test_copies_every_transcript_and_the_history(tmp_path):
    make(tmp_path)
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr
    dst = tmp_path / "cloud" / "claude-transcripts"
    assert unzst(dst / "projects" / "-Users-x-repo" / "s1.jsonl.zst") == b'{"a":1}\n'
    assert unzst(dst / "projects" / "-Users-x-repo" / "s1" / "subagents" / "agent-a.jsonl.zst") == b'{"b":2}\n'
    assert unzst(dst / "history.jsonl.zst") == b'{"h":1}\n'
    assert "copied 2" in r.stdout


def test_unchanged_files_are_skipped_and_newer_ones_copied_again(tmp_path):
    proj = make(tmp_path)
    run(tmp_path)
    r = run(tmp_path)
    assert "copied 0, unchanged 2" in r.stdout
    f = proj / "s1.jsonl"
    f.write_text('{"a":1}\n{"a":2}\n')
    future = time.time() + 5
    os.utime(f, (future, future))
    r = run(tmp_path)
    assert "copied 1" in r.stdout
    dst = tmp_path / "cloud" / "claude-transcripts" / "projects" / "-Users-x-repo" / "s1.jsonl.zst"
    assert unzst(dst) == b'{"a":1}\n{"a":2}\n'


def test_a_pruned_transcript_keeps_its_copy(tmp_path):
    proj = make(tmp_path)
    run(tmp_path)
    (proj / "s1.jsonl").unlink()
    run(tmp_path)
    assert (tmp_path / "cloud" / "claude-transcripts" / "projects" / "-Users-x-repo" / "s1.jsonl.zst").is_file()


def test_refuses_when_the_cloud_folder_is_missing(tmp_path):
    make(tmp_path)
    (tmp_path / "cloud").rmdir()
    r = run(tmp_path)
    assert r.returncode != 0
    assert not (tmp_path / "cloud").exists()


def test_copies_keep_the_original_mtime(tmp_path):
    """The next night compares mtimes, so a copy stamped later than its
    source would mark lines it does not hold as copied."""
    proj = make(tmp_path)
    os.utime(proj / "s1.jsonl", (1_700_000_000, 1_700_000_000))
    run(tmp_path)
    dst = tmp_path / "cloud" / "claude-transcripts" / "projects" / "-Users-x-repo" / "s1.jsonl.zst"
    assert int(dst.stat().st_mtime) == 1_700_000_000


def test_ccs_state_is_copied_without_half_written_files(tmp_path):
    make(tmp_path)
    st = tmp_path / "state" / "claude-sessions"
    for d in ("open", "archive", "transcripts"):
        (st / d).mkdir(parents=True)
    (st / "open" / "1-1.json").write_text("{}")
    (st / "open" / "1-1.json.tmp.123").write_text("")
    (st / "transcripts" / "old.jsonl.zst").write_text("z")
    assert run(tmp_path).returncode == 0
    out = tmp_path / "cloud" / "claude-transcripts" / "ccs-state"
    assert (out / "open" / "1-1.json").is_file()
    assert not (out / "open" / "1-1.json.tmp.123").exists()
    assert (out / "transcripts" / "old.jsonl.zst").is_file(), "the only copy of pruned chats"


def test_a_missing_projects_folder_is_not_an_error(tmp_path):
    (tmp_path / "claude").mkdir()
    (tmp_path / "cloud").mkdir()
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "copied 0" in r.stdout
