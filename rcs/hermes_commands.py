#<[.config/hermes/commands.py]>
"""Hermes commands configuration with dynamic menu generators."""
import re
import subprocess
from pathlib import Path

# ============================================================================
# CONSTANTS
# ============================================================================

VPC_DIR = Path.home() / "dotfiles" / "vpc"

# User-defined static VPC key mappings
# Format: {'key': 'vpc_filename_without_extension'}
VPC_STATIC_MAP = {
    # Example: 's': 'simplymeet',
}

SNIPPETS_FILE = Path.home() / "ProtonDrive" / "_config" / "snippets.txt"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def parse_launchctl_services():
    """Get org.pancia services with their running status."""
    try:
        result = subprocess.run(
            ['launchctl', 'list'],
            capture_output=True, text=True
        )
        services = []
        for line in result.stdout.strip().split('\n')[1:]:
            parts = line.split('\t')
            if len(parts) >= 3 and 'org.pancia' in parts[2]:
                name = parts[2].replace('org.pancia.', '')
                running = parts[0] != '-'
                services.append({'name': name, 'running': running})
        return sorted(services, key=lambda s: s['name'])
    except Exception:
        return []


def assign_keys(items, key_func=lambda x: x[0].lower()):
    """Assign unique single-char keys to items."""
    result = {}
    used = set()
    for item in items:
        key = None
        for char in key_func(item):
            if char.isalnum() and char not in used:
                key = char
                used.add(char)
                break
        if key:
            result[key] = item
    return result


# ============================================================================
# VPC MENU FUNCTIONS
# ============================================================================

def get_vpc_files():
    """Scan VPC directory and return list of .vpc files"""
    if not VPC_DIR.exists():
        return []
    return list(VPC_DIR.glob("*.vpc"))


def assign_vpc_keys(menu, vpc_names, vpc_map, depth=0):
    """
    Recursively assign keys to VPCs based on their names.
    Handle conflicts by creating nested menus.
    """
    if depth > 10:
        return menu

    char_groups = {}
    for vpc_name in vpc_names:
        if depth < len(vpc_name):
            char = vpc_name[depth].lower()
        else:
            char = '0'

        if char not in char_groups:
            char_groups[char] = []
        char_groups[char].append(vpc_name)

    for char, vpcs in char_groups.items():
        if char in menu and not isinstance(menu[char], dict):
            vpc_list = ", ".join(sorted(vpcs))
            if len(vpc_list) > 50:
                vpc_list = vpc_list[:47] + "..."
            nested_menu = {'_desc': vpc_list}
            menu[char + char] = assign_vpc_keys(nested_menu, vpcs, vpc_map, depth + 1)
        elif len(vpcs) == 1:
            vpc_name = vpcs[0]
            vpc_path = vpc_map[vpc_name]
            menu[char] = [vpc_name, f"/Users/anthony/dotfiles/bin/vpc.py '{vpc_path}'"]
        else:
            vpc_list = ", ".join(sorted(vpcs))
            if len(vpc_list) > 50:
                vpc_list = vpc_list[:47] + "..."
            if char not in menu or not isinstance(menu[char], dict):
                menu[char] = {'_desc': vpc_list}
            menu[char] = assign_vpc_keys(menu[char], vpcs, vpc_map, depth + 1)

    return menu


def build_vpc_menu():
    """Build VPC menu with smart key assignment and conflict resolution"""
    vpc_files = get_vpc_files()
    if not vpc_files:
        return {
            '_desc': 'VPC Workspaces',
            'x': ['No VPC files found', 'echo "No .vpc files found in ~/dotfiles/vpc/"']
        }

    vpc_map = {}
    for vpc_path in vpc_files:
        vpc_name = vpc_path.stem
        vpc_map[vpc_name] = vpc_path

    menu = {'_desc': 'VPC Workspaces'}
    assigned_vpcs = set()

    # First pass: assign static mappings
    for key, vpc_name in VPC_STATIC_MAP.items():
        if vpc_name in vpc_map:
            vpc_path = vpc_map[vpc_name]
            menu[key] = [vpc_name, f"/Users/anthony/dotfiles/bin/vpc.py '{vpc_path}'"]
            assigned_vpcs.add(vpc_name)

    # Second pass: assign remaining VPCs dynamically
    unassigned_vpcs = [name for name in vpc_map.keys() if name not in assigned_vpcs]
    if unassigned_vpcs:
        menu = assign_vpc_keys(menu, unassigned_vpcs, vpc_map)

    return menu


# ============================================================================
# SNIPPETS MENU FUNCTIONS
# ============================================================================

