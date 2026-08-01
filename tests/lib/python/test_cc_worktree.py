"""Tests for lib/python/cc_worktree.py — the opt-in marker for Claude Code's
native per-session worktrees.

Each test names the defect it pins. What used to be here — slot races, reaping,
holds, link lists, merge-on-exit, land/release — went when the machinery did:
Claude Code creates and removes worktrees itself now, so none of that is ours to
get wrong any more. What is left is the opt-in decision and the gate the fish
wrapper consults, and the failures that matter are still silent ones: isolation
that quietly does not happen, or a worktree nested inside a worktree.
"""
import os
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))), "lib", "python"))
import cc_worktree  # noqa: E402  (path set above)

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CCWT = os.path.join(DOTFILES, "lib", "python", "cc_worktree.py")

SPY_STUB = """\
#!/bin/bash
echo "$(basename "$0") $*" >> "$VCS_SPY_LOG"
exit 0
"""


class Repo:
    """A throwaway git or jj repo with isolated state."""

    def __init__(self, base, backend):
        self.backend = backend
        self.base = os.path.realpath(base)
        self.root = os.path.join(self.base, "repo")
        self.state = os.path.join(self.base, "state")
        self.bin = os.path.join(self.base, "bin")
        self.spy_log = os.path.join(self.base, "spy.log")
        os.makedirs(self.root)
        os.makedirs(self.bin)

        if backend == "jj":
            self._run(["jj", "git", "init"])
        else:
            self._run(["git", "init", "-q", "-b", "master", "."])
            self._run(["git", "config", "user.email", "t@example.com"])
            self._run(["git", "config", "user.name", "t"])
            # Hermetic: this machine's global gitignore starts with `.*`, so
            # EVERY dotfile is ignored and `git add` silently refuses it. Since
            # every path this tool proposes is a dotfile, a test that tries to
            # track one got "nothing to commit" and then asserted against a
            # premise that never held.
            self._run(["git", "config", "core.excludesFile", "/dev/null"])
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
             "VCS_SPY_LOG": self.spy_log,
             "JJ_USER": "t", "JJ_EMAIL": "t@example.com",
             "PATH": os.environ.get("PATH", "")}
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

    def marker_file(self):
        d = os.path.join(self.root, ".jj" if self.backend == "jj" else ".git")
        return os.path.join(d, "cc-worktree")

    def include_file(self):
        return os.path.join(self.root, ".worktreeinclude")

    def include_entries(self):
        """The actual entries, not the explanatory header.

        Asserting on the raw text matched the generated comment, which names
        node_modules and .venv precisely to explain why they are NOT proposed.
        """
        try:
            with open(self.include_file()) as fh:
                return [ln.strip() for ln in fh
                        if ln.strip() and not ln.lstrip().startswith("#")]
        except OSError:
            return []

    def spy_path(self):
        """A PATH prefix whose git/jj record every invocation."""
        spy = os.path.join(self.base, "spy")
        os.makedirs(spy, exist_ok=True)
        for name in ("git", "jj"):
            p = os.path.join(spy, name)
            with open(p, "w") as fh:
                fh.write(SPY_STUB)
            os.chmod(p, 0o755)
        return spy + os.pathsep + os.environ.get("PATH", "")

    def spied(self):
        try:
            with open(self.spy_log) as fh:
                return fh.read()
        except OSError:
            return ""


@pytest.fixture
def git_repo(tmp_path):
    return Repo(str(tmp_path), "git")


@pytest.fixture
def jj_repo(tmp_path):
    return Repo(str(tmp_path), "jj")


needs_jj = pytest.mark.skipif(shutil.which("jj") is None, reason="jj not installed")


# ------------------------------------------------------------- opt-in refusals

