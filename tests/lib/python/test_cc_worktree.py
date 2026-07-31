"""Tests for lib/python/cc_worktree.py — per-session worktree isolation.

Each test names the defect it pins. Every one of these fails *silently* in
production if the guard is removed: the session runs un-isolated, or on top of
another session, or work is deleted rather than trashed.

`trash` is stubbed onto PATH so a test run never touches ~/.Trash, and so the
"trash refused" branch can be forced.
"""
import json
import os
import shutil
import subprocess
import sys
import threading

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))), "lib", "python"))
import cc_worktree  # noqa: E402  (path set above)

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CCWT = os.path.join(DOTFILES, "lib", "python", "cc_worktree.py")

TRASH_STUB = """\
#!/bin/bash
# Test stub for `trash`: move into $CC_TEST_TRASH instead of ~/.Trash.
if [ -n "$CC_TEST_TRASH_FAIL" ]; then echo "trash: refused" >&2; exit 1; fi
mkdir -p "$CC_TEST_TRASH"
n=0
for p in "$@"; do
  n=$((n+1))
  mv "$p" "$CC_TEST_TRASH/$(basename "$p").$n" || exit 1
done
"""


class Repo:
    """A throwaway git or jj repo with isolated state and trash."""

    def __init__(self, base, backend):
        self.backend = backend
        self.base = os.path.realpath(base)
        self.root = os.path.join(self.base, "repo")
        self.state = os.path.join(self.base, "state")
        self.trash = os.path.join(self.base, "trash")
        self.bin = os.path.join(self.base, "bin")
        os.makedirs(self.root)
        os.makedirs(self.bin)
        stub = os.path.join(self.bin, "trash")
        with open(stub, "w") as fh:
            fh.write(TRASH_STUB)
        os.chmod(stub, 0o755)

        if backend == "jj":
            self._run(["jj", "git", "init"])
        else:
            self._run(["git", "init", "-q", "-b", "master", "."])
            self._run(["git", "config", "user.email", "t@example.com"])
            self._run(["git", "config", "user.name", "t"])
        self.write("a.txt", "hello\n")
        self.write(".gitignore", ".env\nnode_modules\n.venv\n.claude/\n.cc-config\n")
        self.commit("init")

    # ---------------------------------------------------------------- plumbing

    def _run(self, cmd, cwd=None):
        return subprocess.run(cmd, cwd=cwd or self.root, capture_output=True,
                              text=True, env=self.env())

    def env(self, **extra):
        e = {**os.environ,
             "CC_WORKTREE_STATE": self.state,
             "CC_TEST_TRASH": self.trash,
             "JJ_USER": "t", "JJ_EMAIL": "t@example.com",
             "PATH": self.bin + os.pathsep + os.environ.get("PATH", "")}
        e.update({k: v for k, v in extra.items() if v is not None})
        for k, v in extra.items():
            if v is None:
                e.pop(k, None)
        return e

    def write(self, rel, data):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(data)

    def commit(self, msg):
        if self.backend == "jj":
            self._run(["jj", "commit", "-m", msg])
        else:
            self._run(["git", "add", "-A"])
            self._run(["git", "commit", "-qm", msg])

    def cc(self, *args, cwd=None, **envextra):
        return subprocess.run([sys.executable, CCWT, *args], cwd=cwd or self.root,
                              capture_output=True, text=True, env=self.env(**envextra))

    def marker(self, text):
        d = os.path.join(self.root, ".jj" if self.backend == "jj" else ".git")
        with open(os.path.join(d, "cc-worktree"), "w") as fh:
            fh.write(text)

    def trashed(self):
        try:
            return sorted(os.listdir(self.trash))
        except OSError:
            return []

    def trashed_file(self, *parts):
        """Content of a path inside the (single) trashed slot directory."""
        for name in self.trashed():
            p = os.path.join(self.trash, name, *parts)
            if os.path.exists(p):
                with open(p) as fh:
                    return fh.read()
        return None

    # ------------------------------------------------------------------ slots

    def wt(self, slot="w-01", *parts):
        return os.path.join(self.root, ".claude", "worktrees", slot, *parts)

    def owner(self, slot="w-01"):
        return os.path.join(self.root, ".claude", "worktrees", slot + ".owner")

    def hold(self, slot="w-01"):
        return os.path.join(self.root, ".claude", "worktrees", slot + ".hold")

    def orphan(self, slot="w-01"):
        """Make the slot's owner unmistakably dead, as a crash leaves it."""
        rec = json.load(open(self.owner(slot)))
        rec["pid"] = 999999
        rec["pid_lstart"] = "Thu Jan  1 00:00:00 2026"
        with open(self.owner(slot), "w") as fh:
            json.dump(rec, fh)

    def branches(self):
        r = self._run(["git", "branch", "--format=%(refname:short)"])
        return [b for b in r.stdout.split() if b]

    def bookmarks(self):
        r = self._run(["jj", "bookmark", "list", "--ignore-working-copy"])
        return [ln.split(":", 1)[0].strip() for ln in r.stdout.splitlines() if ":" in ln]

    def in_worktree(self, cmd, slot="w-01"):
        return subprocess.run(cmd, cwd=self.wt(slot), capture_output=True,
                              text=True, env=self.env())


