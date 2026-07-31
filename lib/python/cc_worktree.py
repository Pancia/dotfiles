#!/usr/bin/env python3
"""Per-session worktree isolation for Claude Code.

Two Claude sessions in one checkout tread on each other. `ccjj` solves that for
~/dotfiles, which cannot be isolated (about half its tracked files load by
absolute path). Every *other* repo can be, and there the ordinary answer works:
the wrapper creates a git worktree / jj workspace and cd's into it before
launching claude, opt-in per checkout.

    cc-worktree on|off|status      opt this checkout in or out
    cc-worktree create --pid N     claim a slot, print the target directory
    cc-worktree reap [--all]       release finished slots (trash, never delete)
    cc-worktree finish --slot w-NN the exit path: hold, or merge and release
    cc-worktree land w-NN          land the work in the parent, then release
    cc-worktree release w-NN --land|--discard
    cc-worktree current --path P   slot name for a path
    cc-worktree slot-for-session S slot a recorded session ran in

Exit codes:  0 ok · 1 refused or failed · 2 not opted in (no marker)

`create` prints the target directory on STDOUT and everything else on STDERR,
because the fish wrapper captures its stdout and cd's into it.

Most guards below hold back a defect that was reproduced first; the comments say
which, because nearly all of them fail *silently* if removed.
See docs/cc-worktree.md.
"""
import argparse
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from typing import NoReturn

DEADLINE = 30            # seconds; a wedged git/jj must never hang a launch
SLOW_DEADLINE = 300      # `git worktree add` on a large repo is legitimately slow
LOCK_WAIT = 30           # seconds to wait for another cc-worktree run
MAX_SLOTS = 10
WT_REL = os.path.join(".claude", "worktrees")
DEFAULT_ENTRIES = [".cc-config", ".claude/settings.json",
                   ".claude/settings.local.json", ".envrc"]

# Candidates `on` probes for. Only ones that EXIST and are NOT tracked are
# proposed: a tracked file already comes across in the checkout, and linking it
# would silently make every worktree edit bypass the VCS.
#
# A static default list was wrong in the direction that matters -- it shipped
# .envrc (which no project here has) and omitted node_modules and .env, so a
# real Node or Python session started with no dependencies and no secrets. What
# a repo needs is a property of the repo, so ask the repo.
PROBE_ENTRIES = [
    # Claude Code's own per-project state; without these a session starts with
    # no skills, no agents and no granted permissions, and re-prompts for each.
    ".cc-config", ".claude/settings.json", ".claude/settings.local.json",
    ".claude/skills", ".claude/agents", ".claude/commands", ".mcp.json",
    # environment and toolchain: wrong or missing means silently wrong runtime
    ".env", ".env.local", ".envrc", ".direnv",
    ".tool-versions", ".nvmrc", ".python-version", ".ruby-version",
    # installed dependencies and build state: expensive to rebuild per session
    "node_modules", ".venv", "venv", "vendor/bundle", ".bundle",
    "target", ".next", ".nuxt", ".gradle", ".terraform", "_build", "deps",
]

# A slot directory name. Anchored, `w-` + digits only: `_cc_worktree_key` in
# fish uses the same shape, and the two must agree or a path rewritten by one is
# not recognised by the other.
SLOT_RE = re.compile(r"^w-\d+$")
NESTED_RE = re.compile(r"/\.claude/worktrees/w-\d+(/|$)")

_LOCK = None             # module-level: closing the file would drop the flock

MARKER_HEADER = """\
# cc-worktree: this checkout is opted in to per-session worktree isolation.
#
# One path per line, relative to the repo root. Each is SYMLINKED into every
# worktree, so edits through it land in the parent -- which is what you want for
# .envrc, node_modules, .venv, and for permission grants accruing to
# settings.local.json. It also means removing a worktree destroys none of them.
#
#   copy:<path>    copy instead of link, for a path that must diverge
#   max-slots: N   size of the slot pool (default 10)
#
# With no entries below, these defaults apply:
#   .cc-config
#   .claude/settings.json
#   .claude/settings.local.json
#   .envrc
"""


def die(msg, code=1) -> NoReturn:
    # sys.exit(str) always exits 1, which would collapse "not opted in" (2) into
    # "refused" (1) -- and the wrapper branches on exactly that difference.
    print("cc-worktree: " + msg, file=sys.stderr)
    sys.exit(code)


def warn(msg):
    # ALWAYS stderr. `create` prints warnings on its SUCCESS path, and the
    # wrapper captures its stdout as a directory to cd into: a warning on stdout
    # makes that capture a multi-element list, `cd` fails "Too many args", and
    # $status is STILL 0 -- so the wrapper would run un-isolated with a slot
    # claimed.
    print("cc-worktree: " + msg, file=sys.stderr)


def run(cmd, cwd=None, timeout=DEADLINE):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        die("%s exceeded %ds" % (" ".join(cmd), timeout))
    except OSError as exc:
        die("%s: %s" % (cmd[0], exc))


