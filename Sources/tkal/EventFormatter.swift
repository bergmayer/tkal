import Foundation
import EventKit

struct EventFormatter {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func format(_ event: EKEvent, showCalendar: Bool = true) -> String {
        var parts: [String] = []

        // Date/time
        let dateStr: String
        if event.isAllDay {
            dateStr = dateOnlyFormatter.string(from: event.startDate)
        } else {
            dateStr = "\(dateFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
        }
        parts.append(dateStr)

        // Title
        parts.append(event.title)

        // Calendar
        if showCalendar {
            parts.append("[\(event.calendar.title)]")
        }

        // Location
        if let location = event.location, !location.isEmpty {
            parts.append("@ \(location)")
        }

        return parts.joined(separator: " ")
    }

    static func formatDetailed(_ event: EKEvent, showNotes: Bool = false) -> String {
        var output = ""

        output += "Title: \(event.title ?? "Untitled")\n"

        if event.isAllDay {
            output += "Date: \(dateOnlyFormatter.string(from: event.startDate))\n"
        } else {
            output += "Start: \(dateFormatter.string(from: event.startDate))\n"
            output += "End: \(dateFormatter.string(from: event.endDate))\n"
        }

        output += "Calendar: \(event.calendar.title)\n"

        if let location = event.location, !location.isEmpty {
            output += "Location: \(location)\n"
        }

        if let url = event.url {
            output += "URL: \(url.absoluteString)\n"
        }

        if showNotes, let notes = event.notes, !notes.isEmpty {
            output += "Notes: \(notes)\n"
        }

        return output
    }

    static func formatList(_ events: [EKEvent], groupByDay: Bool = true) -> String {
        if events.isEmpty {
            return "No events found"
        }

        if !groupByDay {
            return events.map { format($0) }.joined(separator: "\n")
        }

        // Group by day
        let grouped = Dictionary(grouping: events) { event -> Date in
            Calendar.current.startOfDay(for: event.startDate)
        }

        let sortedDays = grouped.keys.sorted()
        var output = ""

        for day in sortedDays {
            let dayEvents = grouped[day]!.sorted { $0.startDate < $1.startDate }

            // Day header
            let dayFormatter = DateFormatter()
            dayFormatter.dateStyle = .full
            dayFormatter.timeStyle = .none
            output += "\n\(dayFormatter.string(from: day))\n"
            output += String(repeating: "=", count: 60) + "\n"

            // Events for this day
            for event in dayEvents {
                output += format(event) + "\n"
            }
        }

        return output
    }

    static func formatCalendar(_ events: [EKEvent], month: Date) -> String {
        let calendar = Calendar.current
        var output = ""

        // Month header
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthStr = monthFormatter.string(from: month)
        output += "\n" + monthStr.center(width: 28) + "\n"
        output += "Su Mo Tu We Th Fr Sa\n"

        // Get the first day of the month
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let firstOfMonth = calendar.date(from: components) else {
            return "Error: Could not determine first day of month"
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        // Leading spaces
        output += String(repeating: "   ", count: firstWeekday - 1)

        // Days
        for day in 1...daysInMonth {
            let dayString = String(format: "%2d", day)

            // Check if this day has events
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else {
                continue
            }

            let hasEvents = events.contains { event in
                calendar.isDate(event.startDate, inSameDayAs: date)
            }

            if hasEvents {
                output += "\u{001B}[1m\(dayString)\u{001B}[0m "  // Bold
            } else {
                output += "\(dayString) "
            }

            // New line on Saturday
            let weekday = (firstWeekday + day - 1) % 7
            if weekday == 0 {
                output += "\n"
            }
        }

        output += "\n"
        return output
    }
}

extension String {
    func center(width: Int) -> String {
        let padding = width - self.count
        if padding <= 0 { return self }

        let leftPadding = padding / 2
        let rightPadding = padding - leftPadding

        return String(repeating: " ", count: leftPadding) + self + String(repeating: " ", count: rightPadding)
    }
}
