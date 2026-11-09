# Homebrew to MacPorts Migration (Hybrid)

Evaluating a hybrid approach: MacPorts for CLI tools, Homebrew casks for GUI apps.

## CLI Packages — Available in MacPorts (~80%)

fish, fzf, bat, fd, ripgrep, the_silver_searcher, eza, yazi, cloc, difftastic,
git, gradle, jq, lua, luarocks, maven, neovim, nginx, node, postgresql, python,
pyenv, pipx, redis, rename, rlwrap, rsync, ruby, tldr, tree, vnstat, watchman,
wget, yarn, cmus, ffmpeg, exiftool, yt-dlp, awscli, restic, tailscale, gallery-dl

## CLI Packages — Missing/Problematic in MacPorts

| Package | Issue | Workaround |
|---------|-------|------------|
| yabai | Not in MacPorts | Build from source / standalone installer |
| babashka | Custom tap (`borkdude/brew`) | Build from source |
| clj-kondo | Custom tap (`borkdude/brew`) | Build from source |
| planck | Niche Clojure tool | Build from source |
| clojure | MacPorts has it but may lag | Check version parity |
| git-flow-avh | May not exist | Check for `git-flow` port |
| flow | Facebook JS type checker, uncertain | Check MacPorts |
| switchaudio-osx | Homebrew-specific | Manual install |
| terminal-notifier | May not be in MacPorts | Manual install |
| sshpass | Sometimes excluded for security | Check MacPorts |
| peco | Uncertain | Check MacPorts |
| watchexec | Uncertain | Check MacPorts |
| bitwarden-cli | npm package | `npm i -g @bitwarden/cli` |

## Casks — Keep in Homebrew

No MacPorts equivalent for cask installs. Keep Homebrew for GUI apps:

android-platform-tools, bitwarden, blackhole-2ch, claude-code, deluge, ghostty,
hammerspoon, iterm2@beta, karabiner-elements, kitty, stats, xquartz

## Hardcoded Paths to Rewrite (~17 instances)

MacPorts uses `/opt/local` instead of `/opt/homebrew`.

### Service shebangs (6 files)
All use `#!/opt/homebrew/bin/fish`:
- `services/youtube-transcribe/`
- `services/syncthing/script.sh`
- `services/wget_server/`
- `services/bookmark-manager/script.sh`
- `services/lakshmi/script.sh`
- `services/copyparty/script.sh`

### bin/ scripts
- `bin/bat` — execs `/opt/homebrew/bin/bat`
- `bin/g` — subprocess shell `/opt/homebrew/bin/fish`
- `bin/service-wrapper` — pipes to `/opt/homebrew/bin/ts`
- `bin/cmselect` — AppleScript references `/opt/homebrew/bin/fish`

### fish/conf.d/
- `brew.fish` — `brew shellenv`, `HOMEBREW_NO_AUTO_UPDATE`
- `ruby.fish` — `/opt/homebrew/opt/ruby/bin` in PATH
- `asdf.fish` — `/opt/homebrew/opt/asdf/libexec/asdf.fish`
- `android.fish` — GRADLE_HOME at `/usr/local/opt/gradle/libexec`

### Services
- `services/vpc/dotfiles-services-vpc.sh` — `/opt/homebrew/opt/ruby/bin/ruby`
- `services/wget_server/` — `/opt/homebrew/bin/uv`
- `services/copyparty/` — `/opt/homebrew/bin/copyparty`
- `services/youtube-transcribe/` plist PATH includes `/opt/homebrew/bin`

## Fish Integration That Changes

| Current (Homebrew) | Replacement (MacPorts) |
|---------------------|------------------------|
| `brew shellenv` in `conf.d/brew.fish` | Add `/opt/local/bin` etc. to PATH manually |
| Custom `brew` wrapper in `functions/brew.fish` | Remove or repurpose (keep minimal for casks) |
| `brew bundle` in `install` script | Script `port install` calls from a package list |
| `brew services` for vnstat | `port load/unload` |
| Vendor completions at `/opt/homebrew/share/fish/vendor_completions.d/` | `/opt/local/share/fish/vendor_completions.d/` |

## Migration Strategy

1. Install MacPorts
2. Create a `Portfile` list (equivalent to Brewfile) for CLI tools
3. Update `install` script with `port install` task
4. Rewrite hardcoded `/opt/homebrew` paths to `/opt/local` for MacPorts-installed tools
5. Split `conf.d/brew.fish` into `macports.fish` (PATH setup) + slim `brew.fish` (casks only)
6. Slim down Brewfile to casks + any CLI tools that must stay in Homebrew
7. Update service plists and shebangs
8. Test all LaunchAgents boot correctly
