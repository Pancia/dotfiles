"""fish/functions/revive-journal.fish -- the per-pane journal behind `revive`.

Everything here drives a real interactive fish through a pty (see conftest), so
the event *wiring* is under test and not just the handler bodies.
"""

import os
import subprocess
from urllib.parse import unquote

import pytest


def read_record(path):
    """Replay a record the way lib/python/revive.py does."""
    scalars, history = {}, []
    text = path.read_text()
    lines = text.split("\n")
    if text and not text.endswith("\n"):
        lines = lines[:-1]
    for line in lines:
        if "\t" not in line:
            continue
        key, _, value = line.partition("\t")
        if key == "cmd":
            history.append({"cmd": unquote(value), "code": None})
        elif key == "done" and history:
            history[-1]["code"] = unquote(value).split()[0]
        else:
            scalars[key] = unquote(value)
    return scalars, history


def only(paths):
    paths = list(paths)
    assert len(paths) == 1, f"expected exactly one, got {paths}"
    return paths[0]


# ---------------------------------------------------------------- journaling

@pytest.fixture(scope="module")
def _fish_available():
    if not subprocess.run(["which", "fish"], capture_output=True).returncode == 0:
        pytest.skip("fish is not on PATH")


@pytest.fixture
def revive_init(tmp_path):
    """Load the revive command into a pane, with iTerm unreachable."""
    stub = tmp_path / "stubs"
    stub.mkdir()
    osa = stub / "osascript"
    osa.write_text("#!/bin/sh\nexit 1\n")
    osa.chmod(0o755)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return f"set -gx PATH {stub} $PATH\nsource {root}/fish/functions/revive.fish\n"


@pytest.mark.usefixtures("_fish_available")
class TestJournal:
    def test_a_crashed_pane_leaves_its_commands_behind(self, pane, store):
        out = pane("CRASH-0001").run(
            ["echo one", "   ", "false", "sleep 60"]   # no `exit`: this pane dies
        )
        rec = only((store / "live").glob("*.rec"))
        scalars, history = read_record(rec)

        assert scalars["guid"] == "CRASH-0001"
        assert scalars["term"] == "pytest.app"
        cmds = [h["cmd"] for h in history]
        assert cmds == ["echo one", "false", "sleep 60"], \
            "a whitespace-only commandline still fires fish_preexec and must be skipped"
        assert history[1]["code"] == "1", "the exit status of a command is recorded"
        assert history[-1]["code"] is None, \
            "the command that never finished is what the pane was doing when it died"
        # $status reaching the prompt is not disturbed by the postexec handler
        assert "|P status=1|" in out

    def test_closing_a_pane_on_purpose_leaves_nothing(self, pane, store):
        pane("CLEAN-0001").run(["echo one", "exit"])
        assert list((store / "live").glob("*.rec")) == []
        assert list((store / "ghosts").glob("*.rec")) == []

    def test_a_pane_with_no_session_id_does_not_journal(self, pane, store, tmp_path):
        p = pane("IGNORED")
        p.guid = ""            # no ITERM_SESSION_ID value worth keying on
        p.run(["echo one"])
        assert not (store / "live").exists() or list((store / "live").glob("*.rec")) == []


