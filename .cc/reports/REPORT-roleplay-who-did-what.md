# Roleplay bookends: who did what (2026-11-17)

## Problem

A closer told the user "you admitted you'd looked in the wrong folder". In
that turn the assistant's reply said "I was wrong… I had looked only in the
default hooks folder". The writer read the reply's "I" as the user.

## Test

Sonnet, the closer prompt as the mod builds it, one character (Malfoid
(Wife)). Two inputs: the real reply from that turn (kept out of this public
report; it is in that session's transcript, 2026-11-18 00:47 UTC), and a
made-up reply with the same shape (`.cc/misc/roleplay-who-did-what/ask.txt`).

| System prompt | Real reply: line says "you" for the assistant's act | Other problem |
|---|---|---|
| old (`old.txt`) | 6 of 8 | — |
| new2: "in the reply I means the assistant; never say you for it" (`new2.txt`) | 0 of 8 | 6 of 8 had the character say "I looked in the wrong folder": it took the assistant's "I" for itself |
| new3: three parties; the character is neither (`new3.txt`) | 0 of 10 | 1 of 10 ambiguous ("I shan't mention it again") |

On the made-up reply the old prompt did not misattribute (0 of 6), so the
bug needs a reply that confesses in the first person. A first try that told
the writer to "name Claude as the one who did it" fixed the blame but made
every line open with "the assistant searched the wrong folder…"; dropped.

## Change

`SYS` in `ai/mods/roleplay-bookends/hooks/register.tsx` now holds new3's
three-party sentences. The test `the writer is told who did the work` checks
they stay.
