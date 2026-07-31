"""Tests for lib/python/ccjj.py — session-scoped jj commits.

Each test names the defect it pins down. All of these were reproduced against a
working prototype before being fixed, and every one of them failed *silently*,
so a regression here would not announce itself.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time

import pytest

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CCJJ = os.path.join(DOTFILES, "lib", "python", "ccjj.py")

pytestmark = pytest.mark.skipif(shutil.which("jj") is None, reason="jj not installed")


class Repo:
    """A throwaway jj repo with an isolated journal."""

    def __init__(self, base):
        self.root = os.path.join(base, "repo")
        self.journal = os.path.join(base, "journal")
        os.makedirs(self.root)
        os.makedirs(self.journal)
        subprocess.run(["jj", "git", "init"], cwd=self.root, capture_output=True)

    def write(self, rel, data):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as fh:
            fh.write(data if isinstance(data, bytes) else data.encode())

    def read(self, rel):
        with open(os.path.join(self.root, rel), "rb") as fh:
            return fh.read()

    def commit(self, msg):
        subprocess.run(["jj", "commit", "-m", msg], cwd=self.root, capture_output=True)

    def record(self, sid, rel, old=None, new=None, original=None,
               tool="Edit", content=None, replace_all=False, seq=None):
        d = os.path.join(self.journal, self.root.replace("/", "_"), sid)
        os.makedirs(d, exist_ok=True)
        rec = {"schema": 1, "tool": tool, "path": os.path.join(self.root, rel),
               "old": old, "new": new, "content": content,
               "replace_all": replace_all, "original": original}
        n = seq if seq is not None else time.time_ns()
        with open(os.path.join(d, "%019d-0.json" % n), "w") as fh:
            json.dump(rec, fh)

    def run(self, *args, cwd=None, sid="S1", env=None, extra=()):
        return subprocess.run(
            [sys.executable, CCJJ, *args, *extra], cwd=cwd or self.root,
            capture_output=True, text=True,
            env={**os.environ, "CC_JJ_JOURNAL": self.journal,
                 "CLAUDE_SESSION_ID": sid, **(env or {})})

    def windows(self, sid):
        d = os.path.join(self.journal, self.root.replace("/", "_"), sid)
        if not os.path.isdir(d):
            return []
        return sorted(n for n in os.listdir(d) if n.endswith(".win"))

    def jj_(self, *args):
        return subprocess.run(["jj", *args], cwd=self.root,
                              capture_output=True, text=True)

    def op_head(self):
        return self.jj_("op", "log", "--no-graph", "-T", "id", "--limit", "1",
                        "--ignore-working-copy").stdout.strip()

    def divergent(self):
        return "DIVERGENT" in self.jj_(
            "log", "-r", "all()", "--no-graph", "--ignore-working-copy",
            "-T", 'if(divergent, "DIVERGENT")').stdout

    def descriptions(self):
        return self.jj_("log", "-r", "all()", "--no-graph", "--ignore-working-copy",
                        "-T", 'description ++ "\\n"').stdout

    def journal_records(self, sid):
        d = os.path.join(self.journal, self.root.replace("/", "_"), sid)
        if not os.path.isdir(d):
            return []
        return [n for n in os.listdir(d) if n.endswith(".json")]

    def show(self, rel, rev="@-"):
        # bytes, not text: text mode would decode away CRLF and choke on
        # non-UTF8 content, i.e. exactly the cases under test.
        r = subprocess.run(["jj", "file", "show", "-r", rev, 'root-file:"%s"' % rel],
                           cwd=self.root, capture_output=True)
        return r.stdout if r.returncode == 0 else None

    def is_exec(self, rel, rev="@-"):
        r = subprocess.run(
            ["jj", "file", "list", "-r", rev, "-T",
             'json(self.path()) ++ "\\t" ++ self.executable() ++ "\\n"',
             'root-file:"%s"' % rel], cwd=self.root, capture_output=True, text=True)
        for line in r.stdout.splitlines():
            raw, _, ex = line.rpartition("\t")
            if json.loads(raw) == rel:
                return ex.strip() == "true"
        return None


@pytest.fixture
def repo(tmp_path):
    return Repo(str(tmp_path))


# ------------------------------------------------------------------ happy path

def test_commits_only_this_session(repo):
    repo.write("f.txt", "a\nb\nc\n")
    repo.commit("base")
    repo.write("f.txt", "A-mine\nb\nB-theirs\n")     # two sessions, one file
    repo.record("S1", "f.txt", old="a", new="A-mine", original="a\nb\nc\n")
    repo.record("S2", "f.txt", old="c", new="B-theirs", original="A-mine\nb\nc\n")

    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"A-mine\nb\nc\n"
    # the other session's work must survive untouched on disk
    assert repo.read("f.txt") == b"A-mine\nb\nB-theirs\n"

    assert repo.run("commit", "-m", "theirs", sid="S2").returncode == 0
    assert repo.show("f.txt") == b"A-mine\nb\nB-theirs\n"


def test_diff_previews_without_committing(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    r = repo.run("commit", "--diff", sid="S1")
    assert r.returncode == 0
    assert "+A" in r.stdout
    assert repo.show("f.txt") == b"a\n"          # nothing committed


# --------------------------------------------------- placement and attribution

def test_patches_the_right_occurrence(repo):
    """Edit guarantees old_string is unique in the file it was applied to, not in
    @-. First-occurrence replacement silently patched the wrong site."""
    repo.write("f.txt", "foo\nbar\nfoo\n")        # 'foo' twice in @-
    repo.commit("base")
    repo.write("f.txt", "ZED\nbar\nMINE\n")       # another session took line 1
    repo.record("S1", "f.txt", old="foo", new="MINE", original="ZED\nbar\nfoo\n")

    assert repo.run("commit", "-m", "mine", sid="S1").returncode == 0
    assert repo.show("f.txt") == b"foo\nbar\nMINE\n"


def test_adjacent_line_edits_do_not_false_conflict(repo):
    """A line-based 3-way merge refuses this; context anchoring must not."""
    repo.write("f.txt", "a\nb\n")
    repo.commit("base")
    repo.write("f.txt", "A\nB\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\nb\n")
    repo.record("S2", "f.txt", old="b", new="B", original="A\nb\n")

    assert repo.run("commit", "-m", "s2", sid="S2").returncode == 0
    assert repo.run("commit", "-m", "s1", sid="S1").returncode == 0
    assert repo.show("f.txt") == b"A\nB\n"


def test_genuine_overlap_is_refused(repo):
    repo.write("f.txt", "shared line\n")
    repo.commit("base")
    repo.write("f.txt", "theirs\n")
    repo.commit("theirs")                          # already committed by another
    repo.write("f.txt", "mine\n")
    repo.record("S1", "f.txt", old="shared line", new="mine", original="shared line\n")

    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode != 0
    assert "conflict" in r.stderr.lower()


def test_replace_all_count_mismatch_is_refused(repo):
    """Committing would change occurrences the agent never saw."""
    repo.write("f.txt", "d\nd\nd\n")               # three in @-
    repo.commit("base")
    repo.write("f.txt", "D\nD\nD\n")
    repo.record("S1", "f.txt", old="d", new="D", replace_all=True, original="d\nd\n")

    r = repo.run("commit", "-m", "all", sid="S1")
    assert r.returncode != 0
    assert "replace-all mismatch" in r.stderr


# ----------------------------------------------------------------- silent loss

def test_refuses_when_the_commit_would_not_take(repo):
    """jj accepts payload only for paths that already differ between @- and the
    working copy. Otherwise it made an empty commit and reported success."""
    repo.write("f.txt", "b1\n")
    repo.commit("base")                            # working copy now clean
    repo.record("S1", "f.txt", tool="Write", content="MINE\n", original="b1\n")

    r = repo.run("commit", "-m", "claims", sid="S1")
    assert r.returncode != 0
    assert repo.show("f.txt") == b"b1\n"
    live = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    assert os.path.isdir(live), "journal must survive an unverified commit"


def test_works_from_a_subdirectory(repo):
    """jj filesets resolve against the CWD; root-relative paths matched nothing
    and the failure surfaced as a bogus conflict."""
    repo.write("src/app.py", "ORIGINAL\n")
    repo.commit("base")
    sub = os.path.join(repo.root, "sub")
    os.makedirs(sub, exist_ok=True)
    repo.write("src/app.py", "EDITED\n")
    repo.record("S1", "src/app.py", old="ORIGINAL", new="EDITED", original="ORIGINAL\n")

    r = repo.run("commit", "-m", "sub", cwd=sub, sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("src/app.py") == b"EDITED\n"


def test_another_sessions_chmod_does_not_leak(repo):
    """$right is seeded from the working copy, so a mode change by someone else
    landed in my commit even though I only edited content."""
    repo.write("s.sh", "one\n")
    repo.commit("base")
    repo.write("s.sh", "ONE\n")
    os.chmod(os.path.join(repo.root, "s.sh"), 0o755)   # the other session's chmod
    repo.record("S1", "s.sh", old="one", new="ONE", original="one\n")

    assert repo.run("commit", "-m", "content only", sid="S1").returncode == 0
    assert repo.show("s.sh") == b"ONE\n"
    assert repo.is_exec("s.sh") is False, "chmod belonged to another session"


def test_new_file_keeps_its_own_exec_bit(repo):
    repo.write("keep.txt", "x\n")
    repo.commit("base")
    repo.write("tool.sh", "#!/bin/sh\n")
    os.chmod(os.path.join(repo.root, "tool.sh"), 0o755)
    repo.record("S1", "tool.sh", tool="Write", content="#!/bin/sh\n")

    assert repo.run("commit", "-m", "new tool", sid="S1").returncode == 0
    assert repo.is_exec("tool.sh") is True


# ------------------------------------------------------------ bytes and naming

def test_crlf_survives_byte_exact(repo):
    repo.write("w.txt", b"alpha\r\nbeta\r\ngamma\r\n")
    repo.commit("base")
    repo.write("w.txt", b"alpha\r\nBETA\r\ngamma\r\n")
    repo.record("S1", "w.txt", old="beta", new="BETA",
                original="alpha\r\nbeta\r\ngamma\r\n")

    assert repo.run("commit", "-m", "crlf", sid="S1").returncode == 0
    assert repo.show("w.txt") == b"alpha\r\nBETA\r\ngamma\r\n"


def test_non_utf8_does_not_crash(repo):
    repo.write("b.txt", b"caf\xe9 latin1\nsecond\n")
    repo.commit("base")
    repo.write("b.txt", b"caf\xe9 latin1\nSECOND\n")
    repo.record("S1", "b.txt", old="second", new="SECOND")

    r = repo.run("commit", "-m", "bin", sid="S1")
    assert "Traceback" not in r.stderr
    assert repo.show("b.txt") == b"caf\xe9 latin1\nSECOND\n"


@pytest.mark.parametrize("name", ["a~b.txt", "x&y.txt", "g[0].txt",
                                  "paren(1).txt", "p|q.txt"])
def test_glob_metacharacter_filenames(tmp_path, name):
    """jj's default fileset pattern is a glob, so bare paths were parsed as
    expressions: wrong path, no path, or a whole-commit abort."""
    repo = Repo(str(tmp_path))
    repo.write(name, "before\n")
    repo.commit("base")
    repo.write(name, "after\n")
    repo.record("S1", name, old="before", new="after", original="before\n")

    assert repo.run("commit", "-m", "odd", sid="S1").returncode == 0, name
    assert repo.show(name) == b"after\n"


def test_out_of_repo_path_is_named_not_blamed(repo):
    """This produced a '../' fileset whose base read failed, reported as a
    nonexistent conflict, locking the session out permanently."""
    repo.write("f.txt", "x\n")
    repo.commit("base")
    outside = os.path.join(os.path.dirname(repo.root), "cfg.json")
    with open(outside, "w") as fh:
        fh.write("{}\n")
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "%019d-0.json" % time.time_ns()), "w") as fh:
        json.dump({"schema": 1, "tool": "Edit", "path": outside, "old": "{}",
                   "new": "{ }", "content": None, "replace_all": False,
                   "original": "{}\n"}, fh)

    r = repo.run("commit", "-m", "outside", sid="S1")
    assert "outside the repo" in r.stderr
    assert "conflict" not in r.stderr.lower()


# --------------------------------------------------------------------- journal

def test_records_replay_regardless_of_filename_order(repo):
    """Each record carries its own pre-edit content, so ordering is no longer
    load-bearing -- concurrent hooks used to scramble it."""
    repo.write("f.txt", "v0\n")
    repo.commit("base")
    repo.write("f.txt", "v3\n")
    repo.record("S1", "f.txt", old="v2", new="v3", original="v2\n", seq=3)
    repo.record("S1", "f.txt", old="v0", new="v1", original="v0\n", seq=1)
    repo.record("S1", "f.txt", old="v1", new="v2", original="v1\n", seq=2)

    assert repo.run("commit", "-m", "chained", sid="S1").returncode == 0
    assert repo.show("f.txt") == b"v3\n"


def test_large_write_record_survives(repo):
    """A 64KB Write used to interleave into a shared .jsonl and corrupt it."""
    repo.write("g.txt", "small\n")
    repo.commit("base")
    big = "X" * 200_000
    repo.write("g.txt", big)
    repo.record("S1", "g.txt", tool="Write", content=big, original="small\n")

    assert repo.run("commit", "-m", "big", sid="S1").returncode == 0
    assert repo.show("g.txt") == big.encode()


def test_journal_is_archived_only_after_verification(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")

    assert repo.run("commit", "-m", "ok", sid="S1").returncode == 0
    key = os.path.join(repo.journal, repo.root.replace("/", "_"))
    assert not os.path.isdir(os.path.join(key, "S1"))
    archived = [d for d, _, f in os.walk(os.path.join(key, "archive")) if f]
    assert archived, "records should be archived, not deleted"
    # a second run has nothing left to do
    assert repo.run("commit", "-m", "again", sid="S1").returncode == 2


# ----------------------------------------------------------------- concurrency

def test_concurrent_commits_never_diverge(repo):
    """Two concurrent `jj commit` runs created a divergent change: both printed
    success, both exited 0, one commit landed on a dangling head."""
    repo.write("f.txt", "a\nb\n")
    repo.commit("base")
    repo.write("f.txt", "A\nB\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\nb\n")
    repo.record("S2", "f.txt", old="b", new="B", original="A\nb\n")

    out = {}
    threads = [threading.Thread(target=lambda s=s: out.__setitem__(s, repo.run(
        "commit", "-m", s, sid=s))) for s in ("S1", "S2")]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    log = subprocess.run(
        ["jj", "log", "-r", "all()", "--no-graph", "-T",
         'change_id.short() ++ if(divergent," DIVERGENT","") ++ "\\n"'],
        cwd=repo.root, capture_output=True, text=True).stdout
    assert "DIVERGENT" not in log, log
    # one may lose the race and be told to retry, but neither may lose work
    assert sorted(v.returncode for v in out.values()) in ([0, 0], [0, 4])
    if all(v.returncode == 0 for v in out.values()):
        assert repo.show("f.txt") == b"A\nB\n"


# --------------------------------------------------------------- --also, audit

def test_also_takes_whole_paths(repo):
    repo.write("keep.txt", "p\n")
    repo.write("gone.txt", "bye\n")
    repo.commit("base")
    repo.write("keep.txt", "P\n")
    os.remove(os.path.join(repo.root, "gone.txt"))
    repo.record("S1", "keep.txt", old="p", new="P", original="p\n")

    r = repo.run("commit", "-m", "with delete", "--also", "gone.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("gone.txt") is None
    assert repo.show("keep.txt") == b"P\n"


def test_audit_reports_unclaimed_paths(repo):
    repo.write("f.txt", "a\n")
    repo.write("stray.txt", "s\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.write("stray.txt", "CHANGED-BY-NOBODY\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")

    r = repo.run("audit", sid="S1")
    assert r.returncode == 0
    assert "stray.txt" in r.stderr
    assert "f.txt" not in r.stderr.replace("stray.txt", "")


def test_audit_porcelain_is_nul_separated(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    r = repo.run("audit", "--porcelain", sid="S1")
    assert r.stdout.split("\0") == ["f.txt"]


# ------------------------------------------------------------------ hook input

@pytest.mark.parametrize("payload", ["", "not json", "{}", '{"tool_name":"Bash"}'])
def test_record_edit_tolerates_bad_input(tmp_path, payload):
    """The recorder must never fail an agent's tool call."""
    journal = str(tmp_path / "j")
    r = subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                       capture_output=True, text=True,
                       env={**os.environ, "CC_JJ_JOURNAL": journal})
    assert r.returncode == 0
    assert not os.path.isdir(journal) or not os.listdir(journal)


