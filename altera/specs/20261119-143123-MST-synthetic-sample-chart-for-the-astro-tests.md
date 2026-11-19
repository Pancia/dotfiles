# Spec: Synthetic sample chart for the astro tests

**Date**: 2026-11-19
**Status**: draft
**Workflow**: dotfiles-dev

## Overview

The astro tests currently use a real person's birth details. This spec replaces them with a synthetic sample chart, and it gives every new expected value a source that does not depend on the code under test. The repository is public.

The real details sit in these places:

- `tests/bin/astro/conftest.py`: the `birth_data` fixture, plus the `natal_subject` and `natal_cusps` fixtures that are built from it.
- Seven test files: `test_zr.py`, `test_fixes.py`, `test_houses.py`, `test_solar_return.py`, `test_parans.py`, `test_aspect_lines.py` and `test_eclipses.py`. The details appear in code, docstrings, comments and chart names.
- Values derived from the chart. These identify the person just as well:
  - every date in the zodiacal-releasing reference tables, because each date is an offset from the birth moment;
  - the natal planet, cusp and aspect tables in `test_houses.py`;
  - the `equal_cusps` fixture in `TestPlanetInNatalHouse` and its comments, which encode the old Ascendant without using `birth_data`;
  - the year offset, year and month in `test_sr_past_year_works`;
  - the degree and house notes in the docstrings of `test_fixes.py` (`test_forecast_includes_node_chiron_lilith_aspects`, `test_current_position_uses_natal_cusps_for_house`) and of `test_aspect_lines.py` (`test_orb_zero_for_perfect_conjunction`).

This spec names these places by file and function only. It quotes no value.

**Source.** This work comes from two places:

- The first finding of the diff critique, `altera/reviews/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate-diff-critique.md`. It found that the old row PRIVACY was far larger than one sitting. Its MINOR finding asked for a standalone derivation script.
- R13 and the fifth Open Question of the approved spec `20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate`, which moved this work into a spec of its own.

**Binding decisions**

- **Sample inputs.** The name is "Robin Sample" (invented). The place is Greenwich, the Royal Observatory: nation `GB`, latitude `51.4778`, longitude `-0.0014`, time zone `Europe/London`. The longitude is not exactly zero, so that no falsy-zero check can treat the chart as "not geocoded" (R5.2 of the approved spec).
- **Same lot signs.** The chart is a day chart, with the Lot of Fortune in Taurus and the Lot of Spirit in Sagittarius. The zodiacal-releasing tests then keep their sign order, sequence lengths and Loosing-of-the-Bond positions. Only their dates change.
- **Date and time come from a written search.** Row CORE implements it (R1.2). The search window starts in November 2001. Every derived period date is then later than any date the replaced chart could produce, so the leak check's date forms cannot collide with a new value.
- **Side-by-side migration.** CORE adds the fixtures `sample_birth_data`, `sample_natal_subject` and `sample_natal_cusps` beside the old fixtures. Each later row moves one family of tests to the new fixtures. SCRUB deletes the old fixtures last. The component stays green at every step, and no failing assertion prints old values into a recorded run.
- **An independent derivation.** Every new expected value comes from `tests/bin/astro/derive_*.py`. These files use only the standard library and `swisseph`. They never import `bin/astro`, `kerykeion` or stellium. The ephemeris data files that Chiron needs are found without importing kerykeion. Each family has its own derivation module and its own comparison test, so parallel rows share no file.
- **A leak check that quotes nothing.** It reads the old values at run time from a pinned commit (`git show` plus `ast`). It prints only kinds of value, file paths and counts.

**Checked against** `master` at `1f52612e` (`1f52612eab9cbd9e87893773b7c4b235404842a0`). Rows ASTRO and CANARY of the approved spec have not landed there yet. This spec is written for the tree they produce:

- ASTRO's `astro_module` loads `bin/astro` from the tree under test.
- `test_zr.py` has ASTRO's three new tests, so it has 45 tests: 42 on `master` plus 3.
- CANARY's `test_no_test_names_the_live_checkout` scans every `tests/**/*.py`.

Functions are named, not line numbers. No test was run while writing this spec.

## Requirements

**Global rules (every row)**

- **G1** Each row's done check is its labelled block under "Done checks". It is copied verbatim into the brief.
- **G2** Tests are hermetic (checklist item 4). They run with `uv run lib/python/run_tests.py <component or file>` from the worktree root (item 5), never with `cmds test` or a bare `pytest`. New files under `tests/bin/astro/` belong to the existing `bin/astro` entry in `COMPONENTS`, so no new entry is needed. The new `derive_*.py` and `old_chart_guard.py` files do not match `python_files = test_*.py` (`tests/pytest.ini`), so pytest does not collect them as tests.
- **G3** No `rm` (item 9). Use `trash`, `tmp_path`, or a `tempfile.TemporaryDirectory` that removes itself.
- **G4** A behaviour change updates its doc in the same row (item 10).
- **G5 (privacy, item 3).** No brief, worklog, review, commit message or code comment quotes an old value. This includes values derived from the old chart.
  - Cite `file:function` only.
  - Do not paste a diff hunk that shows removed lines.
  - Do not paste a failure output of a test that still uses the old fixtures.
  - Do not write the old values in a scratch file inside the repo.
