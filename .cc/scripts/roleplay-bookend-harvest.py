#!/usr/bin/env python3
"""Harvest roleplay bookends from Claude Code transcripts, with context size.

Writes one JSON object per final message that has an opener and/or closer:
  session, ts, ctx_tokens (input + cache read + cache create of that message),
  turn (assistant-text index in session), opener, closer, character.
Usage: roleplay-bookend-harvest.py DAYS OUT.jsonl
"""
import json, os, re, sys, time, glob

days, out = float(sys.argv[1]), sys.argv[2]
root = os.path.expanduser("~/.claude/projects")
cutoff = time.time() - days * 86400
LINE = re.compile(r'^>\s*🎭 \*\*«([^»]+)»\*\*.*?[—-]\s*(.+)$', re.M)
n = 0
with open(out, "w") as fo:
    for f in glob.glob(f"{root}/*/*.jsonl"):
        if os.path.getmtime(f) < cutoff:
            continue
        turn = 0
        try:
            fh = open(f, errors="replace")
        except OSError:
            continue
        for raw in fh:
            if '🎭' not in raw or '"assistant"' not in raw:
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get("type") != "assistant" or d.get("isSidechain"):
                continue
            msg = d.get("message") or {}
            text = "".join(c.get("text", "") for c in msg.get("content", []) if c.get("type") == "text")
            hits = LINE.findall(text)
            if not hits:
                continue
            turn += 1
            u = msg.get("usage") or {}
            ctx = sum(u.get(k, 0) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
            rec = {"session": os.path.basename(f)[:-6], "project": os.path.basename(os.path.dirname(f)),
                   "ts": d.get("timestamp"), "ctx_tokens": ctx, "turn": turn, "model": msg.get("model"),
                   "character": hits[0][0], "opener": hits[0][1].strip(),
                   "closer": hits[-1][1].strip() if len(hits) > 1 else None}
            fo.write(json.dumps(rec, ensure_ascii=False) + "\n")
            n += 1
print(n, "bookend messages")
