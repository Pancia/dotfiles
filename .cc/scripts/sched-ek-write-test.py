#!/usr/bin/env python3
"""Write test for the calendar scheduler (sched): how EventKit identifies runs.

Touches only the "Automations" calendar, and only events whose title starts
with "sched-probe". It:
  1. makes "sched-probe daily", repeating daily from 2 days ago at 20:00
  2. moves tomorrow's occurrence 1 hour later ("this event only")
  3. makes "sched-probe once" tomorrow at 21:00, then moves it 1 hour later
  4. reads everything back through a fresh store and prints the fields
  5. deletes every "sched-probe" event in Automations

Usage: .cc/scripts/sched-ek-write-test.py [--keep | --cleanup]
  --keep     skip step 5
  --cleanup  only run step 5

Sketch: altera/sketches/20261120-142137-MST-calendar-driven-personal-scheduler-sched.md
"""

import sys
from datetime import datetime, timedelta

import EventKit
from Foundation import NSDate

CAL_TITLE = "Automations"
PREFIX = "sched-probe"
THIS_EVENT, FUTURE_EVENTS = 0, 1


def ns(dt):
    return NSDate.dateWithTimeIntervalSince1970_(dt.timestamp())


def when(nsdate):
    if nsdate is None:
        return "-"
    return datetime.fromtimestamp(nsdate.timeIntervalSince1970()).strftime("%a %m-%d %H:%M")


def automations(store):
    cals = [c for c in store.calendarsForEntityType_(EventKit.EKEntityTypeEvent)
            if c.title() == CAL_TITLE]
    if len(cals) != 1:
        sys.exit(f"need exactly one calendar titled {CAL_TITLE!r}, found {len(cals)}")
    cal = cals[0]
    if cal.isSubscribed() or not cal.allowsContentModifications():
        sys.exit(f"{CAL_TITLE!r} is subscribed or read-only")
    return cal


def probe_events(store, cal, days_back=3, days_ahead=10):
    pred = store.predicateForEventsWithStartDate_endDate_calendars_(
        NSDate.dateWithTimeIntervalSinceNow_(-days_back * 86400),
        NSDate.dateWithTimeIntervalSinceNow_(days_ahead * 86400), [cal])
    evs = [e for e in store.eventsMatchingPredicate_(pred)
           if (e.title() or "").startswith(PREFIX)]
    return sorted(evs, key=lambda e: e.startDate().timeIntervalSince1970())


def save(store, ev, span):
    ok, err = store.saveEvent_span_commit_error_(ev, span, True, None)
    if not ok:
        sys.exit(f"save failed for {ev.title()!r}: {err}")


def new_event(store, cal, title, start):
    ev = EventKit.EKEvent.eventWithEventStore_(store)
    ev.setTitle_(title)
    ev.setCalendar_(cal)
    ev.setStartDate_(ns(start))
    ev.setEndDate_(ns(start + timedelta(minutes=30)))
    return ev


def move(ev, hours):
    ev.setStartDate_(ev.startDate().dateByAddingTimeInterval_(hours * 3600))
    ev.setEndDate_(ev.endDate().dateByAddingTimeInterval_(hours * 3600))


def cleanup(store, cal):
    removed = 0
    for _ in range(5):  # a series delete can leave detached occurrences behind
        evs = probe_events(store, cal, days_back=30, days_ahead=30)
        if not evs:
            break
        ev = evs[0]
        span = FUTURE_EVENTS if ev.hasRecurrenceRules() else THIS_EVENT
        ok, err = store.removeEvent_span_commit_error_(ev, span, True, None)
        if not ok:
            sys.exit(f"delete failed for {ev.title()!r}: {err}")
        removed += 1
    left = probe_events(store, cal, days_back=30, days_ahead=30)
    print(f"cleanup: {removed} delete call(s), {len(left)} {PREFIX} event(s) left")


def main():
    args = sys.argv[1:]
    store = EventKit.EKEventStore.alloc().init()
    cal = automations(store)
    if "--cleanup" in args:
        cleanup(store, cal)
        return
    if probe_events(store, cal):
        sys.exit(f"{PREFIX} events already exist; run with --cleanup first")

    today20 = datetime.now().replace(hour=20, minute=0, second=0, microsecond=0)
    daily = new_event(store, cal, f"{PREFIX} daily", today20 - timedelta(days=2))
    daily.addRecurrenceRule_(EventKit.EKRecurrenceRule.alloc()
                             .initRecurrenceWithFrequency_interval_end_(0, 1, None))
    save(store, daily, FUTURE_EVENTS)

    tomorrow20 = today20 + timedelta(days=1)
    occ = [e for e in probe_events(store, cal)
           if abs(e.startDate().timeIntervalSince1970() - tomorrow20.timestamp()) < 60]
    if len(occ) != 1:
        sys.exit(f"expected 1 occurrence tomorrow 20:00, found {len(occ)}")
    move(occ[0], 1)
    save(store, occ[0], THIS_EVENT)

    once = new_event(store, cal, f"{PREFIX} once", tomorrow20 + timedelta(hours=1))
    save(store, once, THIS_EVENT)
    once_id = once.eventIdentifier()
    once_occ_before = once.occurrenceDate()
    once_item_before = once.calendarItemIdentifier()
    move(once, 1)
    save(store, once, THIS_EVENT)

    fresh = EventKit.EKEventStore.alloc().init()
    print(f"one-off before move: occurrence={when(once_occ_before)}"
          f"  eventIdentifier={once_id}  calendarItemIdentifier={once_item_before}\n")
    for e in probe_events(fresh, automations(fresh)):
        print(f"{e.title()!r:22} start={when(e.startDate())}  occurrence={when(e.occurrenceDate())}"
              f"  recurring={bool(e.hasRecurrenceRules())}  detached={bool(e.isDetached())}")
        print(f"{'':22} eventIdentifier={e.eventIdentifier()}  "
              f"calendarItemIdentifier={e.calendarItemIdentifier()}")

    if "--keep" not in args:
        print()
        cleanup(fresh, automations(fresh))


if __name__ == "__main__":
    main()
