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
| Tailscale | - | Joins the tailnet as `vultr`, 100.64.0.3 (`tun0`) |
| Navidrome | 4533 (Tailscale only) | Music server, on the `/music` disk. Started by `/etc/rc.local` at boot, after Tailscale is up. See "Music streaming" in the root CLAUDE.md |

The user `musicread` exists only for two restricted keys used by Mac background jobs. See
"Music streaming" in the root CLAUDE.md.

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

unix_socket: /var/db/headscale/headscale.sock  # not /var/run: OpenBSD empties that at boot
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

## Music disk (`/music`)

A 40 GB unencrypted Vultr HDD volume (DUID `aa81c53c88998d20`) that holds only
`/music/MyMusic` (tracks and playlists) and `/music/.navidrome`. It is `noauto` in
`/etc/fstab`; `/etc/rc.local` fscks and mounts it in the background, so a problem with it
cannot stop the boot, then starts Navidrome once `tun0` has 100.64.0.3. `/etc/rc.shutdown`
stops Navidrome. `music push` writes here, and `musicread` reads it. When it is not mounted,
`/music` is an empty root-owned folder, so writers check `mount | grep -q ' on /music '`.

## Encrypted disk (`/mnt`)

`/mnt` is a softraid CRYPTO volume on separate block storage. It locks on every server
restart. `~/bin/mnt` unlocks it (it asks for the passphrase); `~/bin/unmnt` locks it and
prints FAILED if the volume is still attached. Neither touches Navidrome or `/music`.
Music details are in "Music streaming" in the root CLAUDE.md.

**When it is locked, `/mnt` is a plain folder on the unencrypted root disk**, and a write
there puts private data on that disk. Every writer must first run
`/usr/local/bin/crypt-mounted`, on the same connection that writes (for rsync, in
`--rsync-path`). It exits 0 only when the encrypted volume is mounted on `/mnt`. It finds
the volume by its disk ID, not by device name, because the `sdN` number changes when
disks are added: it was `sd2a`, and is now `sd3a`. Do not check `mount` for a device name.

Folders, as of 2026-11-10 (disk unlocked):

| Folder | Owner:group, mode | Written by | Read by |
|--------|-------------------|------------|---------|
| `/mnt` (volume root) | root:wheel 750 (since 2026-11-10, so `musicread` and `_navidrome` cannot enter) | – | – |
| `/mnt/MyMusic` | anthony:_navidrome 755 | nothing: an **old copy** from 2026-11-10, kept by choice (see its README) | – |
| `/mnt/private`, `/mnt/ytdl` | anthony:wheel 750 | `~/AKR/scripts/remote-sync` (Mac) | – |
| `/mnt/Movies` | anthony:wheel 700 | `remote-sync` | – |
| `/mnt/backups` | anthony:wheel 750 | – | – |
| `/mnt/backups/akr` | anthony 700 | the vault's `vcs-hooks/post-commit` (it documents the retention) | – |

**Create a new folder by hand, 750 or 700, before anything syncs into it.** A folder that
rsync creates takes mode 755 from the umask, so every account on the server can read it,
`musicread` included.

Traps:
- rsync is `/usr/local/bin/rsync`. Name it in full in `--rsync-path`, after the
  `crypt-mounted` check.
- OpenBSD `xargs` supports `-r`.
- `git bundle verify` needs a repository, and even with one it does not read the pack:
  it passes a truncated bundle. Check a bundle with `git bundle unbundle` into a
  throwaway bare repo. Put that repo on `/mnt`, not `/tmp`, because `unbundle` writes
  the objects out.

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
