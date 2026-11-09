"""fish/functions/dashboard-parts.fish -- the P indicator for plan files."""

import os
import subprocess
from pathlib import Path

import pytest

DASHBOARD = Path(__file__).resolve().parents[2] / "fish" / "functions" / "dashboard-parts.fish"


@pytest.fixture
def parts(tmp_path):
    home = tmp_path / "home"
    work = tmp_path / "work"
    home.mkdir()
    (work / ".cc").mkdir(parents=True)

    def run():
        # `cmds` is stubbed so the @ indicator cannot call the real command.
        script = f"function cmds; end; set -e __revive_pending; source {DASHBOARD}; dashboard-parts"
        result = subprocess.run(
            ["fish", "--no-config", "-c", script],
            cwd=work, env={**os.environ, "HOME": str(home)},
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, result.stderr
        return result.stdout.split()

    run.work = work
    return run


def test_a_plan_at_the_top_of_cc_shows_p(parts):
    (parts.work / ".cc" / "PLAN-x.md").write_text("")
    assert "P" in parts()


def test_a_plan_in_the_plans_folder_shows_p(parts):
    plans = parts.work / ".cc" / "plans"
    plans.mkdir()
    (plans / "PLAN-x.md").write_text("")
    assert "P" in parts()


def test_a_missing_plans_folder_does_not_hide_a_top_level_plan(parts):
    """`find` reports the missing folder and exits nonzero, and still lists .cc."""
    (parts.work / ".cc" / "PLAN-x.md").write_text("")
    assert not (parts.work / ".cc" / "plans").exists()
    assert "P" in parts()


def test_a_plan_nested_in_another_folder_does_not_show_p(parts):
    misc = parts.work / ".cc" / "misc"
    misc.mkdir()
    (misc / "PLAN-x.md").write_text("")
    assert "P" not in parts()


def test_no_plans_does_not_show_p(parts):
    assert "P" not in parts()
