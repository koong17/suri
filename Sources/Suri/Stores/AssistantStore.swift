import Foundation
import Observation

@MainActor
@Observable
final class AssistantStore {
    @ObservationIgnored private let reviewedTaskKeysStorageKey = "assistant.reviewedTaskKeys"
    @ObservationIgnored private let syncService: AssistantSyncService
    @ObservationIgnored private let notificationScheduler: NotificationScheduler
    @ObservationIgnored private let cacheStore: AssistantCacheStore

    var tasks: [AssistantTask]
    var sources: [SourceConnection]
    var notes: [AssistantNote]
    var lastSyncedAt: Date
    var isSyncing = false
    var lastSyncError: String?
    var isUsingFallbackData = false
    var hasCachedSnapshot = false

    init(
        tasks: [AssistantTask],
        sources: [SourceConnection],
        notes: [AssistantNote],
        lastSyncedAt: Date = .now
    ) {
        self.tasks = tasks
        self.sources = sources
        self.notes = notes
        self.lastSyncedAt = lastSyncedAt
        self.syncService = AssistantSyncService()
        self.notificationScheduler = NotificationScheduler()
        self.cacheStore = AssistantCacheStore()
    }

    func sidebarSummaries(dueSoonHours: Double) -> [SidebarSummary] {
        [
            SidebarSummary(item: .today, detail: "\(todayTasks.count)개 일정"),
            SidebarSummary(item: .inbox, detail: "\(openReviewTaskCount)개 확인 필요"),
            SidebarSummary(item: .importantSlack, detail: "\(importantSlackTasks.count)개 중요"),
            SidebarSummary(item: .deadlines, detail: "\(openDueSoonTaskCount(within: dueSoonHours))개 임박"),
            SidebarSummary(item: .followUps, detail: "\(followUpTasks.count)개 후속 조치"),
            SidebarSummary(item: .sources, detail: "\(connectedSourceCount)/\(sources.count) 연결됨"),
            SidebarSummary(item: .notes, detail: "\(notes.count)개 메모")
        ]
    }

    func tasks(for section: SidebarItem, dueSoonHours: Double) -> [AssistantTask] {
        switch section {
        case .today:
            todayTasks
        case .inbox:
            reviewTasks
        case .importantSlack:
            importantSlackTasks
        case .deadlines:
            dueSoonTasks(within: dueSoonHours)
        case .followUps:
            followUpTasks
        case .sources:
            tasks
        case .notes:
            tasks.filter { $0.source == .notes }
        }
    }

    func syncSources() {
        lastSyncedAt = .now
        for index in sources.indices {
            sources[index].lastActivity = .now
        }
    }

    func loadCachedSnapshot() {
        do {
            guard let cachedResult = try cacheStore.load() else {
                return
            }

            apply(cachedResult)
            hasCachedSnapshot = true
            lastSyncError = cachedResult.providerErrors.isEmpty ? nil : cachedResult.providerErrors.joined(separator: "\n")
        } catch {
            lastSyncError = "캐시 로드 실패: \(error.localizedDescription)"
        }
    }

    func syncSources(
        preferences: SyncPreferences,
        force: Bool = false,
        minimumInterval: TimeInterval = 0
    ) async {
        guard !isSyncing else {
            return
        }

        if !force,
           hasCachedSnapshot,
           Date.now.timeIntervalSince(lastSyncedAt) < minimumInterval {
            return
        }

        isSyncing = true
        lastSyncError = nil

        let result = await syncService.sync(preferences: preferences)
        apply(result)
        lastSyncError = result.providerErrors.isEmpty ? nil : result.providerErrors.joined(separator: "\n")
        saveCacheIfUseful(result)

        do {
            try await notificationScheduler.scheduleNotifications(for: tasks, preferences: preferences)
        } catch {
            lastSyncError = [lastSyncError, "알림: \(error.localizedDescription)"]
                .compactMap { $0 }
                .joined(separator: "\n")
        }

        isSyncing = false
    }

    func refreshNotifications(preferences: SyncPreferences) async {
        do {
            try await notificationScheduler.scheduleNotifications(for: tasks, preferences: preferences)
        } catch {
            lastSyncError = "알림: \(error.localizedDescription)"
        }
    }

