#!/usr/bin/env zsh

echo "$(date): bookmark-manager service started"

cd ~/projects/bookmarks_manager && npm run service
