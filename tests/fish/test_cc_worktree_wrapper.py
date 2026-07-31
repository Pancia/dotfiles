"""Tests for the fish half of per-session worktree isolation.

pytest driving `fish -c`, not fishtape. Each test names the defect it pins.

PATH is always set INSIDE the fish command: fish/conf.d/path.fish re-prepends
~/dotfiles/bin at startup, so a stub placed on the outer PATH is defeated before
the code under test ever runs.
"""

import os
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[2]
KEY_FISH = DOTFILES / "fish" / "functions" / "_cc_worktree_key.fish"
SLOT_FISH = DOTFILES / "fish" / "functions" / "_cc_worktree_slot.fish"


def fish_eval(code: str, *, env: dict | None = None, cwd=None):
    return subprocess.run(["fish", "-c", code], capture_output=True, text=True,
                          env={**os.environ, **(env or {})}, cwd=cwd)


def key(path: str) -> str:
    r = fish_eval(f"source {KEY_FISH}\n_cc_worktree_key {path}")
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def slot(path: str) -> str:
    r = fish_eval(f"source {SLOT_FISH}\n_cc_worktree_slot {path}")
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


class TestWorktreeKey:
    """Pins: `ccs list` showing nothing inside a worktree, and ~/Cloud growing
    one cc-sessions tree per slot per repo."""

    def test_slot_root_maps_to_repo(self):
        assert key("/r/proj/.claude/worktrees/w-01") == "/r/proj"

    def test_subdir_is_preserved(self):
        # The fish capture gotcha this was written around: with group 2 absent
        # `count $m` is 2, not 3, so an `-eq 3` test would drop this case.
        assert key("/r/proj/.claude/worktrees/w-07/src/app") == "/r/proj/src/app"

    def test_ordinary_path_passes_through(self):
        assert key("/r/proj/src") == "/r/proj/src"

    def test_non_slot_directory_is_not_rewritten(self):
        """A hand-made .claude/worktrees/foo is not ours and must be left alone;
        rewriting it would file its sessions under a repo it never ran in."""
        assert key("/r/proj/.claude/worktrees/foo") == "/r/proj/.claude/worktrees/foo"

    def test_defaults_to_logical_pwd(self):
        """$PWD, never `pwd -P`.

        Every ccs site this replaces uses logical pwd, and /tmp -> /private/tmp
        (and ~/Cloud, a ProtonDrive symlink) diverge -- which would silently
        orphan every entry recorded before this landed.
        """
        r = fish_eval(f"source {KEY_FISH}\ncd /tmp; _cc_worktree_key")
        assert r.stdout.strip() == "/tmp"


class TestWorktreeSlot:
    def test_slot_extracted(self):
        assert slot("/r/proj/.claude/worktrees/w-07/src/app") == "w-07"
        assert slot("/r/proj/.claude/worktrees/w-01") == "w-01"

    def test_no_slot_outside_a_worktree(self):
        assert slot("/r/proj/src") == ""
        assert slot("/r/proj/.claude/worktrees/foo") == ""


# ===========================================================================
# The wrapper itself
#
# HOME is a temp directory with a `dotfiles` symlink back to the real checkout,
# so `~/dotfiles/...` inside the wrapper still resolves while ~/Cloud and
# ~/.claude stay untouched.
#
# XDG_CONFIG_HOME is redirected to an EMPTY directory as well, and that is not
# optional: it is inherited from the real environment, so fish would otherwise
# load ~/.config/fish/config.fish (a symlink into this repo) with ~ pointing at
# the temp HOME -- re-running _ENSURE_RCS, relinking LaunchAgents against a
# directory that does not exist, and re-prepending ~/dotfiles/bin ahead of the
# stubs, so the REAL proc-label ran. With no user config, fish_function_path and
# PATH have to be set explicitly, which they are (inside the fish command, per
# the same PATH lesson).
# ===========================================================================

import json

import pytest

