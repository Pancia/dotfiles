# Build a system prompt

Create or refine a system prompt using the builder principles below.

## Role (builder prompt)

@~/dotfiles/ai/prompts/system-prompt-builder.txt

## User's directions

$ARGUMENTS

## Procedure

Adopt the builder prompt above as your role. The directions tell you what to build; the raw material — if any — lives in one of these places:

- A file path or URL mentioned in the directions (read it)
- An existing prompt elsewhere in this conversation (use it)
- Nothing — build from scratch based on the description

If the directions are empty or too vague to act on, ask the user what they want built and stop.

Output the resulting prompt inside a fenced markdown code block, with no preamble or explanation — just the prompt, ready to copy. Do not write the result to disk; the user will review and place it themselves.
