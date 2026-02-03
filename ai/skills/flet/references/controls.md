# Flet Controls Reference

Complete reference for Flet controls. See https://docs.flet.dev/controls/ for full documentation.

## Layout Controls

### Page (Root Control)

The root of every Flet app. All other controls are descendants of Page.

```python
def main(page: ft.Page):
    page.title = "My App"
    page.theme_mode = ft.ThemeMode.DARK  # or "dark", "light", "system"
    page.vertical_alignment = ft.MainAxisAlignment.CENTER
    page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
    page.padding = 20
    page.scroll = ft.ScrollMode.AUTO
    page.bgcolor = ft.Colors.BLUE_GREY_900

    # Add controls
    page.add(ft.Text("Hello"))

    # Or set controls directly
    page.controls = [ft.Text("Hello")]
    page.update()
```

Key properties:
- `title` - window title
- `route` - current URL route
- `theme_mode` - light/dark/system
- `theme` - Theme object for customization
- `scroll` - enable page scrolling
- `bgcolor` - background color
- `padding` - page padding
- `splash` - overlay widget (e.g., loading indicator)

Key methods:
- `page.add(*controls)` - add controls and auto-update
- `page.update()` - refresh UI
- `page.go(route)` - navigate to route
- `page.run_task(coro)` - run async task in background
- `page.show_snack_bar(snackbar)` - show notification

### Container

Single-child container with styling.

```python
ft.Container(
    content=ft.Text("Styled content"),
    bgcolor=ft.Colors.BLUE_100,
    padding=20,
    margin=10,
    border_radius=10,
    border=ft.border.all(2, ft.Colors.BLUE),
    alignment=ft.alignment.center,
    width=200,
    height=100,
    ink=True,  # ripple effect on click
    on_click=lambda e: print("clicked"),
)
```

Key properties:
- `content` - child control
- `bgcolor` - background color
- `padding` / `margin` - spacing (int or `ft.padding.only(left=10)`)
- `border_radius` - corner radius (int or `ft.border_radius.only(top_left=10)`)
- `border` - border style
- `alignment` - child alignment
- `width` / `height` - explicit dimensions
- `expand` - fill available space
- `ink` - enable ripple effect for clicks

### Row

Horizontal layout.

```python
ft.Row(
    controls=[
        ft.Text("Left"),
        ft.Text("Center"),
        ft.Text("Right"),
    ],
    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
    vertical_alignment=ft.CrossAxisAlignment.CENTER,
    spacing=10,
    wrap=True,  # wrap to next line if overflow
    scroll=ft.ScrollMode.AUTO,  # enable horizontal scroll
)
```

Key properties:
- `controls` - list of children
- `alignment` - main axis (START, CENTER, END, SPACE_BETWEEN, SPACE_AROUND, SPACE_EVENLY)
- `vertical_alignment` - cross axis (START, CENTER, END, STRETCH)
- `spacing` - gap between children
- `wrap` - wrap overflowing children
- `scroll` - enable scrolling

### Column

Vertical layout. Same properties as Row.

```python
ft.Column(
    controls=[
        ft.Text("Top"),
        ft.Text("Middle"),
        ft.Text("Bottom"),
    ],
    alignment=ft.MainAxisAlignment.START,
    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
    spacing=10,
    expand=True,
    scroll=ft.ScrollMode.AUTO,
)
```

### Stack

Overlapping children (z-order by list position).

```python
ft.Stack(
    controls=[
        ft.Image(src="background.png"),
        ft.Container(
            content=ft.Text("Overlay"),
            alignment=ft.alignment.bottom_center,
        ),
    ],
)
```

### ResponsiveRow

Bootstrap-inspired responsive grid.

```python
ft.ResponsiveRow(
    controls=[
        ft.Container(
            content=ft.Text("A"),
            bgcolor=ft.Colors.RED,
            col={"sm": 6, "md": 4, "lg": 3},  # responsive columns
        ),
        ft.Container(
            content=ft.Text("B"),
            bgcolor=ft.Colors.GREEN,
            col={"sm": 6, "md": 4, "lg": 3},
        ),
    ],
)
```

Breakpoints: `xs` (<576px), `sm` (>=576px), `md` (>=768px), `lg` (>=992px), `xl` (>=1200px), `xxl` (>=1400px)

### ListView

Scrollable list (more efficient than Column with scroll).

```python
ft.ListView(
    controls=[ft.Text(f"Item {i}") for i in range(100)],
    spacing=10,
    padding=20,
    auto_scroll=True,  # scroll to bottom on new items
)
```

