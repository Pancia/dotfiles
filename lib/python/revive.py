#!/usr/bin/env python3
"""Read side of `revive` -- what each terminal pane was doing before it died.

The journal itself is written by fish (fish/functions/revive-journal.fish); this
module only reads, renders and dismisses. It is invoked on demand, never on the
shell startup path, so it can afford an osascript call and a directory walk.

    revive.py list              ghosts, grouped by the live window/tab/pane tree
    revive.py here --key KEY    one pane's ghost in full
    revive.py live              what every currently-journaling pane is doing
    revive.py get N|here        TSV for the fish side (see cmd_get)
    revive.py dismiss N|here|--all   stop reporting a ghost
    revive.py prune [--days N]  drop ghosts older than N days (default 30)

Exit: 0 ok - 1 nothing to report - 2 bad usage.

Docs: docs/revive.md.
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote

CCS_OPEN = "claude-sessions/open"
MAX_HISTORY = 10
# An iTerm session GUID. Has dashes of its own, so a key can never be split on
# its last dash without first checking it is not one of these.
UUID = r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"


def state_home() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def root() -> Path:
    return state_home() / "term-sessions"


# --------------------------------------------------------------------------
# Records
#
# One line per fact: "<key>\t<url-encoded value>". Scalars are last-wins on
# replay; `cmd` and `done` interleave into the history. A record is appended to
# and never rewritten (bar compaction), so a power cut can only ever damage the
# final line -- hence every parse below drops what it cannot read rather than
# failing the listing. The same lesson is written down at ccs.fish:939.
# --------------------------------------------------------------------------

SCALARS = {"guid", "wtp", "pid", "lstart", "term", "cwd"}


class Record:
    def __init__(self, path: Path):
        self.path = path
        self.key = path.name[:-4] if path.name.endswith(".rec") else path.name
        self.fields: dict[str, str] = {}
        self.history: list[dict] = []   # {"cmd": str, "code": str|None, "ms": str|None}
        try:
            self.mtime = path.stat().st_mtime
        except OSError:
            self.mtime = 0.0
        self._parse()

    def _parse(self) -> None:
        try:
            raw = self.path.read_text("utf-8", errors="replace")
        except OSError:
            return
        lines = raw.split("\n")
        if raw and not raw.endswith("\n"):
            lines = lines[:-1]          # a torn final line: drop it, keep the rest
        for line in lines:
            if not line or "\t" not in line:
                continue
            key, _, value = line.partition("\t")
            if key in SCALARS:
                self.fields[key] = unquote(value)
            elif key == "cmd":
                self.history.append({"cmd": unquote(value), "code": None, "ms": None})
            elif key == "done" and self.history:
                bits = unquote(value).split()
                self.history[-1]["code"] = bits[0] if bits else None
                self.history[-1]["ms"] = bits[1] if len(bits) > 1 else None

    @property
    def guid(self) -> str:
        return self.fields.get("guid", self.key)

    @property
    def cwd(self) -> str:
        return self.fields.get("cwd", "")

    @property
    def running(self) -> str:
        """The command that never finished -- what the pane was doing when it died."""
        if self.history and self.history[-1]["code"] is None:
            return self.history[-1]["cmd"]
        return ""

    @property
    def last(self) -> str:
        return self.history[-1]["cmd"] if self.history else ""

    @property
    def interesting(self) -> bool:
        return bool(self.history)

    def recent(self, n: int = MAX_HISTORY) -> list[str]:
        return [h["cmd"] for h in self.history[-n:]]

    @property
    def started(self) -> float:
        """When the shell that wrote this record started, or 0 if unknown."""
        try:
            return time.mktime(time.strptime(self.fields.get("lstart", ""),
                                             "%a %b %d %H:%M:%S %Y"))
        except ValueError:
            return 0.0

    @property
    def adopted(self) -> float:
        """When the next shell took this ghost over -- the latest its pane was dead.

        The last write is not a usable stand-in: `@@` starts Claude through
        `cmds` a few seconds *after* the shell journals the command, so every
        session launched that way would fall outside it.
        """
        tail = self.key[len(self.pane_key) + 1:]
        return float(tail) if tail.isdigit() else self.mtime

    @property
    def pane_key(self) -> str:
        """The pane this ghost belongs to: its filename minus the -<epoch> suffix."""
        if re.fullmatch(UUID, self.key):
            return self.key             # a synthesised ghost: no epoch to strip
        if self.path.parent.name == "ghosts" and re.search(r"-\d+$", self.key):
            return self.key.rsplit("-", 1)[0]
        return self.key


def this_pane_key() -> str:
    """This shell's pane identity, computed exactly as _revive_pane_key does."""
    sid = os.environ.get("ITERM_SESSION_ID") or os.environ.get("TERM_SESSION_ID") or ""
    key = re.sub(r"^w[0-9]+t[0-9]+p[0-9]+:", "", sid)
    if not key:
        return ""
    if os.environ.get("TMUX") and os.environ.get("TMUX_PANE"):
        key += "-" + os.environ["TMUX_PANE"].replace("%", "")
    return re.sub(r"[^A-Za-z0-9._-]", "_", key)