- **G6 (independence).** A worker computes each new expected value with the derivation script. A worker never shifts an old table by a constant, never copies a value printed by `bin/astro`, and never copies `bin/astro` code.
  - A worker may read `bin/astro` for conventions only. Examples: equal houses (`houses_system_identifier="A"`), the true node for natal display, the mean node for lines and parans (`_LINE_PLANETS`), In Mundo geometry for lines, `111.32 · cos(lat)` km per degree, the daily sample time in `forecast_transits`, and the age-to-days rule in `ZRCalculator.snapshot_at_age`.
  - Each family uses a method that differs from the `bin/astro` method where this spec says so.
- **G7 (no tuning).** No row widens a tolerance, removes an assertion or weakens a check. This covers `DATE_TOL_DAYS`, `POSITION_TOLERANCE`, `ORB_TOLERANCE`, `HOUSE_TOLERANCE`, `DELTA_LAT_TOLERANCE`, `KM_TOL_EXACT`, `KM_TOL_APPROX` and `PCT_TOL`. If `bin/astro` and the derivation disagree beyond a test's tolerance, the worker stops and reports which value disagrees and by how much. They change neither side. A real disagreement can be a `bin/astro` bug, and `bin/astro` is live, so the operator decides.
- **G8 (live paths, item 2).** No row touches a checklist item 2 path, `bin/astro` or `bin/astro-zr-helper`. Every change is under `tests/bin/astro/`, `docs/testing.md` or `docs/astro.md`. The operator needs no live check.

### R1 Derivation core and sample chart (row CORE)

- R1.1 New file `tests/bin/astro/derive_core.py`, with imports from the standard library and `swisseph` only:
  - `SAMPLE`: the inputs from the binding decisions, plus the local date and time found by R1.2.
  - `ephemeris_path()`: finds kerykeion's `sweph` folder with `importlib.util.find_spec("kerykeion")`, without importing kerykeion, and passes it to `swe.set_ephe_path`. If the folder is missing, it raises with a clear message. It does not fall back to Moshier, because Chiron needs the data files.
  - `julian_day_ut(local_datetime, tz)` through `zoneinfo`.
  - `bodies(jd)`: tropical geocentric longitude, latitude and speed for Sun to Pluto, the true node, the mean node, Mean Lilith (`swe.MEAN_APOG`) and Chiron.
  - `equatorial(jd, body)`: right ascension and declination.
  - `angles(jd, lat, lng)`: ASC and MC from `swe.houses_ex` with house system `b'A'`.
  - `equal_cusps(asc)` and `house_of(lon, cusps)`.
  - `sun_altitude(jd, lat, lng)`.
  - `lots(asc, sun, moon, is_day)`: Fortune = ASC + Moon − Sun by day, reversed by night. Spirit is the mirror.
  - `criteria(moment)` and `search(start, end, step)`.

  Rows after CORE do not edit `derive_core.py`. A family that needs a helper puts it in its own module.

- R1.2 **Selection rule.** `search` scans from 2001-11-01 00:00 UTC to 2002-02-28 23:55 UTC in 5-minute steps. In that season `Europe/London` is on GMT, so local time equals UTC. It returns the first moment where all of these hold:
  - C1: the Sun's altitude is at least 5° (a day chart that no sect rule can misread);
  - C2: Fortune is in Taurus and Spirit is in Sagittarius, each at least 3° from both edges of its sign;
  - C3: the ASC is at least 2° from a sign edge;
  - C4: Sun to Pluto, both nodes, Mean Lilith and Chiron are each at least 0.5° from their sign edges and from every equal-house cusp;
  - C5: the day of the month is from 3 to 26, so the solar return month is clear.

  The returned moment goes into `SAMPLE` as a literal.

- R1.3 New file `tests/bin/astro/derive_sample_chart.py`:
  - `--json` prints one JSON object. It has sections `birth`, `natal` and `lots`, plus one section from each sibling module `derive_<family>.py`. Each such module exposes `SECTION` and `derive(ctx)`. The script discovers them by glob and skips `derive_core.py` and itself.
  - `--section NAME` prints one section.
  - `--search` prints the R1.2 result.
  - It runs on its own with `uv run --with pyswisseph --with kerykeion python tests/bin/astro/derive_sample_chart.py --json`.
