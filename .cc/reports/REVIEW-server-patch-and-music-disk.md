# Review: syspatch, restart and new music disk on anthonydambrosio.me

Date: 2026-11-10. Read-only review. Three SSH logins as `anthony`, all key-based, no
failures. Nothing on the server was changed.

## Verdict

The goal and the broad order are sound. One restart for both the kernel patches and
the new disk is correct: the disks are `vioblk` devices, which need a restart to
appear. The plan must change in five places before it runs:

1. **Device names shift, and six scripts hard-code `/dev/sd2a`.** After the restart
   the new disk takes `sd2` and the encrypted volume becomes `sd3`. After step 4,
   the unchanged `~/bin/mnt` can mount the unencrypted music disk on `/mnt`. Every
   "is the encrypted disk mounted" check then passes, and private backups go to the
   unencrypted disk. `~/bin/unmnt` would also leave the encrypted volume unlocked
   while it prints "OK".
2. **A normal fstab line for the music disk can stop the whole boot.** If that disk
   fails fsck or is missing, `/etc/rc` drops to single-user mode. Headscale and SSH
   are then down until someone uses the Vultr console.
3. **Navidrome cannot be simply "enabled at boot".** It binds 100.64.0.3, which
   exists only after tailscaled reaches Headscale on the same machine.
4. **Copying the Navidrome database gains nothing and adds duplicates.** Track IDs
   are MD5 hashes of the absolute path. The database is two days old and holds no
   play counts, stars or bookmarks. Start a fresh one.
5. **The "backup on the encrypted disk" stops getting new tracks** the moment
   `music push` points at the new disk. Nothing in the plan keeps it current.

Also: there are 75 pending patches, not 46. Errata 001 says syspatch can fail when
`/usr` is not a separate file system, which is the case here. The plan needs the
errata workaround.

## Facts gathered

All verified on the server unless marked.

| Item | Value | How |
|---|---|---|
| Kernel | `GENERIC#54`, 1 CPU, 1 GB, 530 MB free, swap 256 MB (20 MB used) | `sysctl`, `top` |
| Disks now | `sd0:008bb05f4a333904`, `sd1:30397bee4d4fc7b8` (100 GB, partition `a` type RAID), `cd0`, `sd2:6ff93f0d9222912c` (label `SR CRYPTO`) | `hw.disknames`, `disklabel` |
| Disk driver | `sd0` on `vioblk0`, `sd1` on `vioblk1`; softraid volume `sd2` attaches at `scsibus5` when `bioctl` runs | `dmesg` |
| Space | `/` 17.7 GB free (`/usr` and `/var` are on `/`); `/usr/local` 1.4 GB free; `/mnt` 51.6 GB used of 96.9 GB | `df -h` |
| fstab | root, `/usr/local` and swap by DUID. No `/mnt` line | `/etc/fstab` |
| pkg_scripts | `headscale tailscaled`. `navidrome_flags=NO` | `rc.conf.local`, `rcctl get` |
| `/etc/rc.local`, `/etc/rc.shutdown` | do not exist | `ls` |
| rc order | fsck of all fstab lines with pass > 0, then `mount -a`, base daemons (sshd, relayd, httpd), `pkg_scripts`, then `rc.local`, then `reorder_kernel &` | `/etc/rc` lines 416-680 |
| fsck failure at boot | `do_fsck` runs `exit 1` on codes 2, 8, 12 and others, so boot stops in single-user mode | `/etc/rc` lines 320-345 |
| Navidrome | 0.51.1, `Address = "100.64.0.3"`, `MusicFolder = "/mnt/MyMusic"`, `DataFolder = "/mnt/.navidrome"`, `ScanSchedule = "@every 1h"`; rc.d script has `rc_bg=YES` | `/etc/navidrome.toml`, `/etc/rc.d/navidrome` |
| Navidrome DB | 4,523 tracks; 247 playlists, all with `path` under `/mnt/MyMusic/playlists/` and `sync=1`; 0 annotations, 0 bookmarks, 0 play queues; 1 user; `InitialSetup` 2026-11-09 | read-only `sqlite3` queries |
| Track ID scheme | `md5("/mnt/MyMusic/kalinda's/Scared of the Dark BB2.aif")` = `5859eb1a6eb5ef726cfd28865575da29`, which equals that row's `id` | computed on the Mac |
| DB files | `navidrome.db` 9 MB, `navidrome.db-wal` 71 MB, whole folder 200 MB | `ls`, `du` |
| Permissions | `/mnt` `anthony:_navidrome 750`; `MyMusic` `anthony:_navidrome 755`; `my-music` and `playlists` `750`; tracks `anthony:_navidrome 750`; private folders `anthony:wheel 700/750`; `.navidrome` `_navidrome 700` | `ls -ld` |
| musicread | groups `musicread`, `_navidrome`. Keys: `restrict,command="/usr/libexec/sftp-server -R"` and `restrict,command="/usr/local/bin/server-health"`. No `ChrootDirectory` in sshd_config | `id`, authorized_keys (keys not printed), `sshd_config` |
| pf | 4533 allowed only `on tun0 from 100.64.0.0/10` | `pfctl -sr` |
| syspatch | none installed; `syspatch -c` lists **75** (001_syspatch to 075_video) | `syspatch -l`, `syspatch -c` |
| Errata 018 ports | none of the listed ports are installed (81 packages) | `pkg_info -q` |
| Kernel files | `/bsd` (Nov 9), `/bsd.booted`, `/bsd.rd`, and `/bsd.sp` dated **Apr 28 2023** (a 7.3-era file). No `/obsd` | `ls -l /bsd*` |
| Headscale config | no reference to `/mnt` | `grep` |
| Old double unlock | `softraid0: chunk sd1a already in use` on Nov 9 20:52 | `/var/log/messages` |

