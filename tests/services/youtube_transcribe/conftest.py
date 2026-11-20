"""Keep every youtube-transcribe test out of the real storage and state folders.

`server.py` computes its folders from `Path.home()` at import time:
`~/Cloud/ytdl/server/{transcripts,summaries}` and
`~/.local/state/youtube-transcribe/{logs,jobs}`. A test that runs a stream to
its end calls `save_job_state`, which writes `JOBS_DIR/<id>.json`. Before the
runner isolated HOME, that wrote `test123.json` and `test456.json` into the
real `~/.local/state/youtube-transcribe/jobs/`; under isolation the folder does
not exist and those tests fail.

This fixture points every folder at the test's `tmp_path` and creates it, the
way the app's lifespan does at startup. A test that patches one folder again
(for example `TRANSCRIPTS_DIR`) still wins, because its `monkeypatch.setattr`
runs after this one.
"""

import pytest

import server

_DIRS = {
    "STORAGE_DIR": "storage",
    "TRANSCRIPTS_DIR": "storage/transcripts",
    "SUMMARIES_DIR": "storage/summaries",
    "STATE_DIR": "state",
    "LOGS_DIR": "state/logs",
    "JOBS_DIR": "state/jobs",
    "TEMP_DIR": "temp",
}


@pytest.fixture(autouse=True)
def server_dirs(tmp_path, monkeypatch):
    """Point server's storage, state and temp folders into tmp_path."""
    root = tmp_path / "yt-server"
    paths = {}
    for name, rel in _DIRS.items():
        path = root / rel
        path.mkdir(parents=True, exist_ok=True)
        monkeypatch.setattr(server, name, path)
        paths[name] = path
    return paths