def test_record_edit_ignores_a_failed_edit(tmp_path):
    """No structuredPatch means the Edit did not take; a phantom record would be
    replayed into a commit."""
    repo = Repo(str(tmp_path))
    repo.write("f.txt", "a\n")
    repo.commit("base")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1",
        "tool_input": {"file_path": os.path.join(repo.root, "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {},
    })
    r = subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                       capture_output=True, text=True,
                       env={**os.environ, "CC_JJ_JOURNAL": repo.journal})
    assert r.returncode == 0
    assert not os.path.isdir(os.path.join(repo.journal,
                                          repo.root.replace("/", "_"), "S1"))


def test_record_edit_writes_a_usable_record(tmp_path):
    repo = Repo(str(tmp_path))
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1", "tool_use_id": "toolu_x",
        "tool_input": {"file_path": os.path.join(repo.root, "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})
    # and the record it wrote is enough to commit from
    assert repo.run("commit", "-m", "hooked", sid="S1").returncode == 0
    assert repo.show("f.txt") == b"A\n"


# ---------------------------------------------------------------- liveness

def _owner(repo, sid, pid, lstart):
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), sid)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, ".owner"), "w") as fh:
        fh.write("%s\t%s\n" % (pid, lstart))


def _my_lstart():
    return subprocess.run(["ps", "-o", "lstart=", "-p", str(os.getpid())],
                          capture_output=True, text=True).stdout.strip()


