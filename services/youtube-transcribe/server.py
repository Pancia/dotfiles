#!/usr/bin/env python3
"""
YouTube Transcribe Server

FastAPI server that accepts YouTube URLs, downloads audio via yt-dlp,
transcribes using MLX Whisper, and streams progress via Server-Sent Events.
"""

import asyncio
import json
import os
import re
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

# Logging
def log(msg: str):
    print(f"[yt-transcribe] {msg}", flush=True)

app = FastAPI(title="YouTube Transcribe Server", version="1.0.0")

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
TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
SUMMARIES_DIR.mkdir(parents=True, exist_ok=True)

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


DEFAULT_SUMMARY_PROMPT = """Summarize this transcript in two sections:

## Summary
Provide a concise summary of the main points and key takeaways.

## Personal Relevance
Extract what's most relevant to my life path and current focus:

Core Purpose: Shepherd-king building a loving family and powerful kingdom rooted in reality, community, and frontier exploration of technology, culture, and consciousness. Creating structures that protect space for play, experimentation, and connection with the divine.

Key Themes I'm Working With:
- Sovereignty over duty: joy-first living, rest doesn't need to be earned, heaven is NOW
- Transformation from "good boy" performing for approval to Sacred Sovereign following the flame
- Embodied wisdom over intellectual understanding - must live it before teaching it
- VR psychodrama and techno-shamanic work through Creative Heartbeats
- Integration of programmer, mystic, healer, teacher, and revolutionary
- Physical/mental/spiritual health as sacred foundation
- Men's academy, alchemical circles, art of transformation
- Archetypal work: Odin, Freya, Kali, Shakti-Lila, Dionysian masculine

Current Focus Areas: health (body as teacher), sanctuary/automation tools, creative expression, family healing, attention sovereignty

For this section, be selective - only include genuinely relevant insights. If nothing connects meaningfully, say so briefly."""


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


async def get_video_info(url: str) -> dict:
    """Fetch video metadata using yt-dlp."""
    log(f"Fetching video info for {url}")
    proc = await asyncio.create_subprocess_exec(
        "yt-dlp",
        "--dump-json",
        "--no-download",
        url,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()

    if proc.returncode != 0:
        log(f"Failed to get video info: {stderr.decode()}")
        raise Exception(f"Failed to get video info: {stderr.decode()}")

    info = json.loads(stdout.decode())
    log(f"Video: {info.get('title')} ({info.get('duration')}s)")
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
    url: str, output_path: Path
) -> AsyncGenerator[dict, None]:
    """Download full audio and yield progress updates."""
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
    )

    progress_pattern = re.compile(
        r"\[download\]\s+(\d+\.?\d*)%\s+of.*?at\s+(\S+)\s+ETA\s+(\S+)"
    )

    last_logged = 0
    async for line in proc.stdout:
        line = line.decode().strip()
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
        raise Exception("Download failed")
    log(f"Download complete: {output_path.name}")


async def extract_sections(audio_path: Path, sections: list[str]) -> Path:
    """Extract and concatenate sections from audio file. Returns path to extracted audio."""
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
        await proc.wait()
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
        await proc.wait()
        concat_file.unlink()
        for p in temp_parts:
            p.unlink()

        if proc.returncode != 0:
            raise Exception("Failed to concatenate sections")

    return output_path


