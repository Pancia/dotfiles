# Android development environment
set -gx GRADLE_HOME "/usr/local/opt/gradle/libexec"
set -gx GRADLE_USER_HOME "$HOME/.cache/gradle"
set -gx ANDROID_HOME "/Users/anthony/Library/Android/sdk/"
fish_add_path --prepend "$ANDROID_HOME/platform-tools"
