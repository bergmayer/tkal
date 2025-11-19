import Foundation
import EventKit
import NCursesBridge

class TUI {
    private var calendarWindow: OpaquePointer?
    private var eventsWindow: OpaquePointer?
    private var statusWindow: OpaquePointer?
    private var selectedDate: Date
    private var calendarScrollMonths = 0  // How many months to scroll the calendar view
    private let backend: EventKitBackend
    private var selectedEventIndex = 0
    private var allUpcomingEvents: [EKEvent] = []  // All events from start date forward
    private var enabledCalendars: Set<String>  // Track which calendars are enabled
    private var eventScrollOffset = 0  // For scrolling event list
    private var focusOnCalendar = false  // Which panel has focus (default to events)
    private var statusMessage = ""  // Message to show in status bar
    private var use24HourTime = false  // Time format preference (default to 12-hour/AM-PM)

    init(backend: EventKitBackend) {
        self.backend = backend
        self.selectedDate = Date()
        self.calendarScrollMonths = 0

        // Load config, or use defaults
        if let config = Config.load() {
            self.enabledCalendars = Set(config.enabledCalendars)
            self.use24HourTime = config.use24HourTime
        } else {
            // Enable all calendars by default, use 12-hour time
            self.enabledCalendars = Set(backend.getCalendars().map { $0.calendarIdentifier })
            self.use24HourTime = false
        }
    }

    func run() {
        // Initialize ncurses
        initscr()
        cbreak()
        noecho()
        keypad(stdscr, true)
        curs_set(0) // Hide cursor

        // Enable colors if available
        if has_colors() {
            start_color()
            init_pair(1, Int16(COLOR_WHITE), Int16(COLOR_BLUE))    // Header
            init_pair(2, Int16(COLOR_BLACK), Int16(COLOR_WHITE))   // Selected
            init_pair(3, Int16(COLOR_YELLOW), Int16(COLOR_BLACK))  // Today
            init_pair(4, Int16(COLOR_GREEN), Int16(COLOR_BLACK))   // Event day
            init_pair(5, Int16(COLOR_WHITE), Int16(COLOR_BLACK))   // Alternate month bg
        }

        // Create windows
        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(stdscr, &maxY, &maxX)

        let calendarWidth = min(30, maxX / 3)

        // Calendar on left
        calendarWindow = newwin(maxY - 2, calendarWidth, 0, 0)

        // Events on right
        eventsWindow = newwin(maxY - 2, maxX - calendarWidth, 0, calendarWidth)

        // Status bar at bottom
        statusWindow = newwin(2, maxX, maxY - 2, 0)

        // Enable scrolling in events window
        scrollok(eventsWindow, true)

        // Clear and refresh stdscr first
        clear()
        refresh()

        // Draw initial screen
        drawCalendar()
        drawEvents()
        drawStatus()

        // Force final update and give terminal time to render
        doupdate()
        napms(50)  // Sleep for 50ms to let terminal update

        // Main loop
        var running = true
        while running {
            let ch = getch()

            switch ch {
            case 113, 81: // 'q' or 'Q'
                running = false

            case 9: // Tab - switch focus between panels
                focusOnCalendar = !focusOnCalendar
                statusMessage = ""

            case 106, KEY_DOWN: // 'j' or down arrow - vim binding
                if focusOnCalendar {
                    navigateCalendarDown()  // Move down one week
                } else {
                    navigateEventDown()
                }
                statusMessage = ""

            case 107, KEY_UP: // 'k' or up arrow - vim binding
                if focusOnCalendar {
                    navigateCalendarUp()  // Move up one week
                } else {
                    navigateEventUp()
                }
                statusMessage = ""

            case 104, KEY_LEFT: // 'h' or left arrow - vim binding
                if focusOnCalendar {
                    navigateDayLeft()  // Previous day
                } else {
                    // In events view, left arrow goes back to calendar
                    focusOnCalendar = true
                }
                statusMessage = ""

            case 108, KEY_RIGHT: // 'l' or right arrow - vim binding
                if focusOnCalendar {
                    navigateDayRight()  // Next day
                } else {
                    // In events view, right arrow opens event detail
                    if !allUpcomingEvents.isEmpty && selectedEventIndex < allUpcomingEvents.count {
                        showEventDetail(allUpcomingEvents[selectedEventIndex])
                    }
                }
                statusMessage = ""

            case 10, 13: // Enter - show full event view
                if !focusOnCalendar && !allUpcomingEvents.isEmpty && selectedEventIndex < allUpcomingEvents.count {
                    showEventDetail(allUpcomingEvents[selectedEventIndex])
                }
                statusMessage = ""

            case 110: // 'n' - create new event
                createNewEvent()
                statusMessage = ""

            case 114: // 'r' - refresh
                statusMessage = ""
                break // Just redraw, events will be reloaded

            case 116: // 't' - today
                selectedDate = Date()
                calendarScrollMonths = 0
                selectedEventIndex = 0
                eventScrollOffset = 0
                statusMessage = ""

            case 99: // 'c' - toggle calendars
                toggleCalendars()
                statusMessage = ""

            case 47: // '/' - search events
                searchEvents()
                statusMessage = ""

            case 63: // '?' - show help
                showHelp()
                statusMessage = ""

            case 84: // 'T' (uppercase) - toggle time format
                use24HourTime = !use24HourTime
                saveConfig()
                statusMessage = use24HourTime ? "Switched to 24-hour time" : "Switched to 12-hour time"

            default:
                // Invalid key pressed
                statusMessage = "Press ? for help"
            }

            // Redraw after processing input
            if running {
                drawCalendar()
                drawEvents()
                drawStatus()
                refresh()
                doupdate()
            }
        }

        // Clean up
        delwin(calendarWindow)
        delwin(eventsWindow)
        delwin(statusWindow)
        endwin()
    }

