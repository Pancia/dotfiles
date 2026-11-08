function toggleHiddenFiles --description 'Toggle hidden files in Finder and relaunch it'
    set -l current (defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)
    switch (string lower -- "$current")
        case yes true 1
            defaults write com.apple.finder AppleShowAllFiles NO
        case '*'
            defaults write com.apple.finder AppleShowAllFiles YES
    end
    # Finder only reads this setting at launch.
    killall Finder
end
