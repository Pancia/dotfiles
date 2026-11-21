"""lib/python/run_tests.py -- how `cmds test <arg>` picks what to run."""

import os
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(DOTFILES / "lib" / "python"))

import run_tests  # noqa: E402


@pytest.fixture
def dispatch(monkeypatch):
    """Run main() with the runners replaced. Returns (exit code, calls)."""
    calls = []

    def fake_pytest(target, deps, extra, source_path=None):
        calls.append(("pytest", target, deps, extra, source_path))
        return 0, {}

    def fake_component(component, extra):
        calls.append(("component", component, extra))
        return 0, {}

    def fake_all(extra, components=None):
        calls.append(("all", extra, components))
        return 0

    monkeypatch.setattr(run_tests, "run_pytest", fake_pytest)
    monkeypatch.setattr(run_tests, "run_component", fake_component)
    monkeypatch.setattr(run_tests, "run_all", fake_all)

    def run(*argv):
        monkeypatch.setattr(sys, "argv", ["run_tests.py", *argv])
        with pytest.raises(SystemExit) as caught:
            run_tests.main()
        return caught.value.code, calls

    return run


def test_a_file_path_runs_only_that_file(dispatch):
    code, calls = dispatch("fish/test_chpwd.py", "-v")
    assert code == 0
    assert calls == [("pytest", run_tests.TESTS_DIR / "fish/test_chpwd.py", [], ["-v"],
                      "fish/functions")]


def test_a_documented_file_path_uses_its_components_source_path(dispatch):
    _, calls = dispatch("bin/ytdl/test_ytdl.py")
    assert calls == [("pytest", run_tests.TESTS_DIR / "bin/ytdl/test_ytdl.py", [], [],
                      "bin/ytdl")]


def test_a_file_path_gets_its_components_dependencies(dispatch):
    _, calls = dispatch("bin/astro/test_zr.py")
    assert calls[0][:3] == ("pytest", run_tests.TESTS_DIR / "bin/astro/test_zr.py",
                            ["kerykeion", "pyswisseph"])


def test_a_node_id_is_checked_on_the_file_part(dispatch):
    code, calls = dispatch("fish/test_chpwd.py::test_x")
    assert code == 0
    assert calls[0][1] == run_tests.TESTS_DIR / "fish/test_chpwd.py::test_x"


def test_a_leading_tests_folder_is_stripped(dispatch):
    _, calls = dispatch("tests/fish/test_chpwd.py::test_x")
    assert calls[0][1] == run_tests.TESTS_DIR / "fish/test_chpwd.py::test_x"


def test_a_component_under_tests_runs_the_component(dispatch):
    _, calls = dispatch("tests/lib/python", "-k", "foo")
    assert calls == [("component", "lib/python", ["-k", "foo"])]


def test_a_bare_component_and_an_alias_still_run_the_component(dispatch):
    _, calls = dispatch("fish")
    assert calls == [("component", "fish", [])]
    _, calls = dispatch("yt")
    assert calls[-1] == ("component", "services/youtube_transcribe", [])


def test_a_parent_covers_every_component_under_it(dispatch):
    _, calls = dispatch("bin")
    assert calls == [("all", [], ["bin/astro", "bin/ytdl", "bin/cc-peers", "bin/scratch",
                                  "bin/exocortex-id"])]


def test_flags_only_still_run_everything(dispatch):
    _, calls = dispatch("-k", "cache")
    assert calls == [("all", ["-k", "cache"], None)]


def test_an_unknown_path_exits_2_instead_of_running_everything(dispatch, capsys):
    code, calls = dispatch("nosuch/test_thing.py")
    assert code == 2
    assert calls == []
    assert "nosuch/test_thing.py" in capsys.readouterr().err


CHPWD = run_tests.TESTS_DIR / "fish/test_chpwd.py"
TRASH = run_tests.TESTS_DIR / "fish/test_trash.py"
ZR = run_tests.TESTS_DIR / "bin/astro/test_zr.py"


def test_two_files_in_one_component_share_one_run(dispatch):
    """The second path used to reach pytest unresolved, which then ran nothing."""
    code, calls = dispatch("fish/test_chpwd.py", "tests/fish/test_trash.py", "-v")
    assert code == 0
    assert calls == [("pytest", [CHPWD, TRASH], [], ["-v"], "fish/functions")]


