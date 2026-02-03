# Flet State Management and Events

## State Management

### Basic Pattern

Flet uses a simple state management pattern: modify control properties, then call `update()`.

```python
import flet as ft

def main(page: ft.Page):
    # State is stored in control properties
    counter = ft.Text("0", size=50)

    def increment(e):
        # Modify the control property
        counter.value = str(int(counter.value) + 1)
        # Update the UI
        page.update()

    page.add(counter, ft.ElevatedButton("Add", on_click=increment))

ft.app(main)
```

### Update Scope

- `page.update()` - updates all controls on the page
- `control.update()` - updates only that control and its descendants (more efficient)

```python
def increment(e):
    counter.value = str(int(counter.value) + 1)
    counter.update()  # Only update the counter, not the whole page
```

### Storing State in Class

For complex apps, store state in a class:

```python
class AppState:
    def __init__(self):
        self.count = 0
        self.items = []

def main(page: ft.Page):
    state = AppState()
    counter = ft.Text("0")

    def increment(e):
        state.count += 1
        counter.value = str(state.count)
        page.update()

    page.add(counter, ft.ElevatedButton("Add", on_click=increment))
```

### Third-Party State Management

For larger applications, consider:
- **Neostate** - Redux-like state management
- **FletX** - MVC-style architecture

## Event Handling

### Event Handler Signatures

Handlers receive an event object with context:

```python
# Sync handler
def handle_click(e):
    print(f"Control: {e.control}")
    print(f"Page: {e.page}")
    print(f"Data: {e.data}")

# Async handler
async def handle_click_async(e):
    await asyncio.sleep(1)
    e.control.text = "Clicked!"
    e.page.update()
```

### Common Events

| Event | Controls | Event Object Properties |
|-------|----------|------------------------|
| `on_click` | Button, Container, etc. | `control`, `page` |
| `on_change` | TextField, Dropdown, etc. | `control`, `data` (new value) |
| `on_submit` | TextField | `control`, `data` |
| `on_focus` | TextField, etc. | `control` |
| `on_blur` | TextField, etc. | `control` |
| `on_hover` | Container, etc. | `control`, `data` (True/False) |

### TextField Events

```python
ft.TextField(
    on_change=lambda e: print(f"Changed: {e.control.value}"),
    on_submit=lambda e: print(f"Submitted: {e.control.value}"),
    on_focus=lambda e: print("Focused"),
    on_blur=lambda e: print("Blurred"),
)
```

### Gesture Events

```python
ft.GestureDetector(
    content=ft.Container(bgcolor=ft.Colors.AMBER, width=100, height=100),
    on_tap=lambda e: print("tap"),
    on_tap_down=lambda e: print(f"tap down at {e.local_x}, {e.local_y}"),
    on_tap_up=lambda e: print("tap up"),
    on_double_tap=lambda e: print("double tap"),
    on_long_press_start=lambda e: print("long press start"),
    on_long_press_end=lambda e: print("long press end"),
    on_secondary_tap=lambda e: print("right click"),
    on_pan_start=lambda e: print(f"pan start at {e.local_x}, {e.local_y}"),
    on_pan_update=lambda e: print(f"pan delta: {e.delta_x}, {e.delta_y}"),
    on_pan_end=lambda e: print(f"pan velocity: {e.velocity_x}, {e.velocity_y}"),
    on_scale_start=lambda e: print("scale start"),
    on_scale_update=lambda e: print(f"scale: {e.scale}, rotation: {e.rotation}"),
    on_scale_end=lambda e: print("scale end"),
    drag_interval=50,  # Throttle pan/scale events (milliseconds)
)
```

### Keyboard Events

```python
def main(page: ft.Page):
    def on_keyboard(e: ft.KeyboardEvent):
        print(f"Key: {e.key}, Ctrl: {e.ctrl}, Shift: {e.shift}, Alt: {e.alt}")
        if e.key == "Escape":
            page.window.close()

    page.on_keyboard_event = on_keyboard
```

## Async Operations

### Async Event Handlers

Mix sync and async handlers freely:

```python
import asyncio

async def fetch_data(e):
    # Show loading state
    loading.visible = True
    page.update()

    # Async operation
    await asyncio.sleep(2)  # Simulate API call

    # Update UI
    loading.visible = False
    result.value = "Data loaded!"
    page.update()

button = ft.ElevatedButton("Load", on_click=fetch_data)
```

### Background Tasks with page.run_task()

For operations that shouldn't block the UI thread:

```python
async def long_running_task():
    for i in range(10):
        await asyncio.sleep(1)
        progress.value = (i + 1) / 10
        progress.update()
    status.value = "Complete!"
    status.update()

def start_task(e):
    page.run_task(long_running_task)

button = ft.ElevatedButton("Start", on_click=start_task)
```

### Cancellable Tasks

```python
current_task = None

async def cancellable_operation():
    try:
        for i in range(100):
            await asyncio.sleep(0.1)
            progress.value = i / 100
            progress.update()
    except asyncio.CancelledError:
        status.value = "Cancelled!"
        status.update()

def start(e):
    global current_task
    current_task = page.run_task(cancellable_operation)

def cancel(e):
    if current_task:
        current_task.cancel()
```

## Component Lifecycle

### UserControl Lifecycle Methods

```python
class MyComponent(ft.UserControl):
    def __init__(self):
        super().__init__()
        self.timer = None

    def build(self):
        """Called when control is created and assigned to a page.
        Return the control tree to render."""
        self.text = ft.Text("Hello")
        return ft.Container(content=self.text)

    def did_mount(self):
        """Called after control is added to page.
        Use for API calls, starting timers, subscriptions."""
        self.timer = page.run_task(self.update_clock)

    def will_unmount(self):
        """Called before control is removed from page.
        Use for cleanup: stop timers, close connections."""
        if self.timer:
            self.timer.cancel()

    async def update_clock(self):
        while True:
            self.text.value = datetime.now().strftime("%H:%M:%S")
            self.update()
            await asyncio.sleep(1)
```

### Lifecycle Order

1. `__init__()` - Constructor
2. `build()` - Called when control gets a page reference
3. `did_mount()` - Called after added to visible page
4. (control is visible and interactive)
5. `will_unmount()` - Called before removal from page

## Custom Components (UserControl)

### Basic UserControl

```python
class Counter(ft.UserControl):
    def __init__(self, initial=0):
        super().__init__()
        self.count = initial

    def build(self):
        self.text = ft.Text(str(self.count), size=30)
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

# Usage
page.add(Counter(initial=10))
```

### Styled Control (Single Control Inheritance)

For controls that wrap a single existing control:

```python
class PrimaryButton(ft.ElevatedButton):
    def __init__(self, text, on_click=None):
        super().__init__(
            text=text,
            on_click=on_click,
            style=ft.ButtonStyle(
                color=ft.Colors.WHITE,
                bgcolor=ft.Colors.BLUE_700,
            ),
        )
```

### Composite Control

For complex controls with multiple children:

```python
class SearchBox(ft.UserControl):
    def __init__(self, on_search=None):
        super().__init__()
        self.on_search = on_search

    def build(self):
        self.text_field = ft.TextField(
            hint_text="Search...",
            expand=True,
            on_submit=self.handle_search,
        )
        return ft.Row([
            self.text_field,
            ft.IconButton(ft.Icons.SEARCH, on_click=self.handle_search),
        ])

    def handle_search(self, e):
        if self.on_search:
            self.on_search(self.text_field.value)

# Usage
def search(query):
    print(f"Searching for: {query}")

page.add(SearchBox(on_search=search))
```

### Control with External State Updates

```python
class StatusDisplay(ft.UserControl):
    def __init__(self):
        super().__init__()
        self._status = "Ready"

    @property
    def status(self):
        return self._status

    @status.setter
    def status(self, value):
        self._status = value
        if hasattr(self, 'text'):  # Check if built
            self.text.value = value
            self.update()

    def build(self):
        self.text = ft.Text(self._status)
        return self.text

# Usage
status = StatusDisplay()
page.add(status)
status.status = "Loading..."  # Updates UI automatically
```
