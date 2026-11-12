#!/bin/bash
# Repro for the lost-last-utterance bug in bin/live-transcribe.
# Plays an audio file into BlackHole, runs the engine on BlackHole as its mic,
# sends SIGINT (what LiveTranscribe.app does on a hotkey stop) shortly after
# playback ends, then prints the transcript. The final sentence must appear.
#   usage: live-transcribe-tail-repro.sh ENGINE AUDIO OUTDIR [STOP_DELAY_S] [CUT_AT_S]
# No --save-audio on purpose: every engine start deletes ALL rec_*.wav in
# ~/.local/state/live-transcribe, which would destroy a live session's recording.
# CUT_AT_S truncates the audio so the stop lands mid-speech (the failing case).
set -u
engine=$1 audio=$2 out=$3 delay=${4:-0.3} cut=${5:-}
mkdir -p "$out"
wav="$out/play.wav"
ffmpeg -loglevel error -y -i "$audio" ${cut:+-t $cut} -ar 48000 -ac 2 "$wav"
python3 "$engine" --mic-device BlackHole --output-dir "$out" --debug >"$out/engine.err" 2>&1 &
pid=$!
# wait until the engine is recording
for _ in $(seq 1 100); do grep -q 'Recording started' "$out/engine.err" 2>/dev/null && break; sleep 0.2; done
python3 - "$wav" <<'PY'
import sys, sounddevice as sd, soundfile as sf
data, sr = sf.read(sys.argv[1], dtype="float32")
sd.play(data, sr, device="BlackHole"); sd.wait()
PY
sleep "$delay"
kill -INT $pid
wait $pid
echo "exit=$?"
cat "$out"/transcript_*.txt
