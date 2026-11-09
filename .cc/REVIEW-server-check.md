# Review: `services/server-check`

Date: 2026-11-09 (times are MST). Reviewed `script.sh`, the plist, the launcher, `bin/service-wrapper`, `bin/service` and `_ENSURE_SERVICES`.

## Verdict

The design is sound and the normal path works. Every check detects its failure on the real server. It is silent when healthy and sends one notification per run. Two things should be fixed before it is trusted: a false alarm after a Mac restart, and a hang that can stop all later runs. One further check is too weak to meet the purpose: Navidrome is only tested as a running process.

No repo file, service or server setting was changed. Test copies are in the session scratchpad.

**Side effect of this review:** the no-agent tests produced several failed SSH logins. The server then closed connections from this Mac for under 2 minutes (seen 00:34, clear by 00:36). The cause is probably the default `PerSourcePenalties` in OpenSSH 10.2 (inference: `authlog` is root-only). The server's auth log will show those failures.

## Findings, by severity

### HIGH 1. False "SSH: server unreachable" after a Mac restart

**Verified**, except the last step, which is inference.

- `~/.ssh/id_rsa` has a passphrase (`ssh-keygen -y -P ''` fails).
- launchd gives the job `SSH_AUTH_SOCK`, so it works while the agent holds the key. With the key in the agent and the screen locked, the script reported `ok` at 00:42.
- The agent is empty after each restart. Nothing in `fish/`, `rcs/`, `services/` or `lib/lua` runs `ssh-add`. The agent gets the key only when some `ssh` first uses it (`AddKeysToAgent yes`).
- With no agent, the key depends on the passphrase in the Keychain (`UseKeychain yes`). That worked at 00:28 and 00:30. The screen locked at 00:33:11. From 00:34 every no-agent attempt failed with `Permission denied (publickey,keyboard-interactive)`. Four of the attempts were in a controlled matrix: without the agent both failed, with the agent both passed. `BatchMode=yes` cannot prompt.
- Inference: the Keychain lookup needs an unlocked screen. The timing fits exactly, but the mechanism was not isolated. `security show-keychain-info` reports `no-timeout`.
- The run at 09:00 normally happens with the screen locked. On 2026-11-08 the display turned off at 07:58:30 and did not come back until 10:51.
- This Mac restarted 14 times between 2026-10-01 and 2026-11-07.

Result: restart, then no manual `ssh` before the screen locks, gives a false alert at 09:00. It repeats each day until something loads the key. The disk and Navidrome checks do not run on those days.

Fix (recommended): a dedicated key with no passphrase, limited on the server to one read-only command.

```sh
# Mac
ssh-keygen -t ed25519 -N '' -C server-check -f ~/.ssh/server_check
# Server: put the three check lines in ~/bin/server-status (mode 755), then add to authorized_keys
restrict,command="/home/anthony/bin/server-status" ssh-ed25519 AAAA... server-check
# script.sh: replace the inline remote command with these ssh options
-i "$HOME/.ssh/server_check" -o IdentitiesOnly=yes -o IdentityAgent=none
```

The trade-off is an unencrypted key on the Mac. It can only run that one command. This fix was not tested.

Smaller alternative, with no new key: keep stderr and report the difference. If `state` contains `Permission denied`, add the problem `SSH login failed on this Mac (key not loaded): run ssh once`. This keeps the alert honest, but the server is still unchecked on those days.

### MEDIUM 2. `ssh` can hang forever, and a hung run blocks every later run

**Verified** for the hang, using a local fake server that sends an SSH banner and then goes silent. With `ConnectTimeout=3`, `ssh` was still running when killed at 40 s. With `ServerAliveInterval=3` and `ServerAliveCountMax=2` it exited at 6 s. With no banner, `ConnectTimeout` works (3 s).

**Inference** for the blocking. `man launchd.plist` says a firing during a running job is missed for `StartInterval`, and calendar jobs behave the same way.

A half-dead server (sshd answers, then stalls) is exactly the case this job exists to report. A hung run produces no alert and no later checks until the job is killed or the Mac restarts. `ServerAlive` does not cover a remote command that stalls while sshd still answers, so an outer limit is needed too.

Fix, in `run_checks`:

```sh
state=$(/opt/homebrew/bin/timeout 90 /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=20 \
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$host" '
```

Tested on a copy with shortened timeouts against the fake server: it ended in 13 s and alerted correctly. Without the hang, the longest run is about 250 s: 10 for the internet check, then up to 60 per attempt, plus the 120 s wait.

### MEDIUM 3. Navidrome is checked only as a process

**Verified** that a better check works. `pgrep` proves the process exists. It does not prove the server answers. Navidrome listens only on the Tailscale address, so if `tailscaled` or `tun0` fails after start, phones lose music and this check still passes. Tailscale on the server is not checked anywhere else.