@pytest.mark.usefixtures("_fish_available")
class TestAdoption:
    def test_the_next_shell_adopts_the_ghost_and_banners_it(self, pane, store):
        pane("ADOPT-0001").run(["echo one", "sleep 60"])          # dies
        out = pane("ADOPT-0001").run(["exit"])                    # comes back

        ghost = only((store / "ghosts").glob("*.rec"))
        assert ghost.name.startswith("ADOPT-0001-")
        _, history = read_record(ghost)
        assert [h["cmd"] for h in history] == ["echo one", "sleep 60"]

        banner = store / "pending" / "ADOPT-0001"
        assert banner.read_text().strip(), "an interesting ghost gets a rendered banner"
        assert "sleep 60" in banner.read_text()
        assert "sleep 60" in out, "and the banner is printed on the way in"

    def test_a_pane_that_only_sat_at_a_prompt_gets_no_banner(self, pane, store):
        pane("QUIET-0001").run([])                                # dies, having done nothing
        pane("QUIET-0001").run(["exit"])

        banner = store / "pending" / "QUIET-0001"
        assert banner.exists(), "the marker still appears, for the prompt glyph"
        assert banner.read_text() == "", "but there is nothing worth interrupting for"

    def test_a_banner_survives_later_crashes_that_ran_nothing(self, pane, store):
        pane("AGAIN-0001").run(["echo one", "sleep 60"])          # dies mid-command
        pane("AGAIN-0001").run([])                                # restored, dies idle
        out = pane("AGAIN-0001").run(["exit"])                    # restored again

        banner = store / "pending" / "AGAIN-0001"
        assert "sleep 60" in banner.read_text()
        assert "sleep 60" in out, "the second restart still says what the pane was for"

    def test_a_later_crash_with_commands_replaces_the_banner(self, pane, store):
        pane("NEWER-0001").run(["sleep 61"])
        pane("NEWER-0001").run(["sleep 62"])
        pane("NEWER-0001").run(["exit"])

        text = (store / "pending" / "NEWER-0001").read_text()
        assert "running  sleep 62" in text

    def test_the_banner_ends_with_what_gets_revived(self, pane, store):
        pane("ORDER-0001").run(["echo one", "echo two", "sleep 60"])
        pane("ORDER-0001").run(["exit"])

        text = (store / "pending" / "ORDER-0001").read_text()
        assert text.index("echo one") < text.index("echo two") < text.index("running  sleep 60")

    def test_a_shell_that_only_ran_revive_keeps_the_real_banner(self, pane, store, revive_init):
        pane("OWN-0001").run(["sleep 61"])
        pane("OWN-0001", extra_init=revive_init).run(["revive ls"])
        pane("OWN-0001").run(["exit"])

        assert "running  sleep 61" in (store / "pending" / "OWN-0001").read_text()

    def test_a_crash_during_a_picked_up_command_keeps_that_command(self, pane, store, revive_init):
        pane("PICK-0001").run(["sleep 61"])
        pane("PICK-0001", extra_init=revive_init).run(["revive", "y"])   # dies in the re-run
        pane("PICK-0001").run(["exit"])

        text = (store / "pending" / "PICK-0001").read_text()
        assert "running  sleep 61" in text
        assert "running  revive" not in text

    def test_a_live_owner_is_not_robbed_of_its_pane(self, pane, store):
        """A nested interactive shell must not adopt the outer shell's record."""
        live = store / "live"
        live.mkdir(parents=True)
        lstart = subprocess.run(["ps", "-o", "lstart=", "-p", str(os.getpid())],
                                capture_output=True, text=True).stdout.strip()
        rec = live / "NESTED-0001.rec"
        rec.write_text(f"guid\tNESTED-0001\npid\t{os.getpid()}\n"
                       f"lstart\t{lstart.replace(' ', '%20').replace(':', '%3A')}\n"
                       "cmd\touter%20command\n")
        before = rec.read_text()

        pane("NESTED-0001").run(["echo inner", "exit"])

        assert list((store / "ghosts").glob("*.rec")) == [], \
            "a live owner means this shell is nested, not a replacement"
        assert rec.read_text() == before, "and the nested shell writes nothing"


@pytest.mark.usefixtures("_fish_available")
class TestTolerance:
    def test_a_torn_record_still_yields_a_banner(self, pane, store):
        pane("TORN-0001").run(["echo one", "sleep 60"])
        rec = only((store / "live").glob("*.rec"))
        with rec.open("a") as fh:
            fh.write("cmd\tinterrupted-mid-w")     # a power cut lands here

        pane("TORN-0001").run(["exit"])
        banner = store / "pending" / "TORN-0001"
        assert "sleep 60" in banner.read_text()