@pytest.fixture
def git_repo(tmp_path):
    return Repo(str(tmp_path), "git")


@pytest.fixture
def jj_repo(tmp_path):
    return Repo(str(tmp_path), "jj")


needs_jj = pytest.mark.skipif(shutil.which("jj") is None, reason="jj not installed")


# ------------------------------------------------------------- opt-in refusals

def test_on_refuses_dotfiles(git_repo):
    """Pins: opting in a repo that CANNOT be isolated.

    About half of ~/dotfiles' tracked files load by absolute path, so a worktree
    copy is not the live configuration -- isolation there is silently a lie.
    """
    r = git_repo.cc("on", CC_WORKTREE_DOTFILES=git_repo.root)
    assert r.returncode == 1
    assert "ccjj" in r.stderr
    assert not os.path.exists(os.path.join(git_repo.root, ".git", "cc-worktree"))


def test_nesting_refused_git(git_repo):
    """Pins: recursive worktrees (git).

    From inside a linked worktree --git-common-dir finds the PARENT's marker, so
    without the --git-dir != --git-common-dir check `on` and `create` happily
    nest a worktree inside a worktree.
    """
    wt = os.path.join(git_repo.base, "plain-wt")
    git_repo._run(["git", "worktree", "add", "-q", "-b", "side", wt])
    assert os.path.isfile(os.path.join(wt, ".git")), ".git must be a FILE here"
    r = git_repo.cc("on", cwd=wt)
    assert r.returncode == 1
    assert "linked git worktree" in r.stderr


@needs_jj
def test_nesting_refused_jj(jj_repo):
    """Pins: recursive workspaces (jj). .jj/repo is a FILE in a workspace."""
    ws = os.path.join(jj_repo.base, "plain-ws")
    jj_repo._run(["jj", "workspace", "add", "--name", "side", ws])
    assert os.path.isfile(os.path.join(ws, ".jj", "repo"))
    r = jj_repo.cc("on", cwd=ws)
    assert r.returncode == 1
    assert "jj workspace" in r.stderr


def test_nesting_refused_slot_path(git_repo):
    """Pins: opting in from inside a slot. Resolving a hold sends you there."""
    git_repo.cc("on")
    slot = os.path.join(git_repo.root, ".claude", "worktrees", "w-01")
    git_repo._run(["git", "worktree", "add", "-q", "-b", "w-01", slot])
    r = git_repo.cc("on", cwd=slot)
    assert r.returncode == 1
    assert "cc-worktree slot" in r.stderr


# ---------------------------------------------------------------- marker lookup

def test_marker_found_when_dot_git_is_a_file(git_repo):
    """Pins: `<root>/.git/cc-worktree` in a linked worktree or a submodule.

    .git is a FILE there, so joining a filename onto it yields a path that can
    never be opened -- the marker is silently not found and isolation quietly
    does not happen. Only --git-common-dir resolves it.
    """
    git_repo.cc("on")
    wt = os.path.join(git_repo.base, "plain-wt")
    git_repo._run(["git", "worktree", "add", "-q", "-b", "side", wt])
    assert os.path.isfile(os.path.join(wt, ".git"))
    r = git_repo.cc("status", cwd=wt)
    assert r.returncode == 0, r.stderr
    assert "10 slots" in r.stdout


@needs_jj
def test_on_refuses_untracked_link_entry_in_jj(jj_repo):
    """Pins: jj auto-tracks.

    A symlinked node_modules in a workspace is snapshotted AS A SYMLINK pointing
    into the parent and committed into history. jj has no check-ignore, so the
    only reliable test is a probe workspace.
    """
    os.makedirs(os.path.join(jj_repo.root, "vendorstuff"))
    jj_repo.write("vendorstuff/x", "x\n")
    jj_repo.marker("vendorstuff\nnode_modules\n")
    r = jj_repo.cc("on")
    assert r.returncode == 1
    assert "vendorstuff" in r.stderr
    # node_modules IS ignored, so it must not be named -- a validator that names
    # everything is one nobody can act on.
    assert "node_modules" not in r.stderr
    assert not os.path.exists(os.path.join(jj_repo.root, ".claude", "worktrees",
                                           ".cc-probe"))