def stamp(fmt="%Y%m%d-%H%M%S"):
    return datetime.datetime.now().strftime(fmt)


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
    .git alongside .jj is the norm, and picking git would drive the wrong
    worktree mechanism entirely. os.path.exists rather than isdir because .git
    is a FILE in a linked worktree and in a submodule.
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

    `create` must make no git/jj call at all in a repo that is not opted in --
    otherwise every launch in every other repo pays for a feature it does not
    use, and gains a regression surface it cannot see. So the `.git` file
    ("gitdir: <path>") is resolved by hand, exactly as git does it.
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
    """
    if backend == "jj":
        return os.path.join(root, ".jj", "cc-worktree")
    return os.path.join(git_common_dir(root), "cc-worktree")


def nested_reason(root, backend, path=None):
    """Why this checkout may not be opted in / isolated, or "" if it may.

    Without this, `w-01/.claude/worktrees/w-02` is reachable: from inside a
    linked worktree --git-common-dir finds the PARENT's marker, so `create`
    reads it and happily nests. The design invites the mistake, because
    resolving a hold sends you into the worktree in the first place.
    """
    if NESTED_RE.search(os.path.realpath(path or root)):
        return "already inside a cc-worktree slot"
    if backend == "jj":
        # .jj/repo is a DIRECTORY in the parent and a FILE in a workspace.
        if os.path.isfile(os.path.join(root, ".jj", "repo")):
            return "this is a jj workspace, not the parent repo"
        return ""
    if os.path.realpath(git_dir(root)) != os.path.realpath(git_common_dir(root)):
        return "this is a linked git worktree, not the parent repo"
    return ""


# ------------------------------------------------------------ marker parsing

def parse_marker(text):
    """(entries, max_slots). entries is [(mode, path)] with mode link|copy."""
    entries = []
    max_slots = MAX_SLOTS
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("copy:"):
            p = line[len("copy:"):].strip()
            if p:
                entries.append(("copy", p))
        elif line.startswith("max-slots:"):
            v = line.split(":", 1)[1].strip()
            if v.isdigit() and int(v) > 0:
                max_slots = int(v)
        else:
            entries.append(("link", line))
    if not entries:
        entries = [("link", p) for p in DEFAULT_ENTRIES]
    return entries, max_slots


def read_marker(root, backend):
    """(entries, max_slots) or (None, None) when this checkout is not opted in."""
    try:
        with open(marker_path(root, backend)) as fh:
            return parse_marker(fh.read())
    except OSError:
        return None, None


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
    os.replace(tmp, p)          # atomic: a torn registry loses `reap --all`


def registry_add(root):
    roots = registry_read()
    if root not in roots:
        registry_write(roots + [root])


def registry_remove(root):
    roots = registry_read()
    if root in roots:
        registry_write([r for r in roots if r != root])


# ------------------------------------------------------------- slots on disk

def wt_dir(root):
    return os.path.join(root, WT_REL)


def slot_dir(root, slot):
    return os.path.join(wt_dir(root), slot)


def owner_path(root, slot):
    return os.path.join(wt_dir(root), slot + ".owner")


def hold_path(root, slot):
    return os.path.join(wt_dir(root), slot + ".hold")


def known_slots(root):
    """Every slot with a directory OR an .owner OR a .hold on disk.

    The union, not any one of them: a crash between `git worktree add` and the
    claim leaves a directory with no owner, and a reaper that enumerates only
    owners never sees it -- a tree nothing will ever clean up.
    """
    names = set()
    try:
        listing = os.listdir(wt_dir(root))
    except OSError:
        return []
    for name in listing:
        base = name
        for suffix in (".owner", ".hold"):
            if base.endswith(suffix):
                base = base[:-len(suffix)]
                break
        if SLOT_RE.match(base):
            names.add(base)
    return sorted(names)


def read_owner(root, slot):
    try:
        with open(owner_path(root, slot)) as fh:
            rec = json.load(fh)
        return rec if isinstance(rec, dict) else None
    except (OSError, ValueError):
        return None


def _staged_record(root, slot, record):
    """A fully-written temp file holding `record`, ready to link or rename in.

    mkstemp, not a pid-derived name: two claimers inside ONE process share a pid
    and would then share the staging path, so the winner of the link race can
    publish the LOSER's record -- an .owner naming a pid that never owned the
    slot. Caught by the race test, which is the only thing that would ever see
    it.
    """
    os.makedirs(wt_dir(root), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=wt_dir(root), prefix=".%s.owner." % slot)
    with os.fdopen(fd, "w") as fh:
        json.dump(record, fh)
    return tmp


def write_owner(root, slot, record):
    """Replace an .owner atomically.

    os.replace, never open-and-write: a reaper landing in the window where the
    file exists but is empty must either reap a live slot or invent an age
    heuristic. A rename has no such window.
    """
    os.replace(_staged_record(root, slot, record), owner_path(root, slot))


def claim(root, slot, record):
    """Claim a free slot, or False if someone else got it first.

    os.link is atomic and fails EEXIST, so two shells racing cannot land in the
    same worktree -- the exact thing this whole design exists to prevent. The
    record is written to the temp file FIRST, so the visible .owner is never
    empty.
    """
    tmp = _staged_record(root, slot, record)
    try:
        os.link(tmp, owner_path(root, slot))
        return True
    except FileExistsError:
        return False
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def drop_owner(root, slot):
    try:
        os.unlink(owner_path(root, slot))
    except OSError:
        pass


def write_hold(root, slot, reason):
    os.makedirs(wt_dir(root), exist_ok=True)
    with open(hold_path(root, slot), "w") as fh:
        fh.write(reason.rstrip() + "\n")


def drop_hold(root, slot):
    try:
        os.unlink(hold_path(root, slot))
    except OSError:
        pass


def hold_reason(root, slot):
    try:
        with open(hold_path(root, slot)) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def ps_lstart(pid):
    try:
        return subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def owner_alive(rec):
    """True iff the shell that claimed this slot is still running.

    pid alone is not enough -- pids are recycled, and a recycled pid makes a dead
    slot look live *forever*, which silently costs one slot out of ten. Same
    pid + `ps -o lstart=` identity check as ccs.fish and ccjj's .owner.
    """
    if not rec:
        return False
    pid = str(rec.get("pid") or "")
    if not pid.isdigit():
        return False
    try:
        os.kill(int(pid), 0)
    except OSError:
        return False
    # Indeterminate counts as ALIVE. ps_lstart returns "" on any OSError or a 5s
    # timeout, and a recorded "" compared equal to a real timestamp is False --
    # so a transient ps failure said "dead" about a running session and the next
    # launch's piggybacked reap trashed its worktree and freed the slot.
    # Reproduced. ccjj's owner_alive states the rule this one inverted: a slot we
    # cannot attribute must not be swept away. The pid is still alive here
    # (os.kill succeeded); only the recycled-pid refinement is unavailable.
    now, was = ps_lstart(pid), (rec.get("pid_lstart") or "")
    if not now or not was:
        return True
    return now == was


# --------------------------------------------------------------------- locking

def acquire_lock(root):
    """Exclude another cc-worktree run in this repo.

    Two `cc` launches racing means one's `git worktree prune` can drop a
    registration the other's `git worktree add` is mid-way through creating --
    verified, prune has no expire grace. Same flock shape ccjj uses, but
    non-blocking with a deadline: a wedged holder must not hang a launch
    forever.
    """
    global _LOCK
    os.makedirs(wt_dir(root), exist_ok=True)
    fh = open(os.path.join(wt_dir(root), ".lock"), "w")
    deadline = time.time() + LOCK_WAIT
    while True:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _LOCK = fh          # held for the life of the process
            return fh
        except OSError:
            if time.time() >= deadline:
                die("another cc-worktree run has held the lock in %s for %ds"
                    % (root, LOCK_WAIT))
            time.sleep(0.05)


# --------------------------------------------------------- backend bookkeeping

def jj_workspaces(root):
    r = run(["jj", "workspace", "list", "--ignore-working-copy"], cwd=root)
    return [ln.split(":", 1)[0].strip() for ln in r.stdout.splitlines() if ":" in ln]


def backend_registrations(root, backend):
    """{slot: branch} for slots registered with the backend, captured ONCE.

    `git worktree prune` (step 3 of a release) destroys the registration that
    step 4 reads the branch from, and the "missing .owner" row never had one.
    An orphaned branch makes every later `create` take the w-NN-<stamp> fallback
    FOREVER, so this is captured at the top of a reap and carried through.
    """
    if backend == "jj":
        return {n: "" for n in jj_workspaces(root) if SLOT_RE.match(n)}
    out = {}
    r = run(["git", "worktree", "list", "--porcelain"], cwd=root)
    for block in r.stdout.split("\n\n"):
        path, branch = "", ""
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):]
            elif line.startswith("branch refs/heads/"):
                branch = line[len("branch refs/heads/"):]
        if not path:
            continue
        name = os.path.basename(path)
        if SLOT_RE.match(name) and \
                os.path.realpath(os.path.dirname(path)) == os.path.realpath(wt_dir(root)):
            out[name] = branch
    return out


def unregister(root, backend, slot):
    """Drop a registration whose directory is gone. Idempotent on both backends."""
    if backend == "jj":
        # exits 0 with a warning on an unknown name
        run(["jj", "workspace", "forget", slot], cwd=root)
    else:
        run(["git", "worktree", "prune"], cwd=root)


def git_head_branch(root):
    r = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root)
    return r.stdout.strip() if r.returncode == 0 else ""


def working_copy_dirty(root, backend, at=None):
    at = at or root
    if backend == "jj":
        return "Working copy changes:" in run(["jj", "-R", at, "st"], cwd=root).stdout
    return bool(run(["git", "-C", at, "status", "--porcelain"], cwd=root).stdout.strip())


def slot_dirty(root, backend, slot, entries):
    """Is there work in this slot that is not safely in the repo?

    This is the test that decides between trashing a tree and holding it, and
    SIGKILL / Cmd+Q / tmux kill-session all skip the exit path -- so the crash
    case reaches it via the reaper, and getting it wrong loses the only copy.
    """
    d = slot_dir(root, slot)
    if not os.path.isdir(d):
        return False
    if backend == "jj":
        # Snapshot FIRST. The parent sees only what this workspace LAST
        # snapshotted, so `w-NN@` reads empty while work sits on disk.
        run(["jj", "-R", d, "st"], cwd=root)
        # --no-graph is MANDATORY: without it the output is "@  false" plus graph
        # decoration, the comparison can never match, and this reports clean
        # every time -- uncommitted work straight to the trash.
        r = run(["jj", "log", "--no-graph", "-r", "%s@" % slot, "-T", "empty"], cwd=root)
        if r.returncode != 0:
            return True                     # cannot tell => assume work is there
        return r.stdout.strip() != "true"
    r = run(["git", "-C", d, "status", "--porcelain"], cwd=root)
    names = {rel for _, rel in entries}
    for line in r.stdout.splitlines():
        path = line[3:].strip().strip('"')
        # A link-list symlink we created ourselves is not the user's work. Where
        # an entry is not gitignored (`on` warns about exactly this) every slot
        # would otherwise read dirty and hold, exhausting the pool.
        if path in names:
            continue
        return True
    return False


# ------------------------------------------------------- link-list validation

def git_ignored(root, path):
    return run(["git", "check-ignore", "-q", "--", path], cwd=root).returncode == 0


def jj_untracked_entries(root, entries):
    """Link-list paths jj would auto-track, found by probing a real workspace.

    jj has no surfaced "untracked" concept and no check-ignore, so the only
    reliable test is to build a throwaway workspace, link the list into it and
    ask what changed. A symlink jj tracks gets COMMITTED -- an absolute link
    pointing back into the parent, in the repo's history, forever.

    ("", [paths]) on success; (error, []) when the probe could not be built.
    """
    probe = os.path.join(wt_dir(root), ".cc-probe.%d" % os.getpid())
    name = "cc-probe-%d" % os.getpid()
    os.makedirs(wt_dir(root), exist_ok=True)
    r = run(["jj", "workspace", "add", "--name", name, probe], cwd=root,
            timeout=SLOW_DEADLINE)
    if r.returncode != 0:
        return r.stderr.strip() or "jj workspace add failed", []
    try:
        for mode, rel in entries:
            link_one(root, probe, mode, rel, quiet=True)
        st = run(["jj", "-R", probe, "st"], cwd=root)
        found = []
        probe_rel = os.path.relpath(probe, root) + "/"
        for line in st.stdout.splitlines():
            m = re.match(r"^[AMD] (.+)$", line.strip())
            if not m:
                continue
            # jj reports paths relative to the REPO root, and the probe lives
            # inside it, so strip the probe prefix back to the link-list name.
            p = m.group(1)
            found.append(p[len(probe_rel):] if p.startswith(probe_rel) else p)
        return "", found
    finally:
        run(["jj", "workspace", "forget", name], cwd=root)
        trash(probe)


# ------------------------------------------------------------------- the links

def link_one(root, dest_root, mode, rel, quiet=False):
    """Materialise one link-list entry inside `dest_root`.

    gitignore_global's line 2 is `.*`, so .claude/, .cc-config and .envrc are
    absent from a fresh worktree -- `cc-config sync` then no-ops and the session
    runs unconfigured, silently. This list is mandatory, not a nicety.
    """
    src = os.path.join(root, rel)
    dst = os.path.join(dest_root, rel)
    if not os.path.lexists(src):
        return False                       # missing entries are the normal case
    try:
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        # THE ONLY os.unlink on user content in this tool, so the "nothing is
        # ever deleted, only trashed" promise lives or dies here. Two ways it
        # used to reach into the PARENT and destroy a real file with no copy
        # anywhere, both reproduced:
        #
        #   .claude                        <- links w-01/.claude at the parent
        #   .claude/settings.local.json    <- dst now RESOLVES THROUGH that link,
        #                                     so this unlinked the parent's file
        #                                     and left a self-referential symlink
        #
        # and an absolute entry, where os.path.join returns the entry itself so
        # src == dst and the source was unlinked to make way for a link to
        # itself.
        real_dst_dir = os.path.realpath(os.path.dirname(dst))
        real_dest_root = os.path.realpath(dest_root)
        if real_dst_dir != real_dest_root \
                and not real_dst_dir.startswith(real_dest_root + os.sep):
            warn("refusing to link %s: it resolves outside the worktree (%s).\n"
                 "  An earlier entry probably linked one of its parent"
                 " directories." % (rel, real_dst_dir))
            return False
        if os.path.lexists(dst) and os.path.realpath(dst) == os.path.realpath(src):
            return False                   # already the same file; nothing to do

        if os.path.lexists(dst):
            # Replace a link we own; never a real file. On `--slot --reuse` the
            # surviving tree is adopted as-is, and a real file there is work the
            # session created inside the slot -- ignored, so not on the branch,
            # not stashable, and not in the trash. The only copy.
            if os.path.islink(dst):
                os.unlink(dst)
            else:
                if not quiet:
                    warn("%s already exists in the worktree and is not a link;"
                         " leaving it alone." % rel)
                return False
        if mode == "copy":
            subprocess.run(["cp", "-R" if os.path.isdir(src) else "-p", src, dst],
                           capture_output=True)
        else:
            # Absolute and parent-pointing: a relative link would dangle the
            # moment the worktree moved, and an absolute one cannot be destroyed
            # by removing the worktree.
            os.symlink(src, dst)
        return True
    except OSError as exc:
        if not quiet:
            warn("could not link %s: %s" % (rel, exc))
        return False


def link_all(root, dest_root, entries):
    for mode, rel in entries:
        link_one(root, dest_root, mode, rel)


def trash(path):
    """Move to the trash. 0 also when there is nothing there.

    NEVER `git worktree remove`: without --force it returns 0 and DELETES
    ignored files -- .env, .venv, node_modules -- which is the defect that
    killed the first draft of this design. jj has no surfaced untracked concept
    at all, so trash is the only answer for both backends.
    """
    if not os.path.lexists(path):
        return 0
    r = subprocess.run(["trash", path], capture_output=True, text=True)
    if r.returncode != 0:
        # `trash` moves to ~/.Trash, so a repo on another volume makes this a
        # full cross-device copy. Report the real message rather than a guess.
        warn("trash %s failed: %s" % (path, (r.stderr or r.stdout).strip()))
    return r.returncode


def ccjj_namespace(path):
    """ccjj's journal directory for a worktree, keyed exactly as ccjj keys it."""
    base = os.environ.get("CC_JJ_JOURNAL")
    if not base:
        state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        base = os.path.join(state, "cc-jj-journal")
    return os.path.join(base, path.replace("/", "_"))


