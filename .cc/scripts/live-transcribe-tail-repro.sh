#!/bin/bash
# Repro for the lost-last-utterance bug in bin/live-transcribe (fixed 2026-11-12).
# Plays an audio file into BlackHole, runs the engine on BlackHole as its mic,
# sends SIGINT (what LiveTranscribe.app does on a hotkey stop) shortly after
# playback ends, then prints the transcript. The final sentence must appear.
#
#   usage: live-transcribe-tail-repro.sh ENGINE AUDIO OUTDIR [STOP_DELAY_S] [CUT_AT_S]
#
# CUT_AT_S truncates the audio so the stop lands mid-speech, while the last
# utterance is still buffered (the failing case). Use 0 for STOP_DELAY_S.
#
# The bug only shows when the stop-time .m4a transcode outlasts the worker's 1s
# queue poll, which a run in the scratchpad never does on its own. So the script
# runs a COPY of ENGINE with a 1.5s sleep injected at the top of
# _finalize_recording. Reproduced 2026-11-12 with the session-2 audio, cut 31.5,
# delay 0: the pre-fix engine lost the tail 2/2, the fixed one kept it 2/2.
# SLOW_FINALIZE=0 runs ENGINE unmodified.
#
# No --save-audio: it is not needed (the sleep stands in for the transcode).
# Before the fix the engine also deleted EVERY rec_*.wav at start-up, so a run
# with --save-audio destroyed a live session's recording. It now only sweeps
# files idle for 14 days, but there is still no reason to touch that folder.
set -u
engine=$1 audio=$2 out=$3 delay=${4:-0.3} cut=${5:-}
mkdir -p "$out"

if [ "${SLOW_FINALIZE:-1}" != 0 ]; then
  copy="$out/engine-slow"
  mkdir -p "$copy"
  python3 - "$engine" "$copy/live-transcribe" <<'PY'
import sys
src = open(sys.argv[1]).read()
marker = "def _finalize_recording(self):\n"
assert marker in src, "no _finalize_recording in engine"
src = src.replace(marker, marker + "        import time; time.sleep(1.5)  # REPRO: slow transcode\n", 1)
open(sys.argv[2], "w").write(src)
PY
  # the engine finds whisper-serverd next to itself
  ln -sf "$(cd "$(dirname "$engine")" && pwd)/whisper-serverd" "$copy/whisper-serverd"
  engine="$copy/live-transcribe"
fi

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