- R1.4 `tests/bin/astro/conftest.py`: add the session fixtures `sample_birth_data`, `sample_natal_subject` and `sample_natal_cusps`. They mirror the old three fixtures. `sample_birth_data` holds the `SAMPLE` values as literals. Do not change the old fixtures, and do not import `derive_core` here.
- R1.5 New file `tests/bin/astro/test_derived_core.py`. It runs the script with `sys.executable` (the component's environment has `pyswisseph` and `kerykeion`) and caches the JSON in a module fixture. Tests:
  - `test_derivation_imports_only_stdlib_and_swisseph`. Over every `tests/bin/astro/derive_*.py`, the AST check passes only if:
    - every import is in `sys.stdlib_module_names`, is `swisseph`, or is a sibling `derive_*` module;
    - there are no calls to `importlib.import_module`, `__import__`, `exec`, `runpy` or `SourceFileLoader`;
    - no string literal contains `bin/astro` or `astro-zr-helper`.
  - `test_sample_chart_meets_selection_criteria`: C1 to C5 hold for `SAMPLE`.
  - `test_search_finds_the_sample_moment`: `--search` returns exactly the `SAMPLE` moment.
  - `test_fixture_matches_derivation_inputs`: `sample_birth_data` equals `SAMPLE`, field by field.
- R1.6 Docs: in the `bin/astro` row of `docs/testing.md`, say that the tests use a synthetic sample chart, that expected values come from the derivation script (standard library and `swisseph` only), and give the standalone command from R1.3.

### R2 Zodiacal-releasing derivation (row ZR-DERIVE)

- R2.1 New file `tests/bin/astro/derive_zr.py` (`SECTION = "zr"`). It builds tables from the sample's UTC birth moment and the lot signs that `derive_core` computes. The method is plain arithmetic:
  - minor years: Ari 15, Tau 8, Gem 20, Can 25, Leo 19, Vir 20, Lib 8, Sco 15, Sag 12, Cap 27, Aqu 30, Pis 12;
  - days per minor year: L1 360, L2 30, L3 2.5, L4 5/24;
  - each sub-cycle starts at its parent's start, from the parent's sign;
  - after 12 signs, the sequence jumps to the sign opposite the sub-cycle's start sign (Loosing of the Bond) and continues;
  - the last period is cut at the parent's end;
  - each date is the UTC calendar date of the start instant.

  It outputs one table for each table in `test_zr.py`: the L1 Fortune periods over 100 years, the four L2 Fortune blocks, the first two L1 Spirit periods, the L3 head of the first Capricorn L2 in Spirit, and the L4 periods inside the first Capricorn L3. It also outputs the L1 to L3 signs of the Spirit snapshot at age 12, with age converted to days by `snapshot_at_age`'s rule. It contains no table literals.
- R2.2 New file `tests/bin/astro/test_derived_zr.py`. Its tests check the derivation against rules a person can work out by hand. They do not use the sample's dates.
  - `test_zr_derivation_minor_years_and_multipliers`: Capricorn L2 is 810 days and Aquarius L2 is 900 days. L3 and L4 lengths follow the multipliers.
  - `test_zr_derivation_loosing_of_the_bond`: the 13th L2 sign is opposite the start. A Gemini L1 has 14 L2 entries and a Cancer L1 has 17. The tail is cut at the parent's end.
  - `test_zr_derivation_starts_at_birth_with_lot_signs`: L1 Fortune starts in Taurus on the birth UTC date. L1 Spirit starts in Sagittarius.

### R3 Zodiacal-releasing tests on the sample chart (row ZR)

- R3.1 `tests/bin/astro/test_zr.py`:
  - The `natal_chart` fixture uses `sample_birth_data`. `created_at` is built from it.
  - Replace the dates in `L1_FORTUNE`, `L2_IN_TAURUS_L1`, `L2_IN_GEMINI_L1`, `L2_IN_CANCER_L1`, `L2_IN_LEO_L1`, `L1_SPIRIT_FIRST_TWO`, `L3_HEAD_OF_CAP_L2_SPIRIT` and `L4_IN_CAP_L3_SPIRIT` with the derived dates. Keep the names, lengths and sign columns. If a derived sign column or length differs from the current one, stop and report: the sample chart then breaks the tests' shape.
- R3.2 Every date that a test body asserts or looks up comes from a table row, for example `L2_IN_GEMINI_L1[7][1]`. This covers `_find_at`, `_slice_starting_at`, `test_l1_starts_at_taurus` and the snapshot comments. No date literal stays outside the tables.
- R3.3 ASTRO's tests keep their names. `test_timeline_ignores_the_city_when_coordinates_are_given` uses the sample chart with the invalid city. Rewrite the module docstring: the reference now comes from the derivation, not astro-seek, and the docstring names no chart details. The ±1-day note stays only as it applies to the helper's UTC dates.
- R3.4 In `test_derived_zr.py`, add `test_zr_tables_match_derivation`. It imports the `test_zr` table constants and asserts that each one equals the derived table exactly: signs, order and dates. It also checks the snapshot signs.
- R3.5 Docs: in "Zodiacal Releasing (`zr`)" of `docs/astro.md`, the sentence that says date output is verified against astro-seek's calculator becomes: the tests check the dates against an independent derivation for a synthetic chart.

### R4 Natal chart and house logic (row HOUSES-NATAL)

- R4.1 New file `tests/bin/astro/derive_houses.py` (`SECTION = "houses"`), natal part:
  - sign, degree in sign (2 decimals) and equal house for Sun to Pluto;
  - the 12 equal cusps;
  - natal aspects. Choose 6 aspects whose orb is at most 3° and at most half of kerykeion's default orb for that aspect, so each one surely appears in `NatalAspects.relevant_aspects`. The orb limits come from kerykeion's documented settings, not from an import.
  - a flag that confirms `test_transit_house_differs_from_transit_chart_house` holds at its moment. At least one transit planet must fall in a different house under natal cusps than under the transit chart's own equal houses, and be at least 1° from both cusps. If no planet qualifies, move that test's moment and say so in the worklog.
- R4.2 `tests/bin/astro/test_houses.py`:
  - `TestPlanetInNatalHouse.equal_cusps` gets an invented, round house-1 cusp of 320.0°. Re-pick each test's input so it keeps its stated intent: just past the cusp, wrap past 0°, exactly on the cusp, and so on. Rewrite the comments with the new arithmetic.
  - `TestNatalChart` gets `NATAL_PLANETS`, `NATAL_CUSPS` and `NATAL_ASPECTS` from the derivation. Its reference comment says "derived", not "astro-seek".
  - `TestTransitHousesUseNatalCusps` uses the `sample_*` fixtures.
- R4.3 New file `tests/bin/astro/test_derived_houses.py` with `test_natal_tables_match_derivation`. Degrees match within 0.01°. Signs, houses and aspect names match exactly.

### R5 Transit references (row HOUSES-TRANSIT)

- R5.1 `derive_houses.py`, transit part. Keep both transit moments. They are not personal. They now resolve in the sample's time zone, and the derivation converts them with `zoneinfo`. Output:
  - for the 2026 moment, 5 or 6 transit-to-natal aspects (each orb at most 2° and at most half the default orb);
  - for the 2000 moment, all 10 transit positions with their natal houses (each at least 0.5° from a cusp) and 5 aspects under the same orb rule.
- R5.2 `test_houses.py`: rename `TestAstroSeekReference` to `TestTransitReference`, and `TestAstroSeekReference2000` to `TestTransitReference2000`. Their tables come from the derivation, and their docstrings say "derived". The test method names do not change. Both classes use the `sample_*` fixtures.
- R5.3 In `test_derived_houses.py`, add `test_transit_tables_match_derivation`, with the same comparison rules as R4.3.

### R6 Forecast, current position and solar return (row FIXES)

- R6.1 New file `tests/bin/astro/derive_transits.py` (`SECTION = "transits"`):
  - **Forecast targets.** For each day of the `test_forecast_includes_node_chiron_lilith_aspects` window, at `forecast_transits`' daily sample time, list which of Mean Lilith, the true nodes and Chiron receive a major-aspect from a `MAJOR_PLANETS` transit with an orb of at most 1.0°. Each of the three groups needs at least one hit. If one is missing, move the window start within 2026–2027.
  - **Current position.** Saturn's sign and natal house on the `test_current_position_uses_natal_cusps_for_house` date, at least 1° from a cusp. If it is closer, move the date.
  - **Solar return.** Find the solar return by your own root search on the Sun's longitude (for example, the secant method). Do not use `SolarReturnCalculator`'s bisection. Output the target year offset, year and UTC month that `test_sr_past_year_works` needs, keeping its target year.
  - **Prague angles.** The ASC and MC differences between the natal-place solar return and the Prague solar return for 2026. Each must be at least 8°, so the test's "> 5°" has a margin.
- R6.2 `tests/bin/astro/test_fixes.py`:
  - The three chart-based tests use the `sample_*` fixtures.
  - Chart names change from the old prefix to `sample_`.
  - Docstrings and comments name no old degree, house or Ascendant. They describe the derived hits instead.
  - The expected sign and house become class constants.
- R6.3 `tests/bin/astro/test_solar_return.py`: use the `sample_*` fixtures. The expected offset, year and month become constants. Remove the comment about the birth year.
- R6.4 New file `tests/bin/astro/test_derived_transits.py` with `test_transit_values_match_derivation`.

### R7 Eclipse hits (row ECLIPSES)

- R7.1 New file `tests/bin/astro/derive_eclipses.py` (`SECTION = "eclipses"`):
  - Find solar and lunar eclipses with `swe.sol_eclipse_when_glob` and `swe.lun_eclipse_when` over the window of `test_all_aspect_set_includes_sextile_or_trine`.
  - The eclipse longitude is the Sun for a solar eclipse and the Moon for a lunar eclipse.
  - Compare it with the natal angles relocated to Prague (`angles(natal_jd, 50.0875, 14.4214)`), and list the hits with orb at most 3°.
  - At least one sextile, square or trine hit must have an orb of at most 2°. If none does, move `jd_start` or widen `years`. Never change the orb.
- R7.2 `tests/bin/astro/test_eclipses.py`: the two chart-based tests use `sample_birth_data` and `sample_` chart names. The comment "verified by hand for this chart/window" becomes a pointer to the derivation. The NASA reference tests do not change.
- R7.3 New file `tests/bin/astro/test_derived_eclipses.py` with `test_eclipse_hits_match_derivation`. It checks that the derivation finds a non-canonical hit for the window and settings that the test uses.

### R8 Parans (row PARANS)

- R8.1 New file `tests/bin/astro/derive_parans.py` (`SECTION = "parans"`):
  - Use right ascension and declination from `derive_core.equatorial` for the `_LINE_PLANETS` bodies, with the mean node.
  - The method differs from `ParanCalculator`'s bisection. Scan latitude in steps of 0.01° across ±2.5° of each reference latitude. Use the standard angle-LST formulas. Find the sign changes of the wrapped LST difference, and skip jumps larger than 90°.
  - Keep reference parans that have |Δlat| ≤ 1.5° and are at least 1° from any circumpolar limit. Keep at least 3 at the Taranto latitude and 2 at the Honolulu latitude. Both latitudes stay.
- R8.2 `tests/bin/astro/test_parans.py`:
  - `REFS_TARANTO` and `REFS_HONOLULU` come from the derivation.
  - The docstrings say "derived" instead of astro.com and name no person.
  - All chart-based tests use `sample_birth_data` and `sample_` chart names.
  - The pure-math units do not change.
- R8.3 New file `tests/bin/astro/test_derived_parans.py` with `test_paran_references_match_derivation`.

### R9 Aspect lines (row LINES)

- R9.1 New file `tests/bin/astro/derive_lines.py` (`SECTION = "lines"`), with In Mundo geometry as the convention:
  - For conjunctions and oppositions, use the body's own right ascension and declination. For the 60°, 90° and 120° aspects, use the sensitive degree on the ecliptic.
  - The method differs from `_perp_distance`:
    - MC/IC distance is |Δlng| · 111.32 · cos(lat) to the meridian where the point culminates.
    - AS/DC distance is the minimum over a latitude grid in 0.01° steps across ±30°, with no golden-section search.
  - Keep reference rows with orb at most 2°. AS/DC rows need km ≤ 80, and MC/IC rows need km ≤ 200.
  - Keep at least 2 rows at each location. Across both locations, keep at least one MC/IC row and one AS/DC row. If one location cannot supply them, raise the orb filter to 3°. Do not move the location, because the test names name the cities.
- R9.2 `tests/bin/astro/test_aspect_lines.py`:
  - `REFS_TARANTO` and `REFS_HONOLULU` come from the derivation. Keep the `km_exact` flags.
  - The docstrings say "derived" and name no person.
  - `test_orb_zero_for_perfect_conjunction` uses `sample_birth_data`. Rewrite its comment about the natal Sun's house.
  - All chart names use `sample_`.
- R9.3 New file `tests/bin/astro/test_derived_lines.py` with `test_line_references_match_derivation`. Km values match within 1 km.

### R10 Remove the old fixtures and check that the old values are gone (row SCRUB)

- R10.1 `tests/bin/astro/conftest.py`: delete `birth_data`, `natal_subject` and `natal_cusps`. First confirm with `git grep -n -w -E "birth_data|natal_subject|natal_cusps" -- tests/bin/astro` that only `sample_*` names remain in use. Do not rename the `sample_*` fixtures.
- R10.2 New file `tests/bin/astro/old_chart_guard.py`, standard library only:
  - **Source of the old values.** Set `OLD_COMMIT = "1f52612eab9cbd9e87893773b7c4b235404842a0"`. Read `tests/bin/astro/conftest.py` and `tests/bin/astro/test_houses.py` at that commit with `git show`. Take the `BirthData(...)` keyword literals of `birth_data`, and `TestNatalChart.NATAL_PLANETS` and `NATAL_CUSPS`, with `ast`.
    - If the commit is missing, read `.cc/private/astro-old-chart.json` instead (the same keys; ignored by git).
    - If neither exists, exit 3 with "old values unavailable" and a reason, such as a shallow clone or rewritten history.
  - **Forms, all scopes.** These cover every tracked text file under 1 MB and the commit messages from `OLD_COMMIT..HEAD`:
    - the place name, as a case-insensitive whole word;
    - the birth date in ISO form, in `Y, M, D` argument form, in `year=…, month=…, day=…` keyword form, and written with an English month name;
    - the latitude and longitude, as standalone number tokens with 2 or more decimals.
  - **Forms, `tests/bin/astro/` only.**
    - the name, as a case-insensitive whole word;
    - the local and UTC birth time as `H:MM`, and in `hour=…, minute=…` form;
    - the time zone string;
    - any number token within 0.05° of the old Ascendant's absolute longitude;
    - any tuple literal `(planet, sign, degree)` that matches an old natal row within 0.05°.
  - **Output.** Only lines such as `<kind> in <path>: <n>` or `<kind> in commit <short id> message: <n>`. It never prints a value, a matched line or nearby text. It exits 1 on any hit. When there is no hit, it prints `no old chart values found (<forms> forms, <files> files, <commits> commit messages)` and exits 0.
  - **Git use.** Only read commands: `git show`, `git cat-file -e`, `git ls-files` and `git log --format`. Run them with `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and `GIT_OPTIONAL_LOCKS=0`, against the tree under test, found from `__file__`. This is a deliberate, read-only exception to "git only in temporary repositories" (checklist item 4). It writes nothing and makes no commit.
  - **`--self-test`.** It plants every form in a file inside a `TemporaryDirectory` and scans that folder with `--root`. It checks that each kind is detected and that the captured output contains no planted value. Then it prints `self-test ok (<n> kinds)`.
- R10.3 New file `tests/bin/astro/test_old_chart_guard.py`:
  - `test_old_chart_values_are_gone` runs the script. Exit 0 passes. Exit 3 calls `pytest.skip` with the script's reason. Any other exit fails, and the failure message holds only the script's own output.
  - `test_guard_self_test_detects_every_form` runs `--self-test` and expects exit 0.
  - Neither test holds the old values in its own variables, so pytest's assertion display cannot print them.
- R10.4 Docs: in the `bin/astro` row of `docs/testing.md`, describe the leak check:
  - what it reads (a pinned commit, or the private file);
  - that it prints only kinds, paths and counts;
  - that it skips when neither source exists, which is what happens in a shallow clone or after a history rewrite.

## Acceptance Criteria

- No tracked file, and no commit message after the pinned commit, holds the replaced name, birth date, time, place, coordinates, time zone, Ascendant or natal planet rows.
- The leak check detects every form it knows and never prints a found value.
- The astro tests use a synthetic chart with an invented name and a public place. No test uses the old fixtures.
- The sample chart is a day chart with Fortune in Taurus and Spirit in Sagittarius, and the written search reproduces it.
- A derivation that imports neither `bin/astro`, kerykeion nor stellium produces every chart-specific expected value, and each test table matches it.
- The zodiacal-releasing tests keep their shape: the same signs, sequence lengths and Loosing-of-the-Bond positions. Only the dates change.
- The house, transit, forecast, solar-return, eclipse, paran and line tests pass on the sample chart.
- No tolerance is widened, and no assertion is removed.
- The whole astro component passes after the old fixtures are deleted.
- `docs/testing.md` and `docs/astro.md` describe the sample chart, the derivation and the leak check.
- The operator decides whether to remove the old values from git history.

```acceptance
{"v":1,"criteria":[
 {"id":"AC1","text":"No tracked file, and no commit message after the pinned commit, holds the replaced birth inputs, Ascendant or natal planet rows.","checks":[{"row":"SCRUB","check":"old values guard"}]},
 {"id":"AC2","text":"The leak check detects every form it knows and never prints a found value.","checks":[{"row":"SCRUB","check":"old values guard"}]},
 {"id":"AC3","text":"The astro tests use a synthetic chart with an invented name and a public place, and no test uses the old fixtures.","checks":[{"row":"CORE","check":"core derivation tests"},{"row":"SCRUB","check":"astro component"}]},
 {"id":"AC4","text":"The sample chart is a day chart with Fortune in Taurus and Spirit in Sagittarius, and the written search reproduces it.","checks":[{"row":"CORE","check":"core derivation tests"}]},
 {"id":"AC5","text":"A derivation that imports neither bin/astro, kerykeion nor stellium produces every chart-specific expected value, and each test table matches it.","checks":[{"row":"CORE","check":"core derivation tests"},{"row":"ZR","check":"zr tables match derivation"},{"row":"HOUSES-TRANSIT","check":"house tables match derivation"},{"row":"FIXES","check":"transit values match derivation"},{"row":"ECLIPSES","check":"eclipse hits match derivation"},{"row":"PARANS","check":"paran references match derivation"},{"row":"LINES","check":"line references match derivation"}]},
 {"id":"AC6","text":"The zodiacal-releasing tests keep their signs, sequence lengths and Loosing-of-the-Bond positions; only dates change.","checks":[{"row":"ZR-DERIVE","check":"zr derivation rules"},{"row":"ZR","check":"zr tests on sample chart"}]},
 {"id":"AC7","text":"The house, transit, forecast, solar-return, eclipse, paran and line tests pass on the sample chart.","checks":[{"row":"HOUSES-NATAL","check":"houses natal tests"},{"row":"HOUSES-TRANSIT","check":"houses transit tests"},{"row":"FIXES","check":"fixes tests"},{"row":"FIXES","check":"solar return tests"},{"row":"ECLIPSES","check":"eclipse tests"},{"row":"PARANS","check":"paran tests"},{"row":"LINES","check":"line tests"}]},
 {"id":"AC8","text":"No tolerance is widened and no assertion is removed.","human":"Merge reviewer compares each row's diff: tolerance constants unchanged, test count per file not lower, no assert deleted without a replacement."},
 {"id":"AC9","text":"The whole astro component passes after the old fixtures are deleted.","checks":[{"row":"SCRUB","check":"astro component"}]},
 {"id":"AC10","text":"docs/testing.md and docs/astro.md describe the sample chart, the derivation and the leak check.","human":"Read the bin/astro row of docs/testing.md and the zr section of docs/astro.md."},
 {"id":"AC11","text":"The operator decides whether to remove the old values from git history.","human":"Operator answers the first Open Question (row HISTORY)."}
]}
```

## Documentation Updates

- `docs/testing.md`, the `bin/astro` row of the component table:
  - the synthetic sample chart, the derivation script and its standalone command (CORE);
  - the leak check: its sources, its output and when it skips (SCRUB).
- `docs/astro.md`, "Zodiacal Releasing (`zr`)": the sentence about checking dates against astro-seek now says they are checked against an independent derivation for a synthetic chart (ZR).
- `CLAUDE.md`: none. No section describes the astro tests.
- `ai/skills/`: none.

## Technical Approach

**Order.** CORE comes first. It waits for rows ASTRO and CANARY of the approved spec, which change `conftest.py`'s `astro_module` and `test_zr.py`, and add the static scan the new files must pass. After CORE, the family rows can run in parallel. Each owns its own `derive_<family>.py`, its own `test_derived_<family>.py` and its own test files.

Shared files have one owner at a time:

- `conftest.py`: CORE, then SCRUB.
- `docs/testing.md`: CORE, then SCRUB.
- `test_houses.py`, `derive_houses.py` and `test_derived_houses.py`: HOUSES-NATAL, then HOUSES-TRANSIT.
- `test_derived_zr.py`: ZR-DERIVE, then ZR.
- `derive_core.py`: CORE only.

SCRUB comes last, because it deletes the old fixtures.

**Why the old values stay until SCRUB.** Until SCRUB lands, `conftest.py` still holds the old fixture, and each family file holds its values until its own row lands. That is the price of a component that stays green. Every recorded run, SCRUB's, happens after the values are gone. The non-recorded checks run only migrated files, apart from the untouched classes in `test_houses.py` between the two HOUSES rows. G5 stops anyone pasting their failure output.

**Comparison tests.** The `test_derived_*.py` files import the table constants from sibling test modules by name, for example `from test_zr import L1_FORTUNE`. This relies on pytest's default `prepend` import mode and on `tests/bin/astro/` having no `__init__.py`. Both are true on `master`. These tests are the lasting guard on correctness. The leak check is the lasting guard against the old values coming back.

**Residual risks**

- **No external oracle.** The old tables were transcribed from astro-seek and astro.com. The new ones come from a script that uses the same Swiss Ephemeris, and the conventions are read from `bin/astro`. An ephemeris error or a wrong convention would be mirrored, not caught. The second Open Question proposes an optional external cross-check.
- **A real disagreement between `bin/astro` and the derivation.** G7 stops the row. The likely places are AS/DC km values and paran latitudes near the band edge. The margins in R8 and R9 make this unlikely.
- **The leak check depends on history.** If the pinned commit is missing, it skips. A skip fails SCRUB's done check, which requires `PASSED`. After a rewrite, the check needs `.cc/private/astro-old-chart.json`, which exists only on the operator's machine.
- **A chance collision.** A new reference value could fall inside a leak-check form. One example is a new number within 0.05° of the old Ascendant in `tests/bin/astro/`. Then the fix is to pick a different reference row. The leak check is never weakened.
- **The stellium helper installs from git HEAD.** This is the approved spec's second Open Question. An upstream change can move the zodiacal-releasing dates whatever data the tests use.
- **Chiron needs kerykeion's data files.** If kerykeion stops bundling `sweph`, both `bin/astro` and the derivation fail loudly.

**Cost estimate.**

- 10 missions of 25 to 40 minutes each: about 6 worker-hours, plus a mission critique and a merge review for each.
- By comparison with the approved spec's estimate for 12 missions: roughly **20–30 5h points** over two or three windows, and **8–15 7d points**.
- No mission costs have been measured, so these figures are not based on measured data.

### Mission Breakdown

| Order | Row | Mission | Scope | Est. | Deps | Pri |
|---|---|---|---|---|---|---|
| 1 | CORE | Derivation core, sample chart search, sample fixtures beside the old ones | `tests/bin/astro/derive_core.py`, `derive_sample_chart.py`, `test_derived_core.py`, `conftest.py` (add only), `docs/testing.md` | 40m | ASTRO, CANARY | P1 |
| 2 | ZR-DERIVE | Zodiacal-releasing arithmetic in the derivation | `tests/bin/astro/derive_zr.py`, `test_derived_zr.py` | 30m | CORE | P1 |
| 3 | ZR | Zodiacal-releasing tests on the sample chart | `tests/bin/astro/test_zr.py`, `test_derived_zr.py`, `docs/astro.md` | 35m | ZR-DERIVE | P1 |
| 4 | HOUSES-NATAL | Natal tables, synthetic cusps and the transit-house test on the sample chart | `tests/bin/astro/derive_houses.py`, `test_derived_houses.py`, `test_houses.py` | 40m | CORE | P1 |
| 5 | HOUSES-TRANSIT | Transit reference classes on the sample chart | `tests/bin/astro/derive_houses.py`, `test_derived_houses.py`, `test_houses.py` | 35m | HOUSES-NATAL | P2 |
| 6 | FIXES | Forecast, current-position and solar-return tests on the sample chart | `tests/bin/astro/derive_transits.py`, `test_derived_transits.py`, `test_fixes.py`, `test_solar_return.py` | 40m | CORE | P2 |
| 7 | ECLIPSES | Eclipse aspect-set tests on the sample chart | `tests/bin/astro/derive_eclipses.py`, `test_derived_eclipses.py`, `test_eclipses.py` | 25m | CORE | P2 |
| 8 | PARANS | Paran references on the sample chart | `tests/bin/astro/derive_parans.py`, `test_derived_parans.py`, `test_parans.py` | 40m | CORE | P2 |
| 9 | LINES | Aspect-line references on the sample chart | `tests/bin/astro/derive_lines.py`, `test_derived_lines.py`, `test_aspect_lines.py` | 40m | CORE | P2 |
| 10 | SCRUB | Delete the old fixtures; leak check that prints no values | `tests/bin/astro/conftest.py`, `old_chart_guard.py`, `test_old_chart_guard.py`, `docs/testing.md` | 35m | ZR, HOUSES-TRANSIT, FIXES, ECLIPSES, PARANS, LINES | P1 |
| 11 | HISTORY | Operator step: answer the first Open Question. If the answer is a rewrite, the operator does it by hand after SCRUB, never a worker | — | 15m | SCRUB | P3 |

ASTRO and CANARY in CORE's Deps cell are rows of the approved spec `20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate`, not of this table. `alt spec approve` warns about them. When those missions exist, replace the labels with their mission IDs. Until then, open no mission of this spec.

### Done checks

- **CORE**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"core derivation tests","run":"uv run lib/python/run_tests.py bin/astro/test_derived_core.py -v","stdout_contains":["test_derivation_imports_only_stdlib_and_swisseph PASSED","test_sample_chart_meets_selection_criteria PASSED","test_search_finds_the_sample_moment PASSED","test_fixture_matches_derivation_inputs PASSED"]}
]}
```

- **ZR-DERIVE**
```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"zr derivation rules","run":"uv run lib/python/run_tests.py bin/astro/test_derived_zr.py -v","stdout_contains":["test_zr_derivation_minor_years_and_multipliers PASSED","test_zr_derivation_loosing_of_the_bond PASSED","test_zr_derivation_starts_at_birth_with_lot_signs PASSED"]}
]}
```

- **ZR**
```donecheck
{"v":1,"timeout":"20m","checks":[
 {"kind":"command","title":"zr tables match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_zr.py -v","stdout_contains":["test_zr_tables_match_derivation PASSED","test_zr_derivation_loosing_of_the_bond PASSED"]},
 {"kind":"command","title":"zr tests on sample chart","run":"uv run lib/python/run_tests.py bin/astro/test_zr.py -v","stdout_contains":["test_l1_starts_at_taurus PASSED","test_l2_within_gemini_l1 PASSED","test_lb_lands_on_aquarius_in_leo_cycle PASSED","test_l4_within_cap_l3_full_sequence PASSED","test_snapshot_l3_capricorn PASSED","test_timeline_ignores_the_city_when_coordinates_are_given PASSED"],"stdout_matches":"\\b(4[5-9]|[5-9]\\d) passed"}
]}
```

- **HOUSES-NATAL**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"natal tables match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_houses.py -v","stdout_contains":["test_natal_tables_match_derivation PASSED"]},
 {"kind":"command","title":"houses natal tests","run":"uv run lib/python/run_tests.py bin/astro/test_houses.py -v","stdout_contains":["test_natal_planet_positions PASSED","test_natal_house_cusps PASSED","test_natal_aspects PASSED","test_planet_exactly_on_cusp PASSED","test_transit_house_differs_from_transit_chart_house PASSED"]}
]}
```

- **HOUSES-TRANSIT**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"house tables match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_houses.py -v","stdout_contains":["test_natal_tables_match_derivation PASSED","test_transit_tables_match_derivation PASSED"]},
 {"kind":"command","title":"houses transit tests","run":"uv run lib/python/run_tests.py bin/astro/test_houses.py -v","stdout_contains":["test_signs_aspects_and_orbs_match PASSED","test_transit_planet_houses PASSED","test_transit_aspects_and_orbs PASSED","test_natal_planet_positions PASSED"]}
]}
```