Replace the `pgrep` line with a real request, and change the message to `Navidrome is not responding`:

```sh
[ "$(ftp -MV -o - -w 5 http://100.64.0.3:4533/ping 2>/dev/null)" = . ] && echo navidrome
```

Tested on the server (port 4533 passes, wrong port fails) and through a full dry run on a copy. `-w` limits only the connection, so finding 2's `timeout` is what limits a stalled read.

### LOW 4. The "no internet" check runs only before the first attempt

**Verified** with a copy whose check passes and whose targets then go nowhere: both attempts fail and the alert blames the server. The script's own comment says this should not happen. It needs an outage that starts just after 09:00 and lasts through the retry.

Fix: repeat the check after the wait, before the second `run_checks` (tested on a copy).

```sh
/bin/sleep "${SERVER_CHECK_RETRY_DELAY:-120}"
if ! /usr/bin/nc -z -G 10 1.1.1.1 443 2>/dev/null; then
    echo "$(date): no internet on this Mac; skipped"
    exit 0
fi
run_checks
```

The check is a single attempt, so one failure skips the whole day. This Mac is on Ethernet and did not sleep, so this does not need a fix now.

### LOW 5. Failure reasons are thrown away

**Verified.** Any ssh failure reads as `server unreachable`, including a login failure (finding 1) and a DNS failure. `2>/dev/null` on `ssh` and `curl` means the log cannot tell them apart.

Fix: remove `2>/dev/null` from both. The text goes only to the service log, so it adds no notifications.

### LOW 6. A failed notifier is silent

**Verified** with a copy using a missing notifier, through the real wrapper. The log gets one error line and the wrapper exits 0, because the exit code is that of `ts`. launchd will always show `last exit code = 0`.

Fix: `"$notifier" -title "Vultr server" -message "$message" || /usr/bin/osascript -e "display notification \"$message\" with title \"Vultr server\""`. The messages contain no quotes.

### LOW 7. Certificate problems are reported only once the certificate has expired

**Verified** that an expired certificate is caught. The comment "catches a failed renewal" is true only on expiry day, which is up to about 30 days after renewal first fails. Optional early warning, tested with `/usr/bin/openssl` (14 days):

```sh
echo | /opt/homebrew/bin/timeout 20 /usr/bin/openssl s_client -connect hs.anthonydambrosio.me:443 \
    -servername hs.anthonydambrosio.me 2>/dev/null | /usr/bin/openssl x509 -noout -checkend 1209600 \
    || problems+=("certificate expires within 14 days")
```

## Accepted limits, no fix needed

- **Mac off or not logged in at 09:00: that day is missed** (FileVault is on, no auto-login, no `RunAtLoad`). The next day catches it. The Mac was up at 09:00 on all 7 days sampled (2026-11-01 to 11-07).
- **Sleep:** `man launchd.plist` says a missed time runs at wake, merged into one. No pile-up. This Mac did not sleep (`Sleep Count:0`, Internet Sharing denies sleep). `ziplog` and `disk-snapshot` fired within 5 s of their calendar times.
- **Nothing warns if the job itself stops running.** A heartbeat would add the noise the user wanted to avoid.
- **Disk space is not checked** (`/` 13%, `/mnt` 44%).

## Checked and correct

| Item | Result | How |
|---|---|---|
| launchd PATH and tools | Fine; all external tools are absolute or in `/usr/bin` | `launchctl print`, 2 real runs logged `ok` |
| Launcher with no shebang | Runs | `runs = 2`, same as other services |
| GUI session for notifications | Correct domain | `gui/501`, Aqua monitor. Notifications allowed in `ncprefs`; style bits suggest Alerts (undocumented, inference). No real notification was sent |
| Remote shell | `ksh`, with `/sbin` in PATH | Run on server |
| `pgrep -f` pattern | Matches only the real process, not its own `ksh -c` | Matched one PID, 31986; `navidromeX` gave rc 1 |
| `mount` match | Correct; `bin/mnt` uses the same device | `mount` output, locked variant on a copy |
| `/health` | `{"status":"pass"}`, HTTP 200 | Live request |
| Bad TLS, HTTP 500, 200 without `pass`, bad DNS | All alert | Dry runs |
| Combined message | `A; B` is correct | Dry run |
| `problems` scoping, `IFS`, bash 3.2 | Correct; reset on each attempt | Read and dry runs |
| One notification per run, silent when healthy | Yes | Read and dry runs |
| `_ENSURE_SERVICES` and `bin/service` | Hardlinked and loaded. A relink, `start` or `restart` runs one extra check, which is harmless | Read code, link count 2 |
