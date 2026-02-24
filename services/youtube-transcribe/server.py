#!/usr/bin/env python3
"""
YouTube Transcribe Server

FastAPI server that accepts YouTube URLs, downloads audio via yt-dlp,
transcribes using MLX Whisper, and streams progress via Server-Sent Events.

Features:
- Per-job file logging
- Job persistence for restart recovery
- Graceful shutdown with subprocess cleanup
- Background job execution (jobs continue even if client disconnects)
- SSE reconnection support with event replay
"""

import asyncio
import json
import os
import re
import signal
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse


# Job tracking types
class JobType(str, Enum):
    TRANSCRIBE = "transcribe"
    SUMMARIZE = "summarize"


class JobState(str, Enum):
    PENDING = "pending"
    QUEUED = "queued"  # Waiting for another job to finish
    DOWNLOADING = "downloading"
    EXTRACTING = "extracting"
    TRANSCRIBING = "transcribing"
    SUMMARIZING = "summarizing"
    COMPLETE = "complete"
    ERROR = "error"
    INTERRUPTED = "interrupted"  # Server shutdown mid-job


class JobLogger:
    """Per-job file logger with timestamps."""

    def __init__(self, job_id: str, job_type: str, logs_dir: Path):
        self.job_id = job_id
        self.log_path = logs_dir / f"{job_id}.log"
        # Write header
        with open(self.log_path, "w") as f:
            f.write(f"=== Job {job_id} ({job_type}) ===\n")
            f.write(f"Started: {datetime.now().isoformat()}\n")
            f.write("=" * 40 + "\n\n")

    def _write(self, level: str, message: str):
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        with open(self.log_path, "a") as f:
            f.write(f"[{timestamp}] {level}: {message}\n")

    def info(self, message: str):
        self._write("INFO", message)

    def error(self, message: str):
        self._write("ERROR", message)

    def subprocess_output(self, source: str, line: str):
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        with open(self.log_path, "a") as f:
            f.write(f"[{timestamp}] [{source}] {line}\n")

    def read_logs(self, tail: int = 50) -> list[str]:
        """Read last N lines from log file."""
        if not self.log_path.exists():
            return []
        lines = self.log_path.read_text().splitlines()
        return lines[-tail:] if len(lines) > tail else lines


class ProcessRegistry:
    """Track subprocesses for cleanup on shutdown."""

    def __init__(self):
        self._processes: dict[int, tuple[asyncio.subprocess.Process, str]] = {}
        self._lock = asyncio.Lock()

    async def register(self, proc: asyncio.subprocess.Process, job_id: str):
        async with self._lock:
            self._processes[proc.pid] = (proc, job_id)

    async def unregister(self, proc: asyncio.subprocess.Process):
        async with self._lock:
            self._processes.pop(proc.pid, None)

    async def kill_job(self, job_id: str):
        """Kill all processes for a specific job."""
        async with self._lock:
            to_kill = [(pid, proc) for pid, (proc, jid) in self._processes.items() if jid == job_id]
        for pid, proc in to_kill:
            try:
                proc.terminate()
                await asyncio.wait_for(proc.wait(), timeout=5.0)
            except (ProcessLookupError, asyncio.TimeoutError):
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
            async with self._lock:
                self._processes.pop(pid, None)

    async def kill_all(self):
        """Kill all tracked processes (shutdown)."""
        async with self._lock:
            all_procs = list(self._processes.items())
        for pid, (proc, job_id) in all_procs:
            try:
                proc.terminate()
            except ProcessLookupError:
                pass
        # Wait briefly for graceful termination
        await asyncio.sleep(1)
        for pid, (proc, job_id) in all_procs:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        async with self._lock:
            self._processes.clear()


@dataclass
class JobEventBus:
    """Pub/sub system for job events with history buffer for reconnection replay."""
    job_id: str
    event_history: list[dict] = field(default_factory=list)
    max_history: int = 100
    subscribers: dict[str, asyncio.Queue] = field(default_factory=dict)
    final_result: dict | None = None
    is_complete: bool = False
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    _seq: int = 0  # Sequence number for events

    async def publish(self, event: dict):
        """Broadcast event to all subscribers and add to history."""
        async with self._lock:
            # Add sequence number to event
            event_with_seq = {**event, "_seq": self._seq}
            self._seq += 1

            # Add to history (ring buffer)
            self.event_history.append(event_with_seq)
            if len(self.event_history) > self.max_history:
                self.event_history.pop(0)

            # Capture final result from complete event
            if event.get("event") == "complete":
                self.final_result = event.get("data", {})

            # Broadcast to all subscribers
            for queue in self.subscribers.values():
                try:
                    queue.put_nowait(event_with_seq)
                except asyncio.QueueFull:
                    pass  # Skip if queue is full

    async def subscribe(self, subscriber_id: str) -> asyncio.Queue:
        """Create a subscriber queue and return it."""
        async with self._lock:
            queue = asyncio.Queue(maxsize=100)
            self.subscribers[subscriber_id] = queue
            return queue

    async def unsubscribe(self, subscriber_id: str):
        """Remove a subscriber."""
        async with self._lock:
            self.subscribers.pop(subscriber_id, None)

    async def get_history_since(self, seq: int = 0) -> list[dict]:
        """Get events since a sequence number for replay."""
        async with self._lock:
            return [e for e in self.event_history if e.get("_seq", 0) >= seq]

    async def complete(self):
        """Mark job as complete and send sentinel to all subscribers."""
        async with self._lock:
            self.is_complete = True
            # Send None as sentinel to signal completion
            for queue in self.subscribers.values():
                try:
                    queue.put_nowait(None)
                except asyncio.QueueFull:
                    pass


@dataclass
class Job:
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
    # Extended fields for persistence
    model: str = "small"
    prompt: str | None = None  # For summarize jobs
    sections: list[str] | None = None
    context: str | None = None  # For summarize jobs
    # Runtime fields (not persisted)
    logger: JobLogger | None = field(default=None, repr=False)
    event_bus: JobEventBus | None = field(default=None, repr=False)
    background_task: asyncio.Task | None = field(default=None, repr=False)
    result_content: str | None = field(default=None, repr=False)  # Final transcript/summary text
    result_path: str | None = field(default=None, repr=False)  # Where result was saved


