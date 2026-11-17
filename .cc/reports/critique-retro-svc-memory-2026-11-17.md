# Critique: retro proposals (svc config reload, TCC EPERM, cmds.rb comment, macOS memory, shadow-cljs pin, subagent fixes)

Date: 2026-11-17 (times MST). Read-only review. No project, config or vault file
was changed. Behaviour tests ran in a `scratch new` folder against a demo service.
Patch and test script: `.cc/misc/svc-retro-critique/`.

Token counts use `bin/tokencount` (cl100k). Claude's tokenizer differs, so treat
them as approximate (often 10-20 % higher). Every figure is input tokens, loaded
in every session, for a line added to `rcs/claude-user-claude.md`.

## Summary

| # | Proposal | Verdict | Global tokens |
|---|---|---|---|
| 1 | Docs line: svc.conf edits need a full stop/start | changed: fix `supervise`; doc only `svc_setup` | 0 |
| 2 | Global line: bg sessions get EPERM on protected folders | changed: key on the symptom, not on "background session" | ~50 |
| 3 | Fix vault cmds.rb comment | confirmed, plus the same error in global CLAUDE.md | +8 net (fix of existing lines) |
| 4 | Global rule: report footprint, not RSS | confirmed, shorter wording | ~25 |
| 5 | Startup check for the pinned cider-nrepl | changed: diagnosis false; use the alias, no pin | 0 |
| 6 | Global rule: send approved fixes to the reviewing subagent | changed: narrow to "later steps of a task given to a subagent" | ~34 |

## 1. svc.conf edits need a full stop/start - CHANGED

**Diagnosis: true, and it is live right now.**
- `supervise` evaluates `svc_cmd` once (bin/supervise:68-72) and keeps `"$@"` for
  every respawn. `svc restart`, `svc suspend/resume`, the `r`/`s`/`q` keys and
  `--keep` all reuse it.
- Test (`test-svc-restart-reread.sh` against `~/dotfiles/bin`): after editing
  `svc_cmd` from v1 to v2, `svc restart` and suspend+resume both start v1.