- **FIXES**
```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"transit values match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_transits.py -v","stdout_contains":["test_transit_values_match_derivation PASSED"]},
 {"kind":"command","title":"fixes tests","run":"uv run lib/python/run_tests.py bin/astro/test_fixes.py -v","stdout_contains":["test_forecast_includes_node_chiron_lilith_aspects PASSED","test_current_position_uses_natal_cusps_for_house PASSED","test_station_house_from_natal_cusps PASSED"]},
 {"kind":"command","title":"solar return tests","run":"uv run lib/python/run_tests.py bin/astro/test_solar_return.py -v","stdout_contains":["test_sr_past_year_works PASSED","test_sr_at_natal_vs_prague_produces_different_angles PASSED","test_sr_year_zero_returns_natal_jd PASSED"]}
]}
```

- **ECLIPSES**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"eclipse hits match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_eclipses.py -v","stdout_contains":["test_eclipse_hits_match_derivation PASSED"]},
 {"kind":"command","title":"eclipse tests","run":"uv run lib/python/run_tests.py bin/astro/test_eclipses.py -v","stdout_contains":["test_all_aspect_set_includes_sextile_or_trine PASSED","test_conj_opp_default_excludes_sextile_hits PASSED","test_finds_2024_total_solar_eclipse PASSED"]}
]}
```

- **PARANS**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"paran references match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_parans.py -v","stdout_contains":["test_paran_references_match_derivation PASSED"]},
 {"kind":"command","title":"paran tests","run":"uv run lib/python/run_tests.py bin/astro/test_parans.py -v","stdout_contains":["test_taranto_reference_parans PASSED","test_honolulu_reference_parans PASSED","test_canonical_ordering_no_duplicates PASSED","test_no_chiron_excludes_chiron PASSED"]}
]}
```