# Global registries
active_jobs: dict[str, Job] = {}
cleanup_tasks: set[asyncio.Task] = set()  # Track cleanup tasks for shutdown
job_semaphore = asyncio.Semaphore(1)  # Only one job processes at a time
process_registry = ProcessRegistry()
shutdown_event = asyncio.Event()

# Timeouts (seconds)
VIDEO_INFO_TIMEOUT = 30
DOWNLOAD_TIMEOUT = 600  # 10 minutes
FFMPEG_TIMEOUT = 120    # 2 minutes

# Logging
def log(msg: str):
    print(f"[yt-transcribe] {msg}", flush=True)


def load_persisted_jobs() -> list[Job]:
    """Load incomplete jobs from disk on startup."""
    recovered = []
    if not JOBS_DIR.exists():
        return recovered

    for job_file in JOBS_DIR.glob("*.json"):
        try:
            data = json.loads(job_file.read_text())
            job = job_from_dict(data)
            # Only recover incomplete jobs
            if job.state not in (JobState.COMPLETE, JobState.ERROR):
                job.state = JobState.PENDING  # Reset to pending for restart
                job.progress = 0.0
                active_jobs[job.id] = job
                recovered.append(job)
                log(f"Recovered job {job.id} ({job.job_type.value}) for {job.url}")
        except Exception as e:
            log(f"Failed to load job from {job_file}: {e}")
    return recovered


async def restart_job(job: Job):
    """Restart a recovered job using the background task runner."""
    # Create a new logger and event bus for the restarted job
    job.logger = JobLogger(job.id, job.job_type.value, LOGS_DIR)
    job.event_bus = JobEventBus(job_id=job.id)
    job.logger.info(f"Restarting job (recovered from persistence)")

    # Run in background
    job.background_task = asyncio.create_task(run_job_background(job))

    # Schedule cleanup after job completes
    schedule_cleanup(job)


async def run_job_background(job: Job):
    """Execute job independently, publish events to event bus."""
    if not job.event_bus:
        job.event_bus = JobEventBus(job_id=job.id)

    try:
        # Check if we need to queue (for initial status)
        if job_semaphore.locked():
            job.state = JobState.QUEUED
            persist_job(job)
            if job.logger:
                job.logger.info("Job queued, waiting for semaphore")
            await job.event_bus.publish({"event": "queued", "data": {"message": "Waiting for other jobs to complete"}})

        async with job_semaphore:
            if shutdown_event.is_set():
                if job.logger:
                    job.logger.info("Shutdown requested, aborting job")
                job.state = JobState.INTERRUPTED
                persist_job(job)
                await job.event_bus.publish({"event": "interrupted", "data": {"message": "Server shutting down"}})
                return

            try:
                if job.job_type == JobType.TRANSCRIBE:
                    stream = transcribe_stream(job.url, job.model, job.sections, job)
                else:
                    stream = summarize_stream(job.url, job.model, job.prompt or DEFAULT_SUMMARY_PROMPT, job.sections, job.context, job)

                async for event in stream:
                    await job.event_bus.publish(event)

                    # Capture final result from complete event
                    if event.get("event") == "complete":
                        data = event.get("data", {})
                        job.result_content = data.get("transcript") or data.get("summary")
                        job.result_path = data.get("saved_to")

            except asyncio.CancelledError:
                # Shutdown - mark interrupted
                job.state = JobState.INTERRUPTED
                persist_job(job)
                if job.logger:
                    job.logger.info("Job cancelled")
                await job.event_bus.publish({"event": "interrupted", "data": {"message": "Job cancelled"}})
                raise

    except asyncio.CancelledError:
        raise
    except Exception as e:
        job.state = JobState.ERROR
        job.error = str(e)
        job.completed_at = datetime.now()
        persist_job(job)
        if job.logger:
            job.logger.error(f"Background job failed: {e}")
        await job.event_bus.publish({"event": "error", "data": {"message": str(e)}})
    finally:
        await job.event_bus.complete()


async def subscribe_to_job(job: Job, replay_from: int = 0) -> AsyncGenerator[dict, None]:
    """Subscribe to job events - client disconnect doesn't affect job."""
    subscriber_id = uuid.uuid4().hex[:8]

    # 1. Send job ID
    yield {"event": "job", "data": json.dumps({"job_id": job.id})}

    if not job.event_bus:
        yield {"event": "error", "data": json.dumps({"message": "Job has no event bus"})}
        return

    # 2. Replay missed events if reconnecting
    if replay_from > 0:
        history = await job.event_bus.get_history_since(replay_from)
        for event in history:
            event_type = event.get("event", "message")
            data = event.get("data", event)
            # Strip internal _seq from data
            if isinstance(data, dict):
                data = {k: v for k, v in data.items() if k != "_seq"}
            yield {"event": event_type, "data": json.dumps(data), "id": str(event.get("_seq", 0))}

    # 3. If job complete, send final result and return
    if job.event_bus.is_complete:
        if job.event_bus.final_result:
            yield {"event": "complete", "data": json.dumps(job.event_bus.final_result)}
        return

    # 4. Subscribe to live events
    queue = await job.event_bus.subscribe(subscriber_id)

    try:
        while True:
            try:
                # Wait for event with timeout for keep-alive pings
                event = await asyncio.wait_for(queue.get(), timeout=3.0)

                # Sentinel value means job is complete
                if event is None:
                    break

                event_type = event.get("event", "message")
                data = event.get("data", event)
                # Strip internal _seq from data
                if isinstance(data, dict):
                    data = {k: v for k, v in data.items() if k != "_seq"}
                yield {"event": event_type, "data": json.dumps(data), "id": str(event.get("_seq", 0))}

            except asyncio.TimeoutError:
                # Send keep-alive ping
                yield {"event": "ping", "data": json.dumps({"status": job.state.value, "progress": job.progress})}

    except asyncio.CancelledError:
        # Client disconnected - job keeps running
        if job.logger:
            job.logger.info(f"Subscriber {subscriber_id} disconnected")
    finally:
        await job.event_bus.unsubscribe(subscriber_id)


