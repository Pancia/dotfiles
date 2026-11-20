# Worklog: Astro ZR helper uses saved coordinates; conftest loads tree under test

**Date**: 20261120-151446-MST
**Task**: m-017
**Agent**: w-29

## Summary

Row ASTRO (R5) of the hermetic-test-suite spec.

- R5.0: `uv run lib/python/run_tests.py bin/astro/test_zr.py` on the base commit
  **passed** (42 passed, 10.6s). No error to record: the network was up and
  Nominatim answered. The geocoding dependency is real, though: feeding the
  base-commit helper an ungeocodable city returns
  `{"error": "Could not geocode location: Nowhere-Invalid, GB"}` from
  stellium's `Native._process_location` (`builder.py:314 from_details` →
  `native.py:231`). So the suite failed whenever Nominatim was unreachable or
  rate-limited; that is the cause the row fixes.
- R5.1: `tests/bin/astro/conftest.py` loads `parents[3] / bin / astro`.
- R5.2: `ZRCalculator._birth_payload` adds `lat`, `lng`, `tz_str` when
  `tz_str` is non-empty and `(lat, lng) != (0.0, 0.0)`. The progressions
  payload is untouched.
- R5.3: `_build_chart` in `bin/astro-zr-helper` passes
  `{"latitude", "longitude", "timezone", "name": city}` when the payload has
  `lat` and `lng`, else the `city, nation` string. Docstring updated.
- R5.4: three new tests in `TestSavedCoordinates` (Greenwich / "Sample Person"
  for the payload tests; the timeline test reuses the fixture chart with
  `city="Nowhere-Invalid"` and the unchanged `L1_FORTUNE`).
- R5.5: no reference data, tolerance or assertion changed. All 42 existing ZR
  tests pass under the coordinate path.
- R5.6: `docs/astro.md` zr section says saved coordinates are used and the
  city is geocoded only when the chart has none.
- Astro component: 110 passed.

Extra check for the live path: compared the base-commit helper (geocoding the
city) against the new helper (saved coordinates) over L1, L2 and L3 timelines
for Fortune and Spirit on the fixture chart: 2042 periods, 0 differences in
sign, start, end or score.

## How It Went

Small and direct. The "error" in R5.0 did not reproduce because the run had
network; proving the dependency by feeding an invalid city was the useful
substitute.

## System Learnings

- stellium's `Native._process_location` accepts a dict with `latitude`,
  `longitude`, optional `timezone` and `name`; with a timezone it skips both
  the geocoder and `timezonefinder`.
- `_run_helper` resolves helpers next to `bin/astro`'s own file, so loading
  `bin/astro` from the tree under test also runs the tree's helpers.

## Process Improvements

R5.0 assumes the failure reproduces. A spec step that diagnoses a network
dependency could say how to show it when the network is up (an invalid input,
as here).

## Self-Improvement Notes

Comparing old vs new helper output over the full timeline was cheap and gives
the operator stronger evidence than the ±1 day test tolerance alone.
