#!/usr/bin/env python3
"""Tests for bin/reply-style-nudge, the reply-format reminder on every prompt."""
import json
import os
import re
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).parent.parent.parent
HOOK = DOTFILES / "bin" / "reply-style-nudge"
LIAISON = "liaison-01"


def base_env(entry=None, agent=None):
    # Never inherit: the suite usually runs inside a Claude Code session.
    env = {k: v for k, v in os.environ.items()
           if k not in ("CLAUDE_CODE_ENTRYPOINT", "ALT_AGENT_ID")}
    if entry:
        env["CLAUDE_CODE_ENTRYPOINT"] = entry
    if agent:
        env["ALT_AGENT_ID"] = agent
    return env


def run(stdin, entry=None, agent=None):
    r = subprocess.run([str(HOOK)], input=stdin, capture_output=True, text=True,
                       env=base_env(entry, agent), timeout=10)
    return r.returncode, r.stdout


def payload(path):
    return json.dumps({"session_id": "x", "transcript_path": str(path), "prompt": "hi"})


def transcript(tmp_path, entrypoint="cli", reply="ok"):
    p = tmp_path / "t.jsonl"
    lines = [{"type": "user", "entrypoint": entrypoint, "message": {"content": "q"}},
             {"type": "assistant", "entrypoint": entrypoint,
              "message": {"content": [{"type": "text", "text": reply}]}}]
    p.write_text("\n".join(json.dumps(l) for l in lines) + "\n")
    return p


def note(out):
    if not out.strip():
        return None
    d = json.loads(out)
    assert d["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"
    return d["hookSpecificOutput"]["additionalContext"]


@pytest.mark.parametrize("trans,env,agent,want", [
    ("cli", "cli", None, "format"),
    (None, "cli", None, "format"),
    (None, "sdk-cli", None, None),
    (None, None, None, None),
    ("sdk-cli", "cli", None, None),
    ("cli", "sdk-cli", None, None),   # claude -p --resume of an interactive session
    ("cli", "cli", LIAISON, "both"),
    ("sdk-cli", "cli", LIAISON, None),
    ("sdk-cli", "sdk-cli", LIAISON, None),
])
def test_routing(tmp_path, trans, env, agent, want):
    path = transcript(tmp_path, trans) if trans else tmp_path / "missing.jsonl"
    rc, out = run(payload(path), env, agent)
    assert rc == 0
    n = note(out)
    if want is None:
        assert n is None
    else:
        assert "🟡 `WATCH`" in n            # decoded: raw stdout has \ud83d escapes
        assert ("[Reply style]" in n) == (want == "both")


@pytest.mark.parametrize("bad", ["", "not json", "[1,2]"])
def test_bad_stdin_is_silent(bad):
    rc, out = run(bad, "cli")
    assert (rc, out) == (0, "")


def test_liaison_long_reply_is_reported(tmp_path):
    path = transcript(tmp_path, "cli", reply="word " * 151)
    _, out = run(payload(path), "cli", LIAISON)
    assert "Last reply: 151 words" in note(out)


def test_liaison_short_reply_is_not_reported(tmp_path):
    path = transcript(tmp_path, "cli", reply="word " * 150)
    _, out = run(payload(path), "cli", LIAISON)
    assert "Last reply" not in note(out)


def test_other_sessions_get_no_size_report(tmp_path):
    path = transcript(tmp_path, "cli", reply="word " * 500)
    _, out = run(payload(path), "cli")
    assert "Last reply" not in note(out)


def test_sidechain_reply_is_not_scored(tmp_path):
    p = transcript(tmp_path, "cli", reply="short")
    with p.open("a") as f:
        f.write(json.dumps({"type": "assistant", "isSidechain": True, "entrypoint": "cli",
                            "message": {"content": [{"type": "text", "text": "word " * 500}]}}) + "\n")
    _, out = run(payload(p), "cli", LIAISON)
    assert "Last reply" not in note(out)


def test_labels_match_the_global_rules():
    """The seven labels live in the hook and in the reply-format section."""
    src = HOOK.read_text()
    rules = (DOTFILES / "rcs" / "claude-user-claude.md").read_text()
    sect = rules.split("### Reply format")[1].split("###")[0]
    hook_labels = re.findall(r"(🔴|🟢|🟡|🔵) `([A-Z ]+)`", src)
    rule_labels = re.findall(r"^(🔴|🟢|🟡|🔵) `([A-Z ]+)`$", sect, re.M)
    assert hook_labels == rule_labels
    assert len(hook_labels) == 7