WRAPPER = DOTFILES / "fish" / "functions" / "my-claude-code-wrapper.fish"

CLAUDE_STUB = """\
#!/bin/bash
# Records where and how it was launched, then runs whatever the test asked for.
{ echo "PWD=$PWD"; echo "ARGV=$*"; } >> "$CLAUDE_STUB_LOG"
if [ -n "$CLAUDE_STUB_SCRIPT" ]; then eval "$CLAUDE_STUB_SCRIPT"; fi
exit 0
"""

PROC_LABEL_STUB = """\
#!/bin/bash
# proc-label "<label>" cmd args... -- record the label, then run the command.
echo "$1" >> "$PROC_LABEL_LOG"
shift
exec "$@"
"""

PASSTHROUGH_STUB = "#!/bin/bash\nexit 0\n"

SPY_STUB = """\
#!/bin/bash
echo "$(basename "$0") $*" >> "$VCS_SPY_LOG"
exit 0
"""


class Wrapped:
    """A git repo plus the stub PATH the wrapper needs to run headless."""

    def __init__(self, tmp_path, opt_in=True):
        self.base = Path(os.path.realpath(str(tmp_path)))
        self.root = self.base / "myproj"
        self.home = self.base / "home"
        self.stub = self.base / "stub"
        self.state = self.base / "state"
        self.trash = self.base / "trash"
        self.xdg = self.base / "xdg"
        self.xdg_config = self.base / "xdg-config"
        self.claude_log = self.base / "claude.log"
        self.label_log = self.base / "label.log"
        self.spy_log = self.base / "spy.log"
        for d in (self.root, self.home, self.stub, self.xdg, self.xdg_config):
            d.mkdir(parents=True, exist_ok=True)
        os.symlink(DOTFILES, self.home / "dotfiles")

        for name, body in (("claude", CLAUDE_STUB), ("proc-label", PROC_LABEL_STUB),
                           ("cc-config", PASSTHROUGH_STUB),
                           ("cc-session-review", PASSTHROUGH_STUB)):
            p = self.stub / name
            p.write_text(body)
            p.chmod(0o755)
        trash_stub = self.stub / "trash"
        trash_stub.write_text(
            '#!/bin/bash\nmkdir -p "$CC_TEST_TRASH"\nn=0\n'
            'for p in "$@"; do n=$((n+1)); mv "$p" "$CC_TEST_TRASH/$(basename "$p").$n" '
            '|| exit 1; done\n')
        trash_stub.chmod(0o755)

        self.git("init", "-q", "-b", "master", ".")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        (self.root / "a.txt").write_text("hello\n")
        (self.root / ".gitignore").write_text(".env\n.claude/\n.cc-config\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "init")
        if opt_in:
            r = self.cc("on")
            assert r.returncode == 0, r.stderr

    # ---------------------------------------------------------------- helpers

    def env(self, **extra):
        e = {**os.environ,
             "CC_WORKTREE_STATE": str(self.state),
             "CC_TEST_TRASH": str(self.trash),
             "XDG_STATE_HOME": str(self.xdg),
             "XDG_CONFIG_HOME": str(self.xdg_config),
             "CLAUDE_STUB_LOG": str(self.claude_log),
             "PROC_LABEL_LOG": str(self.label_log),
             "VCS_SPY_LOG": str(self.spy_log),
             "HOME": str(self.home)}
        e.update(extra)
        e.pop("SSH_CONNECTION", None)
        return e

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=str(cwd or self.root),
                              capture_output=True, text=True, env=self.env())

    def cc(self, *args, cwd=None):
        return subprocess.run([str(DOTFILES / "bin" / "cc-worktree"), *args],
                              cwd=str(cwd or self.root), capture_output=True,
                              text=True, env=self.env())

    def run(self, *args, cwd=None, script="", extra_path="", **envextra):
        """Run the wrapper once, in its own fish.

        PATH is set INSIDE the fish command: fish/conf.d/path.fish re-prepends
        ~/dotfiles/bin at startup and would otherwise defeat the stubs.
        """
        argline = " ".join(args)
        code = (
            f"set -g fish_function_path {DOTFILES}/fish/functions $fish_function_path\n"
            f"set -gx PATH {extra_path} {self.stub} $PATH\n"
            f"source {WRAPPER}\n"
            f"cd {cwd or self.root}\n"
            # Cleared here, not at setup: `cd` and fish's own startup legitimately
            # run git, and counting those would make the spy assertion vacuous.
            f"rm -f {self.spy_log}\n"
            f"my-claude-code-wrapper {argline}\n"
        )
        return subprocess.run(["fish", "-c", code], capture_output=True, text=True,
                              env=self.env(CLAUDE_STUB_SCRIPT=script))

    def claude_ran_in(self):
        if not self.claude_log.exists():
            return []
        return [ln[4:] for ln in self.claude_log.read_text().splitlines()
                if ln.startswith("PWD=")]

    def labels(self):
        if not self.label_log.exists():
            return []
        # Only this wrapper's calls: anything else on the box that goes through
        # proc-label would otherwise land in the same log first.
        return [ln for ln in self.label_log.read_text().splitlines()
                if ln.startswith("claude [")]

    def slot_dir(self, slot="w-01"):
        return self.root / ".claude" / "worktrees" / slot

    def hold(self, slot="w-01"):
        return self.root / ".claude" / "worktrees" / (slot + ".hold")

    def owner(self, slot="w-01"):
        return self.root / ".claude" / "worktrees" / (slot + ".owner")