    func createReminder() {
        let reminder = AssistantTask(
            title: "새 확인 항목 정리",
            source: .notes,
            dueDate: Calendar.current.date(byAdding: .hour, value: 4, to: .now),
            priority: .normal,
            status: .open,
            context: "빠르게 기록한 항목입니다. 상세 내용과 연결 소스를 보강하세요.",
            owner: "나",
            requiresUserReview: true,
            recommendedAction: "내용을 정리하고 실제 일정 또는 후속 작업으로 분류",
            metadata: [
                MetadataItem(label: "입력", value: "수동"),
                MetadataItem(label: "상태", value: "초안")
            ]
        )
        tasks.insert(reminder, at: 0)
    }

    func markReviewed(_ id: AssistantTask.ID?) {
        guard let id, let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        tasks[index].requiresUserReview = false
        tasks[index].status = .reviewed
        rememberReviewedTask(tasks[index])
    }

    func dueSoonTasks(within hours: Double) -> [AssistantTask] {
        let endDate = Date.now.addingTimeInterval(hours * 60 * 60)
        return tasks
            .filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate <= endDate
            }
            .sortedForAssistant()
    }

    private var todayTasks: [AssistantTask] {
        tasks
            .filter { task in
                guard let dueDate = task.dueDate else { return task.requiresUserReview }
                return Calendar.current.isDateInToday(dueDate) || task.requiresUserReview || task.status == .reviewed
            }
            .sortedForAssistant()
    }

    private var reviewTasks: [AssistantTask] {
        tasks
            .filter { $0.requiresUserReview || $0.status == .reviewed }
            .sortedForAssistant()
    }

    private var importantSlackTasks: [AssistantTask] {
        tasks
            .filter(\.isImportantSlack)
            .sortedForAssistant()
    }

    private var followUpTasks: [AssistantTask] {
        tasks
            .filter { $0.status == .waiting || $0.recommendedAction.contains("후속") }
            .sortedForAssistant()
    }

    private var connectedSourceCount: Int {
        sources.filter(\.isConnected).count
    }

    private var openReviewTaskCount: Int {
        tasks.filter(\.requiresUserReview).count
    }

    private func openDueSoonTaskCount(within hours: Double) -> Int {
        let endDate = Date.now.addingTimeInterval(hours * 60 * 60)
        return tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate <= endDate && task.status != .reviewed
        }.count
    }

    private func applyingReviewedState(to tasks: [AssistantTask]) -> [AssistantTask] {
        let reviewedKeys = Set(UserDefaults.standard.stringArray(forKey: reviewedTaskKeysStorageKey) ?? [])
        return tasks.map { task in
            guard reviewedKeys.contains(task.reviewKey) else {
                return task
            }

            var reviewedTask = task
            reviewedTask.requiresUserReview = false
            reviewedTask.status = .reviewed
            return reviewedTask
        }
    }

    private func rememberReviewedTask(_ task: AssistantTask) {
        var reviewedKeys = Set(UserDefaults.standard.stringArray(forKey: reviewedTaskKeysStorageKey) ?? [])
        reviewedKeys.insert(task.reviewKey)
        UserDefaults.standard.set(Array(reviewedKeys), forKey: reviewedTaskKeysStorageKey)
    }

    private func apply(_ result: AssistantSyncResult) {
        tasks = applyingReviewedState(to: result.tasks)
        sources = result.sources
        notes = result.notes
        lastSyncedAt = result.syncedAt
        isUsingFallbackData = result.usedFallback
    }

    private func saveCacheIfUseful(_ result: AssistantSyncResult) {
        guard !result.usedFallback,
              result.sources.contains(where: \.isConnected) else {
            return
        }

        do {
            try cacheStore.save(result)
            hasCachedSnapshot = true
        } catch {
            lastSyncError = [lastSyncError, "캐시 저장 실패: \(error.localizedDescription)"]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
    }
}

extension AssistantStore {
    static let empty = AssistantStore(
        tasks: [],
        sources: WorkSource.allCases.map { source in
            SourceConnection(
                source: source,
                isConnected: false,
                unreadCount: 0,
                lastActivity: .now,
                summary: "아직 동기화하지 않았습니다."
            )
        },
        notes: []
    )

