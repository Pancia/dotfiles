# 🎭 Claude Code Character Roleplay

A personality layer for Claude Code: every response is **bookended** with
in-character flavor — an **opener** at the top and a **closer** at the bottom —
drawn from a randomly-rolled character. The technical content in between is
written normally.

Three pieces:

| Piece | File | Role |
|---|---|---|
| Prompt section | `rcs/claude-user-claude.md` → `~/.claude/CLAUDE.md` | format rules only, ~34 lines, **constant size** |
| Roster | `roleplay/roster.tsv` | the cast — 57 characters across 6 universes |
| Hook | `roleplay/bin/roleplay-roll`, wired in `rcs/claude-settings.json` | rolls, and injects the chosen character |
| Examples | `roleplay/examples.md` | style reference — 235 worked bookends, 4–5 per character. **Not read at runtime** |

---

## Why it lives in `roleplay/`

The subsystem is self-contained in one directory so it can be **copied out and
given to someone else** — `roleplay/README.md` is the install guide for a
stranger, and nothing under `roleplay/` reads a path outside it.

Staying wired into dotfiles costs three symlinks, chosen over the alternatives:

| Link | Keeps working |
|---|---|
| `bin/roleplay-roll` → `../roleplay/bin/roleplay-roll` | PATH and the hook registration, both untouched |
| `tests/roleplay` → `../roleplay/tests` | `cmds test roleplay` — `run_component()` does `TESTS_DIR / component`, so an unlinked tree would never run |
| `docs/claude-roleplay.md` → `../roleplay/docs/claude-roleplay.md` | every existing link to this document |

The `bin/` symlink is why the script walks its own symlink chain before
resolving the roster (see the comment at that code). Adding
`roleplay/bin` to `fish/conf.d/path.fish` instead would have avoided the walk —
but it grows PATH once per subsystem, and it does nothing for the person who
copies this directory out and links the script into `~/.local/bin`, which is the
first thing they will do.

---

## Why the roster is not in CLAUDE.md

It used to be. The hook injected `[🎲 Character Roll: N]` and the prompt section
carried a numbered table that Claude indexed into.

That does not survive growth. `~/.claude/CLAUDE.md` loads into **every session in
every project**, so an inline table of 57 characters means paying for 56 unused
ones on every prompt, forever, to flavour two lines. It also duplicated the cast
size into the hook's modulus (`RANDOM % 13`) and into the prompt's "1-13" wording
— three places to keep in sync by hand.

Now the hook resolves the character itself and injects the whole thing:

```
[🎭 Character Roll: «Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest · old-school detective instincts]
```

The tag is self-contained, so per-prompt cost is one line no matter how large the
cast grows, and adding a character is one line in a data file with no modulus to
update anywhere.

---

## The roster format

```
UNIVERSE | Character Name | emoji | traits | signature line (optional)
```