@needs_jj
def test_on_accepts_ignored_link_entries_in_jj(jj_repo):
    """The probe must not refuse the normal case, or nothing can ever opt in."""
    r = jj_repo.cc("on")
    assert r.returncode == 0, r.stderr + r.stdout
    assert os.path.exists(os.path.join(jj_repo.root, ".jj", "cc-worktree"))


# --------------------------------------------------------------- marker parsing

def test_marker_parsing_defaults_and_options(git_repo):
    git_repo.marker("# a comment\n\nmax-slots: 3\ncopy:.tool-versions\nnode_modules\n")
    r = git_repo.cc("status")
    assert r.returncode == 0, r.stderr
    assert "3 slots" in r.stdout
    assert "copy:.tool-versions" in r.stdout
    assert "node_modules" in r.stdout
    # Explicit entries REPLACE the defaults; they are not merged.
    assert ".envrc" not in r.stdout


def test_empty_marker_means_defaults(git_repo):
    git_repo.marker("# nothing but comments\n")
    r = git_repo.cc("status")
    assert ".cc-config" in r.stdout and ".envrc" in r.stdout


def test_status_exits_2_when_not_opted_in(git_repo):
    """Exit 2 is how the wrapper tells "not opted in" from "failed"."""
    r = git_repo.cc("status")
    assert r.returncode == 2


def test_off_removes_marker_and_registry(git_repo):
    git_repo.cc("on")
    assert git_repo.root in open(os.path.join(git_repo.state, "repos")).read()
    r = git_repo.cc("off")
    assert r.returncode == 0
    assert not os.path.exists(os.path.join(git_repo.root, ".git", "cc-worktree"))
    assert git_repo.root not in open(os.path.join(git_repo.state, "repos")).read()


# ------------------------------------------------------------ slot allocation

