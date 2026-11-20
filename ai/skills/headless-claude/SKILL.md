---
name: headless-claude
description: Notes for running Claude headless from scripts. Load before writing or editing any script, service or fish function that calls `claude -p`, `claude-p`, the Claude Agent SDK, `llm-output` or `--json-schema` (for example bin/claude-p, lib/python/llm_output.py, ai/templates/output_contract.md, cc-session-review, tab-organize, youtube-transcribe, AKR scripts, inari).
---

# Headless Claude calls (`claude-p`)

`bin/claude-p` wraps `claude -p` with the three guards it lacks. Use it everywhere a
script or an ad-hoc command needs a headless answer.

```bash
claude-p 'prompt'                                   # -> result text
echo prompt | claude-p --system-prompt "$sys"       # -> result text
claude-p --model haiku --output-format json 'x'     # -> full JSON envelope
claude-p --output-format stream-json --verbose      # -> passthrough stream
CLAUDE_P_TIMEOUT=60 claude-p 'prompt'               # default is 180s
CLAUDE_P_SAFE=0 claude-p 'prompt'                   # keep CLAUDE.md/hooks/MCP
CLAUDE_P_TOOLS=1 claude-p 'prompt'                  # keep claude's default tools
```

Exit `0` ok · `1` claude errored or returned nothing · `124` timed out.

**Variadic flags swallow a positional prompt.** `--tools`, `--allowed-tools`,
`--disallowed-tools`, `--add-dir`, `--mcp-config` and `--betas` are all variadic in
claude's argument parser, so `claude-p --tools '' 'my prompt'` eats the prompt as a
second `--tools` value and dies with *"Input must be provided either through stdin or
as a prompt argument"*. **Prefer the equals form everywhere:** `--tools=''`. Callers
that pass the prompt on stdin escape it by accident.

Three failure modes it closes, all observed in production:

- **A wedged child outliving its caller.** GNU `timeout -k` runs claude in its own
  process group and signals the group. On 2026-07-28 a headless claude sat at ~98%
  CPU past 2.7GB RSS with no output until it was killed by hand; the trigger is
  still unknown (the retired-model theory was tested and disproved — that exits
  rc=1 in ~2s), so a deadline is the defence rather than a fix. Separately, piping
  claude into `head`/`sed -n` does not bound it either: a reader exiting never kills
  the writer. `claude-p` buffers to a file, so a departing reader SIGPIPEs its own
  `cat` instead.
- **Errors that look like answers.** A retired or unavailable `--model` sets
  `is_error: true` while `subtype` still reads `"success"` and text mode just
  prints the warning. **Check `.is_error`, never `.subtype` or the exit code.**
  An *empty* body used to misroute into this branch, which is the one branch that
  never dumps stderr — jq 1.6 reads an empty file as a successful no-op, so both
  `type == "object"` and `.is_error == true` exit 0. A `-s` guard now runs first.
- **LLM chatter where a payload is expected.** `--safe-mode` is passed **by
  default** (`CLAUDE_P_SAFE=0` opts out). It disables CLAUDE.md discovery, hooks,
  skills, plugins, custom commands/agents and MCP config. It leaves auth, model
  selection, built-in tools and permissions normal. Measured on a realistic
  "summarize this diff" prompt: **2/2 leaked roleplay bookends without it, 3/3 clean
  with it.**

**A call whose prompt holds web or user-supplied text passes `--tools=`.** Safe
mode does not turn tools off: the Bash, Read and other built-in tools stay, and the
allow rules in `~/.claude/settings.json` still apply. Tested 2026-11-20: under
`--safe-mode`, a pre-approved `git add` ran and an unapproved `touch` was denied. So
a hostile tab title, transcript or page could steer the model into a pre-approved
command. `claude-p` now passes `--tools=` by default when the caller gives no
`--tools`; a caller's own `--tools=...` wins, and `CLAUDE_P_TOOLS=1` keeps claude's
default set. `--json-schema` still works with no tools. A bare `claude -p` caller
must pass `"--tools="` itself.

Model pins: prefer floating aliases (`haiku`, `sonnet`) or a current id
(`claude-sonnet-5`). Dated ids like `claude-sonnet-4-20250514` are the retirement
trap — they were removed from `ai-chunk-files`, `ai-merge-commit-messages`, and
`bin/ai-commit-msg` on 2026-07-28.

