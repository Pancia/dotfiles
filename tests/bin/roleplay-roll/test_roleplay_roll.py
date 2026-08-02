"""Tests for bin/roleplay-roll, the roleplay character picker.

This script runs as a UserPromptSubmit hook on every prompt in every project, so
its failure modes are unusually expensive: bad stdout is parsed as JSON by Claude
Code, and a non-zero exit or an error message degrades every prompt the user
sends. The fail-open tests below are the load-bearing ones.
"""

import json
import re
import subprocess
from collections import Counter
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parents[3]
SCRIPT = DOTFILES / "bin" / "roleplay-roll"
REAL_ROSTER = DOTFILES / "ai" / "roleplay" / "roster.tsv"


def run(*args, roster=None, seed=None, odds=None):
    """Invoke the script, optionally against a substitute roster."""
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(Path.home())}
    if roster is not None:
        env["ROLEPLAY_ROSTER"] = str(roster)
    if seed is not None:
        env["ROLEPLAY_SEED"] = str(seed)
    if odds is not None:
        env["ROLEPLAY_CATCHPHRASE"] = str(odds)
    return subprocess.run(
        [str(SCRIPT), *args], capture_output=True, text=True, env=env
    )


@pytest.fixture
def roster(tmp_path):
    """Factory writing a substitute roster file."""

    def _write(text):
        p = tmp_path / "roster.tsv"
        p.write_text(text, encoding="utf-8")
        return p

    return _write


# --------------------------------------------------------------------------
# Fail-open. Every one of these must print nothing and exit 0.
# --------------------------------------------------------------------------


def test_missing_roster_is_silent_and_succeeds(tmp_path):
    r = run(roster=tmp_path / "does-not-exist.tsv")
    assert r.returncode == 0
    assert r.stdout == ""


def test_empty_roster_is_silent_and_succeeds(roster):
    r = run(roster=roster(""))
    assert r.returncode == 0
    assert r.stdout == ""


def test_roster_of_only_comments_is_silent(roster):
    r = run(roster=roster("# just a comment\n# and another\n"))
    assert r.returncode == 0
    assert r.stdout == ""


def test_roster_with_no_valid_rows_is_silent(roster):
    """Rows with fewer than 4 fields are skipped, leaving nothing to pick."""
    r = run(roster=roster("A | B\nC | D | E\n"))
    assert r.returncode == 0
    assert r.stdout == ""


def test_unreadable_roster_is_silent(roster):
    p = roster("U | Name | X | traits\n")
    p.chmod(0o000)
    try:
        r = run(roster=p)
        assert r.returncode == 0
        assert r.stdout == ""
    finally:
        p.chmod(0o644)


# --------------------------------------------------------------------------
# Hook output contract
# --------------------------------------------------------------------------


def test_hook_emits_valid_json_envelope(roster):
    r = run(roster=roster("MYTH | Hermes | 🪽 | Fast · a messenger\n"))
    assert r.returncode == 0
    payload = json.loads(r.stdout)
    out = payload["hookSpecificOutput"]
    assert out["hookEventName"] == "UserPromptSubmit"
    assert "Hermes" in out["additionalContext"]
    assert "MYTH" in out["additionalContext"]
    assert "a messenger" in out["additionalContext"]


def test_quotes_in_roster_do_not_break_json(roster):
    """The real roster contains quoted phrases; unescaped they'd emit bad JSON
    on every prompt, which is exactly the kind of break that stays silent."""
    p = roster('U | Name | X | he said "vast and infinite" and left\n')
    r = run(roster=p)
    payload = json.loads(r.stdout)
    assert '"vast and infinite"' in payload["hookSpecificOutput"]["additionalContext"]


def test_backslashes_in_roster_do_not_break_json(roster):
    p = roster("U | Name | X | a path C:\\\\temp and more\n")
    r = run(roster=p)
    payload = json.loads(r.stdout)
    assert "additionalContext" in payload["hookSpecificOutput"]


def test_plain_mode_format(roster):
    r = run("--plain", roster=roster("MYTH | Hermes | 🪽 | Fast · a messenger\n"))
    assert r.stdout.strip() == "«Hermes» 🪽 MYTH — Fast · a messenger"


def test_seed_makes_the_roll_reproducible(roster):
    p = roster(
        "\n".join(f"U{i} | Name{i} | X | traits {i}" for i in range(20)) + "\n"
    )
    first = run("--plain", roster=p, seed=4242).stdout
    again = run("--plain", roster=p, seed=4242).stdout
    assert first == again
    assert first != ""

    # ...and the seed must actually be *used*. Same-seed-same-output alone is
    # equally satisfied by a hardcoded srand(1), which is how this test first
    # let that mutation through.
    varied = {run("--plain", roster=p, seed=s).stdout for s in range(100, 116)}
    assert len(varied) > 1, "every seed produced the same roll -- seed is ignored"


