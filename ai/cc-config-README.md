# cc-config

Per-project skill, agent, and command management for Claude Code.

## Problem

Claude Code loads all skills/agents/commands from `~/.claude/` globally. If you have 20+ Clojure skills but you're editing Python, they all still load. Per-project `.claude/skills/` directories exist but manually managing symlinks is tedious.

## Solution

A config file defines a registry of available skills/agents/commands and named groups. Each project gets a `.cc-config` file listing which groups, skills, agents, or commands to activate (one per line). A Fish wrapper syncs the right symlinks into the project's `.claude/` directory before launching Claude.

## Setup

1. Copy `cc-config.json` to `~/dotfiles/ai/cc-config.json` (or wherever — update the path in `cc-config.fish` line 2)
2. Copy `cc-config.fish` to your Fish functions directory (`~/.config/fish/functions/`)
3. Add the wrapper snippet to your Claude Code launcher (see below)
4. Edit `cc-config.json` to register your own skills, agents, commands, and groups

### Wrapper integration

Add this to your Fish function that launches `claude`:

```fish
if test -f .cc-config
    set -l cc_profile (string match -v '//*' < .cc-config | string trim)
    if test -n "$cc_profile"
        cc-config sync $cc_profile
    end
end
```

## cc-config.json format

```json
{
    "skills": {
        "my-skill": "~/path/to/skill-dir",
        "*glob-label": "~/path/to/many/skills/*"
    },
    "agents": {
        "*my-agents": "~/path/to/agents/*"
    },
    "commands": {
        "my-cmd": "~/path/to/my-cmd.md"
    },
    "groups": {
        "#base":    { "skills": ["my-skill"], "agents": ["some-agent"] },
        "#full":    { "skills": ["#base", "extra-skill"], "agents": ["#base"] },
        "#ALL":     "*"
    }
}
```

- **Skills**: directories containing a `SKILL.md`
- **Agents**: individual `.md` files
- **Commands**: individual `.md` files (slash commands)
- **Glob entries** (`*label`): key prefix `*` is convention only. Path ending in `/*` auto-discovers all items in that directory.
- **Groups**: named presets. Values are objects with `skills`/`agents`/`commands` arrays. Members can reference other groups (resolved recursively with cycle detection). `"*"` means all registered items.
- **`#` prefix on groups**: convention to distinguish group names from skill/agent names

## .cc-config format

One item per line. `//` lines are comments.

```
// My project config
#full
extra-standalone-skill
```

## Commands

```
cc-config init                         # Create .cc-config via fzf multi-select picker
cc-config edit                         # Edit .cc-config in $EDITOR with reference comments
cc-config show                         # Show resolved config for current project
cc-config sync [--dry-run] <group...>  # Sync symlinks into .claude/
cc-config list                         # Show all registered items (* = active)
cc-config groups                       # Show group definitions
```

## How sync works

1. Resolves groups recursively to individual skill/agent/command names
2. Looks up each name in the registry to find its path on disk
3. Wipes all symlinks in `.claude/skills/`, `.claude/agents/`, `.claude/commands/`
4. Creates fresh symlinks from registry paths
5. Non-symlink files in those directories are preserved

## Requirements

- Fish shell
- `jq`
- `fzf` (for `init` only)
