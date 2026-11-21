"""A real pty for driving interactive fish.

`fish -c` fires neither fish_preexec nor fish_postexec, and neither does `fish -i`
reading from a pipe, so a test that only calls `emit fish_preexec` exercises the
handler bodies and not the wiring -- which is the failure this suite exists to
catch. `pty.fork()` gives the child the pty as its *controlling* terminal, which
`subprocess` with start_new_session does not; without that fish refuses with
"No TTY for interactive shell (tcgetpgrp failed)".
"""

import os
import pty
import select
import signal
import subprocess
import time

import pytest

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# fish waits up to 2s for a Primary Device Attribute response the harness never
# sends, and ignores typed input until it gives up.
SETTLE = 2.6


def descendants(pid):
    """Every process below `pid`, from one `ps` of the whole table."""
    rows = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True,
                          text=True).stdout.split("\n")
    kids = {}
    for row in rows:
        bits = row.split()
        if len(bits) == 2:
            kids.setdefault(int(bits[1]), []).append(int(bits[0]))
    out, todo = [], [pid]
    while todo:
        for child in kids.get(todo.pop(), []):
            out.append(child)
            todo.append(child)
    return out


class FishPane:
    """One interactive fish, in its own pty, journaling into a scratch store."""

    def __init__(self, state_dir, guid, extra_init="", env=None):
        self.state_dir = str(state_dir)
        self.guid = guid
        self.extra_init = extra_init
        self.env = env or {}

    def home(self):
        """The pane's own HOME, below its state folder, made on first use.

        `fish --no-config -i` writes no history (`$fish_history` is empty), so
        this is defence in depth: nothing a pane runs reads or writes the real
        home or its XDG folders. Like the runner's `test_home()`, it holds a
        `dotfiles` link to the tree under test, because revive.fish runs
        `~/dotfiles/lib/python/revive.py` and sources `~/dotfiles/fish/...`.
        """
        home = os.path.join(self.state_dir, "pane-home")
        for sub in (".config", os.path.join(".local", "share")):
            os.makedirs(os.path.join(home, sub), exist_ok=True)
        link = os.path.join(home, "dotfiles")
        if not os.path.islink(link):
            os.symlink(DOTFILES, link)
        return home

    def run(self, commands, budget=14.0, settle=SETTLE, powercut=False):
        """Type `commands` into a fresh shell. Returns everything it printed.

        The shell is SIGKILLed at the end unless a command exited it, so a test
        that wants a crash simply does not send `exit`. A `None` in `commands`
        waits a second, for a program that needs time to start. Reading stops
        1 s after the last entry, so output that comes later is lost: put
        `None` entries last to wait for it.

        The output is raw pty bytes, and fish's prompt, OSC codes and `\\r`
        share lines with what a program prints. Search it (`in`,
        `re.findall`); do not split it into lines and match their starts.

        Killing only the shell closes the pty, so its children get SIGHUP and can
        still clean up -- nvim deletes its session then. `powercut=True` kills
        every descendant first, which is the death a power cut gives.
        """
        init = os.path.join(self.state_dir, "init.fish")
        with open(init, "w") as fh:
            fh.write(
                'set -g fish_greeting ""\n'
                'function fish_prompt; echo "|P status=$status|"; end\n'
                f"source {DOTFILES}/fish/functions/revive-journal.fish\n"
                "if status is-interactive; and isatty stdout\n"
                "    revive-banner\n"
                "end\n" + self.extra_init
            )
        home = self.home()
        pid, fd = pty.fork()
        if pid == 0:
            # Defaults first, then the caller's env on top: a caller may set
            # any of these (test_revive_nvim passes its own XDG folders), and
            # repeating a name as a keyword to dict() would raise TypeError
            # here, inside the child, where the test cannot see it.
            env = dict(os.environ)
            env.update(
                TERM="xterm-256color",
                HOME=home,
                XDG_CONFIG_HOME=os.path.join(home, ".config"),
                XDG_DATA_HOME=os.path.join(home, ".local", "share"),
                XDG_STATE_HOME=self.state_dir,
                ITERM_SESSION_ID=f"w0t0p0:{self.guid}",
                TERM_PROGRAM="pytest.app",
            )
            env.update(self.env)
            env.pop("TMUX", None)
            env.pop("TMUX_PANE", None)
            os.execvpe("fish", ["fish", "--no-config", "-i", "-C", f"source {init}"], env)
            os._exit(127)

        out, start, sent, sent_at = b"", time.time(), False, 0.0

        def drain(seconds):
            # Keep reading while typing. With a plain sleep here, a Ctrl-Z sent
            # after `fg` stopped nothing (3 of 3 runs), while the same keys from
            # a reading driver worked. Likely cause, not proved: fish blocks
            # writing to the full pty before it hands the job the terminal.
            nonlocal out
            until = time.time() + seconds
            while time.time() < until:
                ready, _, _ = select.select([fd], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError:
                        return
                    out += chunk

        while time.time() - start < budget:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
            if not sent and time.time() - start > settle:
                for line in commands:
                    if line is None:
                        drain(1.0)
                        continue
                    # A lone control key (Ctrl-Z is "\x1a") is a keypress, not a line
                    raw = len(line) == 1 and ord(line) < 32
                    os.write(fd, (line if raw else line + "\n").encode())
                    drain(0.3)
                sent, sent_at = True, time.time()
                if not commands:
                    break
            # Drain briefly, then stop: a pane that is meant to die does not
            # need the whole budget spent watching it not exit
            if sent and time.time() - sent_at > 1.0:
                break
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
        time.sleep(0.2)
        if powercut:
            for child in descendants(pid):
                try:
                    os.kill(child, signal.SIGKILL)
                except OSError:
                    pass
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        # Reap it. A zombie is still in the process table, so `ps -o lstart=`
        # answers for it -- and the journal would read the next shell in that
        # pane as merely nested, and never adopt the record.
        try:
            os.waitpid(pid, 0)
        except OSError:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        return out.decode("utf-8", "replace")


@pytest.fixture
def pane(tmp_path):
    """Factory: pane(guid) -> FishPane writing into this test's own store."""
    def make(guid="TESTPANE-0001", extra_init="", env=None):
        return FishPane(tmp_path, guid, extra_init, env)
    return make


@pytest.fixture
def store(tmp_path):
    """The journal store the panes write into."""
    return tmp_path / "term-sessions"


@pytest.fixture
def revive_init(tmp_path):
    """Load the revive command into a pane, with iTerm unreachable."""
    stub = tmp_path / "stubs"
    stub.mkdir()
    osa = stub / "osascript"
    osa.write_text("#!/bin/sh\nexit 1\n")
    osa.chmod(0o755)
    return f"set -gx PATH {stub} $PATH\nsource {DOTFILES}/fish/functions/revive.fish\n"
