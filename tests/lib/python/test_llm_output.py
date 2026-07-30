#!/usr/bin/env python3
"""Tests for the `<output>` envelope extractor.

Placement is load-bearing: `cmds test` with no arguments runs only the components
registered in lib/python/run_tests.py, and `lib/python` is one of them. Anything
dropped under tests/fish/ or tests/hooks/ would never run, so a green
"Verification" would have meant nothing.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

DOTFILES = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(DOTFILES / "lib" / "python"))

from llm_output import (  # noqa: E402
    CONTRACT_PATH,
    EmptyEnvelope,
    LLMOutputError,
    MissingEnvelope,
    contract,
    extract,
    extract_json,
)

# Hardcoded, NOT imported from the module. Asserting `returncode == EXIT_MISSING`
# cannot detect a change to the contract value — mutating each constant left the whole
# suite green. These three numbers are the interface every shell caller sees.
EXIT_NO_CONTRACT = 1
EXIT_USAGE = 2
EXIT_MISSING = 3
EXIT_EMPTY = 4
EXIT_BAD_JSON = 5

CLI = DOTFILES / "bin" / "llm-output"


def run_cli(text: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(CLI), *args], input=text, capture_output=True, text=True
    )


class TestPreambleMentioningTheTag:
    """The commonest real preamble shape: the model narrates the format first.

    Plain greedy first-open-to-last-close matching breaks here — it starts at the
    mid-line `<output>` and yields a body beginning " tags:". Line-anchoring is
    what fixes it: a tag only counts when it owns its line.
    """

    def test_mid_line_mention_is_not_a_tag(self):
        text = (
            "Sure! I'll put my answer in <output> tags:\n"
            "\n"
            "<output>\n"
            "the real answer\n"
            "</output>\n"
        )
        assert extract(text) == "the real answer"

    def test_trailing_chatter_is_discarded(self):
        text = (
            "<output>\n"
            "the real answer\n"
            "</output>\n"
            "\n"
            "Or if you want it more granular:\n"
            "- a bullet the caller never asked for\n"
        )
        assert extract(text) == "the real answer"

    def test_restated_template_before_the_real_answer(self):
        """A model that demonstrates the format, then answers, must not have its
        example dragged into the payload."""
        text = (
            "The format is:\n"
            "<output>\n"
            "your answer here\n"
            "</output>\n"
            "\n"
            "Here is the actual answer:\n"
            "\n"
            "<output>\n"
            "the real answer\n"
            "</output>\n"
        )
        assert extract(text) == "the real answer"


class TestTagsMustBalance:
    """Opens and closes must balance in BOTH directions.

    The unmatched-*open* case was a live silent-corruption bug: the depth walk stopped
    early and returned the innermost body, exit 0, no warning. It is reachable from
    contract-legal text — the contract only ever demanded matched *closing* tags — and
    it lands on cc-session-review, which feeds the model a CLAUDE.md documenting these
    very tags. The mirror case raised loudly the whole time; that asymmetry was the bug.
    """

    def test_quoted_lone_open_tag_raises_rather_than_truncating(self):
        text = (
            "<output>\n"
            "Begin your reply with a line reading\n"
            "\n"
            "<output>\n"
            "\n"
            "and then write your answer.\n"
            "</output>\n"
        )
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "unbalanced" in str(e.value)

    def test_the_fragment_it_used_to_return_is_not_returned(self):
        """Regression pin: the old behaviour returned only the tail."""
        text = "<output>\na\n<output>\nb\n<output>\nc\n</output>\n"
        with pytest.raises(MissingEnvelope):
            extract(text)

    def test_realistic_claude_md_review_shape(self):
        text = (
            "<output>\n"
            "## Suggested CLAUDE.md addition\n"
            "\n"
            "Callers must begin the reply with a line reading\n"
            "\n"
            "<output>\n"
            "\n"
            "and take everything after it verbatim.\n"
            "</output>\n"
        )
        with pytest.raises(MissingEnvelope):
            extract(text)

    def test_counts_are_reported(self):
        with pytest.raises(MissingEnvelope) as e:
            extract("<output>\na\n<output>\nb\n</output>\n")
        assert "2 opening" in str(e.value) and "1 closing" in str(e.value)

    def test_balanced_nesting_still_succeeds(self):
        """The balance check must not break the legitimate quoted-envelope case."""
        text = "<output>\nbefore\n<output>\ninner\n</output>\nafter\n</output>\n"
        assert extract(text) == "before\n<output>\ninner\n</output>\nafter"

    def test_postamble_with_a_bare_close_raises(self):
        """Accepted cost of the symmetric rule, and the likelier direction now that
        --safe-mode kills preamble but not postamble. Loud beats a wrong body."""
        text = (
            "<output>\n"
            "the real answer\n"
            "</output>\n"
            "\n"
            "Let me know if you want it different — and remember to end with\n"
            "</output>\n"
        )
        with pytest.raises(MissingEnvelope):
            extract(text)


class TestTruncationGuardIsNotBypassable:
    """A one-line envelope inside the body used to silently replace a truncated
    document, because the one-liner fallback ran before the unclosed-open check."""

    def test_oneliner_in_body_does_not_defeat_the_guard(self):
        text = (
            "<output>\n"
            "# CLAUDE.md suggestions\n"
            "\n"
            "Short replies may use the one-line form:\n"
            "\n"
            "<output>PONG</output>\n"
            "\n"
            "Longer replies use the multi-line form, and this answer was still going\n"
            "when the model hit the token limit so the closing tag never arriv"
        )
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "truncated" in str(e.value)
        assert "PONG" not in str(e.value)


class TestAnchoringIsPinned:
    """Each input here is returned WRONGLY if the corresponding anchor is removed.

    Added after a mutation run showed the suite stayed fully green with `_OPEN`
    completely unanchored, with either of its anchors dropped, with `_ONE_LINE`
    unanchored, and with the lone-CR normalisation removed. The pre-existing
    preamble test passes for a different reason (the depth walk), so it pinned nothing.
    """

    def test_open_tag_needs_its_leading_anchor(self):
        """The tag must be at the START of its line, not merely at the end of one.

        Dropping `^[ \\t]*` makes the mutant match the trailing `<output>` here, giving
        it a balanced 1/1 count and returning 'real answer' — a body chosen by the
        model's narration rather than by the envelope.
        """
        with pytest.raises(MissingEnvelope):
            extract("Sure, I'll wrap it in <output>\nreal answer\n</output>\n")

    def test_mid_line_open_tag_with_trailing_prose(self):
        with pytest.raises(MissingEnvelope):
            extract("Sure, I'll wrap it in <output> for you.\n\nreal answer\n</output>\n")

    def test_open_tag_needs_its_trailing_anchor(self):
        # Without the `$`, returns 'preamble text\nreal answer'
        with pytest.raises(MissingEnvelope):
            extract("<output>preamble text\nreal answer\n</output>\n")

    def test_one_line_form_needs_its_anchors(self):
        # Unanchored `_ONE_LINE` returns 'example'
        with pytest.raises(MissingEnvelope):
            extract("The one-line form is <output>example</output>, by the way.\n")

    def test_close_tag_needs_its_anchors(self):
        with pytest.raises(MissingEnvelope):
            extract("<output>\nreal answer\nand then </output> mid-sentence\n")

    def test_lone_cr_is_normalised(self):
        # Old-Mac line endings; without the lone-`\r` pass this raises instead.
        assert extract("<output>\rhello\r</output>\r") == "hello"

    def test_attribute_cannot_span_lines(self):
        """`\\s[^>]*?` let a single open tag swallow lines; `[ \\t][^>\\n]*?` doesn't.

        The two lines that used to vanish are body text and must survive.
        """
        text = (
            "<output>\n"
            "The opening tag may be written across lines like\n"
            "<output\n"
            "foo>\n"
            "real answer\n"
            "</output>\n"
        )
        body = extract(text)
        assert body.startswith("The opening tag may be written")
        assert body.endswith("real answer")

    def test_self_closing_is_not_also_an_open_tag(self):
        """`<output />` matches `_OPEN` unless a lookbehind excludes the `/`, which
        under the balance rule turns an empty envelope into a truncation error."""
        assert extract("<output />\n", allow_empty=True) == ""


class TestUnclosed:
    """Truncation at the token limit is the likeliest real failure: the reply is
    a valid opening tag and half a document. Returning the partial would write a
    silently truncated file, which is worse than failing."""

    def test_open_with_no_close_raises(self):
        text = "<output>\n# Day score\n\nThe morning went most"
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "truncated" in str(e.value)

    def test_partial_body_is_not_leaked_in_the_message(self):
        text = "<output>\nsecret partial body"
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "secret partial body" not in str(e.value)

    def test_close_with_no_open_raises(self):
        with pytest.raises(MissingEnvelope):
            extract("some prose\n</output>\n")


class TestCliExitCodes:
    """Every shell caller branches on these, so they are part of the contract."""

    def test_happy_path(self):
        r = run_cli("<output>\nhello\n</output>\n")
        assert r.returncode == 0
        assert r.stdout == "hello\n"

    def test_missing_envelope(self):
        r = run_cli("just some prose, no tags at all\n")
        assert r.returncode == EXIT_MISSING
        assert "no <output> envelope" in r.stderr
        assert r.stdout == ""

    def test_unclosed_envelope(self):
        r = run_cli("<output>\nhalf an ans")
        assert r.returncode == EXIT_MISSING
        assert r.stdout == ""

    def test_empty_envelope(self):
        r = run_cli("<output>\n\n</output>\n")
        assert r.returncode == EXIT_EMPTY
        assert r.stdout == ""

    def test_json_mode_rejects_non_json(self):
        r = run_cli("<output>\nnot json at all\n</output>\n", "--json")
        assert r.returncode == EXIT_BAD_JSON

    def test_json_mode_passes_json_through(self):
        r = run_cli('<output>\n{"a": 1}\n</output>\n', "--json")
        assert r.returncode == 0
        assert json.loads(r.stdout) == {"a": 1}

    def test_unknown_flag_is_rejected_not_ignored(self):
        """`-j` used to be dropped silently and return prose with exit 0, which a
        caller would then pipe into jq."""
        r = run_cli("<output>\nhello\n</output>\n", "-j")
        assert r.returncode == EXIT_USAGE
        assert r.stdout == ""
        assert "unknown argument" in r.stderr

    def test_departing_reader_does_not_produce_a_traceback(self):
        """`llm-output < big | head -1` printed a BrokenPipeError traceback and exited
        1 — none of the documented codes.

        The body has to be big enough to overflow the OS pipe buffer, or `print()`
        completes before `head` exits and BrokenPipeError never fires. At 25KB this
        test passed even with the handler removed; ~1MB is what actually triggers it.
        """
        big = "<output>\n" + ("line\n" * 200_000) + "</output>\n"
        # PIPESTATUS, not the pipeline's status. `subprocess.run("cli | head -1")`
        # reports *head's* exit code, so `== 0` held no matter what llm-output returned
        # — the assertion could not fail. Mutating the handler's `return 0` to a nonzero
        # code left the whole suite green.
        p = subprocess.run(
            f"{CLI} | head -1; exit ${{PIPESTATUS[0]}}",
            shell=True, executable="/bin/bash",
            input=big, capture_output=True, text=True,
        )
        assert p.returncode == 0, f"llm-output exited {p.returncode}"
        assert "Traceback" not in p.stderr
        assert "BrokenPipeError" not in p.stderr


class TestQuotedEnvelopeInsideBody:
    """Concrete, not hypothetical: claude-batch-worker interpolates arbitrary file
    contents, and cc-session-review feeds the model a CLAUDE.md that documents
    this very contract. Taking the *last* opening tag would cut the body at the
    quoted example."""

    def test_complete_nested_envelope_survives_whole(self):
        text = (
            "<output>\n"
            "Wrap answers like this:\n"
            "\n"
            "<output>\n"
            "your answer\n"
            "</output>\n"
            "\n"
            "That is the whole contract.\n"
            "</output>\n"
        )
        body = extract(text)
        assert body.startswith("Wrap answers like this:")
        assert body.endswith("That is the whole contract.")
        assert "<output>\nyour answer\n</output>" in body

    def test_unbalanced_quote_refuses_to_guess(self):
        """A bare `</output>` line with no opener makes the boundary ambiguous."""
        text = (
            "<output>\n"
            "the docs say to finish with\n"
            "</output>\n"
            "and that is all\n"
            "</output>\n"
        )
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "unbalanced" in str(e.value)

    def test_close_tag_mid_line_in_prose_is_not_a_tag(self):
        text = (
            "<output>\n"
            "The contract says to close with </output> on its own line.\n"
            "Still the same paragraph.\n"
            "</output>\n"
        )
        body = extract(text)
        assert body.endswith("Still the same paragraph.")
        assert "close with </output> on its own line" in body


class TestEmptyBody:
    """Decided deliberately: an empty body raises. sanctuary and claude-batch-worker
    both branch on emptiness already, and both treat it as failure — sanctuary
    falls back to its default template, the worker leaves $outfile absent. Handing
    back "" would make them do the right thing by accident; raising makes the
    reason visible."""

    def test_empty_raises(self):
        with pytest.raises(EmptyEnvelope):
            extract("<output>\n</output>\n")

    def test_whitespace_only_raises(self):
        with pytest.raises(EmptyEnvelope):
            extract("<output>\n   \n\t\n</output>\n")

    def test_allow_empty_opts_out(self):
        assert extract("<output>\n\n</output>\n", allow_empty=True) == ""


class TestJsonShape:
    def test_wrong_type_is_its_own_failure(self):
        text = '<output>\n{"chunks": []}\n</output>\n'
        with pytest.raises(LLMOutputError) as e:
            extract_json(text, expect=list)
        assert "wanted list" in str(e.value)
        assert "dict" in str(e.value)

    def test_right_type_passes(self):
        text = '<output>\n[["a.md"], ["b.md"]]\n</output>\n'
        assert extract_json(text, expect=list) == [["a.md"], ["b.md"]]

    def test_invalid_json_is_distinct_from_wrong_type(self):
        with pytest.raises(LLMOutputError) as e:
            extract_json("<output>\n[[unquoted]]\n</output>\n", expect=list)
        assert "not valid JSON" in str(e.value)


class TestSelfClosing:
    def test_self_closing_is_an_empty_body(self):
        with pytest.raises(EmptyEnvelope):
            extract("<output/>\n")

    def test_self_closing_allow_empty(self):
        assert extract("<output/>\n", allow_empty=True) == ""

    def test_self_closing_with_space(self):
        assert extract("<output />\n", allow_empty=True) == ""


class TestOrdinaryCases:
    def test_happy_path(self):
        assert extract("<output>\nhello world\n</output>\n") == "hello world"

    def test_one_line_form(self):
        assert extract("<output>PONG</output>\n") == "PONG"

    def test_interior_whitespace_is_preserved(self):
        text = "<output>\n# Title\n\n    indented block\n\nend\n</output>\n"
        assert extract(text) == "# Title\n\n    indented block\n\nend"

    def test_fence_around_the_whole_answer_falls_outside_the_envelope(self):
        """The contract forbids it, but if the model fences the whole reply the
        envelope still wins — the fence lines simply are not inside it, so no
        downstream fence-stripping is needed anywhere."""
        text = "```\n<output>\nthe answer\n</output>\n```\n"
        assert extract(text) == "the answer"

    def test_fenced_code_inside_the_answer_is_kept(self):
        text = "<output>\nRun this:\n\n```sh\nls -la\n```\n</output>\n"
        body = extract(text)
        assert "```sh" in body and body.count("```") == 2

    def test_crlf(self):
        assert extract("<output>\r\nhello\r\n</output>\r\n") == "hello"

    def test_attributes_on_the_open_tag(self):
        assert extract('<output format="markdown">\nhello\n</output>\n') == "hello"

    def test_indented_tags(self):
        assert extract("  <output>\n  hello\n  </output>\n") == "  hello"

    def test_real_captured_roleplay_bookends(self):
        """Verbatim from a leaking run on 2026-07-29 (haiku, no --safe-mode)."""
        text = (
            "> 🎭 **Sister of Battle** 🔥 `WARHAMMER 40K` — "
            '*"Purge the false message, and arm the function with righteous return."*\n'
            "\n"
            "<output>\n"
            'The print message was changed from `"hi"` to `"hello"`.\n'
            "</output>\n"
            "\n"
            "> 🫡 The heresy is corrected. Awaiting the next purge.\n"
        )
        body = extract(text)
        assert body == 'The print message was changed from `"hi"` to `"hello"`.'
        assert "🎭" not in body and "🫡" not in body

    def test_bookends_without_an_envelope_still_raise(self):
        """The negative test: safe-mode kills these, but if one ever arrives at a
        strict callsite it must fail loudly rather than become the payload."""
        text = (
            "> 🎭 **Commissar** 💀 `WARHAMMER 40K` — *\"Report, soldier.\"*\n"
            "\n"
            "The diff renames the greeting and adds a return value.\n"
            "\n"
            "> 🫡 Dismissed.\n"
        )
        with pytest.raises(MissingEnvelope):
            extract(text)

    def test_none_and_empty_input(self):
        with pytest.raises(MissingEnvelope):
            extract("")
        with pytest.raises(MissingEnvelope):
            extract(None)  # type: ignore[arg-type]


class TestContractFlag:
    """`--contract` had no test at all: deleting the branch outright left the suite
    green, and so did printing the contract to STDERR — which alone would have silently
    emptied the contract out of every fish caller's prompt while everything stayed
    passing. Three callers now do `set -l contract (llm-output --contract | ...)`.
    """

    def test_prints_the_contract_to_stdout(self):
        r = subprocess.run([str(CLI), "--contract"], capture_output=True, text=True)
        assert r.returncode == 0
        assert "OUTPUT CONTRACT" in r.stdout
        assert r.stdout.rstrip("\n") == contract()
        assert r.stderr == ""

    def test_does_not_read_stdin(self):
        """The fish callers invoke it with no redirect; reading stdin would hang."""
        r = subprocess.run(
            [str(CLI), "--contract"], stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=30,
        )
        assert r.returncode == 0 and "OUTPUT CONTRACT" in r.stdout

    def test_mutually_exclusive_with_json(self):
        r = subprocess.run(
            [str(CLI), "--contract", "--json"], capture_output=True, text=True
        )
        assert r.returncode == EXIT_USAGE
        assert "mutually exclusive" in r.stderr
        assert r.stdout == ""

    def test_unreadable_contract_exits_no_contract(self, tmp_path, monkeypatch):
        import llm_output

        monkeypatch.setattr(llm_output, "CONTRACT_PATH", tmp_path / "gone.md")
        assert llm_output.main(["--contract"]) == EXIT_NO_CONTRACT

    def test_contract_output_round_trips_through_the_extractor(self):
        """The contract's own worked example is a balanced pair, so piping the contract
        back through llm-output must extract rather than blow up on its own text."""
        r = subprocess.run(
            [str(CLI)], input=contract(), capture_output=True, text=True
        )
        assert r.returncode == 0


class TestRemainingBehaviourPins:
    """Each of these was a surviving mutant — behaviour the code chose deliberately but
    nothing asserted."""

    def test_extra_closes_direction_of_the_balance_check(self):
        """`!=` narrowed to `>` left the suite green, and is NOT redundant with the
        depth walk: on 2 opens / 3 closes the walk still reaches depth 0 and returns a
        wrong body."""
        text = "</output>\n<output>\nA\n<output>\nB\n</output>\n</output>\n"
        with pytest.raises(MissingEnvelope) as e:
            extract(text)
        assert "2 opening" in str(e.value) and "3 closing" in str(e.value)

    def test_attribute_cannot_span_lines_after_a_space(self):
        """Pins the `[^>\\n]` half of _ATTRS. The other span test puts the newline
        immediately after `<output`, where the `[ \\t]` requirement blocks it whatever
        the character class does — so `[^>]` survived as a mutation."""
        text = "<output>\ntag written like\n<output foo\nbar>\nreal answer\n</output>\n"
        body = extract(text)
        assert body.startswith("tag written like")
        assert body.endswith("real answer")

    def test_crlf_inside_the_body_not_only_at_the_edges(self):
        """Dropping the `\\r\\n` pass left the suite green: the existing CRLF test only
        has CRLF adjacent to the tags, where strip("\\n") hides the damage. Interior
        lines each gain a blank line without it."""
        text = "<output>\r\n# Title\r\n\r\nline1\r\nline2\r\n</output>\r\n"
        assert extract(text) == "# Title\n\nline1\nline2"

    def test_near_miss_flag_is_rejected(self):
        """`--jsonx` must not be accepted as `--json`; a prefix check reintroduces the
        silently-ignored-flag bug for a typo."""
        r = run_cli("<output>\nhello\n</output>\n", "--jsonx")
        assert r.returncode == EXIT_USAGE

    def test_last_one_liner_wins(self):
        """Matches the last-wins convention of the multi-line path; `[0]` survived."""
        assert extract("<output>a</output>\n<output>b</output>\n") == "b"

    def test_close_tag_width_rejects_attributes(self):
        """_CLOSE's anchoring is tested; its width was not. A widened _CLOSE would treat
        a quoted `</output foo>` in the body as the real close."""
        text = "<output>\nreal answer\n</output foo>\n</output>\n"
        assert extract(text) == "real answer\n</output foo>"

    def test_stray_close_gets_its_own_message(self):
        """The `if not opens:` branch was deletable without failing anything."""
        with pytest.raises(MissingEnvelope) as e:
            extract("some prose\n</output>\n")
        assert "no opening" in str(e.value)


class TestKnownLimitations:
    """Documented, deliberately not fixed. Pinned so a future change has to be a choice.

    A stray line-anchored `<output>` in the preamble and a stray `</output>` in the
    postamble CANCEL OUT in the balance count, and the depth walk then latches onto the
    preamble's stray open. The chosen body is a locally well-formed nested envelope, so
    no local rule separates "outer envelope quoting an inner one" from "narration, real
    envelope, narration" — the two are structurally identical. Rejecting text outside
    the outermost envelope would fix it and break every legitimate preamble case; a
    prefer-the-inner heuristic would break the answer-IS-a-quoted-envelope case below.
    """

    def test_cancelling_stray_tags_yield_a_wrong_body(self):
        text = (
            "Start with\n<output>\n\n"
            "<output>\nthe real answer\n</output>\n\n"
            "then end with\n</output>\n"
        )
        body = extract(text)
        assert body != "the real answer"  # the limitation, stated plainly
        assert "the real answer" in body  # nothing is lost, it is over-captured

    def test_the_mirror_order_is_handled_correctly(self):
        text = (
            "Remember to finish with\n</output>\n\n"
            "<output>\nthe real answer\n</output>\n\n"
            "And you can start again with\n<output>\n"
        )
        assert extract(text) == "the real answer"

    def test_answer_that_is_itself_a_quoted_envelope_still_works(self):
        """The case a prefer-the-inner fix would break."""
        assert extract("<output>\n<output>\nreal\n</output>\n</output>\n") == (
            "<output>\nreal\n</output>"
        )

    def test_indenting_a_lone_tag_does_not_escape_it(self):
        """Both regexes begin `^[ \\t]*`, so indentation is not an escape. The contract
        tells the model to keep a lone tag inline in a sentence instead."""
        with pytest.raises(MissingEnvelope):
            extract("<output>\nSee:\n\n    <output>\n\ndone.\n</output>\n")

    def test_inline_tag_reference_is_the_working_escape(self):
        text = "<output>\nBegin with `<output>` and end with `</output>`.\n</output>\n"
        assert extract(text) == "Begin with `<output>` and end with `</output>`."


class TestContractText:
    def test_contract_is_readable_and_names_the_tags(self):
        text = contract()
        assert "<output>" in text and "</output>" in text

    def test_contract_forbids_a_whole_answer_fence(self):
        """Fence handling belongs in the contract, not in downstream sniffing."""
        assert "code fence" in contract()

    def test_contract_states_the_balance_rule_the_extractor_enforces(self):
        """extract() rejects a lone opening tag, so the contract has to say so —
        otherwise the model is told one thing and judged by another.

        Whitespace-normalised: the contract is prose and gets rewrapped, so matching
        raw text would make this fail on a reflow rather than on a missing rule.
        """
        flat = " ".join(contract().split())
        assert "balanced in both directions" in flat

    def test_contract_forbids_anything_after_the_closing_tag(self):
        flat = " ".join(contract().split())
        assert "Nothing may follow the closing" in flat

    def test_contract_path_is_derived_from_the_module_not_from_home(self, tmp_path):
        """A worktree or copied tree must prompt with the contract beside it.

        Loaded from a COPY under tmp_path, because in the real tree
        `parents[3]`-of-the-test and `~/dotfiles` are the same directory — so comparing
        them passes even with the `Path.home()` regression reinstated, which is exactly
        the case this protects. Only a relocated copy can tell the two apart.
        """
        import importlib.util

        import llm_output

        lib = tmp_path / "lib" / "python"
        lib.mkdir(parents=True)
        (tmp_path / "ai" / "templates").mkdir(parents=True)
        marker = "CONTRACT FROM THE COPY, not from ~/dotfiles\n"
        (tmp_path / "ai" / "templates" / "output_contract.md").write_text(marker)
        # Source located via the module's own __file__, NOT via CONTRACT_PATH — that
        # would be circular, and it is: with the `Path.home()` regression reinstated,
        # `CONTRACT_PATH.parents[2]` is ~/dotfiles, so the test copied the real
        # unmutated module and passed. That let the mutation survive.
        shutil.copy2(llm_output.__file__, lib / "llm_output.py")

        spec = importlib.util.spec_from_file_location("_copied", lib / "llm_output.py")
        copied = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(copied)

        assert copied.CONTRACT_PATH == tmp_path / "ai" / "templates" / "output_contract.md"
        assert copied.contract() == marker.rstrip("\n")

    def test_missing_contract_raises_an_llm_output_error(self, tmp_path, monkeypatch):
        """Callers build prompts inside `except LLMOutputError`; a bare OSError leaking
        past them turns a missing template into an unrelated crash."""
        import llm_output

        monkeypatch.setattr(llm_output, "CONTRACT_PATH", tmp_path / "nope.md")
        with pytest.raises(LLMOutputError):
            llm_output.contract()