    static let preview = AssistantStore(
        tasks: [
            AssistantTask(
                title: "배포 일정 변경 여부 확인",
                source: .slack,
                dueDate: Date.hoursFromNow(2),
                priority: .high,
                status: .open,
                context: "#release 채널에서 오늘 배포 창구가 30분 밀릴 수 있다는 논의가 있었습니다.",
                owner: "나",
                requiresUserReview: true,
                recommendedAction: "배포 담당자에게 최종 시간 확인 후 캘린더 업데이트",
                metadata: [
                    MetadataItem(label: "채널", value: "#release"),
                    MetadataItem(label: "관련자", value: "플랫폼팀")
                ]
            ),
            AssistantTask(
                title: "계약서 회신 기한",
                source: .email,
                dueDate: Date.hoursFromNow(7),
                priority: .urgent,
                status: .open,
                context: "법무팀에서 오늘 중 확인이 필요하다는 메일을 보냈습니다.",
                owner: "나",
                requiresUserReview: true,
                recommendedAction: "첨부 문서 검토 후 승인 또는 수정 요청 회신",
                metadata: [
                    MetadataItem(label: "보낸 사람", value: "legal@company.test"),
                    MetadataItem(label: "스레드", value: "MSA 갱신")
                ]
            ),
            AssistantTask(
                title: "MR !482 리뷰",
                source: .gitLab,
                dueDate: Date.hoursFromNow(23),
                priority: .high,
                status: .waiting,
                context: "내 리뷰를 기다리는 GitLab merge request입니다. 일정 서비스 변경을 포함합니다.",
                owner: "나",
                requiresUserReview: false,
                recommendedAction: "변경 범위를 확인하고 리뷰 코멘트 남기기",
                metadata: [
                    MetadataItem(label: "프로젝트", value: "tms/scheduler"),
                    MetadataItem(label: "작성자", value: "minji")
                ]
            ),
            AssistantTask(
                title: "TMS-219 QA 확인",
                source: .jira,
                dueDate: Date.hoursFromNow(30),
                priority: .normal,
                status: .scheduled,
                context: "QA가 완료되었고 최종 승인자가 나로 지정되어 있습니다.",
                owner: "나",
                requiresUserReview: true,
                recommendedAction: "테스트 결과와 남은 blocker 확인",
                metadata: [
                    MetadataItem(label: "이슈", value: "TMS-219"),
                    MetadataItem(label: "스프린트", value: "2026-W23")
                ]
            ),
            AssistantTask(
                title: "1:1 메모 후속 일정 잡기",
                source: .notes,
                dueDate: Date.hoursFromNow(72),
                priority: .normal,
                status: .waiting,
                context: "지난 1:1 메모에서 다음 주 설계 리뷰 시간을 잡기로 했습니다.",
                owner: "나",
                requiresUserReview: false,
                recommendedAction: "후속 미팅 일정 후보 2개 제안",
                metadata: [
                    MetadataItem(label: "메모", value: "1:1 / 설계 리뷰"),
                    MetadataItem(label: "참석자", value: "backend leads")
                ]
            )
        ],
        sources: [
            SourceConnection(
                source: .slack,
                isConnected: true,
                unreadCount: 12,
                lastActivity: Date.hoursFromNow(-1),
                summary: "멘션과 릴리즈 채널을 우선 감시합니다."
            ),
            SourceConnection(
                source: .email,
                isConnected: true,
                unreadCount: 5,
                lastActivity: Date.hoursFromNow(-2),
                summary: "기한, 승인, 첨부 문서를 일정 후보로 추출합니다."
            ),
            SourceConnection(
                source: .gitLab,
                isConnected: true,
                unreadCount: 3,
                lastActivity: Date.hoursFromNow(-4),
                summary: "내 리뷰, 실패한 파이프라인, 머지 대기를 추적합니다."
            ),
            SourceConnection(
                source: .jira,
                isConnected: true,
                unreadCount: 7,
                lastActivity: Date.hoursFromNow(-6),
                summary: "담당 이슈와 승인 요청을 가져옵니다."
            ),
            SourceConnection(
                source: .notes,
                isConnected: true,
                unreadCount: 2,
                lastActivity: Date.hoursFromNow(-18),
                summary: "내가 적은 메모에서 약속과 후속 작업을 찾습니다."
            )
        ],
        notes: [
            AssistantNote(
                title: "설계 리뷰 준비",
                body: "다음 주 초까지 API 변경안 공유. 백엔드 리드와 30분 리뷰 필요.",
                capturedAt: Date.hoursFromNow(-18),
                linkedTaskID: nil
            ),
            AssistantNote(
                title: "채용 면접 회고",
                body: "금요일 오전까지 피드백 제출. 역량 평가 근거 보강 필요.",
                capturedAt: Date.hoursFromNow(-36),
                linkedTaskID: nil
            )
        ],
        lastSyncedAt: Date.hoursFromNow(-1)
    )
}
