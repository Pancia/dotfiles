#!/usr/bin/env python3
"""
Multi-language test runner for dotfiles.
Dispatches to pytest, busted, or fishtape based on component config.
"""

import contextlib
import functools
import os
import re
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator
from pathlib import Path

# Derived from this file's location, not $HOME, so a clone or worktree
# somewhere else tests *itself* rather than silently testing ~/dotfiles.
# lib/python/run_tests.py -> parents[2] is the repo root.
DOTFILES = Path(__file__).resolve().parents[2]
TESTS_DIR = DOTFILES / "tests"

# Component configuration: runner + dependencies + aliases
# source_path: path to source code for coverage (relative to DOTFILES)
# isolation: False runs the component's pytest with the inherited environment
#   instead of a throwaway home (see isolated_env). It needs an
#   "isolation_reason" string, which the runner prints, and a line in
#   docs/testing.md. Use it only for a component that cannot run otherwise.
#
# Every directory under tests/ that holds tests must be registered here --
# run_all() iterates this dict, so an unregistered tree never runs at all.
COMPONENTS = {
    "services/youtube_transcribe": {
        "runner": "pytest",
        "deps": ["pytest-asyncio", "httpx", "fastapi", "pydantic", "sse-starlette"],
        "aliases": ["youtube-transcribe", "yt"],
        "source_path": "services/youtube-transcribe",
    },
    # Drives services/server-check/script.sh with a faked server answer, and
    # checks that show.sh has help for every problem message. No network.
    "services/server_check": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["server-check"],
        "source_path": "services/server-check",
    },
    "lib/python": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["python"],
    },
    # Hammerspoon seeds run under plain lua5.4 with a stub `hs`
    # (tests/lib/lua/harness.lua), driven from pytest so the counts reach the
    # summary. busted would need a luarocks install and reports no counts.
    # Skips if lua5.4 is missing.
    "lib/lua": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["lua", "hammerspoon"],
        "source_path": "lib/lua/seeds",
    },
    "bin/astro": {
        "runner": "pytest",
        "deps": ["kerykeion", "pyswisseph"],
        "aliases": ["astro"],
    },
    "bin/ytdl": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["ytdl"],
        "source_path": "bin/ytdl",
    },
    # bin/cc-peers and the PEERS section of bin/vcs-status-for-ai: fake session
    # registries and transcripts under tmp_path; needs git.
    "bin/cc-peers": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["cc-peers"],
        "source_path": "bin/cc-peers",
    },
    # bin/scratch: each test gets its own SCRATCH_ROOT and HOME; needs git.
    "bin/scratch": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["scratch"],
        "source_path": "bin/scratch",
    },
    "bin/exocortex-id": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["exocortex-id", "exocortex"],
        "source_path": "bin/exocortex-id",
    },
    # Drives roleplay/bin/roleplay-roll as a subprocess. No pip deps -- it is a
    # bash script -- but it runs on every prompt via a UserPromptSubmit hook, so
    # a regression here is felt everywhere at once.
    #
    # The tests live in roleplay/tests/, inside the self-contained subsystem, and
    # reach this tree through the `tests/roleplay` symlink. run_component() does
    # `TESTS_DIR / component`, so without that link the component would resolve to
    # nothing and rot unrun -- the exact silent failure this dict exists to stop.
    "roleplay": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["roleplay-roll", "roleplay"],
        "source_path": "roleplay/bin/roleplay-roll",
    },
    # Python tests that drive fish via `fish -c` and assert on the output --
    # NOT fishtape. Needs the `fish` binary on PATH, no pip deps.
    #
    # No single-file aliases here or on lib/python and hooks: `trash`, `cjson`
    # and `ensure-rcs` were named after the one file each component once held,
    # so `cmds test trash` ran every fish test for ~2 minutes. Name the file
    # instead, relative to tests/: `cmds test fish/test_trash.py`.
    "fish": {
        "runner": "pytest",
        "deps": [],
        "source_path": "fish/functions",
    },
    "hooks": {
        "runner": "pytest",
        "deps": [],
        "source_path": "rcs",
    },
    # supervise / svc / svc-tmux, driven as real processes: pty + pyte for the
    # in-pane bar, `ps` for orphans, a private tmux socket per test. Needs tmux
    # for the svc-tmux tests (skipped without it).
    "svc": {
        "runner": "pytest",
        "deps": ["pyte"],
        "aliases": ["supervise", "svc-tmux"],
        "source_path": "bin/supervise",
    },
    # Claude Code mods (ai/mods/<name>): their tests live beside each mod, in
    # ai/mods/<name>/tests/, and only `claude plugin test` runs them.
    # tests/mods/test_mod_suites.py runs it once per mod with a tests/ folder,
    # and skips when `claude` is not on PATH.
    "mods": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["roleplay-bookends"],
        "source_path": "ai/mods",
    },
    # Future components (tests don't exist yet):
    # "lib/lua": {
    #     "runner": "busted",
    #     "deps": [],
    #     "aliases": ["lua", "hammerspoon"],
    # },
    #
    # No component uses the fishtape runner: tests/fish is pytest (above).
    # run_fishtape() is kept for a future tree that wants native fish tests.
}

