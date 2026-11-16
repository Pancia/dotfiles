# Shelling out to Claude (`claude -p`)

Use **`claude-p`** (`~/dotfiles/bin/claude-p`), never bare `claude -p` — in scripts
and in ad-hoc commands alike. It is a drop-in: same flags, same `--output-format`
(text / json / stream-json), same stdin handling. It adds the three guards bare
`claude -p` lacks:

- **A hard deadline.** `timeout -k` in its own process group, so a wedged child
  cannot outlive the call. `CLAUDE_P_TIMEOUT` (default 180s) to adjust.
- **Real error detection.** It asks for JSON underneath and checks `.is_error`.
  A retired or unavailable `--model` returns `is_error: true` while `subtype`
  still reads `"success"` — so **`.is_error` is the only trustworthy signal**.
  An unvalidated caller otherwise treats the error text as a real answer.
- **A clean room.** `--safe-mode` by default (`CLAUDE_P_SAFE=0` to opt out), which
  disables CLAUDE.md discovery, hooks, skills, plugins and MCP config while leaving
  auth, model selection, built-in tools and permissions normal.

Exit codes: `0` ok · `1` claude errored or returned nothing · `124` timed out.

**Never pipe a raw `claude -p` into `head`/`sed -n`.** A reader exiting does not stop
the writer, so the claude process keeps running with nothing watching it. (`claude-p`
buffers to a file, so that SIGPIPE lands on its own `cat`.)

**Prefer the equals form for variadic flags:** `--tools=''`, not `--tools ''`.
`--tools`, `--allowed-tools`, `--disallowed-tools`, `--add-dir`, `--mcp-config` and
`--betas` all swallow a following positional prompt and then die with "Input must be
provided either through stdin or as a prompt argument".

On 2026-07-28 a headless claude wedged at ~98% CPU past 2.7GB RSS with no output and
had to be killed by hand. The trigger is still unknown — the retired-model theory was
tested and disproved (that exits rc=1 in ~2s) — so a deadline is the defence.

**The roleplay bookends used to leak into headless output** — roughly two runs in
three, and `--append-system-prompt` never reliably suppressed them. `--safe-mode`
does (measured 3/3 clean on a prompt that leaked 2/2), so `claude-p` passes it by
default. Since 2026-11-15 the main model writes no bookends at all (the
roleplay-bookends mod draws them, and only for typed prompts), so this leak is
history. What safe-mode does *not* suppress is ordinary preamble, so a
caller whose output must be exactly one thing still needs `--json-schema` (for data)
or the `<output>` envelope (for prose) — see `~/dotfiles/CLAUDE.md`,
"Constraining headless output", and `llm-output`.
