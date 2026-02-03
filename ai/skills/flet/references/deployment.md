# Flet Deployment

## Project Setup

### Create New Project

```bash
# Create a new Flet project
flet create myapp
cd myapp

# Project structure:
# myapp/
# ├── main.py          # Entry point
# ├── assets/          # Static files (images, fonts)
# └── requirements.txt # Dependencies
```

### Dependencies

```bash
# Install Flet with all extras (recommended)
uv add 'flet[all]'

# Or specific targets
uv add flet                    # Core only
uv add 'flet[desktop]'         # Desktop support
uv add 'flet[mobile]'          # Mobile support
uv add 'flet[web]'             # Web support

# With pip
pip install 'flet[all]'
```

## Development

### Run App

```bash
# Desktop (default)
flet run main.py

# Web browser
flet run --web main.py

# With hot reload (default behavior)
flet run -r main.py

# Specific port for web
flet run --web --port 8080 main.py

# Debug mode (verbose output)
flet run -d main.py
```

### Project Diagnostics

```bash
# Check Flet installation and environment
flet doctor
```

## Desktop Build

### macOS

```bash
# Build macOS app bundle
flet build macos

# Output: build/macos/myapp.app

# With custom icon
flet build macos --icon assets/icon.icns

# Custom app name
flet build macos --name "My Application"

# Custom bundle ID
flet build macos --bundle-id com.example.myapp
```

### Windows

```bash
# Build Windows executable
flet build windows

# Output: build/windows/myapp.exe

# With custom icon
flet build windows --icon assets/icon.ico

# Custom app name
flet build windows --name "My Application"
```

### Linux

```bash
# Build Linux executable
flet build linux

# Output: build/linux/myapp
```

### Common Desktop Options

```bash
flet build macos \
  --name "My App" \
  --icon assets/icon.icns \
  --version "1.0.0" \
  --build-number 1 \
  --copyright "Copyright 2026 Example Inc."
```

## Mobile Build

### Android

```bash
# Build Android APK (for testing/sideloading)
flet build apk

# Output: build/apk/myapp.apk

# Build Android App Bundle (for Play Store)
flet build aab

# Output: build/aab/myapp.aab
```

### Android Options

```bash
flet build apk \
  --name "My App" \
  --icon assets/icon.png \           # 1024x1024 PNG
  --version "1.0.0" \
  --build-number 1 \
  --package-name com.example.myapp \
  --splash-color "#FFFFFF" \
  --splash-image assets/splash.png
```

### iOS

```bash
# Build iOS IPA
flet build ipa

# Output: build/ipa/myapp.ipa
```

### iOS Options

```bash
flet build ipa \
  --name "My App" \
  --icon assets/icon.png \           # 1024x1024 PNG
  --version "1.0.0" \
  --build-number 1 \
  --bundle-id com.example.myapp \
  --splash-color "#FFFFFF" \
  --team-id XXXXXXXXXX               # Apple Developer Team ID
```

### Mobile Requirements

**Android:**
- Android SDK installed
- `ANDROID_HOME` environment variable set
- Minimum SDK: 21 (Android 5.0)

**iOS:**
- macOS with Xcode installed
- Apple Developer account (for device testing/distribution)
- CocoaPods installed

## Web Build

### Build for Production

```bash
# Build static web files
flet build web

# Output: build/web/
# ├── index.html
# ├── main.py
# ├── flutter.js
# └── ...
```

### Web Options

```bash
flet build web \
  --base-url "/myapp/" \             # For subdirectory deployment
  --web-renderer canvaskit \         # canvaskit (default) or html
  --route-url-strategy path          # path or hash
```

### Hosting

Deploy `build/web/` to any static hosting:

**Vercel / Netlify / GitHub Pages:**
```bash
# Simply upload build/web/ directory
```

**Nginx:**
```nginx
server {
    listen 80;
    server_name myapp.example.com;
    root /var/www/myapp;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Pyodide (Browser-Only)

Flet web apps run entirely in the browser using Pyodide:
- No server required for Python execution
- Python runs in WebAssembly
- Some Python packages may not be available

## Assets

### Include Static Files

```
myapp/
├── main.py
├── assets/
│   ├── images/
│   │   └── logo.png
│   ├── fonts/
│   │   └── custom.ttf
│   └── data/
│       └── config.json
```

Access in code:
```python
ft.Image(src="assets/images/logo.png")

page.fonts = {
    "Custom": "assets/fonts/custom.ttf",
}
```

### Asset Configuration

```bash
# Include specific asset directories
flet build macos --assets assets/images,assets/fonts
```

## Environment Variables

```python
import os

# Access environment variables
api_key = os.environ.get("API_KEY", "default")

# In development, use .env files
# In production, configure via hosting platform
```

## Build Configuration File

Create `flet.toml` for persistent configuration:

```toml
[project]
name = "My App"
version = "1.0.0"
description = "A Flet application"

[build]
icon = "assets/icon.png"
splash_color = "#FFFFFF"

[build.macos]
bundle_id = "com.example.myapp"

[build.android]
package_name = "com.example.myapp"
min_sdk_version = 21

[build.ios]
bundle_id = "com.example.myapp"
team_id = "XXXXXXXXXX"

[build.web]
base_url = "/"
web_renderer = "canvaskit"
```

## Troubleshooting

### Common Issues

**Build fails with missing SDK:**
```bash
# Check Flutter/Dart SDK
flutter doctor

# Install if missing
# macOS: brew install flutter
# Or download from flutter.dev
```

**Mobile build signing issues:**
```bash
# Android: Ensure keystore is configured
# iOS: Check provisioning profiles in Xcode
```

**Web assets not loading:**
```python
# Use relative paths for assets
ft.Image(src="assets/logo.png")  # Correct
ft.Image(src="/assets/logo.png")  # May fail
```

**Large build size:**
```bash
# Use tree-shaking (automatic)
# Remove unused dependencies
# Compress assets
```

### Build Logs

```bash
# Verbose build output
flet build macos -v

# Debug mode
flet build macos -d
```
