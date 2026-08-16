#!/usr/bin/env python3
"""Tests for bin/rcs-sync, the three-way resolver for rcs/MANIFEST hardlinks.

Every test builds a throwaway dotfiles tree and HOME, so nothing here touches
the real links. The resolver's contract is about *which side survives* a split,
so the assertions check file content and inode identity, not just exit codes.
"""

import json
import os
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).parent.parent.parent
SCRIPT = DOTFILES / "bin" / "rcs-sync"


@pytest.fixture
def env(tmp_path):
    root = tmp_path / "dotfiles"
    (root / "rcs").mkdir(parents=True)
    home = tmp_path / "home"
    home.mkdir()
    state = tmp_path / "state"
    e = dict(os.environ, HOME=str(home), RCS_DOTFILES=str(root), RCS_STATE_DIR=str(state))

    class Env:
        rcs = root / "rcs"
        dst = home / ".config" / "app" / "conf"
        src = root / "rcs" / "app.conf"

        def manifest(self, *lines):
            (root / "rcs" / "MANIFEST").write_text("# comment\n\n" + "\n".join(lines) + "\n")

        def run(self, *args, stdin=""):
            return subprocess.run(
                ["/bin/bash", str(SCRIPT), *args],
                input=stdin, capture_output=True, text=True, env=e,
            )

    ev = Env()
    ev.manifest("app.conf   -> $HOME/.config/app/conf")
    return ev


def linked(a, b):
    return os.stat(a).st_ino == os.stat(b).st_ino


def replace(path, text):
    """Write by rename, the way sed -i / jj / atomic-saving apps do."""
    tmp = path.with_name(path.name + ".new")
    tmp.write_text(text)
    os.replace(tmp, path)


def synced(env, text="v1\n"):
    env.src.write_text(text)
    r = env.run()
    assert r.returncode == 0, r.stderr
    assert linked(env.src, env.dst)
    return r


class TestResolution:
    def test_creates_missing_destination(self, env):
        synced(env)
        assert env.dst.read_text() == "v1\n"

    def test_linked_pair_is_silent(self, env):
        synced(env)
        r = env.run()
        assert r.stderr == ""

    def test_repo_rewrite_wins(self, env):
        """The sed -i / jj restore case: repo replaced, live copy stale."""
        synced(env)
        replace(env.src, "v2\n")
        r = env.run()
        assert linked(env.src, env.dst)
        assert env.dst.read_text() == "v2\n"
        assert "relinked" in r.stderr

    def test_app_rewrite_is_adopted_into_repo(self, env):
        synced(env)
        src_ino = os.stat(env.src).st_ino
        replace(env.dst, "app-saved\n")
        r = env.run()
        assert env.src.read_text() == "app-saved\n"
        assert os.stat(env.src).st_ino == src_ino, "repo file must keep its inode"
        assert linked(env.src, env.dst)
        assert "adopted" in r.stderr

    def test_both_changed_is_left_alone(self, env):
        synced(env)
        replace(env.src, "repo\n")
        replace(env.dst, "app\n")
        r = env.run()
        assert env.src.read_text() == "repo\n"
        assert env.dst.read_text() == "app\n"
        assert not linked(env.src, env.dst)
        assert "CONFLICT" in r.stderr and "both changed" in r.stderr

    def test_no_record_and_different_is_left_alone(self, env):
        env.src.write_text("repo\n")
        env.dst.parent.mkdir(parents=True)
        env.dst.write_text("app\n")
        r = env.run()
        assert env.dst.read_text() == "app\n"
        assert "no sync record" in r.stderr

    def test_equal_content_split_relinks_silently(self, env):
        synced(env)
        replace(env.dst, "v1\n")
        r = env.run()
        assert linked(env.src, env.dst)
        assert r.stderr == ""

    def test_in_place_edit_refreshes_record(self, env):
        """An edit through the link must move the baseline, or the next
        repo-side rewrite would look like a conflict."""
        synced(env)
        env.src.write_text("edited in place, longer\n")  # same inode
        env.run()
        replace(env.src, "then rewritten by jj\n")
        r = env.run()
        assert env.dst.read_text() == "then rewritten by jj\n"
        assert "relinked" in r.stderr

    def test_repeat_splits_keep_resolving(self, env):
        synced(env)
        replace(env.dst, "app1\n")
        env.run()
        replace(env.src, "repo2\n")
        env.run()
        assert env.dst.read_text() == "repo2\n"
        replace(env.dst, "app3\n")
        env.run()
        assert env.src.read_text() == "app3\n"


class TestManifest:
    def test_directory_is_symlinked(self, env):
        (env.rcs / "dir").mkdir()
        env.manifest("dir -> $HOME/.config/dir")
        env.run()
        home_link = env.dst.parent.parent / "dir"
        assert home_link.is_symlink()
        assert os.readlink(home_link) == str(env.rcs / "dir")

    def test_missing_source_warns(self, env):
        r = env.run()
        assert "not found" in r.stderr

    def test_unlisted_rcs_file_warns_only_when_asked(self, env):
        env.src.write_text("x\n")
        (env.rcs / "stray.conf").write_text("x\n")
        assert "stray.conf" not in env.run().stderr
        assert "stray.conf not in MANIFEST" in env.run("--check-unlisted").stderr

    def test_quiet_mode_prints_nothing(self, env):
        synced(env)
        replace(env.src, "v2\n")
        r = env.run("-q")
        assert r.stdout == r.stderr == ""
        assert linked(env.src, env.dst)


class TestHook:
    def test_silent_when_nothing_happened(self, env):
        synced(env)
        r = env.run("--hook", stdin='{"tool_name":"Bash"}')
        assert r.returncode == 0
        assert r.stdout == ""

    def test_reports_as_valid_additional_context(self, env):
        synced(env)
        replace(env.dst, 'has "quotes" and \\ backslash\n')
        r = env.run("--hook", stdin='{"tool_name":"Bash"}')
        out = json.loads(r.stdout)["hookSpecificOutput"]
        assert out["hookEventName"] == "PostToolUse"
        assert "adopted" in out["additionalContext"]
        assert r.stderr == ""

    def test_json_survives_awkward_paths(self, env):
        env.manifest('app.conf -> $HOME/we"ird\\dir/conf')
        env.src.write_text("repo\n")
        weird = Path(env.dst.parent.parent.parent / 'we"ird\\dir')
        weird.mkdir(parents=True)
        (weird / "conf").write_text("app\n")
        r = env.run("--hook")
        json.loads(r.stdout)  # conflict note carries both paths


class TestLocking:
    def test_held_lock_makes_second_run_leave(self, env, tmp_path):
        env.src.write_text("x\n")
        (tmp_path / "state" / "lock").mkdir(parents=True)
        r = env.run()
        assert r.returncode == 0
        assert not env.dst.exists()