async def cleanup_job_after_completion(job: Job):
    """Clean up job after completion - waits for job and gives time for status queries."""
    try:
        # Wait for background task to complete
        if job.background_task:
            try:
                await job.background_task
            except asyncio.CancelledError:
                pass
            except Exception:
                pass  # Error already handled in run_job_background

        # Wait for subscribers to disconnect (with timeout), respecting shutdown
        if job.event_bus:
            for _ in range(60):  # Wait up to 60 seconds
                if not job.event_bus.subscribers or shutdown_event.is_set():
                    break
                await asyncio.sleep(1)

        # Keep job in registry for status queries (but abort on shutdown)
        if job.state in (JobState.COMPLETE, JobState.ERROR, JobState.INTERRUPTED):
            # Sleep in small increments to allow quick shutdown
            for _ in range(300):  # 5 minutes total
                if shutdown_event.is_set():
                    break
                await asyncio.sleep(1)
            active_jobs.pop(job.id, None)
            delete_persisted_job(job.id)
            if job.logger:
                job.logger.info("Job cleaned up from registry")
    except asyncio.CancelledError:
        # Shutdown cancelled us - clean up immediately
        active_jobs.pop(job.id, None)
        raise


def schedule_cleanup(job: Job):
    """Schedule a cleanup task and track it for shutdown."""
    task = asyncio.create_task(cleanup_job_after_completion(job))
    cleanup_tasks.add(task)
    task.add_done_callback(cleanup_tasks.discard)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: startup and shutdown."""
    # Startup
    log("Starting YouTube Transcribe Server")
    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    SUMMARIES_DIR.mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    JOBS_DIR.mkdir(parents=True, exist_ok=True)

    # Load and restart persisted jobs
    recovered_jobs = load_persisted_jobs()
    for job in recovered_jobs:
        asyncio.create_task(restart_job(job))

    yield

    # Shutdown
    log("Shutting down...")
    shutdown_event.set()

    # Cancel background tasks and mark in-progress jobs as interrupted
    for job in active_jobs.values():
        if job.state not in (JobState.COMPLETE, JobState.ERROR, JobState.INTERRUPTED):
            job.state = JobState.INTERRUPTED
            persist_job(job)
            if job.logger:
                job.logger.info("Job interrupted by server shutdown")
            # Cancel background task
            if job.background_task and not job.background_task.done():
                job.background_task.cancel()
            # Signal completion to any subscribers
            if job.event_bus:
                await job.event_bus.publish({"event": "interrupted", "data": {"message": "Server shutting down"}})
                await job.event_bus.complete()

    # Wait briefly for background tasks to cancel
    tasks_to_wait = [job.background_task for job in active_jobs.values() if job.background_task and not job.background_task.done()]
    if tasks_to_wait:
        await asyncio.gather(*tasks_to_wait, return_exceptions=True)

    # Cancel cleanup tasks (they check shutdown_event but we cancel for safety)
    for task in list(cleanup_tasks):
        if not task.done():
            task.cancel()
    if cleanup_tasks:
        await asyncio.gather(*cleanup_tasks, return_exceptions=True)

    # Kill all subprocesses
    await process_registry.kill_all()
    log("Shutdown complete")


app = FastAPI(title="YouTube Transcribe Server", version="1.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TEMP_DIR = Path("/tmp/youtube-transcribe")
TEMP_DIR.mkdir(exist_ok=True)

STORAGE_DIR = Path.home() / "Cloud" / "ytdl" / "server"
TRANSCRIPTS_DIR = STORAGE_DIR / "transcripts"
SUMMARIES_DIR = STORAGE_DIR / "summaries"

# State data (jobs, logs) goes in ~/.local/state per XDG spec
STATE_DIR = Path.home() / ".local" / "state" / "youtube-transcribe"
LOGS_DIR = STATE_DIR / "logs"
JOBS_DIR = STATE_DIR / "jobs"

TRANSCRIBE_SCRIPT = Path.home() / "dotfiles" / "bin" / "transcribe"
DEFAULT_MODEL = "small"


def slugify(text: str) -> str:
    """Convert text to a safe filename slug."""
    text = re.sub(r"[^\w\s-]", "", text.lower())
    return re.sub(r"[-\s]+", "-", text).strip("-")[:50]


def save_content(video_id: str, title: str, content: str, content_type: str) -> Path:
    """Save transcript or summary to storage directory."""
    slug = slugify(title)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{timestamp}_{video_id}_{slug}.txt"

    if content_type == "transcript":
        filepath = TRANSCRIPTS_DIR / filename
    else:
        filepath = SUMMARIES_DIR / filename

    filepath.write_text(content)
    log(f"Saved {content_type} to {filepath}")
    return filepath


class TranscribeRequest(BaseModel):
    url: str
    model: str = DEFAULT_MODEL
    sections: list[str] | None = None  # e.g., ["40:00-45:35", "1:20:00-1:25:00"]


DEFAULT_SUMMARY_PROMPT = """Summarize the provided content in three sections:

## Summary
Provide a concise summary in two paragraphs:
1. **Personal relevance:** How this content connects to my path and what I should take from it
2. **Content summary:** A standalone summary of the main points and key takeaways

## Personal Relevance
Extract what's most relevant to my life path and current focus:

**Core Purpose:** Shepherd-king building a loving family and powerful kingdom rooted in reality, community, and frontier exploration of technology, culture, and consciousness. Creating structures that protect space for play, experimentation, and connection with the divine.

**Key Themes I'm Working With:**
- Sovereignty over duty: joy-first living, rest doesn't need to be earned, heaven is NOW
- Transformation from "good boy" performing for approval to Sacred Sovereign following the flame
- Embodied wisdom over intellectual understanding—must live it before teaching it
- VR psychodrama and techno-shamanic work through Creative Heartbeats
- Integration of programmer, mystic, healer, teacher, and revolutionary
- Physical/mental/spiritual health as sacred foundation
- Men's academy, alchemical circles, art of transformation
- Archetypal work: Odin, Freya, Kali, Shakti-Lila, Dionysian masculine

**Current Focus Areas:** Health (body as teacher), sanctuary/automation tools, creative expression, family healing, attention sovereignty

For this section, be selective—only include genuinely relevant insights. If nothing connects meaningfully, say so briefly.

## Deep Dive
Provide a more detailed exploration of the content. Choose whatever format best serves the material—this might be a structured breakdown of key arguments, a timeline of events, annotated quotes, a concept map, technical details, or something else entirely. Let the content dictate the form.

