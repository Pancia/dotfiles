#!/usr/bin/env bash
# YouTube Transcribe Server launcher
# Managed by LaunchAgent: org.pancia.youtube-transcribe

cd "$(dirname "$0")"
exec uv run --with-requirements requirements.txt python server.py
