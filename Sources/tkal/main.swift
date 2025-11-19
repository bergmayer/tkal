import Foundation
import ArgumentParser
import EventKit

struct Tkal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tkal",
        abstract: "macOS native terminal calendar using EventKit",
        version: "1.0.0",
        subcommands: [
            List.self,
            CalendarView.self,
            New.self,
            Search.self,
            Calendars.self,
            At.self,
            Interactive.self
        ]
    )

    @Flag(name: [.short, .long], help: "Launch interactive TUI mode")
    var interactive: Bool = false

    @Flag(name: [.customShort("s"), .long], help: "Launch simple interactive mode")
    var simple: Bool = false

    @Flag(name: [.customShort("v"), .long], help: "Show version")
    var version: Bool = false

    mutating func run() throws {
        if version {
            print("tkal version \(Self.configuration.version)")
            return
        }

        if interactive {
            let backend = EventKitBackend()
            let tui = TUI(backend: backend)
            tui.run()
        } else if simple {
            let backend = EventKitBackend()
            runSimpleMode(backend: backend)
        } else {
            // Default: show today's events (same as 'at' command)
            let backend = EventKitBackend()
            let targetDate = Date()

            // Get events for the day
            let cal = Foundation.Calendar.current
            let startOfDay = cal.startOfDay(for: targetDate)
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

            let events = backend.getEvents(
                calendarIdentifier: nil,
                startDate: startOfDay,
                endDate: endOfDay
            )

            // Filter to events happening at this time
            let activeEvents = events.filter { event in
                event.startDate <= targetDate && event.endDate >= targetDate
            }

            if activeEvents.isEmpty {
                print("No events at \(EventFormatter.dateFormatter.string(from: targetDate))")
            } else {
                print("Events at \(EventFormatter.dateFormatter.string(from: targetDate)):\n")
                for event in activeEvents {
                    print(EventFormatter.format(event))
                }
            }
        }
    }

    private func runSimpleMode(backend: EventKitBackend) {
        print("""
        Available commands:
          t/today     - Show today's events
          w/week      - Show this week's events
          n/new       - Create a new event
          s/search    - Search events
          l/list      - List calendars
          h/help/?    - Show this help
          q/quit      - Exit

        """)

        var running = true

        while running {
            print("tkal> ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
                continue
            }

            switch input {
            case "t", "today":
                showToday(backend: backend)

            case "w", "week":
                showWeek(backend: backend)

            case "n", "new":
                createEventInteractive(backend: backend)

            case "s", "search":
                searchInteractive(backend: backend)

            case "l", "list":
                listCalendars(backend: backend)

            case "h", "help", "?":
                showHelp()

            case "q", "quit", "exit":
                running = false
                print("Goodbye!")

            case "":
                continue

            default:
                print("Unknown command. Type 'h' for help or 'q' to quit")
            }

            print()
        }
    }

    private func showToday(backend: EventKitBackend) {
        let cal = Foundation.Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let events = backend.getEvents(
            calendarIdentifier: nil,
            startDate: start,
            endDate: end
        )

        if events.isEmpty {
            print("No events today")
        } else {
            print("\n📅 Today's Events (\(events.count)):")
            print(String(repeating: "─", count: 60))
            for event in events.sorted(by: { $0.startDate < $1.startDate }) {
                print(EventFormatter.format(event))
            }
        }
    }

    private func showWeek(backend: EventKitBackend) {
        let cal = Foundation.Calendar.current
        let start = cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
        let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!

        let events = backend.getEvents(
            calendarIdentifier: nil,
            startDate: start,
            endDate: end
        )

        print("\n📅 This Week's Events (\(events.count)):")
        print(String(repeating: "─", count: 60))
        print(EventFormatter.formatList(events, groupByDay: true))
    }

    private func showHelp() {
        print("""

        Available commands:
          t/today     - Show today's events
          w/week      - Show this week's events
          n/new       - Create a new event
          s/search    - Search events
          l/list      - List calendars
          h/help/?    - Show this help
          q/quit      - Exit
        """)
    }

    private func listCalendars(backend: EventKitBackend) {
        let calendars = backend.getCalendars()
        print("\n📚 Available Calendars:")
        print(String(repeating: "─", count: 60))
        for cal in calendars {
            let writable = cal.allowsContentModifications ? "✓" : "✗"
            print("\(writable) \(cal.title)")
        }
    }

    private func searchInteractive(backend: EventKitBackend) {
        print("Search for: ", terminator: "")
        fflush(stdout)

        guard let query = readLine()?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            print("Search cancelled")
            return
        }

        let events = backend.searchEvents(searchString: query)

        if events.isEmpty {
            print("No events found matching '\(query)'")
        } else {
            print("\n🔍 Found \(events.count) event(s) matching '\(query)':")
            print(String(repeating: "─", count: 60))
            for event in events.prefix(20).sorted(by: { $0.startDate < $1.startDate }) {
                print(EventFormatter.format(event))
            }
            if events.count > 20 {
                print("\n... and \(events.count - 20) more")
            }
        }
    }

    private func createEventInteractive(backend: EventKitBackend) {
        print("Event title: ", terminator: "")
        fflush(stdout)
        guard let title = readLine()?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            print("Event creation cancelled")
            return
        }

        print("Start date/time (e.g., 'tomorrow 2pm', 'next friday 9am'): ", terminator: "")
        fflush(stdout)
        guard let startStr = readLine()?.trimmingCharacters(in: .whitespaces),
              let startDate = DateParser.parse(startStr) else {
            print("Invalid start date")
            return
        }

        print("End date/time (press Enter for 1 hour from start): ", terminator: "")
        fflush(stdout)
        let endStr = readLine()?.trimmingCharacters(in: .whitespaces)
        let endDate: Date
        if let endStr = endStr, !endStr.isEmpty, let parsed = DateParser.parse(endStr) {
            endDate = parsed
        } else {
            endDate = Foundation.Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
        }

        // Get available calendars
        let calendars = backend.getCalendars().filter { $0.allowsContentModifications }
        guard !calendars.isEmpty else {
            print("No writable calendars available")
            return
        }

        // Select calendar
        print("\nSelect calendar:")
        for (index, cal) in calendars.enumerated() {
            print("  \(index + 1). \(cal.title)")
        }
        print("Calendar number (1-\(calendars.count)): ", terminator: "")
        fflush(stdout)

        let calendarIndex: Int
        if let input = readLine()?.trimmingCharacters(in: .whitespaces),
           let index = Int(input), index > 0, index <= calendars.count {
            calendarIndex = index - 1
        } else {
            calendarIndex = 0
        }

        let selectedCalendar = calendars[calendarIndex]

        // Get location (optional)
        print("Location (optional): ", terminator: "")
        fflush(stdout)
        let location = readLine()?.trimmingCharacters(in: .whitespaces)

        // Create event
        if let event = backend.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarIdentifier: selectedCalendar.calendarIdentifier,
            location: location?.isEmpty == false ? location : nil
        ) {
            print("\n✓ Event created successfully!")
            print(EventFormatter.formatDetailed(event))
        } else {
            print("\n✗ Failed to create event")
        }
    }
}

