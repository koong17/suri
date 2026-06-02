import Foundation

struct AgentSlackClient: WorkItemProvider {
    let configuration: SlackIntegrationConfiguration

    var source: WorkSource { .slack }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        var messages = try await fetchMentionMessages()

        if configuration.includeLater != false {
            messages += (try? fetchLaterMessages()) ?? []
        }

        messages = filteredMessages(from: messages.deduplicated())
        messages = await applyingCodexImportance(to: messages)

        let tasks = messages.map { message in
            let relevance = message.relevance
            let isImportant = message.isImportant
            var metadata = [
                MetadataItem(label: "채널", value: message.channelName),
                MetadataItem(label: "분류", value: isImportant ? "중요 \(relevance.title)" : relevance.title),
                MetadataItem(label: "링크", value: message.permalink ?? "agent-slack")
            ]
            if let codexReason = message.codexReason?.nilIfEmpty {
                metadata.append(MetadataItem(label: "Codex 판단", value: codexReason))
            }

            return AssistantTask(
                title: message.title,
                source: .slack,
                dueDate: TaskExtractor.inferredDueDate(from: message.searchableText, relativeTo: message.referenceDate ?? .now),
                priority: TaskExtractor.priority(from: message.searchableText, default: isImportant ? .high : relevance.defaultPriority),
                status: .open,
                context: message.context,
                owner: message.authorName,
                requiresUserReview: true,
                recommendedAction: isImportant ? relevance.importantRecommendedAction : relevance.recommendedAction,
                metadata: metadata
            )
        }

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .slack,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "읽음 여부와 무관하게 최근 멘션을 확인했습니다."
            )
        )
    }

    private func filteredMessages(from messages: [AgentSlackMessage]) -> [AgentSlackMessage] {
        let relevantMessages = messages.filter { message in
            message.relevance != .notRelevant && message.isWithinLookback(configuration.lookbackHours ?? 72)
        }
        guard configuration.importantOnly == true else {
            return relevantMessages
        }

        return relevantMessages.filter { message in
            message.relevance == .directMessage
                || message.relevance == .savedForLater
                || message.isImportant
        }
    }

    private func applyingCodexImportance(to messages: [AgentSlackMessage]) async -> [AgentSlackMessage] {
        guard configuration.codexImportanceEnabled != false, !messages.isEmpty else {
            return messages
        }

        do {
            let classifier = CodexSlackImportanceClassifier(
                timeoutSeconds: configuration.codexTimeoutSeconds ?? 30
            )
            let classifications = try await classifier.classify(messages: messages)
            return messages.enumerated().map { index, message in
                guard let classification = classifications[index] else {
                    return message
                }

                var updatedMessage = message
                updatedMessage.codexImportant = classification.important
                updatedMessage.codexReason = classification.reason
                return updatedMessage
            }
        } catch {
            return messages
        }
    }

    private func fetchMentionMessages() async throws -> [AgentSlackMessage] {
        if let query = configuration.query?.nilIfEmpty {
            return try await fetchSearchMessages(query: query)
        }

        var messages: [AgentSlackMessage] = []
        var firstError: Error?

        for query in defaultMentionQueries {
            do {
                messages += try await fetchSearchMessages(query: query)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if messages.isEmpty, let firstError {
            throw firstError
        }

        return messages
    }

    private func fetchSearchMessages(query: String) async throws -> [AgentSlackMessage] {
        let output = try await runAgentSlack(arguments: searchArguments(query: query))
        let response = try JSONDecoder().decode(AgentSlackResponse.self, from: output)
        return response.extractedMessages
    }

    private func fetchLaterMessages() throws -> [AgentSlackMessage] {
        let output = try syncRunAgentSlack(arguments: ["later", "list"])
        let response = try JSONDecoder().decode(AgentSlackLaterResponse.self, from: output)
        return response.items.compactMap { item in
            guard var message = item.message else {
                return nil
            }

            message.channelNameFallback = item.channelName
            message.channelIDFallback = item.channelID
            message.savedForLater = true
            message.laterState = item.state
            message.dateSaved = item.dateSavedDate
            return message
        }
    }

    private func searchArguments(query: String) -> [String] {
        let count = "\(min(configuration.count ?? 20, 100))"
        let workspace = configuration.workspace?.nilIfEmpty
        let lookbackHours = configuration.lookbackHours ?? 72
        let afterDate = Self.searchDateFormatter.string(from: Date.now.addingTimeInterval(-lookbackHours * 60 * 60))

        var args = [
            "search",
            "messages",
            query,
            "--limit",
            count,
            "--max-content-chars",
            "600",
            "--resolve-users",
            "--after",
            afterDate
        ]
        if let workspace {
            args += ["--workspace", workspace]
        }
        return args
    }

    private var defaultMentionQueries: [String] {
        ["to:me", "@here", "@channel", "@everyone"]
    }

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func runAgentSlack(arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["agent-slack"] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ServiceClientError.serviceMessage("agent-slack 실행 실패: \(error.localizedDescription)"))
                return
            }

            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?.nilIfEmpty

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: ServiceClientError.serviceMessage(errorMessage ?? "agent-slack 종료 코드 \(process.terminationStatus)"))
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }

    private func syncRunAgentSlack(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["agent-slack"] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8)?.nilIfEmpty

        guard process.terminationStatus == 0 else {
            throw ServiceClientError.serviceMessage(errorMessage ?? "agent-slack 종료 코드 \(process.terminationStatus)")
        }

        return output
    }
}

