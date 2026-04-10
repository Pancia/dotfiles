# PLAN: Proton Drive → USB backup via rclone

## Context

Currently rsync-ing files from the local Proton Drive folder (`~/Proton Drive/`)
to an external USB drive. Problem: Proton Drive for macOS uses on-demand sync
via the File Provider API — touching a file (which rsync does by reading every
byte) materializes it into the **local** cache on the internal disk.

Proton Drive does **not** automatically reclaim that space. macOS *may* evict
cold cached files when the disk is under pressure, but it's opportunistic and
unreliable. For a multi-TB export, the internal disk will fill up long before
rsync finishes.

## Goal

Migrate the backup pipeline off `rsync ~/Proton Drive/` and onto `rclone` with
the native `protondrive` backend, so bytes flow directly from Proton's API to
the USB drive without ever landing in the local File Provider cache.

## Security posture

This tool will hold **Proton credentials + auth tokens** on disk and will
decrypt end-to-end encrypted data client-side. That makes it a high-trust
binary — we do **not** want to install it from Homebrew where the supply
chain is opaque and updates land silently.

Instead: install via the project's own `vendor` system (`bin/vendor`, Go CLI,
`vendor/MANIFEST.json`). This gives us:

- A pinned commit SHA — not a moving tag, not a brew bottle.
- `last_reviewed` / `reviewed_by` metadata in `MANIFEST.json` — an explicit
  human audit trail before each update lands.
- Weekly update check via `fish/conf.d/vendor_check.fish` that surfaces new
  upstream releases but **doesn't apply them** without `vendor approve`.
- Local build from source, symlinked into `~/.local/bin/rclone`, so PATH
  resolution is predictable and we're not running a third-party bottle.

## Current pipeline (bad)

```
Proton cloud → Proton Drive.app → macOS File Provider cache (internal SSD) → rsync → USB
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                  Fills up, no auto-reclaim
```

## Target pipeline

```
Proton cloud → rclone (streams, no disk cache) → USB
```

## Steps

### 1. Salvage the in-flight rsync

- [ ] Let the current rsync finish whatever file/folder it's on (don't
      interrupt mid-file or you'll have a corrupt partial on the USB).
- [ ] Note which top-level folders have been fully copied already — skip them
      in the rclone run.
- [ ] Reclaim local cache space: in Finder, right-click the completed
      folders inside `~/Proton Drive/` → **"Remove Download" / "Online Only"**.
- [ ] Verify internal disk has headroom again: `df -h /`.

### 2. Install rclone via the vendor system

rclone is Go, so the build step is `go build` against the `./` module root.
Upstream is `https://github.com/rclone/rclone`.

- [ ] Pick a specific upstream release tag to pin (check
      https://github.com/rclone/rclone/releases for the latest stable, e.g.
      `v1.68.2` or newer — must be ≥ 1.66 for a non-buggy `protondrive`
      backend).
- [ ] Register with the vendor CLI:
      ```
      vendor add rclone https://github.com/rclone/rclone.git --ref vX.Y.Z
      ```
- [ ] **Manually review the checkout** before building. At minimum:
  - `cd ~/dotfiles/vendor/rclone && git log vX.Y.Z` — sanity check tag
    points where GitHub says it does.
  - Skim `backend/protondrive/` for anything alarming (this is the code
    path we actually care about).
  - Skim `go.sum` / `go.mod` for unexpected dependencies.
  - Cross-reference against upstream release notes.
