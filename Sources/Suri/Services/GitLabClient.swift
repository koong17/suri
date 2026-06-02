import Foundation

struct GitLabClient: WorkItemProvider {
    let configuration: GitLabIntegrationConfiguration
    let httpClient = HTTPServiceClient()

    var source: WorkSource { .gitLab }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let requests = try requestURLs().map { url -> URLRequest in
            var request = URLRequest(url: url)
            request.setValue(configuration.privateToken, forHTTPHeaderField: "PRIVATE-TOKEN")
            return request
        }

        var mergeRequests: [GitLabMergeRequest] = []
        for request in requests {
            let data = try await httpClient.data(for: request)
            mergeRequests += try JSONDecoder.gitLab.decode([GitLabMergeRequest].self, from: data)
        }

        let tasks = mergeRequests.map { mergeRequest in
            AssistantTask(
                title: mergeRequest.title,
                source: .gitLab,
                dueDate: mergeRequest.milestone?.dueDate ?? TaskExtractor.inferredDueDate(from: mergeRequest.title, fallbackHours: 48),
                priority: mergeRequest.draft == true ? .normal : .high,
                status: .waiting,
                context: mergeRequest.description?.nilIfEmpty ?? "GitLab merge request 확인이 필요합니다.",
                owner: mergeRequest.author?.username ?? "GitLab",
                requiresUserReview: true,
                recommendedAction: "변경 범위와 파이프라인 상태를 확인한 뒤 리뷰 또는 머지 판단",
                metadata: [
                    MetadataItem(label: "MR", value: mergeRequest.reference),
                    MetadataItem(label: "URL", value: mergeRequest.webURL)
                ]
            )
        }

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .gitLab,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "할당된 열린 merge request를 확인했습니다."
            )
        )
    }

    private func requestURLs() throws -> [URL] {
        let baseURL = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let projectIDs = configuration.projectIDs?.filter { !$0.isEmpty } ?? []

        if projectIDs.isEmpty {
            return [try mergeRequestURL(path: "\(baseURL)/api/v4/merge_requests")]
        }

        return try projectIDs.map { projectID in
            let escapedID = Self.encodedProjectID(projectID)
            return try mergeRequestURL(path: "\(baseURL)/api/v4/projects/\(escapedID)/merge_requests")
        }
    }

    private static func encodedProjectID(_ projectID: String) -> String {
        let trimmed = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            let pathComponents = url.path
                .split(separator: "/")
                .map(String.init)
            let projectPath = pathComponents
                .prefix { $0 != "-" }
                .joined(separator: "/")

            if !projectPath.isEmpty {
                return encodeProjectPath(projectPath)
            }
        }

        if trimmed.contains("%2F") || trimmed.contains("%2f") {
            return trimmed
        }

        return encodeProjectPath(trimmed)
    }

    private static func encodeProjectPath(_ projectPath: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return projectPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? projectPath
    }

    private func mergeRequestURL(path: String) throws -> URL {
        guard var components = URLComponents(string: path) else {
            throw ServiceClientError.invalidURL(path)
        }

        let queryItems = [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "scope", value: configuration.scope?.nilIfEmpty ?? "reviews_for_me"),
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "30")
        ]

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ServiceClientError.invalidURL(path)
        }

        return url
    }
}

private struct GitLabMergeRequest: Decodable {
    var iid: Int?
    var title: String
    var description: String?
    var webURL: String
    var draft: Bool?
    var author: GitLabUser?
    var references: GitLabReferences?
    var milestone: GitLabMilestone?

    var reference: String {
        references?.full ?? iid.map { "!\($0)" } ?? "MR"
    }

    enum CodingKeys: String, CodingKey {
        case iid
        case title
        case description
        case webURL = "web_url"
        case draft
        case author
        case references
        case milestone
    }
}

private struct GitLabUser: Decodable {
    var username: String
}

private struct GitLabReferences: Decodable {
    var full: String?
}

private struct GitLabMilestone: Decodable {
    var dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case dueDate = "due_date"
    }
}

private extension JSONDecoder {
    static var gitLab: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.yearMonthDay)
        return decoder
    }
}
