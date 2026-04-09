"""Tests for exocortex-id generator."""

import importlib.machinery
import importlib.util
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Load the script as a module (no .py extension)
_path = str(Path(__file__).resolve().parents[3] / "bin" / "exocortex-id")
_loader = importlib.machinery.SourceFileLoader("exocortex_id", _path)
_spec = importlib.util.spec_from_loader("exocortex_id", _loader)
assert _spec is not None
exo = importlib.util.module_from_spec(_spec)
_loader.exec_module(exo)


# =============================================================================
# to_base36 / from_base36
# =============================================================================

class TestToBase36:
    def test_zero(self):
        assert exo.to_base36(0) == "0"

    def test_single_digit(self):
        assert exo.to_base36(9) == "9"

    def test_letter_range(self):
        assert exo.to_base36(10) == "a"
        assert exo.to_base36(35) == "z"

    def test_multi_digit(self):
        assert exo.to_base36(36) == "10"
        assert exo.to_base36(100) == "2s"

    def test_negative_raises(self):
        with pytest.raises(ValueError):
            exo.to_base36(-1)

    @pytest.mark.parametrize("n", [0, 1, 10, 35, 36, 100, 1000, 35999])
    def test_roundtrip(self, n):
        """base36 string should parse back to the original integer."""
        assert exo.from_base36(exo.to_base36(n)) == n


# =============================================================================
# generate_id — fixed timestamps
# =============================================================================

class TestGenerateId:
    """Test ID generation with known timestamps."""

    @pytest.fixture
    def t1(self):
        """2026-04-08 14:30:45.200000 UTC"""
        return datetime(2026, 4, 8, 14, 30, 45, 200_000, tzinfo=timezone.utc)

    @pytest.fixture
    def t2(self):
        """2023-11-13 20:01:00.000000 UTC (the commented-out test date in the JS)"""
        return datetime(2023, 11, 13, 20, 1, 0, 0, tzinfo=timezone.utc)

    @pytest.fixture
    def midnight_jan1(self):
        """2030-01-01 00:00:00 UTC — edge case: start of year, midnight."""
        return datetime(2030, 1, 1, 0, 0, 0, 0, tzinfo=timezone.utc)

    # -- Default mode --

    def test_default_format(self, t1):
        result = exo.generate_id(now=t1)
        # Should be YY(2) + M(1) + D(1) + "-" + H(1) + TTT(3)
        date, time = result.split("-")
        assert len(date) == 4
        assert len(time) == 4  # H + 3 digits

    def test_default_date_part(self, t1):
        result = exo.generate_id(now=t1)
        assert result.startswith("2648-")  # 26=year, 4=Apr, 8=day

    def test_midnight_jan1(self, midnight_jan1):
        result = exo.generate_id(now=midnight_jan1)
        assert result == "3011-0000"

    def test_default_t2_date(self, t2):
        result = exo.generate_id(now=t2)
        # YY=23, M=b(11), D=d(13), H=k(20)
        assert result.startswith("23bd-k")

    # -- time_digits --

    def test_time_digits_3(self, t1):
        result = exo.generate_id(time_digits=3, now=t1)
        time_part = result.split("-")[1]
        assert len(time_part) == 4  # H + 3

    def test_time_digits_4(self, t1):
        result = exo.generate_id(time_digits=4, now=t1)
        time_part = result.split("-")[1]
        assert len(time_part) == 5  # H + 4

    def test_time_digits_5(self, t1):
        result = exo.generate_id(time_digits=5, now=t1)
        time_part = result.split("-")[1]
        assert len(time_part) == 6  # H + 5

    def test_more_digits_more_precision(self, t1):
        """Higher time_digits should produce IDs with more granular time."""
        id3 = exo.generate_id(time_digits=3, now=t1)
        id5 = exo.generate_id(time_digits=5, now=t1)
        # The 5-digit version should start with the same chars as the 3-digit
        # (they share the same coarse time) — the 3-digit value is a prefix
        # of the 5-digit value's time component
        time3 = id3.split("-")[1]
        time5 = id5.split("-")[1]
        assert time5.startswith(time3[:3])  # H + first 2 time digits match

    # -- decimal_date mode --

    def test_decimal_date(self, t1):
        result = exo.generate_id(decimal_date=True, now=t1)
        assert result.startswith("260408-")

    def test_decimal_date_pads_month(self):
        t = datetime(2026, 1, 5, 0, 0, 0, 0, tzinfo=timezone.utc)
        result = exo.generate_id(decimal_date=True, now=t)
        assert result.startswith("260105-")

    # -- unix_time_base36 mode --

    def test_unix_time(self, t1):
        result = exo.generate_id(unix_time_base36=True, now=t1)
        yy = exo.to_base36(2026 - 1970).zfill(2)
        assert result.startswith(f"{yy}48-")

    def test_unix_time_includes_day(self, t2):
        """Verify the Python version fixes the JS bug: day IS included."""
        result = exo.generate_id(unix_time_base36=True, now=t2)
        yy = exo.to_base36(2023 - 1970).zfill(2)
        m = exo.to_base36(11)
        d = exo.to_base36(13)
        assert result.startswith(f"{yy}{m}{d}-")

    # -- prefix / suffix / separator --

    def test_prefix(self, t1):
        result = exo.generate_id(prefix=".", now=t1)
        assert result.startswith(".")

    def test_suffix(self, t1):
        result = exo.generate_id(suffix="]]", now=t1)
        assert result.endswith("]]")

    def test_wiki_link(self, t1):
        result = exo.generate_id(prefix="[[", suffix="]]", now=t1)
        assert result.startswith("[[") and result.endswith("]]")

    def test_custom_separator(self, t1):
        result = exo.generate_id(separator=".", now=t1)
        parts = result.split(".")
        assert len(parts) == 2

    def test_empty_separator(self, t1):
        result = exo.generate_id(separator="", now=t1)
        assert "-" not in result