@pytest.fixture
def wrapped(tmp_path):
    return Wrapped(tmp_path)


class TestWrapperIsolation:

    def test_session_runs_inside_the_worktree(self, wrapped):
        r = wrapped.run()
        assert r.returncode == 0, r.stderr
        assert wrapped.claude_ran_in() == [str(wrapped.slot_dir())]

    def test_skip_extras_creates_nothing(self, wrapped):
        """Pins: headless -p callers leaking a worktree per run.

        ai.fish, ai_health, ai_inbox, ccpu and sanctuary/main-claude all route
        through this wrapper with -p. Each would otherwise claim a slot AND get
        an empty checkout to inspect.
        """
        r = wrapped.run("-p", "hello")
        assert r.returncode == 0, r.stderr
        assert wrapped.claude_ran_in() == [str(wrapped.root)]
        assert not wrapped.slot_dir().exists()
        assert not wrapped.owner().exists()

    def test_label_is_parent_basename_plus_slot(self, wrapped):
        """Pins: every isolated session reading as "w-01" in Activity Monitor."""
        wrapped.run()
        assert wrapped.labels(), "proc-label was never called"
        label = wrapped.labels()[0]
        assert "myproj w-01" in label, label

    def test_label_has_no_slot_when_not_isolated(self, tmp_path):
        w = Wrapped(tmp_path, opt_in=False)
        w.run()
        assert "myproj" in w.labels()[0]
        assert "w-01" not in w.labels()[0]

    def test_no_marker_runs_no_vcs_command(self, tmp_path):
        """Pins: a cost and a regression surface on every non-opted-in repo.

        A PATH shim ahead of the real binaries records any git/jj invocation.
        """
        w = Wrapped(tmp_path, opt_in=False)
        spy = w.base / "spy"
        spy.mkdir()
        for name in ("git", "jj"):
            p = spy / name
            p.write_text(SPY_STUB)
            p.chmod(0o755)
        r = w.run(extra_path=str(spy))
        assert r.returncode == 0, r.stderr
        assert not w.spy_log.exists(), w.spy_log.read_text()
        assert w.claude_ran_in() == [str(w.root)]

    def test_relaunch_same_shell_gets_a_clean_slot(self, wrapped):
        """Pins: $fish_pid being stable per terminal.

        A pid-derived worktree name collides on the second launch from the same
        terminal ("fatal: branch 'cc-111' already exists"). Stable slots plus
        release-at-exit make the relaunch reuse the slot instead.
        """
        code = (
            f"set -g fish_function_path {DOTFILES}/fish/functions $fish_function_path\n"
            f"set -gx PATH {wrapped.stub} $PATH\n"
            f"source {WRAPPER}\n"
            f"cd {wrapped.root}\n"
            "my-claude-code-wrapper\n"
            "my-claude-code-wrapper\n"
        )
        r = subprocess.run(["fish", "-c", code], capture_output=True, text=True,
                           env=wrapped.env(CLAUDE_STUB_SCRIPT=""))
        assert r.returncode == 0, r.stderr
        assert wrapped.claude_ran_in() == [str(wrapped.slot_dir())] * 2
        assert "already exists" not in r.stderr
        assert not wrapped.owner().exists(), "the slot must be free again"

    def test_parent_dirty_warns_and_base_is_the_parent_commit(self, wrapped):
        """Pins: "help me finish this edit" silently starting from HEAD.

        A worktree is based on HEAD, so the parent's in-progress edits are NOT
        in it. Saying nothing is the failure.

        The file is read DURING the session: a clean exit releases the worktree,
        so looking afterwards finds nothing at all.
        """
        (wrapped.root / "a.txt").write_text("hello\nWORK IN PROGRESS\n")
        seen = wrapped.base / "seen.txt"
        r = wrapped.run(script=f"cat a.txt > {seen}")
        assert "dirty" in r.stderr, r.stderr
        assert seen.read_text() == "hello\n"


