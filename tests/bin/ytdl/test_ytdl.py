"""Unit tests for bin/ytdl.

These tests stub out yt-dlp (and friends) by prepending a directory of fake
binaries to PATH. Each stub logs its argv to YTDL_TEST_LOG, letting us assert
on the exact commands ytdl would have run — no real downloads.
"""

import os
import subprocess
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parents[3]
YTDL = DOTFILES / "bin" / "ytdl"


# ---------------------------------------------------------------------------
# Stub harness
# ---------------------------------------------------------------------------


STUB_TEMPLATE = """#!/bin/bash
name="{name}"
log="$YTDL_TEST_LOG"
{{
    printf '%s' "$name"
    for a in "$@"; do
        printf '\\t%s' "$a"
    done
    printf '\\n'
}} >> "$log"
{body}
"""


def _make_stub(bin_dir: Path, name: str, body: str = "exit 0") -> None:
    path = bin_dir / name
    path.write_text(STUB_TEMPLATE.format(name=name, body=body))
    path.chmod(0o755)


@pytest.fixture
def ytdl_env(tmp_path: Path):
    """Build a sandbox: fake $HOME, stub bin dir, PATH, log file."""
    home = tmp_path / "home"
    (home / "Cloud" / "ytdl").mkdir(parents=True)

    stubs = tmp_path / "stubs"
    stubs.mkdir()

    log = tmp_path / "calls.log"
    log.write_text("")

    # yt-dlp: handle --get-title specially so the ytdl script's title probe
    # produces deterministic output; all other invocations just log and exit 0.
    yt_dlp_body = """
for a in "$@"; do
    if [ "$a" = "--get-title" ]; then
        echo "Fake Title"
        exit 0
    fi
done
exit 0
""".strip()
    _make_stub(stubs, "yt-dlp", yt_dlp_body)

    # ffmpeg/ffprobe/transcribe/trash — just log.
    for name in ("ffmpeg", "ffprobe", "transcribe", "trash"):
        _make_stub(stubs, name)

    # pbpaste used by `ytdl clipboard`.
    _make_stub(stubs, "pbpaste", 'echo "https://youtube.com/watch?v=CLIP123"')

    # fzf used by _ytdl_select_type — echoes the first line of stdin, which
    # happens to be "music" (first element of YTDL_VALID_TYPES).
    _make_stub(stubs, "fzf", "head -n1")

    env = {
        **os.environ,
        "HOME": str(home),
        "PATH": f"{stubs}:{os.environ['PATH']}",
        "YTDL_TEST_LOG": str(log),
    }
    return {"env": env, "home": home, "log": log, "stubs": stubs}


def _run_ytdl(ytdl_env, *args, stdin: str = ""):
    # --no-config: skip fish config.fish so it doesn't rewrite PATH (which
    # would let the real yt-dlp shadow our stub) or try to source a dotfiles
    # config from our sandboxed $HOME.
    return subprocess.run(
        ["fish", "--no-config", str(YTDL), *args],
        capture_output=True,
        text=True,
        env=ytdl_env["env"],
        input=stdin,
    )


def _parse_calls(log: Path) -> list[list[str]]:
    """Return a list of [name, *argv] for each logged invocation."""
    out = []
    for line in log.read_text().splitlines():
        if line:
            out.append(line.split("\t"))
    return out


def _find_call(calls, name: str, must_contain: list[str] | None = None):
    """Find the first call with matching name (and optional required args)."""
    for c in calls:
        if c[0] != name:
            continue
        if must_contain and not all(m in c[1:] for m in must_contain):
            continue
        return c
    return None


def _download_calls(calls):
    """yt-dlp calls that are actual downloads (not --get-title probes)."""
    return [c for c in calls if c[0] == "yt-dlp" and "--get-title" not in c[1:]]


# ---------------------------------------------------------------------------
# Download routing
# ---------------------------------------------------------------------------


