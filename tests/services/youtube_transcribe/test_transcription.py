"""Unit tests for transcription pipeline with mocking.

Tests error handling paths in transcribe_stream and summarize_stream
without actually running subprocesses.
"""

import asyncio
import sys
from datetime import datetime
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

import server
from server import (
    Job, JobType, JobState, JobLogger, JobEventBus,
    transcribe_stream, summarize_stream, get_video_info,
    extract_video_id, process_registry
)


@pytest.fixture
def mock_job(tmp_path):
    """Create a job with mocked logger."""
    logs_dir = tmp_path / "logs"
    logs_dir.mkdir()

    job = Job(
        id="test123",
        job_type=JobType.TRANSCRIBE,
        url="https://youtube.com/watch?v=dQw4w9WgXcQ"
    )
    job.logger = JobLogger(job.id, "transcribe", logs_dir)
    job.event_bus = JobEventBus(job_id=job.id)
    return job


@pytest.fixture
def mock_summarize_job(tmp_path):
    """Create a summarize job with mocked logger."""
    logs_dir = tmp_path / "logs"
    logs_dir.mkdir()

    job = Job(
        id="test456",
        job_type=JobType.SUMMARIZE,
        url="https://youtube.com/watch?v=dQw4w9WgXcQ",
        prompt="Summarize this"
    )
    job.logger = JobLogger(job.id, "summarize", logs_dir)
    job.event_bus = JobEventBus(job_id=job.id)
    return job


class TestTranscribeStreamInvalidUrl:
    """Tests for transcribe_stream with invalid URLs."""

    @pytest.mark.asyncio
    async def test_invalid_youtube_url_yields_error(self, mock_job):
        """Invalid YouTube URL should yield error event immediately."""
        mock_job.url = "https://example.com/not-youtube"

        events = []
        async for event in transcribe_stream("https://example.com/not-youtube", "small", None, mock_job):
            events.append(event)

        assert len(events) == 1
        assert events[0]["event"] == "error"
        assert "invalid" in events[0]["data"]["message"].lower()

    @pytest.mark.asyncio
    async def test_invalid_url_sets_job_error_state(self, mock_job):
        """Invalid URL should set job to ERROR state."""
        mock_job.url = "https://example.com/not-youtube"

        async for _ in transcribe_stream("https://example.com/not-youtube", "small", None, mock_job):
            pass

        assert mock_job.state == JobState.ERROR
        assert mock_job.error == "Invalid YouTube URL"
        assert mock_job.completed_at is not None


class TestSummarizeStreamInvalidUrl:
    """Tests for summarize_stream with invalid URLs."""

    @pytest.mark.asyncio
    async def test_invalid_youtube_url_yields_error(self, mock_summarize_job):
        """Invalid YouTube URL should yield error event."""
        events = []
        async for event in summarize_stream("https://example.com/not-youtube", "small", "Summarize", None, None, mock_summarize_job):
            events.append(event)

        assert len(events) == 1
        assert events[0]["event"] == "error"
        assert "invalid" in events[0]["data"]["message"].lower()

    @pytest.mark.asyncio
    async def test_invalid_url_sets_job_error_state(self, mock_summarize_job):
        """Invalid URL should set job to ERROR state."""
        async for _ in summarize_stream("https://example.com/not-youtube", "small", "Summarize", None, None, mock_summarize_job):
            pass

        assert mock_summarize_job.state == JobState.ERROR
        assert mock_summarize_job.error == "Invalid YouTube URL"


class TestGetVideoInfoTimeout:
    """Tests for get_video_info timeout handling."""

    @pytest.mark.asyncio
    async def test_video_info_timeout_raises(self, mock_job):
        """Timeout during video info fetch should raise exception."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(side_effect=asyncio.TimeoutError())
        mock_proc.kill = AsyncMock()
        mock_proc.wait = AsyncMock()
        mock_proc.pid = 12345

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            with pytest.raises(Exception) as exc_info:
                await get_video_info("https://youtube.com/watch?v=dQw4w9WgXcQ", mock_job)

            assert "timed out" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_video_info_failure_raises(self, mock_job):
        """Non-zero return code from yt-dlp should raise exception."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"", b"Video unavailable"))
        mock_proc.returncode = 1
        mock_proc.pid = 12345

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            with pytest.raises(Exception) as exc_info:
                await get_video_info("https://youtube.com/watch?v=dQw4w9WgXcQ", mock_job)

            assert "failed to get video info" in str(exc_info.value).lower()


