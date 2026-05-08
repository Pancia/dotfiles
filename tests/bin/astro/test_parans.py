"""Tests for ParanCalculator (`astro relocate parans`).

Reproduces astro.com's "Astro Click Travel" parans listing for two reference
latitudes against Anthony's natal chart:

  - Taranto, Italy   (40°28'N)
  - Honolulu, Hawaii (21°22'N)

Reference values are paran pairs and angles only; we don't assert exact paran
latitudes (each within ±2.5° of target is the assertion). Order of (planet_a,
angle_a) vs. (planet_b, angle_b) may swap because we emit canonical lexical
ordering — tests check both orderings.

Solver units exercise: angle-LST formulas, circumpolar None handling, ε-buffer
exclusion near circumpolar boundaries, wrap-discontinuity guard, and a
synthetic known-root bisection.
"""

import pytest


# =============================================================================
# Reference reproductions
# =============================================================================

class TestParanReferenceValues:
    """astro.com Astro Click Travel parans reproductions (Anthony chart)."""

    REFS_TARANTO_LAT = 40.4667
    # astro.com Taranto parans for Anthony chart. Order shown by astro.com:
    REFS_TARANTO = [
        ('Mars',       'IC', 'Saturn',     'DC'),
        ('Mercury',    'DC', 'Mars',       'DC'),
        ('Sun',        'DC', 'Jupiter',    'DC'),
        ('Saturn',     'AC', 'Chiron',     'DC'),
        ('Mercury',    'AC', 'Chiron',     'MC'),
    ]

    REFS_HONOLULU_LAT = 21.3667
    REFS_HONOLULU = [
        ('Saturn',     'AC', 'North Node', 'MC'),
        ('Mercury',    'AC', 'Saturn',     'IC'),
    ]

    DELTA_LAT_TOLERANCE = 2.5  # default for paran band

    def _check_parans(self, rows, expected):
        """Each expected (A, X, B, Y) must appear in rows in some ordering."""

        def _matches(row, exp):
            ea_a, ea_aX, ea_b, ea_bY = exp
            # Either canonical or swapped ordering
            return (
                (row['planet_a'] == ea_a and row['angle_a'] == ea_aX
                 and row['planet_b'] == ea_b and row['angle_b'] == ea_bY)
                or
                (row['planet_a'] == ea_b and row['angle_a'] == ea_bY
                 and row['planet_b'] == ea_a and row['angle_b'] == ea_aX)
            )

        for exp in expected:
            matches = [r for r in rows if _matches(r, exp)]
            assert matches, (
                f"Missing paran: {exp[0]}/{exp[2]} {exp[1]}/{exp[3]}.\n"
                f"  rows: {[(r['planet_a'], r['angle_a'], r['planet_b'], r['angle_b']) for r in rows]}"
            )
            # All matches within tolerance of target
            for row in matches:
                assert abs(row['delta_lat']) <= self.DELTA_LAT_TOLERANCE, (
                    f"Paran {exp} too far: Δlat = {row['delta_lat']:.3f}° "
                    f"(tol {self.DELTA_LAT_TOLERANCE}°)"
                )

    def test_taranto_reference_parans(self, astro_module, transit_calc,
                                      birth_data):
        chart = astro_module.NatalChart(
            name="anthony_taranto_parans",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        pcalc = astro_module.ParanCalculator(transit_calc)
        rows = pcalc.parans_near(
            chart, self.REFS_TARANTO_LAT,
            max_delta_lat=self.DELTA_LAT_TOLERANCE,
        )
        self._check_parans(rows, self.REFS_TARANTO)

    def test_honolulu_reference_parans(self, astro_module, transit_calc,
                                       birth_data):
        chart = astro_module.NatalChart(
            name="anthony_honolulu_parans",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        pcalc = astro_module.ParanCalculator(transit_calc)
        rows = pcalc.parans_near(
            chart, self.REFS_HONOLULU_LAT,
            max_delta_lat=self.DELTA_LAT_TOLERANCE,
        )
        self._check_parans(rows, self.REFS_HONOLULU)


# =============================================================================
# Pure-math units for the LST/angle solver
# =============================================================================

class TestLstOnAngle:
    """Unit tests for ParanCalculator._lst_on_angle (pure spherical-trig math)."""

    def test_mc_returns_planet_ra(self, astro_module):
        ParanC = astro_module.ParanCalculator
        # MC LST = RA, lat-independent
        assert ParanC._lst_on_angle(123.45, -10.0, 'MC',  40.0) == pytest.approx(123.45)
        assert ParanC._lst_on_angle(123.45, -10.0, 'MC',   0.0) == pytest.approx(123.45)
        assert ParanC._lst_on_angle(123.45, -10.0, 'MC', -60.0) == pytest.approx(123.45)

    def test_ic_is_180_offset(self, astro_module):
        ParanC = astro_module.ParanCalculator
        # IC LST = (RA + 180) mod 360
        assert ParanC._lst_on_angle(50.0, 0.0, 'IC', 40.0) == pytest.approx(230.0)
        # Wrap test
        assert ParanC._lst_on_angle(200.0, 0.0, 'IC', 40.0) == pytest.approx(20.0)

    def test_ac_dc_symmetric_around_meridian(self, astro_module):
        """AC LST = RA - H, DC LST = RA + H, so (AC + DC) / 2 = RA (mod 360)."""
        ParanC = astro_module.ParanCalculator
        # Equator + 0° dec planet → H = 90°
        ac = ParanC._lst_on_angle(100.0, 0.0, 'AC', 0.0)
        dc = ParanC._lst_on_angle(100.0, 0.0, 'DC', 0.0)
        # AC at LST = 100 - 90 = 10; DC at LST = 100 + 90 = 190
        assert ac == pytest.approx(10.0)
        assert dc == pytest.approx(190.0)

    def test_circumpolar_returns_none(self, astro_module):
        """Body with declination 80° at lat 85° → never sets, AC/DC undefined."""
        ParanC = astro_module.ParanCalculator
        assert ParanC._lst_on_angle(0.0,  80.0, 'AC',  85.0) is None
        assert ParanC._lst_on_angle(0.0,  80.0, 'DC',  85.0) is None
        # And the perpetual-night case (negative dec, far southern lat)
        assert ParanC._lst_on_angle(0.0, -80.0, 'AC',  85.0) is None
        # MC/IC are always defined
        assert ParanC._lst_on_angle(0.0,  80.0, 'MC',  85.0) is not None

    def test_wrap_signed_maps_to_signed_180_band(self, astro_module):
        ParanC = astro_module.ParanCalculator
        assert ParanC._wrap_signed(190.0)  == pytest.approx(-170.0)
        assert ParanC._wrap_signed(-190.0) == pytest.approx( 170.0)
        assert ParanC._wrap_signed(45.0)   == pytest.approx(  45.0)
        assert ParanC._wrap_signed(-45.0)  == pytest.approx( -45.0)
        # 360° wraps to 0
        assert ParanC._wrap_signed(360.0)  == pytest.approx(   0.0)


class TestParanSolver:
    """Unit tests for the bisection root finder and its safety rails."""

    def test_bisection_finds_synthetic_root(self, astro_module, transit_calc):
        """Given two synthetic planets with known declinations, hand-construct
        a paran latitude and verify the solver finds it within 0.01°.

        Setup: planet A is on MC at all latitudes (LST = RA_A = 100°). Planet B
        is on AC (rising) when LST = RA_B - H_B(L). For LST_A = LST_B:

            100 = 200 - acos(-tan L · tan 0°) = 200 - 90  →  100 = 110  (contradiction)

        So instead pick planet B with non-zero dec to give H_B(L) variation.
        Concrete: RA_B = 190, dec_B = +30°.
            f(L) = LST_A_MC - LST_B_AC
                 = 100 - (190 - acos(-tan L · tan 30°))
                 = -90 + acos(-tan L · tan 30°)
            f(L) = 0  ⇒  acos(-tan L · tan 30°) = 90°
                       ⇒  -tan L · tan 30° = 0
                       ⇒  L = 0°  (the equator)
        """
        ParanC = astro_module.ParanCalculator
        pcalc = ParanC(transit_calc)
        roots = pcalc._find_paran_roots(
            ra_a=100.0, dec_a=0.0,  angle_a='MC',
            ra_b=190.0, dec_b=30.0, angle_b='AC',
            lat_lo=-30.0, lat_hi=30.0,
        )
        # Known root: L = 0°
        assert any(abs(r - 0.0) < 0.01 for r in roots), (
            f"Expected a root at L=0°, got: {roots}"
        )

    def test_circumpolar_does_not_raise(self, astro_module, transit_calc):
        """High-declination planets at high latitudes must not crash the solver."""
        ParanC = astro_module.ParanCalculator
        pcalc = ParanC(transit_calc)
        # Sweep from lat 60 to 89, where dec=80° goes circumpolar (~lat>10°)
        roots = pcalc._find_paran_roots(
            ra_a=10.0,  dec_a=80.0, angle_a='AC',
            ra_b=200.0, dec_b=10.0, angle_b='MC',
            lat_lo=60.0, lat_hi=89.0,
        )
        # No assertion on what roots return — only that the call completes
        assert isinstance(roots, list)

    def test_wrap_discontinuity_not_a_root(self, astro_module, transit_calc):
        """Construct a pair whose LST difference passes through ±180° without
        a real zero crossing. The solver must NOT report a phantom root.

        Two planets both on MC means LST_A_MC - LST_B_MC = RA_A - RA_B (constant
        in lat). If we set RA_A - RA_B = 180°, wrap_signed gives ±180 — a step
        function in latitude that never actually equals zero. Should yield no
        roots."""
        ParanC = astro_module.ParanCalculator
        pcalc = ParanC(transit_calc)
        roots = pcalc._find_paran_roots(
            ra_a=10.0,  dec_a=0.0, angle_a='MC',
            ra_b=190.0, dec_b=0.0, angle_b='MC',
            lat_lo=-60.0, lat_hi=60.0,
        )
        assert roots == [], f"Phantom root from wrap discontinuity: {roots}"

    def test_canonical_ordering_no_duplicates(self, astro_module, transit_calc,
                                              birth_data):
        """parans_near must emit canonical orderings: planet_a comes before
        planet_b in _LINE_PLANETS order; no (B,Y,A,X) duplicates of (A,X,B,Y)."""
        chart = astro_module.NatalChart(
            name="anthony_canon",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        pcalc = astro_module.ParanCalculator(transit_calc)
        rows = pcalc.parans_near(chart, 40.0, max_delta_lat=2.5)

        # _LINE_PLANETS order
        order = {name: i for i, (name, _) in enumerate(astro_module._LINE_PLANETS)}
        for r in rows:
            assert order[r['planet_a']] < order[r['planet_b']], (
                f"Non-canonical ordering: {r['planet_a']} should come before "
                f"{r['planet_b']} in _LINE_PLANETS (got {r})"
            )

    def test_rows_sorted_by_abs_delta_lat(self, astro_module, transit_calc,
                                         birth_data):
        chart = astro_module.NatalChart(
            name="anthony_paran_sort",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        pcalc = astro_module.ParanCalculator(transit_calc)
        rows = pcalc.parans_near(chart, 40.4667, max_delta_lat=2.5)
        deltas = [abs(r['delta_lat']) for r in rows]
        assert deltas == sorted(deltas)

    def test_no_chiron_excludes_chiron(self, astro_module, transit_calc,
                                      birth_data):
        chart = astro_module.NatalChart(
            name="anthony_no_chiron",
            birth_data=birth_data,
            created_at="2026-01-01T00:00:00",
        )
        pcalc = astro_module.ParanCalculator(transit_calc)
        rows = pcalc.parans_near(
            chart, 40.4667,
            max_delta_lat=2.5,
            include_chiron=False,
        )
        for r in rows:
            assert 'Chiron' not in (r['planet_a'], r['planet_b']), (
                f"Chiron row leaked through include_chiron=False: {r}"
            )
