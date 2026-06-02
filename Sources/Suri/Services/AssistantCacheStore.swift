import Foundation

struct AssistantCacheStore {
    static var fileURL: URL {
        IntegrationConfiguration.directoryURL.appendingPathComponent("sync-cache.json")
    }

    func load() throws -> AssistantSyncResult? {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: Self.fileURL)
        return try Self.decoder.decode(AssistantSyncResult.self, from: data)
    }

    func save(_ result: AssistantSyncResult) throws {
        try FileManager.default.createDirectory(
            at: IntegrationConfiguration.directoryURL,
            withIntermediateDirectories: true
        )

        let data = try Self.encoder.encode(result)
        try data.write(to: Self.fileURL, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
