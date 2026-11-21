#!/usr/bin/env python3
"""Tests for ensure-rcs.sh Claude Code hook."""

import json
import os
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).parent.parent.parent
HOOK = DOTFILES / "rcs" / "claude-ensure-rcs-hook.sh"


# The destinations the TestPreMode and TestJsonParsing cases name. The
# fixture home holds a plain file at each, so a path resolves as it would in a
# real home; none is a hardlink of a source, so the tree is never touched.
DESTINATIONS = [
    ".config/tmux/tmux.conf",
    ".config/fish/config.fish",
    ".claude/CLAUDE.md",
    ".claude/hooks/ensure-rcs.sh",
    "Library/LaunchAgents/org.pancia.vpc.plist",
]


@pytest.fixture
def tree_home(tmp_path):
    """A throwaway HOME whose dotfiles links to the tree under test, so the
    hook reads this tree's rcs/MANIFEST rather than the live ~/dotfiles."""
    home = tmp_path / "home"
    home.mkdir()
    (home / "dotfiles").symlink_to(DOTFILES)
    for rel in DESTINATIONS:
        (home / rel).parent.mkdir(parents=True, exist_ok=True)
        (home / rel).write_text("x\n")
    return home


# The hook resolves ~/dotfiles before naming a source, so its messages carry
# the tree's real path, which need not end in "dotfiles".
TREE = DOTFILES.resolve()


def run_hook(mode, file_path, home):
    """Run the hook with given mode and file_path against a throwaway HOME
    (which may be a symlink), return (exit_code, stderr)."""
    payload = json.dumps({"tool_input": {"file_path": str(file_path)}})
    return run_hook_raw(mode, payload, home)


def run_hook_raw(mode, payload, home):
    """Run the hook on a raw JSON payload string against a throwaway HOME."""
    result = subprocess.run(
        [str(HOOK), mode], input=payload, capture_output=True, text=True,
        env=dict(os.environ, HOME=str(home)),
    )
    return result.returncode, result.stderr.strip()


class TestPreMode:
    """PreToolUse: block edits to MANIFEST destination files."""

    def test_blocks_destination_file(self, tree_home):
        # MANIFEST maps tmux.conf to the XDG path, not ~/.tmux.conf. This test
        # asserted the pre-XDG destination for months without failing, because
        # tests/hooks was never registered in run_tests.py and so never ran.
        rc, stderr = run_hook("pre", tree_home / ".config/tmux/tmux.conf", tree_home)
        assert rc == 2
        assert "rcs/MANIFEST" in stderr
        assert str(TREE / "rcs/tmux.conf") in stderr

    def test_blocks_nested_destination(self, tree_home):
        rc, _ = run_hook("pre", tree_home / ".config/fish/config.fish", tree_home)
        assert rc == 2

    def test_allows_source_file(self, tree_home):
        rc, _ = run_hook("pre", tree_home / "dotfiles/rcs/tmux.conf", tree_home)
        assert rc == 0

    def test_allows_unrelated_file(self, tree_home):
        rc, _ = run_hook("pre", "/tmp/some/random/file.txt", tree_home)
        assert rc == 0

    def test_allows_empty_file_path(self, tree_home):
        rc, _ = run_hook_raw("pre", json.dumps({"tool_input": {}}), tree_home)
        assert rc == 0

    def test_blocks_claude_md_destination(self, tree_home):
        rc, stderr = run_hook("pre", tree_home / ".claude/CLAUDE.md", tree_home)
        assert rc == 2
        assert "claude-user-claude.md" in stderr

    def test_blocks_destination_in_other_letter_case(self, tree_home):
        """APFS ignores case, so this names the same file."""
        rc, stderr = run_hook("pre", tree_home / ".Config/TMUX/tmux.conf", tree_home)
        assert rc == 2
        assert str(TREE / "rcs/tmux.conf") in stderr

    def test_blocks_destination_written_with_tilde(self, tree_home):
        rc, _ = run_hook("pre", "~/.config/tmux/tmux.conf", tree_home)
        assert rc == 2

    def test_allows_source_in_other_letter_case(self, tree_home):
        """The source shares the destination's inode; it must stay editable."""
        rc, _ = run_hook("pre", tree_home / "dotfiles/RCS/tmux.conf", tree_home)
        assert rc == 0

    def test_blocks_launch_agent_plist(self, tree_home):
        rc, stderr = run_hook("pre", tree_home / "Library/LaunchAgents/org.pancia.vpc.plist", tree_home)
        assert rc == 2
        assert str(TREE / "services/vpc/org.pancia.vpc.plist") in stderr

    def test_blocks_launch_agent_plist_in_other_letter_case(self, tree_home):
        rc, _ = run_hook("pre", tree_home / "library/launchagents/ORG.PANCIA.VPC.plist", tree_home)
        assert rc == 2

    def test_allows_service_plist_source(self, tree_home):
        rc, _ = run_hook("pre", tree_home / "dotfiles/services/vpc/org.pancia.vpc.plist", tree_home)
        assert rc == 0

    def test_allows_new_file(self, tree_home):
        rc, _ = run_hook("pre", "/tmp/does/not/exist/new.txt", tree_home)
        assert rc == 0

    def test_blocks_own_destination(self, tree_home):
        """The hook should protect its own hardlink."""
        rc, stderr = run_hook("pre", tree_home / ".claude/hooks/ensure-rcs.sh", tree_home)
        assert rc == 2
        assert "claude-ensure-rcs-hook.sh" in stderr

    def test_reads_the_manifest_of_the_tree_under_test(self, tree_home):
        """The hook must read this tree's MANIFEST: its first entry is blocked."""
        manifest = (DOTFILES / "rcs" / "MANIFEST").read_text().splitlines()
        line = next(l for l in manifest if l.strip() and not l.lstrip().startswith("#"))
        src, dst = (part.strip() for part in line.split(" -> ", 1))
        dst = Path(dst.replace("$HOME", str(tree_home)))
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text("x\n")
        rc, stderr = run_hook("pre", dst, tree_home)
        assert rc == 2, stderr
        assert "via rcs/MANIFEST" in stderr
        if not src.startswith(("/", "$HOME")):
            assert str(TREE / "rcs" / src) in stderr


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
        rc, stderr = run_hook("pre", home / "dotfiles/rcs/app.conf", home)
        assert rc == 0, stderr

    def test_destination_blocked_through_symlinked_home(self, home):
        rc, stderr = run_hook("pre", home / ".app.conf", home)
        assert rc == 2
        assert "via rcs/MANIFEST" in stderr

    def test_plist_blocked_through_symlinked_home(self, home):
        rc, _ = run_hook("pre", home / "Library/LaunchAgents/org.pancia.demo.plist", home)
        assert rc == 2

    def test_extra_hardlink_of_a_source_is_blocked_by_inode(self, home):
        extra = home / "elsewhere.conf"
        os.link(home / "dotfiles/rcs/app.conf", extra)
        rc, stderr = run_hook("pre", extra, home)
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
        rc, _ = run_hook("post", plist, home)
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
        rc, _ = run_hook("post", home / "dotfiles/rcs/app.conf", home)
        assert rc == 0
        assert self.ran(home)

    def test_source_file_in_other_case_runs_rcs_sync(self, home):
        rc, _ = run_hook("post", home / "dotfiles/RCS/APP.CONF", home)
        assert rc == 0
        assert self.ran(home)

    def test_skips_unrelated_file(self, home):
        rc, _ = run_hook("post", "/tmp/some/random/file.txt", home)
        assert rc == 0
        assert not self.ran(home)

    def test_skips_non_rcs_dotfiles(self, home):
        rc, _ = run_hook("post", home / "dotfiles/fish/config.fish", home)
        assert rc == 0
        assert not self.ran(home)