---- END OF SUMMARY SECTIONS ----

## Formatting Guidelines
- No markdown tables (broken on mobile)—use lists or prose instead """


class SummarizeRequest(BaseModel):
    url: str
    model: str = DEFAULT_MODEL
    prompt: str = DEFAULT_SUMMARY_PROMPT
    sections: list[str] | None = None  # e.g., ["40:00-45:35", "1:20:00-1:25:00"]
    context: str | None = None  # Additional context to append to the prompt


def parse_timestamp(ts: str) -> float:
    """Parse '00:05.000' or '01:30.500' to seconds."""
    parts = ts.split(":")
    if len(parts) == 2:
        minutes, seconds = parts
        return int(minutes) * 60 + float(seconds)
    return 0.0


def extract_video_id(url: str) -> str | None:
    """Extract video ID from various YouTube URL formats."""
    patterns = [
        r"(?:v=|/v/|/video/|youtu\.be/|/embed/|/shorts/)([a-zA-Z0-9_-]{11})",
        r"^([a-zA-Z0-9_-]{11})$",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


def find_cached_transcript(video_id: str) -> tuple[Path, str] | None:
    """Find an existing transcript for a video_id. Returns (path, content) or None."""
    # Transcripts are saved as: {timestamp}_{video_id}_{slug}.txt
    matches = list(TRANSCRIPTS_DIR.glob(f"*_{video_id}_*.txt"))
    if matches:
        # Return the most recent one (highest timestamp)
        latest = max(matches, key=lambda p: p.name)
        log(f"Found cached transcript: {latest}")
        return latest, latest.read_text()
    return None


# Job persistence functions
def job_to_dict(job: Job) -> dict:
    """Serialize job state for persistence."""
    return {
        "id": job.id,
        "job_type": job.job_type.value,
        "url": job.url,
        "video_id": job.video_id,
        "title": job.title,
        "state": job.state.value,
        "progress": job.progress,
        "error": job.error,
        "started_at": job.started_at.isoformat(),
        "completed_at": job.completed_at.isoformat() if job.completed_at else None,
        "model": job.model,
        "prompt": job.prompt,
        "sections": job.sections,
        "context": job.context,
    }


def job_from_dict(data: dict) -> Job:
    """Deserialize job state from persistence."""
    return Job(
        id=data["id"],
        job_type=JobType(data["job_type"]),
        url=data["url"],
        video_id=data.get("video_id"),
        title=data.get("title"),
        state=JobState(data["state"]),
        progress=data.get("progress", 0.0),
        error=data.get("error"),
        started_at=datetime.fromisoformat(data["started_at"]),
        completed_at=datetime.fromisoformat(data["completed_at"]) if data.get("completed_at") else None,
        model=data.get("model", DEFAULT_MODEL),
        prompt=data.get("prompt"),
        sections=data.get("sections"),
        context=data.get("context"),
    )


def persist_job(job: Job):
    """Save job state to JOBS_DIR/{job_id}.json"""
    job_path = JOBS_DIR / f"{job.id}.json"
    job_path.write_text(json.dumps(job_to_dict(job), indent=2))


def delete_persisted_job(job_id: str):
    """Remove job file after completion cleanup."""
    job_path = JOBS_DIR / f"{job_id}.json"
    job_path.unlink(missing_ok=True)


def read_job_logs(job_id: str, tail: int = 50) -> list[str]:
    """Read logs for a job (even without Job object)."""
    log_path = LOGS_DIR / f"{job_id}.log"
    if not log_path.exists():
        return []
    lines = log_path.read_text().splitlines()
    return lines[-tail:] if len(lines) > tail else lines


async def get_video_info(url: str, job: Job | None = None) -> dict:
    """Fetch video metadata using yt-dlp with timeout."""
    log(f"Fetching video info for {url}")
    if job and job.logger:
        job.logger.info(f"Fetching video info for {url}")

    proc = await asyncio.create_subprocess_exec(
        "yt-dlp",
        "--dump-json",
        "--no-download",
        url,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
    )

    if job:
        await process_registry.register(proc, job.id)
        if job.logger:
            job.logger.info(f"Spawned yt-dlp (PID {proc.pid}) for video info")

    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=VIDEO_INFO_TIMEOUT
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise Exception(f"Timed out fetching video info after {VIDEO_INFO_TIMEOUT}s")
    finally:
        if job:
            await process_registry.unregister(proc)

    if proc.returncode != 0:
        error_msg = stderr.decode()
        log(f"Failed to get video info: {error_msg}")
        if job and job.logger:
            job.logger.error(f"yt-dlp failed: {error_msg}")
        raise Exception(f"Failed to get video info: {error_msg}")

    info = json.loads(stdout.decode())
    log(f"Video: {info.get('title')} ({info.get('duration')}s)")
    if job and job.logger:
        job.logger.info(f"Video: {info.get('title')} ({info.get('duration')}s)")
    return info


def parse_section_time(ts: str) -> float:
    """Parse section timestamp like '40:00' or '1:30:00' to seconds."""
    parts = ts.split(":")
    if len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    elif len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    return float(ts)


async def download_audio(
    url: str, output_path: Path, job: Job | None = None
) -> AsyncGenerator[dict, None]:
    """Download full audio and yield progress updates with timeout."""
    cmd = [
        "yt-dlp",
        "-x",
        "--audio-format", "m4a",
        "--newline",
        "--progress",
        "-o", str(output_path),
        url,
    ]

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
    )

    if job:
        await process_registry.register(proc, job.id)
        if job.logger:
            job.logger.info(f"Spawned yt-dlp (PID {proc.pid}) for audio download")

    progress_pattern = re.compile(
        r"\[download\]\s+(\d+\.?\d*)%\s+of.*?at\s+(\S+)\s+ETA\s+(\S+)"
    )
    extract_pattern = re.compile(r"\[ExtractAudio\]")

    last_logged = 0
    start_time = asyncio.get_event_loop().time()
    extracting = False

    try:
        async for line in proc.stdout:
            # Check timeout
            if asyncio.get_event_loop().time() - start_time > DOWNLOAD_TIMEOUT:
                proc.kill()
                await proc.wait()
                raise Exception(f"Download timed out after {DOWNLOAD_TIMEOUT}s")

            # Check shutdown
            if shutdown_event.is_set():
                proc.terminate()
                await proc.wait()
                raise Exception("Server shutting down")

            line = line.decode().strip()
            if job and job.logger:
                job.logger.subprocess_output("yt-dlp", line)

            # Check for audio extraction phase
            if extract_pattern.search(line) and not extracting:
                extracting = True
                log("Extracting audio...")
                if job:
                    job.state = JobState.EXTRACTING
                    persist_job(job)
                yield {"event": "extracting_audio", "status": "extracting audio from video"}
                continue

            match = progress_pattern.search(line)
            if match:
                percent = float(match.group(1))
                speed = match.group(2)
                eta = match.group(3)
                # Log every 10%
                if int(percent / 10) > last_logged:
                    last_logged = int(percent / 10)
                    log(f"Download: {percent:.0f}% at {speed}, ETA {eta}")
                yield {
                    "percent": percent,
                    "speed": speed,
                    "eta": eta,
                }

        await proc.wait()
        if proc.returncode != 0:
            if job and job.logger:
                job.logger.error("Download failed")
            raise Exception("Download failed")
        log(f"Download complete: {output_path.name}")
        if job and job.logger:
            job.logger.info(f"Download complete: {output_path.name}")
    finally:
        if job:
            await process_registry.unregister(proc)


async def extract_sections(audio_path: Path, sections: list[str], job: Job | None = None) -> Path:
    """Extract and concatenate sections from audio file with timeout. Returns path to extracted audio."""
    output_path = audio_path.parent / f"{audio_path.stem}_sections.m4a"
    temp_parts = []

    for i, section in enumerate(sections):
        start, end = section.split("-")
        start_sec = parse_section_time(start)
        end_sec = parse_section_time(end)
        duration = end_sec - start_sec

        part_path = audio_path.parent / f"{audio_path.stem}_part{i}.m4a"
        temp_parts.append(part_path)

        log(f"Extracting section {i+1}/{len(sections)}: {section}")
        if job and job.logger:
            job.logger.info(f"Extracting section {i+1}/{len(sections)}: {section}")

        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y",
            "-i", str(audio_path),
            "-ss", str(start_sec),
            "-t", str(duration),
            "-c", "copy",
            str(part_path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        if job:
            await process_registry.register(proc, job.id)
            if job.logger:
                job.logger.info(f"Spawned ffmpeg (PID {proc.pid}) for section extraction")

        try:
            await asyncio.wait_for(proc.wait(), timeout=FFMPEG_TIMEOUT)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise Exception(f"FFmpeg timed out extracting section {section}")
        finally:
            if job:
                await process_registry.unregister(proc)

        if proc.returncode != 0:
            raise Exception(f"Failed to extract section {section}")

    # Concatenate parts if multiple sections
    if len(temp_parts) == 1:
        temp_parts[0].rename(output_path)
    else:
        concat_file = audio_path.parent / "concat.txt"
        concat_file.write_text("\n".join(f"file '{p}'" for p in temp_parts))

        proc = await asyncio.create_subprocess_exec(
            "ffmpeg", "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_file),
            "-c", "copy",
            str(output_path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        if job:
            await process_registry.register(proc, job.id)
            if job.logger:
                job.logger.info(f"Spawned ffmpeg (PID {proc.pid}) for concatenation")

        try:
            await asyncio.wait_for(proc.wait(), timeout=FFMPEG_TIMEOUT)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            concat_file.unlink(missing_ok=True)
            for p in temp_parts:
                p.unlink(missing_ok=True)
            raise Exception("FFmpeg timed out concatenating sections")
        finally:
            if job:
                await process_registry.unregister(proc)

        concat_file.unlink()
        for p in temp_parts:
            p.unlink()

        if proc.returncode != 0:
            raise Exception("Failed to concatenate sections")

    if job and job.logger:
        job.logger.info(f"Section extraction complete: {output_path.name}")
    return output_path


async def transcribe_audio(
    audio_path: Path, model: str, duration: float, job: Job | None = None
) -> AsyncGenerator[dict, None]:
    """Transcribe audio using MLX Whisper and yield progress updates."""
    yield {"status": "loading model", "model": model}
    if job and job.logger:
        job.logger.info(f"Loading model: {model}")

    proc = await asyncio.create_subprocess_exec(
        str(TRANSCRIBE_SCRIPT),
        str(audio_path),
        "-m", model,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,  # Combine stderr into stdout for verbose output
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
    )

    if job:
        await process_registry.register(proc, job.id)
        if job.logger:
            job.logger.info(f"Spawned transcribe (PID {proc.pid})")

    # Pattern: [00:00.000 --> 00:05.000] text
    timestamp_pattern = re.compile(r"\[(\d+:\d+\.\d+)\s*-->\s*(\d+:\d+\.\d+)\]")
    last_reported_bucket = -1  # Throttle: only emit once per 5% bucket

    try:
        async for line in proc.stdout:
            # Check shutdown
            if shutdown_event.is_set():
                proc.terminate()
                await proc.wait()
                raise Exception("Server shutting down")

            line = line.decode().strip()
            if job and job.logger:
                job.logger.subprocess_output("transcribe", line)
            match = timestamp_pattern.search(line)
            if match:
                end_time = parse_timestamp(match.group(2))
                percent = min(100, (end_time / duration) * 100) if duration > 0 else 0
                bucket = int(percent // 5)
                if bucket > last_reported_bucket:
                    last_reported_bucket = bucket
                    yield {"status": "transcribing", "percent": round(percent, 1), "timestamp": match.group(2)}

        await proc.wait()

        if proc.returncode != 0:
            if job and job.logger:
                job.logger.error("Transcription failed")
            raise Exception("Transcription failed")

        # Read the transcript file created by the transcribe script
        transcript_path = audio_path.parent / f"{audio_path.name}.transcript.txt"
        if transcript_path.exists():
            transcript_text = transcript_path.read_text()
            transcript_path.unlink()  # Clean up transcript file
            if job and job.logger:
                job.logger.info("Transcription complete")
            yield {"status": "complete", "transcript": transcript_text}
        else:
            raise Exception("Transcript file not created")
    finally:
        if job:
            await process_registry.unregister(proc)


async def transcribe_stream(
    url: str, model: str, sections: list[str] | None = None, job: Job | None = None
) -> AsyncGenerator[dict, None]:
    """Main transcription pipeline with SSE events and job tracking."""
    video_id = extract_video_id(url)
    if not video_id:
        log(f"Invalid YouTube URL: {url}")
        if job:
            job.state = JobState.ERROR
            job.error = "Invalid YouTube URL"
            job.completed_at = datetime.now()
        yield {"event": "error", "data": {"message": "Invalid YouTube URL"}}
        return

    if job:
        job.video_id = video_id

    sections_desc = f" sections={sections}" if sections else ""
    log(f"Starting transcription for {video_id}{sections_desc}")

    # Check for cached transcript (skip cache for partial transcripts)
    cached = find_cached_transcript(video_id) if not sections else None
    if cached:
        cached_path, transcript_text = cached
        log(f"Using cached transcript for {video_id}")
        if job:
            job.state = JobState.COMPLETE
            job.progress = 100.0
            job.completed_at = datetime.now()
        yield {
            "event": "cached",
            "data": {
                "video_id": video_id,
                "cached_from": str(cached_path),
            },
        }
        yield {
            "event": "complete",
            "data": {"transcript": transcript_text, "saved_to": str(cached_path), "cached": True},
        }
        return

    try:
        # Get video info
        info = await get_video_info(url, job)
        title = info.get("title", "Unknown")
        if job:
            job.title = title
            persist_job(job)
        yield {
            "event": "started",
            "data": {
                "video_id": video_id,
                "title": title,
                "duration": info.get("duration", 0),
                "channel": info.get("channel", "Unknown"),
            },
        }

        # Download audio
        if job:
            job.state = JobState.DOWNLOADING
            persist_job(job)
        audio_path = TEMP_DIR / f"{video_id}.m4a"
        sections_path = None
        try:
            log(f"Downloading audio for {video_id}")
            async for progress in download_audio(url, audio_path, job):
                # Check if it's the extraction event (already has "event" key)
                if "event" in progress:
                    yield progress
                else:
                    if job:
                        job.progress = progress.get("percent", 0) * 0.3  # Download is ~30% of total
                    yield {"event": "downloading", "data": progress}

            yield {
                "event": "downloading",
                "data": {"percent": 100, "speed": "-", "eta": "0s"},
            }

            # Extract sections if specified
            transcribe_path = audio_path
            if sections:
                if job:
                    job.state = JobState.EXTRACTING
                    persist_job(job)
                yield {"event": "extracting", "data": {"status": "extracting sections"}}
                sections_path = await extract_sections(audio_path, sections, job)
                transcribe_path = sections_path

            # Transcribe
            if job:
                job.state = JobState.TRANSCRIBING
                persist_job(job)
            log(f"Transcribing {video_id} with model {model}")
            duration = info.get("duration", 0)
            transcript_text = ""
            async for update in transcribe_audio(transcribe_path, model, duration, job):
                if update.get("status") == "complete":
                    transcript_text = update["transcript"]
                    if job:
                        job.state = JobState.COMPLETE
                        job.progress = 100.0
                        job.completed_at = datetime.now()
                        persist_job(job)
                    # Don't save partial transcripts to cache
                    if not sections:
                        saved_path = save_content(video_id, title, transcript_text, "transcript")
                        log(f"Transcription complete for {video_id}")
                        yield {
                            "event": "complete",
                            "data": {"transcript": transcript_text, "saved_to": str(saved_path)},
                        }
                    else:
                        log(f"Partial transcription complete for {video_id}")
                        yield {
                            "event": "complete",
                            "data": {"transcript": transcript_text, "sections": sections},
                        }
                else:
                    if job:
                        # Transcription is 30-100% of total progress
                        job.progress = 30 + update.get("percent", 0) * 0.7
                    yield {"event": "transcribing", "data": update}

        finally:
            # Cleanup temp files
            if audio_path.exists():
                audio_path.unlink()
            if sections_path and sections_path.exists():
                sections_path.unlink()

    except Exception as e:
        log(f"Error transcribing {video_id}: {e}")
        if job:
            job.state = JobState.ERROR
            job.error = str(e)
            job.completed_at = datetime.now()
            persist_job(job)
            if job.logger:
                job.logger.error(str(e))
        yield {"event": "error", "data": {"message": str(e)}}


async def run_claude_summary(transcript: str, prompt: str, job: Job | None = None) -> str:
    """Run Claude CLI to summarize transcript."""
    # Combine prompt and transcript into single message for stdin
    user_message = f"{prompt}\n\n---\n\nTranscript:\n\n{transcript}"

    if job and job.logger:
        job.logger.info("Starting Claude summarization")

    proc = await asyncio.create_subprocess_exec(
        "claude",
        "-p",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    if job:
        await process_registry.register(proc, job.id)
        if job.logger:
            job.logger.info(f"Spawned claude (PID {proc.pid})")

    try:
        stdout, stderr = await proc.communicate(input=user_message.encode())
    finally:
        if job:
            await process_registry.unregister(proc)

    if proc.returncode != 0:
        error_msg = stderr.decode()[:500]
        log(f"Claude stderr: {error_msg}")
        if job and job.logger:
            job.logger.error(f"Claude failed: {error_msg}")
        raise Exception(f"Claude summarization failed: {stderr.decode()}")

    result = stdout.decode().strip()
    if not result:
        error_msg = stderr.decode()[:500]
        log(f"Claude returned empty response. stderr: {error_msg}")
        if job and job.logger:
            job.logger.error(f"Claude returned empty: {error_msg}")
        raise Exception("Claude returned empty response - possible API timeout or rate limit")

    if job and job.logger:
        job.logger.info("Claude summarization complete")
    return result


async def summarize_stream(
    url: str, model: str, prompt: str, sections: list[str] | None = None, context: str | None = None, job: Job | None = None
) -> AsyncGenerator[dict, None]:
    """Transcribe and summarize a YouTube video with job tracking."""
    video_id = extract_video_id(url)
    if not video_id:
        log(f"Invalid YouTube URL: {url}")
        if job:
            job.state = JobState.ERROR
            job.error = "Invalid YouTube URL"
            job.completed_at = datetime.now()
            persist_job(job)
            if job.logger:
                job.logger.error("Invalid YouTube URL")
        yield {"event": "error", "data": {"message": "Invalid YouTube URL"}}
        return

    if job:
        job.video_id = video_id
        persist_job(job)

    # Append user context to prompt if provided
    if context:
        prompt = f"{prompt}\n\n## Additional Context\n{context}"

    sections_desc = f" sections={sections}" if sections else ""
    log(f"Starting summarization for {video_id}{sections_desc}")
    if job and job.logger:
        job.logger.info(f"Starting summarization for {video_id}{sections_desc}")

    try:
        # Check for cached transcript (skip cache for partial transcripts)
        cached = find_cached_transcript(video_id) if not sections else None
        if cached:
            cached_path, transcript_text = cached
            log(f"Using cached transcript for {video_id}")
            if job and job.logger:
                job.logger.info(f"Using cached transcript: {cached_path}")

            # Still need video info for title
            info = await get_video_info(url, job)
            title = info.get("title", "Unknown")
            if job:
                job.title = title
                job.progress = 80.0  # Skip to summarizing
                persist_job(job)

            yield {
                "event": "cached",
                "data": {
                    "video_id": video_id,
                    "title": title,
                    "cached_from": str(cached_path),
                },
            }
        else:
            # Get video info
            info = await get_video_info(url, job)
            title = info.get("title", "Unknown")
            if job:
                job.title = title
                persist_job(job)
            yield {
                "event": "started",
                "data": {
                    "video_id": video_id,
                    "title": title,
                    "duration": info.get("duration", 0),
                    "channel": info.get("channel", "Unknown"),
                },
            }

            # Download audio
            if job:
                job.state = JobState.DOWNLOADING
                persist_job(job)
            audio_path = TEMP_DIR / f"{video_id}.m4a"
            sections_path = None
            try:
                log(f"Downloading audio for {video_id}")
                async for progress in download_audio(url, audio_path, job):
                    # Check if it's the extraction event (already has "event" key)
                    if "event" in progress:
                        yield progress
                    else:
                        if job:
                            job.progress = progress.get("percent", 0) * 0.25  # Download is ~25% of total
                        yield {"event": "downloading", "data": progress}

                yield {
                    "event": "downloading",
                    "data": {"percent": 100, "speed": "-", "eta": "0s"},
                }

                # Extract sections if specified
                transcribe_path = audio_path
                if sections:
                    if job:
                        job.state = JobState.EXTRACTING
                        persist_job(job)
                    yield {"event": "extracting", "data": {"status": "extracting sections"}}
                    sections_path = await extract_sections(audio_path, sections, job)
                    transcribe_path = sections_path

                # Transcribe
                if job:
                    job.state = JobState.TRANSCRIBING
                    persist_job(job)
                log(f"Transcribing {video_id} with model {model}")
                duration = info.get("duration", 0)
                transcript_text = ""
                async for update in transcribe_audio(transcribe_path, model, duration, job):
                    if update.get("status") == "complete":
                        transcript_text = update["transcript"]
                        # Don't save partial transcripts to cache
                        if not sections:
                            save_content(video_id, title, transcript_text, "transcript")
                    else:
                        if job:
                            # Transcription is 25-80% of total progress
                            job.progress = 25 + update.get("percent", 0) * 0.55
                        yield {"event": "transcribing", "data": update}

            finally:
                # Cleanup temp files
                if audio_path.exists():
                    audio_path.unlink()
                if sections_path and sections_path.exists():
                    sections_path.unlink()

        # Summarize with Claude
        if job:
            job.state = JobState.SUMMARIZING
            job.progress = 80.0
            persist_job(job)
        log(f"Summarizing {video_id} with Claude")
        yield {"event": "summarizing", "data": {"status": "running claude"}}
        summary = await run_claude_summary(transcript_text, prompt, job)

        # Save summary
        saved_path = save_content(video_id, title, summary, "summary")
        if job:
            job.state = JobState.COMPLETE
            job.progress = 100.0
            job.completed_at = datetime.now()
            persist_job(job)
            if job.logger:
                job.logger.info(f"Summarization complete, saved to {saved_path}")
        log(f"Summarization complete for {video_id}")
        yield {"event": "complete", "data": {"summary": summary, "saved_to": str(saved_path)}}

    except Exception as e:
        log(f"Error summarizing {video_id}: {e}")
        if job:
            job.state = JobState.ERROR
            job.error = str(e)
            job.completed_at = datetime.now()
            persist_job(job)
            if job.logger:
                job.logger.error(str(e))
        yield {"event": "error", "data": {"message": str(e)}}


@app.post("/transcribe")
async def transcribe(request: TranscribeRequest):
    """Transcribe a YouTube video and stream progress via SSE."""
    # Create job for tracking
    job_id = uuid.uuid4().hex[:8]
    job = Job(
        id=job_id,
        job_type=JobType.TRANSCRIBE,
        url=request.url,
        model=request.model,
        sections=request.sections,
    )
    job.logger = JobLogger(job_id, "transcribe", LOGS_DIR)
    job.event_bus = JobEventBus(job_id=job_id)
    job.logger.info(f"Job created for URL: {request.url}")
    active_jobs[job_id] = job
    persist_job(job)

    # Spawn background task to run the job
    job.background_task = asyncio.create_task(run_job_background(job))

    # Schedule cleanup after job completes
    schedule_cleanup(job)

    # Return SSE subscription
    return EventSourceResponse(subscribe_to_job(job))


@app.post("/summarize")
async def summarize(request: SummarizeRequest):
    """Transcribe and summarize a YouTube video via SSE."""
    # Create job for tracking
    job_id = uuid.uuid4().hex[:8]
    job = Job(
        id=job_id,
        job_type=JobType.SUMMARIZE,
        url=request.url,
        model=request.model,
        prompt=request.prompt,
        sections=request.sections,
        context=request.context,
    )
    job.logger = JobLogger(job_id, "summarize", LOGS_DIR)
    job.event_bus = JobEventBus(job_id=job_id)
    job.logger.info(f"Job created for URL: {request.url}")
    active_jobs[job_id] = job
    persist_job(job)

    # Spawn background task to run the job
    job.background_task = asyncio.create_task(run_job_background(job))

    # Schedule cleanup after job completes
    schedule_cleanup(job)

    # Return SSE subscription
    return EventSourceResponse(subscribe_to_job(job))


@app.get("/subscribe/{job_id}")
async def subscribe_to_existing_job(job_id: str, from_seq: int = Query(0, description="Sequence number to replay from")):
    """Reconnect to an existing job's SSE stream."""
    job = active_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if not job.event_bus:
        raise HTTPException(status_code=400, detail="Job has no event bus")
    return EventSourceResponse(subscribe_to_job(job, replay_from=from_seq))