def test_comment_line_with_pipes_is_not_a_character(roster):
    """The shipped roster documents its own format in a comment:

        # Format:  UNIVERSE | Character Name | emoji | traits

    That line has four pipe-separated fields, so the NF<4 guard does not stop
    it. Only the leading-# rule does. If that rule breaks, 'Character Name'
    quietly joins the cast.
    """
    p = roster(
        "# Format:  UNIVERSE | Character Name | emoji | traits\n"
        "REAL | Actual | X | genuine traits\n"
    )
    seen = {run("--plain", roster=p).stdout.strip() for _ in range(30)}
    assert seen == {"«Actual» X REAL — genuine traits"}, seen


def test_whitespace_around_fields_is_trimmed(roster):
    r = run("--plain", roster=roster("   MYTH   |   Hermes   | 🪽 |   Fast   \n"))
    assert r.stdout.strip() == "«Hermes» 🪽 MYTH — Fast"


# --------------------------------------------------------------------------
# The two-stage roll. This is the property that makes the design what it is.
# --------------------------------------------------------------------------


def test_universe_selection_is_even_not_flat(roster):
    """A universe of 1 must beat a universe of 49 half the time.

    Under the two-stage roll each universe is 1/2, so SOLO lands ~50%. Under a
    flat per-character roll it would land 1/50 = 2%. The gap is enormous, so a
    loose threshold still kills the mutation without ever flaking.
    """
    lines = ["SOLO | Only | X | the sole member"]
    lines += [f"CROWD | Name{i} | X | member {i}" for i in range(49)]
    p = roster("\n".join(lines) + "\n")

    universes = Counter()
    for _ in range(240):
        out = run("--plain", roster=p).stdout
        universes["SOLO" if "SOLO" in out else "CROWD"] += 1

    # Expect ~120 under two-stage, ~5 under flat.
    assert universes["SOLO"] > 60, (
        f"SOLO landed {universes['SOLO']}/240 — looks like a flat roll, "
        "not a two-stage one"
    )
    assert universes["CROWD"] > 60


def test_every_character_in_a_universe_is_reachable(roster):
    p = roster("\n".join(f"U | Name{i} | X | traits" for i in range(5)) + "\n")
    seen = {run("--plain", roster=p).stdout.split("»")[0] for _ in range(200)}
    assert len(seen) == 5, f"only reached {len(seen)} of 5 characters"


# --------------------------------------------------------------------------
# Signature lines: the 5th field, and the ROLEPLAY_CATCHPHRASE roll that
# decides whether it is unlocked. Replaces an earlier unconditional ban.
# --------------------------------------------------------------------------

SIG_ROSTER = "U | Hero | X | brave | THE FAMOUS LINE\n"


# 1/1 and 0/1 are always/never claims, so they must be asserted over many runs.
# A single shot passes by luck at the 1/3 default (1 time in 3, and 2 in 3
# respectively), which let a "ROLEPLAY_CATCHPHRASE is ignored" mutation survive.
_EXTREME_RUNS = 30


def test_signature_always_unlocked_at_one_over_one(roster):
    p = roster(SIG_ROSTER)
    outs = [run("--plain", roster=p, odds="1/1").stdout for _ in range(_EXTREME_RUNS)]
    assert all("SIGNATURE LINE UNLOCKED" in o for o in outs)
    assert all("THE FAMOUS LINE" in o for o in outs)


def test_signature_never_unlocked_at_zero_over_one(roster):
    p = roster(SIG_ROSTER)
    outs = [run("--plain", roster=p, odds="0/1").stdout for _ in range(_EXTREME_RUNS)]
    assert all("spent this roll" in o for o in outs)
    # Still named even when spent, so it can be deliberately avoided.
    assert all("THE FAMOUS LINE" in o for o in outs)


def test_character_without_signature_gets_no_directive(roster):
    out = run("--plain", roster=roster("U | Plain | X | just traits\n")).stdout
    assert "SIGNATURE" not in out.upper()
    assert "spent this roll" not in out


@pytest.mark.parametrize("bad", ["garbage", "1/0", "-1/3", "", "//", "1/2/3x", "a/b"])
def test_unparseable_odds_fall_back_to_the_default(roster, bad):
    """Fail-open: a bad value must not disable the feature or wedge it on."""
    p = roster(SIG_ROSTER)
    unlocked = sum(
        "UNLOCKED" in run("--plain", roster=p, odds=bad).stdout for _ in range(120)
    )
    assert 10 < unlocked < 90, (
        f"odds={bad!r} gave {unlocked}/120 unlocked -- expected the ~1/3 default, "
        "not always-on or always-off"
    )