class TestJsonParsing:
    """file_path is read from the JSON without jq; escapes must survive."""

    @pytest.fixture
    def dst(self, tree_home):
        return str(tree_home / ".config/tmux/tmux.conf")

    def test_escaped_slashes_are_unescaped(self, tree_home, dst):
        rc, _ = run_hook_raw("pre", json.dumps({"tool_input": {"file_path": dst}}).replace("/", "\\/"), tree_home)
        assert rc == 2

    def test_unicode_escape_is_decoded(self, tree_home, dst):
        # json.dumps escapes non-ASCII as \\uXXXX; the 'x' here is written as \\u0078
        payload = json.dumps({"tool_input": {"file_path": dst}}).replace("tmux.conf", "tmu\\u0078.conf")
        rc, _ = run_hook_raw("pre", payload, tree_home)
        assert rc == 2

    def test_escaped_quote_does_not_truncate_the_path(self, tmp_path, tree_home):
        """The old grep stopped at the first \\" and read a different path."""
        weird = tmp_path / 'we"ird'
        weird.mkdir()
        os.symlink(tree_home / ".config/tmux", weird / "tmux")
        rc, _ = run_hook("pre", weird / "tmux" / "tmux.conf", tree_home)
        assert rc == 2

    def test_file_path_text_inside_another_field_is_ignored(self, tree_home, dst):
        payload = json.dumps({"tool_input": {
            "old_string": f'"file_path": "{dst}"',
            "file_path": "/tmp/ok.txt",
        }})
        rc, _ = run_hook_raw("pre", payload, tree_home)
        assert rc == 0


class TestPerformance:
    """Ensure common cases are fast."""

    def test_unrelated_file_under_50ms(self, tree_home):
        """The most common case (unrelated file) should be very fast."""
        import time
        start = time.monotonic()
        for _ in range(5):
            run_hook("post", "/tmp/some/random/file.txt", tree_home)
        elapsed = (time.monotonic() - start) / 5
        assert elapsed < 0.05, f"Average post-mode unrelated file took {elapsed:.3f}s"

    def test_pre_mode_under_100ms(self, tree_home):
        """Pre mode scans MANIFEST but should still be quick."""
        import time
        start = time.monotonic()
        for _ in range(5):
            run_hook("pre", "/tmp/some/random/file.txt", tree_home)
        elapsed = (time.monotonic() - start) / 5
        assert elapsed < 0.1, f"Average pre-mode unrelated file took {elapsed:.3f}s"