# Build alias lookup
ALIASES = {}
for path, config in COMPONENTS.items():
    for alias in config.get("aliases", []):
        ALIASES[alias] = path


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
# pytest's last line, e.g. "==== 1 failed, 11 passed, 2 warnings in 1.83s ===="
TIMING_RE = re.compile(r"\bin\s+[\d.]+s")
COUNT_RE = re.compile(
    r"(\d+)\s+(passed|failed|errors?|skipped|xfailed|xpassed|deselected)\b"
)
# Counts worth showing in the aggregate line, in display order.
REPORTED = ("passed", "failed", "error", "skipped", "xfailed", "xpassed")


def parse_counts(lines: list[str]) -> dict[str, int]:
    """Pull {passed: N, failed: N, ...} out of pytest's final summary line."""
    counts: dict[str, int] = {}
    for raw in lines:
        line = ANSI_RE.sub("", raw).strip().strip("=").strip()
        if not TIMING_RE.search(line):
            continue
        found = COUNT_RE.findall(line)
        if not found:
            continue
        # Last matching line wins -- that is the real summary.
        counts = {}
        for num, word in found:
            counts[word.rstrip("s") if word.startswith("error") else word] = int(num)
    return counts


def format_counts(counts: dict[str, int]) -> str:
    parts = [f"{counts[k]} {k}" for k in REPORTED if counts.get(k)]
    return ", ".join(parts) if parts else "no tests ran"


def stream(cmd: list[str], env: dict[str, str] | None = None) -> tuple[int, list[str]]:
    """Run cmd, echoing output live, and return (exit_code, captured_lines).

    env None inherits this process's environment."""
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )
    lines = []
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(line)
    return proc.wait(), lines


# --- Isolation ---------------------------------------------------------------
#
# Every pytest the runner starts gets a throwaway HOME (test_home) and an
# environment built from the real one (isolated_env). So no test reads or
# writes the real ~/.config, ~/.local/state or ~/.claude, git and jj commit
# under a test identity, and a run inside tmux or a Claude session behaves like
# one outside it. This lives here, not in a conftest fixture, so it covers every
# component alike (roleplay too, through the tests/roleplay symlink) and also the
# paths a test module computes at import time.

TEST_USER = "Dotfiles Test"
TEST_EMAIL = "dotfiles-test@example.invalid"

# Dropped outright: a test must not see the terminal, tmux or Claude session it
# was started from.
DROPPED_VARS = (
    "TMUX",
    "TMUX_PANE",
    "ITERM_SESSION_ID",
    "TERM_SESSION_ID",
    "CLAUDECODE",
    "SVC_FS_CONFIG",
    "SVC_TMUX_SOCKET",
)
DROPPED_PREFIXES = ("CLAUDE_", "CCS_", "CC_JJ_")


