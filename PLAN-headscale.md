# Headscale Setup Plan

Set up Headscale on OpenBSD VPS (Vultr) with Mac and other devices as clients.

## Architecture

```
[OpenBSD VPS] - Headscale control server (public IP)
       |
       +-- [Mac] - Client + exit node for home LAN
       +-- [Phone] - Client
       +-- [Other devices] - Clients
```

## Part 1: Headscale on OpenBSD VPS

### 1.1 Install Headscale
```sh
# OpenBSD has headscale in ports
pkg_add headscale
```

### 1.2 Configure Headscale
Create/edit `/etc/headscale/config.yaml`:
- Set `server_url` to VPS public IP or domain
- Configure `listen_addr: 0.0.0.0:8080`
- Set up database (SQLite default is fine)
- Configure DERP (can use Tailscale's public DERP servers)
- Set `ip_prefixes` for your mesh network (e.g., `100.64.0.0/10`)

### 1.3 Enable and Start Service
```sh
rcctl enable headscale
rcctl start headscale
```

### 1.4 Create User/Namespace
```sh
headscale users create anthony
```

### 1.5 Firewall (if pf enabled)
Allow incoming on port 8080 (or chosen port).

## Part 2: Mac as Client

### 2.1 Install Tailscale
```sh
brew install tailscale
```

Or download official macOS app from https://tailscale.com/download

### 2.2 Connect to Headscale
```sh
# Generate auth key on VPS first
headscale preauthkeys create --user anthony --reusable --expiration 24h

# On Mac, connect using the key
tailscale up --login-server=http://YOUR_VPS_IP:8080 --authkey=KEY
```

### 2.3 Configure as Exit Node (for home LAN access)
```sh
# On Mac
tailscale up --login-server=http://YOUR_VPS_IP:8080 --advertise-exit-node --advertise-routes=192.168.1.0/24
```

Then approve on server:
```sh
headscale routes enable -r ROUTE_ID
```

## Part 3: Other Devices

### iOS/Android
1. Install Tailscale app
2. Settings > "Use an alternate server"
3. Enter `http://YOUR_VPS_IP:8080`
4. Generate auth key and authenticate

### Linux
```sh
tailscale up --login-server=http://YOUR_VPS_IP:8080
```

## Part 4: HTTPS with Let's Encrypt (Recommended)

### 4.1 Point Domain to VPS
Add DNS A record: `hs.yourdomain.com` -> VPS IP

### 4.2 Configure acme-client on OpenBSD
Edit `/etc/acme-client.conf`:
```
authority letsencrypt {
    api url "https://acme-v02.api.letsencrypt.org/directory"
    account key "/etc/acme/letsencrypt-privkey.pem"
}

domain hs.yourdomain.com {
    domain key "/etc/ssl/private/hs.yourdomain.com.key"
    domain full chain certificate "/etc/ssl/hs.yourdomain.com.fullchain.pem"
    sign with letsencrypt
}
```

### 4.3 Get Certificate
```sh
# Temporarily allow HTTP for ACME challenge
acme-client -v hs.yourdomain.com
```

### 4.4 Update Headscale Config for TLS
In `/etc/headscale/config.yaml`:
```yaml
server_url: https://hs.yourdomain.com
listen_addr: 0.0.0.0:443
tls_cert_path: /etc/ssl/hs.yourdomain.com.fullchain.pem
tls_key_path: /etc/ssl/private/hs.yourdomain.com.key
```

### 4.5 Set Up Cert Renewal Cron
Add to root's crontab:
```
0 0 * * * acme-client hs.yourdomain.com && rcctl restart headscale
```

## Files to Create/Modify

| Location | File | Purpose |
|----------|------|---------|
| VPS | `/etc/headscale/config.yaml` | Headscale configuration |
| VPS | `/etc/acme-client.conf` | Let's Encrypt config |
| VPS | `/etc/pf.conf` | Firewall rules (allow 443) |
| Mac | n/a | Just install Tailscale client |

## Verification Steps

1. `headscale nodes list` - shows connected devices
2. `tailscale status` - shows mesh network status
3. `ping 100.64.x.x` - test connectivity between devices
4. Access home LAN device from phone to verify exit node

## Notes

- Headscale on OpenBSD should work but may require building from source if not in ports
- Alternative: Use Go binary from Headscale releases if pkg_add unavailable
- DERP servers: Start with Tailscale's public DERP, can self-host later if needed
