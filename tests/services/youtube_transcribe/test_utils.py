"""Unit tests for pure utility functions in youtube-transcribe service.

These tests cover functions with no side effects that can be tested without mocking.
"""

import sys
from pathlib import Path

import pytest

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

from server import extract_video_id, slugify, parse_timestamp, parse_section_time


class TestExtractVideoId:
    """Tests for extract_video_id() function."""

    def test_standard_watch_url(self):
        """Extract video ID from standard watch URL."""
        assert extract_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_watch_url_with_params(self):
        """Extract video ID from watch URL with additional parameters."""
        assert extract_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120") == "dQw4w9WgXcQ"
        assert extract_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf") == "dQw4w9WgXcQ"

    def test_short_url(self):
        """Extract video ID from youtu.be short URL."""
        assert extract_video_id("https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_short_url_with_params(self):
        """Extract video ID from short URL with timestamp."""
        assert extract_video_id("https://youtu.be/dQw4w9WgXcQ?t=120") == "dQw4w9WgXcQ"

    def test_embed_url(self):
        """Extract video ID from embed URL."""
        assert extract_video_id("https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_shorts_url(self):
        """Extract video ID from YouTube Shorts URL."""
        assert extract_video_id("https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_bare_video_id(self):
        """Extract video ID when only the ID is provided."""
        assert extract_video_id("dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_video_url_format(self):
        """Extract video ID from /video/ URL format."""
        assert extract_video_id("https://www.youtube.com/video/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_v_path_format(self):
        """Extract video ID from /v/ URL format."""
        assert extract_video_id("https://www.youtube.com/v/dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_invalid_url_returns_none(self):
        """Return None for non-YouTube URLs."""
        assert extract_video_id("https://example.com/video") is None
        assert extract_video_id("https://vimeo.com/123456789") is None

    def test_empty_string_returns_none(self):
        """Return None for empty string."""
        assert extract_video_id("") is None

    def test_invalid_video_id_length(self):
        """Return None for video IDs that are too short."""
        assert extract_video_id("https://youtube.com/watch?v=short") is None

    def test_long_video_id_extracts_first_11_chars(self):
        """Long video ID param extracts exactly 11 characters."""
        # The regex matches exactly 11 chars, so longer values still match
        assert extract_video_id("https://youtube.com/watch?v=waytoolongvideoidhere") == "waytoolongv"

    def test_video_id_with_special_chars(self):
        """Video IDs can contain underscores and hyphens."""
        assert extract_video_id("https://youtube.com/watch?v=abc_def-123") == "abc_def-123"

    def test_http_url(self):
        """Extract from HTTP (non-HTTPS) URL."""
        assert extract_video_id("http://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"

    def test_mobile_url(self):
        """Extract from mobile URL."""
        assert extract_video_id("https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"


class TestSlugify:
    """Tests for slugify() function."""

    def test_basic_text(self):
        """Convert basic text to slug."""
        assert slugify("Hello World") == "hello-world"

    def test_removes_special_chars(self):
        """Remove special characters."""
        assert slugify("Test: A/B (Part 1)") == "test-ab-part-1"

    def test_multiple_spaces(self):
        """Collapse multiple spaces to single hyphen."""
        assert slugify("Multiple   Spaces   Here") == "multiple-spaces-here"

    def test_leading_trailing_hyphens(self):
        """Strip leading and trailing hyphens."""
        assert slugify("  ---Hello World---  ") == "hello-world"

    def test_truncates_to_50_chars(self):
        """Truncate long slugs to 50 characters."""
        long_text = "a" * 100
        result = slugify(long_text)
        assert len(result) == 50
        assert result == "a" * 50

    def test_truncates_at_word_boundary_sort_of(self):
        """Long text is truncated (no word boundary guarantee in current impl)."""
        long_text = "This is a very long title that should be truncated at some point"
        result = slugify(long_text)
        assert len(result) <= 50

    def test_unicode_handling(self):
        r"""Unicode word characters are preserved (Python 3 \\w includes unicode)."""
        assert slugify("Cafe Résumé") == "cafe-résumé"

    def test_numbers_preserved(self):
        """Numbers should be preserved in slugs."""
        assert slugify("Episode 123") == "episode-123"

    def test_empty_string(self):
        """Handle empty string."""
        assert slugify("") == ""

    def test_only_special_chars(self):
        """Handle string with only special characters."""
        assert slugify("!@#$%^&*()") == ""


class TestParseTimestamp:
    """Tests for parse_timestamp() function.

    Parses whisper-style timestamps like '00:05.000' or '01:30.500'.
    """

    def test_basic_timestamp(self):
        """Parse basic MM:SS.mmm format."""
        assert parse_timestamp("00:05.000") == 5.0

    def test_with_milliseconds(self):
        """Parse timestamp with milliseconds."""
        assert parse_timestamp("01:30.500") == 90.5

    def test_minutes_only(self):
        """Parse timestamp with just minutes and seconds."""
        assert parse_timestamp("02:15") == 135.0

    def test_zero_timestamp(self):
        """Parse zero timestamp."""
        assert parse_timestamp("00:00.000") == 0.0

    def test_large_minutes(self):
        """Parse timestamp with large minute value."""
        assert parse_timestamp("59:59.999") == 3599.999

    def test_fractional_seconds(self):
        """Parse various fractional second values."""
        assert parse_timestamp("00:00.100") == 0.1
        assert parse_timestamp("00:00.999") == 0.999

    def test_invalid_format_returns_zero(self):
        """Invalid format returns 0.0."""
        assert parse_timestamp("invalid") == 0.0
        assert parse_timestamp("1:2:3:4") == 0.0


class TestParseSectionTime:
    """Tests for parse_section_time() function.

    Parses user-provided section timestamps like '40:00' or '1:30:00'.
    """

    def test_mm_ss_format(self):
        """Parse MM:SS format."""
        assert parse_section_time("01:30") == 90

    def test_hh_mm_ss_format(self):
        """Parse HH:MM:SS format."""
        assert parse_section_time("01:30:00") == 5400

    def test_zero_time(self):
        """Parse zero time."""
        assert parse_section_time("0:00") == 0

    def test_large_hour_value(self):
        """Parse timestamp with large hour value."""
        assert parse_section_time("2:30:00") == 9000

    def test_fractional_seconds(self):
        """Parse timestamp with fractional seconds."""
        assert parse_section_time("01:30.5") == 90.5

    def test_plain_seconds(self):
        """Parse plain seconds value."""
        assert parse_section_time("90") == 90.0

    def test_common_section_times(self):
        """Test common section time values."""
        assert parse_section_time("40:00") == 2400  # 40 minutes
        assert parse_section_time("1:20:00") == 4800  # 1 hour 20 minutes
        assert parse_section_time("45:35") == 2735  # 45 min 35 sec
