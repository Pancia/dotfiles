---
name: flet
description: Use this skill when building Python apps with Flet, creating cross-platform UIs, working with Flet controls (Page, Container, Row, Column, TextField, etc.), managing state, handling events, navigation/routing, theming, or deploying to desktop/mobile/web.
user-invocable: true
disable-model-invocation: false
---

# Flet Python UI Framework

Build cross-platform apps in Python with Flutter-powered UI.

## Version Awareness

**This skill documents Flet v0.80.5** (released January 30, 2026).

To check the user's installed version:
```bash
flet --version
flet doctor
uv pip show flet  # or: pip show flet
```

If the user's version differs significantly, warn them that APIs may have changed
and recommend checking [docs.flet.dev](https://docs.flet.dev/) for updates.

**Latest version:** https://pypi.org/project/flet/

## Official Documentation

| Resource | URL |
|----------|-----|
| Main Docs | https://docs.flet.dev/ |
| Getting Started | https://docs.flet.dev/getting-started/ |
| Installation | https://docs.flet.dev/getting-started/installation/ |
| Controls Reference | https://docs.flet.dev/controls/ |
| Cookbook | https://docs.flet.dev/cookbook/ |
| PyPI | https://pypi.org/project/flet/ |
| GitHub | https://github.com/flet-dev/flet |

## Requirements

- **Python:** >=3.10
- **Platforms:** macOS 12+, Windows 10/11 64-bit, Debian 10-12, Ubuntu 20.04-24.04

## Quick Start

```bash
# Install with uv (recommended)
uv add 'flet[all]'

# Or with pip
pip install 'flet[all]'

# Verify installation
flet --version
flet doctor

# Create a new project
flet create myapp
cd myapp

# Run in development
flet run main.py
```

## Minimal Example

```python
import flet as ft

def main(page: ft.Page):
    page.title = "Hello Flet"

    counter = ft.Text("0", size=50)

    def increment(e):
        counter.value = str(int(counter.value) + 1)
        page.update()  # Required after state changes!

    page.add(
        ft.Column([
            counter,
            ft.ElevatedButton("Increment", on_click=increment),
        ], alignment=ft.MainAxisAlignment.CENTER)
    )

ft.app(main)
```

## Core Concepts

### Page (Root Control)
Every Flet app has a `Page` as the root. Key properties:
- `page.title` - window title
- `page.theme_mode` - `"light"`, `"dark"`, or `"system"`
- `page.route` - current URL route
- `page.update()` - refresh UI after state changes

### Control Hierarchy
Controls are arranged in a tree:
- `Page` contains top-level controls
- Layout controls (Row, Column, Container) organize children
- Each control has properties and optional event handlers

### Event-Driven Model
- Attach handlers to control events: `on_click`, `on_change`, `on_submit`
- Handlers can be sync or async
- Always call `page.update()` after modifying control properties

### Cross-Platform
Same codebase runs on:
- **Desktop:** Windows, macOS, Linux
- **Mobile:** iOS, Android
- **Web:** Browser (Pyodide)

## Control Categories

### Layout
- `Page` - root control
- `Container` - single child with styling (bgcolor, padding, border_radius)
- `Row` / `Column` - horizontal/vertical layouts
- `Stack` - overlapping children
- `ResponsiveRow` - breakpoint-based responsive layout
- `ListView` / `GridView` - scrollable lists

### Input
- `TextField` - text input (multiline, password, validation)
- `Dropdown` / `SearchBar` / `AutoComplete` - selection controls
- `Checkbox` / `Radio` / `Switch` - toggles
- `Slider` / `RangeSlider` - value selectors
- `DatePicker` / `TimePicker` - date/time input

### Navigation
- `AppBar` / `BottomAppBar` - app bars
- `NavigationBar` / `NavigationDrawer` / `NavigationRail` - navigation
- `Tabs` - tabbed interface
- `View` - route-based views

### Display
- `Text` / `Icon` / `Image` / `Markdown` - content display
- `DataTable` / `ListTile` / `Card` - data presentation
- `BarChart` / `LineChart` / `PieChart` - charts
- `ProgressBar` / `ProgressRing` - loading indicators

### Dialogs & Overlays
- `AlertDialog` / `BottomSheet` / `SnackBar` - notifications
- `PopupMenuButton` / `ContextMenu` - menus

### Gestures
- `GestureDetector` - tap, double-tap, long-press, pan, scale events
- `Draggable` / `DragTarget` - drag and drop

## Common Patterns

### Async Event Handler
```python
async def fetch_data(e):
    page.splash = ft.ProgressBar()
    page.update()

    result = await some_api_call()

    page.splash = None
    data_text.value = result
    page.update()
```

### Background Task
```python
def start_background_task(e):
    page.run_task(long_running_operation)

async def long_running_operation():
    await asyncio.sleep(5)
    status.value = "Done!"
    page.update()
```

### Custom Component (UserControl)
```python
class Counter(ft.UserControl):
    def __init__(self):
        super().__init__()
        self.count = 0

    def build(self):
        self.text = ft.Text(str(self.count))
        return ft.Row([
            ft.IconButton(ft.Icons.REMOVE, on_click=self.decrement),
            self.text,
            ft.IconButton(ft.Icons.ADD, on_click=self.increment),
        ])

    def increment(self, e):
        self.count += 1
        self.text.value = str(self.count)
        self.update()

    def decrement(self, e):
        self.count -= 1
        self.text.value = str(self.count)
        self.update()
```

### Simple Routing
```python
def main(page: ft.Page):
    def route_change(e):
        page.views.clear()
        if page.route == "/":
            page.views.append(home_view())
        elif page.route == "/settings":
            page.views.append(settings_view())
        page.update()

    page.on_route_change = route_change
    page.go("/")
```

## Common Pitfalls

1. **Forgetting `page.update()`**
   - After changing any control property, call `page.update()`
   - For UserControl, call `self.update()`

2. **Blocking the Main Thread**
   - Use `async` handlers or `page.run_task()` for long operations
   - Never use `time.sleep()` in handlers

3. **Incorrect Event Handler Signature**
   - Handlers receive an event object: `def handler(e):`
   - Access control via `e.control`, page via `e.page`

4. **Not Cleaning Up Resources**
   - Override `will_unmount()` in UserControl to stop timers, close connections

5. **Control Not Attached to Page**
   - Controls must be added to page before calling `update()`
   - Use `control.page` to check if attached

## Development Commands

```bash
# Run desktop app
flet run main.py

# Run in web browser
flet run --web main.py

# Hot reload (default)
flet run -r main.py

# Build for platforms
flet build macos
flet build windows
flet build linux
flet build apk      # Android
flet build ipa      # iOS
flet build web
```

## Reference Files

- [controls.md](references/controls.md) - Complete controls reference
- [state-and-events.md](references/state-and-events.md) - State management and event handling
- [navigation.md](references/navigation.md) - Routing and navigation patterns
- [theming.md](references/theming.md) - Themes, colors, and fonts
- [deployment.md](references/deployment.md) - Building for desktop, mobile, and web
