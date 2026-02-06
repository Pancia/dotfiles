# Security Remediation Log - 2026-02-06

Remediation of findings from [SECURITY-AUDIT-2026-02-05.md](SECURITY-AUDIT-2026-02-05.md).

## P0 - Critical

### 1. pf.conf locked down

Replaced default allow-all rules in `/etc/pf.conf`. Only ports 22, 80, 443 inbound now.

Backed up original to `/etc/pf.conf.bak` on VPS.

Verified: `nc -zv -G 3 144.202.100.108 8080` -> refused.

### 2. Tailscale stateful filtering enabled

The `--stateful-filtering` flag was removed from `tailscale set` and `tailscale up` in v1.92.3,
but the preference still existed as `NoStatefulFiltering: true`. Set it via LocalAPI:

```sh
tailscale debug localapi PATCH /localapi/v0/prefs '{"NoStatefulFilteringSet": true, "NoStatefulFiltering": false}'
```

The `NoStatefulFilteringSet` mask field is required or the patch is ignored.

Verified: `tailscale debug prefs | grep NoStatefulFiltering` -> `false`.

### 3. Headscale ACL policy created

Created `/etc/headscale/acl.hujson`. Two issues encountered:

1. Headscale v0.26.1 requires `username@` syntax (not bare `anthony`)
2. `autogroup:member` is not supported in v0.26.1 (only `autogroup:internet`)

Working policy uses explicit group:

```json
{
  "groups": { "group:admin": ["anthony@"] },
  "acls": [{ "action": "accept", "src": ["group:admin"], "dst": ["group:admin:*"] }]
}
```

Validate before applying: `doas headscale policy check --file /etc/headscale/acl.hujson`

Updated `policy.path` in `/etc/headscale/config.yaml` and restarted headscale.

## P1 - High

### 4. macOS application firewall enabled

```sh
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

Allowed tailscaled incoming connections when prompted.

### 5. TLS cert auto-renewal cron

Added to root crontab on VPS: `0 4 * * 0 acme-client hs.anthonydambrosio.me && rcctl restart relayd`

### 6. Wildcard DNS removed

Deleted `*.anthonydambrosio.me` A record in Porkbun. Verified: `dig +short random-test-12345.anthonydambrosio.me` -> empty.

### 7. SQLite backup cron

Added to root crontab on VPS: `0 3 * * * cp /var/db/headscale/db.sqlite /var/db/headscale/db.sqlite.bak`

## P2 - Medium

### 8. Tailscale added to Brewfile

Added `brew 'tailscale'` to System Utilities section.

### 9. tailscaled log rotation

Created `/etc/newsyslog.d/tailscaled.conf` on Mac (not in dotfiles repo, lives in /etc):

```
/opt/homebrew/var/log/tailscaled.log  anthony:admin  644  5  5120  *  Z
```

Rotates at 5MB, keeps 5 compressed backups (~2 months of history).

### 10. db.sqlite permissions tightened

`doas chmod 640 /var/db/headscale/db.sqlite` on VPS.

## P3 - Deferred

- Sequential IP allocation (`allocation: random`) - do when convenient
- Self-hosted DERP server - requires additional infra
