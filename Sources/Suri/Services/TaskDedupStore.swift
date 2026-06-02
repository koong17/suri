import Foundation

struct TaskDeduplicationResult {
    var tasks: [AssistantTask]
    var duplicateCounts: [WorkSource: Int]
}

struct TaskDeduplicator {
    func deduplicate(_ tasks: [AssistantTask]) -> TaskDeduplicationResult {
        var seenKeys = Set<String>()
        var uniqueTasks: [AssistantTask] = []
        var duplicateCounts: [WorkSource: Int] = [:]

        for task in tasks {
            let keys = task.deduplicationKeys
            if keys.contains(where: seenKeys.contains) {
                duplicateCounts[task.source, default: 0] += 1
                continue
            }

            uniqueTasks.append(task)
            seenKeys.formUnion(keys)
        }

        return TaskDeduplicationResult(tasks: uniqueTasks, duplicateCounts: duplicateCounts)
    }
}

struct TaskDedupStore {
    private let fileURL: URL
    private let maxRecordCount = 2_000

    init(fileURL: URL = TaskDedupStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        IntegrationConfiguration.directoryURL.appendingPathComponent("dedup-cache.json")
    }

    func recordSeenTasks(_ tasks: [AssistantTask], syncedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var records = try loadRecords()
        for task in tasks {
            for key in task.deduplicationKeys {
                if var record = records[key] {
                    record.lastSeenAt = syncedAt
                    record.seenCount += 1
                    record.title = task.title
                    records[key] = record
                } else {
                    records[key] = TaskDedupRecord(
                        key: key,
                        source: task.source,
                        title: task.title,
                        firstSeenAt: syncedAt,
                        lastSeenAt: syncedAt,
                        seenCount: 1
                    )
                }
            }
        }

        let trimmedRecords = Dictionary(
            uniqueKeysWithValues: records.values
                .sorted { $0.lastSeenAt > $1.lastSeenAt }
                .prefix(maxRecordCount)
                .map { ($0.key, $0) }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(trimmedRecords)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func loadRecords() throws -> [String: TaskDedupRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: TaskDedupRecord].self, from: data)
    }
}

private struct TaskDedupRecord: Codable {
    var key: String
    var source: WorkSource
    var title: String
    var firstSeenAt: Date
    var lastSeenAt: Date
    var seenCount: Int
}

extension AssistantTask {
    var deduplicationKeys: Set<String> {
        var keys: Set<String> = [
            "review:\(reviewKey.dedupNormalized)"
        ]

        if let stableLink = stableMetadataValue?.dedupNormalized, !stableLink.isEmpty {
            keys.insert("link:\(stableLink)")
        }

        let content = [source.rawValue, title, context]
            .joined(separator: "\n")
            .dedupNormalized
        if content.count >= 12 {
            keys.insert("content:\(content.fnv1a64Hex)")
        }

        return keys
    }

    private var stableMetadataValue: String? {
        metadata.first {
            ["링크", "URL", "MR", "PR", "Issue", "이슈", "파일", "메모"].contains($0.label)
        }?.value
    }
}

private extension String {
    var dedupNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var fnv1a64Hex: String {
        let offset: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        let hash = utf8.reduce(offset) { partialResult, byte in
            (partialResult ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", hash)
    }
}
