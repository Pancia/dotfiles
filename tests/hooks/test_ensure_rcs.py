#!/usr/bin/env python3
"""Tests for ensure-rcs.sh Claude Code hook."""

import json
import os
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).parent.parent.parent
HOOK = DOTFILES / "rcs" / "claude-ensure-rcs-hook.sh"


def run_hook(mode, file_path):
    """Run the hook with given mode and file_path, return (exit_code, stderr)."""
    payload = json.dumps({"tool_input": {"file_path": str(file_path)}})
    result = subprocess.run(
        [str(HOOK), mode],
        input=payload,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stderr.strip()


class TestPreMode:
    """PreToolUse: block edits to MANIFEST destination files."""

    def test_blocks_destination_file(self):
        # MANIFEST maps tmux.conf to the XDG path, not ~/.tmux.conf. This test
        # asserted the pre-XDG destination for months without failing, because
        # tests/hooks was never registered in run_tests.py and so never ran.
        rc, stderr = run_hook("pre", Path.home() / ".config/tmux/tmux.conf")
        assert rc == 2
        assert "rcs/MANIFEST" in stderr
        assert "dotfiles/rcs/tmux.conf" in stderr

    def test_blocks_nested_destination(self):
        rc, _ = run_hook("pre", Path.home() / ".config/fish/config.fish")
        assert rc == 2

    def test_allows_source_file(self):
        rc, _ = run_hook("pre", Path.home() / "dotfiles/rcs/tmux.conf")
        assert rc == 0

    def test_allows_unrelated_file(self):
        rc, _ = run_hook("pre", "/tmp/some/random/file.txt")
        assert rc == 0

    def test_allows_empty_file_path(self):
        payload = json.dumps({"tool_input": {}})
        result = subprocess.run(
            [str(HOOK), "pre"],
            input=payload,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

    def test_blocks_claude_md_destination(self):
        rc, stderr = run_hook("pre", Path.home() / ".claude/CLAUDE.md")
        assert rc == 2
        assert "claude-user-claude.md" in stderr

    def test_blocks_destination_in_other_letter_case(self):
        """APFS ignores case, so this names the same file."""
        rc, stderr = run_hook("pre", Path.home() / ".Config/TMUX/tmux.conf")
        assert rc == 2
        assert "dotfiles/rcs/tmux.conf" in stderr

    def test_blocks_destination_written_with_tilde(self):
        rc, _ = run_hook("pre", "~/.config/tmux/tmux.conf")
        assert rc == 2

    def test_allows_source_in_other_letter_case(self):
        """The source shares the destination's inode; it must stay editable."""
        rc, _ = run_hook("pre", Path.home() / "dotfiles/RCS/tmux.conf")
        assert rc == 0

    def test_blocks_launch_agent_plist(self):
        rc, stderr = run_hook("pre", Path.home() / "Library/LaunchAgents/org.pancia.vpc.plist")
        assert rc == 2
        assert "dotfiles/services/vpc/org.pancia.vpc.plist" in stderr

    def test_blocks_launch_agent_plist_in_other_letter_case(self):
        rc, _ = run_hook("pre", Path.home() / "library/launchagents/ORG.PANCIA.VPC.plist")
        assert rc == 2

    def test_allows_service_plist_source(self):
        rc, _ = run_hook("pre", Path.home() / "dotfiles/services/vpc/org.pancia.vpc.plist")
        assert rc == 0

    def test_allows_new_file(self):
        rc, _ = run_hook("pre", "/tmp/does/not/exist/new.txt")
        assert rc == 0

    def test_blocks_own_destination(self):
        """The hook should protect its own hardlink."""
        rc, stderr = run_hook("pre", Path.home() / ".claude/hooks/ensure-rcs.sh")
        assert rc == 2
        assert "claude-ensure-rcs-hook.sh" in stderr


def run_hook_home(mode, file_path, home):
    """Like run_hook, against a throwaway HOME (which may be a symlink)."""
    payload = json.dumps({"tool_input": {"file_path": str(file_path)}})
    result = subprocess.run(
        [str(HOOK), mode], input=payload, capture_output=True, text=True,
        env=dict(os.environ, HOME=str(home)),
    )
    return result.returncode, result.stderr.strip()


class TestResolvedPaths:
    """The target is resolved before matching, so HOME and dotfiles must be
    resolved too, or a symlink in either flips the answer."""

    @pytest.fixture
    def home(self, tmp_path):
        real = tmp_path / "real-home"
        rcs = real / "real-dotfiles" / "rcs"
        rcs.mkdir(parents=True)
        (real / "dotfiles").symlink_to(real / "real-dotfiles")
        (rcs / "MANIFEST").write_text("app.conf -> $HOME/.app.conf\n")
        (rcs / "app.conf").write_text("x\n")
        os.link(rcs / "app.conf", real / ".app.conf")
        (real / "Library" / "LaunchAgents").mkdir(parents=True)
        (real / "Library" / "LaunchAgents" / "org.pancia.demo.plist").write_text("p\n")
        link = tmp_path / "home"
        link.symlink_to(real)
        return link

    def test_source_editable_through_symlinked_home_and_dotfiles(self, home):
        rc, stderr = run_hook_home("pre", home / "dotfiles/rcs/app.conf", home)
        assert rc == 0, stderr

    def test_destination_blocked_through_symlinked_home(self, home):
        rc, stderr = run_hook_home("pre", home / ".app.conf", home)
        assert rc == 2
        assert "via rcs/MANIFEST" in stderr

    def test_plist_blocked_through_symlinked_home(self, home):
        rc, _ = run_hook_home("pre", home / "Library/LaunchAgents/org.pancia.demo.plist", home)
        assert rc == 2

    def test_extra_hardlink_of_a_source_is_blocked_by_inode(self, home):
        extra = home / "elsewhere.conf"
        os.link(home / "dotfiles/rcs/app.conf", extra)
        rc, stderr = run_hook_home("pre", extra, home)
        assert rc == 2
        assert "same file (hardlink)" in stderr

    def test_post_mode_relinks_after_service_plist_edit(self, home):
        """Post mode must call rcs-sync for a services/ plist, not just rcs/."""
        marker = home / "ran"
        stub = home / "dotfiles" / "bin" / "rcs-sync"
        stub.parent.mkdir()
        stub.write_text(f"#!/bin/bash\ntouch {marker}\n")
        stub.chmod(0o755)
        plist = home / "dotfiles/services/demo/org.pancia.demo.plist"
        plist.parent.mkdir(parents=True)
        plist.write_text("p\n")  # post mode runs after the edit, so it exists
        rc, _ = run_hook_home("post", plist, home)
        assert rc == 0
        assert marker.exists()


class TestPostMode:
    """PostToolUse: re-link after editing source files in rcs/. Runs against a
    throwaway HOME whose rcs-sync is a stub, so the real links are never
    touched and the test can see whether rcs-sync was called."""

    @pytest.fixture
    def home(self, tmp_path):
        rcs = tmp_path / "dotfiles" / "rcs"
        rcs.mkdir(parents=True)
        (rcs / "MANIFEST").write_text("app.conf -> $HOME/.app.conf\n")
        (rcs / "app.conf").write_text("x\n")
        (tmp_path / "dotfiles" / "fish").mkdir()
        (tmp_path / "dotfiles" / "fish" / "config.fish").write_text("x\n")
        stub = tmp_path / "dotfiles" / "bin" / "rcs-sync"
        stub.parent.mkdir()
        stub.write_text(f"#!/bin/bash\ntouch {tmp_path / 'ran'}\n")
        stub.chmod(0o755)
        return tmp_path

    def ran(self, home):
        return (home / "ran").exists()

    def test_source_file_runs_rcs_sync(self, home):
        rc, _ = run_hook_home("post", home / "dotfiles/rcs/app.conf", home)
        assert rc == 0
        assert self.ran(home)

    def test_source_file_in_other_case_runs_rcs_sync(self, home):
        rc, _ = run_hook_home("post", home / "dotfiles/RCS/APP.CONF", home)
        assert rc == 0
        assert self.ran(home)

    def test_skips_unrelated_file(self, home):
        rc, _ = run_hook_home("post", "/tmp/some/random/file.txt", home)
        assert rc == 0
        assert not self.ran(home)

    def test_skips_non_rcs_dotfiles(self, home):
        rc, _ = run_hook_home("post", home / "dotfiles/fish/config.fish", home)
        assert rc == 0
        assert not self.ran(home)


def run_hook_raw(mode, payload):
    """Run the hook on a raw JSON payload string."""
    result = subprocess.run(
        [str(HOOK), mode], input=payload, capture_output=True, text=True,
    )
    return result.returncode, result.stderr.strip()


class TestJsonParsing:
    """file_path is read from the JSON without jq; escapes must survive."""

    DST = str(Path.home() / ".config/tmux/tmux.conf")

    def test_escaped_slashes_are_unescaped(self):
        rc, _ = run_hook_raw("pre", json.dumps({"tool_input": {"file_path": self.DST}}).replace("/", "\\/"))
        assert rc == 2

    def test_unicode_escape_is_decoded(self):
        # json.dumps escapes non-ASCII as \\uXXXX; the 'x' here is written as \\u0078
        payload = json.dumps({"tool_input": {"file_path": self.DST}}).replace("tmux.conf", "tmu\\u0078.conf")
        rc, _ = run_hook_raw("pre", payload)
        assert rc == 2

    def test_escaped_quote_does_not_truncate_the_path(self, tmp_path):
        """The old grep stopped at the first \\" and read a different path."""
        weird = tmp_path / 'we"ird'
        weird.mkdir()
        os.symlink(Path.home() / ".config/tmux", weird / "tmux")
        rc, _ = run_hook("pre", weird / "tmux" / "tmux.conf")
        assert rc == 2

    def test_file_path_text_inside_another_field_is_ignored(self):
        payload = json.dumps({"tool_input": {
            "old_string": f'"file_path": "{self.DST}"',
            "file_path": "/tmp/ok.txt",
        }})
        rc, _ = run_hook_raw("pre", payload)
        assert rc == 0


class TestPerformance:
    """Ensure common cases are fast."""

    def test_unrelated_file_under_50ms(self):
        """The most common case (unrelated file) should be very fast."""
        import time
        start = time.monotonic()
        for _ in range(5):
            run_hook("post", "/tmp/some/random/file.txt")
        elapsed = (time.monotonic() - start) / 5
        assert elapsed < 0.05, f"Average post-mode unrelated file took {elapsed:.3f}s"

    def test_pre_mode_under_100ms(self):
        """Pre mode scans MANIFEST but should still be quick."""
        import time
        start = time.monotonic()
        for _ in range(5):
            run_hook("pre", "/tmp/some/random/file.txt")
        elapsed = (time.monotonic() - start) / 5
        assert elapsed < 0.1, f"Average pre-mode unrelated file took {elapsed:.3f}s"