def parse_snippets_file():
    """Parse snippets.txt and return list of snippets."""
    if not SNIPPETS_FILE.exists():
        return []

    snippets = []
    current_snippet = None

    with open(SNIPPETS_FILE, 'r') as f:
        for line in f:
            line = line.rstrip('\n')
            # Check if this is a new snippet header (contains ':')
            if ':' in line and (current_snippet is None or line.split(':')[0].strip()):
                parts = line.split(':', 1)
                if len(parts) == 2:
                    title = parts[0].strip()
                    content = parts[1].strip()

                    # Save previous snippet
                    if current_snippet:
                        snippets.append(current_snippet)

                    # Parse optional trigger: "My Snippet [;ms]" -> title, trigger
                    match = re.match(r'^(.+?)\s*\[([^\]]+)\]\s*$', title)
                    if match:
                        clean_title = match.group(1).strip()
                        trigger = match.group(2)
                    else:
                        clean_title = title
                        trigger = None

                    current_snippet = {
                        'title': clean_title,
                        'content': content,
                        'trigger': trigger
                    }
            elif current_snippet and line.strip():
                # Continue previous snippet content
                current_snippet['content'] += '\n' + line

    # Don't forget the last snippet
    if current_snippet:
        snippets.append(current_snippet)

    return snippets


def build_snippets_menu():
    """Build snippets menu with all snippets and edit option."""
    snippets = parse_snippets_file()

    menu = {'_desc': '+snippets'}

    # Add edit option first
    menu['e'] = ['Edit Snippets', f"vim '{SNIPPETS_FILE}'"]

    if not snippets:
        menu['x'] = ['No snippets found', f"echo 'No snippets in {SNIPPETS_FILE}'"]
        return menu

    # Assign keys to snippets
    used_keys = {'e'}  # 'e' is reserved for edit

    for snippet in snippets:
        title = snippet['title']
        content = snippet['content']
        trigger = snippet.get('trigger', '')

        # Find a unique key for this snippet
        key = None
        # Try first letter, then subsequent letters
        for char in title.lower():
            if char.isalnum() and char not in used_keys:
                key = char
                used_keys.add(char)
                break

        if not key:
            # Try numbers if no letters available
            for i in range(10):
                if str(i) not in used_keys:
                    key = str(i)
                    used_keys.add(key)
                    break

        if key:
            # Display title with trigger if present
            display = title
            if trigger:
                display = f"{title} [{trigger}]"

            # Truncate content preview for display
            preview = content.replace('\n', ' ')[:40]
            if len(content) > 40:
                preview += '...'

            # Use pbcopy to copy to clipboard
            # Escape single quotes in content
            escaped_content = content.replace("'", "'\\''")
            menu[key] = [display, f"echo '{escaped_content}' | pbcopy && echo 'Copied: {title}'"]

    return menu


# ============================================================================
# DYNAMIC MENU GENERATORS
# ============================================================================

def build_services_menu():
    """Generate services menu with live status indicators."""
    services = parse_launchctl_services()
    if not services:
        return {
            '_desc': '+services',
            'x': ['No services found', 'echo "No org.pancia services found"']
        }

    menu = {'_desc': '+services'}
    key_map = assign_keys([s['name'] for s in services])

    for key, name in key_map.items():
        svc = next(s for s in services if s['name'] == name)
        indicator = '\u25cf' if svc['running'] else '\u25cb'
        menu[key] = {
            '_desc': f"{name} {indicator}",
            's': ['Start', f"service start {name}"],
            't': ['Stop', f"service stop {name}"],
            'r': ['Restart', f"service restart {name}"],
            'l': ['Log', f"service log {name}"],
            'e': ['Edit', f"service edit {name}"],
        }

    menu['n'] = ['New Service', "service create $(read --prompt-str 'name>')"]
    return menu


# ============================================================================
# COMMANDS
# ============================================================================

