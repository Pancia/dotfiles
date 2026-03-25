"""Tests for house placement and natal chart calculations in astro."""

import pytest


# Sign abbreviation to absolute degree offset
SIGN_OFFSET = {
    'Ari': 0, 'Tau': 30, 'Gem': 60, 'Can': 90, 'Leo': 120, 'Vir': 150,
    'Lib': 180, 'Sco': 210, 'Sag': 240, 'Cap': 270, 'Aqu': 300, 'Pis': 330,
}


# =============================================================================
# Unit tests for _planet_in_natal_house (pure logic, no kerykeion needed)
# =============================================================================

class TestPlanetInNatalHouse:
    """Test the house lookup algorithm with synthetic cusp data."""

    @pytest.fixture
    def calc(self, astro_module, tmp_path):
        storage = astro_module.AstroStorage(base_path=tmp_path)
        return astro_module.TransitCalculator(storage)

    @pytest.fixture
    def equal_cusps(self):
        """Equal house cusps starting at ~28.83° Aquarius (like Anthony's chart)."""
        # House 1 at 328.83° (28.83° Aquarius), each house 30° apart
        start = 328.83
        return {i: (start + (i - 1) * 30) % 360 for i in range(1, 13)}

    def test_planet_in_first_house(self, calc, equal_cusps):
        # 330° is just past house 1 cusp at 328.83°
        assert calc._planet_in_natal_house(330.0, equal_cusps) == '1'

    def test_planet_in_fourth_house(self, calc, equal_cusps):
        # House 4 cusp at (328.83 + 90) % 360 = 58.83° (28.83° Taurus)
        # 60° (0° Gemini) is just past the 4th house cusp
        assert calc._planet_in_natal_house(60.0, equal_cusps) == '4'

    def test_planet_before_next_cusp(self, calc, equal_cusps):
        # House 5 cusp at 88.83° (28.83° Gemini)
        # 85° Gemini is still in house 4
        assert calc._planet_in_natal_house(85.0, equal_cusps) == '4'

    def test_planet_in_last_house(self, calc, equal_cusps):
        # House 12 cusp at (328.83 - 30) % 360 = 298.83° (28.83° Capricorn)
        # 310° (10° Aquarius) should be in house 12
        assert calc._planet_in_natal_house(310.0, equal_cusps) == '12'

    def test_wraparound_house(self, calc, equal_cusps):
        # 340° (10° Pisces) — past house 1 cusp at 328.83°, before house 2 at 358.83°
        assert calc._planet_in_natal_house(340.0, equal_cusps) == '1'

    def test_wraparound_near_zero(self, calc, equal_cusps):
        # House 2 cusp at 358.83° (28.83° Pisces)
        # 5° (5° Aries) should be in house 2
        assert calc._planet_in_natal_house(5.0, equal_cusps) == '2'

    def test_planet_exactly_on_cusp(self, calc, equal_cusps):
        # Exactly on house 1 cusp — should be in house 1
        assert calc._planet_in_natal_house(328.83, equal_cusps) == '1'

    def test_planet_at_zero_degrees(self, calc, equal_cusps):
        # 0° Aries — house 2 cusp is at 358.83°, house 3 at 28.83°
        assert calc._planet_in_natal_house(0.0, equal_cusps) == '2'

    def test_planet_at_359(self, calc, equal_cusps):
        # 359° — just past house 2 cusp at 358.83°
        assert calc._planet_in_natal_house(359.0, equal_cusps) == '2'

    def test_non_equal_cusps(self, calc):
        """Test with Placidus-like unequal house sizes."""
        cusps = {
            1: 10.0, 2: 35.0, 3: 65.0, 4: 100.0,
            5: 135.0, 6: 165.0, 7: 190.0, 8: 215.0,
            9: 245.0, 10: 280.0, 11: 315.0, 12: 345.0,
        }
        assert calc._planet_in_natal_house(20.0, cusps) == '1'
        assert calc._planet_in_natal_house(40.0, cusps) == '2'
        assert calc._planet_in_natal_house(350.0, cusps) == '12'
        assert calc._planet_in_natal_house(5.0, cusps) == '12'  # wraparound


# =============================================================================
# Integration: transit houses use natal cusps, not transit chart houses
# =============================================================================

