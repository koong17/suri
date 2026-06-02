import Foundation

enum PreferenceKeys {
    static let dailyBriefingEnabled = "dailyBriefingEnabled"
    static let notificationsEnabled = "notificationsEnabled"
    static let notificationLeadTimeRaw = "notificationLeadTimeRaw"
    static let dueSoonHours = "dueSoonHours"
    static let autoSyncEnabled = "autoSyncEnabled"
    static let syncIntervalMinutes = "syncIntervalMinutes"
    static let quietHoursEnabled = "quietHoursEnabled"
    static let slackEnabled = "source.slack.enabled"
    static let emailEnabled = "source.email.enabled"
    static let gitLabEnabled = "source.gitLab.enabled"
    static let githubEnabled = "source.github.enabled"
    static let jiraEnabled = "source.jira.enabled"
    static let notesEnabled = "source.notes.enabled"
}

enum NotificationLeadTime: String, CaseIterable, Identifiable {
    case oneHour
    case sixHours
    case oneDay
    case twoDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            "1시간 전"
        case .sixHours:
            "6시간 전"
        case .oneDay:
            "1일 전"
        case .twoDays:
            "2일 전"
        }
    }

    var hours: Double {
        switch self {
        case .oneHour:
            1
        case .sixHours:
            6
        case .oneDay:
            24
        case .twoDays:
            48
        }
    }
}

struct SyncPreferences {
    var enabledSources: Set<WorkSource>
    var notificationsEnabled: Bool
    var dueSoonHours: Double
    var notificationLeadTime: NotificationLeadTime

    func includes(_ source: WorkSource) -> Bool {
        enabledSources.contains(source)
    }
}
