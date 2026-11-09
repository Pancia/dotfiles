#!/usr/bin/env python3
"""Move cmus's library, playlists and tag cache to a new music folder.

Run only while cmus is NOT running: cmus rewrites these files when it exits.
usage: cmus-repath.py OLD_PREFIX NEW_PREFIX [--dry-run]

The tag cache holds one record per file, each starting with its length as a
little-endian uint32 and padded to 8 bytes. A new path length changes both, so a
plain text replace would corrupt it. Keeping the cache means cmus does not have
to read the tags of 4,000 files over the network again.
"""
import pathlib, struct, sys

old, new = sys.argv[1].encode(), sys.argv[2].encode()
dry = "--dry-run" in sys.argv
home = pathlib.Path.home() / ".config/cmus"
HEADER = 8


def align(n):
    return (n + 7) & ~7


def rewrite_cache(data):
    assert data[:3] == b"CTC", "unknown cache format"
    out, pos, total, changed = bytearray(data[:HEADER]), HEADER, 0, 0
    while pos < len(data):
        size = struct.unpack_from("<I", data, pos)[0]
        assert size >= 8 and pos + size <= len(data), f"bad record at {pos}"
        rec = data[pos:pos + size]
        i = rec.find(old)
        if i != -1:
            rec = rec[:i] + new + rec[i + len(old):]
            rec = struct.pack("<I", len(rec)) + rec[4:]
            changed += 1
        out += rec + b"\0" * (align(len(rec)) - len(rec))
        pos += align(size)
        total += 1
    # The last record has no padding, so the walk may overshoot by up to 7 bytes.
    assert 0 <= pos - len(data) < 8, f"walk ended at {pos}, file is {len(data)}"
    return bytes(out), total, changed


cache = home / "cache"
new_cache, total, changed = rewrite_cache(cache.read_bytes())
print(f"cache: {changed} of {total} records")
texts = [home / "lib.pl", *sorted((home / "playlists").iterdir())]
new_texts = []
for f in texts:
    if f.is_file():
        b = f.read_bytes()
        print(f"{f.name}: {b.count(old)} paths")
        new_texts.append((f, b.replace(old, new)))
if not dry:
    cache.write_bytes(new_cache)
    for f, b in new_texts:
        f.write_bytes(b)
    print("written")