## Findings, by severity

### Critical 1: device names shift, and the `/dev/sd2a` checks then fail in both directions

**Verified:** these six places use the literal device:

| Where | What it does with `/dev/sd2a` |
|---|---|
| `~/bin/mnt` | `bioctl -c C -l sd1a softraid0`, then `mount /dev/sd2a /mnt`, then starts Navidrome if `^/dev/sd2a on /mnt ` |
| `~/bin/unmnt` | `umount /mnt`, then `bioctl -d sd2`; prints "OK" whatever happened |
| `/usr/local/bin/server-health` | prints `unlocked` if `^/dev/sd2a on /mnt ` |
| `lib/ruby/music/push.cmd.rb` | `PUSH_MOUNTED` gate before sending tracks |
| `~/ProtonDrive/bin/remote-sync` | `MOUNTED_CHECK`, the guard against writing private data to the root disk |
| `~/AKR/vcs-hooks/post-commit` | `MOUNT_CHECK`, in the probe, in `--rsync-path` and in `SAVE_DATED` |

**Verified:** the `mount` output always shows `/dev/sdNa`, even for a file system
mounted by DUID (root is mounted by DUID and shows as `/dev/sd0a`). So the checks
cannot be fixed by mounting by DUID alone.

**Inference (strong):** physical `vioblk` disks attach during kernel autoconf. The
softraid volume attaches later, when `bioctl` runs. So after the restart the new
disk is `sd2` and the unlocked encrypted volume is `sd3`. If Vultr places the new
device on a lower PCI slot, the new disk could be `sd1` and the RAID chunk `sd2`.
Either way the names change.

What then happens, in order:

- **Step 3, unchanged `mnt`, new disk still blank.** `bioctl` unlocks the volume as
  `sd3`. `mount /dev/sd2a` fails, because a blank disk has no `a` partition. Navidrome
  does not start. All literal checks report "locked": AKR step 3 fails, remote-sync
  stops, push stops, server-check alerts. This direction fails safe.
