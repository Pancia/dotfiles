#!/usr/bin/env python3
"""Tests for ensure-rcs.sh Claude Code hook."""

import json
import subprocess
from pathlib import Path

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
        rc, stderr = run_hook("pre", Path.home() / ".tmux.conf")
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

    def test_blocks_own_destination(self):
        """The hook should protect its own hardlink."""
        rc, stderr = run_hook("pre", Path.home() / ".claude/hooks/ensure-rcs.sh")
        assert rc == 2
        assert "claude-ensure-rcs-hook.sh" in stderr


class TestPostMode:
    """PostToolUse: re-link after editing source files in rcs/."""

    def test_allows_source_file(self):
        rc, _ = run_hook("post", Path.home() / "dotfiles/rcs/tmux.conf")
        assert rc == 0

    def test_skips_unrelated_file_fast(self):
        rc, _ = run_hook("post", "/tmp/some/random/file.txt")
        assert rc == 0

    def test_skips_non_rcs_dotfiles(self):
        rc, _ = run_hook("post", Path.home() / "dotfiles/fish/config.fish")
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