def test_a_second_node_id_is_resolved_too(dispatch):
    _, calls = dispatch("fish/test_chpwd.py", "fish/test_trash.py::test_x")
    assert calls[0][1] == [CHPWD, run_tests.TESTS_DIR / "fish/test_trash.py::test_x"]


def test_files_in_two_components_run_separately_with_their_own_deps(dispatch, capsys):
    code, calls = dispatch("fish/test_chpwd.py", "bin/astro/test_zr.py", "-x")
    assert code == 0
    assert calls == [
        ("pytest", [CHPWD], [], ["-x"], "fish/functions"),
        ("pytest", [ZR], ["kerykeion", "pyswisseph"], ["-x"], None),
    ]
    out = capsys.readouterr().out
    assert "cmds test summary" in out
    assert "fish" in out and "bin/astro" in out


def test_several_components_report_the_failing_exit_code(dispatch, monkeypatch, capsys):
    def fake_pytest(target, deps, extra, source_path=None):
        return (1 if target == [ZR] else 0), {"passed": 3}

    monkeypatch.setattr(run_tests, "run_pytest", fake_pytest)
    code, _ = dispatch("fish/test_chpwd.py", "bin/astro/test_zr.py")
    assert code == 1
    assert "FAIL  bin/astro" in capsys.readouterr().out


def fake_clock(monkeypatch, *readings):
    """Make time.monotonic() return these readings in turn."""
    ticks = iter(readings)
    monkeypatch.setattr(run_tests.time, "monotonic", lambda: next(ticks))


def test_summary_shows_each_components_time(dispatch, monkeypatch, capsys):
    def fake_pytest(target, deps, extra, source_path=None):
        return (1 if target == [ZR] else 0), {"passed": 3}

    monkeypatch.setattr(run_tests, "run_pytest", fake_pytest)
    # fish runs from 100.0 to 112.34, bin/astro from 200.0 to 201.0.
    fake_clock(monkeypatch, 100.0, 112.34, 200.0, 201.0)
    dispatch("fish/test_chpwd.py", "bin/astro/test_zr.py")
    lines = capsys.readouterr().out.splitlines()
    assert "  PASS  fish       3 passed  [12.3s]" in lines
    assert "  FAIL  bin/astro  3 passed  [1.0s]" in lines
    assert lines[-2] == "           6 passed  [13.3s]"


def test_run_all_times_each_component_and_the_total(monkeypatch, capsys):
    monkeypatch.setattr(run_tests, "run_component", lambda c, extra: (0, {"passed": 1}))
    fake_clock(monkeypatch, 0.0, 2.0, 5.0, 5.25)
    assert run_tests.run_all([], ["hooks", "fish"]) == 0
    lines = capsys.readouterr().out.splitlines()
    assert "  PASS  hooks  1 passed  [2.0s]" in lines
    assert "  PASS  fish   1 passed  [0.2s]" in lines
    assert lines[-2] == "  PASSED — 2 components, 2 passed  [2.2s]"


def test_a_whole_component_absorbs_files_inside_it(dispatch):
    _, calls = dispatch("fish/test_chpwd.py", "fish")
    assert calls == [("component", "fish", [])]


def test_a_component_and_a_file_elsewhere_both_run(dispatch):
    _, calls = dispatch("hooks", "fish/test_chpwd.py")
    assert calls == [("component", "hooks", []),
                     ("pytest", [CHPWD], [], [], "fish/functions")]


def test_a_flags_value_is_never_read_as_a_path(dispatch):
    _, calls = dispatch("fish/test_chpwd.py", "-k", "fish/test_trash.py",
                        "--deselect", "nosuch.py::t")
    assert calls == [("pytest", CHPWD, [], ["-k", "fish/test_trash.py",
                                            "--deselect", "nosuch.py::t"],
                      "fish/functions")]


def test_an_unknown_second_path_exits_2_and_runs_nothing(dispatch, capsys):
    code, calls = dispatch("fish/test_chpwd.py", "fish/test_nosuch.py", "-v")
    assert code == 2
    assert calls == []
    assert "fish/test_nosuch.py" in capsys.readouterr().err


