"""Tests for bin/cc-peers and the PEERS section of bin/vcs-status-for-ai.

cc-peers tells /cc:commit, in a git repo, which other live Claude sessions are
working in the checkout and which files they wrote. A false negative lets a
commit sweep up a peer's work in progress; a false positive withholds "Split
everything" for no reason. Every fixture here is a fake registry and fake
transcripts under tmp_path; the real ~/.claude is never read.
"""

import json
import os
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parents[3]
PEERS = DOTFILES / "bin" / "cc-peers"
STATUS = DOTFILES / "bin" / "vcs-status-for-ai"


def lstart(pid):
    """The registry's procStart format: `ps -o lstart` in UTC."""
    out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                         env=dict(os.environ, TZ="UTC", LC_ALL="C"),
                         capture_output=True, text=True).stdout
    return " ".join(out.split())


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=str(cwd), check=True, capture_output=True)


@pytest.fixture
def world(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@t.t")
    git(repo, "config", "user.name", "t")
    (repo / "a.txt").write_text("a\n")
    git(repo, "add", "a.txt")
    git(repo, "commit", "-qm", "init")
    sessions = tmp_path / "sessions"
    projects = tmp_path / "projects"
    sessions.mkdir()
    projects.mkdir()
    procs = []

    def live():
        p = subprocess.Popen(["sleep", "60"])
        procs.append(p)
        return p.pid

    yield {"repo": repo, "sessions": sessions, "projects": projects,
           "live": live, "tmp": tmp_path}
    for p in procs:
        p.kill()
        p.wait()


def register(w, sid, pid, cwd, proc_start=None, name=None):
    entry = {"pid": pid, "sessionId": sid, "cwd": str(cwd), "status": "idle",
             "procStart": lstart(pid) if proc_start is None else proc_start,
             "startedAt": 1794340409462}
    if name:
        entry["name"] = name
    (w["sessions"] / ("%d.json" % pid)).write_text(json.dumps(entry))


def transcript(w, sid, writes, subagent=False):
    d = w["projects"] / "-key"
    f = d / (sid + ".jsonl")
    if subagent:
        d = d / sid / "subagents"
        f = d / "agent-x.jsonl"
    d.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps({"type": "user", "message": {"content": "hi"}})]
    for tool, path in writes:
        key = "notebook_path" if tool == "NotebookEdit" else "file_path"
        lines.append(json.dumps({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": tool, "input": {key: str(path)}}]}}))
    with open(f, "a") as fh:
        fh.write("\n".join(lines) + "\n")


def run(w, *args, cwd=None):
    r = subprocess.run([str(PEERS), "--sessions-dir", str(w["sessions"]),
                        "--projects-dir", str(w["projects"]), "--session", "",
                        *args],
                       cwd=str(cwd or w["repo"]), capture_output=True, text=True)
    return r.returncode, r.stdout


def test_no_registry_entries_is_silent_exit_1(world):
    assert run(world) == (1, "")


def test_live_peer_listed_with_its_files_relative_to_the_checkout(world):
    pid = world["live"]()
    repo = world["repo"]
    register(world, "peer-1", pid, repo, name="repo-ab")
    transcript(world, "peer-1", [("Edit", repo / "a.txt"),
                                 ("Write", repo / "sub" / "new.js"),
                                 ("Edit", repo / "a.txt"),
                                 ("Read", repo / "read-only.txt"),
                                 ("Write", world["tmp"] / "elsewhere.txt")])
    transcript(world, "peer-1", [("NotebookEdit", repo / "nb.ipynb")], subagent=True)
    code, out = run(world)
    assert code == 0
    lines = out.splitlines()
    assert lines[0].startswith('session peer-1 "repo-ab" (pid %d, idle' % pid)
    assert lines[1:] == ["    a.txt", "    nb.ipynb", "    sub/new.js"]


def test_peer_without_writes_still_counts(world):
    # It may be about to write, or working through Bash; it is still live here.
    register(world, "peer-1", world["live"](), world["repo"])
    code, out = run(world)
    assert code == 0
    assert "(no Edit or Write in this checkout)" in out


def test_peer_in_a_subfolder_of_the_checkout_counts(world):
    sub = world["repo"] / "src"
    sub.mkdir()
    register(world, "peer-1", world["live"](), sub)
    assert run(world)[0] == 0


def test_dead_process_is_not_a_peer(world):
    p = subprocess.Popen(["true"])
    p.wait()
    register(world, "gone", p.pid, world["repo"], proc_start="Mon Jan  1 00:00:00 2024")
    assert run(world) == (1, "")


def test_reused_pid_with_another_start_time_is_not_a_peer(world):
    register(world, "old", world["live"](), world["repo"],
             proc_start="Mon Jan  1 00:00:00 2024")
    assert run(world) == (1, "")


def test_idle_for_hours_is_still_a_peer(world):
    # Liveness is the process, never a file time: the session this was built
    # for sat idle for five hours while its peer committed its files.
    pid = world["live"]()
    register(world, "idle", pid, world["repo"])
    transcript(world, "idle", [("Edit", world["repo"] / "a.txt")])
    old = 1_000_000_000
    for f in list(world["sessions"].iterdir()) + list(world["projects"].rglob("*.jsonl")):
        os.utime(f, (old, old))
    assert run(world)[0] == 0


def test_other_checkouts_are_not_peers(world):
    # A linked worktree nested inside the checkout is its own checkout.
    wt = world["repo"] / ".claude" / "worktrees" / "w1"
    git(world["repo"], "worktree", "add", "-q", str(wt))
    other = world["tmp"] / "other"
    other.mkdir()
    (other / ".git").mkdir()
    register(world, "in-worktree", world["live"](), wt)
    register(world, "in-other", world["live"](), other)
    assert run(world) == (1, "")
    # ...and from inside the worktree, the main checkout's session is not a peer.
    register(world, "in-main", world["live"](), world["repo"])
    code, out = run(world, cwd=wt)
    assert code == 0 and "in-worktree" in out and "in-main" not in out


def test_own_session_id_is_left_out(world):
    register(world, "me", world["live"](), world["repo"])
    code, _ = run(world, "--session", "me")
    assert code == 1


def test_own_process_tree_is_left_out_but_an_unrelated_session_is_not(world):
    # This test process is an ancestor of cc-peers, so registering it plays the
    # part of "this session". A child of it plays a helper this session started
    # (a commit-message `claude -p`). pid 1 is a live process outside the tree.
    register(world, "me", os.getpid(), world["repo"])
    register(world, "my-helper", world["live"](), world["repo"])
    assert run(world) == (1, "")
    register(world, "unrelated", 1, world["repo"])
    code, out = run(world)
    assert code == 0
    assert "unrelated" in out and "my-helper" not in out and "session me " not in out


def test_outside_any_checkout_exits_2(world, tmp_path):
    bare = tmp_path / "plain"
    bare.mkdir()
    code, _ = run(world, "--root", str(bare))
    # tmp_path may itself sit inside a checkout on some machines; only assert
    # the no-checkout exit where there really is none.
    if not any((p / ".git").exists() or (p / ".jj").is_dir()
               for p in [bare, *bare.parents]):
        assert code == 2


def test_corrupt_registry_and_transcript_lines_are_skipped(world):
    (world["sessions"] / "999.json").write_text("{not json")
    pid = world["live"]()
    register(world, "peer-1", pid, world["repo"])
    d = world["projects"] / "-key"
    d.mkdir()
    (d / "peer-1.jsonl").write_text('{"tool_use" "Edit" broken\n')
    transcript(world, "peer-1", [("Edit", world["repo"] / "a.txt")])
    code, out = run(world)
    assert code == 0 and "    a.txt" in out


# ------------------------------------------------------------ vcs-status-for-ai

def status_output(w):
    env = dict(os.environ, CC_PEERS_SESSIONS_DIR=str(w["sessions"]),
               CC_PEERS_PROJECTS_DIR=str(w["projects"]), CLAUDE_SESSION_ID="")
    r = subprocess.run([str(STATUS)], cwd=str(w["repo"]), env=env,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout


def test_status_has_no_peers_section_when_alone(world):
    assert "### PEERS" not in status_output(world)


def test_status_lists_peers_in_a_git_repo(world):
    register(world, "peer-1", world["live"](), world["repo"], name="repo-ab")
    transcript(world, "peer-1", [("Edit", world["repo"] / "a.txt")])
    out = status_output(world)
    section = out.split("### PEERS\n", 1)[1].split("\n\n", 1)[0]
    assert section.startswith('session peer-1 "repo-ab"')
    assert "    a.txt" in section
    # Before the commit sections, so a reader sees it with the status.
    assert out.index("### PEERS") < out.index("### CURRENT_COMMIT")
