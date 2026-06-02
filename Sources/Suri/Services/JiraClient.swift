import Foundation

struct JiraClient: WorkItemProvider {
    let configuration: JiraIntegrationConfiguration
    let httpClient = HTTPServiceClient()

    var source: WorkSource { .jira }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let baseURL = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql") else {
            throw ServiceClientError.invalidURL(configuration.baseURL)
        }

        components.queryItems = [
            URLQueryItem(name: "jql", value: configuration.jql ?? "assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC"),
            URLQueryItem(name: "maxResults", value: "30"),
            URLQueryItem(name: "fields", value: "summary,duedate,status,priority,assignee")
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL("Jira search")
        }

        var request = URLRequest(url: url)
        let credential = "\(configuration.email):\(configuration.apiToken)"
        let encodedCredential = Data(credential.utf8).base64EncodedString()
        request.setValue("Basic \(encodedCredential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await httpClient.data(for: request)
        let response = try JSONDecoder.jira.decode(JiraSearchResponse.self, from: data)

        let tasks = response.issues.map { issue in
            let summary = issue.fields.summary
            let context = "\(issue.key) \(issue.fields.status?.name ?? "상태 없음")"
            return AssistantTask(
                title: summary,
                source: .jira,
                dueDate: issue.fields.dueDate ?? TaskExtractor.inferredDueDate(from: summary, fallbackHours: 72),
                priority: issue.fields.priority.taskPriority,
                status: .scheduled,
                context: context,
                owner: issue.fields.assignee?.displayName ?? "나",
                requiresUserReview: TaskExtractor.requiresReview(from: summary),
                recommendedAction: "Jira 이슈 상태와 남은 blocker를 확인",
                metadata: [
                    MetadataItem(label: "이슈", value: issue.key),
                    MetadataItem(label: "상태", value: issue.fields.status?.name ?? "알 수 없음")
                ]
            )
        }

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .jira,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "Jira JQL 결과에서 담당 이슈를 가져왔습니다."
            )
        )
    }
}

private struct JiraSearchResponse: Decodable {
    var issues: [JiraIssue]
}

private struct JiraIssue: Decodable {
    var key: String
    var fields: JiraIssueFields
}

private struct JiraIssueFields: Decodable {
    var summary: String
    var dueDate: Date?
    var status: JiraNamedValue?
    var priority: JiraNamedValue?
    var assignee: JiraAssignee?

    enum CodingKeys: String, CodingKey {
        case summary
        case dueDate = "duedate"
        case status
        case priority
        case assignee
    }
}

private struct JiraNamedValue: Decodable {
    var name: String
}

private struct JiraAssignee: Decodable {
    var displayName: String
}

private extension JiraNamedValue? {
    var taskPriority: TaskPriority {
        switch self?.name.lowercased() {
        case "highest", "blocker", "critical":
            .urgent
        case "high":
            .high
        case "low", "lowest":
            .low
        default:
            .normal
        }
    }
}

private extension JSONDecoder {
    static var jira: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.yearMonthDay)
        return decoder
    }
}