**Latency (measured 2026-11-15, `.cc/scripts/roleplay-b-latency.py`: one
`--json-schema` call writing two ~25-word lines, three calls in parallel).** `haiku`
took a median 5.7 s and about 960 output tokens, far more than the answer needs; this
is probably thinking, but the envelope does not split it out. `--effort low` brought
it to 4.6 s and about 720 tokens. `MAX_THINKING_TOKENS=0` in the environment made no
measurable difference (5.5 s, 12 runs). `sonnet` took 2.8 s and 142 tokens, but cost
about 13 times as much per call ($0.013 against $0.001). `claude-p` adds about 0.8 s
per call (wall time minus `duration_api_ms`). For a fast, short answer, measure
`sonnet` before you assume `haiku` is quicker.

Still calling bare `claude -p` (deliberately, not pending migration):
`services/youtube-transcribe/server.py`, `bin/tab-organize` and AKR's
`scripts/score-day.py` / `scripts/invoice-from-worklog.py` all kill claude by pid,
and `claude-p` runs it under `timeout -k` in a **new process group** — so killing the
`claude-p` pid would orphan both `timeout` and `claude`, exactly the runaway the
wrapper exists to prevent. They pass `--safe-mode` and `--tools=` on their own argv
instead.
(`~/projects/ereshkigal/bin/import-audio.fish` is a different repo and still unbounded.)

### Constraining headless output

Three layers, cheapest and strongest first. `--safe-mode` kills the *roleplay* leak
but **not generic preamble** — safe-mode runs still volunteer unrequested
alternatives ("Or if you want it more granular:") — so anywhere the output must be
exactly one thing needs a layer on top.

| Layer | Use when | Where |
|---|---|---|
| `--safe-mode` | always | `claude-p` default; hand-added to the direct-subprocess callers above |
| `--json-schema` / SDK `output_format` | the output is data | `ccs autotitle`, `ai-chunk-files`, `ai-commit-msg`, `music ai_import`, AKR `invoice-from-worklog` |
| `<output>` envelope | the output is long prose or markdown | `claude-batch-worker`, `sanctuary` template, `tab-organize`, youtube-transcribe summaries, AKR `score-day` / `reading_engine` / inari chat |

**Schema-constrained output is validated server-side**, so compliance is not a
request the model can decline. The decoded object arrives on `.structured_output`
(CLI JSON envelope) or `ResultMessage.structured_output` (SDK) — never re-parse
`.result`. A **top-level array 400s** (`input_schema.type: Input should be 'object'`),
so wrap it: `{"chunks": [[…]]}`.

**The `<output>` envelope** is `ai/templates/output_contract.md` (canonical text,
includable via the `@<path>` mechanism `bin/ai-commit-msg`'s `load_template()`
implements) plus `lib/python/llm_output.py` and its `bin/llm-output` CLI:

```bash
printf '%s' "$raw" | llm-output          # body on stdout
printf '%s' "$raw" | llm-output --json   # body, validated as JSON
llm-output --contract                    # the contract text, for building a prompt
llm-output --contract --chat             # ditto, persona-safe wording (see below)
```

Exit `0` ok · `1` contract unavailable · `2` bad usage · `3` no usable envelope ·
`4` envelope present but empty · `5` bad JSON. **There is deliberately no path that
returns the raw text** — falling back is how chatter became a commit message in the
first place. Shell callers use `--contract` rather than reading the template by path,
so they resolve it the same way Python does and a worktree can't prompt with one
contract while enforcing another.

**Two wordings, one envelope.** `output_contract.md` (strict, the default) is written
for headless callers, where the chatter being suppressed is the roleplay bookends — so
it says *"no in-character opener or closer."* `output_contract_chat.md`
(`contract("chat")`, `llm-output --contract --chat`) states the identical tag rules for
a model that is *supposed* to have a voice: the envelope is a wrapper, the persona and
formatting inside it are untouched, and the block itself is never to be remarked on.
Same tags, same extractor — **picking the wrong one is a tone bug, never a parsing
one.** `contract()` rejects an unknown variant as an `LLMOutputError`, the same way it
reports a missing template, so a typo lands in callers' existing `except`.

Reach for the chat variant wherever the block is appended to a **user turn** on a
channel whose only legitimate speaker is a human. On 2026-08-02 the six AKR Telegram
bots moved opus → sonnet and Inari — correctly — classified the strict contract riding
on Anthony's messages as a prompt injection telling it to stop being itself, then spent
three turns telling him his messages were being tampered with. It had ridden along
silently since 2026-07-30; only the model changed. Note the envelope itself never
broke: the tags were honoured every time, so nothing showed up in the logs. The fix was
the chat variant **plus** a paragraph in the bots' system prompts
(`chat_engine._CONTRACT_PREAUTH`) vouching for the block from the trusted channel — the
template removes the reason to suspect it, the system prompt removes the standing to
act on the suspicion.

