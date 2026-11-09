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


@pytest.fixture(autouse=True)
def _no_inherited_claude_pid(monkeypatch):
    """Under Claude Code every hook here would inherit one owner, and the
    sessions in these tests would merge as one process's rotated ids."""
    monkeypatch.delenv("CLAUDE_PID", raising=False)


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

def _hook_edit_crlf(repo, sid, rel, old, new):
    """An Edit of a CRLF file, in the shape Claude Code really reports it:
    every string normalized to LF, while the disk keeps CRLF (checked against
    a real Edit). A record with CRLF in `original` cannot come from the hook."""
    p = os.path.join(repo.root, rel)
    disk = open(p, "rb").read()
    orig = disk.replace(b"\r\n", b"\n").decode()
    open(p, "wb").write(orig.replace(old, new, 1).replace("\n", "\r\n").encode())
    payload = json.dumps({
        "tool_name": "Edit", "session_id": sid, "tool_use_id": "t",
        "tool_input": {"file_path": p, "old_string": old, "new_string": new},
        "tool_response": {"oldString": old, "newString": new, "originalFile": orig,
                          "replaceAll": False, "structuredPatch": [{"lines": ["x"]}]}})
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})


def test_crlf_survives_byte_exact(repo):
    repo.write("w.txt", b"alpha\r\nbeta\r\ngamma\r\n")
    repo.commit("base")
    _hook_edit_crlf(repo, "S1", "w.txt", "beta", "BETA")

    r = repo.run("commit", "-m", "crlf", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("w.txt") == b"alpha\r\nBETA\r\ngamma\r\n"


def test_multiline_edit_of_a_crlf_file_replays(repo):
    """A multi-line `old` holds LF and the committed file holds CRLF, so it
    never matched, and the error blamed a Bash change that did not happen."""
    repo.write("w.txt", b"alpha\r\nbeta\r\ngamma\r\n")
    repo.commit("base")
    _hook_edit_crlf(repo, "S1", "w.txt", "alpha\nbeta", "alpha\nBETA\nnew")

    r = repo.run("commit", "-m", "crlf", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("w.txt") == b"alpha\r\nBETA\r\nnew\r\ngamma\r\n"


def test_edit_inserting_lines_into_crlf_does_not_mix_endings(repo):
    repo.write("w.txt", b"alpha\r\nbeta\r\n")
    repo.commit("base")
    _hook_edit_crlf(repo, "S1", "w.txt", "beta", "beta\nadded")

    r = repo.run("commit", "-m", "crlf", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("w.txt") == b"alpha\r\nbeta\r\nadded\r\n"


def test_an_lf_file_is_left_alone(repo):
    repo.write("w.txt", "alpha\nbeta\n")
    repo.commit("base")
    _hook_edit(repo, "S1", "w.txt", "alpha\nbeta", "alpha\nBETA")

    r = repo.run("commit", "-m", "lf", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("w.txt") == b"alpha\nBETA\n"


def test_an_empty_payload_jj_did_not_take_is_rolled_back(repo):
    """`jj file show` prints nothing for an absent path, so an empty payload
    compared equal and was reported verified while not in the commit."""
    repo.write(".gitignore", "ignored.txt\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    repo.write("ignored.txt", "")
    _hook_write(repo, "S1", "ignored.txt", "")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")

    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "did not take" in r.stderr
    assert repo.show("mine.txt") == b"m\n"


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


# ------------------------------------------------------------------- path case
#
# macOS is case-insensitive but case-preserving, and os.path.realpath does not
# normalize case -- so one directory has two working spellings. ROOT comes from
# `jj root` (canonical); a record's path comes from the agent's file_path,
# whatever it used. Comparing them as STRINGS made `ccjj audit` silently drop
# every mismatched record from its claims and made `ccjj commit` abort the whole
# run on the first one, both for paths sitting plainly inside the repo.

def _load_ccjj():
    """ccjj.py imported as a module, for the few pure functions worth unit
    testing directly. It is a script, not a package member, so it is loaded by
    path rather than imported by name."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("ccjj_under_test", CCJJ)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _case_insensitive(base):
    p = os.path.join(base, "CaseProbe")
    os.mkdir(p)
    try:
        return os.path.isdir(os.path.join(base, "caseprobe"))
    finally:
        os.rmdir(p)


@pytest.fixture
def icase(tmp_path):
    if not _case_insensitive(str(tmp_path)):
        pytest.skip("filesystem is case-sensitive; the bug cannot arise")


def _variant(root):
    """`root` with its last component upper-cased -- the same directory here."""
    return os.path.join(os.path.dirname(root), os.path.basename(root).upper())


def _write_rec(repo, sid, path, **kw):
    """A schema-1 record, i.e. one written before `rel` existed."""
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), sid)
    os.makedirs(d, exist_ok=True)
    rec = {"schema": 1, "tool": "Write", "path": path, "old": None, "new": None,
           "content": None, "replace_all": False, "original": None}
    rec.update(kw)
    with open(os.path.join(d, "%019d-0.json" % time.time_ns()), "w") as fh:
        json.dump(rec, fh)


def test_legacy_record_spelled_with_other_case_still_commits(repo, icase):
    """`ccjj commit` aborted the ENTIRE run -- build() called rel() unguarded,
    so one mis-cased record refused every path the session owned.

    NESTED on purpose. under_root() rebuilds the relative path from components
    collected walking UP, so it must reverse them; every one-level-deep path
    makes that reversal a no-op and lets `a/b/f` -> `f/b/a` pass unnoticed."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("deep/nest/new.md", "written\n")
    _write_rec(repo, "S1", os.path.join(_variant(repo.root), "deep", "nest", "new.md"),
               content="written\n")

    r = repo.run("commit", "-m", "cased", sid="S1")
    assert r.returncode == 0, r.stderr
    assert "outside the repo" not in r.stderr
    assert repo.show(os.path.join("deep", "nest", "new.md")) == b"written\n"


def test_legacy_record_spelled_with_other_case_counts_as_claimed(repo, icase):
    """survey() swallowed rel()'s exit and `continue`d, so the path vanished
    from the claims set and audit reported it as owned by nobody."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "b\n")
    _write_rec(repo, "S1", os.path.join(_variant(repo.root), "f.txt"),
               content="b\n")

    r = repo.run("audit", sid="S1")
    assert "outside the repo" not in r.stderr
    assert "f.txt" not in r.stdout.split("claimed by no session")[-1]


def test_a_genuinely_outside_path_is_still_refused(repo):
    """The inode fallback must not turn into 'accept anything that escapes'.
    No icase fixture: a sibling repo is outside on every filesystem, and this
    is exactly the assertion worth keeping on a case-sensitive one."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    sibling = os.path.join(os.path.dirname(repo.root), "repo2")
    os.makedirs(sibling)
    with open(os.path.join(sibling, "f.txt"), "w") as fh:
        fh.write("x\n")
    _write_rec(repo, "S1", os.path.join(sibling, "f.txt"), content="x\n")

    r = repo.run("commit", "-m", "outside", sid="S1")
    assert r.returncode != 0
    assert "outside the repo" in r.stderr


def test_record_edit_stores_a_repo_relative_path(tmp_path):
    """Schema 2. Derived where the root is known to be this path's ancestor,
    so no reader has to re-derive it against a differently-spelled ROOT."""
    repo = Repo(str(tmp_path))
    repo.write("d/f.txt", "a\n")
    repo.commit("base")
    repo.write("d/f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1", "tool_use_id": "t",
        "tool_input": {"file_path": os.path.join(repo.root, "d", "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})

    names = repo.journal_records("S1")
    assert len(names) == 1
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    with open(os.path.join(d, names[0])) as fh:
        rec = json.load(fh)
    assert rec["schema"] == 2
    assert rec["rel"] == os.path.join("d", "f.txt")


def test_recorder_and_reader_agree_on_the_journal_directory(tmp_path, icase):
    """repo_key() names the journal dir from the root STRING. The recorder
    resolved it from the agent's file_path and readers from `jj root`, so a
    mis-cased cwd wrote a second journal -- masked here because both names open
    one directory, but a real split on any case-sensitive volume."""
    repo = Repo(str(tmp_path))
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1", "tool_use_id": "t",
        "tool_input": {"file_path": os.path.join(_variant(repo.root), "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})

    # keyed by the canonical root, not the spelling the payload happened to use
    assert os.listdir(repo.journal) == [repo.root.replace("/", "_")]
    assert repo.run("commit", "-m", "hooked", sid="S1").returncode == 0
    assert repo.show("f.txt") == b"A\n"


def test_record_edit_stores_rel_for_a_mis_cased_path(tmp_path, icase):
    """find_repo() canonicalizes the root it returns, so computing `rel` against
    a bare realpath compared a normalized string to an unnormalized one and
    stored null -- in precisely the case the field was added for. Schema 2 then
    silently delivered nothing and the inode fallback carried every record."""
    repo = Repo(str(tmp_path))
    repo.write("sub/f.txt", "a\n")
    repo.commit("base")
    repo.write("sub/f.txt", "A\n")
    payload = json.dumps({
        "tool_name": "Edit", "session_id": "S1", "tool_use_id": "t",
        "tool_input": {"file_path": os.path.join(_variant(repo.root), "sub", "f.txt"),
                       "old_string": "a", "new_string": "A"},
        "tool_response": {"originalFile": "a\n",
                          "structuredPatch": [{"lines": ["-a", "+A"]}]},
    })
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})

    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    with open(os.path.join(d, repo.journal_records("S1")[0])) as fh:
        rec = json.load(fh)
    assert rec["rel"] == os.path.join("sub", "f.txt")


def test_a_stored_rel_is_what_readers_use(repo):
    """Pins that schema 2 is HONORED, not merely written. The two fields are
    made to disagree deliberately -- nothing produces this in the wild -- because
    a reader that quietly re-derived from `path` would otherwise be invisible."""
    repo.write("a.txt", "a\n")
    repo.write("b.txt", "b\n")
    repo.commit("base")
    repo.write("b.txt", "from-rel\n")
    _write_rec(repo, "S1", os.path.join(repo.root, "a.txt"),
               schema=2, rel="b.txt", content="from-rel\n", original="b\n")

    r = repo.run("commit", "-m", "stored rel wins", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("b.txt") == b"from-rel\n"     # the record's `rel`
    assert repo.show("a.txt") == b"a\n"            # not its `path`


def test_also_excludes_records_by_the_same_key_build_uses(repo):
    """`--also` takes a path WHOLESALE, so its records must not ALSO be replayed.
    The filter has to key exactly as build() does: build() moved to rec_rel while
    the filter still called rel(), so a record whose stored `rel` differs from
    its `path` slipped through and was applied on top of the wholesale copy --
    the double-application the exclusion exists to prevent.

    The two fields are made to disagree deliberately; see the test above."""
    repo.write("a.txt", "a\n")
    repo.write("b.txt", "b\n")
    repo.commit("base")
    repo.write("b.txt", "from-working-copy\n")
    _write_rec(repo, "S1", os.path.join(repo.root, "a.txt"),
               schema=2, rel="b.txt", content="from-record\n", original="b\n")

    r = repo.run("commit", "-m", "also", "--also", "b.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    # wholesale from the working copy, NOT the record replayed over it
    assert repo.show("b.txt") == b"from-working-copy\n"


def test_claim_survives_a_mis_cased_absolute_path(repo, icase):
    """rel_literal() has the same string-compare trap as rel(), and `ccjj claim`
    is the one caller that reaches it -- with no coverage at all before this."""
    _optin(repo)
    repo.write("s.sh", "one\ntwo\n")
    repo.commit("base")
    _bash(repo)
    repo.write("s.sh", "one\nTWO-via-sed\n")
    _bash(repo)

    c = repo.run("claim", os.path.join(_variant(repo.root), "s.sh"), sid="S1")
    assert c.returncode == 0, c.stderr
    assert "outside the repo" not in c.stderr
    assert repo.run("commit", "-m", "sed", sid="S1").returncode == 0
    assert repo.show("s.sh") == b"one\nTWO-via-sed\n"


def test_true_case_refuses_to_guess_between_two_spellings(monkeypatch):
    """On a case-SENSITIVE volume `Foo` and `foo` are different directories, so
    a lone case-insensitive match is the only safe one. Weakened to `len < 1`
    the walk picks hits[0] arbitrarily and silently retargets the journal.

    Driven through a faked listdir because the ambiguity is unconstructible on
    the case-insensitive filesystem this suite runs on."""
    ccjj = _load_ccjj()
    monkeypatch.setattr(ccjj.os, "listdir",
                        lambda d: ["Foo", "foo"] if d == os.sep else [])
    # ambiguous -> the remainder is handed back verbatim, never guessed
    assert ccjj.true_case("/FOO") == "/FOO"
    monkeypatch.setattr(ccjj.os, "listdir",
                        lambda d: ["Foo"] if d == os.sep else [])
    assert ccjj.true_case("/FOO") == "/Foo"


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


def test_should_scope_accepts_with_no_records_of_my_own(repo):
    """A session with nothing recorded (Bash-only work, or none) must still be
    scoped while a peer is live. Declining sent ai_jj_commit and /cc:commit
    down the whole-copy path: `jj commit` took the peer's unfinished edit under
    this session's message, and `retire-all` archived the peer's journal."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    repo.record("OTHER", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "OTHER", str(os.getpid()), _my_lstart())

    assert repo.run("should-scope", "-q", sid="NEW").returncode == 0
    r = repo.run("commit", "-m", "x", sid="NEW")
    assert r.returncode == 2 and "nothing recorded" in r.stderr


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


def test_claim_replaces_the_sessions_own_edits_without_applying_them_twice(repo):
    """A claimed blob contains those edits already. Replaying both duplicates a
    hunk for an insertion-shaped Edit, the commonest shape, and refusing made a
    cycle: commit said "claim it" and claim said "commit first"."""
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a\n", "a\nadded-by-edit\n")
    with open(os.path.join(repo.root, "f.txt"), "a") as fh:
        fh.write("added-by-bash\n")
    _bash(repo, tuid="t2")
    assert repo.run("commit", "-m", "x", sid="S1").returncode == 5

    r = repo.run("claim", "f.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    assert "added-by-bash" in r.stdout              # the reader sees the diff
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"a\nadded-by-edit\nadded-by-bash\n"


def test_claim_dry_run_over_edits_changes_nothing(repo):
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a", "A")
    _bash(repo, tuid="t2")
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    before = sorted(n for n in os.listdir(d) if n.endswith(".json"))
    r = repo.run("claim", "f.txt", "-n", sid="S1")
    assert r.returncode == 0, r.stderr
    assert "dry run" in r.stdout
    assert sorted(n for n in os.listdir(d) if n.endswith(".json")) == before


def test_superseded_records_are_kept_in_forgotten(repo):
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a", "A")
    _bash(repo, tuid="t2")
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1")
    name = next(n for n in os.listdir(d) if n.endswith(".json"))
    assert repo.run("claim", "f.txt", sid="S1").returncode == 0
    assert os.path.exists(os.path.join(d, "forgotten", name))
    assert not os.path.exists(os.path.join(d, name))


def test_second_claim_on_one_file_works(repo):
    """Claim #1's own record used to block claim #2, with no Edit involved."""
    _optin(repo)
    repo.write("f.txt", "one\n")
    repo.commit("base")
    _bash(repo)
    repo.write("f.txt", "two\n")
    _bash(repo, tuid="t2")
    assert repo.run("claim", "f.txt", sid="S1").returncode == 0
    repo.write("f.txt", "three\n")
    _bash(repo, tuid="t3")
    r = repo.run("claim", "f.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"three\n"


def test_an_edit_after_a_superseding_claim_replays_on_top(repo):
    _optin(repo)
    repo.write("f.txt", "a\nb\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a", "A")
    _bash(repo, tuid="t2")
    assert repo.run("claim", "f.txt", sid="S1").returncode == 0
    _hook_edit(repo, "S1", "f.txt", "b", "B")
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"A\nB\n"


def test_superseding_claim_still_respects_a_peers_stake(repo):
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a", "A")
    repo.record("S2", "f.txt", old="a", new="A", original="a\n")
    _owner(repo, "S2", str(os.getpid()), _my_lstart())
    _bash(repo, tuid="t2")
    r = repo.run("claim", "f.txt", sid="S1")
    assert r.returncode == 1
    assert "also claimed" in r.stderr


def test_also_is_rolled_back_when_jj_does_not_take_the_path(repo):
    """An ignored path selects nothing. With another path the commit is not
    empty, so it reported success having taken nothing for --also."""
    repo.write(".gitignore", "ignored.txt\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    repo.write("ignored.txt", "x\n")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "ignored.txt", sid="S1")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "--also did not take" in r.stderr
    assert repo.show("mine.txt") == b"m\n"          # rolled back


def test_also_delete_and_symlink_pass_the_check(repo):
    repo.write("gone.txt", "g\n")
    repo.write("target.txt", "t\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    os.remove(os.path.join(repo.root, "gone.txt"))
    os.symlink("target.txt", os.path.join(repo.root, "link"))
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "gone.txt", "--also", "link", sid="S1")
    assert r.returncode == 0, r.stderr
    files = repo.jj_("file", "list", "-r", "@-").stdout.split()
    assert "gone.txt" not in files and "link" in files


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
    assert "another session has" in r.stderr and "S2 (live)" in r.stderr
    assert repo.show("g.txt") == b"g\n"                  # their work not taken

    ok = repo.run("commit", "-m", "mine plus g", "--also", "g.txt", sid="S1",
                  extra=["--force"])
    assert ok.returncode == 0, ok.stderr
    assert "matched to the working copy" in ok.stdout    # not "committed and verified"


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


def test_stop_fires_when_a_journaled_path_also_changed_via_bash(repo):
    """The check excluded paths already in `mine`, so a file with BOTH journal
    records and Bash-window changes was committed from the records alone and the
    Bash half vanished. This cost a partial commit of ccjj's own source tree --
    the committed plan file was one draft behind the working copy."""
    _optin(repo)
    repo.write("doc.md", "line1\n")
    repo.commit("base")
    _bash(repo)
    repo.write("doc.md", "line1-edited\n")                 # the journaled edit
    repo.record("S1", "doc.md", old="line1", new="line1-edited", original="line1\n")
    repo.write("doc.md", "line1-edited\nappended-by-bash\n")  # then a Bash append
    _bash(repo)

    r = repo.run("commit", "-m", "doc", sid="S1")
    assert r.returncode == 5, r.stdout + r.stderr
    assert "ccjj claim doc.md" in r.stderr
    assert repo.show("doc.md") == b"line1\n"               # nothing committed

    # and --no-claim still commits just the journaled half, deliberately
    ok = repo.run("commit", "-m", "doc", sid="S1", extra=["--no-claim"])
    assert ok.returncode == 0, ok.stderr
    assert repo.show("doc.md") == b"line1-edited\n"


# ------------------------------------------------------------- `ccjj forget`
#
# Every journal defect found so far was worked around by deleting a record by
# hand, while two die() messages told you to do exactly that and nothing
# implemented it. These pin the command that does.


def test_forget_removes_this_sessions_records_for_a_path(repo):
    repo.write("a.txt", "one\n")
    repo.commit("base")
    repo.write("a.txt", "ONE\n")
    repo.record("S1", "a.txt", old="one", new="ONE", original="one\n")

    assert len(repo.journal_records("S1")) == 1
    r = repo.run("forget", "a.txt")
    assert r.returncode == 0, r.stderr
    assert repo.journal_records("S1") == []


def test_forget_leaves_other_paths_alone(repo):
    repo.write("a.txt", "one\n")
    repo.write("b.txt", "two\n")
    repo.commit("base")
    repo.write("a.txt", "ONE\n")
    repo.write("b.txt", "TWO\n")
    repo.record("S1", "a.txt", old="one", new="ONE", original="one\n")
    repo.record("S1", "b.txt", old="two", new="TWO", original="two\n")

    assert repo.run("forget", "a.txt").returncode == 0
    assert len(repo.journal_records("S1")) == 1

    ok = repo.run("commit", "-m", "b only", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("b.txt") == b"TWO\n"
    assert repo.show("a.txt") == b"one\n"      # the forgotten edit did not land


def test_forget_dry_run_removes_nothing(repo):
    repo.write("a.txt", "one\n")
    repo.commit("base")
    repo.write("a.txt", "ONE\n")
    repo.record("S1", "a.txt", old="one", new="ONE", original="one\n")

    r = repo.run("forget", "-n", "a.txt")
    assert r.returncode == 0, r.stderr
    assert "dry run" in r.stdout
    assert len(repo.journal_records("S1")) == 1


def test_forget_moves_records_rather_than_deleting_them(repo):
    """Forgetting is silent data loss when it is wrong -- the edits simply do
    not get committed and nothing says so -- so it has to be reversible."""
    repo.write("a.txt", "one\n")
    repo.commit("base")
    repo.write("a.txt", "ONE\n")
    repo.record("S1", "a.txt", old="one", new="ONE", original="one\n")

    assert repo.run("forget", "a.txt").returncode == 0
    kept = os.path.join(repo.journal, repo.root.replace("/", "_"),
                        "S1", "forgotten")
    assert len(os.listdir(kept)) == 1


def test_forgotten_records_are_not_replayed(repo):
    """`forgotten/` lives inside the session journal dir, so load_records has
    to skip it -- it filters on the .json suffix, and this pins that."""
    repo.write("a.txt", "one\n")
    repo.commit("base")
    repo.write("a.txt", "ONE\n")
    repo.record("S1", "a.txt", old="one", new="ONE", original="one\n")
    assert repo.run("forget", "a.txt").returncode == 0

    r = repo.run("commit", "-m", "nothing left", sid="S1")
    assert r.returncode != 0                    # nothing to commit, not a replay
    assert repo.show("a.txt") == b"one\n"


def test_forget_exits_2_when_no_record_matches(repo):
    repo.write("a.txt", "one\n")
    repo.commit("base")
    assert repo.run("forget", "a.txt").returncode == 2


def test_forget_unwedges_an_inconsistent_record(repo):
    """Bug 1. `old` is not a substring of `original`, so anchored_replace dies
    and takes the whole commit with it -- including the unrelated good record.
    Before `forget` there was no CLI route out of this at all.
    """
    repo.write("a.txt", "alpha\n")
    repo.write("b.txt", "beta\n")
    repo.commit("base")
    repo.write("a.txt", "ALPHA\n")
    repo.write("b.txt", "BETA\n")
    repo.record("S1", "a.txt", old="NOT-IN-THE-FILE", new="ALPHA",
                original="alpha\n")
    repo.record("S1", "b.txt", old="beta", new="BETA", original="beta\n")

    wedged = repo.run("commit", "-m", "wedged", sid="S1")
    assert wedged.returncode != 0
    assert "inconsistent" in wedged.stderr
    assert "ccjj forget" in wedged.stderr       # the message names its own escape

    assert repo.run("forget", "a.txt").returncode == 0
    ok = repo.run("commit", "-m", "unwedged", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("b.txt") == b"BETA\n"


def test_forget_stops_a_deleted_throwaway_being_resurrected(repo):
    """Bug 3. build() never consults the filesystem, so a Write record for a
    file created and then deleted in-session still reconstructs it."""
    repo.write("keep.txt", "keep\n")
    repo.commit("base")
    repo.write("keep.txt", "KEEP\n")
    repo.record("S1", "keep.txt", old="keep", new="KEEP", original="keep\n")

    repo.write("probe.py", "secret\n")
    repo.record("S1", "probe.py", tool="Write", content="secret\n")
    os.remove(os.path.join(repo.root, "probe.py"))

    assert repo.run("forget", "probe.py").returncode == 0
    ok = repo.run("commit", "-m", "no probe", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("keep.txt") == b"KEEP\n"
    assert repo.show("probe.py") is None


# ------------------------------------------- review 2026-11-07: regressions
#
# Each of these was reproduced against the unpatched tool first. Every
# hook payload below is the shape Claude Code sends, so no test asserts on a
# record the real hook cannot produce.

def _hook_edit(repo, sid, rel, old, new, req_old=None, req_new=None):
    """Apply an Edit on disk and fire the real record-edit hook.

    req_old/req_new are what the agent ASKED for, when Edit normalized it."""
    p = os.path.join(repo.root, rel)
    orig = open(p).read()
    open(p, "w").write(orig.replace(old, new, 1))
    payload = json.dumps({
        "tool_name": "Edit", "session_id": sid, "tool_use_id": "t",
        "tool_input": {"file_path": p, "old_string": req_old or old,
                       "new_string": req_new or new},
        "tool_response": {"oldString": old, "newString": new,
                          "originalFile": orig, "replaceAll": False,
                          "structuredPatch": [{"lines": ["x"]}]}})
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})


def _hook_write(repo, sid, rel, content):
    p = os.path.join(repo.root, rel)
    orig = open(p).read() if os.path.exists(p) else None
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(content)
    payload = json.dumps({
        "tool_name": "Write", "session_id": sid, "tool_use_id": "t",
        "tool_input": {"file_path": p, "content": content},
        "tool_response": {"type": "create" if orig is None else "update",
                          "content": content, "originalFile": orig,
                          "structuredPatch": []}})
    subprocess.run([sys.executable, CCJJ, "record-edit"], input=payload,
                   capture_output=True, text=True,
                   env={**os.environ, "CC_JJ_JOURNAL": repo.journal})


def _ended(repo, sid):
    _owner(repo, sid, "99999999", "Mon Jan  1 00:00:00 2001")


def test_record_takes_the_applied_strings_not_the_requested_ones(repo):
    """Edit normalizes the request (curly quotes) before applying it, so
    tool_input.old_string is not in originalFile and the record was poisoned:
    "journal record ... is inconsistent", the whole commit refused."""
    repo.write("q.txt", 'say "hi"\n')
    repo.commit("base")
    _hook_edit(repo, "S1", "q.txt", 'say "hi"', 'say "HI"',
               req_old="say “hi”", req_new="say “HI”")
    r = repo.run("commit", "-m", "q", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("q.txt") == b'say "HI"\n'


def test_also_refuses_a_bash_only_peers_path(repo):
    """--also checked live peers' RECORDS only; a Bash-only peer's bytes were
    committed under your message, exit 0, while `claim` refused by name."""
    _optin(repo)
    repo.write("peer.txt", "p\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, "S2")
    repo.write("peer.txt", "p-S2-UNFINISHED\n")
    _bash(repo, "S2")
    _bash(repo, "S1")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "peer.txt", "--no-claim", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "S2 (live)" in r.stderr
    assert repo.show("peer.txt") == b"p\n"


def test_also_refuses_an_ended_peers_uncommitted_path(repo):
    repo.write("peer.txt", "p\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    _hook_edit(repo, "S2", "peer.txt", "p", "p-S2-UNFINISHED")
    _ended(repo, "S2")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "peer.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "S2 (ended)" in r.stderr
    assert repo.show("peer.txt") == b"p\n"


def test_claim_checks_peers_before_redirecting_a_delete_to_also(repo):
    """The delete/rename redirect sat ABOVE claim's peer check, so for exactly
    the operations --also exists for, claim printed an --also command that
    nothing had checked -- and following it deleted a live peer's work."""
    _optin(repo)
    repo.write("peer.txt", "p\n")
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, "S2")
    repo.write("peer.txt", "p-S2-UNFINISHED\n")
    _bash(repo, "S2")
    os.remove(os.path.join(repo.root, "peer.txt"))
    _bash(repo, "S1")
    r = repo.run("claim", "peer.txt", sid="S1")
    assert r.returncode == 1
    assert "Bash span of session(s) S2" in r.stderr and "--also" not in r.stderr


# ------------------------------------- exit 5: paths that are not really loose
#
# A window is a whole-copy tree diff, so these all appear inside one. Each false
# stop trained agents to pass --no-claim, and the printed `ccjj claim` for a
# shared file committed the peer's unfinished hunk.

def _contended(repo):
    _optin(repo)
    open(os.path.join(repo.root, ".jj", "ccjj-contended"), "w").close()


def _three_files(repo):
    for f in ("a.txt", "b.txt", "c.txt"):
        repo.write(f, "line1\nline2\nline3\n")
    repo.commit("base")


def test_commit_does_not_stop_on_a_file_a_peer_already_committed(repo):
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _owner(repo, "A", str(os.getpid()), _my_lstart())   # or B's commit prunes it
    _hook_edit(repo, "B", "b.txt", "line1", "PEER")
    assert repo.run("commit", "-m", "peer", sid="B").returncode == 0
    _bash(repo, "A", tuid="t2")
    _hook_edit(repo, "A", "a.txt", "line1", "MINE")
    r = repo.run("commit", "-m", "mine", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("a.txt") == b"MINE\nline2\nline3\n"


def test_commit_does_not_stop_on_a_file_only_a_peer_has_edited(repo):
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _hook_edit(repo, "B", "b.txt", "line1", "PEER-UNFINISHED")
    _bash(repo, "A", tuid="t2")
    _hook_edit(repo, "A", "a.txt", "line1", "MINE")
    r = repo.run("commit", "-m", "mine", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("b.txt") == b"line1\nline2\nline3\n"


def test_two_edit_only_sessions_on_one_file_do_not_stop(repo):
    """The main use case. A's reconstruction rightly lacks B's hunk, so it never
    matches the disk; exit 5 then sent A to `claim --force`, which took B's
    unfinished hunk under A's message at exit 0."""
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _hook_edit(repo, "A", "a.txt", "line1", "A-EDIT")
    _hook_edit(repo, "B", "a.txt", "line3", "B-UNFINISHED")
    _bash(repo, "A", tuid="t2")
    r = repo.run("commit", "-m", "mine", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("a.txt") == b"A-EDIT\nline2\nline3\n"
    assert repo.read("a.txt") == b"A-EDIT\nline2\nB-UNFINISHED\n"
    assert "have edits there" in r.stderr


# ------------------------------------------- offers: what --no-claim leaves

def _left_behind(repo):
    """A commits an Edit with --no-claim, leaving a Bash edit to b.txt."""
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _bash(repo, "B")
    _hook_edit(repo, "A", "a.txt", "line1", "EDIT")
    repo.write("b.txt", "A-PERL\nline2\nline3\n")
    _bash(repo, "A", tuid="t2")
    repo.write("z.txt", "z\n")
    _bash(repo, "B", tuid="t2")
    r = repo.run("commit", "-m", "first", sid="A", extra=["--no-claim"])
    assert r.returncode == 0, r.stderr
    _bash(repo, "A", tuid="t3")          # commit-mine's own PostToolUse


def test_a_path_left_by_no_claim_can_still_be_claimed(repo):
    _left_behind(repo)
    r = repo.run("claim", "--force", "b.txt", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    r = repo.run("commit", "-m", "second", sid="A", extra=["--no-claim"])
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("b.txt") == b"A-PERL\nline2\nline3\n"


def test_a_path_left_by_no_claim_keeps_its_stake(repo):
    """Retiring the windows also retired the stake, so a peer could claim the
    left-behind file unrefused and commit it under its own message."""
    _left_behind(repo)
    r = repo.run("claim", "b.txt", sid="B")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "A (live)" in r.stderr or "A (ended)" in r.stderr
    assert not repo.journal_records("B")


def test_no_claim_does_not_stop_the_next_commit(repo):
    """Keeping the .win files themselves made the next commit exit 5 on files
    the previous commit had just landed: a window is not per-path."""
    _left_behind(repo)
    _hook_edit(repo, "A", "c.txt", "line1", "C")
    r = repo.run("commit", "-m", "second", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("a.txt") == b"EDIT\nline2\nline3\n"
    assert repo.show("b.txt") == b"line1\nline2\nline3\n"


def test_an_offer_survives_a_later_commit(repo):
    _left_behind(repo)
    _hook_edit(repo, "A", "c.txt", "line1", "C")
    assert repo.run("commit", "-m", "second", sid="A").returncode == 0
    _bash(repo, "A", tuid="t4")
    r = repo.run("claim", "--force", "b.txt", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.run("commit", "-m", "third", sid="A", extra=["--no-claim"]).returncode == 0
    assert repo.show("b.txt") == b"A-PERL\nline2\nline3\n"


def test_an_offer_ends_once_its_path_is_committed(repo):
    _left_behind(repo)
    r = repo.run("commit", "-m", "wholesale", "--also", "b.txt", "--force", sid="A",
                 extra=["--no-claim"])
    assert r.returncode == 0, r.stdout + r.stderr
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "A")
    offers = [json.load(open(os.path.join(d, n))) for n in os.listdir(d)
              if n.endswith(".offer")] if os.path.isdir(d) else []
    assert not any("b.txt" in o["paths"] for o in offers)


def test_an_offer_only_journal_is_not_pruned_as_empty(repo):
    _left_behind(repo)
    assert repo.run("prune", sid="A").returncode == 0
    r = repo.run("claim", "--force", "b.txt", sid="A")
    assert r.returncode == 0, r.stdout + r.stderr


def test_a_new_bash_change_to_an_offered_path_stops_the_next_commit(repo):
    """An offered path is skipped by exit 5 only while nothing new touched it."""
    _left_behind(repo)
    repo.write("b.txt", "A-PERL\nline2\nA-PERL-AGAIN\n")
    _bash(repo, "A", tuid="t4")
    _hook_edit(repo, "A", "c.txt", "line1", "C")
    r = repo.run("commit", "-m", "second", sid="A")
    assert r.returncode == 5, r.stdout + r.stderr
    assert "ccjj claim b.txt" in r.stderr


def test_an_offer_moves_with_compaction(repo, monkeypatch):
    _left_behind(repo)
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "A")
    _owner(repo, "A", str(os.getpid()), _my_lstart())
    assert any(n.endswith(".offer") for n in os.listdir(d))
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    r = repo.run("claim", "--force", "b.txt", sid="A2")
    assert r.returncode == 0, r.stdout + r.stderr


def test_claim_with_no_windows_does_not_say_none_were_recorded(repo):
    """After a commit archived them this read "No Bash calls have been recorded
    yet", which was false and sent the agent looking for a hook failure."""
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _hook_edit(repo, "A", "a.txt", "line1", "EDIT")
    _bash(repo, "A", tuid="t2")
    assert repo.run("commit", "-m", "x", sid="A").returncode == 0
    r = repo.run("claim", "b.txt", sid="A")
    assert r.returncode == 2, r.stdout + r.stderr
    assert "have been recorded" not in r.stderr
    assert "archives windows" in r.stderr


# ----------------------------------------------------- refusals say what is known

def test_window_only_stake_does_not_say_claimed(repo):
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _bash(repo, "B")
    repo.write("a.txt", "A-PERL\nline2\nline3\n")
    _bash(repo, "A", tuid="t2")
    repo.write("z.txt", "z\n")
    _bash(repo, "B", tuid="t2")
    r = repo.run("claim", "a.txt", sid="A")
    assert r.returncode == 1
    assert "also claimed" not in r.stderr
    assert "may not have touched this path" in r.stderr
    assert "A-PERL" in r.stderr                    # the diff is there to read


def test_a_peers_edit_record_is_named_as_such(repo):
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    repo.write("a.txt", "A-PERL\nline2\nline3\n")
    _hook_edit(repo, "B", "a.txt", "line3", "B-EDIT")
    _bash(repo, "A", tuid="t2")
    r = repo.run("claim", "a.txt", sid="A")
    assert r.returncode == 1
    assert "also claimed by" in r.stderr
    assert "commit-mine --no-claim" in r.stderr


def test_also_refusal_prints_the_diff_and_the_evidence(repo):
    """--also printed no diff, so "read the diff, then --force" was impossible."""
    _contended(repo)
    _three_files(repo)
    _bash(repo, "A")
    _bash(repo, "B")
    repo.write("a.txt", "A-PERL\nline2\nline3\n")
    _bash(repo, "A", tuid="t2")
    repo.write("z.txt", "z\n")
    _bash(repo, "B", tuid="t2")
    _hook_edit(repo, "A", "c.txt", "line1", "C")
    r = repo.run("commit", "-m", "x", "--also", "a.txt", "--no-claim", sid="A")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "Bash span only" in r.stderr
    assert "+A-PERL" in r.stderr
    assert repo.show("a.txt") == b"line1\nline2\nline3\n"


# -------------------------------------------------------- drift, by liveness

def _stray_sweep(repo, sid, live):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    if live:
        _owner(repo, sid, str(os.getpid()), _my_lstart())
    else:
        _ended(repo, sid)
    _base(repo, sid, _parent_id(repo))


def test_ended_sessions_drift_is_one_line_with_no_undo(repo):
    _stray_sweep(repo, "S2", live=False)
    _hook_edit(repo, "S2", "f.txt", "a", "S2-WORK")
    _ended(repo, "S2")
    repo.commit("stray")
    r = repo.run("audit", sid="NEW")
    assert "1 ended session(s)" in r.stderr, r.stdout + r.stderr
    assert "jj op restore" not in r.stderr
    assert "nothing unclaimed" not in r.stdout      # the sweep is not hidden


def test_ended_session_with_no_work_is_not_reported(repo):
    _stray_sweep(repo, "S2", live=False)
    repo.commit("stray")
    repo.jj_("new")
    r = repo.run("audit", sid="NEW")
    assert "ended session(s)" not in r.stderr
    assert "@- has moved" not in r.stderr
    assert "nothing unclaimed" in r.stdout


def test_a_live_sessions_drift_keeps_the_undo(repo):
    _stray_sweep(repo, "S1", live=True)
    _hook_edit(repo, "S1", "f.txt", "a", "S1-WORK")
    repo.commit("stray")
    r = repo.run("audit", sid="S1")
    assert "@- has moved" in r.stderr and "jj op restore" in r.stderr


# --------------------------------------------- previews and other sessions' ids

def _pre_clear_journal(repo, monkeypatch):
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _three_files(repo)
    _hook_edit(repo, "PRE", "a.txt", "line1", "EDIT")
    _owner(repo, "PRE", str(os.getpid()), _my_lstart())
    return os.path.join(repo.journal, repo.root.replace("/", "_"))


def test_diff_does_not_move_this_processes_journal(repo, monkeypatch):
    j = _pre_clear_journal(repo, monkeypatch)
    repo.write("b.txt", "B\nline2\nline3\n")   # recorded directly: a real hook would absorb
    repo.record("POST", "b.txt", old="line1", new="B", original="line1\nline2\nline3\n")
    before = sorted(os.listdir(os.path.join(j, "PRE")))
    r = repo.run("commit", "--diff", sid="POST")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sorted(os.listdir(os.path.join(j, "PRE"))) == before
    assert "leaves out edits" in r.stderr


def test_explicit_other_session_does_not_absorb(repo, monkeypatch):
    j = _pre_clear_journal(repo, monkeypatch)
    before = sorted(os.listdir(os.path.join(j, "PRE")))
    r = repo.run("commit", "--session", "UNUSED", "--diff", sid="MINE")
    assert r.returncode == 2, r.stdout + r.stderr       # nothing recorded for it
    assert sorted(os.listdir(os.path.join(j, "PRE"))) == before
    repo.run("audit", "--session", "UNUSED", sid="MINE")
    assert sorted(os.listdir(os.path.join(j, "PRE"))) == before
    assert not os.path.isdir(os.path.join(j, "UNUSED"))


def test_explicit_own_session_still_absorbs(repo, monkeypatch):
    j = _pre_clear_journal(repo, monkeypatch)
    r = repo.run("commit", "-m", "x", "--session", "MINE", sid="MINE")
    assert r.returncode == 0, r.stdout + r.stderr
    assert repo.show("a.txt") == b"EDIT\nline2\nline3\n"
    assert not os.path.isdir(os.path.join(j, "PRE"))


def test_also_names_a_symlink_not_its_target(repo):
    """rel() realpaths, so `--also link` became `--also target.txt`: exit 0,
    the link never committed."""
    repo.write("target.txt", "t\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    os.symlink("target.txt", os.path.join(repo.root, "link"))
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "link", sid="S1")
    assert r.returncode == 0, r.stderr
    assert "link" in repo.jj_("file", "list", "-r", "@-").stdout.split()


def test_edit_then_bash_delete_does_not_resurrect_the_file(repo):
    """Edit, then `rm`: exit 0, "committed and verified", and the deleted file
    put back into history."""
    repo.write("gone.txt", "one\ntwo\n")
    repo.write("keep.txt", "k\n")
    repo.commit("base")
    _hook_edit(repo, "S1", "gone.txt", "one", "ONE")
    _hook_edit(repo, "S1", "keep.txt", "k", "K")
    os.remove(os.path.join(repo.root, "gone.txt"))
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 1
    assert "--also gone.txt" in r.stderr and "ccjj forget gone.txt" in r.stderr
    assert repo.show("gone.txt") == b"one\ntwo\n"          # nothing committed
    ok = repo.run("commit", "-m", "x", "--also", "gone.txt", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert "gone.txt" not in repo.jj_("file", "list", "-r", "@-").stdout.split()


def test_write_then_delete_of_a_new_file_is_skipped_not_wedged(repo):
    repo.write("keep.txt", "k\n")
    repo.commit("base")
    _hook_edit(repo, "S1", "keep.txt", "k", "K")
    _hook_write(repo, "S1", "tmp.txt", "throwaway\n")
    _hook_write(repo, "S1", "empty.txt", "")
    os.remove(os.path.join(repo.root, "tmp.txt"))
    os.remove(os.path.join(repo.root, "empty.txt"))
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 0, r.stderr
    assert "empty.txt" not in r.stdout          # was "committed and verified"
    files = repo.jj_("file", "list", "-r", "@-").stdout.split()
    assert "tmp.txt" not in files and "empty.txt" not in files
    assert repo.show("keep.txt") == b"K\n"


def test_recreated_new_file_does_not_commit_the_superseded_version(repo):
    """Write v1, rm, re-create v2 via Bash: v1 was committed over v2, exit 0."""
    repo.write("keep.txt", "k\n")
    repo.commit("base")
    _hook_write(repo, "S1", "probe.txt", "SECRET v1\n")
    os.remove(os.path.join(repo.root, "probe.txt"))
    repo.write("probe.txt", "v2 via bash\n")
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 1
    assert "--also probe.txt" in r.stderr
    assert "probe.txt" not in repo.jj_("file", "list", "-r", "@-").stdout.split()


def test_bash_created_then_edited_file_names_the_way_out(repo):
    """Heredoc then Edit -- a common agent shape -- refused the whole commit
    with only a 1MiB explanation, while `claim` refused too."""
    repo.write("keep.txt", "k\n")
    repo.commit("base")
    repo.write("new.sh", "echo hi\n")                       # cat > new.sh <<EOF
    _hook_edit(repo, "S1", "new.sh", "echo hi", "echo hello")
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 1
    assert "--also new.sh" in r.stderr and "heredoc" in r.stderr
    ok = repo.run("commit", "-m", "x", "--also", "new.sh", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("new.sh") == b"echo hello\n"


def test_commit_does_not_erase_another_sessions_drift(repo):
    """refresh_bases rewrote every .base, so after a stray whole-copy commit
    swept S2's work, S1's next commit-mine made audit forget it happened."""
    repo.write("a.txt", "a\n")
    repo.write("b.txt", "b\n")
    repo.commit("base")
    _hook_edit(repo, "S2", "b.txt", "b", "B")
    repo.commit("stray whole-copy commit")
    _hook_edit(repo, "S1", "a.txt", "a", "A")
    assert "has moved" in repo.run("audit", sid="S1").stderr
    assert repo.run("commit", "-m", "x", sid="S1").returncode == 0
    assert "has moved" in repo.run("audit", sid="S1").stderr


def test_an_edit_recorded_during_the_commit_stays_live(repo, tmp_path):
    """retire() moved the whole directory, so a record written between
    load_records() and retire() was archived without being committed."""
    repo.write("a.txt", "a\n")
    repo.write("b.txt", "b\n")
    repo.commit("base")
    _hook_edit(repo, "S1", "a.txt", "a", "A")
    stub = tmp_path / "slow"
    stub.mkdir()
    (stub / "jj").write_text(
        '#!/bin/bash\nfor a in "$@"; do [ "$a" = commit ] && sleep 2 && break; done\n'
        'exec %s "$@"\n' % shutil.which("jj"))
    (stub / "jj").chmod(0o755)
    p = subprocess.Popen(
        [sys.executable, CCJJ, "commit", "-m", "x"], cwd=repo.root,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        env={**os.environ, "CC_JJ_JOURNAL": repo.journal, "CLAUDE_SESSION_ID": "S1",
             "PATH": str(stub) + os.pathsep + os.environ["PATH"]})
    time.sleep(1.0)
    _hook_edit(repo, "S1", "b.txt", "b", "B")              # a subagent, mid-commit
    _, err = p.communicate()
    assert p.returncode == 0, err
    assert repo.show("b.txt") == b"b\n"
    r = repo.run("commit", "-m", "y", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("b.txt") == b"B\n"


def test_next_commit_does_not_stop_on_files_the_last_commit_took(repo):
    """A restored .last let commit-mine's own Bash hook open a window over the
    edits it had just committed, so the next commit exited 5 naming them."""
    repo.write("a.txt", "a\n")
    repo.write("b.txt", "b\n")
    repo.commit("base")
    _optin(repo)
    open(os.path.join(repo.root, ".jj", "ccjj-contended"), "w").close()
    _bash(repo, "S1", tuid="t1")
    _hook_edit(repo, "S1", "a.txt", "a", "A")
    r = repo.run("commit", "-m", "first", sid="S1")
    assert r.returncode == 0, r.stderr
    _bash(repo, "S1", tuid="t2")          # commit-mine's own PostToolUse
    _hook_edit(repo, "S1", "b.txt", "b", "B")
    r = repo.run("commit", "-m", "second", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("b.txt") == b"B\n"


def test_commit_does_not_restore_a_dead_owner(repo):
    """After a resume .owner names the dead process. A commit used to clear it,
    so the next hook stamped the live one; restoring it kept the session
    "ended" and let a peer take the whole-copy route over its work."""
    repo.write("f.txt", "f\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")
    _hook_edit(repo, "S1", "f.txt", "f", "F")
    # The first commit runs the once-a-day prune, which would hide the defect.
    r = repo.run("commit", "-m", "first", sid="S1")
    assert r.returncode == 0, r.stderr
    _hook_edit(repo, "S1", "g.txt", "g", "G")
    _owner(repo, "S1", "1", "Thu Jan  1 00:00:00 1970")
    r = repo.run("commit", "-m", "second", sid="S1")
    assert r.returncode == 0, r.stderr
    owner = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1", ".owner")
    assert not os.path.exists(owner)


def test_also_through_a_directory_symlink_commits_the_real_file(repo):
    """Only the last component stays literal. jj tracks real/f.txt, so
    `--also ln/f.txt` matched nothing and still reported success."""
    os.makedirs(os.path.join(repo.root, "real"))
    repo.write("real/f.txt", "old\n")
    repo.write("mine.txt", "m\n")
    os.symlink("real", os.path.join(repo.root, "ln"))
    repo.commit("base")
    repo.write("real/f.txt", "new\n")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "ln/f.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("real/f.txt") == b"new\n"


def _two_files(repo):
    repo.write("f.txt", "f\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")


def test_commit_after_compaction_includes_the_earlier_edits(repo, monkeypatch):
    """A new session id in the same process made the earlier edits a "live
    peer": commit-mine left them out and still reported "verified"."""
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    _hook_edit(repo, "PRE", "f.txt", "f", "F")
    _hook_edit(repo, "POST", "g.txt", "g", "G")
    assert repo.run("should-scope", "-q", sid="POST").returncode == 1
    r = repo.run("commit", "-m", "x", sid="POST")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"F\n"
    assert repo.show("g.txt") == b"G\n"


def test_commit_straight_after_compaction_finds_the_earlier_edits(repo, monkeypatch):
    """commit-mine can be the first call under the new id, before any hook."""
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    _hook_edit(repo, "PRE", "f.txt", "f", "F")
    r = repo.run("commit", "-m", "x", sid="POST")
    assert r.returncode == 0, r.stderr
    assert "before /clear or compaction" in r.stderr
    assert repo.show("f.txt") == b"F\n"


def test_claim_after_compaction_sees_the_earlier_bash_window(repo, monkeypatch):
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    _optin(repo)
    _bash(repo, "PRE", tuid="t1")
    repo.write("f.txt", "bash\n")
    _bash(repo, "PRE", tuid="t2")
    r = repo.run("claim", "f.txt", sid="POST")
    assert r.returncode == 0, r.stderr
    r = repo.run("commit", "-m", "x", sid="POST")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"bash\n"


def test_another_process_journal_is_not_absorbed(repo, monkeypatch):
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    peer = subprocess.Popen(["sleep", "120"])
    try:
        lstart = subprocess.run(["ps", "-o", "lstart=", "-p", str(peer.pid)],
                                capture_output=True, text=True).stdout.strip()
        repo.record("PEER", "f.txt", old="f", new="F", original="f\n")
        _owner(repo, "PEER", str(peer.pid), lstart)
        repo.write("f.txt", "F\n")
        _hook_edit(repo, "POST", "g.txt", "g", "G")
        assert repo.run("should-scope", "-q", sid="POST").returncode == 0
        r = repo.run("commit", "-m", "x", sid="POST")
        assert r.returncode == 0, r.stderr
        assert repo.show("f.txt") == b"f\n"          # the peer's work not taken
    finally:
        peer.kill()
        peer.wait()


def test_journal_past_the_stale_limit_is_not_absorbed(repo, monkeypatch):
    """An abandoned edit from long before a /clear must not rejoin commits."""
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    _hook_edit(repo, "PRE", "f.txt", "f", "F")
    d = os.path.join(repo.journal, repo.root.replace("/", "_"), "PRE")
    old = time.time() - 13 * 3600
    for n in os.listdir(d):
        os.utime(os.path.join(d, n), (old, old))
    _hook_edit(repo, "POST", "g.txt", "g", "G")
    r = repo.run("commit", "-m", "x", sid="POST")
    assert r.returncode == 0, r.stderr
    assert repo.show("f.txt") == b"f\n"
    assert repo.show("g.txt") == b"G\n"


def test_resumed_session_replaces_its_dead_owner(repo, monkeypatch):
    """--resume keeps the session id in a new process. A written-once .owner
    read as "ended" while the session worked."""
    monkeypatch.setenv("CLAUDE_PID", str(os.getpid()))
    _two_files(repo)
    _hook_edit(repo, "S1", "f.txt", "f", "F")
    _owner(repo, "S1", "1", "Thu Jan  1 00:00:00 1970")
    _hook_edit(repo, "S1", "g.txt", "g", "G")
    owner = os.path.join(repo.journal, repo.root.replace("/", "_"), "S1", ".owner")
    assert open(owner).read().startswith(str(os.getpid()) + "\t")


# ---------------------------- moves and deletes: advice, previews and wording

LONG = "".join("line %d\n" % i for i in range(40))


def _moved(repo, sid="S1"):
    """In one Bash window: old.txt moved to new.txt, gone.txt deleted, sed.txt edited."""
    _optin(repo)
    repo.write("old.txt", LONG)
    repo.write("gone.txt", "bye\n")
    repo.write("sed.txt", "s\n")
    repo.commit("base")
    _bash(repo, sid)
    os.rename(os.path.join(repo.root, "old.txt"), os.path.join(repo.root, "new.txt"))
    os.remove(os.path.join(repo.root, "gone.txt"))
    repo.write("sed.txt", "s-via-sed\n")
    _bash(repo, sid)


def _also_line(text):
    lines = [l for l in text.splitlines() if 'commit-mine -m "msg"' in l]
    assert len(lines) == 1, text
    return lines[0]


def test_audit_routes_moves_and_deletes_to_one_also_line(repo):
    """audit printed `ccjj claim` for every path in your window, and claim always
    refuses renames and deletes. A per-path --also would strand half a rename."""
    _moved(repo)
    r = repo.run("audit", sid="S1")
    for p in ("old.txt", "new.txt", "gone.txt"):
        assert "ccjj claim " + p not in r.stderr, r.stderr
    assert "ccjj claim sed.txt" in r.stderr
    line = _also_line(r.stderr)
    assert "--also old.txt --also new.txt" in line
    assert line.count("--also old.txt") == 1 and "--also gone.txt" in line


def test_exit_5_routes_moves_and_deletes_to_one_also_line(repo):
    _moved(repo)
    r = repo.run("commit", "-m", "x", "--also", "sed.txt", sid="S1")
    assert r.returncode == 5, r.stdout + r.stderr
    assert "ccjj claim" not in r.stderr, r.stderr
    line = _also_line(r.stderr)
    assert "--also old.txt --also new.txt" in line and "--also gone.txt" in line


def test_exit_5_following_the_advice_commits_both_halves(repo):
    _moved(repo)
    r = repo.run("commit", "-m", "x", "--also", "old.txt", sid="S1")
    assert r.returncode == 5, r.stdout + r.stderr
    # Partner named even though old.txt was already passed: a lone half strands
    # the other, so the advice must never be narrower than the whole move.
    assert "--also old.txt --also new.txt" in _also_line(r.stderr)

    assert repo.run("claim", "sed.txt", sid="S1").returncode == 0
    ok = repo.run("commit", "-m", "x", "--also", "old.txt", "--also", "new.txt",
                  "--also", "gone.txt", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("new.txt") == LONG.encode()
    assert repo.show("old.txt") in (None, b"")
    assert repo.show("sed.txt") == b"s-via-sed\n"


def _edited_and_loose(repo):
    _optin(repo)
    repo.write("edited.txt", "a\n")
    repo.write("sedded.txt", "s\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")
    _bash(repo)
    repo.write("sedded.txt", "s-via-sed\n")
    _bash(repo)
    repo.write("edited.txt", "A\n")
    repo.record("S1", "edited.txt", old="a", new="A", original="a\n")


def test_diff_previews_through_the_unclaimed_refusal(repo):
    _edited_and_loose(repo)
    r = repo.run("commit", "--diff", sid="S1")
    assert r.returncode == 5, r.stderr            # ai_jj_commit stops on this
    assert "+A" in r.stdout
    assert "a real commit would refuse" in r.stderr
    assert "ccjj claim sedded.txt" in r.stderr
    assert repo.show("edited.txt") == b"a\n"


def test_diff_previews_through_the_also_refusal(repo):
    repo.write("f.txt", "a\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")
    repo.write("f.txt", "A\n")
    repo.record("S1", "f.txt", old="a", new="A", original="a\n")
    repo.write("g.txt", "g-S2\n")
    repo.record("S2", "g.txt", old="g", new="g-S2", original="g\n")

    r = repo.run("commit", "--diff", "--also", "g.txt", sid="S1")
    assert r.returncode == 1, r.stderr
    assert "+A" in r.stdout
    assert "whole path, taken from the working copy) g.txt" in r.stdout
    assert "a stake in them" in r.stderr
    assert repo.show("g.txt") == b"g\n"


def test_diff_exits_with_the_first_refusals_code(repo):
    """Exit 0 would spend a model call and then refuse."""
    _edited_and_loose(repo)
    repo.write("g.txt", "g-S2\n")
    repo.record("S2", "g.txt", old="g", new="g-S2", original="g\n")

    r = repo.run("commit", "--diff", "--also", "g.txt", sid="S1")
    assert r.returncode == 1, r.stderr            # --also came first, not the 5
    assert "a stake in them" in r.stderr
    assert "ccjj claim sedded.txt" in r.stderr
    assert "+A" in r.stdout


def test_diff_still_stops_on_a_build_conflict(repo):
    repo.write("f.txt", "shared line\n")
    repo.commit("base")
    repo.write("f.txt", "theirs\n")
    repo.commit("theirs")
    repo.write("f.txt", "mine\n")
    repo.record("S1", "f.txt", old="shared line", new="mine", original="shared line\n")

    r = repo.run("commit", "--diff", sid="S1")
    assert r.returncode != 0
    assert "conflict" in r.stderr.lower()
    assert "+mine" not in r.stdout


def _window_peer(repo, path="peer.txt", peer="S2"):
    """`peer`'s Bash window covers a change to path; S1 has an edit elsewhere."""
    _optin(repo)
    repo.write(path, "p\n")
    repo.write("mine.txt", "m\n")
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, peer)
    repo.write(path, "p-changed\n")
    _bash(repo, peer)
    _bash(repo, "S1")


def test_claim_says_a_window_only_peer_may_not_have_touched_the_path(repo):
    """window_span runs first to last Bash call, so an idle peer still counts."""
    _window_peer(repo)
    r = repo.run("claim", "peer.txt", sid="S1")
    assert r.returncode == 1                       # the refusal itself stays
    assert "Bash span of session(s) S2 (live)" in r.stderr
    assert "may not have touched" in r.stderr
    assert "claimed" not in r.stderr and "overlap" not in r.stderr
    assert not repo.journal_records("S1")


def test_claim_keeps_the_claimed_wording_for_a_peer_with_records(repo):
    _optin(repo)
    repo.write("shared.txt", "base\n")
    repo.commit("base")
    _bash(repo, sid="S1")
    repo.write("shared.txt", "base\ntheirs\n")
    repo.record("S2", "shared.txt", old="base\n", new="base\ntheirs\n", original="base\n")
    _bash(repo, sid="S1")
    r = repo.run("claim", "shared.txt", sid="S1")
    assert r.returncode == 1
    assert "also claimed by session(s) S2 (live)" in r.stderr
    assert "may not have touched" not in r.stderr


def test_claim_keeps_records_over_a_window_across_a_rename(repo):
    """stakes.update let a window-only result for one half of a rename overwrite
    the records result for the other."""
    _optin(repo)
    repo.write("old.txt", LONG)
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, "S2")
    os.rename(os.path.join(repo.root, "old.txt"), os.path.join(repo.root, "new.txt"))
    repo.record("S2", "old.txt", old="line 1", new="LINE 1", original=LONG)
    _bash(repo, "S2")
    _bash(repo, "S1")
    # The halves are walked as a set, so which one lands last depends on the
    # string hash. Several seeds, or the overwrite would slip through by luck.
    for seed in "1234":
        r = repo.run("claim", "new.txt", sid="S1", env={"PYTHONHASHSEED": seed})
        assert r.returncode == 1
        assert "also claimed by session(s) S2" in r.stderr
        assert "Bash span of" not in r.stderr


def test_also_refusal_for_a_window_only_peer_makes_no_claim_of_a_stake(repo):
    _window_peer(repo)
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "peer.txt", "--no-claim", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "Bash span only: S2 (live)" in r.stderr
    assert "may not have touched" in r.stderr
    assert "stake" not in r.stderr and "claimed" not in r.stderr
    assert repo.show("peer.txt") == b"p\n"


def test_also_refusal_separates_records_from_windows(repo):
    _window_peer(repo, peer="S3")
    repo.record("S2", "peer.txt", old="p\n", new="p-changed\n", original="p\n")
    _hook_edit(repo, "S1", "mine.txt", "m", "M")
    r = repo.run("commit", "-m", "x", "--also", "peer.txt", "--no-claim", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "records: S2 (live); Bash span only: S3 (live)" in r.stderr
    assert "a stake in them" in r.stderr


def _peer_over_a_move(repo, edit=False):
    """S1 moves old.txt to new.txt inside a span of S2's Bash calls."""
    _optin(repo)
    repo.write("old.txt", LONG)
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, "S2")
    os.rename(os.path.join(repo.root, "old.txt"), os.path.join(repo.root, "new.txt"))
    if edit:
        repo.write("new.txt", LONG.replace("line 7\n", "line seven\n"))
    _bash(repo, "S2")
    _bash(repo, "S1")


def test_also_refusal_marks_a_move_with_identical_bytes_and_still_refuses(repo):
    """The note is information only: the guard refuses exactly as before."""
    _peer_over_a_move(repo)
    r = repo.run("commit", "-m", "x", "--also", "old.txt", "--also", "new.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert r.stderr.count("[move, bytes identical to @-]") == 2, r.stderr
    assert repo.show("new.txt") in (None, b"")


def test_also_refusal_does_not_mark_a_move_that_was_edited(repo):
    _peer_over_a_move(repo, edit=True)
    status = repo.jj_("diff", "--from", "@-", "--to", "@", "-T", 'self.status() ++ "\\n"')
    assert "renamed" in status.stdout              # jj still pairs the halves
    r = repo.run("commit", "-m", "x", "--also", "old.txt", "--also", "new.txt", sid="S1")
    assert r.returncode == 1, r.stdout
    assert "bytes identical" not in r.stderr


# ----------------------------------------------------------- moved-base warning

def test_drift_skips_an_ended_session_with_an_empty_journal(repo):
    """One Bash call stamps .base and writes nothing else, so the session never
    held work that could have been swept."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _base(repo, "S1", _parent_id(repo))
    _ended(repo, "S1")
    repo.commit("stray")
    r = repo.run("audit", sid="S9")
    assert "@- has moved" not in r.stderr, r.stderr


def test_drift_keeps_an_ended_session_with_only_bash_windows(repo):
    """No records, but its Bash work may be what got swept."""
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo, "S1")
    repo.write("f.txt", "b\n")
    _bash(repo, "S1")
    _ended(repo, "S1")
    repo.commit("stray")
    r = repo.run("audit", sid="S9")
    assert "@- has moved" in r.stderr, r.stderr


def test_drift_keeps_a_live_session_with_an_empty_journal(repo):
    """session_is_live is False for any journal with no activity, so using it
    here would silence every session that has only just started."""
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _base(repo, "S1", _parent_id(repo))
    _owner(repo, "S1", str(os.getpid()), _my_lstart())
    repo.commit("stray")
    r = repo.run("audit", sid="S9")
    assert "@- has moved" in r.stderr, r.stderr


def test_drift_merges_every_no_restore_case_into_one_line(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    for sid, fake in (("S1", "a" * 40), ("S2", "b" * 40)):
        repo.record(sid, "f.txt", old="a", new="A", original="a\n")
        _base(repo, sid, fake)
    r = repo.run("audit", sid="S9")
    assert "@- has moved" in r.stderr
    assert r.stderr.count("no action is needed") == 1, r.stderr
    assert "No undo is available for 2 older base(s)" in r.stderr
    assert "after 48 hours idle" in r.stderr
    assert "jj op restore" not in r.stderr


# --------------------------------------------------------------------- ccjj who

def test_who_lists_each_sessions_state_and_kind_of_stake(repo):
    _optin(repo)
    repo.write("shared.txt", "base\n")
    repo.commit("base")
    _bash(repo, "S1")
    _bash(repo, "S2")
    repo.write("shared.txt", "base\nmore\n")
    repo.record("S1", "shared.txt", old="base\n", new="base\nmore\n", original="base\n")
    repo.record("S3", "shared.txt", old="base\n", new="base\nmore\n", original="base\n")
    _ended(repo, "S3")
    _bash(repo, "S2")
    _bash(repo, "S1")

    r = repo.run("who", "shared.txt", sid="S1")
    assert r.returncode == 0, r.stderr
    rows = {l.split()[0]: l.split(None, 1)[1] for l in r.stdout.splitlines()[1:]}
    assert rows["S1"].split() == ["live", "records", "(this", "session)"]
    assert rows["S2"].split() == ["live", "window", "only"]
    assert rows["S3"].split() == ["ended", "records"]


def test_who_does_not_snapshot_the_working_copy(repo):
    """A snapshot landing inside another session's commit kills it."""
    _optin(repo)
    repo.write("f.txt", "a\n")
    repo.commit("base")
    _bash(repo, "S1")
    repo.write("f.txt", "b\n")
    _bash(repo, "S1")
    repo.write("unsnapshotted.txt", "new\n")
    before = repo.op_head()
    assert repo.run("who", "f.txt", sid="S1").returncode == 0
    assert repo.op_head() == before


def test_who_says_so_when_nobody_has_a_stake(repo):
    repo.write("f.txt", "a\n")
    repo.commit("base")
    r = repo.run("who", "f.txt", sid="S1")
    assert r.returncode == 0
    assert "no session has" in r.stdout


# ------------------------- exit 5: a span that holds another session's commit

def _peer_moves_and_commits(repo, sid="S1"):
    """A peer moves a file and commits, between two of this session's Bash calls."""
    _optin(repo)
    repo.write("moved.txt", LONG)
    repo.write("own.txt", "o\n")
    repo.write("other.txt", "x\n")
    repo.commit("base")
    _bash(repo, sid)
    os.rename(os.path.join(repo.root, "moved.txt"), os.path.join(repo.root, "dest.txt"))
    repo.write("other.txt", "peer committed\n")
    repo.commit("peer commit")
    _bash(repo, sid, tuid="t2")


def test_commit_does_not_stop_on_paths_committed_inside_the_span(repo):
    _peer_moves_and_commits(repo)
    _hook_edit(repo, "S1", "own.txt", "o", "O")
    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode == 0, r.stderr
    assert repo.show("own.txt") == b"O\n"


def test_uncommitted_bash_change_stops_without_naming_committed_moves(repo):
    _peer_moves_and_commits(repo)
    _hook_edit(repo, "S1", "own.txt", "o", "O")
    repo.write("other.txt", "my bash change\n")
    _bash(repo, "S1", tuid="t3")
    r = repo.run("commit", "-m", "mine", sid="S1")
    assert r.returncode == 5, r.stderr
    assert "ccjj claim other.txt" in r.stderr, r.stderr
    assert "moved.txt" not in r.stderr, r.stderr
    assert "--also" not in r.stderr.replace("--no-claim", ""), r.stderr


def test_uncommitted_rename_still_stops_and_names_both_halves(repo):
    _moved(repo)
    r = repo.run("commit", "-m", "x", "--also", "sed.txt", sid="S1")
    assert r.returncode == 5, r.stderr
    assert "--also old.txt --also new.txt" in _also_line(r.stderr)


def test_also_advice_omits_the_half_of_a_move_already_committed(repo):
    """--also dies on a path in neither the working copy nor @-, so naming the
    committed half made the whole printed command unusable."""
    _peer_moves_and_commits(repo)
    repo.write("dest.txt", LONG + "tail from bash\n")
    _bash(repo, "S1", tuid="t3")
    _hook_edit(repo, "S1", "own.txt", "o", "O")
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 5, r.stderr
    line = _also_line(r.stderr)
    assert "--also moved.txt" not in line, line
    assert "--also dest.txt" in line, line
    ok = repo.run("commit", "-m", "x", "--also", "dest.txt", sid="S1")
    assert ok.returncode == 0, ok.stderr
    assert repo.show("dest.txt") == (LONG + "tail from bash\n").encode()


def test_records_that_differ_from_disk_stop_even_when_the_path_equals_parent(repo):
    """Filtering this branch on "differs from @-" turned exit 5, with a claim
    that works, into "the commit did not take" and a rollback."""
    _optin(repo)
    repo.write("f.txt", "a\nb\n")
    repo.write("g.txt", "g\n")
    repo.commit("base")
    _bash(repo)
    _hook_edit(repo, "S1", "f.txt", "a", "A")          # record a->A
    repo.write("f.txt", "a\nB\n")                       # Bash undoes it, changes b
    _bash(repo, tuid="t2")
    repo.commit("peer sweeps whole working copy")      # @- has a\nB, @ == @- for f
    _bash(repo, tuid="t3")
    _hook_edit(repo, "S1", "g.txt", "g", "G")
    r = repo.run("commit", "-m", "x", sid="S1")
    assert r.returncode == 5, r.stdout + r.stderr
    assert "ccjj claim f.txt" in r.stderr