# =============================================================================
# parse_id — roundtrip
# =============================================================================

class TestParseId:
    """Test that parse_id recovers the original datetime."""

    @pytest.fixture(params=[
        datetime(2026, 4, 8, 14, 30, 45, 200_000, tzinfo=timezone.utc),
        datetime(2023, 11, 13, 20, 1, 0, 0, tzinfo=timezone.utc),
        datetime(2030, 1, 1, 0, 0, 0, 0, tzinfo=timezone.utc),
        datetime(2025, 12, 31, 23, 59, 59, 0, tzinfo=timezone.utc),
        datetime(2026, 6, 15, 12, 0, 0, 0, tzinfo=timezone.utc),
    ])
    def sample_time(self, request):
        return request.param

    def _assert_close(self, original, parsed, max_error_seconds):
        """Assert parsed datetime is within max_error of original."""
        delta = abs((original - parsed).total_seconds())
        assert delta < max_error_seconds, (
            f"Parsed {parsed} differs from {original} by {delta:.6f}s "
            f"(max allowed: {max_error_seconds}s)"
        )

    # -- default mode roundtrip --

    def test_roundtrip_3_digits(self, sample_time):
        id_str = exo.generate_id(now=sample_time)
        parsed = exo.parse_id(id_str)
        # 3 digits: precision ~77ms
        self._assert_close(sample_time, parsed, 0.08)

    def test_roundtrip_4_digits(self, sample_time):
        id_str = exo.generate_id(time_digits=4, now=sample_time)
        parsed = exo.parse_id(id_str)  # auto-detects 4 digits
        # 4 digits: precision ~2.1ms
        self._assert_close(sample_time, parsed, 0.003)

    def test_roundtrip_5_digits(self, sample_time):
        id_str = exo.generate_id(time_digits=5, now=sample_time)
        parsed = exo.parse_id(id_str)  # auto-detects 5 digits
        # 5 digits: precision ~60µs
        self._assert_close(sample_time, parsed, 0.0001)

    def test_roundtrip_6_digits(self, sample_time):
        id_str = exo.generate_id(time_digits=6, now=sample_time)
        parsed = exo.parse_id(id_str)  # auto-detects 6 digits
        # 6 digits: precision ~1.7µs
        self._assert_close(sample_time, parsed, 0.000002)

    # -- date is exact --

    def test_date_exact(self, sample_time):
        id_str = exo.generate_id(now=sample_time)
        parsed = exo.parse_id(id_str)
        assert parsed.year == sample_time.year
        assert parsed.month == sample_time.month
        assert parsed.day == sample_time.day
        assert parsed.hour == sample_time.hour

    # -- decimal_date roundtrip --

    def test_roundtrip_decimal_date(self, sample_time):
        kwargs = dict(decimal_date=True)
        id_str = exo.generate_id(now=sample_time, **kwargs)
        parsed = exo.parse_id(id_str, **kwargs)
        self._assert_close(sample_time, parsed, 0.08)

    # -- unix_time roundtrip --

    def test_roundtrip_unix_time(self, sample_time):
        kwargs = dict(unix_time_base36=True)
        id_str = exo.generate_id(now=sample_time, **kwargs)
        parsed = exo.parse_id(id_str, **kwargs)
        self._assert_close(sample_time, parsed, 0.08)

    # -- prefix/suffix roundtrip --

    def test_roundtrip_prefix_suffix(self, sample_time):
        kwargs = dict(prefix="[[", suffix="]]")
        id_str = exo.generate_id(now=sample_time, **kwargs)
        parsed = exo.parse_id(id_str, **kwargs)
        self._assert_close(sample_time, parsed, 0.08)

    # -- midnight edge case --

    def test_midnight_exact(self):
        t = datetime(2030, 1, 1, 0, 0, 0, 0, tzinfo=timezone.utc)
        id_str = exo.generate_id(now=t)
        parsed = exo.parse_id(id_str)
        assert parsed == t

    # -- end of hour edge case --

    def test_end_of_hour(self):
        t = datetime(2026, 6, 15, 14, 59, 59, 999_000, tzinfo=timezone.utc)
        id_str = exo.generate_id(time_digits=5, now=t)
        parsed = exo.parse_id(id_str, time_digits=5)
        self._assert_close(t, parsed, 0.0001)

    # -- auto-detection works across digit counts --

    @pytest.mark.parametrize("digits", [3, 4, 5, 6, 7])
    def test_auto_detect_time_digits(self, digits):
        """parse_id should auto-detect time_digits from ID length."""
        t = datetime(2026, 4, 8, 14, 30, 45, 200_000, tzinfo=timezone.utc)
        id_str = exo.generate_id(time_digits=digits, now=t)
        parsed = exo.parse_id(id_str)
        # Date and hour should always be exact
        assert parsed.year == t.year
        assert parsed.month == t.month
        assert parsed.day == t.day
        assert parsed.hour == t.hour

    # -- bad input --

    def test_missing_separator_raises(self):
        with pytest.raises(ValueError):
            exo.parse_id("2648e123")


