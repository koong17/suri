import Foundation

protocol WorkItemProvider {
    var source: WorkSource { get }
    func fetchSnapshot() async throws -> ProviderSnapshot
}

struct ProviderSnapshot {
    var tasks: [AssistantTask]
    var connection: SourceConnection
    var notes: [AssistantNote]

    init(tasks: [AssistantTask], connection: SourceConnection, notes: [AssistantNote] = []) {
        self.tasks = tasks
        self.connection = connection
        self.notes = notes
    }
}

struct AssistantSyncResult: Codable {
    var tasks: [AssistantTask]
    var sources: [SourceConnection]
    var notes: [AssistantNote]
    var providerErrors: [String]
    var usedFallback: Bool
    var syncedAt: Date
}

enum ServiceClientError: LocalizedError {
    case missingConfiguration
    case invalidURL(String)
    case badStatus(Int, URL?)
    case serviceMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "연동 설정이 없습니다."
        case let .invalidURL(value):
            "잘못된 URL: \(value)"
        case let .badStatus(status, url):
            if let url {
                "HTTP 상태 코드 \(status): \(url.absoluteString)"
            } else {
                "HTTP 상태 코드 \(status)"
            }
        case let .serviceMessage(message):
            message
        }
    }
}

struct HTTPServiceClient {
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceClientError.badStatus(httpResponse.statusCode, request.url)
        }

        return data
    }
}
