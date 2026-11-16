"""Tests for bin/scratch, the auditable throwaway space.

Every run gets its own SCRATCH_ROOT and HOME under tmp_path, so the real
~/.local/share/claude-scratch is never touched. CLAUDECODE is removed unless
a test sets it, so the birth-time check is off by default.
"""

import json
import os
import subprocess
import time
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parents[3]
SCRATCH = DOTFILES / "bin" / "scratch"


class Env:
    def __init__(self, tmp_path):
        self.tmp = Path(os.path.realpath(tmp_path))
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.root = self.home / ".local/share/claude-scratch"
        self.work = self.home / "work"
        self.work.mkdir()

    def run(self, *args, cwd=None, extra=None):
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("CLAUDE") and not k.startswith("SCRATCH_")}
        # The host's free space must not decide a test: 0 GB minimum unless set.
        env.update({"HOME": str(self.home), "SCRATCH_ROOT": str(self.root),
                    "SCRATCH_TMP_CLAUDE": str(self.tmp / "tc"), "SCRATCH_MIN_FREE_GB": "0",
                    **(extra or {})})
        return subprocess.run([str(SCRATCH), *args], capture_output=True, text=True,
                              cwd=str(cwd or self.home), env=env)

    def audit(self):
        out = []
        for f in sorted((self.root / "audit").glob("*.jsonl")):
            out += [json.loads(x) for x in f.read_text().splitlines()]
        return out

    def batches(self):
        d = self.root / "discard"
        return sorted(p for p in d.iterdir() if p.is_dir()) if d.is_dir() else []


@pytest.fixture
def e(tmp_path):
    return Env(tmp_path)


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True,
                   env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})


# --- new ---------------------------------------------------------------------

def test_new_makes_a_run_and_logs_it(e):
    r = e.run("new", "vote test!")
    assert r.returncode == 0, r.stderr
    run = Path(r.stdout.strip())
    assert run.is_dir() and run.parent == e.root / "runs"
    assert "-vote-test-" in run.name
    meta = json.loads((run / ".scratch-meta.json").read_text())
    assert meta["label"] == "vote-test"
    assert [a["action"] for a in e.audit()] == ["new"]
    assert e.audit()[0]["path"] == str(run)


def test_two_runs_never_share_a_folder(e):
    a = e.run("new", "x").stdout.strip()
    b = e.run("new", "x").stdout.strip()
    assert a != b


# --- discard -----------------------------------------------------------------

def test_discard_moves_into_a_batch_with_a_manifest(e):
    f = e.work / "out.log"
    f.write_text("hello")
    d = e.work / "build"
    (d / "sub").mkdir(parents=True)
    (d / "sub" / "x").write_text("x")
    r = e.run("discard", str(f), str(d) + "/", cwd=e.work)
    assert r.returncode == 0, r.stderr
    assert not f.exists() and not d.exists()
    [batch] = e.batches()
    assert (batch / "1-out.log").read_text() == "hello"
    assert (batch / "2-build" / "sub" / "x").exists()
    man = [json.loads(x) for x in (batch / "MANIFEST.jsonl").read_text().splitlines()]
    assert [m["from"] for m in man] == [str(f), str(d)]
    assert man[0]["bytes"] == 5
    assert [a["action"] for a in e.audit()] == ["discard", "discard"]


def test_a_symlink_moves_and_its_target_stays(e):
    target = e.work / "real.txt"
    target.write_text("keep me")
    link = e.work / "link"
    link.symlink_to(target)
    assert e.run("discard", str(link), cwd=e.work).returncode == 0
    assert target.read_text() == "keep me"
    [batch] = e.batches()
    assert (batch / "1-link").is_symlink()


def test_one_refused_path_moves_nothing(e):
    ok = e.work / "ok.txt"
    ok.write_text("x")
    r = e.run("discard", str(ok), "/", cwd=e.work)
    assert r.returncode == 2
    assert ok.exists()
    assert e.batches() == []
    assert e.audit()[-1]["action"] == "discard-refused"


