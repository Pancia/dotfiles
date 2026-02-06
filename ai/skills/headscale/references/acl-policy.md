# Headscale ACL Policy Reference

## File Location

`/etc/headscale/acl.hujson` on VPS.

Referenced in `/etc/headscale/config.yaml`:

```yaml
policy:
  mode: file
  path: "/etc/headscale/acl.hujson"
```

## Syntax (Headscale v0.26.1)

HuJSON format (JSON with comments and trailing commas).

### User References

Users MUST have `@` appended:

```
"anthony@"     # correct
"anthony"      # WRONG - treated as a host, fails validation
```

### Autogroups

Only `autogroup:internet` is supported in v0.26.1. `autogroup:member`, `autogroup:self`, etc. are NOT available.

### Groups

Define groups to reference users:

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

### Destination Format

- `"group:name:*"` - all ports
- `"group:name:22"` - specific port
- `"group:name:80,443"` - multiple ports

### Tags

Tags can be used for device-level access control:

```json
{
  "tagOwners": {
    "tag:server": ["group:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["group:admin"],
      "dst": ["tag:server:22,443"]
    }
  ]
}
```

## Validation

ALWAYS validate before applying:

```sh
doas headscale policy check --file /etc/headscale/acl.hujson
```

If headscale fails to start with a bad policy, it gives a fatal error and exits. The `rcctl restart` will show `(failed)` but won't tell you why. To see the actual error:

```sh
doas timeout 5 headscale serve 2>&1
```

## Applying Changes

```sh
# Validate first
doas headscale policy check --file /etc/headscale/acl.hujson

# Then restart
doas rcctl restart headscale

# Verify
doas headscale policy get
```

## Rollback

To disable ACL policy entirely (back to default allow-all):

```sh
doas sed -i 's|path: "/etc/headscale/acl.hujson"|path: ""|' /etc/headscale/config.yaml
doas rcctl restart headscale
```