class TestTranscribeStreamCacheHit:
    """Tests for cache hit behavior in transcribe_stream."""

    @pytest.mark.asyncio
    async def test_cached_transcript_yields_cached_and_complete(self, mock_job, tmp_path, monkeypatch):
        """Cached transcript should yield cached + complete events without downloading."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)

        # Create cached transcript
        video_id = "dQw4w9WgXcQ"
        cached_file = transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        cached_file.write_text("Cached transcript content")

        events = []
        async for event in transcribe_stream(f"https://youtube.com/watch?v={video_id}", "small", None, mock_job):
            events.append(event)

        assert len(events) == 2
        assert events[0]["event"] == "cached"
        assert events[0]["data"]["video_id"] == video_id
        assert events[1]["event"] == "complete"
        assert events[1]["data"]["cached"] is True
        assert events[1]["data"]["transcript"] == "Cached transcript content"

    @pytest.mark.asyncio
    async def test_sections_bypass_cache(self, mock_job, tmp_path, monkeypatch):
        """When sections are specified, cache should be bypassed."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)

        # Create cached transcript
        video_id = "dQw4w9WgXcQ"
        cached_file = transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        cached_file.write_text("Cached transcript content")

        # Mock get_video_info to fail (proving cache was bypassed)
        with patch.object(server, "get_video_info", side_effect=Exception("Network error")):
            events = []
            async for event in transcribe_stream(
                f"https://youtube.com/watch?v={video_id}",
                "small",
                ["0:00-5:00"],  # sections specified
                mock_job
            ):
                events.append(event)

            # Should have tried to fetch video info (bypassed cache) and failed
            assert events[-1]["event"] == "error"
            assert "network error" in events[-1]["data"]["message"].lower()


class TestJobLogger:
    """Tests for JobLogger functionality."""

    def test_logger_creates_log_file(self, tmp_path):
        """JobLogger should create a log file on initialization."""
        logs_dir = tmp_path / "logs"
        logs_dir.mkdir()

        logger = JobLogger("test123", "transcribe", logs_dir)

        log_file = logs_dir / "test123.log"
        assert log_file.exists()
        content = log_file.read_text()
        assert "Job test123" in content
        assert "transcribe" in content

    def test_logger_info_writes_timestamp(self, tmp_path):
        """info() should write timestamped messages."""
        logs_dir = tmp_path / "logs"
        logs_dir.mkdir()

        logger = JobLogger("test123", "transcribe", logs_dir)
        logger.info("Test message")

        content = (logs_dir / "test123.log").read_text()
        assert "INFO: Test message" in content

    def test_logger_error_writes_timestamp(self, tmp_path):
        """error() should write timestamped error messages."""
        logs_dir = tmp_path / "logs"
        logs_dir.mkdir()

        logger = JobLogger("test123", "transcribe", logs_dir)
        logger.error("Something failed")

        content = (logs_dir / "test123.log").read_text()
        assert "ERROR: Something failed" in content

    def test_logger_subprocess_output(self, tmp_path):
        """subprocess_output() should log with source label."""
        logs_dir = tmp_path / "logs"
        logs_dir.mkdir()

        logger = JobLogger("test123", "transcribe", logs_dir)
        logger.subprocess_output("yt-dlp", "[download] 50% complete")

        content = (logs_dir / "test123.log").read_text()
        assert "[yt-dlp]" in content
        assert "50% complete" in content

    def test_logger_read_logs(self, tmp_path):
        """read_logs() should return recent log lines."""
        logs_dir = tmp_path / "logs"
        logs_dir.mkdir()

        logger = JobLogger("test123", "transcribe", logs_dir)
        logger.info("Line 1")
        logger.info("Line 2")
        logger.info("Line 3")

        lines = logger.read_logs(tail=2)

        assert len(lines) == 2
        assert "Line 2" in lines[0]
        assert "Line 3" in lines[1]


class TestProcessRegistry:
    """Tests for ProcessRegistry subprocess tracking."""

    @pytest.mark.asyncio
    async def test_register_and_unregister(self):
        """Processes can be registered and unregistered."""
        registry = server.ProcessRegistry()
        mock_proc = MagicMock()
        mock_proc.pid = 12345

        await registry.register(mock_proc, "job123")
        assert 12345 in registry._processes

        await registry.unregister(mock_proc)
        assert 12345 not in registry._processes

    @pytest.mark.asyncio
    async def test_unregister_nonexistent_process(self):
        """Unregistering nonexistent process should not error."""
        registry = server.ProcessRegistry()
        mock_proc = MagicMock()
        mock_proc.pid = 99999

        # Should not raise
        await registry.unregister(mock_proc)


