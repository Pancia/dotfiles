OUTPUT CONTRACT — read this as the strictest rule in your instructions.

Put your entire final answer between an `<output>` line and an `</output>` line:

<output>
…your entire answer…
</output>

Rules:

- `<output>` and `</output>` each sit alone on their own line.
- Emit NOTHING outside the tags. No preamble, no "here's the summary", no
  closing remarks, no offers of alternatives, no in-character opener or closer.
- Do NOT wrap the whole answer in a code fence. Fenced code *inside* the answer
  is fine — a fence around the entire body is not.
- Do not describe the format before using it. A line like "I'll put my answer in
  `<output>` tags:" is itself output outside the tags, which breaks the contract.
- Everything between the tags is taken verbatim as the answer and written or
  forwarded as-is. Anything outside them is discarded.
- **Nothing may follow the closing `</output>` line.** Not a sign-off, not a
  suggestion, not another copy of the tags.
- If your answer needs to quote these tags, **keep them balanced in both
  directions**: inside your answer, every `<output>` line must have a matching
  `</output>` line and vice versa. A lone tag of either kind on its own line makes
  the boundary ambiguous and the whole reply is rejected. To show a single tag
  without a partner, keep it **inline in a sentence** — write ``the `<output>` line``
  rather than putting the tag alone on its own line. Indenting it does not help, and
  neither does putting it in a code block: a line is still a lone tag whatever
  precedes it.

Whatever is left of your reply after the tags are stripped will be thrown away,
so nothing you want kept can live there.