def test_default_odds_are_one_in_three(roster):
    p = roster(SIG_ROSTER)
    unlocked = sum("UNLOCKED" in run("--plain", roster=p).stdout for _ in range(200))
    # Expect ~67 of 200 (sd ~6.7). The band excludes always, never, and 1/2.
    assert 40 <= unlocked <= 95, f"{unlocked}/200 unlocked -- not a 1/3 rate"


def test_odds_are_honoured_between_the_extremes(roster):
    p = roster(SIG_ROSTER)
    half = sum("UNLOCKED" in run("--plain", roster=p, odds="1/2").stdout for _ in range(160))
    assert 55 <= half <= 105, f"1/2 gave {half}/160"


def test_signature_roll_happens_after_character_selection(roster):
    """Stage 3 must consume its rand() *after* the two picks.

    If it ran first it would shift the stream, so merely adding a signature
    field would change which character a given seed lands on. Comparing two
    same-seed runs at different odds cannot detect that -- both shift together
    -- so this compares a roster with signatures against one without.
    """
    plain = "\n".join(f"U{i} | Name{i} | X | traits" for i in range(20)) + "\n"
    signed = "\n".join(f"U{i} | Name{i} | X | traits | LINE{i}" for i in range(20)) + "\n"

    p = roster(plain)
    without = run("--plain", roster=p, seed=99).stdout.split("»")[0]
    p.write_text(signed, encoding="utf-8")
    with_sig = run("--plain", roster=p, seed=99).stdout.split("»")[0]

    assert without == with_sig, (
        "adding signature lines changed which character seed 99 picked -- "
        "the signature rand() is being consumed before the character picks"
    )


def test_check_reports_signature_configuration(roster):
    out = run("--check", roster=roster(SIG_ROSTER + "U | Other | Y | plain\n")).stdout
    assert "signature lines: 1 characters have one" in out
    assert "1/3" in out


def test_real_roster_has_signature_lines():
    out = run("--check", roster=REAL_ROSTER).stdout
    m = re.search(r"signature lines: (\d+) characters", out)
    assert m and int(m.group(1)) >= 5, out


# --------------------------------------------------------------------------
# --list / --check
# --------------------------------------------------------------------------


def test_check_reports_duplicate_emoji(roster):
    r = run("--check", roster=roster("U | A | 🔥 | x\nU | B | 🔥 | y\n"))
    assert "DUPLICATE EMOJI" in r.stdout


def test_check_reports_duplicate_names(roster):
    r = run("--check", roster=roster("U | A | 🔥 | x\nV | A | 💧 | y\n"))
    assert "DUPLICATE NAME" in r.stdout


def test_check_is_clean_on_a_good_roster(roster):
    r = run("--check", roster=roster("U | A | 🔥 | x\nU | B | 💧 | y\n"))
    assert "no duplicate names or emoji" in r.stdout
    assert "DUPLICATE" not in r.stdout


def test_list_shows_every_character(roster):
    p = roster("U | Alpha | 🔥 | x\nV | Beta | 💧 | y\n")
    out = run("--list", roster=p).stdout
    assert "Alpha" in out and "Beta" in out
    assert "2 characters across 2 universes" in out


# --------------------------------------------------------------------------
# The roster that actually ships. Guards typos made while adding characters.
# --------------------------------------------------------------------------


def test_real_roster_is_valid():
    r = run("--check", roster=REAL_ROSTER)
    assert r.returncode == 0
    assert "DUPLICATE" not in r.stdout, r.stdout
    assert "no duplicate names or emoji" in r.stdout


def test_real_roster_rows_have_four_or_five_fields():
    """4 fields, or 5 when the character declares a signature line."""
    bad = []
    for n, line in enumerate(REAL_ROSTER.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line.split("|")) not in (4, 5):
            bad.append(f"line {n}: {line!r}")
    assert not bad, "malformed roster rows:\n" + "\n".join(bad)


def test_real_roster_comments_are_not_characters():
    """Directly assert the format-documenting comment never becomes a member."""
    out = run("--list", roster=REAL_ROSTER).stdout
    assert "Character Name" not in out
    for line in out.splitlines():
        assert not line.strip().startswith("#"), f"comment leaked into roster: {line}"


def test_real_roster_produces_a_usable_roll():
    payload = json.loads(run(roster=REAL_ROSTER).stdout)
    ctx = payload["hookSpecificOutput"]["additionalContext"]
    assert ctx.startswith("[🎭 Character Roll: «")
    assert ctx.endswith("]")