- **Any `mnt` run after step 4, while the music disk is not mounted at `/music`.**
  `mount /dev/sd2a /mnt` mounts the **unencrypted music disk** on `/mnt`. Every check
  then passes. remote-sync writes `private/`, `Movies/` and `ytdl/` to the
  unencrypted disk. The AKR hook writes its bundles there. server-health says
  `unlocked`. This is the dangerous direction. It needs only one boot where the music
  disk did not mount (see Critical 3).
- **`unmnt` with the new names.** `bioctl -d sd2` targets the music disk and fails.
  The encrypted volume `sd3` stays attached with its key in memory, and the script
  still prints `>>> OK: UNMOUNTED SUCCESSFULLY <<<`.
- **If the new disk lands at `sd1`.** `bioctl -l sd1a` fails (no `a` partition on a
  blank disk). Harmless, but the unlock does not work.

**Fix.** Find both devices by DUID every time, and put the check in one server-side
helper that all clients call. Do this **before** the restart; it works with today's
names too.

`/usr/local/bin/crypt-mounted` (root:bin 755):

```sh
#!/bin/sh
# Exit 0 only if the encrypted volume is mounted on /mnt.
# The volume is found by DUID, because sdN numbers change when disks are added.
VOL=6ff93f0d9222912c
d=$(/sbin/sysctl -n hw.disknames | /usr/bin/tr , '\n' | /usr/bin/sed -n "s/:$VOL\$//p")
[ -n "$d" ] && /sbin/mount | /usr/bin/grep -q "^/dev/${d}a on /mnt "
```

`~/bin/mnt`:

```sh
#!/bin/sh
# Unlock and mount the encrypted disk. Disks are found by DUID, never by sdN.
set -e
CHUNK=30397bee4d4fc7b8   # 100 GB Vultr volume; partition a is the CRYPTO chunk
VOL=6ff93f0d9222912c     # the unlocked CRYPTO volume
dev_of() { sysctl -n hw.disknames | tr , '\n' | sed -n "s/:$1\$//p"; }
if [ -z "$(dev_of $VOL)" ]; then
    chunk=$(dev_of $CHUNK)
    [ -n "$chunk" ] || { echo "mnt: encrypted chunk disk not found"; exit 1; }
    doas bioctl -c C -l /dev/${chunk}a softraid0
fi
/usr/local/bin/crypt-mounted || doas mount $VOL.a /mnt
/usr/local/bin/crypt-mounted || { echo "mnt: /mnt is not the encrypted volume"; exit 1; }
ls -l /mnt
# Until step 6 of the migration, keep: doas rcctl -f start navidrome
```

`mount` accepts a DUID (verified in `mount(8)` on the server). `bioctl(8)` does not
document DUIDs, so the script resolves the chunk to `/dev/sdNa` itself. It is also
idempotent, which fixes the Nov 9 double-unlock message.

`~/bin/unmnt`:

```sh
#!/bin/sh
set -e
VOL=6ff93f0d9222912c
# Until step 6: doas rcctl -f stop navidrome
doas umount /mnt
d=$(sysctl -n hw.disknames | tr , '\n' | sed -n "s/:$VOL\$//p")
[ -n "$d" ] && doas bioctl -d $d
if sysctl -n hw.disknames | grep -q ":$VOL"; then
    echo ">>> FAILED: the encrypted volume is still attached <<<"; exit 1
fi
echo ">>> OK: locked <<<"
```

Clients: replace each `mount | grep -q '^/dev/sd2a on /mnt '` with
`/usr/local/bin/crypt-mounted`. In the AKR hook that covers `MOUNT_CHECK`, and so
`--rsync-path="/usr/local/bin/crypt-mounted && /usr/local/bin/rsync"` and
`SAVE_DATED`. In server-health, replace the grep line with
`/usr/local/bin/crypt-mounted && echo unlocked`. `hw.disknames` is readable without
root (verified: read as `anthony`), so `musicread`'s forced command can run it.

