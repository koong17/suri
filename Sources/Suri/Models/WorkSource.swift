import SwiftUI

enum WorkSource: String, CaseIterable, Identifiable, Hashable, Codable {
    case slack
    case email
    case gitLab
    case github
    case jira
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slack:
            "Slack"
        case .email:
            "Email"
        case .gitLab:
            "GitLab"
        case .github:
            "GitHub"
        case .jira:
            "Jira"
        case .notes:
            "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .slack:
            "bubble.left.and.bubble.right"
        case .email:
            "envelope"
        case .gitLab:
            "chevron.left.forwardslash.chevron.right"
        case .github:
            "curlybraces.square"
        case .jira:
            "checklist"
        case .notes:
            "note.text"
        }
    }

    var accent: Color {
        switch self {
        case .slack:
            .purple
        case .email:
            .blue
        case .gitLab:
            .orange
        case .github:
            .primary
        case .jira:
            .indigo
        case .notes:
            .green
        }
    }
}

enum SourceHealthState: String, CaseIterable, Hashable, Codable {
    case healthy
    case degraded
    case disconnected
    case disabled

    var title: String {
        switch self {
        case .healthy:
            "정상"
        case .degraded:
            "주의"
        case .disconnected:
            "오류"
        case .disabled:
            "비활성"
        }
    }

    var systemImage: String {
        switch self {
        case .healthy:
            "checkmark.circle"
        case .degraded:
            "exclamationmark.triangle"
        case .disconnected:
            "xmark.circle"
        case .disabled:
            "pause.circle"
        }
    }

    var tint: Color {
        switch self {
        case .healthy:
            .green
        case .degraded:
            .orange
        case .disconnected:
            .red
        case .disabled:
            .secondary
        }
    }
}

struct SourceConnection: Identifiable, Hashable, Codable {
    let source: WorkSource
    var isConnected: Bool
    var unreadCount: Int
    var lastActivity: Date
    var summary: String
    var health: SourceHealthState
    var lastSuccessAt: Date?
    var lastAttemptAt: Date?
    var duplicateCount: Int
    var errorMessage: String?

    var id: WorkSource { source }

    init(
        source: WorkSource,
        isConnected: Bool,
        unreadCount: Int,
        lastActivity: Date,
        summary: String,
        health: SourceHealthState? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        duplicateCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.source = source
        self.isConnected = isConnected
        self.unreadCount = unreadCount
        self.lastActivity = lastActivity
        self.summary = summary
        self.health = health ?? (isConnected ? .healthy : .disconnected)
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.duplicateCount = duplicateCount
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case source
        case isConnected
        case unreadCount
        case lastActivity
        case summary
        case health
        case lastSuccessAt
        case lastAttemptAt
        case duplicateCount
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(WorkSource.self, forKey: .source)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        lastActivity = try container.decode(Date.self, forKey: .lastActivity)
        summary = try container.decode(String.self, forKey: .summary)
        health = try container.decodeIfPresent(SourceHealthState.self, forKey: .health)
            ?? (isConnected ? .healthy : .disconnected)
        lastSuccessAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        duplicateCount = try container.decodeIfPresent(Int.self, forKey: .duplicateCount) ?? 0
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}