# Helper for creating async generators in tests
async def async_iter(items):
    """Convert a list to an async generator for mocking."""
    for item in items:
        yield item


class TestTranscribeStreamOrchestration:
    """Tests for transcribe_stream orchestration logic (mocking helper functions)."""

    @pytest.mark.asyncio
    async def test_happy_path_event_sequence(self, mock_job, tmp_path, monkeypatch):
        """Transcribe happy path should emit: started → downloading → transcribing → complete."""
        # Setup temp directories
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)

        # Mock helper functions
        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe:

            mock_info.return_value = {"title": "Test Video", "duration": 120, "channel": "Test Channel"}

            async def download_gen():
                yield {"percent": 50, "speed": "1MB/s", "eta": "10s"}
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            async def transcribe_gen():
                yield {"status": "loading model", "model": "small"}
                yield {"status": "transcribing", "percent": 50, "timestamp": "01:00.000"}
                yield {"status": "complete", "transcript": "Hello world"}
            mock_transcribe.return_value = transcribe_gen()

            events = []
            async for event in transcribe_stream("https://youtube.com/watch?v=abcdefghijk", "small", None, mock_job):
                events.append(event)

        # Verify event sequence
        event_types = [e["event"] for e in events]
        assert event_types[0] == "started"
        assert "downloading" in event_types
        assert "transcribing" in event_types
        assert event_types[-1] == "complete"

        # Verify started event data
        started = next(e for e in events if e["event"] == "started")
        assert started["data"]["title"] == "Test Video"
        assert started["data"]["video_id"] == "abcdefghijk"

        # Verify complete event data
        complete = events[-1]
        assert complete["data"]["transcript"] == "Hello world"

    @pytest.mark.asyncio
    async def test_happy_path_job_state_transitions(self, mock_job, tmp_path, monkeypatch):
        """Job state should transition: PENDING → DOWNLOADING → TRANSCRIBING → COMPLETE."""
        # Setup temp directories
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)

        states_seen = []

        # Mock persist_job to capture state transitions
        original_persist = server.persist_job
        def capture_persist(job):
            states_seen.append(job.state)
        monkeypatch.setattr(server, "persist_job", capture_persist)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            async def transcribe_gen():
                yield {"status": "complete", "transcript": "Done"}
            mock_transcribe.return_value = transcribe_gen()

            async for _ in transcribe_stream("https://youtube.com/watch?v=abcdefghijk", "small", None, mock_job):
                pass

        # Verify final job state
        assert mock_job.state == JobState.COMPLETE
        assert mock_job.progress == 100.0
        assert mock_job.completed_at is not None

        # Verify state transitions were persisted
        assert JobState.DOWNLOADING in states_seen
        assert JobState.TRANSCRIBING in states_seen
        assert JobState.COMPLETE in states_seen

    @pytest.mark.asyncio
    async def test_with_sections_emits_extracting(self, mock_job, tmp_path, monkeypatch):
        """When sections specified, should emit extracting event."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)

        states_seen = []
        def capture_persist(job):
            states_seen.append(job.state)
        monkeypatch.setattr(server, "persist_job", capture_persist)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "extract_sections") as mock_extract, \
             patch.object(server, "transcribe_audio") as mock_transcribe:

            mock_info.return_value = {"title": "Test", "duration": 3600, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            # extract_sections returns a path
            extracted_path = temp_dir / "test_sections.m4a"
            extracted_path.touch()
            mock_extract.return_value = extracted_path

            async def transcribe_gen():
                yield {"status": "complete", "transcript": "Section content"}
            mock_transcribe.return_value = transcribe_gen()

            events = []
            async for event in transcribe_stream(
                "https://youtube.com/watch?v=abcdefghijk",
                "small",
                ["40:00-45:00"],
                mock_job
            ):
                events.append(event)

        # Verify extracting event emitted
        event_types = [e["event"] for e in events]
        assert "extracting" in event_types

        # Verify EXTRACTING state was seen
        assert JobState.EXTRACTING in states_seen

        # Verify sections passed to complete event (not saved to cache)
        complete = events[-1]
        assert complete["event"] == "complete"
        assert complete["data"].get("sections") == ["40:00-45:00"]

    @pytest.mark.asyncio
    async def test_error_during_download(self, mock_job, tmp_path, monkeypatch):
        """Error during download should yield error event and set job state."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def failing_download():
                yield {"percent": 25, "speed": "1MB/s", "eta": "30s"}
                raise Exception("Network connection lost")
            mock_download.return_value = failing_download()

            events = []
            async for event in transcribe_stream("https://youtube.com/watch?v=abcdefghijk", "small", None, mock_job):
                events.append(event)

        # Verify error event
        assert events[-1]["event"] == "error"
        assert "network connection lost" in events[-1]["data"]["message"].lower()

        # Verify job state
        assert mock_job.state == JobState.ERROR
        assert "network connection lost" in mock_job.error.lower()

    @pytest.mark.asyncio
    async def test_error_during_transcription(self, mock_job, tmp_path, monkeypatch):
        """Error during transcription should yield error event and cleanup temp files."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            async def failing_transcribe():
                yield {"status": "loading model", "model": "small"}
                yield {"status": "transcribing", "percent": 30, "timestamp": "00:20.000"}
                raise Exception("Whisper crashed")
            mock_transcribe.return_value = failing_transcribe()

            events = []
            async for event in transcribe_stream("https://youtube.com/watch?v=abcdefghijk", "small", None, mock_job):
                events.append(event)

        # Verify error event
        assert events[-1]["event"] == "error"
        assert "whisper crashed" in events[-1]["data"]["message"].lower()

        # Verify job state
        assert mock_job.state == JobState.ERROR

    @pytest.mark.asyncio
    async def test_progress_updates(self, mock_job, tmp_path, monkeypatch):
        """Job progress should update during download and transcription."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        progress_values = []

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 50, "speed": "1MB/s", "eta": "10s"}
                progress_values.append(("download_50", mock_job.progress))
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
                progress_values.append(("download_100", mock_job.progress))
            mock_download.return_value = download_gen()

            async def transcribe_gen():
                yield {"status": "transcribing", "percent": 50, "timestamp": "00:30.000"}
                progress_values.append(("transcribe_50", mock_job.progress))
                yield {"status": "complete", "transcript": "Done"}
            mock_transcribe.return_value = transcribe_gen()

            async for _ in transcribe_stream("https://youtube.com/watch?v=abcdefghijk", "small", None, mock_job):
                pass

        # Download is 30% of total, so 50% download = 15% total
        # Transcription is 30-100%, so 50% transcription = 30 + 35 = 65% total
        assert len(progress_values) >= 2
        # Final progress should be 100
        assert mock_job.progress == 100.0