private struct AgentSlackResponse: Decodable {
    var messages: [AgentSlackMessage]?
    var channels: [AgentSlackChannel]?

    var extractedMessages: [AgentSlackMessage] {
        if let messages {
            return messages
        }

        return channels?.flatMap { channel in
            (channel.messages ?? []).map { message in
                var enriched = message
                enriched.channelNameFallback = channel.channelName
                enriched.channelIDFallback = channel.channelID
                enriched.channelTypeFallback = channel.channelType
                enriched.mentionCountFallback = channel.mentionCount
                return enriched
            }
        } ?? []
    }

    var unreadCount: Int {
        channels?.reduce(0) { $0 + ($1.unreadCount ?? 0) } ?? (messages?.count ?? 0)
    }
}

private struct AgentSlackChannel: Decodable {
    var channelID: String?
    var channelName: String?
    var channelType: String?
    var unreadCount: Int?
    var mentionCount: Int?
    var messages: [AgentSlackMessage]?

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case channelName = "channel_name"
        case channelType = "channel_type"
        case unreadCount = "unread_count"
        case mentionCount = "mention_count"
        case messages
    }
}

private struct AgentSlackLaterResponse: Decodable {
    var items: [AgentSlackLaterItem]
}

private struct AgentSlackLaterItem: Decodable {
    var channelID: String?
    var channelName: String?
    var state: String?
    var dateSaved: Date?
    var message: AgentSlackMessage?

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case channelName = "channel_name"
        case state
        case dateSaved = "date_saved"
        case dateSavedCamel = "dateSaved"
        case savedAt = "saved_at"
        case savedAtCamel = "savedAt"
        case created
        case createdAt = "created_at"
        case ts
        case messageTS = "message_ts"
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try container.decodeIfPresent(String.self, forKey: .channelID)
        channelName = try container.decodeIfPresent(String.self, forKey: .channelName)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        dateSaved = container.decodeFlexibleDateIfPresent(forKeys: [
            .dateSaved,
            .dateSavedCamel,
            .savedAt,
            .savedAtCamel,
            .created,
            .createdAt
        ])

        var decodedMessage = try container.decodeIfPresent(AgentSlackMessage.self, forKey: .message)
        if decodedMessage?.ts == nil {
            decodedMessage?.ts = container.decodeFlexibleStringIfPresent(forKey: .messageTS)
                ?? container.decodeFlexibleStringIfPresent(forKey: .ts)
        }
        message = decodedMessage
    }

    var dateSavedDate: Date? {
        dateSaved
    }
}