COMMANDS = {
    'c': ['calendar', "agenda $(read --prompt-str 'hours>' -c '24' HOURS && echo $HOURS)"],

    'd': {
        '_desc': '+dotfiles',
        'e': ['Edit dotfiles', 'cd ~/dotfiles && v'],
    },

    'j': ['Emoji Picker', 'hs -c \'hs.eventtap.keyStroke({"cmd", "ctrl", "alt", "shift"}, "j")\''],

    'f': {
        '_desc': '+finder',
        '_': ['View spirituality', 'finder-here $HOME/ProtonDrive/_spirituality'],
        'b': ['View MediaBoard', 'finder-here $HOME/MediaBoard'],
        'd': ['View Dotfiles', 'finder-here $HOME/dotfiles'],
        'h': ['View Home', 'finder-here $HOME'],
        'i': ['View inbox', 'finder-here $HOME/ProtonDrive/_inbox/'],
        'm': ['View Media', 'finder-here $HOME/Media'],
        'o': ['View ProtonDrive', 'finder-here $HOME/ProtonDrive'],
        'p': ['View Projects', 'finder-here $HOME/projects'],
        's': ['View Screenshots', 'finder-here $HOME/Screenshots'],
        't': ['View transcripts', 'finder-here $HOME/transcripts'],
        'w': ['View Downloads', 'finder-here $HOME/Downloads'],
        'y': ['View YTDL', 'finder-here $HOME/Downloads/ytdl/'],
    },

    'a': ['App Launcher', ['/Users/anthony/dotfiles/bin/app-launcher']],
    'w': ['Window Switcher', ['/Users/anthony/dotfiles/bin/window-switcher']],

    'q': {
        '_desc': '+apps',
        'b': ['Brave', "open -a 'Brave Browser'"],
        'c': ['Claude', 'open -a Claude'],
        'd': ['Discord', 'open -a Discord'],
        'g': ['Signal', 'open -a Signal'],
        'k': ['kosmik', "open -a 'Kosmik'"],
        'l': ['Telegram', "open -a 'Telegram'"],
        'o': ['Opera', "open -na 'Opera'"],
        'p': ['Proton Password', "open -a 'Proton Pass'"],
        's': ['Spotify', 'open -a Spotify'],
        't': ['iTerm', "open -a 'iTerm'"],
        'x': ['Opera GX', "open -a 'Opera GX'"],
        'z': ['Zen Browser', "open -a 'Zen Browser'"],
        'w': {
            '_desc': '+new window',
            'b': ['Brave', "open -na 'Brave Browser'"],
            'o': ['Opera', "open -na 'Opera'"],
            't': ['iTerm', "open -na 'iTerm'"],
            'x': ['Opera GX', "open -na 'Opera GX'"],
        },
    },

    'h': {
        '_desc': '+hammerspoon',
        'r': ['Reload', 'hs -c \'hs.eventtap.keyStroke({"cmd", "ctrl"}, "r")\''],
        'c': ['Console', "hs -c 'hs.openConsole()'"],
        'e': ['Edit init.lua', 'vim ~/dotfiles/lib/lua/init.lua'],
        's': ['Edit Seeds', 'vim ~/dotfiles/lib/lua/seeds/'],
    },

    'k': {
        '_desc': '+karabiner',
        'e': ['Edit Config', 'vim ~/dotfiles/rcs/karabiner.json'],
        'v': ['Event Viewer', "open -a 'Karabiner-EventViewer'"],
        'k': ['Karabiner Elements', "open -a 'Karabiner-Elements'"],
    },

    'p': build_snippets_menu,  # Dynamic generator

    's': build_services_menu,  # Dynamic generator

    'v': build_vpc_menu,  # Dynamic generator

    'y': {
        '_desc': '+ytdl',
        'i': ['ytdl interactive', 'ytdl'],
        'y': ['ytdl clipboard', 'ytdl clipboard'],
    },

    'm': {
        '_desc': '+music',
        'c': ['Play or Pause', 'cmus-remote --pause'],
        'e': ['Edit Track', 'cmedit'],
        'y': ['Redownload from Youtube', 'cmytdl'],
        'a': ['Open Track in Audacity', 'cmaudacity'],
        's': ['Select Track by Playlist', 'music select'],
        't': ['Select Track by Tags', 'music select --filter-by-tags'],
        'n': ['Next Track', 'cmus-remote --next'],
        'p': ['Prev Track', 'cmus-remote --prev'],
        'l': ['Seek 10 Forwards', 'cmus-remote --seek +10'],
        'h': ['Seek 10 Backwards', 'cmus-remote --seek -10'],
        '.': ['Seek 30 Forwards', 'cmus-remote --seek +30'],
        ',': ['Seek 30 Backwards', 'cmus-remote --seek -30'],
        'j': ['Volume Down', 'cmus-remote --volume -5'],
        'k': ['Volume Up', 'cmus-remote --volume +5'],
    },

    '=': ['edit Hermes config', 'vim ~/dotfiles/rcs/hermes_commands.py'],
    '-': ["superwhisper: $(echo `cat ~/private/.superwhisper.counter` '/' `cat ~/private/.superwhisper.max-count`)", '~/private/bin/superwhisper_reset'],
}
