"""nvim sessions for `revive`: nvim/lua/revive_session.lua, the `nvim` fish
wrapper that turns it on, and the journal and pick-up that carry the session.

The pty tests drive real fish and real nvim. nvim runs with a test init that
loads only the module, so no plugins are involved. See docs/revive.md.
"""

import json
import os
import re
import shutil
import subprocess

import pytest

DOTFILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TRAILER = '" vim: set ft=vim :'

pytestmark = pytest.mark.skipif(shutil.which("nvim") is None, reason="nvim is not on PATH")


@pytest.fixture
def work(tmp_path):
    """A folder with three files, an nvim init that loads only the module, and
    XDG folders so the test nvims leave nothing in the real home."""
    w = tmp_path / "w"
    w.mkdir()
    for name in ("f1.txt", "f2.txt", "f3.txt"):
        (w / name).write_text("line\n" * 50)
    init = tmp_path / "nvim-init.lua"
    init.write_text(
        f'package.path = "{DOTFILES}/nvim/lua/?.lua;" .. package.path\n'
        "require('revive_session').setup()\n"
    )
    env = {}
    for var in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        d = tmp_path / var.lower()
        d.mkdir()
        env[var] = str(d)
    return {"dir": w, "init": init, "env": env}


def nvim_pane(pane, work, guid, extra=""):
    return pane(guid, extra_init=f"source {DOTFILES}/fish/functions/nvim.fish\n"
                                 f"cd {work['dir']}\n" + extra,
                env=work["env"])


def sessions(folder):
    return sorted(folder.glob("*.vim")) if folder.is_dir() else []


# ---------------------------------------------------------------- pty wiring

class TestPane:
    def test_a_power_cut_leaves_the_session_and_the_next_shell_adopts_it(self, pane, store, work):
        start = f"nvim -u {work['init']} -c 'vsplit f2.txt' -c 'tabnew f3.txt' f1.txt"
        nvim_pane(pane, work, "NV-0001").run([start, None, None], powercut=True)

        live = only(sessions(store / "live" / "NV-0001.nvim"))
        text = live.read_text()
        assert text.rstrip("\n").endswith(TRAILER)
        assert [l.split()[-1] for l in text.splitlines() if l.startswith("badd ")] == \
            ["f1.txt", "f2.txt", "f3.txt"]

        nvim_pane(pane, work, "NV-0001").run(["exit"])
        ghost = only((store / "ghosts").glob("NV-0001-*.rec"))
        moved = only(sessions(ghost.with_name(ghost.name[:-4] + ".nvim")))
        assert moved.read_text() == text, "the session travels with its record"
        banner = (store / "pending" / "NV-0001").read_text()
        assert "✎ nvim  f1.txt, f2.txt, f3.txt" in banner
        assert "revive to reopen nvim" in banner

    def test_a_clean_quit_leaves_no_session(self, pane, store, work):
        nvim_pane(pane, work, "NV-0002").run(
            [f"nvim -u {work['init']} f1.txt", None, ":qa", None], powercut=True)
        assert sessions(store / "live" / "NV-0002.nvim") == []

    def test_closing_the_pane_removes_the_folder(self, pane, store, work):
        nvim_pane(pane, work, "NV-0003").run(
            [f"nvim -u {work['init']} f1.txt", None, ":qa", None, "exit"])
        assert not (store / "live" / "NV-0003.nvim").exists()

    def test_only_the_wrapper_turns_it_on(self, pane, store, work):
        nvim_pane(pane, work, "NV-0004").run(
            [f"command nvim -u {work['init']} f1.txt", None], powercut=True)
        assert sessions(store / "live" / "NV-0004.nvim") == []

    def test_a_session_left_by_a_crashed_nvim_is_cleared(self, pane, store, work):
        folder = store / "live" / "NV-0005.nvim"
        folder.mkdir(parents=True)
        (folder / "999.vim").write_text("badd +0 old.txt\n" + TRAILER + "\n")
        (folder / "998.vim.tmp").write_text("")
        nvim_pane(pane, work, "NV-0005").run(["echo hi"])
        assert list(folder.iterdir()) == [], \
            "with no job left, no nvim of this shell can own a session file"


