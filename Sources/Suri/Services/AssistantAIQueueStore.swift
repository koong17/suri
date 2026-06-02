import Foundation

struct AssistantAIQueueStore {
    private let fileURL: URL

    init(fileURL: URL = AssistantAIQueueStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        IntegrationConfiguration.directoryURL.appendingPathComponent("ai-queue.json")
    }

    func refreshPendingItems(from tasks: [AssistantTask], syncedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let items = tasks
            .filter(\.needsAIReview)
            .map { task in
                AssistantAIQueueItem(
                    id: task.reviewKey.stableQueueID,
                    source: task.source,
                    title: task.title,
                    context: String(task.context.prefix(1_500)),
                    queuedAt: syncedAt,
                    contentHash: task.queueContentHash
                )
            }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private struct AssistantAIQueueItem: Codable, Identifiable {
    var id: String
    var source: WorkSource
    var title: String
    var context: String
    var queuedAt: Date
    var contentHash: String
}

private extension AssistantTask {
    var needsAIReview: Bool {
        requiresUserReview && (
            source == .slack
                || source == .email
                || source == .notes
        )
    }

    var queueContentHash: String {
        [source.rawValue, title, context, recommendedAction]
            .joined(separator: "\n")
            .stableQueueID
    }
}

private extension String {
    var stableQueueID: String {
        let offset: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let hash = normalized.utf8.reduce(offset) { partialResult, byte in
            (partialResult ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", hash)
    }
}
