#!/usr/bin/env python3
"""Read-only EventKit probe for the calendar scheduler (sched).

Writes nothing and never asks for Calendar access. It prints:
  1. calendar sources (is there an "On My Mac" local source?)
  2. every calendar with its id and flags
  3. every occurrence of events whose title contains the marker
     (default "sched-probe"), from 3 days ago to 10 days ahead

Sketch: altera/sketches/20261120-142137-MST-calendar-driven-personal-scheduler-sched.md

Usage: .cc/scripts/sched-ek-probe.py [MARKER]
"""

import sys
from datetime import datetime

import EventKit
from Foundation import NSDate

SOURCE_TYPES = {0: "local", 1: "exchange", 2: "caldav/icloud", 3: "mobileme",
                4: "subscribed", 5: "birthdays"}
AUTH = {0: "not determined", 1: "restricted", 2: "denied", 3: "authorized",
        4: "full access", 5: "write only"}


def when(nsdate):
    if nsdate is None:
        return "-"
    return datetime.fromtimestamp(nsdate.timeIntervalSince1970()).strftime(
        "%a %Y-%m-%d %H:%M")


def main():
    marker = sys.argv[1] if len(sys.argv) > 1 else "sched-probe"
    status = EventKit.EKEventStore.authorizationStatusForEntityType_(
        EventKit.EKEntityTypeEvent)
    print(f"auth: {AUTH.get(status, status)}")
    if status not in (3, 4):
        print("No full Calendar access for this app. Not asking; stopping.")
        return 1

    store = EventKit.EKEventStore.alloc().init()

    print("\n== sources")
    for s in store.sources():
        print(f"  {SOURCE_TYPES.get(s.sourceType(), s.sourceType()):14} "
              f"{s.title()}  id={s.sourceIdentifier()}")
    has_local = any(s.sourceType() == 0 for s in store.sources())
    print(f"  local (On My Mac) source present: {has_local}")

    print("\n== calendars")
    cals = list(store.calendarsForEntityType_(EventKit.EKEntityTypeEvent))
    for c in cals:
        print(f"  {c.title()!r}")
        print(f"     id={c.calendarIdentifier()}  source={c.source().title()}"
              f"  subscribed={bool(c.isSubscribed())}"
              f"  writable={bool(c.allowsContentModifications())}")

    print(f"\n== occurrences with {marker!r} in the title (-3d .. +10d)")
    start = NSDate.dateWithTimeIntervalSinceNow_(-3 * 86400)
    end = NSDate.dateWithTimeIntervalSinceNow_(10 * 86400)
    pred = store.predicateForEventsWithStartDate_endDate_calendars_(start, end, cals)
    events = [e for e in store.eventsMatchingPredicate_(pred)
              if marker in (e.title() or "")]
    events.sort(key=lambda e: e.startDate().timeIntervalSince1970())
    if not events:
        print("  none found")
    for e in events:
        moved = (e.occurrenceDate() is not None and
                 e.occurrenceDate().timeIntervalSince1970()
                 != e.startDate().timeIntervalSince1970())
        print(f"  {e.title()!r} in {e.calendar().title()!r}")
        print(f"     start={when(e.startDate())}  occurrence={when(e.occurrenceDate())}"
              f"  start!=occurrence={moved}")
        print(f"     eventIdentifier={e.eventIdentifier()}")
        print(f"     calendarItemIdentifier={e.calendarItemIdentifier()}")
        print(f"     recurring={bool(e.hasRecurrenceRules())}  detached={bool(e.isDetached())}"
              f"  attendees={bool(e.hasAttendees())}  all_day={bool(e.isAllDay())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
