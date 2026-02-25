---
name: cmds
description: Use this skill when the user asks you to create, modify, or inspect cmds.rb command definitions for a project. cmds is a per-directory command runner for human use — the AI's role is to help author commands, not execute them.
user-invocable: true
disable-model-invocation: false
---

# cmds — Per-Directory Command Runner

`cmds` (alias `@`) gives each project directory its own named shell commands (`start`, `test`, `deploy`, etc.) for human use. Command definitions live in Ruby files managed inside the dotfiles repo.

## Path Convention

The cmds.rb for any directory lives at:
```
~/dotfiles/cmds/<absolute-path-of-directory>/cmds.rb
```

Example: for `/Users/anthony/projects/lakshmi/`, the file is:
```
~/dotfiles/cmds/Users/anthony/projects/lakshmi/cmds.rb
```

Run `cmds path` from any directory to get the exact path.

## Discovery Commands

| Command | Output |
|---------|--------|
| `cmds path` | Prints the cmds.rb file path for the current directory |
| `cmds describe` | Plain-text list of commands with descriptions (no formatting) |
| `cmds list` | Space-separated command names |

## Template Structure

Every cmds.rb follows this structure:

```ruby
module CMD
  def command_name(opts)
    opts.banner = "Usage: command_name [args]"
    opts.info = "One-line description of what this does"
    lambda { |*args|
      EXE.bash %{
        actual shell command here #{args.join " "}
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
```

The template file is at `~/dotfiles/cmds/template.rb`.

## Conventions

- Every function goes inside `module CMD` / `end`
- `opts.banner` = usage string, `opts.info` = one-line description — both required
- Body returns a `lambda` that receives `*args` (remaining CLI arguments)
- Use `EXE.bash %{ ... }` for bash commands, `EXE.fish %{ ... }` for fish commands
- `EXE.bash`/`EXE.fish` display the command with syntax highlighting before executing
- Pass `{silent: true}` to suppress the preview: `EXE.bash %{ ... }, {silent: true}`
- The `trap "SIGINT"` block at the end of the file handles Ctrl-C (required)
- Function names use snake_case — they become the subcommand names
- To forward CLI args through to the shell command: `#{args.join " "}`
- Name the primary entry point `main` or `start` (the `@@` shell shortcut runs whichever exists)

## Creating a New cmds.rb

Run `cmds init` from the project directory. This creates the file from template and prints the path:
```
$ cmds init
/Users/anthony/dotfiles/cmds/Users/anthony/projects/myapp/cmds.rb
```

Optionally scaffold a named function: `cmds init deploy`

Then use the Read tool to read the file and Edit tool to modify it.

Do NOT use `cmds edit` — it opens `$EDITOR` which is not useful in an AI context.

## Modifying Existing Commands

1. Run `cmds path` to get the file path
2. Use the Read tool to read the file
3. Use the Edit tool to modify functions

## Real Example

From lakshmi (a Flet mobile app):

```ruby
module CMD
  def start(opts)
    opts.banner = "Usage: start [args...]"
    opts.info = "Run Flet app on port 8555"
    lambda { |*args|
      EXE.bash %{
        uv run flet run --recursive --port 8555 #{args.join " "}
      }
    }
  end
  def build(opts)
    opts.banner = "Usage: build"
    opts.info = "Build Lakshmi APK with deep linking"
    lambda { |*args|
      EXE.bash %{
        uv run flet build apk --deep-linking-scheme=lakshmi --deep-linking-host=app --project "Lakshmi"
      }
    }
  end
  def deploy(opts)
    opts.banner = "Usage: deploy"
    opts.info = "Uninstall and reinstall APK on device"
    lambda { |*args|
      EXE.bash %{
        adb uninstall com.flet.lakshmi; adb install build/apk/app-release.apk
      }
    }
  end
end

trap "SIGINT" do
  exit 130
end
```
