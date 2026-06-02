import Foundation

struct SlackClient: WorkItemProvider {
    let configuration: SlackIntegrationConfiguration
    let httpClient = HTTPServiceClient()

    var source: WorkSource { .slack }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let token = configuration.token?.nilIfEmpty else {
            throw ServiceClientError.missingConfiguration
        }

        let query = configuration.query?.nilIfEmpty ?? "to:me OR @here OR @channel OR @everyone"
        guard var components = URLComponents(string: "https://slack.com/api/search.messages") else {
            throw ServiceClientError.invalidURL("https://slack.com/api/search.messages")
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "count", value: "\(min(configuration.count ?? 20, 100))"),
            URLQueryItem(name: "sort", value: "timestamp"),
            URLQueryItem(name: "sort_dir", value: "desc")
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL("Slack search.messages")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await httpClient.data(for: request)
        let response = try JSONDecoder().decode(SlackSearchResponse.self, from: data)

        guard response.ok else {
            throw ServiceClientError.serviceMessage(response.error ?? "Slack API 요청 실패")
        }

        let matches = (response.messages?.matches ?? []).filter {
            $0.isWithinLookback(configuration.lookbackHours ?? 72)
        }
        let tasks = matches.map { message in
            AssistantTask(
                title: message.title,
                source: .slack,
                dueDate: TaskExtractor.inferredDueDate(from: message.text, relativeTo: message.timestampDate ?? .now),
                priority: TaskExtractor.priority(from: message.text, default: .normal),
                status: .open,
                context: message.text.trimmingCharacters(in: .whitespacesAndNewlines),
                owner: message.username ?? message.user ?? "Slack",
                requiresUserReview: TaskExtractor.requiresReview(from: message.text),
                recommendedAction: "메시지 내용을 확인하고 필요한 답변 또는 일정 조정을 진행",
                metadata: [
                    MetadataItem(label: "채널", value: message.channel?.name ?? message.channel?.id ?? "알 수 없음"),
                    MetadataItem(label: "링크", value: message.permalink ?? "없음")
                ]
            )
        }

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .slack,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "Slack 검색 결과에서 확인/일정 후보를 가져왔습니다."
            )
        )
    }
}

private struct SlackSearchResponse: Decodable {
    var ok: Bool
    var error: String?
    var messages: SlackMessages?
}

private struct SlackMessages: Decodable {
    var matches: [SlackMessage]
}

private struct SlackMessage: Decodable {
    var text: String
    var permalink: String?
    var ts: String?
    var user: String?
    var username: String?
    var channel: SlackChannel?

    var title: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Slack 확인 항목"
        }

        return String(trimmed.prefix(72))
    }

    var timestampDate: Date? {
        SlackDateParser.date(from: ts)
    }

    func isWithinLookback(_ lookbackHours: Double) -> Bool {
        guard lookbackHours > 0, let timestampDate else {
            return true
        }

        return timestampDate >= Date.now.addingTimeInterval(-lookbackHours * 60 * 60)
    }
}

private struct SlackChannel: Decodable {
    var id: String?
    var name: String?
}
