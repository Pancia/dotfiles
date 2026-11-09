#!/usr/bin/env bash
# Show the music on the Vultr server as a local folder, for cmus.
#
# Read-only on purpose: /mnt/MyMusic is the only independent copy of the library.
# Needs the rclone remote "music-server" (sftp, ~/.config/rclone/rclone.conf).
# If the server's encrypted disk is locked, the folder is empty: run bin/mnt there.
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
exec /opt/homebrew/bin/rclone nfsmount music-server:/mnt/MyMusic/my-music "$mount_point" \
    --read-only \
    --vfs-cache-mode full \
    --vfs-cache-max-size 2G \
    --vfs-cache-max-age 24h \
    --dir-cache-time 168h \
    --vfs-fast-fingerprint \
    --sftp-idle-timeout 0 \
    --log-level NOTICE