Test before the restart: `crypt-mounted; echo $?` prints 0 now, and 1 after `unmnt`.

### Critical 2: step 4 can destroy the encrypted disk if the wrong device is chosen

**Inference.** `fdisk -iy` and `disklabel` on the wrong `sdN` overwrite the label.
On `sd1` that loses the CRYPTO chunk. On the unlocked `sd3` it loses the file system.
`/mnt/MyMusic` is the only copy with an independent lineage, and the Vultr instance
snapshot does not include block volumes (inference from Vultr's documentation).

**Fix.** Prepare the new disk **before** unlocking, so the encrypted volume is not
even attached. Pick the disk by size and an empty label, and check that its DUID is
none of the three known ones:

```sh
sysctl hw.disknames                  # expect a new sdN with no DUID yet
dmesg | grep '^sd[0-9]:'             # the new disk shows 40960MB, 83886080 sectors
doas disklabel sdN | grep -e 'total sectors' -e duid -e '^  [a-p]:'
#   must show 83886080 sectors, no partitions except c,
#   and must not be 008bb05f4a333904, 30397bee4d4fc7b8 or 6ff93f0d9222912c
doas fdisk -iy sdN
doas disklabel -E sdN                # a a, accept defaults, 4.2BSD; w; q
doas newfs sdNa
doas disklabel sdN | grep duid       # note the new DUID
```

### Critical 3: the music disk in fstab must not be able to stop the boot

**Verified:** `/etc/rc` fscks every fstab entry with pass > 0, and a failure ends in
`exit 1`, which is single-user mode. The last restart already stopped this way on
`/`. A network block volume adds a second way to fail (missing, slow, or unclean).
Then SSH and Headscale are down until the Vultr console.

**Verified:** `mount -a` failures in `/etc/rc` do not stop the boot.

**Fix.** Use `noauto` and pass 0, and mount the disk from `/etc/rc.local`, which runs
after `pkg_scripts` (verified). Nothing there can stop the boot.

`/etc/fstab`, new line:

```
NEWDUID.a /music ffs rw,nodev,nosuid,noexec,noatime,noauto 0 0
```

`/etc/rc.local` (new file; the same script also solves Important 1):

```sh
# Music disk and Navidrome. Runs in the background, so a failure here
# never stops the boot. Navidrome binds 100.64.0.3, which appears only after
# tailscaled reaches Headscale.
(
    if fsck -p NEWDUID.a && mount /music; then
        i=0
        until ifconfig tun0 2>/dev/null | grep -q 'inet 100.64.0.3 '; do
            i=$((i + 1))
            if [ $i -gt 150 ]; then
                logger -t rc.local "tun0 has no 100.64.0.3 after 5 min; Navidrome not started"
                exit 1
            fi
            sleep 2
        done
        rcctl -f start navidrome
    else
        logger -t rc.local "music disk did not mount; Navidrome not started"
    fi
) &
```

`/etc/rc.shutdown` (new file), so Navidrome stops before the file systems unmount:

```sh
rcctl -f stop navidrome
```

Not verified: that `fsck -p` accepts a DUID argument. Test it by hand in step 3, on
the new unmounted file system: `doas fsck -p NEWDUID.a; echo $?` must print 0. If it
does not, resolve the DUID to `/dev/sdNa` with `hw.disknames`, as `~/bin/mnt` does.
The `inet 100.64.0.3 ` pattern matches today's `ifconfig tun0` output (verified).

Keep `navidrome_flags=NO` (do not `rcctl enable` it, and do not add it to
`pkg_scripts`). Create the mount point as `root:wheel 755`. If the disk is not
mounted, `_navidrome` cannot create `/music/.navidrome` there, so Navidrome cannot
start on an empty folder (inference about Navidrome's behaviour when its data folder
cannot be created).

### Important 1: a boot-enabled Navidrome races tailscaled

**Verified:** `Address = "100.64.0.3"`; `rc_bg=YES` for navidrome, tailscaled and
headscale; tailscaled gets that address only after it reaches Headscale through
relayd on port 443 of the same machine.

**Inference:** if Navidrome starts first, its listen call fails, Navidrome exits, and
`rcctl` still reports success because the daemon runs in the background.

**Fix:** the wait loop in the `rc.local` above. Binding to `0.0.0.0` would also work,
because pf already limits 4533 to `tun0`, but it gives up one layer of protection.

### Important 2: do not copy the Navidrome database; start a fresh one

**Verified:** track IDs are the MD5 of the absolute path, so a new `MusicFolder`
gives all 4,523 tracks new IDs. All 247 playlists are stored by their
`/mnt/MyMusic/playlists/...` path. The database holds no play counts, stars,
ratings, bookmarks or play queues, and was created on 2026-11-09.

**Inference:** after a copy plus a path change, the 0.51 scanner imports every track
and every playlist again under the new path. The old playlist rows stay behind with
no playable tracks, so clients show about 494 playlists. Old track rows may also
stay, because they are outside the new folder.

**Fix:** set `DataFolder = "/music/.navidrome"` with an empty folder. On first start,
create the user `pancia` with the same password, so phone clients keep working.
Then let the first full scan run (30 minutes or more on this disk). Check afterwards:
4,523 tracks and 247 playlists. The playlists use relative paths
(`../my-music/<id>.m4a`, verified in `push.cmd.rb`), so they survive the move
unchanged. Keep `/mnt/.navidrome` as it is, as the undo.

If you copy the database anyway, stop Navidrome first. The 71 MB WAL file holds
recent writes, and a copy of `navidrome.db` alone loses them.

### Important 3: the encrypted copy of the music stops getting new tracks

**Verified:** `music push` writes to one place only. After step 7 that is the new
disk.

**Inference:** from then on, new tracks exist only on an unencrypted HDD block
volume with no snapshot, and in ProtonDrive. `/mnt/MyMusic`, the only copy with an
independent lineage, slowly goes out of date. Nobody will notice.

**Fix:** have `~/bin/mnt` (or a separate `~/bin/music-backup`) copy new files after
each unlock, add-only:

```sh
doas /usr/local/bin/rsync -rtp --ignore-existing /music/MyMusic/my-music/ /mnt/MyMusic/my-music/
doas /usr/local/bin/rsync -rtpc /music/MyMusic/playlists/ /mnt/MyMusic/playlists/
```

Never use `--delete`, for the reason `remote-sync` documents. Run it only after
`crypt-mounted` succeeds.

### Important 4: syspatch has 75 patches, and errata 001 needs its workaround here

**Verified:** `syspatch -c` lists 001 to 075. Errata 001 says syspatch can fail
"probably because /usr is not a separate filesystem". `/usr` is on `/` here. The
errata's steps:

```sh
doas sh -c "sed -e 's/.checkfs/#checkfs/g' /usr/sbin/syspatch > /root/syspatch"
doas ksh /root/syspatch
doas syspatch          # run again as instructed, until syspatch -c prints nothing
doas rm /root/syspatch
doas dev_mkdb
```

Run plain `doas syspatch` first. Use the steps above only if it fails.

Other patch effects, from the errata page (data) and the server:

- **Errata 018** (pledge `tmppath` removed): "ports that use pledge tmppath have to be
  adapted and rebuilt before rebooting". None of the listed ports are installed
  (verified). Headscale, tailscale, Navidrome and rsync are not mentioned.
- **pledge and unveil** (015 to 019, 022, 047): base programs only. relayd, httpd and
  acme-client are base and are patched together with the kernel.
- **TLS:** 004 (libssl) and 060 (LibreSSL) change the libraries relayd and
  acme-client use. 013 fixes httpd. No relayd, sshd, softraid, vioblk, ffs or tun
  patch.
- **Memory and space:** 530 MB free, 17.7 GB free on `/`, relink tree 708 MB. That is
  enough for the relink (inference).
- **Boot time:** the first boot after a kernel or libc patch reorders libraries before
  the daemons start, and relinks the kernel after them. Expect a slower boot. Wait
  for `pgrep -f reorder_kernel` to show nothing before the next restart.

### Important 5: restart cleanly, and keep a kernel to fall back to

**Inference:** the Vultr console "Restart" is a hard reset. The last unclean
shutdown is what needed the manual fsck.

**Fix:**

- Before syspatch: `doas cp -p /bsd /bsd.pre-syspatch`. If the new kernel does not
  boot, type `boot /bsd.pre-syspatch` at the `boot>` prompt in the Vultr console.
- Restart from SSH: `~/bin/unmnt` (the new one), check that it says locked, then
  `doas shutdown -r now`. Do not use the console button except as a last resort.
- Check in the Vultr console that the snapshot shows as complete before you start.

### Medium 1: server-check reports the wrong things after the move

**Verified:** `server-check` tests Navidrome only when the disk is unlocked
(`elif`), and alerts "disk locked: run bin/mnt" every day while it is locked.

**Fix:**

- server-health prints `musicdisk` if `/music` is mounted, `unlocked` from
  `crypt-mounted`, and keeps the `navidrome` ping.
- server-check tests the music disk and Navidrome on their own.
- A locked disk now only pauses the AKR and remote-sync backups. Decide whether it
  stays a daily alert or becomes a softer message such as "backups paused: disk
  locked".

### Medium 2: permissions on the new disk

**Verified:** BSD gives new files the group of their parent folder. That is how
tracks get `_navidrome` today.

**Fix:**

```sh
doas mkdir /music                                  # root:wheel 755, on the root disk
doas mount /music
doas install -d -o anthony -g _navidrome -m 750 /music/MyMusic
doas install -d -o _navidrome -g _navidrome -m 700 /music/.navidrome
doas /usr/local/bin/rsync -aH /mnt/MyMusic/ /music/MyMusic/
doas /usr/local/bin/rsync -aHn -c -i /mnt/MyMusic/ /music/MyMusic/   # must print nothing
```

Stop Navidrome for the copy. `-a` as root keeps owner, group, mode and times.
`musicread` has no chroot, so it can read anything that is world-readable or
readable by `_navidrome`. That is fine for `/music`.

After the move, `doas chgrp wheel /mnt` (while it is mounted, so the encrypted file
system's root changes). Navidrome no longer needs `/mnt`. This removes the "new
folders inherit `_navidrome`" trap, and stops `musicread` listing the private folder
names.

### Medium 3: everything on the Mac and server that names the old paths

| File | Change |
|---|---|
| `lib/ruby/music/push.cmd.rb` | `PUSH_REMOTE`, `PUSH_TRACKS`, `PUSH_PLAYLISTS` to `/music/MyMusic/...`. `PUSH_MOUNTED` to a check that `/music` is mounted (for example `mount \| grep -q ' on /music type ffs'`), not the encrypted-disk check |
| `services/music-mount/script.sh` | `music-server:/music/MyMusic/my-music`; comment about the locked disk; then `service restart music-mount`. The VFS cache refills once |
| `services/server-check/script.sh` | see Medium 1 |
| `~/ProtonDrive/bin/remote-sync` | `MOUNTED_CHECK` to `/usr/local/bin/crypt-mounted`. Paths stay on `/mnt` |
| `~/AKR/vcs-hooks/post-commit` | `MOUNT_CHECK` to `/usr/local/bin/crypt-mounted`. Paths stay on `/mnt` |
| `/etc/navidrome.toml` | `MusicFolder`, `DataFolder`, and the comments about not enabling at boot |
| `~/bin/mnt`, `~/bin/unmnt` | Critical 1 versions, then remove the Navidrome start and stop |
| `/usr/local/bin/server-health` | Medium 1 |
| `CLAUDE.md`, "Music streaming" | paths, the `/dev/sd2a` check, Navidrome at boot, the encrypted backup copy, the `/mnt` group rule |
| `remote/anthonydambrosio.me/README.md` | the Navidrome row; the stale "Encrypted Storage" `m` / `m-x` section; a disks section with the four DUIDs |
| `.cc/scripts/navidrome-m3u.py` | comment that names `/mnt/MyMusic/playlists/` |
| `~/.config/rclone/rclone.conf` | no change: the remote has no path in it (verified) |

Do not run `music push`, `remote-sync` or a manual AKR hook while the migration is
in progress.

### Low

- `/bsd.sp` is dated Apr 28 2023, so it is a 7.3-era kernel. Never boot it. Delete
  it when convenient. (verified date)
- Headscale has no `/mnt` dependency (verified). The new boot path does not touch it.
- Consider a second restart at the end, **without** unlocking. It proves that music
  works with the encrypted disk locked, which is the whole point of the change.

## Corrected order

| # | Step | Verify | Undo |
|---|---|---|---|
| 0 | Check the Vultr snapshot is complete. `doas cp -p /bsd /bsd.pre-syspatch`. Install `crypt-mounted`, the new `mnt`/`unmnt` (Navidrome lines kept for now), and the new server-health line. Switch remote-sync and the AKR hook to `crypt-mounted` | `crypt-mounted` exits 0 now; `server-check` dry run shows no problem | restore the `*.bak-*` scripts |
| 1 | `doas syspatch`; errata 001 steps if it fails; repeat until `syspatch -c` is empty | `syspatch -l` lists 001-075 | `syspatch -r` (one patch per run, newest first), or snapshot restore |
| 2 | `~/bin/unmnt` (says locked), then `doas shutdown -r now`, with the console open | console reaches login; `uname -v` is a new build; `curl https://hs.anthonydambrosio.me/health` from the Mac; `tailscale status`; `ifconfig tun0` shows 100.64.0.3; `doas rcctl check relayd httpd headscale tailscaled` | `boot /bsd.pre-syspatch` at `boot>`; snapshot restore |
| 3 | Do **not** unlock yet. Find the 40 GB disk by size and empty label (Critical 2). fdisk, disklabel, newfs. Add the `noauto 0 0` fstab line. `mkdir /music`, mount, create the two folders | `disklabel` of `sd1` still shows `a: RAID`; `df -h /music` shows ~39 GB | remove the fstab line; `rmdir /music` |
| 4 | `~/bin/mnt` (new). Do not start Navidrome | `crypt-mounted` exits 0; `ls /mnt` shows the private folders | `~/bin/unmnt` |
| 5 | Copy `MyMusic` with rsync as root (Medium 2). Do not copy `.navidrome` | checksum dry run prints nothing; file counts match | delete `/music/MyMusic`; the original is untouched |
| 6 | Edit `navidrome.toml`. `doas rcctl -f start navidrome`. Create `pancia`. Wait for the full scan | web UI and a phone client play; 4,523 tracks and 247 playlists | restore the old toml; start with the old data folder |
| 7 | Add `/etc/rc.local` and `/etc/rc.shutdown`. Remove the Navidrome lines from `mnt`/`unmnt`. Update push, music-mount, server-health, server-check, docs | `music -n push` lists 0 to send; `service restart music-mount` then play in cmus | revert the files |
| 8 | `~/bin/unmnt`, then `doas shutdown -r now`, and do not unlock | music plays from the phone and cmus with the disk locked; `server-check` dry run gives only the locked-disk message you chose | `rcctl -f start navidrome` by hand; fix `rc.local` |
| 9 | Unlock. Add the add-only `/music` to `/mnt` sync (Important 3). `doas chgrp wheel /mnt` | sync runs with no errors; `ls -ld /mnt` shows `wheel` | `chgrp _navidrome /mnt` |

Effort: about 2 to 3 hours including the two scans and the two restarts. Most of it
is waiting.