@app.get("/status/{job_id}")
async def get_job_status(job_id: str, include_result: bool = Query(False, description="Include result content for completed jobs")):
    """Get status of a transcribe/summarize job."""
    job = active_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    response = {
        "id": job.id,
        "type": job.job_type.value,
        "state": job.state.value,
        "progress": job.progress,
        "video_id": job.video_id,
        "title": job.title,
        "url": job.url,
        "started_at": job.started_at.isoformat(),
        "completed_at": job.completed_at.isoformat() if job.completed_at else None,
        "error": job.error,
        "result_path": job.result_path,
    }
    # Include result content if requested and job is complete
    if include_result and job.state == JobState.COMPLETE and job.result_content:
        response["result_content"] = job.result_content
    return response


@app.get("/health")
async def health(logs: bool = Query(False, description="Include job logs"), tail: int = Query(20, description="Number of log lines")):
    """Health check with active job info."""
    running = []
    for j in active_jobs.values():
        if j.state not in (JobState.COMPLETE, JobState.ERROR, JobState.INTERRUPTED):
            job_info = {
                "id": j.id,
                "type": j.job_type.value,
                "state": j.state.value,
                "video_id": j.video_id,
                "title": j.title,
                "progress": j.progress,
            }
            if logs:
                job_info["logs"] = read_job_logs(j.id, tail)
            running.append(job_info)
    return {
        "status": "ok",
        "version": "1.2.0",
        "active_jobs": len(running),
        "queue_locked": job_semaphore.locked(),
        "jobs": running,
    }


