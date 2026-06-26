import Foundation
import Testing
@testable import Suri

struct LocalNotesClientTests {
    @Test
    func includesAppCreatedNotesWhenNotesFolderIsEmpty() async throws {
        let directory = try temporaryDirectory()
        let notesDirectory = directory.appendingPathComponent("Notes", isDirectory: true)
        let store = LocalNoteStore(fileURL: directory.appendingPathComponent("app-notes.json"))
        let note = AssistantNote(
            title: "검토 요청",
            body: "내일까지 확인 부탁합니다.",
            capturedAt: Date(timeIntervalSince1970: 1_000),
            linkedTaskID: nil
        )
        try store.save([note])

        let client = LocalNotesClient(
            configuration: DirectoryIntegrationConfiguration(enabled: true, directory: notesDirectory.path),
            localNoteStore: store
        )

        let snapshot = try await client.fetchSnapshot()

        #expect(snapshot.notes == [note])
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.connection.unreadCount == 1)
        #expect(snapshot.connection.summary.contains("앱 내부 메모"))
    }

    @Test
    func combinesFolderNotesAndAppCreatedNotes() async throws {
        let directory = try temporaryDirectory()
        let notesDirectory = directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try """
        # 회의 후속
        오늘 논의한 결정사항 확인 부탁합니다.
        """.write(to: notesDirectory.appendingPathComponent("meeting.md"), atomically: true, encoding: .utf8)

        let store = LocalNoteStore(fileURL: directory.appendingPathComponent("app-notes.json"))
        try store.save([
            AssistantNote(
                title: "앱 메모",
                body: "다음 주까지 정리 필요",
                capturedAt: Date(timeIntervalSince1970: 2_000),
                linkedTaskID: nil
            )
        ])

        let client = LocalNotesClient(
            configuration: DirectoryIntegrationConfiguration(enabled: true, directory: notesDirectory.path),
            localNoteStore: store
        )

        let snapshot = try await client.fetchSnapshot()

        #expect(snapshot.notes.count == 2)
        #expect(snapshot.connection.unreadCount == 2)
        #expect(snapshot.connection.summary.contains("로컬 메모 폴더"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suri-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
