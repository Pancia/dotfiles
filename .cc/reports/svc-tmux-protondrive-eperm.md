# svc tmux server: EPERM on ProtonDrive files

Date: 2026-11-17 (times are MST). Investigation only; no config or code changed.

## Answer (proved)

The `svc` tmux server is not sandboxed by Claude Code's Bash sandbox. macOS
privacy control (TCC) blocks it, because the server's **responsible process**
is the Claude Code background-session host (`ClaudeCode.app`, bundle id
`com.anthropic.claude-code`, pid 32688), not iTerm2.

- TCC checks protected folders against the responsible process, not against
  `tmux` or `head`.
- iTerm2 has grants for Documents, Downloads and the cloud File Provider
  folders. `com.anthropic.claude-code` has none of these.
- A process keeps its responsible process for life, and its children inherit
  it. The tmux server and every window and `run-shell` in it are therefore
  judged as "Claude Code", for as long as the server runs.

The other session was not "the CLI inside iTerm2" when it ran `svc-tmux up`.
It is a Claude Code background session (`sessionKind: "bg"` in both
transcripts, back to 2026-11-11). At 2026-11-16 15:50:02 MST, session
`a5349931` (2.1.325) was continued in session `f00bde53` (2.1.326) (transcript
line `continued-in`), under a new host. The `svc-tmux up --wait --timeout 40
web` call at 2026-11-17 00:27:48Z (17:27:48 MST, the server's start time) is
in `f00bde53`, `sessionKind: "bg"`, with no `dangerouslyDisableSandbox`. That
session runs under the Claude daemon: iTerm2 → fish → `claude` (96905) →
daemon `~/.local/bin/claude` (32391) → `ClaudeCode.app/.../claude --bg-pty-host
.../f00bde53.sock` (32688) → session process 2.1.326 (34943) → Bash → svc-tmux
→ tmux server (41882). Pid 32688 is responsible for itself, so everything below
it lost iTerm2's grants.

## Evidence

### Responsible process (private API `responsibility_get_pid_responsible_for_pid`, via python ctypes)

```
41882 tmux                          -> responsible 32688 ClaudeCode.app/Contents/MacOS/claude
42202 bash (supervise web)          -> responsible 32688 ClaudeCode.app/Contents/MacOS/claude
34943 versions/2.1.326 (bg session) -> responsible 32688 ClaudeCode.app/Contents/MacOS/claude
32688 ClaudeCode.app --bg-pty-host  -> responsible 32688 (itself)
32391 daemon ~/.local/bin/claude    -> responsible 672 iTerm2
96905 claude [3d-vr-scene-...]      -> responsible 672 iTerm2
80666 claude (this session)         -> responsible 672 iTerm2
this session's bash                 -> responsible 672 iTerm2
throwaway tmux server (repro)       -> responsible 672 iTerm2
```

`ClaudeCode.app` (`~/.local/share/claude/ClaudeCode.app`) is a hard link to
`versions/2.1.326`, signed as `com.anthropic.claude-code`, team Q6L2SF6YDW,
`LSUIElement=1`, with its own privacy usage strings. It is built to be a
separate TCC identity.

### TCC log for a probe from inside `svc` (15:44:07 MST)

```
AUTHREQ_CTX: msgID=403.79290, service=kTCCServiceSystemPolicyAllFiles, preflight=yes
AUTHREQ_ATTRIBUTION: msgID=403.79290, attribution={responsible={TCCDProcess:
  identifier=com.anthropic.claude-code, pid=32688, ... binary_path=.../versions/2.1.326},
  accessing={TCCDProcess: identifier=com.apple.head, pid=17098, binary_path=/usr/bin/head},
  requesting={... com.apple.sandboxd ...}}
AUTHREQ_RESULT: msgID=403.79290, authValue=0, authReason=5
sandboxd: TCCAccessRequestIndirectWithOptions (kTCCIndirectObjectFileProviderDomainID = "ch.protonmail.drive.f...")
sandboxd: access request result was 0, timeout was 0
kernel (Sandbox) System Policy: head(17098) deny(1) file-read-data
  /Users/anthony/Library/CloudStorage/ProtonDrive-*/Developer/bitwarden-password.txt
...
AUTHREQ_CTX: msgID=403.79295, service=kTCCServiceSystemPolicyDocumentsFolder, preflight=no
AUTHREQ_ATTRIBUTION: ... responsible= com.anthropic.claude-code pid=32688 ... accessing= /bin/ls
AUTHREQ_RESULT: msgID=403.79295, authValue=0, authReason=2
kernel (Sandbox) System Policy: ls(17099) deny(1) file-read-data /Users/anthony/Documents
```

"System Policy" is the kernel's TCC-backed platform policy. A Claude Code
Seatbelt profile would log as `Sandbox: <proc>(pid) deny(1) ...` with no
"System Policy" prefix, and would not involve tccd.

`authReason=2` (user consent) with `authValue=0` on Documents means a stored
"deny" record for Claude Code exists for that folder (or one was recorded from
an unanswered prompt). The user TCC database could not be read to confirm,
because iTerm2 has no Full Disk Access.

The original failure has the same attribution:

```
2026-11-17 15:33:33.036 tccd AUTHREQ_CTX: msgID=403.78968, service=kTCCServiceSystemPolicyAllFiles, preflight=yes
2026-11-17 15:33:33.036 tccd AUTHREQ_ATTRIBUTION: msgID=403.78968, attribution={responsible={TCCDProcess:
  identifier=com.anthropic.claude-code, pid=32688, ... responsible_path=.../versions/2.1.326 ...
2026-11-17 15:33:33.055 tccd AUTHREQ_RESULT: msgID=403.78968, authValue=0, authReason=5
2026-11-17 15:33:33.077 kernel (Sandbox) System Policy: node(74589) deny(1) file-read-data
  .../ProtonDrive-*/Developer/bitwarden-password.txt
(the same deny again at 15:36:21 node(86091) and 15:37:00 head(89764))
```

### Direct Seatbelt test

`sandbox_check(pid, NULL, 0)` (libsystem, via ctypes) returns 0 ("not
sandboxed") for the tmux server 41882, its `supervise` child 42202, the bg
session process 34943, the host 32688, and this session's Bash.

### Same paths: `svc` server vs this session's Bash

| path | `svc` server | this Bash (iTerm2) |
|---|---|---|
| ~/Desktop | EPERM | EPERM |
| ~/Documents | EPERM | ok |
| ~/Downloads | EPERM | ok |
| CloudStorage/ProtonDrive-… | EPERM | ok |
| CloudStorage/Dropbox | EPERM | ok |
| CloudStorage/GoogleDrive-… | EPERM | ok |
| ~/Library/Mail, Messages, Safari, Notes container | EPERM | EPERM |
| ~/dotfiles, ~/Pictures, ~/Movies, /tmp write | ok | ok |

The pattern is exactly "iTerm2's per-folder grants, minus all of them". It is
not specific to ProtonDrive. Desktop and Mail are denied in both, so iTerm2 has
no Desktop grant and no Full Disk Access.

### Repro

A throwaway server started from this session's sandbox-default Bash (`env -u
CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u SECURITYSESSIONID -u TERM_SESSION_ID -u
ITERM_SESSION_ID tmux -L tccprobe-23353 -f lib/svc/tmux.conf new-session -d
... sleep 60`, a partial copy of the `svc-tmux` env scrub) has parent pid 1,
responsible iTerm2, and reads the file. It was killed afterwards.

This reproduces only the working side. The failing side was not reproduced:
that needs a server started from a Claude Code bg session whose host is
self-responsible. To prove it, run the ctypes probe below plus the one-byte
read from a fresh bg session's Bash; expect "responsible = ClaudeCode.app" and
EPERM together.

## Candidates ruled out

- **Claude Code Bash sandbox (Seatbelt) inherited by tmux.** No `sandbox` key
  in `~/.claude/settings.json`, `~/.claude/settings.local.json` (missing), the
  3d-vr project `.claude/` (missing), or managed settings (no
  `/Library/Application Support/ClaudeCode`, no `/Library/Managed Preferences`).
  The `svc` server can write outside the project (`touch
  ~/Library/Caches/svc-tcc-probe-2467` succeeded; file trashed), which a Claude
  Code sandbox profile forbids. `sandbox_check` reports the server and its
  children as not sandboxed. The deny lines are "System Policy" with tccd
  attribution, not a Seatbelt profile.
- **A TCC grant changed after the server started / ProtonDrive restart.** The
  same denial pattern hits Documents, Downloads, Dropbox and Google Drive, which
  are separate grants and separate File Provider domains. A grant change or a
  ProtonDrive restart would not remove all of them at once. A fresh server from
  an iTerm2-responsible process reads the file now.
- **Environment differences (no CLAUDECODE, ITERM2_COOKIE present).** TCC
  ignores environment variables. The throwaway server had the same scrubbed env
  and works.
- **Permission mode of the other session.** It was `auto`. That controls Claude
  Code tool approval only, not macOS privacy.

The unified log keeps no tccd lines at all for 2026-11-16 17:00–18:00 MST
(tccd lines from that day are sparse; one remains at 10:07). So the log
cannot show what TCC did when the server started. That does not change the
cause: responsibility is fixed at process creation, and today's lines show it.

## Open points

- Why 32688 is self-responsible but the newer spare host (94777, started
  2026-11-17 12:27, same binary) and its `bg-spare` child (94788) are
  responsible to iTerm2 is not known. It may depend on the Claude Code
  version or on how a host is spawned. So a new bg session may or may not have
  the same problem. Check a session with the ctypes probe below.
- Whether a stored "deny" for Claude Code on the ProtonDrive File Provider
  domain exists (vs. "never asked"). Seen in System Settings → Privacy &
  Security → Files & Folders → Claude Code.

Probe (prints the responsible pid and name for each pid given):

```python
import ctypes, subprocess, sys
f = ctypes.CDLL(None).responsibility_get_pid_responsible_for_pid
f.restype = ctypes.c_int; f.argtypes = [ctypes.c_int]
for p in map(int, sys.argv[1:]):
    r = f(p)
    print(p, '->', r, subprocess.run(['ps','-o','comm=','-p',str(r)],
                                     capture_output=True, text=True).stdout.strip())
```

## Fixes that keep privacy protection on

The `svc` server must be restarted to change its responsible process. Nothing
done inside it can change that. Do not restart it while the other session's
`web` service runs there.

1. **Recommended: start the `svc` tmux server only from a process that iTerm2
   is responsible for.** For example `cmds services` in an iTerm2 pane, or a
   foreground (non-bg) Claude session. Exposes nothing new: services get the
   same folder grants as the user's own shell. A guard in `svc-tmux` (in
   `new_window`, only on the branch that creates the server) could check the
   responsible process with the probe above. If it is
   `ClaudeCode.app`/`com.anthropic.claude-code`, refuse with a message such as
   "a Claude background session would own the svc server; it cannot read
   Documents/Downloads/cloud folders; start it from your terminal". A cheaper
   check: try to list a TCC-protected folder that iTerm2 can read, such as
   `~/Library/CloudStorage/ProtonDrive-*`, and fail on EPERM. Note that a
   `svc-tmux up` from any process joins an existing server, so the guard only
   matters at server creation.
2. **Keep the secret out of a TCC-protected folder for this service.** Both
   ways weaken protection, so prefer option 1.
   - Login Keychain via `security find-generic-password -w ...`. The caller is
     always `/usr/bin/security`, and an item made with `security
     add-generic-password` trusts that tool. So any process running as
     anthony, including any agent command, can read it with no prompt while
     the keychain is unlocked. The gain over a plain file is encryption at
     rest and no access while the keychain is locked.
   - A copy at a plain path such as `~/.config/...` with mode 0600: any
     process running as anthony can read it at any time, with no TCC check.
3. **Grant "Claude Code" access to the ProtonDrive domain only** (System
   Settings → Privacy & Security → Files & Folders → Claude Code → ProtonDrive,
   or answer the prompt when it appears). This exposes all of ProtonDrive to
   every Claude Code background session and every command, server and
   subprocess those sessions run, with no human in the loop in `auto` mode.
   Narrower than Full Disk Access, but broader than option 1. Not recommended
   unless background sessions must reach ProtonDrive.

Not recommended: Full Disk Access for Claude Code or for tmux. That would let
any background agent command read Mail, Messages, Safari data and all cloud
folders.
