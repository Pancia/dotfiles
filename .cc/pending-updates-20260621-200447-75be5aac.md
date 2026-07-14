# Pending CLAUDE.md Updates

_Generated: 20260621-200447_
_Session: 75be5aac-5428-4cb0-8aab-27994e97dd42_

Add documentation for the new service supervision pattern (`whisper-serverd`) that was implemented to optimize `live-transcribe` startup time.

**Change:** Add a new subsection under "## Key Patterns" to document `bin/whisper-serverd`:

**Section to add after "### Claude Code Project Artifacts":**

```
### Service Supervision with Idle TTL (whisper-serverd)

`bin/whisper-serverd` — Supervises long-running services (currently `whisper-server`) with warm-cache optimization and automatic idle cleanup. Clients touch a heartbeat while running; the supervisor reaps the service after idle-ttl seconds with no activity, eliminating model-load latency on repeat invocations.

```bash
whisper-serverd ensure --port 8178 --model large --idle-ttl 300   # adopt or spawn
whisper-serverd supervise --port 8178 --model large --idle-ttl 300  # run supervisor
whisper-serverd stop [--port 8178]                                  # cleanly stop
whisper-serverd status [--port 8178]                                # check state
```

`live-transcribe` adopts the warm server by default; use `--server-url` or `--ephemeral` to override.
```
