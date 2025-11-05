# Rust environment (racer integration)
fish_add_path --prepend "$HOME/.cargo/bin"
set -gx RUST_SRC_PATH "$HOME/.rustup/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src/"
