# current-space

A lightweight C utility to get the current macOS Mission Control space number.

## Architecture

This is a two-part solution:

1. **C Binary** (`lib/c/current-space/current-space`) - Fast, low-level binary that queries the current space ID using private CoreGraphics APIs
2. **Shell Wrapper** (`bin/current-space`) - Bash script that calls the C binary and maps the ID to the correct Mission Control space number by parsing `~/Library/Preferences/com.apple.spaces.plist`

This separation keeps the C code simple and fast while handling the complexity of Mission Control ordering in the shell wrapper.

## Building

```bash
# Build the C binary
make
```

## Usage

```bash
# Get current space number (use the wrapper)
current-space
# Output: 6

# Or get raw space ID (use C binary directly)
lib/c/current-space/current-space
# Output: 12
```

## How It Works

### C Binary
1. Connects to the macOS window server via `_CGSDefaultConnection()`
2. Gets the current active space ID using `CGSGetActiveSpace()`
3. Returns the space ID

### Shell Wrapper
1. Calls the C binary to get the current space ID
2. Parses `~/Library/Preferences/com.apple.spaces.plist` to get spaces in Mission Control order
3. Finds the index of the current space ID in that ordered list
4. Returns the 1-indexed space number

**Why two parts?** `CGSCopySpaces()` returns spaces in creation order, not Mission Control display order. The plist file contains the correct ordering, so we parse it in the wrapper.

## Technical Details

### Private APIs Used

- `_CGSDefaultConnection()` - Get connection to window server
- `CGSGetActiveSpace(cid)` - Get active space ID

These are private APIs from the CoreGraphics Services (CGS) framework. They are not officially documented by Apple and may change in future macOS versions.

### Requirements

- macOS (tested on macOS 10.15+)
- Xcode Command Line Tools (for `clang` compiler)
- No special permissions or SIP disabling required

### Limitations

- May not work correctly with fullscreen app spaces (they use different space IDs)
- Currently only supports the main display (multi-monitor support could be added)
- Uses undocumented APIs that could break in future macOS updates

## Integration Examples

### Shell Scripts

```bash
#!/bin/bash
current=$(current-space)
echo "You are on space $current"

# Conditional logic based on space
if [ "$current" -eq 1 ]; then
    echo "On main workspace"
fi
```

### Karabiner Integration

Use with Karabiner-Elements to create space-aware keyboard shortcuts.

### Status Bar Display

Parse the JSON output to show current space in a status bar (e.g., with BitBar/SwiftBar).

## Development

```bash
# Build
make

# Test locally
./current-space -v

# Install to bin/
make install

# Clean build artifacts
make clean
```

## License

Part of personal dotfiles. Use at your own risk.

## See Also

- [yabai](https://github.com/koekeishiya/yabai) - Full-featured tiling window manager that uses similar APIs
- [NUIKit/CGSInternal](https://github.com/NUIKit/CGSInternal) - Private CoreGraphics API headers