def test_slot_race_two_claimers(git_repo):
    """Pins: check-then-create TOCTOU.

    Two sessions landing in ONE worktree is the exact failure this whole design
    exists to prevent, and it is silent -- they just start overwriting each
    other. os.link is atomic and fails EEXIST; `if exists: ... else: write` has
    a window wide enough to lose the race in practice.

    Run over ten slots so a single lucky interleaving cannot pass a broken
    implementation.
    """
    os.makedirs(git_repo.wt().rsplit("/", 1)[0], exist_ok=True)
    for n in range(1, 11):
        slot = "w-%02d" % n
        winners = []
        lock = threading.Lock()
        barrier = threading.Barrier(24)

        def claimer(i):
            barrier.wait()
            if cc_worktree.claim(git_repo.root, slot, {"pid": i}):
                with lock:
                    winners.append(i)

        threads = [threading.Thread(target=claimer, args=(i,)) for i in range(24)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert len(winners) == 1, "slot %s claimed %d times" % (slot, len(winners))
        # And the visible record is complete, never a half-written file.
        assert json.load(open(git_repo.owner(slot)))["pid"] == winners[0]


def test_claim_survives_kill_before_create(git_repo):
    """Pins: a claimed-but-empty slot leaking forever.

    A crash between the claim and `git worktree add` leaves an .owner with no
    directory. Nothing else in the system would ever remove it, so the slot is
    gone from the pool for good.
    """
    git_repo.cc("on")
    os.makedirs(git_repo.wt().rsplit("/", 1)[0], exist_ok=True)
    with open(git_repo.owner(), "w") as fh:
        json.dump({"pid": 999999, "pid_lstart": "x", "slot": "w-01",
                   "branch": None, "backend": "git", "repo": git_repo.root}, fh)
    r = git_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.exists(git_repo.owner())


def test_dir_without_owner_is_reaped(git_repo):
    """Pins: a tree no reaper enumerates.

    A crash between `git worktree add` and the claim -- or a hand-deleted
    .owner -- leaves a directory that an owner-only enumeration never sees.

    The backend registration is destroyed too, so that the DIRECTORY scan is the
    only thing that can find this slot. With the registration left in place the
    union's other leg covers for a broken enumeration and the guard is never
    exercised.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    os.unlink(git_repo.owner())
    shutil.rmtree(os.path.join(git_repo.root, ".git", "worktrees", "w-01"))
    assert os.path.isdir(git_repo.wt())
    r = git_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(git_repo.wt())
    assert git_repo.trashed()


def test_pid_alive_lstart_differs_is_dead(git_repo):
    """Pins: pid recycling.

    The recorded pid really is running -- it is this test process -- but it is a
    different process than the one that claimed the slot. Without the lstart
    half of the identity check the slot looks live forever.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    rec = json.load(open(git_repo.owner()))
    rec["pid"] = os.getpid()
    rec["pid_lstart"] = "Thu Jan  1 00:00:00 2026"
    with open(git_repo.owner(), "w") as fh:
        json.dump(rec, fh)
    git_repo.cc("reap")
    assert not os.path.exists(git_repo.owner())
    assert not os.path.isdir(git_repo.wt())


def test_all_slots_held_fails_loudly(git_repo):
    """Pins: silently running un-isolated when the pool is exhausted."""
    git_repo.marker("max-slots: 2\n.cc-config\n")
    wt = os.path.join(git_repo.root, ".claude", "worktrees")
    os.makedirs(wt)
    for slot in ("w-01", "w-02"):
        with open(os.path.join(wt, slot + ".owner"), "w") as fh:
            json.dump({"pid": 999999, "pid_lstart": "x", "slot": slot}, fh)
        with open(os.path.join(wt, slot + ".hold"), "w") as fh:
            fh.write("uncommitted\n")
    r = git_repo.cc("create")
    assert r.returncode == 1
    # The exhaustion sentence itself, not just the held-slot notices the
    # piggybacked reap prints anyway -- those appear either way and would let a
    # silent failure pass.
    assert "every one of the 2 slots" in r.stderr
    assert "w-01" in r.stderr and "w-02" in r.stderr
    assert "cc-worktree release w-01 --land" in r.stderr
    assert r.stdout.strip() == "", "stdout must stay clean: the wrapper cd's into it"


# --------------------------------------------------------------- the link list

def test_link_list_resolves_in_worktree(git_repo):
    """Pins: draft one's defect 2.

    gitignore_global line 2 is `.*`, so .cc-config and .claude/ are absent from
    a fresh worktree -- `cc-config sync` then no-ops and the session runs
    unconfigured, silently. Parent directories must be created too.
    """
    git_repo.write(".cc-config", "default\n")
    git_repo.write(".claude/settings.json", '{"a": 1}\n')
    git_repo.cc("on")
    r = git_repo.cc("create")
    assert r.returncode == 0, r.stderr

    assert os.path.islink(git_repo.wt("w-01", ".cc-config"))
    assert os.path.islink(git_repo.wt("w-01", ".claude", "settings.json"))
    # Absolute and parent-pointing, so removing the worktree destroys neither,
    # and an edit inside the worktree lands in the parent.
    assert os.readlink(git_repo.wt("w-01", ".cc-config")) == \
        os.path.join(git_repo.root, ".cc-config")
    with open(git_repo.wt("w-01", ".claude", "settings.json"), "w") as fh:
        fh.write('{"a": 2}\n')
    assert open(os.path.join(git_repo.root, ".claude", "settings.json")).read() == \
        '{"a": 2}\n'


def test_copy_prefix_diverges(git_repo):
    git_repo.write(".tool-versions", "python 3.11\n")
    git_repo.marker("copy:.tool-versions\n")
    git_repo.cc("create")
    p = git_repo.wt("w-01", ".tool-versions")
    assert os.path.isfile(p) and not os.path.islink(p)
    with open(p, "w") as fh:
        fh.write("python 3.12\n")
    assert open(os.path.join(git_repo.root, ".tool-versions")).read() == "python 3.11\n"


def test_missing_subdir_falls_back_to_root(git_repo):
    """Pins: `cd` into a path that does not exist in the worktree.

    Untracked directories do not come across, and aborting the launch over that
    would be worse than starting at the worktree root.
    """
    git_repo.cc("on")
    sub = os.path.join(git_repo.root, "scratch")
    os.makedirs(sub)
    r = git_repo.cc("create", cwd=sub)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == git_repo.wt()
    assert "scratch" in r.stderr


def test_existing_subdir_is_the_target(git_repo):
    git_repo.write("src/app.py", "x\n")
    git_repo.commit("src")
    git_repo.cc("on")
    r = git_repo.cc("create", cwd=os.path.join(git_repo.root, "src"))
    assert r.stdout.strip() == git_repo.wt("w-01", "src")


# ------------------------------------------------------------------- reaping

def test_reap_trashes_ignored_env_file_git(git_repo):
    """Pins: draft one's KILLER defect.

    `git worktree remove` without --force returns 0 and DELETES ignored files.
    A slot with a .env, a .venv or a node_modules would be silently destroyed by
    a "safe" removal that reported success.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", ".env"), "w") as fh:
        fh.write("TOKEN=hunter2\n")
    git_repo.orphan()
    r = git_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(git_repo.wt())
    assert git_repo.trashed_file(".env") == "TOKEN=hunter2\n"


@needs_jj
def test_reap_trashes_ignored_env_file_jj(jj_repo):
    """Same defect, jj side: jj has no surfaced untracked concept at all."""
    jj_repo.cc("on")
    jj_repo.cc("create")
    with open(jj_repo.wt("w-01", ".env"), "w") as fh:
        fh.write("TOKEN=hunter2\n")
    jj_repo.orphan()
    r = jj_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(jj_repo.wt())
    assert jj_repo.trashed_file(".env") == "TOKEN=hunter2\n"


def test_trash_failure_aborts_release(git_repo):
    """Pins: continuing past a failed trash.

    `bin/trash` exits 1 on failure -- and `trash` moves to ~/.Trash, so a repo on
    another volume makes release a full cross-device copy that really can fail.
    Pruning and removing .owner anyway leaves a non-empty directory at the slot
    path, and `git worktree add` then hard-fails there FOREVER.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.orphan()
    r = git_repo.cc("reap", CC_TEST_TRASH_FAIL="1")
    assert "NOT released" in r.stdout
    assert os.path.exists(git_repo.owner()), ".owner must survive so a reap retries"
    assert os.path.isdir(git_repo.wt())
    # And the retry, once trash works again, completes.
    git_repo.cc("reap")
    assert not os.path.exists(git_repo.owner())
    assert not os.path.isdir(git_repo.wt())


def test_reap_is_idempotent_after_interrupt(git_repo):
    """Pins: a half-released slot wedging allocation.

    Interrupted after the trash but before the unregister/unlink, the slot is
    claimed by an .owner whose directory is gone. .owner is removed LAST for
    exactly this reason: a re-run finishes the remaining steps.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.orphan()
    shutil.move(git_repo.wt(), os.path.join(git_repo.base, "pretend-trashed"))
    assert os.path.exists(git_repo.owner())
    r = git_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.exists(git_repo.owner())
    listed = git_repo._run(["git", "worktree", "list", "--porcelain"]).stdout
    assert "w-01" not in listed, "the registration must be pruned too"
    # The slot is genuinely free again.
    assert git_repo.cc("create").stdout.strip() == git_repo.wt()


def test_held_slot_never_reaped_and_named(git_repo):
    """Pins: reaping unmerged work, and doing it silently.

    A hold is the normal end of a session. Reaping one trashes work the exit
    path deliberately preserved -- and a hold nobody is told about is a slot
    that silently never comes back.

    The worktree is deliberately CLEAN: a merge-conflict hold looks exactly like
    this, and only the .hold check stands between it and a release. Leaving
    uncommitted work in it instead would make the dirty check hold the slot
    anyway, and the test would pass with .hold ignored entirely.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.in_worktree(["git", "commit", "-q", "--allow-empty", "-m", "slot work"])
    git_repo.orphan()
    with open(git_repo.hold(), "w") as fh:
        fh.write("merge conflict on w-01\n")
    r = git_repo.cc("reap")
    assert os.path.isdir(git_repo.wt())
    assert os.path.exists(git_repo.owner()), "a held slot stays claimed"
    assert "w-01" in r.stdout and "held" in r.stdout
    assert "release w-01" in r.stdout


def test_crashed_dirty_slot_is_held_not_trashed(git_repo):
    """Pins: the crash case.

    SIGKILL, Cmd+Q and `tmux kill-session` all skip the exit path, so the reaper
    is where uncommitted work from a crashed session is decided -- and trashing
    there loses the only copy.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "note.txt"), "w") as fh:
        fh.write("half done\n")
    git_repo.orphan()
    r = git_repo.cc("reap")
    assert os.path.isdir(git_repo.wt())
    assert "uncommitted (crashed)" in open(git_repo.hold()).read()
    assert "w-01" in r.stdout


def test_unmerged_branch_survives_release(git_repo):
    """Pins: `git branch -D`.

    -D would destroy the commits the release just went to the trouble of
    preserving. -d refuses an unmerged branch, and that refusal IS the recovery
    handle -- so it must be reported, not swallowed.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.in_worktree(["git", "commit", "-q", "--allow-empty", "-m", "slot work"])
    git_repo.orphan()
    r = git_repo.cc("reap")
    assert "w-01" in git_repo.branches(), "the branch is the only copy left"
    assert "git merge w-01" in r.stdout


def test_release_removes_ccjj_journal_namespace(git_repo, tmp_path):
    """Pins: an unprunable cc-jj-journal/<path>/ namespace per worktree, forever."""
    journal = str(tmp_path / "journal")
    ns = os.path.join(journal, git_repo.wt().replace("/", "_"))
    git_repo.cc("on", CC_JJ_JOURNAL=journal)
    git_repo.cc("create", CC_JJ_JOURNAL=journal)
    os.makedirs(os.path.join(ns, "S1"))
    git_repo.orphan()
    git_repo.cc("reap", CC_JJ_JOURNAL=journal)
    assert not os.path.exists(ns)


def test_reap_all_drops_repos_that_opted_out(git_repo):
    git_repo.cc("on")
    os.unlink(os.path.join(git_repo.root, ".git", "cc-worktree"))
    r = git_repo.cc("reap", "--all", cwd=git_repo.base)
    assert "no longer opted in" in r.stdout
    assert git_repo.root not in open(os.path.join(git_repo.state, "repos")).read()


# --------------------------------------------------------------- jj specifics

@needs_jj
def test_jj_bookmark_set_before_forget(jj_repo):
    """Pins: bookmarking after `jj workspace forget`.

    After a forget the working-copy commit is no longer in the default revset,
    and `w-NN@` no longer resolves at all -- so a bookmark set afterwards is
    never created and the commits become invisible.
    """
    jj_repo.cc("on")
    jj_repo.cc("create")
    with open(jj_repo.wt("w-01", "b.txt"), "w") as fh:
        fh.write("slot work\n")
    jj_repo.in_worktree(["jj", "commit", "-m", "slot work"])
    jj_repo.orphan()
    r = jj_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    marks = [b for b in jj_repo.bookmarks() if b.startswith("w-01-")]
    assert marks, "no recovery bookmark: the commits are unreachable"
    log = jj_repo._run(["jj", "log", "--no-graph", "-r", "::" + marks[0],
                        "-T", 'description ++ "\\n"']).stdout
    assert "slot work" in log


@needs_jj
def test_jj_unsnapshotted_file_only_in_trash(jj_repo):
    """Pins: over-claiming that the bookmark recovers everything.

    The parent sees only what a workspace LAST snapshotted, so the reaper has to
    snapshot before it can judge -- and what it then finds is uncommitted work,
    which is held rather than released. Without the snapshot, `w-NN@` reads
    empty and the file goes straight to the trash unannounced.
    """
    jj_repo.cc("on")
    jj_repo.cc("create")
    with open(jj_repo.wt("w-01", "never-snapshotted.txt"), "w") as fh:
        fh.write("only copy\n")
    jj_repo.orphan()
    r = jj_repo.cc("reap")
    assert "uncommitted (crashed)" in open(jj_repo.hold()).read(), r.stdout + r.stderr
    assert open(jj_repo.wt("w-01", "never-snapshotted.txt")).read() == "only copy\n"
    # --discard is the only path allowed to lose it, and even then it is in the
    # trash rather than gone.
    jj_repo.cc("release", "w-01", "--discard")
    assert not os.path.isdir(jj_repo.wt())
    assert jj_repo.trashed_file("never-snapshotted.txt") == "only copy\n"


@needs_jj
def test_jj_clean_slot_releases(jj_repo):
    jj_repo.cc("on")
    jj_repo.cc("create")
    jj_repo.orphan()
    r = jj_repo.cc("reap")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(jj_repo.wt())
    assert not os.path.exists(jj_repo.owner())
    assert "w-01" not in jj_repo._run(["jj", "workspace", "list"]).stdout


# ------------------------------------------------------------- the exit path

def test_finish_merges_clean_and_releases(git_repo):
    """The round trip: commit in the slot, exit, the parent has it, slot free."""
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "b.txt"), "w") as fh:
        fh.write("from the slot\n")
    git_repo.in_worktree(["git", "add", "-A"])
    git_repo.in_worktree(["git", "commit", "-qm", "slot work"])
    r = git_repo.cc("finish", "--slot", "w-01")
    assert r.returncode == 0, r.stderr
    assert open(os.path.join(git_repo.root, "b.txt")).read() == "from the slot\n"
    assert "w-01" not in git_repo.branches()
    assert not os.path.exists(git_repo.owner())
    assert not os.path.isdir(git_repo.wt())


