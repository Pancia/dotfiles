"""Tests for Zodiacal Releasing (astro zr / astro-zr-helper).

Reference data captured from astro-seek's ZR calculator for Anthony's chart
(1993-10-20 16:14 MDT, Provo, US — Universal Time 22:14 UTC).

Astro-seek and our canonical engine both use Egyptian years:
    1 year  = 360 days
    1 month = 30 days

Period start dates can differ by up to ±1 day from astro-seek because
astro-seek prints dates in local time while the helper prints the UTC
date of the same moment.

These tests pin down the three Valens-canon fixes in astro-zr-helper:
    1. L1 uses 360-day schematic years (not 365.25).
    2. Sign minor-years follow the canonical table — Cap=27, Aqu=30 —
       even though both are Saturn-ruled.
    3. The L2+ sub-period loop continues through the Loosing of the Bond
       cycle until the parent's duration is exhausted (not stopped at
       12 signs).
"""
from datetime import date

import pytest


# ---------------------------------------------------------------------------
# Reference data (Fortune lot, astro-seek)
# ---------------------------------------------------------------------------

# L1 Fortune periods within default 100-year lifespan, in zodiac order.
L1_FORTUNE = [
    ("Taurus",      "1993-10-20"),
    ("Gemini",      "2001-09-08"),
    ("Cancer",      "2021-05-26"),
    ("Leo",         "2046-01-15"),
    ("Virgo",       "2064-10-07"),
    ("Libra",       "2084-06-24"),
    ("Scorpio",     "2092-05-13"),
]

# L2 sub-periods within Tau L1 (8 minor years = 2880 days). No LB reached.
L2_IN_TAURUS_L1 = [
    ("Taurus",      "1993-10-20"),
    ("Gemini",      "1994-06-17"),
    ("Cancer",      "1996-02-07"),
    ("Leo",         "1998-02-26"),
    ("Virgo",       "1999-09-19"),
    ("Libra",       "2001-05-11"),  # truncated by parent end (2001-09-08)
]

# L2 sub-periods within Gem L1 (20 minor years = 7200 days).
# Includes Cap=27/Aqu=30 boundary AND the LB at sign #13.
L2_IN_GEMINI_L1 = [
    ("Gemini",      "2001-09-08"),
    ("Cancer",      "2003-05-01"),
    ("Leo",         "2005-05-20"),
    ("Virgo",       "2006-12-11"),
    ("Libra",       "2008-08-02"),
    ("Scorpio",     "2009-03-30"),
    ("Sagittarius", "2010-06-23"),
    ("Capricorn",   "2011-06-18"),  # 27 × 30 = 810 days
    ("Aquarius",    "2013-09-05"),  # 30 × 30 = 900 days  ← Valens quirk
    ("Pisces",      "2016-02-22"),
    ("Aries",       "2017-02-16"),
    ("Taurus",      "2018-05-12"),
    ("Sagittarius", "2019-01-07"),  # LB — opposite of cycle start (Gem)
    ("Capricorn",   "2020-01-02"),  # truncated
]

# L2 sub-periods within Can L1 (25 minor years). LB lands on Cap.
L2_IN_CANCER_L1 = [
    ("Cancer",      "2021-05-26"),
    ("Leo",         "2023-06-15"),
    ("Virgo",       "2025-01-05"),
    ("Libra",       "2026-08-28"),
    ("Scorpio",     "2027-04-25"),
    ("Sagittarius", "2028-07-18"),
    ("Capricorn",   "2029-07-13"),
    ("Aquarius",    "2031-10-01"),
    ("Pisces",      "2034-03-19"),
    ("Aries",       "2035-03-14"),
    ("Taurus",      "2036-06-06"),
    ("Gemini",      "2037-02-01"),
    ("Capricorn",   "2038-09-24"),  # LB — opposite of Can
    ("Aquarius",    "2040-12-12"),
    ("Pisces",      "2043-05-31"),
    ("Aries",       "2044-05-25"),
    ("Taurus",      "2045-08-18"),  # truncated
]

# L2 sub-periods within Leo L1 (19 minor years). LB lands on Aqu.
L2_IN_LEO_L1 = [
    ("Leo",         "2046-01-15"),
    ("Virgo",       "2047-08-08"),
    ("Libra",       "2049-03-30"),
    ("Scorpio",     "2049-11-25"),
    ("Sagittarius", "2051-02-18"),
    ("Capricorn",   "2052-02-13"),
    ("Aquarius",    "2054-05-03"),
    ("Pisces",      "2056-10-19"),
    ("Aries",       "2057-10-14"),
    ("Taurus",      "2059-01-07"),
    ("Gemini",      "2059-09-04"),
    ("Cancer",      "2061-04-26"),
    ("Aquarius",    "2063-05-16"),  # LB — opposite of Leo
]


