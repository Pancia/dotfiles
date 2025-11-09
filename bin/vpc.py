#!/usr/bin/env python3
"""
VPC (Virtual Personal Computer) - Workspace Setup Script
Manages applications, browser tabs, and window layouts for different workspaces.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


@dataclass
class GridBounds:
    """Represents the bounds of a grid area."""
    total_rows: int
    total_cols: int
    min_row: int
    max_row: int
    min_col: int
    max_col: int

    def to_yabai_grid(self) -> str:
        """Convert to yabai grid format: rows:cols:start_x:start_y:width:height"""
        width = self.max_col - self.min_col
        height = self.max_row - self.min_row
        return f"{self.total_rows}:{self.total_cols}:{self.min_col}:{self.min_row}:{width}:{height}"


class VPCConfig:
    """Parse and validate .vpc JSON configuration files."""

    def __init__(self, config_path: str):
        self.config_path = Path(config_path).expanduser()
        self.config = self._load_config()

    def _load_config(self) -> dict:
        """Load and parse JSON config file."""
        try:
            with open(self.config_path, 'r') as f:
                content = f.read()
                return json.loads(content)
        except FileNotFoundError:
            error_msg = f"""
{'='*60}
VPC CONFIG ERROR
{'='*60}
Config file not found: {self.config_path}

Please check that the file exists and the path is correct.
{'='*60}
"""
            print(error_msg, file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            # Read the file again to show context
            with open(self.config_path, 'r') as f:
                lines = f.readlines()

            # Get context around the error
            error_line = e.lineno
            start_line = max(1, error_line - 2)
            end_line = min(len(lines), error_line + 2)

            context = ""
            for i in range(start_line - 1, end_line):
                line_num = i + 1
                marker = ">>>" if line_num == error_line else "   "
                context += f"{marker} {line_num:3d}: {lines[i]}"
                if line_num == error_line and e.colno:
                    context += " " * (len(marker) + 6 + e.colno - 1) + "^\n"

            error_msg = f"""
{'='*60}
VPC CONFIG ERROR - INVALID JSON
{'='*60}
File: {self.config_path}
Error: {e.msg}
Location: Line {e.lineno}, Column {e.colno}

