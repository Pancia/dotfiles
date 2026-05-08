"""Tests for SolarReturnCalculator (`astro relocate solar-return`).

Covers:
  - Birth-year self-consistency: SR for natal year reproduces natal Sun
  - Future-year SR places Sun at natal Sun longitude (within bisection tol)
  - Destination tz_str (not natal!) drives SR house cusps
  - Past-year support
  - Bisection bracket holds for chart with Sun near 0° Aries (wrap-edge)
"""


# =============================================================================
# Self-consistency: SR returns Sun to natal Sun longitude
# =============================================================================

class TestSolarReturnSelfConsistency:

    def test_sr_year_zero_returns_natal_jd(self, astro_module, transit_calc,
                                           birth_data, natal_subject):
        """SR target_year = birth year ⇒ SR JD equals natal JD exactly."""
        srcalc = astro_module.SolarReturnCalculator(transit_calc)
        natal_jd = natal_subject.julian_day
        natal_sun = natal_subject.sun.abs_pos
        sr_jd = srcalc.find_sr_jd(natal_jd, natal_sun, target_year_offset=0)
        assert abs(sr_jd - natal_jd) < 1e-9

    def test_sr_future_year_places_sun_at_natal_longitude(
            self, astro_module, transit_calc, birth_data, natal_subject):
        """For arbitrary future year, transiting Sun at SR JD = natal Sun lon."""
        import swisseph as swe
        srcalc = astro_module.SolarReturnCalculator(transit_calc)
        natal_jd = natal_subject.julian_day
        natal_sun = natal_subject.sun.abs_pos

        for offset in (1, 5, 10, 33):
            sr_jd = srcalc.find_sr_jd(natal_jd, natal_sun, target_year_offset=offset)
            sun_at_sr = swe.calc_ut(sr_jd, swe.SUN)[0][0] % 360.0
            # The signed-wrap difference must be within bisection tolerance
            diff = ((sun_at_sr - natal_sun + 180) % 360) - 180
            assert abs(diff) < 0.001, (
                f"offset={offset}: SR sun {sun_at_sr:.6f}° vs natal "
                f"{natal_sun:.6f}° — diff {diff:.6f}° exceeds 0.001° tol"
            )

    def test_sr_past_year_works(self, astro_module, transit_calc, birth_data,
                                natal_subject):
        """Past year SR works (retrospective analysis)."""
        import swisseph as swe
        srcalc = astro_module.SolarReturnCalculator(transit_calc)
        natal_jd = natal_subject.julian_day
        natal_sun = natal_subject.sun.abs_pos
        # Anthony was born 1993; cast SR for 2020 (offset = 27)
        sr_jd_2020 = srcalc.find_sr_jd(natal_jd, natal_sun, target_year_offset=27)
        sun_at_sr = swe.calc_ut(sr_jd_2020, swe.SUN)[0][0] % 360.0
        diff = ((sun_at_sr - natal_sun + 180) % 360) - 180
        assert abs(diff) < 0.001
        # 2020 SR should fall in October-ish
        y, mo, _d, _h = swe.revjul(sr_jd_2020)
        assert y == 2020
        assert mo == 10  # birthday month


# =============================================================================
# Destination tz_str matters
# =============================================================================

class TestSolarReturnDestinationTz:
    """SR cast at different locations + tz produces different ASC/MC.

    This is the core SR-vs-relocate distinction: SR uses destination-local
    TIME (different tz, different LST, different angles). If we used natal
    tz_str instead (the relocate-chart convention), the same SR would
    erroneously produce identical angles regardless of destination.
    """

    def test_sr_at_natal_vs_prague_produces_different_angles(
            self, astro_module, transit_calc, birth_data):
        chart = astro_module.NatalChart(
            name="anthony_sr_tz",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        srcalc = astro_module.SolarReturnCalculator(transit_calc)

        # SR at natal coords + natal tz
        sr_natal = srcalc.compute(
            chart,
            lat=birth_data.lat, lng=birth_data.lng,
            tz_str=birth_data.tz_str,
            target_year=2026,
        )
        # SR at Prague + Europe/Prague tz
        sr_prague = srcalc.compute(
            chart,
            lat=50.0875, lng=14.4214,
            tz_str='Europe/Prague',
            target_year=2026,
        )

        # SR moment (UTC) is identical — only Sun's longitude matters
        assert abs(sr_natal['sr_jd'] - sr_prague['sr_jd']) < 1e-6

        # But angles differ — different lat, different lng, different LST
        for code in ('ASC', 'MC'):
            diff = abs(((sr_natal['angles'][code] - sr_prague['angles'][code] + 180)
                        % 360) - 180)
            assert diff > 5.0, (
                f"{code} should differ between natal-loc SR and Prague SR; "
                f"got natal {sr_natal['angles'][code]:.2f}° vs Prague "
                f"{sr_prague['angles'][code]:.2f}° (diff {diff:.2f}°)"
            )


# =============================================================================
# Bisection edge cases
# =============================================================================

class TestSolarReturnBisection:

    def test_bisection_handles_natal_sun_near_aries_zero(
            self, astro_module, transit_calc):
        """Synthetic chart with natal Sun near 0° Aries — bisection bracket
        must keep the signed-wrap function monotone. Without bracketing, the
        wrap discontinuity would silently produce a wrong root."""
        import swisseph as swe
        srcalc = astro_module.SolarReturnCalculator(transit_calc)
        # Build a chart born around vernal equinox (Sun near 0° Aries)
        # 2000-03-20 12:00 UT — Sun at ~0°6' Aries
        natal_jd = swe.julday(2000, 3, 20, 12.0)
        natal_sun = swe.calc_ut(natal_jd, swe.SUN)[0][0] % 360.0
        # Verify the test setup is what we expect
        assert natal_sun < 1.0 or natal_sun > 359.0, (
            f"Test relies on natal Sun near 0° Aries; got {natal_sun:.4f}°"
        )

        # SR for 5 years later
        sr_jd = srcalc.find_sr_jd(natal_jd, natal_sun, target_year_offset=5)
        sun_at_sr = swe.calc_ut(sr_jd, swe.SUN)[0][0] % 360.0
        diff = ((sun_at_sr - natal_sun + 180) % 360) - 180
        assert abs(diff) < 0.001, (
            f"Bisection drift at Aries-zero: SR sun {sun_at_sr:.6f}° vs "
            f"natal {natal_sun:.6f}°, diff {diff:.6f}°"
        )
        # SR should be approx 5 years after natal — sanity check
        assert abs(sr_jd - natal_jd - 5 * 365.2422) < 30.0  # ±30 days