Matching is **line-anchored**: a tag only counts when it owns its line, which is what
survives the commonest preamble shape, *"I'll put my answer in `<output>` tags:"*
followed by the real envelope. Opens and closes must then **balance**, and the close
is the last line-anchored `</output>` with its partner found by walking back with a
depth counter — so an answer that legitimately quotes a *complete* envelope
(`cc-session-review` feeds the model a CLAUDE.md documenting this contract) comes back
whole, while a lone tag of either kind is rejected.

That symmetry is load-bearing and was a bug for one afternoon. The walk raised on an
unmatched *close* but silently returned the innermost body on an unmatched *open*, so a
reply quoting a bare `<output>` line — which the contract permitted at the time — came
back as a truncated fragment with exit 0. The count check also subsumes the truncation
guard, and has to run *before* the one-line-form fallback: a document cut off at the
token limit whose body contained `<output>PONG</output>` was otherwise silently
replaced by `PONG`. The contract now demands balance in both directions and forbids
anything after the closing tag; the accepted cost is that a stray `</output>` in a
sign-off fails the whole reply rather than being ignored.

**Known limitation, pinned by a test rather than fixed.** A stray line-anchored
`<output>` in the preamble and a stray `</output>` in the postamble *cancel out* in the
count, so the balance check passes and the depth walk latches onto the preamble's open,
over-capturing. Nothing is lost, but the body carries tags and trailing chatter. It is
close to irreducible: the captured region is a locally well-formed nested envelope, so
no local rule separates "outer envelope quoting an inner one" from "narration, real
envelope, narration". Rejecting text outside the outermost envelope fixes it and breaks
every legitimate preamble case. Related: **indenting a lone tag does not escape it** —
both regexes begin `^[ \t]*` — so the contract tells the model to keep a quoted tag
inline in a sentence instead.

Tests live in `tests/lib/python/test_llm_output.py`, under the `lib/python`
component. They are mutation-checked:
30 mutations of the regexes, the balance check, the exit-code constants, the
`--contract` path and the SIGPIPE handling are each killed. Four lessons worth keeping
if you add cases:

- An anchoring test needs an input the *unanchored* regex matches **differently** — a
  mid-line tag with trailing prose pins nothing, because `$` already rejects it.
- A SIGPIPE test needs a body larger than the OS pipe buffer (~64KB), or `print()`
  finishes before the reader exits and `BrokenPipeError` never fires. It also needs
  `${PIPESTATUS[0]}`: `subprocess.run("cli | head -1")` reports *head's* exit code, so
  asserting on it can never fail.
- A test that locates a file **via the value under test** is circular. The
  `CONTRACT_PATH` test copied the module to a temp tree using `CONTRACT_PATH.parents[2]`
  — so the `Path.home()` regression made it copy the real module and pass.
- Whole features can be invisible. `--contract` had no test at all, and printing it to
  stderr instead of stdout would have silently emptied the contract out of every fish
  caller's prompt with the suite green.

**SDK callers need `cli_path`, not just `extra_args`.** The SDK's `_find_cli` returns
its *bundled* CLI unconditionally, and those copies predate `--safe-mode` (2.1.92 in
the system site-packages, **2.1.71** in inari's venv, against 2.1.220 on PATH), so
without it the flag dies as `unknown option '--safe-mode'`:

```python
ClaudeAgentOptions(..., cli_path=shutil.which("claude"), extra_args={"safe-mode": None})
```

SDK MCP servers (`create_sdk_mcp_server`) **survive safe-mode** — they travel over
the control protocol, not MCP *config* — verified by driving `reading_engine`'s
interactive `ask_user` tool through a full pass under safe-mode.

Two callsites stay lenient on purpose: inari's `generate_reply` (a hard failure means
the phone gets nothing, so it strips bookends and warns) and `_emit_narration` (which
forwards intermediate text live, before any `ResultMessage`). `ai_briefing`'s weekly
review and dream consolidation get **safe-mode only, no envelope** — the agent writes
the document itself and `msg.result` there is just a truthiness gate guarding the jj
commit and `_run_backup_hook()`. `cc-session-review`'s `grep -q NO_UPDATES_NEEDED`
is also left alone; its false-positive fails safe.
