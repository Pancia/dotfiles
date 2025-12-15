import EventKit
import Foundation

let hours = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 8 : 8

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)

store.requestFullAccessToEvents { granted, error in
    defer { semaphore.signal() }
    guard granted else { return }

    let now = Date()
    let later = Calendar.current.date(byAdding: .hour, value: hours, to: now)!
    let predicate = store.predicateForEvents(withStart: now, end: later, calendars: nil)
    let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

    let timeFmt = DateFormatter()
    timeFmt.dateFormat = "HH:mm"

    let dayFmt = DateFormatter()
    dayFmt.dateFormat = "EEEE, MMM d"

    var currentDay = ""
    for e in events {
        let day = dayFmt.string(from: e.startDate)
        if day != currentDay {
            if !currentDay.isEmpty { print() }
            print(day)
            currentDay = day
        }
        print("  \(timeFmt.string(from: e.startDate)) - \(e.title ?? "")")
    }
}

semaphore.wait()
