#!/usr/bin/env bash
# Daily expiry of the claude-scratch root (bin/scratch): deletes runs and
# discard batches past SCRATCH_KEEP_DAYS (14), and the oldest past
# SCRATCH_MAX_GB (5) or below SCRATCH_MIN_FREE_GB (10) free, never anything
# younger than 3 days. Every delete goes to the scratch audit log
# (`scratch log`). A cap it cannot meet sends one notification.
#
# The only place anything in the scratch root is deleted. `scratch expire`
# refuses to run inside a Claude session, so only launchd or the user deletes.
# Preview what it would delete: ~/dotfiles/bin/scratch expire --dry-run
exec "$HOME/dotfiles/bin/scratch" expire --notify
