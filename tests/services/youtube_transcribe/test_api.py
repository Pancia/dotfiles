"""FastAPI endpoint tests for youtube-transcribe service."""

import sys
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

from server import app, active_jobs, Job, JobType, JobState, JobEventBus


@pytest.fixture
def clear_active_jobs():
    """Clear active jobs before and after each test."""
    active_jobs.clear()
    yield
    active_jobs.clear()


@pytest.fixture
async def async_client():
    """Create an async test client."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


class TestHealthEndpoint:
    """Tests for /health endpoint."""

    @pytest.mark.asyncio
    async def test_health_endpoint(self, async_client, clear_active_jobs):
        """Health endpoint should return status ok."""
        response = await async_client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "version" in data
        assert "active_jobs" in data

    @pytest.mark.asyncio
    async def test_health_shows_active_jobs(self, async_client, clear_active_jobs):
        """Health endpoint should show active job count."""
        # Add a job
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.DOWNLOADING
        )
        active_jobs["test123"] = job

        response = await async_client.get("/health")

        data = response.json()
        assert data["active_jobs"] == 1
        assert len(data["jobs"]) == 1
        assert data["jobs"][0]["id"] == "test123"


class TestStatusEndpoint:
    """Tests for /status/{job_id} endpoint."""

    @pytest.mark.asyncio
    async def test_status_not_found(self, async_client, clear_active_jobs):
        """Status endpoint should return 404 for nonexistent job."""
        response = await async_client.get("/status/nonexistent")

        assert response.status_code == 404
        data = response.json()
        assert "not found" in data["detail"].lower()

    @pytest.mark.asyncio
    async def test_status_returns_job_info(self, async_client, clear_active_jobs):
        """Status endpoint should return job information."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            video_id="test123",
            title="Test Video",
            state=JobState.TRANSCRIBING,
            progress=50.0
        )
        active_jobs["test123"] = job

        response = await async_client.get("/status/test123")

        assert response.status_code == 200
        data = response.json()
        assert data["id"] == "test123"
        assert data["type"] == "transcribe"
        assert data["state"] == "transcribing"
        assert data["progress"] == 50.0
        assert data["title"] == "Test Video"

    @pytest.mark.asyncio
    async def test_status_includes_result_path(self, async_client, clear_active_jobs):
        """Completed jobs should include result_path."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.COMPLETE
        )
        job.result_path = "/path/to/transcript.txt"
        active_jobs["test123"] = job

        response = await async_client.get("/status/test123")

        data = response.json()
        assert data["result_path"] == "/path/to/transcript.txt"

    @pytest.mark.asyncio
    async def test_status_includes_result_content_when_requested(self, async_client, clear_active_jobs):
        """Status with include_result=true should include result content."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.COMPLETE
        )
        job.result_content = "This is the transcript content."
        active_jobs["test123"] = job

        response = await async_client.get("/status/test123?include_result=true")

        data = response.json()
        assert data["result_content"] == "This is the transcript content."


