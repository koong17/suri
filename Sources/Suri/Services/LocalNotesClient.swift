import Foundation

struct LocalNotesClient: WorkItemProvider {
    let configuration: DirectoryIntegrationConfiguration

    var source: WorkSource { .notes }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let files = try Self.noteFiles(in: configuration.directoryURL)
        let notes = try files.prefix(50).map(Self.note(from:))
        let tasks = notes
            .filter { TaskExtractor.requiresReview(from: "\($0.title)\n\($0.body)") || TaskExtractor.inferredDueDate(from: "\($0.title)\n\($0.body)") != nil }
            .map { note in
                AssistantTask(
                    title: note.title,
                    source: .notes,
                    dueDate: TaskExtractor.inferredDueDate(from: "\(note.title)\n\(note.body)", fallbackHours: 72),
                    priority: TaskExtractor.priority(from: note.body, default: .normal),
                    status: .waiting,
                    context: note.body,
                    owner: "나",
                    requiresUserReview: TaskExtractor.requiresReview(from: note.body),
                    recommendedAction: "메모 내용을 실제 일정 또는 후속 작업으로 정리",
                    metadata: [
                        MetadataItem(label: "메모", value: note.title)
                    ]
                )
            }

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .notes,
                isConnected: true,
                unreadCount: notes.count,
                lastActivity: .now,
                summary: "로컬 메모 폴더에서 일정 후보를 추출했습니다."
            ),
            notes: Array(notes)
        )
    }

    private static func noteFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
            .sortedByModificationDateDescending()
    }

    private static func note(from url: URL) throws -> AssistantNote {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let firstLine = lines.first?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstLine?.nilIfEmpty ?? url.deletingPathExtension().lastPathComponent
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date ?? .now

        return AssistantNote(
            title: title,
            body: body.nilIfEmpty ?? content,
            capturedAt: modifiedAt,
            linkedTaskID: nil
        )
    }
}
