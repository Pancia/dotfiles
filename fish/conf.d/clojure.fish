# Clojure development environment
set -gx BOOT_JVM_OPTIONS '-XX:-OmitStackTraceInFastThrow'
set -gx LEIN_SUPPRESS_USER_LEVEL_REPO_WARNINGS 1
fish_add_path --append "$HOME/Developer/datomic-cli"