# ---------------------------------------------------------------------------
# Fixtures (module-scoped — each helper invocation spawns a uv subprocess)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def natal_chart(astro_module, birth_data):
    return astro_module.NatalChart(
        name=birth_data.full_name,
        birth_data=birth_data,
        created_at="1993-10-20T16:14:00",
    )


@pytest.fixture(scope="module")
def zr_calc(astro_module, transit_calc):
    return astro_module.ZRCalculator(transit_calc.storage)


@pytest.fixture(scope="module")
def l1_fortune(zr_calc, natal_chart):
    return zr_calc.timeline(natal_chart, "fortune", level=1)


@pytest.fixture(scope="module")
def l2_fortune(zr_calc, natal_chart):
    return zr_calc.timeline(natal_chart, "fortune", level=2)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

DATE_TOL_DAYS = 1


def _d(iso):
    return date.fromisoformat(iso)


def _dates_close(a_iso, b_iso, tol=DATE_TOL_DAYS):
    return abs((_d(a_iso) - _d(b_iso)).days) <= tol


def _find_at(periods, sign, start_iso):
    """Find the period with matching sign whose start is near start_iso."""
    for p in periods:
        if p.sign == sign and _dates_close(p.start, start_iso):
            return p
    raise AssertionError(f"No {sign} period near {start_iso}")


def _slice_starting_at(periods, start_iso, count):
    """Return `count` consecutive periods beginning near start_iso."""
    target = _d(start_iso)
    for i, p in enumerate(periods):
        if abs((_d(p.start) - target).days) <= DATE_TOL_DAYS:
            return periods[i:i + count]
    raise AssertionError(f"No period starts near {start_iso}")


def _assert_matches(actual_periods, expected):
    assert len(actual_periods) == len(expected), (
        f"length mismatch: got {len(actual_periods)}, expected {len(expected)}"
    )
    for got, (sign, start) in zip(actual_periods, expected):
        assert got.sign == sign, f"expected {sign}, got {got.sign} at {got.start}"
        assert _dates_close(got.start, start), (
            f"{sign}: expected start {start}, got {got.start}"
        )


# ---------------------------------------------------------------------------
# Lot alias resolution — pure unit test, no helper subprocess
# ---------------------------------------------------------------------------

class TestResolveLotAliases:
    """ZRCalculator._resolve_lot maps short names to stellium's canonical lots.

    Pure dict-lookup test — runs in microseconds, doesn't touch the helper.
    """

    def test_fortune_alias(self, zr_calc):
        assert zr_calc._resolve_lot("fortune") == "Part of Fortune"

    def test_spirit_alias(self, zr_calc):
        assert zr_calc._resolve_lot("spirit") == "Part of Spirit"

    def test_eros_alias(self, zr_calc):
        assert zr_calc._resolve_lot("eros") == "Part of Eros"

    def test_necessity_alias(self, zr_calc):
        assert zr_calc._resolve_lot("necessity") == "Part of Necessity"

    def test_courage_alias(self, zr_calc):
        assert zr_calc._resolve_lot("courage") == "Part of Courage"

    def test_victory_alias(self, zr_calc):
        assert zr_calc._resolve_lot("victory") == "Part of Victory"

    def test_nemesis_alias(self, zr_calc):
        assert zr_calc._resolve_lot("nemesis") == "Part of Nemesis"

    def test_alias_case_insensitive(self, zr_calc):
        assert zr_calc._resolve_lot("FORTUNE") == "Part of Fortune"
        assert zr_calc._resolve_lot("Spirit") == "Part of Spirit"

    def test_canonical_name_passes_through(self, zr_calc):
        # "Part of Fortune".lower() = "part of fortune", not in alias map,
        # so the original (un-lowered) string is returned unchanged.
        assert zr_calc._resolve_lot("Part of Fortune") == "Part of Fortune"

    def test_unknown_lot_passes_through(self, zr_calc):
        assert zr_calc._resolve_lot("custom_lot") == "custom_lot"


# ---------------------------------------------------------------------------
# L1 timeline — Fortune
# ---------------------------------------------------------------------------

class TestL1FortuneTimeline:
    """The L1 schedule pins down the 360-day schematic year fix."""

    def test_l1_starts_at_taurus(self, l1_fortune):
        assert l1_fortune[0].sign == "Taurus"
        assert _dates_close(l1_fortune[0].start, "1993-10-20")

    def test_l1_full_lifespan_sequence(self, l1_fortune):
        # default lifespan=100 captures Tau through (at least) Sco.
        assert len(l1_fortune) >= len(L1_FORTUNE)
        _assert_matches(l1_fortune[:len(L1_FORTUNE)], L1_FORTUNE)


