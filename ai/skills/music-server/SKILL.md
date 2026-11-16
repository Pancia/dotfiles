---
name: music-server
description: Notes for the music library on the Vultr server and the Mac. Load before working on cmus, bin/cmus-add-new, fish/functions/cmus.fish, the `music` CLI (music push, music import, lib/ruby/music), services/music-mount, rclone, q remote-sync, Navidrome, Feishin, Syncthing, or the server's /music and /mnt disks.
---

# Music streaming (Navidrome + cmus mount)

The library lives on the Vultr server (`ssh anthony@anthonydambrosio.me`, OpenBSD 7.8; see
[remote/anthonydambrosio.me/README.md](~/dotfiles/remote/anthonydambrosio.me/README.md)), at
`/music/MyMusic/my-music/<uuid>.m4a`. Phones use Navidrome over Tailscale. The Mac plays it in
cmus through a mount.

**Two disks, since 2026-11-10.** `/music` is a 40 GB unencrypted Vultr HDD volume that holds only
the music and Navidrome's data, so music works after a restart with nothing unlocked. `/mnt` is
the 100 GB encrypted softraid CRYPTO volume for private files and `remote-sync`.
It locks on every restart, and only the user can unlock it with `~/bin/mnt` (it asks for the
passphrase; `~/bin/unmnt` locks it). **Locked is the normal state**: nothing automatic writes
there. Since 2026-11-12 the AKR post-commit hook encrypts its bundle on the Mac with `age` and
writes it to `~/backups/akr` on the root disk; `remote-sync` copies that into
`/mnt/backups/akr-age/`. The private key is `~/.config/age/akr-backup.key` and Proton Pass,
never the server. Auto-unlocking was rejected: it needs the passphrase stored somewhere
unattended, which defeats the lock. **`/mnt/MyMusic` is an old copy from 2026-11-10, kept by
choice and never updated**; a README there, the login message and `bin/mnt` all say so.
ProtonDrive is the main backup of the music.

**Find disks by DUID, never by `sdN`.** Device numbers shift when a disk is added: after the music
disk arrived, the encrypted chunk moved from `sd1` to `sd2` and the unlocked volume from `sd2` to
`sd3`. A script that writes to `/mnt` must first run `/usr/local/bin/crypt-mounted` (exit 0 only
when the encrypted volume is mounted there); one that writes to `/music` checks
`mount | grep -q ' on /music '`. Unmounted, either path is a plain folder on the root disk. DUIDs:
root `008bb05f4a333904`, encrypted chunk `30397bee4d4fc7b8`, unlocked volume `6ff93f0d9222912c`,
music `aa81c53c88998d20`.

**Boot.** `/music` is `noauto` in `/etc/fstab`, and `/etc/rc.local` fscks and mounts it in the
background, waits for `tun0` to get 100.64.0.3, then starts Navidrome. A bad music disk therefore
cannot stop the boot (a normal fstab entry that fails fsck drops to single-user mode, which happened
once on `/`). Navidrome stays disabled in `rcctl`: started earlier, it would fail to bind the
Tailscale address. `/etc/rc.shutdown` stops it.

`q remote-sync` (`~/AKR/scripts/remote-sync`, moved from `~/ProtonDrive/bin/` on 2026-11-10, with
`restic-sync`; the `q` registry in `~/.config/q/` points there) was rebuilt without `--delete`: never add it back,
because its old `Music/MyMusic` source is empty.

Syncthing runs Mac to phone over Tailscale: the Mac dials `tcp://100.64.0.2:22000`, and global
discovery, relays and NAT mapping are off.

**Navidrome** is the OpenBSD package, 0.51.1. No newer OpenBSD build exists. It binds only to
`100.64.0.3:4533`, and pf allows that port only on `tun0`. Config is `/etc/navidrome.toml`, data
is `/music/.navidrome` (started fresh on 2026-11-10; the old one stays in `/mnt/.navidrome`).
Track IDs are an MD5 of the file path, so moving the music folder means a new database, a new
user (`pancia`, same password, so clients keep working) and a full scan.
- It reports its version as `dev`, so current Feishin in Navidrome mode sends a `missing` filter
  that 0.51 does not have and its pages fail with SQL errors. Add the server as Subsonic/OpenSubsonic.
