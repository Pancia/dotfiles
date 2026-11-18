# 🎭 Claude Code Character Roleplay

A personality layer for Claude Code: the final message of every turn is
**bookended** with in-character flavor — an **opener** at the top and a
**closer** at the bottom —
drawn from a randomly-rolled character. The technical content in between is
written normally.

> **In these dotfiles, since 2026-11-15, the main model no longer writes the
> bookends.** The `roleplay-bookends` mod (`ai/mods/roleplay-bookends`, loaded
> through `CLAUDE_CODE_PLUGIN_DIRS` in `rcs/claude-settings.json`) calls
> `roleplay-roll --votes` itself and has Sonnet write the opener when a typed
> prompt's turn starts and the closer when it ends. It draws them around the
> turn on screen only, so they never enter the transcript. The hook below is
> no longer registered, and the CLAUDE.md section only says not to write
> bookends. Why: a blind test showed lines going flat in long sessions, and a
> second one rated Sonnet's lines level with the main model's. Data and
> scripts: `.cc/private/roleplay-blind-test/`, `.cc/scripts/roleplay-*`.
> The mod also shows a reminder row when votes pile up, with a Review button
> that opens a review session (`bin/rolevotes-review`, prompt
> `ai/prompts/rolevotes-review.md`).
> The hook design below still works for anyone using `roleplay/` on its own.
>
> **Two modes (2026-11-16).** `/roleplay random` is the mode above: a new
> character on each typed prompt, with the vote links, and each bookend shows
> dim odds after the name (the character's overall chance) and after the
> universe (its share of rolls). `/roleplay session` keeps one character for
> the whole session, with no vote links and no odds. A dim row above the
> prompt is always there: a mode button that shows the mode (a press switches
> it), then in session mode **Reroll** (a new random character, never the
> same) and **Pick** (a pane with a search field and one row per character,
> each with both odds), then the character, or "a new character each
> prompt". Pick is hidden in random mode, where it would switch modes
> unasked. `/roleplay reroll` and
> `/roleplay pick` do the same from the prompt and, from random mode, put the
> session in session mode without changing the default (in universe mode they
> change the universe; see below). The mode button and `/roleplay
> session|random` also set the default for new sessions (the mod's
> `$.store`). Each session's mode and character are also kept in `$.store`
> by session id (the newest 50), so `--resume` gets them back; `/clear` rolls
> a new character. The odds and the pick list come from `roleplay-roll
> --roster`, read once per mod load and read again after a failure. A session
> roll is a weighted pick by overall share in the mod, which is the script's
> two-stage roll, and is not logged. The signature line is drawn again on
> each turn, at a fixed 1/3 (`ROLEPLAY_CATCHPHRASE` does not reach the mod).
> Tests: `ai/mods/roleplay-bookends/tests/modes.test.tsx`. Review:
> `.cc/reports/REVIEW-roleplay-modes.md`.
>
> **Universe mode (2026-11-17).** `/roleplay universe` keeps one universe for
> the whole session and rolls a new character from it on each typed prompt,
> never the same one twice in a row (a mod reload forgets the last one, so
> the first roll after it may repeat). The vote links show, as in random mode.
> The character's odds are its share within the universe (they ignore the
> skipped character); the universe's odds are its usual share of rolls. The
> mode button cycles random → session → universe. In universe mode,
> **Reroll** rolls a new universe (weighted, never the same) and **Pick**
> lists universes, not characters. A universe at 0% (benched, or all its
> characters off) never rolls and is not in Pick: `--roster` cannot tell the
> two apart, and a pinned universe nobody can roll gives no bookend. Each roll
> is `roleplay-roll --votes --universe=NAME --not=LAST`, so it is logged and
> votable. If a roll prints nothing (the universe was renamed or switched off
> after the roster loaded), that turn gets a random roll, the roster is read
> again, and the session gets another universe, with a toast. `/clear` rolls
> a new universe; `--resume` gets it back. Entering universe mode from
> session mode keeps the session character's universe, and the first roll
> skips that character; from random mode it returns to the universe the
> session last had, or rolls one. Review:
> `.cc/reports/REVIEW-roleplay-universe-mode.md`.
>
> **Who did what (2026-11-17).** The writer's system prompt names three
> parties: the user wrote the request, the assistant did the work and wrote
> the reply, and the character only comments. Before it, a reply where the
> assistant said "I was wrong" got lines blaming the user, 6 times in 8.
> `.cc/reports/REPORT-roleplay-who-did-what.md`.

