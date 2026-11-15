"""Hammerspoon seeds under plain lua5.4, with a stub `hs`.

Hammerspoon runs Lua 5.4, and `brew 'lua'` in the Brewfile installs lua5.4, so
the seeds' own logic can run here without Hammerspoon. harness.lua stubs only
what these seeds touch (hs.alert, hs.pasteboard, hs.urlevent) and calls the
bound URL handlers directly, so no hammerspoon:// URL is ever opened and the
real votes log is never written: every test passes its own paths.
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
HARNESS = HERE / "harness.lua"
LUA = shutil.which("lua5.4")

pytestmark = pytest.mark.skipif(LUA is None, reason="lua5.4 not installed")

STAMP = re.compile(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d")


def unesc(s):
    return re.sub(r"\\(.)", lambda m: {"t": "\t", "n": "\n"}.get(m[1], m[1]), s)


def drive(seed, *calls, config=None, tmp_path=None):
    """Run the harness. `calls` are lists like ["r", "v=ab121"]. Returns a list
    of (kind, text) records."""
    cfg = "-"
    if config is not None:
        cfg_file = tmp_path / "config.lua"
        body = ", ".join(f"{k} = [[{v}]]" for k, v in config.items())
        cfg_file.write_text(f"return {{ {body} }}\n", encoding="utf-8")
        cfg = str(cfg_file)
    argv = [LUA, str(HARNESS), seed, cfg]
    for i, call in enumerate(calls):
        if i:
            argv.append("--")
        argv.extend(call)
    r = subprocess.run(argv, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    recs = []
    for line in r.stdout.splitlines():
        kind, _, text = line.partition("\t")
        recs.append((kind, unesc(text)))
    assert not [t for k, t in recs if k == "ERROR"], recs
    return recs


def alerts(recs):
    return [t for k, t in recs if k == "ALERT"]


# --------------------------------------------------------------------------
# rolevote
# --------------------------------------------------------------------------


@pytest.fixture
def vote(tmp_path):
    """Run rolevote against a temp rolls.tsv; return (records, votes rows)."""
    votes = tmp_path / "state" / "votes.tsv"
    rolls = tmp_path / "rolls.tsv"

    def _run(*calls, rolls_text=None):
        if rolls_text is not None:
            rolls.write_text(rolls_text, encoding="utf-8")
        recs = drive("seeds.rolevote", *calls, tmp_path=tmp_path,
                     config={"votes": votes, "rolls": rolls})
        rows = []
        if votes.exists():
            rows = [l.split("\t") for l in votes.read_text(encoding="utf-8").splitlines()]
        return recs, rows

    return _run


ROLLS = "2026-11-15 10:00:00\tab12\tHolo\tSPICE & WOLF\n"


def test_each_slot_maps_to_place_kind_and_vote(vote):
    calls = [["r", f"v=ab12{d}"] for d in "12345678"]
    _, rows = vote(*calls, rolls_text=ROLLS)
    got = [tuple(r[2:6]) for r in rows]
    assert got == [
        ("opener", "up", "character", "Holo"),
        ("opener", "down", "character", "Holo"),
        ("opener", "up", "universe", "SPICE & WOLF"),
        ("opener", "down", "universe", "SPICE & WOLF"),
        ("closer", "up", "character", "Holo"),
        ("closer", "down", "character", "Holo"),
        ("closer", "up", "universe", "SPICE & WOLF"),
        ("closer", "down", "universe", "SPICE & WOLF"),
    ]


def test_a_vote_row_has_eight_fields(vote):
    _, rows = vote(["r", "v=ab121"], rolls_text=ROLLS)
    (row,) = rows
    assert len(row) == 8
    assert STAMP.fullmatch(row[0])
    assert row[1] == "ab12"
    assert row[6] == "2026-11-15 10:00:00"  # the roll's own time
    assert row[7] == ""  # the short form stores no line


def test_alert_names_what_was_voted_on(vote):
    recs, _ = vote(["r", "v=ab121"], ["r", "v=ab124"], rolls_text=ROLLS)
    assert alerts(recs) == ["+ Holo", "− SPICE & WOLF"]


def test_newest_roll_wins_when_an_id_repeats(vote):
    rolls = ROLLS + "2026-11-15 11:00:00\tab12\tViral\tGURREN LAGANN\n"
    _, rows = vote(["r", "v=ab121"], rolls_text=rolls)
    assert rows[0][5:7] == ["Viral", "2026-11-15 11:00:00"]


def test_unknown_id_is_recorded_and_flagged(vote):
    recs, rows = vote(["r", "v=zzzz1"], rolls_text=ROLLS)
    assert alerts(recs) == ["+ unknown vote id zzzz"]
    assert rows[0][1:7] == ["zzzz", "opener", "up", "character", "", ""]


def test_missing_roll_log_is_an_unknown_id_not_a_crash(vote):
    recs, rows = vote(["r", "v=ab121"])
    assert alerts(recs) == ["+ unknown vote id ab12"]
    assert len(rows) == 1


@pytest.mark.parametrize("v", ["ab120", "ab129", "ab12", "ab1211", "AB121", "ab-21", ""])
def test_bad_short_links_write_nothing(vote, v):
    recs, rows = vote(["r", f"v={v}"], rolls_text=ROLLS)
    assert alerts(recs) == ["rolevote: bad link"]
    assert rows == []


def test_long_form_cleans_tabs_and_newlines(vote):
    recs, rows = vote(["rate", "vote=down", "kind=universe",
                       "name=A\tB", "line=one\ntwo"])
    (row,) = rows
    assert row[1:8] == ["", "", "down", "universe", "A B", "", "one two"]
    assert alerts(recs) == ["− A B"]


@pytest.mark.parametrize("params", [
    ["vote=sideways", "kind=character", "name=X"],
    ["vote=up", "kind=planet", "name=X"],
    ["vote=up", "kind=character"],
    ["vote=up", "kind=character", "name="],
])
def test_bad_long_links_write_nothing(vote, params):
    recs, rows = vote(["rate", *params])
    assert alerts(recs) == ["rolevote: bad link"]
    assert rows == []


def test_unwritable_votes_path_alerts(tmp_path):
    blocker = tmp_path / "file"
    blocker.write_text("x")
    recs = drive("seeds.rolevote", ["r", "v=ab121"], tmp_path=tmp_path,
                 config={"votes": blocker / "sub" / "votes.tsv",
                         "rolls": tmp_path / "rolls.tsv"})
    (msg,) = alerts(recs)
    assert msg.startswith("rolevote: cannot write")


def test_rolevote_stop_unbinds_both_events(tmp_path):
    recs = drive("seeds.rolevote", ["__stop"], tmp_path=tmp_path,
                 config={"votes": tmp_path / "v.tsv", "rolls": tmp_path / "r.tsv"})
    assert [t for k, t in recs if k == "BOUND"] == []


def test_rolevote_binds_r_and_rate(tmp_path):
    recs = drive("seeds.rolevote", tmp_path=tmp_path,
                 config={"votes": tmp_path / "v.tsv", "rolls": tmp_path / "r.tsv"})
    assert [t for k, t in recs if k == "BOUND"] == ["r", "rate"]


# --------------------------------------------------------------------------
# copylink
# --------------------------------------------------------------------------


def test_copy_puts_the_text_on_the_clipboard_silently():
    # Hammerspoon has already URL-decoded the params, so %0A arrives as "\n".
    recs = drive("seeds.copylink", ["copy", "text=ls -la\npwd"])
    assert [t for k, t in recs if k == "PASTE"] == ["ls -la\npwd"]
    assert alerts(recs) == []


@pytest.mark.parametrize("call", [["copy"], ["copy", "text="]])
def test_copy_without_text_alerts_and_copies_nothing(call):
    recs = drive("seeds.copylink", call)
    assert [k for k, _ in recs if k == "PASTE"] == []
    assert alerts(recs) == ["copylink: no text in link"]


def test_copylink_stop_unbinds():
    assert [t for k, t in drive("seeds.copylink") if k == "BOUND"] == ["copy"]
    assert [t for k, t in drive("seeds.copylink", ["__stop"]) if k == "BOUND"] == []
