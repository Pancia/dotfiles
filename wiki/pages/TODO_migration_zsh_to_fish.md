# Migration Outline: zsh → fish

## 1. Directory & File Structure Changes

**Current:** `~/dotfiles/zsh/`
**New:** `~/dotfiles/fish/` or `~/dotfiles/config/fish/`

- `rcs/zshrc` → `rcs/config.fish` (main config file)
- `rcs/zshenv` → Environment vars move into `config.fish` or `conf.d/` files
- `zsh/init.zsh` → `fish/config.fish`
- `zsh/functions.zsh` → `fish/functions/*.fish` (one file per function)
- `zsh/fns/*.zsh` → `fish/functions/*.fish` (auto-loaded)
- `zsh/env/*.zsh` → `fish/conf.d/*.fish` (auto-loaded on startup)
- `zsh/completions/` → `fish/completions/` (different syntax)

## 2. Plugin Management Migration

**Current:** Antigen (oh-my-zsh plugins)
**Options:**
- **Fisher** (recommended, minimal like Antigen)
- **Oh My Fish** (similar to oh-my-zsh)
- **Tide** (modern, built-in plugin manager)

**Plugins to replace:**
- `zsh-autosuggestions` → Built into fish natively!
- `zsh-syntax-highlighting` → fish-syntax-highlighting or built-in
- `zsh-history-substring-search` → Built into fish natively!
- `powerlevel9k` → Tide, Starship, or Pure (fish versions)
- oh-my-zsh git plugin → fish has git completions built-in
- oh-my-zsh brew plugins → fish has brew completions built-in

## 3. Syntax Changes Required

**Major differences:**

| zsh | fish |
|-----|------|
| `function name { ... }` | `function name; ...; end` |
| `[[ condition ]]` | `test condition` or `[ condition ]` |
| `$variable` | `$variable` (same for reading) |
| `variable=value` | `set variable value` |
| `export VAR=value` | `set -x VAR value` |
| `local var=value` | `set -l var value` |
| `source file` | `source file` (same) |
| `&&` / `||` | `and` / `or` |
| `$@` | `$argv` |
| `$(command)` | `(command)` |
| `for i in ...; do` | `for i in ...; ... ; end` |
| `if [...]; then` | `if test ...; ... ; end` |

## 4. Function & Alias Migration

**Simple aliases** (mostly unchanged):
```fish
# Current: alias ga='git add'
alias ga 'git add'  # fish syntax
```

**Function wrappers** need rewriting:
```fish
# Current zsh/functions.zsh:
# function cat { bat "$@" }

# Fish version:
function cat
    bat $argv
end
```

**All 20+ files in `zsh/fns/`** need syntax conversion:
- `fns/git.zsh` → `functions/git_*.fish` (split aliases into functions)
- `fns/music.zsh` → `functions/music.fish`
- `fns/ai.zsh` → `functions/ai.fish`
- `fns/asdf.zsh` → `functions/asdf.fish`
- `fns/bak.zsh` → `functions/bak.fish`
- `fns/chpwd.zsh` → `functions/chpwd.fish`
- `fns/clojure.zsh` → `functions/clojure.fish`
- `fns/cmds.zsh` → `functions/cmds.fish`
- `fns/ctrl-z.zsh` → `functions/ctrl-z.fish`
- `fns/d.zsh` → `functions/d.fish`
- `fns/help.zsh` → `functions/help.fish`
- `fns/osx.zsh` → `functions/osx.fish`
- `fns/pyenv.zsh` → `functions/pyenv.fish`
- `fns/python.zsh` → `functions/python.fish`
- `fns/q.zsh` → `functions/q.fish`
- `fns/search.zsh` → `functions/search.fish`
- `fns/security.zsh` → `functions/security.fish`
- `fns/trash.zsh` → `functions/trash.fish`
- `fns/vim.zsh` → `functions/vim.fish`
- `fns/vims.zsh` → `functions/vims.fish`
- `fns/watch.zsh` → `functions/watch.fish`
- `fns/z.zsh` → `functions/z.fish`

## 5. Prompt/Theme Migration

**Current:** Powerlevel9k via Antigen
**Options:**
- **Tide** (modern, customizable, most similar to Powerlevel10k)
- **Starship** (cross-shell, very popular)
- **Pure** (minimal)
- Custom fish prompt