class TestTransitHousesUseNatalCusps:
    """Regression test: _parse_aspects must use natal cusps for transit houses."""

    def test_transit_houses_match_natal_cusps(self, astro_module, transit_calc,
                                              birth_data, natal_subject, natal_cusps):
        """Every transit house in _parse_aspects output should match
        _planet_in_natal_house against natal cusps."""
        from kerykeion import AstrologicalSubject, SynastryAspects

        # Create transit subject for a fixed time (2026-03-24 20:44 MDT = 02:44 UTC Mar 25)
        transit = transit_calc._make_subject(
            "Transit", 2026, 3, 24, 20, 44, birth_data
        )

        aspects = SynastryAspects(transit, natal_subject)
        events = transit_calc._parse_aspects(
            aspects.relevant_aspects, transit, natal_subject, natal_cusps
        )

        assert len(events) > 0, "Should find at least some transit aspects"

        for event in events:
            # Get the transit planet object and compute expected house
            t_planet = transit_calc._get_planet_obj(transit, event.transit_planet)
            if t_planet and event.transit_house:
                expected = transit_calc._planet_in_natal_house(t_planet.abs_pos, natal_cusps)
                assert event.transit_house == expected, (
                    f"{event.transit_planet} in {event.transit_sign}: "
                    f"got house {event.transit_house}, expected {expected} from natal cusps"
                )

    def test_transit_house_differs_from_transit_chart_house(self, astro_module, transit_calc,
                                                             birth_data, natal_subject, natal_cusps):
        """Verify that at least some transit houses differ from what the transit
        chart's own house system would give — proving we use natal cusps."""
        from kerykeion import AstrologicalSubject, SynastryAspects

        transit = transit_calc._make_subject(
            "Transit", 2026, 3, 24, 20, 44, birth_data
        )

        aspects = SynastryAspects(transit, natal_subject)
        events = transit_calc._parse_aspects(
            aspects.relevant_aspects, transit, natal_subject, natal_cusps
        )

        house_map = {
            'First_House': '1', 'Second_House': '2', 'Third_House': '3',
            'Fourth_House': '4', 'Fifth_House': '5', 'Sixth_House': '6',
            'Seventh_House': '7', 'Eighth_House': '8', 'Ninth_House': '9',
            'Tenth_House': '10', 'Eleventh_House': '11', 'Twelfth_House': '12',
        }

        differs = False
        for event in events:
            t_planet = transit_calc._get_planet_obj(transit, event.transit_planet)
            if t_planet:
                transit_chart_house = house_map.get(getattr(t_planet, 'house', ''), '')
                if transit_chart_house and event.transit_house != transit_chart_house:
                    differs = True
                    break

        assert differs, (
            "Expected at least one transit planet house to differ between "
            "natal cusps and transit chart houses"
        )


# =============================================================================
# Snapshot test against astro-seek reference data
# =============================================================================

class TestAstroSeekReference:
    """Verify our calculations match astro-seek.com for 2026-03-24 20:44 MDT."""

    # Reference data from astro-seek.com
    # (transit_planet, transit_sign, aspect, natal_planet, natal_sign, orb)
    ASTRO_SEEK_TRANSITS = [
        ("Jupiter", "Can", "trine", "Mars", "Sco", 0.93),
        ("Mars", "Pis", "sextile", "Neptune", "Cap", 0.77),
        ("Mars", "Pis", "sextile", "Uranus", "Cap", 0.73),
        ("Venus", "Ari", "sextile", "Saturn", "Aqu", 0.53),
        ("Mercury", "Pis", "sextile", "Moon", "Cap", 0.97),
        ("Moon", "Gem", "trine", "Jupiter", "Lib", 0.22),
    ]

    ORB_TOLERANCE = 0.15  # degrees — allows for ephemeris/time differences

    def test_signs_aspects_and_orbs_match(self, astro_module, transit_calc,
                                           birth_data, natal_subject, natal_cusps):
        """Major aspects should match astro-seek's signs, aspect types, and orbs."""
        from kerykeion import SynastryAspects

        transit = transit_calc._make_subject(
            "Transit", 2026, 3, 24, 20, 44, birth_data
        )

        aspects = SynastryAspects(transit, natal_subject)
        events = transit_calc._parse_aspects(
            aspects.relevant_aspects, transit, natal_subject, natal_cusps
        )

        # Build lookup by (transit_planet, aspect, natal_planet)
        our_aspects = {}
        for e in events:
            key = (e.transit_planet, e.transit_sign, e.aspect,
                   e.natal_planet, e.natal_sign)
            our_aspects[key] = e

        for t_planet, t_sign, aspect, n_planet, n_sign, expected_orb in self.ASTRO_SEEK_TRANSITS:
            key = (t_planet, t_sign, aspect, n_planet, n_sign)
            assert key in our_aspects, (
                f"Missing aspect: transit {t_planet} in {t_sign} "
                f"{aspect} natal {n_planet} in {n_sign}"
            )
            actual_orb = abs(our_aspects[key].orb)
            assert abs(actual_orb - expected_orb) < self.ORB_TOLERANCE, (
                f"{t_planet} {aspect} {n_planet}: "
                f"orb {actual_orb:.2f}° vs astro-seek {expected_orb:.2f}° "
                f"(diff {abs(actual_orb - expected_orb):.2f}°, tolerance {self.ORB_TOLERANCE}°)"
            )



