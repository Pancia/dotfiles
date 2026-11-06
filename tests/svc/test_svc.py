"""supervise / svc / svc-tmux, driven as real processes.

Screen checks run supervise in a pseudo-terminal rendered by pyte. Process
checks look for orphans by a unique marker in each test's service argv: the
failures that matter here (a closed pane leaving a JVM behind, two supervisors
racing, an LLM-started tmux server leaking its env) are only visible in `ps`.

tmux tests use a private socket per test and the wrapper's own config, so the
user's tmux server is never touched.
"""

import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import subprocess
import termios
import time
import uuid
from pathlib import Path

import pyte
import pytest

DOTFILES = Path(__file__).resolve().parents[2]
SUP = str(DOTFILES / "bin" / "supervise")
SVC = str(DOTFILES / "bin" / "svc")
SVC_TMUX = str(DOTFILES / "bin" / "svc-tmux")

needs_tmux = pytest.mark.skipif(shutil.which("tmux") is None, reason="tmux not installed")

SERVE_PY = """\
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen()
if sys.argv[1]:
    open(sys.argv[1], "w").write(str(s.getsockname()[1]))
time.sleep(3600)
"""

SVC_CONF = """\
SVC_SERVICES="web worker"
SVC_ENV="WANTED"
svc_port_file() {{ case "$1" in web) echo .web-port ;; slow) echo .slow-port ;; esac; }}
svc_cmd() {{ case "$1" in
  web)    echo "env > .web-env; exec python3 serve.py .web-port {mark}" ;;
  slow)   echo "sleep 2; exec python3 serve.py .slow-port {mark}" ;;
  worker) echo "exec python3 serve.py '' {mark}" ;;
  broken) echo "echo boom-message; exit 3" ;;
esac; }}
"""


def wait_for(pred, timeout=15.0, step=0.1):
    end = time.time() + timeout
    while time.time() < end:
        if pred():
            return True
        time.sleep(step)
    return pred()


def marked(mark):
    """PIDs of service processes carrying this test's marker."""
    out = subprocess.run(["pgrep", "-f", mark], capture_output=True, text=True).stdout
    return [int(p) for p in out.split()]


def make_project(path: Path, mark: str) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    (path / "serve.py").write_text(SERVE_PY)
    (path / ".svc.conf").write_text(SVC_CONF.format(mark=mark))
    return path


@pytest.fixture(autouse=True)
def private_fs_config(tmp_path, monkeypatch):
    """Point the vault lookup at an empty per-test tree: no test may read (or be
    changed by) the real ~/Vaults/work-config."""
    root = tmp_path / "fs-config"
    root.mkdir()
    monkeypatch.setenv("SVC_FS_CONFIG", str(root))
    return root


class ProjPath(type(Path())):
    """A project dir that also carries its orphan-detection marker."""

    mark = ""


@pytest.fixture
def proj(tmp_path):
    mark = f"svcmark-{uuid.uuid4().hex[:10]}"
    p = ProjPath(make_project(tmp_path / "proj", mark))
    p.mark = mark
    yield p
    # supervise's argv has no project path, so find this project's supervisors
    # through their pidfiles (a failed test must not leak them).
    for pidfile in (p / ".run").glob("*.pid"):
        try:
            os.kill(int(pidfile.read_text().split()[0]), signal.SIGTERM)
        except (OSError, ValueError, IndexError):
            pass
    subprocess.run(["pkill", "-f", mark])


def run(argv, cwd, env=None, timeout=60):
    return subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def read(path: Path) -> str:
    try:
        return path.read_text()
    except OSError:
        return ""