    private func drawCalendar() {
        guard let win = calendarWindow else { return }

        wclear(win)

        // Draw box with green color if focused
        if focusOnCalendar {
            wattron(win, COLOR_PAIR(4))
        }
        box(win, 0, 0)
        if focusOnCalendar {
            wattroff(win, COLOR_PAIR(4))
        }

        // Draw title
        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        let title = " Calendar "
        bridge_mvwprintw(win, 0, 2, title)
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(win, &maxY, &maxX)

        let cal = Calendar.current
        var row: Int32 = 2

        // Draw multiple months (scrollable)
        // Start from calendarScrollMonths offset
        for monthOffset in calendarScrollMonths..<(calendarScrollMonths + 12) {
            if row >= maxY - 1 {
                break
            }

            guard let monthDate = cal.date(byAdding: .month, value: monthOffset, to: Date()) else {
                continue
            }

            let components = cal.dateComponents([.year, .month], from: monthDate)
            guard let firstOfMonth = cal.date(from: components) else { continue }

            // Alternate background colors for readability
            let colorPair = (monthOffset % 2 == 0) ? 0 : 5

            if colorPair == 5 {
                wattron(win, COLOR_PAIR(5))
            }

            // Month/Year header
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let monthYear = formatter.string(from: monthDate)

            wattron(win, Int32(bridge_a_bold()))
            bridge_mvwprintw(win, row, 2, monthYear)
            wattroff(win, Int32(bridge_a_bold()))
            row += 1

            // Day headers
            bridge_mvwprintw(win, row, 2, "Mo Tu We Th Fr Sa Su")
            row += 1

            // Calculate days
            let firstWeekday = cal.component(.weekday, from: firstOfMonth)
            let daysInMonth = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30

            // Adjust for Monday start (weekday 1=Sunday, we want Monday=0)
            let adjustedFirstWeekday = (firstWeekday == 1) ? 6 : (firstWeekday - 2)

            var dayRow: Int32 = row
            var col: Int32 = 2 + Int32(adjustedFirstWeekday * 3)

            let today = cal.startOfDay(for: Date())
            let selectedDay = cal.startOfDay(for: selectedDate)

            for day in 1...daysInMonth {
                // Stop if we're too close to the bottom border
                if dayRow >= maxY - 1 {
                    break
                }

                guard let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) else {
                    continue
                }
                let dayOfMonth = cal.startOfDay(for: date)

                // Check if this day has events
                let hasEvents = hasEventsOnDay(date)

                // Highlight today
                if dayOfMonth == today {
                    wattron(win, COLOR_PAIR(3) | Int32(bridge_a_bold()))
                }
                // Highlight selected date
                if dayOfMonth == selectedDay {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }
                // Show events in green
                else if hasEvents {
                    wattron(win, COLOR_PAIR(4))
                }

                bridge_mvwprintw(win, dayRow, col, String(format: "%2d", day))

                wattroff(win, COLOR_PAIR(3) | Int32(bridge_a_bold()))
                wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                wattroff(win, COLOR_PAIR(4))

                col += 3
                if col >= 2 + 21 { // 7 days * 3 chars
                    col = 2
                    dayRow += 1
                }
            }

            row = dayRow + 2  // Add spacing between months

            if colorPair == 5 {
                wattroff(win, COLOR_PAIR(5))
            }
        }

