"""fish/functions/chpwd.fish -- the capped lists and the once-a-day reminder."""

import os
import subprocess
from pathlib import Path

import pytest

CHPWD = Path(__file__).resolve().parents[2] / "fish" / "functions" / "chpwd.fish"


@pytest.fixture
def fish(tmp_path):
    home = tmp_path / "home"
    work = tmp_path / "work"
    home.mkdir()
    (work / ".cc").mkdir(parents=True)

    def run(script):
        result = subprocess.run(
            ["fish", "--no-config", "-c", f"source {CHPWD}; {script}"],
            cwd=work, env={**os.environ, "HOME": str(home)},
            capture_output=True, text=True, timeout=30,
        )
        assert result.returncode == 0, result.stderr
        return result.stdout

    run.work = work
    return run


def make_plans(work, count):
    """PLAN-01 is the oldest and the highest number is the newest."""
    for n in range(1, count + 1):
        plan = work / ".cc" / f"PLAN-{n:02}.md"
        plan.write_text("")
        os.utime(plan, (1000 + n, 1000 + n))


def test_plans_print_newest_first_with_a_count_of_the_rest(fish):
    make_plans(fish.work, 8)
    lines = fish("showPlans").splitlines()
    assert lines[0] == "&> Plans:"
    assert [l.strip() for l in lines[1:6]] == [
        f".cc/PLAN-{n:02}.md" for n in (8, 7, 6, 5, 4)]
    assert "... 3 more" in lines[6]
    assert len(lines) == 7


def test_a_list_at_the_limit_has_no_more_line(fish):
    make_plans(fish.work, 5)
    out = fish("showPlans")
    assert out.count("PLAN-") == 5
    assert "more" not in out


def test_no_plans_prints_nothing(fish):
    assert fish("showPlans") == ""


def test_claude_sessions_are_capped_per_section_and_sorted(fish):
    script = r"""
    function ccs
        echo '  Open'
        for day in 01 02 03 04 05 06 07
            echo "  row$day — 2026-11-$day 10:00"
        end
        echo ''
        echo '  Saved'
        echo '  old — 2026-03-14 10:38'
        echo '  new — 2026-10-01 09:00'
    end
    listClaudeSessions
    """
    lines = fish(script).splitlines()
    assert lines[1] == "  Open"
    assert "row07" in lines[2] and "row03" in lines[6]
    assert "... 2 more" in lines[7]
    assert lines[8] == "  Saved"
    assert "new" in lines[9] and "old" in lines[10]
    assert len(lines) == 11


def test_the_reminder_prints_once_per_interval(fish):
    show = "cache global try-out-reminder 1440 showTryOutReminder"
    assert "Remember to try out" in fish(show)
    assert fish(show) == ""
