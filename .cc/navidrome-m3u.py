#!/usr/bin/env python3
"""Build Navidrome .m3u playlists from the music catalog ($MUSIC_CATALOG).

usage: navidrome-m3u.py OUTPUT_DIR
Copy the output to /mnt/MyMusic/playlists/ on the server. Paths are relative to
that folder. Navidrome reads the display name from the #PLAYLIST line.
"""
import collections, json, os, re, sys

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
catalog = json.load(open(os.environ["MUSIC_CATALOG"]))
lists = collections.defaultdict(list)
for track_id, track in catalog.items():
    lists[track["playlist"]].append(track)

used = set()
for name, tracks in sorted(lists.items()):
    stem = re.sub(r'[/\\:\x00-\x1f]', "-", name).strip(". ") or "unnamed"
    while stem.lower() in used:
        stem += "_"
    used.add(stem.lower())
    with open(os.path.join(out, stem[:200] + ".m3u"), "w", encoding="utf-8") as f:
        f.write(f"#EXTM3U\n#PLAYLIST:{name}\n")
        for t in sorted(tracks, key=lambda t: (t.get("artist") or "", t.get("name") or "")):
            f.write(f'#EXTINF:-1,{t.get("artist") or ""} - {t.get("name") or ""}\n')
            f.write(f'../my-music/{t["id"]}.m4a\n')
print(f"{len(lists)} playlists, {sum(map(len, lists.values()))} entries")
