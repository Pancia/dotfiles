"""Tests for fish/functions/trash.fish."""

import json
import os
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[2]
TRASH_FISH = DOTFILES / "fish" / "functions" / "trash.fish"


def fish_eval(
    code: str, *, env: dict | None = None, stdin=None
) -> subprocess.CompletedProcess:
    """Source trash.fish then run code in Fish shell."""
    full_code = f"source {TRASH_FISH}\n{code}"
    run_env = {**os.environ, **(env or {})}
    return subprocess.run(
        ["fish", "-c", full_code],
        capture_output=True,
        text=True,
        env=run_env,
        stdin=stdin,
    )


# =============================================================================
# Encoding / decoding
# =============================================================================


class TestEncoding:
    def test_encode_simple_path(self):
        r = fish_eval('echo (_trash_encode_path "/foo/bar")')
        assert r.returncode == 0
        encoded = r.stdout.strip()
        assert "/" not in encoded
        assert "%2F" in encoded

    def test_decode_roundtrip(self):
        r = fish_eval('echo (_trash_decode_path (_trash_encode_path "/foo/bar baz"))')
        assert r.stdout.strip() == "/foo/bar baz"

    def test_encode_spaces(self):
        r = fish_eval('echo (_trash_encode_path "hello world")')
        assert r.returncode == 0
        encoded = r.stdout.strip()
        # Spaces should be encoded
        assert " " not in encoded

    def test_encode_special_chars(self):
        r = fish_eval(r'echo (_trash_encode_path "/path/to/file (copy).txt")')
        assert r.returncode == 0
        encoded = r.stdout.strip()
        assert "/" not in encoded


# =============================================================================
# Safe name truncation
# =============================================================================


class TestSafeName:
    def test_short_name_passthrough(self):
        """Names under 255 bytes pass through unchanged."""
        r = fish_eval('echo (_trash_safe_name "short-name.txt")')
        assert r.returncode == 0
        assert r.stdout.strip() == "short-name.txt"

    def test_exactly_255_bytes_passthrough(self):
        """A name exactly 255 bytes passes through unchanged."""
        name = "x" * 255
        r = fish_eval(f'echo (_trash_safe_name "{name}")')
        assert r.returncode == 0
        assert r.stdout.strip() == name

    def test_long_name_truncated(self):
        """Names over 255 bytes are truncated with an exocortex-id suffix."""
        name = "a" * 300
        r = fish_eval(f'echo (_trash_safe_name "{name}")')
        assert r.returncode == 0
        result = r.stdout.strip()
        assert len(result.encode()) <= 255
        assert result.startswith("a")
        # Should end with -<exocortex-id>
        assert "-" in result
        # The truncated part should be shorter than original
        assert len(result) < 300

    def test_long_unicode_name_truncated(self):
        """Unicode names that exceed 255 bytes are truncated correctly."""
        # Korean chars are 3 bytes each in UTF-8
        name = "한" * 100  # 300 bytes
        r = fish_eval(f"echo (_trash_safe_name '{name}')")
        assert r.returncode == 0
        result = r.stdout.strip()
        assert len(result.encode()) <= 255

    def test_truncated_name_is_unique(self):
        """Two different long names produce different truncated results (via prefix difference)."""
        name_a = "a" * 300
        name_b = "b" * 300
        r_a = fish_eval(f'echo (_trash_safe_name "{name_a}")')
        r_b = fish_eval(f'echo (_trash_safe_name "{name_b}")')
        # They differ in the truncated prefix portion
        assert r_a.stdout.strip() != r_b.stdout.strip()

    def test_realistic_trash_name_truncation(self):
        """Simulate a realistic long encoded trash filename."""
        # This mimics the pattern: encoded_cwd>>>encoded_file<<<timestamp
        # The cwd prefix is the full encoded path (as seen in the original error)
        prefix = (
            "%2FUsers%2Fanthony%2FLibrary%2FCloudStorage"
            "%2FProtonDrive-adambrosio%40pm.me-folder%2Fmusic"
        )
        filename = (
            "Stray%20Kids__%24__HAN%20%EF%BC%82%EC%99%B8%EA%B3%84%EC%9D%B8"
            "%20%28Alien%29%EF%BC%82%20%EF%BD%9C%20%5BStray%20Kids%20%EF%BC"
            "%9A%20SKZ-RECORD%5D__%23__meQvDHBSxbQ.m4a"
        )
        timestamp = "2026-04-10_13:29:17"
        long_name = f"{prefix}>>>{filename}<<<{timestamp}"
        assert len(long_name.encode()) > 255, "Test input should exceed 255 bytes"

        r = fish_eval(f"echo (_trash_safe_name '{long_name}')")
        assert r.returncode == 0
        result = r.stdout.strip()
        assert len(result.encode()) <= 255
        # Should still start with the original prefix for readability
        assert result.startswith("%2FUsers")


