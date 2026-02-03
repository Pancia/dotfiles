# Flet Navigation and Routing

## Page Routing

### Basic Routing

Every Page has a `route` property representing the current URL path.

```python
import flet as ft

def main(page: ft.Page):
    def route_change(e):
        print(f"Route changed to: {page.route}")
        page.views.clear()

        # Home view
        page.views.append(
            ft.View(
                route="/",
                controls=[
                    ft.AppBar(title=ft.Text("Home")),
                    ft.ElevatedButton("Go to Settings", on_click=lambda _: page.go("/settings")),
                ],
            )
        )

        # Settings view (if route matches)
        if page.route == "/settings":
            page.views.append(
                ft.View(
                    route="/settings",
                    controls=[
                        ft.AppBar(title=ft.Text("Settings"), leading=ft.IconButton(ft.Icons.ARROW_BACK, on_click=lambda _: page.go("/"))),
                        ft.Text("Settings page"),
                    ],
                )
            )

        page.update()

    def view_pop(e):
        page.views.pop()
        top_view = page.views[-1]
        page.go(top_view.route)

    page.on_route_change = route_change
    page.on_view_pop = view_pop
    page.go(page.route or "/")

ft.app(main)
```

### Navigation Methods

```python
# Navigate to a route
page.go("/settings")

# Navigate with query parameters
page.go("/search?q=flet&page=1")

# Go back (pops current view)
page.views.pop()
page.update()

# Access current route
print(page.route)  # "/settings"

# Access query parameters
# For "/search?q=flet", parse manually:
from urllib.parse import urlparse, parse_qs
parsed = urlparse(page.route)
params = parse_qs(parsed.query)  # {'q': ['flet']}
```

## TemplateRoute (URL Parameters)

Use TemplateRoute for ExpressJS-style URL patterns with parameters.

```python
import flet as ft
from flet import TemplateRoute

def main(page: ft.Page):
    def route_change(e):
        # Create template route from current route
        troute = TemplateRoute(page.route)

        page.views.clear()

        # Home
        if troute.match("/"):
            page.views.append(home_view())

        # User profile: /users/123
        elif troute.match("/users/:user_id"):
            user_id = troute.user_id
            page.views.append(user_view(user_id))

        # User posts: /users/123/posts/456
        elif troute.match("/users/:user_id/posts/:post_id"):
            user_id = troute.user_id
            post_id = troute.post_id
            page.views.append(post_view(user_id, post_id))

        # 404
        else:
            page.views.append(not_found_view())

        page.update()

    page.on_route_change = route_change
    page.go("/")

def home_view():
    return ft.View(
        route="/",
        controls=[
            ft.AppBar(title=ft.Text("Home")),
            ft.ElevatedButton("User 123", on_click=lambda _: page.go("/users/123")),
        ],
    )

def user_view(user_id):
    return ft.View(
        route=f"/users/{user_id}",
        controls=[
            ft.AppBar(title=ft.Text(f"User {user_id}")),
            ft.Text(f"Viewing user: {user_id}"),
            ft.ElevatedButton("Post 456", on_click=lambda _: page.go(f"/users/{user_id}/posts/456")),
        ],
    )

def post_view(user_id, post_id):
    return ft.View(
        route=f"/users/{user_id}/posts/{post_id}",
        controls=[
            ft.AppBar(title=ft.Text(f"Post {post_id}")),
            ft.Text(f"User {user_id}, Post {post_id}"),
        ],
    )

def not_found_view():
    return ft.View(
        route="/404",
        controls=[
            ft.AppBar(title=ft.Text("Not Found")),
            ft.Text("Page not found"),
        ],
    )
```

## View-Based Architecture

### View Properties

```python
ft.View(
    route="/settings",
    controls=[...],
    appbar=ft.AppBar(title=ft.Text("Settings")),
    floating_action_button=ft.FloatingActionButton(icon=ft.Icons.ADD),
    navigation_bar=ft.NavigationBar(...),
    drawer=ft.NavigationDrawer(...),
    end_drawer=ft.NavigationDrawer(...),
    vertical_alignment=ft.MainAxisAlignment.START,
    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
    spacing=10,
    padding=20,
    bgcolor=ft.Colors.SURFACE,
    scroll=ft.ScrollMode.AUTO,
)
```

### View Factory Pattern

Organize views as factory functions:

```python
def create_home_view(page):
    def go_to_settings(e):
        page.go("/settings")

    return ft.View(
        route="/",
        controls=[
            ft.AppBar(title=ft.Text("Home")),
            ft.Text("Welcome!"),
            ft.ElevatedButton("Settings", on_click=go_to_settings),
        ],
    )

def create_settings_view(page):
    return ft.View(
        route="/settings",
        controls=[
            ft.AppBar(
                title=ft.Text("Settings"),
                leading=ft.IconButton(ft.Icons.ARROW_BACK, on_click=lambda _: page.go("/")),
            ),
            ft.Text("Settings content"),
        ],
    )

# Router
ROUTES = {
    "/": create_home_view,
    "/settings": create_settings_view,
}

def main(page: ft.Page):
    def route_change(e):
        page.views.clear()
        view_factory = ROUTES.get(page.route, create_not_found_view)
        page.views.append(view_factory(page))
        page.update()

    page.on_route_change = route_change
    page.go("/")
```

### View Classes

For more complex views, use classes:

```python
class SettingsView:
    def __init__(self, page: ft.Page):
        self.page = page
        self.theme_mode = ft.Switch(
            label="Dark mode",
            value=page.theme_mode == ft.ThemeMode.DARK,
            on_change=self.toggle_theme,
        )

    def toggle_theme(self, e):
        self.page.theme_mode = (
            ft.ThemeMode.DARK if e.control.value else ft.ThemeMode.LIGHT
        )
        self.page.update()

    def build(self):
        return ft.View(
            route="/settings",
            controls=[
                ft.AppBar(
                    title=ft.Text("Settings"),
                    leading=ft.IconButton(ft.Icons.ARROW_BACK, on_click=lambda _: self.page.go("/")),
                ),
                self.theme_mode,
            ],
        )

# Usage in router
page.views.append(SettingsView(page).build())
```

## Navigation Components

### NavigationBar (Bottom Navigation)

```python
def main(page: ft.Page):
    content = ft.Text("Home content")

    def nav_change(e):
        index = e.control.selected_index
        if index == 0:
            content.value = "Home content"
        elif index == 1:
            content.value = "Search content"
        elif index == 2:
            content.value = "Profile content"
        page.update()

    page.navigation_bar = ft.NavigationBar(
        selected_index=0,
        on_change=nav_change,
        destinations=[
            ft.NavigationBarDestination(icon=ft.Icons.HOME, label="Home"),
            ft.NavigationBarDestination(icon=ft.Icons.SEARCH, label="Search"),
            ft.NavigationBarDestination(icon=ft.Icons.PERSON, label="Profile"),
        ],
    )

    page.add(content)
```

### NavigationRail (Side Navigation)

```python
rail = ft.NavigationRail(
    selected_index=0,
    label_type=ft.NavigationRailLabelType.ALL,
    min_width=100,
    min_extended_width=200,
    extended=True,
    destinations=[
        ft.NavigationRailDestination(icon=ft.Icons.HOME, label="Home"),
        ft.NavigationRailDestination(icon=ft.Icons.SETTINGS, label="Settings"),
    ],
    on_change=lambda e: print(e.control.selected_index),
)

page.add(
    ft.Row([
        rail,
        ft.VerticalDivider(width=1),
        ft.Column([ft.Text("Main content")], expand=True),
    ], expand=True)
)
```

### Tabs Navigation

```python
tabs = ft.Tabs(
    selected_index=0,
    animation_duration=300,
    tabs=[
        ft.Tab(
            text="Tab 1",
            icon=ft.Icons.HOME,
            content=ft.Container(content=ft.Text("Tab 1 content"), alignment=ft.alignment.center),
        ),
        ft.Tab(
            text="Tab 2",
            icon=ft.Icons.SETTINGS,
            content=ft.Container(content=ft.Text("Tab 2 content"), alignment=ft.alignment.center),
        ),
    ],
    expand=True,
)

page.add(tabs)
```

## Deep Linking

Flet supports deep linking for web and mobile apps:

```python
def main(page: ft.Page):
    # Initial route from URL (web) or intent (mobile)
    initial_route = page.route or "/"

    def route_change(e):
        # Handle route...
        pass

    page.on_route_change = route_change
    page.go(initial_route)

# Web: https://myapp.com/#/users/123 -> page.route = "/users/123"
# Mobile: Configure URL schemes in app manifest
```

## Browser History

For web apps, Flet automatically manages browser history:

```python
# Each page.go() adds to browser history
page.go("/page1")  # History: ["/page1"]
page.go("/page2")  # History: ["/page1", "/page2"]

# Back button triggers on_view_pop
def view_pop(e):
    page.views.pop()
    if page.views:
        top_view = page.views[-1]
        page.go(top_view.route)

page.on_view_pop = view_pop
```