def test_run_pytest_passes_every_target(monkeypatch):
    seen = []
    monkeypatch.setattr(run_tests, "stream", lambda cmd, env=None: (seen.append(cmd), (0, []))[1])
    run_tests.run_pytest([CHPWD, TRASH], ["dep"], ["-v"])
    cmd = seen[0]
    i = cmd.index("pytest", cmd.index("dep"))
    assert cmd[i + 1:i + 4] == [str(CHPWD), str(TRASH), "-v"]


def test_run_pytest_cov_without_source_path_covers_every_target(monkeypatch):
    seen = []
    monkeypatch.setattr(run_tests, "stream", lambda cmd, env=None: (seen.append(cmd), (0, []))[1])
    run_tests.run_pytest([CHPWD, TRASH], [], ["--cov"])
    assert f"--cov={CHPWD}" in seen[0] and f"--cov={TRASH}" in seen[0]
    assert "--cov" not in seen[0]


def test_a_component_name_is_not_matched_as_a_string_prefix(dispatch, monkeypatch, tmp_path):
    """`fishing/x.py` is not inside the `fish` component."""
    (tmp_path / "fishing").mkdir()
    (tmp_path / "fishing" / "x.py").write_text("")
    monkeypatch.setattr(run_tests, "TESTS_DIR", tmp_path)
    _, calls = dispatch("fishing/x.py")
    assert calls == [("pytest", tmp_path / "fishing/x.py", [], [], None)]


# --- Isolation: every pytest runs under a throwaway home -----------------------

TEST_HOME = Path("/tmp/dotfiles-test-home-fake")
TREE_BIN = str(run_tests.DOTFILES / "bin")


def _env(base, home=TEST_HOME, uv_cache="/uv/cache", uv_python="/uv/python"):
    return run_tests.isolated_env(base, home, uv_cache, uv_python)


def test_isolated_env_points_home_and_xdg_into_the_test_home():
    base = {
        "HOME": "/Users/real",
        "XDG_CONFIG_HOME": "/Users/real/.config",
        "XDG_STATE_HOME": "/Users/real/.local/state",
        "PATH": "/usr/bin",
    }
    before = dict(base)
    env = _env(base)
    assert env["HOME"] == str(TEST_HOME)
    assert env["XDG_CONFIG_HOME"] == str(TEST_HOME / ".config")
    assert env["XDG_DATA_HOME"] == str(TEST_HOME / ".local/share")
    assert env["XDG_STATE_HOME"] == str(TEST_HOME / ".local/state")
    assert env["XDG_CACHE_HOME"] == str(TEST_HOME / ".cache")
    assert env["GIT_CONFIG_GLOBAL"] == str(TEST_HOME / ".gitconfig")
    assert env["GIT_CONFIG_NOSYSTEM"] == "1"
    assert env["JJ_CONFIG"] == str(TEST_HOME / ".config/jj/config.toml")
    assert env["JJ_USER"] == run_tests.TEST_USER
    assert env["JJ_EMAIL"] == run_tests.TEST_EMAIL
    assert not any("/Users/real" in v for v in env.values())
    assert base == before, "isolated_env must not change its input"


def test_isolated_env_keeps_the_uv_folders():
    base = {"HOME": "/Users/real", "UV_CACHE_DIR": "/elsewhere", "PATH": ""}
    env = _env(base, uv_cache="/Users/real/.cache/uv",
               uv_python="/Users/real/.local/share/uv/python")
    assert env["UV_CACHE_DIR"] == "/Users/real/.cache/uv"
    assert env["UV_PYTHON_INSTALL_DIR"] == "/Users/real/.local/share/uv/python"


def test_isolated_env_drops_terminal_and_claude_variables():
    dropped = {
        "TMUX": "/tmp/tmux-501/default,1,0",
        "TMUX_PANE": "%3",
        "ITERM_SESSION_ID": "w0t0p0:ABC",
        "TERM_SESSION_ID": "w0t0p0:ABC",
        "CLAUDECODE": "1",
        "SVC_FS_CONFIG": "/x",
        "SVC_TMUX_SOCKET": "svc-x",
        "CLAUDE_CODE_SESSION_ID": "s",
        "CLAUDE_PROJECT_DIR": "/p",
        "CCS_TITLE": "t",
        "CC_JJ_SESSION": "j",
    }
    kept = {"TERM": "xterm-256color", "LANG": "en_US.UTF-8", "TMPDIR": "/tmp/x",
            "TMUX_PLUGIN_MANAGER_PATH": "/t", "ITERM_PROFILE": "Default"}
    env = _env({**dropped, **kept, "HOME": "/Users/real", "PATH": "/usr/bin"})
    assert not set(dropped) & set(env)
    for key, value in kept.items():
        assert env[key] == value