class TestAstroSeekReference2000:
    """Verify calculations match astro-seek.com for 2000-08-13 12:37 MDT."""

    ORB_TOLERANCE = 0.15
    HOUSE_TOLERANCE = 0.10  # for degree comparison when verifying houses

    # Transit planet positions with natal houses from astro-seek
    # (planet_name, sign, degree_in_sign, natal_house)
    TRANSIT_POSITIONS = [
        ("Sun", "Leo", 21.28, "6"),
        ("Moon", "Aqu", 5.38, "12"),
        ("Mercury", "Leo", 12.53, "6"),
        ("Venus", "Vir", 8.65, "7"),
        ("Mars", "Leo", 8.20, "6"),
        ("Jupiter", "Gem", 7.85, "4"),
        ("Saturn", "Gem", 0.18, "4"),
        ("Uranus", "Aqu", 18.73, "12"),
        ("Neptune", "Aqu", 4.72, "12"),
        ("Pluto", "Sag", 10.15, "10"),
    ]

    # (transit_planet, transit_sign, aspect, natal_planet, natal_sign, orb)
    TRANSIT_ASPECTS = [
        ("Neptune", "Aqu", "trine", "Venus", "Lib", 1.37),
        ("Jupiter", "Gem", "trine", "Venus", "Lib", 1.73),
        ("Venus", "Vir", "trine", "Moon", "Cap", 1.65),
        ("Moon", "Aqu", "trine", "Venus", "Lib", 0.70),
        ("Sun", "Leo", "square", "Mercury", "Sco", 0.27),
    ]

    @pytest.fixture(scope="class")
    def transit_2000(self, transit_calc, birth_data):
        return transit_calc._make_subject(
            "Transit", 2000, 8, 13, 12, 37, birth_data
        )

    def test_transit_planet_houses(self, transit_calc, transit_2000, natal_cusps):
        """Transit planet houses should match astro-seek's natal house placements."""
        for planet_name, expected_sign, expected_deg, expected_house in self.TRANSIT_POSITIONS:
            obj = transit_calc._get_planet_obj(transit_2000, planet_name)
            assert obj is not None, f"Could not find transit {planet_name}"

            assert obj.sign == expected_sign, (
                f"Transit {planet_name}: sign {obj.sign} != expected {expected_sign}"
            )

            degree_in_sign = obj.abs_pos % 30
            assert abs(degree_in_sign - expected_deg) < self.HOUSE_TOLERANCE, (
                f"Transit {planet_name}: degree {degree_in_sign:.2f}° != expected {expected_deg:.2f}°"
            )

            house = transit_calc._planet_in_natal_house(obj.abs_pos, natal_cusps)
            assert house == expected_house, (
                f"Transit {planet_name} at {expected_sign} {expected_deg:.2f}°: "
                f"house {house} != expected {expected_house}"
            )

    def test_transit_aspects_and_orbs(self, transit_calc, transit_2000,
                                       natal_subject, natal_cusps):
        """Transit aspects should match astro-seek's reference data."""
        from kerykeion import SynastryAspects

        aspects = SynastryAspects(transit_2000, natal_subject)
        events = transit_calc._parse_aspects(
            aspects.relevant_aspects, transit_2000, natal_subject, natal_cusps
        )

        our_aspects = {}
        for e in events:
            key = (e.transit_planet, e.transit_sign, e.aspect,
                   e.natal_planet, e.natal_sign)
            our_aspects[key] = e

        for t_planet, t_sign, aspect, n_planet, n_sign, expected_orb in self.TRANSIT_ASPECTS:
            key = (t_planet, t_sign, aspect, n_planet, n_sign)
            assert key in our_aspects, (
                f"Missing aspect: transit {t_planet} in {t_sign} "
                f"{aspect} natal {n_planet} in {n_sign}"
            )
            actual_orb = abs(our_aspects[key].orb)
            assert abs(actual_orb - expected_orb) < self.ORB_TOLERANCE, (
                f"{t_planet} {aspect} {n_planet}: "
                f"orb {actual_orb:.2f}° vs astro-seek {expected_orb:.2f}° "
                f"(diff {abs(actual_orb - expected_orb):.2f}°, tolerance {self.ORB_TOLERANCE}°)"
            )


# =============================================================================
# Natal chart verification against astro-seek
# =============================================================================