**Your theme config:**
```zsh
# zsh/theme.zsh
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time)
POWERLEVEL9K_SHORTEN_STRATEGY="truncate_middle"
POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
```

Would become (with Tide):
```fish
tide configure  # interactive setup
```

## 6. Completions

**Current:** Custom zsh completions in `zsh/completions/`

Fish has **different completion syntax**:
```zsh
# Current (_notes):
function _notes { __eval_completion notes --zsh-completions }
```

```fish
# Fish version (completions/notes.fish):
complete -c notes -a '(notes --fish-completions)'
```

**Action:** Rewrite all 4 completion files:
- `_notes` → `completions/notes.fish`
- `_cmds` → `completions/cmds.fish`
- `_q` → `completions/q.fish`
- `_d` → `completions/d.fish`
- `_music` → `completions/music.fish`

## 7. Key Bindings

**Current** (`zsh/setup.zsh`):
```zsh
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
```

**Fish version:**
```fish
# fish has history search built-in with up/down arrows
# For custom bindings:
bind \e\[A history-search-backward  # Up arrow
bind \e\[B history-search-forward   # Down arrow

# VI mode:
fish_vi_key_bindings
```

## 8. Shell Options & History

**Current:**
```zsh
setopt EXTENDED_HISTORY
setopt IGNORE_EOF
setopt HIST_IGNORE_SPACE
```

**Fish equivalents:**
```fish
# Fish history is advanced by default
set -U fish_greeting ""  # disable greeting
set -U fish_key_bindings fish_default_key_bindings

# History settings go in config.fish:
# (most are defaults in fish)
```

## 9. Hooks & Events

**Current:**
```zsh
function zshaddhistory() { record_dir_change; return 0 }
function chpwd() { ... }
```

**Fish version:**
```fish
function __fish_on_directory_change --on-variable PWD
    record_dir_change
end

# Or use fish's built-in events:
function my_prompt --on-event fish_prompt
    # runs before each prompt
end
```

## 10. Initialization & RC Management

**Current complex system:**
- `rcs/zshrc` → sources `zsh/zshrc`
- `zsh/zshrc` → manages linking, services, calls init
- Profiling support with `PROF=1` flag

**Fish simpler approach:**
```fish
# config.fish handles everything
# conf.d/*.fish auto-loads
# functions/*.fish auto-loads on demand
```

**Your `_ENSURE_RCS` and `_ENSURE_SERVICES` functions** would need:
- Rewrite in fish syntax
- Move to `functions/ensure_rcs.fish` and call from `config.fish`
- Move to `functions/ensure_services.fish` and call from `config.fish`

## 11. Environment Variables

**All files in `zsh/env/`** need migration:
- `env/antigen.zsh` → (N/A - using Fisher instead)
- `env/android.zsh` → `conf.d/android.fish`
- `env/bat.zsh` → `conf.d/bat.fish`
- `env/brew.zsh` → `conf.d/brew.fish`
- `env/clojure.zsh` → `conf.d/clojure.fish`
- `env/git.zsh` → `conf.d/git.fish`
- `env/java.zsh` → `conf.d/java.fish`
- `env/music.zsh` → `conf.d/music.fish`
- `env/node.zsh` → `conf.d/node.fish` (use fish-nvm plugin)
- `env/nvim.zsh` → `conf.d/nvim.fish`
- `env/pager.zsh` → `conf.d/pager.fish`
- `env/python.zsh` → `conf.d/python.fish`
- `env/ruby.zsh` → `conf.d/ruby.fish`
- `env/rust.zsh` → `conf.d/rust.fish`

**Strategy:** Convert to `conf.d/` files or source in `config.fish`

## 12. Special Features to Address

**Your custom features that need special attention:**

1. **Prompt command injection** (`zsh/zshrc` lines 36-67):
   - The `ZSHRC prompt` and `ZSHRC eval` functionality
   - Would need fish-specific implementation

2. **Profiling system** (lines 76-113):
   - Fish has `fish --profile` built-in
   - Less need for custom profiling

3. **NVM integration** (lines 71-73):
   - Use `fisher install jorgebucaran/nvm.fish`

4. **Service management** (`_ENSURE_SERVICES`):
   - Can keep as-is, just convert syntax