def test_on_refuses_dotfiles(git_repo):
    """~/dotfiles cannot be isolated: about half its tracked files load by
    absolute path, so a worktree copy is not the live configuration."""
    r = git_repo.cc("on", CC_WORKTREE_DOTFILES=git_repo.root)
    assert r.returncode == 1
    assert "cannot be isolated" in r.stderr
    assert "ccjj" in r.stderr
    assert not os.path.exists(git_repo.marker_file())


def test_status_names_ccjj_in_dotfiles(git_repo):
    """Do NOT suggest `on` where `on` refuses — pointing at a command that
    cannot work reads as a bug in the tool rather than a property of the repo."""
    r = git_repo.cc("status", CC_WORKTREE_DOTFILES=git_repo.root)
    assert r.returncode == 2
    assert "ccjj" in r.stdout
    assert "cc-worktree on" not in r.stdout


def test_nesting_refused_in_a_git_worktree(git_repo):
    """From inside a linked worktree, --git-common-dir finds the PARENT's
    marker — so without this guard a worktree nests inside a worktree."""
    wt = os.path.join(git_repo.root, ".claude", "worktrees", "cc-1")
    os.makedirs(os.path.dirname(wt), exist_ok=True)
    git_repo._run(["git", "worktree", "add", "-q", "-b", "b1", wt])
    r = git_repo.cc("on", cwd=wt)
    assert r.returncode == 1
    assert "linked git worktree" in r.stderr or "already inside" in r.stderr


@needs_jj
def test_nesting_refused_in_a_jj_workspace(jj_repo):
    """.jj/repo is a DIRECTORY in the parent and a FILE in a workspace."""
    ws = os.path.join(jj_repo.base, "ws")
    jj_repo._run(["jj", "workspace", "add", ws])
    r = jj_repo.cc("on", cwd=ws)
    assert r.returncode == 1
    assert "workspace" in r.stderr


def test_marker_found_when_dot_git_is_a_file(git_repo):
    """The marker lives at --git-common-dir, NEVER <root>/.git.

    In a linked worktree and in a submodule .git is a *file*, so joining a
    filename onto it produces a path that can never be opened — the marker
    would silently not be found and isolation would quietly not happen.
    """
    assert git_repo.cc("on").returncode == 0
    wt = os.path.join(git_repo.root, ".claude", "worktrees", "cc-1")
    os.makedirs(os.path.dirname(wt), exist_ok=True)
    git_repo._run(["git", "worktree", "add", "-q", "-b", "b1", wt])
    assert os.path.isfile(os.path.join(wt, ".git")), "precondition: .git is a file"
    # Resolved by hand, without forking git.
    assert os.path.realpath(cc_worktree.git_common_dir(wt)) == \
        os.path.realpath(os.path.join(git_repo.root, ".git"))


def test_marker_lives_outside_the_working_tree(git_repo):
    """Opting in is a property of THIS checkout, not of the project: the marker
    must not show up as an untracked file or travel in a commit."""
    assert git_repo.cc("on").returncode == 0
    r = git_repo._run(["git", "status", "--porcelain"])
    assert "cc-worktree" not in r.stdout, r.stdout


# ----------------------------------------------------------------- the gate

