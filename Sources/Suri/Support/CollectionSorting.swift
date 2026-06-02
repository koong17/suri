import Foundation

extension Array where Element == AssistantTask {
    func sortedForAssistant() -> [AssistantTask] {
        sorted { first, second in
            switch (first.dueDate, second.dueDate) {
            case let (.some(firstDate), .some(secondDate)):
                firstDate < secondDate
            case (.some, .none):
                true
            case (.none, .some):
                false
            case (.none, .none):
                first.priority.sortRank > second.priority.sortRank
            }
        }
    }
}

extension Array where Element == AssistantNote {
    func sortedByCapturedDateDescending() -> [AssistantNote] {
        sorted { $0.capturedAt > $1.capturedAt }
    }
}

extension Array where Element == URL {
    func sortedByModificationDateDescending() -> [URL] {
        sorted { first, second in
            let firstDate = (try? first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let secondDate = (try? second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return firstDate > secondDate
        }
    }
}

extension TaskPriority {
    var sortRank: Int {
        switch self {
        case .low:
            0
        case .normal:
            1
        case .high:
            2
        case .urgent:
            3
        }
    }
}

extension DateFormatter {
    static var yearMonthDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }
}

extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
