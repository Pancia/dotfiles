#!/usr/bin/env python3
"""Opt-in marker for Claude Code's native per-session worktrees.

Two Claude sessions in one checkout tread on each other. `ccjj` solves that for
~/dotfiles, which cannot be isolated (about half its tracked files load by
absolute path). Every *other* repo can be -- and Claude Code has created
worktrees natively since v2.1.49, so all this has to do is record that a
checkout wants them. `my-claude-code-wrapper` then appends `--worktree`.

    cc-worktree on|off|status     opt this checkout in or out
    cc-worktree should-isolate    exit 0 when opted in (the wrapper's gate)

Exit codes:  0 ok · 1 refused or failed · 2 not opted in (no marker)

WHAT WENT, AND WHY. This file was 1413 lines. Slots, holds, a reaper,
land/release/finish, `.owner`/`.hold` files, a flock, a link list and
slot-aware resume all existed for one reason: the wrapper created the worktree
itself and cd'd into it *before* launching claude, which hid it from Claude
Code -- so Claude Code could not name, resume, list or clean up its own
sessions, and every one of those jobs had to be reimplemented here. Handing the
job back deleted all of it, along with the bugs it carried (`link_one` once
deleted files in the parent repo). What remains is the opt-in decision, which is
genuinely ours to make.

THE ONE THING TO KNOW. `claude --worktree` in a colocated jj repo creates a
*git* worktree with no `.jj` of its own, so `jj` inside it resolves to the
PARENT. Use git inside a worktree; the parent picks the commits up as a jj
bookmark automatically. `bin/cc-worktree-nudge` warns the agent on every prompt.

See docs/cc-worktree.md.
"""
import argparse
import os
import subprocess
import sys
from typing import NoReturn

DEADLINE = 30            # seconds; a wedged git/jj must never hang a launch

# Paths `on` proposes for .worktreeinclude -- Claude Code's own mechanism for
# carrying untracked local state into a new worktree.
#
# It COPIES rather than symlinks (measured, not assumed), which decides the
# shape of this list: small config only. A copied node_modules or .venv would be
# slow and waste disk per session, and a copied settings.local.json means
# permission grants stop accruing to the parent. Anything bulky is left for the
# human to add knowingly rather than proposed by default.
INCLUDE_CANDIDATES = [
    # Claude Code's own per-project state; without these a session starts with
    # no skills, no agents and no granted permissions, and re-prompts for each.
    ".cc-config", ".claude/settings.json", ".claude/settings.local.json",
    ".mcp.json",
    # environment and toolchain: wrong or missing means a silently wrong runtime
    ".env", ".env.local", ".envrc",
    ".tool-versions", ".nvmrc", ".python-version", ".ruby-version",
]

INCLUDE_FILE = ".worktreeinclude"

MARKER_HEADER = """\
# cc-worktree: this checkout is opted in to per-session worktree isolation.
#
# The presence of this file is the whole setting. `my-claude-code-wrapper` sees
# it via `cc-worktree should-isolate` and appends `--worktree` to claude, so
# each session gets its own checkout under .claude/worktrees/.
#
# `cc <args> --no-worktree` opts out for a single run.
#
# To choose what untracked local state each worktree gets, edit .worktreeinclude
# in the repo root -- that is Claude Code's mechanism, not ours. Note it COPIES,
# so keep it to small config files.
"""


def die(msg, code=1) -> NoReturn:
    # sys.exit(str) always exits 1, which would collapse "not opted in" (2) into
    # "refused" (1) -- and callers branch on exactly that difference.
    print("cc-worktree: " + msg, file=sys.stderr)
    sys.exit(code)


def warn(msg):
    print("cc-worktree: " + msg, file=sys.stderr)


def run(cmd, cwd=None, timeout=DEADLINE):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        die("%s exceeded %ds" % (" ".join(cmd), timeout))
    except OSError as exc:
        die("%s: %s" % (cmd[0], exc))


# ------------------------------------------------------------ repo and backend