@pytest.mark.parametrize("what", ["home", "home-child", "cwd", "cwd-parent", "root", "runs",
                                  "library", "missing"])
def test_refuses_places_that_are_never_throwaway(e, what):
    (e.home / "Library" / "CloudStorage" / "ProtonDrive").mkdir(parents=True)
    (e.work / "deep" / "inner").mkdir(parents=True)
    e.run("new")  # makes the root
    path = {
        "home": e.home, "home-child": e.work, "cwd": e.work / "deep" / "inner",
        "cwd-parent": e.work / "deep", "root": e.root, "runs": e.root / "runs",
        "library": e.home / "Library" / "CloudStorage" / "ProtonDrive",
        "missing": e.work / "nope",
    }[what]
    r = e.run("discard", str(path), cwd=e.work / "deep" / "inner")
    assert r.returncode != 0
    assert path.exists() or what == "missing"


# Review finding 1: on a case-insensitive disk, and through the firmlink
# prefix, another spelling of a guarded place must still be refused.
@pytest.mark.parametrize("what", ["library", "cwd-parent", "audit", "firmlink-home-child"])
def test_another_spelling_of_a_guarded_place_is_refused(e, what):
    cloud = e.home / "Library" / "CloudStorage" / "ProtonDrive"
    cloud.mkdir(parents=True)
    (e.work / "deep" / "inner").mkdir(parents=True)
    e.run("new")
    if not Path(str(e.home).upper()).exists():
        pytest.skip("this disk is case-sensitive")
    path, real = {
        "library": (str(e.home / "library" / "cloudstorage" / "PROTONDRIVE"), cloud),
        "cwd-parent": (str(e.work / "DEEP"), e.work / "deep"),
        "audit": (str(e.root).upper() + "/AUDIT", e.root / "audit"),
        "firmlink-home-child": ("/System/Volumes/Data" + str(e.work), e.work),
    }[what]
    if what == "firmlink-home-child" and not Path(path).exists():
        pytest.skip("no /System/Volumes/Data firmlink here")
    r = e.run("discard", path, cwd=e.work / "deep" / "inner")
    assert r.returncode == 2, r.stderr
    assert real.exists()


def test_a_tracked_file_named_in_another_case_is_refused(e):
    if not Path(str(e.home).upper()).exists():
        pytest.skip("this disk is case-sensitive")
    repo = e.work / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    (repo / "Plain").write_text("t")
    git(repo, "add", "Plain")
    git(repo, "commit", "-qm", "one")
    r = e.run("discard", str(repo / "PLAIN"), cwd=e.work)
    assert r.returncode == 2 and "tracked by git" in r.stderr


def test_a_tracked_file_whose_name_looks_like_pathspec_magic_is_refused(e):
    repo = e.work / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    (repo / ":junk").write_text("t")
    git(repo, "add", "--", ":(literal):junk")
    git(repo, "commit", "-qm", "one")
    r = e.run("discard", str(repo / ":junk"), cwd=e.work)
    assert r.returncode == 2 and "tracked by git" in r.stderr


def test_a_path_through_git_is_refused(e):
    repo = e.work / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    r = e.run("discard", str(repo / ".git" / "HEAD"), cwd=e.work)
    assert r.returncode == 2 and ".git" in r.stderr


def test_dotdot_follows_the_symlink_as_mv_would(e):
    elsewhere = e.work / "elsewhere"
    (elsewhere / "dir").mkdir(parents=True)
    (elsewhere / "x").write_text("the one mv means")
    b = e.work / "b"
    b.mkdir()
    (b / "x").write_text("not this one")
    (b / "link").symlink_to(elsewhere / "dir")
    assert e.run("discard", str(b / "link" / ".." / "x"), cwd=e.work).returncode == 0
    assert not (elsewhere / "x").exists() and (b / "x").exists()