def test_dead_session_claims_do_not_suppress_the_warning(repo):
    """A dead session's paths are exactly what you want to hear about --
    nobody is going to commit them."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    # pid 1 exists but its start time will not match, so the owner is gone
    _owner(repo, "S1", "1", "Thu Jan  1 00:00:00 2000")

    r = repo.run("audit", sid="S2")
    assert "f.txt" in r.stderr, r.stdout + r.stderr
    assert "ended, never committed" in r.stdout


def test_live_session_claims_suppress_the_warning(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "S1", str(os.getpid()), _my_lstart())

    r = repo.run("audit", sid="S2")
    assert "claimed by no session" not in r.stderr
    assert "(live)" in r.stdout


def test_prune_retires_orphaned_journals_but_not_live_ones(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("DEAD", "f.txt", old="a", new="A", original="a\n")
    repo.record("LIVE", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "DEAD", "1", "Thu Jan  1 00:00:00 2000")
    _owner(repo, "LIVE", str(os.getpid()), _my_lstart())
    key = os.path.join(repo.journal, repo.root.replace("/", "_"))
    # age the dead one past --stale-days
    old = time.time() - 5 * 24 * 3600
    for n in os.listdir(os.path.join(key, "DEAD")):
        os.utime(os.path.join(key, "DEAD", n), (old, old))

    r = repo.run("prune", "--stale-days", "2", sid="S1")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(os.path.join(key, "DEAD")), "orphan should be retired"
    assert os.path.isdir(os.path.join(key, "LIVE")), "live journal must survive"


def test_recent_orphan_is_left_alone(repo):
    """Owner gone but the journal is fresh -- the session may have just crashed
    and the work is still recoverable."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("DEAD", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "DEAD", "1", "Thu Jan  1 00:00:00 2000")
    key = os.path.join(repo.journal, repo.root.replace("/", "_"))

    repo.run("prune", "--stale-days", "2", sid="S1")
    assert os.path.isdir(os.path.join(key, "DEAD"))


def test_disown_retires_a_journal_by_hand(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    key = os.path.join(repo.journal, repo.root.replace("/", "_"))

    r = repo.run("disown", "S1", sid="S2")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(os.path.join(key, "S1"))


def test_record_edit_stamps_an_owner(tmp_path):
    repo = Repo(str(tmp_path))
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1",
        "tool_input": {"file_path": os.path.join(repo.root, "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal,
                        "CLAUDE_PID": str(os.getpid())})
    owner = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1", ".owner")
    assert os.path.isfile(owner)
    pid, _, lstart = open(owner).read().strip().partition("\t")
    assert pid == str(os.getpid()) and lstart


# ------------------------------------------------- base drift (stray commits)

def _base(repo, sid, value):
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), sid)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, ".base"), "w") as fh:
        fh.write(value)


def _parent_id(repo):
    return subprocess.run(["jj", "log", "--no-graph", "-T", "commit_id", "-r", "@-",
                           "--ignore-working-copy"], cwd=repo.root,
                          capture_output=True, text=True).stdout.strip()