def dotfiles_root():
    """The checkout that cannot be isolated.

    Derived from this file's own location, not $HOME, so a clone somewhere else
    refuses *itself* rather than the original. The env override exists because a
    test cannot create a repo at the real path.
    """
    override = os.environ.get("CC_WORKTREE_DOTFILES")
    if override:
        return os.path.realpath(override)
    return os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", ".."))


def find_repo(start):
    """(root, backend) for the repo containing `start`, else (None, None).

    jj wins when both markers are present: every jj repo here is colocated, so a
    .git alongside .jj is the norm, and picking git would put the marker in the
    wrong place. os.path.exists rather than isdir because .git is a FILE in a
    linked worktree and in a submodule.
    """
    d = os.path.realpath(start)
    while True:
        if os.path.exists(os.path.join(d, ".jj")):
            return d, "jj"
        if os.path.exists(os.path.join(d, ".git")):
            return d, "git"
        parent = os.path.dirname(d)
        if parent == d:
            return None, None
        d = parent


def git_dir(root):
    """--git-dir, WITHOUT forking git.

    `should-isolate` runs on EVERY claude launch in EVERY repo, so it must make
    no git/jj call at all -- otherwise every launch pays for a feature it does
    not use. So the `.git` file ("gitdir: <path>") is resolved by hand, exactly
    as git does it.
    """
    dot = os.path.join(root, ".git")
    if os.path.isdir(dot):
        return dot
    try:
        with open(dot) as fh:
            line = fh.read().strip()
    except OSError:
        return dot
    if not line.startswith("gitdir:"):
        return dot
    gd = line.split(":", 1)[1].strip()
    return gd if os.path.isabs(gd) else os.path.normpath(os.path.join(root, gd))


def git_common_dir(root):
    """--git-common-dir, without forking git.

    A linked worktree's git dir carries a `commondir` file pointing at the
    parent's; a submodule's does not, and its git dir IS its common dir.
    """
    gd = git_dir(root)
    try:
        with open(os.path.join(gd, "commondir")) as fh:
            cd = fh.read().strip()
    except OSError:
        return gd
    return cd if os.path.isabs(cd) else os.path.normpath(os.path.join(gd, cd))


def marker_path(root, backend):
    """Where the opt-in marker lives.

    git: --git-common-dir, NEVER `<root>/.git`. In a linked worktree and in a
    submodule .git is a *file*, so joining a filename onto it produces a path
    that can never be opened -- the marker would silently not be found and
    isolation would quietly not happen.

    Both locations are outside the working tree on purpose: opting in is a
    property of this checkout, not of the project, so it must not show up as an
    untracked file or travel to anyone else in a commit.
    """
    if backend == "jj":
        return os.path.join(root, ".jj", "cc-worktree")
    return os.path.join(git_common_dir(root), "cc-worktree")


def nested_reason(root, backend, path=None):
    """Why this checkout may not be opted in, or "" if it may.

    Without this, a worktree inside a worktree is reachable: from inside a
    linked worktree --git-common-dir finds the PARENT's marker, so the gate
    reads it and happily nests.
    """
    if "/.claude/worktrees/" in os.path.realpath(path or root) + "/":
        return "already inside a Claude Code worktree"
    if backend == "jj":
        # .jj/repo is a DIRECTORY in the parent and a FILE in a workspace.
        if os.path.isfile(os.path.join(root, ".jj", "repo")):
            return "this is a jj workspace, not the parent repo"
        return ""
    if os.path.realpath(git_dir(root)) != os.path.realpath(git_common_dir(root)):
        return "this is a linked git worktree, not the parent repo"
    return ""


def opted_in(root, backend):
    return os.path.exists(marker_path(root, backend))


# ---------------------------------------------------------------- the registry

def state_dir():
    override = os.environ.get("CC_WORKTREE_STATE")
    if override:
        return override
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "cc-worktree")


def registry_path():
    return os.path.join(state_dir(), "repos")