### GridView

Grid of controls.

```python
ft.GridView(
    controls=[ft.Container(bgcolor=ft.Colors.AMBER) for _ in range(20)],
    max_extent=150,  # max item width
    spacing=10,
    run_spacing=10,
)
```

## Input Controls

### TextField

Text input with extensive customization.

```python
ft.TextField(
    label="Username",
    hint_text="Enter your username",
    value="",
    text_size=16,
    border=ft.InputBorder.OUTLINE,  # OUTLINE, UNDERLINE, NONE
    border_radius=10,
    prefix_icon=ft.Icons.PERSON,
    suffix_icon=ft.Icons.CLEAR,
    password=True,
    can_reveal_password=True,
    multiline=True,
    min_lines=3,
    max_lines=5,
    max_length=100,
    on_change=lambda e: print(e.control.value),
    on_submit=lambda e: print("submitted"),
    on_focus=lambda e: print("focused"),
    on_blur=lambda e: print("blurred"),
)
```

Key properties:
- `value` - current text
- `label` / `hint_text` - descriptive text
- `password` - hide input
- `multiline` - allow multiple lines
- `read_only` - prevent editing
- `autofocus` - focus on load
- `error_text` - validation error message

### Dropdown

Selection from predefined options.

```python
ft.Dropdown(
    label="Country",
    value="us",
    options=[
        ft.dropdown.Option("us", "United States"),
        ft.dropdown.Option("uk", "United Kingdom"),
        ft.dropdown.Option("ca", "Canada"),
    ],
    on_change=lambda e: print(e.control.value),
)
```

### Checkbox

Boolean toggle with optional label.

```python
ft.Checkbox(
    label="I agree to terms",
    value=False,
    on_change=lambda e: print(e.control.value),
)
```

### Radio and RadioGroup

Single selection from group.

```python
ft.RadioGroup(
    value="option1",
    content=ft.Column([
        ft.Radio(value="option1", label="Option 1"),
        ft.Radio(value="option2", label="Option 2"),
        ft.Radio(value="option3", label="Option 3"),
    ]),
    on_change=lambda e: print(e.control.value),
)
```

### Switch

On/off toggle.

```python
ft.Switch(
    label="Enable notifications",
    value=True,
    on_change=lambda e: print(e.control.value),
)
```

### Slider

Value selection within range.

```python
ft.Slider(
    min=0,
    max=100,
    value=50,
    divisions=10,
    label="{value}%",
    on_change=lambda e: print(e.control.value),
)
```

### DatePicker

Date selection dialog.

```python
def open_date_picker(e):
    page.open(
        ft.DatePicker(
            first_date=datetime.date(2020, 1, 1),
            last_date=datetime.date(2030, 12, 31),
            on_change=lambda e: print(e.control.value),
        )
    )

ft.ElevatedButton("Pick date", on_click=open_date_picker)
```

### TimePicker

Time selection dialog.

```python
def open_time_picker(e):
    page.open(
        ft.TimePicker(
            on_change=lambda e: print(e.control.value),
        )
    )
```

## Navigation Controls

### AppBar

Top app bar.

```python
page.appbar = ft.AppBar(
    title=ft.Text("My App"),
    center_title=True,
    bgcolor=ft.Colors.SURFACE_VARIANT,
    leading=ft.IconButton(ft.Icons.MENU),
    actions=[
        ft.IconButton(ft.Icons.SEARCH),
        ft.IconButton(ft.Icons.SETTINGS),
    ],
)
```

### NavigationBar

Bottom navigation bar.

```python
page.navigation_bar = ft.NavigationBar(
    selected_index=0,
    destinations=[
        ft.NavigationBarDestination(icon=ft.Icons.HOME, label="Home"),
        ft.NavigationBarDestination(icon=ft.Icons.SEARCH, label="Search"),
        ft.NavigationBarDestination(icon=ft.Icons.PERSON, label="Profile"),
    ],
    on_change=lambda e: print(e.control.selected_index),
)
```

### NavigationDrawer

Side drawer menu.

```python
drawer = ft.NavigationDrawer(
    controls=[
        ft.NavigationDrawerDestination(
            icon=ft.Icons.HOME,
            label="Home",
        ),
        ft.Divider(),
        ft.NavigationDrawerDestination(
            icon=ft.Icons.SETTINGS,
            label="Settings",
        ),
    ],
    on_change=lambda e: print(e.control.selected_index),
)

page.drawer = drawer
page.appbar = ft.AppBar(
    leading=ft.IconButton(ft.Icons.MENU, on_click=lambda e: page.open(drawer)),
)
```

