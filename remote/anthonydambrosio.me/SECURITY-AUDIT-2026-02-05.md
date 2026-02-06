# Headscale/Tailscale Security Audit - 2026-02-05

## Summary

Audit of Headscale (server) and Tailscale (client) configuration.
**12 findings** identified: 3 critical (P0), 4 high (P1), 3 medium (P2), 2 low (P3).

---

## P0 - Critical

### 1. Port 8080 (Headscale) exposed to internet without TLS

**Status:** CONFIRMED VULNERABLE

pf is running but uses default OpenBSD rules (`pass` = allow all). Headscale listens
on `0.0.0.0:8080` and is directly accessible from the internet without TLS:

```
$ nc -zv 144.202.100.108 8080
Connection to 144.202.100.108 port 8080 succeeded!

$ curl -s http://144.202.100.108:8080/key
capability version must be set
```

This means the Headscale Noise protocol API is reachable unencrypted, bypassing relayd's
TLS termination entirely. An attacker could perform MITM attacks or interact with the
coordination server directly.

**Remediation:** Add pf rules to restrict inbound traffic to only SSH, HTTP, and HTTPS.
Edit `/etc/pf.conf`:

```
set skip on lo

block return all

pass in proto tcp to port { 22 80 443 }
pass out all

# Allow headscale to accept connections from relayd (localhost via lo, already skipped)
# Block direct access to 8080 from external
```

Then reload: `doas pfctl -f /etc/pf.conf`

### 2. NoStatefulFiltering=true on Tailscale client

**Status:** CONFIRMED

```
"NoStatefulFiltering": true
```

With stateful filtering disabled, any peer on the tailnet can send unsolicited packets
to ANY port on this machine. Combined with the 12 open services on 100.64.0.1, this is
especially dangerous.

**Remediation:** `tailscale set --stateful-filtering`

### 3. No ACL policy on Headscale (default-allow)

**Status:** CONFIRMED

```
$ doas headscale policy get
Failed loading ACL Policy: ... open : no such file or directory
```

Policy `path: ""` in config.yaml. Without ACLs, every node can reach every port on every
other node - full mesh access.

**Remediation:** Create `/etc/headscale/acl.hujson`:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["anthony"],
      "dst": ["anthony:*"]
    }
  ]
}
```

Update `/etc/headscale/config.yaml`:
```yaml
policy:
  mode: file
  path: "/etc/headscale/acl.hujson"
```

Then restart: `doas rcctl restart headscale`

---

## P1 - High

### 4. macOS application firewall disabled

**Status:** CONFIRMED

```
$ /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
Firewall is disabled. (State = 0)
```

Combined with 12 services bound to wildcard addresses, these services are exposed on
all interfaces: LAN, Tailscale, and any other network.

Open ports on 100.64.0.1 (and likely all interfaces):

| Port | Service |
|------|---------|
| 22 | SSH |
| 3003 | Bookmark manager |
| 3333 | Unknown |
| 3939 | Copyparty |
| 3940 | wget_server |
| 5000 | Unknown |
| 7000 | Unknown |
| 8086 | Copyparty |
| 8420 | python http.server (no auth) |
| 8765 | Unknown |
| 22000 | Syncthing |
| 62045 | Unknown |

**Remediation:** Enable macOS firewall:
```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

### 5. No TLS certificate auto-renewal cron

**Status:** CONFIRMED

Root crontab has only standard OpenBSD entries (newsyslog, daily/weekly/monthly).
User crontab is empty. Current cert expires **April 5, 2026** (59 days from now).

**Remediation:** Add to root crontab:
```
0 4 * * 0 acme-client hs.anthonydambrosio.me && rcctl restart relayd
```

### 6. Wildcard DNS record (*.anthonydambrosio.me)

**Status:** CONFIRMED

```
$ dig +short random-test-12345.anthonydambrosio.me
144.202.100.108
```