class Pane:
    """A process in a pty, rendered by pyte."""

    def __init__(self, argv, cwd, rows=12, cols=100, env=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:  # pragma: no cover - child
            os.chdir(cwd)
            os.execvpe(argv[0], argv, env if env is not None else os.environ)
        self.screen = pyte.Screen(cols, rows)
        self.stream = pyte.ByteStream(self.screen)
        self.resize(rows, cols)
        self.status = None

    def resize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.screen.resize(rows, cols)

    def pump(self, t=0.1):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    self.stream.feed(os.read(self.fd, 65536))
                except OSError:
                    return

    def until(self, pred, timeout=15.0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            if pred():
                return True
        return pred()

    def send(self, data: bytes):
        os.write(self.fd, data)

    def lines(self):
        return [line.rstrip() for line in self.screen.display]

    def text(self):
        return "\n".join(self.lines())

    def wait_exit(self, timeout=15.0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.1)
            pid, st = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.status = os.waitstatus_to_exitcode(st)
                return self.status
        return None

    def kill(self):
        if self.status is None:
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except OSError:
                pass
        try:
            os.close(self.fd)
        except OSError:
            pass


@pytest.fixture
def panes():
    made = []
    yield lambda *a, **k: made.append(Pane(*a, **k)) or made[-1]
    for p in made:
        p.kill()


def gen(proj, name="web"):
    return read(proj / ".run" / f"{name}.gen").split()[:1]


# --- in-pane keys, bar, panel -------------------------------------------------


def test_keys_restart_suspend_resume_quit(proj, panes):
    p = panes([SUP, "web"], proj)  # no command: comes from svc_cmd
    assert p.until(lambda: (proj / ".web-port").exists()), p.text()
    p.send(b"r")
    assert p.until(lambda: gen(proj) == ["2"]), p.text()
    p.send(b"s")
    assert p.until(lambda: (proj / ".run/web.suspended").exists()), p.text()
    assert wait_for(lambda: not marked(proj.mark)), "suspend must stop the child"
    p.send(b"s")
    assert p.until(lambda: gen(proj) == ["3"]), p.text()
    p.send(b"q")
    assert p.wait_exit() == 0
    assert not marked(proj.mark)
    assert not (proj / ".run/web.pid").exists()


def test_q_under_tmux_stops_but_keeps_the_supervisor(proj, panes):
    """In a tmux window, q suspends (window stays, r/s restart it) instead of exiting."""
    env = dict(os.environ, TMUX="/tmp/fake-tmux-socket,1,0")
    p = panes([SUP, "web"], proj, env=env)
    assert p.until(lambda: "q stop" in p.lines()[-1]), p.text()
    p.send(b"q")
    assert p.until(lambda: (proj / ".run/web.suspended").exists()), p.text()
    assert p.until(lambda: "stopped · r or s to start" in p.lines()[-1]), p.text()
    assert wait_for(lambda: not marked(proj.mark)), "q must still stop the service"
    assert p.status is None and p.wait_exit(timeout=1) is None, "supervisor must stay"
    p.send(b"r")
    assert p.until(lambda: gen(proj) == ["2"] and "● up" in p.lines()[-1]), p.text()
    p.send(b"\x03")                                   # Ctrl-C still really exits
    assert p.wait_exit() == 0


def test_bar_separator_and_panel_render(proj, panes):
    p = panes([SUP, "web"], proj, rows=12, cols=100)
    assert p.until(lambda: "● up" in p.lines()[-1]), p.text()
    bar = p.lines()[-1]
    assert "web" in bar and "r restart" in bar and "? help" in bar
    assert p.lines()[-2].startswith("─" * 20), "separator above the bar"

    p.send(b"?")
    assert p.until(lambda: "restart (resumes if suspended)" in p.text()), p.text()
    assert "close help" in p.lines()[-1]
    assert p.lines()[-6].startswith("── supervise web"), p.text()
    p.send(b"?")
    assert p.until(lambda: "restart (resumes" not in p.text() and "? help" in p.lines()[-1]), p.text()

    p.resize(9, 60)
    assert p.until(lambda: p.lines()[-1].endswith("r s c q ?")), p.text()
    p.send(b"q")
    assert p.wait_exit() == 0
    assert "● up" not in p.text(), "bar is cleared on exit"


def test_tty_mode_restored_after_ctrl_c(proj, panes):
    out = proj / "stty.txt"
    p = panes(["bash", "-c", f"{SUP} web; stty -a > {out}"], proj)
    assert p.until(lambda: (proj / ".web-port").exists()), p.text()
    p.send(b"\x03")
    # p.until, not wait_for: it keeps reading the pty. An unread pty fills its
    # small buffer and every later write in supervise blocks.
    assert p.until(lambda: out.exists() and out.stat().st_size > 0), p.text()
    words = out.read_text().split()
    assert "echo" in words and "icanon" in words, out.read_text()
    assert not marked(proj.mark)


# --- Phase 0: lifecycle bugs --------------------------------------------------


def test_closing_the_terminal_stops_and_drains(proj, panes):
    """A closed pane HUPs supervise. That used to mean 'restart', and the
    restart then died on the dead tty, orphaning the child with no pidfile."""
    p = panes([SUP, "web"], proj)
    assert p.until(lambda: (proj / ".web-port").exists()), p.text()
    assert marked(proj.mark)
    os.close(p.fd)  # the terminal goes away
    assert wait_for(lambda: not marked(proj.mark)), "child orphaned"
    assert wait_for(lambda: not (proj / ".run/web.pid").exists())
    assert "not running" in run([SVC, "status", "web"], proj).stdout


def test_svc_controls_a_no_argument_supervisor(proj):
    """`supervise web` (command from svc_cmd) is the last argv, so svc's
    trailing-space name match must still see it."""
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".web-port").exists())
        assert f"sup pid {sup.pid}" in run([SVC, "status", "web"], proj).stdout
        assert "p2" in read(proj / ".run/web.pid")
        r = run([SVC, "restart", "web"], proj)
        assert r.returncode == 0, r.stderr
        assert gen(proj) == ["2"] and sup.poll() is None
        r = run([SVC, "suspend", "web"], proj)
        assert r.returncode == 0 and "suspended" in run([SVC, "status", "web"], proj).stdout
        r = run([SVC, "restart", "web"], proj)  # a restart request resumes a held child
        assert r.returncode == 0, r.stderr
        run([SVC, "stop", "web"], proj)
        assert sup.wait(15) == 0
        assert not marked(proj.mark)
    finally:
        sup.kill()


