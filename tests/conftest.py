"""Shared pytest fixtures for dotfiles tests."""

import asyncio
import sys
import tempfile
from pathlib import Path
from typing import AsyncGenerator
from unittest.mock import MagicMock

import pytest

# Add services to path for imports
DOTFILES = Path(__file__).parent.parent
sys.path.insert(0, str(DOTFILES / "services" / "youtube-transcribe"))
sys.path.insert(0, str(DOTFILES / "lib" / "python"))


@pytest.fixture
def temp_storage_dir(tmp_path: Path) -> Path:
    """Temporary directory for test outputs."""
    storage = tmp_path / "storage"
    storage.mkdir()
    (storage / "transcripts").mkdir()
    (storage / "summaries").mkdir()
    (storage / "logs").mkdir()
    (storage / "jobs").mkdir()
    return storage


@pytest.fixture
def mock_job():
    """Factory for creating mock Job objects."""
    from datetime import datetime
    from dataclasses import dataclass, field
    from enum import Enum

    class JobState(str, Enum):
        PENDING = "pending"
        QUEUED = "queued"
        DOWNLOADING = "downloading"
        EXTRACTING = "extracting"
        TRANSCRIBING = "transcribing"
        SUMMARIZING = "summarizing"
        COMPLETE = "complete"
        ERROR = "error"
        INTERRUPTED = "interrupted"

    class JobType(str, Enum):
        TRANSCRIBE = "transcribe"
        SUMMARIZE = "summarize"

    @dataclass
    class MockJob:
        id: str
        job_type: JobType
        url: str
        video_id: str | None = None
        title: str | None = None
        state: JobState = JobState.PENDING
        progress: float = 0.0
        error: str | None = None
        started_at: datetime = field(default_factory=datetime.now)
        completed_at: datetime | None = None
        model: str = "small"
        prompt: str | None = None
        sections: list[str] | None = None
        context: str | None = None
        logger: MagicMock | None = None
        event_bus: MagicMock | None = None
        background_task: asyncio.Task | None = None
        result_content: str | None = None
        result_path: str | None = None

    def _create_job(
        job_id: str = "test123",
        job_type: str = "transcribe",
        url: str = "https://youtube.com/watch?v=test123",
        **kwargs
    ) -> MockJob:
        return MockJob(
            id=job_id,
            job_type=JobType(job_type),
            url=url,
            **kwargs
        )

    return _create_job
