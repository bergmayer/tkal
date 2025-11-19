import Foundation
import EventKit

class EventKitBackend {
    let store: EKEventStore
    private var accessGranted = false

    init() {
        self.store = EKEventStore()
        requestAccess()
    }

    func requestAccess() {
        let semaphore = DispatchSemaphore(value: 0)

        store.requestAccess(to: .event) { [weak self] granted, error in
            self?.accessGranted = granted
            if let error = error {
                print("Error requesting calendar access: \(error.localizedDescription)")
            }
            if !granted {
                print("Calendar access not granted. Please allow access in System Preferences > Security & Privacy > Privacy > Calendars")
            }
            semaphore.signal()
        }

        semaphore.wait()
    }

    func getCalendars() -> [EKCalendar] {
        return store.calendars(for: .event)
    }

    func getCalendar(byTitle title: String) -> EKCalendar? {
        return getCalendars().first { $0.title == title }
    }

    func getCalendar(byIdentifier identifier: String) -> EKCalendar? {
        return store.calendar(withIdentifier: identifier)
    }

    func getEvents(
        calendarIdentifier: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [EKEvent] {
        let start = startDate ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let end = endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        var calendars: [EKCalendar]
        if let identifier = calendarIdentifier,
           let calendar = getCalendar(byIdentifier: identifier) {
            calendars = [calendar]
        } else {
            calendars = getCalendars()
        }

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )

        return store.events(matching: predicate)
    }

    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        calendarIdentifier: String,
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        url: URL? = nil
    ) -> EKEvent? {
        guard let calendar = getCalendar(byIdentifier: calendarIdentifier) else {
            print("Calendar \(calendarIdentifier) not found")
            return nil
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay

        if let location = location {
            event.location = location
        }
        if let notes = notes {
            event.notes = notes
        }
        if let url = url {
            event.url = url
        }

        do {
            try store.save(event, span: .thisEvent)
            return event
        } catch {
            print("Failed to create event: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func updateEvent(_ event: EKEvent) -> Bool {
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            print("Failed to update event: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteEvent(_ event: EKEvent) -> Bool {
        do {
            try store.remove(event, span: .thisEvent)
            return true
        } catch {
            print("Failed to delete event: \(error.localizedDescription)")
            return false
        }
    }

    func searchEvents(searchString: String) -> [EKEvent] {
        let allEvents = getEvents()
        return allEvents.filter { event in
            event.title.lowercased().contains(searchString.lowercased()) ||
            (event.notes?.lowercased().contains(searchString.lowercased()) ?? false) ||
            (event.location?.lowercased().contains(searchString.lowercased()) ?? false)
        }
    }
}
