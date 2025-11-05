#!/usr/bin/env python3
"""Check calendar authorization status"""

import EventKit

status = EventKit.EKEventStore.authorizationStatusForEntityType_(EventKit.EKEntityTypeEvent)

status_names = {
    0: "Not Determined (not asked yet)",
    1: "Restricted (parental controls)",
    2: "Denied",
    3: "Authorized (legacy)",
    4: "Full Access"
}

print(f"Calendar Access Status: {status_names.get(status, f'Unknown ({status})')}")

if status == 2:
    print("\n❌ Python does NOT have calendar access")
    print("   Go to: System Settings → Privacy & Security → Calendars")
    print("   Enable: Python or python3")
elif status in [3, 4]:
    print("\n✓ Python has calendar access")
else:
    print("\n⚠️  Permission status unclear - try running the calendar_query.py script")
