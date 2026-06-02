import Foundation

struct JiraClient: WorkItemProvider {
    let configuration: JiraIntegrationConfiguration
    let httpClient = HTTPServiceClient()

    var source: WorkSource { .jira }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let baseURL = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let authorizationHeader = basicAuthorizationHeader()
        try await validateAuthentication(baseURL: baseURL, authorizationHeader: authorizationHeader)

        guard var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql") else {
            throw ServiceClientError.invalidURL(configuration.baseURL)
        }

        components.queryItems = [
            URLQueryItem(name: "jql", value: configuration.jql ?? Self.defaultJQL),
            URLQueryItem(name: "maxResults", value: "30"),
            URLQueryItem(name: "fields", value: "summary,duedate,status,priority,assignee,reporter,creator")
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL("Jira search")
        }

        var request = URLRequest(url: url)
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
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
                    MetadataItem(label: "상태", value: issue.fields.status?.name ?? "알 수 없음"),
                    MetadataItem(label: "URL", value: "\(baseURL)/browse/\(issue.key)")
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

    private static let defaultJQL = """
    (assignee = currentUser() OR reporter = currentUser() OR creator = currentUser() OR watcher = currentUser()) AND statusCategory != Done ORDER BY updated DESC
    """

    private func basicAuthorizationHeader() -> String {
        let credential = "\(configuration.email):\(configuration.apiToken)"
        let encodedCredential = Data(credential.utf8).base64EncodedString()
        return "Basic \(encodedCredential)"
    }

    private func validateAuthentication(baseURL: String, authorizationHeader: String) async throws {
        guard let url = URL(string: "\(baseURL)/rest/api/3/myself") else {
            throw ServiceClientError.invalidURL("\(baseURL)/rest/api/3/myself")
        }

        var request = URLRequest(url: url)
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            _ = try await httpClient.data(for: request)
        } catch ServiceClientError.badStatus(401, _) {
            throw ServiceClientError.serviceMessage("Jira 인증 실패: Settings의 email/apiToken을 다시 확인하세요.")
        } catch ServiceClientError.badStatus(403, _) {
            throw ServiceClientError.serviceMessage("Jira 권한 부족: 현재 계정으로 프로젝트/이슈를 볼 수 없습니다.")
        } catch {
            throw error
        }
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