def test_concurrent_starts_exactly_one_wins(proj):
    procs = [subprocess.Popen([SUP, "worker"], cwd=proj, stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
             for _ in range(4)]
    try:
        assert wait_for(lambda: sum(p.poll() is not None for p in procs) == 3)
        live = [p for p in procs if p.poll() is None]
        assert len(live) == 1
        assert all(p.returncode == 1 for p in procs if p is not live[0])
        assert read(proj / ".run/worker.pid").split()[0] == str(live[0].pid)
        assert wait_for(lambda: len(marked(proj.mark)) == 1)
    finally:
        for p in procs:
            p.terminate()
        for p in procs:
            p.wait(15)


def test_an_unexpected_exit_still_drains_the_child(proj):
    """Any exit path - here a set -e failure writing state mid-restart - must
    take the child down too, not leave it running with no pidfile."""
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".web-port").exists())
        (proj / ".run/web.gen").chmod(0o444)   # the respawn's state write will fail
        (proj / ".run/web.req").write_text("restart\n")   # what `svc restart` sends,
        os.kill(sup.pid, signal.SIGUSR1)                  # without its 90s wait-for-up
        assert sup.wait(15) != 0
        assert wait_for(lambda: not marked(proj.mark)), "child orphaned"
    finally:
        sup.kill()


def test_second_no_argument_start_is_refused(proj):
    first = subprocess.Popen([SUP, "worker"], cwd=proj, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: marked(proj.mark))
        second = run([SUP, "worker"], proj, timeout=15)
        assert second.returncode == 1 and "already running" in second.stderr
    finally:
        first.terminate()
        first.wait(15)


