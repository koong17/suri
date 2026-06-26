import Foundation
import Network

struct GmailOAuthClientCredentials {
    var clientID: String
    var clientSecret: String
    var sourceDescription: String

    static func resolve(
        configuration: GmailIntegrationConfiguration,
        candidateFiles: [URL]? = nil
    ) throws -> GmailOAuthClientCredentials {
        if let clientID = configuration.clientID?.nilIfEmpty,
           let clientSecret = configuration.clientSecret?.nilIfEmpty {
            return GmailOAuthClientCredentials(
                clientID: clientID,
                clientSecret: clientSecret,
                sourceDescription: "integrations.json"
            )
        }

        let files = candidateFiles ?? defaultCandidateFiles(for: configuration)
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            let document = try JSONDecoder().decode(GoogleOAuthClientSecretDocument.self, from: data)
            if let secret = document.preferredClientSecret {
                return GmailOAuthClientCredentials(
                    clientID: secret.clientID,
                    clientSecret: secret.clientSecret,
                    sourceDescription: file.path
                )
            }
        }

        let preferredPath = IntegrationConfiguration.gmailClientSecretFileURL.path
        throw ServiceClientError.serviceMessage(
            "Gmail OAuth 클라이언트 설정이 없습니다. Google Cloud에서 Desktop OAuth JSON을 내려받아 \(preferredPath)에 저장하거나 integrations.json의 email.gmail.clientID/clientSecret을 설정하세요."
        )
    }

    private static func defaultCandidateFiles(for configuration: GmailIntegrationConfiguration) -> [URL] {
        var files: [URL] = []
        if let configuredPath = configuration.clientSecretFile?.nilIfEmpty {
            files.append(URL(fileURLWithPath: configuredPath.expandingTildeInPath))
        }
        files.append(IntegrationConfiguration.gmailClientSecretFileURL)
        files.append(IntegrationConfiguration.googleCredentialsFileURL)
        return files.removingDuplicatesByPath()
    }
}

struct GmailOAuthService {
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private let tokenStore = GmailTokenStore()

    func authorize(configuration: GmailIntegrationConfiguration) async throws {
        let credentials = try GmailOAuthClientCredentials.resolve(configuration: configuration)
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let loopbackServer = OAuthLoopbackServer(expectedState: state)
        let port = try await loopbackServer.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let authURL = try authorizationURL(clientID: credentials.clientID, redirectURI: redirectURI, state: state)

        try openInBrowser(authURL)
        let code = try await waitForAuthorizationCode(from: loopbackServer)
        let token = try await exchangeAuthorizationCode(
            code,
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret,
            redirectURI: redirectURI
        )
        try tokenStore.save(token)
    }

