#!/usr/bin/env python3
"""
Query macOS Calendar events using EventKit
Much faster than AppleScript approach
"""

import sys
import json
from datetime import datetime, timedelta
import time

try:
    import EventKit
    from Foundation import NSDate, NSPredicate
except ImportError:
    print(json.dumps({"error": "PyObjC not installed. Run: pip3 install pyobjc-framework-EventKit"}))
    sys.exit(1)

def nsdate_to_local_string(nsdate):
    """
    Convert NSDate to local timezone string

    Args:
        nsdate: NSDate object

    Returns:
        String in format "YYYY-MM-DD HH:MM:SS" in local timezone
    """
    # Get Unix timestamp from NSDate
    timestamp = nsdate.timeIntervalSince1970()

    # Convert to local datetime
    local_dt = datetime.fromtimestamp(timestamp)

    # Format as string
    return local_dt.strftime("%Y-%m-%d %H:%M:%S")

def get_events(hours_ahead=24, calendars=None):
    """
    Query calendar events

    Args:
        hours_ahead: How many hours ahead to query
        calendars: List of calendar names to query (None = all)
    """
    store = EventKit.EKEventStore.alloc().init()

    # Check authorization status
    auth_status = EventKit.EKEventStore.authorizationStatusForEntityType_(EventKit.EKEntityTypeEvent)

    # Request access if needed (this is async but should work for subsequent calls)
    if auth_status != EventKit.EKAuthorizationStatusAuthorized:
        import time
        import sys as _sys
        _sys.stderr.write(f"DEBUG: Auth status = {auth_status}, requesting permission...\n")

        granted = [None]
        error = [None]
        def callback(g, e):
            granted[0] = g
            error[0] = e

        store.requestFullAccessToEventsWithCompletion_(callback)

        # Wait for callback
        timeout = 10  # seconds
        waited = 0
        while granted[0] is None and waited < timeout:
            time.sleep(0.1)
            waited += 0.1

        _sys.stderr.write(f"DEBUG: Permission granted = {granted[0]}, error = {error[0]}\n")

        if not granted[0]:
            _sys.stderr.write("ERROR: Calendar access not granted\n")
            return []

    # Get calendars
    all_calendars = store.calendarsForEntityType_(EventKit.EKEntityTypeEvent)

    if calendars:
        target_calendars = [c for c in all_calendars if c.title() in calendars]
    else:
        target_calendars = list(all_calendars)

    # Query events
    start_date = NSDate.date()
    end_date = NSDate.dateWithTimeIntervalSinceNow_(hours_ahead * 3600)

    predicate = store.predicateForEventsWithStartDate_endDate_calendars_(
        start_date, end_date, target_calendars
    )

    events = store.eventsMatchingPredicate_(predicate)

    # Format results
    results = []
    for event in events:
        results.append({
            "id": event.calendarItemIdentifier(),
            "title": event.title(),
            "start": nsdate_to_local_string(event.startDate()),
            "end": nsdate_to_local_string(event.endDate()),
            "calendar": event.calendar().title(),
            "notes": event.notes() or "",
            "location": event.location() or "",
            "all_day": event.isAllDay()
        })

    return results

if __name__ == "__main__":
    hours = int(sys.argv[1]) if len(sys.argv) > 1 else 24
    cal_names = sys.argv[2:] if len(sys.argv) > 2 else None

    try:
        events = get_events(hours, cal_names)
        print(json.dumps({"success": True, "events": events, "count": len(events)}, indent=2))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)
