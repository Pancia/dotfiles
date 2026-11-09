---
description: Suggest improvements based on what this session actually experienced
argument-hint: "[optional focus, e.g. 'the test tooling' or 'our instructions']"
---

# Session Retrospective

Suggest improvements to the things this session actually used, based on what
actually happened in it. Your value here is first-hand experience that nobody
else has: what was confusing, what failed, and what took more steps than it
should have. A suggestion that any reviewer could make without this session
does not belong in the answer.

## Focus

$ARGUMENTS

If the block above is non-empty, limit the retrospective to that focus. Otherwise
cover the whole session.

## What to look for

Go back through this conversation for moments of friction:

- an error message that was wrong, vague, or did not say what to do next
- a command, flag, or tool that behaved differently from its documentation
- instructions that were missing, out of date, or that contradicted each other
- a workaround, a retry, or a route you were sent down that was a dead end
- work you had to do by hand or repeat that a tool could have done
- a guard that blocked correct work, or a guard that should have blocked and did not
- a correction from the user, and what would have made it unnecessary
- facts you had to rediscover that should have been written down

Anything the session touched is in scope: the project's code, its tests, its
tooling, its documentation, agent instructions such as CLAUDE.md, hooks, skills,
commands, and the assistant's own behaviour.

## Rules

1. **Evidence first.** Each suggestion must name the specific thing that happened
   in this session. If you cannot point to a moment, drop the suggestion.
2. **Check the cause.** Where the relevant code, config, or docs are available,
   read them before claiming why something happened. Mark each suggestion as
   *verified* (you confirmed the cause) or *inferred* (you saw only the symptom).
3. **Be honest about your own mistakes.** If you caused the friction, say so. Do
   not suggest changing a tool to cover a slip of yours, unless better instructions
   or a clearer message would realistically have prevented it. A new rule counts
   only if it names the situation and the action, so that it would have changed
   what you did. "Find the cause first" and "be more careful" do not count.
4. **Propose a concrete fix.** Say what to change and where. Name what the fix
   could break or what it costs. Prefer the smallest change that removes the problem.
5. **Respect past decisions.** If a comment or document explains why something is
   the way it is, take that reasoning into account, and say why it still does or
   does not hold.
6. **Read-only until approved.** Do not change anything. Do not spawn subagents to
   produce the suggestions, because they do not have this session's experience.
7. **State the limits.** If part of this conversation was compacted or summarized,
   say that the evidence for that part may be incomplete.
8. **Improvements only.** A suggestion must make later sessions go better, or fix a
   defect left in the project. Routine unfinished work, such as an uncommitted
   change, is not a suggestion. Neither is a past misstatement: if it could still
   mislead the user, correct it in one line outside the lists.

## Output

Follow any reporting rules in the user's instructions; they take precedence over
this format.

There is no fixed number of main suggestions. A main suggestion must pass this
bar: fixing it would have saved real time, prevented a wrong result, or removed a
trap likely to catch the next session. List these most valuable first. For each
one, give the problem, what happened, the fix, its cost or risk, and whether it
is verified or inferred. Give the cost and the label on every suggestion. One
blanket statement for the whole list does not count.

After them, you may add a **Minor** list of at most five small or style points
that fall below the bar. Number the main suggestions and the Minor items in one
sequence, so that the user can approve any item by number. Give each Minor item a
single line, and name the change to make.
Each must still come from something you noticed in this session, and be something
you would actually fix. Leave out one-off oddities. The list is optional: omit it
rather than fill it.

If the session was smooth, say so plainly and suggest nothing.

End by asking which suggestions to take forward.

## After the user approves

Wait for the user to say which suggestions to take forward. Then:

1. Spawn one critique subagent for the approved suggestions, unless the user says
   to skip it. It has none of this session's context, so brief it with what
   happened, your diagnosis, the proposed fix, and the files to read. Tell it to
   try to refute each suggestion: is the diagnosis true, would the fix work, what
   would it break, is there a smaller fix, and is there a worse defect in the same
   code? It must not change the project, and any behaviour tests go in a throwaway
   copy.
2. Report each verdict as confirmed, changed, or rejected. Say plainly where your
   idea was wrong, and give the revised fix.
3. Ask which revised fixes to implement. Always implement them in a subagent, not
   in this conversation. Continue the critique subagent if you can, because it
   already knows the code. Otherwise brief a new one with the revised fixes, the
   review findings, the files, and the tests to run. It implements only the
   approved fixes. Report what it changed and the real test result.
4. Keep these changes in their own commit, separate from the session's main work.