def registry_read():
    try:
        with open(registry_path()) as fh:
            return [ln.strip() for ln in fh if ln.strip()]
    except OSError:
        return []


def registry_write(roots):
    p = registry_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write("".join(r + "\n" for r in roots))
    os.replace(tmp, p)          # atomic: a torn registry loses the repo list


def registry_add(root):
    roots = registry_read()
    if root not in roots:
        registry_write(roots + [root])


def registry_remove(root):
    roots = registry_read()
    if root in roots:
        registry_write([r for r in roots if r != root])


# -------------------------------------------------------------------- commands

def resolve(start=None):
    """(root, backend), or exit."""
    root, backend = find_repo(start or os.getcwd())
    if not root:
        die("not inside a git or jj repository", 1)
    return root, backend


def tracked_paths(root, backend):
    """Repo-relative paths the VCS tracks. Empty set on failure (the probe then
    proposes nothing rather than proposing something wrong)."""
    if backend == "git":
        r = run(["git", "ls-files", "-z"], cwd=root)
    else:
        r = run(["jj", "file", "list", "-r", "@"], cwd=root)
    if r is None or r.returncode != 0:
        return set()
    out = r.stdout                     # run() is text mode, not bytes
    parts = out.split("\0") if backend == "git" else out.splitlines()
    return {p.strip().strip('"') for p in parts if p.strip()}


def probe_entries(root, backend):
    """(proposed, skipped_because_tracked) — what this repo actually needs.

    Existence AND untrackedness are both required. A tracked path arrives in the
    worktree by itself, so including it would copy a file git already put there.
    """
    tracked = tracked_paths(root, backend)
    proposed, skipped = [], []
    for rel in INCLUDE_CANDIDATES:
        if not os.path.lexists(os.path.join(root, rel)):
            continue
        if rel in tracked or any(t.startswith(rel + "/") for t in tracked):
            skipped.append(rel)
        else:
            proposed.append(rel)
    return proposed, skipped


def working_copy_dirty(root, backend):
    if backend == "jj":
        return "Working copy changes:" in run(["jj", "-R", root, "st"],
                                              cwd=root).stdout
    return bool(run(["git", "status", "--porcelain"], cwd=root).stdout.strip())


def worktrees(root):
    """Existing Claude Code worktrees, by name."""
    d = os.path.join(root, ".claude", "worktrees")
    try:
        return sorted(n for n in os.listdir(d)
                      if os.path.isdir(os.path.join(d, n)))
    except OSError:
        return []


def cmd_on(args):
    root, backend = resolve()

    if root == dotfiles_root():
        die("%s cannot be isolated: about half its tracked files load by\n"
            "  absolute path, so a worktree copy is not the live configuration.\n"
            "  `ccjj` / `commit-mine` is the answer for this repo." % root)
    reason = nested_reason(root, backend)
    if reason:
        die("%s: %s.\n"
            "  Opt in from the parent checkout instead; nesting is refused."
            % (root, reason))

    path = marker_path(root, backend)
    fresh = not os.path.exists(path)
    if fresh:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(MARKER_HEADER)

    # Offer a starter .worktreeinclude, but never overwrite one: it lives in the
    # working tree and may well be the human's, or the project's.
    inc = os.path.join(root, INCLUDE_FILE)
    if not os.path.exists(inc):
        proposed, skipped = probe_entries(root, backend)
        if proposed:
            with open(inc, "w") as fh:
                fh.write("# Untracked local state copied into each Claude Code\n"
                         "# worktree. Written by `cc-worktree on`; edit freely.\n"
                         "# NOTE: these are COPIED, so keep the list small --\n"
                         "# node_modules or .venv here would be slow and large.\n")
                fh.write("".join(p + "\n" for p in proposed))
            print("cc-worktree: wrote %s with %d detected path(s):"
                  % (INCLUDE_FILE, len(proposed)))
            for p in proposed:
                print("    %s" % p)
        else:
            print("cc-worktree: nothing untracked to carry into a worktree; no "
                  "%s written." % INCLUDE_FILE)
        if skipped:
            print("  (tracked, so already in every worktree: %s)"
                  % ", ".join(skipped))
    else:
        print("cc-worktree: %s already exists; leaving it alone." % INCLUDE_FILE)

    if os.path.exists(os.path.join(root, ".gitmodules")):
        warn("this repo has submodules; a fresh worktree leaves them EMPTY.\n"
             "  Run `git submodule update --init --recursive` inside one.")
    if working_copy_dirty(root, backend):
        warn("the working copy is dirty. A worktree is based on HEAD, so\n"
             "  in-progress edits will NOT be in it.")

    registry_add(root)
    print("cc-worktree: %s is opted in (%s)." % (root, backend))
    print("  marker: %s" % path)
    print("  `cc` now passes --worktree here; `cc --no-worktree` opts out once.")
    if backend == "jj":
        print("  NOTE: worktrees are git, not jj. Use `git` inside one -- jj\n"
              "  there resolves to THIS repo. Commits come back as a bookmark.")
    return 0


