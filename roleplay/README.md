# 🎭 Claude Code Character Roleplay

Every Claude Code response gets **bookended** with in-character flavour — an
opener at the top, a closer at the bottom — from a character rolled fresh on each
prompt. The technical content in between is written normally.

```
> 🎭 «Togusa» 🔍 GHOST IN THE SHELL — "Old-school approach. Let me read the file first."

...the actual answer...

> 🎭 «Togusa» 🔍 GHOST IN THE SHELL — Case closed. Filed the report.
```

57 characters across 6 universes. Costs one line of context per prompt, not 57.

This directory is **self-contained**: copy it anywhere and it works. Nothing in it
reads a path outside itself.

## Install

Two files to place, two config edits to make.

**1. Put the command on your PATH.** Symlink it — the script walks the link to
find its own roster, so it does not care where the link lives:

```bash
git clone <this-repo> ~/roleplay          # or copy the directory anywhere
ln -s ~/roleplay/bin/roleplay-roll ~/.local/bin/roleplay-roll
roleplay-roll --plain                     # should print a character
```

If that prints nothing, PATH or the roster is wrong — see *Troubleshooting*.

**2. Register the hook.** Merge `snippets/settings-hook.json` into
`~/.claude/settings.json`. If you already have a `UserPromptSubmit` array, append
to it rather than replacing — Claude Code runs every entry.

**3. Add the prompt section.** Append `snippets/CLAUDE.md.section` to
`~/.claude/CLAUDE.md`:

```bash
cat ~/roleplay/snippets/CLAUDE.md.section >> ~/.claude/CLAUDE.md
```

That is the whole install. Start a new Claude Code session and the bookends
appear.

## Layout

| Path | What |
|---|---|
| `bin/roleplay-roll` | the hook. bash + awk, no dependencies |
| `roster.tsv` | the cast. Add characters here |
| `examples.md` | 235 worked bookends, 4–5 per character. **Not read at runtime** — a style reference for you |
| `docs/claude-roleplay.md` | the design: why two-stage rolls, why the roster is external, the failure modes |
| `snippets/` | the two things you paste into your own Claude config |
| `tests/` | 43 pytest tests driving the script as a subprocess. `pytest tests/` |

## Usage

```bash
roleplay-roll             # hook JSON envelope (what Claude Code calls)
roleplay-roll --plain     # just the character line, for eyeballing
roleplay-roll --list      # the whole roster, grouped by universe
roleplay-roll --check     # validate: counts, per-character odds, duplicate names/emoji
```

## Adding a character

Add a line to `roster.tsv`:

```
UNIVERSE | Character Name | 🎯 | trait · trait · trait | optional signature line
```

Then run `roleplay-roll --check`. It recomputes the odds table and flags
duplicate names or emoji. Changes take effect on the **next prompt** — the hook is
a fresh subprocess each time and nothing caches.

The optional 5th field is the character's one overwhelmingly famous quote. Naming
it there does not ban it; it rations it to roughly one roll in three
(`ROLEPLAY_CATCHPHRASE`), and the injected tag tells Claude which roll it got. The
point is that the quote stops being the default without becoming forbidden.

## Environment

| Variable | Effect |
|---|---|
| `ROLEPLAY_ROSTER` | use a different roster file |
| `ROLEPLAY_SEED` | force the RNG seed, making a roll reproducible |
| `ROLEPLAY_CATCHPHRASE` | `N/M` odds a signature line is unlocked. Default `1/3`; `0/1` never, `1/1` always |

## Troubleshooting

**The script fails open, always.** Missing roster, unreadable file, broken awk,
empty result — every failure path prints nothing and exits 0. This is deliberate:
a `UserPromptSubmit` hook that errors or emits garbage degrades *every prompt you
ever send*, and stdout is parsed as JSON by Claude Code. The only acceptable
failure is a silently missing bookend.

The cost is that every problem looks identical — no bookends, no error. So debug
in this order:

1. `roleplay-roll --plain` — nothing? The command isn't found, or the roster isn't.
2. `command -v roleplay-roll` — not on PATH? Fix the symlink.
3. `ROLEPLAY_ROSTER=/path/to/roster.tsv roleplay-roll --plain` — works now? The
   script isn't finding its own roster; check the symlink actually points into
   this directory.
4. Command works but no bookends in Claude Code? The hook or the CLAUDE.md
   section didn't land. Check `~/.claude/settings.json` parses as valid JSON.

**Non-interactive sessions get no bookends on purpose.** Headless `claude -p`
runs with `--safe-mode`, which disables hooks — so no roll tag is injected, and
the CLAUDE.md section says that a missing tag means no bookends. Flavour in a
payload slot is just chatter.

## Requirements

bash and awk. Both BSD (macOS) and GNU awk work — the script avoids `\xNN`
escapes for exactly this reason. `pytest` only if you want to run the tests.