# ------------------------------------------------------------- reap and release

def release_slot(root, backend, slot, branch, out=sys.stdout):
    """recover-and-release. Every step leaves a state a re-run finishes.

    That ordering is what makes an interrupt anywhere non-destructive, and it is
    the whole reason this is a numbered sequence rather than a cleanup.
    """
    d = slot_dir(root, slot)

    # 1. jj: bookmark BEFORE forgetting. After `jj workspace forget` the
    #    working-copy commit is no longer in the default revset, so an
    #    un-bookmarked recovery point is effectively invisible. Runs from the
    #    PARENT -- never enter the workspace.
    if backend == "jj" and slot in jj_workspaces(root):
        run(["jj", "bookmark", "set", "%s-%s" % (slot, stamp("%Y%m%d-%H%M")),
             "-r", "%s@" % slot], cwd=root)

    # 2. Trash, never delete -- and a NONZERO trash ABORTS the release with
    #    .owner intact. Continuing would leave a non-empty directory at the slot
    #    path, and `git worktree add` then hard-fails there forever.
    if trash(d) != 0:
        print("cc-worktree: %s NOT released: trash failed; .owner left in place "
              "so a later reap retries" % slot, file=out)
        return False

    # 3. Unregister. Both cleaners are exactly the "registered but gone" case,
    #    and both are idempotent, so trashing first is safe.
    unregister(root, backend, slot)

    # 4. git: -d, NOT -D. -D would destroy the commits this release just went to
    #    the trouble of preserving; -d refuses an unmerged branch and leaves it
    #    as the recovery handle.
    if backend == "git" and branch:
        if run(["git", "branch", "-d", branch], cwd=root).returncode != 0:
            print("cc-worktree: %s: branch %s kept (unmerged) — `git merge %s` "
                  "from %s to recover" % (slot, branch, branch, root), file=out)

    drop_hold(root, slot)
    drop_owner(root, slot)       # 5. LAST: while .owner exists the slot is
                                 #    claimed, so any earlier interrupt is
                                 #    re-processed rather than orphaned.
    trash(ccjj_namespace(d))     # 6. else an unprunable journal namespace per
                                 #    worktree, forever.
    return True