# ---------------------------------------------------------------------------
# L2 timeline — Fortune
# ---------------------------------------------------------------------------

class TestL2FortuneSubPeriods:
    """L2 cycles pin down LB-cycle continuation and the Cap=27/Aqu=30 quirk."""

    def test_l2_within_taurus_l1(self, l2_fortune):
        block = _slice_starting_at(l2_fortune, "1993-10-20",
                                   len(L2_IN_TAURUS_L1))
        _assert_matches(block, L2_IN_TAURUS_L1)

    def test_l2_within_gemini_l1(self, l2_fortune):
        block = _slice_starting_at(l2_fortune, "2001-09-08",
                                   len(L2_IN_GEMINI_L1))
        _assert_matches(block, L2_IN_GEMINI_L1)

    def test_l2_within_cancer_l1(self, l2_fortune):
        block = _slice_starting_at(l2_fortune, "2021-05-26",
                                   len(L2_IN_CANCER_L1))
        _assert_matches(block, L2_IN_CANCER_L1)

    def test_l2_within_leo_l1(self, l2_fortune):
        block = _slice_starting_at(l2_fortune, "2046-01-15",
                                   len(L2_IN_LEO_L1))
        _assert_matches(block, L2_IN_LEO_L1)


# ---------------------------------------------------------------------------
# Specific Valens-canon assertions
# ---------------------------------------------------------------------------

class TestCanonicalMinorYears:
    """Direct duration checks on the Cap=27/Aqu=30 distinction.

    Without this fix, stellium derives Aqu's minor years from its ruler
    Saturn, giving Aqu=27 instead of 30 — visible as a 90-day shift on
    every Aqu period across every level.
    """

    def test_capricorn_l2_lasts_810_days(self, l2_fortune):
        # Cap L2 inside Gem L1 — 27 × 30 days.
        cap = _find_at(l2_fortune, "Capricorn", "2011-06-18")
        assert (_d(cap.end) - _d(cap.start)).days == 810

    def test_aquarius_l2_lasts_900_days(self, l2_fortune):
        # Aqu L2 inside Gem L1 — 30 × 30 days. The headline fix.
        aqu = _find_at(l2_fortune, "Aquarius", "2013-09-05")
        assert (_d(aqu.end) - _d(aqu.start)).days == 900


class TestLoosingOfTheBond:
    """The is_lb flag fires on the 13th sign of each L2 cycle."""

    def test_lb_flag_set_at_gemini_cycle_13(self, l2_fortune):
        # 13th sign in Gem L1's L2 cycle is Sag (opposite of Gem).
        lb = _find_at(l2_fortune, "Sagittarius", "2019-01-07")
        assert lb.is_lb is True

    def test_lb_flag_unset_on_pre_lb_sagittarius(self, l2_fortune):
        # Earlier Sag in Gem cycle (sign #7) must NOT be flagged LB.
        pre = _find_at(l2_fortune, "Sagittarius", "2010-06-23")
        assert pre.is_lb is False

    def test_lb_lands_on_capricorn_in_cancer_cycle(self, l2_fortune):
        # Can's opposite is Cap.
        lb = _find_at(l2_fortune, "Capricorn", "2038-09-24")
        assert lb.is_lb is True

    def test_lb_lands_on_aquarius_in_leo_cycle(self, l2_fortune):
        # Leo's opposite is Aqu.
        lb = _find_at(l2_fortune, "Aquarius", "2063-05-16")
        assert lb.is_lb is True


class TestLBCycleContinuation:
    """L2+ must continue through the LB jump until the parent ends.

    Stellium 0.18.1 stops L2 at exactly 12 signs; the canonical engine
    keeps going. Gem L1 has 14 L2 entries (12 + LB + 1 truncated tail).
    """

    def test_gemini_l1_has_post_lb_l2_entries(self, l2_fortune):
        block = _slice_starting_at(l2_fortune, "2001-09-08",
                                   len(L2_IN_GEMINI_L1))
        post_lb = [p for p in block if p.is_lb] + block[block.index(
            _find_at(block, "Sagittarius", "2019-01-07")
        ) + 1:]
        assert len(post_lb) >= 2  # the LB sign itself + at least one after

    def test_cancer_l1_continues_past_lb(self, l2_fortune):
        # Can L1 has 17 L2 entries — 12 pre-LB, the LB, 4 post-LB tail.
        block = _slice_starting_at(l2_fortune, "2021-05-26",
                                   len(L2_IN_CANCER_L1))
        assert len(block) == 17


