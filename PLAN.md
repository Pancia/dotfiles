# Dotfiles: Version Manager Consolidation Plan

## Goal

Replace individual version managers with a single tool to manage all
runtime/language versions, with per-project pinning via `.tool-versions`.

## Tool Choice: mise vs asdf

| | asdf | mise |
|---|---|---|
| Language | Shell | Rust (faster) |
| Reads `.tool-versions` | Yes | Yes |
| asdf plugin compatible | N/A | Yes |
| Env var management | No | Yes |
| Task runner | No | Yes |
| Status | Mature, large ecosystem | Actively developed, drop-in replacement |

**Recommendation:** Use **mise** — it's faster, backwards-compatible with asdf
plugins and `.tool-versions`, and adds env var and task runner features.

## What to Manage

Tools detected in this dotfiles repo that have asdf/mise plugins:

| Tool | Evidence | Plugin |
|---|---|---|
| Ruby | `Gemfile` | `ruby` |
| Clojure | `lib/clojure/` | `clojure` |
| clj-kondo | `lib/clojure/my-kondo/` | `clj-kondo` |
| Java | `gradle.properties` (JVM) | `java` |
| Gradle | `rcs/gradle.properties` | `gradle` |
| Lua / LuaJIT | `lib/lua/` (Hammerspoon) | `lua` / `luaJIT` |
| Neovim | `nvim/` config | `neovim` |
| Python | `misc/parse-zsh-profiling.py` | `python` |
| Node.js | `ftplugin/javascript.vim` | `nodejs` |
| Rust | `nvim/plugs/rust.vim` | `rust` |
| peco | `rcs/peco.json` | `peco` |
| uv | Python package management | `uv` |

## What Stays in Homebrew

Brew remains the right choice for system tools and apps that don't need
per-project versioning:

- git, tmux, ripgrep, fd, fzf, jq
- GUI apps (via cask)
- Libraries and system dependencies
- mise/asdf itself (`brew install mise`)

## Steps

### 1. Install mise

```sh
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc  # or fish equivalent
```

### 2. Create global `.tool-versions`

```sh
# ~/.tool-versions
nodejs 22.x
python 3.12.x
ruby 3.3.x
java temurin-21
clojure 1.12.x
lua 5.4.x
neovim stable
rust stable
peco latest
uv latest
```

### 3. Install everything

```sh
mise install
```

### 4. Per-project overrides

Add `.tool-versions` to individual project repos as needed:

```sh
cd ~/projects/some-legacy-app
mise use nodejs@18
# creates/updates .tool-versions in that directory
```

### 5. Remove old version managers

Once mise is working, uninstall any individual managers:

- nvm / fnm
- pyenv
- rbenv
- sdkman
- rustup (optional — some prefer keeping rustup for Rust)

### 6. Commit `.tool-versions` to dotfiles

Track the global config alongside existing dotfiles so it's reproducible
across machines.

## mise and uv: How They Interact

mise and uv are **complementary, not competing** — they operate at different layers:

| Tool | Layer | What it does |
|---|---|---|
| **mise** | Version manager | Installs/switches versions of `uv`, `python`, `node`, etc. |
| **uv** | Python project manager | Replaces pip, poetry, virtualenv — manages venvs, deps, lockfiles |

**Do not uninstall uv.** mise installs uv; uv manages your Python packages.

### Avoiding overlap: Python versions

Both mise and uv can install Python. Pick one source to avoid conflicts:

| Approach | Setup | Best for |
|---|---|---|
| **mise provides Python** | `mise use python@3.12`, uv finds it automatically | Consistency — mise is the single source for all runtimes |
| **uv provides Python** | `uv python install 3.12`, remove `python` from `.tool-versions` | Simplicity — fewer moving parts if Python/uv is your main use case |

### Recommendation

Let **uv manage Python** (it does this well and auto-downloads the right version
per-project via `uv sync`). Use **mise to manage uv itself** plus all non-Python
runtimes. Remove `python` from the global `.tool-versions` to avoid conflicts.

## Not in Scope

- Docker/devcontainers — separate concern, overkill for local dev tooling
- Nix — powerful but steep learning curve, revisit later if needed