def reap(root, backend, entries, wts, out=sys.stdout):
    """Release finished slots. Anything skipped is NAMED, never silent."""
    for slot in sorted(set(known_slots(root)) | set(wts)):
        rec = read_owner(root, slot)
        owner_exists = os.path.exists(owner_path(root, slot))
        dir_exists = os.path.isdir(slot_dir(root, slot))

        if owner_exists and owner_alive(rec):
            continue
        if os.path.exists(hold_path(root, slot)):
            # Nothing in this system ever reaps a held slot.
            print("cc-worktree: %s held: %s — `cc-worktree release %s --land` "
                  "or `--discard`" % (slot, hold_reason(root, slot) or "no reason recorded",
                                      slot), file=out)
            continue
        if not dir_exists:
            # crash mid-release, or a registration whose directory is long gone
            unregister(root, backend, slot)
            drop_owner(root, slot)
            continue
        if slot_dirty(root, backend, slot, entries):
            # SIGKILL / Cmd+Q / tmux kill-session all skip the exit path, so THIS
            # is the crash case -- the one where trashing loses the only copy.
            write_hold(root, slot, "uncommitted (crashed)")
            print("cc-worktree: %s has uncommitted work and its session is gone; "
                  "held. `cc-worktree release %s --land` or `--discard`"
                  % (slot, slot), file=out)
            continue
        release_slot(root, backend, slot, wts.get(slot, ""), out=out)


