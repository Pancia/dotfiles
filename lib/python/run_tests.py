#!/usr/bin/env python3
"""
Multi-language test runner for dotfiles.
Dispatches to pytest, busted, or fishtape based on component config.
"""

import re
import subprocess
import sys
from pathlib import Path

# Derived from this file's location, not $HOME, so a clone or worktree
# somewhere else tests *itself* rather than silently testing ~/dotfiles.
# lib/python/run_tests.py -> parents[2] is the repo root.
DOTFILES = Path(__file__).resolve().parents[2]
TESTS_DIR = DOTFILES / "tests"

# Component configuration: runner + dependencies + aliases
# source_path: path to source code for coverage (relative to DOTFILES)
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
    "lib/python": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["cjson", "python"],
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
    "bin/exocortex-id": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["exocortex-id", "exocortex"],
        "source_path": "bin/exocortex-id",
    },
    # Python tests that drive fish via `fish -c` and assert on the output --
    # NOT fishtape. Needs the `fish` binary on PATH, no pip deps.
    "fish": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["trash"],
        "source_path": "fish/functions",
    },
    "hooks": {
        "runner": "pytest",
        "deps": [],
        "aliases": ["ensure-rcs"],
        "source_path": "rcs",
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


def stream(cmd: list[str]) -> tuple[int, list[str]]:
    """Run cmd, echoing output live, and return (exit_code, captured_lines)."""
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )
    lines = []
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(line)
    return proc.wait(), lines


def run_pytest(
    target: Path, deps: list[str], extra_args: list[str], source_path: str | None = None
) -> tuple[int, dict[str, int]]:
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
            extra_args.append(f"--cov={target}")

    # Output is piped (so we can parse the summary), which makes pytest drop
    # colour. Put it back when we ourselves are on a terminal.
    if sys.stdout.isatty() and not any(a.startswith("--color") for a in extra_args):
        extra_args.append("--color=yes")

    cmd.extend(["pytest", str(target)] + extra_args)
    code, lines = stream(cmd)
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


def print_summary(results: list[tuple[str, int, dict[str, int]]]) -> None:
    """Aggregate line: every component runs in its own pytest, so without this
    the output just ends with the *last* component's tally and reads as if
    nothing else ran."""
    width = max((len(name) for name, _, _ in results), default=0)
    totals: dict[str, int] = {}
    failed_components = []

    print()
    print("=" * 72)
    print(f"cmds test summary — {DOTFILES}")
    print("=" * 72)
    for name, code, counts in results:
        ok = code == 0
        if not ok:
            failed_components.append(name)
        for key, val in counts.items():
            totals[key] = totals.get(key, 0) + val
        status = "PASS" if ok else "FAIL"
        detail = format_counts(counts) if counts else f"exit {code}"
        print(f"  {status}  {name:<{width}}  {detail}")

    print("-" * 72)
    total_detail = format_counts(totals)
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
    results: list[tuple[str, int, dict[str, int]]] = []

    for component in names:
        target = TESTS_DIR / component
        if not target.exists():
            continue
        result, counts = run_component(component, extra_args)
        results.append((component, result, counts))
        if result != 0:
            exit_code = result

    if not results:
        print(f"No test components found under {TESTS_DIR}", file=sys.stderr)
        return 1

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
    elif args[0] in ALIASES:
        # Alias lookup
        component = ALIASES[args[0]]
        sys.exit(run_component(component, args[1:])[0])
    elif args[0] in COMPONENTS:
        # Direct component path
        sys.exit(run_component(args[0], args[1:])[0])
    elif (TESTS_DIR / args[0]).exists():
        # Subpath - find every matching component (e.g. "bin" covers
        # bin/astro, bin/ytdl and bin/exocortex-id).
        subpath = args[0]
        matches = [
            c
            for c in COMPONENTS
            if subpath.startswith(c) or c.startswith(subpath.rstrip("/") + "/") or c == subpath
        ]
        if len(matches) == 1:
            sys.exit(run_component(matches[0], args[1:])[0])
        elif matches:
            sys.exit(run_all(args[1:], components=matches))
        # Fallback: treat as pytest path
        sys.exit(run_pytest(TESTS_DIR / subpath, [], args[1:])[0])
    else:
        # Unknown - pass through to run_all as pytest args
        sys.exit(run_all(args))


if __name__ == "__main__":
    main()