def test_audit_notices_a_stray_jj_new(repo):
    """A stray `jj new` sweeps the work into an unnamed commit and empties the
    @- vs @ delta, so audit used to print 'all clear' at the worst moment."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "EDITED\n")
    repo.record("S1", "f.txt", old="a", new="EDITED", original="a\n")
    _owner(repo, "S1", str(os.getpid()), _my_lstart())
    _base(repo, "S1", _parent_id(repo))

    subprocess.run(["jj", "new"], cwd=repo.root, capture_output=True)

    r = repo.run("audit", sid="S1")
    assert "@- has moved" in r.stderr, r.stdout + r.stderr
    assert "every changed path is claimed" not in r.stdout


def test_audit_is_quiet_when_ccjj_moved_the_base(repo):
    """Our own commit must not read as someone else moving the base."""
    repo.write("f.txt", "a\n")
    repo.write("g.txt", "x\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.write("g.txt", "X\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    repo.record("S2", "g.txt", old="x", new="X", original="x\n")
    for s in ("S1", "S2"):
        _owner(repo, s, str(os.getpid()), _my_lstart())
        _base(repo, s, _parent_id(repo))

    assert repo.run("commit", "-m", "s1", sid="S1").returncode == 0
    r = repo.run("audit", sid="S2")
    assert "@- has moved" not in r.stderr, r.stdout + r.stderr


def test_record_edit_stamps_a_base(tmp_path):
    repo = Repo(str(tmp_path))
    repo.write("f.txt", "a\n")
    repo.commit("base")
    expected = _parent_id(repo)
    repo.write("f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1",
        "tool_input": {"file_path": os.path.join(repo.root, "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    assert open(os.path.join(d, ".base")).read().strip() == expected


# ----------------------------------------------------------------- the nudge

def _nudge(repo, cwd, sid):
    payload = json.dumps({"cwd": cwd, "session_id": sid})
    return subprocess.run([sys.executable, CCJJ, "nudge"], input=payload,
                          capture_output=True, text=True,
                          env={**os.environ, "CC_JJ_JOURNAL": repo.journal})


def test_nudge_is_silent_with_no_other_session(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "S1", str(os.getpid()), _my_lstart())

    r = _nudge(repo, repo.root, "S1")     # my own journal must not nag me
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_nudge_fires_for_another_live_session(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("OTHER", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "OTHER", str(os.getpid()), _my_lstart())

    r = _nudge(repo, repo.root, "ME")
    out = json.loads(r.stdout)
    ctx = out["hookSpecificOutput"]["additionalContext"]
    assert "commit-mine" in ctx
    assert out["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"


def test_nudge_ignores_a_dead_session(repo):
    """Without liveness this would fire forever after any session that did not
    commit with ccjj -- one line of noise on every prompt, until ignored."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("OTHER", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "OTHER", "1", "Thu Jan  1 00:00:00 2000")

    assert _nudge(repo, repo.root, "ME").stdout.strip() == ""


def test_nudge_is_silent_outside_a_jj_repo(tmp_path):
    repo = Repo(str(tmp_path))
    plain = str(tmp_path / "plain")
    os.makedirs(plain)
    r = _nudge(repo, plain, "ME")
    assert r.returncode == 0 and r.stdout.strip() == ""


@pytest.mark.parametrize("payload", ["", "not json", "{}"])
def test_nudge_tolerates_bad_input(tmp_path, payload):
    r = subprocess.run([sys.executable, CCJJ, "nudge"], input=payload,
                       capture_output=True, text=True,
                       env={**os.environ, "CC_JJ_JOURNAL": str(tmp_path)})
    assert r.returncode == 0
    assert r.stdout.strip() == ""


# ------------------------------------------------------- routing / interop

def test_should_scope_declines_when_alone(repo):
    """A lone session is better off with a whole-copy commit -- that also
    captures Bash-made changes ccjj cannot see."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "S1", str(os.getpid()), _my_lstart())

    assert repo.run("should-scope", "-q", sid="S1").returncode == 1


def test_should_scope_accepts_when_another_session_is_live(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    repo.record("OTHER", "f.txt", old="a", new="A", original="a\n")
    for s in ("S1", "OTHER"):
        _owner(repo, s, str(os.getpid()), _my_lstart())

    assert repo.run("should-scope", "-q", sid="S1").returncode == 0


def test_should_scope_declines_with_no_records_of_my_own(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("OTHER", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "OTHER", str(os.getpid()), _my_lstart())

    assert repo.run("should-scope", "-q", sid="NEW").returncode == 1


def test_retire_all_clears_every_journal(repo):
    """After a deliberate whole-copy commit every claim is in history; leaving
    them live would wedge the nudge on permanently."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    repo.record("S2", "f.txt", old="a", new="A", original="a\n")
    key = os.path.join(repo.journal, repo.root.replace("/", "_"))

    assert repo.run("retire-all", sid="S1").returncode == 0
    assert not os.path.isdir(os.path.join(key, "S1"))
    assert not os.path.isdir(os.path.join(key, "S2"))
    assert os.path.isdir(os.path.join(key, "archive"))


def test_commit_releases_the_shared_lock(repo):
    """ai_jj_commit and ccjj now share one lockdir; a leaked one wedges both
    tools for 30 minutes."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")

    assert repo.run("commit", "-m", "x", sid="S1").returncode == 0
    lockdir = os.path.expanduser(
        "~/.local/state/ai-jj-commit/%s.lock" % repo.root.replace("/", "_"))
    assert not os.path.exists(lockdir)


def test_diff_mode_also_releases_the_lock(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")

    assert repo.run("commit", "--diff", sid="S1").returncode == 0
    lockdir = os.path.expanduser(
        "~/.local/state/ai-jj-commit/%s.lock" % repo.root.replace("/", "_"))
    assert not os.path.exists(lockdir)


def test_commit_refuses_while_the_shared_lock_is_held(repo):
    """A `g run ci` in flight must make a session commit back off, not race it."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    lockdir = os.path.expanduser(
        "~/.local/state/ai-jj-commit/%s.lock" % repo.root.replace("/", "_"))
    os.makedirs(lockdir, exist_ok=True)
    with open(os.path.join(lockdir, "pid"), "w") as fh:
        fh.write("%d %s\n" % (os.getpid(), _my_lstart()))
    try:
        r = repo.run("commit", "-m", "x", sid="S1")
        assert r.returncode == 4, r.stderr
        assert "in progress" in r.stderr
    finally:
        shutil.rmtree(lockdir, ignore_errors=True)


# ------------------------------------- commit-path failures that were silent
#
# All four were found by an adversarial review of the Phase 2 plan, and all four
# affect `commit-mine` today. See .cc/PLAN-ccjj-bash-windows.md, "Live bugs".

def test_merge_working_copy_is_refused(repo):
    """`jj log -T commit_id -r @-` on a merge exits 0 and CONCATENATES both
    parents into one 80-char string, so the returncode-gated guard never fired
    and `pinned` became nonsense."""
    repo.write("f.txt", "a\n")
    repo.commit("A")
    a = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", a)
    repo.write("g.txt", "b\n")
    repo.commit("B")
    b = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", a)
    repo.write("h.txt", "c\n")
    repo.commit("C")
    c = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", b, c)                      # @ is now a merge

    repo.write("f.txt", "a2\n")
    repo.record("S1", "f.txt", old="a", new="a2", original="a\n")
    r = repo.run("commit", "-m", "into a merge", sid="S1")

    assert r.returncode == 4, r.stderr        # retryable, not a hard refusal
    assert "merge" in r.stderr.lower()
    # and the journal survives so it can be retried after the merge is resolved
    assert repo.journal_records("S1")


