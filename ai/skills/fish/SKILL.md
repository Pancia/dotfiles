---
name: fish
description: Fish shell syntax and idioms. Load this skill when writing or modifying Fish shell code to avoid common gotchas.
user-invocable: true
disable-model-invocation: false
---

# Fish Shell Gotchas

Reference for writing correct Fish shell code. Fish is NOT bash — many familiar
patterns are wrong or subtly broken in Fish.

## Variables & `set`

- **No `=` in set**: `set x 5` not `set x=5`
- **`status` is reserved** — it holds the last command's exit code. Never `set -l status`. Capture it immediately: `set -l exit_code $status` — any intervening command overwrites it.
- **`argv` is special** — function arguments live here. Be careful with scoping.
- **Scope matters**: `set -l` (local to function), `set -g` (global), `set -U` (universal persistent). Wrong scope causes silent bugs.
- **`set -l` is function-scoped, NOT block-scoped.** A `set -l` inside `if`/`for`/`while` is visible for the rest of the function. But if the branch isn't taken, the variable is never set. Declare at function level to ensure it exists:
- **Erase with `set -e`**, not `unset`.
- **No `export`** — use `set -gx VAR value`.
- **`set -a` / `set --append`** to build lists: `set -a mylist item`. Not `mylist+=item`.
- **Arrays are 1-indexed**: `$argv[1]` is the first element, not `$argv[0]`.

```fish
# WRONG - if branch not taken, $msg was never set
if test $big
    set -l msg (generate_message)
end
echo $msg  # empty if branch wasn't taken!

# RIGHT - declare first, assign inside
set -l msg
if test $big
    set msg (generate_message)
end
echo $msg  # works — empty string if branch wasn't taken
```

## Control Flow

- **`&&` / `||` work** (Fish 3.0+) and are fine to use. `; and` / `; or` is the older idiom.
- **`if test ...`** not `if [ ... ]` — brackets work but `test` is idiomatic.
- **`if not command`** — not `if ! command` (though `!` works in modern Fish).
- **`for x in (command)`** not `for x in $(command)` — parens, not dollar-parens. `$(...)` works in Fish 3.4+ but `(...)` is idiomatic.
- **`switch`/`case`/`end`** — not bash's `case`/`esac`:
- **Early exit**: use `or return` / `or begin ... end` patterns.

```fish
switch $action
    case start stop
        do_something
    case '*'
        echo "unknown action"
end

set -l result (some_command)
or return 1

read -l -P "Continue? " confirm
or return  # handles Ctrl-C during read
```

## Strings & Quoting

- **Command substitution**: `(command)` not `` `command` ``. `$(command)` works in Fish 3.4+ but bare parens are idiomatic.
- **`string` builtin** for all manipulation: `string split`, `string match`, `string replace`, `string trim`, `string collect`, etc.
- **`string match` uses globs by default** — use `string match -r` for regex. Forgetting `-r` is a common bug.
- **Double quotes**: `"$var"` works but arrays expand differently than bash — `"$list"` joins with spaces, `$list` keeps elements separate.
- **Multi-line capture loses newlines**: `set -l output (command)` splits output into a list by newlines. `"$output"` then joins with spaces, collapsing all lines into one. For multi-line output, write to a temp file instead: `command > $tmpfile`.
- **Escape sequences work in quotes**: `\t`, `\n`, `\r` are interpreted in both single and double quotes (unlike bash). Use `printf` when you need precise control.
- **No heredocs** (`<<EOF`). Use `printf`, multi-line quoted strings, or `echo` piped:

```fish
# Instead of heredoc, pipe echo or printf
printf '%s\n' "line 1" "line 2" "line 3" | command

# Or multi-line quoted string
echo "line 1
line 2
line 3" | command

# List expansion — one element per line
printf '%s\n' $list    # RIGHT: one element per line
printf '%s\n' "$list"  # WRONG: one line with spaces
```

## Math

- **`math` builtin** — not `$(( ))`:

```fish
set -l result (math "1 + 2")     # RIGHT
set -l result (math $x / $y)     # variables work directly
# NOT: set -l result $(( 1 + 2 ))
```

## Functions

- **Syntax**: `function name; ...; end` — no braces.
- **Arguments**: `$argv[1]`, `$argv[2]`, etc. — not `$1`, `$2`. Arrays are 1-indexed.
- **`--description` flag**: `function name --description "what it does"` for self-documenting functions.
- **Return values**: `return 0` for success, `return 1` for failure. Use `or return` after commands that might fail.
- **`command` prefix** bypasses function wrappers: `command ls` runs the real `ls`, not a user-defined `ls` function.

## Input & Testing

- **`read`**: `read -l -P "prompt: " var` — `-P` for prompt, `-l` for local scope.
- **Ctrl-C and `read`**: SIGINT kills `read` but may not stop the function. Use `or return` after `read`.
- **Quote variables in `test`**: `test -n "$var"` — unquoted empty `$var` expands to nothing, making `test -n` return true (wrong!). Always quote.
- **Array length**: `count $list` — not `${#list[@]}`.
- **List membership**: `contains $item $list` — don't grep an array.

## Redirection

- **Stderr to file**: `command 2>file`
- **Both stdout+stderr to file**: `command &>file`
- **Pipe both stdout+stderr**: `command &| other_command` — not `|&` (bash).
- **No process substitution** (`<(command)`). Use the `psub` builtin: `command (other_command | psub)`.