# ------------------------------------------------------------------ subcommands

def resolve(start=None):
    """(root, backend), or exit. Every subcommand starts here."""
    root, backend = find_repo(start or os.getcwd())
    if not root:
        die("not inside a git or jj repository", 1)
    return root, backend


def opted_in(root, backend):
    entries, max_slots = read_marker(root, backend)
    if entries is None:
        die("%s is not opted in; `cc-worktree on` first" % root, 2)
    return entries, max_slots


def tracked_paths(root, backend):
    """Repo-relative paths the VCS tracks. Empty set on failure (probe then
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

    Existence AND untrackedness are both required. Tracked paths arrive in the
    checkout by themselves, and linking one would route every worktree edit
    around the VCS.
    """
    tracked = tracked_paths(root, backend)
    proposed, skipped = [], []
    for rel in PROBE_ENTRIES:
        if not os.path.lexists(os.path.join(root, rel)):
            continue
        if rel in tracked or any(t.startswith(rel + "/") for t in tracked):
            skipped.append(rel)
        else:
            proposed.append(rel)
    return proposed, skipped


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
        # Probe rather than defaulting. What a worktree must borrow from its
        # parent is a property of THIS repo, and a static list got it wrong in
        # the direction that matters -- see PROBE_ENTRIES.
        proposed, skipped = probe_entries(root, backend)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(MARKER_HEADER)
            if proposed:
                fh.write("\n# detected in this repo when it was opted in:\n")
                fh.write("".join(p + "\n" for p in proposed))
        if proposed:
            print("cc-worktree: detected %d path(s) to share with each worktree:"
                  % len(proposed))
            for p in proposed:
                print("    %s" % p)
        else:
            print("cc-worktree: nothing local to share; using defaults.")
        if skipped:
            print("  (tracked, so already in every checkout: %s)"
                  % ", ".join(skipped))
        if os.path.exists(os.path.join(root, ".gitmodules")):
            warn("this repo has submodules; a fresh worktree leaves them EMPTY.\n"
                 "  `create` runs `git submodule update --init --recursive`, which\n"
                 "  is slow on first launch. Consider whether isolation is worth it.")
    entries, max_slots = read_marker(root, backend)

    # jj auto-tracks. A symlinked node_modules in a workspace is snapshotted as
    # a symlink into the parent and COMMITTED -- so this refuses rather than
    # warns, and undoes the opt-in it just wrote.
    if backend == "jj":
        err, untracked = jj_untracked_entries(root, entries)
        if err:
            warn("could not verify the link list (%s); jj auto-tracks, so check\n"
                 "  by hand that every entry is ignored." % err)
        elif untracked:
            if fresh:
                os.unlink(path)
            die("jj would track these link-list entries, and commit a symlink\n"
                "  pointing into the parent repo:\n"
                "    %s\n"
                "  Add them to .gitignore, then run `cc-worktree on` again."
                % "\n    ".join(untracked))
    else:
        loose = [rel for _, rel in entries
                 if os.path.lexists(os.path.join(root, rel))
                 and not git_ignored(root, rel)]
        if loose:
            warn("these link-list entries are not ignored by git, so the symlink\n"
                 "  will show up as a change in the worktree: %s" % ", ".join(loose))

    if os.path.exists(os.path.join(root, ".gitmodules")):
        warn("this repo has submodules: `git submodule update --init --recursive`\n"
             "  runs after each worktree is created, which is slow. jj has no equivalent.")
    if working_copy_dirty(root, backend):
        warn("the working copy is dirty. A worktree is based on HEAD/@-, so\n"
             "  in-progress edits will NOT be in it.")

    registry_add(root)
    print("cc-worktree: %s is opted in (%s)." % (root, backend))
    print("  marker: %s" % path)
    print("  links:  %s" % fmt_entries(entries))
    print("  slots:  %d" % max_slots)
    return 0


def fmt_entries(entries):
    return ", ".join("%s%s" % ("copy:" if m == "copy" else "", p) for m, p in entries)


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
    left = known_slots(root)
    if left:
        # Named, never silent: the trees are still on disk and nothing will reap
        # them now that the marker is gone.
        print("  %d slot(s) remain on disk; release them by hand: %s"
              % (len(left), ", ".join(left)))
    return 0


