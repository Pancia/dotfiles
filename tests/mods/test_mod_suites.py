"""Runs each Claude Code mod's own tests through `claude plugin test`.

The mods in ai/mods/ (loaded in every session by CLAUDE_CODE_PLUGIN_DIRS in
rcs/claude-settings.json) keep their tests beside them, in ai/mods/<name>/tests/,
as *.test.ts and *.test.tsx files that only `claude plugin test <folder>` can
run. This file is the bridge that puts them in `cmds test`, so they cannot rot
unrun. One pytest case per mod folder that has a tests/ folder.

`claude plugin test` runs each test file in a child of the claude binary, with
no fs, network or process access: it needs no login and writes nothing.
Skipped when `claude` is not on PATH.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parents[2]
MODS = DOTFILES / "ai" / "mods"
SUITES = sorted(p.parent for p in MODS.glob("*/tests") if p.is_dir())


def test_some_mod_has_tests():
    """A glob that finds nothing would make this whole file pass silently."""
    assert SUITES, f"no ai/mods/*/tests folder under {MODS}"


@pytest.mark.parametrize("mod", SUITES, ids=[p.name for p in SUITES])
def test_mod_suite_passes(mod):
    claude = shutil.which("claude")
    if not claude:
        pytest.skip("claude is not on PATH")
    r = subprocess.run([claude, "plugin", "test", str(mod)],
                       capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
    assert r.returncode == 0, out
    assert " 0 fail" in out, out
