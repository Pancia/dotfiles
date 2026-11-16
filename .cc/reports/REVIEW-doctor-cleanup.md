# Review: doctor cleanup proposal (2026-11-15)

Adversarial review of `.cc/reports/REPORT-doctor-2026-11-15.md`, checks 1, 3, 4, 8
and 10. Read-only; nothing else was changed. Line numbers refer to `CLAUDE.md` and
`rcs/claude-user-claude.md` as they are on disk now (including the other session's
uncommitted hunks).

## Verdicts

| Group | Verdict |
|---|---|
| Check 3 — cut "derivable" text from `CLAUDE.md` | **Change.** Pure-derivable cuts are fine. The "global file says the same" cuts are only valid if check 10 is *not* applied to the same global text; as proposed, both copies leave the always-loaded files. Keep the lines listed under P1. |
| Check 4 — move sections to skills / `docs/` | **Change.** Direction is right, but the "stays in root" lists miss several rules whose absence causes damage (P2, P4), and the ccs section gets the weakest delivery (a bare pointer) despite being the densest in invariants (P5). |
| Check 10 — trim global `CLAUDE.md` | **Change.** Keep lists drop four always-relevant rules, and one global line points at a heading check 4 moves away (P1, P6). Pointers must be absolute paths. |
| Check 1 — kagi | **Keep**, plus remove the stale allow rule. No token saving. |
| Check 1 — Calendar / Drive connectors | **Change**: disable in Claude Code only, if at all. Do not turn them off on claude.ai. |
| Check 1 — Claude Docs connector | **Keep** (disable in Claude Code). The only connector change that saves tokens. |
| Check 1 — `/prompt:build` | **Change**: remove it through cc-config, not `skillOverrides`. Trivial either way. |
| Check 8 — pin `defaultMode: "auto"` | **Change / decide explicitly.** Measured: it switches every headless `claude -p` run from `default` to `auto` (P3). |
| Mechanics / sequencing | **Blocker until the other session commits** (P4). Any edit to `ai/cc-config.json` must first register `ui-style`, or the next sync deletes it (P7). |

Side effects of this review: three short headless `claude-p` probe runs (haiku/sonnet,
`--tools=''`) to read the permission mode. Nothing else was run or changed.

## Problems, by severity

### P1 (high) — check 3 and check 10 cancel each other's justification

Check 3 cuts project text because "the global file says the same". Check 10 then moves
that same global text to `docs/claude-global/`. Applied together, the rule is in neither
always-loaded file:

- **Work-config vault.** Project 336–347 is cut (check 3); global 297–308 becomes a
  pointer (check 10). Lost from both: global 305 "`...because dotfiles is public.`" and
  306 "**Edits there are only backed up when committed in the vault**". The global copy
  is the one that matters: it loads in `~/projects/work/*`, where this repo's file does
  not. Project 341 "`cmds init` puts anything under `~/projects/work/` there" exists only
  in the project file (global 301 just says `cmds init` creates a file).
