"""Tests for the three fixes addressing agent-surfaced limitations:

  A. `forecast` includes transit aspects to natal nodes / Chiron / Lilith by
     default (without `--all`).
  B. `forecast` surfaces a Sustained Aspects section for slow-moving aspects
     that hold within a wider orb for stretches.
  C. `astro planet`:
       (i) "Current Position" reflects the planet's actual position today,
           not the date of the last detected event.
       (ii) `_detect_station` uses natal cusps for the house, not the
            transit chart's house attribute.
"""

from datetime import datetime, timedelta
from types import SimpleNamespace

import pytest


# =============================================================================
# Fix A — forecast natal-side filter accepts nodes / Chiron / Lilith
# =============================================================================

class TestImportantNatalPoints:
    """Regression: forecast must show transit aspects to natal nodes/Chiron/Lilith
    in default (`major_only=True`) mode. Previously the natal-side filter only
    allowed MAJOR_PLANETS, hiding these objects unless `--all` was used."""

    def test_important_natal_points_constant(self, astro_module):
        """The constant must include nodes, Chiron, Lilith, and the major planets."""
        calc_cls = astro_module.TransitCalculator
        assert 'True_North_Lunar_Node' in calc_cls.IMPORTANT_NATAL_POINTS
        assert 'True_South_Lunar_Node' in calc_cls.IMPORTANT_NATAL_POINTS
        assert 'Chiron' in calc_cls.IMPORTANT_NATAL_POINTS
        assert 'Mean_Lilith' in calc_cls.IMPORTANT_NATAL_POINTS
        # Should be a strict superset of MAJOR_PLANETS
        assert calc_cls.MAJOR_PLANETS.issubset(calc_cls.IMPORTANT_NATAL_POINTS)

    def test_forecast_includes_node_chiron_lilith_aspects(
        self, astro_module, birth_data, tmp_path,
    ):
        """A 60-day default-mode forecast on Anthony's chart should include at
        least one transit aspect to natal North Node, Chiron, or Lilith.

        For 2026, Saturn is conjunct natal Lilith (~ARI 11°), Neptune trines
        natal North Node (~SAG 3.6°), and Pluto sextiles natal North Node from
        Aquarius. So default-mode forecast must surface these by name."""
        chart = astro_module.NatalChart(
            name="anthony_test",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        # Use a fresh storage for this test so cache isn't shared.
        storage = astro_module.AstroStorage(base_path=tmp_path)
        calc = astro_module.TransitCalculator(storage)

        forecast = calc.forecast_transits(
            chart, days=60, orb_limit=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )

        natal_targets = set()
        for _date, events in forecast:
            for e in events:
                natal_targets.add(e.natal_planet)

        assert 'Mean_Lilith' in natal_targets, \
            f"Expected Mean_Lilith aspect in default forecast; got {sorted(natal_targets)}"
        assert ('True_North_Lunar_Node' in natal_targets
                or 'True_South_Lunar_Node' in natal_targets), \
            f"Expected node aspect in default forecast; got {sorted(natal_targets)}"
        assert 'Chiron' in natal_targets, \
            f"Expected Chiron aspect in default forecast; got {sorted(natal_targets)}"

    def test_forecast_filter_blocks_nonmajor_transit_planet(
        self, astro_module, birth_data, tmp_path,
    ):
        """The transit side stays restricted to MAJOR_PLANETS in default mode —
        e.g. Ascendant or Imum_Coeli should NOT appear as a transit planet
        unless `--all` is set."""
        chart = astro_module.NatalChart(
            name="anthony_test_blocked",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        storage = astro_module.AstroStorage(base_path=tmp_path)
        calc = astro_module.TransitCalculator(storage)

        forecast = calc.forecast_transits(
            chart, days=14, orb_limit=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )

        for _date, events in forecast:
            for e in events:
                # Skip ingress/station/lunar sentinel events
                if e.aspect in {'sign_ingress', 'house_ingress',
                                'station_retrograde', 'station_direct'}:
                    continue
                if e.transit_planet in ('New Moon', 'Full Moon'):
                    continue
                assert e.transit_planet in calc.MAJOR_PLANETS, (
                    f"Transit-side filter leaked: got transit_planet={e.transit_planet!r} "
                    f"in default mode (should require --all)"
                )


# =============================================================================
# Fix B — sustained aspects pass-splitting and filtering
# =============================================================================

def _make_event(transit_planet, natal_planet, aspect, orb):
    """Build a TransitEvent with just the fields sustained_aspects reads."""
    return SimpleNamespace(
        transit_planet=transit_planet,
        natal_planet=natal_planet,
        aspect=aspect,
        orb=orb,
        transit_sign='', transit_house='',
        natal_sign='', natal_house='',
        applying=True, exact_date=None,
    )


class TestSustainedAspects:
    """Test the sustained_aspects pass-splitting, peak detection, and filters.

    Uses synthetic per-day data via a stub storage that returns canned
    aspect lists. No kerykeion needed for these tests."""

    @pytest.fixture
    def stub_calc(self, astro_module):
        """A TransitCalculator with storage stubbed so we can drive
        `sustained_aspects` with synthetic per-day data."""
        # daily_events: dict keyed by ISO date string -> list[TransitEvent]
        daily_events: dict[str, list] = {}

        class StubStorage:
            def load_config(self):
                return astro_module.Config()

            def get_cached_transit(self, date_str, _chart_name):
                # Always return a cached entry (empty for missing days) so
                # sustained_aspects doesn't fall through to compute_day_transits
                # which needs a real natal chart.
                events = daily_events.get(date_str, [])
                return {'aspects': [vars(e).copy() for e in events]}

            def cache_transit(self, *_args, **_kwargs):
                pass

        calc = astro_module.TransitCalculator(StubStorage())
        return calc, daily_events

    def test_pass_splits_on_gap(self, astro_module, stub_calc):
        """Two in-orb runs separated by > 2 days should become two passes.

        Saturn-Moon square: in orb day 1-3, gap, in orb day 8-10."""
        calc, daily = stub_calc

        for offset, orb in [(0, 1.5), (1, 0.8), (2, 1.2)]:
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Saturn', 'Moon', 'square', orb)]
        # gap (no events on 2026-05-07)
        for offset, orb in [(7, 1.4), (8, 0.5), (9, 1.6)]:
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Saturn', 'Moon', 'square', orb)]

        chart = astro_module.NatalChart(
            name="stub", birth_data=None, created_at="x",
        )
        # Bypass compute_day_transits entirely by relying on the stub cache
        results = calc.sustained_aspects(
            chart, days=12, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )

        # Saturn is a SLOW_PLANET so 3-day passes pass the duration filter.
        sat_moon = [r for r in results
                    if r.transit_planet == 'Saturn' and r.natal_planet == 'Moon']
        assert len(sat_moon) == 2, \
            f"Expected 2 passes split by the gap; got {len(sat_moon)}"
        # First pass peaks on day 2 (orb 0.8), second on day 9 (orb 0.5)
        peaks = sorted([(p.peak_date, p.peak_orb) for p in sat_moon])
        assert peaks[0][0] == '2026-05-05'
        assert peaks[0][1] == pytest.approx(0.8)
        assert peaks[1][0] == '2026-05-12'
        assert peaks[1][1] == pytest.approx(0.5)

    def test_short_fast_planet_pass_filtered_out(self, astro_module, stub_calc):
        """A 3-day Mercury pass should be filtered out (not a SLOW_PLANET,
        duration < 5 days)."""
        calc, daily = stub_calc

        for offset in range(3):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Mercury', 'Sun', 'trine', 0.4)]

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=5, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        mercury = [r for r in results if r.transit_planet == 'Mercury']
        assert mercury == [], \
            "Short Mercury pass should be filtered out (fast + duration < 5)"

    def test_long_fast_planet_pass_kept(self, astro_module, stub_calc):
        """A 6-day Sun pass should be kept (duration >= 5)."""
        calc, daily = stub_calc

        for offset in range(6):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Sun', 'Mercury', 'opposition', 0.3)]

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=8, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        suns = [r for r in results if r.transit_planet == 'Sun']
        assert len(suns) == 1
        assert suns[0].first_date == '2026-05-04'
        assert suns[0].last_date == '2026-05-09'

    def test_short_slow_planet_pass_kept(self, astro_module, stub_calc):
        """A 2-day Pluto pass should be kept (Pluto is a SLOW_PLANET)."""
        calc, daily = stub_calc

        for offset in range(2):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Pluto', 'Venus', 'trine', 1.5)]

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=5, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        pluto = [r for r in results if r.transit_planet == 'Pluto']
        assert len(pluto) == 1, \
            "Short Pluto pass should be kept (slow planet bypasses duration filter)"

    def test_sustained_orb_threshold_excludes_wide_aspects(
        self, astro_module, stub_calc,
    ):
        """Aspects with |orb| > sustained_orb should be excluded."""
        calc, daily = stub_calc

        for offset in range(7):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            # All days have orb 2.5° — wider than the 2.0° threshold below
            daily[d] = [_make_event('Jupiter', 'Sun', 'square', 2.5)]

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=8, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        assert results == [], \
            "Aspects with |orb| > sustained_orb must be excluded"

    def test_ongoing_flag_set_when_pass_runs_to_window_end(
        self, astro_module, stub_calc,
    ):
        """Pass extending to the last day of the window must have ongoing=True."""
        calc, daily = stub_calc

        # 5 days, last day == window end
        for offset in range(5):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily[d] = [_make_event('Saturn', 'Sun', 'trine', 1.0)]

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=5, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        assert len(results) == 1
        assert results[0].ongoing is True

    def test_results_sorted_by_duration_desc(self, astro_module, stub_calc):
        """Longest passes should sort first."""
        calc, daily = stub_calc

        # Saturn-Moon: 8-day pass
        for offset in range(8):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily.setdefault(d, []).append(_make_event('Saturn', 'Moon', 'square', 1.0))
        # Pluto-Venus: 3-day pass (slow planet, kept)
        for offset in range(3):
            d = (datetime(2026, 5, 4) + timedelta(days=offset)).date().isoformat()
            daily.setdefault(d, []).append(_make_event('Pluto', 'Venus', 'trine', 1.5))

        chart = astro_module.NatalChart(name="stub", birth_data=None, created_at="x")
        results = calc.sustained_aspects(
            chart, days=10, sustained_orb=2.0, major_only=True,
            start_date=datetime(2026, 5, 4),
        )
        assert len(results) == 2
        # Saturn-Moon (7-day duration: last - first = 7) before Pluto-Venus (2-day)
        assert results[0].transit_planet == 'Saturn'
        assert results[1].transit_planet == 'Pluto'


# =============================================================================
# Fix C(i) — current_position snapshot
# =============================================================================

class TestCurrentPosition:
    """`current_position` returns the planet's actual position at the given
    date, with the natal house resolved from cusps."""

    def test_current_position_uses_natal_cusps_for_house(
        self, astro_module, transit_calc, birth_data, natal_cusps,
    ):
        """Saturn at 2026-05-04 is in Aries ~9-10°. Anthony's natal cusps put
        Aries 0-28.83° in House 2, so the current_position must report '2'.

        Before the fix, `astro planet` could surface stale event-derived
        houses (e.g. "House 7") because it used `events[-1].house` from the
        last station event."""
        chart = astro_module.NatalChart(
            name="anthony_test_curr",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        snapshot = transit_calc.current_position(
            chart, 'saturn', datetime(2026, 5, 4),
        )
        assert snapshot is not None
        assert snapshot.event_type == 'current_position'
        assert snapshot.sign == 'Ari'
        # Independent verification via the same primitive used by the fix
        expected = transit_calc._planet_in_natal_house(snapshot.degree, natal_cusps)
        assert snapshot.house == expected
        assert snapshot.house == '2'  # Aries 9-10° in Anthony's chart

    def test_current_position_unknown_planet_returns_none(
        self, transit_calc, birth_data, astro_module,
    ):
        chart = astro_module.NatalChart(
            name="anthony_test_unknown",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        snap = transit_calc.current_position(
            chart, 'nonexistent_planet', datetime(2026, 5, 4),
        )
        assert snap is None


# =============================================================================
# Fix C(ii) — _detect_station uses natal cusps for house
# =============================================================================

class TestDetectStationHouse:
    """Regression: stations report the natal house, not the transit chart's."""

    def test_station_house_from_natal_cusps(
        self, transit_calc, birth_data, natal_cusps,
    ):
        """Build prev/curr subjects on either side of Pluto's 2026-05-06 retro
        station. The detected event must have `house` matching
        `_planet_in_natal_house` against natal cusps — NOT the transit chart's
        own house attribute (which would give a different value because the
        transit chart's AC is wherever it is at that moment)."""
        # Pluto stations retrograde around 2026-05-06 at ~5.5° Aquarius.
        prev_subj = transit_calc._make_subject(
            "Transit", 2026, 5, 5, 12, 0, birth_data,
        )
        curr_subj = transit_calc._make_subject(
            "Transit", 2026, 5, 7, 12, 0, birth_data,
        )

        event = transit_calc._detect_station(
            'pluto', datetime(2026, 5, 7).date(),
            prev_subj, curr_subj, natal_cusps,
        )
        assert event is not None, "Should detect Pluto retrograde station"
        assert event.event_type == 'station_retrograde'

        # House must equal _planet_in_natal_house against natal cusps
        pluto = transit_calc._get_planet_obj(curr_subj, 'pluto')
        expected = transit_calc._planet_in_natal_house(pluto.abs_pos, natal_cusps)
        assert event.house == expected, (
            f"Station house {event.house!r} doesn't match natal-cusp lookup "
            f"{expected!r} — the bug from the agent report has resurfaced."
        )

    def test_station_event_none_when_no_speed_crossing(
        self, transit_calc, birth_data, natal_cusps,
    ):
        """No station event when speed sign doesn't change."""
        # Two days during normal direct motion — Sun moves direct always
        prev_subj = transit_calc._make_subject(
            "Transit", 2026, 5, 4, 12, 0, birth_data,
        )
        curr_subj = transit_calc._make_subject(
            "Transit", 2026, 5, 5, 12, 0, birth_data,
        )
        event = transit_calc._detect_station(
            'sun', datetime(2026, 5, 5).date(),
            prev_subj, curr_subj, natal_cusps,
        )
        assert event is None