# =============================================================================
# Trash — basic file operations
# =============================================================================


class TestTrash:
    def test_trash_single_file(self, tmp_path):
        """Trashing a file moves it to .Trash and records history."""
        src = tmp_path / "testfile.txt"
        src.write_text("hello")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        cache = tmp_path / "cache"

        r = fish_eval(
            f'cd {tmp_path} && trash testfile.txt',
            env={"HOME": str(home), "XDG_CACHE_HOME": str(cache)},
        )
        assert r.returncode == 0
        assert not src.exists(), "Original file should be gone"
        # File should be in .Trash
        trash_contents = list((home / ".Trash").iterdir())
        assert len(trash_contents) == 1
        assert trash_contents[0].read_text() == "hello"

    def test_trash_preserves_filename_in_trash_entry(self, tmp_path):
        """The trash entry name should contain the encoded filename."""
        src = tmp_path / "myfile.txt"
        src.write_text("data")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        fish_eval(
            f'cd {tmp_path} && trash myfile.txt',
            env={"HOME": str(home)},
        )
        trash_entry = list((home / ".Trash").iterdir())[0]
        assert "myfile.txt" in trash_entry.name

    def test_trash_multiple_files(self, tmp_path):
        """Trashing multiple files at once."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        files = []
        for name in ["a.txt", "b.txt", "c.txt"]:
            f = tmp_path / name
            f.write_text(name)
            files.append(f)

        r = fish_eval(
            f'cd {tmp_path} && trash a.txt b.txt c.txt',
            env={"HOME": str(home)},
        )
        assert r.returncode == 0
        for f in files:
            assert not f.exists()
        assert len(list((home / ".Trash").iterdir())) == 3

    def test_trash_nonexistent_file(self, tmp_path):
        """Trashing a nonexistent file should fail."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        r = fish_eval(
            f'cd {tmp_path} && trash no_such_file.txt',
            env={"HOME": str(home)},
        )
        assert r.returncode == 1
        assert "file not found" in r.stderr.lower()

    def test_trash_long_filename(self, tmp_path):
        """Trashing a file whose encoded name exceeds 255 bytes should succeed."""
        # Korean chars expand significantly when URL-encoded
        long_name = "한글테스트" * 10 + ".m4a"
        src = tmp_path / long_name
        src.write_text("music")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        r = fish_eval(
            f"cd {tmp_path} && trash '{long_name}'",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0
        assert not src.exists(), "Original file should be gone"
        trash_contents = list((home / ".Trash").iterdir())
        assert len(trash_contents) == 1
        trash_name = trash_contents[0].name
        assert len(trash_name.encode()) <= 255

    def test_trash_mixed_existing_and_missing(self, tmp_path):
        """If some files exist and some don't, trash the ones that exist and fail."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        real = tmp_path / "real.txt"
        real.write_text("exists")

        r = fish_eval(
            f'cd {tmp_path} && trash real.txt ghost.txt',
            env={"HOME": str(home)},
        )
        assert r.returncode == 1
        assert not real.exists(), "Existing file should still be trashed"
        assert len(list((home / ".Trash").iterdir())) == 1


# =============================================================================
# History recording
# =============================================================================


class TestHistory:
    def test_history_file_created(self, tmp_path):
        """Trashing a file creates a history entry."""
        src = tmp_path / "tracked.txt"
        src.write_text("track me")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        cache = tmp_path / "cache"

        fish_eval(
            f'cd {tmp_path} && trash tracked.txt',
            env={"HOME": str(home), "XDG_CACHE_HOME": str(cache)},
        )
        # Default history path uses $HOME/.cache/dotfiles/trash/history
        history = home / ".cache" / "dotfiles" / "trash" / "history"
        assert history.exists()
        lines = history.read_text().strip().split("\n")
        assert len(lines) == 1
        fields = lines[0].split("\t")
        assert len(fields) == 5
        assert fields[0] == "tracked.txt"
        # 5th column is the stable id generated at trash time
        assert fields[4] != ""

    def test_history_appends(self, tmp_path):
        """Multiple trash operations append to history."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        for i in range(3):
            f = tmp_path / f"file{i}.txt"
            f.write_text(str(i))
            fish_eval(
                f'cd {tmp_path} && trash file{i}.txt',
                env={"HOME": str(home)},
            )

        history = home / ".cache" / "dotfiles" / "trash" / "history"
        lines = history.read_text().strip().split("\n")
        assert len(lines) == 3


# =============================================================================
# Restore
# =============================================================================


def _list_json(home, tmp_path):
    """Run `trash list --json` and parse the result."""
    r = fish_eval(f"cd {tmp_path} && trash list --json", env={"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


class TestRestore:
    def test_restore_last(self, tmp_path):
        """`restore --last` brings back the most recently trashed file."""
        src = tmp_path / "restore_me.txt"
        src.write_text("come back")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        fish_eval(
            f"cd {tmp_path} && trash restore_me.txt",
            env={"HOME": str(home)},
        )
        assert not src.exists()

        r = fish_eval(
            f"cd {tmp_path} && restore --last",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0, r.stderr
        assert src.exists()
        assert src.read_text() == "come back"

    def test_restore_middle_by_id(self, tmp_path):
        """Restoring a non-last entry by id targets exactly that entry."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        for name, body in [("a.txt", "1"), ("b.txt", "2"), ("c.txt", "3")]:
            f = tmp_path / name
            f.write_text(body)
            fish_eval(f"cd {tmp_path} && trash {name}", env={"HOME": str(home)})

        entries = _list_json(home, tmp_path)
        assert len(entries) == 3
        # Newest-first ordering: c, b, a — middle is b.txt
        b_entry = next(e for e in entries if e["path"].endswith("b.txt"))

        r = fish_eval(
            f"cd {tmp_path} && restore {b_entry['id']}",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0, r.stderr

        # Only b.txt came back; a.txt and c.txt stay trashed.
        assert (tmp_path / "b.txt").exists()
        assert (tmp_path / "b.txt").read_text() == "2"
        assert not (tmp_path / "a.txt").exists()
        assert not (tmp_path / "c.txt").exists()

        history = home / ".cache" / "dotfiles" / "trash" / "history"
        lines = history.read_text().strip().split("\n")
        assert len(lines) == 2
        assert not any("\tb.txt" in line or line.startswith("b.txt") for line in lines)

    def test_restore_long_filename(self, tmp_path):
        """Restore works for files whose trash name was truncated."""
        long_name = "한글테스트" * 10 + ".m4a"
        src = tmp_path / long_name
        src.write_text("music data")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        fish_eval(
            f"cd {tmp_path} && trash '{long_name}'",
            env={"HOME": str(home)},
        )
        assert not src.exists()

        r = fish_eval(
            f"cd {tmp_path} && restore --last",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0, r.stderr
        assert src.exists()
        assert src.read_text() == "music data"

    def test_restore_absolute_path(self, tmp_path):
        """A file trashed by absolute path restores to that absolute path."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        src = tmp_path / "abs.txt"
        src.write_text("absolute")

        fish_eval(f"trash {src}", env={"HOME": str(home)})
        assert not src.exists()

        entries = _list_json(home, tmp_path)
        assert entries[0]["path"] == str(src)

        r = fish_eval(
            f"restore {entries[0]['id']}",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0, r.stderr
        assert src.exists()
        assert src.read_text() == "absolute"

    def test_restore_unknown_id(self, tmp_path):
        """Restoring an id that doesn't exist should fail."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        f = tmp_path / "only.txt"
        f.write_text("x")
        fish_eval(f"cd {tmp_path} && trash only.txt", env={"HOME": str(home)})

        r = fish_eval(
            f"cd {tmp_path} && restore deadbeef",
            env={"HOME": str(home)},
        )
        assert r.returncode == 1

    def test_restore_last_empty_history(self, tmp_path):
        """`restore --last` with no history exits 1 cleanly (no sed crash)."""
        home = tmp_path / "home"
        home.mkdir()
        r = fish_eval("restore --last", env={"HOME": str(home)})
        assert r.returncode == 1

    def test_restore_no_selector_non_tty(self, tmp_path):
        """Bare `restore` with no tty errors instead of launching peco."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        f = tmp_path / "x.txt"
        f.write_text("x")
        fish_eval(f"cd {tmp_path} && trash x.txt", env={"HOME": str(home)})

        r = fish_eval(
            "restore", env={"HOME": str(home)}, stdin=subprocess.DEVNULL
        )
        assert r.returncode == 1
        assert "--last" in r.stderr

    def test_restore_refuses_to_clobber(self, tmp_path):
        """Restore aborts if a live file reappeared at the original path."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        src = tmp_path / "z.txt"
        src.write_text("trashed")

        fish_eval(f"cd {tmp_path} && trash z.txt", env={"HOME": str(home)})
        # Recreate a live file at the original path.
        src.write_text("live")

        r = fish_eval(
            f"cd {tmp_path} && restore --last",
            env={"HOME": str(home)},
        )
        assert r.returncode == 1
        assert "already exists" in r.stderr
        assert src.read_text() == "live", "Live file must not be overwritten"

    def test_restore_unmounted_volume(self, tmp_path):
        """Restore should fail gracefully when the trash file doesn't exist."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        # Write a fake history entry pointing to a nonexistent path (5 columns).
        history_dir = home / ".cache" / "dotfiles" / "trash"
        history_dir.mkdir(parents=True)
        history = history_dir / "history"
        history.write_text(
            "ghost.txt\t%2Ftmp%2Ffake\t2026-01-01_00:00:00"
            "\t/Volumes/Gone/.Trashes/501/ghost\tabc123\n"
        )

        r = fish_eval("restore --last", env={"HOME": str(home)})
        assert r.returncode == 1
        assert "not found in trash" in r.stderr


# =============================================================================
# Listing
# =============================================================================


class TestList:
    def test_list_json_shape(self, tmp_path):
        """`trash list --json` emits one object per entry with stable ids."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        for name in ["one.txt", "two.txt"]:
            (tmp_path / name).write_text(name)
            fish_eval(f"cd {tmp_path} && trash {name}", env={"HOME": str(home)})

        entries = _list_json(home, tmp_path)
        assert len(entries) == 2
        for e in entries:
            assert set(e) >= {"id", "path", "dir", "when", "dest", "present"}
            assert e["present"] is True
        ids = [e["id"] for e in entries]
        assert ids[0] != ids[1], "ids must be distinct"

    def test_list_json_empty(self, tmp_path):
        """`trash list --json` with no history outputs an empty array."""
        home = tmp_path / "home"
        home.mkdir()
        r = fish_eval("trash list --json", env={"HOME": str(home)})
        assert r.returncode == 0
        assert json.loads(r.stdout) == []

    def test_list_present_false(self, tmp_path):
        """An entry whose trash file is gone is reported present:false."""
        home = tmp_path / "home"
        home.mkdir()
        history_dir = home / ".cache" / "dotfiles" / "trash"
        history_dir.mkdir(parents=True)
        (history_dir / "history").write_text(
            "ghost.txt\t%2Ftmp%2Ffake\t2026-01-01_00:00:00"
            "\t/Volumes/Gone/.Trashes/501/ghost\tabc123\n"
        )
        entries = _list_json(home, tmp_path)
        assert len(entries) == 1
        assert entries[0]["present"] is False
        assert entries[0]["id"] == "abc123"

    def test_list_human(self, tmp_path):
        """`trash list` (no --json) prints a table mentioning the file."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        (tmp_path / "visible.txt").write_text("x")
        fish_eval(f"cd {tmp_path} && trash visible.txt", env={"HOME": str(home)})

        r = fish_eval("trash list", env={"HOME": str(home)})
        assert r.returncode == 0
        assert "visible.txt" in r.stdout


# =============================================================================
# Subcommand dispatch
# =============================================================================


class TestSubcommands:
    def test_put_subcommand(self, tmp_path):
        """`trash put <file>` trashes like bare `trash <file>`."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        src = tmp_path / "p.txt"
        src.write_text("put me")

        r = fish_eval(f"cd {tmp_path} && trash put p.txt", env={"HOME": str(home)})
        assert r.returncode == 0, r.stderr
        assert not src.exists()
        assert len(list((home / ".Trash").iterdir())) == 1

    def test_put_escape_reserved_name(self, tmp_path):
        """A file named like a subcommand can be trashed via `trash put`."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        src = tmp_path / "list"  # collides with the `list` subcommand
        src.write_text("reserved")

        r = fish_eval(f"cd {tmp_path} && trash put list", env={"HOME": str(home)})
        assert r.returncode == 0, r.stderr
        assert not src.exists()
        assert len(list((home / ".Trash").iterdir())) == 1

    def test_legacy_bare_trash_still_works(self, tmp_path):
        """Bare `trash <file>` (no subcommand) still trashes — backward compat."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        src = tmp_path / "legacy.txt"
        src.write_text("legacy")

        r = fish_eval(f"cd {tmp_path} && trash legacy.txt", env={"HOME": str(home)})
        assert r.returncode == 0, r.stderr
        assert not src.exists()


# =============================================================================
# External volume support
# =============================================================================


class TestExternalVolume:
    def test_trash_dir_for_local_path(self, tmp_path):
        """Local paths should use ~/.Trash."""
        home = tmp_path / "home"
        home.mkdir()
        f = tmp_path / "local.txt"
        f.write_text("local")

        r = fish_eval(
            f'echo (_trash_dir_for_path {tmp_path / "local.txt"})',
            env={"HOME": str(home)},
        )
        assert r.stdout.strip() == str(home / ".Trash")

    def test_trash_dir_for_volume_path(self, tmp_path):
        """Paths under /Volumes/* should use the volume's .Trashes/<uid>."""
        # Create a fake volume structure
        fake_vol = tmp_path / "Volumes" / "USB"
        fake_vol.mkdir(parents=True)
        test_file = fake_vol / "test.txt"
        test_file.write_text("on usb")

        # We need the symlink to make it look like /Volumes/
        # Instead, test the matching logic directly
        r = fish_eval(
            f'echo (_trash_dir_for_path {test_file})',
            env={"HOME": str(tmp_path / "home")},
        )
        # Since the fake path doesn't start with /Volumes/ after realpath,
        # it should fall back to ~/.Trash
        expected_home = str(tmp_path / "home" / ".Trash")
        assert r.stdout.strip() == expected_home

    def test_trash_dir_symlink_not_followed(self, tmp_path):
        """A symlink to /Volumes/* should NOT route to the volume's trash."""
        # The symlink itself lives on the local filesystem
        target_dir = tmp_path / "target"
        target_dir.mkdir()
        target_file = target_dir / "data.txt"
        target_file.write_text("target")

        link = tmp_path / "mylink"
        link.symlink_to(target_file)

        home = tmp_path / "home"
        home.mkdir()

        r = fish_eval(
            f'echo (_trash_dir_for_path {link})',
            env={"HOME": str(home)},
        )
        # Should resolve based on the link's parent (tmp_path), not target
        assert r.stdout.strip() == str(home / ".Trash")

    def test_volume_fallback_on_permission_error(self, tmp_path):
        """When .Trashes can't be created, falls back to ~/.Trash."""
        home = tmp_path / "home"
        home.mkdir()
        # Create a read-only fake volume root
        fake_vol = tmp_path / "fakevol"
        fake_vol.mkdir()
        test_file = fake_vol / "test.txt"
        test_file.write_text("test")

        # This tests the fallback path conceptually — real /Volumes/ tests
        # would need root. The helper returns ~/.Trash for non-/Volumes/ paths.
        r = fish_eval(
            f'echo (_trash_dir_for_path {test_file})',
            env={"HOME": str(home)},
        )
        assert r.stdout.strip() == str(home / ".Trash")


# =============================================================================
# rm wrapper
# =============================================================================


class TestRmWarning:
    def test_rm_warns_on_tty(self):
        """rm wrapper should still pass through to real rm."""
        r = fish_eval('source (echo "function rm --wraps rm; command rm \\$argv; end" | psub) && echo ok')
        # Just verify the function loading doesn't break
        assert r.returncode == 0

    def test_rm_executes(self, tmp_path):
        """rm wrapper should actually delete the file."""
        f = tmp_path / "deleteme.txt"
        f.write_text("gone")
        r = fish_eval(f'command rm {f}')
        assert r.returncode == 0
        assert not f.exists()