def _is_dotfiles_bin(entry: str, real_home: str | None) -> bool:
    """A PATH entry that is some checkout's dotfiles/bin folder."""
    path = Path(os.path.expanduser(entry))
    if path.parts[-2:] == ("dotfiles", "bin"):
        return True
    if not real_home:
        return False
    live = Path(real_home) / "dotfiles" / "bin"
    if os.path.normpath(path) == os.path.normpath(live):
        return True
    with contextlib.suppress(OSError):
        return path.resolve() == live.resolve()
    return False


def isolated_env(base: dict, home: Path, uv_cache: str, uv_python: str) -> dict:
    """The environment for one test run: base, with HOME moved into `home`.

    Pure: reads nothing but its arguments. `home` is a test_home(); `uv_cache`
    and `uv_python` are the real uv folders, so uv does not download every
    dependency and Python again into the throwaway home.
    """
    env = {
        k: v
        for k, v in base.items()
        if k not in DROPPED_VARS and not k.startswith(DROPPED_PREFIXES)
    }
    home = Path(home)
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    env["XDG_DATA_HOME"] = str(home / ".local" / "share")
    env["XDG_STATE_HOME"] = str(home / ".local" / "state")
    env["XDG_CACHE_HOME"] = str(home / ".cache")

    env["GIT_CONFIG_GLOBAL"] = str(home / ".gitconfig")
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["JJ_CONFIG"] = str(home / ".config" / "jj" / "config.toml")
    env["JJ_USER"] = TEST_USER
    env["JJ_EMAIL"] = TEST_EMAIL

    env["UV_CACHE_DIR"] = uv_cache
    env["UV_PYTHON_INSTALL_DIR"] = uv_python

    # The tree's own bin goes first and every other dotfiles/bin goes: the live
    # ~/dotfiles/bin is on the operator's PATH, so a command run by bare name
    # would otherwise be the live copy, not the one under test.
    tree_bin = str(DOTFILES / "bin")
    real_home = base.get("HOME")
    rest = [
        p
        for p in base.get("PATH", "").split(os.pathsep)
        if p and os.path.normpath(p) != tree_bin and not _is_dotfiles_bin(p, real_home)
    ]
    env["PATH"] = os.pathsep.join([tree_bin, *rest])
    return env


@contextlib.contextmanager
def test_home() -> Iterator[Path]:
    """A throwaway HOME, removed on exit.

    Holds `dotfiles` linked to the tree under test (scripts hard-code
    $HOME/dotfiles, e.g. rcs/claude-ensure-rcs-hook.sh), the four XDG folders,
    and git and jj configs that carry only a test identity.
    """
    with tempfile.TemporaryDirectory(
        prefix="dotfiles-test-home-", ignore_cleanup_errors=True
    ) as tmp:
        # Resolved, so /var/folders and /private/var/folders never disagree.
        home = Path(tmp).resolve()
        (home / "dotfiles").symlink_to(DOTFILES, target_is_directory=True)
        for sub in (".config", ".local/share", ".local/state", ".cache"):
            (home / sub).mkdir(parents=True, exist_ok=True)
        (home / ".gitconfig").write_text(
            "[user]\n"
            f"\tname = {TEST_USER}\n"
            f"\temail = {TEST_EMAIL}\n"
            "[init]\n"
            "\tdefaultBranch = master\n"
        )
        vcs_cfg = home / ".config" / "jj"
        vcs_cfg.mkdir(parents=True, exist_ok=True)
        (vcs_cfg / "config.toml").write_text(
            f'[user]\nname = "{TEST_USER}"\nemail = "{TEST_EMAIL}"\n'
        )
        yield home


# test_home is a context manager, not a test: keep pytest from collecting it
# when a test module does `from run_tests import test_home`.
test_home.__test__ = False


