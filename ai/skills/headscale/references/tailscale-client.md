# Tailscale Client Reference

## Version

v1.92.3 installed via Homebrew (`brew install tailscale`).

Service managed by: `sudo brew services start tailscale`

## Preferences via LocalAPI

Some preferences are not exposed as CLI flags (removed in newer versions but the prefs still exist). Use the LocalAPI to manage them.

### Reading Preferences

```sh
tailscale debug prefs
```

### Setting Preferences

Use `PATCH /localapi/v0/prefs` with a JSON body. Include the `*Set` mask field to force the update:

```sh
# Enable stateful filtering (NoStatefulFiltering = false means filtering IS on)
tailscale debug localapi PATCH /localapi/v0/prefs \
  '{"NoStatefulFilteringSet": true, "NoStatefulFiltering": false}'
```

The mask field (`NoStatefulFilteringSet`) is required. Without it, the PATCH is silently ignored.

### Key Preferences

| Preference | Meaning when `true` | Set via |
|------------|---------------------|---------|
| `NoStatefulFiltering` | Stateful filtering DISABLED (bad) | LocalAPI only (v1.92.3) |
| `NoSNAT` | SNAT disabled for subnet routes | `tailscale set --snat-subnet-routes` |
| `ShieldsUp` | Block all incoming connections | `tailscale set --shields-up` |
| `RouteAll` | Accept all advertised routes | `tailscale set --accept-routes` |
| `CorpDNS` | Accept DNS config from server | `tailscale set --accept-dns` |

## Common Commands

```sh
# Status
tailscale status

# Network check
tailscale netcheck

# Ping a peer
tailscale ping HOSTNAME

# Debug: see DERP map
tailscale debug derp-map

# Debug: see control knobs
tailscale debug control-knobs

# Disconnect
tailscale down

# Reconnect
tailscale up
```

## Log File

`/opt/homebrew/var/log/tailscaled.log`

Rotated by newsyslog at 5MB, 5 compressed backups kept (`/etc/newsyslog.d/tailscaled.conf`).

## macOS Firewall

The macOS application firewall must allow tailscaled incoming connections. When enabling the firewall (`socketfilterfw --setglobalstate on`), a dialog will prompt to allow tailscaled. Click Allow.

```sh
# Check firewall state
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Enable
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```