def dismissed() -> set[str]:
    """GUIDs whose synthesised ghost has been waved off.

    A ghost built out of a `ccs` entry has no file of its own, so there is
    nothing for dismiss to delete -- without a tombstone it would come back
    every time.
    """
    try:
        return {p.name for p in (root() / "dismissed").iterdir()}
    except OSError:
        return set()


def read_dir(d: Path) -> list[Record]:
    try:
        paths = sorted(d.glob("*.rec"))
    except OSError:
        return []
    return [r for r in (Record(p) for p in paths) if r.fields or r.history]


def ghosts() -> list[Record]:
    out = read_dir(root() / "ghosts")
    out.sort(key=lambda r: -r.mtime)
    return out


def live_records() -> list[Record]:
    out = read_dir(root() / "live")
    out.sort(key=lambda r: -r.mtime)
    return out


# --------------------------------------------------------------------------
# The live iTerm tree
#
# `id of s` is the bare GUID -- no wNtMpK: prefix -- which is the join key. The
# prefix recorded in a journal is stale by construction (it is set once at spawn
# and never refreshed), so grouping has to come from here. Never join on an
# index: AppleScript numbers windows from 1, the env prefixes from 0.
#
# The separator is bound *outside* the tell block on purpose: inside it, `tab`
# is iTerm's own tab class, so `& tab &` silently writes the word "tab".
# --------------------------------------------------------------------------

TREE_SCRIPT = r'''set sep to character id 9
set out to ""
tell application "iTerm2"
  repeat with wi from 1 to count of windows
    set w to window wi
    repeat with ti from 1 to count of tabs of w
      set t to tab ti of w
      repeat with si from 1 to count of sessions of t
        set s to session si of t
        set out to out & wi & sep & ti & sep & si & sep & (id of s) & sep & (tty of s) & sep & (name of s) & linefeed
      end repeat
    end repeat
  end repeat
end tell
return out'''


