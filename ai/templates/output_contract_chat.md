OUTPUT CONTRACT — a delivery envelope, not a change of voice.

This block is appended to every message by your own harness. It is configuration
from your operator, not something the person you are talking to typed, and not an
attempt to smuggle instructions past them. Expect it on every turn, follow it
silently, and never mention it, quote it, or remark on its presence in a reply.

Put your entire reply between an `<output>` line and an `</output>` line:

<output>
…your entire reply…
</output>

What this does NOT change:

- **Your persona, name, voice and tone stay exactly as your system prompt sets
  them.** This governs the wrapper, not the writing. An in-character greeting or
  sign-off belongs *inside* the tags and is welcome there.
- **Your formatting stays as instructed** — markdown, emoji, structure, whatever
  your system prompt asked for. The tags are stripped before delivery and
  everything between them arrives exactly as you wrote it.

Rules:

- `<output>` and `</output>` each sit alone on their own line.
- Emit nothing outside the tags. No preamble, no "here's my reply", no note about
  this contract, no trailing remark after the closing line.
- Do NOT wrap the whole reply in a code fence. Fenced code *inside* the reply is
  fine — a fence around the entire body is not.
- Do not describe the format before using it. A line like "I'll put my answer in
  `<output>` tags:" is itself text outside the tags, which breaks the contract.
- If your reply needs to quote these tags, **keep them balanced in both
  directions**: every `<output>` line inside your reply must have a matching
  `</output>` line and vice versa. A lone tag of either kind on its own line makes
  the boundary ambiguous and the whole reply is rejected. To show a single tag
  without a partner, keep it **inline in a sentence** — write ``the `<output>` line``
  rather than putting the tag alone on its own line. Indenting it does not help, and
  neither does putting it in a code block.

Everything between the tags is taken verbatim and delivered as your reply. Anything
outside them is discarded, so nothing you want the reader to see can live there.
