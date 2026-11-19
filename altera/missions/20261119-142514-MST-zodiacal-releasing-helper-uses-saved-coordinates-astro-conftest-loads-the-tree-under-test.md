# Mission: Zodiacal-releasing helper uses saved coordinates; astro conftest loads the tree under test

**Date**: 20261119-142514-MST
**Task**: m-017 bold-lynx

## Objective
Implement row ASTRO (requirement R5) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"20m","checks":[
 {"kind":"command","title":"astro component","run":"uv run lib/python/run_tests.py astro -v","stdout_contains":["test_birth_payload_sends_saved_coordinates PASSED","test_birth_payload_without_coordinates_keeps_the_city PASSED","test_timeline_ignores_the_city_when_coordinates_are_given PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Context
- `bin/astro`:
  - `BirthData` (class at line 63): `lat`, `lng` and `tz_str` (lines 73 to 75) default to `0.0`, `0.0` and an empty string, which means not geocoded;
  - `ZRCalculator` (line 2954, `HELPER` at 2957): its `_birth_payload` (line 2965) sends only city and nation;
  - the progressions `_birth_payload` (line 2907) already sends coordinates. Do not change it.
- `bin/astro-zr-helper`:
  - `_build_chart` (line 181) builds a city and nation string and calls stellium's `ChartBuilder.from_details`, which geocodes over the network with Nominatim;
  - stellium's `Native._process_location` skips the geocoder, and the timezone lookup, for a dict with `latitude`, `longitude` and `timezone`;
  - the module docstring documents the request format (lines 8 to 19).
- `tests/bin/astro/conftest.py`: `astro_module` (line 29) loads `Path.home() / dotfiles / bin / astro`, the live checkout.
- Steps:
  1. R5.0: run `uv run lib/python/run_tests.py bin/astro/test_zr.py` and record the error text in the worklog, without personal chart data. If the error is not geocoding, find the real cause before you change code.
  2. R5.1: load from `Path(__file__).resolve().parents[3] / bin / astro`.
  3. R5.2: add `lat`, `lng` and `tz_str` to the payload when the chart has coordinates: `tz_str` is non-empty and `(lat, lng) != (0.0, 0.0)`.
  4. R5.3: when the payload has `lat` and `lng`, pass a dict with `latitude`, `longitude`, `timezone` and `name` set to the city. Otherwise pass the city string as today. Update the docstring.
  5. R5.4: add `test_birth_payload_sends_saved_coordinates`, `test_birth_payload_without_coordinates_keeps_the_city` and `test_timeline_ignores_the_city_when_coordinates_are_given`. The last one uses the same reference L1 Fortune periods with `city='Nowhere-Invalid'`.
- The two payload tests use neutral sample data: an invented name and a public place such as Greenwich. Never copy the fixture's personal birth details into new tests, the worklog or any report.
- R5.5: do not change the `L1_*` or `L2_*` reference data, `DATE_TOL_DAYS` or any assertion. If a period moves by more than one day, stop and report it rather than widen the tolerance.
- R5.6: in the `### Zodiacal Releasing (zr)` section of `docs/astro.md` (line 65), say that the chart's saved coordinates are used, and the city is geocoded only when the chart has none.
- Here, offline means no geocoder. The helper's shebang still installs stellium from an unpinned git URL, so uv may fetch over the network. Pinning it is out of scope.
- ISOLATE has merged. The astro component runs under a throwaway home, with uv's cache pinned to its real location.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Live path: `bin/astro` and `bin/astro-zr-helper` run from `~/dotfiles/bin` on `PATH`, so they go live on merge. Say so in the mission-ready note. The operator checks that `astro zr` and `astro zr --age 32` print the same periods as before for their saved chart.

## Success Criteria
- The whole astro component passes, including the three new tests, with the reference data unchanged.
- The conftest loads `bin/astro` from the tree under test.
- The helper's docstring and the zr section of `docs/astro.md` describe the coordinates-first behaviour.
- Every check in the done check passes.

## Out of Scope
- Replacing the personal data in the astro test fixture (a separate spec).
- Pinning stellium (the spec's second Open Question).
- kerykeion deprecation warnings.
- Other components.
