"""lib/python/run_tests.py -- how `cmds test <arg>` picks what to run."""

import sys
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
    assert calls == [("all", [], ["bin/astro", "bin/ytdl", "bin/exocortex-id"])]


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
    monkeypatch.setattr(run_tests, "stream", lambda cmd: (seen.append(cmd), (0, []))[1])
    run_tests.run_pytest([CHPWD, TRASH], ["dep"], ["-v"])
    cmd = seen[0]
    i = cmd.index("pytest", cmd.index("dep"))
    assert cmd[i + 1:i + 4] == [str(CHPWD), str(TRASH), "-v"]


def test_run_pytest_cov_without_source_path_covers_every_target(monkeypatch):
    seen = []
    monkeypatch.setattr(run_tests, "stream", lambda cmd: (seen.append(cmd), (0, []))[1])
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
