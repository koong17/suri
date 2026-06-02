import Foundation

struct GmailClient: WorkItemProvider {
    let configuration: EmailIntegrationConfiguration
    private let authService = GmailOAuthService()
    private let httpClient = HTTPServiceClient()

    var source: WorkSource { .email }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let gmail = configuration.gmail else {
            throw ServiceClientError.serviceMessage("Gmail 설정이 integrations.json에 없습니다.")
        }

        let accessToken = try await authService.accessToken(configuration: gmail)
        let refs = try await listMessages(accessToken: accessToken, configuration: gmail)
        var tasks: [AssistantTask] = []

        for reference in refs {
            do {
                let message = try await fetchMessage(id: reference.id, accessToken: accessToken)
                tasks.append(task(from: message))
            } catch {
                continue
            }
        }

        return ProviderSnapshot(
            tasks: tasks.sortedForAssistant(),
            connection: SourceConnection(
                source: .email,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "Gmail API에서 최근 메일 확인 항목을 가져왔습니다."
            )
        )
    }

    private func listMessages(
        accessToken: String,
        configuration: GmailIntegrationConfiguration
    ) async throws -> [GmailMessageReference] {
        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages") else {
            throw ServiceClientError.invalidURL("Gmail messages")
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: configuration.query?.nilIfEmpty ?? "in:inbox newer_than:7d"),
            URLQueryItem(name: "maxResults", value: "\(min(max(configuration.count ?? 30, 1), 100))")
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL("Gmail messages")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await httpClient.data(for: request)
        return try JSONDecoder().decode(GmailListResponse.self, from: data).messages ?? []
    }

    private func fetchMessage(id: String, accessToken: String) async throws -> GmailMessage {
        guard var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)") else {
            throw ServiceClientError.invalidURL("Gmail message")
        }
        components.queryItems = [
            URLQueryItem(name: "format", value: "full")
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL("Gmail message")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await httpClient.data(for: request)
        return try JSONDecoder().decode(GmailMessage.self, from: data)
    }

    private func task(from message: GmailMessage) -> AssistantTask {
        let subject = message.header("Subject")?.nilIfEmpty ?? "(no subject)"
        let from = message.header("From")?.nilIfEmpty ?? "Gmail"
        let body = message.bodyText.nilIfEmpty ?? message.snippet ?? subject
        let searchableText = [subject, from, body, message.labelIDs?.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: "\n")

        return AssistantTask(
            title: subject,
            source: .email,
            dueDate: TaskExtractor.inferredDueDate(from: searchableText),
            priority: TaskExtractor.priority(from: searchableText, default: message.isImportant ? .high : .normal),
            status: .open,
            context: body,
            owner: from,
            requiresUserReview: true,
            recommendedAction: "메일 본문을 확인하고 회신, 승인, 일정 등록 여부를 결정",
            metadata: [
                MetadataItem(label: "보낸 사람", value: from),
                MetadataItem(label: "라벨", value: message.labelIDs?.joined(separator: ", ") ?? "Gmail"),
                MetadataItem(label: "URL", value: "https://mail.google.com/mail/u/0/#inbox/\(message.id)")
            ]
        )
    }
}

private struct GmailListResponse: Decodable {
    var messages: [GmailMessageReference]?
}

private struct GmailMessageReference: Decodable {
    var id: String
}

private struct GmailMessage: Decodable {
    var id: String
    var snippet: String?
    var internalDate: String?
    var labelIDs: [String]?
    var payload: GmailPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case snippet
        case internalDate
        case labelIDs = "labelIds"
        case payload
    }

    var isImportant: Bool {
        labelIDs?.contains("IMPORTANT") == true
    }

    var bodyText: String {
        payload?.extractedText ?? ""
    }

    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct GmailPayload: Decodable {
    var mimeType: String?
    var headers: [GmailHeader]?
    var body: GmailBody?
    var parts: [GmailPayload]?

    var extractedText: String {
        if mimeType == "text/plain",
           let text = body?.decodedText.nilIfEmpty {
            return text
        }

        if mimeType == "text/html",
           let text = body?.decodedText.strippingHTML.nilIfEmpty {
            return text
        }

        return parts?
            .map(\.extractedText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n") ?? ""
    }
}

private struct GmailHeader: Decodable {
    var name: String
    var value: String
}

private struct GmailBody: Decodable {
    var data: String?

    var decodedText: String {
        guard let data else {
            return ""
        }

        var base64 = data
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }

        guard let decoded = Data(base64Encoded: base64) else {
            return ""
        }
        return String(data: decoded, encoding: .utf8) ?? ""
    }
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