- **LINES**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"line references match derivation","run":"uv run lib/python/run_tests.py bin/astro/test_derived_lines.py -v","stdout_contains":["test_line_references_match_derivation PASSED"]},
 {"kind":"command","title":"line tests","run":"uv run lib/python/run_tests.py bin/astro/test_aspect_lines.py -v","stdout_contains":["test_taranto_reference PASSED","test_honolulu_reference PASSED","test_orb_zero_for_perfect_conjunction PASSED","test_as_dc_marked_approximate PASSED"]}
]}
```

- **SCRUB**
```donecheck
{"v":1,"timeout":"30m","checks":[
 {"kind":"command","title":"old values guard","run":"uv run lib/python/run_tests.py bin/astro/test_old_chart_guard.py -v","stdout_contains":["test_old_chart_values_are_gone PASSED","test_guard_self_test_detects_every_form PASSED"]},
 {"kind":"command","title":"astro component","run":"uv run lib/python/run_tests.py astro -v","record":true,"stdout_contains":["test_derivation_imports_only_stdlib_and_swisseph PASSED","test_zr_tables_match_derivation PASSED","test_transit_tables_match_derivation PASSED","test_line_references_match_derivation PASSED","test_old_chart_values_are_gone PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Out of Scope

- Any change to `bin/astro` or `bin/astro-zr-helper`, including pinning stellium (the approved spec's second Open Question).
- Rewriting git history. The first Open Question covers it, and a rewrite would be an operator step, never a worker's.
- Removing the old values from places outside this repository, such as forks, caches and archives.
- Porting the kerykeion v5 deprecations.
- Personal data in any test component other than `bin/astro`.

## Open Questions

1. **Remove the old values from git history?** They first entered `master` in `b51dd8fc` (2026-03-24). They are on `origin/master`, and 351 of the 1505 commits on `master` follow that commit. No commit message holds them.

   **Recommendation: do not rewrite.** The values have been public for eight months, so forks, clones, GitHub's cached views and public archives already hold them. A rewrite cannot take them back. It would also:
   - change every later commit id, which breaks every Altera spec, review and worklog that cites one, including this spec's pinned `OLD_COMMIT`;
   - force a re-clone of every checkout, worktree and jj working copy;
   - turn the leak check into a skip unless the private file exists.

   If the operator still wants it, do it after SCRUB as a separate operator step:
   - First write `.cc/private/astro-old-chart.json`.
   - Run `git filter-repo --replace-text` with an expressions file kept in `.cc/private/`.
   - Force-push, and ask GitHub Support to purge cached views and pull-request refs.
   - Re-clone everywhere, and update the cited commit ids.

2. **Cross-check the sample chart against an outside calculator?** The new tables lose the astro-seek and astro.com oracle. **Recommendation: yes, as an optional 10-minute operator step after ZR, not a gate.** Enter the public sample chart into astro-seek's zodiacal-releasing calculator and compare the L1 and L2 Fortune dates within ±1 day. The sample chart is synthetic, so nothing private is sent.

3. **Keep the leak check after this work lands?** **Recommendation: keep it.** It takes under a second. It catches an old value copied back from history. It skips cleanly where history is missing.

4. **Rename the `sample_*` fixtures back to `birth_data` and the others in SCRUB?** **Recommendation: no.** The rename touches every file again for no gain, and the `sample_` prefix tells a reader that the chart is synthetic.