class TestShouldIsolate:
    """The wrapper consults this before every launch, in every repo."""

    def test_exit_0_when_opted_in(self, git_repo):
        assert git_repo.cc("on").returncode == 0
        assert git_repo.cc("should-isolate").returncode == 0

    def test_exit_2_when_not_opted_in(self, git_repo):
        assert git_repo.cc("should-isolate").returncode == 2

    def test_exit_2_outside_any_repo(self, git_repo, tmp_path):
        outside = tmp_path / "elsewhere"
        outside.mkdir()
        r = git_repo.cc("should-isolate", cwd=str(outside))
        assert r.returncode == 2

    def test_is_silent(self, git_repo):
        """A shell asking a yes/no would capture anything on stdout."""
        assert git_repo.cc("on").returncode == 0
        r = git_repo.cc("should-isolate")
        assert r.stdout == ""
        assert r.stderr == ""

    def test_refuses_inside_a_worktree(self, git_repo):
        """Pins a worktree nested inside a worktree. The parent is opted in, and
        --git-common-dir from the worktree finds the parent's marker, so the
        naive answer here is yes."""
        assert git_repo.cc("on").returncode == 0
        wt = os.path.join(git_repo.root, ".claude", "worktrees", "cc-1")
        os.makedirs(os.path.dirname(wt), exist_ok=True)
        git_repo._run(["git", "worktree", "add", "-q", "-b", "b1", wt])
        assert git_repo.cc("should-isolate", cwd=wt).returncode == 2

    def test_makes_no_vcs_call(self, git_repo):
        """Pins a cost and a regression surface on every launch in every repo.

        A PATH shim ahead of the real binaries records any git/jj invocation.
        The marker is resolved by reading files, exactly as git does it.
        """
        assert git_repo.cc("on").returncode == 0
        r = git_repo.cc("should-isolate", PATH=git_repo.spy_path())
        assert r.returncode == 0
        assert git_repo.spied() == "", git_repo.spied()

    def test_makes_no_vcs_call_when_not_opted_in_either(self, git_repo):
        r = git_repo.cc("should-isolate", PATH=git_repo.spy_path())
        assert r.returncode == 2
        assert git_repo.spied() == "", git_repo.spied()


# ------------------------------------------------------------- on / off / status

def test_status_exits_2_when_not_opted_in(git_repo):
    r = git_repo.cc("status")
    assert r.returncode == 2
    assert "not opted in" in r.stdout


def test_off_removes_marker_and_registry(git_repo):
    assert git_repo.cc("on").returncode == 0
    assert os.path.exists(git_repo.marker_file())
    assert git_repo.root in open(
        os.path.join(git_repo.state, "repos")).read()

    r = git_repo.cc("off")
    assert r.returncode == 0
    assert not os.path.exists(git_repo.marker_file())
    assert git_repo.root not in open(
        os.path.join(git_repo.state, "repos")).read()


def test_off_names_worktrees_left_on_disk(git_repo):
    """Named, never silent: the trees are still there and nothing here will
    remove them now the marker is gone."""
    assert git_repo.cc("on").returncode == 0
    os.makedirs(os.path.join(git_repo.root, ".claude", "worktrees", "cc-9"))
    r = git_repo.cc("off")
    assert "cc-9" in r.stdout
    assert "git worktree remove" in r.stdout


def test_on_is_idempotent(git_repo):
    assert git_repo.cc("on").returncode == 0
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert os.path.exists(git_repo.marker_file())


# ------------------------------------------------------------ .worktreeinclude

def test_on_writes_detected_untracked_state(git_repo):
    """Claude Code copies these into each worktree. Without them a session
    starts with no permissions granted and no environment."""
    git_repo.write(".env", "SECRET=1\n")
    git_repo.write(".claude/settings.local.json", "{}\n")
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert ".env" in git_repo.include_entries()
    assert ".claude/settings.local.json" in git_repo.include_entries()


def test_on_does_not_propose_a_tracked_path(git_repo):
    """A tracked path arrives in the worktree by itself; including it would
    copy a file git already put there."""
    git_repo.write(".mcp.json", "{}\n")
    git_repo.commit("track mcp")
    git_repo.write(".env", "SECRET=1\n")
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert ".mcp.json" not in git_repo.include_entries()
    assert ".env" in git_repo.include_entries()
    assert "tracked" in r.stdout