Delimiter is `|`, surrounding whitespace is trimmed (so columns can be padded for
readability), lines starting with `#` are comments, and lines with fewer than 4
fields are skipped. The 5th field is the character's one famous quote — see
[Signature lines](#signature-lines) below. Most characters have no such line and
simply omit it.

**Careful with comments:** the leading-`#` rule is the *only* thing keeping a
comment out of the cast. A comment that documents the format —
`# Format: UNIVERSE | Character Name | emoji | traits` — has four pipe-separated
fields, so the field-count guard does not catch it. A test pins this specifically.

### Current cast

| Universe | Members |
|---|---|
| `WARHAMMER 40K` | 6 — Techpriest Logis, Commissar, Imperial Adjutant, Rogue Trader Navigator, Sister of Battle, Inquisitor |
| `GHOST IN THE SHELL` | 7 — Major Kusanagi, Batou, Togusa, Tachikoma, Puppet Master, Laughing Man, Kuze Hideo |
| `GURREN LAGANN` | 8 — Simon, Kamina, Lordgenome (Spiral King), Leeron, Rossiu, Viral, Yoko, Nia |
| `PANTHEON` | 14 — Ishtar, Ereshkigal, Shiva, Shakti, Prometheus, Hephaestus, Aphrodite, Mars, Odin, Freya, Loki, Lila, Maya, Lakshmi |
| `ZODIAC` | 12 — the signs |
| `TAROT` | 10 — 6 major arcana + 4 court cards |

`PANTHEON` spans five mythologies rather than one canon, which is why it is not
called `FATE`. Ishtar and Ereshkigal keep their Fate/Grand Order characterization;
the rest come from the source myths.

Two universes are harvested from prompts that already existed in `ai/prompts/`:

- **TAROT** traits come from the `STYLE AND TONE` block of the matching
  `ai/prompts/*.txt` coaching persona. **Only that block transfers.** Those files'
  `MISSION` and `BEHAVIOR` sections are built for introspective life-guidance and
  would be actively wrong in a debugging session — The Star's `No lists in
  responses` constraint in particular must never leak into technical answers.
- **Shiva and Shakti** come from `ai/prompts/shakti-and-shiva.txt`, whose whole
  structure is that polarity: Shakti leads with receptive, poetic, felt knowing;
  Shiva follows with grounded reasoning and structure.

---

## Two-stage selection

`roleplay-roll` picks a **universe at even odds**, then a character within it.

Under a flat roll across all 57 entries, the zodiac, tarot and pantheon groups
would be 63% of everything and any single 40K character would land under 2% of the
time. Two-stage holds every universe at 1/6 however lopsided the groups get, so
you can add 40 more tarot cards without burying the Techpriest.

The cost: **per-character odds are not equal across universes.** A small universe
over-represents each of its members.

| Universe | Members | Each |
|---|---|---|
| `WARHAMMER 40K` | 6 | 2.78% ← most likely |
| `GHOST IN THE SHELL` | 7 | 2.38% |
| `GURREN LAGANN` | 8 | 2.08% |
| `TAROT` | 10 | 1.67% |
| `ZODIAC` | 12 | 1.39% |
| `PANTHEON` | 14 | 1.19% ← least likely |

The Techpriest is ~2.3x likelier to appear than Lakshmi. Universe variety was judged
the thing worth protecting; to flatten the spread, **grow the small universes**
rather than switching to a flat roll — that spread was 4.7x when `GURREN LAGANN`
had only 3 members, and adding five closed it to 2.3x. `roleplay-roll --check`
recomputes this table from the file, so verify against that rather than trusting
the numbers here.

---

## Signature lines

An archetype's most-quoted line is also the first one that comes to mind — which is
exactly why it has already been used, every previous time the die landed there. The
Laughing Man reached for the Salinger quote essentially every appearance, which is
what prompted this whole rework.

**The first design banned them outright, and that was too blunt.** The quote was
never the problem; its appearing *every single time* was. So the ban became a roll.

A character names its famous line in the 5th roster field. Each roll then decides
whether that line is unlocked, at `ROLEPLAY_CATCHPHRASE` odds (**default 1/3**), and
the injected tag says which:

```
… || SIGNATURE LINE UNLOCKED (1/3 roll) — you may use: 'the net is vast and infinite'
… || signature line spent this roll — do not use 'the net is vast and infinite'; reach for a less-worn part of the character instead
```

The line is named in **both** branches — when spent it has to be identified in order
to be avoided. `0/1` disables signature lines entirely, `1/1` always unlocks them.

Seven characters currently declare one: Techpriest Logis, Commissar, Major Kusanagi,
Tachikoma, Laughing Man, Simon, Kamina. `roleplay-roll --check` reports the count and
the configured odds; `--list` shows each as `[sig: …]`.

This also simplified the roster: those characters' traits went back to plain
description, since the prohibition prose they used to carry now lives in a field the
hook understands.

---

## The hook fails open, deliberately

`roleplay-roll` runs on every prompt in every project, and its stdout is parsed as
JSON by Claude Code. Every failure path — missing roster, unreadable file, broken
awk, empty result — prints nothing and exits 0.

**Never add `set -e`, and never let a diagnostic reach stdout.** A hook that errors
or emits garbage degrades every prompt the user ever sends; the only acceptable
failure is a silently missing bookend.

Seeding is from bash's `$RANDOM`, not awk's bare `srand()`. `srand()` with no
argument seeds from time-of-day at one-second resolution, so two prompts sent in the
same second would get the same character.

---

## Usage

```bash
roleplay-roll             # hook JSON envelope (what the hook calls)
roleplay-roll --plain     # just the character line
roleplay-roll --list      # the whole roster, grouped
roleplay-roll --check     # validate: counts, odds, duplicate emoji/names
```

| Env var | Effect |
|---|---|
| `ROLEPLAY_CATCHPHRASE` | signature-line odds as `N/M`, default `1/3`. `0/1` never, `1/1` always. Unparseable values fall back to the default rather than erroring |
| `ROLEPLAY_ROSTER` | override the roster path (for the tests) |
| `ROLEPLAY_SEED` | force the RNG seed, making a roll reproducible (for the tests) |

### When changes take effect

The three pieces reload differently, which matters when you are editing them.

| Change | Takes effect | Why |
|---|---|---|
| `roleplay/roster.tsv` | **next prompt** | the hook is a fresh subprocess per prompt that re-reads the file; nothing caches it |
| `rcs/claude-settings.json` (hook wiring) | **next prompt** | hooks are resolved per invocation |
| `rcs/claude-user-claude.md` (prompt section) | **next session** | `~/.claude/CLAUDE.md` is supplied as context at session start, so a running session keeps the copy it began with |

The first two were confirmed live rather than assumed: adding five Gurren Lagann
characters put Yoko in a roll 26 calls later with nothing restarted, and the
session that rewired this hook saw its own injected tag change from the old
`[🎲 Character Roll: 7]` to the new self-contained form mid-conversation.

The third is the one to watch. If you edit the format rules and the bookends do
not change, that is expected — start a new session rather than debugging it.

### Adding a character

1. Add a line to `roleplay/roster.tsv`.
2. Run `roleplay-roll --check` — it recomputes the odds table and flags duplicate
   names or emoji. (It caught 👁️ being on both the Inquisitor and the Puppet Master,
   a collision inherited from the original inline table.)
3. If the character has one overwhelmingly famous quote, put it in the 5th field.
4. Optionally add a block to `examples.md` in the same shape as the others.

Nothing else needs updating — no modulus, no prompt-section edit.

### The examples file

`roleplay/examples.md` holds 235 worked bookends — four per character (two
openers, two closers) plus a fifth for each of the seven signature characters
showing the famous line used well on the roll where it is unlocked.

**Nothing reads it at runtime.** Loading it would undo the entire external-roster
design, which exists so a prompt carries one line rather than the cast. It is a
style reference: read it when adding a character, or when a universe starts
sounding samey.

It was generated by six subagents, one per universe, each reading the roster
itself so no name or emoji was retyped. Assembly verified all 57 characters
present exactly once, emoji matching the roster, signature blocks appearing for
exactly the seven characters that declare one, and — the check that mattered —
that no signature quote appears in any of the four *ordinary* examples.

---

## Tests

`cmds test roleplay` — 43 tests under the `roleplay` component, registered in
`COMPONENTS` (`lib/python/run_tests.py`). They drive the script as a subprocess.
The tests themselves live in `roleplay/tests/`, reached through the
`tests/roleplay` symlink; they derive their root from `__file__` with `.resolve()`
so a standalone copy tests itself, and `pytest roleplay/tests/` works with no
dotfiles around it at all.

Mutation-checked. 9 of 10 mutations are killed; the survivor is `[ -r "$roster" ]`,
which is genuinely redundant with the `|| exit 0` on the awk capture and is kept
only as an explicit statement of intent.

**Six of the 43 cover symlink resolution**, which is load-bearing now that the
copy which actually runs is reached through `bin/roleplay-roll`. They are worth
more than their line count suggests: neutering the walk to `while false; do` —
a one-line mutation — makes the script read whatever `roster.tsv` happens to sit
beside the *link*, at exit 0 with plausible output. Verified against a decoy
roster, which is what `test_symlink_next_to_a_decoy_roster_ignores_the_decoy`
pins. Every one of those tests omits `ROLEPLAY_ROSTER` deliberately; the override
would mask the resolution being tested.

Lessons from those runs, each of which had left a real gap:

- **An always/never claim needs many runs, not one.** `ROLEPLAY_CATCHPHRASE=0/1`
  asserted over a single roll passes by luck 2 times in 3 at the 1/3 default — which
  is exactly how a "the env var is ignored" mutation survived. Both extreme-odds
  tests now assert over 30 runs.
- **Same-seed comparisons cannot detect a reordered RNG stream.** Three runs at
  different odds all shift together, so the test that was meant to pin "the signature
  roll happens last" proved nothing. It now compares a roster *with* signatures
  against one *without*, where a reorder genuinely changes the character picked.

- **A multi-word `-k` selector silently collects zero tests.** The first mutation
  harness scored those runs as KILLED because the word "error" appeared in
  the output. Verdicts must require a real `N failed` tally *and* that tests ran.
- **Same-seed-same-output does not prove the seed is used.** A hardcoded `srand(1)`
  satisfies it equally well, and did. The test now also asserts that *different*
  seeds produce different rolls.
- **Comment-skipping looked tested but wasn't.** The comment lines in the fixture
  had no `|`, so `NF < 4` skipped them regardless and the leading-`#` rule was never
  exercised. The fixture now uses a comment with four pipe-separated fields, which
  is the shape the real roster actually contains.