@app.get("/logs/{job_id}")
async def get_job_logs(job_id: str, tail: int = Query(100, description="Number of log lines to return")):
    """Get logs for a job."""
    log_lines = read_job_logs(job_id, tail)
    if not log_lines:
        raise HTTPException(status_code=404, detail="No logs found for job")
    return {
        "job_id": job_id,
        "lines": len(log_lines),
        "logs": log_lines,
    }


@app.delete("/jobs/{job_id}")
async def kill_job(job_id: str):
    """Kill a specific job and its subprocesses."""
    job = active_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job.state in (JobState.COMPLETE, JobState.ERROR, JobState.INTERRUPTED):
        return {"status": "already_finished", "job_id": job_id, "state": job.state.value}

    log(f"Killing job {job_id}")
    if job.logger:
        job.logger.info("Job killed by user request")

    # Kill subprocesses
    await process_registry.kill_job(job_id)

    # Cancel background task
    if job.background_task and not job.background_task.done():
        job.background_task.cancel()

    # Update job state
    job.state = JobState.INTERRUPTED
    job.error = "Killed by user"
    job.completed_at = datetime.now()
    persist_job(job)

    # Notify subscribers
    if job.event_bus:
        await job.event_bus.publish({"event": "killed", "data": {"message": "Job killed by user"}})
        await job.event_bus.complete()

    return {"status": "killed", "job_id": job_id}


