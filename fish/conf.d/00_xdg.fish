# XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir-spec/latest/
# Loaded first (00_ prefix) so other conf.d files can reference these.

set -gx XDG_CONFIG_HOME ~/.config
set -gx XDG_DATA_HOME ~/.local/share
set -gx XDG_STATE_HOME ~/.local/state
set -gx XDG_CACHE_HOME ~/.cache

# --- Tool relocations (env var support) ---

# Rust/Cargo
set -gx CARGO_HOME $XDG_DATA_HOME/cargo

# Gradle
set -gx GRADLE_USER_HOME $XDG_DATA_HOME/gradle

# npm cache
set -gx npm_config_cache $XDG_CACHE_HOME/npm

# History files -> state
set -gx LESSHISTFILE $XDG_STATE_HOME/less/history
set -gx PYTHON_HISTORY $XDG_STATE_HOME/python/history
set -gx PSQL_HISTORY $XDG_STATE_HOME/psql/history
set -gx NODE_REPL_HISTORY $XDG_STATE_HOME/node/history
set -gx SQLITE_HISTORY $XDG_STATE_HOME/sqlite/history

# Docker
set -gx DOCKER_CONFIG $XDG_CONFIG_HOME/docker

# AWS CLI
set -gx AWS_CONFIG_FILE $XDG_CONFIG_HOME/aws/config
set -gx AWS_SHARED_CREDENTIALS_FILE $XDG_CONFIG_HOME/aws/credentials

# Clojure gitlibs cache
set -gx GITLIBS $XDG_CACHE_HOME/gitlibs

# Ollama
set -gx OLLAMA_MODELS $XDG_DATA_HOME/ollama/models

# Ruby
set -gx BUNDLE_USER_HOME $XDG_DATA_HOME/bundle
set -gx GEM_HOME $XDG_DATA_HOME/gem

# Python matplotlib
set -gx MPLCONFIGDIR $XDG_CONFIG_HOME/matplotlib

# Babashka/deps.clj tools cache
set -gx DEPS_CLJ_TOOLS_DIR $XDG_CACHE_HOME/deps.clj

# Elixir Hex
set -gx HEX_HOME $XDG_DATA_HOME/hex

# Maven
set -gx MAVEN_OPTS "-Dmaven.repo.local=$XDG_CACHE_HOME/maven"

# wget hsts
alias wget 'command wget --hsts-file="$XDG_STATE_HOME/wget/hsts"'