class TestSummarizeStreamOrchestration:
    """Tests for summarize_stream orchestration logic (mocking helper functions)."""

    @pytest.mark.asyncio
    async def test_happy_path_with_cache(self, mock_summarize_job, tmp_path, monkeypatch):
        """With cached transcript, should emit: cached → summarizing → complete."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        summaries_dir = tmp_path / "summaries"
        summaries_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        # Create cached transcript
        video_id = "dQw4w9WgXcQ"
        cached_file = transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        cached_file.write_text("This is the transcript content")

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "run_claude_summary") as mock_claude:

            mock_info.return_value = {"title": "Test Video", "duration": 300, "channel": "Test"}
            mock_claude.return_value = "This is the summary"

            events = []
            async for event in summarize_stream(
                f"https://youtube.com/watch?v={video_id}",
                "small",
                "Summarize this",
                None,
                None,
                mock_summarize_job
            ):
                events.append(event)

        # Verify event sequence
        event_types = [e["event"] for e in events]
        assert "cached" in event_types
        assert "summarizing" in event_types
        assert event_types[-1] == "complete"

        # Should NOT have downloading or transcribing (used cache)
        assert "downloading" not in event_types
        assert "transcribing" not in event_types

        # Verify complete data
        complete = events[-1]
        assert complete["data"]["summary"] == "This is the summary"

    @pytest.mark.asyncio
    async def test_happy_path_no_cache(self, mock_summarize_job, tmp_path, monkeypatch):
        """Without cache, should emit: started → downloading → transcribing → summarizing → complete."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        summaries_dir = tmp_path / "summaries"
        summaries_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe, \
             patch.object(server, "run_claude_summary") as mock_claude:

            mock_info.return_value = {"title": "Test Video", "duration": 120, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            async def transcribe_gen():
                yield {"status": "transcribing", "percent": 50, "timestamp": "01:00.000"}
                yield {"status": "complete", "transcript": "The full transcript text"}
            mock_transcribe.return_value = transcribe_gen()

            mock_claude.return_value = "Summary of the video"

            events = []
            async for event in summarize_stream(
                "https://youtube.com/watch?v=dQw4w9WgXcQ",
                "small",
                "Summarize this",
                None,
                None,
                mock_summarize_job
            ):
                events.append(event)

        # Verify full event sequence
        event_types = [e["event"] for e in events]
        assert event_types[0] == "started"
        assert "downloading" in event_types
        assert "transcribing" in event_types
        assert "summarizing" in event_types
        assert event_types[-1] == "complete"

        # Verify job state
        assert mock_summarize_job.state == JobState.COMPLETE

    @pytest.mark.asyncio
    async def test_error_during_summarization(self, mock_summarize_job, tmp_path, monkeypatch):
        """Error during Claude summarization should yield error event."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        summaries_dir = tmp_path / "summaries"
        summaries_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        # Create cached transcript to skip to summarization quickly
        video_id = "dQw4w9WgXcQ"
        cached_file = transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        cached_file.write_text("Cached transcript")

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "run_claude_summary") as mock_claude:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}
            mock_claude.side_effect = Exception("Claude API rate limit exceeded")

            events = []
            async for event in summarize_stream(
                f"https://youtube.com/watch?v={video_id}",
                "small",
                "Summarize",
                None,
                None,
                mock_summarize_job
            ):
                events.append(event)

        # Verify error event
        assert events[-1]["event"] == "error"
        assert "rate limit" in events[-1]["data"]["message"].lower()

        # Verify job state
        assert mock_summarize_job.state == JobState.ERROR
        assert mock_summarize_job.error is not None

    @pytest.mark.asyncio
    async def test_context_appended_to_prompt(self, mock_summarize_job, tmp_path, monkeypatch):
        """Additional context should be appended to the prompt."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        summaries_dir = tmp_path / "summaries"
        summaries_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        monkeypatch.setattr(server, "persist_job", lambda j: None)

        video_id = "dQw4w9WgXcQ"
        cached_file = transcripts_dir / f"20240101_120000_{video_id}_test-video.txt"
        cached_file.write_text("Transcript")

        captured_prompt = None

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "run_claude_summary") as mock_claude:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def capture_claude(transcript, prompt, job=None):
                nonlocal captured_prompt
                captured_prompt = prompt
                return "Summary"
            mock_claude.side_effect = capture_claude

            events = []
            async for event in summarize_stream(
                f"https://youtube.com/watch?v={video_id}",
                "small",
                "Base prompt",
                None,
                "Focus on business aspects",  # context
                mock_summarize_job
            ):
                events.append(event)

        # Verify context was appended
        assert captured_prompt is not None
        assert "Base prompt" in captured_prompt
        assert "Additional Context" in captured_prompt
        assert "Focus on business aspects" in captured_prompt

    @pytest.mark.asyncio
    async def test_state_transitions_summarize(self, mock_summarize_job, tmp_path, monkeypatch):
        """Summarize job should transition through correct states."""
        transcripts_dir = tmp_path / "transcripts"
        transcripts_dir.mkdir()
        summaries_dir = tmp_path / "summaries"
        summaries_dir.mkdir()
        temp_dir = tmp_path / "temp"
        temp_dir.mkdir()
        monkeypatch.setattr(server, "TRANSCRIPTS_DIR", transcripts_dir)
        monkeypatch.setattr(server, "SUMMARIES_DIR", summaries_dir)
        monkeypatch.setattr(server, "TEMP_DIR", temp_dir)

        states_seen = []
        def capture_persist(job):
            states_seen.append(job.state)
        monkeypatch.setattr(server, "persist_job", capture_persist)

        with patch.object(server, "get_video_info") as mock_info, \
             patch.object(server, "download_audio") as mock_download, \
             patch.object(server, "transcribe_audio") as mock_transcribe, \
             patch.object(server, "run_claude_summary") as mock_claude:

            mock_info.return_value = {"title": "Test", "duration": 60, "channel": "Ch"}

            async def download_gen():
                yield {"percent": 100, "speed": "1MB/s", "eta": "0s"}
            mock_download.return_value = download_gen()

            async def transcribe_gen():
                yield {"status": "complete", "transcript": "Text"}
            mock_transcribe.return_value = transcribe_gen()

            mock_claude.return_value = "Summary"

            async for _ in summarize_stream(
                "https://youtube.com/watch?v=dQw4w9WgXcQ",
                "small",
                "Summarize",
                None,
                None,
                mock_summarize_job
            ):
                pass

        # Verify all states were seen
        assert JobState.DOWNLOADING in states_seen
        assert JobState.TRANSCRIBING in states_seen
        assert JobState.SUMMARIZING in states_seen
        assert JobState.COMPLETE in states_seen