@app.delete("/jobs")
async def kill_all_jobs():
    """Kill all active jobs and their subprocesses."""
    killed = []
    for job_id, job in list(active_jobs.items()):
        if job.state not in (JobState.COMPLETE, JobState.ERROR, JobState.INTERRUPTED):
            log(f"Killing job {job_id}")
            if job.logger:
                job.logger.info("Job killed by user request (kill all)")

            # Cancel background task
            if job.background_task and not job.background_task.done():
                job.background_task.cancel()

            # Update job state
            job.state = JobState.INTERRUPTED
            job.error = "Killed by user (kill all)"
            job.completed_at = datetime.now()
            persist_job(job)

            # Notify subscribers
            if job.event_bus:
                await job.event_bus.publish({"event": "killed", "data": {"message": "Job killed by user"}})
                await job.event_bus.complete()

            killed.append(job_id)

    # Kill all subprocesses
    await process_registry.kill_all()

    return {"status": "killed", "killed_jobs": killed, "count": len(killed)}


@app.get("/")
async def root():
    """Root endpoint with usage info."""
    return {
        "service": "YouTube Transcribe Server",
        "version": "1.2.0",
        "endpoints": {
            "POST /transcribe": "Transcribe a YouTube video (SSE stream, returns job_id)",
            "POST /summarize": "Transcribe and summarize a YouTube video (SSE stream, returns job_id)",
            "GET /subscribe/{job_id}": "Reconnect to existing job's SSE stream (query: from_seq=0)",
            "GET /status/{job_id}": "Get status of a job (query: include_result=false)",
            "GET /logs/{job_id}": "Get logs for a job (query: tail=100)",
            "GET /health": "Health check with active job info (query: logs=true, tail=20)",
            "DELETE /jobs/{job_id}": "Kill a specific job",
            "DELETE /jobs": "Kill all active jobs",
        },
        "example": {
            "url": "https://youtube.com/watch?v=VIDEO_ID",
            "model": "turbo",
            "prompt": "Summarize this transcript concisely",
            "sections": ["40:00-45:35", "1:20:00-1:25:00"],
            "context": "Focus on the business strategy aspects",
        },
        "job_states": ["pending", "queued", "downloading", "extracting", "transcribing", "summarizing", "complete", "error", "interrupted"],
        "features": {
            "per_job_logging": "Each job logs to ~/.local/state/youtube-transcribe/logs/{job_id}.log",
            "job_persistence": "Jobs are persisted to ~/.local/state/youtube-transcribe/jobs/ for restart recovery",
            "graceful_shutdown": "Server kills child processes and marks jobs as interrupted on shutdown",
            "background_execution": "Jobs continue running even if client disconnects",
            "sse_reconnection": "Reconnect to running jobs via GET /subscribe/{job_id}",
        },
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8765))
    log(f"Starting YouTube Transcribe Server on port {port}")
    log(f"Storage: {STORAGE_DIR}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