class TestWrapperExitPath:

    def test_exit_merges_clean_and_releases(self, wrapped):
        """The round trip: commit in the slot, exit, the parent has it."""
        r = wrapped.run(script="echo 'from the slot' > b.txt; "
                               "git add -A; git commit -qm 'slot work'")
        assert r.returncode == 0, r.stderr
        assert (wrapped.root / "b.txt").read_text() == "from the slot\n"
        assert not wrapped.slot_dir().exists()
        assert not wrapped.owner().exists()
        assert "w-01" not in wrapped.git("branch", "--format=%(refname:short)").stdout

    def test_exit_conflict_aborts_and_holds(self, wrapped):
        """Pins: a conflicted merge left half-applied, or the branch trashed by
        a later reaper.

        The parent has to move DURING the session for the two sides to diverge.
        Committing in the parent beforehand just gives the worktree a newer base
        and the exit merge fast-forwards -- no conflict, and the test would be
        pinning nothing.
        """
        r = wrapped.run(script=(
            "echo 'slot version' > a.txt; git commit -qam 'slot side'; "
            f"echo 'parent version' > {wrapped.root}/a.txt; "
            f"git -C {wrapped.root} commit -qam 'parent side'"))
        assert r.returncode == 0, r.stderr
        assert "conflict" in wrapped.hold().read_text()
        assert not (wrapped.root / ".git" / "MERGE_HEAD").exists()
        assert (wrapped.root / "a.txt").read_text() == "parent version\n"
        assert "w-01" in wrapped.git("branch", "--format=%(refname:short)").stdout

    def test_exit_holds_uncommitted_work(self, wrapped):
        r = wrapped.run(script="echo 'half done' >> a.txt")
        assert wrapped.hold().read_text().strip() == "uncommitted"
        assert wrapped.slot_dir().exists()
        assert "cc-worktree land w-01" in r.stdout

    def test_exit_path_runs_in_the_parent(self, wrapped):
        """`cc-worktree finish` refuses to run from inside a slot, and the agent
        in the worktree cannot merge its own branch, so the cd back is not
        cosmetic."""
        r = wrapped.run(script="echo 'from the slot' > b.txt; "
                               "git add -A; git commit -qm 'slot work'")
        assert "Refusing to nest" not in r.stderr
        assert "already checked out" not in r.stderr
        assert (wrapped.root / "b.txt").exists()


