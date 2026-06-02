import SwiftUI

struct InspectorView: View {
    let section: SidebarItem
    let selectedTask: AssistantTask?
    let sources: [SourceConnection]
    let notes: [AssistantNote]
    let lastSyncedAt: Date
    let dueSoonHours: Double
    let onMarkReviewed: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedTask {
                    SelectedTaskInspector(task: selectedTask, onMarkReviewed: onMarkReviewed)
                } else {
                    SectionInspector(section: section, dueSoonHours: dueSoonHours)
                }

                SourceHealthInspector(sources: sources, lastSyncedAt: lastSyncedAt)

                NotesInspector(notes: notes)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SelectedTaskInspector: View {
    let task: AssistantTask
    let onMarkReviewed: () -> Void

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(task.source.title, systemImage: task.source.systemImage)
                    .foregroundStyle(task.source.accent)

                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(task.context)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                MetadataRow(label: "기한", value: AssistantFormatters.dueText(for: task.dueDate))
                MetadataRow(label: "우선순위", value: task.priority.title)
                MetadataRow(label: "상태", value: task.status.title)
                MetadataRow(label: "담당", value: task.owner)

                ForEach(task.metadata) { item in
                    if item.label == "URL" || item.label == "링크",
                       let url = URL(string: item.value) {
                        HStack(alignment: .top) {
                            Text(item.label)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Link("열기", destination: url)
                                .lineLimit(1)
                        }
                        .font(.callout)
                    } else {
                        MetadataRow(label: item.label, value: item.value)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("추천 행동")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(task.recommendedAction)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onMarkReviewed) {
                    Label("확인 완료로 표시", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!task.requiresUserReview)
            }
        }
    }
}

private struct SectionInspector: View {
    let section: SidebarItem
    let dueSoonHours: Double

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(section.title, systemImage: section.systemImage)
                    .font(.headline)

                Text(sectionDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                MetadataRow(label: "임박 기준", value: "\(Int(dueSoonHours))시간")
            }
        }
    }

    private var sectionDescription: String {
        switch section {
        case .today:
            "오늘 집중해야 할 일정과 결정을 보여줍니다."
        case .inbox:
            "내 판단이 필요한 메시지, 메일, 이슈를 모읍니다."
        case .importantSlack:
            "최근 Slack 멘션 중 우선 처리해야 할 가능성이 높은 항목입니다."
        case .deadlines:
            "설정된 시간 안에 마감되는 항목을 강조합니다."
        case .followUps:
            "내가 약속했거나 다시 확인해야 하는 후속 작업입니다."
        case .sources:
            "연결 상태와 새 항목 수를 확인합니다."
        case .notes:
            "메모에서 감지한 일정 후보를 검토합니다."
        }
    }
}

private struct SourceHealthInspector: View {
    let sources: [SourceConnection]
    let lastSyncedAt: Date

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("소스 상태")
                    .font(.headline)

                MetadataRow(
                    label: "마지막 동기화",
                    value: AssistantFormatters.relative.localizedString(for: lastSyncedAt, relativeTo: .now)
                )

                ForEach(sources) { connection in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(connection.source.title, systemImage: connection.source.systemImage)
                                .foregroundStyle(connection.source.accent)
                            Spacer()
                            Label(connection.health.title, systemImage: connection.health.systemImage)
                                .foregroundStyle(connection.health.tint)
                        }

                        HStack {
                            Text("\(connection.unreadCount)개 항목")
                                .monospacedDigit()
                            if connection.duplicateCount > 0 {
                                Text("중복 \(connection.duplicateCount)개 정리")
                            }
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let errorMessage = connection.errorMessage?.nilIfEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }
}

private struct NotesInspector: View {
    let notes: [AssistantNote]

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 메모")
                    .font(.headline)

                ForEach(notes.prefix(2)) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.callout.weight(.medium))
                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct InspectorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