def test_failed_commit_rolls_back_and_keeps_the_journal(repo, tmp_path):
    """A failed `jj commit` is NOT a no-op: a racing `jj util snapshot` leaves
    the commit on a dangling head and the repo DIVERGENT. The old code die()d
    before reaching any rollback."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "a2\n")
    repo.record("S1", "f.txt", old="a", new="a2", original="a\n")

    # A jj that fails the way a concurrent checkout does: the commit PARTLY
    # LANDS and then it dies. Failing before doing anything would leave nothing
    # to roll back, so the test would pass with or without the restore --
    # verified by mutation, that version survived deleting the fix.
    stub = tmp_path / "stub"
    stub.mkdir()
    real = shutil.which("jj")
    (stub / "jj").write_text(
        "#!/bin/sh\n"
        'for a in "$@"; do\n'
        '  if [ "$a" = "--tool=ccjj" ]; then\n'
        '    %s "$@" >/dev/null 2>&1\n'
        '    echo "Internal error: Failed to check out commit" >&2\n'
        '    echo "Caused by: Concurrent checkout" >&2\n'
        '    exit 255\n'
        '  fi\n'
        'done\n'
        'exec %s "$@"\n' % (real, real))
    (stub / "jj").chmod(0o755)

    r = repo.run("commit", "-m", "doomed", sid="S1",
                 env={"PATH": str(stub) + os.pathsep + os.environ["PATH"]})

    assert r.returncode == 4, r.stderr
    assert "rolled back" in r.stderr
    # `jj op restore` makes a NEW operation, so the op id is expected to differ.
    # What must hold is the state: no divergence, no stray commit, nothing in @-.
    assert not repo.divergent()
    assert "doomed" not in repo.descriptions()
    assert repo.show("f.txt") == b"a\n"        # nothing landed in @-
    assert repo.journal_records("S1")          # and the work is still claimable


def test_empty_commit_is_refused_and_rolled_back(repo):
    """The byte check only notices failure when the payload DIFFERS from @-, so
    a reconstruction that coincidentally equals @- verified clean, banked an
    empty commit under the message, and consumed the journal."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "theirs\n")            # another session's uncommitted work
    # S1's replay reproduces @- exactly, so there is nothing of its own to commit
    repo.record("S1", "f.txt", old="a\n", new="a\n", original="a\n")

    r = repo.run("commit", "-m", "nothing of mine", sid="S1")

    assert r.returncode == 2, r.stderr
    assert "empty" in r.stderr.lower()
    assert not repo.divergent()
    assert "nothing of mine" not in repo.descriptions()   # no empty commit banked
    assert repo.journal_records("S1")          # NOT archived
    assert repo.read("f.txt") == b"theirs\n"   # their work untouched on disk


# ------------------------------------------------- bash windows (the offer)
#
# Windows are NEVER attributed automatically: a window's delta is a whole-copy
# diff, so it contains every write that landed inside it. `audit` offers them
# and `claim` requires a reader to accept the diff.

def _bash(repo, sid="S1", tuid="t1", path_prepend=None):
    """One PostToolUse(Bash) hook call."""
    payload = json.dumps({"tool_name": "Bash", "session_id": sid,
                          "cwd": repo.root, "tool_use_id": tuid})
    env = {**os.environ, "CC_JJ_JOURNAL": repo.journal}
    if path_prepend:
        env["PATH"] = path_prepend + os.pathsep + env["PATH"]
    return subprocess.run(
        [sys.executable, CCJJ, "bash-window"], input=payload, cwd=repo.root,
        capture_output=True, text=True, env=env)


def _counting_jj(tmp_path):
    """A jj on PATH that logs every invocation. Returns (dir, logfile)."""
    stub = tmp_path / "stub"
    stub.mkdir(exist_ok=True)
    log = tmp_path / "jj-calls"
    (stub / "jj").write_text('#!/bin/sh\necho called >> "%s"\nexec %s "$@"\n'
                             % (log, shutil.which("jj")))
    (stub / "jj").chmod(0o755)
    return str(stub), log


def _optin(repo):
    open(os.path.join(repo.root, ".jj", "ccjj-bash"), "w").close()


