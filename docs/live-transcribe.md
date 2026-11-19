# Live Transcribe

- Engine: `bin/live-transcribe` (Python). App: `cmd/live-transcribe-app/main.swift`, built into `bin/LiveTranscribe.app` by `./install lta`. A rebuild does not crash a running app; restart the app to load it.
- The Makefile signs with the "LiveTranscribe Self-Signed" certificate, so the mic permission survives a rebuild. Without it, the build signs ad hoc, prints a warning, and macOS asks for the mic again.
- Transcripts and their `.m4a` go to `~/Cloud/transcripts` (ProtonDrive). `~/transcripts` is the same folder and is the engine's default.
- Logs: `~/.local/state/live-transcribe/last.log` is the current session; `session_<ts>.log` keeps the 20 before it. The temp recording `rec_<ts>.wav` is there while a session records; `kept_<ts>.wav` is one whose transcode failed.
- History: the clock pull-down in the panel, the menu-bar "Recent Transcripts" submenu, and `bin/transcript-pick` (⌘Space → u → t).
- To test the engine, use BlackHole as the mic and an `--output-dir` in the scratchpad. Never pass `--save-audio`. `.cc/scripts/live-transcribe-tail-repro.sh` does this.
- Check `pgrep -f LiveTranscribe.app/Contents/MacOS/` first. A test run shares the warm whisper server and slows a live session.

### Warm Whisper Server with Idle TTL (whisper-serverd)

`bin/whisper-serverd` keeps a `whisper-server` loaded between `live-transcribe` runs, so
repeat startups skip the 8-20s model load. `live-transcribe` touches a heartbeat file
while it runs, and the supervisor reaps the server after `--idle-ttl` seconds without one
(default 30, minimum 20; checked every 5s, so the reap lands 5-10s after the TTL). A running
supervisor keeps the TTL it started with; adopting it does not change it.

```bash
whisper-serverd ensure --model large --port 8178 --idle-ttl 30    # start or adopt, wait until ready
whisper-serverd status [--port 8178]                              # report state as JSON
whisper-serverd stop                                              # kill the server and supervisor
```

`whisper-serverd supervise` is the internal long-lived loop. `live-transcribe` uses the
warm server by default; `--server-url` or `--ephemeral` overrides that.
