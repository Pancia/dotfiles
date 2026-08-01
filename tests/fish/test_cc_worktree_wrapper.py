"""Tests for the fish half of per-session worktree isolation.

pytest driving `fish -c`, not fishtape. Each test names the defect it pins.

The wrapper no longer creates or enters a worktree -- Claude Code does, natively
-- so everything here is about ARGV: does `--worktree` get appended, and is
`--no-worktree` honoured and never forwarded. The old suite tested slot
creation, holds, merge-on-exit and slot-aware resume; all of that machinery is
gone, along with the tests for it.

PATH is always set INSIDE the fish command: fish/conf.d/path.fish re-prepends
~/dotfiles/bin at startup, so a stub placed on the outer PATH is defeated before
the code under test ever runs.
"""

import os
import re
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[2]
KEY_FISH = DOTFILES / "fish" / "functions" / "_cc_worktree_key.fish"


def fish_eval(code: str, *, env: dict | None = None, cwd=None):
    return subprocess.run(["fish", "-c", code], capture_output=True, text=True,
                          env={**os.environ, **(env or {})}, cwd=cwd)


def key(path: str) -> str:
    r = fish_eval(f"source {KEY_FISH}\n_cc_worktree_key {path}")
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


class TestWorktreeKey:
    """Pins: `ccs list` showing nothing inside a worktree, and ~/Cloud growing
    one cc-sessions tree per worktree per repo."""

    def test_worktree_root_maps_to_repo(self):
        assert key("/r/proj/.claude/worktrees/cc-101530-42") == "/r/proj"

    def test_subdir_is_preserved(self):
        # The fish capture gotcha this was written around: with group 2 absent
        # `count $m` is 2, not 3, so an `-eq 3` test would drop this case.
        assert key("/r/proj/.claude/worktrees/w-07/src/app") == "/r/proj/src/app"

    def test_ordinary_path_passes_through(self):
        assert key("/r/proj/src") == "/r/proj/src"

    def test_generated_names_are_matched(self):
        """Pins the regression that retiring the slot pool introduced.

        The pattern used to be `w-\\d+`, which Claude Code's generated names --
        `warm-discovering-metcalfe`, `cc-101530-42` -- do not match. That made
        this function a silent no-op for every native worktree, filing sessions
        under the worktree path instead of the repo: exactly what it exists to
        prevent, and invisible because it still returned a plausible path.
        """
        assert key("/r/proj/.claude/worktrees/warm-discovering-metcalfe") == "/r/proj"
        assert key("/r/proj/.claude/worktrees/anything-at-all/deep") == "/r/proj/deep"

    def test_defaults_to_logical_pwd(self):
        """$PWD, never `pwd -P`.

        Every ccs site this replaces uses logical pwd, and /tmp -> /private/tmp
        (and ~/Cloud, a ProtonDrive symlink) diverge -- which would silently
        orphan every entry recorded before this landed.
        """
        r = fish_eval(f"source {KEY_FISH}\ncd /tmp; _cc_worktree_key")
        assert r.stdout.strip() == "/tmp"


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

    def run(self, *args, cwd=None, script="", extra_path=""):
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

    def claude_argv(self):
        if not self.claude_log.exists():
            return []
        return [ln[5:] for ln in self.claude_log.read_text().splitlines()
                if ln.startswith("ARGV=")]

    def labels(self):
        if not self.label_log.exists():
            return []
        # Only this wrapper's calls: anything else on the box that goes through
        # proc-label would otherwise land in the same log first.
        return [ln for ln in self.label_log.read_text().splitlines()
                if ln.startswith("claude [")]


@pytest.fixture
def wrapped(tmp_path):
    return Wrapped(tmp_path)