Context:
{context}
{'='*60}
"""
            print(error_msg, file=sys.stderr)
            sys.exit(1)

    def get(self, key: str, default: Any = None) -> Any:
        """Get a config value."""
        return self.config.get(key, default)

    def expand_path(self, path: str) -> str:
        """Expand $HOME and ~ in paths."""
        if not path:
            return path
        expanded = path.replace('$HOME', os.environ['HOME'])
        expanded = expanded.replace('~', os.environ['HOME'])
        return expanded

    def get_app_configs(self) -> dict[str, Any]:
        """Get all app configurations (excluding special keys like 'space', 'yabai')."""
        special_keys = {'space', 'yabai'}
        return {
            key: value
            for key, value in self.config.items()
            if key not in special_keys
        }

    @staticmethod
    def normalize_app_config(config: Any) -> list[dict]:
        """Normalize app config to list format.

        If config is a dict, return [config].
        If config is a list, return it as-is.
        Otherwise, return empty list.
        """
        if isinstance(config, dict):
            return [config]
        elif isinstance(config, list):
            return config
        else:
            return []


class WindowQuery:
    """Query yabai for window information."""

    @staticmethod
    def run_yabai(args: list[str]) -> dict | list | None:
        """Run a yabai command and return JSON output."""
        try:
            result = subprocess.run(
                ['yabai', '-m'] + args,
                capture_output=True,
                text=True,
                check=True
            )
            if result.stdout.strip():
                return json.loads(result.stdout)
            return None
        except subprocess.CalledProcessError as e:
            print(f"Warning: yabai command failed: {e}")
            return None
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON from yabai: {e}")
            return None

    @staticmethod
    def find_window_by_app(app_name: str, max_retries: int = 10, delay: float = 0.5) -> Optional[int]:
        """Find window ID for an app, with retries."""
        for attempt in range(max_retries):
            windows = WindowQuery.run_yabai(['query', '--windows'])
            if windows:
                for window in windows:
                    if window.get('app') == app_name:
                        return window.get('id')
            if attempt < max_retries - 1:
                time.sleep(delay)

        print(f"Warning: Could not find window for {app_name}")
        return None


class YabaiManager:
    """Manage yabai window positioning and layouts."""

    def __init__(self, config: VPCConfig):
        self.config = config
        self.yabai_config = config.get('yabai', {})
        self.enabled = self.yabai_config.get('enabled', False)
        self.available = self._check_yabai_available()

        # Warn if enabled but not available
        if self.enabled and not self.available:
            print("Warning: yabai is enabled in config but not running.")
            print("         Skipping all window positioning operations.")
            print()

    def _check_yabai_available(self) -> bool:
        """Check if yabai is running and available."""
        if not self.enabled:
            return False

        try:
            result = subprocess.run(
                ['yabai', '-m', 'query', '--spaces'],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
            return False

    def apply_space_config(self):
        """Apply space-level configuration (layout)."""
        if not self.enabled or not self.available:
            return

        space_config = self.yabai_config.get('space_config', {})

        # Set layout
        layout = space_config.get('layout')
        if layout:
            self._run_yabai(['space', '--layout', layout])

    def position_window(self, app_name: str, window_config: dict):
        """Position a window using grid + resize + offset."""
        if not self.enabled or not self.available:
            return

        if not window_config:
            return

        # Find window
        window_id = WindowQuery.find_window_by_app(app_name)
        if not window_id:
            return

        print(f"Positioning {app_name} (window id: {window_id})")

        # Step 1: Grid positioning
        grid = None
        if 'area' in window_config:
            # Calculate grid from CSS Grid layout
            area = window_config['area']
            grid = self._calculate_grid_from_area(area)
        elif 'grid' in window_config:
            # Use manual grid specification
            grid = window_config['grid']

        if grid:
            print(f"  Grid: {grid}")
            self._run_yabai(['window', str(window_id), '--grid', grid])

        # Step 2: Resize operations
        resize_ops = window_config.get('resize', [])
        for op in resize_ops:
            anchor = op['anchor']
            x = op['x']
            y = op['y']
            print(f"  Resize: {anchor} by ({x}, {y})")
            self._run_yabai(['window', str(window_id), '--resize', f'{anchor}:{x}:{y}'])

        # Step 3: Offset (relative move)
        offset = window_config.get('offset')
        if offset:
            x = offset['x']
            y = offset['y']
            print(f"  Offset: ({x}, {y})")
            self._run_yabai(['window', str(window_id), '--move', f'rel:{x}:{y}'])

        # Step 4: Layer
        layer = window_config.get('layer')
        if layer:
            print(f"  Layer: {layer}")
            self._run_yabai(['window', str(window_id), '--layer', layer])

        # Step 5: Focus
        if window_config.get('focus', False):
            print(f"  Focusing window")
            self._run_yabai(['window', str(window_id), '--focus'])

    def balance_space(self):
        """Balance window sizes in the space."""
        if not self.enabled or not self.available:
            return

        space_config = self.yabai_config.get('space_config', {})
        if space_config.get('balance', False):
            print("Balancing space")
            self._run_yabai(['space', '--balance'])

    def _calculate_grid_from_area(self, area_name: str) -> Optional[str]:
        """Calculate yabai grid from CSS Grid area name."""
        layout = self.yabai_config.get('layout', {})
        template = layout.get('template', [])

        if not template:
            return None

        try:
            bounds = self._parse_grid_template(template, area_name)
            return bounds.to_yabai_grid()
        except ValueError as e:
            print(f"Warning: Could not parse grid template: {e}")
            return None

    @staticmethod
    def _parse_grid_template(template: list[str], area_name: str) -> GridBounds:
        """Parse CSS Grid template and find bounds for named area."""
        if not template:
            raise ValueError("Empty template")

        total_rows = len(template)
        total_cols = len(template[0].split())

        # Find all cells with this area name
        cells = []
        for row_idx, row in enumerate(template):
            cols = row.split()
            for col_idx, cell in enumerate(cols):
                if cell == area_name:
                    cells.append((row_idx, col_idx))

        if not cells:
            raise ValueError(f"Area '{area_name}' not found in template")

        # Calculate bounds
        rows = [r for r, c in cells]
        cols = [c for r, c in cells]

        return GridBounds(
            total_rows=total_rows,
            total_cols=total_cols,
            min_row=min(rows),
            max_row=max(rows) + 1,
            min_col=min(cols),
            max_col=max(cols) + 1
        )

    @staticmethod
    def _run_yabai(args: list[str]):
        """Run a yabai command."""
        try:
            subprocess.run(
                ['yabai', '-m'] + args,
                check=True,
                capture_output=True,
                text=True
            )
        except subprocess.CalledProcessError as e:
            print(f"Warning: yabai command failed: {args}")
            if e.stderr:
                print(f"  Error: {e.stderr.strip()}")


class SpaceSwitcher:
    """Handle space switching via VPC server."""

    def __init__(self, config: VPCConfig):
        self.config = config

    def switch_space(self):
        """Switch to the specified space."""
        space = self.config.get('space')

        # Only switch if space is specified and not "current"
        if space and space != 'null' and space != 'current':
            print(f"Switching to space: {space}")
            try:
                result = subprocess.run(
                    ['curl', '-X', 'POST', f'http://localhost:31415/vpc/{space}'],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=5
                )
                print(f"  Response: {result.stdout.strip()}")
            except subprocess.CalledProcessError:
                print("ERROR: Failed to connect to VPC server")
                sys.exit(404)
            except subprocess.TimeoutExpired:
                print("ERROR: VPC server timeout")
                sys.exit(404)
        else:
            print("Using current space (no switch)")


class AppLauncher:
    """Launch and configure applications."""

    def __init__(self, config: VPCConfig, yabai: YabaiManager):
        self.config = config
        self.yabai = yabai

    def launch_all(self):
        """Launch all configured applications in order."""
        print()

        app_configs = self.config.get_app_configs()

        for app_name, app_config in app_configs.items():
            # Normalize to list format
            configs = VPCConfig.normalize_app_config(app_config)

            for config in configs:
                self._launch_app(app_name, config)

    def _launch_app(self, app_name: str, config: dict):
        """Launch a single app window with the given config."""
        # Detect app type and call appropriate launcher
        if app_name == 'iTerm2':
            self.launch_iterm(config)
        elif app_name == 'Google Chrome':
            self.launch_chrome(config)
        elif app_name == 'Brave Browser':
            self.launch_brave(config)
        elif app_name == 'CotEditor':
            self.launch_coteditor(config)
        else:
            # Generic app - just open it
            self.launch_generic(app_name, config)

    def launch_iterm(self, config: dict):
        """Launch iTerm with configured tabs."""
        print("Launching iTerm...")

        term_dir = json.dumps(self.config.expand_path(config.get('dir', '')))
        term_tabs = json.dumps(config.get('tabs', []))

        iterm_script = Path.home() / 'dotfiles' / 'bin' / 'iterm.py'

        try:
            subprocess.run(
                [str(iterm_script), term_dir, term_tabs],
                check=True
            )
            print("  iTerm done")

            # Position with yabai
            self.yabai.position_window('iTerm2', config)
        except subprocess.CalledProcessError as e:
            print(f"  Warning: iTerm launch failed: {e}")

    def launch_chrome(self, config: dict):
        """Launch Chrome with a new window and tabs via AppleScript."""
        print("Launching Chrome...")
        chrome_urls = config.get('urls', [])

        if not chrome_urls:
            return

        # Create new window with all URLs via AppleScript
        print(f"  Creating new window with {len(chrome_urls)} tab(s)")
        self._create_chrome_window(chrome_urls)

        print("  Chrome done")

        # Position with yabai
        self.yabai.position_window('Google Chrome', config)

    def launch_brave(self, config: dict):
        """Launch Brave with a new window and tabs via AppleScript."""
        print("Launching Brave...")
        brave_urls = config.get('urls', [])

        if not brave_urls:
            return

        # Create new window with all URLs via AppleScript
        print(f"  Creating new window with {len(brave_urls)} tab(s)")
        self._create_brave_window(brave_urls)

        print("  Brave done")

        # Position with yabai
        self.yabai.position_window('Brave Browser', config)

    def launch_generic(self, app_name: str, config: dict):
        """Launch a generic application."""
        print(f"Launching {app_name}...")
        subprocess.run(['open', '-a', app_name])
        print(f"  {app_name} done")

        # Position with yabai
        self.yabai.position_window(app_name, config)

    def launch_coteditor(self, config: dict):
        """Launch board file in CotEditor."""
        file_path = config.get('file')
        if not file_path:
            print("  Warning: No file specified for CotEditor")
            return

        print("Launching CotEditor...")
        expanded_path = self.config.expand_path(file_path)
        print(f"  Opening {expanded_path}")

        subprocess.run(['open', '-a', 'CotEditor', '-n', expanded_path])
        print("  CotEditor done")

        # Position with yabai
        self.yabai.position_window('CotEditor', config)

    @staticmethod
    def _create_chrome_window(urls: list[str]):
        """Create a new Chrome window with the given URLs."""
        if not urls:
            return

        # AppleScript to create new window and populate with tabs
        # Don't activate to avoid switching spaces
        applescript = '''
        on run argv
            tell application "Google Chrome"
                make new window
                set targetWindow to window 1
                set URL of active tab of targetWindow to item 1 of argv

                if (count of argv) > 1 then
                    repeat with i from 2 to count of argv
                        tell targetWindow to make new tab with properties {URL:item i of argv}
                    end repeat
                end if
            end tell
        end run
        '''

        try:
            subprocess.run(
                ['osascript', '-e', applescript] + urls,
                check=True,
                capture_output=True
            )
        except subprocess.CalledProcessError as e:
            print(f"  Warning: Failed to create Chrome window: {e}")

    @staticmethod
    def _create_brave_window(urls: list[str]):
        """Create a new Brave window with the given URLs."""
        if not urls:
            return

        # AppleScript to create new window and populate with tabs
        # Don't activate to avoid switching spaces
        applescript = '''
        on run argv
            tell application "Brave Browser"
                make new window
                set targetWindow to window 1
                set URL of active tab of targetWindow to item 1 of argv

                if (count of argv) > 1 then
                    repeat with i from 2 to count of argv
                        tell targetWindow to make new tab with properties {URL:item i of argv}
                    end repeat
                end if
            end tell
        end run
        '''

        try:
            subprocess.run(
                ['osascript', '-e', applescript] + urls,
                check=True,
                capture_output=True
            )
        except subprocess.CalledProcessError as e:
            print(f"  Warning: Failed to create Brave window: {e}")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='VPC - Setup workspace with apps and window layouts'
    )
    parser.add_argument('config', help='Path to .vpc config file')
    args = parser.parse_args()

    print(f"Loading config: {args.config}")
    print(time.strftime("%c"))
    print()

    # Load configuration
    config = VPCConfig(args.config)

    # Switch space
    space_switcher = SpaceSwitcher(config)
    space_switcher.switch_space()

    # Initialize yabai manager
    yabai = YabaiManager(config)
    yabai.apply_space_config()

    # Launch applications
    launcher = AppLauncher(config, yabai)
    launcher.launch_all()

    # Balance space if configured
    yabai.balance_space()

    print()
    print("VPC setup complete!")


if __name__ == '__main__':
    main()
