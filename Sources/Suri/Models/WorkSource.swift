import SwiftUI

enum WorkSource: String, CaseIterable, Identifiable, Hashable, Codable {
    case slack
    case email
    case gitLab
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
        case .jira:
            .indigo
        case .notes:
            .green
        }
    }
}

struct SourceConnection: Identifiable, Hashable, Codable {
    let source: WorkSource
    var isConnected: Bool
    var unreadCount: Int
    var lastActivity: Date
    var summary: String

    var id: WorkSource { source }
}
