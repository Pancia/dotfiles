function bat --wraps bat
    # Detect macOS appearance mode and set theme accordingly
    if defaults read -g AppleInterfaceStyle &>/dev/null
        # Dark mode
        command bat --theme="Monokai Extended" $argv
    else
        # Light mode
        command bat --theme="Monokai Extended Light" $argv
    end
end