def cmd_status(args):
    root, backend = resolve()
    entries, max_slots = read_marker(root, backend)
    if entries is None:
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
    print("cc-worktree: %s (%s), %d slots" % (root, backend, max_slots))
    print("  marker: %s" % marker_path(root, backend))
    print("  links:  %s" % fmt_entries(entries))
    slots = known_slots(root)
    if not slots:
        print("  no slots in use")
        return 0
    for slot in slots:
        rec = read_owner(root, slot)
        held = hold_reason(root, slot)
        if held:
            state = "HELD: %s" % held
        elif rec is None:
            state = "orphaned (no .owner) — `cc-worktree reap` will release it"
        elif owner_alive(rec):
            state = "active (pid %s, %s)" % (rec.get("pid"), rec.get("cwd", ""))
        else:
            state = "finished — `cc-worktree reap` will release it"
        print("  %-6s %s" % (slot, state))
    return 0


def create_tree(root, backend, slot):
    """(branch, error). The branch is "" for jj, which needs none."""
    d = slot_dir(root, slot)
    if backend == "jj":
        if slot in jj_workspaces(root):
            # A registration whose directory is gone blocks `workspace add` on
            # the same name; reap normally clears it, this is belt and braces.
            run(["jj", "workspace", "forget", slot], cwd=root)
        r = run(["jj", "workspace", "add", "--name", slot, d], cwd=root,
                timeout=SLOW_DEADLINE)
        return ("", "") if r.returncode == 0 else ("", r.stderr.strip())

    # `git worktree add -b w-NN` HARD-FAILS on an existing branch, and a
    # released-but-unmerged slot leaves exactly that behind (release's
    # `git branch -d` refuses on purpose). So this is not optional.
    branch = slot
    if run(["git", "rev-parse", "--verify", "--quiet", "refs/heads/" + slot],
           cwd=root).returncode == 0:
        if run(["git", "branch", "-d", slot], cwd=root).returncode != 0:
            branch = "%s-%s" % (slot, stamp())
    r = run(["git", "worktree", "add", "-b", branch, d], cwd=root,
            timeout=SLOW_DEADLINE)
    if r.returncode != 0:
        return "", r.stderr.strip()
    if os.path.exists(os.path.join(root, ".gitmodules")):
        # `git worktree add` leaves submodules empty.
        run(["git", "-C", d, "submodule", "update", "--init", "--recursive"],
            cwd=root, timeout=SLOW_DEADLINE)
    return branch, ""


def cmd_create(args):
    root, backend = resolve()
    entries, max_slots = read_marker(root, backend)
    if entries is None:
        # Exit 2 with NO git/jj call made at all: this is the common case, on
        # every launch in every repo that has not opted in, and it must cost one
        # process and nothing else.
        sys.exit(2)
    reason = nested_reason(root, backend)
    if reason:
        die("%s: %s. Refusing to nest a worktree inside a worktree." % (root, reason))

    acquire_lock(root)
    wts = backend_registrations(root, backend)
    # Piggybacked reap: its notices go to STDERR here, because this command's
    # stdout is a directory the wrapper cd's into.
    reap(root, backend, entries, wts, out=sys.stderr)
    wts = backend_registrations(root, backend)

    pid = str(args.pid or os.getpid())
    record = {"pid": int(pid), "pid_lstart": ps_lstart(pid), "slot": None,
              "branch": None, "backend": backend, "repo": root,
              "parent_branch": git_head_branch(root) if backend == "git" else "",
              "cwd": os.getcwd(), "created_at": int(time.time())}

    adopt = False
    if args.slot:
        # Slot-aware resume: --resume must land in the SAME directory the
        # session ran in, because Claude Code keys transcripts by mangled cwd.
        slot = args.slot
        rec = read_owner(root, slot)
        # A live owner with OUR pid is this same terminal resuming its own held
        # slot -- the commonest resume there is, because `finish` writes the
        # hold while the owning shell is still at its prompt. Only a *different*
        # live session is a real collision.
        if rec and owner_alive(rec) and str(rec.get("pid")) != pid:
            die("slot %s is in use by a live session (pid %s); cannot resume into it"
                % (slot, rec.get("pid")))
        record["slot"] = slot
        adopt = os.path.isdir(slot_dir(root, slot))
        write_owner(root, slot, record)
        # The session is live again. If it exits dirty it will hold again.
        drop_hold(root, slot)
    else:
        slot = ""
        for n in range(1, max_slots + 1):
            cand = "w-%02d" % n
            record["slot"] = cand
            if claim(root, cand, record):
                slot = cand
                break
        if not slot:
            held = [(s, hold_reason(root, s)) for s in known_slots(root)
                    if os.path.exists(hold_path(root, s))]
            lines = ["every one of the %d slots in %s is in use." % (max_slots, root)]
            for s, why in held:
                lines.append("  %s held: %s" % (s, why or "no reason recorded"))
                lines.append("    cc-worktree release %s --land   # or --discard" % s)
            die("\n".join(lines))

    if adopt:
        # Resuming into a slot whose tree survived: the uncommitted work is
        # right there, which is exactly what a resume wants.
        branch = (read_owner(root, slot) or {}).get("branch") or wts.get(slot, "")
    else:
        branch, err = create_tree(root, backend, slot)
        if err:
            # Nothing to preserve, so release WITHOUT a hold.
            trash(slot_dir(root, slot))
            unregister(root, backend, slot)
            drop_owner(root, slot)
            die("could not create the worktree for %s:\n  %s" % (slot, err))

    record["branch"] = branch
    # Completed record replaces the claim by RENAME, so the no-empty-window
    # property of the claim survives.
    write_owner(root, slot, record)

    link_all(root, slot_dir(root, slot), entries)

    if working_copy_dirty(root, backend):
        warn("the parent working copy is dirty; this worktree is based on\n"
             "  HEAD/@- and does NOT contain those edits.")

    rel = os.path.relpath(os.getcwd(), root)
    target = slot_dir(root, slot)
    if rel not in (".", ""):
        sub = os.path.join(target, rel)
        if os.path.isdir(sub):
            target = sub
        else:
            # Untracked directories do not come across; aborting the launch over
            # that would be worse than starting at the worktree root.
            warn("%s does not exist in the worktree; starting at its root instead." % rel)
    print(target)
    return 0