private struct AgentSlackMessage: Decodable {
    var channelID: String?
    var rawChannelName: String?
    var ts: String?
    var permalink: String?
    var content: String?
    var text: String?
    var body: String?
    var author: AgentSlackAuthor?
    var user: String?
    var username: String?
    var rawMentionCount: Int?
    var channelNameFallback: String?
    var channelIDFallback: String?
    var channelTypeFallback: String?
    var mentionCountFallback: Int?
    var savedForLater = false
    var laterState: String?
    var dateSaved: Date?
    var codexImportant: Bool?
    var codexReason: String?

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case rawChannelName = "channel_name"
        case ts
        case permalink
        case content
        case text
        case body
        case author
        case user
        case username
        case rawMentionCount = "mention_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try container.decodeIfPresent(String.self, forKey: .channelID)
        rawChannelName = try container.decodeIfPresent(String.self, forKey: .rawChannelName)
        ts = container.decodeFlexibleStringIfPresent(forKey: .ts)
        permalink = try container.decodeIfPresent(String.self, forKey: .permalink)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        author = try container.decodeIfPresent(AgentSlackAuthor.self, forKey: .author)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        rawMentionCount = container.decodeFlexibleIntIfPresent(forKey: .rawMentionCount)
    }

    var channelNameResolved: String {
        rawChannelName ?? channelNameFallback ?? channelID ?? channelIDFallback ?? "Slack"
    }

    var channelName: String {
        channelNameResolved
    }

    var authorName: String {
        author?.displayName ?? author?.realName ?? author?.name ?? username ?? user ?? "Slack"
    }

    var mentionCountResolved: Int {
        rawMentionCount ?? mentionCountFallback ?? 0
    }

    var searchableText: String {
        [content, text, body, title].compactMap { $0 }.joined(separator: "\n")
    }

    var context: String {
        (content ?? text ?? body ?? title).nilIfEmpty ?? "Slack 메시지 확인이 필요합니다."
    }

    var title: String {
        let value = (content ?? text ?? body)?.nilIfEmpty ?? "Slack 확인 항목"
        return String(value.prefix(72))
    }

    var mentionCount: Int {
        mentionCountResolved
    }

    var channelType: String {
        channelTypeFallback ?? ""
    }

    var relevance: SlackMessageRelevance {
        if isDirectMessage {
            return .directMessage
        }

        if savedForLater {
            return .savedForLater
        }

        if isMentionLike {
            return isBroadcastMention ? .broadcastMention : .mention
        }

        return .notRelevant
    }

    var isDirectMessage: Bool {
        channelType == "dm" || channelID?.hasPrefix("D") == true || channelIDFallback?.hasPrefix("D") == true
    }

    var isMentionLike: Bool {
        mentionCount > 0 || isBroadcastMention || containsUserMention
    }

    var isBroadcastMention: Bool {
        let lowered = searchableText.lowercased()
        return lowered.contains("@here")
            || lowered.contains("@channel")
            || lowered.contains("@everyone")
            || lowered.contains("<!here>")
            || lowered.contains("<!channel>")
            || lowered.contains("<!everyone>")
    }

    var containsUserMention: Bool {
        searchableText.contains("<@")
    }

    var isImportant: Bool {
        if let codexImportant {
            return codexImportant
        }

        if isLowSignalBroadcast {
            return false
        }

        let lowered = searchableText.lowercased()
        let importantKeywords = [
            "urgent", "asap", "important", "blocker", "blocked", "incident",
            "outage", "error", "failed", "failure", "prod", "production",
            "deploy", "release", "review", "approve", "confirm", "decision",
            "deadline", "due", "today", "tomorrow", "eod", "ping",
            "긴급", "중요", "장애", "에러", "실패", "배포", "릴리즈",
            "리뷰", "검토", "승인", "확인", "결정", "마감", "기한",
            "오늘", "내일", "요청", "대응", "답변", "블로커", "운영"
        ]

        return importantKeywords.contains { lowered.contains($0) }
            || TaskExtractor.requiresReview(from: searchableText)
            || TaskExtractor.inferredDueDate(from: searchableText, relativeTo: referenceDate ?? .now) != nil
    }

    var isLowSignalBroadcast: Bool {
        guard isBroadcastMention else {
            return false
        }

        let lowered = searchableText.lowercased()
        let lowSignalKeywords = [
            "점심", "식당", "메뉴", "메뉴보기", "투표", "다시 누르면", "샐러드",
            "막국수", "분식", "한식", "lunch", "menu", "vote"
        ]

        return lowSignalKeywords.contains { lowered.contains($0) }
    }

    var timestampDate: Date? {
        SlackDateParser.date(from: ts)
    }

    var referenceDate: Date? {
        dateSaved ?? timestampDate
    }

    func isWithinLookback(_ lookbackHours: Double) -> Bool {
        guard lookbackHours > 0 else {
            return true
        }

        let threshold = Date.now.addingTimeInterval(-lookbackHours * 60 * 60)

        if let timestampDate {
            return timestampDate >= threshold
        }

        if let dateSaved {
            return dateSaved >= threshold
        }

        return !savedForLater
    }
}

