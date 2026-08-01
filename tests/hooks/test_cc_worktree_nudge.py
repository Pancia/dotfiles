#!/usr/bin/env python3
"""Tests for bin/cc-worktree-nudge, the git-worktree-inside-a-jj-repo warning.

The hook's whole job is to fire in exactly one situation and stay silent in
every other, so most of these tests are negatives. A false positive is noise in
every unrelated project; a false negative lets an agent run `jj commit` in a
worktree and commit a peer session's working copy.
"""

import json
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).parent.parent.parent
HOOK = DOTFILES / "bin" / "cc-worktree-nudge"


def git(cwd, *args):
    subprocess.run(
        ["git", *args], cwd=str(cwd), check=True, capture_output=True, text=True
    )


def make_repo(path):
    """A git repo with one commit, so `git worktree add` has something to base on."""
    path.mkdir(parents=True, exist_ok=True)
    git(path, "init", "-q")
    git(path, "config", "user.email", "t@t.t")
    git(path, "config", "user.name", "t")
    (path / "f.txt").write_text("hi\n")
    git(path, "add", "-A")
    git(path, "commit", "-qm", "init")
    return path


def run_hook(cwd, payload=None, env=None):
    """Run the hook with a cwd, return (exit_code, stdout)."""
    if payload is None:
        payload = json.dumps({"session_id": "x", "cwd": str(cwd), "prompt": "hi"})
    kwargs = {}
    if env is not None:
        kwargs["env"] = env
    result = subprocess.run(
        [str(HOOK)], input=payload, capture_output=True, text=True, **kwargs
    )
    return result.returncode, result.stdout


@pytest.fixture
def jj_worktree(tmp_path):
    """A git worktree belonging to a jj repo -- the one case that must warn.

    `.jj` is created with mkdir rather than a real `jj git init --colocate`:
    the hook's only jj test is `[ -d "$MAIN/.jj" ]`, so this is a faithful
    exercise of its actual contract and keeps the suite independent of the jj
    binary and its version.
    """
    main = make_repo(tmp_path / "jjrepo")
    (main / ".jj").mkdir()
    wt = main / ".claude" / "worktrees" / "cc-1"
    wt.parent.mkdir(parents=True)
    git(main, "worktree", "add", "-q", "-b", "wtbranch", str(wt))
    return wt, main


class TestWarns:
    """The single positive case."""

    def test_warns_in_jj_repo_worktree(self, jj_worktree):
        wt, _ = jj_worktree
        rc, out = run_hook(wt)
        assert rc == 0
        assert out.strip(), "expected a warning, got nothing"

    def test_output_is_valid_json_for_the_right_event(self, jj_worktree):
        # The bug this pins: backticks were emitted as `\\``, which is not a
        # legal JSON escape. The hook still exited 0 and still printed ~800
        # bytes, so every eyeball check passed -- but Claude Code discards a
        # malformed payload silently, meaning the warning never arrived.
        wt, _ = jj_worktree
        _, out = run_hook(wt)
        parsed = json.loads(out)
        assert parsed["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"
        assert parsed["hookSpecificOutput"]["additionalContext"]

    def test_message_says_use_git_not_jj(self, jj_worktree):
        wt, _ = jj_worktree
        _, out = run_hook(wt)
        msg = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        assert "`git`" in msg
        assert "NOT `jj`" in msg

    def test_message_overrides_claude_md(self, jj_worktree):
        # A repo's CLAUDE.md is tracked, so it IS checked out into the worktree
        # and IS loaded there -- and in this repo it says "use jj". The warning
        # has to beat a standing instruction, not just fill a silence.
        wt, _ = jj_worktree
        _, out = run_hook(wt)
        msg = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        assert "CLAUDE.md" in msg

    def test_message_names_the_parent_repo(self, jj_worktree):
        # "contains the answer, not a pointer": an agent may not follow a link.
        wt, main = jj_worktree
        _, out = run_hook(wt)
        msg = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        assert str(main) in msg

    def test_message_names_the_landing_branch(self, jj_worktree):
        wt, _ = jj_worktree
        _, out = run_hook(wt)
        msg = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        assert "wtbranch" in msg

    def test_warns_from_a_subdirectory_of_the_worktree(self, jj_worktree):
        wt, _ = jj_worktree
        deep = wt / "deep" / "nested"
        deep.mkdir(parents=True)
        rc, out = run_hook(deep)
        assert rc == 0
        assert json.loads(out)["hookSpecificOutput"]["additionalContext"]

    def test_detached_head_does_not_promise_a_branch(self, jj_worktree):
        # "your work lands on branch X" would be a lie on a detached HEAD, and
        # the parent genuinely will not pick the commits up by name.
        wt, _ = jj_worktree
        git(wt, "checkout", "-q", "--detach")
        _, out = run_hook(wt)
        msg = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        assert "detached HEAD" in msg
        assert "git switch -c" in msg


class TestSilent:
    """Everything else. Each of these would be noise in a normal project."""

    def test_silent_in_the_jj_parent(self, jj_worktree):
        _, main = jj_worktree
        rc, out = run_hook(main)
        assert rc == 0
        assert out == ""

    def test_silent_in_a_plain_git_repo(self, tmp_path):
        repo = make_repo(tmp_path / "gitrepo")
        rc, out = run_hook(repo)
        assert rc == 0
        assert out == ""

    def test_silent_in_a_plain_git_worktree(self, tmp_path):
        # A git worktree of a NON-jj repo is completely ordinary. This is the
        # negative that distinguishes "is a worktree" from "is the hazard".
        repo = make_repo(tmp_path / "gitrepo")
        wt = tmp_path / "wt1"
        git(repo, "worktree", "add", "-q", "-b", "wtb", str(wt))
        rc, out = run_hook(wt)
        assert rc == 0
        assert out == ""

    def test_silent_outside_any_repo(self, tmp_path):
        rc, out = run_hook(tmp_path)
        assert rc == 0
        assert out == ""

    def test_silent_for_a_nonexistent_cwd(self, tmp_path):
        rc, out = run_hook(tmp_path / "does-not-exist")
        assert rc == 0
        assert out == ""

    def test_silent_when_payload_has_no_cwd(self):
        rc, out = run_hook(None, payload=json.dumps({"session_id": "x"}))
        assert rc == 0
        assert out == ""

    def test_silent_on_empty_stdin(self):
        rc, out = run_hook(None, payload="")
        assert rc == 0
        assert out == ""

    def test_silent_on_garbage_stdin(self):
        rc, out = run_hook(None, payload="not json at all")
        assert rc == 0
        assert out == ""


class TestCost:
    """This runs on every prompt in every project."""

    def test_spawns_no_subprocess(self, jj_worktree):
        # Run with a completely empty environment, so there is no PATH at all.
        # If the hook shelled out to cat/grep/sed/git anywhere on this path it
        # could not find them and the output would change. Bash builtins are
        # unaffected, so an unchanged warning proves the fast path is builtin-only.
        wt, _ = jj_worktree
        rc, out = run_hook(wt, env={})
        assert rc == 0
        assert json.loads(out)["hookSpecificOutput"]["additionalContext"]

    def test_silent_path_spawns_no_subprocess(self, tmp_path):
        rc, out = run_hook(tmp_path, env={})
        assert rc == 0
        assert out == ""
