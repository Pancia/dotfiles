"""Extract the payload from an `<output>`-enveloped LLM reply.

Headless Claude callsites read the model's prose reply and treat it as data, and
LLM chatter keeps arriving where a payload is expected — the roleplay bookends
from ~/.claude/CLAUDE.md (roughly two runs in three) and generic preamble
("okay, I have all the context, here's my reply"). `--safe-mode` kills the
bookends but not the preamble, so wherever the output must be exactly one thing,
the prompt carries ai/templates/output_contract.md and the reply comes back
through here.

The one rule that matters: **a reply with no usable envelope raises.** There is
no fall-back to raw text, because falling back is precisely how chatter became
a commit message / a journal template / a day's score in the first place.

Matching is line-anchored — a tag only counts when it owns its line. That is what
survives the commonest preamble shape, "I'll put my answer in `<output>` tags:"
followed by the real envelope: mid-line tags are not tags. The close is taken as
the LAST line-anchored `</output>`, and its partner open is found by walking back
with a depth counter, so an answer that legitimately quotes a complete envelope
(cc-session-review feeds it a CLAUDE.md documenting this very contract) comes
back whole instead of being cut at the inner tag.

Line-anchored tags must also **balance**: an unmatched opening tag is as fatal as an
unmatched closing one. The asymmetry was a real bug — quoting a lone `<output>` line
is contract-legal text, and it used to come back as a silently truncated fragment.

CLI:
    llm-output < reply.txt          # body on stdout
    llm-output --json < reply.txt   # body must parse as JSON
    llm-output --contract           # the contract text, for building a prompt
Exit: 0 ok · 1 contract unavailable · 2 bad usage · 3 no usable envelope ·
4 envelope present but empty · 5 bad JSON.

`--contract` exists so shell callers resolve the contract the same way Python does —
relative to this file — instead of hardcoding a path to ~/dotfiles and defeating the
worktree-safety that CONTRACT_PATH exists for.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

__all__ = [
    "LLMOutputError",
    "MissingEnvelope",
    "EmptyEnvelope",
    "extract",
    "extract_json",
    "contract",
    "EXIT_MISSING",
    "EXIT_EMPTY",
    "EXIT_BAD_JSON",
    "EXIT_USAGE",
    "EXIT_NO_CONTRACT",
]

EXIT_MISSING = 3
EXIT_EMPTY = 4
EXIT_BAD_JSON = 5
EXIT_USAGE = 2
EXIT_NO_CONTRACT = 1

# Derived from __file__, not from ~/dotfiles: a git worktree or a copied tree must
# prompt with the contract that ships beside it, or the model is told one thing and
# the extractor enforces another. lib/python/llm_output.py -> parents[2] is the root.
CONTRACT_PATH = (
    Path(__file__).resolve().parents[2] / "ai" / "templates" / "output_contract.md"
)

# A tag counts only when it owns its line. `<output ...>` with attributes is
# tolerated: models add them unprompted, and rejecting the whole reply over an
# attribute would be a loss with no upside.
#
# `[ \t][^>\n]*?` rather than `\s[^>]*?` for that attribute part, deliberately: `\s`
# and `[^>]` both match a newline, so under MULTILINE the old form let a single open
# tag span lines — which silently fused a body line beginning `<output` with a later
# line ending in `>` and swallowed everything between them.
_ATTRS = r"(?:[ \t][^>\n]*?)?"
# `(?<!/)` so a self-closing `<output />` is not also counted as an opening tag. The
# old code hid this by testing _SELF before _OPEN; once opens and closes have to
# balance, an over-broad _OPEN turns an empty envelope into a truncation error.
_OPEN = re.compile(rf"^[ \t]*<output{_ATTRS}(?<!/)>[ \t]*$", re.MULTILINE)
_CLOSE = re.compile(r"^[ \t]*</output[ \t]*>[ \t]*$", re.MULTILINE)
_SELF = re.compile(rf"^[ \t]*<output{_ATTRS}/>[ \t]*$", re.MULTILINE)
_ONE_LINE = re.compile(
    rf"^[ \t]*<output{_ATTRS}>(?P<body>.*?)</output[ \t]*>[ \t]*$", re.MULTILINE
)


class LLMOutputError(Exception):
    """Base for every way an enveloped reply can be unusable."""


class MissingEnvelope(LLMOutputError):
    """No usable `<output>` envelope: absent, unclosed, or unbalanced."""


class EmptyEnvelope(LLMOutputError):
    """An envelope was found but its body is empty or whitespace only."""


def contract() -> str:
    """The canonical contract text, for appending to a prompt.

    Read from ai/templates/output_contract.md rather than duplicated here, so the
    shell callers' `@<path>` includes and the Python callers say the same thing.

    A missing file surfaces as LLMOutputError rather than FileNotFoundError: callers
    build prompts inside `except LLMOutputError` blocks, and an OSError leaking past
    them turns a missing template into an unhandled crash somewhere unrelated.
    """
    try:
        return CONTRACT_PATH.read_text().rstrip("\n")
    except OSError as e:
        raise LLMOutputError(f"cannot read the output contract at {CONTRACT_PATH}: {e}") from None


def _match_open(text: str, close_start: int) -> re.Match[str]:
    """Find the `<output>` that partners the close at ``close_start``.

    Walks the line-anchored tags before it back-to-front with a depth counter, so
    a quoted inner envelope inside the body doesn't get mistaken for the real
    opening tag — and, equally, a model that restates the template *before*
    answering ("<output>your answer</output>… here's the actual answer:") does
    not drag its example into the payload.
    """
    tags = [(m.start(), True) for m in _OPEN.finditer(text, 0, close_start)]
    tags += [(m.start(), False) for m in _CLOSE.finditer(text, 0, close_start)]
    if not tags:
        raise MissingEnvelope(
            "reply has a closing </output> with no opening <output> line"
        )
    tags.sort(reverse=True)

    depth = 1
    for pos, is_open in tags:
        depth += -1 if is_open else 1
        if depth == 0:
            return next(m for m in _OPEN.finditer(text, pos) if m.start() == pos)
    # Equal counts overall (extract() checked) but interleaved so the last close has
    # no partner — e.g. `<output> </output> </output> <output>`. Genuinely ambiguous.
    raise MissingEnvelope(
        "unbalanced <output> tags: the closing line has no matching opening line "
        "before it, so the payload boundary is ambiguous — refusing to guess"
    )


def extract(text: str, *, allow_empty: bool = False) -> str:
    """Return the body of the `<output>` envelope in ``text``.

    Raises MissingEnvelope when there is no usable envelope and EmptyEnvelope
    when the body is blank (unless ``allow_empty``). Leading and trailing blank
    lines are stripped; interior whitespace is left exactly as the model wrote it.
    """
    text = (text or "").replace("\r\n", "\n").replace("\r", "\n")

    opens = list(_OPEN.finditer(text))
    closes = list(_CLOSE.finditer(text))

    # Balance first, and in BOTH directions. The depth walk below assumes the tags
    # nest, and an unmatched *extra open* used to make it stop early and return the
    # innermost body — so a reply quoting a lone `<output>` line came back as a
    # fragment, silently, exit 0. That is contract-legal text (the contract only ever
    # demanded that closing tags be matched), and it lands precisely on
    # cc-session-review, which feeds the model a CLAUDE.md documenting these tags.
    #
    # The count check also subsumes the truncation guard, and has to run *before* the
    # one-line fallback below: a document cut off at the token limit whose body
    # happened to contain a one-line envelope was otherwise silently replaced by that
    # one-liner, walking straight past the guard written to stop exactly that.
    if len(opens) != len(closes):
        if not closes:
            raise MissingEnvelope(
                "reply opens <output> but never closes it — most likely truncated "
                "at the token limit; refusing to return the partial body"
            )
        if not opens:
            raise MissingEnvelope(
                "reply has a closing </output> with no opening <output> line"
            )
        raise MissingEnvelope(
            f"unbalanced <output> tags: {len(opens)} opening line(s) against "
            f"{len(closes)} closing — the payload boundary is ambiguous, refusing "
            f"to guess"
        )

    if closes:
        close = closes[-1]
        open_ = _match_open(text, close.start())
        body = text[open_.end() : close.start()]
    else:
        # No tags that own their line at all. A short answer may have used the
        # one-line form, or the self-closing form for an empty one.
        one_liners = list(_ONE_LINE.finditer(text))
        if one_liners:
            body = one_liners[-1].group("body")
        elif _SELF.search(text):
            body = ""
        else:
            raise MissingEnvelope(
                "reply contains no <output> envelope (a tag only counts when it "
                "owns its line)"
            )

    body = body.strip("\n")
    if not body.strip() and not allow_empty:
        raise EmptyEnvelope("<output> envelope is empty")
    return body


def extract_json(text: str, *, expect: type | tuple[type, ...] | None = None):
    """Extract the envelope body and decode it as JSON.

    ``expect`` type-checks the decoded value (e.g. ``list``), because valid JSON
    of the wrong shape is a distinct failure from invalid JSON and callers that
    index into it deserve to hear which one happened.
    """
    body = extract(text)
    try:
        value = json.loads(body)
    except json.JSONDecodeError as e:
        raise LLMOutputError(f"<output> body is not valid JSON: {e}") from None
    if expect is not None and not isinstance(value, expect):
        names = expect.__name__ if isinstance(expect, type) else "/".join(
            t.__name__ for t in expect
        )
        raise LLMOutputError(
            f"<output> body decoded as {type(value).__name__}, wanted {names}"
        )
    return value


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    # Reject rather than ignore. A silently-dropped `-j` typo returned prose with exit
    # 0, which a caller then piped into jq.
    unknown = [a for a in argv if a not in ("--json", "--contract")]
    if unknown:
        print(f"llm-output: unknown argument(s): {' '.join(unknown)}", file=sys.stderr)
        print("usage: llm-output [--json] < reply | llm-output --contract",
              file=sys.stderr)
        return EXIT_USAGE

    if "--contract" in argv:
        if "--json" in argv:
            print("llm-output: --contract and --json are mutually exclusive",
                  file=sys.stderr)
            return EXIT_USAGE
        try:
            print(contract())
        except LLMOutputError as e:
            print(f"llm-output: {e}", file=sys.stderr)
            return EXIT_NO_CONTRACT
        return 0

    want_json = "--json" in argv
    try:
        if want_json:
            value = extract_json(sys.stdin.read())
            print(json.dumps(value))
        else:
            print(extract(sys.stdin.read()))
    except BrokenPipeError:
        # A departing reader is not our error — `llm-output < big | head -1` printed a
        # full traceback and exited 1, which is none of the documented codes. Point
        # stdout at devnull so the interpreter's shutdown flush stays quiet too. Same
        # discipline bin/claude-p applies to claude.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0
    except MissingEnvelope as e:
        print(f"llm-output: {e}", file=sys.stderr)
        return EXIT_MISSING
    except EmptyEnvelope as e:
        print(f"llm-output: {e}", file=sys.stderr)
        return EXIT_EMPTY
    except LLMOutputError as e:
        print(f"llm-output: {e}", file=sys.stderr)
        return EXIT_BAD_JSON
    return 0


if __name__ == "__main__":
    sys.exit(main())