enum SlackDateParser {
    static func date(from value: String?) -> Date? {
        guard let value = value?.nilIfEmpty else {
            return nil
        }

        if let timestamp = Double(value) {
            return Date(timeIntervalSince1970: timestamp)
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        return nil
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        return nil
    }

    func decodeFlexibleDateIfPresent(forKeys keys: [Key]) -> Date? {
        for key in keys {
            if let value = decodeFlexibleStringIfPresent(forKey: key),
               let date = SlackDateParser.date(from: value) {
                return date
            }
        }

        return nil
    }
}

private struct CodexSlackImportanceClassifier {
    let timeoutSeconds: Double

    func classify(messages: [AgentSlackMessage]) async throws -> [Int: CodexClassification] {
        let promptItems = messages.enumerated().map { index, message in
            CodexPromptItem(
                index: index,
                source: message.relevance.title,
                text: String(message.searchableText.prefix(1_200))
            )
        }

        let data = try JSONEncoder().encode(promptItems)
        guard let payload = String(data: data, encoding: .utf8) else {
            return [:]
        }

        let prompt = """
        You classify Slack messages for a personal assistant app.
        Mark important=true only when the user likely needs to act, reply, approve, decide, handle an incident, track a release, or meet a deadline.
        Mark important=false for lunch polls, menu votes, broad social chatter, lightweight FYI, or content that only needs passive reading.
        Return only a JSON array. Each item must be {"index": number, "important": boolean, "reason": "short Korean reason"}.

        Slack messages:
        \(payload)
        """

        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("suri-codex-importance-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let output = try await runCodex(prompt: prompt, outputURL: outputURL)
        let json = try extractJSONArray(from: output)
        let classifications = try JSONDecoder().decode([CodexClassification].self, from: json)
        return Dictionary(uniqueKeysWithValues: classifications.map { ($0.index, $0) })
    }

    private func runCodex(prompt: String, outputURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "codex",
                "exec",
                "--ephemeral",
                "--skip-git-repo-check",
                "--ask-for-approval",
                "never",
                "--sandbox",
                "read-only",
                "--color",
                "never",
                "-C",
                FileManager.default.temporaryDirectory.path,
                "-o",
                outputURL.path,
                "-"
            ]

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let completion = CodexProcessCompletion()

            process.terminationHandler = { process in
                _ = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?.nilIfEmpty

                guard process.terminationStatus == 0 else {
                    completion.finish(
                        .failure(ServiceClientError.serviceMessage(errorMessage ?? "codex 종료 코드 \(process.terminationStatus)")),
                        continuation: continuation
                    )
                    return
                }

                do {
                    let data = try Data(contentsOf: outputURL)
                    let output = String(data: data, encoding: .utf8) ?? ""
                    completion.finish(.success(output), continuation: continuation)
                } catch {
                    completion.finish(.failure(error), continuation: continuation)
                }
            }

            do {
                try process.run()
                if let data = prompt.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                try? inputPipe.fileHandleForWriting.close()
            } catch {
                completion.finish(
                    .failure(ServiceClientError.serviceMessage("codex 실행 실패: \(error.localizedDescription)")),
                    continuation: continuation
                )
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + max(timeoutSeconds, 5)) {
                guard completion.shouldTerminate else {
                    return
                }

                if process.isRunning {
                    process.terminate()
                }
                completion.finish(
                    .failure(ServiceClientError.serviceMessage("codex 중요도 분류 시간 초과")),
                    continuation: continuation
                )
            }
        }
    }

