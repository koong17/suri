import SwiftUI

struct DetailView: View {
    let section: SidebarItem
    let tasks: [AssistantTask]
    let sources: [SourceConnection]
    let notes: [AssistantNote]
    let lastSyncedAt: Date
    let dueSoonHours: Double
    let isSyncing: Bool
    let lastSyncError: String?
    let isUsingFallbackData: Bool
    @Binding var selectedTaskID: AssistantTask.ID?
    let onSync: () -> Void
    let onCreateReminder: () -> Void
    let onMarkReviewed: () -> Void
    @Binding var showInspector: Bool

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                section: section,
                itemCount: tasks.count,
                lastSyncedAt: lastSyncedAt,
                dueSoonHours: dueSoonHours,
                isSyncing: isSyncing,
                lastSyncError: lastSyncError,
                isUsingFallbackData: isUsingFallbackData
            )

            Divider()

            if section == .sources {
                SourcesDetailView(
                    sources: sources,
                    tasks: tasks,
                    selectedTaskID: $selectedTaskID
                )
            } else if section == .notes {
                NotesDetailView(notes: notes, tasks: tasks, selectedTaskID: $selectedTaskID)
            } else {
                TaskListView(tasks: tasks, selectedTaskID: $selectedTaskID)
            }
        }
        .navigationTitle(section.title)
        .toolbar {
            ToolbarItemGroup {
                Button(action: onSync) {
                    Label(isSyncing ? "동기화 중" : "동기화", systemImage: "arrow.clockwise")
                }
                .disabled(isSyncing)
                .help("Slack, Email, GitLab, GitHub, Jira, Notes를 다시 확인")

                Button(action: onCreateReminder) {
                    Label("확인 항목 추가", systemImage: "plus")
                }
                .help("빠른 확인 항목 추가")

                Button(action: onMarkReviewed) {
                    Label("확인 완료", systemImage: "checkmark.circle")
                }
                .disabled(selectedTaskID == nil)
                .help("선택한 항목을 확인 완료로 표시")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("인스펙터 보기")
            }

            ToolbarItem {
                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
                .help("Suri 설정 열기")
            }
        }
    }
}

private struct DetailHeader: View {
    let section: SidebarItem
    let itemCount: Int
    let lastSyncedAt: Date
    let dueSoonHours: Double
    let isSyncing: Bool
    let lastSyncError: String?
    let isUsingFallbackData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.title2.weight(.semibold))

                    Text(summaryText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(itemCount)")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("표시 항목")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                DetailMetricCard(
                    title: "마지막 동기화",
                    value: isSyncing ? "진행 중" : AssistantFormatters.relative.localizedString(for: lastSyncedAt, relativeTo: .now),
                    systemImage: "arrow.clockwise"
                )

                DetailMetricCard(
                    title: "임박 기준",
                    value: "\(Int(dueSoonHours))시간",
                    systemImage: "timer"
                )

                DetailMetricCard(
                    title: "알림 상태",
                    value: itemCount > 0 ? "확인 필요" : "정상",
                    systemImage: itemCount > 0 ? "bell.badge" : "bell"
                )
            }

            if isUsingFallbackData {
                StatusBanner(
                    title: "연동 데이터 없음",
                    message: "연동 설정이 없거나 활성화된 클라이언트가 없어 실제 항목을 표시하지 못했습니다.",
                    systemImage: "info.circle"
                )
            }

            if let lastSyncError {
                StatusBanner(
                    title: "동기화 확인 필요",
                    message: lastSyncError,
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .padding()
    }

    private var summaryText: String {
        switch section {
        case .today:
            "오늘 처리해야 할 일정, 확인 요청, 대기 중인 결정을 한곳에 모았습니다."
        case .inbox:
            "Suri가 판단을 요청하는 Slack, Email, GitLab, GitHub, Jira, Notes 항목입니다."
        case .importantSlack:
            "최근 Slack 멘션 중 답변, 승인, 마감, 장애, 배포처럼 우선 확인해야 할 항목입니다."
        case .deadlines:
            "설정된 임박 기준 안에 들어온 마감과 승인 요청입니다."
        case .followUps:
            "내가 다음 행동을 해야 하거나 상대 응답을 기다리는 항목입니다."
        case .sources:
            "연결된 업무 소스와 최근 활동 상태입니다."
        case .notes:
            "내 메모에서 추출한 일정 후보와 후속 작업입니다."
        }
    }
}

private struct StatusBanner: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TaskListView: View {
    let tasks: [AssistantTask]
    @Binding var selectedTaskID: AssistantTask.ID?

    var body: some View {
        List(selection: $selectedTaskID) {
            ForEach(tasks) { task in
                TaskRow(task: task)
                    .tag(task.id as AssistantTask.ID?)
            }
        }
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "표시할 항목 없음",
                    systemImage: "checkmark.seal",
                    description: Text("현재 선택한 분류에 남은 확인 항목이 없습니다.")
                )
            }
        }
    }
}

private struct TaskRow: View {
    let task: AssistantTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(task.source.title, systemImage: task.source.systemImage)
                    .font(.caption)
                    .foregroundStyle(task.source.accent)

                Spacer()

                Text(task.priority.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(priorityStyle)
            }

            Text(task.title)
                .font(.headline)
                .lineLimit(2)
                .strikethrough(task.status == .reviewed)
                .foregroundStyle(task.status == .reviewed ? .secondary : .primary)

            Text(task.context)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Label(AssistantFormatters.dueText(for: task.dueDate), systemImage: "calendar")
                Label(task.status.title, systemImage: task.status.systemImage)
                if task.requiresUserReview {
                    Label("확인 필요", systemImage: "exclamationmark.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var priorityStyle: AnyShapeStyle {
        switch task.priority {
        case .low, .normal:
            AnyShapeStyle(.secondary)
        case .high:
            AnyShapeStyle(.orange)
        case .urgent:
            AnyShapeStyle(.red)
        }
    }
}

private struct SourcesDetailView: View {
    let sources: [SourceConnection]
    let tasks: [AssistantTask]
    @Binding var selectedTaskID: AssistantTask.ID?

    var body: some View {
        List(selection: $selectedTaskID) {
            ForEach(sources) { connection in
                Section {
                    sourceStatusRow(connection)

                    let sourceTasks = tasks.filter { $0.source == connection.source }
                    if sourceTasks.isEmpty {
                        Text("표시할 항목 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sourceTasks) { task in
                            TaskRow(task: task)
                                .tag(task.id as AssistantTask.ID?)
                        }
                    }
                } header: {
                    Label(connection.source.title, systemImage: connection.source.systemImage)
                }
            }
        }
    }

    private func sourceStatusRow(_ connection: SourceConnection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: connection.source.systemImage)
                .foregroundStyle(connection.source.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(connection.source.title)
                    .font(.headline)
                Text(connection.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Label(connection.health.title, systemImage: connection.health.systemImage)
                    .foregroundStyle(connection.health.tint)
                Text("\(connection.unreadCount)개 새 항목")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if connection.duplicateCount > 0 {
                    Text("중복 \(connection.duplicateCount)개 정리")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct NotesDetailView: View {
    let notes: [AssistantNote]
    let tasks: [AssistantTask]
    @Binding var selectedTaskID: AssistantTask.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedTaskID) {
                Section("메모에서 추출한 작업") {
                    ForEach(tasks) { task in
                        TaskRow(task: task)
                            .tag(task.id as AssistantTask.ID?)
                    }
                }

                Section("최근 메모") {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title)
                                .font(.headline)
                            Text(note.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(AssistantFormatters.relative.localizedString(for: note.capturedAt, relativeTo: .now))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
}