def test_bash_window_is_inert_without_optin(repo, tmp_path):
    """The gate is the whole cost story: this hook runs on every Bash call in
    every project, so a non-opted-in checkout must not even start jj."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)                                  # would-be baseline
    repo.write("f.txt", "sed-made\n")            # a real change to notice
    stub, log = _counting_jj(tmp_path)
    _bash(repo, path_prepend=stub)

    assert not repo.windows("S1")
    assert not log.exists()                      # not one jj process


def test_bash_window_first_call_only_baselines(repo, tmp_path):
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    assert repo.windows("S1") == []          # nothing to bound it against
    repo.write("f.txt", "sed-made\n")
    stub, log = _counting_jj(tmp_path)
    _bash(repo, path_prepend=stub)
    assert len(repo.windows("S1")) == 1
    # ...and the opted-in path snapshots in ONE process, not snapshot-then-read
    assert len(log.read_text().split()) == 1


def test_audit_offers_a_bash_change_and_claim_commits_it(repo):
    _optin(repo)
    repo.write("s.sh", "one\ntwo\nthree\n")
    repo.commit("base")
    _bash(repo)
    repo.write("s.sh", "one\nTWO-via-sed\nthree\n")   # a Bash-made content change
    _bash(repo)

    a = repo.run("audit", sid="S1")
    assert "s.sh" in a.stderr
    assert "ccjj claim s.sh" in a.stderr              # offered, not attributed

    # nothing is committable until the offer is accepted
    assert repo.run("commit", "-m", "x", sid="S1").returncode == 2

    c = repo.run("claim", "s.sh", sid="S1")
    assert c.returncode == 0, c.stderr
    assert "+TWO-via-sed" in c.stdout                 # the diff is shown

    assert repo.run("commit", "-m", "sed change", sid="S1").returncode == 0
    assert repo.show("s.sh") == b"one\nTWO-via-sed\nthree\n"


def test_claim_preserves_another_sessions_uncommitted_work(repo):
    """The point of the whole tool: claiming a Bash change must not sweep up an
    unrelated file another session is still working on."""
    _optin(repo)
    repo.write("mine.sh", "a\n")
    repo.write("theirs.txt", "t\n")
    repo.commit("base")
    _bash(repo)
    repo.write("mine.sh", "a-sed\n")
    repo.write("theirs.txt", "their half-written work\n")
    _bash(repo)

    assert repo.run("claim", "mine.sh", sid="S1").returncode == 0
    # theirs.txt also changed inside S1's window -- a window is a whole-copy
    # diff -- so the commit now stops rather than quietly leaving it behind.
    # --no-claim is how you say "commit only what I actually claimed".
    assert repo.run("commit", "-m", "mine", sid="S1").returncode == 5
    assert repo.run("commit", "-m", "mine", sid="S1",
                    extra=["--no-claim"]).returncode == 0
    assert repo.show("mine.sh") == b"a-sed\n"
    assert repo.show("theirs.txt") == b"t\n"          # NOT committed
    assert repo.read("theirs.txt") == b"their half-written work\n"


def test_claim_refuses_a_new_symlink(repo):
    """`jj file show` exits 0 with EMPTY stdout for a symlink, so claiming one
    would write a zero-byte regular file over it -- and the byte verification
    would compare b'' to b'' and pass."""
    _optin(repo)
    repo.write("target.txt", "real\n")
    repo.commit("base")
    _bash(repo)
    os.symlink("target.txt", os.path.join(repo.root, "link"))
    _bash(repo)

    r = repo.run("claim", "link", sid="S1")
    assert r.returncode == 1
    assert "symlink" in r.stderr
    assert not repo.journal_records("S1")


def test_claim_refuses_a_retargeted_symlink(repo):
    """The one the endpoint re-check cannot catch: both ends read as b'', so
    without the entry-type check the narrowing sees 'no change' and reports the
    wrong reason for refusing."""
    _optin(repo)
    repo.write("a.txt", "one\n")
    repo.write("b.txt", "two\n")
    os.symlink("a.txt", os.path.join(repo.root, "link"))
    repo.commit("base")
    _bash(repo)
    os.remove(os.path.join(repo.root, "link"))
    os.symlink("b.txt", os.path.join(repo.root, "link"))
    _bash(repo)

    r = repo.run("claim", "link", sid="S1")
    assert r.returncode == 1
    assert "symlink" in r.stderr
    assert not repo.journal_records("S1")


def test_claim_does_not_resolve_symlinks_in_the_path(repo):
    """rel() realpaths, which is right for an Edit and wrong here: it silently
    retargets the claim at a different file."""
    _optin(repo)
    repo.write("real.txt", "content\n")
    repo.commit("base")
    os.symlink("real.txt", os.path.join(repo.root, "alias"))
    _bash(repo)
    repo.write("real.txt", "changed\n")
    _bash(repo)

    # `alias` is a symlink entry in its own right, so it must be refused as one
    # rather than quietly claimed as `real.txt`.
    r = repo.run("claim", "alias", sid="S1")
    assert r.returncode != 0
    assert "real.txt" not in r.stdout


def test_claim_refuses_a_symlink_partway_through_the_window(repo):
    """The span-level entry type is read at the LAST boundary, but the claim is
    narrowed to the tightest run that changed -- which can end earlier. Here the
    span ends on an empty regular file (so the span check passes) while the
    narrowed endpoint is a symlink, and only the endpoint re-check sees it."""
    _optin(repo)
    repo.write("thing", "content\n")
    repo.commit("base")
    _bash(repo)
    os.remove(os.path.join(repo.root, "thing"))
    os.symlink("elsewhere", os.path.join(repo.root, "thing"))
    _bash(repo)                                   # boundary 1: a symlink
    os.remove(os.path.join(repo.root, "thing"))
    repo.write("thing", "")                       # boundary 2: an EMPTY file
    _bash(repo)

    r = repo.run("claim", "thing", sid="S1")
    assert r.returncode == 1
    assert "symlink" in r.stderr
    assert not repo.journal_records("S1")


def test_claim_refuses_a_deletion_and_points_at_also(repo):
    _optin(repo)
    repo.write("gone.txt", "bye\n")
    repo.commit("base")
    _bash(repo)
    os.remove(os.path.join(repo.root, "gone.txt"))
    _bash(repo)

    r = repo.run("claim", "gone.txt", sid="S1")
    assert r.returncode == 1
    assert "--also" in r.stderr


def test_claim_refuses_when_the_session_also_edited_the_file(repo):
    """The claimed blob already contains those edits, so replaying both would
    apply them twice -- silently duplicating a hunk for an insertion-shaped
    Edit, which is the commonest shape."""
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    repo.write("f.txt", "a\nadded-by-edit\n")
    repo.record("S1", "f.txt", old="a\n", new="a\nadded-by-edit\n", original="a\n")
    _bash(repo)

    r = repo.run("claim", "f.txt", sid="S1")
    assert r.returncode == 1
    assert "twice" in r.stderr


def test_claim_warns_when_a_live_session_shares_the_path(repo):
    """A window's delta is a whole-copy diff, so it carries the other session's
    bytes. Claiming it unforced would commit their work under your name."""
    _optin(repo)
    repo.write("shared.txt", "base\n")
    repo.commit("base")
    _bash(repo, sid="S1")
    repo.write("shared.txt", "base\ntheirs\n")
    repo.record("S2", "shared.txt", old="base\n", new="base\ntheirs\n",
                original="base\n")
    _bash(repo, sid="S1")

    r = repo.run("claim", "shared.txt", sid="S1")
    assert r.returncode == 1
    assert "under your name" in r.stderr
    assert not repo.journal_records("S1")

    forced = repo.run("claim", "shared.txt", sid="S1", extra=["--force"])
    assert forced.returncode == 0


def test_claim_round_trips_non_utf8_content(repo):
    """Window content comes off disk, not out of a JSON tool payload, so it need
    not be UTF-8. Records store it base64 for exactly this reason."""
    _optin(repo)
    repo.write("bin.dat", b"\x00\x01\x02 base\n")
    repo.commit("base")
    _bash(repo)
    repo.write("bin.dat", b"\xff\xfe binary \x00 changed\n")
    _bash(repo)

    assert repo.run("claim", "bin.dat", sid="S1").returncode == 0
    assert repo.run("commit", "-m", "binary", sid="S1").returncode == 0
    assert repo.show("bin.dat") == b"\xff\xfe binary \x00 changed\n"


# ------------------------------------------------ naming the undo operation

def test_drift_names_an_operation_that_actually_undoes_it(repo):
    """The alarm already fires when something else moves @-. This asserts it
    hands over a `jj op restore` that WORKS -- by running it and checking the
    repo comes back -- rather than telling you to go read `jj op log`."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    base = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                    "--ignore-working-copy").stdout.strip()
    repo.write("mine.txt", "session work in flight\n")
    repo.record("S1", "mine.txt", tool="Write", content="session work in flight\n")
    # stamp .base the way the record-edit hook does
    jdir = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    with open(os.path.join(jdir, ".base"), "w") as fh:
        fh.write(base)

    repo.commit("a stray commit by someone else")     # sweeps mine.txt up
    assert repo.show("mine.txt") is not None          # it really did get swept

    r = repo.run("audit", sid="S1")
    assert "@- has moved" in r.stderr
    assert "was moved by operation" in r.stderr

    m = re.search(r"jj op restore (\w+)", r.stderr)
    assert m, r.stderr
    assert repo.jj_("op", "restore", m.group(1)).returncode == 0

    # back where the session started, and its work is uncommitted again
    now = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                   "--ignore-working-copy").stdout.strip()
    assert now == base
    assert repo.show("mine.txt") is None
    assert repo.read("mine.txt") == b"session work in flight\n"


# --------------------------------------------- review findings (second pass)
#
# Found by an adversarial code review of the Bash-window work. Three were
# critical; two of those were the SAME defect as an earlier fix, left standing
# in a sibling call site.

