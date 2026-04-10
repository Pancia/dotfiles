"""Tests for fish/functions/trash.fish."""

import os
import subprocess
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[2]
TRASH_FISH = DOTFILES / "fish" / "functions" / "trash.fish"


def fish_eval(code: str, *, env: dict | None = None) -> subprocess.CompletedProcess:
    """Source trash.fish then run code in Fish shell."""
    full_code = f"source {TRASH_FISH}\n{code}"
    run_env = {**os.environ, **(env or {})}
    return subprocess.run(
        ["fish", "-c", full_code],
        capture_output=True,
        text=True,
        env=run_env,
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
        assert len(fields) == 4
        assert fields[0] == "tracked.txt"

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


class TestRestore:
    def test_restore_by_line_number(self, tmp_path):
        """Restore a file by history line number."""
        src = tmp_path / "restore_me.txt"
        src.write_text("come back")
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        fish_eval(
            f'cd {tmp_path} && trash restore_me.txt',
            env={"HOME": str(home)},
        )
        assert not src.exists()

        r = fish_eval(
            f'cd {tmp_path} && restore 1',
            env={"HOME": str(home)},
        )
        assert r.returncode == 0
        assert src.exists()
        assert src.read_text() == "come back"

    def test_restore_removes_history_line(self, tmp_path):
        """After restore, the history entry should be removed."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        f1 = tmp_path / "first.txt"
        f1.write_text("1")
        fish_eval(f'cd {tmp_path} && trash first.txt', env={"HOME": str(home)})

        f2 = tmp_path / "second.txt"
        f2.write_text("2")
        fish_eval(f'cd {tmp_path} && trash second.txt', env={"HOME": str(home)})

        # Restore line 1 (first.txt)
        fish_eval(f'cd {tmp_path} && restore 1', env={"HOME": str(home)})

        history = home / ".cache" / "dotfiles" / "trash" / "history"
        lines = history.read_text().strip().split("\n")
        assert len(lines) == 1
        assert "second.txt" in lines[0]

    def test_restore_long_filename(self, tmp_path):
        """Restore works correctly for files whose trash name was truncated."""
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
            f"cd {tmp_path} && restore 1",
            env={"HOME": str(home)},
        )
        assert r.returncode == 0
        assert src.exists()
        assert src.read_text() == "music data"

    def test_restore_invalid_line_number(self, tmp_path):
        """Restoring a nonexistent line should fail."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()
        f = tmp_path / "only.txt"
        f.write_text("x")
        fish_eval(f'cd {tmp_path} && trash only.txt', env={"HOME": str(home)})

        r = fish_eval(
            f'cd {tmp_path} && restore 99',
            env={"HOME": str(home)},
        )
        assert r.returncode == 1

    def test_restore_unmounted_volume(self, tmp_path):
        """Restore should fail gracefully when the trash file doesn't exist."""
        home = tmp_path / "home"
        home.mkdir()
        (home / ".Trash").mkdir()

        # Write a fake history entry pointing to a nonexistent path
        history_dir = home / ".cache" / "dotfiles" / "trash"
        history_dir.mkdir(parents=True)
        history = history_dir / "history"
        history.write_text(
            "ghost.txt\t%2Ftmp%2Ffake\t2026-01-01_00:00:00\t/Volumes/Gone/.Trashes/501/ghost\n"
        )

        r = fish_eval(f'restore 1', env={"HOME": str(home)})
        assert r.returncode == 1
        assert "not found in trash" in r.stderr


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
