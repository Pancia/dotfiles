# pf Firewall Reference (OpenBSD VPS)

## Current Rules

`/etc/pf.conf`:

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

## Key Points

- `set skip on lo` means localhost traffic (relayd -> headscale on 8080) is unfiltered
- Headscale listens on `0.0.0.0:8080` but pf blocks external access to it
- Only SSH (22), HTTP (80), and HTTPS (443) are reachable from outside

## Management

```sh
# Reload rules
doas pfctl -f /etc/pf.conf

# Show active rules
doas pfctl -sr

# Show state table (active connections)
doas pfctl -ss

# Show statistics
doas pfctl -si
```

## Testing from Mac

```sh
# Should succeed (allowed ports)
nc -zv -G 3 144.202.100.108 22
nc -zv -G 3 144.202.100.108 443

# Should be refused (blocked)
nc -zv -G 3 144.202.100.108 8080
nc -zv -G 3 144.202.100.108 9090
```

## Safety

Backup at `/etc/pf.conf.bak` on VPS. If SSH is locked out, use Vultr console access.

Before changing rules, always verify port 22 is in the `pass in` list.