- [ ] Edit `vendor/MANIFEST.json` for the `rclone` entry to set:
  - `install`: `go build -trimpath -ldflags="-s -w" -o rclone .`
  - `link_binary`: `rclone`
  - `link_to`: `~/.local/bin/rclone`
  - `audit.watch_patterns`: `["backend/protondrive/*.go", "go.mod", "go.sum", "fs/**/*.go"]`
  - `audit.ignore_patterns`: `["docs/*", "cmd/serve/**/*_test.go"]`
  - `notes`: short rationale ("used for direct-to-USB Proton Drive backup,
    holds Proton credentials, review carefully on updates").
- [ ] Build + install:
      ```
      vendor build rclone
      vendor install rclone
      ```
- [ ] `vendor approve rclone` — sets `last_reviewed` / `reviewed_by` to lock
      in the current state as trusted.
- [ ] Confirm: `which rclone` → `~/.local/bin/rclone`, `rclone version` shows
      the pinned tag and a build timestamp (not a brew bottle hash).
- [ ] Commit the `vendor/MANIFEST.json` change to jj
      (`vendor/rclone/` itself stays gitignored — only the manifest is
      tracked).

### 3. Configure the `proton:` remote

- [ ] `rclone config`
  - `n` (new remote)
  - name: `proton`
  - storage: `protondrive`
  - username / password / 2FA / mailbox password as prompted
- [ ] Confirm the entry in `~/.config/rclone/rclone.conf`.
- [ ] Smoke test: `rclone lsd proton:` — should list top-level folders.
- [ ] Smoke test: `rclone ls proton:SomeSmallFolder | head` — should list files.

### 4. Dry-run the copy

- [ ] Pick a small subfolder first to validate end-to-end:
      ```
      rclone copy proton:SmallFolder /Volumes/USB/proton-backup/SmallFolder \
          --dry-run -P
      ```
- [ ] Review the plan, confirm nothing unexpected.
- [ ] Run for real without `--dry-run`, verify files land on USB and hashes
      are sensible (`rclone check` against source).

### 5. Full backup run

- [ ] Kick off the top-level copy:
      ```
      rclone copy proton: /Volumes/USB/proton-backup \
          -P \
          --transfers 4 \
          --log-file=$HOME/.local/state/log/rclone-proton-backup.log \
          --log-level INFO
      ```
- [ ] Consider `--bwlimit 10M` if the uplink needs to stay usable during the
      copy (Proton + encryption can saturate CPU/network).
- [ ] `rclone copy` is resumable — safe to Ctrl+C and re-run; skips files
      already present with matching size+mtime.
- [ ] If extra paranoia warranted: re-run with `--checksum` to verify by hash
      instead of size+mtime.

### 6. Verify

- [ ] `rclone check proton: /Volumes/USB/proton-backup` — compares both sides,
      flags missing / differing files.
- [ ] Spot-check a handful of large / important files manually (open, hash,
      eyeball).
- [ ] Keep `rclone-proton-backup.log` for auditing.

### 7. Cleanup

- [ ] Once USB backup is verified, decide whether to keep the Proton Drive
      macOS app installed or not.
- [ ] If keeping: mark bulk folders as **Online Only** so they don't rehydrate
      into the local cache on next access.
- [ ] If removing: uninstall Proton Drive.app, delete `~/Proton Drive/`
      placeholder folder, revoke the app's File Provider extension in System
      Settings → General → Login Items & Extensions → File Provider.

## Caveats & gotchas

- **Supply chain** — by vendoring from source with a pinned commit, we're
  trading convenience for auditability. Updates require running
  `vendor build rclone` + review + `vendor approve rclone` — do **not**
  blind-approve. The weekly `vendor_check` notification is a prompt to look,
  not a command to apply.
- **`protondrive` backend is marked experimental** in rclone docs. Works well
  for most cases, but historically edge cases around very large files and
  deeply nested trees. Always keep the log file and run `rclone check`.
- **2FA auth** — interactive prompt during `rclone config`; have the OTP
  device ready.
- **Client-side encryption** — Proton decrypts client-side, so CPU (not
  network) may be the bottleneck on bulk transfers. `--transfers 4` is a
  reasonable default; bump up only if CPU has headroom.
- **No symlinks** — Proton Drive doesn't store symlinks. If any existed in
  the source, note them separately.
- **Filename edge cases** — colons, trailing dots, reserved names. `rclone`
  will warn; decide per-case.
- **USB filesystem** — if the USB is exFAT or FAT32, watch out for the 4 GiB
  file size cap and loss of POSIX permissions/timestamps. HFS+ or APFS
  preferred for a backup target.

## Open questions

- [ ] How big is the Proton Drive dataset total? (`rclone size proton:` will
      answer this once configured.)
- [ ] Is the USB drive large enough + formatted appropriately?
- [ ] One-shot backup, or should this become a recurring job (LaunchAgent +
      `rclone sync` with `--backup-dir` for versioning)?

## References

- [rclone protondrive backend](https://rclone.org/protondrive/)
- [rclone copy](https://rclone.org/commands/rclone_copy/)
- [rclone check](https://rclone.org/commands/rclone_check/)
- [Proton Drive on-demand sync (macOS)](https://proton.me/support/proton-drive-macos-on-demand-sync)
