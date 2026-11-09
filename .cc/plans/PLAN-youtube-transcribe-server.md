# YouTube Transcribe Server - Implementation Plan

## Overview
A FastAPI web server that accepts YouTube URLs, downloads audio via yt-dlp, transcribes using MLX Whisper, and streams progress updates via Server-Sent Events.

## Architecture

```
Client Request (YouTube URL)
    │
    ▼
FastAPI Server (SSE endpoint)
    │
    ├─► yt-dlp: Download audio (progress events)
    │
    ├─► transcribe: MLX Whisper (progress events)
    │
    └─► Return transcript (completion event)
```

## Directory Structure

```
services/youtube-transcribe/
├── org.pancia.youtube-transcribe.plist   # LaunchAgent
├── dotfiles-services-youtube-transcribe.sh  # Launcher script
├── server.py                              # FastAPI application
├── requirements.txt                       # Python dependencies
└── pyproject.toml                         # Optional: for uv
```

## Implementation Steps

### Step 1: Create service directory and FastAPI server

**File: `services/youtube-transcribe/server.py`**

- FastAPI app with SSE streaming endpoint
- `POST /transcribe` - accepts `{"url": "youtube_url"}`, returns SSE stream
- `GET /health` - health check endpoint
- Progress stages:
  1. `{"event": "started", "data": {"video_id": "...", "title": "..."}}`
  2. `{"event": "downloading", "data": {"percent": 45.2, "speed": "1.2MiB/s"}}`
  3. `{"event": "transcribing", "data": {"status": "processing"}}`
  4. `{"event": "complete", "data": {"transcript": "..."}}`
  5. `{"event": "error", "data": {"message": "..."}}`

### Step 2: yt-dlp integration

- Extract video ID and metadata using `yt-dlp --dump-json`
- Download audio only: `yt-dlp -x --audio-format m4a -o tempfile`
- Parse yt-dlp progress output (percentage, speed, ETA)
- Use subprocess with real-time stdout reading for progress
- Temp files in `/tmp/youtube-transcribe/`

### Step 3: MLX Whisper integration

- Call existing `~/dotfiles/bin/transcribe` script
- Or import mlx_whisper directly for finer progress control
- Use "turbo" model by default (fastest on Apple Silicon)
- Stream transcription progress if possible

### Step 4: LaunchAgent configuration

**File: `services/youtube-transcribe/org.pancia.youtube-transcribe.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.pancia.youtube-transcribe</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/anthony/dotfiles/bin/service-wrapper</string>
        <string>/Users/anthony/dotfiles/services/youtube-transcribe</string>
        <string>uv</string>
        <string>run</string>
        <string>python</string>
        <string>server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/anthony/.log/services/youtube-transcribe.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/anthony/.log/services/youtube-transcribe.log</string>
</dict>
</plist>
```

### Step 5: Dependencies

**File: `services/youtube-transcribe/requirements.txt`**

```
fastapi
uvicorn[standard]
sse-starlette
yt-dlp
mlx-whisper
```

## API Design

### POST /transcribe

**Request:**
```json
{
  "url": "https://www.youtube.com/watch?v=VIDEO_ID",
  "model": "turbo"  // optional: tiny, base, small, medium, large, turbo
}
```

**Response:** Server-Sent Events stream

```
event: started
data: {"video_id": "abc123", "title": "Video Title", "duration": 300}

event: downloading
data: {"percent": 25.5, "speed": "2.1MiB/s", "eta": "12s"}

event: downloading
data: {"percent": 100, "speed": "2.1MiB/s", "eta": "0s"}

event: transcribing
data: {"status": "loading model"}

event: transcribing
data: {"status": "processing audio"}

event: complete
data: {"transcript": "Full transcript text here..."}
```

### GET /health

**Response:**
```json
{"status": "ok", "version": "1.0.0"}
```

## Configuration

- Default port: `8765` (or configurable via env var)
- Temp directory: `/tmp/youtube-transcribe/`
- Default Whisper model: `turbo`
- Cleanup temp files after transcription

## Error Handling

- Invalid URL → immediate error event
- Download failure → error event with yt-dlp message
- Transcription failure → error event with details
- All errors include `{"event": "error", "data": {"message": "..."}}`

## Usage Example

```bash
# Start server (if not using LaunchAgent)
cd ~/dotfiles/services/youtube-transcribe
uv run python server.py

# Client request
curl -N -X POST http://localhost:8765/transcribe \
  -H "Content-Type: application/json" \
  -d '{"url": "https://youtube.com/watch?v=VIDEO_ID"}'
```

## Files to Create

1. `services/youtube-transcribe/server.py` - Main FastAPI application
2. `services/youtube-transcribe/requirements.txt` - Dependencies
3. `services/youtube-transcribe/org.pancia.youtube-transcribe.plist` - LaunchAgent
4. `services/youtube-transcribe/dotfiles-services-youtube-transcribe.sh` - Launcher
5. Symlink plist to `~/Library/LaunchAgents/`