def test_finish_dirty_holds(git_repo):
    """A hold is the NORMAL end of a session: Ctrl-C mid-task, "commit later"."""
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "a.txt"), "a") as fh:
        fh.write("unfinished\n")
    r = git_repo.cc("finish", "--slot", "w-01")
    assert r.returncode == 0, r.stderr
    assert open(git_repo.hold()).read().strip() == "uncommitted"
    assert os.path.isdir(git_repo.wt())
    assert "cc-worktree land w-01" in r.stdout


def test_finish_conflict_aborts_and_holds(git_repo):
    """Pins: a conflicted merge left half-applied, or the branch trashed later.

    Both sides change the same line, so the merge really conflicts. Aborting is
    mandatory -- an in-progress merge in the parent is a booby trap for the next
    session -- and the branch must survive as the recovery handle.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.in_worktree(["git", "commit", "-qam", "slot side"],)
    with open(git_repo.wt("w-01", "a.txt"), "w") as fh:
        fh.write("slot version\n")
    git_repo.in_worktree(["git", "commit", "-qam", "slot side"])
    git_repo.write("a.txt", "parent version\n")
    git_repo.commit("parent side")

    r = git_repo.cc("finish", "--slot", "w-01")
    assert r.returncode == 0, r.stderr
    assert "conflict" in open(git_repo.hold()).read()
    assert not os.path.exists(os.path.join(git_repo.root, ".git", "MERGE_HEAD")), \
        "the merge must be aborted, not left half-applied"
    assert open(os.path.join(git_repo.root, "a.txt")).read() == "parent version\n"
    assert "w-01" in git_repo.branches()
    assert "git merge w-01" in r.stdout


def test_finish_local_changes_would_be_overwritten_holds(git_repo):
    """Pins: the likeliest merge failure, which is NEITHER of the other two.

    An uncommitted parent edit to a file the slot touched fails what was a
    FAST-FORWARD with "Your local changes would be overwritten" -- and
    `git merge --abort` then exits 128 ("no merge to abort"), so a handler that
    aborts reports that instead of the advice that actually works.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "a.txt"), "w") as fh:
        fh.write("slot version\n")
    git_repo.in_worktree(["git", "commit", "-qam", "slot side"])
    git_repo.write("a.txt", "dirty parent\n")          # uncommitted, on purpose

    r = git_repo.cc("finish", "--slot", "w-01")
    assert r.returncode == 0, r.stderr
    assert "git stash && git merge w-01 && git stash pop" in r.stdout
    assert "no merge to abort" not in (r.stdout + r.stderr)
    assert "uncommitted parent changes" in open(git_repo.hold()).read()
    assert open(os.path.join(git_repo.root, "a.txt")).read() == "dirty parent\n"


