"""fish/functions/ccs.fish -- the launch flags a resume has to pass again.

Claude Code does not persist --system-prompt and friends, so an entry that only
records the session id resumes the akr-assistant without its persona. Pins the
flags making it into the entry and back out intact.
"""

import json
import os
import subprocess
from pathlib import Path

CCS = Path(__file__).resolve().parents[2] / "fish" / "functions" / "ccs.fish"
KEY = CCS.parent / "_cc_worktree_key.fish"


def fish(code, state):
    # --no-config disables autoloading from ~/.config/fish/functions, so every
    # function ccs.fish calls from another file is sourced here explicitly.
    # Without KEY, _ccs_open_register still exits 0 but records cwd "".
    r = subprocess.run(["fish", "--no-config", "-c", f"source {CCS}\nsource {KEY}\n{code}"],
                       capture_output=True,
                       text=True, stdin=subprocess.DEVNULL, timeout=30,
                       env={**os.environ, "XDG_STATE_HOME": str(state)})
    assert r.returncode == 0, r.stderr
    return r.stdout


def flags(state, *args):
    quoted = " ".join("'" + a.replace("\\", "\\\\").replace("'", "\\'") + "'" for a in args)
    out = fish(f"_ccs_launch_flags {quoted} | string split0 | string escape", state)
    return [line for line in out.splitlines()]


def test_only_session_shaping_flags_survive(tmp_path):
    got = flags(tmp_path, "--process-label", "akr", "--resume", "abc", "--model=opus",
                "--dangerously-skip-permissions", "do the thing", "--continue")
    assert got == ["--process-label", "akr", "--model=opus",
                   "--dangerously-skip-permissions"], \
        "the initial prompt would be sent again as a new message; --resume twice fails"


def test_a_value_that_looks_like_a_flag_is_kept_as_the_value(tmp_path):
    assert flags(tmp_path, "--system-prompt", "--resume") == ["--system-prompt", "--resume"]


def test_the_entry_round_trips_a_multi_line_prompt(tmp_path):
    """jq 1.6 parses a `--args` value starting with `--` as its own option, and
    truncates NUL-split raw input at the first multi-line element; both were
    tried first."""
    out = fish(
        "set f (_ccs_open_register $fish_pid (_ccs_launch_flags --process-label akr "
        "--system-prompt 'one\ntwo' | string split0))\n"
        "echo $f\n"
        "set l (jq -j '(.argv // [])[] | (., \"\\u0000\")' $f | string split0)\n"
        "count $l",
        tmp_path)
    path, n = out.split()
    assert json.loads(Path(path).read_text())["argv"] == \
        ["--process-label", "akr", "--system-prompt", "one\ntwo"]
    assert n == "4"


def test_no_flags_records_an_empty_list(tmp_path):
    path = fish("_ccs_open_register $fish_pid", tmp_path).strip()
    assert json.loads(Path(path).read_text())["argv"] == []


def test_a_clean_exit_hands_the_flags_to_the_saved_record(tmp_path):
    """The entry is deleted on a clean exit, so a saved session resumed from
    the picker used to come back without its --system-prompt."""
    home = tmp_path / "home"
    work = tmp_path / "work"
    work.mkdir()
    saved = home / "Cloud" / "cc-sessions" / str(work).lstrip("/") / "sessions.json"
    saved.parent.mkdir(parents=True)
    saved.write_text(json.dumps([{"id": "sid-1", "ts": "t", "title": "kept"},
                                 {"id": "other", "ts": "t", "title": "x"}]))
    key = CCS.parent / "_cc_worktree_key.fish"
    r = subprocess.run(
        ["fish", "--no-config", "-c",
         f"source {CCS}; source {key}; cd {work}\n"
         "set f (_ccs_open_register $fish_pid (_ccs_launch_flags --system-prompt 'a\nb' | string split0))\n"
         "jq '.session_id = \"sid-1\"' $f > $f.x; and mv $f.x $f\n"
         "_ccs_open_finalize $fish_pid\n"
         "if test -f $f; echo STILL-THERE; end"],
        capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30,
        env={**os.environ, "HOME": str(home), "XDG_STATE_HOME": str(tmp_path / "state")})
    assert r.returncode == 0, r.stderr
    assert "STILL-THERE" not in r.stdout
    records = {e["id"]: e for e in json.loads(saved.read_text())}
    assert records["sid-1"]["argv"] == ["--system-prompt", "a\nb"]
    assert records["sid-1"]["title"] == "kept"
    assert "argv" not in records["other"]