class TestSubscribeEndpoint:
    """Tests for /subscribe/{job_id} endpoint."""

    @pytest.mark.asyncio
    async def test_subscribe_to_nonexistent_job(self, async_client, clear_active_jobs):
        """Subscribe endpoint should return 404 for nonexistent job."""
        response = await async_client.get("/subscribe/nonexistent")

        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_subscribe_requires_event_bus(self, async_client, clear_active_jobs):
        """Subscribe should return 400 if job has no event bus."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )
        job.event_bus = None
        active_jobs["test123"] = job

        response = await async_client.get("/subscribe/test123")

        assert response.status_code == 400


class TestRootEndpoint:
    """Tests for / root endpoint."""

    @pytest.mark.asyncio
    async def test_root_returns_usage_info(self, async_client):
        """Root endpoint should return usage information."""
        response = await async_client.get("/")

        assert response.status_code == 200
        data = response.json()
        assert data["service"] == "YouTube Transcribe Server"
        assert "endpoints" in data
        assert "POST /transcribe" in data["endpoints"]
        assert "POST /summarize" in data["endpoints"]


class TestLogsEndpoint:
    """Tests for /logs/{job_id} endpoint."""

    @pytest.mark.asyncio
    async def test_logs_not_found(self, async_client, clear_active_jobs):
        """Logs endpoint should return 404 for nonexistent job."""
        response = await async_client.get("/logs/nonexistent")

        assert response.status_code == 404


class TestTranscribeEndpoint:
    """Tests for POST /transcribe endpoint.

    Note: SSE streaming tests are skipped because httpx blocks reading the stream.
    These endpoints are tested via integration tests or manual testing.
    """

    def test_transcribe_job_creation(self, clear_active_jobs, tmp_path):
        """Verify transcribe creates proper Job object."""
        from datetime import datetime

        # Direct job creation test (not via HTTP to avoid SSE blocking)
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=dQw4w9WgXcQ",
            model="small",
            sections=None
        )

        assert job.id == "test123"
        assert job.job_type == JobType.TRANSCRIBE
        assert job.state == JobState.PENDING
        assert job.model == "small"


class TestSummarizeEndpoint:
    """Tests for POST /summarize endpoint.

    Note: SSE streaming tests are skipped because httpx blocks reading the stream.
    """

    def test_summarize_job_with_context(self, clear_active_jobs):
        """Verify summarize job stores context."""
        job = Job(
            id="test123",
            job_type=JobType.SUMMARIZE,
            url="https://youtube.com/watch?v=dQw4w9WgXcQ",
            prompt="Summarize this",
            context="Focus on the business aspects"
        )

        assert job.context == "Focus on the business aspects"
        assert job.prompt == "Summarize this"
        assert job.job_type == JobType.SUMMARIZE


class TestRequestValidation:
    """Tests for request validation via Pydantic models."""

    @pytest.mark.asyncio
    async def test_transcribe_missing_url(self, async_client):
        """Transcribe endpoint should reject requests without URL."""
        response = await async_client.post("/transcribe", json={})

        assert response.status_code == 422
        data = response.json()
        assert "url" in str(data).lower()

    @pytest.mark.asyncio
    async def test_summarize_missing_url(self, async_client):
        """Summarize endpoint should reject requests without URL."""
        response = await async_client.post("/summarize", json={})

        assert response.status_code == 422
        data = response.json()
        assert "url" in str(data).lower()

    @pytest.mark.asyncio
    async def test_transcribe_invalid_sections_type(self, async_client):
        """Transcribe should reject non-list sections."""
        response = await async_client.post("/transcribe", json={
            "url": "https://youtube.com/watch?v=test123",
            "sections": "not-a-list"
        })

        assert response.status_code == 422

    @pytest.mark.asyncio
    async def test_summarize_invalid_sections_type(self, async_client):
        """Summarize should reject non-list sections."""
        response = await async_client.post("/summarize", json={
            "url": "https://youtube.com/watch?v=test123",
            "sections": "not-a-list"
        })

        assert response.status_code == 422

    def test_transcribe_request_model_defaults(self):
        """TranscribeRequest should have correct defaults."""
        from server import TranscribeRequest

        request = TranscribeRequest(url="https://youtube.com/watch?v=test123")

        assert request.model == "small"
        assert request.sections is None

    def test_summarize_request_model_defaults(self):
        """SummarizeRequest should have correct defaults."""
        from server import SummarizeRequest, DEFAULT_SUMMARY_PROMPT

        request = SummarizeRequest(url="https://youtube.com/watch?v=test123")

        assert request.model == "small"
        assert request.prompt == DEFAULT_SUMMARY_PROMPT
        assert request.sections is None
        assert request.context is None

    def test_transcribe_request_accepts_valid_sections(self):
        """TranscribeRequest should accept valid sections list."""
        from server import TranscribeRequest

        request = TranscribeRequest(
            url="https://youtube.com/watch?v=test123",
            sections=["0:00-5:00", "10:00-15:00"]
        )

        assert request.sections == ["0:00-5:00", "10:00-15:00"]

    def test_summarize_request_accepts_context(self):
        """SummarizeRequest should accept context parameter."""
        from server import SummarizeRequest

        request = SummarizeRequest(
            url="https://youtube.com/watch?v=test123",
            context="Focus on the technical aspects"
        )

        assert request.context == "Focus on the technical aspects"
