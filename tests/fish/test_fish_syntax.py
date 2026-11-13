"""Every fish file in the repo parses (`fish -n`).

A parse error in a function file breaks every function in it, and one in
conf.d breaks shell startup. ccs.fish once failed to source because an
apostrophe in a Python comment ended the single-quoted `python3 -c` string
around it. That took down the claude wrapper, every ccs command and chpwd, and
only a test that happened to source the file noticed.

`fish -n a.fish b.fish` checks only a.fish and passes the rest to it as argv,
so each file gets its own call.

Limit: `fish -n` only sees what changes the parse. An even number of
apostrophes in a quoted program closes and reopens the string, which still
parses, and silently cuts the program short at run time. Keep programs in
other languages out of fish strings (ccs.fish now calls lib/python files).
"""

import subprocess
from pathlib import Path

FISH = Path(__file__).resolve().parents[2] / "fish"
FILES = sorted(
    [*FISH.glob("functions/*.fish"), *FISH.glob("conf.d/*.fish"), *FISH.glob("*.fish")]
)


def parse_errors(path):
    r = subprocess.run(["fish", "--no-config", "-n", str(path)],
                       capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)
    return None if r.returncode == 0 else (r.stderr.strip() or f"exit {r.returncode}")


def test_the_file_list_covers_all_three_folders():
    folders = {p.parent.name for p in FILES}
    assert {"functions", "conf.d", "fish"} <= folders
    assert FISH / "functions" / "ccs.fish" in FILES


def test_fish_n_catches_a_quote_ended_by_an_apostrophe(tmp_path):
    """The check itself: the shape that broke ccs.fish must fail `fish -n`."""
    bad = tmp_path / "bad.fish"
    bad.write_text("function f\n    python3 -c '\n# don't\nfor a, b in ((1, 2),):\n"
                   "    print(a)\n' x\nend\n")
    assert parse_errors(bad) is not None


def test_every_fish_file_parses():
    failures = {}
    for path in FILES:
        err = parse_errors(path)
        if err is not None:
            failures[str(path.relative_to(FISH.parent))] = err
    assert not failures, "\n\n".join(f"{p}:\n{e}" for p, e in failures.items())
