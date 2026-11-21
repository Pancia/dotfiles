"""Clean-clone guard: the suite runs in a throwaway home, never the live checkout.

`lib/python/run_tests.py` starts every component's pytest with a throwaway
`HOME` that holds a `dotfiles` symlink to the tree under test. These tests pin
that, and scan the test sources for paths that name the live `~/dotfiles`.

A bare `pytest` (not through the runner) fails `test_home_is_a_throwaway` on
purpose: it runs against the real home, so it is not the gate's environment.
"""

import os
import pwd
import re
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
THIS = Path(__file__).resolve()

# The three spellings of the live checkout. `Path.home()` counts only when the
# same line joins it with `dotfiles` (`/ "dotfiles"`, `.joinpath("dotfiles")`).
LIVE_PATH = re.compile(
    r"Path\.home\(\)\s*(?:/|\.joinpath\()\s*['\"]dotfiles"
    r"|~/dotfiles"
    r"|\$HOME/dotfiles"
)

# Lines that name the live checkout on purpose. Keyed by file and the exact
# stripped line text, never by pattern: a new live-path line in one of these
# files still fails. Each value is the reason it stays.
ALLOWED = {
    (
        "tests/fish/test_cc_worktree_wrapper.py",
        "points at the live ~/dotfiles, not this checkout). So nothing re-orders PATH",
    ): "docstring: the file guards against the live checkout, so it names it",
    (
        "tests/fish/test_cc_worktree_wrapper.py",
        "~/dotfiles/bin ahead of the stubs. PATH is still set inside the fish",
    ): "docstring: the same guard against the live checkout's bin/",
    (
        "tests/fish/test_trash.py",
        "the live ~/dotfiles) and costs ~0.7s a call. This checkout's bin/ goes first",
    ): "docstring: the guard that puts this checkout's bin/ before the live one",
    (
        "tests/fish/conftest.py",
        "`~/dotfiles/lib/python/revive.py` and sources `~/dotfiles/fish/...`.",
    ): "docstring: why each pane's home links dotfiles to the tree under test",
    (
        "tests/fish/test_pane_isolation.py",
        "'echo \"|LINK=\"(realpath $HOME/dotfiles)\"|\"',",
    ): "fish run in the throwaway home: checks its dotfiles link is this tree",
    (
        "tests/hooks/test_ensure_rcs.py",
        'hook reads this tree\'s rcs/MANIFEST rather than the live ~/dotfiles."""',
    ): "docstring: why the hook is pointed at this tree",
    (
        "tests/lib/python/test_cc_worktree.py",
        '"""~/dotfiles cannot be isolated: about half its tracked files load by',
    ): "docstring: the refusal under test names the checkout it refuses",
    (
        "tests/lib/python/test_cc_worktree.py",
        '"""Defect: `rcs/gitconfig` sets `core.hooksPath = ~/dotfiles/git/hooks`, so',
    ): "docstring: describes the live hooksPath the runner's git config drops",
    (
        "tests/lib/python/test_llm_output.py",
        "`parents[3]`-of-the-test and `~/dotfiles` are the same directory — so comparing",
    ): "docstring: why the contract path is derived from the module",
    (
        "tests/lib/python/test_llm_output.py",
        'marker = "CONTRACT FROM THE COPY, not from ~/dotfiles\\n"',
    ): "input string the code under test reads from a copied tree",
    (
        "tests/lib/python/test_llm_output.py",
        '"""Derived from the module, not from ~/dotfiles — a worktree must prompt with',
    ): "docstring: why the contract path is derived from the module",
}


def _real(path) -> Path:
    # macOS has /var and /private/var: resolve both sides before comparing.
    return Path(os.path.realpath(path))


def test_home_is_a_throwaway():
    home = _real(os.environ["HOME"])
    real_home = _real(pwd.getpwuid(os.getuid()).pw_dir)
    tmp = _real(tempfile.gettempdir())
    assert home != real_home, (
        f"HOME is the real home {real_home}; run through lib/python/run_tests.py"
    )
    assert home.is_relative_to(tmp), f"HOME {home} is not under {tmp}"


def test_dotfiles_in_home_is_the_tree_under_test():
    link = Path(os.environ["HOME"]) / "dotfiles"
    assert link.exists(), f"{link} is missing"
    assert _real(link) == _real(REPO)


def _sources():
    yield from sorted((REPO / "tests").rglob("*.py"))
    yield from sorted((REPO / "roleplay" / "tests").glob("*.py"))


def _live_path_lines():
    for path in _sources():
        if path.resolve() == THIS:
            continue
        rel = path.relative_to(REPO).as_posix()
        for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            text = line.strip()
            if text.startswith("#") or not LIVE_PATH.search(text):
                continue
            yield rel, n, text


def test_no_test_names_the_live_checkout():
    found = list(_live_path_lines())
    bad = [f"{rel}:{n}: {text}" for rel, n, text in found if (rel, text) not in ALLOWED]
    assert not bad, "tests name the live ~/dotfiles checkout:\n" + "\n".join(bad)


def test_allowlist_has_no_stale_entries():
    seen = {(rel, text) for rel, _, text in _live_path_lines()}
    stale = [f"{rel}: {text}" for rel, text in ALLOWED if (rel, text) not in seen]
    assert not stale, "allowlist entries match no line:\n" + "\n".join(stale)


def test_scan_catches_each_spelling():
    for line in (
        'p = Path.home() / "dotfiles" / "bin"',
        "p = Path.home().joinpath('dotfiles')",
        'cmd = "~/dotfiles/bin/x"',
        'cmd = "$HOME/dotfiles/bin/x"',
    ):
        assert LIVE_PATH.search(line), line
    assert not LIVE_PATH.search("home = Path.home()")
