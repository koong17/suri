import Foundation

struct AssistantTask: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var source: WorkSource
    var dueDate: Date?
    var priority: TaskPriority
    var status: TaskStatus
    var context: String
    var owner: String
    var requiresUserReview: Bool
    var recommendedAction: String
    var metadata: [MetadataItem]

    var reviewKey: String {
        let stableMetadata = metadata
            .first { ["링크", "URL", "MR", "이슈", "파일", "메모"].contains($0.label) }?
            .value
            ?? context

        return [
            source.rawValue,
            title,
            stableMetadata
        ]
        .joined(separator: "|")
    }

    var isImportantSlack: Bool {
        source == .slack
            && metadata.contains { $0.label == "분류" && $0.value.contains("중요") }
    }

    var isActiveJiraIssue: Bool {
        guard source == .jira, status != .reviewed else {
            return false
        }

        let jiraStatus = metadata
            .first { $0.label == "상태" }?
            .value
            .lowercased()
            ?? context.lowercased()

        return jiraStatus.contains("진행")
            || jiraStatus.contains("in progress")
            || jiraStatus.contains("doing")
    }

    var primaryURL: URL? {
        metadata
            .filter { ["링크", "URL", "MR", "PR", "Issue", "이슈"].contains($0.label) }
            .compactMap { URL(string: $0.value) }
            .first { $0.scheme != nil }
    }

    init(
        id: UUID = UUID(),
        title: String,
        source: WorkSource,
        dueDate: Date?,
        priority: TaskPriority,
        status: TaskStatus,
        context: String,
        owner: String,
        requiresUserReview: Bool,
        recommendedAction: String,
        metadata: [MetadataItem] = []
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.dueDate = dueDate
        self.priority = priority
        self.status = status
        self.context = context
        self.owner = owner
        self.requiresUserReview = requiresUserReview
        self.recommendedAction = recommendedAction
        self.metadata = metadata
    }
}

enum TaskPriority: String, CaseIterable, Hashable, Codable {
    case low
    case normal
    case high
    case urgent

    var title: String {
        switch self {
        case .low:
            "낮음"
        case .normal:
            "보통"
        case .high:
            "높음"
        case .urgent:
            "긴급"
        }
    }
}

enum TaskStatus: String, CaseIterable, Hashable, Codable {
    case open
    case waiting
    case scheduled
    case reviewed

    var title: String {
        switch self {
        case .open:
            "열림"
        case .waiting:
            "대기"
        case .scheduled:
            "일정화됨"
        case .reviewed:
            "확인 완료"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            "circle"
        case .waiting:
            "clock"
        case .scheduled:
            "calendar"
        case .reviewed:
            "checkmark.circle"
        }
    }
}

struct MetadataItem: Identifiable, Hashable, Codable {
    let label: String
    let value: String

    var id: String { "\(label)-\(value)" }
}

struct AssistantNote: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var body: String
    var capturedAt: Date
    var linkedTaskID: AssistantTask.ID?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        capturedAt: Date,
        linkedTaskID: AssistantTask.ID?
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.capturedAt = capturedAt
        self.linkedTaskID = linkedTaskID
    }
}