class TestNatalChart:
    """Verify natal planet positions, houses, and aspects match astro-seek.com."""

    POSITION_TOLERANCE = 0.05  # degrees

    # Reference: astro-seek.com natal chart for 1993-10-20 16:14 MDT, Provo UT
    # (planet_name, sign, degree_in_sign, house)
    NATAL_PLANETS = [
        ("Sun", "Lib", 27.53, "8"),
        ("Moon", "Cap", 10.32, "11"),
        ("Mercury", "Sco", 21.02, "9"),
        ("Venus", "Lib", 6.10, "8"),
        ("Mars", "Sco", 16.33, "9"),
        ("Jupiter", "Lib", 25.58, "8"),
        ("Saturn", "Aqu", 23.67, "12"),
        ("Uranus", "Cap", 18.45, "11"),
        ("Neptune", "Cap", 18.48, "11"),
        ("Pluto", "Sco", 24.33, "9"),
    ]

    # Equal house system: all cusps at 28°48' (28.80°) in sequential signs
    # (house_number, sign, degree_in_sign)
    NATAL_CUSPS = [
        (1, "Aqu", 28.80),
        (2, "Pis", 28.80),
        (3, "Ari", 28.80),
        (4, "Tau", 28.80),
        (5, "Gem", 28.80),
        (6, "Can", 28.80),
        (7, "Leo", 28.80),
        (8, "Vir", 28.80),
        (9, "Lib", 28.80),
        (10, "Sco", 28.80),
        (11, "Sag", 28.80),
        (12, "Cap", 28.80),
    ]

    # (planet1, planet2, aspect, orb)
    NATAL_ASPECTS = [
        ("Sun", "Jupiter", "conjunction", 1.93),
        ("Mercury", "Mars", "conjunction", 4.67),
        ("Mercury", "Pluto", "conjunction", 3.32),
        ("Jupiter", "Saturn", "trine", 1.92),
        ("Saturn", "Pluto", "square", 0.65),
        ("Uranus", "Neptune", "conjunction", 0.03),
    ]

    def test_natal_planet_positions(self, transit_calc, natal_subject, natal_cusps):
        """Natal planet signs, degrees, and houses should match astro-seek."""
        for planet_name, expected_sign, expected_deg, expected_house in self.NATAL_PLANETS:
            obj = transit_calc._get_planet_obj(natal_subject, planet_name)
            assert obj is not None, f"Could not find natal {planet_name}"

            assert obj.sign == expected_sign, (
                f"{planet_name}: sign {obj.sign} != expected {expected_sign}"
            )

            degree_in_sign = obj.abs_pos % 30
            assert abs(degree_in_sign - expected_deg) < self.POSITION_TOLERANCE, (
                f"{planet_name}: degree {degree_in_sign:.2f}° != expected {expected_deg:.2f}°"
            )

            house = transit_calc._planet_in_natal_house(obj.abs_pos, natal_cusps)
            assert house == expected_house, (
                f"{planet_name}: house {house} != expected {expected_house}"
            )

    def test_natal_house_cusps(self, natal_cusps):
        """ASC and MC cusp positions should match astro-seek."""
        for house_num, expected_sign, expected_deg in self.NATAL_CUSPS:
            cusp_abs = natal_cusps[house_num]
            sign_idx = int(cusp_abs / 30) % 12
            signs = ['Ari', 'Tau', 'Gem', 'Can', 'Leo', 'Vir',
                     'Lib', 'Sco', 'Sag', 'Cap', 'Aqu', 'Pis']
            actual_sign = signs[sign_idx]
            actual_deg = cusp_abs % 30

            assert actual_sign == expected_sign, (
                f"House {house_num}: sign {actual_sign} != expected {expected_sign}"
            )
            assert abs(actual_deg - expected_deg) < self.POSITION_TOLERANCE, (
                f"House {house_num}: degree {actual_deg:.2f}° != expected {expected_deg:.2f}°"
            )

    def test_natal_aspects(self, transit_calc, natal_subject):
        """Key natal aspects should match astro-seek."""
        from kerykeion import NatalAspects

        natal_aspects = NatalAspects(natal_subject)

        # Build lookup by planet pair
        our_aspects = {}
        for asp in natal_aspects.relevant_aspects:
            key = (asp['p1_name'], asp['p2_name'])
            our_aspects[key] = asp

        for p1, p2, expected_aspect, expected_orb in self.NATAL_ASPECTS:
            key = (p1, p2)
            assert key in our_aspects, (
                f"Missing natal aspect: {p1} {expected_aspect} {p2}"
            )
            asp = our_aspects[key]
            assert asp['aspect'] == expected_aspect, (
                f"{p1}-{p2}: aspect {asp['aspect']} != expected {expected_aspect}"
            )
            assert abs(abs(asp['orbit']) - expected_orb) < self.POSITION_TOLERANCE, (
                f"{p1} {expected_aspect} {p2}: "
                f"orb {abs(asp['orbit']):.2f}° != expected {expected_orb:.2f}°"
            )