- A restart does not start a scan. The schedule is `@every 1h`, counted from the restart.
- **`music push` is the route for new tracks** (`lib/ruby/music/push.cmd.rb`; `music -n push` is a
  dry run). It sends catalog tracks the server lacks from `$MUSIC_CLOUD`, only adding, and rewrites
  the playlists in `/music/MyMusic/playlists/` from `$MUSIC_CATALOG`. It skips files changed in the
  last 2 minutes, because a track is tagged after it is copied and `--ignore-existing` would keep
  the untagged one. Navidrome picks changes up at its next hourly scan.
- Tracks must be in the database before their playlists import correctly, and playlists import
  only once an admin user exists. A playlist folder already scanned is not re-read until it
  changes: `touch` the `.m3u` files and the folder, then scan. Run one scan at a time.

**The mount** (`services/music-mount/`) needs the rclone remote `music-server`, which is in
`~/.config/rclone/rclone.conf` and is not tracked. Homebrew's rclone has no `mount`, but
`nfsmount` works without root.

**Background jobs use their own keys,** because the normal key has a passphrase and is unavailable
after a Mac restart until someone logs in. `~/.ssh/music_mount` (the mount) and `~/.ssh/server_check`
(the daily check) have no passphrase. Both log in as the server user `musicread`, and
`authorized_keys` limits each one: the first to `sftp-server -R` (read-only), the second to
`/usr/local/bin/server-health`. `musicread` is in group `_navidrome`, which is how it reads `MyMusic`.
So any new folder under `/mnt` that holds private data needs group `wheel` and mode 750 or 700. New
folders get `/mnt`'s group (now `wheel`), but mode 755, which every account can read, `musicread`
included. A forced command breaks rclone's hash probing, so the remote
needs `shell_type = none` and `disable_hashcheck = true`. Repeated failed SSH logins make the server
refuse this Mac for a couple of minutes.
- **`$MUSIC_PLAYBACK` is the mount; `$MUSIC_LIBRARY` must never point at it.** The mount is
  read-only, so tools that change audio files (tagging) fail.
- `$MUSIC_LIBRARY` now equals `$MUSIC_CLOUD`, so `music import` and `import_single` write to
  ProtonDrive and `music push` sends from there. They add the catalog entry *before* the copy,
  so a failed copy leaves an entry with no file.
- `music tag_from_db` and `music backup` read every file, which would download the whole library
  from ProtonDrive. They refuse to run on a cloud or network `$MUSIC_LIBRARY`. Set it to a local
  copy to run them.
- The nightly `music-backup` service is off: its source drive is dead, and it had failed 221 of 222
  runs with `music: command not found` (launchd has no such PATH). Its plist is renamed
  `*.plist.disabled`, because `_ENSURE_SERVICES` in `fish/config.fish` reinstalls any `services/*/*.plist`
  on shell startup, so `service stop` or deleting the installed copy does not last.
- The settings are measured, so do not drop them casually. `--vfs-fast-fingerprint` skips a
  full-file checksum on the server, and `--sftp-idle-timeout 0` with `ServerAliveInterval` in the
  rclone `ssh` line avoids a new SSH login per song. Together they took the first 64 KB of an
  uncached track from a median of 2.06 s to 0.76 s.
- `--dir-cache-time 168h` means new server tracks can take a week to appear. `service restart
  music-mount` shows them now.
- Listing the 4,300-file folder takes about 107 s through the mount and 6 s with `rclone lsf`. While
  a request is that slow, macOS prints "nfs server ... not responding" onto the terminal of the
  blocked process, which garbles cmus until Ctrl-L. So since 2026-11-14 the `cmus` function no
  longer adds the folder at startup: `bin/cmus-add-new` lists the server directly (about 2 s) and
  adds only tracks cmus lacks, with `cmus-remote -l`. It never removes tracks. Files cmus cannot
  read are offered again at each start, because cmus drops them.

**Scripting cmus.** `save -l`, `save -L` and bare `save` return a hash-table order sorted by
`lib_sort`, **not** the play order, and they ignore `:rand` (0 of 5 next tracks predicted). `save -p -`
and `save -q -` are exact. Remote `rand` and `clear` act only when focus is on the track window, not
the left panel, and do nothing silently otherwise: use `win-next`, and verify. cmus rewrites `lib.pl`
and `cache` on exit, so edit those only while it is closed (`.cc/scripts/cmus-repath.py` moves them to a new
folder). Preloading and a cmus patch were evaluated and rejected once tuning brought song start under
2 s: [.cc/reports/REVIEW-cmus-preload-patch.md](~/dotfiles/.cc/reports/REVIEW-cmus-preload-patch.md).