# ---------------------------------------------------------------------------
# Reference data — Spirit lot
# ---------------------------------------------------------------------------

# Spirit's first two L1 periods. Sag is 12 minor years (4320 days), so
# Cap starts 12 × 360 days after birth = 2005-08-18, matching astro-seek.
# Different starting sign than Fortune (Tau) — exercises lot alias resolution.
L1_SPIRIT_FIRST_TWO = [
    ("Sagittarius", "1993-10-20"),
    ("Capricorn",   "2005-08-18"),
]

# L3 sub-periods at the head of Cap L1 / Cap L2.
# Locks down L3 multiplier = 2.5 days per minor year (canonical 12th-part).
L3_HEAD_OF_CAP_L2_SPIRIT = [
    ("Capricorn", "2005-08-18"),  # 27 × 2.5 = 67.5 days
    ("Aquarius",  "2005-10-25"),  # 30 × 2.5 = 75   days
]

# L4 sub-periods inside the FIRST L3 (Cap L3) of Cap L2.
# Locks down L4 multiplier = 5/24 days per minor year and L4 LB cycle
# continuation. 19 entries: 12 + LB Cancer (#13) + 6 truncated tail.
L4_IN_CAP_L3_SPIRIT = [
    ("Capricorn",   "2005-08-18"),
    ("Aquarius",    "2005-08-24"),
    ("Pisces",      "2005-08-30"),
    ("Aries",       "2005-09-02"),
    ("Taurus",      "2005-09-05"),
    ("Gemini",      "2005-09-06"),
    ("Cancer",      "2005-09-11"),
    ("Leo",         "2005-09-16"),
    ("Virgo",       "2005-09-20"),
    ("Libra",       "2005-09-24"),
    ("Scorpio",     "2005-09-26"),
    ("Sagittarius", "2005-09-29"),
    ("Cancer",      "2005-10-01"),  # LB — opposite of Cap
    ("Leo",         "2005-10-06"),
    ("Virgo",       "2005-10-10"),
    ("Libra",       "2005-10-14"),
    ("Scorpio",     "2005-10-16"),
    ("Sagittarius", "2005-10-19"),
    ("Capricorn",   "2005-10-22"),  # truncated by parent end
]


# ---------------------------------------------------------------------------
# Spirit fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def l1_spirit(zr_calc, natal_chart):
    return zr_calc.timeline(natal_chart, "spirit", level=1)


@pytest.fixture(scope="module")
def l3_spirit(zr_calc, natal_chart):
    return zr_calc.timeline(natal_chart, "spirit", level=3)


@pytest.fixture(scope="module")
def l4_spirit(zr_calc, natal_chart):
    return zr_calc.timeline(natal_chart, "spirit", level=4)


@pytest.fixture(scope="module")
def snapshot_age_12_spirit(zr_calc, natal_chart):
    return zr_calc.snapshot_at_age(natal_chart, "spirit", age=12.0)


# ---------------------------------------------------------------------------
# Spirit lot
# ---------------------------------------------------------------------------

class TestL1SpiritTimeline:
    """Spirit's first L1 sign differs from Fortune's — exercises lot alias."""

    def test_l1_spirit_first_two_periods(self, l1_spirit):
        _assert_matches(l1_spirit[:len(L1_SPIRIT_FIRST_TWO)],
                        L1_SPIRIT_FIRST_TWO)


class TestL3CanonicalMultiplier:
    """L3 = 2.5 days/year (the 4th Valens fix). Without it, all L3 dates drift."""

    def test_l3_head_of_cap_l2_spirit(self, l3_spirit):
        block = _slice_starting_at(l3_spirit, "2005-08-18",
                                   len(L3_HEAD_OF_CAP_L2_SPIRIT))
        _assert_matches(block, L3_HEAD_OF_CAP_L2_SPIRIT)

    def test_capricorn_l3_lasts_67_or_68_days(self, l3_spirit):
        # 27 × 2.5 = 67.5 days; date-truncation rounds to 67 or 68.
        cap = _find_at(l3_spirit, "Capricorn", "2005-08-18")
        duration = (_d(cap.end) - _d(cap.start)).days
        assert duration in (67, 68), f"Cap L3 was {duration} days, expected 67-68"

    def test_aquarius_l3_lasts_about_75_days(self, l3_spirit):
        # 30 × 2.5 = 75 days; allow ±1 for date truncation.
        aqu = _find_at(l3_spirit, "Aquarius", "2005-10-25")
        duration = (_d(aqu.end) - _d(aqu.start)).days
        assert 74 <= duration <= 76, f"Aqu L3 was {duration} days, expected ~75"