def test_svc_setup_runs_once_and_its_exports_reach_respawns(proj):
    conf = proj / ".svc.conf"
    conf.write_text(conf.read_text() + """
svc_setup() { echo x >> .setup-count; export FROM_SETUP=yes; }
""")
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".web-port").exists())
        (proj / ".web-env").unlink()      # so only the respawn can recreate it
        assert run([SVC, "restart", "web"], proj).returncode == 0
        assert wait_for(lambda: (proj / ".web-env").exists())
        assert "FROM_SETUP=yes" in read(proj / ".web-env"), "export reaches the respawned child"
        assert read(proj / ".setup-count").count("x") == 1, "setup ran once, not per spawn"
    finally:
        sup.terminate()
        sup.wait(15)


def test_restart_waits_for_the_port_file(proj):
    """With svc_port_file but no svc_eval, 'back up' must mean the new instance
    wrote its port file - supervise deletes it on every restart."""
    sup = subprocess.Popen([SUP, "slow"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".slow-port").exists())
        r = run([SVC, "restart", "slow"], proj)
        assert r.returncode == 0, r.stderr
        assert (proj / ".slow-port").exists(), "reported up before the port file existed"
        assert "ready=up" in run([SVC, "status", "slow"], proj).stdout
    finally:
        sup.terminate()
        sup.wait(15)


def test_request_during_setup_does_not_disable_later_requests(proj):
    conf = proj / ".svc.conf"
    conf.write_text(conf.read_text() + "\nsvc_setup() { sleep 2; }\n")
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".run/web.pid").exists())
        (proj / ".run/web.req").write_text("suspend\n")     # lands during svc_setup
        os.kill(sup.pid, signal.SIGUSR1)
        assert wait_for(lambda: (proj / ".web-port").exists())
        assert not (proj / ".run/web.suspended").exists()
        r = run([SVC, "restart", "web"], proj, timeout=30)
        assert r.returncode == 0 and gen(proj) == ["2"], r.stderr
        # macOS ps can't show ignored signals, so test the disposition directly:
        # with the default action SIGUSR1 kills the child; inherited SIG_IGN wouldn't.
        child = int(read(proj / ".run/web.gen").split()[1])
        os.kill(child, signal.SIGUSR1)
        assert wait_for(lambda: subprocess.run(["kill", "-0", str(child)],
                                               capture_output=True).returncode != 0, timeout=5), \
            "child inherited SIGUSR1=IGN"
    finally:
        sup.terminate()
        sup.wait(15)


def linked_project(tmp_path, mark):
    """A project with its config in the vault tree, reached through a symlink."""
    real = tmp_path / "real-proj"
    real.mkdir()
    (real / "serve.py").write_text(SERVE_PY)
    link = tmp_path / "link-proj"
    link.symlink_to(real)
    return real, link, SVC_CONF.format(mark=mark)


@pytest.mark.parametrize("key", ["logical", "physical"])
def test_vault_svc_conf_is_found_through_a_symlink(tmp_path, private_fs_config, key):
    mark = f"svcmark-{uuid.uuid4().hex[:10]}"
    real, link, conf = linked_project(tmp_path, mark)
    keyed = private_fs_config / str(link if key == "logical" else real).lstrip("/")
    keyed.mkdir(parents=True)
    (keyed / "svc.conf").write_text(conf)
    env = dict(os.environ, PWD=str(link))       # what a shell that cd'd via the link sets
    out = run([SVC, "status", "--short"], link, env).stdout.strip()
    assert out == "○ web  ○ worker", out


def test_declare_in_a_config_reaches_the_service(proj, private_fs_config):
    """Configs are sourced at top level: inside a function, `declare` would make
    the variable local and drop it (and bash 3.2 has no declare -g)."""
    keyed = private_fs_config / str(proj).lstrip("/")
    keyed.mkdir(parents=True)
    (keyed / "svc.conf").write_text("declare -x FROM_DECLARE=kept\n")
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".web-env").exists())
        assert "FROM_DECLARE=kept" in read(proj / ".web-env")
    finally:
        sup.terminate()
        sup.wait(15)


