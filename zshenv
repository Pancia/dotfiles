function cache {
    #This function has to be in zshenv because of what zsh loads for scripts
    #see wiki/zsh
    local cache_root="$HOME/.cache/dot-cache"

    case "$1" in
        clear|purge) command rm -r $cache_root ;;
        *)
            local stamp_file="$cache_root/`pwd`/cache.$1.date"
            local interval="$2"
            local now=$(date +%s 2>/dev/null)
            local last=$(cat $stamp_file 2>/dev/null || echo '0')

            local SEC_TO_MIN=60
            local delta=$(($now-$last))
            interval=$(($interval*SEC_TO_MIN))
            if [ $delta -ge $interval ]; then
                local script="$(cat /dev/stdin)"
                zsh -c "$script"
                mkdir -p "$(dirname $stamp_file)" && echo "$now" > $stamp_file
            fi
            ;;
    esac
}

export SHELL=/bin/zsh
export LEIN_SUPPRESS_USER_LEVEL_REPO_WARNINGS=1
export EDITOR='nvim'
export GIT_EDITOR='nvim'
export XDG_CONFIG_HOME=~/.config
export FEATURE_BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null | sed -e 's/feature.//')"
export NVIM_LISTEN_ADDRESS=/tmp/mynvimsocket

#rust - racer integration
export PATH="$HOME/.cargo/bin:$PATH"
export RUST_SRC_PATH="$HOME/.rustup/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src/:$PATH"

#git (& ∴ less) doesn't show UTF-8 file properly
export LESSCHARSET=UTF-8

setopt IGNORE_EOF

export BOOT_JVM_OPTIONS='-XX:-OmitStackTraceInFastThrow'

export PATH="$HOME/.jenv/shims:$PATH"

[ -e ~/dotfiles/extra.env.zsh ] && source ~/dotfiles/extra.env.zsh
