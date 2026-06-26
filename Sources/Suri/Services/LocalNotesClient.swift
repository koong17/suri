import Foundation

struct LocalNotesClient: WorkItemProvider {
    let configuration: DirectoryIntegrationConfiguration
    private let localNoteStore: LocalNoteStore

    init(configuration: DirectoryIntegrationConfiguration, localNoteStore: LocalNoteStore = LocalNoteStore()) {
        self.configuration = configuration
        self.localNoteStore = localNoteStore
    }

    var source: WorkSource { .notes }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let folderNotes = try Self.noteFiles(in: configuration.directoryURL)
            .prefix(50)
            .map(Self.note(from:))
        let appNotes = try localNoteStore.load()
        let notes = Self.mergedNotes(appNotes + folderNotes)
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
                lastActivity: notes.first?.capturedAt ?? .now,
                summary: Self.summary(appNoteCount: appNotes.count, folderNoteCount: folderNotes.count)
            ),
            notes: notes
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

    private static func mergedNotes(_ notes: [AssistantNote]) -> [AssistantNote] {
        var seen = Set<AssistantNote.ID>()
        return notes
            .filter { note in
                seen.insert(note.id).inserted
            }
            .sortedByCapturedDateDescending()
    }

    private static func summary(appNoteCount: Int, folderNoteCount: Int) -> String {
        switch (appNoteCount, folderNoteCount) {
        case (0, 0):
            "앱 메모와 로컬 메모 폴더에 아직 메모가 없습니다."
        case (0, _):
            "로컬 메모 폴더에서 일정 후보를 추출했습니다."
        case (_, 0):
            "앱 내부 메모에서 일정 후보를 추출했습니다."
        default:
            "앱 내부 메모와 로컬 메모 폴더에서 일정 후보를 추출했습니다."
        }
    }
}