def test_isolated_env_puts_the_tree_bin_first_on_path():
    base = {
        "HOME": "/Users/real",
        "PATH": os.pathsep.join([
            "/usr/local/bin",
            "/Users/real/dotfiles/bin",
            "/Volumes/clone/dotfiles/bin/",
            TREE_BIN,
            "/usr/bin",
            "/bin",
        ]),
    }
    path = _env(base)["PATH"].split(os.pathsep)
    assert path == [TREE_BIN, "/usr/local/bin", "/usr/bin", "/bin"]


def test_isolated_env_with_no_path_still_has_the_tree_bin():
    assert _env({"HOME": "/Users/real"})["PATH"] == TREE_BIN


def test_test_home_links_dotfiles_to_the_tree_under_test():
    with run_tests.test_home() as home:
        assert home.name.startswith("dotfiles-test-home-")
        assert Path(tempfile.gettempdir()).resolve() in home.parents
        link = home / "dotfiles"
        assert link.is_symlink()
        assert link.resolve() == run_tests.DOTFILES
        assert (link / "lib/python/run_tests.py").is_file()
        for sub in (".config", ".local/share", ".local/state", ".cache"):
            assert (home / sub).is_dir()

        def git_get(key):
            return subprocess.run(
                ["git", "config", "--file", str(home / ".gitconfig"), "--get", key],
                capture_output=True, text=True, check=True,
            ).stdout.strip()

        assert git_get("user.name") == run_tests.TEST_USER
        assert git_get("user.email") == run_tests.TEST_EMAIL
        assert git_get("init.defaultBranch") == "master"
        vcs = tomllib.loads((home / ".config/jj/config.toml").read_text())
        assert vcs["user"] == {"name": run_tests.TEST_USER, "email": run_tests.TEST_EMAIL}
    assert not home.exists(), "the test home is removed on exit"


def test_run_pytest_runs_under_the_isolated_env(monkeypatch):
    seen = {}

    def fake_stream(cmd, env=None):
        home = Path(env["HOME"])
        seen.update(cmd=cmd, env=env, home=home,
                    linked=(home / "dotfiles").resolve() == run_tests.DOTFILES)
        return 0, ["==== 1 passed in 0.01s ====\n"]

    monkeypatch.setattr(run_tests, "stream", fake_stream)
    monkeypatch.setattr(run_tests, "uv_folders", lambda: ("/uv/cache", "/uv/python"))
    monkeypatch.setenv("TMUX", "/tmp/tmux-501/default,1,0")
    monkeypatch.setenv("CLAUDECODE", "1")
    monkeypatch.setenv("HOME", "/Users/real")

    code, counts = run_tests.run_pytest(CHPWD, [], ["-v"])

    assert (code, counts) == (0, {"passed": 1})
    env = seen["env"]
    assert seen["home"].name.startswith("dotfiles-test-home-")
    assert seen["linked"]
    assert env == run_tests.isolated_env(
        {**os.environ}, seen["home"], "/uv/cache", "/uv/python")
    assert "TMUX" not in env and "CLAUDECODE" not in env
    assert env["UV_CACHE_DIR"] == "/uv/cache"
    assert not seen["home"].exists(), "the test home is gone once pytest returns"


def test_an_opted_out_component_inherits_the_environment(monkeypatch, capsys):
    seen = []
    monkeypatch.setattr(run_tests, "stream",
                        lambda cmd, env=None: (seen.append(env), (0, []))[1])
    fish = {**run_tests.COMPONENTS["fish"], "isolation": False,
            "isolation_reason": "needs the real home for a reason"}
    monkeypatch.setitem(run_tests.COMPONENTS, "fish", fish)
    run_tests.run_pytest(CHPWD, [], [])
    assert seen == [None]
    assert "isolation off: needs the real home for a reason" in capsys.readouterr().out

