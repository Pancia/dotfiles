# Homebrew configuration
if test -d /opt/homebrew
    eval (/opt/homebrew/bin/brew shellenv)
end

set -gx HOMEBREW_NO_AUTO_UPDATE 1
