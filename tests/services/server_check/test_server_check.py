#!/usr/bin/env python3
"""Tests for services/server-check/script.sh, the daily Vultr server check.

Every run fakes the server's SSH answer (SERVER_CHECK_STATE) and the Headscale
health page (a file:// URL), so no case touches the network. The fixture always
sets SERVER_CHECK_DRY=1, or a problem case would send a real notification, and
SERVER_CHECK_RETRY_DELAY=0, or each problem case would sleep 120 s.

show.sh is only parsed, never run: it ends with `exec fish -l`, and fish startup
runs _ENSURE_SERVICES, which loads the real LaunchAgents.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

DIR = Path(__file__).resolve().parents[3] / "services" / "server-check"
SCRIPT = DIR / "script.sh"
SHOW = DIR / "show.sh"

HEALTHY = "reachable musicdisk navidrome"


@pytest.fixture
def check(tmp_path):
    def run(state, health="pass"):
        url_file = tmp_path / "health"
        if health is None:
            url_file.unlink(missing_ok=True)
        else:
            url_file.write_text(health + "\n")
        env = {k: v for k, v in os.environ.items() if not k.startswith("SERVER_CHECK_")}
        env.update(SERVER_CHECK_DRY="1", SERVER_CHECK_RETRY_DELAY="0",
                   SERVER_CHECK_URL="file://%s" % url_file,
                   SERVER_CHECK_STATE=state,
                   SERVER_CHECK_HOST="nobody@invalid.invalid")
        r = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True,
                           text=True, timeout=30)
        assert r.returncode == 0, r.stderr
        return r.stdout
    return run


def problem(out):
    """The notified message, or None when the check passed."""
    m = re.search(r"^would notify: (.*)$", out, re.M)
    if m is None:
        assert re.search(r": ok$", out, re.M), out
    else:
        assert "PROBLEM: " + m.group(1) in out
    return m and m.group(1)


def test_healthy_server_is_silent(check):
    assert problem(check(HEALTHY)) is None


def test_unlocked_disk_warns(check):
    assert problem(check(HEALTHY + " unlocked")) == \
        "encrypted disk is unlocked: lock it with unmnt when done"


def test_missing_music_disk(check):
    assert problem(check("reachable navidrome")) == "music disk not mounted"


def test_navidrome_down(check):
    assert problem(check("reachable musicdisk")) == "Navidrome is not answering"


def test_empty_answer_means_unreachable(check):
    assert problem(check("")) == "SSH: server unreachable"


def test_unreachable_is_not_reachable(check):
    # A bare substring grep would read "unreachable" as "reachable".
    assert problem(check("unreachable musicdisk navidrome")) == "SSH: server unreachable"


def test_failed_health_page(check):
    assert problem(check(HEALTHY, health=None)) == "Headscale or its certificate"
    assert problem(check(HEALTHY, health="fail")) == "Headscale or its certificate"


def test_problems_are_joined(check):
    assert problem(check(HEALTHY + " unlocked", health=None)) == \
        "Headscale or its certificate; encrypted disk is unlocked: lock it with unmnt when done"


# ---------------------------------------------------------------- drift check

def messages():
    found = re.findall(r'problems\+=\("([^"]+)"\)', SCRIPT.read_text())
    assert found, "no problems+=(...) lines found in script.sh"
    return found


def help_patterns():
    # Only the per-problem help matches: `[[ "$latest" == *"..."* ]]`.
    found = re.findall(r'== \*"([^"]+)"\*', SHOW.read_text())
    assert found, "no help patterns found in show.sh"
    return found


def test_every_message_has_help():
    pats = help_patterns()
    missing = [m for m in messages() if not any(p in m for p in pats)]
    assert not missing, "show.sh has no help for: %s" % missing


def test_every_help_section_matches_a_message():
    msgs = messages()
    stale = [p for p in help_patterns() if not any(p in m for m in msgs)]
    assert not stale, "show.sh help matches no message in script.sh: %s" % stale
