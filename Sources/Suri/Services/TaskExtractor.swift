import Foundation

enum TaskExtractor {
    static func inferredDueDate(from text: String, fallbackHours: Double? = nil, relativeTo referenceDate: Date = .now) -> Date? {
        let lowered = text.lowercased()

        if lowered.contains("today") || text.contains("오늘") || lowered.contains("eod") {
            return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: referenceDate)
        }

        if lowered.contains("tomorrow") || text.contains("내일") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
            return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)
        }

        if let isoDate = firstISODate(in: text) {
            return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: isoDate)
        }

        if let fallbackHours {
            return referenceDate.addingTimeInterval(fallbackHours * 60 * 60)
        }

        return nil
    }

    static func priority(from text: String, default defaultPriority: TaskPriority = .normal) -> TaskPriority {
        let lowered = text.lowercased()
        if lowered.contains("urgent") || lowered.contains("asap") || text.contains("긴급") {
            return .urgent
        }

        if lowered.contains("important") || text.contains("중요") || text.contains("확인 필요") {
            return .high
        }

        return defaultPriority
    }

    static func requiresReview(from text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("review")
            || lowered.contains("approve")
            || lowered.contains("confirm")
            || text.contains("확인")
            || text.contains("승인")
            || text.contains("검토")
    }

    private static func firstISODate(in text: String) -> Date? {
        let pattern = #"(\d{4})-(\d{2})-(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range(at: 0), in: text) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.date(from: String(text[matchRange]))
    }
}