def test_finish_holds_when_parent_branch_moved(git_repo):
    """Pins: merging into whatever the parent happens to have checked out now.

    The merge target is implicit. If the parent moved while the session ran, the
    work lands somewhere nobody asked for -- so hold, and name both branches.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.in_worktree(["git", "commit", "-q", "--allow-empty", "-m", "slot work"])
    git_repo._run(["git", "checkout", "-q", "-b", "elsewhere"])
    r = git_repo.cc("finish", "--slot", "w-01")
    assert "parent moved from master to elsewhere" in open(git_repo.hold()).read()
    assert os.path.isdir(git_repo.wt())
    assert "elsewhere" in r.stdout and "master" in r.stdout


@needs_jj
def test_finish_jj_clean_releases_without_merge(jj_repo):
    """jj needs no merge: bookmarks are repo-global, so the slot's own
    `jj commit` + `jj bookmark set master -r @-` already advanced master."""
    jj_repo.cc("on")
    jj_repo.cc("create")
    jj_repo.in_worktree(["jj", "commit", "-m", "slot work"])
    jj_repo.in_worktree(["jj", "bookmark", "set", "master", "-r", "@-"])
    r = jj_repo.cc("finish", "--slot", "w-01")
    assert r.returncode == 0, r.stderr
    assert not os.path.isdir(jj_repo.wt())
    assert "master" in jj_repo.bookmarks()


# ---------------------------------------------------------------- land/release

def test_release_without_land_or_discard_refuses(git_repo):
    """Pins: `--force` being ambiguous between "clear the hold" and "lose the work"."""
    git_repo.cc("on")
    git_repo.cc("create")
    r = git_repo.cc("release", "w-01")
    assert r.returncode == 1
    assert "--land" in r.stderr and "--discard" in r.stderr
    assert os.path.isdir(git_repo.wt())


def test_land_brings_uncommitted_work_into_the_parent(git_repo):
    """Pins: ten uncommitted exits from one terminal exhausting MAX_SLOTS.

    A hold is the normal ending, so there has to be a way out of one that is not
    "throw the work away".
    """
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "a.txt"), "a") as fh:
        fh.write("unfinished\n")
    git_repo.cc("finish", "--slot", "w-01")
    assert os.path.exists(git_repo.hold())

    r = git_repo.cc("land", "w-01")
    assert r.returncode == 0, r.stderr + r.stdout
    assert open(os.path.join(git_repo.root, "a.txt")).read() == "hello\nunfinished\n"
    assert not os.path.isdir(git_repo.wt())
    assert not os.path.exists(git_repo.hold())


def test_land_brings_untracked_files_across(git_repo):
    """Pins: `git stash create` silently omitting untracked files.

    They would then be trashed by the release, making `land` a work-losing path
    when only --discard is allowed to be one.
    """
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "brand-new.txt"), "w") as fh:
        fh.write("only copy\n")
    git_repo.cc("finish", "--slot", "w-01")
    r = git_repo.cc("land", "w-01")
    assert r.returncode == 0, r.stderr + r.stdout
    assert open(os.path.join(git_repo.root, "brand-new.txt")).read() == "only copy\n"


def test_land_refuses_to_overwrite_a_parent_file(git_repo):
    git_repo.cc("on")
    git_repo.cc("create")
    with open(git_repo.wt("w-01", "brand-new.txt"), "w") as fh:
        fh.write("slot copy\n")
    git_repo.cc("finish", "--slot", "w-01")
    git_repo.write("brand-new.txt", "parent copy\n")
    r = git_repo.cc("land", "w-01")
    assert r.returncode == 1
    assert "brand-new.txt" in r.stderr
    assert open(os.path.join(git_repo.root, "brand-new.txt")).read() == "parent copy\n"
    assert os.path.isdir(git_repo.wt()), "nothing may be released on a refusal"


# ------------------------------------------------------------- resume by slot

def test_create_slot_reuse_adopts_a_held_tree(git_repo):
    """Pins: slot-aware resume.

    `claude --resume` is scoped to the project directory, so a session that ran
    in w-03 can only be resumed from w-03. Adopting the surviving tree is what
    makes "resume the session I Ctrl-C'd" work at all.
    """
    git_repo.cc("on")
    # --pid keeps w-01's owner alive (it is this pytest process), so the piggy-
    # backed reap does not release it and the second create really takes w-02.
    git_repo.cc("create", "--pid", str(os.getpid()))          # w-01
    r2 = git_repo.cc("create", "--pid", str(os.getpid()))     # w-02
    assert r2.stdout.strip() == git_repo.wt("w-02"), r2.stderr
    with open(git_repo.wt("w-02", "a.txt"), "a") as fh:
        fh.write("half done\n")
    git_repo.cc("finish", "--slot", "w-02")
    assert os.path.exists(git_repo.hold("w-02"))

    # Same terminal, same pid: `finish` holds the slot while the owning shell is
    # still at its prompt, so its own resume must not read as a collision.
    r = git_repo.cc("create", "--slot", "w-02", "--reuse", "--pid", str(os.getpid()))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == git_repo.wt("w-02")
    assert not os.path.exists(git_repo.hold("w-02")), "the session is live again"
    assert open(git_repo.wt("w-02", "a.txt")).read() == "hello\nhalf done\n"


def test_create_slot_reuse_recreates_a_reaped_tree(git_repo):
    """The transcript lives in ~/.claude/projects, not the worktree, so the tree
    need not have survived -- only the PATH has to be the same."""
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.orphan()
    git_repo.cc("reap")
    assert not os.path.isdir(git_repo.wt())
    r = git_repo.cc("create", "--slot", "w-01", "--reuse")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == git_repo.wt()
    assert os.path.isdir(git_repo.wt())


def test_create_slot_reuse_refuses_a_live_owner(git_repo):
    git_repo.cc("on")
    git_repo.cc("create")
    rec = json.load(open(git_repo.owner()))
    rec["pid"] = os.getpid()
    rec["pid_lstart"] = cc_worktree.ps_lstart(os.getpid())
    with open(git_repo.owner(), "w") as fh:
        json.dump(rec, fh)
    r = git_repo.cc("create", "--slot", "w-01", "--reuse")
    assert r.returncode == 1
    assert "live session" in r.stderr


def test_branch_name_falls_back_when_w_nn_exists(git_repo):
    """Pins: `git worktree add -b w-01` hard-failing on a branch a previous
    unmerged release deliberately left behind."""
    git_repo.cc("on")
    git_repo.cc("create")
    git_repo.in_worktree(["git", "commit", "-q", "--allow-empty", "-m", "slot work"])
    git_repo.orphan()
    git_repo.cc("reap")
    assert "w-01" in git_repo.branches()
    r = git_repo.cc("create")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == git_repo.wt()
    branch = json.load(open(git_repo.owner()))["branch"]
    assert branch.startswith("w-01-"), branch


def test_current_reports_the_slot(git_repo):
    r = git_repo.cc("current", "--path", "/r/proj/.claude/worktrees/w-07/src")
    assert r.returncode == 0 and r.stdout.strip() == "w-07"
    assert git_repo.cc("current", "--path", "/r/proj/src").returncode == 1


# ---------------------------------------------------------------- cheapness

def test_no_marker_runs_no_vcs_command(git_repo):
    """Pins: a cost and a regression surface on EVERY launch in every other repo.

    `create` on a repo that has not opted in must exit 2 having spawned nothing
    -- not even `git rev-parse`. A PATH shim records any attempt.
    """
    spy = os.path.join(git_repo.base, "spy")
    os.makedirs(spy)
    log = os.path.join(git_repo.base, "vcs-calls.log")
    for name in ("git", "jj"):
        p = os.path.join(spy, name)
        with open(p, "w") as fh:
            fh.write('#!/bin/bash\necho "%s $*" >> "%s"\nexit 0\n' % (name, log))
        os.chmod(p, 0o755)
    env = git_repo.env()
    env["PATH"] = spy + os.pathsep + env["PATH"]
    r = subprocess.run([sys.executable, CCWT, "create"], cwd=git_repo.root,
                       capture_output=True, text=True, env=env)
    assert r.returncode == 2
    assert not os.path.exists(log), open(log).read()
