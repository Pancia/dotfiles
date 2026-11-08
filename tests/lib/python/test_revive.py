"""lib/python/revive.py -- the read side of the per-pane journal.

The journal is written by fish; these tests build records by hand, which is also
the point: the reader has to survive whatever a power cut left on disk.
"""

import os
import time
from urllib.parse import quote

import pytest

import revive


def enc(value):
    return quote(value, safe="")


def write_record(path, scalars=None, events=(), trailing=""):
    """events: ("cmd", "ls") / ("done", "0 12"). trailing: a torn final line."""
    lines = [f"{k}\t{enc(v)}" for k, v in (scalars or {}).items()]
    lines += [f"{k}\t{enc(v)}" for k, v in events]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n" + trailing)
    return path


@pytest.fixture
def store(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    monkeypatch.setattr(revive, "iterm_tree", lambda: {})
    return tmp_path / "term-sessions"


# ------------------------------------------------------------------ records

class TestRecord:
    def test_scalars_are_last_wins_and_commands_accumulate(self, store):
        p = write_record(
            store / "ghosts" / "G1-100.rec",
            {"guid": "G1", "cwd": "/one"},
            [("cmd", "echo one"), ("done", "0 5"), ("cwd", "/two"), ("cmd", "echo two")],
        )
        rec = revive.Record(p)
        assert rec.guid == "G1"
        assert rec.cwd == "/two", "a pane that cds twice is in the second directory"
        assert [h["cmd"] for h in rec.history] == ["echo one", "echo two"]

    def test_the_unfinished_command_is_what_it_was_doing(self, store):
        p = write_record(store / "ghosts" / "G2-100.rec", {"guid": "G2"},
                         [("cmd", "make"), ("done", "0 5"), ("cmd", "sleep 60")])
        rec = revive.Record(p)
        assert rec.running == "sleep 60"
        assert rec.last == "sleep 60"

    def test_a_finished_pane_reports_no_running_command(self, store):
        p = write_record(store / "ghosts" / "G3-100.rec", {"guid": "G3"},
                         [("cmd", "make"), ("done", "2 5")])
        rec = revive.Record(p)
        assert rec.running == ""
        assert rec.last == "make"

    def test_newlines_and_tabs_survive_the_round_trip(self, store):
        gnarly = "claude --system-prompt (cat p.txt\n| string collect)\tand\tmore"
        p = write_record(store / "ghosts" / "G4-100.rec", {"guid": "G4"},
                         [("cmd", gnarly)])
        assert revive.Record(p).running == gnarly

    def test_a_torn_final_line_is_dropped_not_the_record(self, store):
        p = write_record(store / "ghosts" / "G5-100.rec", {"guid": "G5"},
                         [("cmd", "echo one"), ("done", "0 5")],
                         trailing="cmd\techo%20tw")
        rec = revive.Record(p)
        assert [h["cmd"] for h in rec.history] == ["echo one"], \
            "the power cut landed mid-line; everything before it still counts"

    def test_junk_lines_are_skipped(self, store):
        p = store / "ghosts" / "G6-100.rec"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("guid\tG6\nnot a record line at all\n\ncmd\tls\n")
        rec = revive.Record(p)
        assert rec.guid == "G6"
        assert rec.running == "ls"

    def test_revive_is_not_part_of_the_story(self, store):
        p = write_record(store / "ghosts" / "G8-100.rec", {"guid": "G8"},
                         [("cmd", "make"), ("done", "0 5"), ("cmd", "revive")])
        rec = revive.Record(p)
        assert [h["cmd"] for h in rec.history] == ["make"]
        assert rec.running == "", "an unfinished `revive` is not what the pane was doing"

    def test_the_done_of_a_revive_does_not_close_the_command_before_it(self, store):
        p = write_record(store / "ghosts" / "G9-100.rec", {"guid": "G9"},
                         [("cmd", "sleep 60"), ("cmd", "revive ls"), ("done", "0 5")])
        assert revive.Record(p).running == "sleep 60"

    def test_a_picked_up_command_takes_the_done_of_its_revive(self, store):
        p = write_record(store / "ghosts" / "G10-100.rec", {"guid": "G10"},
                         [("cmd", "revive"), ("cmd", "make"), ("done", "2 5")])
        rec = revive.Record(p)
        assert rec.running == ""
        assert rec.history[-1]["code"] == "2"

    @pytest.mark.parametrize("cmd,own", [
        ("revive", True), ("  revive  ", True), ("revive 3", True),
        ("revive dismiss --all", True), ("revive prune --days 3", True),
        ("revive && make", False), ("reviver", False), ("echo revive", False),
    ])
    def test_what_counts_as_revive_itself(self, cmd, own):
        assert (revive.OWN_COMMAND.fullmatch(cmd) is not None) is own

    def test_an_empty_record_is_ignored_entirely(self, store):
        (store / "ghosts").mkdir(parents=True)
        (store / "ghosts" / "G7-100.rec").write_text("")
        assert revive.ghosts() == []


# --------------------------------------------------------------- the joins

class TestClaudeJoin:
    def test_the_newest_entry_at_or_before_the_ghost_wins(self):
        entries = [
            {"guid": "A", "started_at": 100, "title": "old", "session_id": "s1", "cwd": ""},
            {"guid": "A", "started_at": 200, "title": "right", "session_id": "s2", "cwd": ""},
            {"guid": "A", "started_at": 900, "title": "later", "session_id": "s3", "cwd": ""},
            {"guid": "B", "started_at": 150, "title": "other", "session_id": "s4", "cwd": ""},
        ]
        # One GUID with several entries is the real shape of this data, not an edge case
        assert revive.ccs_for(entries, "A", 500)["title"] == "right"
        assert revive.ccs_for(entries, "A", 50) is None
        assert revive.ccs_for(entries, "C", 500) is None


class TestPlacement:
    def test_a_ghost_whose_pane_came_back_is_located(self, store, monkeypatch):
        write_record(store / "ghosts" / "LIVE1-100.rec", {"guid": "LIVE1", "cwd": "/x"},
                     [("cmd", "ls")])
        monkeypatch.setattr(revive, "iterm_tree", lambda: {
            "LIVE1": {"window": "2", "tab": "1", "pane": "2", "tty": "/dev/ttys004", "name": "x"}})
        entry = revive.collect()[0]
        assert not entry.gone
        assert entry.where() == "window 2 · tab 1 · pane 2"

    def test_a_ghost_whose_pane_did_not_come_back_is_gone(self, store):
        write_record(store / "ghosts" / "DEAD1-100.rec", {"guid": "DEAD1", "cwd": "/x"},
                     [("cmd", "ls")])
        entry = revive.collect()[0]
        assert entry.gone
        assert entry.where() == "gone"

    def test_gone_panes_sort_after_the_ones_still_open(self, store, monkeypatch):
        write_record(store / "ghosts" / "GONE-100.rec", {"guid": "GONE"}, [("cmd", "a")])
        write_record(store / "ghosts" / "HERE-100.rec", {"guid": "HERE"}, [("cmd", "b")])
        monkeypatch.setattr(revive, "iterm_tree", lambda: {
            "HERE": {"window": "1", "tab": "1", "pane": "1", "tty": "", "name": ""}})
        assert [e.rec.guid for e in revive.collect()] == ["HERE", "GONE"]


# ------------------------------------------------------------------ verbs

class TestVerbs:
    def test_get_hands_fish_the_guid_not_the_filename(self, store, capsys):
        write_record(store / "ghosts" / "GET1-12345.rec",
                     {"guid": "GET1", "cwd": "/some/dir"}, [("cmd", "make world")])
        assert revive.cmd_get("1") == 0
        guid, cwd, session, cmd, entry, title = \
            capsys.readouterr().out.rstrip("\n").split("\t")
        assert (guid, cwd, cmd) == ("GET1", "/some/dir", "make world"), \
            "`revive go` focuses by GUID, so the filename's -<epoch> must not leak"
        assert (session, entry, title) == ("", "", "")

    def test_get_rejects_a_number_out_of_range(self, store, capsys):
        write_record(store / "ghosts" / "GET2-1.rec", {"guid": "GET2"}, [("cmd", "x")])
        assert revive.cmd_get("4") == 1

    def test_dismiss_removes_the_ghost_and_its_banner(self, store):
        write_record(store / "ghosts" / "DIS1-777.rec", {"guid": "DIS1"}, [("cmd", "x")])
        (store / "pending").mkdir(parents=True, exist_ok=True)
        (store / "pending" / "DIS1").write_text("banner text")

        assert revive.cmd_dismiss("--all") == 0
        assert list((store / "ghosts").glob("*.rec")) == []
        assert not (store / "pending" / "DIS1").exists(), \
            "the prompt glyph reads the pending marker, so it has to go too"

    def test_prune_keeps_what_is_still_recent(self, store):
        old = write_record(store / "ghosts" / "OLD-1.rec", {"guid": "OLD"}, [("cmd", "x")])
        new = write_record(store / "ghosts" / "NEW-2.rec", {"guid": "NEW"}, [("cmd", "x")])
        long_ago = time.time() - 60 * 86400
        import os
        os.utime(old, (long_ago, long_ago))

        assert revive.cmd_prune(30) == 0
        assert not old.exists()
        assert new.exists()

    def test_list_says_so_when_there_is_nothing(self, store, capsys):
        assert revive.main(["list"]) == 1
        assert "Nothing to revive" in capsys.readouterr().out


# ------------------------------------------------------------- the osascript

class TestTreeScript:
    def test_the_separator_is_bound_outside_the_tell_block(self):
        """Inside `tell application "iTerm2"`, `tab` is iTerm's own tab class.

        Using it as a separator there does not fail -- it silently writes the
        word "tab" into every field, and the join then matches nothing.
        """
        script = revive.TREE_SCRIPT
        assert script.index("set sep to") < script.index('tell application')
        body = script[script.index("tell application"):]
        assert " & tab & " not in body


class TestFormatting:
    @pytest.mark.parametrize("seconds,expected", [
        (5, "5s"), (300, "5m"), (7200, "2h"), (86400 * 3, "3d")])
    def test_ago(self, seconds, expected):
        assert revive.ago(seconds) == expected

    def test_elide_collapses_whitespace_and_truncates(self):
        assert revive.elide("a\n  b\tc") == "a b c"
        assert revive.elide("x" * 200).endswith("…")
        assert len(revive.elide("x" * 200, 40)) == 40


# ------------------------------------------------------- synthesised ghosts

@pytest.fixture
def one_claude_pane(store, monkeypatch):
    """A pane iTerm still has open, with a Claude session but no journal record."""
    monkeypatch.setattr(revive, "iterm_tree", lambda: {
        "OLD1": {"window": "6", "tab": "1", "pane": "1", "tty": "/dev/ttys004",
                 "name": "~/v/akashic (fish)"}})
    monkeypatch.setattr(revive, "ccs_entries", lambda: [
        {"guid": "OLD1", "started_at": 100, "title": "a crashed session",
         "session_id": "abc123", "cwd": "/Users/x/vault"}])
    monkeypatch.setattr(revive, "boot_time", lambda: 500.0)
    return store


class TestSynthesised:
    def test_a_pane_older_than_the_journal_still_shows_up(self, one_claude_pane):
        entry = revive.collect()[0]
        assert entry.synthetic
        assert entry.claude["title"] == "a crashed session"
        assert entry.where() == "window 6 · tab 1"

    def test_an_entry_from_after_the_boot_is_not_a_crash(self, store, monkeypatch):
        monkeypatch.setattr(revive, "iterm_tree", lambda: {
            "NEW1": {"window": "1", "tab": "1", "pane": "1", "tty": "", "name": ""}})
        monkeypatch.setattr(revive, "ccs_entries", lambda: [
            {"guid": "NEW1", "started_at": 900, "title": "still running",
             "session_id": "x", "cwd": "/tmp"}])
        monkeypatch.setattr(revive, "boot_time", lambda: 500.0)
        assert revive.collect() == []

    def test_a_real_ghost_wins_over_a_synthesised_one(self, one_claude_pane):
        write_record(one_claude_pane / "ghosts" / "OLD1-999.rec",
                     {"guid": "OLD1", "cwd": "/real"}, [("cmd", "nvim")])
        items = revive.collect()
        assert len(items) == 1
        assert not items[0].synthetic
        assert items[0].rec.running == "nvim"

    def test_dismissing_one_leaves_a_tombstone_so_it_stays_gone(self, one_claude_pane):
        assert len(revive.collect()) == 1
        assert revive.cmd_dismiss("1") == 0
        assert (one_claude_pane / "dismissed" / "OLD1").exists(), \
            "there is no file to delete, so the only way to remember is a marker"
        assert revive.collect() == []

    def test_the_listing_and_get_agree_on_the_numbering(self, one_claude_pane, capsys):
        """`revive 1` must act on the entry the listing printed as 1."""
        revive.render_list(tty=False)
        listing = capsys.readouterr().out
        assert "a crashed session" in listing

        assert revive.cmd_get("1") == 0
        guid, cwd, session, _, _, title = capsys.readouterr().out.rstrip("\n").split("\t")
        assert (guid, session, title) == ("OLD1", "abc123", "a crashed session")
        assert cwd == "/Users/x/vault"


# ------------------------------------------------------------ this pane

G = "9F67859D-B179-4E36-BF69-2F215B4B7C91"
LSTART = "Thu Sep 24 14:00:00 2026"


def shell_start():
    return time.mktime(time.strptime(LSTART, "%a %b %d %H:%M:%S %Y"))


def entry(started_at, sid, title="t", guid=G):
    return {"guid": guid, "started_at": started_at, "title": title,
            "session_id": sid, "cwd": "/v", "file": f"/open/{sid}.json"}


@pytest.fixture
def in_pane(store, monkeypatch):
    monkeypatch.setenv("ITERM_SESSION_ID", f"w1t11p0:{G}")
    monkeypatch.delenv("TMUX", raising=False)
    return store


class TestThisPane:
    def test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost(
            self, store, monkeypatch, capsys):
        monkeypatch.setenv("ITERM_SESSION_ID", f"w1t11p0:{G}")
        monkeypatch.setattr(revive, "ccs_entries", lambda: [])
        write_record(store / "ghosts" / f"{G}-100.rec", {"guid": G, "cwd": "/real"},
                     [("cmd", "make test")])
        newer = write_record(store / "ghosts" / f"{G}-200.rec", {"guid": G, "cwd": "/x"},
                             [("cmd", "revive")])
        os.utime(newer, (time.time() + 60, time.time() + 60))
        assert revive.cmd_get("here") == 0
        fields = capsys.readouterr().out.rstrip("\n").split("\t")
        assert fields[1] == "/real"
        assert fields[3] == "make test", "and `revive` is never offered back"

    def test_here_prints_what_gets_revived_after_the_history(
            self, store, monkeypatch, capsys):
        monkeypatch.setattr(revive, "ccs_entries", lambda: [])
        write_record(store / "ghosts" / f"{G}-100.rec", {"guid": G, "cwd": "/real"},
                     [("cmd", "one"), ("done", "0 1"), ("cmd", "two"), ("done", "0 1"),
                      ("cmd", "three")])
        assert revive.render_here(G, tty=False) == 0
        out = capsys.readouterr().out
        assert out.index("one") < out.index("two") < out.index("running  three")
        assert out.count("three") == 1, "the revived command is not also in recent"

    def test_the_session_join_is_bounded_by_the_dead_shell(self, in_pane, monkeypatch):
        """An older crash in the same pane is not this ghost's session.

        Only the guid linked them before, so a pane that crashed Claude weeks
        ago and was then idle at a prompt would have resumed the wrong one.
        """
        start = shell_start()
        write_record(in_pane / "ghosts" / f"{G}-{int(start) + 500}.rec",
                     {"guid": G, "lstart": LSTART, "cwd": "/v"}, [("cmd", "@@")])
        monkeypatch.setattr(revive, "ccs_entries", lambda: [
            entry(start - 86400, "weeks-old"), entry(start + 30, "right")])
        assert revive.collect()[0].claude["session_id"] == "right"

    def test_a_session_launched_after_the_last_write_still_joins(self, in_pane, monkeypatch):
        """Pins the `@@` miss: cmds starts Claude seconds after the shell
        journals the command, so bounding by the record's mtime lost it."""
        start = shell_start()
        rec = write_record(in_pane / "ghosts" / f"{G}-{int(start) + 500}.rec",
                           {"guid": G, "lstart": LSTART}, [("cmd", "@@")])
        import os
        os.utime(rec, (start + 10, start + 10))
        monkeypatch.setattr(revive, "ccs_entries", lambda: [entry(start + 14, "via-cmds")])
        assert revive.collect()[0].claude["session_id"] == "via-cmds"

    def test_a_session_from_the_adopting_shell_is_not_the_ghosts(self, in_pane, monkeypatch):
        start = shell_start()
        write_record(in_pane / "ghosts" / f"{G}-{int(start) + 500}.rec",
                     {"guid": G, "lstart": LSTART}, [("cmd", "ls")])
        monkeypatch.setattr(revive, "ccs_entries", lambda: [entry(start + 900, "newer")])
        assert revive.collect()[0].claude is None

    def test_get_here_finds_this_panes_ghost_not_the_newest(self, in_pane, capsys):
        write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G, "cwd": "/mine"},
                     [("cmd", "mine")])
        other = write_record(in_pane / "ghosts" / "OTHER-200.rec",
                             {"guid": "OTHER", "cwd": "/theirs"}, [("cmd", "theirs")])
        import os
        os.utime(other, (time.time() + 60, time.time() + 60))
        assert revive.cmd_get("here") == 0
        assert capsys.readouterr().out.split("\t")[1] == "/mine"

    def test_get_here_skips_later_deaths_that_ran_nothing(self, in_pane, capsys):
        import os
        write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G, "cwd": "/busy"},
                     [("cmd", "real work")])
        idle = write_record(in_pane / "ghosts" / f"{G}-200.rec", {"guid": G, "cwd": "/idle"})
        os.utime(idle, (time.time() + 60, time.time() + 60))
        assert revive.cmd_get("here") == 0
        assert capsys.readouterr().out.split("\t")[1] == "/busy"

    def test_get_here_falls_back_to_an_idle_ghost(self, in_pane, capsys):
        write_record(in_pane / "ghosts" / f"{G}-200.rec", {"guid": G, "cwd": "/idle"})
        assert revive.cmd_get("here") == 0
        assert capsys.readouterr().out.split("\t")[1] == "/idle"

    def test_prune_drops_the_banner_with_the_last_real_ghost(self, in_pane):
        import os
        old = write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G}, [("cmd", "x")])
        os.utime(old, (1000, 1000))
        write_record(in_pane / "ghosts" / f"{G}-200.rec", {"guid": G})   # recent, idle
        (in_pane / "pending").mkdir(parents=True, exist_ok=True)
        (in_pane / "pending" / G).write_text("banner")
        assert revive.cmd_prune(30) == 0
        assert not (in_pane / "pending" / G).exists()

    def test_prune_keeps_the_banner_while_a_real_ghost_remains(self, in_pane):
        import os
        old = write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G}, [("cmd", "x")])
        os.utime(old, (1000, 1000))
        write_record(in_pane / "ghosts" / f"{G}-200.rec", {"guid": G}, [("cmd", "y")])
        (in_pane / "pending").mkdir(parents=True, exist_ok=True)
        (in_pane / "pending" / G).write_text("banner")
        assert revive.cmd_prune(30) == 0
        assert (in_pane / "pending" / G).exists()

    def test_a_tmux_pane_does_not_claim_its_windows_ghost(self, in_pane, monkeypatch, capsys):
        write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G}, [("cmd", "x")])
        monkeypatch.setenv("TMUX", "/tmp/tmux-501/default,1,0")
        monkeypatch.setenv("TMUX_PANE", "%3")
        assert revive.cmd_get("here") == 1

    def test_a_pane_with_no_ghost_says_so(self, in_pane, capsys):
        write_record(in_pane / "ghosts" / "OTHER-1.rec", {"guid": "OTHER"}, [("cmd", "x")])
        assert revive.cmd_get("here") == 1
        assert "no ghost" in capsys.readouterr().err

    def test_the_listing_marks_this_pane(self, in_pane, capsys):
        write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G, "cwd": "/a"},
                     [("cmd", "x")])
        write_record(in_pane / "ghosts" / "OTHER-1.rec", {"guid": "OTHER", "cwd": "/b"},
                     [("cmd", "y")])
        revive.render_list(tty=False)
        marked = [l for l in capsys.readouterr().out.splitlines() if "this pane" in l]
        assert len(marked) == 1 and "/a" in marked[0]

    def test_dismiss_here_clears_the_banner_too(self, in_pane):
        write_record(in_pane / "ghosts" / f"{G}-100.rec", {"guid": G}, [("cmd", "x")])
        (in_pane / "pending").mkdir(parents=True, exist_ok=True)
        (in_pane / "pending" / G).write_text("banner")
        assert revive.cmd_dismiss("here") == 0
        assert not (in_pane / "pending" / G).exists()
        assert revive.collect() == []

    def test_a_synthesised_guid_is_not_mistaken_for_an_epoch(self, store):
        """A GUID's last group can be all digits; stripping it as a -<epoch>
        suffix would detach the ghost from its pane."""
        numeric = "9F67859D-B179-4E36-BF69-123456789012"
        rec = revive.Record(store / "ghosts" / f"{numeric}.rec")
        assert rec.pane_key == numeric