async def transcribe_audio(
    audio_path: Path, model: str, duration: float
) -> AsyncGenerator[dict, None]:
    """Transcribe audio using MLX Whisper and yield progress updates."""
    yield {"status": "loading model", "model": model}

    proc = await asyncio.create_subprocess_exec(
        str(TRANSCRIBE_SCRIPT),
        str(audio_path),
        "-m", model,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,  # Combine stderr into stdout for verbose output
    )

    # Pattern: [00:00.000 --> 00:05.000] text
    timestamp_pattern = re.compile(r"\[(\d+:\d+\.\d+)\s*-->\s*(\d+:\d+\.\d+)\]")

    async for line in proc.stdout:
        line = line.decode().strip()
        match = timestamp_pattern.search(line)
        if match:
            end_time = parse_timestamp(match.group(2))
            percent = min(100, (end_time / duration) * 100) if duration > 0 else 0
            yield {"status": "transcribing", "percent": round(percent, 1), "timestamp": match.group(2)}

    await proc.wait()

    if proc.returncode != 0:
        raise Exception("Transcription failed")

    # Read the transcript file created by the transcribe script
    transcript_path = audio_path.parent / f"{audio_path.name}.transcript.txt"
    if transcript_path.exists():
        transcript_text = transcript_path.read_text()
        transcript_path.unlink()  # Clean up transcript file
        yield {"status": "complete", "transcript": transcript_text}
    else:
        raise Exception("Transcript file not created")


async def transcribe_stream(
    url: str, model: str, sections: list[str] | None = None
) -> AsyncGenerator[dict, None]:
    """Main transcription pipeline with SSE events."""
    video_id = extract_video_id(url)
    if not video_id:
        log(f"Invalid YouTube URL: {url}")
        yield {"event": "error", "data": {"message": "Invalid YouTube URL"}}
        return

    sections_desc = f" sections={sections}" if sections else ""
    log(f"Starting transcription for {video_id}{sections_desc}")

    # Check for cached transcript (skip cache for partial transcripts)
    cached = find_cached_transcript(video_id) if not sections else None
    if cached:
        cached_path, transcript_text = cached
        log(f"Using cached transcript for {video_id}")
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
        info = await get_video_info(url)
        title = info.get("title", "Unknown")
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
        audio_path = TEMP_DIR / f"{video_id}.m4a"
        sections_path = None
        try:
            log(f"Downloading audio for {video_id}")
            async for progress in download_audio(url, audio_path):
                yield {"event": "downloading", "data": progress}

            yield {
                "event": "downloading",
                "data": {"percent": 100, "speed": "-", "eta": "0s"},
            }

            # Extract sections if specified
            transcribe_path = audio_path
            if sections:
                yield {"event": "extracting", "data": {"status": "extracting sections"}}
                sections_path = await extract_sections(audio_path, sections)
                transcribe_path = sections_path

            # Transcribe
            log(f"Transcribing {video_id} with model {model}")
            duration = info.get("duration", 0)
            transcript_text = ""
            async for update in transcribe_audio(transcribe_path, model, duration):
                if update.get("status") == "complete":
                    transcript_text = update["transcript"]
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
                    yield {"event": "transcribing", "data": update}

        finally:
            # Cleanup temp files
            if audio_path.exists():
                audio_path.unlink()
            if sections_path and sections_path.exists():
                sections_path.unlink()

    except Exception as e:
        log(f"Error transcribing {video_id}: {e}")
        yield {"event": "error", "data": {"message": str(e)}}


