"""Repro: what the revive journal records for Ctrl-Z then `fg`.

Types `sleep 300`, Ctrl-Z, `fg`, then SIGKILLs the shell (a crash), and prints
the raw record, then what a second shell in the same pane adopts and shows.
Run: python3 .cc/scripts/revive-ctrlz-repro.py
"""
import os, pty, select, signal, sys, tempfile, time
from urllib.parse import unquote

DOTFILES = os.path.expanduser("~/dotfiles")
GUID = "REPRO-CTRLZ-0001"

def drive(state, keys, settle=2.6):
    init = os.path.join(state, "init.fish")
    with open(init, "w") as fh:
        fh.write('set -g fish_greeting ""\n'
                 'function fish_prompt; echo "|P status=$status|"; end\n'
                 f"source {DOTFILES}/fish/functions/revive-journal.fish\n"
                 "revive-banner\n")
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm-256color", XDG_STATE_HOME=state,
                   ITERM_SESSION_ID=f"w0t0p0:{GUID}", TERM_PROGRAM="repro")
        env.pop("TMUX", None); env.pop("TMUX_PANE", None)
        os.execvpe("fish", ["fish", "--no-config", "-i", "-C", f"source {init}"], env)
    out, t0 = b"", time.time()
    def pump(secs):
        nonlocal out
        end = time.time() + secs
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try: out += os.read(fd, 65536)
                except OSError: return
    pump(settle)
    for k in keys:
        os.write(fd, k.encode()); pump(0.8)
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); os.close(fd)
    return out.decode("utf-8", "replace")

def dump(path):
    for line in open(path):
        k, _, v = line.rstrip("\n").partition("\t")
        if k in ("cmd", "done", "stop", "cwd"):
            print(f"    {k:5} {unquote(v)}")

state = tempfile.mkdtemp(prefix="revive-ctrlz-")
drive(state, ["sleep 300\n", "\x1a", "fg\n"])
live = os.path.join(state, "term-sessions/live", GUID + ".rec")
print("record after: sleep 300, Ctrl-Z, fg, crash")
dump(live)
out = drive(state, [])
print("\nbanner the next shell in that pane prints:")
for l in out.splitlines():
    if "⟲" in l or l.startswith("    ") or "recent" in l:
        print("  ", l.replace("\x1b", "").strip()[:100])
sys.path.insert(0, os.path.join(DOTFILES, "lib/python"))
os.environ["XDG_STATE_HOME"] = state
import revive
g = revive.ghosts()
print("\nrevive.py ghost: running =", repr(g[0].running), " last =", repr(g[0].last))