def _uv_dir(var: str, subcommand: list[str]) -> str:
    if os.environ.get(var):
        return os.environ[var]
    return subprocess.run(
        ["uv", *subcommand], capture_output=True, text=True, check=True
    ).stdout.strip()


@functools.lru_cache(maxsize=1)
def uv_folders() -> tuple[str, str]:
    """(cache dir, python install dir) from the real environment, read once.

    Read before HOME moves: under the throwaway home uv would pick fresh, empty
    folders and download every dependency and Python again on every run.
    """
    return (
        _uv_dir("UV_CACHE_DIR", ["cache", "dir"]),
        _uv_dir("UV_PYTHON_INSTALL_DIR", ["python", "dir"]),
    )


def component_of(target: Path) -> str | None:
    """The COMPONENTS entry a test path (or node id) belongs to, if any."""
    try:
        rel = Path(str(target).split("::", 1)[0]).relative_to(TESTS_DIR).as_posix()
    except ValueError:
        return None
    owners = [c for c in COMPONENTS if rel == c or rel.startswith(c + "/")]
    return max(owners, key=len) if owners else None


def opt_out_reason(targets: list[Path]) -> str | None:
    """The isolation_reason when the targets' component sets isolation False."""
    for target in targets:
        config = COMPONENTS.get(component_of(target) or "", {})
        if config.get("isolation", True) is False:
            return config.get("isolation_reason") or "(no reason given)"
    return None


def run_pytest(
    target: Path | list[Path],
    deps: list[str],
    extra_args: list[str],
    source_path: str | None = None,
) -> tuple[int, dict[str, int]]:
    """Run pytest on one target, or on several in one run (same dependencies)."""
    targets = target if isinstance(target, list) else [target]
    cmd = ["uv", "run", "--with", "pytest"]
    for dep in deps:
        cmd.extend(["--with", dep])

    extra_args = list(extra_args)  # Copy to avoid mutation

    # Handle --cov flag: add pytest-cov and resolve source path
    if "--cov" in extra_args:
        cmd.extend(["--with", "pytest-cov"])
        extra_args.remove("--cov")
        if source_path:
            extra_args.append(f"--cov={DOTFILES / source_path}")
        else:
            extra_args.extend(f"--cov={t}" for t in targets)

    # Output is piped (so we can parse the summary), which makes pytest drop
    # colour. Put it back when we ourselves are on a terminal.
    if sys.stdout.isatty() and not any(a.startswith("--color") for a in extra_args):
        extra_args.append("--color=yes")

    cmd.extend(["pytest", *map(str, targets)] + extra_args)

    reason = opt_out_reason(targets)
    if reason is not None:
        print(f"isolation off: {reason}")
        code, lines = stream(cmd)
        return code, parse_counts(lines)

    uv_cache, uv_python = uv_folders()
    with test_home() as home:
        env = isolated_env(dict(os.environ), home, uv_cache, uv_python)
        code, lines = stream(cmd, env=env)
    return code, parse_counts(lines)


def run_busted(
    target: Path, deps: list[str], extra_args: list[str]
) -> tuple[int, dict[str, int]]:
    code, _ = stream(["busted", str(target)] + extra_args)
    return code, {}


def run_fishtape(
    target: Path, deps: list[str], extra_args: list[str]
) -> tuple[int, dict[str, int]]:
    code, _ = stream(["fishtape", str(target)] + extra_args)
    return code, {}


RUNNERS = {
    "pytest": run_pytest,
    "busted": run_busted,
    "fishtape": run_fishtape,
}