def cmd_reap(args):
    if args.all:
        keep = []
        for root in registry_read():
            backend = "jj" if os.path.exists(os.path.join(root, ".jj")) else "git"
            if not os.path.exists(marker_path(root, backend)):
                print("cc-worktree: %s is no longer opted in; dropped from the registry"
                      % root)
                continue
            keep.append(root)
            entries, _ = read_marker(root, backend)
            acquire_lock(root)
            reap(root, backend, entries, backend_registrations(root, backend))
        registry_write(keep)
        return 0
    root, backend = resolve()
    entries, _ = opted_in(root, backend)
    acquire_lock(root)
    reap(root, backend, entries, backend_registrations(root, backend))
    return 0


def merge_and_release(root, slot, branch, entries, wts):
    """git exit path: merge the slot branch into the parent, or hold and explain."""
    if not branch:
        release_slot(root, "git", slot, "")
        return 0
    m = run(["git", "merge", "--no-edit", branch], cwd=root, timeout=SLOW_DEADLINE)
    if m.returncode == 0:
        release_slot(root, "git", slot, branch)
        return 0
    text = m.stdout + m.stderr
    if "would be overwritten" in text:
        # The likeliest failure, and it is NEITHER a conflict nor a generic
        # error: an uncommitted parent edit to a touched file fails what was a
        # FAST-FORWARD, and `git merge --abort` then exits 128 ("no merge to
        # abort") -- which would be reported instead of the actionable advice.
        write_hold(root, slot, "merge blocked by uncommitted parent changes (%s)" % branch)
        print("cc-worktree: %s held: the parent has uncommitted changes to files\n"
              "  this session touched. From %s:\n"
              "    git stash && git merge %s && git stash pop" % (slot, root, branch))
        return 0
    run(["git", "merge", "--abort"], cwd=root)
    kind = "merge conflict" if ("CONFLICT" in text or "Automatic merge failed" in text) \
        else "merge failed"
    write_hold(root, slot, "%s on %s" % (kind, branch))
    print("cc-worktree: %s held: %s on %s. Aborted, nothing half-applied.\n"
          "  From %s:  git merge %s" % (slot, kind, branch, root, branch))
    if kind == "merge failed":
        print("  git said: %s" % (text.strip().splitlines() or [""])[0])
    return 0


def cmd_finish(args):
    """The wrapper's exit path, in one place so it can be tested."""
    root, backend = resolve()
    entries, _ = opted_in(root, backend)
    slot = args.slot
    if not SLOT_RE.match(slot):
        die("%s is not a slot name" % slot)
    acquire_lock(root)
    wts = backend_registrations(root, backend)
    rec = read_owner(root, slot) or {}
    branch = rec.get("branch") or wts.get(slot, "")

    if not os.path.isdir(slot_dir(root, slot)):
        release_slot(root, backend, slot, branch)
        return 0

    if slot_dirty(root, backend, slot, entries):
        # The NORMAL end of a session: Ctrl-C mid-task, "commit later".
        write_hold(root, slot, "uncommitted")
        print("cc-worktree: %s held: uncommitted work in %s\n"
              "  cc-worktree land %s      # bring it into the parent, then release\n"
              "  cc-worktree release %s --discard   # throw it away (to the trash)"
              % (slot, slot_dir(root, slot), slot, slot))
        return 0

    if backend == "jj":
        # No merge needed: bookmarks are repo-global, so the agent's own
        # `jj commit` + `jj bookmark set master -r @-` inside the workspace has
        # already advanced master.
        release_slot(root, backend, slot, branch)
        return 0

    # The merge target is whatever the parent has checked out NOW. If it moved,
    # merging lands the work somewhere nobody asked for -- so hold and name
    # both. Checked BEFORE the merge, which is the only order that prevents it.
    was = rec.get("parent_branch") or ""
    now = git_head_branch(root)
    if was and now and was != now:
        write_hold(root, slot, "parent moved from %s to %s" % (was, now))
        print("cc-worktree: %s held: the parent was on %s when this session "
              "started and is on %s now.\n"
              "  git -C %s merge %s   # when you are back on %s"
              % (slot, was, now, root, branch, was))
        return 0
    return merge_and_release(root, slot, branch, entries, wts)


