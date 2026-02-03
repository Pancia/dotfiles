"""Tests for Job state transitions and lifecycle."""

import json
import sys
from datetime import datetime
from pathlib import Path

import pytest

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

from server import Job, JobType, JobState, job_to_dict, job_from_dict


class TestJobInitialState:
    """Tests for job initialization."""

    def test_job_initial_state_is_pending(self):
        """New jobs should start in PENDING state."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        assert job.state == JobState.PENDING

    def test_job_initial_progress_is_zero(self):
        """New jobs should start with 0% progress."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        assert job.progress == 0.0

    def test_job_default_model(self):
        """Jobs should default to 'small' model."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        assert job.model == "small"

    def test_job_started_at_set(self):
        """Jobs should have started_at set on creation."""
        before = datetime.now()
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )
        after = datetime.now()

        assert before <= job.started_at <= after


class TestJobStateTransitions:
    """Tests for job state transitions."""

    def test_pending_to_downloading(self):
        """Jobs can transition from PENDING to DOWNLOADING."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        job.state = JobState.DOWNLOADING

        assert job.state == JobState.DOWNLOADING

    def test_downloading_to_transcribing(self):
        """Jobs can transition from DOWNLOADING to TRANSCRIBING."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.DOWNLOADING
        )

        job.state = JobState.TRANSCRIBING

        assert job.state == JobState.TRANSCRIBING

    def test_transcribing_to_complete(self):
        """Jobs can transition from TRANSCRIBING to COMPLETE."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.TRANSCRIBING
        )

        job.state = JobState.COMPLETE
        job.completed_at = datetime.now()

        assert job.state == JobState.COMPLETE
        assert job.completed_at is not None

    def test_any_state_to_error(self):
        """Jobs can transition to ERROR from any state."""
        for state in [JobState.PENDING, JobState.DOWNLOADING, JobState.TRANSCRIBING]:
            job = Job(
                id="test123",
                job_type=JobType.TRANSCRIBE,
                url="https://youtube.com/watch?v=test123",
                state=state
            )

            job.state = JobState.ERROR
            job.error = "Something went wrong"

            assert job.state == JobState.ERROR
            assert job.error == "Something went wrong"

    def test_summarize_job_has_summarizing_state(self):
        """Summarize jobs can transition through SUMMARIZING state."""
        job = Job(
            id="test123",
            job_type=JobType.SUMMARIZE,
            url="https://youtube.com/watch?v=test123",
            state=JobState.TRANSCRIBING
        )

        job.state = JobState.SUMMARIZING

        assert job.state == JobState.SUMMARIZING


class TestJobPersistence:
    """Tests for job serialization and deserialization."""

    def test_job_to_dict_includes_all_fields(self):
        """job_to_dict should include all persistable fields."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            video_id="test123",
            title="Test Video",
            state=JobState.DOWNLOADING,
            progress=50.0,
            model="turbo",
            sections=["0:00-5:00"]
        )

        data = job_to_dict(job)

        assert data["id"] == "test123"
        assert data["job_type"] == "transcribe"
        assert data["url"] == "https://youtube.com/watch?v=test123"
        assert data["video_id"] == "test123"
        assert data["title"] == "Test Video"
        assert data["state"] == "downloading"
        assert data["progress"] == 50.0
        assert data["model"] == "turbo"
        assert data["sections"] == ["0:00-5:00"]

    def test_job_from_dict_restores_all_fields(self):
        """job_from_dict should restore all fields correctly."""
        data = {
            "id": "test123",
            "job_type": "summarize",
            "url": "https://youtube.com/watch?v=test123",
            "video_id": "test123",
            "title": "Test Video",
            "state": "summarizing",
            "progress": 80.0,
            "error": None,
            "started_at": "2024-01-01T12:00:00",
            "completed_at": None,
            "model": "turbo",
            "prompt": "Summarize this",
            "sections": None,
            "context": "Extra context"
        }

        job = job_from_dict(data)

        assert job.id == "test123"
        assert job.job_type == JobType.SUMMARIZE
        assert job.state == JobState.SUMMARIZING
        assert job.progress == 80.0
        assert job.prompt == "Summarize this"
        assert job.context == "Extra context"

    def test_job_roundtrip(self):
        """Jobs should survive serialization roundtrip."""
        original = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            video_id="test123",
            title="Test Video",
            state=JobState.COMPLETE,
            progress=100.0,
            model="small",
        )
        original.completed_at = datetime.now()

        data = job_to_dict(original)
        restored = job_from_dict(data)

        assert restored.id == original.id
        assert restored.job_type == original.job_type
        assert restored.url == original.url
        assert restored.video_id == original.video_id
        assert restored.title == original.title
        assert restored.state == original.state
        assert restored.progress == original.progress

    def test_job_to_dict_json_serializable(self):
        """job_to_dict output should be JSON serializable."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        data = job_to_dict(job)
        json_str = json.dumps(data)

        assert isinstance(json_str, str)
        # Should be parseable back
        parsed = json.loads(json_str)
        assert parsed["id"] == "test123"


class TestJobTypes:
    """Tests for different job types."""

    def test_transcribe_job_type(self):
        """TRANSCRIBE job type should work correctly."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123"
        )

        assert job.job_type == JobType.TRANSCRIBE
        assert job.job_type.value == "transcribe"

    def test_summarize_job_type(self):
        """SUMMARIZE job type should work correctly."""
        job = Job(
            id="test123",
            job_type=JobType.SUMMARIZE,
            url="https://youtube.com/watch?v=test123",
            prompt="Summarize this"
        )

        assert job.job_type == JobType.SUMMARIZE
        assert job.job_type.value == "summarize"
        assert job.prompt == "Summarize this"


class TestJobSections:
    """Tests for section-based transcription."""

    def test_job_with_sections(self):
        """Jobs can have section specifications."""
        job = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            sections=["0:00-5:00", "10:00-15:00"]
        )

        assert job.sections == ["0:00-5:00", "10:00-15:00"]

    def test_job_sections_in_persistence(self):
        """Sections should be preserved in persistence."""
        original = Job(
            id="test123",
            job_type=JobType.TRANSCRIBE,
            url="https://youtube.com/watch?v=test123",
            sections=["1:00:00-1:05:00"]
        )

        data = job_to_dict(original)
        restored = job_from_dict(data)

        assert restored.sections == ["1:00:00-1:05:00"]