def only(paths):
    paths = list(paths)
    assert len(paths) == 1, f"expected exactly one, got {paths}"
    return paths[0]


# ------------------------------------------------------------------ pick-up

@pytest.fixture
def ghost_with_session(store, work):
    """A ghost of pane NV-PICK whose shell ran `v`, with one nvim session."""
    (store / "ghosts").mkdir(parents=True)
    rec = store / "ghosts" / "NV-PICK-100.rec"
    rec.write_text(f"guid\tNV-PICK\ncwd\t{work['dir']}\ncmd\tv\n")
    folder = store / "ghosts" / "NV-PICK-100.nvim"
    folder.mkdir()
    (folder / "123.vim").write_text(
        f"cd {work['dir']}\nbadd +0 f1.txt\nbadd +0 gone.txt\n{TRAILER}\n")
    return rec


STUB = 'function nvim; echo "NVIM-ARGS $argv"; end\n'


class TestPickUp:
    def test_yes_reopens_the_session_in_nvim(self, pane, store, work, revive_init,
                                             ghost_with_session):
        out = pane("NV-PICK", extra_init=revive_init + STUB).run(["revive", "", None, None])
        assert "nvim had open: f1.txt, gone.txt · 1 missing" in out
        # fish's prompt codes share the line, so search rather than match
        args = re.findall(r"NVIM-ARGS [^\r\n]*", out)
        assert len(args) == 1 and "-S " in args[0] and "/reopen/NV-PICK-100.nvim-" in args[0] \
            and args[0].endswith("/123.vim"), out
        assert list((store / "reopen").iterdir()) == [], "used, then removed"
        assert not ghost_with_session.exists()
        assert not (store / "ghosts" / "NV-PICK-100.nvim").exists()

    def test_no_falls_through_to_the_command(self, pane, store, work, revive_init,
                                             ghost_with_session):
        out = pane("NV-PICK", extra_init=revive_init + STUB).run(["revive", "n", "n", None])
        assert "Reopen them in nvim?" in out
        assert "Run it again? [Y/n]" in out, "`n` still offers the command, here `v`"
        assert "NVIM-ARGS" not in out
        assert list((store / "reopen").iterdir()) == []

    def test_a_second_nvim_is_kept_and_named(self, pane, store, work, revive_init,
                                            ghost_with_session):
        older = store / "ghosts" / "NV-PICK-100.nvim" / "77.vim"
        older.write_text(f"cd {work['dir']}\nbadd +0 f2.txt\n{TRAILER}\n")
        os.utime(older, (1, 1))
        out = pane("NV-PICK", extra_init=revive_init + STUB).run(["revive", "", None, None])
        assert "another nvim: nvim -S " in out and "/77.vim" in out
        assert re.findall(r"NVIM-ARGS [^\r\n]*123\.vim", out), "the newest is reopened"
        kept = list((store / "reopen").rglob("*.vim"))
        assert [p.name for p in kept] == ["77.vim"], "the other stays, for a day"


# ------------------------------------------------------- the module, headless

def headless(work, tmp_path, script, dirvar):
    """Run the module in headless nvim; the script writes facts to `out`."""
    out = tmp_path / "facts.json"
    path = tmp_path / "t.vim"
    path.write_text(script.replace("OUT", str(out)))
    env = dict(os.environ, REVIVE_NVIM_DIR=dirvar, **work["env"])
    subprocess.run(["nvim", "--headless", "-u", str(work["init"]), "-S", str(path), "-c", "qa!"],
                   cwd=work["dir"], env=env, timeout=30, capture_output=True)
    assert out.exists(), "the headless script did not get to the end"
    return json.loads(out.read_text())


SAVE = 'lua require("revive_session")._save()\nlua vim.wait(400)\n'