The pieces:

| Piece | File | Role |
|---|---|---|
| Prompt section | `rcs/claude-user-claude.md` → `~/.claude/CLAUDE.md` | here: a short note that the mod draws the bookends and the main model must not. Stand-alone: the format rules, ~22 lines, **constant size** |
| Mod (these dotfiles) | `ai/mods/roleplay-bookends`, loaded by `CLAUDE_CODE_PLUGIN_DIRS` in `rcs/claude-settings.json` | rolls through `roleplay-roll --votes`, has Sonnet write both lines, draws them, logs them, and shows the vote reminder. `/roleplay` switches between a new character per prompt, a new character per prompt from one universe, and one character per session |
| Roster | `roleplay/roster.tsv` | the cast — 81 characters across 9 universes — and the odds weights |
| Roller | `roleplay/bin/roleplay-roll` | rolls a character. Stand-alone it runs as a `UserPromptSubmit` hook and injects the character; here the mod calls it, and no hook is registered |
| Terminal command | `roleplay/bin/roleplay-say` | rolls, then has Sonnet write the line, for use outside a session |
| Examples | `roleplay/examples.md` | style reference — 338 worked bookends, 4–5 per character. **The hook never reads it**; `roleplay-say` and the `roleplay-bookends` mod (`ai/mods/roleplay-bookends`) read the rolled character's entries |

---

## Why it lives in `roleplay/`

The subsystem is self-contained in one directory so it can be **copied out and
given to someone else** — `roleplay/README.md` is the install guide for a
stranger, and nothing under `roleplay/` reads a path outside it. The only outside
program is `claude-p`, called through PATH by the optional `roleplay-say`.

Staying wired into dotfiles costs four symlinks, chosen over the alternatives:

| Link | Keeps working |
|---|---|
| `bin/roleplay-roll` → `../roleplay/bin/roleplay-roll` | PATH and the hook registration, both untouched |
| `bin/roleplay-say` → `../roleplay/bin/roleplay-say` | PATH for the terminal command |
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
every project**, so an inline table of 80 characters means paying for 79 unused
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
simply omit it. Lines starting with `@` set odds — see
[Weights](#weights) below.

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
| `TAROT` | 10 — 6 major arcana + 4 court cards |
| `FAVORITES` | 12 rows, 10 characters — Holo (Spice & Wolf), Malfoid (a female Draco Malfoy, two rows: as herself and grown up as your wife), Ahri (League of Legends), Tenka Izumo (Chained Soldier), Asuna Ichinose (Blue Archive), Houshou Marine (two rows, one clean and one raunchy, weighted separately), Charlie Morningstar (Hazbin Hotel), Artoria Pendragon as Saber and as Lancer (Fate), Sayuri Ninomiya (Silver Plan to Redo From JK) |
| `THE LEGEND OF ZELDA` | 5 — Breath of the Wild, Twilight Princess, Tetra, Sheik, Skyward Sword |
| `STEEL MAGNOLIAS` | 7 — Maggie Greene, Bonnie MacFarlane, Charlotte La Bouff, Blanche Devereaux, Julia Sugarbaker, Sadie Adler, Cass |
| `ZODIAC` | 12 — the signs |

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

`roleplay-roll` picks a **universe**, then a character within it.

Under a flat roll across every row, the biggest groups would take most of the
rolls: with 57 characters, the zodiac, tarot and pantheon groups were 63% of
everything. Two-stage holds each universe at its own share however lopsided the
groups get, so you can add 40 more tarot cards without burying the Techpriest.

The cost: **per-character odds are not equal across universes.** A small universe
over-represents each of its members.

| Universe | Members | Weight | Each |
|---|---|---|---|
| `THE LEGEND OF ZELDA` | 5 | 2 | 3.40% |
| `FAVORITES` | 12 rows | 3 | 1.65% (Marine Uncut and Malfoid Wife 4.94% each ← most likely, Marine 0.82%) |
| `STEEL MAGNOLIAS` | 7 | 2 | 2.43% |
| `WARHAMMER 40K` | 6 | 1 | 1.42% |
| `GHOST IN THE SHELL` | 7 | 1 | 1.22% |
| `GURREN LAGANN` | 8 | 1 | 1.06% |
| `PANTHEON` | 14 | 1 | 0.61% |
| `TAROT` | 10 | 0.5 | 0.43% |
| `ZODIAC` | 12 | 0.25 | 0.18% ← least likely |

`roleplay-roll --check` recomputes this table from the file, so verify against
that rather than trusting the numbers here.

### Weights

Both stages are weighted. A weight is a share relative to its peers, and anything
not named weighs 1:

```
@universe  | ZODIAC | 0        # never rolls
@universe  | TAROT  | 2        # twice the share of a universe at 1
@character | Holo   | 0.5      # half the share of her universe's members at 1
```

(The trailing comments above are for this page. A real weight line has exactly
three fields.)

- **A `@character` weight divides its universe's share.** It cannot grow it. To see
  a lone character more often, raise the `@universe` weight instead.
- **A one-member universe needs a weight.** At 1 it receives a whole universe's
  share, so that one character would appear as often as all 40K characters combined.
- **Weight 0 keeps the row.** It takes a character or universe out of rotation and
  is reversed by editing one number.
- **A universe whose members are all at 0 is skipped at stage 1.** Otherwise a roll
  could land on it and find nobody.
- **A weight of 1 is the old even roll, exactly.** The weighted pick takes one
  `rand()` and lands where the even pick did, so existing seeds are unaffected. A
  test pins this.
- **Bad weight lines fail open.** A malformed value leaves the weight at 1. `--check`
  reports malformed lines and names that match nothing, because a misspelled name
  would otherwise have no effect and give no sign of it.

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

Thirteen roster rows currently declare one: Techpriest Logis, Commissar, Major Kusanagi,
Tachikoma, Laughing Man, Simon, Kamina, Holo, Malfoid, Malfoid (Wife), Houshou Marine,
Houshou Marine (Uncut), Artoria Pendragon (Saber). `roleplay-roll --check` reports the count and the
configured odds; `--list` shows each as `[sig: …]`.

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
roleplay-roll             # hook JSON envelope
roleplay-roll --votes     # the same, plus a vote id and a roll log (what the mod calls here)
roleplay-roll --plain     # just the character line
roleplay-roll --list      # the whole roster, grouped
roleplay-roll --check     # validate: counts, odds, duplicate emoji/names
roleplay-roll --roster    # one tab-separated row per character with its odds, for programs

roleplay-say                       # roll, and have Sonnet write the line
roleplay-say fixing the login bug  # ...about this
roleplay-say --closer shipped it   # a closer instead of an opener
git diff | roleplay-say -          # context from stdin, only with an explicit -
roleplay-say -m haiku tests pass   # another model. The default is sonnet
```

| Env var | Effect |
|---|---|
| `ROLEPLAY_CATCHPHRASE` | signature-line odds as `N/M`, default `1/3`. `0/1` never, `1/1` always. Unparseable values fall back to the default rather than erroring |
| `ROLEPLAY_ROSTER` | override the roster path (for the tests) |
| `ROLEPLAY_SEED` | force the RNG seed, making a roll reproducible (for the tests) |
| `ROLEPLAY_ROLL_LOG` | `--votes` only: the roll log path. Default `$XDG_STATE_HOME/roleplay/rolls.tsv`; empty logs nothing and drops the id. Set it empty for a test run with `--votes` |
| `ROLEPLAY_SAY_MODEL` | `roleplay-say` default model when `-m` is not given |
| `ROLEPLAY_EXAMPLES` | `roleplay-say` examples file, `/dev/null` for none |
| `CLAUDE_P_TIMEOUT` | `roleplay-say` deadline in seconds, default `60` |

`roleplay-say` **fails loudly**, unlike the hook: a message on stderr and exit 1,
with stdout carrying only the finished line. A person or a script calls it, so
nothing parses its failure as a prompt. It needs `claude-p` and `jq` on PATH.

### Vote ids (`--votes`)

With `--votes`, each roll gets a random 4-character id, added to the tag as
`|| vote id: k3f2` and logged with the character and universe to `rolls.tsv`. Here the
mod draws `[ − ] [ + ]` buttons next to the name and the universe. A press writes
`votes.tsv` itself (`castVote`); no Hammerspoon is involved. Each part (the character or the
universe of one opener or closer) holds at most one vote: the first press casts it, the
same button again clears it, and the other button changes it. The script writes the whole
new file (that part's old line dropped, matched on id, roll time, place and kind; the new
line added) to a temp file and renames it in one step, under `lockf` on `votes.lock`, so
parallel writers lose nothing. Presses run one at a time in the mod, so two quick presses
cast and then clear. A cast vote draws bold, + green and − red. `roleplay-roll --votes`
draws a new id when the one it drew is already in `rolls.tsv`. Stand-alone, the bookend format in the prompt section draws
`hammerspoon://r?v=<id><slot>` links instead, and the Hammerspoon seed
`lib/lua/seeds/rolevote.lua` records each click in the same line format. The vote does not
store the line; the mod's `~/.local/state/roleplay/mod-lines.jsonl` holds it under the same
vote id.

**The receiver lives outside `roleplay/`,** so the flag is off by default and this directory
stays usable on its own. Here the mod passes it (`ownRoll` in its `register.tsx`), not the
settings `env` block: that block also reaches every Bash call Claude makes, so a run by hand
would write the real log. A run without the flag logs nothing. Seed tests: `cmds test lua`.

### When changes take effect

The three pieces reload differently, which matters when you are editing them.

| Change | Takes effect | Why |
|---|---|---|
| `roleplay/roster.tsv` | **next prompt** | the roller is a fresh subprocess per roll that re-reads the file; nothing caches it |
| `roleplay/examples.md` | **next session or mod reload** | the mod reads it once, at `session.start` (not on `/clear`) |
| `ai/mods/roleplay-bookends/` | **in the session that saved it: end of that turn (seen 2026-11-15); in every other open session: about ¼ s after the last save, even mid-turn (from the plugin guide, not observed)** | the reload drops the module's memory: a Sonnet call in flight is cut off, and a turn already running gets no closer. How to edit, test and type-check a mod: [ai/mods/README.md](../../ai/mods/README.md) |
| `CLAUDE_CODE_PLUGIN_DIRS` in `rcs/claude-settings.json` | **next session** | the plugin folders are read at start |
| `rcs/claude-user-claude.md` (prompt section) | **next session** | `~/.claude/CLAUDE.md` is supplied as context at session start, so a running session keeps the copy it began with |

The roster row was confirmed live when the hook still rolled: adding five Gurren
Lagann characters put Yoko in a roll 26 calls later with nothing restarted. The
mod row was seen live on 2026-11-15: each save reloaded the mod at the end of
the turn. Stand-alone, hook wiring in the settings also takes effect on the next
prompt, and a format-rule edit only in a new session.

After a change to how the mod handles prompts or turns, run `claude plugin test
ai/mods/roleplay-bookends`. Then send one typed prompt and check the screen: an
opener under the prompt and a closer under the answer. Only then call it working.
While `DEBUG` is true, `~/.local/state/roleplay/mod-debug.log` also shows
`opener <turnId> who=…` and `write opener <turnId> … ok` for that turn.

### Adding a character

1. Add a line to `roleplay/roster.tsv`.
2. Run `roleplay-roll --check` — it recomputes the odds table and flags duplicate
   names or emoji. (It caught 👁️ being on both the Inquisitor and the Puppet Master,
   a collision inherited from the original inline table.)
3. If the character has one overwhelmingly famous quote, put it in the 5th field.
4. Optionally add a block to `examples.md` in the same shape as the others.

Nothing else needs updating — no modulus, no prompt-section edit.

### The examples file

`roleplay/examples.md` holds 338 worked bookends — four per character (two
openers, two closers) plus a fifth for the signature characters, showing the
famous line used well on the roll where it is unlocked.

**The hook never reads it.** Loading it would undo the entire external-roster
design, which exists so a prompt carries one line rather than the cast. It is a
style reference: read it when adding a character, or when a universe starts
sounding samey. `roleplay-say` is the one reader. It takes the rolled character's
first four entries and skips the fifth, because showing the signature line would
defeat a roll that came up spent.

The first 57 characters were generated by six subagents, one per universe, each
reading the roster itself so no name or emoji was retyped. Assembly verified all
57 present exactly once, emoji matching the roster, signature blocks appearing for
exactly the seven characters that then declared one, and — the check that mattered
— that no signature quote appears in any of the four *ordinary* examples.

---

## Tests

`cmds test roleplay` — 81 tests under the `roleplay` component, registered in
`COMPONENTS` (`lib/python/run_tests.py`). They drive the scripts as subprocesses.
The tests themselves live in `roleplay/tests/`, reached through the
`tests/roleplay` symlink; they derive their root from `__file__` with `.resolve()`
so a standalone copy tests itself, and `pytest roleplay/tests/` works with no
dotfiles around it at all.

Mutation-checked. 9 of 10 mutations are killed; the survivor is `[ -r "$roster" ]`,
which is genuinely redundant with the `|| exit 0` on the awk capture and is kept
only as an explicit statement of intent.

**Six of them cover symlink resolution**, which is load-bearing now that the
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