### Tabs

Tabbed interface.

```python
ft.Tabs(
    selected_index=0,
    tabs=[
        ft.Tab(text="Tab 1", content=ft.Text("Content 1")),
        ft.Tab(text="Tab 2", content=ft.Text("Content 2")),
        ft.Tab(text="Tab 3", icon=ft.Icons.SETTINGS, content=ft.Text("Content 3")),
    ],
    on_change=lambda e: print(e.control.selected_index),
)
```

## Display Controls

### Text

Text display with styling.

```python
ft.Text(
    "Hello World",
    size=24,
    weight=ft.FontWeight.BOLD,
    italic=True,
    color=ft.Colors.BLUE,
    text_align=ft.TextAlign.CENTER,
    overflow=ft.TextOverflow.ELLIPSIS,
    max_lines=2,
    selectable=True,
    style=ft.TextStyle(decoration=ft.TextDecoration.UNDERLINE),
)
```

### Icon

Material icons.

```python
ft.Icon(
    ft.Icons.FAVORITE,
    color=ft.Colors.RED,
    size=48,
)
```

### Image

Image display from various sources.

```python
# From URL
ft.Image(src="https://example.com/image.png", width=200)

# From file
ft.Image(src="assets/logo.png", width=200)

# From base64
ft.Image(src_base64=base64_string, width=200)

# With fit mode
ft.Image(
    src="image.png",
    fit=ft.ImageFit.COVER,
    width=200,
    height=200,
    border_radius=10,
)
```

### Markdown

Render markdown content.

```python
ft.Markdown(
    """
# Heading
**Bold** and *italic* text.
- List item 1
- List item 2
    """,
    selectable=True,
    extension_set=ft.MarkdownExtensionSet.GITHUB_WEB,
    on_tap_link=lambda e: page.launch_url(e.data),
)
```

### DataTable

Tabular data display.

```python
ft.DataTable(
    columns=[
        ft.DataColumn(ft.Text("Name")),
        ft.DataColumn(ft.Text("Age"), numeric=True),
        ft.DataColumn(ft.Text("City")),
    ],
    rows=[
        ft.DataRow(cells=[
            ft.DataCell(ft.Text("Alice")),
            ft.DataCell(ft.Text("30")),
            ft.DataCell(ft.Text("NYC")),
        ]),
        ft.DataRow(cells=[
            ft.DataCell(ft.Text("Bob")),
            ft.DataCell(ft.Text("25")),
            ft.DataCell(ft.Text("LA")),
        ]),
    ],
)
```

### Card

Material card with elevation.

```python
ft.Card(
    content=ft.Container(
        content=ft.Column([
            ft.ListTile(
                leading=ft.Icon(ft.Icons.ALBUM),
                title=ft.Text("Card Title"),
                subtitle=ft.Text("Card subtitle"),
            ),
            ft.Row([
                ft.TextButton("ACTION 1"),
                ft.TextButton("ACTION 2"),
            ]),
        ]),
        padding=10,
    ),
)
```

### ProgressBar / ProgressRing

Loading indicators.

```python
# Determinate
ft.ProgressBar(value=0.5)
ft.ProgressRing(value=0.5)

# Indeterminate (no value)
ft.ProgressBar()
ft.ProgressRing()
```

## Charts

### BarChart

```python
ft.BarChart(
    bar_groups=[
        ft.BarChartGroup(
            x=0,
            bar_rods=[ft.BarChartRod(from_y=0, to_y=40, color=ft.Colors.BLUE)],
        ),
        ft.BarChartGroup(
            x=1,
            bar_rods=[ft.BarChartRod(from_y=0, to_y=60, color=ft.Colors.GREEN)],
        ),
    ],
    border=ft.border.all(1, ft.Colors.GREY),
    left_axis=ft.ChartAxis(labels_size=40),
    bottom_axis=ft.ChartAxis(labels=[
        ft.ChartAxisLabel(value=0, label=ft.Text("Jan")),
        ft.ChartAxisLabel(value=1, label=ft.Text("Feb")),
    ]),
)
```

### LineChart

```python
ft.LineChart(
    data_series=[
        ft.LineChartData(
            data_points=[
                ft.LineChartDataPoint(0, 10),
                ft.LineChartDataPoint(1, 20),
                ft.LineChartDataPoint(2, 15),
            ],
            color=ft.Colors.BLUE,
            stroke_width=2,
        ),
    ],
)
```

### PieChart

