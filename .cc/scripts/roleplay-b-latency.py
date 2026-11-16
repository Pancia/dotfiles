#!/usr/bin/env python3
"""Plan B experiment: a separate model writes the opener and closer after a reply.

For each blind-test item, rebuild what a Stop hook would see -- the user's prompt
and the final reply with its bookends removed -- and ask MODEL for both lines via
claude-p with a JSON schema. Records wall time, tokens and cost per call.
Nothing is hooked or shown live; this only reads old transcripts.
Usage: roleplay-b-latency.py DIR MODEL [LIMIT] [JOBS]  -> DIR/b-<model>.jsonl
"""
import json, os, re, subprocess, sys, time, glob, random
from concurrent.futures import ThreadPoolExecutor
d, model = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 999
jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 3
key = json.load(open(f"{d}/key.json"))
harvest = {(r["session"], r["ts"]): r for r in map(json.loads, open(f"{d}/harvest.jsonl"))}
roster = {}
for line in open(os.path.expanduser("~/dotfiles/roleplay/roster.tsv")):
    if line.lstrip().startswith(("#", "@")):
        continue
    f = [x.strip() for x in line.split("|")]
    if len(f) >= 4:
        roster[f[1]] = {"universe": f[0], "emoji": f[2], "traits": f[3]}
examples = open(os.path.expanduser("~/dotfiles/roleplay/examples.md")).read()

def samples(name, n=2):
    m = re.search(r"^### .*?" + re.escape(name) + r" · .*?\n(.*?)(?=^---|\Z)", examples, re.M | re.S)
    if not m:
        return []
    lines = re.findall(r'— \*"(.*?)"\*', m.group(1))
    random.Random(name).shuffle(lines)
    return lines[:n]

BOOK = re.compile(r"^>\s*🎭.*$\n?", re.M)
def context(item):
    h = harvest[(item["session"], item["ts"])]
    f = os.path.expanduser(f"~/.claude/projects/{h['project']}/{item['session']}.jsonl")
    prompt, reply = None, None
    for raw in open(f, errors="replace"):
        r = json.loads(raw)
        if r.get("isSidechain"):
            continue
        if r.get("type") == "user":
            c = r["message"].get("content")
            if isinstance(c, str) and not c.startswith("<"):
                prompt = c
            elif isinstance(c, list):
                t = [x.get("text", "") for x in c if x.get("type") == "text" and not x.get("text", "").startswith("<")]
                if t:
                    prompt = "\n".join(t)
        if r.get("type") == "assistant" and r.get("timestamp") == item["ts"]:
            reply = "".join(x.get("text", "") for x in r["message"]["content"] if x.get("type") == "text")
            break
    return prompt, BOOK.sub("", reply or "").strip()

SCHEMA = json.dumps({"type": "object", "properties": {"opener": {"type": "string"}, "closer": {"type": "string"}},
                     "required": ["opener", "closer"], "additionalProperties": False})
SYS = ("You write two short in-character lines that bookend an assistant's reply to a user. "
       "The opener sits at the top of the reply and reacts to what it reports. The closer sits at the bottom: "
       "a closing line, a salute, a brief scene beat, or a quip about how the task went. "
       "Each is at most 20 words, in the character's own voice, about this specific work. "
       "A plain status sentence with no character in it is a failure. Do not use technical jargon from the "
       "character's universe to describe the technical work. Return only the two lines, without quotes.")

def run(i):
    item = key[str(i)]
    name = item["character"]
    ch = roster.get(name, {"universe": "?", "traits": ""})
    prompt, reply = context(item)
    ex = samples(name)
    user = (f"Character: {name} ({ch['universe']}) — {ch['traits']}\n"
            + (f"Example lines in this voice (style only, do not copy):\n" + "\n".join(f"- {e}" for e in ex) + "\n" if ex else "")
            + f"\nThe user asked:\n{(prompt or '')[-3000:]}\n\nThe reply:\n{reply[-8000:]}\n")
    t0 = time.time()
    effort = os.environ.get("EFFORT")
    p = subprocess.run(["claude-p", "--model", model, *(["--effort", effort] if effort else []), "--output-format", "json", "--system-prompt", SYS,
                        "--tools=", f"--json-schema={SCHEMA}"], input=user, capture_output=True, text=True,
                       env={**os.environ, "CLAUDE_P_TIMEOUT": "90"})
    dt = time.time() - t0
    out = {"id": i, "model": model, "effort": os.environ.get("EFFORT"), "wall_s": round(dt, 2), "rc": p.returncode, "input_chars": len(user)}
    try:
        e = json.loads(p.stdout)
        u = e.get("usage", {})
        out.update(api_ms=e.get("duration_api_ms"), cost=e.get("total_cost_usd"),
                   in_tok=u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0),
                   out_tok=u.get("output_tokens"), **(e.get("structured_output") or {}))
    except ValueError:
        out["err"] = (p.stderr or p.stdout)[-300:]
    print(json.dumps(out, ensure_ascii=False), flush=True)
    return out

ids = sorted(map(int, key))[:limit]
with ThreadPoolExecutor(jobs) as ex, open(f"{d}/b-{model}{os.environ.get('TAG','')}{os.environ.get('EFFORT') and '-' + os.environ['EFFORT'] or ''}.jsonl", "w") as fo:
    for o in ex.map(run, ids):
        fo.write(json.dumps(o, ensure_ascii=False) + "\n")
