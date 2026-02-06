# anthonydambrosio.me Server

OpenBSD 7.8 VPS on Vultr running Headscale (self-hosted Tailscale).

## Server Details

- **IP**: 144.202.100.108
- **OS**: OpenBSD 7.8
- **Provider**: Vultr
- **User**: anthony

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Headscale | 8080 (internal) | Tailscale coordination server |
| relayd | 443 | TLS termination for Headscale |
| httpd | 80 | ACME challenges only |
| sshd | 22 | SSH access |

## DNS Records (Porkbun)

```
A    anthonydambrosio.me      144.202.100.108  TTL 600
A    hs.anthonydambrosio.me   144.202.100.108  TTL 600
```

## Configuration Files

### /etc/pf.conf
```
set skip on lo

block return all

# Allow inbound SSH, HTTP (ACME), HTTPS (relayd) only
pass in proto tcp to port { 22 80 443 }

# Allow all outbound (needed for DNS, pkg updates, ACME, DERP)
pass out all

# Port build user does not need network
block return out log proto {tcp udp} user _pbuild
```

### /etc/headscale/config.yaml
```yaml
server_url: https://hs.anthonydambrosio.me
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443

noise:
  private_key_path: /etc/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default

database:
  type: sqlite
  sqlite:
    path: /var/db/headscale/db.sqlite
    write_ahead_log: true

policy:
  mode: file
  path: "/etc/headscale/acl.hujson"

dns:
  magic_dns: true
  base_domain: tail.anthonydambrosio.me
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1

unix_socket: /var/run/headscale/headscale.sock
```

### /etc/headscale/acl.hujson
```json
{
  "groups": {
    "group:admin": ["anthony@"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:admin"],
      "dst": ["group:admin:*"]
    }
  ]
}
```

### /etc/relayd.conf
```
table <headscale> { 127.0.0.1 }

tcp protocol headscale-proto {
    tls keypair "hs.anthonydambrosio.me"
}

relay headscale-tls {
    listen on 0.0.0.0 port 443 tls
    protocol headscale-proto
    forward to <headscale> port 8080
}
```

### /etc/httpd.conf
```
server "hs.anthonydambrosio.me" {
    listen on * port 80
    location "/.well-known/acme-challenge/*" {
        root "/acme"
        request strip 2
    }
    location * {
        block return 302 "https://$HTTP_HOST$REQUEST_URI"
    }
}
```

### /etc/acme-client.conf
```
authority letsencrypt {
    api url "https://acme-v02.api.letsencrypt.org/directory"
    account key "/etc/acme/letsencrypt-privkey.pem"
}

domain hs.anthonydambrosio.me {
    domain key "/etc/ssl/private/hs.anthonydambrosio.me.key"
    domain full chain certificate "/etc/ssl/hs.anthonydambrosio.me.fullchain.pem"
    sign with letsencrypt
}
```

## TLS Certificates

- **Cert**: `/etc/ssl/hs.anthonydambrosio.me.fullchain.pem`
- **Key**: `/etc/ssl/private/hs.anthonydambrosio.me.key`
- **Symlink**: `/etc/ssl/hs.anthonydambrosio.me.crt` -> fullchain.pem (for relayd)

Auto-renewed weekly via root crontab (Sunday 4am). Manual renewal:
```sh
doas acme-client -v hs.anthonydambrosio.me && doas rcctl restart relayd
```

## Headscale Management

```sh
# List users
doas headscale users list

# Create user
doas headscale users create USERNAME

# Generate auth key (24h, reusable)
doas headscale preauthkeys create --user 1 --reusable --expiration 24h

# List nodes
doas headscale nodes list

# Delete node
doas headscale nodes delete --identifier NODE_ID
```

## Connecting Clients

### macOS (Homebrew)
```sh
brew install tailscale
sudo brew services start tailscale
tailscale up --login-server=https://hs.anthonydambrosio.me --authkey=YOUR_KEY
```

### iOS/Android
1. Install Tailscale app
2. Settings > Use alternate server
3. Enter `https://hs.anthonydambrosio.me`
4. Authenticate with key

### Linux
```sh
tailscale up --login-server=https://hs.anthonydambrosio.me --authkey=YOUR_KEY
```

## Service Management

```sh
# Check status
doas rcctl check headscale relayd httpd

# Restart services
doas rcctl restart headscale
doas rcctl restart relayd

# View logs
doas tail -f /var/log/messages
```

## Security

See [SECURITY-AUDIT-2026-02-05.md](SECURITY-AUDIT-2026-02-05.md) for full audit results.

**Remediated 2026-02-06:**
- pf.conf locked down (only 22/80/443 inbound)
- Tailscale stateful filtering enabled
- Headscale ACL policy created (`/etc/headscale/acl.hujson`)
- macOS application firewall enabled
- TLS cert auto-renewal cron added (weekly)
- SQLite daily backup cron added
- db.sqlite permissions tightened to 640

## Automated Crons (root)

| Schedule | Command | Purpose |
|----------|---------|---------|
| Daily 3am | `cp db.sqlite db.sqlite.bak` | Headscale DB backup |
| Sunday 4am | `acme-client && rcctl restart relayd` | TLS cert renewal |

## System Maintenance

```sh
# Update packages
doas pkg_add -u

# System patches
doas syspatch

# Firmware updates
doas fw_update
```

## Encrypted Storage

The server has separate encrypted block storage (from Sivers guide):

```sh
# Mount encrypted storage
m

# Unmount
m-x
```

## SSH Access

```sh
ssh anthony@anthonydambrosio.me
```

## Setup History

1. Created OpenBSD 7.3 VPS on Vultr
2. Upgraded through 7.4 -> 7.5 -> 7.6 -> 7.7 -> 7.8
3. Installed Headscale via pkg_add
4. Configured TLS with acme-client + relayd
5. Set up Headscale with SQLite backend