def test_write_without_a_base_over_existing_content_is_refused(repo):
    """CRITICAL. A claimed window whose path was absent at the window's start
    has original=None. Taking it wholesale REVERTED a commit another session
    landed in between -- exit 0, verification passing -- and the diff `claim`
    printed was against b'', so the reader was never shown what would die."""
    repo.write("f.txt", "THEIRS-IMPORTANT\n")
    repo.commit("theirs")
    repo.write("f.txt", "regenerated-by-my-script\n")
    repo.record("S1", "f.txt", tool="Write",
                content="regenerated-by-my-script\n", original=None)

    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode != 0
    assert "did not exist when your change began" in r.stderr
    assert repo.show("f.txt") == b"THEIRS-IMPORTANT\n"      # history intact


def _merge_wc(repo):
    repo.write("f.txt", "a\n")
    repo.commit("A")
    a = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", a); repo.write("g.txt", "b\n"); repo.commit("B")
    b = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", a); repo.write("h.txt", "c\n"); repo.commit("C")
    c = repo.jj_("log", "--no-graph", "-T", "commit_id", "-r", "@-",
                 "--ignore-working-copy").stdout.strip()
    repo.jj_("new", b, c)


def test_audit_refuses_on_a_merge_instead_of_reporting_all_clear(repo):
    """CRITICAL. survey() read @- with the same bare `commit_id` template that
    was fixed in cmd_commit: on a merge it exits 0 with both parents
    CONCATENATED, the diff then matches nothing, and audit -- the thing the
    whole design leans on -- reported 'nothing unclaimed'."""
    _merge_wc(repo)
    repo.write("stray.txt", "claimed by nobody\n")

    r = repo.run("audit", sid="S1")
    assert r.returncode == 4, r.stdout + r.stderr
    assert "merge" in r.stderr.lower()
    assert "nothing unclaimed" not in r.stdout


def test_stamp_base_declines_on_a_merge(repo):
    """.base is written ONCE, so an 80-char value is permanent: phantom drift
    forever, and drift_undo() can never match it."""
    _merge_wc(repo)
    payload = json.dumps({"tool_name": "Edit", "session_id": "S1",
                          "cwd": repo.root,
                          "tool_input": {"file_path": os.path.join(repo.root, "f.txt"),
                                         "old_string": "a", "new_string": "A"},
                          "tool_response": {"originalFile": "a\n",
                                            "structuredPatch": [1]}})
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   cwd=repo.root, capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})
    jdir = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    base = os.path.join(jdir, ".base")
    assert not os.path.exists(base) or len(open(base).read().strip()) == 40


def test_claim_warns_about_a_bash_only_peer(repo):
    """CRITICAL. other_live_sessions() required a .json, so a peer doing only
    Bash work was invisible -- and in an opted-in contended checkout that is the
    likeliest peer there is. Its work was claimable with no warning at all."""
    _optin(repo)
    repo.write("shared.txt", "base\n")
    repo.commit("base")
    _bash(repo, sid="S1")
    _bash(repo, sid="S2")
    repo.write("shared.txt", "base\nfrom-S2\n")     # the peer's Bash-made change
    _bash(repo, sid="S2")
    _bash(repo, sid="S1")

    r = repo.run("claim", "shared.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "under your name" in r.stderr
    assert not repo.journal_records("S1")

    a = repo.run("audit", sid="S1")
    assert "also inside session" in a.stderr       # both coverers named


def test_second_commit_in_a_day_archives_the_journal(repo):
    """The archive path used `not os.path.exists(dest)` and silently did
    nothing on a session's SECOND commit of the day. The third then replayed
    already-committed records, jj selected nothing, and it failed for good."""
    repo.write("g.txt", "a\n")
    repo.commit("base")
    for prev, cur, msg in (("a", "b", "first"), ("b", "c", "second"),
                           ("c", "d", "third")):
        repo.write("g.txt", cur + "\n")
        repo.record("S1", "g.txt", old=prev, new=cur, original=prev + "\n")
        r = repo.run("commit", "-m", msg, sid="S1")
        assert r.returncode == 0, "%s: %s" % (msg, r.stderr)
        assert not repo.journal_records("S1"), "%s left records live" % msg
    assert repo.show("g.txt") == b"d\n"


def test_empty_check_fails_closed(repo, tmp_path):
    """`== "true"` alone meant ANY failure of that one jj call silently reopened
    the hole the guard exists to close."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "theirs\n")
    repo.record("S1", "f.txt", old="a\n", new="a\n", original="a\n")

    stub = tmp_path / "stub"
    stub.mkdir()
    real = shutil.which("jj")
    (stub / "jj").write_text(
        "#!/bin/sh\n"
        'for a in "$@"; do [ "$a" = "empty" ] && exit 3; done\n'
        'exec %s "$@"\n' % real)
    (stub / "jj").chmod(0o755)

    r = repo.run("commit", "-m", "nothing of mine", sid="S1",
                 env={"PATH": str(stub) + os.pathsep + os.environ["PATH"]})
    assert r.returncode != 0
    assert "empty" in r.stderr.lower()
    assert "nothing of mine" not in repo.descriptions()
    assert repo.journal_records("S1")


def test_nudge_never_clears_the_contention_marker(repo):
    """`others` is relative to the prompting session, so clearing here made two
    sessions fight: the established one deleted the marker because the new peer
    had no journal yet, and the peer could not record a window to get one until
    the marker existed."""
    _optin(repo)
    busy = os.path.join(repo.root, ".jj", "ccjj-contended")
    open(busy, "w").close()
    payload = json.dumps({"session_id": "S1", "cwd": repo.root})
    subprocess.run([sys.executable, CCJJ, "nudge"], input=payload, cwd=repo.root,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})
    assert os.path.exists(busy)


def test_audit_backs_off_while_a_commit_is_in_flight(repo):
    """survey() snapshots, and a snapshot inside another session's
    `jj commit --tool` kills it with Concurrent checkout -- while the nudge
    tells every agent to run `ccjj audit`."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    lockdir = os.path.expanduser(
        "~/.local/state/ai-jj-commit/%s.lock" % repo.root.replace("/", "_"))
    os.makedirs(lockdir, exist_ok=True)
    try:
        r = repo.run("audit", sid="S1")
        assert r.returncode == 4, r.stdout + r.stderr
        assert "in progress" in r.stderr
    finally:
        shutil.rmtree(lockdir, ignore_errors=True)


# ------------------------------------------- test-drive findings (third pass)

def test_a_stale_record_is_not_applied_twice(repo):
    """CRITICAL. An external commit consumes a path but does not retire the
    record, so the next commit replays it. When `old` is a SUBSTRING of `new`
    -- extending an identifier, the commonest edit shape -- the replacement
    re-fires on its own output and commits text that existed NOWHERE."""
    repo.write("g.txt", "g1\ng2\ng3\n")
    repo.commit("base")
    repo.write("g.txt", "g1\ng2-S\ng3\n")
    repo.record("S1", "g.txt", old="g2", new="g2-S", original="g1\ng2\ng3\n")
    repo.jj_("commit", "g.txt", "-m", "a hand fix by someone else")   # external
    repo.write("g.txt", "g1-S\ng2-S\ng3\n")
    repo.record("S1", "g.txt", old="g1", new="g1-S", original="g1\ng2-S\ng3\n")

    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("g.txt") == b"g1-S\ng2-S\ng3\n"      # NOT g2-S-S
    assert repo.show("g.txt") == repo.read("g.txt")       # history matches disk
    assert "already in @-" in r.stderr                    # and it said so