def iterm_tree() -> dict[str, dict]:
    """guid -> {window, tab, pane, tty, name}. Empty when iTerm is not reachable."""
    try:
        proc = subprocess.run(["osascript", "-e", TREE_SCRIPT],
                              capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return {}
    if proc.returncode != 0:
        return {}
    tree: dict[str, dict] = {}
    for line in proc.stdout.splitlines():
        bits = line.split("\t")
        if len(bits) < 6:
            continue
        w, t, p, guid, tty, name = bits[0], bits[1], bits[2], bits[3], bits[4], bits[5]
        tree[guid] = {"window": w, "tab": t, "pane": p, "tty": tty, "name": name}
    return tree


# --------------------------------------------------------------------------
# The Claude join
#
# ccs entries carry terminal.iterm_session, so a ghost can borrow a real session
# -- its title, and the entry `revive` resumes. It is one-to-many in practice --
# one GUID here has two entries eleven days apart -- so take the newest entry
# started while the ghost's shell was alive, never just the first match.
#
# Not a pid join, tempting as it is (the wrapper is a fish function, so a
# direct launch records the shell's own pid). `@@` goes through `cmds`, which
# spawns a fresh fish, and on 2026-09-26 that was four of the thirteen ghosts.
# An entry still in open/ is one whose Claude never exited cleanly, so a clean
# exit earlier in the same shell cannot be picked up by mistake.
# --------------------------------------------------------------------------

def ccs_entries() -> list[dict]:
    import json
    d = state_home() / CCS_OPEN
    out = []
    try:
        paths = list(d.glob("*.json"))
    except OSError:
        return out
    for p in paths:
        try:
            data = json.loads(p.read_text("utf-8"))
        except (OSError, ValueError):
            continue                    # half-written entry: skip it, not the listing
        sid = (data.get("terminal") or {}).get("iterm_session") or ""
        guid = sid.split(":")[-1]
        if not guid:
            continue
        out.append({
            "guid": guid,
            "started_at": data.get("started_at") or 0,
            "title": data.get("title") or "",
            "session_id": data.get("session_id") or "",
            "cwd": data.get("cwd") or "",
            "file": str(p),
        })
    out.sort(key=lambda e: e["started_at"])
    return out


def ccs_for(entries: list[dict], guid: str, before: float,
            after: float = 0.0) -> dict | None:
    best = None
    for e in entries:
        if e["guid"] != guid:
            continue
        if after - 1 <= e["started_at"] <= before + 1:
            best = e                    # entries are sorted, so the last match wins
    return best


def boot_time() -> float:
    try:
        out = subprocess.run(["sysctl", "-n", "kern.boottime"],
                             capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return 0.0
    m = re.search(r"sec\s*=\s*(\d+)", out)
    return float(m.group(1)) if m else 0.0


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

ORANGE = "\x1b[1;38;2;215;135;31m"
DIM = "\x1b[2m"
OFF = "\x1b[0m"


def colour(on: bool):
    if on:
        return ORANGE, DIM, OFF
    return "", "", ""


def tilde(path: str) -> str:
    home = str(Path.home())
    if path == home:
        return "~"
    if path.startswith(home + "/"):
        return "~" + path[len(home):]
    return path


def ago(seconds: float) -> str:
    if seconds < 0:
        seconds = 0
    for limit, div, unit in ((90, 1, "s"), (5400, 60, "m"), (172800, 3600, "h")):
        if seconds < limit:
            return f"{int(seconds / div)}{unit}"
    return f"{int(seconds / 86400)}d"


def elide(text: str, width: int = 76) -> str:
    one = " ".join(text.split())
    return one if len(one) <= width else one[: width - 1] + "…"


class Entry:
    """A ghost, plus everything known about where its pane is now."""

    def __init__(self, rec, place, claude, synthetic=False):
        self.rec, self.place, self.claude, self.synthetic = rec, place, claude, synthetic

    @property
    def gone(self) -> bool:
        return self.place is None

    def where(self) -> str:
        if self.place is None:
            return "gone"
        p = self.place
        pane = f" · pane {p['pane']}" if p["pane"] != "1" else ""
        return f"window {p['window']} · tab {p['tab']}{pane}"


def place(tree: dict[str, dict], guid: str) -> dict | None:
    """Where that pane is now, if it is anywhere.

    A record made inside tmux is keyed <guid>-<tmux pane>, and only the GUID in
    front is an iTerm session -- without the fallback every tmux pane reads as
    `gone` while its window is sitting right there.
    """
    hit = tree.get(guid)
    if hit is None and "-" in guid:
        hit = tree.get(guid.rsplit("-", 1)[0])
    return hit


def collect(include_ccs: bool = True) -> list[Entry]:
    tree = iterm_tree()
    entries = ccs_entries()
    out: list[Entry] = []
    seen: set[str] = set()
    for rec in ghosts():
        guid = rec.guid
        seen.add(guid)
        # a tmux record is <guid>-<pane>; ccs only ever saw the iTerm half
        m = re.match(UUID, guid)
        claude = ccs_for(entries, m.group(0) if m else guid, rec.adopted, rec.started)
        out.append(Entry(rec, place(tree, guid), claude))
    if include_ccs:
        boot = boot_time()
        buried = dismissed()
        for guid, spot in tree.items():
            if guid in seen or guid in buried:
                continue
            hit = ccs_for(entries, guid, boot)
            if not hit:
                continue
            rec = Record(root() / "ghosts" / f"{guid}.rec")   # absent: an empty shell
            rec.fields["guid"] = guid
            rec.fields["cwd"] = hit["cwd"]
            rec.mtime = float(hit["started_at"])
            out.append(Entry(rec, spot, hit, synthetic=True))
    out.sort(key=lambda e: (e.gone, -e.rec.mtime))
    return out


def resolve(items: list[Entry], target: str) -> Entry | None:
    """`here` or a 1-based number -> that ghost, with the error printed if none."""
    if target == "here":
        key = this_pane_key()
        for e in items:                 # newest first, so a pane that died twice
            if key and e.rec.pane_key == key:   # comes back as its latest death
                return e
        print("This pane has no ghost.", file=sys.stderr)
        return None
    try:
        n = int(target)
    except ValueError:
        print(f"revive: expected a number or 'here', got '{target}'", file=sys.stderr)
        return None
    if n < 1 or n > len(items):
        print(f"No ghost {n} (there are {len(items)}).", file=sys.stderr)
        return None
    return items[n - 1]


def render_list(tty: bool) -> int:
    items = collect()
    here = this_pane_key()
    c, dim, off = colour(tty)
    if not items:
        print("Nothing to revive — no pane has left a record behind.")
        return 1
    now = time.time()
    plural = "" if len(items) == 1 else "s"
    print(f"{c}⟲ {len(items)} pane{plural} left a record behind{off}")
    for n, e in enumerate(items, 1):
        rec = e.rec
        print()
        line = f" {n:>2}  {tilde(rec.cwd) or '?'}"
        mine = f"  {off}{c}← this pane" if here and rec.pane_key == here else ""
        print(f"{line}{dim}   {ago(now - rec.mtime)} ago · {e.where()}{mine}{off}")
        if rec.running:
            print(f"     running  {elide(rec.running)}")
        elif rec.last:
            print(f"     last     {elide(rec.last)}")
        if e.claude and e.claude["title"]:
            print(f"     {dim}⎈{off} \"{elide(e.claude['title'], 66)}\"")
        elif e.place and not rec.history:
            print(f"     {dim}title    {elide(e.place['name'], 66)}{off}")
    print()
    print(f"{dim} revive <n> to pick one up (resumes its Claude session) · "
          f"revive go <n> to find it · revive dismiss --all{off}")
    return 0


def render_here(key: str, tty: bool) -> int:
    c, dim, off = colour(tty)
    mine = [e for e in collect() if e.rec.pane_key == key]
    if not mine:
        print("This pane has no ghost.")
        return 1
    e = mine[0]
    rec = e.rec
    print(f"{c}⟲ Before it died, this pane was in {tilde(rec.cwd) or '?'}{off}")
    if rec.running:
        print(f"    running  {elide(rec.running)}")
    if e.claude and e.claude["title"]:
        print(f"    ⎈ \"{e.claude['title']}\"")
    recent = rec.recent()
    if recent:
        print("  recent:")
        for cmd in recent:
            print(f"    {elide(cmd)}")
    what = "resume that Claude session" if e.claude and e.claude["session_id"] \
        else "pick it up"
    print(f"{dim}  revive to {what} · revive dismiss here{off}")
    return 0


def render_live(tty: bool) -> int:
    tree = iterm_tree()
    c, dim, off = colour(tty)
    recs = live_records()
    if not recs:
        print("No pane is journaling yet.")
        return 1
    here = (os.environ.get("ITERM_SESSION_ID") or "").split(":")[-1]
    now = time.time()
    print(f"{c}▸ {len(recs)} pane{'' if len(recs) == 1 else 's'} journaling{off}")
    for rec in recs:
        spot = place(tree, rec.guid)
        if spot is None:
            where = "gone"
        else:
            where = f"w{spot['window']}t{spot['tab']}p{spot['pane']}"
            if rec.guid not in tree:      # matched through the tmux fallback
                where += "." + rec.guid.rsplit("-", 1)[1]
        mark = "*" if rec.guid == here else " "
        doing = rec.running or rec.last or ""
        print(f" {mark} {where:<10} {tilde(rec.cwd) or '?':<44}{dim} {ago(now - rec.mtime)}{off}")
        if doing:
            print(f"     {dim}{'running ' if rec.running else 'last    '}{off} {elide(doing, 66)}")
    return 0


def flat(text: str) -> str:
    return text.replace("\t", "    ").replace("\n", " ")


def cmd_get(target: str) -> int:
    """One TSV line for the fish side:

    guid, cwd, claude session id, command, ccs entry file, claude title.
    The entry file is what `_ccs_resume_entry` resumes from; it carries the
    launch flags, which the session id alone does not.
    """
    e = resolve(collect(), target)
    if e is None:
        return 1
    c = e.claude or {}
    cmd = e.rec.running or e.rec.last or ""
    print("\t".join([e.rec.guid, e.rec.cwd, c.get("session_id", ""), flat(cmd),
                     c.get("file", ""), flat(c.get("title", ""))]))
    return 0


def cmd_dismiss(target: str) -> int:
    items = collect()
    if target == "--all":
        chosen = items
    else:
        one = resolve(items, target)
        if one is None:
            return 1
        chosen = [one]
    for e in chosen:
        if e.synthetic:
            bury = root() / "dismissed"
            bury.mkdir(parents=True, exist_ok=True)
            (bury / e.rec.guid).touch()
            continue
        # A ghost keyed <pane>-<epoch> shares its pending marker with the pane
        for path in (e.rec.path, root() / "pending" / e.rec.pane_key):
            try:
                path.unlink()
            except OSError:
                pass
    print(f"Dismissed {len(chosen)}.")
    return 0


def cmd_prune(days: int) -> int:
    cutoff = time.time() - days * 86400
    gone = 0
    for rec in ghosts():
        if rec.mtime < cutoff:
            try:
                rec.path.unlink()
                gone += 1
            except OSError:
                pass
    print(f"Pruned {gone} ghost(s) older than {days} days.")
    return 0


def main(argv: list[str]) -> int:
    tty = sys.stdout.isatty()
    verb = argv[0] if argv else "list"
    rest = argv[1:]
    if verb in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    if verb == "list":
        return render_list(tty)
    if verb == "here":
        key = rest[rest.index("--key") + 1] if "--key" in rest else \
            (os.environ.get("ITERM_SESSION_ID") or "").split(":")[-1]
        if not key:
            print("revive here: no pane identity available", file=sys.stderr)
            return 2
        return render_here(key, tty)
    if verb == "live":
        return render_live(tty)
    if verb == "get":
        if not rest:
            return 2
        return cmd_get(rest[0])
    if verb == "dismiss":
        return cmd_dismiss(rest[0] if rest else "--all")
    if verb == "prune":
        days = int(rest[rest.index("--days") + 1]) if "--days" in rest else 30
        return cmd_prune(days)
    print(f"revive: unknown command '{verb}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
