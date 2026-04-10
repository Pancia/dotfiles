# Music management configuration
set -gx MUSIC_VAULT   "$HOME/vaults/music"
set -gx MUSIC_CATALOG "$MUSIC_VAULT/my-music.json"
set -gx MUSIC_LIBRARY "/Volumes/vansuny128/music-db/"
set -gx MUSIC_CLOUD   "$HOME/Cloud/Music/music-db/"
set -gx MUSIC_BACKUPS "$HOME/Cloud/backups/music-restic"
set -gx MUSIC_INBOX   "$HOME/Cloud/ytdl/music/"