def test_scratchpad_contents_are_exempt_but_session_folders_are_not(e):
    sess = e.tmp / "tc" / "-Users-x-proj" / "sid-1"
    (sess / "scratchpad" / "repo" / ".git").mkdir(parents=True)
    (sess / "tasks").mkdir()
    (sess / "tasks" / "out.txt").write_text("agent output")
    env = {"CLAUDECODE": "1"}  # no CLAUDE_PID: only an exempt path can pass
    assert e.run("discard", str(sess / "scratchpad" / "repo"), cwd=e.work, extra=env).returncode == 0
    for p in (sess, sess / "scratchpad", sess / "tasks" / "out.txt"):
        r = e.run("discard", str(p), cwd=e.work, extra=env)
        assert r.returncode == 2 and "session folder" in r.stderr, p


def test_in_claude_only_this_session_s_runs_are_exempt(e):
    mine = Path(e.run("new", "mine", extra={"CLAUDE_CODE_SESSION_ID": "me"}).stdout.strip())
    theirs = Path(e.run("new", "theirs", extra={"CLAUDE_CODE_SESSION_ID": "them"}).stdout.strip())
    for run in (mine, theirs):
        (run / "repo" / ".git").mkdir(parents=True)
    env = {"CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "me"}
    assert e.run("discard", str(mine / "repo"), cwd=e.work, extra=env).returncode == 0
    r = e.run("discard", str(theirs / "repo"), cwd=e.work, extra=env)
    assert r.returncode == 2 and "holds a repo" in r.stderr


def test_refuses_a_cloud_folder_reached_through_a_symlink(e):
    cloud = e.home / "Library" / "CloudStorage" / "ProtonDrive"
    (cloud / "doc").mkdir(parents=True)
    (e.home / "Cloud").symlink_to(cloud)
    r = e.run("discard", str(e.home / "Cloud" / "doc"), cwd=e.work)
    assert r.returncode == 2 and "Library" in r.stderr
    assert (cloud / "doc").exists()


def test_refuses_a_fifo(e):
    p = e.work / "pipe"
    os.mkfifo(p)
    r = e.run("discard", str(p), cwd=e.work)
    assert r.returncode == 2 and "FIFO" in r.stderr


def test_more_than_twenty_paths_need_many(e):
    files = []
    for i in range(21):
        f = e.work / f"f{i}"
        f.write_text("x")
        files.append(str(f))
    assert e.run("discard", *files, cwd=e.work).returncode == 1
    assert e.run("discard", "--many", *files, cwd=e.work).returncode == 0


def test_refuses_a_file_git_tracks_and_takes_an_untracked_one(e):
    repo = e.work / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    (repo / "tracked.txt").write_text("t")
    git(repo, "add", "tracked.txt")
    git(repo, "commit", "-qm", "one")
    (repo / "junk.log").write_text("j")
    r = e.run("discard", str(repo / "tracked.txt"), cwd=e.work)
    assert r.returncode == 2 and "tracked by git" in r.stderr
    assert e.run("discard", str(repo / "junk.log"), cwd=e.work).returncode == 0
    assert (repo / "tracked.txt").exists() and not (repo / "junk.log").exists()


@pytest.mark.skipif(not __import__("shutil").which("jj"), reason="jj not installed")
def test_refuses_a_file_jj_tracks_in_its_parent_commit(e):
    repo = e.work / "jjrepo"
    repo.mkdir()
    env = {**os.environ, "JJ_USER": "t", "JJ_EMAIL": "t@t", "JJ_CONFIG": "/dev/null"}
    subprocess.run(["jj", "git", "init", str(repo)], check=True, capture_output=True, env=env)
    (repo / "kept.txt").write_text("k")
    subprocess.run(["jj", "commit", "-R", str(repo), "-m", "one"], check=True, capture_output=True,
                   env=env)
    (repo / "junk.log").write_text("j")
    r = e.run("discard", str(repo / "kept.txt"), cwd=e.work)
    assert r.returncode == 2 and "tracked by jj" in r.stderr
    assert e.run("discard", str(repo / "junk.log"), cwd=e.work).returncode == 0


def test_refuses_a_folder_that_holds_a_repo(e):
    repo = e.work / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    r = e.run("discard", str(repo), cwd=e.work)
    assert r.returncode == 2 and "holds a repo" in r.stderr


def test_a_run_s_contents_are_exempt_from_the_repo_check(e):
    run = Path(e.run("new", "repo").stdout.strip())
    repo = run / "testrepo"
    repo.mkdir()
    git(repo, "init", "-q")
    assert e.run("discard", str(repo), cwd=e.work).returncode == 0


def test_inside_claude_a_path_older_than_the_session_needs_old(e):
    old = e.work / "old.txt"
    old.write_text("made before")
    time.sleep(1.2)
    # A process started after the file: it stands for the Claude session.
    sess = subprocess.Popen(["sleep", "30"])
    try:
        time.sleep(1.2)
        new = e.work / "new.txt"
        new.write_text("made during")
        env = {"CLAUDECODE": "1", "CLAUDE_PID": str(sess.pid), "CLAUDE_CODE_SESSION_ID": "s-1"}
        r = e.run("discard", str(old), cwd=e.work, extra=env)
        assert r.returncode == 2 and "before this session" in r.stderr
        assert e.run("discard", str(new), cwd=e.work, extra=env).returncode == 0
        assert e.run("discard", "--old", str(old), cwd=e.work, extra=env).returncode == 0
        last = e.audit()[-1]
        assert last["old"] is True and last["session"] == "s-1"
    finally:
        sess.kill()


def test_inside_claude_without_a_pid_needs_old(e):
    f = e.work / "f"
    f.write_text("x")
    r = e.run("discard", str(f), cwd=e.work, extra={"CLAUDECODE": "1"})
    assert r.returncode == 2 and "CLAUDE_PID" in r.stderr


def test_a_path_named_with_its_parent_is_refused(e):
    d = e.work / "d"
    d.mkdir()
    (d / "f").write_text("x")
    r = e.run("discard", str(d), str(d / "f"), cwd=e.work)
    assert r.returncode == 2 and "also named" in r.stderr


# --- ls and log --------------------------------------------------------------

def test_ls_and_log_show_what_happened(e):
    e.run("new", "first")
    f = e.work / "x.txt"
    f.write_text("x")
    e.run("discard", str(f), cwd=e.work)
    ls = e.run("ls").stdout
    assert "runs" in ls and "discard" in ls and str(f) in ls
    log = e.run("log", "5").stdout
    assert "new" in log and "discard" in log


# --- expire ------------------------------------------------------------------

def age(path, days):
    """Backdate a run or batch: its metadata and every file in it."""
    meta = path / ".scratch-meta.json"
    m = json.loads(meta.read_text())
    from datetime import datetime, timedelta
    m["created"] = (datetime.now().astimezone() - timedelta(days=days)).isoformat(timespec="seconds")
    meta.write_text(json.dumps(m))
    t = time.time() - days * 86400
    for dirpath, dirs, files in os.walk(path):
        for n in dirs + files:
            os.utime(os.path.join(dirpath, n), (t, t), follow_symlinks=False)
    os.utime(path, (t, t))


def test_expire_deletes_only_what_is_past_its_time(e):
    old = Path(e.run("new", "old").stdout.strip())
    young = Path(e.run("new", "young").stdout.strip())
    age(old, 15)
    age(young, 2)
    r = e.run("expire")
    assert r.returncode == 0, r.stderr
    assert not old.exists() and young.exists()
    assert any(a["action"] == "expire" and a["path"] == str(old) for a in e.audit())


def test_a_run_used_recently_is_kept_though_made_long_ago(e):
    run = Path(e.run("new", "busy").stdout.strip())
    age(run, 20)
    (run / "fresh.txt").write_text("touched today")
    e.run("expire")
    assert run.exists()


def test_a_batch_ages_from_when_it_was_made_not_from_its_files(e):
    f = e.work / "ancient.txt"
    f.write_text("x")
    t = time.time() - 100 * 86400
    os.utime(f, (t, t))
    e.run("discard", str(f), cwd=e.work)
    e.run("expire")
    assert len(e.batches()) == 1


def test_expire_dry_run_deletes_nothing(e):
    run = Path(e.run("new").stdout.strip())
    age(run, 30)
    r = e.run("expire", "--dry-run")
    assert "would delete" in r.stdout and run.exists()


def test_expire_refuses_inside_claude(e):
    run = Path(e.run("new").stdout.strip())
    age(run, 30)
    r = e.run("expire", extra={"CLAUDECODE": "1"})
    assert r.returncode == 3 and run.exists()


def test_over_the_size_cap_the_oldest_go_but_never_under_three_days(e):
    runs = []
    for days in (10, 5, 1):
        run = Path(e.run("new", f"d{days}").stdout.strip())
        (run / "blob").write_bytes(b"x" * 400_000)
        age(run, days)
        runs.append(run)
    # Cap of about 0.5 MB: the three runs hold 1.2 MB.
    r = e.run("expire", extra={"SCRATCH_MAX_GB": str(0.5 / 1024)})
    d10, d5, d1 = runs
    assert not d10.exists() and not d5.exists()
    assert d1.exists(), "younger than the 3-day floor"
    assert "over its" not in r.stderr  # 0.4 MB left: under the cap


def test_a_cap_the_floor_cannot_meet_is_reported_and_logged(e):
    run = Path(e.run("new", "young").stdout.strip())
    (run / "blob").write_bytes(b"x" * 400_000)
    age(run, 1)
    r = e.run("expire", extra={"SCRATCH_MAX_GB": str(0.1 / 1024)})
    assert run.exists()
    assert "over its" in r.stderr
    assert e.audit()[-1]["action"] == "expire-shortfall"


def test_a_run_whose_scan_does_not_finish_is_kept_and_logged(e):
    # Review finding 2: an unfinished scan may have missed today's change.
    run = Path(e.run("new", "huge").stdout.strip())
    (run / "sub").mkdir()
    age(run, 20)
    e.run("expire", extra={"SCRATCH_SCAN_SECONDS": "0"})
    assert run.exists()
    assert any(a["action"] == "expire-unsure" for a in e.audit())


def test_a_read_only_tree_is_deleted_and_never_logged_falsely(e):
    run = Path(e.run("new", "ro").stdout.strip())
    (run / "locked" / "inner").mkdir(parents=True)
    (run / "locked" / "inner" / "f").write_text("x")
    age(run, 20)
    os.chmod(run / "locked" / "inner", 0o500)
    os.chmod(run / "locked", 0o500)
    e.run("expire")
    assert not run.exists()
    assert [a["action"] for a in e.audit()].count("expire") == 1


def test_a_lost_metadata_file_does_not_make_a_batch_look_new(e):
    f = e.work / "f"
    f.write_text("x")
    e.run("discard", str(f), cwd=e.work)
    [batch] = e.batches()
    old = batch.parent / ("20200101-000000-" + batch.name.split("-", 2)[2])
    batch.rename(old)
    (old / ".scratch-meta.json").unlink()
    e.run("expire")
    assert not old.exists()


def test_old_audit_months_are_pruned(e):
    e.run("new")
    (e.root / "audit" / "2020-01.jsonl").write_text("{}\n")
    e.run("expire")
    assert not (e.root / "audit" / "2020-01.jsonl").exists()


def test_a_low_disk_is_logged_but_not_blamed_on_scratch(e):
    e.run("new")
    r = e.run("expire", extra={"SCRATCH_MIN_FREE_GB": "100000"})
    assert "over its" not in r.stderr and "free" in r.stderr
    assert e.audit()[-1]["action"] == "expire-lowdisk"


def test_log_zero_prints_nothing(e):
    e.run("new")
    assert e.run("log", "0").stdout == ""


def test_expire_without_a_root_does_nothing(e):
    r = e.run("expire")
    assert r.returncode == 0 and "nothing to do" in r.stdout
