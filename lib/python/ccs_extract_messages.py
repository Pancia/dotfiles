"""Print a session transcript's text messages, trimmed for a title prompt.

Called by `_ccs_extract_messages` in fish/functions/ccs.fish as
`python3 ccs_extract_messages.py <session.jsonl>`. It was a fish single-quoted
`python3 -c` string, where one apostrophe in a comment ended the string.
"""
import json, sys
msgs = []
with open(sys.argv[1]) as f:
    for line in f:
        try:
            rec = json.loads(line)
        except:
            continue
        msg = rec.get("message", {})
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        content = msg.get("content", "")
        texts = []
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block["text"])
        for t in texts:
            # skip huge content (diffs, system prompts, etc)
            if len(t) > 1000:
                t = t[:500] + "..."
            if t.strip():
                prefix = "Human" if role == "user" else "Assistant"
                msgs.append(f"{prefix}: {t}")
# Keep it reasonable for haiku - first and last few messages
if len(msgs) > 12:
    msgs = msgs[:6] + ["..."] + msgs[-4:]
print("\n".join(msgs))
