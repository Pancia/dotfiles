#!/usr/bin/env python3
"""A/B the roleplay-bookends closer prompt on real recent turns.

Rebuilds the closer `ask` the mod sends (ai/mods/roleplay-bookends/hooks/
register.tsx, startCloser) from the transcript, then runs it through Sonnet
with the old SYS and with a candidate SYS. Prints both sets of lines.

Usage: python3 .cc/scripts/bookend-prompt-ab.py [samples-per-variant]
"""
import glob, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

HOME = os.path.expanduser('~')
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2

# (closer time from mod-lines.jsonl, session id, character name)
CASES = [
    ('2026-11-21T01:25:47.557Z', 'f4f6a9f8-6fe9-404c-ae1c-f65381d3c4be', 'Nia Teppelin'),
    ('2026-11-17T19:34:51.711Z', '64b6df4a-8a01-4613-a0ff-f08036029020', 'Julia Sugarbaker (Designing Women)'),
    ('2026-11-20T20:10:41.805Z', '9cfbe7b8-2f00-4f4c-a0e6-370e85a4e6ec', 'Sadie Adler (Red Dead Redemption 2)'),
    ('2026-11-20T22:10:07.659Z', '0cd080ae-e39d-4624-b010-6aad711a0c85', 'Techpriest Logis'),
    ('2026-11-20T23:34:01.006Z', 'c71fba05-1fd3-47e7-a312-9e1660534f7b', 'Batou'),
]

src = open(f'{HOME}/dotfiles/ai/mods/roleplay-bookends/hooks/register.tsx').read()
m = re.search(r'export const SYS =\n(.*?)\n\n', src, re.S)
OLD = ''.join(a or b for a, b in re.findall(r"""'([^']*)'|"([^"]*)\"""", m.group(1)))
OLD_PART = "At most 25 words, in the character's own voice, about this specific work. "
assert OLD_PART in OLD, OLD
NEW = OLD.replace(OLD_PART,
    "At most 25 words, in the character's own voice. "
    'Start from this moment, but keep its technical detail out: no file names, commands, tools, counts or code terms. '
    'If the line names the work, use everyday words, like "the backup". '
    'Say what the moment means, as a feeling or a small truth the character sees in it. ')

roster = {}
out = subprocess.run([f'{HOME}/dotfiles/roleplay/bin/roleplay-roll', '--roster'], capture_output=True, text=True).stdout
for row in out.splitlines():
    f = row.split('\t')
    if len(f) == 7:
        roster[f[1]] = f

examples = open(f'{HOME}/dotfiles/roleplay/examples.md').read()


def samples(name):
    i = examples.find(f' {name} · ')
    end = examples.find('\n---', i)
    return re.findall(r'— \*"(.*?)"\*', examples[i:end if end > 0 else None])[:2]


def text_of(msg):
    c = msg.get('content')
    if isinstance(c, str):
        return c
    return '\n'.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')


def turn(session, at):
    path = glob.glob(f'{HOME}/.claude/projects/*/{session}.jsonl')[0]
    cut = datetime.fromisoformat(at.replace('Z', '+00:00'))
    prompt, reply = '', []
    for line in open(path):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ts = e.get('timestamp')
        if not ts or datetime.fromisoformat(ts.replace('Z', '+00:00')) > cut:
            continue
        msg = e.get('message') or {}
        if e.get('type') == 'user' and isinstance(msg.get('content'), str) and not e.get('isMeta'):
            if msg['content'].startswith('<'):
                continue
            prompt, reply = msg['content'], []
        elif e.get('type') == 'assistant':
            t = text_of(msg).strip()
            if t:
                reply.append(t)
    return prompt, (reply[-1] if reply else '')


def ask_for(name, prompt, reply):
    f = roster[name]
    extra = f'\nNote: Signature line spent this time: do not use {f[4]}; use a less-worn part of the character.' if f[4] else ''
    ex = samples(name)
    exb = f'Example lines in this voice (style only, do not copy):\n' + '\n'.join(f'- {x}' for x in ex) + '\n' if ex else ''
    answer = re.sub(r'^>\s*🎭.*$\n?', '', reply, flags=re.M).strip()
    return (f'Character: {name} ({f[0]}) — {f[3]}{extra}\n' + exb +
            f'\nThe user asked:\n{prompt[-2000:]}\n\nThe assistant\'s reply:\n{answer[-6000:]}\n\n'
            'Write the CLOSER: the line at the bottom of the reply. A closing line, a salute, a brief scene beat, '
            'or a quip about how the task went.')


def run(system, ask):
    r = subprocess.run([f'{HOME}/dotfiles/bin/claude-p', '--model', 'sonnet', '--tools=', '--output-format', 'json',
                        '--system-prompt', system], input=ask, capture_output=True, text=True)
    try:
        j = json.loads(r.stdout)
        return '(error)' if j.get('is_error') else j.get('result', '').strip()
    except ValueError:
        return f'(failed: {r.stderr.strip()[:100]})'


jobs = []
for at, sid, name in CASES:
    prompt, reply = turn(sid, at)
    a = ask_for(name, prompt, reply)
    for label, system in (('old', OLD), ('new', NEW)):
        for _ in range(N):
            jobs.append((name, prompt, label, system, a))

with ThreadPoolExecutor(8) as pool:
    results = list(pool.map(lambda j: run(j[3], j[4]), jobs))

seen = None
for (name, prompt, label, _, _), line in zip(jobs, results):
    if name != seen:
        seen = name
        print(f'\n### {name}\nPrompt: {prompt[:160]!r}')
    print(f'  {label}: {line}')
