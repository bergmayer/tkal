import Foundation

struct DateParser {
    static let calendar = Calendar.current

    static func parse(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Handle special cases
        if trimmed == "now" || trimmed == "today" {
            return Date()
        }

        if trimmed == "tomorrow" {
            return calendar.date(byAdding: .day, value: 1, to: Date())
        }

        if trimmed == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: Date())
        }

        // Handle "next week", "next month", etc.
        if trimmed == "next week" {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: Date())
        }

        if trimmed == "last week" {
            return calendar.date(byAdding: .weekOfYear, value: -1, to: Date())
        }

        if trimmed == "next month" {
            return calendar.date(byAdding: .month, value: 1, to: Date())
        }

        if trimmed == "last month" {
            return calendar.date(byAdding: .month, value: -1, to: Date())
        }

        // Handle day names: "next friday", "this monday", "last tuesday"
        if let date = parseRelativeDay(trimmed) {
            return date
        }

        // Handle "in X days/weeks/months": "in 3 days", "in 2 weeks"
        if let date = parseRelativeInterval(trimmed) {
            return date
        }

        // Handle combined formats: "tomorrow 2pm", "next friday 3:30pm"
        if let date = parseCombinedFormat(input) {
            return date
        }

        // Try various date formats
        let formatters = createFormatters()

        for formatter in formatters {
            if let date = formatter.date(from: input) {
                return date
            }
        }

        return nil
    }

    private static func parseRelativeDay(_ input: String) -> Date? {
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

        for (index, weekday) in weekdays.enumerated() {
            // "next friday"
            if input == "next \(weekday)" {
                return nextWeekday(index + 1, direction: 1)
            }

            // "this friday" - find the next occurrence this week, or today if today
            if input == "this \(weekday)" {
                let today = calendar.component(.weekday, from: Date())
                let targetDay = index + 1

                if today == targetDay {
                    return calendar.startOfDay(for: Date())
                } else if targetDay > today {
                    return nextWeekday(targetDay, direction: 0, allowToday: true)
                } else {
                    return nextWeekday(targetDay, direction: 1)
                }
            }

            // "last friday"
            if input == "last \(weekday)" {
                return nextWeekday(index + 1, direction: -1)
            }

            // Just "friday" - interpret as next occurrence
            if input == weekday {
                return nextWeekday(index + 1, direction: 0, allowToday: false)
            }
        }

        return nil
    }

    private static func nextWeekday(_ targetWeekday: Int, direction: Int, allowToday: Bool = false) -> Date? {
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)

        var daysToAdd: Int

        if direction == 0 {
            // Find next occurrence (could be today if allowToday)
            if currentWeekday == targetWeekday && allowToday {
                daysToAdd = 0
            } else if targetWeekday > currentWeekday {
                daysToAdd = targetWeekday - currentWeekday
            } else {
                daysToAdd = 7 - currentWeekday + targetWeekday
            }
        } else if direction > 0 {
            // Next week's occurrence
            if targetWeekday > currentWeekday {
                daysToAdd = targetWeekday - currentWeekday
            } else {
                daysToAdd = 7 - currentWeekday + targetWeekday
            }
        } else {
            // Last week's occurrence
            if targetWeekday < currentWeekday {
                daysToAdd = -(currentWeekday - targetWeekday)
            } else {
                daysToAdd = -(7 - targetWeekday + currentWeekday)
            }
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: now)
    }

    private static func parseRelativeInterval(_ input: String) -> Date? {
        // Match "in X days/weeks/months/years"
        let pattern = #"^in\s+(\d+)\s+(day|week|month|year)s?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return nil
        }

        guard let numberRange = Range(match.range(at: 1), in: input),
              let unitRange = Range(match.range(at: 2), in: input),
              let value = Int(input[numberRange]) else {
            return nil
        }

        let unit = String(input[unitRange])
        let component: Calendar.Component

        switch unit {
        case "day":
            component = .day
        case "week":
            component = .weekOfYear
        case "month":
            component = .month
        case "year":
            component = .year
        default:
            return nil
        }

        return calendar.date(byAdding: component, value: value, to: Date())
    }

    private static func parseCombinedFormat(_ input: String) -> Date? {
        // Split on common time indicators
        let parts = input.components(separatedBy: " ")

        if parts.count >= 2 {
            // Try to parse first part as date, last part as time
            let datePart = parts.dropLast().joined(separator: " ")
            let timePart = parts.last!

            // Parse the date part
            guard let baseDate = parse(datePart) else {
                return nil
            }

            // Parse the time part
            let timeFormatters = [
                "HH:mm:ss",
                "HH:mm",
                "h:mma",
                "h:mm a",
                "ha",
                "h a"
            ]

            for format in timeFormatters {
                let formatter = DateFormatter()
                formatter.dateFormat = format

                if let timeDate = formatter.date(from: timePart) {
                    // Extract time components
                    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeDate)

                    // Combine with base date
                    var baseComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                    baseComponents.hour = timeComponents.hour
                    baseComponents.minute = timeComponents.minute
                    baseComponents.second = timeComponents.second

                    return calendar.date(from: baseComponents)
                }
            }
        }

        return nil
    }

    static func parseRange(_ inputs: [String]) -> (start: Date, end: Date)? {
        if inputs.isEmpty {
            // Default to today
            let start = calendar.startOfDay(for: Date())
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }

        if inputs.count == 1 {
            // Single date - treat as that day
            guard let start = parse(inputs[0]) else { return nil }
            let startOfDay = calendar.startOfDay(for: start)
            let end = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return (startOfDay, end)
        }

        // Two dates - start and end
        guard let start = parse(inputs[0]),
              let end = parse(inputs[1]) else {
            return nil
        }

        return (start, end)
    }

    private static func createFormatters() -> [DateFormatter] {
        var formatters: [DateFormatter] = []

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "dd.MM.yyyy HH:mm",
            "dd.MM.yyyy",
            "HH:mm",
            "h:mm a",
            "ha"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale.current
            formatters.append(formatter)
        }

        return formatters
    }
}