class TestWorktreeFlag:
    """The whole feature: does claude get --worktree, and with what."""

    def test_opted_in_gets_the_flag(self, wrapped):
        r = wrapped.run()
        assert r.returncode == 0, r.stderr
        argv = wrapped.claude_argv()
        assert argv, "claude was never launched"
        assert "--worktree" in argv[0], argv[0]

    def test_generated_name_is_passed(self, wrapped):
        """A stable default name would put two concurrent sessions in ONE
        worktree, which is the opposite of the point."""
        wrapped.run()
        argv = wrapped.claude_argv()[0].split()
        name = argv[argv.index("--worktree") + 1]
        assert name.startswith("cc-"), name
        assert len(name) > 4, name

    def test_not_opted_in_gets_no_flag(self, tmp_path):
        w = Wrapped(tmp_path, opt_in=False)
        w.run()
        assert w.claude_argv(), "claude was never launched"
        assert "--worktree" not in w.claude_argv()[0]

    def test_wrapper_never_changes_directory(self, wrapped):
        """Claude Code cd's into the worktree itself. The wrapper doing it too
        was what hid the worktree from Claude Code and forced the whole
        slot/hold/reaper apparatus that has now been deleted."""
        wrapped.run()
        assert wrapped.claude_ran_in() == [str(wrapped.root)]

    def test_no_vcs_command_when_not_opted_in(self, tmp_path):
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

    def test_no_vcs_command_when_opted_in_either(self, wrapped):
        """should-isolate resolves the marker by reading files, never by forking
        git -- so even the opted-in path costs no VCS process."""
        spy = wrapped.base / "spy"
        spy.mkdir()
        for name in ("git", "jj"):
            p = spy / name
            p.write_text(SPY_STUB)
            p.chmod(0o755)
        r = wrapped.run(extra_path=str(spy))
        assert r.returncode == 0, r.stderr
        assert not wrapped.spy_log.exists(), wrapped.spy_log.read_text()

    def test_label_is_the_repo_basename(self, wrapped):
        wrapped.run()
        assert wrapped.labels(), "proc-label was never called"
        assert "myproj" in wrapped.labels()[0]


class TestNoWorktreeOptOut:

    def test_suppresses_the_flag(self, wrapped):
        r = wrapped.run("--no-worktree")
        assert r.returncode == 0, r.stderr
        assert "--worktree" not in wrapped.claude_argv()[0]

    def test_is_never_forwarded_to_claude(self, wrapped):
        """claude does not know this flag and would reject it."""
        wrapped.run("--no-worktree")
        assert "--no-worktree" not in wrapped.claude_argv()[0]

    def test_survives_after_process_label(self, wrapped):
        """Pins the ordering bug: --process-label takes the NEXT argument as its
        value, so matching it before --no-worktree swallows the opt-out as label
        text and the flag silently does nothing -- the worst outcome for a flag
        whose entire job is to let the user say no.
        """
        r = wrapped.run("--process-label", "--no-worktree")
        assert r.returncode == 0, r.stderr
        assert "--worktree" not in wrapped.claude_argv()[0]

    def test_process_label_still_works_alongside_it(self, wrapped):
        wrapped.run("--process-label", "mylabel", "--no-worktree")
        assert "mylabel" in wrapped.labels()[0], wrapped.labels()
        assert "--worktree" not in wrapped.claude_argv()[0]


class TestSuppressionCases:
    """Situations where a worktree is wrong even in an opted-in repo."""

    def test_print_mode_gets_no_worktree(self, wrapped):
        """Pins: headless -p callers leaking a worktree per run.

        ai.fish, ai_health, ai_inbox, ccpu and sanctuary/main-claude all route
        through this wrapper with -p. Each would otherwise leave a worktree
        behind AND get a checkout without the parent's in-progress work.
        """
        r = wrapped.run("-p", "hello")
        assert r.returncode == 0, r.stderr
        assert "--worktree" not in wrapped.claude_argv()[0]

    @pytest.mark.parametrize("flag", ["--resume", "-r", "-c", "--continue"])
    def test_resume_gets_no_worktree(self, wrapped, flag):
        """Claude Code already returns a resumed session to the worktree it ran
        in, so appending the flag would strand it in a fresh empty one."""
        wrapped.run(flag, "SID-123" if flag in ("--resume", "-r") else "")
        assert "--worktree" not in wrapped.claude_argv()[0]

    @pytest.mark.parametrize("given", ["-w", "--worktree", "--worktree=mine", "-wmine"])
    def test_explicit_flag_is_not_duplicated(self, wrapped, given):
        """The user's own choice wins. `contains` cannot see the attached forms
        (`--worktree=x`, `-wname`), which is why the check globs instead.

        Asserting on the wrapper's own GENERATED name, not on a substring count:
        `--worktree` contains `-w`, so counting substrings made this pass and
        fail for the wrong reasons. `-wmine` was a real escape -- fish 4 dropped
        `?` as a glob wildcard, so the original `-w?*` pattern matched nothing.
        """
        wrapped.run(given)
        argv = wrapped.claude_argv()[0]
        assert not re.search(r"--worktree cc-\d{6}-\d+", argv), argv
