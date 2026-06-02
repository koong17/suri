import Foundation

struct SlackDirectMessageTaskGrouper {
    func grouped(_ tasks: [AssistantTask]) -> [AssistantTask] {
        let groupedDMTasks = Dictionary(grouping: tasks.filter(\.isSlackDirectMessageTask)) {
            $0.dmConversationKey
        }
        .values
        .map(makeGroupedTask)

        let nonDMTasks = tasks.filter { !$0.isSlackDirectMessageTask }
        return nonDMTasks + groupedDMTasks
    }

    private func makeGroupedTask(_ tasks: [AssistantTask]) -> AssistantTask {
        let orderedTasks = tasks
        guard let latestTask = orderedTasks.first else {
            preconditionFailure("DM group cannot be empty")
        }

        let messageCount = orderedTasks.count
        let owner = latestTask.owner.nilIfEmpty ?? "Slack"
        let isImportant = orderedTasks.contains { $0.isImportantSlack }
        let summary = bestSummary(from: orderedTasks)
        let context = contextSummary(from: orderedTasks)
        let dueDate = orderedTasks.compactMap(\.dueDate).min()
        let priority = orderedTasks.map(\.priority).maxBySortRank() ?? latestTask.priority
        let stableConversationKey = latestTask.dmConversationKey

        var metadata = [
            MetadataItem(label: "대화", value: "slack-dm:\(stableConversationKey)"),
            MetadataItem(label: "상대", value: owner),
            MetadataItem(label: "메시지", value: "\(messageCount)건"),
            MetadataItem(label: "채널", value: latestTask.metadataValue(for: "채널") ?? "DM"),
            MetadataItem(label: "분류", value: isImportant ? "중요 DM 묶음" : "DM 묶음")
        ]

        if let link = orderedTasks.compactMap(\.primaryURL).first {
            metadata.append(MetadataItem(label: "링크", value: link.absoluteString))
        } else if let fallbackLink = latestTask.metadataValue(for: "링크") {
            metadata.append(MetadataItem(label: "링크", value: fallbackLink))
        }

        let codexReasons = orderedTasks
            .compactMap { $0.metadataValue(for: "Codex 판단")?.nilIfEmpty }
            .uniqued()
        if !codexReasons.isEmpty {
            metadata.append(MetadataItem(label: "Codex 판단", value: codexReasons.prefix(2).joined(separator: " / ")))
        }

        return AssistantTask(
            id: latestTask.id,
            title: "\(owner) DM \(messageCount)건: \(summary)",
            source: .slack,
            dueDate: dueDate,
            priority: priority,
            status: .open,
            context: context,
            owner: owner,
            requiresUserReview: orderedTasks.contains { $0.requiresUserReview },
            recommendedAction: isImportant
                ? "중요한 DM 묶음입니다. 최근 흐름을 보고 답변 또는 일정 등록 여부를 결정"
                : "DM 대화 흐름을 확인하고 답변 또는 일정 등록 여부를 결정",
            metadata: metadata
        )
    }

    private func bestSummary(from tasks: [AssistantTask]) -> String {
        let candidates = tasks.map { task in
            task.context.cleanedSlackSummaryText
        }

        let preferred = candidates.first {
            TaskExtractor.requiresReview(from: $0)
                || TaskExtractor.inferredDueDate(from: $0, relativeTo: .now) != nil
                || TaskExtractor.priority(from: $0, default: .normal).sortRank > TaskPriority.normal.sortRank
        }

        return String((preferred ?? candidates.first ?? "확인 필요").prefix(48))
    }

    private func contextSummary(from tasks: [AssistantTask]) -> String {
        let lines = tasks
            .prefix(4)
            .map { "- \($0.context.cleanedSlackSummaryText)" }
        return "최근 DM \(tasks.count)건\n" + lines.joined(separator: "\n")
    }
}

private extension AssistantTask {
    var isSlackDirectMessageTask: Bool {
        source == .slack
            && metadataValue(for: "분류")?.contains("DM") == true
    }

    var dmConversationKey: String {
        owner
            .nilIfEmpty?
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        ?? "unknown"
    }

    func metadataValue(for label: String) -> String? {
        metadata.first { $0.label == label }?.value
    }
}

private extension Array where Element == TaskPriority {
    func maxBySortRank() -> TaskPriority? {
        self.max { $0.sortRank < $1.sortRank }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var cleanedSlackSummaryText: String {
        replacingOccurrences(of: #"<@[A-Z0-9]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "확인 필요"
    }
}
