---
name: headscale
description: Use this skill when managing Headscale (self-hosted Tailscale coordination server) or Tailscale clients. Covers ACL policies, server administration, pf firewall, TLS certificates, client configuration, and troubleshooting.
user-invocable: true
disable-model-invocation: false
---

# Headscale / Tailscale Administration

Self-hosted Tailscale coordination server on OpenBSD VPS with Tailscale clients.

## Infrastructure

| Component | Location | Details |
|-----------|----------|---------|
| Headscale | VPS (anthonydambrosio.me) | OpenBSD 7.8, v0.26.1 |
| relayd | VPS | TLS termination (443 -> 8080) |
| httpd | VPS | ACME challenges only (port 80) |
| pf | VPS | Firewall: 22/80/443 inbound only |
| Tailscale | Mac (local) | v1.92.3 via Homebrew |

## SSH Access

```sh
ssh anthony@anthonydambrosio.me
```

All server commands require `doas` (OpenBSD sudo equivalent).

## Common Operations

### Node Management

```sh
# List nodes
doas headscale nodes list

# List users
doas headscale users list

# Generate auth key (24h, reusable)
doas headscale preauthkeys create --user 1 --reusable --expiration 24h

# Delete node
doas headscale nodes delete --identifier NODE_ID

# Expire a node key
doas headscale nodes expire --identifier NODE_ID
```

### Service Management

```sh
# Check all services
doas rcctl check headscale relayd httpd

# Restart headscale
doas rcctl restart headscale

# Restart relayd (after cert renewal)
doas rcctl restart relayd
```

### TLS Certificates

Auto-renewed weekly (Sunday 4am) via root crontab. Manual renewal:

```sh
doas acme-client -v hs.anthonydambrosio.me && doas rcctl restart relayd
```

### Client Connection

```sh
# macOS
brew install tailscale
sudo brew services start tailscale
tailscale up --login-server=https://hs.anthonydambrosio.me --authkey=YOUR_KEY

# Check status
tailscale status
```

## ACL Policy

Policy file: `/etc/headscale/acl.hujson`

See [acl-policy.md](references/acl-policy.md) for syntax details and gotchas.

### Validate Before Applying

Always validate before restarting headscale:

```sh
doas headscale policy check --file /etc/headscale/acl.hujson
```

### View Active Policy

```sh
doas headscale policy get
```

## Tailscale Client Preferences

See [tailscale-client.md](references/tailscale-client.md) for LocalAPI usage and preference management.

## Firewall (pf)

See [pf-firewall.md](references/pf-firewall.md) for rules and management.

## Key Config Files (VPS)

| File | Purpose |
|------|---------|
| `/etc/headscale/config.yaml` | Main headscale config |
| `/etc/headscale/acl.hujson` | ACL policy |
| `/etc/pf.conf` | Packet filter rules |
| `/etc/relayd.conf` | TLS termination |
| `/etc/httpd.conf` | ACME challenge server |
| `/etc/acme-client.conf` | Let's Encrypt config |
| `/var/db/headscale/db.sqlite` | Headscale database (0640) |

## Key Config Files (Mac)

| File | Purpose |
|------|---------|
| `/etc/newsyslog.d/tailscaled.conf` | Log rotation (5MB, 5 backups) |
| `/opt/homebrew/var/log/tailscaled.log` | Tailscale daemon log |

## Troubleshooting

### Headscale won't start after config change

Revert the change, start headscale, then debug:

```sh
# Revert and start
doas sed -i 's|path: "/etc/headscale/acl.hujson"|path: ""|' /etc/headscale/config.yaml
doas rcctl start headscale

# Test the change in isolation
doas timeout 5 headscale serve 2>&1
```

The `timeout` trick shows startup errors that `rcctl` swallows.

### Check what headscale logs

Headscale does NOT log to syslog by default. Use `headscale serve` directly to see output, or check if configured to log to a file.

## Documentation

Local docs in `remote/anthonydambrosio.me/`:

| File | Contents |
|------|----------|
| `README.md` | Full server config reference |
| `SECURITY-AUDIT-2026-02-05.md` | Security audit findings |
| `REMEDIATION-2026-02-06.md` | Remediation steps and gotchas |
