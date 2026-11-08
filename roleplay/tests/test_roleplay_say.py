"""Tests for roleplay/bin/roleplay-say, using a stub in place of claude-p.

Nothing here calls a model. The stub records its arguments and stdin, so the tests
pin what the script sends and how it treats what comes back.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "roleplay-say"
JQ_DIR = Path(shutil.which("jq") or "/usr/bin/jq").parent

ROSTER = "TESTVERSE | Test Hero | 🧪 | stubborn · dry | 'the famous line'\n"
EXAMPLES = """### 🧪 Test Hero · `TESTVERSE`

> 🎭 **«Test Hero»** 🧪 `TESTVERSE` — *"one"*
> 🎭 **«Test Hero»** 🧪 `TESTVERSE` — *"two"*
> 🎭 **«Test Hero»** 🧪 `TESTVERSE` — *"three"*
> 🎭 **«Test Hero»** 🧪 `TESTVERSE` — *"four"*
> 🎭 **«Test Hero»** 🧪 `TESTVERSE` — *"SIGNATURE EXAMPLE"*

### 🐙 Someone Else · `OTHER`

> 🎭 **«Someone Else»** 🐙 `OTHER` — *"not mine"*
"""


class Env:
    def __init__(self, tmp_path):
        self.tmp = tmp_path
        self.stub_dir = tmp_path / "stub"
        self.stub_dir.mkdir()
        self.reply = tmp_path / "reply.json"
        self.set_reply({"structured_output": {"line": "A dry remark."}})
        (tmp_path / "roster.tsv").write_text(ROSTER, encoding="utf-8")
        (tmp_path / "examples.md").write_text(EXAMPLES, encoding="utf-8")
        self.write_stub(
            f'printf \'%s\\n\' "$@" > "{tmp_path}/argv"\n'
            f'cat > "{tmp_path}/stdin"\n'
            f'cat "{self.reply}"\n'
        )

    def write_stub(self, body):
        stub = self.stub_dir / "claude-p"
        stub.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
        stub.chmod(0o755)

    def set_reply(self, obj):
        self.reply.write_text(json.dumps(obj), encoding="utf-8")

    def run(self, *args, stdin="", extra_env=None):
        env = {
            "PATH": f"{self.stub_dir}:{JQ_DIR}:/usr/bin:/bin",
            "HOME": str(Path.home()),
            "ROLEPLAY_ROSTER": str(self.tmp / "roster.tsv"),
            "ROLEPLAY_EXAMPLES": str(self.tmp / "examples.md"),
            "ROLEPLAY_SEED": "1",
            "ROLEPLAY_CATCHPHRASE": "0/1",
            **(extra_env or {}),
        }
        return subprocess.run(
            [str(SCRIPT), *args], input=stdin, capture_output=True, text=True, env=env
        )

    @property
    def argv(self):
        return (self.tmp / "argv").read_text(encoding="utf-8").splitlines()

    @property
    def prompt(self):
        return (self.tmp / "stdin").read_text(encoding="utf-8")


@pytest.fixture
def e(tmp_path):
    return Env(tmp_path)


def test_stdout_is_exactly_the_finished_line(e):
    r = e.run("anything")
    assert r.returncode == 0
    assert r.stdout == '🎭 «Test Hero» 🧪 TESTVERSE — "A dry remark."\n'


def test_context_is_optional(e):
    assert e.run().returncode == 0
    assert "The work:" not in e.prompt


def test_words_become_the_context(e):
    e.run("fixing", "the", "login", "bug")
    assert "The work:\nfixing the login bug" in e.prompt


def test_stdin_is_used_with_a_dash(e):
    e.run("-", stdin="diff --git a/x b/x")
    assert "diff --git a/x b/x" in e.prompt


def test_stdin_is_ignored_without_a_dash(e):
    e.run(stdin="should not appear")
    assert "should not appear" not in e.prompt


def test_defaults_to_an_opener_on_haiku(e):
    e.run()
    assert "Kind: opener" in e.prompt
    assert e.argv[e.argv.index("--model") + 1] == "haiku"


def test_closer_and_model_flags(e):
    e.run("--closer", "-m", "sonnet", "done")
    assert "Kind: closer" in e.prompt
    assert e.argv[e.argv.index("--model") + 1] == "sonnet"


def test_only_this_characters_ordinary_examples_are_sent(e):
    e.run()
    assert '"four"' in e.prompt
    assert "SIGNATURE EXAMPLE" not in e.prompt
    assert "not mine" not in e.prompt


def test_quotes_from_the_model_are_not_doubled(e):
    e.set_reply({"structured_output": {"line": '"Already quoted."'}})
    assert e.run().stdout.endswith('— "Already quoted."\n')


def test_unknown_option_fails_before_any_model_call(e):
    r = e.run("--nope")
    assert r.returncode == 1 and r.stdout == ""
    assert not (e.tmp / "argv").exists()


def test_model_failure_is_loud(e):
    e.write_stub("cat > /dev/null\nexit 1\n")
    r = e.run("x")
    assert r.returncode == 1 and r.stdout == ""
    assert "model call failed" in r.stderr


def test_empty_line_is_an_error(e):
    e.set_reply({"structured_output": {"line": "  "}})
    r = e.run("x")
    assert r.returncode == 1 and r.stdout == ""


def test_empty_roll_is_an_error(e):
    r = e.run("x", extra_env={"ROLEPLAY_ROSTER": str(e.tmp / "missing.tsv")})
    assert r.returncode == 1 and r.stdout == ""
    assert "roll came back empty" in r.stderr


def test_runs_through_a_symlink(e, tmp_path):
    link = tmp_path / "linked-say"
    link.symlink_to(SCRIPT)
    r = subprocess.run(
        [str(link)],
        input="",
        capture_output=True,
        text=True,
        env={
            "PATH": f"{e.stub_dir}:{JQ_DIR}:/usr/bin:/bin",
            "ROLEPLAY_ROSTER": str(tmp_path / "roster.tsv"),
        },
    )
    assert r.returncode == 0 and "Test Hero" in r.stdout
