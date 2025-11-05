# macOS helper functions
function showFiles --description 'Show hidden files in Finder'
    defaults write com.apple.finder AppleShowAllFiles YES
end

function hideFiles --description 'Hide hidden files in Finder'
    defaults write com.apple.finder AppleShowAllFiles NO
end
