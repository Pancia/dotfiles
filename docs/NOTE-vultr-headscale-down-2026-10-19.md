# Vultr / headscale down (noticed 2026-10-19)

## What's wrong
- `hs.anthonydambrosio.me` resolves to 144.202.100.108, but the box does not respond:
  ping 100% loss, ports 22 and 443 closed, HTTPS request times out.
- Tailscale on the Mac reports "logged out" (cannot fetch control key from headscale).
- Phone cannot join the tailnet either.

## To do
- Check the Vultr dashboard: instance stopped? suspended for billing? IP changed?
- Reboot it, or if the IP changed, update the DNS record.
- Then confirm with `tailscale status` on the Mac.

## Syncthing changes made the same night (Mac side)
- Turned OFF: global discovery, relays, NAT port-mapping (via REST API).
- Local discovery still ON, so sync works over the Mac's Internet Sharing Wi-Fi (bridge100, 192.168.2.x).
- Mobile-data sync does not work for now.
- Once Tailscale is back: add the Mac's tailnet address to the phone's Syncthing
  (`tcp://100.x.x.x:22000`) so it syncs over Tailscale instead of public servers.
- To undo: 127.0.0.1:8384 -> Actions -> Settings -> Connections.

## Syncthing folders (for reference)
- Android Bin: ~/dotfiles/android/bin (active)
- android-media: ~/ProtonDrive/Media/Android (active, this is what reaches the phone)
- music: /Volumes/vansuny128/music-db (PAUSED, drive not mounted)