def run_component(component: str, extra_args: list[str]) -> tuple[int, dict[str, int]]:
    """Run tests for a single component, returning (exit_code, counts)."""
    config = COMPONENTS.get(component)
    if not config:
        print(f"Unknown component: {component}", file=sys.stderr)
        return 1, {}

    target = TESTS_DIR / component
    if not target.exists():
        print(f"Test directory not found: {target}", file=sys.stderr)
        return 1, {}

    runner_name = config["runner"]
    if runner_name == "pytest":
        return run_pytest(
            target, config.get("deps", []), extra_args, config.get("source_path")
        )

    runner = RUNNERS.get(runner_name)
    if not runner:
        print(f"Unknown runner: {runner_name}", file=sys.stderr)
        return 1, {}

    return runner(target, config.get("deps", []), extra_args)


# One summary row: (name, exit code, counts, wall seconds).
Result = tuple[str, int, dict[str, int], float]


def format_seconds(seconds: float) -> str:
    """Wall time as the summary prints it: `[12.3s]`."""
    return f"[{seconds:.1f}s]"


def print_summary(results: list[Result]) -> None:
    """Aggregate line: every component runs in its own pytest, so without this
    the output just ends with the *last* component's tally and reads as if
    nothing else ran. Each line, and the total, ends with its wall time."""
    width = max((len(name) for name, _, _, _ in results), default=0)
    totals: dict[str, int] = {}
    failed_components = []
    total_seconds = sum(seconds for _, _, _, seconds in results)

    print()
    print("=" * 72)
    print(f"cmds test summary — {DOTFILES}")
    print("=" * 72)
    for name, code, counts, seconds in results:
        ok = code == 0
        if not ok:
            failed_components.append(name)
        for key, val in counts.items():
            totals[key] = totals.get(key, 0) + val
        status = "PASS" if ok else "FAIL"
        detail = format_counts(counts) if counts else f"exit {code}"
        print(f"  {status}  {name:<{width}}  {detail}  {format_seconds(seconds)}")

    print("-" * 72)
    total_detail = f"{format_counts(totals)}  {format_seconds(total_seconds)}"
    if failed_components:
        print(
            f"  FAILED — {len(results)} components, "
            f"{len(failed_components)} failed ({', '.join(failed_components)})"
        )
        print(f"           {total_detail}")
    else:
        print(f"  PASSED — {len(results)} components, {total_detail}")
    print("=" * 72)


def run_all(extra_args: list[str], components: list[str] | None = None) -> int:
    """Run components (all of them by default), return worst exit code."""
    names = components if components is not None else list(COMPONENTS)
    exit_code = 0
    results: list[Result] = []

    for component in names:
        target = TESTS_DIR / component
        if not target.exists():
            continue
        start = time.monotonic()
        result, counts = run_component(component, extra_args)
        results.append((component, result, counts, time.monotonic() - start))
        if result != 0:
            exit_code = result

    if not results:
        print(f"No test components found under {TESTS_DIR}", file=sys.stderr)
        return 1

    print_summary(results)
    return exit_code


# A unit of work for one argument: (component, target). The component is None for
# a path under tests/ that no component owns. The target is None when the whole
# component runs, else the file or node id inside it.
Unit = tuple[str | None, Path | None]


def resolve_arg(arg: str) -> list[Unit] | None:
    """What one positional argument names, or None if it names nothing."""
    # Paths are relative to tests/, but `tests/fish/x.py` is what tab completion
    # from the repo root produces. A node id (`x.py::test_y`) is not a file, so
    # only the part before `::` can be checked for existence or matched.
    target = "" if arg.rstrip("/") == "tests" else arg.removeprefix("tests/")
    file_part = target.split("::", 1)[0].rstrip("/")

    if not target:
        return [(c, None) for c in COMPONENTS if (TESTS_DIR / c).exists()]
    if target in ALIASES:
        return [(ALIASES[target], None)]
    if file_part in COMPONENTS and "::" not in target:
        return [(file_part, None)]
    if not (TESTS_DIR / file_part).exists():
        return None
    # A path inside one component runs just that file or node, with that
    # component's dependencies. It used to run the whole component.
    owners = [c for c in COMPONENTS if file_part.startswith(c + "/")]
    if owners:
        return [(max(owners, key=len), TESTS_DIR / target)]
    # A parent directory runs every component under it (e.g. "bin" covers
    # bin/astro, bin/ytdl and bin/exocortex-id).
    matches = [c for c in COMPONENTS if c.startswith(file_part + "/")]
    if matches:
        return [(c, None) for c in matches]
    # Fallback: a plain pytest path that no component owns
    return [(None, TESTS_DIR / target)]