async def run_claude_summary(transcript: str, prompt: str) -> str:
    """Run Claude CLI to summarize transcript."""
    # Combine prompt and transcript into single message for stdin
    user_message = f"{prompt}\n\n---\n\nTranscript:\n\n{transcript}"

    proc = await asyncio.create_subprocess_exec(
        "claude",
        "-p",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    stdout, stderr = await proc.communicate(input=user_message.encode())

    if proc.returncode != 0:
        log(f"Claude stderr: {stderr.decode()[:500]}")
        raise Exception(f"Claude summarization failed: {stderr.decode()}")

    return stdout.decode()


async def summarize_stream(
    url: str, model: str, prompt: str, sections: list[str] | None = None, context: str | None = None
) -> AsyncGenerator[dict, None]:
    """Transcribe and summarize a YouTube video."""
    video_id = extract_video_id(url)
    if not video_id:
        log(f"Invalid YouTube URL: {url}")
        yield {"event": "error", "data": {"message": "Invalid YouTube URL"}}
        return

    # Append user context to prompt if provided
    if context:
        prompt = f"{prompt}\n\n## Additional Context\n{context}"

    sections_desc = f" sections={sections}" if sections else ""
    log(f"Starting summarization for {video_id}{sections_desc}")

    try:
        # Check for cached transcript (skip cache for partial transcripts)
        cached = find_cached_transcript(video_id) if not sections else None
        if cached:
            cached_path, transcript_text = cached
            log(f"Using cached transcript for {video_id}")

            # Still need video info for title
            info = await get_video_info(url)
            title = info.get("title", "Unknown")

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
            info = await get_video_info(url)
            title = info.get("title", "Unknown")
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
            audio_path = TEMP_DIR / f"{video_id}.m4a"
            sections_path = None
            try:
                log(f"Downloading audio for {video_id}")
                async for progress in download_audio(url, audio_path):
                    yield {"event": "downloading", "data": progress}

                yield {
                    "event": "downloading",
                    "data": {"percent": 100, "speed": "-", "eta": "0s"},
                }

                # Extract sections if specified
                transcribe_path = audio_path
                if sections:
                    yield {"event": "extracting", "data": {"status": "extracting sections"}}
                    sections_path = await extract_sections(audio_path, sections)
                    transcribe_path = sections_path

                # Transcribe
                log(f"Transcribing {video_id} with model {model}")
                duration = info.get("duration", 0)
                transcript_text = ""
                async for update in transcribe_audio(transcribe_path, model, duration):
                    if update.get("status") == "complete":
                        transcript_text = update["transcript"]
                        # Don't save partial transcripts to cache
                        if not sections:
                            save_content(video_id, title, transcript_text, "transcript")
                    else:
                        yield {"event": "transcribing", "data": update}

            finally:
                # Cleanup temp files
                if audio_path.exists():
                    audio_path.unlink()
                if sections_path and sections_path.exists():
                    sections_path.unlink()

        # Summarize with Claude
        log(f"Summarizing {video_id} with Claude")
        yield {"event": "summarizing", "data": {"status": "running claude"}}
        summary = await run_claude_summary(transcript_text, prompt)

        # Save summary
        saved_path = save_content(video_id, title, summary, "summary")
        log(f"Summarization complete for {video_id}")
        yield {"event": "complete", "data": {"summary": summary, "saved_to": str(saved_path)}}

    except Exception as e:
        log(f"Error summarizing {video_id}: {e}")
        yield {"event": "error", "data": {"message": str(e)}}


@app.post("/transcribe")
async def transcribe(request: TranscribeRequest):
    """Transcribe a YouTube video and stream progress via SSE."""

    async def event_generator():
        async for event in transcribe_stream(request.url, request.model, request.sections):
            event_type = event.get("event", "message")
            data = event.get("data", event)
            yield {"event": event_type, "data": json.dumps(data)}

    return EventSourceResponse(event_generator())


@app.post("/summarize")
async def summarize(request: SummarizeRequest):
    """Transcribe and summarize a YouTube video via SSE."""

    async def event_generator():
        async for event in summarize_stream(request.url, request.model, request.prompt, request.sections, request.context):
            event_type = event.get("event", "message")
            data = event.get("data", event)
            yield {"event": event_type, "data": json.dumps(data)}

    return EventSourceResponse(event_generator())


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "version": "1.0.0"}


@app.get("/")
async def root():
    """Root endpoint with usage info."""
    return {
        "service": "YouTube Transcribe Server",
        "version": "1.0.0",
        "endpoints": {
            "POST /transcribe": "Transcribe a YouTube video (SSE stream)",
            "POST /summarize": "Transcribe and summarize a YouTube video (SSE stream)",
            "GET /health": "Health check",
        },
        "example": {
            "url": "https://youtube.com/watch?v=VIDEO_ID",
            "model": "turbo",
            "prompt": "Summarize this transcript concisely",
            "sections": ["40:00-45:35", "1:20:00-1:25:00"],
            "context": "Focus on the business strategy aspects",
        },
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8765))
    log(f"Starting YouTube Transcribe Server on port {port}")
    log(f"Storage: {STORAGE_DIR}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
