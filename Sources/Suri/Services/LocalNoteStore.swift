import Foundation

struct LocalNoteStore {
    private let fileURL: URL

    init(fileURL: URL = LocalNoteStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        IntegrationConfiguration.directoryURL.appendingPathComponent("app-notes.json")
    }

    func load() throws -> [AssistantNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AssistantNote].self, from: data)
    }

    func save(_ notes: [AssistantNote]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(notes.sortedByCapturedDateDescending())
        try data.write(to: fileURL, options: [.atomic])
    }
}