Any subdomain resolves to the VPS, expanding attack surface. Also causes MagicDNS
names (e.g. `anthonys-mac-mini.tail.anthonydambrosio.me`) to resolve to the VPS IP
instead of the Tailscale IP when not using the MagicDNS resolver.

**Remediation:** Remove `*.anthonydambrosio.me` A record from Porkbun DNS. Keep only
specific records: `anthonydambrosio.me` and `hs.anthonydambrosio.me`.

### 7. No SQLite database backup

**Status:** CONFIRMED

Database at `/var/db/headscale/db.sqlite` (73KB + 4MB WAL) has no backup mechanism.

**Remediation:** Add to root crontab:
```
0 3 * * * cp /var/db/headscale/db.sqlite /var/db/headscale/db.sqlite.bak
```

---

## P2 - Medium

### 8. Tailscale not in Brewfile

**Status:** CONFIRMED

```
$ grep tailscale Brewfile
(no results)
```

If the machine is reprovisioned from the Brewfile, Tailscale won't be installed.

**Remediation:** Add `brew "tailscale"` to Brewfile.

### 9. tailscaled.log growing unbounded (14MB)

**Status:** CONFIRMED

```
$ ls -lh /opt/homebrew/var/log/tailscaled.log
-rw-r--r--  1 anthony  admin  14M Feb  5 20:45
```

No log rotation configured.

**Remediation:** Create `/etc/newsyslog.d/tailscaled.conf`:
```
/opt/homebrew/var/log/tailscaled.log  anthony:admin  644  5  1024  *  Z
```

### 10. Node keys never expire

**Status:** CONFIRMED

Neither SelfNode nor Peers have a `KeyExpiry` field set. If a device is compromised,
its key remains valid indefinitely.

**Remediation:** Set key expiry in headscale config or per-node:
```
doas headscale nodes expire --identifier NODE_ID
```

---

## P3 - Low

### 11. Sequential IP allocation

**Status:** CONFIRMED

```yaml
prefixes:
  allocation: sequential
```

Sequential IPs (100.64.0.1, 100.64.0.2...) make it trivial to enumerate all nodes.

**Remediation:** Change to `allocation: random` in config.yaml.

### 12. Using public DERP relay servers only

**Status:** CONFIRMED (by design)

```yaml
derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
```

Relay traffic goes through Tailscale Inc's infrastructure. Acceptable for now since
traffic is end-to-end encrypted, but a self-hosted DERP would eliminate metadata exposure.

---

## Positive Findings

| Check | Status |
|-------|--------|
| TLS certificate valid | Let's Encrypt, expires Apr 5 2026 |
| TLS 1.0 disabled | Confirmed (connection refused) |
| TLS 1.1 disabled | Confirmed (connection refused) |
| HTTP redirects to HTTPS | 302 redirect confirmed |
| SSH: PasswordAuthentication | no (key-only) |
| SSH: PermitRootLogin | no |
| noise_private.key permissions | 0600 (owner-only) |
| Config file permissions | 0640 root:_headscale |
| Metrics port (9090) | localhost only |
| gRPC port (50443) | Not listening (good, gRPC insecure=false) |
| SMTP (25) | localhost only |
| Pre-auth keys | Both expired (Jan 6 and Feb 4) |
| Headscale version | 0.26.1 (current) |

## db.sqlite permissions note

```
-rw-r--r--  1 _headscale  _headscale  73728  db.sqlite
```

The SQLite database is world-readable (0644). While only `_headscale` owns it and the
directory is restricted (0770 root:_headscale), tightening to 0640 would be defense-in-depth.

---

## Verification Checklist (Post-Remediation)

- [ ] `tailscale debug prefs | grep NoStatefulFiltering` shows `false`
- [ ] `nc -zv 144.202.100.108 8080` is refused
- [ ] `doas headscale policy get` returns valid ACL
- [ ] `dig +short random-test.anthonydambrosio.me` returns nothing
- [ ] macOS firewall shows State=1
- [ ] Root crontab includes acme-client renewal
- [ ] `grep tailscale Brewfile` returns a match