class TestDependencyDirectories:
    """node_modules and friends: wanted by every session, and not carriable.

    `.worktreeinclude` copies AND silently skips symlinks, so a copied
    node_modules arrives without `.bin` -- measured. That fails as
    command-not-found while the directory visibly exists, which is harder to
    diagnose than an empty worktree. So they are excluded, but NAMED.
    """

    @staticmethod
    def _node_and_python(repo):
        os.makedirs(os.path.join(repo.root, "node_modules"))
        os.makedirs(os.path.join(repo.root, ".venv"))
        repo.write(".env", "SECRET=1\n")

    def test_not_written_into_the_include_file(self, git_repo):
        self._node_and_python(git_repo)
        assert git_repo.cc("on").returncode == 0
        assert "node_modules" not in git_repo.include_entries()
        assert ".venv" not in git_repo.include_entries()
        assert ".env" in git_repo.include_entries()

    def test_named_in_the_output(self, git_repo):
        """Pins the silent omission. Opting in a Node project produced a tidy
        result missing exactly what the session needs, and the omission only
        surfaced when the first worktree could not build."""
        self._node_and_python(git_repo)
        r = git_repo.cc("on")
        assert "node_modules" in r.stdout
        assert ".venv" in r.stdout

    def test_output_gives_the_reason_and_the_remedy(self, git_repo):
        """Naming them without saying why invites someone to add them by hand
        and hit the broken-copy failure this is steering around."""
        self._node_and_python(git_repo)
        out = git_repo.cc("on").stdout
        assert "SYMLINK" in out.upper()
        assert "installer" in out

    def test_reported_on_stdout_not_stderr(self, git_repo):
        """stderr is unbuffered and stdout is not, so warn() here surfaced
        ABOVE the 'wrote .worktreeinclude' summary it qualifies."""
        self._node_and_python(git_repo)
        r = git_repo.cc("on")
        assert "node_modules" in r.stdout
        assert "node_modules" not in r.stderr

    def test_no_false_nothing_untracked_claim(self, git_repo):
        """With deps present and nothing small to carry, "nothing untracked"
        would be flatly untrue -- they ARE untracked, just not carriable."""
        os.makedirs(os.path.join(git_repo.root, "node_modules"))
        r = git_repo.cc("on")
        assert r.returncode == 0
        assert not os.path.exists(git_repo.include_file())
        assert "node_modules" in r.stdout
        assert "nothing untracked" not in r.stdout

    def test_tracked_dependency_dir_is_not_reported(self, git_repo):
        """A repo that commits its vendored deps already has them in every
        worktree, so warning about them would be noise."""
        git_repo.write("deps/thing.txt", "vendored\n")
        git_repo.commit("track deps")
        r = git_repo.cc("on")
        assert "not carriable" not in r.stdout


def test_on_never_overwrites_an_existing_include(git_repo):
    """It lives in the working tree and may well be the human's, or the
    project's."""
    git_repo.write(".worktreeinclude", "# mine\nkeep-this\n")
    git_repo.write(".env", "SECRET=1\n")
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert open(git_repo.include_file()).read() == "# mine\nkeep-this\n"
    assert "already exists" in r.stdout


def test_on_says_so_when_there_is_nothing_local(git_repo):
    # "nothing SMALL and untracked": the qualifier is load-bearing, because a
    # repo can have untracked node_modules and still nothing carriable. See
    # TestDependencyDirectories.
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert "nothing small and untracked" in r.stdout
    assert not os.path.exists(git_repo.include_file())


def test_on_warns_when_the_working_copy_is_dirty(git_repo):
    """A worktree is based on HEAD, so in-progress edits are NOT in it. Saying
    nothing is the failure."""
    git_repo.write("a.txt", "hello\nWORK IN PROGRESS\n")
    r = git_repo.cc("on")
    assert r.returncode == 0
    assert "dirty" in r.stderr


@needs_jj
def test_jj_repo_is_told_worktrees_are_git(jj_repo):
    """The one thing to know: `claude --worktree` makes a *git* worktree, so jj
    inside it resolves to the PARENT and `jj commit` there commits the parent's
    working copy."""
    r = jj_repo.cc("on")
    assert r.returncode == 0
    assert "git" in r.stdout
    assert "jj" in r.stdout
