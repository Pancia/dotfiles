# Music management configuration
set -gx MUSIC_VAULT   "$HOME/vaults/music"
set -gx MUSIC_CATALOG "$MUSIC_VAULT/my-music.json"
# Where imports and tagging write. Same folder as MUSIC_CLOUD since the USB drive died.
set -gx MUSIC_LIBRARY "$HOME/Cloud/Music/music-db/"
# Read-only view of the server's music, for playback (services/music-mount).
# Keep this separate from MUSIC_LIBRARY: imports and tagging cannot write to it.
set -gx MUSIC_PLAYBACK "$HOME/Music/music-server/"
set -gx MUSIC_CLOUD   "$HOME/Cloud/Music/music-db/"
set -gx MUSIC_BACKUPS "$HOME/Cloud/backups/music-restic"
set -gx MUSIC_INBOX   "$HOME/Cloud/ytdl/music/"
