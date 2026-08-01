"""Tests for fish/functions/__jump_direct.fish.

__jump_direct is the shared short-circuit behind `p`, `j` and `z`. All three
take their argument as a *fuzzy query* for a picker, but their completions hand
back whole paths — so tab-completing leaves an exact directory on the command
line, which the picker then narrows to a single row and waits for a second
Enter on. __jump_direct catches that case and jumps.

The contract is deliberately narrow, and each half matters:

  - returns 0 having cd'd, only when the single argument is already a directory
  - returns 1 having changed nothing *and said nothing* otherwise, so the
    caller falls through to its picker

The fall-through half is what these tests guard hardest: a false positive would
silently swallow a fuzzy query the user meant for the picker.
"""

import os
import subprocess
from pathlib import Path
from typing import NamedTuple

DOTFILES = Path(__file__).resolve().parents[2]
JUMP_DIRECT = DOTFILES / "fish" / "functions" / "__jump_direct.fish"


def fish_eval(code: str, *, env: dict | None = None) -> subprocess.CompletedProcess:
    """Source __jump_direct.fish then run code in Fish shell.

    --no-config keeps the user's own config (and the real `p`/`j`/`z`) out of
    the way, so a test can override $HOME without fish trying to load a config
    tree from the fixture directory.
    """
    full_code = f"source {JUMP_DIRECT}\n{code}"
    run_env = {**os.environ, **(env or {})}
    return subprocess.run(
        ["fish", "--no-config", "-c", full_code],
        capture_output=True,
        text=True,
        env=run_env,
    )


class Jump(NamedTuple):
    rc: int
    pwd: str
    stderr: str


def jump(arg_code: str, *, start: str | None = None, env: dict | None = None) -> Jump:
    """Run `__jump_direct <arg_code>` and report rc, resulting pwd, and stderr.

    stderr is part of the contract, not incidental. Checking only rc and pwd
    cannot distinguish `test -d` from `test -e`: with -e a *file* argument
    passes the check, `cd` then fails, and rc is 1 with pwd unchanged either
    way. The only difference is that -e dumps a six-line fish stack trace into
    the terminal on every such fall-through. Silence is what pins that guard —
    without asserting it, swapping -d for -e leaves the suite green.

    $status is captured on the very next line: any intervening command would
    overwrite it.
    """
    cd_first = f"cd {start}\n" if start else ""
    code = f"{cd_first}__jump_direct {arg_code}\nset -l rc $status\npwd\nexit $rc"
    r = fish_eval(code, env=env)
    return Jump(r.returncode, r.stdout.strip().splitlines()[-1], r.stderr)


def samefile(a: str, b) -> bool:
    """Compare paths through symlinks — /tmp is /private/tmp on macOS."""
    return Path(a).resolve() == Path(b).resolve()


# =============================================================================
# Jumps: the argument is already a directory
# =============================================================================


class TestJumps:
    def test_absolute_directory(self, tmp_path):
        target = tmp_path / "youtube-enhancer"
        target.mkdir()
        r = jump(f"'{target}'", start="/")
        assert r.rc == 0
        assert samefile(r.pwd, target)

    def test_tilde_is_expanded(self, tmp_path):
        # The helper expands ~/ itself; fish would normally have done it at
        # parse time, but a quoted or programmatically-passed argument arrives
        # literal.
        (tmp_path / "projects").mkdir()
        r = jump("'~/projects'", start="/", env={"HOME": str(tmp_path)})
        assert r.rc == 0
        assert samefile(r.pwd, tmp_path / "projects")

    def test_relative_path_with_a_slash(self, tmp_path):
        (tmp_path / "a" / "b").mkdir(parents=True)
        r = jump("a/b", start=f"'{tmp_path}'")
        assert r.rc == 0
        assert samefile(r.pwd, tmp_path / "a" / "b")

    def test_trailing_slash(self, tmp_path):
        target = tmp_path / "proj"
        target.mkdir()
        r = jump(f"'{target}/'", start="/")
        assert r.rc == 0
        assert samefile(r.pwd, target)

    def test_path_containing_spaces(self, tmp_path):
        target = tmp_path / "my project"
        target.mkdir()
        r = jump(f"'{target}'", start="/")
        assert r.rc == 0
        assert samefile(r.pwd, target)

    def test_symlink_to_a_directory(self, tmp_path):
        # Jump targets are often symlinks (~/.config/fish/functions is one).
        real = tmp_path / "real"
        real.mkdir()
        link = tmp_path / "link"
        link.symlink_to(real)
        r = jump(f"'{link}'", start="/")
        assert r.rc == 0

    def test_emits_nothing_on_stdout(self, tmp_path):
        # Callers use it as `if __jump_direct $argv`, and `p`/`j` follow up with
        # their own output; stray chatter here would land in the terminal.
        target = tmp_path / "proj"
        target.mkdir()
        r = fish_eval(f"__jump_direct '{target}'")
        assert r.returncode == 0
        assert r.stdout == ""


# =============================================================================
# Fall-through: the argument is a query, not a directory
#
# Every case here asserts silence as well as rc and pwd. See jump()'s docstring
# for why: without it, `test -d` -> `test -e` survives.
# =============================================================================


class TestFallsThrough:
    def test_bare_word_stays_a_query(self, tmp_path):
        # The whole point: `p you` must still reach the picker.
        r = jump("you", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_bare_word_that_names_a_real_subdirectory(self, tmp_path):
        # Even when it *would* resolve, a slashless word is a query. Otherwise
        # `p src` would jump into ./src instead of searching for a project.
        (tmp_path / "src").mkdir()
        r = jump("src", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_dot_is_not_swallowed(self, tmp_path):
        r = jump(".", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_dotdot_is_not_swallowed(self, tmp_path):
        (tmp_path / "sub").mkdir()
        r = jump("..", start=f"'{tmp_path}/sub'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path / "sub")
        assert r.stderr == ""

    def test_nonexistent_absolute_path(self, tmp_path):
        r = jump(f"'{tmp_path}/definitely-not-here'", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_existing_file_is_not_a_directory(self, tmp_path):
        # `test -d`, not `test -e`. fzfm's __fzfm_filter_existing uses -e; with
        # -e here the file passes the check and `cd` fails, which looks correct
        # from rc alone but spews a stack trace. The stderr assertion is the
        # one that fails under that mutation.
        f = tmp_path / "notes.txt"
        f.write_text("x")
        r = jump(f"'{f}'", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_no_arguments(self, tmp_path):
        r = jump("", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_two_arguments(self, tmp_path):
        # `z` joins multiple args into one query; a multi-word invocation is
        # never an exact path.
        target = tmp_path / "proj"
        target.mkdir()
        r = jump(f"'{target}' extra", start=f"'{tmp_path}'")
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""

    def test_tilde_alone(self, tmp_path):
        # No slash, so it never reaches the -d check. In a real shell fish has
        # already expanded a bare ~ to an absolute path before we see it.
        r = jump("'~'", start=f"'{tmp_path}'", env={"HOME": str(tmp_path)})
        assert r.rc == 1
        assert samefile(r.pwd, tmp_path)
        assert r.stderr == ""
