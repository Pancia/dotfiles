#!/usr/bin/env python3
"""Session-scoped jj commits for concurrent Claude Code sessions.

Several Claude sessions can share one jj working copy. jj snapshots the *entire*
working copy on every command, so a plain `jj commit` in one session captures
whatever the others have half-written -- including files they created. This
reconstructs just one session's contribution and commits that, leaving everyone
else's work untouched and on disk.

    ccjj record-edit          PostToolUse hook (Edit|Write); journals one record
    ccjj commit -m MSG        commit only this session's edits
    ccjj audit                report working-copy changes no session claims
    ccjj who PATH             list the sessions with a stake in one path
    ccjj prune                retire old journals

`commit-mine` is a shim for `ccjj commit`.

Exit codes:  0 ok · 1 refused · 2 nothing to do · 4 locked or base moved
             5 unclaimed Bash-window paths (claim them, or --no-claim)

Most of the guards below are holding back a defect that was reproduced first;
the comments say which, because nearly all of them fail *silently* if removed.
See docs/cc-jj-sessions.md.
"""
import argparse
import atexit
import base64
import datetime
import fcntl
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time
from typing import NoReturn

JJ_DEADLINE = 8          # seconds; a wedged jj must never hang the agent
SCHEMA = 2               # 2 adds "rel"; schema 1 records still read, see rec_rel
ROOT = ""                # repo root, set once in main() before any subcommand
# Everything that counts as a session's journal content. A filter that lists the
# suffixes by hand misses the next one: an offer-only journal read as empty, so
# the daily prune retired it.
JOURNAL_SUFFIXES = (".json", ".win", ".offer")
OFFERED = "offered"      # window_coverage's status for a path an offer holds


# --------------------------------------------------------------- shared paths

def journal_root():
    base = os.environ.get("CC_JJ_JOURNAL")
    if base:
        return base
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "cc-jj-journal")


def repo_key(root):
    # Byte-identical to ai_jj_commit.fish's convention so both tools show the
    # same repo names side by side in the state dir.
    return root.replace("/", "_")


def true_case(path):
    """`path` respelled with the casing the filesystem actually stores.

    macOS is case-INSENSITIVE but case-PRESERVING, and os.path.realpath does not
    normalize case (posixpath resolves symlinks, nothing more). So one directory
    has two equally-working spellings, and the recorder -- which resolves the
    root from the agent's file_path -- could spell it differently from readers,
    which take it from `jj root`. repo_key() turns that string into the journal
    directory NAME, so the journal would silently split in two on any
    case-sensitive volume; here it merely masks the split. Canonicalizing at the
    two places a root originates keeps all 20-odd repo_key() call sites
    consistent without touching any of them.

    Resolution is per component and best-effort: an unreadable, missing or
    ambiguous component ends the walk and the REMAINDER is kept verbatim, so a
    path that does not exist yet still gets its existing ancestors canonicalized.
    All-or-nothing would have been worse in the one case that matters -- a record
    names a file, and only its directories can be looked up.

    Two same-inode spellings cannot both appear in one listdir on a
    case-insensitive volume, so the ambiguity guard only ever fires on a
    case-sensitive one, where `Foo` and `foo` are genuinely different
    directories and guessing between them would be a data-loss bug.
    """
    if not os.path.isabs(path):
        return path
    out = os.sep
    parts = [p for p in path.split(os.sep) if p]
    for i, part in enumerate(parts):
        try:
            names = os.listdir(out)
        except OSError:
            return os.path.join(out, *parts[i:])
        if part not in names:
            hits = [n for n in names if n.lower() == part.lower()]
            if len(hits) != 1:
                return os.path.join(out, *parts[i:])
            part = hits[0]
        out = os.path.join(out, part)
    return out


def under_root(p, resolve=True):
    """`p` relative to ROOT by INODE, or None when genuinely outside.

    os.path.relpath is a pure string compare against a ROOT that may be spelled
    with different case (see true_case), so `.../Vaults/x` under a ROOT of
    `.../vaults` read as "outside the repo" though both name one directory --
    same st_ino. Walking up by identity is the only comparison that cannot be
    fooled by spelling. Non-existent components are skipped rather than fatal:
    a record may name a file that has since been deleted, and only its
    ancestors need to exist for containment to be decidable.

    resolve=False keeps rel_literal()'s contract where it is load-bearing: a
    LEAF symlink still names itself rather than its target, so a claim cannot be
    silently retargeted. Ancestor directories are resolved either way -- os.stat
    follows links and must, since containment is a question about real
    directories -- which is a change only for a symlinked ancestor, where it
    replaces a spurious refusal with the right answer.

    The starting point is true_case'd so the components handed back are the
    names jj tracks. Without it a record spelled `.../ROOT/SUB/f.txt` yielded
    `SUB/f.txt`, which no revision contains, and build() then mistook a file it
    could not find for a newly created one and adopted its content wholesale
    instead of reporting the conflict.
    """
    try:
        st_root = os.stat(ROOT)
    except OSError:
        return None
    cur = true_case(os.path.realpath(p) if resolve else os.path.abspath(p))
    parts = []
    while True:
        try:
            if os.path.samestat(os.stat(cur), st_root):
                return os.path.join(*reversed(parts)) if parts else "."
        except OSError:
            pass
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        parts.append(os.path.basename(cur))
        cur = parent


def find_repo(start):
    d = os.path.realpath(start)
    while True:
        if os.path.isdir(os.path.join(d, ".jj")):
            # Canonical case, so repo_key() names one journal dir per repo
            # however the agent happened to spell the path it handed us.
            return true_case(d)
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def die(msg, code=1) -> NoReturn:
    # sys.exit(str) always exits 1, which would silently discard every documented
    # exit code. Callers distinguish "retry" (4) from "refused" (1).
    print("ccjj: " + msg, file=sys.stderr)
    sys.exit(code)


def jj(*args, check=True, cwd=None):
    # cwd=ROOT is load-bearing: jj filesets resolve against the CWD, so running
    # from a subdirectory matched nothing and surfaced as a bogus conflict.
    try:
        r = subprocess.run(["jj", *args], capture_output=True,
                           cwd=cwd or ROOT, timeout=JJ_DEADLINE)
    except subprocess.TimeoutExpired:
        die("jj %s exceeded %ds" % (" ".join(args), JJ_DEADLINE), 4)
    if check and r.returncode != 0:
        die("jj %s failed:\n%s" % (" ".join(args), r.stderr.decode(errors="replace")))
    return r


def fs(path):
    # jj's default fileset pattern is a GLOB, so a bare path containing
    # ~ & | ( ) [ ] : or a leading dash is parsed as an expression.
    return 'root-file:"%s"' % path.replace("\\", "\\\\").replace('"', '\\"')


def rel(p):
    r = os.path.relpath(os.path.realpath(p), ROOT)
    if r == ".." or r.startswith(".." + os.sep) or os.path.isabs(r):
        # The string compare escaped. That is the answer on a case-sensitive
        # filesystem and a lie on this one, so confirm by inode before refusing:
        # `ccjj audit` dropped every record whose path was spelled with
        # different case, and `ccjj commit` aborted the WHOLE run on the first
        # one -- both while the path sat plainly inside the repo.
        alt = under_root(p)
        if alt is not None:
            return alt
        die("%s is outside the repo (%s).\n"
            "  It cannot be committed here; remove its journal record and re-run." % (p, ROOT))
    return r


def parent_ids():
    """(list of @-'s commit ids, error text). None on failure.

    The "\\n" is load-bearing, and this lives at module scope because getting it
    wrong was the SAME defect in three places. With a bare `commit_id` template a
    MERGE working copy exits 0 and CONCATENATES both parents into one 80-char
    string, which: defeated cmd_commit's merge guard (gated on returncode);
    made survey() diff from a nonsense revision, so `ccjj audit` reported
    all-clear with everything unclaimed; and let stamp_base() write an 80-char
    .base that can never match again, so that session reports drift forever.
    """
    p = jj("log", "--no-graph", "-T", 'commit_id ++ "\\n"', "-r", "@-",
           "--ignore-working-copy", check=False)
    if p.returncode != 0:
        return None, p.stderr.decode(errors="replace")
    return p.stdout.decode().split(), ""


def rel_literal(p):
    """Repo-relative path WITHOUT resolving symlinks.

    rel() realpaths, which is right for an Edit -- the write went through the
    link, so the link's target is the file that actually changed -- and wrong
    for a Bash window, which names the link itself. Resolving it silently
    retargets the claim: reproduced, a record for `cfg` became `b.txt`, the
    payload then equalled @-, and the commit verified clean having committed
    nothing. abspath normalizes `.` and `..` without touching symlinks.
    """
    r = os.path.relpath(os.path.abspath(p), ROOT)
    if r == ".." or r.startswith(".." + os.sep) or os.path.isabs(r):
        alt = under_root(p, resolve=False)   # same case trap as rel()
        if alt is not None:
            return alt
        die("%s is outside the repo (%s)." % (p, ROOT))
    return r


def rec_rel(rec):
    """Repo-relative path of a journal record.

    Schema 2 records carry it, computed at record time against the root the
    recorder itself resolved -- so it needs no re-derivation and no comparison
    that spelling can break. Schema 1 records hold only an absolute path, which
    must still be measured against ROOT; that is the path rel() now guards by
    inode, and it is how records written before this change keep working.
    """
    return rec.get("rel") or rel(rec["path"])


# ---------------------------------------------------------------- shared lock

def ps_lstart(pid):
    try:
        return subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def acquire_shared_lock():
    """Take ai_jj_commit's lock, in ai_jj_commit's format, at its path.

    The two tools used different locks -- a mkdir lockdir here, an flock on
    .jj/ccjj.lock there -- so they did not exclude each other, and a `g run ci`
    racing a session commit is exactly the divergent-change failure the flock
    exists to prevent. Same directory, same `pid lstart` file, same staleness
    rule, so either tool can see and clear the other's.

    Returns the lockdir path. Exits 4 (retry) rather than blocking, matching
    ai_jj_commit's contract.
    """
    base = os.path.expanduser("~/.local/state/ai-jj-commit")
    try:
        os.makedirs(base, exist_ok=True)
    except OSError:
        die("cannot create lock directory %s" % base)
    lockdir = os.path.join(base, repo_key(ROOT) + ".lock")

    def claim():
        try:
            os.mkdir(lockdir)
            return True
        except FileExistsError:
            return False

    if not claim():
        try:
            holder = open(os.path.join(lockdir, "pid")).read().strip()
        except OSError:
            holder = ""
        if not holder:
            # Between another process's mkdir and its pid write. Stealing here is
            # the exact interleaving the lock prevents; only an ancient empty
            # lockdir is safe to clear.
            try:
                age = time.time() - os.stat(lockdir).st_mtime
            except OSError:
                age = 0
            if age < 30 * 60:
                die("another commit is being started; retry shortly", 4)
        else:
            pid = holder.split(" ")[0]
            started = " ".join(holder.split(" ")[1:])
            if pid.isdigit() and ps_lstart(pid) and ps_lstart(pid) == started:
                die("another commit is in progress (pid %s)" % pid, 4)
        subprocess.run(["rm", "-rf", lockdir])
        if not claim():
            die("could not acquire lock at %s" % lockdir, 4)

    with open(os.path.join(lockdir, "pid"), "w") as fh:
        fh.write("%d %s\n" % (os.getpid(), ps_lstart(os.getpid())))
    # atexit rather than a finally: every die() and the --diff early return are
    # exit paths too, and a leaked lockdir wedges both tools for 30 minutes.
    atexit.register(lambda: subprocess.run(["rm", "-rf", lockdir]))
    return lockdir


# ------------------------------------------------------------------- liveness

STALE_HOURS = 12         # a journal untouched this long is not "live" any more


