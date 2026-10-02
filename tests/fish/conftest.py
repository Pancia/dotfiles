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
import time

import pytest

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# fish waits up to 2s for a Primary Device Attribute response the harness never
# sends, and ignores typed input until it gives up.
SETTLE = 2.6


class FishPane:
    """One interactive fish, in its own pty, journaling into a scratch store."""

    def __init__(self, state_dir, guid, extra_init=""):
        self.state_dir = str(state_dir)
        self.guid = guid
        self.extra_init = extra_init

    def run(self, commands, budget=14.0, settle=SETTLE):
        """Type `commands` into a fresh shell. Returns everything it printed.

        The shell is SIGKILLed at the end unless a command exited it, so a test
        that wants a crash simply does not send `exit`.
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
        pid, fd = pty.fork()
        if pid == 0:
            env = dict(
                os.environ,
                TERM="xterm-256color",
                XDG_STATE_HOME=self.state_dir,
                ITERM_SESSION_ID=f"w0t0p0:{self.guid}",
                TERM_PROGRAM="pytest.app",
            )
            env.pop("TMUX", None)
            env.pop("TMUX_PANE", None)
            os.execvpe("fish", ["fish", "--no-config", "-i", "-C", f"source {init}"], env)
            os._exit(127)

        out, start, sent, sent_at = b"", time.time(), False, 0.0
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
                    os.write(fd, (line + "\n").encode())
                    time.sleep(0.3)
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
    def make(guid="TESTPANE-0001", extra_init=""):
        return FishPane(tmp_path, guid, extra_init)
    return make


@pytest.fixture
def store(tmp_path):
    """The journal store the panes write into."""
    return tmp_path / "term-sessions"
