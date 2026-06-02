import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AssistantStore.empty
    @State private var didRunInitialSync = false
    @SceneStorage("assistant.selectedSidebarItem") private var selectedSidebarItemRaw = SidebarItem.today.rawValue
    @SceneStorage("assistant.selectedTaskID") private var selectedTaskIDRaw = ""
    @SceneStorage("assistant.showInspector") private var showInspector = true
    @SceneStorage("assistant.searchText") private var searchText = ""
    @AppStorage(PreferenceKeys.dueSoonHours) private var dueSoonHours = 24.0
    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.notificationLeadTimeRaw) private var notificationLeadTimeRaw = NotificationLeadTime.oneDay.rawValue
    @AppStorage(PreferenceKeys.autoSyncEnabled) private var autoSyncEnabled = true
    @AppStorage(PreferenceKeys.syncIntervalMinutes) private var syncIntervalMinutes = 5.0
    @AppStorage(PreferenceKeys.slackEnabled) private var slackEnabled = true
    @AppStorage(PreferenceKeys.emailEnabled) private var emailEnabled = true
    @AppStorage(PreferenceKeys.gitLabEnabled) private var gitLabEnabled = true
    @AppStorage(PreferenceKeys.githubEnabled) private var githubEnabled = true
    @AppStorage(PreferenceKeys.jiraEnabled) private var jiraEnabled = true
    @AppStorage(PreferenceKeys.notesEnabled) private var notesEnabled = true

    private var selectedSidebarItem: SidebarItem {
        SidebarItem(rawValue: selectedSidebarItemRaw) ?? .today
    }

    private var selectedTaskID: AssistantTask.ID? {
        UUID(uuidString: selectedTaskIDRaw)
    }

    private var selectedTask: AssistantTask? {
        guard let selectedTaskID else { return nil }
        return store.tasks.first { $0.id == selectedTaskID }
    }

    private var filteredTasks: [AssistantTask] {
        let sectionTasks = store.tasks(for: selectedSidebarItem, dueSoonHours: dueSoonHours)
        guard !searchText.isEmpty else {
            return sectionTasks
        }

        return sectionTasks.filter { task in
            task.title.localizedCaseInsensitiveContains(searchText)
                || task.context.localizedCaseInsensitiveContains(searchText)
                || task.source.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: sidebarSelection,
                summaries: store.sidebarSummaries(dueSoonHours: dueSoonHours)
            )
            .navigationTitle("Suri")
        } detail: {
            DetailView(
                section: selectedSidebarItem,
                tasks: filteredTasks,
                sources: store.sources,
                notes: store.notes,
                editableNoteIDs: store.editableNoteIDs,
                lastSyncedAt: store.lastSyncedAt,
                dueSoonHours: dueSoonHours,
                isSyncing: store.isSyncing,
                lastSyncError: store.lastSyncError,
                isUsingFallbackData: store.isUsingFallbackData,
                selectedTaskID: selectedTaskBinding,
                onSync: syncNow,
                onCreateReminder: store.createReminder,
                onCreateNote: { title, body in store.createNote(title: title, body: body) },
                onUpdateNote: store.updateNote,
                onDeleteNote: store.deleteNote,
                onMarkReviewed: { store.markReviewed(selectedTaskID) },
                showInspector: $showInspector
            )
            .inspector(isPresented: $showInspector) {
                InspectorView(
                    section: selectedSidebarItem,
                    selectedTask: selectedTask,
                    sources: store.sources,
                    notes: store.notes,
                    lastSyncedAt: store.lastSyncedAt,
                    dueSoonHours: dueSoonHours,
                    onMarkReviewed: { store.markReviewed(selectedTaskID) }
                )
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "검색")
        .navigationSplitViewStyle(.prominentDetail)
        .background(WindowSizeBridge(minimumSize: CGSize(width: 1_180, height: 680)))
        .focusedValue(\.assistantCommandHandlers, commandHandlers)
        .task {
            guard !didRunInitialSync else {
                return
            }

            didRunInitialSync = true
            store.loadCachedSnapshot()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, autoSyncEnabled else {
                return
            }

            await syncOnActivation()
            await runPeriodicSyncLoop()
        }
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding {
            selectedSidebarItem
        } set: { newValue in
            selectedSidebarItemRaw = (newValue ?? .today).rawValue
            selectedTaskIDRaw = ""
        }
    }

    private var selectedTaskBinding: Binding<AssistantTask.ID?> {
        Binding {
            selectedTaskID
        } set: { newValue in
            selectedTaskIDRaw = newValue?.uuidString ?? ""
        }
    }

    private var commandHandlers: AssistantCommandHandlers {
        AssistantCommandHandlers(
            syncSources: syncNow,
            createReminder: store.createReminder,
            markSelectedReviewed: { store.markReviewed(selectedTaskID) },
            toggleInspector: { showInspector.toggle() }
        )
    }

    private var syncPreferences: SyncPreferences {
        var enabledSources: Set<WorkSource> = []
        if slackEnabled { enabledSources.insert(.slack) }
        if emailEnabled { enabledSources.insert(.email) }
        if gitLabEnabled { enabledSources.insert(.gitLab) }
        if githubEnabled { enabledSources.insert(.github) }
        if jiraEnabled { enabledSources.insert(.jira) }
        if notesEnabled { enabledSources.insert(.notes) }

        return SyncPreferences(
            enabledSources: enabledSources,
            notificationsEnabled: notificationsEnabled,
            dueSoonHours: dueSoonHours,
            notificationLeadTime: NotificationLeadTime(rawValue: notificationLeadTimeRaw) ?? .oneDay
        )
    }

    private func syncNow() {
        Task {
            await store.syncSources(preferences: syncPreferences, force: true)
        }
    }

    private func syncIfNeeded() async {
        guard autoSyncEnabled else {
            return
        }

        await store.syncSources(
            preferences: syncPreferences,
            force: false,
            minimumInterval: syncIntervalSeconds
        )
    }

    private func syncOnActivation() async {
        guard autoSyncEnabled else {
            return
        }

        await store.syncSources(preferences: syncPreferences, force: true)
    }

    private func runPeriodicSyncLoop() async {
        while !Task.isCancelled && scenePhase == .active && autoSyncEnabled {
            do {
                try await Task.sleep(nanoseconds: UInt64(syncIntervalSeconds * 1_000_000_000))
            } catch {
                return
            }

            await syncIfNeeded()
        }
    }

    private var syncIntervalSeconds: TimeInterval {
        max(syncIntervalMinutes, 1) * 60
    }
}
