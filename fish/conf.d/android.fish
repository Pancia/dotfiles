# Android development environment
set -gx GRADLE_HOME "/usr/local/opt/gradle/libexec"
# GRADLE_USER_HOME set in 00_xdg.fish
set -gx ANDROID_HOME "/Users/anthony/Library/Android/sdk/"
fish_add_path --prepend "$ANDROID_HOME/platform-tools"