def cmd_off(args):
    root, backend = resolve()
    path = marker_path(root, backend)
    if not os.path.exists(path):
        print("cc-worktree: %s is not opted in." % root)
        registry_remove(root)
        return 0
    os.unlink(path)
    registry_remove(root)
    print("cc-worktree: %s is opted out." % root)
    left = worktrees(root)
    if left:
        # Named, never silent: the trees are still on disk. Claude Code owns
        # them now, so point at its command rather than reimplementing removal.
        print("  %d worktree(s) remain on disk; remove with `git worktree "
              "remove`: %s" % (len(left), ", ".join(left)))
    return 0


def cmd_status(args):
    root, backend = resolve()
    if not opted_in(root, backend):
        print("cc-worktree: %s is not opted in (%s)." % (root, backend))
        # Do NOT suggest `on` where `on` refuses -- pointing at a command that
        # cannot work reads as a bug in the tool rather than a property of the
        # repo, and this is the one repo the author is standing in most often.
        if root == dotfiles_root():
            print("  ...and cannot be: about half its tracked files load by absolute\n"
                  "  path, so a worktree copy is not the live configuration.\n"
                  "  Use `ccjj` / `commit-mine` here — docs/cc-jj-sessions.md.")
        else:
            print("  `cc-worktree on` to enable per-session isolation here.")
        return 2
    print("cc-worktree: %s (%s) is opted in." % (root, backend))
    print("  marker:  %s" % marker_path(root, backend))
    inc = os.path.join(root, INCLUDE_FILE)
    print("  include: %s" % (inc if os.path.exists(inc) else "(none)"))
    wts = worktrees(root)
    if not wts:
        print("  no worktrees on disk")
    else:
        # Claude Code creates, resumes and removes these; this is a plain
        # listing, not a state machine.
        print("  worktrees (managed by Claude Code):")
        for name in wts:
            print("    %s" % name)
    return 0


def cmd_should_isolate(args):
    """The wrapper's gate. Silent, and makes no git/jj call.

    Silence matters: this runs before every launch in every repo, and anything
    on stdout would be captured by a shell that is only asking a yes/no.
    """
    root, backend = find_repo(os.getcwd())
    if not root:
        return 2
    if not opted_in(root, backend):
        return 2
    # A worktree of an opted-in repo would otherwise nest one inside another.
    if nested_reason(root, backend):
        return 2
    return 0


def main():
    ap = argparse.ArgumentParser(prog="cc-worktree",
                                 description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("on", help="opt this checkout in to worktree isolation")
    sub.add_parser("off", help="opt this checkout out")
    sub.add_parser("status", help="marker, include file and worktrees")
    sub.add_parser("should-isolate",
                   help="exit 0 when this checkout is opted in (silent)")
    args = ap.parse_args()
    sys.exit({"on": cmd_on, "off": cmd_off, "status": cmd_status,
              "should-isolate": cmd_should_isolate}[args.cmd](args))


if __name__ == "__main__":
    main()
