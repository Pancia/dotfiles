"""Unit tests for cache lookup functions in youtube-transcribe service."""

import sys
from pathlib import Path

import pytest

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

# Need to patch TRANSCRIPTS_DIR before importing find_cached_transcript
import server


class TestFindCachedTranscript:
    """Tests for find_cached_transcript() function."""

    @pytest.fixture
    def mock_transcripts_dir(self, tmp_path, monkeypatch):
        """Create a temporary transcripts directory."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        return transcripts_dir

    def test_finds_cached_transcript(self, mock_transcripts_dir):
        """Return cached transcript when it exists."""
        video_id = "dQw4w9WgXcQ"
        transcript_file = mock_transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        transcript_content = "This is the cached transcript content."
        transcript_file.write_text(transcript_content)

        result = server.find_cached_transcript(video_id)

        assert result is not None
        path, content = result
        assert path == transcript_file
        assert content == transcript_content

    def test_returns_none_for_cache_miss(self, mock_transcripts_dir):
        """Return None when no cached transcript exists."""
        result = server.find_cached_transcript("nonexistent123")

        assert result is None

    def test_returns_most_recent_version(self, mock_transcripts_dir):
        """Return the most recent transcript when multiple versions exist."""
        video_id = "dQw4w9WgXcQ"

        # Create older transcript
        older_file = mock_transcripts_dir / f"20240101_100000_{video_id}_test-video.txt"
        older_file.write_text("Older transcript")

        # Create newer transcript (higher timestamp = more recent by filename sort)
        newer_file = mock_transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        newer_file.write_text("Newer transcript")

        result = server.find_cached_transcript(video_id)

        assert result is not None
        path, content = result
        assert path == newer_file
        assert content == "Newer transcript"

    def test_matches_video_id_in_middle(self, mock_transcripts_dir):
        """Video ID should match in the middle of the filename pattern."""
        video_id = "dQw4w9WgXcQ"

        # Different video ID shouldn't match
        other_file = mock_transcripts_dir / "20240101_120000_othervideoID_test-video.txt"
        other_file.write_text("Other video")

        # Target video ID should match
        target_file = mock_transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        target_file.write_text("Target transcript")

        result = server.find_cached_transcript(video_id)

        assert result is not None
        path, content = result
        assert path == target_file

    def test_empty_transcript_directory(self, mock_transcripts_dir):
        """Return None when transcripts directory is empty."""
        result = server.find_cached_transcript("dQw4w9WgXcQ")

        assert result is None

    def test_handles_special_chars_in_slug(self, mock_transcripts_dir):
        """Handle transcripts with various slug formats."""
        video_id = "abc_def-123"
        transcript_file = mock_transcripts_dir / f"20240101_120000_{video_id}_weird-title-here.txt"
        transcript_file.write_text("Transcript with special video ID")

        result = server.find_cached_transcript(video_id)

        assert result is not None
        path, content = result
        assert path == transcript_file


class TestSaveContent:
    """Tests for save_content() function."""

    @pytest.fixture
    def mock_storage_dirs(self, tmp_path, monkeypatch):
        """Create temporary storage directories."""
        transcripts_dir = tmp_path / "transcripts"
        summaries_dir = tmp_path / "summaries"
        transcripts_dir.mkdir()
        summaries_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        return {"transcripts": transcripts_dir, "summaries": summaries_dir}

    def test_save_transcript(self, mock_storage_dirs):
        """Save transcript to transcripts directory."""
        video_id = "dQw4w9WgXcQ"
        title = "Test Video Title"
        content = "This is the transcript content."

        saved_path = server.save_content(video_id, title, content, "transcript")

        assert saved_path.exists()
        assert saved_path.parent == mock_storage_dirs["transcripts"]
        assert video_id in saved_path.name
        assert saved_path.read_text() == content

    def test_save_summary(self, mock_storage_dirs):
        """Save summary to summaries directory."""
        video_id = "dQw4w9WgXcQ"
        title = "Test Video Title"
        content = "This is the summary content."

        saved_path = server.save_content(video_id, title, content, "summary")

        assert saved_path.exists()
        assert saved_path.parent == mock_storage_dirs["summaries"]
        assert video_id in saved_path.name
        assert saved_path.read_text() == content

    def test_filename_includes_timestamp(self, mock_storage_dirs):
        """Saved files should include a timestamp prefix."""
        saved_path = server.save_content("vid123", "Test", "content", "transcript")

        # Filename format: {timestamp}_{video_id}_{slug}.txt
        # Timestamp format: YYYYMMDD_HHMMSS
        filename = saved_path.name
        parts = filename.split("_")
        assert len(parts[0]) == 8  # YYYYMMDD
        assert len(parts[1]) == 6  # HHMMSS

    def test_filename_includes_slugified_title(self, mock_storage_dirs):
        """Saved files should include slugified title."""
        saved_path = server.save_content("vid123", "My Test Video", "content", "transcript")

        assert "my-test-video" in saved_path.name.lower()
