#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["textual"]
# ///
import os
from textual.app import App, ComposeResult
from textual.widgets import Input, Static, Button
from textual.containers import Horizontal
from datetime import datetime, timedelta

MIN_WIDTH = 35
MIN_HEIGHT = 10

class PomoConfig(App):
    CSS = """
    Horizontal { height: 3; }
    .label { width: 14; padding: 1; }
    Input { width: 16; }
    #projection { color: cyan; margin-left: 1; }
    Button { margin-top: 1; }
    """

    BINDINGS = [
        ("up", "focus_previous", "Previous"),
        ("down", "focus_next", "Next"),
    ]

    def compose(self) -> ComposeResult:
        yield Static("Configure Pomodoro Session", id="title")
        with Horizontal():
            yield Static("Work mins:", classes="label")
            yield Input(value="24", id="work")
        with Horizontal():
            yield Static("Break mins:", classes="label")
            yield Input(value="3", id="short")
        with Horizontal():
            yield Static("Sessions:", classes="label")
            yield Input(value="2", id="sessions")
        yield Static("", id="projection")
        yield Button("Start", id="submit", variant="primary")

    def on_mount(self):
        self.query_one("#work").focus()
        self.update_projection()

    def on_input_changed(self, event: Input.Changed):
        self.update_projection()

    def on_button_pressed(self, event: Button.Pressed):
        self.submit_config()

    def on_input_submitted(self, event: Input.Submitted):
        self.submit_config()

    def submit_config(self):
        w = self.query_one("#work", Input).value or "24"
        s = self.query_one("#short", Input).value or "3"
        n = self.query_one("#sessions", Input).value or "2"
        self.exit(f"{w}/{s}/{n}")

    def update_projection(self):
        try:
            work = int(self.query_one("#work", Input).value or 24)
            short = int(self.query_one("#short", Input).value or 3)
            sessions = int(self.query_one("#sessions", Input).value or 2)
            total = work * sessions + short * (sessions - 1)
            end = datetime.now() + timedelta(minutes=total)
            hours, mins = divmod(total, 60)
            duration = f"{hours}h {mins}m" if hours else f"{mins}m"
            self.query_one("#projection").update(f"will take {duration}, ends at ~{end:%H:%M}")
        except ValueError:
            self.query_one("#projection").update("")

if __name__ == "__main__":
    try:
        size = os.get_terminal_size()
        if size.columns < MIN_WIDTH or size.lines < MIN_HEIGHT:
            import sys
            print(f"Terminal too small ({size.columns}x{size.lines}), need {MIN_WIDTH}x{MIN_HEIGHT}", file=sys.stderr)
            sys.exit(1)
    except OSError:
        pass

    app = PomoConfig()
    result = app.run()
    if result:
        print(result)
