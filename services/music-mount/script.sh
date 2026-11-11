#!/usr/bin/env bash
# Show the music on the Vultr server as a local folder, for cmus.
#
# Read-only on purpose: the server copy is what Navidrome serves.
# Needs the rclone remote "music-server" (sftp, ~/.config/rclone/rclone.conf). It logs
# in as "musicread" with ~/.ssh/music_mount, which has no passphrase so this works after
# a restart. The server limits that key to read-only file access.
# The music lives on the server's unencrypted /music disk, so it works while the
# encrypted /mnt is locked. /mnt/MyMusic is an old copy.
#
# Do NOT mount this at $MUSIC_LIBRARY. The nightly `music backup` copies that
# path over ProtonDrive, and these files are older.

mount_point="$HOME/Music/music-server"
mkdir -p "$mount_point"

# A previous run that died leaves a dead mount behind, and rclone refuses it.
if /sbin/mount | grep -q " on $mount_point "; then
    /sbin/umount -f "$mount_point"
fi

echo "$(date): mounting music-server at $mount_point"
exec /opt/homebrew/bin/rclone nfsmount music-server:/music/MyMusic/my-music "$mount_point" \
    --read-only \
    --vfs-cache-mode full \
    --vfs-cache-max-size 2G \
    --vfs-cache-max-age 24h \
    --dir-cache-time 168h \
    --vfs-fast-fingerprint \
    --sftp-idle-timeout 0 \
    --log-level NOTICE
