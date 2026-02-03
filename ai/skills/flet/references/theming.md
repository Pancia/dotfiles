# Flet Theming

## Theme Configuration

### Basic Theme Setup

```python
import flet as ft

def main(page: ft.Page):
    # Set theme mode
    page.theme_mode = ft.ThemeMode.LIGHT  # LIGHT, DARK, or SYSTEM

    # Configure theme
    page.theme = ft.Theme(
        color_scheme_seed=ft.Colors.BLUE,  # Generates full color scheme
    )

    # Dark theme (optional, for SYSTEM mode)
    page.dark_theme = ft.Theme(
        color_scheme_seed=ft.Colors.INDIGO,
    )
```

### Color Scheme from Seed

The `color_scheme_seed` generates a complete Material 3 color scheme:

```python
page.theme = ft.Theme(
    color_scheme_seed=ft.Colors.GREEN,  # Primary color
)

# This generates:
# - primary, onPrimary, primaryContainer, onPrimaryContainer
# - secondary, onSecondary, secondaryContainer, onSecondaryContainer
# - tertiary, onTertiary, tertiaryContainer, onTertiaryContainer
# - error, onError, errorContainer, onErrorContainer
# - background, onBackground, surface, onSurface
# - surfaceVariant, onSurfaceVariant, outline, outlineVariant
# - shadow, scrim, inverseSurface, onInverseSurface, inversePrimary
```

### Custom Color Scheme

Override specific colors:

```python
page.theme = ft.Theme(
    color_scheme=ft.ColorScheme(
        primary=ft.Colors.PURPLE_500,
        secondary=ft.Colors.ORANGE_500,
        background=ft.Colors.GREY_100,
        surface=ft.Colors.WHITE,
        error=ft.Colors.RED_500,
        on_primary=ft.Colors.WHITE,
        on_secondary=ft.Colors.WHITE,
        on_background=ft.Colors.BLACK,
        on_surface=ft.Colors.BLACK,
        on_error=ft.Colors.WHITE,
    ),
)
```

## Theme Mode Toggle

```python
def main(page: ft.Page):
    page.theme_mode = ft.ThemeMode.LIGHT

    def toggle_theme(e):
        page.theme_mode = (
            ft.ThemeMode.DARK
            if page.theme_mode == ft.ThemeMode.LIGHT
            else ft.ThemeMode.LIGHT
        )
        page.update()

    page.add(
        ft.Switch(
            label="Dark mode",
            value=page.theme_mode == ft.ThemeMode.DARK,
            on_change=toggle_theme,
        )
    )
```

## Custom Fonts

### Define Custom Fonts

```python
page.fonts = {
    "Roboto": "https://fonts.googleapis.com/css2?family=Roboto",
    "Open Sans": "/fonts/OpenSans-Regular.ttf",  # Local file
    "Custom Font": "assets/fonts/CustomFont.ttf",
}

page.theme = ft.Theme(
    font_family="Roboto",
)
```

### Use Custom Fonts

```python
# Set default font for the app
page.theme = ft.Theme(font_family="Roboto")

# Use specific font on a control
ft.Text("Hello", font_family="Open Sans")
```

## Text Theming

### Text Theme Configuration

```python
page.theme = ft.Theme(
    text_theme=ft.TextTheme(
        display_large=ft.TextStyle(size=57, weight=ft.FontWeight.NORMAL),
        display_medium=ft.TextStyle(size=45, weight=ft.FontWeight.NORMAL),
        display_small=ft.TextStyle(size=36, weight=ft.FontWeight.NORMAL),
        headline_large=ft.TextStyle(size=32, weight=ft.FontWeight.NORMAL),
        headline_medium=ft.TextStyle(size=28, weight=ft.FontWeight.NORMAL),
        headline_small=ft.TextStyle(size=24, weight=ft.FontWeight.NORMAL),
        title_large=ft.TextStyle(size=22, weight=ft.FontWeight.MEDIUM),
        title_medium=ft.TextStyle(size=16, weight=ft.FontWeight.MEDIUM),
        title_small=ft.TextStyle(size=14, weight=ft.FontWeight.MEDIUM),
        body_large=ft.TextStyle(size=16, weight=ft.FontWeight.NORMAL),
        body_medium=ft.TextStyle(size=14, weight=ft.FontWeight.NORMAL),
        body_small=ft.TextStyle(size=12, weight=ft.FontWeight.NORMAL),
        label_large=ft.TextStyle(size=14, weight=ft.FontWeight.MEDIUM),
        label_medium=ft.TextStyle(size=12, weight=ft.FontWeight.MEDIUM),
        label_small=ft.TextStyle(size=11, weight=ft.FontWeight.MEDIUM),
    ),
)
```

### Using Text Styles

```python
# Use predefined text styles
ft.Text("Display Large", theme_style=ft.TextThemeStyle.DISPLAY_LARGE)
ft.Text("Headline Medium", theme_style=ft.TextThemeStyle.HEADLINE_MEDIUM)
ft.Text("Body Small", theme_style=ft.TextThemeStyle.BODY_SMALL)
ft.Text("Label Large", theme_style=ft.TextThemeStyle.LABEL_LARGE)
```

## Component Theming

### Button Theme

