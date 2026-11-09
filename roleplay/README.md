# 🎭 Claude Code Character Roleplay

Every Claude Code response gets **bookended** with in-character flavour — an
opener at the top, a closer at the bottom — from a character rolled fresh on each
prompt. The technical content in between is written normally.

```
> 🎭 «Togusa» 🔍 GHOST IN THE SHELL — "Old-school approach. Let me read the file first."

...the actual answer...

> 🎭 «Togusa» 🔍 GHOST IN THE SHELL — Case closed. Filed the report.
```

Dozens of characters across several universes, with adjustable odds. Costs one
line of context per prompt, not one per character.

This directory is **self-contained**: copy it anywhere and it works. Nothing in it
reads a path outside itself. The one outside program is `claude-p`, which only the
optional `roleplay-say` command needs (see *Install*).

---

## Porting this

If you are reading this to **reimplement** the idea rather than install it —
different shell, different agent harness, your own cast — start here. The whole
subsystem is ~3,300 lines, 1,400 of them examples, and fits in one context.

**Read in this order.** `docs/claude-roleplay.md` first: it is the *why*, and
almost every decision below has a paragraph there explaining what it cost to
learn. Then `bin/roleplay-roll` (bash + awk). Then skim `examples.md`
— it is the only artifact that conveys what "in character but *not* quoting the
famous line" actually reads like, which is the hard part of the design and the
part a reimplementation usually misses. `README.md` and `tests/` are the least
interesting here; they serve installers and regressions.

**Non-negotiables.** These look incidental and are not. Each was a bug first:

- **Fail open on every path.** Missing roster, unreadable file, broken awk, empty
  result — print nothing, exit 0. A prompt-submit hook that errors or emits
  garbage degrades *every prompt the user ever sends*. `set -uo pipefail`,
  deliberately never `set -e`. The cost is that all failures look identical, which
  the Troubleshooting section below exists to offset. Take the trade anyway.
- **Nothing but the payload on stdout.** Claude Code parses it as JSON. A stray
  diagnostic is not a warning, it is a broken prompt.
- **JSON-escape the roster text.** Characters legitimately carry quotes and
  backslashes in their traits and signature lines. Unescaped, they emit invalid
  JSON and the hook silently does nothing.
- **Keep the cast out of the system prompt.** This is the entire design, not a
  file-layout preference: the prompt section is constant-size and the injected tag
  is self-contained, so per-prompt cost is one line whether the roster holds 6
  characters or 600. An inline table pays for every unused character on every
  prompt forever. If your port inlines the cast, you have ported the flavour and
  thrown away the point.
- **Do not seed the RNG from time-of-day.** awk's `srand()` with no argument has
  one-second resolution, so two prompts sent in the same second get the same
  character. Seed from something per-process (`$RANDOM` here).
- **Two-stage selection is deliberate.** Universe first, *then* character within
  it. A flat roll across all entries lets one large group swallow the
  distribution — 63%, in the cast that prompted this. The tradeoff is that
  per-character odds are then unequal across groups; that is the accepted cost.
  `@universe` and `@character` weight lines in the roster tilt either stage, and
  everything weighs 1 by default.
- **Ration the famous quote, do not ban it.** An unconditional ban was the first
  design and it was too blunt — the problem was never the quote, only that it
  appeared *every single time*. Roll for it (1/3 default) and tell the model which
  way it landed, naming the line in **both** branches: when spent, it has to be
  identified in order to be avoided.
- **The signature roll must happen after the character picks.** It consumes from
  the same RNG stream; moving it earlier shifts every downstream selection.
- **No roll tag → no bookends.** That convention is what keeps flavour out of
  headless/non-interactive output, where it would land in a payload slot rather
  than a chat. Your port needs an equivalent, or it will corrupt scripted calls.

**Two things that are just bash trivia**, safe to drop if your target language
differs: the awk program is single-quoted, so no apostrophe may appear anywhere
inside it; and the guillemets and em-dash are literal UTF-8 rather than `\xNN`
escapes, because BSD awk on macOS does not read those the way gawk does.

**The harness-specific piece** is the output envelope. Here it is Claude Code's
`UserPromptSubmit` hook contract:

```json
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[🎭 Character Roll: «Name» 🔍 UNIVERSE — traits]"}}
```

Anything that can inject a line into the model's context per turn will do —
substitute your harness's mechanism and the rest of the design carries over
unchanged.

---

## Install

One symlink, two edits to your own Claude config. Nothing is copied into this
directory and nothing here is modified, so updating later is a `git pull`.

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

**Optional: `roleplay-say`.** The hook does not need this command. It writes a
character's line from a plain terminal, and it needs its own symlink:

```bash
ln -s ~/roleplay/bin/roleplay-say ~/.local/bin/roleplay-say
```

It also needs `jq` and `claude-p` on your PATH. `claude-p` is not in this
directory. It is a wrapper around `claude -p`, from the dotfiles this came from,
that adds a deadline, error checks and `--safe-mode`. Your own `claude-p` only has
to pass its arguments and stdin to `claude -p --safe-mode`.

## Layout

| Path | What |
|---|---|
| `bin/roleplay-roll` | the hook. bash + awk, no dependencies |
| `roster.tsv` | the cast. Add characters here |
| `bin/roleplay-say` | rolls a character and has a cheap model write its line, from a plain terminal |
| `examples.md` | 333 worked bookends, 4–5 per character. A style reference for you. The hook never reads it; `roleplay-say` reads one character's entries |
| `docs/claude-roleplay.md` | the design: why two-stage rolls, why the roster is external, the failure modes |
| `snippets/` | the two things you paste into your own Claude config |
| `tests/` | 81 pytest tests driving the scripts as subprocesses. `pytest tests/` |

## Usage

```bash
roleplay-roll             # hook JSON envelope (what Claude Code calls)
roleplay-roll --plain     # just the character line, for eyeballing
roleplay-roll --list      # the whole roster, grouped by universe
roleplay-roll --check     # validate: counts, per-character odds, duplicate names/emoji

roleplay-say                       # roll, and have a cheap model write the line
roleplay-say fixing the login bug  # ...about this. Words are optional context
roleplay-say --closer shipped it   # a closer instead of an opener
git diff | roleplay-say -          # context from stdin, only with an explicit -
roleplay-say -m sonnet tests pass  # another model. The default is haiku
```

`roleplay-say` is the one piece that needs more than bash and awk: `claude-p` and
`jq` on your PATH. Unlike the hook it fails loudly, with a message on stderr and
exit 1.

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
| `ROLEPLAY_SAY_MODEL` | `roleplay-say` only: the default model when `-m` is not given |
| `ROLEPLAY_EXAMPLES` | `roleplay-say` only: use a different examples file, or `/dev/null` for none |
| `CLAUDE_P_TIMEOUT` | `roleplay-say` only: deadline in seconds. Default `60` |

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
`jq` and `claude-p` only if you want `roleplay-say`.
