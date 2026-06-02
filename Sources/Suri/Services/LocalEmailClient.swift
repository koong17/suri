import Foundation

struct LocalEmailClient: WorkItemProvider {
    let configuration: DirectoryIntegrationConfiguration

    var source: WorkSource { .email }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let files = try Self.messageFiles(in: configuration.directoryURL)
        let tasks = try files.prefix(30).map(Self.task(from:))

        return ProviderSnapshot(
            tasks: tasks,
            connection: SourceConnection(
                source: .email,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "로컬 이메일 내보내기 폴더에서 확인 항목을 읽었습니다."
            )
        )
    }

    private static func messageFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { ["eml", "txt"].contains($0.pathExtension.lowercased()) }
            .sortedByModificationDateDescending()
    }

    private static func task(from url: URL) throws -> AssistantTask {
        let content = try String(contentsOf: url, encoding: .utf8)
        let subject = header("Subject", in: content) ?? url.deletingPathExtension().lastPathComponent
        let from = header("From", in: content) ?? "Email"
        let body = bodyText(from: content)

        return AssistantTask(
            title: subject,
            source: .email,
            dueDate: TaskExtractor.inferredDueDate(from: content, fallbackHours: 24),
            priority: TaskExtractor.priority(from: content, default: .normal),
            status: .open,
            context: body.nilIfEmpty ?? subject,
            owner: from,
            requiresUserReview: TaskExtractor.requiresReview(from: content),
            recommendedAction: "메일 본문을 확인하고 회신, 승인, 일정 등록 여부를 결정",
            metadata: [
                MetadataItem(label: "파일", value: url.lastPathComponent),
                MetadataItem(label: "보낸 사람", value: from)
            ]
        )
    }

    private static func header(_ name: String, in content: String) -> String? {
        content
            .components(separatedBy: .newlines)
            .first { $0.lowercased().hasPrefix("\(name.lowercased()):") }?
            .dropFirst(name.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func bodyText(from content: String) -> String {
        if let range = content.range(of: "\n\n") {
            return String(content[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