def stamp_owner(jdir):
    """Record which claude process owns this journal, once.

    pid alone is not enough -- pids are recycled -- so the process start time is
    recorded alongside it, the same identity check used by ccs.fish:812 and
    ai_jj_commit.fish:70-92. $CLAUDE_PID is inherited by hooks and names the
    owning `claude` process (verified).
    """
    owner = os.path.join(jdir, ".owner")
    # A dead owner is replaced, because `--resume` keeps the session id in a new
    # process. Written once, the session read as "ended" while it worked: prune
    # retired it, and a peer's should-scope took the whole-copy route over it.
    if os.path.exists(owner) and owner_alive(jdir):
        return
    pid = os.environ.get("CLAUDE_PID", "")
    if not pid:
        return
    try:
        lstart = subprocess.run(["ps", "-o", "lstart=", "-p", pid],
                                capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return
    if not lstart:
        return
    with open(owner, "w") as fh:
        fh.write("%s\t%s\n" % (pid, lstart))


def stamp_base(jdir, root):
    """Record the @- this session started from, once.

    Comparing the working copy against the *current* @- is not enough on its
    own: a stray `jj new` (or `jj squash`, or a `git commit` in this colocated
    repo) moves @-, which makes that delta empty. `ccjj audit` then reported
    "every changed path is claimed" at the exact moment the work was swept into
    an unnamed commit. A recorded base is how that drift becomes visible.
    """
    f = os.path.join(jdir, ".base")
    if os.path.exists(f):
        return
    try:
        r = subprocess.run(["jj", "log", "--no-graph", "-T", 'commit_id ++ "\\n"',
                            "-r", "@-", "--ignore-working-copy"],
                           capture_output=True, text=True, cwd=root, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return
    ids = r.stdout.split()
    # Written ONCE, so a bad value is permanent. On a merge working copy the
    # bare template concatenated both parents into an 80-char string that can
    # never equal @- again -- permanent phantom drift, and drift_undo() could
    # never match it either. Better to have no base than a poisoned one.
    if r.returncode != 0 or len(ids) != 1:
        return
    with open(f, "w") as fh:
        fh.write(ids[0])


def read_base(jdir):
    try:
        return open(os.path.join(jdir, ".base")).read().strip()
    except OSError:
        return ""


def refresh_bases(new_base, old_base=None):
    """After ccjj itself moves @-, re-baseline the sessions that were current.

    Without this, our own commit would look to every other session like someone
    else moving the base underneath them.

    With old_base, ONLY sessions whose base was old_base move. Rewriting every
    .base unconditionally erased drift that had already happened: a stray
    `jj commit` sweeps session B's work, `ccjj audit` correctly reports B's base
    moved -- and the next commit-mine from A overwrote B's .base and audit went
    back to "nothing unclaimed", the evidence gone. Reproduced.
    """
    base = os.path.join(journal_root(), repo_key(ROOT))
    if not os.path.isdir(base):
        return
    for sid in os.listdir(base):
        d = os.path.join(base, sid)
        if sid == "archive" or not os.path.isdir(d):
            continue
        if old_base is not None and read_base(d) not in ("", old_base):
            continue
        try:
            with open(os.path.join(d, ".base"), "w") as fh:
                fh.write(new_base)
        except OSError:
            pass


def owner_alive(jdir):
    """True iff the owning claude process is still running.

    Unknown owner counts as alive: a journal we cannot attribute must not be
    swept away or silently ignored.
    """
    owner = os.path.join(jdir, ".owner")
    if not os.path.isfile(owner):
        return True
    try:
        pid, _, lstart = open(owner).read().strip().partition("\t")
    except OSError:
        return True
    if not pid.isdigit():
        return True
    try:
        os.kill(int(pid), 0)
    except (OSError, ProcessLookupError):
        return False
    try:
        now = subprocess.run(["ps", "-o", "lstart=", "-p", pid],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return True
    return now == lstart


def has_activity(d):
    """Any journal content at all -- edit records OR Bash windows.

    A session doing only Bash work has no .json, and would otherwise read as
    dead: absent from the nudge, and swept by prune while still working.
    """
    try:
        return any(n.endswith(JOURNAL_SUFFIXES) for n in os.listdir(d))
    except OSError:
        return False


def journal_age_hours(jdir):
    newest = 0.0
    for name in os.listdir(jdir):
        if name.endswith(JOURNAL_SUFFIXES):
            try:
                newest = max(newest, os.stat(os.path.join(jdir, name)).st_mtime)
            except OSError:
                pass
    if not newest:
        return float("inf")
    return (time.time() - newest) / 3600.0


def session_is_live(jdir):
    """For non-destructive decisions (claims, the nudge).

    Both conditions are needed. `/clear` and compaction rotate the session id in
    the *same* process, so the pre-clear journal keeps a live owner pid forever
    and would otherwise claim its paths and nag about them indefinitely.
    """
    return owner_alive(jdir) and journal_age_hours(jdir) < STALE_HOURS


def same_process_journals(root, sid):
    """Earlier session ids of this process that still hold a live journal.

    Read-only, so `commit-mine --diff` can mention them without moving them.
    """
    pid = os.environ.get("CLAUDE_PID", "")
    base = os.path.join(journal_root(), repo_key(root))
    found = []
    if not pid or not sid or not os.path.isdir(base):
        return found
    for other in sorted(os.listdir(base)):
        d = os.path.join(base, other)
        if other in ("archive", sid) or not os.path.isdir(d):
            continue
        try:
            owner_pid = open(os.path.join(d, ".owner")).read().partition("\t")[0]
            if owner_pid == pid and session_is_live(d):
                found.append(other)
        except OSError:
            pass
    return found


def may_absorb(args):
    """False when --session names someone other than the caller.

    absorb_same_process moves this PROCESS's journals into the id it is given,
    so `--session <unused-id>` moved the caller's whole journal into that id.
    """
    return not args.session or args.session == os.environ.get("CLAUDE_SESSION_ID", "")


def absorb_same_process(root, sid):
    """Move this process's journals from earlier session ids into `sid`.

    `/clear` and compaction give the same `claude` process a new session id, and
    the journal is keyed by that id. The earlier edits then belonged to a "live
    peer" that was really this session: commit-mine left them out and still
    reported "verified", audit said all-clear, and --also refused them.

    Moving the files once, at every entry point, keeps the rest of the tool
    unaware of rotation. Record names are t_ns-pid, so the order survives. A
    journal past STALE_HOURS stays put: session_is_live already ignores those,
    and an old abandoned edit must not start blocking commits. Returns the ids
    taken. Hooks call this too, so it must never raise.
    """
    base = os.path.join(journal_root(), repo_key(root))
    taken = []
    me = os.path.join(base, sid)
    for other in same_process_journals(root, sid):
        d = os.path.join(base, other)
        try:
            os.makedirs(me, mode=0o700, exist_ok=True)
            for n in os.listdir(d):
                if n.endswith(JOURNAL_SUFFIXES):
                    os.replace(os.path.join(d, n), os.path.join(me, n))
            taken.append(other)
            # The earlier base wins: drift since then must stay visible.
            if os.path.exists(os.path.join(d, ".base")):
                os.replace(os.path.join(d, ".base"), os.path.join(me, ".base"))
            for n in (".owner", ".last"):
                if os.path.exists(os.path.join(d, n)):
                    os.remove(os.path.join(d, n))
            os.rmdir(d)
        except OSError:
            # Another hook in this process got there first, or a late write
            # from the old id refilled the directory. The next call finishes.
            pass
    return taken


# ------------------------------------------------------------- record-edit hook

def cmd_record_edit(_args):
    """PostToolUse (Edit|Write). Always exits 0: a recorder that blocks the
    agent is worse than one that misses a record, and `ccjj audit` is what
    catches a miss."""
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if payload.get("tool_name") not in ("Edit", "Write"):
        return

    tin = payload.get("tool_input") or {}
    tres = payload.get("tool_response") or {}
    # The session id must come from the PAYLOAD, never from $CLAUDE_SESSION_ID.
    # A nested `claude -p` inherits the spawning session's value in its hook
    # environment (verified), so the env var can name the wrong session.
    path, sid = tin.get("file_path"), payload.get("session_id")
    if not path or not sid:
        return
    # A real edit reports a patch. Without this a *failed* Edit would leave a
    # phantom record to be replayed into a commit.
    if payload.get("tool_name") == "Edit" and not tres.get("structuredPatch"):
        return
    if tres.get("success") is False:
        return

    root = find_repo(os.path.dirname(path) or payload.get("cwd") or ".")
    if not root:
        return

    # Resolved here, where the root is known to be an ancestor of this very
    # path, rather than re-derived at read time against a root that arrives
    # from `jj root` and may be spelled with different case.
    #
    # true_case on BOTH sides or neither: find_repo() canonicalizes what it
    # returns, so comparing it against a bare realpath reintroduced the exact
    # string mismatch this field exists to avoid -- every mis-cased record
    # stored rel=null and fell back to the very path being fixed.
    rp = os.path.relpath(true_case(os.path.realpath(path)), root)
    if rp == ".." or rp.startswith(".." + os.sep) or os.path.isabs(rp):
        rp = None   # a genuine escape: a leaf symlink out of the repo

    def applied(res_key, in_key):
        # What the tool APPLIED, not what it was asked for. Edit normalizes the
        # request against the file before applying it (curly quotes, escapes),
        # so tool_input.old_string need not occur in originalFile at all -- and
        # anchored_replace then dies "inconsistent record" on a perfectly good
        # edit. tool_response echoes the applied strings, which are substrings
        # of originalFile by construction (657/657 in the transcripts on disk;
        # the request form failed 1/657). Fall back for payloads without them.
        v = tres.get(res_key)
        return v if isinstance(v, str) else tin.get(in_key)

    ra = tres.get("replaceAll")
    record = {
        "schema": SCHEMA,
        "tool": payload["tool_name"],
        "path": path,
        "rel": rp,
        "old": applied("oldString", "old_string"),
        "new": applied("newString", "new_string"),
        "content": applied("content", "content"),
        "replace_all": ra if isinstance(ra, bool) else bool(tin.get("replace_all")),
        # The text this edit was actually applied to. Without it the replay can
        # only match by first occurrence, which patched the wrong site whenever
        # the committed file held the old text more than once.
        "original": tres.get("originalFile"),
        "tool_use_id": payload.get("tool_use_id"),
        "t_ns": time.time_ns(),
    }

    d = os.path.join(journal_root(), repo_key(root), sid)
    os.makedirs(d, mode=0o700, exist_ok=True)
    absorb_same_process(root, sid)
    stamp_owner(d)
    stamp_base(d, root)
    # One file per record, O_EXCL. Appending to a shared .jsonl interleaved
    # under concurrent hooks: order was scrambled and a 64KB Write produced
    # unparseable JSON.
    name = "%019d-%d.json" % (record["t_ns"], os.getpid())
    fd = os.open(os.path.join(d, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(record, fh)


# ----------------------------------------------------------- bash windows
#
# A window is the pair of working-copy commit ids either side of one Bash tool
# call. That is the whole storage scheme: a rewritten working-copy commit stays
# readable and diffable by id (verified across 10 further snapshots, 3 commits,
# `jj abandon`, `jj undo` and `jj op restore`).
#
# Windows are NEVER attributed automatically. A window's delta is a whole-copy
# diff, so it contains every write that landed inside it -- another session's
# Edit, a hardlinked file rewritten from another project (103 tracked files
# here are hardlinked outside the repo), `funcsave` through the
# ~/.config/fish/functions symlink. Attributing that silently commits other
# people's bytes under your name with a PASSING verification, because the
# verification checks fidelity of transcription, not provenance. So `audit`
# offers them and `ccjj claim` requires someone to look at the diff first.

MARKER_OPTIN = "ccjj-bash"       # .jj/<name>: this checkout records windows
MARKER_BUSY = "ccjj-contended"   # .jj/<name>: another live session is here

WIN_T = ('self.status() ++ "\\t" ++ json(self.source().path()) ++ "\\t" '
         '++ json(self.target().path()) ++ "\\t" ++ self.target().file_type() ++ "\\n"')


def marker(root, name):
    return os.path.join(root, ".jj", name)


def cmd_bash_window(_args):
    """PostToolUse hook (Bash). Records [previous id, current id] for this session.

    PostToolUse only, deliberately. A paired pre/post would double the cost and
    leak an open window whenever Post does not fire -- which it often does not
    for a failing Bash command. With a rolling marker a missing Post just widens
    the next window, so orphans are not a category.
    """
    global ROOT
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    sid = payload.get("session_id")
    if not sid:
        return
    root = find_repo(payload.get("cwd") or ".")
    if not root or not os.path.isfile(marker(root, MARKER_OPTIN)):
        return
    ROOT = root

    # A snapshot landing inside another session's `jj commit --tool` kills it
    # with "Concurrent checkout" and leaves the repo divergent (reproduced 3/3).
    # Skipping is free; the window just does not cover this call.
    lockdir = os.path.join(os.path.expanduser("~/.local/state/ai-jj-commit"),
                           repo_key(root) + ".lock")
    if os.path.isdir(lockdir):
        return

    # One process that snapshots AND returns the id: 20ms idle, 70ms with a
    # pending change on a 4000-file repo. `jj util snapshot` then a separate
    # read costs two. (Never pass --ignore-working-copy here: it reports
    # "No snapshot needed" and does nothing, with real changes on disk.)
    r = jj("log", "--no-graph", "-T", "commit_id", "-r", "@", check=False)
    now = r.stdout.decode().strip()
    if r.returncode != 0 or len(now) != 40:
        return

    d = os.path.join(journal_root(), repo_key(root), sid)
    os.makedirs(d, mode=0o700, exist_ok=True)
    absorb_same_process(root, sid)
    stamp_owner(d)
    stamp_base(d, root)

    last = os.path.join(d, ".last")
    try:
        prev = open(last).read().strip()
    except OSError:
        prev = ""
    # Subagents share the parent's session id and run concurrently, so two of
    # these hooks genuinely can be here at once. A torn read yields a short
    # prefix, which jj may resolve ambiguously -- and since window_span always
    # starts at ws[0]["before"], one bad first window locks the session out of
    # `claim` for good, with a misleading "the ids no longer resolve".
    if len(prev) != 40:
        prev = ""
    tmp = last + ".%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write(now)
    os.replace(tmp, last)
    # The first Bash call of a session only establishes the baseline; there is
    # no earlier id to bound it. Documented, not silently swallowed.
    if not prev or prev == now:
        return

    rec = {"schema": SCHEMA, "kind": "window", "before": prev, "after": now,
           "t_ns": time.time_ns(), "tool_use_id": payload.get("tool_use_id")}
    name = "%019d-%d.win" % (rec["t_ns"], os.getpid())
    fd = os.open(os.path.join(d, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(rec, fh)


def load_windows(jdir):
    if not os.path.isdir(jdir):
        return []
    out = []
    for name in sorted(os.listdir(jdir)):
        if not name.endswith(".win"):
            continue
        try:
            with open(os.path.join(jdir, name)) as fh:
                out.append(json.load(fh))
        except (json.JSONDecodeError, OSError):
            # Unlike a journal record, a window is only ever an offer -- never
            # load-bearing for a commit -- so a damaged one is skipped, not fatal.
            continue
    return out


def load_offers(jdir):
    """What earlier commits left behind: [{"paths": [...], "windows": [...]}].

    A .win is a whole-copy id pair, so it cannot be kept "for one path": a kept
    window also spans the files that commit took, and the next commit stopped
    with exit 5 on them. An offer names its paths, and only those.
    """
    out = []
    if not os.path.isdir(jdir):
        return out
    for name in sorted(os.listdir(jdir)):
        if not name.endswith(".offer"):
            continue
        try:
            with open(os.path.join(jdir, name)) as fh:
                offer = json.load(fh)
        except (json.JSONDecodeError, OSError):
            continue          # like a window, only ever an offer
        if isinstance(offer.get("paths"), list) and isinstance(offer.get("windows"), list):
            out.append(offer)
    return out


def write_offer(jdir, paths, windows):
    os.makedirs(jdir, mode=0o700, exist_ok=True)
    name = "%019d-%d.offer" % (time.time_ns(), os.getpid())
    with open(os.path.join(jdir, name), "w") as fh:
        json.dump({"schema": SCHEMA, "kind": "offer", "paths": sorted(paths),
                   "windows": windows}, fh)


def leave_offers(archived, jdir, only):
    """After a commit, keep what `claim` needs for the work it left behind.

    retire() has just archived every window, which made a later claim impossible
    and took the session's stake with it: a peer could then claim the left-behind
    file unrefused. `only` limits new offers: None means every covered path still
    changed (--no-claim), a set means just those. Earlier offers carry over for
    paths that are still changed, so a committed path stops being offered.
    """
    still = working_copy_paths()
    for offer in load_offers(archived):
        kept = set(offer["paths"]) if still is None else set(offer["paths"]) & still
        if kept:
            write_offer(jdir, kept, offer["windows"])
    wins = load_windows(archived)
    if not wins:
        return
    covered = set()
    for status, src, tgt, _ in window_delta(wins[0]["before"], wins[-1]["after"]) or ():
        covered.add(tgt)
        if status == "renamed":
            covered.add(src)
    if only is not None:
        covered &= only
    if still is not None:
        covered &= still
    if covered:
        write_offer(jdir, covered, wins)


def claimable_windows(jdir, path):
    """This session's live windows, plus any an earlier commit kept for `path`."""
    wins = {(w["before"], w["after"]): w for w in load_windows(jdir)}
    for offer in load_offers(jdir):
        if path in offer["paths"]:
            wins.update({(w["before"], w["after"]): w for w in offer["windows"]})
    return sorted(wins.values(), key=lambda w: w.get("t_ns", 0))


def window_span(jdir):
    """(before, after) covering every Bash call this session recorded.

    Windows are contiguous by construction -- each starts where the previous one
    ended -- so the first `before` and last `after` bound the union exactly.
    """
    ws = load_windows(jdir)
    return (ws[0]["before"], ws[-1]["after"]) if ws else None


def window_delta(before, after):
    """[(status, source, target, target_type)], or None if the ids are gone.

    `jj op abandon` destroys a stored id INSTANTLY -- no gc needed, no grace
    period -- because resolution goes through the op-log-derived index rather
    than the object store. So an unresolvable window is a real state.
    """
    r = jj("--ignore-working-copy", "diff", "--from", before, "--to", after,
           "-T", WIN_T, check=False)
    if r.returncode != 0:
        return None
    out = []
    for line in r.stdout.decode(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        try:
            out.append((parts[0], json.loads(parts[1]), json.loads(parts[2]), parts[3]))
        except json.JSONDecodeError:
            continue
    return out


def window_coverage():
    """path -> {session id: status}. One jj call per session, not per window.

    A dict per path, not a single winner: two sessions' windows routinely cover
    the same path, and picking whichever session id sorted first attributed it
    to one and said nothing about the other.
    """
    cov = {}
    base = os.path.join(journal_root(), repo_key(ROOT))
    if not os.path.isdir(base):
        return cov
    for sid in sorted(os.listdir(base)):
        d = os.path.join(base, sid)
        if sid == "archive" or not os.path.isdir(d):
            continue
        span = window_span(d)
        delta = window_delta(*span) if span else None
        for status, src, tgt, _ in delta or ():
            cov.setdefault(tgt, {}).setdefault(sid, status)
            if status == "renamed":
                cov.setdefault(src, {}).setdefault(sid, status)
        # After the windows: a new Bash change to an offered path must read as a
        # change, or the exit-5 check would skip it and silently lose it.
        for offer in load_offers(d):
            for p in offer["paths"]:
                cov.setdefault(p, {}).setdefault(sid, OFFERED)
    return cov


# ------------------------------------------------------------------- the nudge

def cmd_nudge(_args):
    """UserPromptSubmit hook. Tells the agent, before it reads the prompt, that
    someone else is working here.

    This exists because the user types "commit stuff", not `/cc:commit` — so the
    steer has to arrive without them invoking anything. Deliberately NOT a
    PreToolUse block: hooks do not inherit the agent's shell environment, so an
    env-var escape hatch cannot work; a command-pattern list misses `jj new`,
    `jj ci` and `git commit`; and hooks fail *open* on timeout.

    Deliberately does not look at what the user typed. Gating on repo state
    instead of on phrasing means there is no wording to slip past.

    Makes zero `jj` calls: it runs on every prompt in every project.
    """
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    root = find_repo(payload.get("cwd") or ".")
    if not root:
        return
    me = payload.get("session_id") or ""
    absorb_same_process(root, me)

    base = os.path.join(journal_root(), repo_key(root))
    others = []
    if os.path.isdir(base):
        for sid in sorted(os.listdir(base)):
            d = os.path.join(base, sid)
            if sid == "archive" or sid == me or not os.path.isdir(d):
                continue
            if has_activity(d) and session_is_live(d):
                others.append(sid)

    # Maintain the contention marker for the Bash-window shell gate, which must
    # decide in two `test -f` and no interpreter start. This is the only place
    # that already computes liveness on every prompt. Opted-in checkouts only,
    # so nothing is written into any other repo.
    # SET ONLY, never clear. `others` is relative to the prompting session, so
    # clearing here made two sessions fight over it: a brand-new peer has no
    # journal yet, so the established session saw "no others" and deleted the
    # marker -- and the peer could not record a window to get a journal until
    # the marker existed. Windows silently stopped. Clearing belongs where the
    # whole picture is known (prune / retire-all), and a stale marker only ever
    # costs a snapshot.
    if others and os.path.isfile(marker(root, MARKER_OPTIN)):
        try:
            open(marker(root, MARKER_BUSY), "a").close()
        except OSError:
            pass

    if not others:
        return

    who = "Another Claude session is" if len(others) == 1 \
        else "%d other Claude sessions are" % len(others)
    msg = ("[ccjj] %s working in %s. Commit with `commit-mine -m \"msg\"` -- a "
           "plain `jj commit` captures their unfinished work too. "
           "`ccjj audit` shows what nobody has claimed."
           % (who, os.path.basename(root)))
    json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                      "additionalContext": msg}}, sys.stdout)


# ------------------------------------------------------------------- rebuilding

def record_names(jdir):
    try:
        return sorted(n for n in os.listdir(jdir) if n.endswith(".json"))
    except OSError:
        return []


def load_records(jdir, names=None):
    if not os.path.isdir(jdir):
        return []
    out = []
    for name in (record_names(jdir) if names is None else names):
        if not name.endswith(".json"):
            continue
        fp = os.path.join(jdir, name)
        try:
            with open(fp) as fh:
                out.append(json.load(fh))
        except (json.JSONDecodeError, OSError) as e:
            die("journal record %s is unreadable (%s).\n"
                "  Inspect or remove it, then re-run. `ccjj forget` cannot take\n"
                "  this one -- it matches by repo path and this record has none\n"
                "  that parses -- so move the file aside by hand." % (fp, e))
    return out


def already_applied(target, original, old, new):
    """True when this edit is ALREADY present in `target`, in its own context.

    A journal record is not retired when something OUTSIDE ccjj commits its path
    -- a bare `jj commit`, a `git commit`, another session's `--also`. The record
    stays live and the next `ccjj commit` replays it a second time. When `old` is
    a SUBSTRING of `new` (extending an identifier, appending an argument -- the
    commonest edit shape) the replacement re-fires on its own output and commits
    text that never existed anywhere: `g2 -> g2-S` applied twice yields
    `g2-S-S`, exit 0, "committed and verified". The post-commit byte check
    cannot catch it, because it verifies transcription of the payload, not that
    the payload corresponds to anything real.

    Context is what distinguishes the two: with enough of it, the applied form
    matches and the unapplied form does not.
    """
    if not new or old == new:
        return False
    i = original.find(old)
    if i < 0:
        return False
    before, after = original[:i], original[i + len(old):]
    for width in (8, 32, 128, 512, 4096):
        b, a = before[-width:], after[:width]
        if (b + new + a) in target and (b + old + a) not in target:
            return True
    return False


def anchored_replace(target, original, old, new, path, label):
    """Apply one recorded edit to `target`, positioned by surrounding context.

    Not a plain str.replace: Edit only guarantees `old` is unique in the text it
    was applied to (`original`), and the target here is @-, which is different
    text. Not a 3-way merge either: git merge-file is line-based, so two sessions
    editing *adjacent* lines produce a false conflict and a legitimate commit
    gets refused. Anchoring only needs the edit's immediate neighbourhood to be
    unique.
    """
    i = original.find(old)
    if i < 0:
        die("journal record for %s is inconsistent: its recorded pre-edit\n"
            "  content does not contain %r.\n"
            "  Remove it with:  ccjj forget %s\n"
            "  That drops this session's records for the path, so the edits they\n"
            "  describe will not be committed -- check `jj status` after."
            % (path, old, path))
    before, after = original[:i], original[i + len(old):]

    n = target.count(old)
    if n == 0:
        if not target:
            # The 1MiB explanation used to be the ONLY one offered, and it is the
            # rare case. The common one: the agent created the file with a Bash
            # heredoc (or a peer created it with Write) and then Edited it, so no
            # record of THIS session holds the file's creation. `claim` refuses
            # (the path has records) and this refusal took every other path in
            # the commit down with it, naming no way out.
            die("%s is not in @- and no record of yours creates it, so there is\n"
                "  nothing to apply your edit to. Usually the file was created\n"
                "  outside Edit/Write -- a Bash heredoc, `cp`, a generator -- or by\n"
                "  another session's Write, and then edited here.\n"
                "  If the whole file is yours:  commit-mine -m \"msg\" --also %s\n"
                "  If another session made it: let it commit first.\n"
                "  (Rarely: the file exceeds `snapshot.max-new-file-size`, 1MiB by\n"
                "  default, and jj refused to snapshot it -- `jj st` warns.)"
                % (path, path))
        die("conflict: cannot place your edit to %s (%s).\n"
            "  The reconstruction does not contain %r.\n"
            "  Most often this means YOU also changed %s through Bash -- a\n"
            "  `sed -i`, a heredoc, a script that rewrote it. Those are not\n"
            "  journaled, so replaying only the recorded edits cannot rebuild the\n"
            "  file, and a later edit anchors on text that is missing. Check with\n"
            "  `ccjj audit`. If the Bash change is yours, `ccjj claim %s` replaces\n"
            "  your records with the file as it is now. Otherwise another session\n"
            "  changed the same region, or your base moved: resolve by hand, or\n"
            "  commit this path wholesale with `--also %s` if nobody else is on it."
            % (path, label, old, path, path, path))
    if n > 1:
        # Grow the window from SMALL to large and take the first width that
        # isolates one site. Match count is monotonically non-increasing in
        # width, so the first 1 is the smallest sufficient anchor and a 0 means
        # the recorded context has diverged, where no wider window can help.
        for width in (1, 2, 4, 8, 16, 32, 64, 128, 256, 1024, 4096):
            pat = before[-width:] + old + after[:width]
            c = target.count(pat)
            if c == 1:
                j = target.index(pat)
                return target[:j] + before[-width:] + new + after[:width] \
                    + target[j + len(pat):]
            if c == 0:
                break
        die("conflict: cannot place your edit to %s (%s) unambiguously.\n"
            "  %r occurs %d times in the committed file and its recorded context\n"
            "  matches none of them uniquely. Resolve by hand." % (path, label, old, n))
    return target.replace(old, new, 1)


def merge3(current, base, ours, path, label):
    """Three-way merge, used for a whole-file Write over existing content."""
    # Exact by definition, and it is what makes a BINARY payload work at all:
    # `git merge-file` refuses binary outright (rc 255, "Cannot merge binary
    # files"), which the returncode > 0 branch below would otherwise report as
    # a content conflict -- a misdiagnosis that sends you looking for an overlap
    # that does not exist.
    if current == base:
        return ours
    if ours == base:
        return current
    with tempfile.TemporaryDirectory(prefix="ccjj-merge-") as d:
        p = {}
        for name, blob in (("cur", current), ("base", base), ("ours", ours)):
            p[name] = os.path.join(d, name)
            with open(p[name], "wb") as fh:
                fh.write(blob)
        r = subprocess.run(
            ["git", "merge-file", "-p", "--diff3",
             "-L", "already committed", "-L", "before your write", "-L", "your write",
             p["cur"], p["base"], p["ours"]], capture_output=True)
    if r.returncode < 0:
        die("git merge-file failed for %s:\n%s" % (path, r.stderr.decode(errors="replace")))
    if r.returncode > 0:
        if b"binary" in r.stderr:
            die("%s is binary and changed in @- as well as here, so the two\n"
                "  versions cannot be merged. Commit it wholesale instead:\n"
                "    commit-mine -m \"msg\" --also %s" % (path, path))
        die("conflict: cannot apply your write to %s (%s) -- the committed file\n"
            "  changed in the same region. Resolve by hand." % (path, label))
    return r.stdout


def blob(rec, key):
    """A record field as bytes.

    Claimed Bash windows are stored base64 because their content comes off disk
    rather than out of a JSON tool payload, so it need not be UTF-8 -- a build
    artifact or a CRLF file would otherwise be unrepresentable.
    """
    v = rec.get(key)
    if v is None:
        return None
    if rec.get("encoding") == "base64":
        return base64.b64decode(v)
    # surrogateescape, not plain encode(): a non-UTF-8 file arrives from the
    # hook payload with lone surrogates, and `v.encode()` raised
    # UnicodeEncodeError -- which blocked every OTHER path in the journal too.
    return v.encode("utf-8", "surrogateescape")


def _record_result(rec):
    """The file as this record left it, or None when that cannot be known."""
    if rec.get("tool") == "Write":
        return blob(rec, "content") or b""
    o, old, new = blob(rec, "original"), rec.get("old"), rec.get("new")
    if o is None or old is None or new is None:
        return None
    ob = old.encode("utf-8", "surrogateescape")
    nb = new.encode("utf-8", "surrogateescape")
    if rec.get("replace_all"):
        return o.replace(ob, nb)
    return o.replace(ob, nb, 1) if o.count(ob) == 1 else None


def _merge_clean(current, base, ours):
    """Three-way merge, or None on any conflict. Never dies: a conflict here
    only means "not already committed", which the caller handles."""
    if current == base:
        return ours
    if ours == base:
        return current
    with tempfile.TemporaryDirectory(prefix="ccjj-merge-") as d:
        p = []
        for name, b in (("cur", current), ("base", base), ("ours", ours)):
            p.append(os.path.join(d, name))
            with open(p[-1], "wb") as fh:
                fh.write(b)
        r = subprocess.run(["git", "merge-file", "-p", *p], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def committed_prefix(content, recs):
    """(k, seen): the first k of this path's records are already in `content`,
    and `seen` lists the records already_applied() alone finds there.

    already_applied() judges one record at a time, so it misses an edit whose
    `new` this session changed again later. The commonest shape: insert a
    section, then edit inside it. The insert's `new` is no longer verbatim in
    @-, its anchor (`old`) still is, and replaying it put the whole section in
    a SECOND time, beside two "already in @-" notes. So judge the file each
    record LEFT, by a three-way merge from the session's starting point: one
    that changes nothing means everything up to that record is committed, even
    when @- also holds other sessions' edits to the same file. Identical
    changes on both sides merge cleanly; peer text that was on disk at the
    start sits in both base and ours, so @-'s version of it wins.

    Gated on already_applied(): with no sign of an external commit, no merge
    runs and replay is exactly what it was.
    """
    base = blob(recs[0], "original")
    if base is None or not content or b"\r\n" in content:
        return 0, []
    seen = []
    for i, r in enumerate(recs):
        o, old, new = blob(r, "original"), r.get("old"), r.get("new")
        if r.get("tool") == "Write" or o is None or old is None or new is None:
            continue
        if already_applied(content, o, old.encode("utf-8", "surrogateescape"),
                           new.encode("utf-8", "surrogateescape")):
            seen.append(i)
    if not seen:
        return 0, seen
    for k in range(len(recs), 0, -1):
        t = _record_result(recs[k - 1])
        if t is not None and _merge_clean(content, base, t) == content:
            return k, seen
    return 0, seen


def build(records, present, pinned):
    """Reconstruct, per path, '@- plus exactly this session's edits'."""
    by_path = {}
    for rec in records:
        if rec.get("path"):
            by_path.setdefault(rec_rel(rec), []).append(rec)

    mine = {}
    for path, recs in by_path.items():
        content = jj("file", "show", "-r", "@-", fs(path)).stdout if path in present else b""

        done, seen = committed_prefix(content, recs)
        if seen and max(seen) >= done:
            # Skipping one applied record while replaying its neighbours is
            # exactly how the duplicate section was made.
            die("conflict: some of your edits to %s are already in @- (committed\n"
                "  outside this session) and others are not, and the committed\n"
                "  file also differs from yours there, so replaying the rest could\n"
                "  duplicate text. Compare with:  jj diff -r @- %s\n"
                "  If @- already has everything you want:  ccjj forget %s\n"
                "  If the file as it is on disk is right:   --also %s"
                % (path, path, path, path))
        if done:
            # One line per path, with counts: a per-record "skipping" note
            # printed above a diff that still re-added text read as "handled".
            print("note: %d of your %d edit(s) to %s are already in @- (committed\n"
                  "  outside this session); replaying only the rest."
                  % (done, len(recs), path), file=sys.stderr)
            recs = recs[done:]

        for rec in recs:
            original = blob(rec, "original")

            if rec.get("tool") == "Write":
                ours = blob(rec, "content") or b""
                if not content:
                    content = ours          # nothing in @- to preserve
                elif original is None:
                    # @- HAS content, but this record has no pre-state to merge
                    # against -- for a claimed window that means the path did
                    # not exist when the window opened. Taking `ours` wholesale
                    # here REVERTED a commit another session had landed in
                    # between, exit 0, verification passing. Worse, the diff
                    # `claim` showed was against b"", so the reader was never
                    # told what was about to be destroyed.
                    die("conflict: %s did not exist when your change began, but\n"
                        "  %s already has content there -- another session committed\n"
                        "  it in between. Committing would overwrite that. Resolve by\n"
                        "  hand, or re-make your change on top of the current file."
                        % (path, pinned[:12]))
                else:
                    content = merge3(content, original, ours, path, pinned[:12])
                continue

            old, new = rec.get("old"), rec.get("new")
            if old is None or new is None:
                continue
            ob = old.encode("utf-8", "surrogateescape")
            nb = new.encode("utf-8", "surrogateescape")

            # Edit reports a CRLF file with every line ending normalized to LF
            # (verified on a real Edit), and writes CRLF back to disk. Replayed
            # as recorded, a multi-line `old` never matched and died blaming
            # Bash, and a multi-line `new` put LF lines into a CRLF file.
            if original is not None and b"\r\n" in content and b"\r" not in original:
                original, ob, nb = (x.replace(b"\n", b"\r\n") for x in (original, ob, nb))

            if original is not None:
                if already_applied(content, original, ob, nb):
                    # Not silent: the path may end up contributing nothing, and
                    # the caller needs to know why its edit "vanished".
                    print("note: an edit to %s is already in @- (committed outside\n"
                          "  this session); skipping it rather than applying it twice."
                          % path, file=sys.stderr)
                    continue
                if rec.get("replace_all"):
                    # The agent asked for every occurrence it could see. A
                    # different count means the file changed materially and
                    # "every" no longer denotes the same set.
                    want, have = original.count(ob), content.count(ob)
                    if have == 0:
                        die("conflict: replace-all edit to %s (%s): %r does not occur\n"
                            "  in the committed file." % (path, pinned[:12], old))
                    if want != have:
                        die("conflict: replace-all mismatch for %s (%s): you saw %d\n"
                            "  occurrence(s) of %r, the committed file has %d. Committing\n"
                            "  would change lines you never saw. Resolve by hand."
                            % (path, pinned[:12], want, old, have))
                    content = content.replace(ob, nb)
                else:
                    content = anchored_replace(content, original, ob, nb, path, pinned[:12])
            else:
                # Pre-edit content missing (an older record). Fall back to direct
                # replacement but refuse when ambiguous rather than guessing.
                if ob not in content:
                    die("conflict: cannot replay an edit to %s onto @- (%s).\n"
                        "  looked for: %r" % (path, pinned[:12], old))
                if not rec.get("replace_all") and content.count(ob) > 1:
                    die("ambiguous replay for %s: %r appears %d times in @- and this\n"
                        "  record predates pre-edit-content capture. Re-make the edit."
                        % (path, old, content.count(ob)))
                content = content.replace(ob, nb) if rec.get("replace_all") \
                    else content.replace(ob, nb, 1)
        mine[path] = content
    return mine


def drop_vanished(records, present):
    """Reconcile records with the filesystem BEFORE build(), which never looks.

    The journal is append-only and a Bash `rm` is journaled nowhere, so nothing
    subtracts a record whose file is gone. build() seeds only from @-, so:
      Write + rm, path new     -> payload for a file that no longer exists; jj
                                  selects nothing; "the commit did not take",
                                  which blames something else and wedges the
                                  WHOLE session commit (an empty Write instead
                                  "verified" a file that is not in the commit)
      Edit + rm, path in @-    -> exit 0, "committed and verified", and the
                                  deleted file RESURRECTED in history
    Ordering matters: this runs on the records build() will replay, after
    --also has removed its paths, so `--also <deleted path>` still works.
    """
    out, vanished = [], {}
    for r in records:
        p = r.get("path") and rec_rel(r)
        if p and not os.path.lexists(os.path.join(ROOT, p)):
            vanished.setdefault(p, []).append(r)
            continue
        out.append(r)
    resurrect = sorted(p for p in vanished if p in present)
    if resurrect:
        die("%s: deleted from the working copy after you edited it, outside\n"
            "  Edit/Write. Replaying your edits would put the file back.\n"
            "  To commit the deletion:      commit-mine -m \"msg\" --also %s\n"
            "  To leave it uncommitted:     ccjj forget %s"
            % (", ".join(resurrect), " --also ".join(resurrect),
               " ".join(resurrect)), 1)
    for p in sorted(vanished):
        print("note: %s was created and then deleted in this session; its %d\n"
              "  record(s) are skipped." % (p, len(vanished[p])), file=sys.stderr)
    return out


def check_new_files_against_disk(mine, present, sid):
    """A path new in this session must reconstruct to what is on disk.

    Write v1, `rm`, re-create v2 through Bash: the v1 record still replays,
    and v1 -- a deleted probe, a scratch credential -- was committed over what
    is on disk, exit 0, "verified", because verification checks transcription,
    not correspondence to reality. For a path absent from @- the only
    legitimate difference is a PEER editing the new file, which leaves a stake.
    Paths already in @- are left to the Bash-window check below.
    """
    bad = []
    for p, want in mine.items():
        if p in present:
            continue
        have = working_copy_bytes(p)
        if have is not None and have != want and not peers_with_a_stake(p, sid):
            bad.append(p)
    if bad:
        die("%s: new in this session, but what is on disk now is not what your\n"
            "  Edit/Write records rebuild -- it was rewritten or re-created\n"
            "  outside them. Committing would commit the recorded version.\n"
            "  To take the file exactly as it is now:  --also %s\n"
            "  To leave it out:                        ccjj forget %s"
            % (", ".join(bad), " --also ".join(bad), " ".join(bad)), 1)


def parent_exec_bits(paths):
    """Executable bit for each path as it exists in @-.

    Needed because the merge tool's $right is seeded from the working copy, so
    another session's `chmod +x` on a file I merely edited would otherwise land
    in my commit.
    """
    if not paths:
        return {}
    r = jj("file", "list", "-r", "@-",
           "-T", 'json(self.path()) ++ "\\t" ++ self.executable() ++ "\\n"',
           *[fs(p) for p in paths], check=False)
    bits = {}
    for line in r.stdout.decode(errors="replace").splitlines():
        if "\t" not in line:
            continue
        raw, _, ex = line.rpartition("\t")
        try:
            bits[json.loads(raw)] = (ex.strip() == "true")
        except json.JSONDecodeError:
            continue
    return bits


# ---------------------------------------------------------------------- commit

def cmd_commit(args):
    if not args.diff and not args.message:
        die("-m/--message is required unless --diff")
    sid = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    if not sid:
        die("no --session and CLAUDE_SESSION_ID is unset")

    caller_cwd = os.getcwd()
    jdir = os.path.join(journal_root(), repo_key(ROOT), sid)
    if args.diff:
        # A preview must not change state, so it reports rather than moves them.
        for old in same_process_journals(ROOT, sid) if may_absorb(args) else ():
            print("note: this preview leaves out edits from before /clear or "
                  "compaction\n  (session %s). A real commit includes them." % old[:8],
                  file=sys.stderr)
    elif may_absorb(args):
        for old in absorb_same_process(ROOT, sid):
            print("note: including this process's edits from before /clear or "
                  "compaction (session %s)." % old[:8], file=sys.stderr)
    # The exact set replayed, so retirement can leave anything newer live.
    loaded = record_names(jdir)
    records = load_records(jdir, loaded)
    if not records and not args.also:
        hint = ""
        if load_windows(jdir) or load_offers(jdir):
            hint = ("\n  This session has Bash windows, though: `ccjj audit` lists what\n"
                    "  they changed, and `ccjj claim <path>` takes one as yours.")
        die("nothing recorded for session %s%s" % (sid, hint), 2)

    # --also is spelled by whoever is standing in some directory, so it resolves
    # against that, not the repo root.
    #
    # rel_literal, not rel: --also names a PATH, and for a symlink that is the
    # link itself. rel() realpaths, so `--also link` silently became
    # `--also target.txt` -- exit 0, the link left uncommitted, and the target
    # (possibly carrying a peer's edit) taken wholesale instead. A link whose
    # target is outside the repo died "outside the repo" instead.
    #
    # Only the last component stays literal. A symlinked DIRECTORY on the way
    # there must resolve: jj tracks `real/f.txt`, so `ln/f.txt` matches nothing
    # and the commit reports success having taken nothing.
    also = [rel_literal(os.path.join(
                os.path.realpath(os.path.dirname(os.path.join(caller_cwd, p))),
                os.path.basename(p))) for p in args.also]

    # Outermost: excludes ai_jj_commit / `g run ci`, which use this same lockdir.
    acquire_shared_lock()
    lockp = os.path.join(ROOT, ".jj", "ccjj.lock")
    with open(lockp, "w") as lock:
        # Two concurrent `jj commit` runs load the same parent operation and
        # create a DIVERGENT change: both print success, both exit 0, one commit
        # lands on a dangling head. A parent-id recheck cannot fix that, so the
        # whole read-modify-commit must be exclusive.
        fcntl.flock(lock, fcntl.LOCK_EX)

        def parent_id():
            ids, err = parent_ids()
            if ids is None:
                if "more than one revision" in err:
                    die("the working copy is a merge, so @- is ambiguous.\n"
                        "  Resolve the merge before committing session work.", 4)
                die("could not read @-:\n%s" % err)
            if len(ids) != 1:
                die("the working copy is a merge (@- resolves to %d revisions),\n"
                    "  so there is no single parent to replay onto. Resolve the\n"
                    "  merge before committing session work." % len(ids), 4)
            return ids[0]

        refused = []     # exit codes of the refusals --diff has previewed through

        def refuse(msg, code):
            # --diff shows the patch even when a real commit would stop, so the
            # preview stays useful. It still exits with the first refusal's code:
            # ai_jj_commit stops on a --diff exit 5, and an exit 0 here would
            # spend a model call on a message and then refuse anyway.
            if not args.diff:
                die(msg, code)
            print("ccjj: warning: a real commit would refuse:\n  " + msg, file=sys.stderr)
            refused.append(code)

        pinned = parent_id()
        # `jj file show` exits 0 while matching nothing, in several distinct
        # ways, so returncode is not a usable presence test.
        present = set(jj("file", "list", "-r", "@-").stdout
                      .decode(errors="surrogateescape").splitlines())

        for p in also:
            if not os.path.lexists(os.path.join(ROOT, p)) and p not in present:
                die("--also %s: no such path in the working copy or in @-.\n"
                    "  --also is resolved against the directory you are standing in\n"
                    "  (%s), not the repo root." % (p, caller_cwd))
        if also and not args.force:
            # --also takes a path WHOLESALE, so a peer's unfinished work in it
            # lands under your message with no hunk-level split. This used to
            # check live peers' RECORDS only, strictly weaker than `claim` on
            # both axes: a Bash-only peer, or an ended-but-uncommitted one, had
            # its bytes committed (or, for a delete, destroyed) at exit 0 --
            # reproduced, and reachable by following claim's own printed advice.
            cov = window_coverage()
            contested = {p: stakes for p in also
                         for stakes in [peers_with_a_stake(p, sid, cov)] if stakes}
            if contested:
                refuse(also_refusal(contested), 1)

        # --also takes a path WHOLESALE, so its journal records must NOT also be
        # replayed. Without this, `--also <path>` could never rescue a path whose
        # records conflict -- which is precisely what the conflict message
        # recommends it for, so the advice was useless. Found by using the tool.
        also_set = set(also)
        scoped = []
        for r in records:
            p = r.get("path")
            if p:
                try:
                    # rec_rel, not rel: build() keys by rec_rel, and an
                    # exclusion filter that keys differently silently fails to
                    # exclude -- which is the double-application above.
                    if rec_rel(r) in also_set:
                        continue
                except SystemExit:
                    pass
            scoped.append(r)

        scoped = drop_vanished(scoped, present)
        mine = build(scoped, present, pinned)
        check_new_files_against_disk(mine, present, sid)
        if not mine and not also:
            die("nothing to commit", 2)

        # BEFORE committing, not after. `ccjj commit` already reported unclaimed
        # paths on the way out, which is too late to do anything about them --
        # the commit has happened. Anything this session's own Bash windows
        # cover but nobody has claimed is recoverable right now, and silently
        # leaving it behind is the exact blind spot windows exist to close.
        shared = set()
        if os.path.isfile(marker(ROOT, MARKER_OPTIN)) and not args.no_claim:
            # `p not in mine` was WRONG, and it cost a partial commit of this
            # tool's own source tree. A path with BOTH journal records and
            # Bash-window changes is in `mine` -- reconstructed from the records
            # alone -- so it was excluded from this check and the Bash half was
            # dropped silently. The reconstruction differing from the working
            # copy is exactly when the warning is most needed.
            #
            # Three more false stops, each of which trained agents to pass
            # --no-claim. A window is a whole-copy tree diff, so it also holds:
            # a file a peer has already committed (hence the `still` test), a
            # file only a peer has edited, and a peer's hunk in a file both
            # sessions edited, which `mine` rightly leaves out. Following the
            # printed `ccjj claim` for that last one committed the peer's
            # unfinished hunk under this session's message, exit 0.
            #
            # `still` applies only outside `mine`. Records that rebuild something
            # other than the disk must stop even when the path equals @-: jj has
            # nothing to select there, so the commit dies with "did not take",
            # where exit 5 gives a `claim` that works.
            cov = window_coverage()
            still = working_copy_paths()
            peer_edits = peer_record_paths(sid)
            uncovered = [p for p, who in cov.items()
                         if sid in who and who[sid] != OFFERED and p not in also
                         and ((p not in mine and (still is None or p in still))
                              or (p in mine and mine[p] != working_copy_bytes(p)))]
            loose = sorted(p for p in uncovered if p not in peer_edits)
            shared = {p for p in uncovered if p in mine and p in peer_edits}
            if loose:
                # STOP, rather than note-and-proceed. Surfacing alone did not
                # work: ai_jj_commit runs preflight-message-commit in one shot,
                # so the agent read the note only after the commit had landed
                # and the best it could do was a second commit. Stopping is what
                # turns "claim it and re-run" into a true statement.
                #
                # Only reachable with a session id, and ai_jj_commit only routes
                # here when one is set -- so a human's `g run ci` never lands in
                # this branch. It takes the whole working copy, which captures
                # Bash-made changes anyway, and has nothing to claim.
                refuse(unclaimed_refusal(loose, sid), 5)
            for p in sorted(shared):
                print("note: %s on disk differs from what this commit takes, and\n"
                      "  session(s) %s have edits there. The difference stays in the\n"
                      "  working copy. Any of it that is your own Bash change stays\n"
                      "  uncommitted and can still be claimed."
                      % (p, ", ".join(s[:8] for s in peer_edits[p])), file=sys.stderr)

        if args.diff:
            for path in sorted(mine):
                base = jj("file", "show", "-r", "@-", fs(path)).stdout if path in present else b""
                with tempfile.TemporaryDirectory(prefix="ccjj-diff-") as d:
                    a, b = os.path.join(d, "a"), os.path.join(d, "b")
                    with open(a, "wb") as fh:
                        fh.write(base)
                    with open(b, "wb") as fh:
                        fh.write(mine[path])
                    subprocess.run(["diff", "-u", "--label", "a/" + path,
                                    "--label", "b/" + path, a, b])
            for path in sorted(also):
                print("(whole path, taken from the working copy) %s" % path)
            if refused:
                sys.exit(refused[0])
            return

        exec_bits = parent_exec_bits([p for p in mine if p in present])

        with tempfile.TemporaryDirectory(prefix="ccjj-") as tmp:
            payload = os.path.join(tmp, "payload")
            modes = {}
            for path, content in mine.items():
                dest = os.path.join(payload, path)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as fh:
                    fh.write(content)   # bytes: text mode mangled CRLF whole-file
                if path in exec_bits:
                    modes[path] = 0o755 if exec_bits[path] else 0o644

            tool = os.path.join(tmp, "pick.py")
            with open(tool, "w") as fh:
                fh.write("#!/usr/bin/env python3\n"
                         "import shutil, os, sys\n"
                         "payload, modes = %r, %r\n"
                         "right = sys.argv[2]\n"
                         "for r in %r:\n"
                         "    d = os.path.join(right, r)\n"
                         "    os.makedirs(os.path.dirname(d), exist_ok=True)\n"
                         # jj materializes a tracked symlink in $right as a REAL
                         # symlink, and copyfile follows it -- so without the
                         # unlink we write through the link, clobbering its
                         # target (which may be outside the repo entirely:
                         # bin/hermes-native points into ~/projects/hermes).
                         # islink, NOT lexists: for a regular file copyfile
                         # writes IN PLACE and thereby preserves the mode $right
                         # arrived with, which is the only thing carrying the
                         # exec bit for a path that does not exist in @- yet.
                         # Unlinking first creates a 0644 file and silently
                         # drops it -- caught by test_new_file_keeps_its_own_exec_bit.
                         "    if os.path.islink(d): os.remove(d)\n"
                         "    shutil.copyfile(os.path.join(payload, r), d)\n"
                         "    if r in modes: os.chmod(d, modes[r])\n"
                         % (payload, modes, list(mine)))
            os.chmod(tool, 0o755)

            # The lock excludes other ccjj runs; a bare `jj` from an agent's Bash
            # or a terminal can still move @- underneath us, and committing a
            # payload built against a stale parent REVERTS what landed between.
            if parent_id() != pinned:
                die("@- moved from %s to %s while preparing the payload.\n"
                    "  Nothing committed; re-run." % (pinned[:12], parent_id()[:12]), 4)

            paths = sorted(set(mine) | set(also))
            also_wanted = {p: disk_state(p) for p in also}
            before_op = jj("op", "log", "--no-graph", "-T", "id", "--limit", "1",
                           "--ignore-working-copy").stdout.decode().strip()
            c = jj("--config", "merge-tools.ccjj.program=%s" % tool,
                   "--config", 'merge-tools.ccjj.edit-args=["$left","$right"]',
                   "commit", "--tool=ccjj", "-m", args.message,
                   *[fs(p) for p in paths], check=False)
            if c.returncode != 0:
                # A failed `jj commit` is NOT a no-op. A `jj util snapshot`
                # racing it -- which ~/.claude/hooks/jj-snapshot.sh runs on every
                # Edit in every session, and which our lock does not exclude --
                # returns rc 0 instantly while the commit dies rc 255 with
                # "Concurrent checkout", leaving the commit on a dangling head
                # and two DIVERGENT changes. Reproduced 3/3. Without this
                # restore the repo stays divergent and nothing says so.
                rollback(before_op)
                die("commit failed (rolled back to operation %s):\n%s"
                    % (before_op[:12], c.stderr.decode(errors="replace")), 4)

            # The byte check below only notices a failure when the payload
            # DIFFERS from @-. A reconstruction that coincidentally equals @-
            # verifies clean no matter what actually happened -- so a commit that
            # selected nothing at all passes it, banks an empty commit under your
            # message, and consumes the journal. Ask jj directly instead.
            e = jj("log", "--no-graph", "-T", "empty", "-r", "@-",
                   "--ignore-working-copy", check=False).stdout.decode().strip()
            # Fail CLOSED. `== "true"` alone meant any failure of this one call
            # -- a renamed keyword in a future jj, a transient error -- silently
            # reopened the exact hole this guard exists to close.
            if e not in ("true", "false"):
                rollback(before_op)
                die("could not tell whether the new commit is empty (got %r).\n"
                    "  Rolled back to operation %s; nothing committed."
                    % (e[:60], before_op[:12]))
            if e == "true":
                rollback(before_op)
                die("nothing of yours differed from @-, so the commit was empty.\n"
                    "  Rolled back to operation %s; the journal is intact.\n"
                    "  Your edits may already be in history via another session."
                    % before_op[:12], 2)

            # MANDATORY. `jj commit --tool` accepts $right only for paths that
            # already differ between @- and the working copy; for any other path
            # it discards the payload, makes an empty commit and reports success.
            # Without this the journal would then be consumed and the work
            # rendered unattributable.
            # The file-type check is for an empty payload: `jj file show` prints
            # nothing for an absent path too, so b"" == b"" passed having
            # committed nothing.
            bad = [p for p, want in mine.items()
                   if jj("file", "show", "-r", "@-", fs(p), check=False).stdout != want
                   or (not want and file_type_at("@-", p) != "file")]
            if bad:
                rollback(before_op)
                die("the commit did not take for: %s\n"
                    "  Rolled back to operation %s; nothing was committed.\n"
                    "  Most likely those paths have no working-copy change to select\n"
                    "  from, because something outside this session already committed\n"
                    "  them. Re-running reproduces this exactly -- it is not transient.\n"
                    "  `ccjj audit` shows whether @- moved. `ccjj forget %s` drops\n"
                    "  just those paths' records, so the session's OTHER, still-\n"
                    "  uncommitted work is not held hostage by them. (`ccjj disown`\n"
                    "  drops ALL of them, which also strands that other work.)"
                    % (", ".join(bad), before_op[:12], " ".join(bad)))

            # jj selects nothing for an --also path it does not track (ignored,
            # or a new file over snapshot.max-new-file-size), and the commit
            # still succeeds when another path made it non-empty.
            bad = [p for p, want in also_wanted.items() if not at_parent_is(p, want)]
            if bad:
                rollback(before_op)
                die("--also did not take for: %s\n"
                    "  Rolled back to operation %s; nothing was committed.\n"
                    "  The path changed during the commit, or jj does not track it\n"
                    "  (ignored, or a new file over its size limit -- `jj st` warns)."
                    % (", ".join(bad), before_op[:12]))

    # Only now that the content is verified present is the journal retired, and
    # moved out of the live namespace rather than renamed beside it so that
    # "scan every claim" sweeps cannot pick it up again. Via retire(), which
    # uniquifies -- the inline version here silently did nothing on a session's
    # SECOND commit of the same day, and the third then failed unrecoverably.
    if os.path.isdir(jdir):
        dest = retire(jdir, sid, "committed")
        if not dest:
            print("warning: could not archive the journal for %s; its records will\n"
                  "  be replayed again by the next commit. Move %s aside by hand."
                  % (sid[:8], jdir), file=sys.stderr)
        else:
            keep_unreplayed(dest, jdir, set(loaded))
            leave_offers(dest, jdir, None if args.no_claim else shared)

    # We moved @- ourselves, so re-baseline the other live sessions -- otherwise
    # our own commit reads to them as someone else moving the base.
    now = jj("log", "--no-graph", "-T", "commit_id", "-r", "@-",
             "--ignore-working-copy", check=False)
    if now.returncode == 0:
        refresh_bases(now.stdout.decode().strip(), old_base=pinned)

    verified = sorted(mine)
    if verified:
        print("committed and verified %d path(s): %s"
              % (len(verified), ", ".join(verified)))
    if also:
        # A separate line: these are checked against the disk, not against a
        # replay of this session's edits, so they prove less. The peer check
        # is what stands between them and another session's bytes.
        print("took %d path(s) wholesale, matched to the working copy: %s"
              % (len(also), ", ".join(sorted(also))))
    unclaimed, _, _, _ = survey()
    if unclaimed:
        cov = window_coverage() if os.path.isfile(marker(ROOT, MARKER_OPTIN)) else {}
        report_unclaimed(unclaimed, prefix="note: ", cov=cov, me=sid)
    maybe_prune()


# ----------------------------------------------------------------------- claim

def working_copy_bytes(path):
    """The path as it is on disk right now, or None if unreadable.

    Used to tell "my reconstruction matches the file" from "the journal has an
    older version of it" -- the difference between a complete commit and one
    that silently drops every Bash-made edit to a file the session also Edited.
    """
    try:
        with open(os.path.join(ROOT, path), "rb") as fh:
            return fh.read()
    except OSError:
        return None


def disk_state(path):
    """(kind, bytes) of an --also path on disk; kind is None when absent.

    A directory returns "dir", which at_parent_is accepts unchecked: --also on
    one takes everything under it. A symlink's target is not compared, because
    `jj file show` returns nothing for a symlink.
    """
    full = os.path.join(ROOT, path)
    if os.path.islink(full):
        return ("symlink", None)
    if os.path.isdir(full):
        return ("dir", None)
    if not os.path.exists(full):
        return (None, None)
    return ("file", working_copy_bytes(path))


def at_parent_is(path, want):
    kind, data = want
    if kind == "dir":
        return True
    at = file_type_at("@-", path) or None
    if at != kind:
        return False
    return kind != "file" or file_bytes("@-", path) == data


def file_bytes(rev, path):
    """Content at a revision, or None if absent. Callers MUST have checked the
    entry type first: `jj file show` exits 0 with EMPTY stdout for a symlink and
    for a directory, so emptiness alone cannot distinguish them from a file."""
    r = jj("file", "show", "-r", rev, fs(path), "--ignore-working-copy", check=False)
    return r.stdout if r.returncode == 0 else None


def file_type_at(rev, path):
    """"file" / "symlink" / ... , or "" when the path is absent.

    `jj file list` always exits 0, so the signal is stdout: empty <=> absent.
    """
    r = jj("file", "list", "-r", rev, "-T",
           'json(self.path()) ++ "\\t" ++ self.file_type() ++ "\\n"',
           fs(path), "--ignore-working-copy", check=False)
    for line in r.stdout.decode(errors="replace").splitlines():
        raw, _, kind = line.rpartition("\t")
        try:
            if json.loads(raw) == path:
                return kind.strip()
        except json.JSONDecodeError:
            continue
    return ""


def cmd_claim(args):
    """Turn one Bash-window-covered path into an ordinary journal record.

    This is the whole point of the offer model: a window's delta may contain
    bytes this session never wrote, and no local rule can tell which. Printing
    the diff and requiring an explicit claim puts the one detector that works --
    a reader -- in the loop, and keeps `ccjj commit` exact by construction.
    """
    sid = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    if not sid:
        die("no --session and CLAUDE_SESSION_ID is unset")
    jdir = os.path.join(journal_root(), repo_key(ROOT), sid)
    if may_absorb(args):
        absorb_same_process(ROOT, sid)
    path = rel_literal(args.path)
    wins = claimable_windows(jdir, path)
    if not wins:
        hint = ("  A window needs two Bash calls with a working-copy change between\n"
                "  them, and `commit-mine` archives windows when it commits. After\n"
                "  that, only paths a commit left behind can still be claimed."
                if os.path.isfile(marker(ROOT, MARKER_OPTIN))
                else "  Enable them with `ccjj bash-windows on`.")
        die("no Bash windows are live for session %s, and none were kept for %s.\n%s"
            % (sid[:8], path, hint), 2)

    span = (wins[0]["before"], wins[-1]["after"])
    delta = window_delta(*span)
    if delta is None:
        die("this session's Bash windows no longer resolve (%s..%s).\n"
            "  `jj op abandon` discards them instantly. Nothing to claim."
            % (span[0][:12], span[1][:12]), 2)
    entry = next((e for e in delta if e[2] == path or e[1] == path), None)
    if entry is None:
        die("no Bash window of yours changed %s.\n"
            "  `ccjj audit` lists what they did change." % path, 2)
    status, src, tgt, kind = entry

    # BEFORE the delete/rename redirects. Those print an `--also` command, and
    # when this check sat below them it was never reached for exactly the
    # operations --also exists for: a delete of a Bash-only peer's file was
    # handed straight to --also, which (then) did not look either.
    cov = window_coverage()
    stakes = {}
    for p in {path, src, tgt} - {None}:
        # Records outrank a window. A plain update() let a window-only result
        # for one half of a rename overwrite the records result for the other.
        for s, v in peers_with_a_stake(p, sid, cov).items():
            if s not in stakes or v[1] == STAKE_RECORDS:
                stakes[s] = v
    if stakes and not args.force:
        recs, spans = split_stakes(stakes)
        why = []
        if recs:
            why.append("%s is also claimed by session(s) %s.\n"
                       "  Their bytes can be in this window, and claiming it would commit\n"
                       "  their work under your name."
                       % (path, describe_stakes(recs)))
        if spans:
            why.append("%s changed during the Bash span of session(s) %s.\n%s\n"
                       "  If they did, claiming it would commit their work under your name."
                       % (path, describe_stakes(spans), SPAN_NOTE))
        die("%s\n  Re-run with --force only if the diff below is genuinely all yours.\n"
            "  If any of it is not, leave it out with `commit-mine --no-claim`.\n%s"
            % ("\n".join(why),
               unified(file_bytes(span[0], path), file_bytes(span[1], path), path)), 1)

    if status == "removed":
        die("%s was deleted inside a Bash window.\n"
            "  A whole-path change has no hunks to split, so commit it with:\n"
            "    commit-mine -m \"msg\" --also %s" % (path, path), 1)
    if status == "renamed":
        # src and tgt, never `path` twice: claiming the OLD half printed
        # "x was renamed from x" and an --also pair that committed the delete
        # with no add, orphaning the new file.
        die("%s was renamed to %s inside a Bash window.\n"
            "  A rename has no hunks to split; commit both halves wholesale:\n"
            "    commit-mine -m \"msg\" --also %s --also %s"
            % (src, tgt, src, tgt), 1)
    if kind != "file":
        die("%s is a %s, not a regular file.\n"
            "  `jj file show` returns empty for those, so claiming it would\n"
            "  commit a zero-byte regular file over it. Use --also instead."
            % (path, kind or "missing entry"), 1)

    # Replaying a claimed whole-file blob AND the edits already inside it would
    # apply the edits twice -- silently, for the commonest (insertion-shaped)
    # Edit, which duplicates a hunk rather than failing to match. Refusing that
    # made a cycle: commit said "claim it", claim said "commit first".
    earlier = [n for n in record_names(jdir)
               for r in load_records(jdir, [n])
               if r.get("path") and rec_rel(r) == path]
    if earlier:
        supersede_records(jdir, path, earlier, span, args.dry_run)
        return

    # Narrow to the tightest run of windows that actually changed this path, so
    # the claim carries as little foreign content as it can.
    bounds = [wins[0]["before"]] + [w["after"] for w in wins]
    blobs = [file_bytes(b, path) for b in bounds]
    lo = hi = None
    for i in range(len(blobs) - 1):
        if blobs[i] != blobs[i + 1]:
            if lo is None:
                lo = i
            hi = i + 1
    if lo is None or hi is None:
        die("no Bash window changed the contents of %s" % path, 2)
    before_id, after_id = bounds[lo], bounds[hi]
    # Re-check at the narrowed endpoints: the span endpoints were regular files,
    # but the path could have been a symlink partway through.
    for label, rev in (("start", before_id), ("end", after_id)):
        t = file_type_at(rev, path)
        if t not in ("file", "") or (label == "end" and t == ""):
            die("%s is a %s at the %s of its window; refusing to claim it."
                % (path, t or "missing entry", label), 1)

    original, content = blobs[lo], blobs[hi]
    if content is None:
        die("could not read %s at %s; nothing claimed." % (path, after_id[:12]), 1)

    print(unified(original, content, path), end="")
    if args.dry_run:
        print("(dry run -- nothing recorded)")
        return

    # Sorts at the window's own time, so a later Edit to the same file replays
    # on top of it rather than underneath.
    write_claim(jdir, path, original, content, [before_id, after_id],
                wins[max(hi - 1, 0)]["t_ns"])
    print("claimed %s (%s..%s) -- it will be included by `commit-mine`."
          % (path, before_id[:12], after_id[:12]))


def write_claim(jdir, path, original, content, window, t_ns, **extra):
    rec = {"schema": SCHEMA, "tool": "Write", "path": os.path.join(ROOT, path),
           "old": None, "new": None, "replace_all": False,
           "content": base64.b64encode(content).decode(),
           "original": base64.b64encode(original).decode() if original is not None else None,
           "encoding": "base64", "claimed": True,
           "window": window, "t_ns": t_ns, **extra}
    name = "%019d-%d.json" % (t_ns, os.getpid())
    fd = os.open(os.path.join(jdir, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(rec, fh)


def supersede_records(jdir, path, names, span, dry_run):
    """Replace this session's records for `path` with one whole-file claim.

    The working copy holds the Edits and the Bash change together, and @- is
    what they all sit on, so "@- to disk" is the exact delta. The caller has
    already refused a path another session has a stake in, and the printed diff
    is the check on anything else. The old records go to forgotten/, like
    `ccjj forget`, before the new one is written: a crash between the two then
    loses a record the working copy still covers, instead of applying it twice.
    """
    if os.path.islink(os.path.join(ROOT, path)):
        die("%s is now a symlink on disk; refusing to claim it." % path, 1)
    content = working_copy_bytes(path)
    if content is None:
        die("could not read %s from the working copy; nothing claimed." % path, 1)
    kind = file_type_at("@-", path)
    if kind not in ("file", ""):
        die("%s is a %s in @-; refusing to claim it." % (path, kind), 1)
    original = file_bytes("@-", path) if kind else None

    print(unified(original, content, path), end="")
    if dry_run:
        print("(dry run -- nothing recorded; would replace %d record(s))" % len(names))
        return

    forgotten = os.path.join(jdir, "forgotten")
    os.makedirs(forgotten, mode=0o700, exist_ok=True)
    for n in names:
        os.replace(os.path.join(jdir, n), os.path.join(forgotten, n))
    # Now, not a window's time: these bytes are the disk as of this moment.
    write_claim(jdir, path, original, content, list(span), time.time_ns(),
                superseded=names)
    print("claimed %s, replacing %d earlier record(s) with the file as it is now.\n"
          "  It will be included by `commit-mine`." % (path, len(names)))


STAKE_RECORDS = "records"        # Edit/Write records name this path
STAKE_WINDOW = "window only"     # only a Bash window covers it

SPAN_NOTE = ("  A Bash span runs from a session's first Bash call to its last, so that\n"
             "  session's commands may not have touched this path.")


def stakes_on(path, cov=None, skip=None):
    """{session id: (state, kind)} for every session with a stake in path.

    state is "live" or "ended". kind is STAKE_RECORDS when the session has
    journal records for the path, else STAKE_WINDOW, and a session with both is
    STAKE_RECORDS. The two are different evidence: a record says the session
    wrote this file, while a window only says the path changed somewhere between
    that session's first and last Bash call -- a session idle between two calls
    still counts. `claim`, `--also` and `who` all read this one classification.
    """
    cov = window_coverage() if cov is None else cov
    base_dir = os.path.join(journal_root(), repo_key(ROOT))
    if not os.path.isdir(base_dir):
        return {}
    out = {}
    for s in sorted(os.listdir(base_dir)):
        d = os.path.join(base_dir, s)
        if s in ("archive", skip) or not os.path.isdir(d):
            continue
        if path in claims_of(s):
            kind = STAKE_RECORDS
        elif s in cov.get(path, ()):
            kind = STAKE_WINDOW
        else:
            continue
        # A session listed here has a .json or a .win, so has_activity holds
        # and session_is_live is the whole liveness test.
        out[s] = ("live" if session_is_live(d) else "ended", kind)
    return out


def peers_with_a_stake(path, me, cov=None):
    """{session id: (state, kind)} for every OTHER session with a stake in path.

    The one definition used by both `claim` and `--also`. A stake is an
    Edit/Write record OR a Bash window of the peer's own, and an ENDED peer
    counts too: its uncommitted work is the ordinary residue of a session that
    exited without committing, and taking it wholesale is just as wrong. The two
    callers used to disagree on both axes, and --also -- the weaker one -- is
    where claim's refusals send you.
    """
    return stakes_on(path, cov, skip=me)


def split_stakes(stakes):
    """(the peers with records, the peers with only a Bash window)."""
    recs = {s: v for s, v in stakes.items() if v[1] == STAKE_RECORDS}
    return recs, {s: v for s, v in stakes.items() if s not in recs}


def peer_record_paths(me):
    """{path: [session ids]} for every OTHER session's Edit/Write records.

    Ended sessions count: their uncommitted hunks are on disk just the same.
    """
    base = os.path.join(journal_root(), repo_key(ROOT))
    out = {}
    if os.path.isdir(base):
        for s in sorted(os.listdir(base)):
            if s not in ("archive", me) and os.path.isdir(os.path.join(base, s)):
                try:
                    paths = claims_of(s)
                except SystemExit:
                    continue      # a peer's torn record must not block this commit
                for p in paths:
                    out.setdefault(p, []).append(s)
    return out


def whole_path_diff(path):
    """What --also would commit for `path`, against @-."""
    kind, data = disk_state(path)
    if kind not in ("file", None) or file_type_at("@-", path) not in ("file", ""):
        return "(%s is not a regular file, so there is no diff to show)\n" % path
    return unified(file_bytes("@-", path), data, path)


def describe_stakes(stakes):
    return ", ".join("%s (%s)" % (s[:8], v[0]) for s, v in sorted(stakes.items()))


def stake_summary(stakes):
    recs, spans = split_stakes(stakes)
    parts = []
    if recs:
        parts.append("records: " + describe_stakes(recs))
    if spans:
        parts.append("Bash span only: " + describe_stakes(spans))
    return "; ".join(parts)


def identical_moves(paths):
    """The members of `paths` that are one half of a move with unchanged bytes.

    Pairs come from jj's own rename detection, as the window delta's do, so a
    file that was moved and then edited does not match. Information for the
    reader only: nothing may decide whether to refuse on this.
    """
    out = set()
    for status, src, tgt, kind in window_delta("@-", "@") or ():
        if status != "renamed" or kind != "file" or not {src, tgt} & set(paths):
            continue
        # file_bytes needs the type checked first: `jj file show` exits 0 with
        # empty stdout for a symlink, which would match an empty file.
        if (file_type_at("@-", src) == "file"
                and not os.path.islink(os.path.join(ROOT, tgt))
                and file_bytes("@-", src) == working_copy_bytes(tgt)):
            out |= {src, tgt}
    return out


def also_refusal(contested):
    """The refusal for --also paths in which another session has a stake."""
    moves = identical_moves(contested)
    rows = "\n".join("    %s  (%s)%s" % (p, stake_summary(s),
                                         "  [move, bytes identical to @-]" if p in moves else "")
                     for p, s in sorted(contested.items()))
    kinds = {v[1] for stakes in contested.values() for v in stakes.values()}
    if STAKE_RECORDS in kinds:
        lead = ("--also would take these wholesale, but another session has\n"
                "  a stake in them:")
        tail = "  Their unfinished work would be committed under your message.\n"
    else:
        lead = ("--also would take these wholesale, and another session's Bash\n"
                "  commands ran during the span that changed them:")
        tail = ""
    if STAKE_WINDOW in kinds:
        tail += SPAN_NOTE + "\n  If they did, their work would be committed under your message.\n"
    return ("%s\n%s\n%s  Re-run with --force only if you are sure, and never for a path\n"
            "  another session has records on. What would be committed:\n%s"
            % (lead, rows, tail, "".join(whole_path_diff(p) for p in sorted(contested))))


def whole_path_changes(sid):
    """Groups of paths this session's Bash windows moved or deleted, in delta order.

    `claim` refuses these, and they go through --also instead. A rename is one
    group of both halves, because a per-path --also is dangerous: `--also a.txt`
    alone commits the delete and strands the add. From the window delta and not
    window_coverage(), which keeps the status per path but not the partner.
    """
    span = window_span(os.path.join(journal_root(), repo_key(ROOT), sid))
    delta = window_delta(*span) if span else None
    groups = []
    for status, src, tgt, _ in delta or ():
        if status == "renamed":
            groups.append((src, tgt))
        elif status == "removed":
            groups.append((tgt,))
    still = working_copy_paths()
    if still is None:
        return groups
    # A half already committed cannot be named: --also dies on a path that is in
    # neither the working copy nor @-, so one such half voids the whole command.
    trimmed = [tuple(p for p in g if p in still) for g in groups]
    return [g for g in trimmed if g]


def also_advice(paths, groups):
    """One `commit-mine --also` line for `paths` and every partner they need."""
    want, picked, grew = set(paths), [], True
    while grew:     # repeat until stable: two renames can share a path
        grew = False
        for g in groups:
            if g not in picked and want & set(g):
                picked.append(g)
                want |= set(g)
                grew = True
    args = list(dict.fromkeys(p for g in picked for p in g))
    return 'commit-mine -m "msg" ' + " ".join("--also " + shlex.quote(p) for p in args)


def unclaimed_refusal(loose, sid):
    """The exit-5 message: what to claim, and what must go through --also."""
    groups = whole_path_changes(sid)
    moved = {p for g in groups for p in g}
    claimable = [p for p in loose if p not in moved]
    whole = [p for p in loose if p in moved]
    msg = ("%d path(s) changed inside your Bash windows are not claimed,\n"
           "  and would NOT be committed:\n%s\n"
           % (len(loose), "\n".join("    " + p for p in loose)))
    if claimable:
        msg += ("  Claim the ones that are yours, then re-run:\n%s\n"
                % "\n".join("    ccjj claim " + p for p in claimable))
    if whole:
        msg += ("  Moves and deletes cannot be claimed. Commit the ones that are\n"
                "  yours whole, with both halves of every move:\n    %s\n"
                % also_advice(whole, groups))
    return msg + "  Or pass --no-claim to commit without them; they stay claimable."


def claims_of(sid):
    paths = set()
    for rec in load_records(os.path.join(journal_root(), repo_key(ROOT), sid)):
        if rec.get("path"):
            try:
                paths.add(rec_rel(rec))
            except SystemExit:
                continue
    return paths


def unified(a, b, path):
    with tempfile.TemporaryDirectory(prefix="ccjj-claim-") as d:
        pa, pb = os.path.join(d, "a"), os.path.join(d, "b")
        with open(pa, "wb") as fh:
            fh.write(a or b"")
        with open(pb, "wb") as fh:
            fh.write(b or b"")
        r = subprocess.run(["diff", "-u", "--label", "a/" + path,
                            "--label", "b/" + path, pa, pb], capture_output=True)
    return r.stdout.decode(errors="replace")


def cmd_bash_windows(args):
    m = marker(ROOT, MARKER_OPTIN)
    if args.action == "on":
        open(m, "w").close()
        print("Bash windows ON for %s.\n"
              "  Changes made through Bash are now offered by `ccjj audit`;\n"
              "  nothing is attributed until you run `ccjj claim <path>`." % ROOT)
    elif args.action == "off":
        for f in (m, marker(ROOT, MARKER_BUSY)):
            if os.path.exists(f):
                os.remove(f)
        print("Bash windows OFF for %s." % ROOT)
    else:
        on = os.path.isfile(m)
        print("Bash windows: %s" % ("on" if on else "off"))
        if on:
            print("contended:    %s" % os.path.isfile(marker(ROOT, MARKER_BUSY)))


# ----------------------------------------------------------------------- audit

DELTA_T = ('self.status() ++ "\\t" ++ json(self.source().path()) ++ "\\t" '
           '++ json(self.target().path()) ++ "\\n"')


def parse_delta(stdout):
    paths = set()
    for line in stdout.decode(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        for raw in parts[1:3]:
            try:
                paths.add(json.loads(raw))
            except json.JSONDecodeError:
                pass
    return paths


def working_copy_paths():
    """Paths that differ between @- and @ as of the last snapshot, or None.

    None on failure, and callers then treat every path as still changed, so a
    jj error costs a stop or an extra offer rather than lost work.
    """
    r = jj("--ignore-working-copy", "diff", "--from", "@-", "--to", "@",
           "-T", DELTA_T, check=False)
    return parse_delta(r.stdout) if r.returncode == 0 else None


def survey():
    """(paths changed in the working copy that no live session claims, claims)."""
    # One call that both snapshots and reports the id -- half the latency and one
    # lock instead of two.
    wc = jj("log", "-r", "@", "--no-graph", "-T", "commit_id").stdout.decode().strip()
    ids, _ = parent_ids()
    if ids is None:
        return [], {}, {}, {}
    if len(ids) != 1:
        # Reporting an empty delta here would say "nothing unclaimed" at the
        # moment the repo is in its most confusing state -- and `ccjj commit`
        # refuses at exactly the same moment, so the two would disagree.
        die("the working copy is a merge (@- resolves to %d revisions), so there\n"
            "  is no single parent to compare against. Resolve the merge first."
            % len(ids), 4)
    parent_id = ids[0]
    r = jj("--ignore-working-copy", "diff", "--from", parent_id,
           "--to", wc, "-T", DELTA_T, check=False)
    delta = parse_delta(r.stdout)

    claims, stale, drifted = {}, {}, {}
    base = os.path.join(journal_root(), repo_key(ROOT))
    if os.path.isdir(base):
        for sid in sorted(os.listdir(base)):
            d = os.path.join(base, sid)
            if sid == "archive" or not os.path.isdir(d):
                continue
            paths = set()
            for rec in load_records(d):
                if rec.get("path"):
                    try:
                        paths.add(rec_rel(rec))
                    except SystemExit:
                        continue
            if paths:
                (claims if session_is_live(d) else stale)[sid] = paths
            # Drift is about the repo's history moving unexpectedly, not about
            # liveness: a dead session's base moving means its orphaned work was
            # swept into someone's commit, which is just as worth hearing.
            #
            # The one exception is a session that ended with an empty journal:
            # a single Bash call stamps .base and leaves nothing else, so it had
            # no work to sweep. has_activity, not "has records": an ended session
            # with Bash windows and no records can still have swept work. And
            # owner_alive, not session_is_live, which is False for ANY journal
            # with no activity and so could not tell ended from just started.
            b = read_base(d)
            if b and b != parent_id and (has_activity(d) or owner_alive(d)):
                drifted[sid] = b

    # Only a LIVE session's claim suppresses a warning. A dead session's paths
    # are exactly what you want to hear about: nobody is going to commit them.
    claimed = set()
    for paths in claims.values():
        claimed |= paths
    # A session that has just committed no longer appears at all -- its journal
    # was moved to archive/ precisely so sweeps cannot re-count it.
    return sorted(delta - claimed), claims, stale, drifted


def rollback(before_op):
    """Restore, and say so LOUDLY if the restore itself failed.

    Every caller prints "rolled back ... the journal is intact" and stops. The
    commit-failure site is reached precisely when the repo is already in a bad
    state, which is when a restore is most likely to fail -- and a false
    reassurance there is worse than no message at all.
    """
    r = jj("op", "restore", before_op, check=False)
    if r.returncode != 0:
        print("ccjj: ROLLBACK FAILED. The repo is NOT back at operation %s.\n"
              "  Run `jj op restore %s` by hand and check `jj op log`.\n%s"
              % (before_op[:12], before_op, r.stderr.decode(errors="replace")),
              file=sys.stderr)
    return r.returncode == 0


DRIFT_LIMIT = 40


def drift_undos(bases):
    """{base_id: (operation to restore to, the operation that moved @-)}.

    Nothing records who moved @-, so the only way to find out is to replay the
    operation log asking "was @- still this here?". The newest operation that
    says yes is the last good state; the one immediately after it is the culprit.

    ONE walk for every base, not one per base. Each probe is a jj process
    (~40ms), so per-base walking made `ccjj audit` take 4s on this repo with two
    drifted sessions -- and the nudge tells every agent to run `ccjj audit`.
    """
    out: dict = {b: (None, None) for b in bases}
    pending = set(bases)
    r = jj("op", "log", "--no-graph", "-T", 'id ++ "\\t" ++ description ++ "\\n"',
           "--limit", str(DRIFT_LIMIT), "--ignore-working-copy", check=False)
    if r.returncode != 0:
        return out
    culprit = None
    for line in r.stdout.decode(errors="replace").splitlines():
        if not pending:
            break
        oid, _, desc = line.partition("\t")
        oid = oid.strip()
        if not oid or not oid.strip("0"):     # the root operation resolves nothing
            break
        at = jj("--at-op", oid, "log", "--no-graph", "-T", "commit_id", "-r", "@-",
                "--ignore-working-copy", check=False)
        val = at.stdout.decode().strip() if at.returncode == 0 else ""
        if val in pending:
            out[val] = (oid, culprit)
            pending.discard(val)
        culprit = (oid, desc.strip())
    return out


def report_drift(drifted, me=""):
    """Report @- moving under a session.

    Ended sessions get one line. Their work really can be inside a stray commit
    and this is then the only signal, but naming a culprit and an undo for them
    was wrong: their bases are usually older than the walk can reach, and a
    restore would rewind every live session. Skipping them also spares a full
    40-operation walk on every audit.
    """
    base_dir = os.path.join(journal_root(), repo_key(ROOT))
    ended_with_work = 0
    current = {}
    for sid, base in drifted.items():
        # owner_alive, not session_is_live, as in survey(): a session that has
        # only just started has an empty journal. survey() has already dropped
        # an ended session with no work, so every ended one here has some.
        if sid == me or owner_alive(os.path.join(base_dir, sid)):
            current[sid] = base
        else:
            ended_with_work += 1
    print("", file=sys.stderr)
    if ended_with_work:
        print("%d ended session(s) with uncommitted work: @- has moved since they\n"
              "  started, so some of that work may already be in history. No undo is\n"
              "  offered and no action is needed; `ccjj prune` retires these after 48\n"
              "  hours idle." % ended_with_work, file=sys.stderr)
    if not current:
        return
    drifted = current
    for sid, base in sorted(drifted.items()):
        print("session %s started from %s, but @- has moved."
              % (sid[:8], base[:12]), file=sys.stderr)
    print("  Something other than `ccjj commit` created a commit -- a bare\n"
          "  `jj commit`/`jj new`/`git commit`. Session work may now be inside it.",
          file=sys.stderr)
    undos = drift_undos(sorted(set(drifted.values())))
    # Naming a culprit for these was a contradiction: without a restore point we
    # never found where the base was still current, so the oldest operation we
    # happened to examine is not evidence of anything. One line for all of them.
    # prune is named by its gate, because it refuses a journal idle under 48h.
    no_undo = sum(1 for base in undos if not undos[base][0])
    if no_undo:
        print("  No undo is available for %d older base(s), and no action is needed; "
              "`ccjj prune` retires these after 48 hours idle." % no_undo, file=sys.stderr)
    for base in sorted(set(drifted.values())):
        restore, culprit = undos[base]
        if not restore:
            continue
        if culprit:
            print("  %s was moved by operation %s (%s)."
                  % (base[:12], culprit[0][:12], culprit[1][:60]), file=sys.stderr)
        print("  Undo with:  jj op restore %s" % restore[:12], file=sys.stderr)
        print("    That rewinds the WHOLE repo to before it, so it also undoes\n"
              "    anything else that happened since. Read `jj op log` first.",
              file=sys.stderr)


def status_label(status):
    return "left by an earlier commit" if status == OFFERED else status


def report_unclaimed(unclaimed, prefix="", cov=None, me=""):
    cov = cov or {}
    print("%s%d working-copy path(s) claimed by no session:" % (prefix, len(unclaimed)),
          file=sys.stderr)
    if len(unclaimed) > 20 and not cov:
        groups = {}
        for p in unclaimed:
            groups.setdefault(p.split("/")[0], 0)
            groups[p.split("/")[0]] += 1
        for g, n in sorted(groups.items(), key=lambda kv: -kv[1]):
            print("    %-40s %d" % (g, n), file=sys.stderr)
    else:
        groups = whole_path_changes(me) if me and cov else []
        moved = {p for g in groups for p in g}
        for p in unclaimed:
            print("    " + p, file=sys.stderr)
            who = cov.get(p) or {}
            if me and me in who:
                if p in moved:
                    print("        changed inside your Bash window (%s) -- a move or "
                          "delete cannot be claimed, see below" % status_label(who[me]),
                          file=sys.stderr)
                else:
                    print("        changed inside your Bash window (%s) -- recoverable:"
                          % status_label(who[me]), file=sys.stderr)
                    print("        ccjj claim %s   # after reading the diff it prints"
                          % p, file=sys.stderr)
            for sid, status in sorted(who.items()):
                if sid != me:
                    print("        also inside session %s's Bash window (%s)"
                          % (sid[:8], status_label(status)), file=sys.stderr)
        mine = [p for p in unclaimed if p in moved]
        if mine:
            print("  To commit your moves and deletes whole, with both halves of every move:\n"
                  "    %s" % also_advice(mine, groups), file=sys.stderr)
    print("  These will NOT be committed by any `ccjj commit`. They were made\n"
          "  outside Edit/Write (a Bash command, an editor), or by a session\n"
          "  whose hooks were disabled -- note `claude-p` disables hooks unless\n"
          "  CLAUDE_P_SAFE=0.", file=sys.stderr)
    if not cov and unclaimed:
        print("  `ccjj bash-windows on` makes Bash-made changes recoverable.",
              file=sys.stderr)


def cmd_who(args):
    """List every session with journal records or a Bash window on one path.

    Read-only, so it neither calls survey() nor absorb_same_process(): it reads
    the journals and asks jj only with --ignore-working-copy, because a snapshot
    landing inside another session's `jj commit --tool` kills it.
    """
    me = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    path = rel_literal(args.path)
    stakes = stakes_on(path)
    if not stakes:
        print("no session has journal records or a Bash window on %s" % path)
        return
    print(path)
    for s, (state, kind) in sorted(stakes.items()):
        print("  %-8s  %-5s  %s%s"
              % (s[:8], state, kind, "  (this session)" if s == me else ""))


def cmd_audit(args):
    # survey() deliberately snapshots (one call that both snapshots and reports
    # the id). A snapshot landing inside another session's `jj commit --tool`
    # kills it with "Concurrent checkout" -- and the nudge tells every agent to
    # run `ccjj audit`, so this collision is actively encouraged.
    if os.path.isdir(os.path.join(os.path.expanduser("~/.local/state/ai-jj-commit"),
                                  repo_key(ROOT) + ".lock")):
        die("a commit is in progress here; retry in a moment.", 4)
    me = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    if may_absorb(args):
        absorb_same_process(ROOT, me)
    unclaimed, claims, stale, drifted = survey()
    if args.porcelain:
        sys.stdout.write("\0".join(unclaimed))
        return
    for sid, paths in sorted(claims.items()):
        print("session %s (live) claims %d path(s)" % (sid[:8], len(paths)))
    for sid, paths in sorted(stale.items()):
        print("session %s (ended, never committed) left %d claimed path(s) -- "
              "`ccjj prune` will retire it" % (sid[:8], len(paths)))
    # A session that has only made Bash changes has windows but no records, so
    # claims/stale are both empty while it is very much working here.
    base = os.path.join(journal_root(), repo_key(ROOT))
    win_only = sorted(
        sid for sid in (os.listdir(base) if os.path.isdir(base) else [])
        if sid != "archive" and sid not in claims and sid not in stale
        and os.path.isdir(os.path.join(base, sid))
        and (load_windows(os.path.join(base, sid))
             or load_offers(os.path.join(base, sid))))
    for sid in win_only:
        print("session %s has Bash windows but no edits yet -- "
              "nothing of its own to commit until something is claimed" % sid[:8])
    if not claims and not stale and not win_only:
        print("no session journals for this repo")
    if drifted:
        # Without this, a stray `jj new` or `git commit` swept the work into a
        # commit and audit still reported all-clear, because the @- vs @ delta
        # had gone empty.
        report_drift(drifted, me)
    if unclaimed:
        cov = window_coverage() if os.path.isfile(marker(ROOT, MARKER_OPTIN)) else {}
        report_unclaimed(unclaimed, cov=cov, me=me)
    elif not drifted:
        print("nothing unclaimed in the working copy")


# ----------------------------------------------------------------------- prune

def retire(jdir, sid, reason):
    """Move a session journal out of the live namespace."""
    archive = os.path.join(journal_root(), repo_key(ROOT), "archive",
                           datetime.date.today().isoformat())
    os.makedirs(archive, mode=0o700, exist_ok=True)
    dest = os.path.join(archive, sid)
    if os.path.exists(dest):
        dest += "-" + reason
    # Counter, not "give up after one suffix". Committing twice in a day from
    # one session is the NORMAL pattern, and a silent failure to archive leaves
    # already-committed records live: the next commit replays them, jj selects
    # nothing, and the mandatory verification fails with a message blaming the
    # working copy. The session is then wedged until it is disowned.
    n, base = 2, dest
    while os.path.exists(dest):
        dest = "%s-%d" % (base, n)
        n += 1
        if n > 1000:
            return False
    os.rename(jdir, dest)
    return dest


def keep_unreplayed(archived, jdir, replayed):
    """Move back to the live journal what the commit did not replay.

    retire() moves the whole directory, and the record-edit hook takes no lock,
    so an Edit that landed between load_records() and retire() -- a subagent
    (same session id) or the agent itself while commit-mine ran in the
    background -- was archived without ever being committed. Reproduced: the
    edit stayed on disk, the session's next commit said "nothing recorded".

    Records only. .last must not come back: commit-mine is itself a Bash call,
    so its hook would open a window from the old @ over edits this commit just
    took, and the next commit would stop with exit 5 on files already in @-.
    .owner must not come back either: after a resume it names the dead process,
    and an absent .owner lets the next hook stamp the live one.
    """
    back = [n for n in record_names(archived) if n not in replayed]
    if not back:
        return
    os.makedirs(jdir, mode=0o700, exist_ok=True)
    for n in back:
        os.replace(os.path.join(archived, n), os.path.join(jdir, n))
    print("note: %d edit(s) recorded while this commit ran were not part of\n"
          "  it; they stay live for the next commit-mine." % len(back),
          file=sys.stderr)


def other_live_sessions(me):
    base = os.path.join(journal_root(), repo_key(ROOT))
    if not os.path.isdir(base):
        return []
    out = []
    for sid in sorted(os.listdir(base)):
        d = os.path.join(base, sid)
        if sid == "archive" or sid == me or not os.path.isdir(d):
            continue
        # has_activity, not a .json-only test: a peer doing ONLY Bash work has
        # windows and no records, and in an opted-in contended checkout that is
        # the likeliest peer there is. The .json test made it invisible to
        # `should-scope` (so `g run ci` did a whole-copy commit that swallowed
        # its work) and to `claim`'s shared-path guard, while `nudge` -- which
        # already used has_activity -- was announcing it.
        if has_activity(d) and session_is_live(d):
            out.append(sid)
    return out


def cmd_should_scope(args):
    """Exit 0 when a commit here ought to be session-scoped.

    Called by ai_jj_commit so the routing decision lives in one place. Scoping
    only helps when someone else is actually working here: with a single session
    a whole-working-copy commit is better, because it also captures Bash-made
    changes that this tool cannot see.
    """
    sid = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    if not sid:
        sys.exit(1)
    # Deliberately NOT gated on this session having records of its own. That
    # gate sent a session with only Bash work (or none) down the whole-copy
    # path while a peer was live: ai_jj_commit and /cc:commit then `jj commit`
    # the ENTIRE working copy -- the peer's unfinished edits included, under
    # this session's message -- and `retire-all` archives the peer's journal,
    # so its own commit-mine later reports "nothing recorded". Whether anyone
    # ELSE is here is the whole question; with nothing of mine recorded the
    # scoped commit says so (exit 2) and points at `claim`, which is correct.
    if may_absorb(args):
        absorb_same_process(ROOT, sid)
    others = other_live_sessions(sid)
    if not others:
        sys.exit(1)
    if not args.quiet:
        print(" ".join(s[:8] for s in others))
    sys.exit(0)


def cmd_retire_all(args):
    """Retire every session journal for this repo.

    Called after a deliberate whole-working-copy commit: every session's claims
    are now in history, so leaving the journals live would make their paths look
    permanently claimed and wedge the nudge on forever.
    """
    base = os.path.join(journal_root(), repo_key(ROOT))
    n = 0
    if os.path.isdir(base):
        for sid in sorted(os.listdir(base)):
            d = os.path.join(base, sid)
            if sid == "archive" or not os.path.isdir(d):
                continue
            if retire(d, sid, "committed-whole"):
                n += 1
            else:
                print("warning: could not archive %s; the nudge will stay on."
                      % d, file=sys.stderr)
    # Contention is over as far as this repo is concerned; clear the marker the
    # nudge only ever sets.
    busy = marker(ROOT, MARKER_BUSY)
    if os.path.exists(busy):
        try:
            os.remove(busy)
        except OSError:
            pass
    now = jj("log", "--no-graph", "-T", "commit_id", "-r", "@-",
             "--ignore-working-copy", check=False)
    if now.returncode == 0 and len(now.stdout.decode().split()) == 1:
        refresh_bases(now.stdout.decode().strip())
    if not args.quiet:
        print("retired %d session journal(s)" % n)


def cmd_disown(args):
    base = os.path.join(journal_root(), repo_key(ROOT))
    d = os.path.join(base, args.session)
    if not os.path.isdir(d):
        die("no journal for session %s in this repo" % args.session, 2)
    if not retire(d, args.session, "disowned"):
        die("could not archive %s; it is still live. Move it aside by hand." % d)
    print("disowned %s -- its claims no longer suppress warnings" % args.session[:8])


def cmd_forget(args):
    """Remove this session's journal records for one or more paths.

    Every journal defect found so far has been worked around the same way: find
    the journal directory and delete a record by hand. Two die() messages
    instruct exactly that -- anchored_replace's "Remove the record" and
    load_records' "Inspect or remove it" -- while nothing implemented it. This
    does, and it is the recovery route for whatever the next such defect is.

    Records are MOVED, not unlinked. Forgetting is destructive in a way nothing
    else here is: the edits a forgotten record describes are then simply not
    committed, with no error, so a mistake looks exactly like work that was
    never done. `forgotten/` lives inside the session journal, where
    load_records skips it (it filters on the .json suffix) and retire() carries
    it along with the rest of the session.
    """
    sid = args.session or os.environ.get("CLAUDE_SESSION_ID", "")
    if not sid:
        die("no --session and CLAUDE_SESSION_ID is unset")

    jdir = os.path.join(journal_root(), repo_key(ROOT), sid)
    if may_absorb(args):
        absorb_same_process(ROOT, sid)
    if not os.path.isdir(jdir):
        die("no journal for session %s in this repo" % sid[:8], 2)

    wanted = {rel(os.path.abspath(p)) for p in args.path}

    def describe(rec):
        if rec.get("tool") == "Write":
            return "Write, %d bytes" % len(blob(rec, "content") or b"")

        old, new = rec.get("old") or "", rec.get("new") or ""

        def head(s):
            return s.split("\n")[0][:44]

        if head(old) == head(new):
            # Real edits usually share a long first line -- an anchored replace
            # keeps its context -- and two identical-looking previews are no
            # help at all when the preview is the thing you decide from.
            return "Edit, %d -> %d bytes, first lines identical" % (len(old), len(new))
        return "%r -> %r" % (head(old), head(new))

    hits, unreadable = [], []
    for name in sorted(os.listdir(jdir)):
        if not name.endswith(".json"):
            continue
        fp = os.path.join(jdir, name)
        try:
            with open(fp) as fh:
                rec = json.load(fh)
        except (json.JSONDecodeError, OSError):
            # Deliberately not load_records(): that dies on an unreadable
            # record, which would make the one escape from an unreadable record
            # unreachable. Report them instead -- they have no parseable path,
            # so they cannot be matched by one.
            unreadable.append(name)
            continue
        if not rec.get("path"):
            continue
        try:
            r = rec_rel(rec)
        except SystemExit:
            # Same reasoning: a record whose path no longer resolves against
            # ROOT is exactly a thing that must stay removable.
            r = os.path.relpath(rec["path"], ROOT)
        if r in wanted:
            hits.append((fp, name, rec, r))

    if not hits:
        msg = "no records for %s in session %s" % (", ".join(sorted(wanted)), sid[:8])
        if unreadable:
            msg += ("\n  %d unreadable record(s) are present and cannot be matched\n"
                    "  by path: %s" % (len(unreadable), ", ".join(unreadable)))
        die(msg, 2)

    print("session %s -- %d record(s):" % (sid[:8], len(hits)))
    for _, name, rec, r in hits:
        print("    %s  %s  %s" % (name, rec.get("tool", "?"), r))
        print("        %s" % describe(rec))

    if args.dry_run:
        print("(dry run -- nothing removed)")
        return

    dest = os.path.join(jdir, "forgotten")
    os.makedirs(dest, mode=0o700, exist_ok=True)
    for fp, name, _, _ in hits:
        os.replace(fp, os.path.join(dest, name))

    print("forgotten %d record(s). `ccjj commit` will no longer replay them, so\n"
          "  whatever they describe will NOT be committed by this session --\n"
          "  check `jj status` if you expected those edits to land.\n"
          "  Moved to %s; move them back to undo." % (len(hits), dest))
    if unreadable:
        print("  note: %d unreadable record(s) remain and cannot be matched by\n"
              "  path: %s" % (len(unreadable), ", ".join(unreadable)))


def cmd_prune(args, quiet=False):
    base = os.path.join(journal_root(), repo_key(ROOT))
    arch = os.path.join(base, "archive")
    removed = 0

    # Retire journals whose owning claude process is gone. Without this nothing
    # ever retires a LIVE journal -- only a successful `ccjj commit` does -- so
    # every session that edits a file and commits some other way leaves a
    # permanent claim on those paths.
    swept = []
    if os.path.isdir(base):
        for sid in sorted(os.listdir(base)):
            d = os.path.join(base, sid)
            if sid == "archive" or not os.path.isdir(d):
                continue
            # Dead owner AND old. A stale-but-still-running owner (the /clear
            # case) is excluded from claims already; destroying its journal
            # could throw away work it can still commit.
            owned = os.path.isfile(os.path.join(d, ".owner"))
            if (owned and owner_alive(d)) or journal_age_hours(d) < args.stale_days * 24:
                continue
            if args.dry_run:
                swept.append(sid)
            elif retire(d, sid, "orphaned"):
                swept.append(sid)
    for sid in swept:
        print("%s orphaned journal %s (owner gone)"
              % ("would retire" if args.dry_run else "retired", sid[:8]))

    cutoff = datetime.date.today() - datetime.timedelta(days=args.days)
    if os.path.isdir(arch):
        for name in sorted(os.listdir(arch)):
            try:
                when = datetime.date.fromisoformat(name)
            except ValueError:
                continue          # unparseable names are left alone deliberately
            if when < cutoff:
                if args.dry_run:
                    print("would remove archive/%s" % name)
                else:
                    subprocess.run(["rm", "-rf", os.path.join(arch, name)])
                removed += 1
    # The piggybacked daily call must not editorialise on every first commit of
    # the day; only speak when it actually did something, or when asked directly.
    if not quiet or removed or swept:
        print("prune: %d archived day(s) %s"
              % (removed, "would go" if args.dry_run else "removed"))
    return removed + len(swept)


def maybe_prune():
    """Daily, piggybacked on a successful commit -- no LaunchAgent, and pruning
    that only runs when the tool is used cannot leak."""
    stamp = os.path.join(journal_root(), repo_key(ROOT), ".pruned")
    today = datetime.date.today().isoformat()
    try:
        if os.path.isfile(stamp) and open(stamp).read().strip() == today:
            return
        ns = argparse.Namespace(days=14, stale_days=2, dry_run=False)
        cmd_prune(ns, quiet=True)
        with open(stamp, "w") as fh:
            fh.write(today)
    except OSError:
        pass


# ------------------------------------------------------------------------ main

def main():
    global ROOT
    ap = argparse.ArgumentParser(prog="ccjj")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("record-edit", help="PostToolUse hook (Edit|Write)")
    sub.add_parser("nudge", help="UserPromptSubmit hook")

    c = sub.add_parser("commit", help="commit only this session's edits")
    c.add_argument("-m", "--message")
    c.add_argument("--session", default="")
    c.add_argument("--also", action="append", default=[],
                   help="path to take wholesale (a Bash-made add/delete/rename)")
    c.add_argument("--diff", action="store_true", help="show the patch, commit nothing")
    c.add_argument("--force", action="store_true",
                   help="--also a path another session has a stake in")
    c.add_argument("--no-claim", action="store_true",
                   help="commit without the unclaimed Bash-window paths")

    ss = sub.add_parser("should-scope",
                        help="exit 0 if a commit here should be session-scoped")
    ss.add_argument("--session", default="")
    ss.add_argument("-q", "--quiet", action="store_true")

    ra = sub.add_parser("retire-all",
                        help="retire every session journal (after a whole-copy commit)")
    ra.add_argument("-q", "--quiet", action="store_true")

    a = sub.add_parser("audit", help="report changes no session claims")
    a.add_argument("--porcelain", action="store_true")
    a.add_argument("--session", default="")

    wh = sub.add_parser("who", help="list the sessions with a stake in a path (read-only)")
    wh.add_argument("path")
    wh.add_argument("--session", default="")

    sub.add_parser("bash-window", help="PostToolUse hook (Bash)")

    bw = sub.add_parser("bash-windows", help="opt this checkout in or out")
    bw.add_argument("action", nargs="?", default="status",
                    choices=["on", "off", "status"])

    cl = sub.add_parser("claim", help="accept a Bash-window change as your own")
    cl.add_argument("path")
    cl.add_argument("--session", default="")
    cl.add_argument("-n", "--dry-run", action="store_true")
    cl.add_argument("--force", action="store_true",
                    help="claim even though another session has a stake in it")

    p = sub.add_parser("prune", help="retire orphaned and old journals")
    p.add_argument("--days", type=int, default=14,
                   help="delete archived days older than this")
    p.add_argument("--stale-days", type=int, default=2,
                   help="retire live journals whose owner is gone and which are older")
    p.add_argument("-n", "--dry-run", action="store_true")

    dz = sub.add_parser("disown", help="retire one session's journal by hand")
    dz.add_argument("session")

    fg = sub.add_parser("forget",
                        help="remove this session's records for a path")
    fg.add_argument("path", nargs="+")
    fg.add_argument("--session", default="")
    fg.add_argument("-n", "--dry-run", action="store_true")

    args = ap.parse_args()

    if args.cmd in ("record-edit", "nudge", "bash-window"):
        {"record-edit": cmd_record_edit, "nudge": cmd_nudge,
         "bash-window": cmd_bash_window}[args.cmd](args)
        return

    r = subprocess.run(["jj", "root"], capture_output=True, text=True)
    if r.returncode != 0:
        die("not inside a jj repo", 2)
    # true_case for the same reason find_repo() applies it: both sides must
    # agree on the spelling, or repo_key() names two journals for one repo.
    ROOT = true_case(os.path.realpath(r.stdout.strip()))

    {"commit": cmd_commit, "audit": cmd_audit, "prune": cmd_prune,
     "disown": cmd_disown, "should-scope": cmd_should_scope,
     "retire-all": cmd_retire_all, "claim": cmd_claim,
     "forget": cmd_forget, "who": cmd_who,
     "bash-windows": cmd_bash_windows}[args.cmd](args)


if __name__ == "__main__":
    if os.environ.get("CCJJ_HOOK_SAFE") != "0" and len(sys.argv) > 1 \
            and sys.argv[1] in ("record-edit", "nudge", "bash-window"):
        # The hook must never fail the agent's tool call. SystemExit is a
        # BaseException, so `except Exception` alone would let a die() inside
        # jj() escape as a nonzero hook exit.
        try:
            main()
        except (Exception, SystemExit):
            pass
        sys.exit(0)
    main()