def run_unit_group(
    component: str | None, targets: list[Path] | None, extra_args: list[str]
) -> tuple[int, dict[str, int]]:
    """Run one component's share: the whole component, or some of its files."""
    if targets is None:
        return run_component(component, extra_args)
    if component is None:
        return run_pytest(targets, [], extra_args)
    config = COMPONENTS[component]
    return run_pytest(targets, config.get("deps", []), extra_args, config.get("source_path"))


def run_many(positionals: list[str], extra_args: list[str]) -> int:
    """Several paths: one pytest per component, each with its own dependencies.

    Before this, every path after the first went to pytest unresolved. pytest
    then failed on it ("file or directory not found", exit 4) and ran nothing.
    """
    resolved = [(arg, resolve_arg(arg)) for arg in positionals]
    unknown = [arg for arg, units in resolved if units is None]
    if unknown:
        for arg in unknown:
            print(f"Unknown component or path under {TESTS_DIR}: {arg}", file=sys.stderr)
        return 2

    # Group by component, in first-seen order. A whole component absorbs any
    # files named inside it, since running it covers them.
    groups: dict[str | None, list[Path] | None] = {}
    for _, units in resolved:
        for component, target in units:
            if target is None:
                groups[component] = None
            elif component not in groups:
                groups[component] = [target]
            elif groups[component] is not None and target not in groups[component]:
                groups[component].append(target)

    if len(groups) == 1:
        [(component, targets)] = groups.items()
        return run_unit_group(component, targets, extra_args)[0]

    exit_code = 0
    results: list[Result] = []
    for component, targets in groups.items():
        start = time.monotonic()
        code, counts = run_unit_group(component, targets, extra_args)
        name = component if component is not None else "(no component)"
        results.append((name, code, counts, time.monotonic() - start))
        if code != 0:
            exit_code = code
    print_summary(results)
    return exit_code


def main():
    args = sys.argv[1:]
    print(f"dotfiles root: {DOTFILES}")

    if not args:
        sys.exit(run_all([]))
    elif args[0].startswith("-"):
        # Flags only - run all with flags
        sys.exit(run_all(args))

    # The leading arguments are what to run; everything from the first flag on
    # goes to pytest untouched. Stopping there is what keeps a flag's value
    # (`-k expr`, `--deselect x.py::t`) from being read as a path.
    first_flag = next((i for i, a in enumerate(args) if a.startswith("-")), len(args))
    positionals, extra = args[:first_flag], args[first_flag:]

    if len(positionals) > 1:
        sys.exit(run_many(positionals, extra))

    arg = positionals[0]
    units = resolve_arg(arg)
    if units is None:
        # Not a pass-through: an unknown word used to reach run_all as a pytest
        # argument, so a typo ran the whole suite (and then failed on the path).
        print(f"Unknown component or path under {TESTS_DIR}: {arg}", file=sys.stderr)
        sys.exit(2)
    if arg.rstrip("/") == "tests":
        sys.exit(run_all(extra))
    if len(units) > 1:
        sys.exit(run_all(extra, components=[c for c, _ in units]))
    [(component, target)] = units
    if target is None:
        sys.exit(run_component(component, extra)[0])
    if component is None:
        sys.exit(run_pytest(target, [], extra)[0])
    config = COMPONENTS[component]
    sys.exit(run_pytest(target, config.get("deps", []), extra, config.get("source_path"))[0])


if __name__ == "__main__":
    main()