        wrefresh(win)
    }

    private func drawEvents() {
        guard let win = eventsWindow else { return }

        wclear(win)

        // Draw box with green color if focused
        if !focusOnCalendar {
            wattron(win, COLOR_PAIR(4))
        }
        box(win, 0, 0)
        if !focusOnCalendar {
            wattroff(win, COLOR_PAIR(4))
        }

        // Draw title
        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        let title = " Events "
        bridge_mvwprintw(win, 0, 2, title)
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        // Get events starting from selectedDate (always start from highlighted day)
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: selectedDate)
        // Get events for next 90 days
        let endDate = cal.date(byAdding: .day, value: 90, to: startOfDay)!

        // Filter events by enabled calendars
        let allEvents = backend.getEvents(
            startDate: startOfDay,
            endDate: endDate
        )

        allUpcomingEvents = allEvents.filter { event in
            enabledCalendars.contains(event.calendar.calendarIdentifier)
        }.sorted { $0.startDate < $1.startDate }

        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(win, &maxY, &maxX)

        if allUpcomingEvents.isEmpty {
            bridge_mvwprintw(win, 2, 2, "No upcoming events")
        } else {
            var row: Int32 = 2
            var currentDay: Date?
            let dayFormatter = DateFormatter()
            dayFormatter.dateStyle = .medium

            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.dateFormat = "HH:mm"

            // Apply scroll offset
            let visibleEvents = allUpcomingEvents.dropFirst(eventScrollOffset)

            for (index, event) in visibleEvents.enumerated() {
                if row >= maxY - 1 {
                    break // Don't overflow window
                }

                let eventDay = cal.startOfDay(for: event.startDate)

                // Print day header if this is a new day
                if currentDay == nil || !cal.isDate(eventDay, inSameDayAs: currentDay!) {
                    currentDay = eventDay
                    let dayStr = dayFormatter.string(from: eventDay)

                    if row > 2 {
                        row += 1 // Add spacing between days
                    }

                    // Check if we have room for day header
                    if row >= maxY - 1 {
                        break
                    }

                    wattron(win, Int32(bridge_a_bold()))
                    bridge_mvwprintw(win, row, 2, dayStr)
                    wattroff(win, Int32(bridge_a_bold()))
                    row += 1
                }

                // Check if we have room for this event
                if row >= maxY - 1 {
                    break
                }

                let actualIndex = eventScrollOffset + index

                // Highlight selected event
                if actualIndex == selectedEventIndex && !focusOnCalendar {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                    bridge_mvwprintw(win, row, 1, ">")
                }

                // Format event time - use simple format
                var timeStr = ""
                if event.isAllDay {
                    timeStr = "All Day "
                } else {
                    let components = cal.dateComponents([.hour, .minute], from: event.startDate)
                    if let hour = components.hour, let minute = components.minute {
                        if use24HourTime {
                            timeStr = String(format: "%02d:%02d", hour, minute)
                        } else {
                            let period = hour >= 12 ? "PM" : "AM"
                            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
                            timeStr = String(format: "%2d:%02d %@", displayHour, minute, period)
                        }
                    }
                }

                // Truncate title to fit window
                let maxTitleLen = Int(maxX) - 15
                let title = cleanString(event.title ?? "Untitled")
                let truncatedTitle = title.count > maxTitleLen ? String(title.prefix(maxTitleLen - 3)) + "..." : title

                let eventLine = "  \(timeStr) \(truncatedTitle)"
                bridge_mvwprintw(win, row, 2, eventLine)

                if actualIndex == selectedEventIndex && !focusOnCalendar {
                    wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                row += 1
            }
        }

        wrefresh(win)
    }

    private func drawStatus() {
        guard let win = statusWindow else { return }

        wclear(win)
        wattron(win, COLOR_PAIR(1))

        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(win, &maxY, &maxX)

        // Fill status bar
        for x in 0..<maxX {
            bridge_mvwaddch(win, 0, x, UInt32(ord(" ")))
        }

        // Show status message if present, otherwise show minimal help
        let help: String
        if !statusMessage.isEmpty {
            help = " \(statusMessage) "
        } else {
            help = " ?:Help "
        }
        bridge_mvwprintw(win, 0, 2, help)

        wattroff(win, COLOR_PAIR(1))
        wrefresh(win)
    }

    private func hasEventsOnDay(_ date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let events = backend.getEvents(startDate: start, endDate: end)
        let filteredEvents = events.filter { event in
            enabledCalendars.contains(event.calendar.calendarIdentifier)
        }
        return !filteredEvents.isEmpty
    }

    private func navigateEventDown() {
        if !allUpcomingEvents.isEmpty && selectedEventIndex < allUpcomingEvents.count - 1 {
            selectedEventIndex += 1
            // Auto-scroll if needed
            let maxVisible = 20
            if selectedEventIndex - eventScrollOffset >= maxVisible {
                eventScrollOffset += 1
            }
            // Update selected date to match the event's date
            updateSelectedDateFromEvent()
        }
    }

    private func navigateEventUp() {
        if selectedEventIndex > 0 {
            selectedEventIndex -= 1
            // Auto-scroll if needed
            if selectedEventIndex < eventScrollOffset {
                eventScrollOffset = selectedEventIndex
            }
            // Update selected date to match the event's date
            updateSelectedDateFromEvent()
        }
    }

    private func updateSelectedDateFromEvent() {
        if !allUpcomingEvents.isEmpty && selectedEventIndex < allUpcomingEvents.count {
            let event = allUpcomingEvents[selectedEventIndex]
            let cal = Calendar.current
            selectedDate = cal.startOfDay(for: event.startDate)
        }
    }

    private func navigateCalendarDown() {
        // Move down one week
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        selectedEventIndex = 0
        eventScrollOffset = 0
    }

    private func navigateCalendarUp() {
        // Move up one week
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        selectedEventIndex = 0
        eventScrollOffset = 0
    }

    private func navigateDayLeft() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        selectedEventIndex = 0
        eventScrollOffset = 0
    }

    private func navigateDayRight() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        selectedEventIndex = 0
        eventScrollOffset = 0
    }

    private func toggleCalendars() {
        // Create calendar selection interface with arrow key navigation
        guard let win = eventsWindow else { return }

        let calendars = backend.getCalendars()
        var selectedIndex = 0

        var selecting = true
        while selecting {
            wclear(win)
            box(win, 0, 0)

            wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
            bridge_mvwprintw(win, 1, 2, "Toggle Calendars")
            wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

            bridge_mvwprintw(win, 2, 2, "Arrows:Navigate  Space:Toggle  q:Done")

            var row: Int32 = 4

            for (index, calendar) in calendars.enumerated() {
                let enabled = enabledCalendars.contains(calendar.calendarIdentifier) ? "[X]" : "[ ]"

                // Highlight selected item
                if index == selectedIndex {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                    bridge_mvwprintw(win, row, 1, ">")
                }

                let line = " \(enabled) \(calendar.title)"
                bridge_mvwprintw(win, row, 3, line)

                if index == selectedIndex {
                    wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                row += 1
            }

            wrefresh(win)

            let ch = getch()
            switch ch {
            case 113: // 'q' - quit
                selecting = false

            case 106, KEY_DOWN: // 'j' or down - move down
                if selectedIndex < calendars.count - 1 {
                    selectedIndex += 1
                }

            case 107, KEY_UP: // 'k' or up - move up
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }

            case 32: // Space - toggle
                let calId = calendars[selectedIndex].calendarIdentifier
                if enabledCalendars.contains(calId) {
                    enabledCalendars.remove(calId)
                } else {
                    enabledCalendars.insert(calId)
                }

            default:
                break
            }
        }

        // Save config after toggling calendars
        saveConfig()
    }

    private func saveConfig() {
        let config = Config(
            enabledCalendars: Array(enabledCalendars),
            use24HourTime: use24HourTime
        )
        config.save()
    }

    private func showEventDetail(_ event: EKEvent) {
        guard let win = eventsWindow else { return }

        wclear(win)
        box(win, 0, 0)

        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        bridge_mvwprintw(win, 1, 2, "Event Details")
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        var row: Int32 = 3
        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(win, &maxY, &maxX)

        // Title
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "Title:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        let title = cleanString(event.title ?? "Untitled")
        bridge_mvwprintw(win, row, 4, title)
        row += 2

        // Date/Time
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "When:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1

        let dateFormatter = DateFormatter()
        if event.isAllDay {
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .none
            let dateStr = dateFormatter.string(from: event.startDate)
            bridge_mvwprintw(win, row, 4, dateStr + " (all day)")
        } else {
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            let startStr = dateFormatter.string(from: event.startDate)
            let endStr = dateFormatter.string(from: event.endDate)
            bridge_mvwprintw(win, row, 4, startStr)
            row += 1
            bridge_mvwprintw(win, row, 4, "to " + endStr)
        }
        row += 2

        // Calendar
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "Calendar:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        bridge_mvwprintw(win, row, 4, event.calendar.title)
        row += 2

        // Location
        if let location = event.location, !location.isEmpty {
            wattron(win, Int32(bridge_a_bold()))
            bridge_mvwprintw(win, row, 2, "Location:")
            wattroff(win, Int32(bridge_a_bold()))
            row += 1
            let cleanLoc = cleanString(location)
            bridge_mvwprintw(win, row, 4, cleanLoc)
            row += 2
        }

        // URL
        var eventURL: URL? = nil
        if let url = event.url {
            eventURL = url
            wattron(win, Int32(bridge_a_bold()))
            bridge_mvwprintw(win, row, 2, "URL:")
            wattroff(win, Int32(bridge_a_bold()))
            row += 1
            bridge_mvwprintw(win, row, 4, url.absoluteString)
            row += 2
        }

        // Notes
        if let notes = event.notes, !notes.isEmpty {
            wattron(win, Int32(bridge_a_bold()))
            bridge_mvwprintw(win, row, 2, "Notes:")
            wattroff(win, Int32(bridge_a_bold()))
            row += 1

            let cleanedNotes = cleanString(notes)
            let lines = cleanedNotes.split(separator: "\n")
            for line in lines {
                if row >= maxY - 3 { break }
                let wrappedLine = String(line.prefix(Int(maxX) - 6))
                bridge_mvwprintw(win, row, 4, wrappedLine)
                row += 1
            }
        }

        // Show appropriate help text
        if eventURL != nil {
            bridge_mvwprintw(win, maxY - 2, 2, "o:Open URL  q:Back")
        } else {
            bridge_mvwprintw(win, maxY - 2, 2, "q:Back")
        }
        wrefresh(win)

        // Wait for key and handle URL opening
        var viewing = true
        while viewing {
            let key = getch()
            if key == 111 || key == 79 { // 'o' or 'O'
                if let url = eventURL {
                    // Open URL in default browser using macOS 'open' command
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = [url.absoluteString]
                    try? task.run()
                }
            } else {
                // Any other key (including 'q') exits
                viewing = false
            }
        }
    }

    private func cleanString(_ input: String) -> String {
        // Remove or replace problematic characters
        return input
            .replacingOccurrences(of: "\u{2019}", with: "'")  // Right single quotation mark
            .replacingOccurrences(of: "\u{2018}", with: "'")  // Left single quotation mark
            .replacingOccurrences(of: "\u{201C}", with: "\"") // Left double quotation mark
            .replacingOccurrences(of: "\u{201D}", with: "\"") // Right double quotation mark
            .replacingOccurrences(of: "\u{2013}", with: "-")  // En dash
            .replacingOccurrences(of: "\u{2014}", with: "--") // Em dash
            .replacingOccurrences(of: "\u{2026}", with: "...") // Ellipsis
    }

    private func createNewEvent() {
        guard let win = eventsWindow else { return }

        // Step 1: Select calendar
        guard let selectedCalendar = selectCalendar() else {
            return  // User cancelled
        }

        // Step 2: Enter title
        guard let title = getTextInput(prompt: "Event Title", required: true) else {
            return  // User cancelled
        }

        // Step 3: Select/enter date
        guard let eventDate = selectDate() else {
            return  // User cancelled
        }

        // Step 4: Enter time (optional - can be all-day)
        let timeInput = getTextInput(prompt: "Start Time (or press Enter for all-day)", required: false)
        var startDate: Date
        var isAllDay = false

        if let timeStr = timeInput, !timeStr.isEmpty {
            // Parse time and combine with date
            if let parsedTime = DateParser.parse(timeStr) {
                let cal = Calendar.current
                let timeComponents = cal.dateComponents([.hour, .minute], from: parsedTime)
                var dateComponents = cal.dateComponents([.year, .month, .day], from: eventDate)
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                startDate = cal.date(from: dateComponents) ?? eventDate
            } else {
                showMessage("Invalid time format. Using all-day event.")
                napms(1500)
                startDate = Calendar.current.startOfDay(for: eventDate)
                isAllDay = true
            }
        } else {
            startDate = Calendar.current.startOfDay(for: eventDate)
            isAllDay = true
        }

        // Step 5: Enter duration (optional)
        var endDate: Date
        if !isAllDay {
            let durationInput = getTextInput(prompt: "Duration (e.g., '1h', '30min', or press Enter for 1h)", required: false)
            if let durStr = durationInput, !durStr.isEmpty {
                endDate = parseDuration(durStr, from: startDate) ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
            } else {
                endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate)!
            }
        } else {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        }

        // Step 6: Optional location
        let location = getTextInput(prompt: "Location (optional)", required: false)

        // Step 7: Optional notes
        let notes = getTextInput(prompt: "Notes (optional)", required: false)

        // Step 8: Confirm and create
        wclear(win)
        box(win, 0, 0)

        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        bridge_mvwprintw(win, 1, 2, "Confirm New Event")
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        var row: Int32 = 3
        bridge_mvwprintw(win, row, 2, "Title: \(title)")
        row += 1

        let dateFormatter = DateFormatter()
        if isAllDay {
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            bridge_mvwprintw(win, row, 2, "Date: \(dateFormatter.string(from: startDate)) (all-day)")
        } else {
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            bridge_mvwprintw(win, row, 2, "Start: \(dateFormatter.string(from: startDate))")
            row += 1
            bridge_mvwprintw(win, row, 2, "End: \(dateFormatter.string(from: endDate))")
        }
        row += 1

        bridge_mvwprintw(win, row, 2, "Calendar: \(selectedCalendar.title)")
        row += 1

        if let loc = location, !loc.isEmpty {
            bridge_mvwprintw(win, row, 2, "Location: \(loc)")
            row += 1
        }

        if let n = notes, !n.isEmpty {
            bridge_mvwprintw(win, row, 2, "Notes: \(n)")
            row += 1
        }

        row += 1
        bridge_mvwprintw(win, row, 2, "Press 'y' to create, any other key to cancel")
        wrefresh(win)

        let confirmKey = getch()
        if confirmKey == 121 || confirmKey == 89 { // 'y' or 'Y'
            // Create the event
            if let _ = backend.createEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                calendarIdentifier: selectedCalendar.calendarIdentifier,
                location: location?.isEmpty == false ? location : nil,
                notes: notes?.isEmpty == false ? notes : nil,
                isAllDay: isAllDay
            ) {
                showMessage("Event created successfully!")
            } else {
                showMessage("Failed to create event")
            }
            napms(1500)
        }
    }

    private func selectCalendar() -> EKCalendar? {
        guard let win = eventsWindow else { return nil }

        let calendars = backend.getCalendars().filter { $0.allowsContentModifications }

        if calendars.isEmpty {
            showMessage("No writable calendars available")
            napms(1500)
            return nil
        }

        var selectedIndex = 0
        var selecting = true
        var result: EKCalendar? = nil

        while selecting {
            wclear(win)
            box(win, 0, 0)

            wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
            bridge_mvwprintw(win, 1, 2, "Select Calendar")
            wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

            bridge_mvwprintw(win, 2, 2, "Arrows:Navigate  Enter:Select  q:Cancel")

            var row: Int32 = 4

            for (index, calendar) in calendars.enumerated() {
                if index == selectedIndex {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                    bridge_mvwprintw(win, row, 1, ">")
                }

                bridge_mvwprintw(win, row, 3, calendar.title)

                if index == selectedIndex {
                    wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                row += 1
            }

            wrefresh(win)

            let ch = getch()
            switch ch {
            case 113: // 'q' - cancel
                selecting = false

            case 10, 13: // Enter - select
                result = calendars[selectedIndex]
                selecting = false

            case 106, KEY_DOWN: // 'j' or down
                if selectedIndex < calendars.count - 1 {
                    selectedIndex += 1
                }

            case 107, KEY_UP: // 'k' or up
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }

            default:
                break
            }
        }

        return result
    }

    private func selectDate() -> Date? {
        guard let win = eventsWindow else { return nil }

        var selectedDate = self.selectedDate
        var selecting = true
        var result: Date? = nil

        while selecting {
            wclear(win)
            box(win, 0, 0)

            wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
            bridge_mvwprintw(win, 1, 2, "Select Date")
            wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

            bridge_mvwprintw(win, 2, 2, "Arrows:Navigate  Enter:Select  t:Type  q:Cancel")

            // Draw mini calendar
            let cal = Calendar.current
            let components = cal.dateComponents([.year, .month], from: selectedDate)
            guard let firstOfMonth = cal.date(from: components) else { continue }

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            let monthStr = monthFormatter.string(from: firstOfMonth)

            var row: Int32 = 4
            bridge_mvwprintw(win, row, 2, monthStr)
            row += 1

            bridge_mvwprintw(win, row, 2, "Su Mo Tu We Th Fr Sa")
            row += 1

            let firstWeekday = cal.component(.weekday, from: firstOfMonth)
            let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

            var dayColumn: Int32 = Int32((firstWeekday - 1) * 3)
            var currentRow = row

            for day in 1...daysInMonth {
                guard let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }

                let dayStr = String(format: "%2d", day)

                // Highlight selected day
                if cal.isDate(date, inSameDayAs: selectedDate) {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                bridge_mvwprintw(win, currentRow, 2 + dayColumn, dayStr)

                if cal.isDate(date, inSameDayAs: selectedDate) {
                    wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                dayColumn += 3

                // New line after Saturday
                if (firstWeekday + day - 1) % 7 == 0 {
                    currentRow += 1
                    dayColumn = 0
                }
            }

            wrefresh(win)

            let ch = getch()
            switch ch {
            case 113: // 'q' - cancel
                selecting = false

            case 10, 13: // Enter - select current date
                result = selectedDate
                selecting = false

            case 116: // 't' - type date
                if let typed = getTextInput(prompt: "Enter date (e.g., 'tomorrow', 'next friday', '2025-12-25')", required: false) {
                    if let parsed = DateParser.parse(typed) {
                        result = parsed
                        selecting = false
                    } else {
                        showMessage("Invalid date format")
                        napms(1000)
                    }
                }

            case 104, KEY_LEFT: // 'h' or left - previous day
                selectedDate = cal.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate

            case 108, KEY_RIGHT: // 'l' or right - next day
                selectedDate = cal.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate

            case 107, KEY_UP: // 'k' or up - previous week
                selectedDate = cal.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate

            case 106, KEY_DOWN: // 'j' or down - next week
                selectedDate = cal.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate

            default:
                break
            }
        }

        return result
    }

    private func getTextInput(prompt: String, required: Bool) -> String? {
        guard let win = eventsWindow else { return nil }

        wclear(win)
        box(win, 0, 0)

        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        bridge_mvwprintw(win, 1, 2, prompt)
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        if required {
            bridge_mvwprintw(win, 3, 2, "Type and press Enter  ESC:Cancel")
        } else {
            bridge_mvwprintw(win, 3, 2, "Type and press Enter (or Enter to skip)  ESC:Cancel")
        }

        bridge_mvwprintw(win, 5, 2, "> ")
        wmove(win, 5, 4)
        curs_set(1)
        wrefresh(win)

        var input = ""
        var inputting = true
        var col: Int32 = 4

        while inputting {
            let ch = getch()

            switch ch {
            case 27: // ESC - cancel
                input = ""
                inputting = false

            case 10, 13: // Enter - done
                inputting = false

            case 127, KEY_BACKSPACE, 8: // Backspace
                if !input.isEmpty {
                    input.removeLast()
                    col -= 1
                    bridge_mvwprintw(win, 5, col, " ")
                    wmove(win, 5, col)
                    wrefresh(win)
                }

            default:
                if ch >= 32 && ch < 127 { // Printable characters
                    let char = Character(UnicodeScalar(UInt8(ch)))
                    input.append(char)
                    bridge_mvwprintw(win, 5, col, String(char))
                    col += 1
                    wmove(win, 5, col)
                    wrefresh(win)
                }
            }
        }

        // Hide cursor
        curs_set(0)

        if input.isEmpty && required {
            return nil
        }

        return input.isEmpty ? nil : input
    }

    private func parseDuration(_ input: String, from startDate: Date) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Try to parse patterns like "1h", "30min", "1:30", etc.
        if let hours = Int(trimmed.replacingOccurrences(of: "h", with: "")) {
            return Calendar.current.date(byAdding: .hour, value: hours, to: startDate)
        }

        if let minutes = Int(trimmed.replacingOccurrences(of: "min", with: "")) {
            return Calendar.current.date(byAdding: .minute, value: minutes, to: startDate)
        }

        // Try "1:30" format (hour:minute)
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) {
            var result = Calendar.current.date(byAdding: .hour, value: hours, to: startDate)!
            result = Calendar.current.date(byAdding: .minute, value: minutes, to: result)!
            return result
        }

        return nil
    }

    private func showMessage(_ message: String) {
        guard let win = eventsWindow else { return }

        wclear(win)
        box(win, 0, 0)

        var maxY: Int32 = 0
        var maxX: Int32 = 0
        bridge_getmaxyx(win, &maxY, &maxX)

        bridge_mvwprintw(win, maxY / 2, 2, message)
        wrefresh(win)
    }

    private func showHelp() {
        guard let win = eventsWindow else { return }

        wclear(win)
        box(win, 0, 0)

        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        bridge_mvwprintw(win, 1, 2, "tkal Help")
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        var row: Int32 = 3

        // Navigation
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "Navigation:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        bridge_mvwprintw(win, row, 4, "Tab         - Switch between calendar and events")
        row += 1
        bridge_mvwprintw(win, row, 4, "Arrows/hjkl - Navigate (day/week in calendar, events in list)")
        row += 1
        bridge_mvwprintw(win, row, 4, "Left        - Back to calendar (from events view)")
        row += 1
        bridge_mvwprintw(win, row, 4, "Right/Enter - View event details (from events view)")
        row += 2

        // Actions
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "Actions:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        bridge_mvwprintw(win, row, 4, "n           - Create new event")
        row += 1
        bridge_mvwprintw(win, row, 4, "/           - Search events")
        row += 1
        bridge_mvwprintw(win, row, 4, "t           - Jump to today")
        row += 1
        bridge_mvwprintw(win, row, 4, "r           - Refresh events")
        row += 1
        bridge_mvwprintw(win, row, 4, "c           - Toggle calendars on/off")
        row += 1
        bridge_mvwprintw(win, row, 4, "Shift+T     - Toggle time format (12/24 hour)")
        row += 2

        // Event Detail View
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "Event Detail View:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        bridge_mvwprintw(win, row, 4, "o           - Open URL in browser")
        row += 1
        bridge_mvwprintw(win, row, 4, "q           - Go back")
        row += 2

        // General
        wattron(win, Int32(bridge_a_bold()))
        bridge_mvwprintw(win, row, 2, "General:")
        wattroff(win, Int32(bridge_a_bold()))
        row += 1
        bridge_mvwprintw(win, row, 4, "?           - Show this help")
        row += 1
        bridge_mvwprintw(win, row, 4, "q           - Quit (or back)")
        row += 2

        bridge_mvwprintw(win, row, 2, "Press any key to close")
        wrefresh(win)

        getch()
    }

    private func searchEvents() {
        guard let win = eventsWindow else { return }

        // Get search query
        wclear(win)
        box(win, 0, 0)

        wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
        bridge_mvwprintw(win, 1, 2, "Search Events")
        wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

        bridge_mvwprintw(win, 3, 2, "ESC:Cancel")
        bridge_mvwprintw(win, 5, 2, "/")

        // Position cursor and show it for input
        wmove(win, 5, 3)
        curs_set(1)
        wrefresh(win)

        var searchQuery = ""
        var inputting = true
        var col: Int32 = 3

        while inputting {
            let ch = getch()

            switch ch {
            case 27: // ESC - cancel
                curs_set(0)
                return

            case 10, 13: // Enter - search
                inputting = false

            case 127, KEY_BACKSPACE, 8: // Backspace
                if !searchQuery.isEmpty {
                    searchQuery.removeLast()
                    col -= 1
                    bridge_mvwprintw(win, 5, col, " ")
                    wmove(win, 5, col)
                    wrefresh(win)
                }

            default:
                if ch >= 32 && ch < 127 { // Printable characters
                    let char = Character(UnicodeScalar(UInt8(ch)))
                    searchQuery.append(char)
                    bridge_mvwprintw(win, 5, col, String(char))
                    col += 1
                    wmove(win, 5, col)
                    wrefresh(win)
                }
            }
        }

        // Hide cursor
        curs_set(0)

        if searchQuery.isEmpty {
            return
        }

        // Perform search
        let results = backend.searchEvents(searchString: searchQuery)

        if results.isEmpty {
            showMessage("No events found matching '\(searchQuery)'")
            napms(1500)
            return
        }

        // Display results
        var selectedIndex = 0
        var browsing = true

        while browsing {
            wclear(win)
            box(win, 0, 0)

            wattron(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))
            bridge_mvwprintw(win, 1, 2, "Search Results: \(results.count) events matching '\(searchQuery)'")
            wattroff(win, COLOR_PAIR(1) | Int32(bridge_a_bold()))

            bridge_mvwprintw(win, 2, 2, "Arrows:Navigate  Enter:View  q:Back")

            var maxY: Int32 = 0
            var maxX: Int32 = 0
            bridge_getmaxyx(win, &maxY, &maxX)

            var row: Int32 = 4
            let maxDisplayRows = Int(maxY) - 6

            // Calculate scroll offset
            var scrollOffset = 0
            if selectedIndex >= maxDisplayRows {
                scrollOffset = selectedIndex - maxDisplayRows + 1
            }

            for (index, event) in results.enumerated() {
                if index < scrollOffset { continue }
                if row >= maxY - 2 { break }

                // Highlight selected item
                if index == selectedIndex {
                    wattron(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                    bridge_mvwprintw(win, row, 1, ">")
                }

                // Format event - use explicit format to avoid Unicode characters
                let dateStr: String
                if event.isAllDay {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "M/d/yy"
                    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateStr = dateFormatter.string(from: event.startDate) + " All Day"
                } else {
                    let dateFormatter = DateFormatter()
                    if use24HourTime {
                        dateFormatter.dateFormat = "M/d/yy HH:mm"
                    } else {
                        dateFormatter.dateFormat = "M/d/yy h:mm a"
                    }
                    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateStr = dateFormatter.string(from: event.startDate)
                }

                let title = cleanString(event.title ?? "Untitled")
                let line = " \(dateStr)  \(title)"
                let displayLine = String(line.prefix(Int(maxX) - 4))
                bridge_mvwprintw(win, row, 3, displayLine)

                if index == selectedIndex {
                    wattroff(win, COLOR_PAIR(2) | Int32(bridge_a_bold()))
                }

                row += 1
            }

            wrefresh(win)

            let ch = getch()
            switch ch {
            case 113: // 'q' - back
                browsing = false

            case 10, 13: // Enter - view event
                showEventDetail(results[selectedIndex])

            case 106, KEY_DOWN: // 'j' or down
                if selectedIndex < results.count - 1 {
                    selectedIndex += 1
                }

            case 107, KEY_UP: // 'k' or up
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }

            default:
                break
            }
        }
    }
}

private func ord(_ char: Character) -> UInt32 {
    return char.unicodeScalars.first?.value ?? 0
}