5. **Directory tracking** (`init.zsh` lines 15-29):
   - Rewrite using fish events

---

## Migration Strategy

### Phase 1: Foundation
1. Install fish shell: `brew install fish`
2. Add fish to `/etc/shells`: `echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells`
3. Create `~/dotfiles/fish/` directory structure:
   ```
   fish/
   ├── config.fish
   ├── conf.d/
   ├── functions/
   └── completions/
   ```
4. Install Fisher plugin manager: `curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher`
5. Install base plugins:
   - `fisher install IlanCosman/tide` (prompt)
   - `fisher install jorgebucaran/nvm.fish` (node version management)

### Phase 2: Core Migration
1. Convert `zsh/env/*.zsh` → `fish/conf.d/*.fish` (14 files)
2. Convert simple aliases in `functions.zsh` → `config.fish`
3. Port `_ENSURE_RCS` and `_ENSURE_SERVICES` → `functions/ensure_rcs.fish` & `functions/ensure_services.fish`
4. Update `rcs/config.fish` to replace `rcs/zshrc`

### Phase 3: Functions
1. Convert all 22 files in `zsh/fns/` to fish syntax
2. Test each function individually
3. Handle git aliases specially (they're used frequently)

### Phase 4: Advanced Features
1. Rewrite 5 completion files
2. Configure key bindings (history search, vi mode)
3. Port directory tracking (`init.zsh` lines 15-29)
4. Handle special initialization logic
5. Configure Tide prompt to match Powerlevel9k appearance

### Phase 5: Testing & Refinement
1. Test all workflows
2. Compare behavior with zsh
3. Fix edge cases
4. Update installation scripts if needed
5. Update documentation

---

## Effort Estimate

- **Simple conversion (basic functionality):** 4-8 hours
- **Full conversion (all features):** 12-20 hours
- **Testing & refinement:** 4-8 hours
- **Total:** 20-36 hours

---

## Key Benefits of Fish

1. **Built-in features** replace many plugins:
   - Autosuggestions (native)
   - Syntax highlighting (native)
   - Better completions (native)
   - Web-based configuration UI (`fish_config`)

2. **Simpler syntax** for most operations
3. **Better defaults** (less configuration needed)
4. **Faster startup** (typically)
5. **Better documentation** and error messages

## Potential Drawbacks

1. **Not POSIX-compliant** - scripts need proper shebangs (`#!/bin/bash` for bash scripts, `#!/usr/bin/env fish` for fish scripts)
2. **Smaller ecosystem** than zsh (but growing)
3. **Learning curve** for syntax differences
4. **Some tools** expect bash/zsh (rare, usually work-aroundable)

---

## Decision Points

Before starting, decide on:

1. **Plugin manager:** Fisher, Oh My Fish, or Tide?
   - Recommendation: **Fisher** (minimal, fast)

2. **Prompt/theme:** Tide, Starship, Pure, or custom?
   - Recommendation: **Tide** (most similar to Powerlevel9k, highly customizable)

3. **Migration approach:** Big bang or gradual?
   - **Big bang:** Convert everything, switch shells, test
   - **Gradual:** Run fish alongside zsh, test features incrementally
   - Recommendation: **Gradual** - keep zsh as default while building fish config

4. **Script conversion:** Convert bin/ scripts or keep as bash?
   - Recommendation: **Keep as bash** (more portable, less work)

---

## Resources

- [Fish Tutorial](https://fishshell.com/docs/current/tutorial.html)
- [Fish Cookbook](https://github.com/jorgebucaran/cookbook.fish)
- [Fish for bash users](https://fishshell.com/docs/current/fish_for_bash_users.html)
- [Fisher plugin manager](https://github.com/jorgebucaran/fisher)
- [Tide prompt](https://github.com/IlanCosman/tide)
- [Awesome Fish](https://github.com/jorgebucaran/awsm.fish) - curated list of packages

---

## Quick Start Commands

```bash
# Install fish
brew install fish

# Add fish to shells
echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells

# Try fish (without changing default shell)
fish

# Install Fisher
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher

# Install Tide prompt
fisher install IlanCosman/tide

# Configure Tide
tide configure

# Change default shell (only after testing!)
chsh -s /opt/homebrew/bin/fish
```
