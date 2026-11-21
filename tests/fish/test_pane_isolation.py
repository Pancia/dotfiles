"""A FishPane runs in a home of its own, never the operator's.

The paths are compared against this test's own `tmp_path`, not against "some
temporary folder": under the test runner HOME is already a throwaway home, so a
weaker check would pass with the pane still inheriting it.
"""

import os
import re

from .conftest import DOTFILES, FishPane


def test_an_interactive_pane_runs_in_its_own_home(tmp_path):
    out = FishPane(tmp_path, "ISOLATION-0001").run([
        'echo "|HOME=$HOME|"',
        'echo "|DATA=$XDG_DATA_HOME|"',
        'echo "|CONFIG=$XDG_CONFIG_HOME|"',
        'echo "|LINK="(realpath $HOME/dotfiles)"|"',
        'echo "|HIST=[$fish_history]|"',
        "exit",
    ])

    def seen(name):
        found = re.findall(rf"\|{name}=([^|\r\n]*)\|", out)
        assert found, f"{name} not printed:\n{out}"
        return found[-1]

    own = os.path.realpath(tmp_path)
    home = os.path.realpath(seen("HOME"))
    assert home == os.path.join(own, "pane-home")
    for name in ("DATA", "CONFIG"):
        path = os.path.realpath(seen(name))
        assert os.path.commonpath([path, home]) == home, (name, path)
    assert seen("LINK") == os.path.realpath(DOTFILES)
    assert seen("HIST") == "[]"
