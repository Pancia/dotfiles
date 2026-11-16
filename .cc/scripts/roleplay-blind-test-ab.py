#!/usr/bin/env python3
"""Second blind page: real bookends vs Haiku vs Sonnet for the same turns.
Usage: roleplay-blind-test-ab.py DIR  -> DIR/rate-ab.html, DIR/key-ab.json"""
import json, re, random, html, sys
d = sys.argv[1]
page = open(f"{d}/rate.html").read()
key = json.load(open(f"{d}/key.json"))
def orig(i):
    m = re.search(r'data-id="%d">.*?Open</span> (.*?)</p>.*?Close</span> (.*?)</p>' % i, page, re.S)
    return html.unescape(m.group(1)), html.unescape(m.group(2))
gen = {m: {r["id"]: r for r in map(json.loads, open(f"{d}/b-{m}.jsonl"))} for m in ("haiku", "sonnet")}
items = []
for i in sorted(gen["sonnet"]):
    items.append(("original", i, *orig(i)))
    for m in ("haiku", "sonnet"):
        r = gen[m][i]; items.append((m, i, r["opener"], r["closer"]))
rng = random.Random(7); rng.shuffle(items)
tmpl = open(__file__.replace("-ab.py", "-page.html")).read()
rows, k = [], {}
for n, (src, i, o, c) in enumerate(items, 1):
    k[n] = {"source": src, "turn_item": i}
    rows.append(f'''<div class="item" data-id="{n}">
  <div class="label">Item {n:02d} · {html.escape(key[str(i)]["character"])}</div>
  <div class="indent">
    <p class="line"><span class="num">Open</span> {html.escape(o)}</p>
    <p class="line"><span class="num">Close</span> {html.escape(c)}</p>
    <div class="score">{"".join(f'<button class="secondary" data-v="{v}">{v}</button>' for v in range(1, 6))}</div>
  </div>
</div>''')
json.dump(k, open(f"{d}/key-ab.json", "w"), indent=1)
out = (tmpl.replace("<!--ITEMS-->", "\n".join(rows)).replace("__TOTAL__", str(len(items)))
       .replace("bookend-blind-2026-11-15", "bookend-blind-ab-2026-11-15")
       .replace("<title>Bookend blind test</title>", "<title>Bookend blind test 2</title>")
       .replace("<h1>Bookend blind test</h1>", "<h1>Bookend blind test 2</h1>")
       .replace("Context size is hidden.", "The same turn appears three times, written three ways. Which way is hidden."))
open(f"{d}/rate-ab.html", "w").write(out)
print(len(items), "items")
