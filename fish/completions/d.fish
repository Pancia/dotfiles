# Completions for directory bookmark system (d)

# Get list of bookmarks dynamically (fast - reads files directly)
function __d_bookmarks
    ls -1 ~/.config/d 2>/dev/null
end

# d - navigate to bookmark
complete -c d -f -a '(__d_bookmarks)' -d 'Navigate to bookmarked directory'

# d! - set bookmark
complete -c d! -f -a '(__d_bookmarks)' -d 'Set directory bookmark'

# de - edit bookmark
complete -c de -f -a '(__d_bookmarks)' -d 'Edit directory bookmark'

# d_ - delete bookmark
complete -c d_ -f -a '(__d_bookmarks)' -d 'Delete directory bookmark'