def test_also_refuses_a_path_that_does_not_exist(repo):
    """`--also` is CWD-relative by design, so a run from a subdirectory invented
    `sub/oldname.txt` -- and reported it as 'committed and verified'."""
    repo.write("f.txt", "a\n")
    repo.write("sub/keep.txt", "k\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")

    r = repo.run("commit", "-m", "x", "--also", "nope.txt", sid="S1",
                 cwd=os.path.join(repo.root, "sub"))
    assert r.returncode != 0
    assert "no such path" in r.stderr
    assert "f.txt" not in repo.descriptions()


def test_also_refuses_a_path_a_live_session_is_working_on(repo):
    """`--also` takes a path WHOLESALE, so a peer's unfinished work lands under
    your message. `claim` refuses this by name; --also did not even look."""
    repo.write("f.txt", "a\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    repo.write("g.txt", "g-S2-UNFINISHED\n")
    repo.record("S2", "g.txt", old="g", new="g-S2-UNFINISHED", original="g\n")

    r = repo.run("commit", "-m", "mine plus g", "--also", "g.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "live session is" in r.stderr
    assert repo.show("g.txt") == b"g\n"                  # their work not taken

    ok = repo.run("commit", "-m", "mine plus g", "--also", "g.txt", sid="S1",
                  extra=["--force"])
    assert ok.returncode == 0, ok.stderr
    assert "unverified" in ok.stdout                     # not called "verified"


def test_non_utf8_content_does_not_block_the_journal(repo):
    """`v.encode()` raised UnicodeEncodeError on a lone surrogate, which blocked
    every OTHER path in the journal too. The decode direction was guarded; this
    is the encode direction."""
    raw = b"caf\xe9\n"
    orig = raw.decode("utf-8", "surrogateescape")
    repo.write("f.txt", raw)
    repo.write("normal.txt", "plain\n")
    repo.commit("base")
    repo.write("f.txt", b"caf\xe9 changed\n")
    repo.write("normal.txt", "PLAIN\n")
    repo.record("S1", "f.txt", old=orig.strip("\n"),
                new=orig.strip("\n") + " changed", original=orig)
    repo.record("S1", "normal.txt", old="plain", new="PLAIN", original="plain\n")

    r = repo.run("commit", "-m", "latin1", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"caf\xe9 changed\n"
    assert repo.show("normal.txt") == b"PLAIN\n"         # not collateral damage


def test_rename_refusal_names_both_halves(repo):
    """Claiming the OLD half printed 'x was renamed from x' and an --also pair
    that commits the delete with no add, orphaning the new file."""
    _optin(repo)
    repo.write("oldname.txt", "content\n")
    repo.commit("base")
    _bash(repo)
    os.rename(os.path.join(repo.root, "oldname.txt"),
              os.path.join(repo.root, "newname.txt"))
    _bash(repo)

    r = repo.run("claim", "oldname.txt", sid="S1")
    assert r.returncode == 1
    assert "--also oldname.txt --also newname.txt" in r.stderr
    assert "--also oldname.txt --also oldname.txt" not in r.stderr


def test_claim_also_warns_about_a_session_that_has_ended(repo):
    """The live case refused by name; a session that died seconds ago had its
    uncommitted work absorbed with no warning at all -- which is exactly the
    work least likely to be recoverable from anywhere else."""
    _optin(repo)
    repo.write("shared.txt", "base\n")
    repo.commit("base")
    _bash(repo, sid="S1")
    repo.write("shared.txt", "base\nfrom-the-dead-session\n")
    repo.record("S9", "shared.txt", old="base\n",
                new="base\nfrom-the-dead-session\n", original="base\n")
    _bash(repo, sid="S1")
    # mark S9 as ended: a recorded owner whose pid is long gone
    jdir = os.path.join(repo.journal, repo.root.replace("/", "_"), "S9")
    with open(os.path.join(jdir, ".owner"), "w") as fh:
        fh.write("999999\tSat Jan  1 00:00:00 2000\n")

    r = repo.run("claim", "shared.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "ended" in r.stderr
    assert not repo.journal_records("S1")


def test_commit_stops_on_unclaimed_window_paths(repo):
    """Surfacing alone did not work: ai_jj_commit runs preflight-message-commit
    in one shot, so the agent read the note only after the commit had landed.
    Stopping is what makes 'claim it and re-run' true."""
    _optin(repo)
    repo.write("edited.txt", "a\n")
    repo.write("sedded.txt", "s\n")
    repo.commit("base")
    _bash(repo)
    repo.write("sedded.txt", "s-via-sed\n")
    _bash(repo)
    repo.write("edited.txt", "A\n")
    repo.record("S1", "edited.txt", old="a", new="A", original="a\n")

    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode == 5, r.stdout + r.stderr
    assert "ccjj claim sedded.txt" in r.stderr
    assert repo.show("edited.txt") == b"a\n"          # NOTHING committed yet

    # claim, re-run -> ONE commit holding both
    assert repo.run("claim", "sedded.txt", sid="S1").returncode == 0
    ok = repo.run("commit", "-m", "mine", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("edited.txt") == b"A\n"
    assert repo.show("sedded.txt") == b"s-via-sed\n"


def test_no_claim_commits_without_the_window_paths(repo):
    """The escape hatch: a Bash-touched path the session never wants committed
    must not wedge every future commit."""
    _optin(repo)
    repo.write("edited.txt", "a\n")
    repo.write("artifact.log", "x\n")
    repo.commit("base")
    _bash(repo)
    repo.write("artifact.log", "noise\n")
    _bash(repo)
    repo.write("edited.txt", "A\n")
    repo.record("S1", "edited.txt", old="a", new="A", original="a\n")

    r = repo.run("commit", "-m", "mine", sid="S1", extra=["--no-claim"])
    assert r.returncode == 0, r.stderr
    assert repo.show("edited.txt") == b"A\n"
    assert repo.show("artifact.log") == b"x\n"


def test_also_overrides_conflicting_records_for_that_path(repo):
    """`--also` takes a path wholesale, so its journal records must not ALSO be
    replayed. Without this the conflict message's own recommended remedy
    (`--also <path>`) hit the identical conflict and was useless -- found by
    using the tool on its own source tree."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    # a record that cannot be replayed: its anchor text is not in @-
    repo.write("f.txt", "rewritten wholesale by a script\n")
    repo.record("S1", "f.txt", old="NOT-IN-BASE", new="X",
                original="NOT-IN-BASE\n")

    bad = repo.run("commit", "-m", "x", sid="S1")
    assert bad.returncode != 0
    assert "conflict" in bad.stderr

    ok = repo.run("commit", "-m", "wholesale", "--also", "f.txt", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("f.txt") == b"rewritten wholesale by a script\n"