- **This repo is public.** Project 338 ("This repo is public, so private per-project
  config...") and 466 ("...and this repo is public, so everything there gets published on
  the next push") are both in cut sections. The global file (216) only says "some repos
  are public". After the cut, nothing always-loaded says *this* repo is one of them —
  and every `.cc/reports/` file here, including this one, is published on push. Keep one
  line in the root.
- **`service` usage.** Project 53–70 command list is cut as duplicating "`service --help`
  and the global file", and global 367–390 is trimmed to the two-row table. `service
  --help` does carry the subcommands, but project line 55 "Use the `service` CLI (not
  `launchctl` directly)" exists nowhere else (`launchctl` appears 0 times in the global
  file). Keep line 55.
- **`claude-p`.** Project 618–676 rationale is cut as duplicated; global 310–349 is
  trimmed to three rules. Dropped from both: global 319–321 "`.is_error` is the only
  trustworthy signal" (check 4 keeps it in the root, so this one survives *here* but not
  in other projects), 327 exit codes, and 346–348 "a caller whose output must be exactly
  one thing still needs `--json-schema` (for data) or the `<output>` envelope" — the one
  rule that applies to any script in any project. Keep 346–348 in the global file.
- **Dangling reference.** Global 348–349 says "see `~/dotfiles/CLAUDE.md`, 'Constraining
  headless output'". Check 4 moves that heading into skill `headless-claude`. Repoint it
  (to the skill name or a docs file), or the pointer leads nowhere.

Fix: treat each "duplicate" pair as one fact with one surviving home, and pick the home
first. For anything that applies outside this repo, the home is the global file.

### P2 (high) — a migrated exception contradicts a global "never"

Global 312: "Use **`claude-p`** ..., never bare `claude -p` — in scripts and in ad-hoc
commands alike." The exception lives only at project 669–673:

> 669 Still calling bare `claude -p` (deliberately, not pending migration):
> 671 `scripts/score-day.py` / `scripts/invoice-from-worklog.py` all kill claude by pid,

Check 4 moves it into `headless-claude`, keeping only `.is_error`, the `llm-output`
no-fallback rule and `cli_path`. A session fixing a bug in `bin/tab-organize` will not
think "headless-claude" and load the skill; it will see the global "never" and migrate
the call — creating the orphaned `timeout`+`claude` the wrapper exists to prevent.
`services/youtube-transcribe/server.py:1194` carries a "Deliberately NOT migrated to
claude-p" comment, so it is protected at the call site. **`bin/tab-organize` has no such
comment** (it has `kill_group` / `start_new_session=True` at 260–299, but nothing that
says "do not switch to claude-p"). Keep the 669–673 sentence in the root, and add a
one-line comment in `bin/tab-organize`. Best of all: one clause in global 312, "except
callers that kill claude by pid — see the comment at each".

### P3 (high, decision needed) — pinning auto mode changes headless runs

The report says auto mode "looks like the account default" and that pinning it only
guards against that default changing. That holds for interactive sessions only. Measured
today with `claude-p --output-format stream-json --verbose`:

- Current settings: headless init reports `permissionMode: default`.
- With `--settings='{"permissions":{"defaultMode":"auto"}}'` (the same value from a
  flag source): `permissionMode: auto` for both `--model haiku` and `--model sonnet`;
  output stayed clean (`ok`, `is_error: false`).

The probe set the value from a flag source. That the user-scope file has the same effect
under `--safe-mode` is inferred, not measured — but `claude-p` documents that safe-mode
leaves permissions normal, so expect a user-scope `defaultMode` to reach every headless
caller (`cc-session-review`, `tab-organize`, youtube-transcribe, any SDK
caller that reads user settings). In `default` mode a headless run *denies* any tool call
that needs approval; in `auto` mode the classifier may approve it. That widens what those
agents can do and adds classifier calls. It may be fine — most callers pass `--tools=''`
or a schema — but it is a real change, not the no-op the report describes.

Fix: either accept it explicitly, or pin auto and have `bin/claude-p` pass
`--permission-mode default` unless the caller passes its own. That does not cover the
callers that run bare `claude -p` on purpose (P2) or the SDK callers; each of those needs
its own `--permission-mode default` (SDK: `permission_mode`). Verify once with a
`claude-p` stream-json probe after the pin. (The `ccs.fish` flag list at
993 already knows `--permission-mode` as a flag.) The report's other claim checks out:
the binary's own guidance says the value must be in the user file, which
`rcs/claude-settings.json` is, and no project/local `defaultMode` shadows it here.

### P4 (high, sequencing) — another session's uncommitted edits sit inside moved text

`git diff HEAD` shows two uncommitted hunks in `CLAUDE.md`:

- line 85: the new `freeze-logger` row in Available Services (stays in root — low risk);
- lines 438–444: the `cmus-add-new` rewrite **inside Music streaming**, which check 4
  moves wholesale into skill `music-server`.

`rcs/claude-settings.json` also has uncommitted changes (`"model": "opus"`,
`advisorModel`, `promptSuggestionEnabled`, `preferredNotifChannel`,
`remoteControlAtStartup`, a `claude-fable-5-2` effort entry). Some look like Claude Code
`/config` saves adopted by `rcs-sync`, but they are uncommitted either way.

If the cleanup moves the music section now, its journal holds a deletion of lines that
include the peer's uncommitted text plus a new skill file containing that text.
`commit-mine` replays onto `@-`, where those lines do not exist. I did not test the
outcome. `docs/cc-jj-sessions.md:123` says edits are anchored by context in `@-`, so the
likely result is a refusal (exit `1`) that wedges the cleanup commit; the bad case is the
peer's text landing in the cleanup commit (inside the new skill file) and the peer's own
`commit-mine` then failing to find its context. Either way, do not overlap. Also, the report's safety net "The current
text stays recoverable with `jj file show -r @- CLAUDE.md`" is false for those hunks —
they are not in `@-`.

Fix: have the other session (or the user) commit first. Then do the restructure as its
own commit while no other live session has edits in `CLAUDE.md` or
`rcs/claude-settings.json`. Do the settings edits (kagi allow rule, auto mode,
`skillOverrides` if kept) in a separate small commit.

### P5 (medium) — omissions from the "stays in root" lists

Lines whose loss causes damage, not just inconvenience. Each is one short line.

Music (check 4 keeps four rules):
- 371 "A script that writes to `/mnt` must first run `/usr/local/bin/crypt-mounted`" and
  the next sentence, "Unmounted, either path is a plain folder on the root disk." A write
  to an unmounted `/mnt` fills the server's root disk. Keeping "find disks by DUID" does
  not cover this.
- 416 "any new folder under `/mnt` that holds private data needs group `wheel` and mode
  750 or 700" — the default 755 is readable by `musicread`. A security rule.
- 363–364 "The private key is `~/.config/age/akr-backup.key` and Proton Pass, never the
  server." A security "never" the report omits despite claiming "every never rule stays".
- 377 `/music` is `noauto` in fstab because a failing fsck in a normal entry drops the
  boot to single-user mode. Someone "tidying" fstab breaks remote boot.

Headless:
- 669–673 (see P2).
- 692 "never re-parse `.result`" (read `.structured_output`).
- 664 "Model pins: prefer floating aliases" — dated ids are "the retirement trap". A
  session writing any new script that calls claude needs it; global has 0 hits for it.
- 802 `cc-session-review`'s `grep -q NO_UPDATES_NEEDED` "is also left alone" — a
  dotfiles fish function a session might "fix".

Session-scoped jj commits (check 4 keeps four rules):
- 253 "Exit `4` means locked or the base moved — retry, it is not an error." Without it a
  session treats a routine retry as a failure. (`docs/cc-jj-sessions.md:74` has it, but
  only if read.)

Live Transcribe:
- 481 keeps "Never pass `--save-audio`" but must also keep "an `--output-dir` in the
  scratchpad" from the same line: the default output is `~/transcripts` =
  `~/Cloud/transcripts` (478), so a test without it writes into the real ProtonDrive
  transcript folder.
- 482 "Check `pgrep -f LiveTranscribe.app/Contents/MacOS/` first" — a test slows a live
  session.

Hermes (keeps only the reserved-keys table):
- 568 "A duplicate key fails *silently*" and 572 "one-off scripts go in `x` (+utils)".

Testing (keeps `cmds test` and `COMPONENTS`):
- 829–831 "put `--` before it. Do not write `cmds test fish -- -k foo`" — a usage trap
  every test run can hit.
- 838–839 "keep Python out of fish strings" — this is a fish-authoring rule, not a
  testing one. Move it into `ai/skills/fish/SKILL.md`, which is REQUIRED before any fish
  edit, instead of `docs/testing.md`.

LaunchAgents: 55 (see P1). Shell Commands table: the `ccjj forget` row's "Records are
**moved**, not unlinked ... because the edits they describe then silently stop being
committed" is a warning, not a restatement; it points at a `.cc/plans/` file, not a
section. Keep that clause. (The report's "restate their own sections" is also false for
`revive`, `cc-worktree` and `roleplay-roll`: they point at `docs/`, which does carry the
content — `docs/cc-worktree.md:110–122` has the symlink gotcha, `docs/revive.md` the
GUID story, `docs/claude-roleplay.md:209` "The hook fails open, deliberately" — so
shortening those three is fine.) The rows for `ccs`, `commit-mine`, `claude-p` and
`llm-output` point at sections that check 4 moves away; each shortened row must name the
new target (`docs/ccs.md`, `docs/cc-jj-sessions.md`, skill `headless-claude`).

### P6 (medium) — check 10's global keep lists

Global rules not in any keep list, each needed outside this repo:
- 285 "Do not 'fix' that by redoing the work." and 287 "Tell by location: ... cwd is
  under `.claude/worktrees/<name>/`, or `.git` is a **file**". The nudge re-asserts the
  rule each prompt, but the detection line is what makes it usable without the nudge.
- 402 "It needs `svc_cmd` ...; without one, ask me. Stop only what you started" and 403
  "If `svc` reports 'not running', also check whether it's a `service`". Both are
  behavioural rules for any project with `.svc.conf`.
- 413 "`nohup` does not escape this, and macOS has no `setsid` command" — the reason the
  kept double-fork line exists; without it a session tries `nohup` first.
- 234–236 (sound pages: write locally, open in Brave, publish only if asked) and 248 "Do
  not grep the transcripts first" — these are instructions, so the pointer line must
  state the rule, not just the topic.
- 305–306 (P1).

Pointer mechanics: the global file loads in every project, so the pointer must be an
absolute path (`~/dotfiles/docs/claude-global/<x>.md`), not `docs/claude-global/...`.
Reading a file outside the current project can raise a permission prompt in default
mode, which makes the model less likely to follow the pointer. Moving the text adds no
new public exposure: `rcs/claude-user-claude.md` is already tracked here.

### P7 (medium) — reach of skills and docs pointers

- **ccs (256–325) gets a bare "one pointer line".** It is the section densest in
  invariants: 273 "no hook writes it" (`.cwd`), 275 "`ccs resume` archives only after
  the transcript is in place", 312 "Both hooks gate on identity", 323 "Every fix
  considered (tombstone files, pid checks) introduced a worse failure mode" (that is,
  do not try them again). Work here is usually an edit to `fish/functions/ccs.fish`, the
  wrapper or a hook, often while debugging something else. Use the fish pattern, which
  has evidence behind it (78 uses): "**REQUIRED:** read `docs/ccs.md` before editing
  `fish/functions/ccs.fish`, `my-claude-code-wrapper.fish`, `bin/ccs-title-hook`,
  `bin/ccsave-hook` or `services/cc-transcript-backup/`." Name the files; a topic name
  does not match a task.
- **Skills load only on a description match.** `music-server` must name the surfaces in
  its description: cmus, `bin/cmus-add-new`, `music push`, `services/music-mount`, rclone,
  remote-sync, Navidrome, the server's disks. Same for `headless-claude`: "writing or
  editing any script or service that calls `claude -p` or the Agent SDK". Consider
  putting the server half of the music section in the existing
  `remote/anthonydambrosio.me/README.md` or the `headscale` skill (same server), and
  keeping only the Mac half in the new skill.
- **Registration is not what the report says, and editing the registry deletes
  `ui-style`.** The wrapper syncs any folder that has a `.claude/` dir, including `~`
  (`~/.claude/.cc-sync-stamp` exists, dated Nov 9 10:47, the same minute as the
  `~/.claude/skills/{cmds,fish}` and `~/.claude/commands/*` links). The stamp hashes
  `ai/cc-config.json`, so *any* registry edit — adding a skill, removing `prompt:build`
  — triggers a re-sync at the next `claude` launched from `~`. That sync is "Wipe and
  relink" (`fish/functions/cc-config.fish:503–509` removes every symlink in the target
  dir first). `~/.claude/skills/ui-style` is a symlink that is **not in
  `ai/cc-config.json`** (added Nov 12 by some other route), so it would be silently
  deleted, and the user-level UI style skill would vanish from every project. Fix:
  register `ui-style` in `#GLOBAL` (or wherever it belongs) in the same edit, before
  anything else touches the registry. Other points: a skill added to `#GLOBAL` lands at
  user level and in every project that inherits `#GLOBAL` (`#clojure`, `#macos`); a
  dotfiles-only skill goes in this repo's `.cc-config`, which is **untracked**
  (`git ls-files .cc-config` is empty), so a fresh machine registers it but never syncs
  it. Sync happens at the next launch, not in running sessions.

### P8 (low) — size estimates

Measured per section (bytes; chars/4 as the report uses):

- Totals are right: `CLAUDE.md` 70,092 bytes (70,138 chars per `wc -m`; ~17.5k est.
  tokens), global 27,560 bytes (~6.9k).
- Check 3: Neovim + Primary Tools + Installation = 177 + 521 + 162 = **860**, not 1,200.
  Hours + Crawler = 791 (report 900). Vault + Artifacts = 1,645 (report 1,300). Sum of
  the check 3 table as measured ≈ 12.3k (report ~13k). Fine.
- Check 4: "11.9k after check 3's cut" is the figure **before** the cut (3,564 + 8,347 =
  11,911), so check 3's 2,000 is counted twice. The check 4 table's own rows sum to about
  34k after fixing that, not the stated ~28k; the stated "after" of ~29k only works out
  if ~5k stays in the root. Real landing point: ~27–30k as proposed, ~32–34k with the
  lines this review keeps. Still well under the 40k warning line, so the extra lines are
  affordable.
- Check 10: 2,000 + 2,300 + 1,500 + 1,500 = 7,300 saved → ~20.3k, consistent. With P6's
  lines kept, ~21.5k (~1.5k tokens saved per request instead of ~1.8k).
- chars/4 likely underestimates tokens by 10–20% for this identifier-heavy text, so the
  absolute savings are a little larger than stated. That changes no decision.

### P9 (low) — check 1 details

- **kagi**: configured only for `~/dotfiles` (`~/.claude.json` project entry; no user
  `mcpServers`). So global line 254 "Kagi search ... is also available as an alternative"
  is already wrong in every other project — drop it regardless. The report misses the
  allow rule `mcp__kagi__kagi_summarizer` in `rcs/claude-settings.json` (line 81 of the
  live copy); remove it with the server. Deferred tools cost ~0 resident tokens, so this
  is declutter only, as the report says.
- **Calendar / Drive**: both now expose only `authenticate` tools, so "0 calls in 90 d"
  may just mean "signed out", not "unwanted". Deferred, so ~0 tokens. The scan covers
  Claude Code transcripts only; turning them off **on claude.ai** also removes them from
  the web and desktop apps, where there is no evidence either way. If anything, use
  `/mcp disable` in Claude Code. Note `/mcp disable` is per project, so it must be
  repeated per project to have a global effect.
- **Claude Docs**: a quick search found one transcript file with a `tool_use` of it,
  consistent with the report's "1 call" (file count, fixed key order, under a timeout —
  not an exhaustive count). It has been visible
  since about 2026-09-17, so it is not "too new" in the way `plainify` and `ui-style`
  are. Its non-deferred schemas and long server instructions are the only real resident
  cost here (estimate ~0.6–1.2k tokens). Disabling it also removes its instruction to
  make a doc first, which suits this setup. Keep, in Claude Code only.
- **`/prompt:build`**: `skillOverrides` with `"off"` is a real setting (the binary refers
  to a skill "set to off in the skillOverrides setting"). But this command is managed by
  cc-config: it is in `#GLOBAL.commands` in `ai/cc-config.json` and symlinked into
  `~/.claude/commands/` and each project's `.claude/commands/`. An override in settings
  leaves cc-config claiming it is installed — two sources of truth. Remove it from
  `#GLOBAL` instead; the next sync (in `~` and in each project) drops its links. That
  edit triggers the wipe-and-relink described in P7, so register `ui-style` first.
  ~20 tokens; doing nothing is also reasonable.

### P10 (low) — hardlink mechanics

Both edit targets are hardlinked now (same inode as their `~/.claude/` destination). An
Edit on `rcs/claude-user-claude.md` or `rcs/claude-settings.json` replaces the file and
splits the link; the `rcs-sync --hook` / ensure-rcs path then relinks (repo changed, live
unchanged → repo wins). If Claude Code saves `~/.claude/settings.json` by atomic rename
in between (any `/config`, `/effort`, `/permissions` in another session), it reports a
CONFLICT instead. After each edit, check `ls -li` shows one inode, and read any
"adopted"/"CONFLICT" line. Editing the destinations directly is blocked by the hook, as
the report already says.

## Things the report gets right

- Pure-derivable cuts (Repository Structure, XDG, Neovim, Primary Tools, Installation,
  Hours, Crawler, File Locations) carry no rule that the code lacks.
- The worktree paragraph at project 184 ff. is safe to cut: the global file (277–290)
  and `bin/cc-worktree-nudge` carry it, and it cannot arise here.
- `@` imports would save nothing; pointers are the right mechanism.
- Auto mode must be pinned in the user file, not project settings.
- Every change is reversible — except for the uncommitted peer hunks (P4).
