"""Tests for the `p` and `j` jump commands (fish/functions/{p,j}.fish).

These cover the wiring around __jump_direct rather than __jump_direct itself
(see test_jump_direct.py). Two things are easy to break silently:

  - the exact-directory short-circuit must run *before* the picker, and must
    still record the jump in fish history the way the picker's own jump path
    does
  - --select-1 is handed to fzf through FZF_OPTS_OVERRIDE, which only works
    because the variable is *exported*. A plain `set -l` is invisible to the
    called function, costs nothing at parse time, raises no error, and simply
    stops the feature working.
"""

import os
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[2]
FUNCTIONS = DOTFILES / "fish" / "functions"

# Stubs for everything p/j reach outside their own file, so the tests exercise
# the wiring without launching a picker or writing to real fish history.
STUBS = """
function __fzfm_search
    echo "SEARCH mode=$argv[1] query=$argv[2] opts=$FZF_OPTS_OVERRIDE"
end
function __fzfm_save_pwd_history
    echo "SAVED_HISTORY"
end
"""


def run(cmd: str, *, sources: list[Path], cwd: str | None = None):
    preamble = "\n".join(f"source {p}" for p in sources)
    code = f"{preamble}\n{STUBS}\n{cmd}"
    return subprocess.run(
        ["fish", "--no-config", "-c", code],
        capture_output=True,
        text=True,
        cwd=cwd,
        env=os.environ.copy(),
    )


def jump_cmd(name: str, args: str, *, cwd: str | None = None):
    return run(
        f"{name} {args}",
        sources=[FUNCTIONS / "__jump_direct.fish", FUNCTIONS / f"{name}.fish"],
        cwd=cwd,
    )


class TestSelectOne:
    """--select-1 makes fzf accept a unique match without drawing the picker."""

    def test_p_passes_select_1_to_fzf(self):
        r = jump_cmd("p", "youtube-enh")
        assert "--select-1" in r.stdout, (
            "FZF_OPTS_OVERRIDE did not reach __fzfm_search; `set -l` instead of "
            f"`set -lx` is the usual cause. Got: {r.stdout!r}"
        )

    def test_j_passes_select_1_to_fzf(self):
        r = jump_cmd("j", "somewhere")
        assert "--select-1" in r.stdout

    def test_existing_override_is_preserved(self):
        # A user-set FZF_OPTS_OVERRIDE must be extended, not replaced.
        r = run(
            "set -gx FZF_OPTS_OVERRIDE --my-flag\np query",
            sources=[FUNCTIONS / "__jump_direct.fish", FUNCTIONS / "p.fish"],
        )
        assert "--my-flag" in r.stdout
        assert "--select-1" in r.stdout

    def test_override_does_not_leak_to_the_shell(self):
        # It is local-exported precisely so it does not persist after the jump.
        r = run(
            "p query\nset -q FZF_OPTS_OVERRIDE; and echo LEAKED; or echo CLEAN",
            sources=[FUNCTIONS / "__jump_direct.fish", FUNCTIONS / "p.fish"],
        )
        assert "CLEAN" in r.stdout
        assert "LEAKED" not in r.stdout


class TestShortCircuit:
    """An argument that is already a directory must never reach the picker."""

    def test_p_exact_directory_skips_the_picker(self, tmp_path):
        target = tmp_path / "proj"
        target.mkdir()
        r = jump_cmd("p", f"'{target}'", cwd="/")
        assert "SEARCH" not in r.stdout

    def test_j_exact_directory_skips_the_picker(self, tmp_path):
        target = tmp_path / "proj"
        target.mkdir()
        r = jump_cmd("j", f"'{target}'", cwd="/")
        assert "SEARCH" not in r.stdout

    def test_p_records_the_jump_in_history(self, tmp_path):
        # The picker's own jump path calls __fzfm_save_pwd_history; the
        # short-circuit has to match it or jumps stop appearing in history.
        target = tmp_path / "proj"
        target.mkdir()
        r = jump_cmd("p", f"'{target}'", cwd="/")
        assert "SAVED_HISTORY" in r.stdout

    def test_j_records_the_jump_in_history(self, tmp_path):
        target = tmp_path / "proj"
        target.mkdir()
        r = jump_cmd("j", f"'{target}'", cwd="/")
        assert "SAVED_HISTORY" in r.stdout

    def test_p_fuzzy_word_still_reaches_the_picker(self):
        r = jump_cmd("p", "youtube-enh")
        assert "SEARCH mode=jump_projects query=youtube-enh" in r.stdout
        assert "SAVED_HISTORY" not in r.stdout

    def test_j_fuzzy_word_still_reaches_the_picker(self):
        r = jump_cmd("j", "somewhere")
        assert "SEARCH mode=jump_frecent query=somewhere" in r.stdout
        assert "SAVED_HISTORY" not in r.stdout

    def test_p_with_no_arguments_reaches_the_picker(self):
        r = jump_cmd("p", "")
        assert "SEARCH mode=jump_projects" in r.stdout
