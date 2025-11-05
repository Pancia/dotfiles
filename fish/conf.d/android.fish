# Android development environment
set -gx GRADLE_HOME "/usr/local/opt/gradle/libexec"
set -gx ANDROID_HOME "/Users/pancia/Library/Android/sdk/"
fish_add_path --prepend "$ANDROID_HOME/platform-tools"