def land_git(root, slot, entries, commit):
    """Bring a held slot's uncommitted work into the parent. "" ok, else why not."""
    d = slot_dir(root, slot)
    if commit:
        run(["git", "-C", d, "add", "-A"], cwd=root)
        r = run(["git", "-C", d, "commit", "-m", "wip: %s" % slot], cwd=root)
        if r.returncode != 0 and "nothing to commit" not in (r.stdout + r.stderr):
            return "could not commit in %s:\n%s" % (d, (r.stderr or r.stdout).strip())
        return ""

    # `git stash create` does NOT include untracked files, so they are handled
    # separately -- without this they would be trashed by the release below and
    # `land` would be a work-losing path, which only --discard is allowed to be.
    untracked = [p for p in run(["git", "-C", d, "ls-files", "--others",
                                 "--exclude-standard"], cwd=root).stdout.splitlines()
                 if p.strip()]
    clash = [p for p in untracked if os.path.lexists(os.path.join(root, p))]
    if clash:
        return ("these files exist only in %s but already exist in the parent:\n"
                "    %s\n"
                "  Retry with --commit, or move them by hand." % (slot, "\n    ".join(clash)))

    sha = run(["git", "-C", d, "stash", "create"], cwd=root).stdout.strip()
    if sha:
        r = run(["git", "stash", "apply", sha], cwd=root)
        if r.returncode != 0:
            return ("could not apply %s's changes to the parent:\n%s\n"
                    "  The slot is untouched; resolve and retry, or use --commit."
                    % (slot, (r.stderr or r.stdout).strip()))
    for p in untracked:
        dst = os.path.join(root, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        subprocess.run(["cp", "-p", os.path.join(d, p), dst], capture_output=True)
        print("cc-worktree: %s: brought across untracked %s" % (slot, p))
    return ""


def cmd_land(args):
    root, backend = resolve()
    entries, _ = opted_in(root, backend)
    slot = args.slot
    if not SLOT_RE.match(slot):
        die("%s is not a slot name" % slot)
    acquire_lock(root)
    wts = backend_registrations(root, backend)
    rec = read_owner(root, slot) or {}
    if rec and owner_alive(rec):
        die("%s is in use by a live session (pid %s)" % (slot, rec.get("pid")))
    branch = rec.get("branch") or wts.get(slot, "")
    if not os.path.isdir(slot_dir(root, slot)):
        die("%s has no worktree at %s" % (slot, slot_dir(root, slot)))

    if backend == "jj":
        # Snapshot, and release_slot's bookmark then captures it. Bookmarks are
        # repo-global, so there is nothing to merge.
        run(["jj", "-R", slot_dir(root, slot), "st"], cwd=root)
        release_slot(root, backend, slot, branch)
        return 0

    if slot_dirty(root, backend, slot, entries):
        why = land_git(root, slot, entries, args.commit)
        if why:
            die("cannot land %s: %s" % (slot, why))
    return merge_and_release(root, slot, branch, entries, wts)


def cmd_release(args):
    root, backend = resolve()
    entries, _ = opted_in(root, backend)
    slot = args.slot
    if not SLOT_RE.match(slot):
        die("%s is not a slot name" % slot)
    if not args.land and not args.discard:
        die("release needs to know what to do with the work in %s:\n"
            "  cc-worktree release %s --land      # bring it into the parent first\n"
            "  cc-worktree release %s --discard   # trash it (the only path that "
            "loses work)" % (slot, slot, slot))
    if args.land:
        return cmd_land(args)
    acquire_lock(root)
    wts = backend_registrations(root, backend)
    rec = read_owner(root, slot) or {}
    if rec and owner_alive(rec):
        die("%s is in use by a live session (pid %s)" % (slot, rec.get("pid")))
    release_slot(root, backend, slot, rec.get("branch") or wts.get(slot, ""))
    return 0


def ccs_entry_dirs():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return [os.path.join(base, "claude-sessions", "open"),
            os.path.join(base, "claude-sessions", "archive")]


def cmd_slot_for_session(args):
    """The slot a recorded session ran in, exit 1 if there is none.

    `claude --resume <id>` is scoped to the project directory -- Claude Code
    keys transcripts by mangled cwd -- so a session that ran in w-03 can ONLY be
    resumed from w-03. Exit 1 (no slot) is the correct answer for an entry that
    predates this feature: its transcript is keyed to the parent, so the parent
    is where it resumes.
    """
    for d in ccs_entry_dirs():
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(d, name)) as fh:
                    rec = json.load(fh)
            except (OSError, ValueError):
                continue
            if rec.get("session_id") != args.session:
                continue
            slot = rec.get("slot") or ""
            if SLOT_RE.match(slot):
                print(slot)
                return 0
    return 1


def cmd_current(args):
    """Slot name for a path, exit 1 if it is not inside one. Pure string work."""
    m = NESTED_RE.search(args.path if args.path.endswith("/") else args.path + "/")
    if not m:
        return 1
    seg = args.path.rstrip("/").split("/.claude/worktrees/")[-1].split("/")[0]
    print(seg)
    return 0


def main():
    ap = argparse.ArgumentParser(prog="cc-worktree",
                                 description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("on", help="opt this checkout in to worktree isolation")
    sub.add_parser("off", help="opt this checkout out")
    sub.add_parser("status", help="marker, link list and slot state")

    c = sub.add_parser("create", help="claim a slot; print the target directory")
    c.add_argument("--pid", help="the owning shell's pid ($fish_pid)")
    c.add_argument("--slot", help="claim this slot specifically (resume)")
    c.add_argument("--reuse", action="store_true",
                   help="with --slot: adopt an existing tree rather than fail")

    r = sub.add_parser("reap", help="release finished slots")
    r.add_argument("--all", action="store_true", help="every opted-in repo")

    f = sub.add_parser("finish", help="exit path: hold, or merge and release")
    f.add_argument("--slot", required=True)

    la = sub.add_parser("land", help="bring a slot's work into the parent, then release")
    la.add_argument("slot")
    la.add_argument("--commit", action="store_true",
                    help="commit `wip: w-NN` on the branch instead of stashing")

    rl = sub.add_parser("release", help="release a slot")
    rl.add_argument("slot")
    rl.add_argument("--land", action="store_true")
    rl.add_argument("--discard", action="store_true")
    rl.add_argument("--commit", action="store_true")

    cu = sub.add_parser("current", help="slot name for a path")
    cu.add_argument("--path", required=True)

    sfs = sub.add_parser("slot-for-session", help="slot a recorded session ran in")
    sfs.add_argument("session")

    args = ap.parse_args()
    # slot-for-session reads only the ccs registry, so it must NOT require a
    # repo: the wrapper calls it before it knows whether isolation applies.
    if args.cmd == "slot-for-session":
        sys.exit(cmd_slot_for_session(args))
    sys.exit({"on": cmd_on, "off": cmd_off, "status": cmd_status,
              "create": cmd_create, "reap": cmd_reap, "finish": cmd_finish,
              "land": cmd_land, "release": cmd_release,
              "current": cmd_current}[args.cmd](args))


if __name__ == "__main__":
    main()