class TestModule:
    def test_children_cannot_claim_the_pane(self, work, tmp_path):
        facts = headless(work, tmp_path, SAVE + (
            "let f = {}\n"
            "let f.child = system('printenv REVIVE_NVIM_DIR')\n"
            "let f.so = &sessionoptions\n"
            "let f.this = v:this_session\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(tmp_path / "d"))
        assert facts["child"] == ""
        assert facts["so"] == "blank,buffers,curdir,folds,help,tabpages,winsize,terminal", \
            "the user's sessionoptions are put back after a save"
        assert facts["this"] == "", "SessionSave must not see the pane file"

    def test_terminals_help_and_plugin_buffers_are_left_out(self, work, tmp_path):
        d = tmp_path / "d"
        facts = headless(work, tmp_path, (
            "edit f1.txt\n"
            "split | terminal\n"
            "help help\n"
            "new | file undotree_2 | setlocal buftype=nofile\n"
            + SAVE +
            "let f = {}\n"
            f"let f.body = readfile(glob('{d}/*.vim'))\n"
            "let f.listed = getbufinfo({'buflisted': 1})->map({_, b -> b.name})\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(d))
        body = "\n".join(facts["body"])
        assert "term://" not in body, "a restored terminal would re-run its command"
        assert "undotree_2" not in body
        assert "help.txt" not in body
        assert re.search(r"^badd \+\d+ f1\.txt$", body, re.M)
        assert any(n.endswith("undotree_2") for n in facts["listed"]), \
            "a plugin buffer is unlisted only for the length of the save"

    def test_an_unchanged_layout_is_not_rewritten(self, work, tmp_path):
        d = tmp_path / "d"
        facts = headless(work, tmp_path, (
            "edit f1.txt\n" + SAVE +
            "let f = {}\n"
            f"let f.first = getftime(glob('{d}/*.vim'))\n"
            "lua vim.wait(1100)\n" + SAVE +
            f"let f.second = getftime(glob('{d}/*.vim'))\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(d))
        assert facts["first"] > 0
        assert facts["second"] == facts["first"]

    def test_a_cursor_pause_does_not_delay_a_layout_save(self, work, tmp_path):
        # CursorHold fires 200 ms into every pause, so it arrives right after
        # most layout changes; it once pushed their save back to 2 s
        d = tmp_path / "d"
        facts = headless(work, tmp_path, (
            "edit f1.txt\n"
            f"call delete(glob('{d}/*.vim'))\n"
            "doautocmd revive_session WinNew\n"
            "doautocmd revive_session CursorHold\n"
            "lua vim.wait(800)\n"
            f"let f = {{'saved': len(glob('{d}/*.vim', 0, 1))}}\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(d))
        assert facts["saved"] == 1

    def test_a_save_does_not_set_off_another(self, work, tmp_path):
        # Unlisting a plugin buffer fires BufDelete, which the module listens to
        facts = headless(work, tmp_path, (
            "edit f1.txt\n"
            "split | terminal\n"
            "new | file undo_x | setlocal buftype=nofile\n"
            "lua vim.wait(800)\n"
            "lua _G.n = 0; vim.api.nvim_create_autocmd({'BufDelete', 'BufAdd'}, "
            "{callback = function() _G.n = _G.n + 1 end})\n"
            "lua vim.wait(1500)\n"
            "let f = {'events': luaeval('_G.n')}\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(tmp_path / "d"))
        assert facts["events"] == 0, "saving in a loop, and telling every plugin"

    def test_a_clean_exit_removes_the_file(self, work, tmp_path):
        d = tmp_path / "d"
        facts = headless(work, tmp_path, (
            "edit f1.txt\n" + SAVE +
            f"let f = {{'during': len(glob('{d}/*.vim', 0, 1))}}\n"
            "call writefile([json_encode(f)], 'OUT')\n"), str(d))
        assert facts["during"] == 1
        assert sessions(d) == [] and list(d.glob("*.tmp")) == []

    def test_an_empty_variable_turns_it_off(self, work, tmp_path):
        facts = headless(work, tmp_path, (
            "edit f1.txt\n" + SAVE +
            "let f = {'group': exists('#revive_session')}\n"
            "call writefile([json_encode(f)], 'OUT')\n"), "")
        assert facts["group"] == 0