class TestL4CanonicalMultiplier:
    """L4 = 5/24 days/year (≈ 5 hours/year). Without it, all L4 dates drift."""

    def test_l4_within_cap_l3_full_sequence(self, l4_spirit):
        block = _slice_starting_at(l4_spirit, "2005-08-18",
                                   len(L4_IN_CAP_L3_SPIRIT))
        _assert_matches(block, L4_IN_CAP_L3_SPIRIT)

    def test_capricorn_l4_lasts_5_or_6_days(self, l4_spirit):
        # 27 × 5/24 = 5.625 days; date-truncation rounds to 5 or 6.
        cap = _find_at(l4_spirit, "Capricorn", "2005-08-18")
        duration = (_d(cap.end) - _d(cap.start)).days
        assert duration in (5, 6), f"Cap L4 was {duration} days, expected 5-6"

    def test_taurus_l4_lasts_1_or_2_days(self, l4_spirit):
        # 8 × 5/24 = 1.667 days; date-truncation rounds to 1 or 2.
        tau = _find_at(l4_spirit, "Taurus", "2005-09-05")
        duration = (_d(tau.end) - _d(tau.start)).days
        assert duration in (1, 2), f"Tau L4 was {duration} days, expected 1-2"


class TestL4LoosingOfBond:
    """LB at sign #13 also fires at L4 — proves the fix applies at every level."""

    def test_l4_lb_at_cancer(self, l4_spirit):
        lb = _find_at(l4_spirit, "Cancer", "2005-10-01")
        assert lb.is_lb is True

    def test_l4_pre_lb_cancer_not_flagged(self, l4_spirit):
        pre = _find_at(l4_spirit, "Cancer", "2005-09-11")
        assert pre.is_lb is False


class TestSpiritSnapshot:
    """End-to-end snapshot pinning all 4 levels at one moment.

    Exercises the snapshot codepath (separate from the timeline path) and
    proves the lot-alias resolution feeds through unchanged.
    """

    def test_snapshot_has_all_four_levels(self, snapshot_age_12_spirit):
        snap = snapshot_age_12_spirit
        assert snap.l1 is not None
        assert snap.l2 is not None
        assert snap.l3 is not None
        assert snap.l4 is not None

    def test_snapshot_l1_capricorn(self, snapshot_age_12_spirit):
        # Cap L1 spans 2005-08-18 → 2032-04-04 (27 × 360 days).
        # Any age in [11.8, 38.5] yrs is in Cap L1.
        assert snapshot_age_12_spirit.l1.sign == "Capricorn"

    def test_snapshot_l2_capricorn(self, snapshot_age_12_spirit):
        # Cap L2 spans 2005-08-18 → 2007-11-04 (27 × 30 days).
        # Age 12.0 (≈ 2005-10-20) is firmly inside.
        assert snapshot_age_12_spirit.l2.sign == "Capricorn"

    def test_snapshot_l3_capricorn(self, snapshot_age_12_spirit):
        # Cap L3 spans 2005-08-18 → 2005-10-25 (~67.5 days).
        # Age 12.0 (≈ 2005-10-20) is in the last week of Cap L3.
        assert snapshot_age_12_spirit.l3.sign == "Capricorn"


# ---------------------------------------------------------------------------
# Period continuity invariant
# ---------------------------------------------------------------------------

class TestPeriodContinuity:
    """No gaps or overlaps between consecutive periods.

    For every adjacent pair, period[i].end must equal period[i+1].start.
    Catches bugs at LB transitions and parent-truncation boundaries that
    the start-only tests would miss.
    """

    @staticmethod
    def _check_continuous(periods):
        for i in range(len(periods) - 1):
            assert periods[i].end == periods[i + 1].start, (
                f"discontinuity at index {i}: "
                f"{periods[i].sign} ends {periods[i].end}, "
                f"{periods[i + 1].sign} starts {periods[i + 1].start}"
            )

    def test_l1_fortune_continuous(self, l1_fortune):
        self._check_continuous(l1_fortune)

    def test_l2_fortune_continuous(self, l2_fortune):
        self._check_continuous(l2_fortune)

    def test_l1_spirit_continuous(self, l1_spirit):
        self._check_continuous(l1_spirit)

    def test_l3_spirit_continuous(self, l3_spirit):
        self._check_continuous(l3_spirit)

    def test_l4_spirit_continuous(self, l4_spirit):
        self._check_continuous(l4_spirit)
