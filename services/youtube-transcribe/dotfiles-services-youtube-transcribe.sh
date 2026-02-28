#!/opt/homebrew/bin/fish
# YouTube Transcribe Server launcher
# Managed by LaunchAgent: org.pancia.youtube-transcribe

cd (status dirname)
exec uv run --with-requirements requirements.txt --with setproctitle proc-label youtube-transcribe python server.py