extension Tkal {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all events between start and end datetime"
        )

        @Option(name: .shortAndLong, help: "Calendar to include")
        var calendar: String?

        @Option(name: .shortAndLong, help: "Number of days to include")
        var days: Int?

        @Flag(name: .shortAndLong, help: "Include all events in one week")
        var week: Bool = false

        @Argument(help: "Date range [START [END]]")
        var dateRange: [String] = []

        func run() throws {
            let backend = EventKitBackend()

            var startDate: Date
            var endDate: Date

            if week {
                // Show events for this week
                let cal = Foundation.Calendar.current
                startDate = cal.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date!
                endDate = cal.date(byAdding: .weekOfYear, value: 1, to: startDate)!
            } else if let days = days {
                // Show events for N days
                startDate = Foundation.Calendar.current.startOfDay(for: Date())
                endDate = Foundation.Calendar.current.date(byAdding: .day, value: days, to: startDate)!
            } else if let range = DateParser.parseRange(dateRange) {
                startDate = range.start
                endDate = range.end
            } else {
                print("Invalid date range")
                return
            }

            let events = backend.getEvents(
                calendarIdentifier: calendar,
                startDate: startDate,
                endDate: endDate
            )

            print(EventFormatter.formatList(events, groupByDay: true))
        }
    }

    struct CalendarView: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "calendar",
            abstract: "Print calendar with agenda"
        )

        @Option(name: .shortAndLong, help: "Calendar to include")
        var calendar: String?

        @Argument(help: "Date range")
        var dateRange: [String] = []

        func run() throws {
            let backend = EventKitBackend()

            let displayMonth: Date
            if let firstArg = dateRange.first, let parsed = DateParser.parse(firstArg) {
                displayMonth = parsed
            } else {
                displayMonth = Date()
            }

            // Get events for the month
            let cal = Foundation.Calendar.current
            let components = cal.dateComponents([.year, .month], from: displayMonth)
            guard let startOfMonth = cal.date(from: components),
                  let endOfMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth) else {
                print("Error calculating month range")
                return
            }

            let events = backend.getEvents(
                calendarIdentifier: calendar,
                startDate: startOfMonth,
                endDate: endOfMonth
            )

            // Display calendar
            print(EventFormatter.formatCalendar(events, month: displayMonth))

            // Display upcoming events
            let upcoming = events
                .filter { $0.startDate >= Date() }
                .sorted { $0.startDate < $1.startDate }
                .prefix(10)

            if !upcoming.isEmpty {
                print("\nUpcoming Events:")
                print(String(repeating: "=", count: 60))
                for event in upcoming {
                    print(EventFormatter.format(event))
                }
            }
        }
    }

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new event"
        )

        @Option(name: .shortAndLong, help: "Calendar to add event to")
        var calendar: String?

        @Option(name: .shortAndLong, help: "Event location")
        var location: String?

        @Option(name: .shortAndLong, help: "Event URL")
        var url: String?

        @Flag(name: .long, help: "All-day event")
        var allDay: Bool = false

        @Argument(help: "Event details: START [END] TITLE [:: NOTES]")
        var details: [String]

        func run() throws {
            let backend = EventKitBackend()

            // Find calendar
            let selectedCalendar: EKCalendar
            if let calId = calendar {
                if let cal = backend.getCalendar(byTitle: calId) ?? backend.getCalendar(byIdentifier: calId) {
                    selectedCalendar = cal
                } else {
                    print("Calendar '\(calId)' not found")
                    return
                }
            } else {
                // Use first writable calendar
                let writableCalendars = backend.getCalendars().filter { $0.allowsContentModifications }
                guard let first = writableCalendars.first else {
                    print("No writable calendars found")
                    return
                }
                selectedCalendar = first
            }

            // Parse details
            guard details.count >= 2 else {
                print("Usage: tkal new START [END] TITLE [:: NOTES]")
                return
            }

            var remainingDetails = details
            let startStr = remainingDetails.removeFirst()
            guard let startDate = DateParser.parse(startStr) else {
                print("Invalid start date: \(startStr)")
                return
            }

            // Check if second argument is a date (end time) or title
            var endDate: Date

            if let secondParsed = DateParser.parse(remainingDetails.first ?? "") {
                endDate = secondParsed
                remainingDetails.removeFirst()
            } else {
                // No end date specified, default to 1 hour later
                endDate = Foundation.Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
            }

            // Everything else is title/notes
            let combined = remainingDetails.joined(separator: " ")

            // Split on ::
            var title: String
            var notes: String?

            if let separatorIndex = combined.range(of: "::") {
                title = String(combined[..<separatorIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
                notes = String(combined[separatorIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                title = combined.trimmingCharacters(in: .whitespaces)
                notes = nil
            }

            guard !title.isEmpty else {
                print("Event title is required")
                return
            }

            // Create event
            if let event = backend.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                calendarIdentifier: selectedCalendar.calendarIdentifier,
                location: location,
                notes: notes,
                isAllDay: allDay,
                url: url.flatMap { URL(string: $0) }
            ) {
                print("Event created successfully:")
                print(EventFormatter.formatDetailed(event))
            } else {
                print("Failed to create event")
            }
        }
    }

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search for events matching a search string"
        )

        @Argument(help: "Search string")
        var searchString: String

        func run() throws {
            let backend = EventKitBackend()
            let events = backend.searchEvents(searchString: searchString)

            if events.isEmpty {
                print("No events found matching '\(searchString)'")
            } else {
                print("Found \(events.count) event(s):\n")
                print(EventFormatter.formatList(events, groupByDay: true))
            }
        }
    }

    struct Calendars: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "calendars",
            abstract: "List all calendars"
        )

        func run() throws {
            let backend = EventKitBackend()
            let calendars = backend.getCalendars()

            print("\nAvailable Calendars:")
            print(String(repeating: "=", count: 60))

            for calendar in calendars {
                let writable = calendar.allowsContentModifications ? "✓" : "✗"
                print("\(writable) \(calendar.title) [\(calendar.calendarIdentifier)]")
            }

            print("\n✓ = writable, ✗ = read-only")
        }
    }

    struct At: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print all events at a specific datetime (defaults to now)"
        )

        @Option(name: .shortAndLong, help: "Calendar to include")
        var calendar: String?

        @Argument(help: "Datetime (defaults to now)")
        var datetime: [String] = []

        func run() throws {
            let backend = EventKitBackend()

            let targetDate: Date
            if datetime.isEmpty || datetime.first == "now" {
                targetDate = Date()
            } else {
                guard let parsed = DateParser.parse(datetime.joined(separator: " ")) else {
                    print("Invalid datetime")
                    return
                }
                targetDate = parsed
            }

            // Get events for the day
            let cal = Foundation.Calendar.current
            let startOfDay = cal.startOfDay(for: targetDate)
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

            let events = backend.getEvents(
                calendarIdentifier: calendar,
                startDate: startOfDay,
                endDate: endOfDay
            )

            // Filter to events happening at this time
            let activeEvents = events.filter { event in
                event.startDate <= targetDate && event.endDate >= targetDate
            }

            if activeEvents.isEmpty {
                print("No events at \(EventFormatter.dateFormatter.string(from: targetDate))")
            } else {
                print("Events at \(EventFormatter.dateFormatter.string(from: targetDate)):\n")
                for event in activeEvents {
                    print(EventFormatter.format(event))
                }
            }
        }
    }

    struct Interactive: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Interactive TUI mode - browse and manage events"
        )

        func run() throws {
            let backend = EventKitBackend()
            let tui = TUI(backend: backend)
            tui.run()
        }
    }
}

Tkal.main()