```python
page.theme = ft.Theme(
    elevated_button_theme=ft.ElevatedButtonTheme(
        color=ft.Colors.WHITE,
        bgcolor=ft.Colors.BLUE_700,
        elevation=4,
        padding=ft.padding.symmetric(horizontal=20, vertical=10),
        shape=ft.RoundedRectangleBorder(radius=10),
    ),
    text_button_theme=ft.TextButtonTheme(
        color=ft.Colors.BLUE_700,
    ),
    outlined_button_theme=ft.OutlinedButtonTheme(
        color=ft.Colors.BLUE_700,
        side=ft.BorderSide(width=2, color=ft.Colors.BLUE_700),
    ),
)
```

### TextField Theme

```python
page.theme = ft.Theme(
    input_decoration_theme=ft.InputDecorationTheme(
        border_radius=10,
        filled=True,
        fill_color=ft.Colors.GREY_100,
        border_color=ft.Colors.GREY_400,
        focused_border_color=ft.Colors.BLUE_700,
        label_style=ft.TextStyle(color=ft.Colors.GREY_700),
        hint_style=ft.TextStyle(color=ft.Colors.GREY_500),
    ),
)
```

### AppBar Theme

```python
page.theme = ft.Theme(
    appbar_theme=ft.AppBarTheme(
        bgcolor=ft.Colors.BLUE_700,
        color=ft.Colors.WHITE,  # Text/icon color
        elevation=4,
        center_title=True,
    ),
)
```

### Card Theme

```python
page.theme = ft.Theme(
    card_theme=ft.CardTheme(
        color=ft.Colors.WHITE,
        elevation=2,
        margin=ft.margin.all(8),
        shape=ft.RoundedRectangleBorder(radius=12),
    ),
)
```

## Local Theme Overrides

### Container-Level Theme

Override theme for specific sections:

```python
# Light section in dark app
ft.Container(
    theme=ft.Theme(color_scheme_seed=ft.Colors.AMBER),
    theme_mode=ft.ThemeMode.LIGHT,
    content=ft.Column([
        ft.Text("This section uses light theme"),
        ft.ElevatedButton("Light Button"),
    ]),
)
```

### Control-Level Styling

Override individual control styles:

```python
ft.ElevatedButton(
    "Custom Button",
    style=ft.ButtonStyle(
        color={
            ft.ControlState.DEFAULT: ft.Colors.WHITE,
            ft.ControlState.HOVERED: ft.Colors.YELLOW,
            ft.ControlState.PRESSED: ft.Colors.AMBER,
            ft.ControlState.DISABLED: ft.Colors.GREY,
        },
        bgcolor={
            ft.ControlState.DEFAULT: ft.Colors.BLUE_700,
            ft.ControlState.HOVERED: ft.Colors.BLUE_800,
            ft.ControlState.PRESSED: ft.Colors.BLUE_900,
            ft.ControlState.DISABLED: ft.Colors.GREY_400,
        },
        elevation={
            ft.ControlState.DEFAULT: 4,
            ft.ControlState.HOVERED: 8,
            ft.ControlState.PRESSED: 2,
        },
        animation_duration=200,
        padding=ft.padding.symmetric(horizontal=30, vertical=15),
        shape=ft.RoundedRectangleBorder(radius=20),
    ),
)
```

## Colors Reference

### Material Colors

```python
ft.Colors.RED
ft.Colors.RED_50, ft.Colors.RED_100, ..., ft.Colors.RED_900
ft.Colors.RED_ACCENT
ft.Colors.RED_ACCENT_100, ..., ft.Colors.RED_ACCENT_700

# Available color families:
# RED, PINK, PURPLE, DEEP_PURPLE, INDIGO, BLUE, LIGHT_BLUE, CYAN,
# TEAL, GREEN, LIGHT_GREEN, LIME, YELLOW, AMBER, ORANGE, DEEP_ORANGE,
# BROWN, GREY, BLUE_GREY

# Special colors
ft.Colors.WHITE
ft.Colors.BLACK
ft.Colors.TRANSPARENT
```

### Semantic Colors

```python
ft.Colors.PRIMARY
ft.Colors.ON_PRIMARY
ft.Colors.PRIMARY_CONTAINER
ft.Colors.ON_PRIMARY_CONTAINER
ft.Colors.SECONDARY
ft.Colors.ON_SECONDARY
ft.Colors.SURFACE
ft.Colors.ON_SURFACE
ft.Colors.BACKGROUND
ft.Colors.ON_BACKGROUND
ft.Colors.ERROR
ft.Colors.ON_ERROR
```

### Custom Colors

```python
# Hex colors
"#FF5733"
"#FF573380"  # With alpha

# ARGB
ft.Colors.with_opacity(0.5, ft.Colors.BLUE)  # 50% opacity blue
```

## Visual Density

Control spacing and sizing:

```python
page.theme = ft.Theme(
    visual_density=ft.VisualDensity.COMPACT,  # COMPACT, COMFORTABLE, STANDARD
)
```

## Scrollbar Theme

```python
page.theme = ft.Theme(
    scrollbar_theme=ft.ScrollbarTheme(
        thickness=8,
        radius=4,
        thumb_color={
            ft.ControlState.DEFAULT: ft.Colors.GREY_400,
            ft.ControlState.HOVERED: ft.Colors.GREY_600,
        },
        track_color=ft.Colors.GREY_200,
        track_visibility=True,
    ),
)
```