@needs_tmux
def test_svc_tmux_windows_find_a_logically_keyed_vault_conf(tmp_path, private_fs_config, tmux_env):
    mark = f"svcmark-{uuid.uuid4().hex[:10]}"
    real, link, conf = linked_project(tmp_path, mark)
    keyed = private_fs_config / str(link).lstrip("/")
    keyed.mkdir(parents=True)
    (keyed / "svc.conf").write_text(conf)
    env = dict(tmux_env, PWD=str(link))
    try:
        r = run([SVC_TMUX, "up", "--wait", "--timeout", "20", "web"], link, env)
        assert r.returncode == 0, r.stdout + r.stderr
    finally:
        run([SVC_TMUX, "down"], link, env)
        subprocess.run(["pkill", "-f", mark])


def test_status_short(proj):
    sup = subprocess.Popen([SUP, "web"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: (proj / ".web-port").exists())
        assert run([SVC, "-C", str(proj), "status", "--short"], "/").stdout.strip() == "● web  ○ worker"
        tm = run([SVC, "-C", str(proj), "status", "--short", "--tmux"], "/").stdout
        assert "#[fg=green]●#[default] web" in tm
    finally:
        sup.terminate()
        sup.wait(15)


# --- svc-tmux -----------------------------------------------------------------



@pytest.fixture
def tmux_env(tmp_path):
    sock = f"svctest-{uuid.uuid4().hex[:8]}"
    # The real config minus the user's own tmux.conf: its plugins (tpm) add ~3s
    # to every server start, and each test starts one.
    real = (DOTFILES / "lib/svc/tmux.conf").read_text()
    assert "source-file -q ~/.config/tmux/tmux.conf" in real
    conf = tmp_path / "svc-tmux.conf"
    conf.write_text(real.replace("source-file -q ~/.config/tmux/tmux.conf", ""))
    env = dict(os.environ, SVC_TMUX_SOCKET=sock, SVC_TMUX_CONF=str(conf))
    env.pop("TMUX", None)
    yield env
    subprocess.run(["tmux", "-L", sock, "kill-server"], capture_output=True)
    # kill-server doesn't always remove the socket file; don't litter /tmp/tmux-UID.
    Path(f"/private/tmp/tmux-{os.getuid()}/{sock}").unlink(missing_ok=True)


def tm(env, *args):
    return subprocess.run(["tmux", "-L", env["SVC_TMUX_SOCKET"], *args],
                          capture_output=True, text=True).stdout


@needs_tmux
def test_up_wait_is_idempotent_clean_env_and_down(proj, tmux_env):
    env = dict(tmux_env, CLAUDECODE="1", CCS_ENTRY_FILE="/x/entry", WANTED="yes",
               SVC_TEST_TOOLCONF="kept")
    r = run([SVC_TMUX, "up", "--wait", "--timeout", "30"], proj, env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "web          up" in r.stdout and "worker       up" in r.stdout

    svc_env = read(proj / ".web-env")
    assert "WANTED=yes" in svc_env, "SVC_ENV names are passed through"
    assert "CLAUDECODE" not in svc_env and "CCS_ENTRY_FILE" not in svc_env
    # Not an allowlist: tool config such as XDG_CONFIG_HOME must survive - it is
    # where clojure finds ~/.config/clojure/deps.edn and its aliases.
    assert "SVC_TEST_TOOLCONF=kept" in svc_env

    r = run([SVC_TMUX, "up"], proj, env)
    assert r.stdout.count("running") == 2 and "started" not in r.stdout
    assert len(tm(env, "list-windows", "-a").splitlines()) == 2

    r = run([SVC_TMUX, "down"], proj, env)
    assert r.returncode == 0, r.stderr
    assert tm(env, "ls") == ""
    assert not marked(proj.mark)


@needs_tmux
def test_concurrent_ups_make_one_window_per_service(proj, tmux_env):
    ups = [subprocess.Popen([SVC_TMUX, "up", "--wait", "--timeout", "30"], cwd=proj, env=tmux_env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
           for _ in range(3)]
    for u in ups:
        out, err = u.communicate(timeout=60)
        assert u.returncode == 0, out + err
    names = tm(tmux_env, "list-windows", "-a", "-F", "#{window_name}").split()
    assert sorted(names) == ["web", "worker"], names


@needs_tmux
def test_killing_the_session_leaves_no_orphan(proj, tmux_env):
    assert run([SVC_TMUX, "up", "--wait", "--timeout", "30"], proj, tmux_env).returncode == 0
    session = run([SVC_TMUX, "session"], proj, tmux_env).stdout.strip()
    tm(tmux_env, "kill-session", "-t", f"={session}")
    assert wait_for(lambda: not marked(proj.mark)), "children orphaned by kill-session"
    assert wait_for(lambda: not (proj / ".run/web.pid").exists())


@needs_tmux
def test_clean_exit_closes_the_window_crash_keeps_it(proj, tmux_env):
    assert run([SVC_TMUX, "up", "--wait", "web"], proj, tmux_env).returncode == 0
    run([SVC, "stop", "web"], proj)
    assert wait_for(lambda: "web" not in tm(tmux_env, "list-windows", "-a", "-F", "#{window_name}").split())

    run([SVC_TMUX, "up", "--wait", "--timeout", "10", "broken"], proj, tmux_env)
    dead = tm(tmux_env, "list-windows", "-a", "-F", "#{window_name} #{pane_dead}")
    assert "broken 1" in dead, dead
    session = run([SVC_TMUX, "session"], proj, tmux_env).stdout.strip()
    screen = tm(tmux_env, "capture-pane", "-p", "-t", f"={session}:=broken")
    assert "broken crashed (exit 3)" in screen and "boom-message" in screen, screen


@needs_tmux
def test_up_wait_reports_a_dead_pane(proj, tmux_env):
    r = run([SVC_TMUX, "up", "--wait", "--timeout", "20", "broken"], proj, tmux_env)
    assert r.returncode != 0
    assert "boom-message" in r.stderr, r.stderr


@needs_tmux
def test_colliding_project_names_stay_separate(tmp_path, tmux_env):
    mark = f"svcmark-{uuid.uuid4().hex[:10]}"
    a = make_project(tmp_path / "p", mark)
    b = make_project(tmp_path / "p.one", mark)
    try:
        for d in (a, b):
            assert run([SVC_TMUX, "up", "--wait", "worker"], d, tmux_env).returncode == 0
        assert len(tm(tmux_env, "ls").splitlines()) == 2
        assert run([SVC_TMUX, "down"], a, tmux_env).returncode == 0
        sessions = tm(tmux_env, "ls", "-F", "#{session_name}").split()
        assert sessions == [run([SVC_TMUX, "session"], b, tmux_env).stdout.strip()]
        assert len(marked(mark)) == 1, "only p's worker stopped"
    finally:
        subprocess.run(["pkill", "-f", mark])


@needs_tmux
def test_up_and_down_leave_an_outside_instance_alone(proj, tmux_env):
    sup = subprocess.Popen([SUP, "worker"], cwd=proj, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_for(lambda: f"sup pid {sup.pid}" in run([SVC, "status", "worker"], proj).stdout)
        r = run([SVC_TMUX, "up", "worker"], proj, tmux_env)
        assert "running elsewhere" in r.stdout, r.stdout
        r = run([SVC_TMUX, "down", "worker"], proj, tmux_env)
        assert "not stopped" in r.stdout and sup.poll() is None
    finally:
        sup.terminate()
        sup.wait(15)
