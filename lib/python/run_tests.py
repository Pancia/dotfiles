#!/usr/bin/env python3
"""
Multi-language test runner for dotfiles.
Dispatches to pytest, busted, or fishtape based on component config.
"""

import subprocess
import sys
from pathlib import Path

DOTFILES = Path.home() / "dotfiles"
TESTS_DIR = DOTFILES / "tests"

# Component configuration: runner + dependencies + aliases
# source_path: path to source code for coverage (relative to DOTFILES)
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
    # Future components (tests don't exist yet):
    # "lib/lua": {
    #     "runner": "busted",
    #     "deps": [],
    #     "aliases": ["lua", "hammerspoon"],
    # },
    # "fish": {
    #     "runner": "fishtape",
    #     "deps": [],
    #     "aliases": ["fish"],
    # },
}

# Build alias lookup
ALIASES = {}
for path, config in COMPONENTS.items():
    for alias in config.get("aliases", []):
        ALIASES[alias] = path


def run_pytest(target: Path, deps: list[str], extra_args: list[str], source_path: str | None = None) -> int:
    cmd = ["uv", "run", "--with", "pytest"]
    for dep in deps:
        cmd.extend(["--with", dep])

    # Handle --cov flag: add pytest-cov and resolve source path
    if "--cov" in extra_args:
        cmd.extend(["--with", "pytest-cov"])
        extra_args = list(extra_args)  # Copy to avoid mutation
        extra_args.remove("--cov")
        if source_path:
            extra_args.append(f"--cov={DOTFILES / source_path}")
        else:
            extra_args.append(f"--cov={target}")

    cmd.extend(["pytest", str(target)] + extra_args)
    return subprocess.call(cmd)


def run_busted(target: Path, deps: list[str], extra_args: list[str]) -> int:
    cmd = ["busted", str(target)] + extra_args
    return subprocess.call(cmd)


def run_fishtape(target: Path, deps: list[str], extra_args: list[str]) -> int:
    cmd = ["fishtape", str(target)] + extra_args
    return subprocess.call(cmd)


RUNNERS = {
    "pytest": run_pytest,
    "busted": run_busted,
    "fishtape": run_fishtape,
}


def run_component(component: str, extra_args: list[str]) -> int:
    """Run tests for a single component."""
    config = COMPONENTS.get(component)
    if not config:
        print(f"Unknown component: {component}", file=sys.stderr)
        return 1

    target = TESTS_DIR / component
    if not target.exists():
        print(f"Test directory not found: {target}", file=sys.stderr)
        return 1

    runner_name = config["runner"]
    if runner_name == "pytest":
        return run_pytest(target, config.get("deps", []), extra_args, config.get("source_path"))

    runner = RUNNERS.get(runner_name)
    if not runner:
        print(f"Unknown runner: {runner_name}", file=sys.stderr)
        return 1

    return runner(target, config.get("deps", []), extra_args)


def run_all(extra_args: list[str]) -> int:
    """Run all components, return worst exit code."""
    exit_code = 0
    for component in COMPONENTS:
        target = TESTS_DIR / component
        if target.exists():
            result = run_component(component, extra_args)
            if result != 0:
                exit_code = result
    return exit_code


def main():
    args = sys.argv[1:]

    if not args:
        sys.exit(run_all([]))
    elif args[0].startswith("-"):
        # Flags only - run all with flags
        sys.exit(run_all(args))
    elif args[0] in ALIASES:
        # Alias lookup
        component = ALIASES[args[0]]
        sys.exit(run_component(component, args[1:]))
    elif args[0] in COMPONENTS:
        # Direct component path
        sys.exit(run_component(args[0], args[1:]))
    elif (TESTS_DIR / args[0]).exists():
        # Subpath - find matching component
        subpath = args[0]
        for component in COMPONENTS:
            if subpath.startswith(component) or component.startswith(subpath):
                sys.exit(run_component(component, args[1:]))
        # Fallback: treat as pytest path
        sys.exit(run_pytest(TESTS_DIR / subpath, [], args[1:]))
    else:
        # Unknown - pass through to run_all as pytest args
        sys.exit(run_all(args))


if __name__ == "__main__":
    main()