    private func extractJSONArray(from output: String) throws -> Data {
        guard let start = output.firstIndex(of: "["),
              let end = output.lastIndex(of: "]"),
              start <= end else {
            throw ServiceClientError.serviceMessage("codex 중요도 분류 결과를 JSON으로 읽지 못했습니다.")
        }

        return Data(output[start...end].utf8)
    }
}

private struct CodexPromptItem: Encodable {
    var index: Int
    var source: String
    var text: String
}

private struct CodexClassification: Decodable {
    var index: Int
    var important: Bool
    var reason: String
}

private final class CodexProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false

    var shouldTerminate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !didFinish
    }

    func finish(
        _ result: Result<String, Error>,
        continuation: CheckedContinuation<String, Error>
    ) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }

        didFinish = true
        lock.unlock()

        continuation.resume(with: result)
    }
}

private extension Array where Element == AgentSlackMessage {
    func deduplicated() -> [AgentSlackMessage] {
        var seen = Set<String>()
        var result: [AgentSlackMessage] = []

        for message in self {
            let key = message.permalink ?? "\(message.channelName)-\(message.ts ?? message.title)"
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(message)
        }

        return result
    }
}

private struct AgentSlackAuthor: Decodable {
    var name: String?
    var realName: String?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case realName = "real_name"
        case displayName = "display_name"
    }
}

private enum SlackMessageRelevance {
    case directMessage
    case mention
    case broadcastMention
    case savedForLater
    case notRelevant

    var title: String {
        switch self {
        case .directMessage:
            "DM"
        case .mention:
            "멘션"
        case .broadcastMention:
            "@here/@channel"
        case .savedForLater:
            "나중에 확인"
        case .notRelevant:
            "제외"
        }
    }

    var defaultPriority: TaskPriority {
        switch self {
        case .directMessage:
            .normal
        case .mention, .broadcastMention:
            .normal
        case .savedForLater:
            .normal
        case .notRelevant:
            .low
        }
    }

    var recommendedAction: String {
        switch self {
        case .directMessage:
            "DM 내용을 확인하고 답변 또는 일정 등록 여부를 결정"
        case .mention:
            "나를 멘션한 중요한 Slack 메시지를 확인하고 필요한 후속 조치 결정"
        case .broadcastMention:
            "@here/@channel/@everyone 멘션 중 중요한 항목으로 판단되어 확인 필요"
        case .savedForLater:
            "Slack Later에 저장된 과거 메시지입니다. 읽음 여부와 상관없이 확인 필요"
        case .notRelevant:
            "Slack 메시지 확인"
        }
    }

    var importantRecommendedAction: String {
        switch self {
        case .directMessage:
            "중요한 DM으로 판단됩니다. 답변 또는 일정 등록 여부를 먼저 결정"
        case .mention:
            "중요한 개인 멘션으로 판단됩니다. 필요한 답변, 승인, 일정 조정을 먼저 처리"
        case .broadcastMention:
            "중요한 전사/채널 멘션으로 판단됩니다. 공지 영향 범위와 필요한 후속 조치를 확인"
        case .savedForLater:
            "중요한 Slack Later 항목으로 판단됩니다. 읽음 여부와 별개로 후속 처리 필요"
        case .notRelevant:
            "중요 Slack 메시지 확인"
        }
    }
}