```python
ft.PieChart(
    sections=[
        ft.PieChartSection(value=40, color=ft.Colors.BLUE, title="40%"),
        ft.PieChartSection(value=30, color=ft.Colors.GREEN, title="30%"),
        ft.PieChartSection(value=30, color=ft.Colors.RED, title="30%"),
    ],
    center_space_radius=50,
)
```

## Dialog & Overlay Controls

### AlertDialog

Modal dialog.

```python
dialog = ft.AlertDialog(
    title=ft.Text("Confirm"),
    content=ft.Text("Are you sure?"),
    actions=[
        ft.TextButton("Cancel", on_click=lambda e: page.close(dialog)),
        ft.TextButton("OK", on_click=handle_confirm),
    ],
)

page.open(dialog)
```

### BottomSheet

Bottom sheet overlay.

```python
sheet = ft.BottomSheet(
    content=ft.Container(
        content=ft.Column([
            ft.Text("Sheet content"),
            ft.ElevatedButton("Close", on_click=lambda e: page.close(sheet)),
        ]),
        padding=20,
    ),
)

page.open(sheet)
```

### SnackBar

Temporary notification.

```python
page.show_snack_bar(
    ft.SnackBar(
        content=ft.Text("Action completed!"),
        action="Undo",
        on_action=handle_undo,
    )
)
```

## Gesture Controls

### GestureDetector

Detect gestures on any control.

```python
ft.GestureDetector(
    content=ft.Container(bgcolor=ft.Colors.AMBER, width=100, height=100),
    on_tap=lambda e: print("tap"),
    on_double_tap=lambda e: print("double tap"),
    on_long_press_start=lambda e: print("long press"),
    on_pan_start=lambda e: print(f"pan start: {e.local_x}, {e.local_y}"),
    on_pan_update=lambda e: print(f"pan: {e.delta_x}, {e.delta_y}"),
    on_pan_end=lambda e: print("pan end"),
    on_scale_start=lambda e: print("scale start"),
    on_scale_update=lambda e: print(f"scale: {e.scale}"),
    drag_interval=50,  # throttle drag events (ms)
)
```

### Draggable / DragTarget

Drag and drop.

```python
def drag_accept(e):
    # e.data contains the dragged content
    target.content.value = e.data
    page.update()

ft.Draggable(
    content=ft.Container(content=ft.Text("Drag me"), bgcolor=ft.Colors.AMBER),
    content_feedback=ft.Container(content=ft.Text("Dragging..."), bgcolor=ft.Colors.AMBER_200),
)

target = ft.DragTarget(
    content=ft.Container(content=ft.Text("Drop here"), bgcolor=ft.Colors.BLUE_100, width=200, height=200),
    on_accept=drag_accept,
)
```

## Button Controls

### ElevatedButton

Primary raised button.

```python
ft.ElevatedButton(
    text="Click me",
    icon=ft.Icons.ADD,
    on_click=handle_click,
    style=ft.ButtonStyle(
        color=ft.Colors.WHITE,
        bgcolor=ft.Colors.BLUE,
    ),
)
```

### FilledButton / OutlinedButton / TextButton

Button variants.

```python
ft.FilledButton("Filled", on_click=handle)
ft.OutlinedButton("Outlined", on_click=handle)
ft.TextButton("Text", on_click=handle)
```

### IconButton

Icon-only button.

```python
ft.IconButton(
    icon=ft.Icons.FAVORITE,
    icon_color=ft.Colors.RED,
    icon_size=30,
    tooltip="Favorite",
    on_click=handle_click,
)
```

### FloatingActionButton

Floating action button.

```python
page.floating_action_button = ft.FloatingActionButton(
    icon=ft.Icons.ADD,
    on_click=handle_click,
)
```

## Cupertino (iOS) Controls

iOS-styled controls for native iOS look.

```python
# iOS-style button
ft.CupertinoButton(
    content=ft.Text("iOS Button"),
    on_click=handle_click,
)

# iOS-style switch
ft.CupertinoSwitch(
    value=True,
    on_change=lambda e: print(e.control.value),
)

# iOS-style text field
ft.CupertinoTextField(
    placeholder="Enter text",
    on_change=lambda e: print(e.control.value),
)

# iOS-style slider
ft.CupertinoSlider(
    value=0.5,
    on_change=lambda e: print(e.control.value),
)

# iOS-style alert dialog
ft.CupertinoAlertDialog(
    title=ft.Text("Alert"),
    content=ft.Text("This is an iOS-style alert"),
    actions=[
        ft.CupertinoDialogAction("OK", on_click=handle),
    ],
)
```