# =============================================================================
# Sortability
# =============================================================================

class TestSortability:
    """IDs generated from sequential times should sort lexicographically."""

    @pytest.mark.parametrize("time_digits", [3, 4, 5])
    def test_same_day_ordering(self, time_digits):
        times = [
            datetime(2026, 4, 8, h, m, 0, 0, tzinfo=timezone.utc)
            for h in range(0, 24, 4)
            for m in range(0, 60, 15)
        ]
        ids = [exo.generate_id(time_digits=time_digits, now=t) for t in times]
        assert ids == sorted(ids)

    def test_cross_day_ordering(self):
        times = [
            datetime(2026, 4, d, 12, 0, 0, 0, tzinfo=timezone.utc)
            for d in range(1, 29)
        ]
        ids = [exo.generate_id(now=t) for t in times]
        assert ids == sorted(ids)

    def test_cross_month_ordering(self):
        times = [
            datetime(2026, m, 1, 12, 0, 0, 0, tzinfo=timezone.utc)
            for m in range(1, 13)
        ]
        ids = [exo.generate_id(now=t) for t in times]
        assert ids == sorted(ids)


# =============================================================================
# CLI (main function)
# =============================================================================

class TestCLI:
    def test_no_args(self, capsys):
        exo.main([])
        out = capsys.readouterr().out.strip()
        assert len(out) >= 7
        assert "-" in out

    def test_prefix_flag(self, capsys):
        exo.main(["--prefix", "."])
        out = capsys.readouterr().out.strip()
        assert out.startswith(".")

    def test_decimal_date_flag(self, capsys):
        exo.main(["--decimal-date"])
        out = capsys.readouterr().out.strip()
        date_part = out.split("-")[0]
        assert len(date_part) == 6

    def test_unix_time_flag(self, capsys):
        exo.main(["--unix-time"])
        out = capsys.readouterr().out.strip()
        assert "-" in out

    def test_time_digits_flag(self, capsys):
        exo.main(["-t", "5"])
        out = capsys.readouterr().out.strip()
        time_part = out.split("-")[1]
        assert len(time_part) == 6  # H + 5

    def test_parse_flag(self, capsys):
        exo.main(["--parse", "3011-0000"])
        out = capsys.readouterr().out.strip()
        assert out.startswith("2030-01-01 00:00:00")

    def test_parse_roundtrip_cli(self, capsys):
        """Generate then parse via CLI flags."""
        exo.main([])
        id_str = capsys.readouterr().out.strip()
        exo.main(["--parse", id_str])
        out = capsys.readouterr().out.strip()
        assert out.endswith("UTC")
        # Should be today's date
        assert "2026" in out or "2025" in out  # flexible for test timing
