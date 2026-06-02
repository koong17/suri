import Foundation

enum AssistantFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func dueText(for date: Date?) -> String {
        guard let date else {
            return "기한 없음"
        }

        return relative.localizedString(for: date, relativeTo: .now)
    }
}

extension Date {
    static func hoursFromNow(_ hours: Double) -> Date {
        Date.now.addingTimeInterval(hours * 60 * 60)
    }
}
