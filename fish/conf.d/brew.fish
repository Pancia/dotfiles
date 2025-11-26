# Homebrew configuration
if test -d /opt/homebrew
    eval (/opt/homebrew/bin/brew shellenv)
end

# potentially not needed, they might've made it faster/better?
#set -gx HOMEBREW_NO_AUTO_UPDATE 1