class TestSlotAwareResume:

    def test_register_records_the_slot(self, wrapped):
        """Pins: a resume that cannot find the slot its session ran in.

        The ccs entry is the only durable record of which slot a session used,
        and the entry is keyed to the PARENT — so without this field the slot is
        unrecoverable and the resume silently lands in the wrong directory.
        """
        wrapped.run()
        entries = list((wrapped.xdg / "claude-sessions" / "open").glob("*.json"))
        # The entry is deleted on a clean exit, so read the archive of what was
        # written by re-running with a stub that reads it mid-session.
        assert not entries
        r = wrapped.run(script='cat "$CCS_ENTRY_FILE" > ' + str(wrapped.base / "entry.json"))
        assert r.returncode == 0, r.stderr
        rec = json.loads((wrapped.base / "entry.json").read_text())
        assert rec["slot"] == "w-01"
        assert rec["cwd"] == str(wrapped.root), "cwd must be the PARENT repo path"

    def test_resume_reuses_the_recorded_slot(self, wrapped):
        """Pins: the whole point — resume must land in the SAME directory."""
        # A session in w-02 that ended held, with its ccs entry left behind as a
        # crash would leave it.
        wrapped.run()                                   # w-01, released at exit
        r = wrapped.run(script='cat "$CCS_ENTRY_FILE" > ' + str(wrapped.base / "e.json")
                        + '; echo half >> a.txt')
        assert r.returncode == 0, r.stderr
        rec = json.loads((wrapped.base / "e.json").read_text())
        assert rec["slot"] == "w-01"
        open_dir = wrapped.xdg / "claude-sessions" / "open"
        open_dir.mkdir(parents=True, exist_ok=True)
        rec["session_id"] = "SID-123"
        (open_dir / "recorded.json").write_text(json.dumps(rec))

        wrapped.claude_log.unlink(missing_ok=True)
        r = wrapped.run("--resume", "SID-123")
        assert r.returncode == 0, r.stderr
        assert wrapped.claude_ran_in() == [str(wrapped.slot_dir("w-01"))]
        # The held tree, with its half-finished work, is what we came back to.
        assert "half" in (wrapped.slot_dir("w-01") / "a.txt").read_text()

    def test_resume_without_a_recorded_slot_runs_unisolated(self, wrapped):
        """An entry predating this feature has no slot. Its transcript is keyed
        to the parent, so the parent is exactly where it must resume."""
        r = wrapped.run("--resume", "NO-SUCH-SESSION")
        assert r.returncode == 0, r.stderr
        # A fresh slot is still allocated (that is `create`'s normal path); what
        # must NOT happen is a failure or a wrong-slot landing.
        assert wrapped.claude_ran_in() == [str(wrapped.slot_dir("w-01"))]


class TestChpwdSurfacing:
    """Pins: a held slot being invisible until the pool runs out.

    A hold is work the exit path deliberately preserved and nothing will ever
    reap. `cc-worktree status` shows it, but only if you think to run it.
    """

    def _show(self, cwd):
        code = (f"source {DOTFILES}/fish/functions/chpwd.fish\n"
                f"cd {cwd}\nshowHeldWorktrees\n")
        return fish_eval(code).stdout

    def test_silent_with_no_holds(self, tmp_path):
        (tmp_path / ".claude" / "worktrees").mkdir(parents=True)
        assert self._show(tmp_path).strip() == ""

    def test_silent_outside_a_repo(self, tmp_path):
        assert self._show(tmp_path).strip() == ""

    def test_names_the_count_when_slots_are_held(self, tmp_path):
        wt = tmp_path / ".claude" / "worktrees"
        wt.mkdir(parents=True)
        (wt / "w-01.hold").write_text("uncommitted\n")
        (wt / "w-03.hold").write_text("merge conflict on w-03\n")
        out = self._show(tmp_path)
        assert "2 cc-worktree slots" in out
        assert "cc-worktree status" in out
