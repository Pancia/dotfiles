"""Tests for EclipseCalculator (`astro relocate eclipses`).

Reference data: NASA Five Millennium Catalog of Solar/Lunar Eclipses.
We pin two well-known eclipses and verify our calculator finds them at
the correct Julian Day and longitude:

  - 2024-04-08 18:17 UT  Total solar eclipse at 19°24' Aries
  - 2024-03-25 07:13 UT  Penumbral lunar eclipse at 5°07' Libra

Plus solver units exercising the lunar-vs-solar longitude convention,
the conj-opp default aspect set, and iteration termination.
"""

# =============================================================================
# Reference reproductions: NASA-published 2024 eclipses
# =============================================================================

class TestEclipseReferenceValues:

    def test_finds_2024_total_solar_eclipse(self, astro_module, transit_calc):
        """Starting from 2024-01-01, we find the April 8 2024 total solar
        eclipse at the right JD (within ±60 sec) and longitude (within 0.1°)."""
        import swisseph as swe
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        jd_start = swe.julday(2024, 1, 1, 0)
        eclipses = ec.eclipses_in_range(jd_start, 0.5, types=('solar',))
        # First solar eclipse in 2024 is the April 8 total
        assert eclipses, "Should find at least one solar eclipse"
        e = eclipses[0]
        # NASA: peak at 2024-04-08 18:17:21 UT  →  jd ≈ 2460409.262...
        expected_jd = 2460409.2621
        assert abs(e['jd'] - expected_jd) < 1.0 / 1440  # within 1 minute
        assert abs(e['lon'] - 19.40) < 0.1  # 19°24' Aries
        assert e['sign'] == 'Ari'
        assert e['type'] == 'solar'

    def test_finds_2024_lunar_eclipse(self, astro_module, transit_calc):
        """March 25 2024 penumbral lunar eclipse at ~5°07' Libra."""
        import swisseph as swe
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        jd_start = swe.julday(2024, 1, 1, 0)
        eclipses = ec.eclipses_in_range(jd_start, 0.5, types=('lunar',))
        assert eclipses, "Should find at least one lunar eclipse"
        e = eclipses[0]
        # NASA: peak ≈ 2024-03-25 07:12:48 UT
        expected_jd = swe.julday(2024, 3, 25, 7 + 13 / 60.0)
        assert abs(e['jd'] - expected_jd) < 5.0 / 1440  # within 5 minutes
        # Moon at 5°07' Libra → 185.12° absolute
        assert abs(e['lon'] - 185.12) < 0.5
        assert e['sign'] == 'Lib'
        assert e['type'] == 'lunar'


# =============================================================================
# Solver units
# =============================================================================

class TestEclipseSolverUnits:

    def test_solar_eclipse_longitude_is_sun(self, astro_module, transit_calc):
        """At peak, our reported eclipse_lon should equal swe.calc_ut(jd, SUN)."""
        import swisseph as swe
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        jd_start = swe.julday(2024, 1, 1, 0)
        e = ec.eclipses_in_range(jd_start, 0.5, types=('solar',))[0]
        sun_lon = swe.calc_ut(e['jd'], swe.SUN)[0][0] % 360.0
        assert abs(e['lon'] - sun_lon) < 0.001

    def test_lunar_eclipse_longitude_is_moon_not_sun(self, astro_module, transit_calc):
        """At lunar eclipse peak, eclipse_lon should equal MOON longitude
        (NOT Sun, which is 180° away). Easy bug to introduce."""
        import swisseph as swe
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        jd_start = swe.julday(2024, 1, 1, 0)
        e = ec.eclipses_in_range(jd_start, 0.5, types=('lunar',))[0]
        moon_lon = swe.calc_ut(e['jd'], swe.MOON)[0][0] % 360.0
        sun_lon = swe.calc_ut(e['jd'], swe.SUN)[0][0] % 360.0
        # eclipse_lon matches Moon
        assert abs(e['lon'] - moon_lon) < 0.001
        # And does NOT match Sun (Sun is opposite Moon at lunar eclipse peak)
        diff_sun = abs(((e['lon'] - sun_lon + 180) % 360) - 180)
        assert diff_sun > 170, (
            f"eclipse_lon should be ~180° from Sun for lunar eclipse, "
            f"got separation {diff_sun:.2f}°"
        )

    def test_iteration_terminates(self, astro_module, transit_calc):
        """5-year window across both types should complete fast and find
        ~10 solar + ~10 lunar eclipses without infinite loop."""
        import swisseph as swe
        import time
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        jd_start = swe.julday(2024, 1, 1, 0)
        t0 = time.time()
        eclipses = ec.eclipses_in_range(jd_start, 5.0, types=('solar', 'lunar'))
        elapsed = time.time() - t0
        assert elapsed < 5.0, f"Took {elapsed:.1f}s — possible inefficiency"
        # ~2 solar + ~2 lunar per year
        n_solar = sum(1 for e in eclipses if e['type'] == 'solar')
        n_lunar = sum(1 for e in eclipses if e['type'] == 'lunar')
        assert 8 <= n_solar <= 14, f"unexpected solar count {n_solar}"
        assert 8 <= n_lunar <= 14, f"unexpected lunar count {n_lunar}"


class TestAspectSetFiltering:
    """Default `--aspects conj-opp` excludes sextile/square/trine; `--aspects all` includes them."""

    def test_conj_opp_default_excludes_sextile_hits(
            self, astro_module, transit_calc, birth_data):
        chart = astro_module.NatalChart(
            name="anthony_eclipse_test",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        import swisseph as swe
        jd_start = swe.julday(2026, 1, 1, 0)
        # Conj-opp only (default)
        rows_co = ec.hits_to_relocated_angles(
            chart, 50.0875, 14.4214,
            years=2.0, orb=3.0, aspect_set='conj-opp',
            jd_start=jd_start,
        )
        # All aspects
        rows_all = ec.hits_to_relocated_angles(
            chart, 50.0875, 14.4214,
            years=2.0, orb=3.0, aspect_set='all',
            jd_start=jd_start,
        )
        # `all` returns >= conj-opp count
        assert len(rows_all) >= len(rows_co)
        # All conj-opp rows have aspect ∈ {conj, opposition}
        for r in rows_co:
            assert r['aspect'] in ('conj', 'opposition'), (
                f"conj-opp returned non-canonical aspect: {r}"
            )

    def test_all_aspect_set_includes_sextile_or_trine(
            self, astro_module, transit_calc, birth_data):
        chart = astro_module.NatalChart(
            name="anthony_eclipse_all",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        rc = astro_module.RelocationCalculator(transit_calc.storage, transit_calc)
        ec = astro_module.EclipseCalculator(transit_calc, rc)
        import swisseph as swe
        jd_start = swe.julday(2026, 1, 1, 0)
        rows = ec.hits_to_relocated_angles(
            chart, 50.0875, 14.4214,
            years=2.0, orb=3.0, aspect_set='all',
            jd_start=jd_start,
        )
        aspect_kinds = {r['aspect'] for r in rows}
        # In a 2-year window for Anthony @ Prague there's at least one
        # non-canonical aspect (verified by hand for this chart/window).
        non_canon = aspect_kinds - {'conj', 'opposition'}
        assert non_canon, (
            f"expected at least one sextile/square/trine hit in `all` mode; "
            f"got only {aspect_kinds}"
        )