    private func waitForAuthorizationCode(from loopbackServer: OAuthLoopbackServer) async throws -> String {
        defer {
            loopbackServer.cancel()
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await loopbackServer.waitForCode()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                throw ServiceClientError.serviceMessage("Gmail 로그인 시간이 초과되었습니다.")
            }

            guard let code = try await group.next() else {
                throw ServiceClientError.serviceMessage("Gmail OAuth code가 없습니다.")
            }
            group.cancelAll()
            return code
        }
    }

    func accessToken(configuration: GmailIntegrationConfiguration) async throws -> String {
        let credentials = try GmailOAuthClientCredentials.resolve(configuration: configuration)
        guard var token = try tokenStore.load() else {
            throw ServiceClientError.serviceMessage("Gmail 로그인이 필요합니다. Settings > Integrations에서 Gmail 로그인을 먼저 실행하세요.")
        }

        if token.expiresAt.timeIntervalSinceNow > 60 {
            return token.accessToken
        }

        token = try await refreshToken(
            token.refreshToken,
            clientID: credentials.clientID,
            clientSecret: credentials.clientSecret
        )
        try tokenStore.save(token)
        return token.accessToken
    }

    private func authorizationURL(clientID: String, redirectURI: String, state: String) throws -> URL {
        guard var components = URLComponents(string: Self.authEndpoint) else {
            throw ServiceClientError.invalidURL(Self.authEndpoint)
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw ServiceClientError.invalidURL(Self.authEndpoint)
        }
        return url
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> GmailToken {
        let body = formEncoded([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
        let response: GmailTokenResponse = try await postTokenRequest(body: body)
        guard let refreshToken = response.refreshToken?.nilIfEmpty else {
            throw ServiceClientError.serviceMessage("Google이 refresh token을 반환하지 않았습니다. Google 계정 권한에서 앱을 제거한 뒤 다시 로그인하세요.")
        }
        return response.token(refreshToken: refreshToken)
    }

    private func refreshToken(_ refreshToken: String, clientID: String, clientSecret: String) async throws -> GmailToken {
        let body = formEncoded([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        let response: GmailTokenResponse = try await postTokenRequest(body: body)
        return response.token(refreshToken: refreshToken)
    }

    private func postTokenRequest<T: Decodable>(body: Data) async throws -> T {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8)?.nilIfEmpty ?? "Google token 요청 실패"
            throw ServiceClientError.serviceMessage(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func formEncoded(_ values: [String: String]) -> Data {
        let encoded = values.map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .joined(separator: "&")
        return Data(encoded.utf8)
    }

    private func openInBrowser(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
    }
}

private struct GmailTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    func token(refreshToken: String) -> GmailToken {
        GmailToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date.now.addingTimeInterval(expiresIn)
        )
    }
}

private struct GoogleOAuthClientSecretDocument: Decodable {
    var installed: GoogleOAuthClientSecret?
    var web: GoogleOAuthClientSecret?
    var google: GoogleOAuthClientSecret?
    var clientID: String?
    var clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case installed
        case web
        case google
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }

    var preferredClientSecret: GoogleOAuthClientSecret? {
        if let installed {
            return installed
        }
        if let google {
            return google
        }
        if let clientID = clientID?.nilIfEmpty,
           let clientSecret = clientSecret?.nilIfEmpty {
            return GoogleOAuthClientSecret(clientID: clientID, clientSecret: clientSecret)
        }
        return nil
    }
}

private struct GoogleOAuthClientSecret: Decodable {
    var clientID: String
    var clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

private struct GmailToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

private struct GmailTokenStore {
    private let fileURL = IntegrationConfiguration.directoryURL.appendingPathComponent("gmail-token.json")

    func load() throws -> GmailToken? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GmailToken.self, from: data)
    }

    func save(_ token: GmailToken) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(token)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    private let expectedState: String
    private let queue = DispatchQueue(label: "suri.gmail.oauth.loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?
    private var didFinish = false

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let ready = OneShotContinuation(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        ready.resume(.success(port.rawValue))
                    }
                case let .failed(error):
                    ready.resume(.failure(ServiceClientError.serviceMessage("OAuth loopback 실패: \(error.localizedDescription)")))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                lock.unlock()
                continuation.resume(with: pendingResult)
                return
            }
            codeContinuation = continuation
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        listener?.cancel()
        listener = nil
        lock.unlock()
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let result = self.parseRequest(request)
            self.respond(to: connection, result: result)
            switch result {
            case let .success(code):
                self.finish(.success(code))
            case let .failure(error):
                self.finish(.failure(error))
            case .unrelated:
                break
            }
        }
    }

    private func parseRequest(_ request: String) -> OAuthCallbackResult {
        guard let firstLine = request.components(separatedBy: .newlines).first else {
            return .failure(ServiceClientError.serviceMessage("OAuth callback 요청을 읽지 못했습니다."))
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
            return .failure(ServiceClientError.serviceMessage("OAuth callback URL을 읽지 못했습니다."))
        }

        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        if let error = values["error"] {
            return .failure(ServiceClientError.serviceMessage("Gmail 로그인 거부: \(error)"))
        }

        guard values["code"] != nil || values["state"] != nil else {
            return .unrelated
        }

        guard values["state"] == expectedState else {
            return .failure(ServiceClientError.serviceMessage("Gmail OAuth state가 일치하지 않습니다."))
        }

        guard let code = values["code"]?.nilIfEmpty else {
            return .failure(ServiceClientError.serviceMessage("Gmail OAuth code가 없습니다."))
        }

        return .success(code)
    }

    private func respond(to connection: NWConnection, result: OAuthCallbackResult) {
        let message = switch result {
        case .success:
            "Authorized - you can close this tab."
        case .failure:
            "Authorization failed - return to Suri."
        case .unrelated:
            "Waiting for Google authorization..."
        }
        let body = "<!doctype html><meta charset=utf-8><body style=\"font-family:system-ui;padding:2rem\">\(message)</body>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        listener?.cancel()
        if let continuation = codeContinuation {
            codeContinuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }
    }
}

private enum OAuthCallbackResult {
    case success(String)
    case failure(Error)
    case unrelated
}

private final class OneShotContinuation<T, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Failure>?

    init(_ continuation: CheckedContinuation<T, Failure>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Failure>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension Array where Element == URL {
    func removingDuplicatesByPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.path).inserted
        }
    }
}

private extension CharacterSet {
    static var urlFormAllowed: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }
}
