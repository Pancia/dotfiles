"""fish/functions/ccs.fish -- the paths that decide whether a chat stays findable.

Each test pins one way a session used to drop out of `ccs list` or become
unresumable: an entry deleted while claude was still alive or had crashed, a
restore that gave up without a recorded transcript path, and a failed resume
that archived its entry anyway.
"""

import json
import os
import subprocess
from pathlib import Path

CCS = Path(__file__).resolve().parents[2] / "fish" / "functions" / "ccs.fish"
KEY = CCS.parent / "_cc_worktree_key.fish"


def fish(code, tmp_path, check=True):
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    r = subprocess.run(["fish", "--no-config", "-c", f"source {CCS}\nsource {KEY}\n{code}"],
                       capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30,
                       env={**os.environ, "XDG_STATE_HOME": str(tmp_path / "state"),
                            "HOME": str(home)})
    if check:
        assert r.returncode == 0, r.stderr
    return r


def entry(tmp_path, **fields):
    d = tmp_path / "state" / "claude-sessions" / "open"
    d.mkdir(parents=True, exist_ok=True)
    f = d / "1-1.json"
    f.write_text(json.dumps({"pid": 1, "pid_lstart": "never", "started_at": 1, **fields}))
    return f


def test_finish_keeps_an_entry_whose_session_did_not_end(tmp_path):
    """claude crashed (or was killed) under a live shell: no SessionEnd ran."""
    f = entry(tmp_path, session_id="s1", cwd="/r")
    r = fish(f"_ccs_open_finish {f} 137", tmp_path)
    assert f.exists()
    assert "did not end cleanly (exit 137)" in r.stdout
    assert json.loads(f.read_text())["claude_exited"] is True


def test_scan_lists_a_dead_claude_under_a_live_shell_as_crashed(tmp_path):
    """The entry pid is the shell's, which is still alive. A "running" row
    would only switch to the dead pane instead of resuming."""
    repo = tmp_path / "repo"
    repo.mkdir()
    me = os.getpid()
    lstart = subprocess.run(["ps", "-o", "lstart=", "-p", str(me)],
                            capture_output=True, text=True).stdout.strip()
    f = entry(tmp_path, session_id="s1", cwd=str(repo), pid=me, pid_lstart=lstart)
    assert fish(f"cd {repo}; _ccs_open_scan", tmp_path).stdout.startswith("running\t")
    e = json.loads(f.read_text())
    e["claude_exited"] = True
    f.write_text(json.dumps(e))
    assert fish(f"cd {repo}; _ccs_open_scan", tmp_path).stdout.startswith("crashed\t")


def test_finish_retires_an_ended_entry(tmp_path):
    f = entry(tmp_path, session_id="s1", cwd="/r", ended=True)
    fish(f"_ccs_open_finish {f} 0", tmp_path)
    assert not f.exists()


def test_finish_retires_an_entry_that_never_got_an_id(tmp_path):
    f = entry(tmp_path, cwd="/r")
    fish(f"_ccs_open_finish {f} 0", tmp_path)
    assert not f.exists()


def test_scan_retires_an_ended_entry_and_lists_a_crashed_one(tmp_path):
    """A suspended claude that ended after `fg` was never finalized."""
    repo = tmp_path / "repo"
    repo.mkdir()
    ended = entry(tmp_path, session_id="s1", cwd=str(repo), ended=True)
    crashed = ended.with_name("2-2.json")
    crashed.write_text(json.dumps({"pid": 2, "pid_lstart": "never", "started_at": 1,
                                   "session_id": "s2", "cwd": str(repo)}))
    r = fish(f"cd {repo}; _ccs_open_scan", tmp_path)
    assert not ended.exists()
    assert crashed.exists()
    assert "s2" in r.stdout and "s1" not in r.stdout


def zst(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["zstd", "-qf", str(src), "-o", str(dst)], check=True)


def test_restore_without_a_recorded_path_uses_the_cwd_folder(tmp_path):
    """The session died before its first Stop, so transcript_path is empty."""
    raw = tmp_path / "raw.jsonl"
    raw.write_text('{"x":1}\n')
    zst(raw, tmp_path / "state" / "claude-sessions" / "transcripts" / "s1.jsonl.zst")
    f = entry(tmp_path, session_id="s1", cwd="/Users/a/vaults/the.akashic", transcript_path="")
    fish(f"_ccs_restore_transcript s1 {f}", tmp_path)
    out = tmp_path / "home" / ".claude" / "projects" / "-Users-a-vaults-the-akashic" / "s1.jsonl"
    assert out.read_text() == '{"x":1}\n'


def test_restore_falls_back_to_the_nightly_cloud_copy(tmp_path):
    raw = tmp_path / "raw.jsonl"
    raw.write_text('{"y":2}\n')
    zst(raw, tmp_path / "home" / "Cloud" / "claude-transcripts" / "projects" / "-r" / "s1.jsonl.zst")
    f = entry(tmp_path, session_id="s1", cwd="/r")
    fish(f"_ccs_restore_transcript s1 {f}", tmp_path)
    assert (tmp_path / "home" / ".claude" / "projects" / "-r" / "s1.jsonl").read_text() == '{"y":2}\n'


def test_restore_takes_the_newest_copy(tmp_path):
    """The local copy is throttled; after a crash the nightly one can hold more."""
    old, new = tmp_path / "old.jsonl", tmp_path / "new.jsonl"
    old.write_text('{"n":1}\n')
    new.write_text('{"n":1}\n{"n":2}\n')
    local = tmp_path / "state" / "claude-sessions" / "transcripts" / "s1.jsonl.zst"
    nightly = tmp_path / "home" / "Cloud" / "claude-transcripts" / "projects" / "-real-folder" / "s1.jsonl.zst"
    zst(old, local)
    zst(new, nightly)
    os.utime(local, (1000, 1000))
    os.utime(nightly, (2000, 2000))
    f = entry(tmp_path, session_id="s1", cwd="/somewhere/else")
    fish(f"_ccs_restore_transcript s1 {f}", tmp_path)
    out = tmp_path / "home" / ".claude" / "projects" / "-real-folder" / "s1.jsonl"
    assert out.read_text() == '{"n":1}\n{"n":2}\n', "newest copy, in the copy's real folder"


def test_a_resume_with_nothing_to_restore_keeps_the_entry(tmp_path):
    f = entry(tmp_path, session_id="gone", cwd="/r")
    r = fish(f"function my-claude-code-wrapper; echo LAUNCHED; end; _ccs_resume_entry {f}",
             tmp_path, check=False)
    assert r.returncode == 1
    assert "LAUNCHED" not in r.stdout
    assert f.exists(), "the entry is the only pointer left to this session"
