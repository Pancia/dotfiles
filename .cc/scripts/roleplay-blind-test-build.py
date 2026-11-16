#!/usr/bin/env python3
"""Build a blind rating page from harvest.jsonl (see roleplay-bookend-harvest.py).

Early = context under EARLY tokens, late = over LATE tokens. One item per session
per bucket, N per bucket, shuffled. The page shows no context size; the key
(item id -> bucket, ctx, session) goes to key.json beside it.
Also prints a self-repetition metric per bucket: the share of a line's word
trigrams already used by earlier bookends in the same session.
Usage: roleplay-blind-test-build.py DIR [N] [EARLY] [LATE] [EXCLUDE_SESSION]
"""
import json, random, re, sys, html, collections
d = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 20
EARLY = int(sys.argv[3]) if len(sys.argv) > 3 else 100_000
LATE = int(sys.argv[4]) if len(sys.argv) > 4 else 400_000
EXCL = sys.argv[5] if len(sys.argv) > 5 else ""
recs = [json.loads(l) for l in open(f"{d}/harvest.jsonl")]
recs = [r for r in recs if r["model"] == "claude-opus-5-5" and r["session"] != EXCL]

def clean(s):
    s = (s or "").replace("*", "").strip()
    if s.count('"') == 2 and s.startswith('"') and s.endswith('"'):
        s = s[1:-1]
    return s

def tri(s):
    w = re.findall(r"[a-z']+", clean(s).lower())
    return {tuple(w[i:i+3]) for i in range(len(w) - 2)}

# self-repetition, over all records (not just the sample)
by_sess = collections.defaultdict(list)
for r in recs:
    by_sess[r["session"]].append(r)
rep = {"early": [], "mid": [], "late": []}
for rs in by_sess.values():
    rs.sort(key=lambda r: r["ts"] or "")
    seen = set()
    for r in rs:
        t = tri(r["opener"]) | tri(r["closer"])
        if t and seen:
            b = "early" if r["ctx_tokens"] < EARLY else "late" if r["ctx_tokens"] > LATE else "mid"
            rep[b].append(len(t & seen) / len(t))
        seen |= t
for b, v in rep.items():
    if v:
        print(f"repetition {b:5}: n={len(v):4}  mean={sum(v)/len(v):.3f}  any-reuse={sum(x>0 for x in v)/len(v):.2f}")
lens = collections.defaultdict(list)
for r in recs:
    b = "early" if r["ctx_tokens"] < EARLY else "late" if r["ctx_tokens"] > LATE else "mid"
    lens[b].append(len(clean(r["opener"]).split()) + len(clean(r["closer"]).split()))
for b, v in lens.items():
    print(f"words/pair {b:5}: n={len(v):4}  mean={sum(v)/len(v):.1f}")

rng = random.Random(20261115)
def pick(pred):
    pool = [r for r in recs if pred(r) and r["closer"]]
    rng.shuffle(pool)
    out, used = [], set()
    for r in pool:
        if r["session"] in used:
            continue
        used.add(r["session"]); out.append(r)
        if len(out) == N:
            break
    return out
early = pick(lambda r: r["ctx_tokens"] < EARLY)
late = pick(lambda r: r["ctx_tokens"] > LATE)
items = [("early", r) for r in early] + [("late", r) for r in late]
rng.shuffle(items)
key = {}
rows = []
for i, (b, r) in enumerate(items, 1):
    key[i] = {"bucket": b, "ctx_tokens": r["ctx_tokens"], "session": r["session"], "ts": r["ts"], "character": r["character"]}
    rows.append(f'''<div class="item" data-id="{i}">
  <div class="label">Item {i:02d} · {html.escape(r["character"])}</div>
  <div class="indent">
    <p class="line"><span class="num">Open</span> {html.escape(clean(r["opener"]))}</p>
    <p class="line"><span class="num">Close</span> {html.escape(clean(r["closer"]))}</p>
    <div class="score">{"".join(f'<button class="secondary" data-v="{v}">{v}</button>' for v in range(1, 6))}</div>
  </div>
</div>''')
json.dump(key, open(f"{d}/key.json", "w"), indent=1)
print(f"sampled early={len(early)} late={len(late)}")
page = open(__file__.replace("-build.py", "-page.html")).read()
open(f"{d}/rate.html", "w").write(page.replace("<!--ITEMS-->", "\n".join(rows)).replace("__TOTAL__", str(len(items))))
