# Clojure Tooling

## bbin

[bbin](https://github.com/babashka/bbin) installs Babashka-based scripts from
git repos or Maven coordinates into `~/.local/bin/`, similar to `pipx` for
Python. It depends on Babashka (`borkdude/brew/babashka`).

bbin itself is installed via Homebrew from the `rads/bbin` tap (see
`Brewfile`). Scripts that bbin manages are reinstalled by the
`./install bbin` task — re-running it is safe and idempotent.

## Installed scripts

All three come from [`clojure-mcp-light`](https://github.com/bhauman/clojure-mcp-light)
and land in `~/.local/bin/`:

| Script                          | Purpose                                                    |
|---------------------------------|------------------------------------------------------------|
| `clj-nrepl-eval`                | Evaluate Clojure forms against a running nREPL server      |
| `clj-paren-repair`              | Repair unbalanced parens in Clojure source                 |
| `clj-paren-repair-claude-hook`  | Claude Code `PostToolUse` hook — auto-repairs paren errors |

The hook script is referenced from `rcs/claude-settings.json` (lines 99, 129,
179) as a `PostToolUse` command. Without it installed, those hooks fail
silently on a fresh machine — which is exactly why this install task exists.

## Reinstalling

```bash
cd ~/dotfiles && ./install bbin
```

## Known failure mode (2026-05-18)

The two `v0.2.2` scripts (`clj-nrepl-eval`, `clj-paren-repair`) had previously
been installed against a pinned git SHA (`401e2746…`) that was later pruned
upstream. Symptom was a misleading error:

```
Cannot run program "/usr/bin/java"
```

Root cause: Babashka tried to `chdir` into the missing gitlibs directory
before exec'ing java. Fix: just rerun `./install bbin` — it resolves to the
latest release tag rather than re-pinning a SHA.

The install commands deliberately do **not** pin git SHAs, for this reason.