class TestDownloadMedia:
    def test_audio_uses_bestaudio_format(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "audio", "abc123")
        assert r.returncode == 0, r.stderr

        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        # Format flag
        assert "-f" in call
        assert call[call.index("-f") + 1] == "bestaudio"
        # No merge format for audio
        assert "--merge-output-format" not in call
        # Video ID passed after --
        assert call[-1] == "abc123"
        assert call[-2] == "--"

    def test_music_uses_bestaudio_format(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "music", "abc123")
        assert r.returncode == 0, r.stderr
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert call[call.index("-f") + 1] == "bestaudio"

    def test_video_regular_uses_480p_avc(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "video", "abc123")
        assert r.returncode == 0, r.stderr

        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        fmt = call[call.index("-f") + 1]
        assert "height<=480" in fmt
        assert "vcodec^=avc" in fmt
        # Video downloads merge to mp4
        assert "--merge-output-format" in call
        assert call[call.index("--merge-output-format") + 1] == "mp4"

    def test_video_best_quality_drops_height_cap(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "--quality", "best", "video", "abc123")
        assert r.returncode == 0, r.stderr

        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        fmt = call[call.index("-f") + 1]
        assert "height<=480" not in fmt
        assert "vcodec^=avc" in fmt

    def test_output_path_contains_type_and_template(self, ytdl_env):
        _run_ytdl(ytdl_env, "audio", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        out = call[call.index("-o") + 1]
        assert "/Cloud/ytdl/audio/" in out
        assert "%(channel)s" in out
        assert "%(title)s" in out
        assert "%(id)s" in out
        # Single video: no playlist segment
        assert "%(playlist_title)s" not in out

    def test_playlist_url_adds_playlist_segment(self, ytdl_env):
        url = "https://youtube.com/playlist?list=PL123"
        _run_ytdl(ytdl_env, "audio", url)
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        out = call[call.index("-o") + 1]
        assert "%(playlist_title)s" in out

    def test_watch_url_with_list_still_treated_as_single(self, ytdl_env):
        url = "https://youtube.com/watch?v=abc123&list=PL123"
        _run_ytdl(ytdl_env, "audio", url)
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        out = call[call.index("-o") + 1]
        assert "%(playlist_title)s" not in out


class TestDownloadText:
    def test_text_format_prefers_m4a(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "text", "abc123")
        assert r.returncode == 0, r.stderr
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        fmt = call[call.index("-f") + 1]
        assert fmt == "bestaudio[ext=m4a]/bestaudio"

    def test_text_output_dir(self, ytdl_env):
        _run_ytdl(ytdl_env, "text", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        out = call[call.index("-o") + 1]
        assert "/Cloud/ytdl/text/" in out

    def test_notes_routes_to_notes_dir(self, ytdl_env):
        _run_ytdl(ytdl_env, "notes", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        out = call[call.index("-o") + 1]
        assert "/Cloud/ytdl/notes/" in out

    def test_text_mode_does_not_merge_mp4(self, ytdl_env):
        _run_ytdl(ytdl_env, "text", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert "--merge-output-format" not in call


# ---------------------------------------------------------------------------
# URL parsing
# ---------------------------------------------------------------------------


class TestVideoIdExtraction:
    def test_extracts_id_from_watch_url(self, ytdl_env):
        _run_ytdl(ytdl_env, "audio", "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert call[-1] == "dQw4w9WgXcQ"

    def test_strips_trailing_query_params(self, ytdl_env):
        _run_ytdl(ytdl_env, "audio", "https://youtube.com/watch?v=abc123&t=42s")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert call[-1] == "abc123"

    def test_raw_id_passed_through(self, ytdl_env):
        _run_ytdl(ytdl_env, "audio", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert call[-1] == "abc123"


# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------


class TestFlags:
    def test_invalid_type_rejected(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "bogus", "abc123")
        assert r.returncode != 0
        assert "Invalid type" in r.stdout + r.stderr

    def test_invalid_quality_rejected(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "--quality", "ultra", "audio", "abc123")
        assert r.returncode != 0
        assert "Invalid quality" in r.stdout + r.stderr

    def test_missing_quality_value_rejected(self, ytdl_env):
        r = _run_ytdl(ytdl_env, "--quality")
        assert r.returncode != 0
        assert "requires a value" in r.stdout + r.stderr

    def test_quiet_flag_does_not_reach_ytdlp(self, ytdl_env):
        _run_ytdl(ytdl_env, "--quiet", "audio", "abc123")
        call = _download_calls(_parse_calls(ytdl_env["log"]))[0]
        assert "--quiet" not in call
        # but --newline is added for progress parsing
        assert "--newline" in call


# ---------------------------------------------------------------------------
# Age-restricted retry
# ---------------------------------------------------------------------------


class TestAgeRestrictedRetry:
    def _make_age_restricted_ytdlp(self, stubs: Path):
        # First call exits 1 with the age-restricted message; second call
        # (with --cookies-from-browser) succeeds. We track state via a marker
        # file in the stubs dir.
        body = """
# --get-title probe: answer without incrementing the retry counter.
for a in "$@"; do
    if [ "$a" = "--get-title" ]; then
        echo "Fake Title"
        exit 0
    fi
done

# Count only real download invocations.
marker="$(dirname "$0")/.ytdlp_call_count"
count=0
[ -f "$marker" ] && count=$(cat "$marker")
count=$((count + 1))
echo "$count" > "$marker"

if [ "$count" = "1" ]; then
    echo "ERROR: Sign in to confirm your age" >&2
    exit 1
fi
exit 0
""".strip()
        _make_stub(stubs, "yt-dlp", body)

    def test_retries_with_cookies_on_age_restriction(self, ytdl_env):
        self._make_age_restricted_ytdlp(ytdl_env["stubs"])

        r = _run_ytdl(ytdl_env, "audio", "abc123")
        assert r.returncode == 0, r.stderr

        calls = _download_calls(_parse_calls(ytdl_env["log"]))
        assert len(calls) == 2
        # First call: no cookies
        assert "--cookies-from-browser" not in calls[0]
        # Second call: cookies from brave
        assert "--cookies-from-browser" in calls[1]
        assert calls[1][calls[1].index("--cookies-from-browser") + 1] == "brave"

    def test_retries_with_cookies_in_quiet_mode(self, ytdl_env):
        self._make_age_restricted_ytdlp(ytdl_env["stubs"])

        r = _run_ytdl(ytdl_env, "--quiet", "audio", "abc123")
        assert r.returncode == 0, r.stderr

        calls = _download_calls(_parse_calls(ytdl_env["log"]))
        assert len(calls) == 2
        assert "--cookies-from-browser" in calls[1]


# ---------------------------------------------------------------------------
# Clipboard mode
# ---------------------------------------------------------------------------


class TestClipboardMode:
    def test_clipboard_reads_pbpaste_and_prompts_type(self, ytdl_env):
        # fzf stub returns the first YTDL_VALID_TYPES entry = "music"
        r = _run_ytdl(ytdl_env, "clipboard")
        assert r.returncode == 0, r.stderr

        calls = _parse_calls(ytdl_env["log"])
        assert _find_call(calls, "pbpaste") is not None
        assert _find_call(calls, "fzf") is not None

        dl = _download_calls(calls)[0]
        # pbpaste stub returned ?v=CLIP123, so video_id should be CLIP123
        assert dl[-1] == "CLIP123"
        # Selected type was "music" (first fzf line), so output dir is music
        out = dl[dl.index("-o") + 1]
        assert "/Cloud/ytdl/music/" in out
