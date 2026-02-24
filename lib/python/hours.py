"""Calculate hours worked from time entry strings.

Usage:
    from hours import calc_hours

    entries = [
        "1/29 : 01:00 - 01:50 (ai-mult 2.00) - setting up",
        "1/31 : 21:00 - 22:00 (ai-mult 2.00) - planning",
        "2/3  : 19:40 - 01:00 - no multiplier entry",
    ]
    calc_hours(entries)
"""

import re
from datetime import datetime, timedelta


def parse_entry(line):
    """Parse a time entry string into components.

    Expected format:
        DATE : HH:MM - HH:MM (ai-mult N.NN) - description
    The (ai-mult ...) and description are optional.
    """
    m = re.match(
        r'\s*(\S+)\s*:\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})'
        r'(?:\s*\(ai-mult\s+([\d.]+)\))?'
        r'(?:\s*-\s*(.*))?',
        line
    )
    if not m:
        raise ValueError(f"Cannot parse: {line}")

    date, start, end, mult, desc = m.groups()
    mult = float(mult) if mult else 1.0
    desc = (desc or '').strip()
    return date, start, end, mult, desc


def duration(start, end):
    """Calculate duration between two HH:MM times, handling overnight spans."""
    s = datetime.strptime(start, '%H:%M')
    e = datetime.strptime(end, '%H:%M')
    dur = e - s
    if dur < timedelta(0):
        dur += timedelta(days=1)
    return dur.total_seconds() / 3600


def calc_hours(entries):
    """Parse and display hours for a list of time entry strings."""
    total = 0
    for line in entries:
        line = line.strip()
        if not line:
            continue
        date, start, end, mult, desc = parse_entry(line)
        raw = duration(start, end)
        adj = raw * mult
        total += adj
        mult_str = f'  x{mult:.0f}  =  {adj:.2f}h' if mult != 1.0 else ''
        label = f'  - {desc}' if desc else ''
        print(f'{date:6s}  {start} - {end}  =  {raw:.2f}h{mult_str}{label}')

    print()
    print(f'Total: {total:.2f}h')
    return total
