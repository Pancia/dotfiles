"""Classify the ccs open-session entries for one directory; print them as TSV.

Called by `_ccs_open_scan` in fish/functions/ccs.fish as
`python3 ccs_open_scan.py <open_dir> <cwd>`. It was a fish single-quoted
`python3 -c` string, where one apostrophe in a comment ended the string.
Emits TSV: klass, session_id, entry_file, started_at, term_summary, title.
Also deletes dead entries that never captured a session id.
"""
import json, os, subprocess, sys

open_dir, want_cwd = sys.argv[1], sys.argv[2]
GARBAGE_AGE = 5 * 60
now = int(__import__("time").time())

# One ps call for every pid, instead of one per entry
alive = {}
try:
    out = subprocess.run(["ps", "-eo", "pid=,lstart="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid, _, lstart = line.partition(" ")
        alive[pid.strip()] = lstart.strip()
except Exception:
    pass

project_root = os.path.expanduser("~/.claude/projects")
try:
    project_dirs = [e.path for e in os.scandir(project_root) if e.is_dir()]
except OSError:
    project_dirs = []

def transcript_for(sid):
    # Glob rather than deriving the dir name from cwd: Claude Code mangles "."
    # as well as "/", and the full rule is not documented.
    for d in project_dirs:
        p = os.path.join(d, sid + ".jsonl")
        if os.path.isfile(p):
            return p
    return ""

def title_from(path):
    try:
        with open(path, "rb") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    # Claude Code records its own title as {"type":"ai-title","aiTitle":...},
    # refreshed as the session drifts, so the last record wins. Parse the whole
    # record rather than slicing between quotes: a title containing an escaped
    # quote would otherwise be cut mid-escape and yield a trailing backslash.
    # Falls back to the last user prompt for sessions Claude never titled.
    for key, field in ((b"\"type\":\"ai-title\"", "aiTitle"),
                       (b"\"type\":\"last-prompt\"", "lastPrompt")):
        for line in reversed(lines):
            if key not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            val = rec.get(field)
            # Must be a string: a lastPrompt array would otherwise be stored as
            # its JSON rendering and shown as the title.
            if isinstance(val, str) and val:
                return val
    return ""

def clean(s, limit=58):
    s = " ".join(str(s).split())
    if len(s) > limit:
        s = s[:limit - 1] + "…"
    return s

rows = []
try:
    names = sorted(os.listdir(open_dir))
except OSError:
    names = []

for name in names:
    if not name.endswith(".json"):
        continue
    path = os.path.join(open_dir, name)
    try:
        with open(path) as fh:
            e = json.load(fh)
    except Exception:
        # Corrupt or half-written: skip this entry, never the whole listing
        continue
    if not isinstance(e, dict):
        continue

    # Case-insensitive: some entries recorded Vaults/, others vaults/, and a
    # string compare hid whichever case you were not standing in.
    if str(e.get("cwd", "")).lower() != want_cwd.lower():
        continue

    sid = str(e.get("session_id") or "")
    try:
        started = int(e.get("started_at") or 0)
    except (TypeError, ValueError):
        started = 0
    pid = str(e.get("pid") or "")
    lstart = str(e.get("pid_lstart") or "")

    is_alive = bool(pid) and alive.get(pid) == lstart and lstart != ""
    if e.get("ended") is True:
        # Retired by the fish side before this ran; skip any that raced it.
        continue
    if is_alive and e.get("claude_exited") is not True:
        klass = "running"
    elif e.get("claude_exited") is True and sid:
        # claude died under a shell that is still open (an OOM kill, a
        # segfault). The pid is that of the shell, so it reads as alive, and a
        # "running" row only switches to the dead pane instead of resuming.
        klass = "crashed"
    elif not sid:
        if now - started > GARBAGE_AGE:
            # Dead and it never captured a session id: nothing recoverable
            try:
                os.remove(path)
            except OSError:
                pass
        continue
    else:
        klass = "crashed"

    term = e.get("terminal") or {}
    program = str(term.get("program") or "") or "shell"
    tmux_session = str(term.get("tmux_session") or "")
    tmux_pane = str(term.get("tmux_pane") or "")
    summary = "%s %s:%s" % (program, tmux_session, tmux_pane) if tmux_session else program

    # Prefer the title the Stop hook recorded while the session was alive: it
    # outlives the transcript, which Claude Code eventually prunes.
    title = str(e.get("title") or "")
    if not title and sid:
        p = str(e.get("transcript_path") or "")
        if not p or not os.path.isfile(p):
            p = transcript_for(sid)
        if p:
            title = title_from(p)

    rows.append((started, klass, sid, path, summary, title))

# Dedup only among real session ids. Several entries share the empty id — one of
# them can be the live session — so keying on it would collapse them into one row.
# Order running-first, then newest, and keep the FIRST per id: a dead entry with
# a newer started_at must never displace a live one, or `ccs list` would show a
# running session as crashed and `ccs resume` would start a second Claude on an
# already-open transcript instead of switching to its terminal.
best = {}
loose = []
for r in sorted(rows, key=lambda r: (r[1] != "running", -r[0])):
    sid = r[2]
    if not sid:
        loose.append(r)
    elif sid not in best:
        best[sid] = r

for started, klass, sid, path, summary, title in sorted(
        list(best.values()) + loose, key=lambda r: -r[0]):
    # Tabs and newlines would break the TSV contract downstream
    print("\t".join(clean(x, 400) if i < 4 else clean(x) for i, x in
                    enumerate([klass, sid, path, str(started), summary, title])))