- Live: the three festivar supervisors started 15:55:32 (pidfile cookie). The
  vault svc.conf was changed again at 16:01:04 (vault commit "browser 1.5g; exit
  on OutOfMemoryError"). All three running JVMs show `-Xmx1g` and none has
  `-XX:+ExitOnOutOfMemoryError`. So the last svc.conf edit is not in effect.
  Nothing was restarted by this review.

**Would the proposed docs line work?** Yes, but it is heavier than needed:
- `svc-tmux down` (all) then `up` restarts all three JVMs. The server's
  `svc_setup` then fetches credentials from Bitwarden again (login/unlock).
- Per service is enough: `svc-tmux down browser; svc-tmux up browser`.
- It leaves the trap in place for every future session and every project.

**Better: make `supervise` re-read `svc_cmd` at each respawn.** Prototype:
`.cc/misc/svc-retro-critique/supervise-reread-svc_cmd.patch` (12 lines).
- Re-reads only when the command came from `svc_cmd` (not `supervise name -- cmd`).
- Re-reads at the spawn site, so restart, resume and `--keep` all apply it.
- Reads in a subshell with `svc_cmd` unset first, so a broken config cannot kill
  the supervisor and cannot silently return the old definition.
- Tested: restart after edit -> v2; suspend+resume after edit -> v3; syntax error
  in the config -> keeps the old command, prints "could not re-read svc_cmd",
  supervisor stays up; `svc_cmd` removed -> same.
- (A first version without `unset -f svc_cmd` silently returned the old command
  on a broken config. The subshell inherits the parent's function.)

**What it changes / could break:**
- `svc_setup` still runs only once. An edit to `svc_setup` (or to `SVC_ENV`,
  which svc-tmux applies at window creation) still needs a per-service
  `svc-tmux down <name>; svc-tmux up <name>` by the user.
- Trade-off: today the command is fixed when the user starts the supervisor.
  After the patch, an LLM's `svc restart` runs whatever the config now says,
  inside the environment that `svc_setup` exported (AWS credentials). The config
  is in the user's vault, so the LLM edits it only when asked; but an LLM edit
  then takes effect without the user starting anything. I think that is the
  intended workflow, but it is a real change of who controls the command.

**Cheap detection (`svc restart` warns):** works. The pidfile cookie is the start
epoch, and today's data proves it (15:55:32 < 16:01:04). But mtime also fires on
comment-only edits. With the patch, a better signal is exact: `supervise` prints
"svc_cmd changed" to the pane. For the caller, `svc restart` could print one note
when any `svc_conf_files` mtime is newer than the cookie: "config changed since
this supervisor started; svc_cmd edits apply now, svc_setup edits need
`svc-tmux down/up <name>`". About 5 lines in `cmd_restart`. Optional.

**Revised fix:**
1. Apply the patch to `bin/supervise` (add the test to `tests/svc/`).
2. One line in the wiki config section and in festivar CLAUDE.local.md
   "Restarting a service": "`svc restart` re-reads `svc_cmd`. `svc_setup` runs
   once per supervisor: after editing it, ask the user to run
   `svc-tmux down <name>; svc-tmux up <name>`." (project-local file, ~35 tokens
   in festivar sessions only; 0 global).
3. Tell the user the browser/server/test_repl JVMs do not yet run the 16:01
   config.

**Worse defect nearby:** a syntax error in any svc config makes `svc` itself exit
2 at source time (`set -e` + top-level `.`). `svc status`, `svc stop` and
`svc restart` all stop working until the file is fixed, and `supervise`/`svc-tmux
up` refuse to start. A half-saved vault edit can therefore cut the LLM off from
the whole control surface. Fix: in `svc`, source each file with `|| echo "svc:
config error in $_cf" >&2` so status/stop still work on the state files.

## 2. Background sessions and TCC-protected folders - CHANGED

**Diagnosis: true for the host that was tested, not for every bg session.**
- Re-probed now: bg session 34943 and its host 32688 (`ClaudeCode.app ...
  --bg-pty-host`) -> responsible 32688 (ClaudeCode.app). The spare host 94777 and
  its `bg-spare` child 94788 -> responsible iTerm2. Same binary; the spare was
  started as `claude bg-pty-host`, not through the ClaudeCode.app path.
- So "in a background session, reads fail" overclaims. "Can fail" is accurate.

**Can a session tell it is a background session?** Partly, and it does not help:
- The bg session process env has `CLAUDE_CODE_SESSION_KIND=bg` (also
  `CLAUDE_BG_BACKEND=daemon`, `CLAUDE_JOB_DIR`). A foreground session (this one)
  has neither.
- But the spare (iTerm2-responsible, reads fine) also has
  `CLAUDE_CODE_SESSION_KIND=bg`. The variable does not tell grant or no grant.
- Unchecked: whether the Bash tool's shells inherit the variable. The bg session
  had no child process to inspect.
- The transcripts mark it too (`"sessionKind":"bg"`, 5 transcripts), but a session
  cannot read its own record cheaply.

**Revised fix:** key the rule on the symptom. Add to the "Cloud-only files in
~/Cloud" section:

> EPERM on a read under `~/Cloud`, `~/Developer`, `~/Documents` or
> `~/Downloads`, when file modes allow it, is macOS privacy: a background session
> can lack these grants. Ask me; do not work around it.

~50 tokens (the proposal's 35 was low). A docs file plus pointer ("EPERM under
... : read `docs/claude-global/tcc-eperm.md`") is ~32 tokens, but the line is
already short and self-contained; the saving is ~18 tokens and costs one Read
when it fires. Recommend the inline line. Note `~/Developer` is a link into
ProtonDrive and `~/Desktop` is denied for iTerm2 too, so leave Desktop out.

## 3. Vault cmds.rb comment - CONFIRMED (plus a wider error)

- True: cmds.rb lines 20-21 say the commands live in `.svc.local.conf`. No
  `.svc*` file exists in the project root; `svc_cmd` and `svc_setup` are in the
  vault `svc.conf` in the same folder.
- `svc` has no subcommand that prints where config is read from.
  `svc_conf_where` is an internal shell function used only in error messages, so
  the comment should not name it.
- Revised comment: "The commands live in svc.conf next to this file (svc_cmd,
  svc_setup), shared with `svc-tmux up`. These run one service in this pane
  instead." Commit in the vault afterwards (backup runs on commit).

**Worse defect nearby (global):** the same wrong pointer is in every session.
`rcs/claude-user-claude.md` line 329 ("Declared in ... `.svc.conf` /
`.svc.local.conf`") and line 357, plus `docs/claude-global/background-processes.md`
line 43, omit the vault `svc.conf`, which is where festivar's config lives. That
is how an agent ends up looking for `.svc.local.conf`. Fix:
- line 329 cell: "`.svc.conf`, vault `svc.conf` or `.svc.local.conf`" (34 -> 36)
- line 357: "Per-project services are declared in `.svc.conf`, the vault
  `svc.conf` or `.svc.local.conf`" (16 -> 22)
- Net +8 tokens. Same edit in background-processes.md (not loaded by default).
- Minor: `svc_conf_where` prints only the logical path and joins the files with
  "or", though all three are sourced in layers. A `svc config` subcommand that
  prints `svc_conf_files` (3 lines) would answer "where" exactly. Optional.

## 4. macOS process memory - CONFIRMED, shorter wording

Measured on the three running JVMs (no sudo needed; same user):

| process | `ps` rss | `top -stats mem` | `footprint -p` | `vmmap --summary` |
|---|---|---|---|---|
| browser | 1310 MB | 1476M | 1477 MB | 1.4G |
| server | 387 MB | 784M | - | - |
| test_repl | 30 MB | 872M | 872 MB | 871.5M |

- `top` MEM, `footprint` and vmmap "Physical footprint" agree. They are
  phys_footprint, which is Activity Monitor's Memory column. RSS leaves out
  compressed pages: test_repl shows 30 MB RSS against 872 MB footprint.
- Speed: `footprint PID` 0.11-0.14 s, `top -l 1 -pid PID -stats pid,mem` 0.33 s,
  `vmmap --summary` 1.4-2.2 s. Use `footprint` (or `top` for several pids).
- Revised line (~25 tokens): "For a macOS process's memory, give `footprint PID`
  (Activity Monitor's figure), not `ps` RSS."

## 5. Pinned cider-nrepl in the direct shadow-cljs command - CHANGED (diagnosis false)

**Where 0.25.8 comes from:** not from the launcher or the shadow-cljs version.
- `node_modules/shadow-cljs/cli/dist.js` contains no "cider". Its deps-mode
  builder (`$o`) takes `:deps :aliases` from shadow-cljs.edn, adds the user
  config's `:deps-aliases`, `-Sdeps` only for `:dependencies`/`-d`, and `-J` for
  each `:jvm-opts`.
- The user config is `$XDG_CONFIG_HOME/shadow-cljs/config.edn`
  (= `~/.config/shadow-cljs/config.edn`, from `rcs/shadow-cljs.config.edn`):
  `{:deps-aliases [:local/cider] ...}`.
- `:local/cider` in `~/.config/clojure/deps.edn` is
  `cider/cider-nrepl {:mvn/version "0.25.8"}`.
- So a shadow-cljs upgrade will not change it. It drifts only if the user edits
  that alias or `:deps-aliases`, or the repo changes shadow-cljs.edn
  `:deps {:aliases [:cljs :test]}`.
- The svc.conf comment "the launcher also adds cider-nrepl 0.25.8" is therefore
  wrong too.

**Classpath check (computed only; no JVM started, ports 9000/9630 untouched):**
- `shadow-cljs classpath` in deps mode runs `clojure <launcher args> -Spath`
  before any server logic. It took 0.14 s.
- Launcher classpath vs `clojure -A:cljs:test:local/cider -Spath`: byte-identical.
  Vs the current `-Sdeps` pin: same entries. `-Spath` itself: 0.03 s (cached).

**Nothing else lost by bypassing the launcher:**
- `--npm` is declared in `shadow.cljs.devtools.cli-opts` as "internal, used by the
  shadow-cljs npm package". A scan of the shadow-cljs 2.24.1 jar's devtools
  sources found no read of it (the `npm` keys there are runtime components).
- The launcher's only other node-side step (`op`) warns if package.json lacks
  shadow-cljs. The `-XX:-OmitStackTraceInFastThrow` flag in svc_cmd is redundant:
  the clojure CLI already adds it (it shows twice in `ps`).
- The JVM loads the user config (`open-file-command`) itself
  (`shadow.cljs.devtools.config/load-user-config`), so that still works.

**Keeping the launcher with a local heap cap: not possible without a repo edit.**
- `--config-merge` merges into the build config, not the launcher's `:jvm-opts`.
- `JDK_JAVA_OPTIONS=-Xmx300m java -Xmx2G` and the same with `JAVA_TOOL_OPTIONS`
  both give MaxHeapSize 2 GB: the launcher's `-J-Xmx2G` wins.
- An alias `:jvm-opts` loses too: the clojure CLI puts `-J` options after alias
  jvm-opts.
- The launcher's EDN reader supports `#shadow/env` with a default. A one-line
  repo change such as `:jvm-opts [#shadow/env ["SHADOW_XMX" :default "-Xmx2G"]]`
  would let everyone keep 2 GB and let the vault set its own cap through the
  launcher. Unchecked (not run), and it needs a team-visible commit.

**Revised fix (no pin, no 1-2 s check):**
1. In the browser `svc_cmd`, replace the `-Sdeps "{...cider-nrepl 0.25.8...}"`
   pin with the alias: `-A:cljs:test:local/cider`. It follows the user's own
   alias, so the version can never drift from what the launcher would use.
   Fix the comment to say where cider comes from.
2. Optional warning for the remaining drift (repo aliases, user deps-aliases),
   ~0.2 s per start, inside the command string before `exec`:
   `cmp -s <(shadow-cljs classpath 2>/dev/null) <(clojure -A:cljs:test:local/cider -Spath) || echo "WARN: browser classpath differs from the shadow-cljs launcher's" >&2`.
   It fails soft (warns, still starts). Note `shadow-cljs` must resolve to the
   project's `node_modules/.bin` launcher in that shell.
3. The `-J-XX:-OmitStackTraceInFastThrow` can go (redundant).

## 6. Send approved fixes to the reviewing subagent - CHANGED (narrower)

- No conflict with "Agent chatter" (that rule is about not announcing a finished
  agent) or the "Reporting Back" agent rules. No existing rule says who does the
  follow-up work.
- The proposed wording overgeneralises in two ways. It would also fire when the
  user approved a review he did not frame as "the subagent fixes it". And it
  says nothing for the case where the user asks the main session to fix.
- The real lesson from the incident: the user gave one subagent a task with a
  later step ("review, then wait for approval, then fix and commit"). The later
  step belonged to the same agent.
- Revised line (~34 tokens): "When I give a subagent a task with later steps
  ("review, then fix after I approve"), send those steps to that agent with
  SendMessage, unless I say otherwise."
- It is one incident. If the user prefers to save the tokens, a retro note in
  the dotfiles CLAUDE.md (loaded only in dotfiles sessions) is the cheaper home,
  since that is where "dotfiles subagent" reviews happen.

## Evidence files

- `.cc/misc/svc-retro-critique/supervise-reread-svc_cmd.patch`
- `.cc/misc/svc-retro-critique/test-svc-restart-reread.sh` - run against
  `~/dotfiles/bin` (shows the defect) and against a patched copy (shows the fix).
  Its output for both runs is quoted in item 1.
