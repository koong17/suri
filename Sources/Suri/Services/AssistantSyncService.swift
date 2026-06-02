import Foundation

@MainActor
struct AssistantSyncService {
    func sync(preferences: SyncPreferences) async -> AssistantSyncResult {
        do {
            let attemptedAt = Date.now
            guard let configuration = try IntegrationConfiguration.load() else {
                return emptyResult(reason: "연동 설정 파일이 없습니다.")
            }

            let providers = configuredProviders(from: configuration, preferences: preferences)
            guard !providers.isEmpty else {
                return emptyResult(reason: "활성화된 연동 클라이언트가 없습니다.")
            }

            var tasks: [AssistantTask] = []
            var sources: [SourceConnection] = []
            var notes: [AssistantNote] = []
            var errors: [String] = []

            for provider in providers {
                do {
                    let snapshot = try await provider.fetchSnapshot()
                    tasks += snapshot.tasks
                    sources.append(healthyConnection(snapshot.connection, attemptedAt: attemptedAt))
                    notes += snapshot.notes
                } catch {
                    errors.append("\(provider.source.title): \(error.localizedDescription)")
                    sources.append(disconnectedSource(provider.source, error: error, attemptedAt: attemptedAt))
                }
            }

            let deduplicationResult = TaskDeduplicator().deduplicate(tasks.sortedForAssistant())
            do {
                try TaskDedupStore().recordSeenTasks(deduplicationResult.tasks, syncedAt: attemptedAt)
            } catch {
                errors.append("중복 캐시: \(error.localizedDescription)")
            }

            do {
                try AssistantAIQueueStore().refreshPendingItems(from: deduplicationResult.tasks, syncedAt: attemptedAt)
            } catch {
                errors.append("AI 큐: \(error.localizedDescription)")
            }

            return AssistantSyncResult(
                tasks: deduplicationResult.tasks,
                sources: completeSources(
                    from: sources,
                    attemptedAt: attemptedAt,
                    duplicateCounts: deduplicationResult.duplicateCounts
                ),
                notes: notes.sortedByCapturedDateDescending(),
                providerErrors: errors,
                usedFallback: false,
                syncedAt: attemptedAt
            )
        } catch {
            return emptyResult(reason: error.localizedDescription)
        }
    }

    private func configuredProviders(
        from configuration: IntegrationConfiguration,
        preferences: SyncPreferences
    ) -> [any WorkItemProvider] {
        var providers: [any WorkItemProvider] = []

        if preferences.includes(.slack),
           let slack = configuration.slack,
           slack.enabled != false {
            if slack.mode == .agentSlack || slack.mode == nil && slack.token?.nilIfEmpty == nil {
                providers.append(AgentSlackClient(configuration: slack))
            } else {
                providers.append(SlackClient(configuration: slack))
            }
        }

        if preferences.includes(.gitLab),
           let gitLab = configuration.gitLab,
           gitLab.enabled != false {
            providers.append(GitLabClient(configuration: gitLab))
        }

        if preferences.includes(.github),
           let github = configuration.github,
           github.enabled != false {
            providers.append(GitHubClient(configuration: github))
        }

        if preferences.includes(.jira),
           let jira = configuration.jira,
           jira.enabled != false {
            providers.append(JiraClient(configuration: jira))
        }

        if preferences.includes(.email),
           let email = configuration.email,
           email.enabled != false {
            providers.append(LocalEmailClient(configuration: email))
        }

        if preferences.includes(.notes),
           let notes = configuration.notes,
           notes.enabled != false {
            providers.append(LocalNotesClient(configuration: notes))
        }

        return providers
    }

    private func emptyResult(reason: String?) -> AssistantSyncResult {
        var errors: [String] = []
        if let reason {
            errors.append(reason)
        }

        return AssistantSyncResult(
            tasks: [],
            sources: completeSources(from: [], attemptedAt: .now, duplicateCounts: [:]),
            notes: [],
            providerErrors: errors,
            usedFallback: true,
            syncedAt: .now
        )
    }

    private func healthyConnection(_ connection: SourceConnection, attemptedAt: Date) -> SourceConnection {
        var connection = connection
        connection.isConnected = true
        connection.health = .healthy
        connection.lastSuccessAt = attemptedAt
        connection.lastAttemptAt = attemptedAt
        connection.errorMessage = nil
        return connection
    }

    private func disconnectedSource(_ source: WorkSource, error: Error, attemptedAt: Date) -> SourceConnection {
        SourceConnection(
            source: source,
            isConnected: false,
            unreadCount: 0,
            lastActivity: attemptedAt,
            summary: error.localizedDescription,
            health: .disconnected,
            lastAttemptAt: attemptedAt,
            errorMessage: error.localizedDescription
        )
    }

    private func completeSources(
        from sources: [SourceConnection],
        attemptedAt: Date,
        duplicateCounts: [WorkSource: Int]
    ) -> [SourceConnection] {
        WorkSource.allCases.map { source in
            var connection = sources.first { $0.source == source }
                ?? SourceConnection(
                    source: source,
                    isConnected: false,
                    unreadCount: 0,
                    lastActivity: attemptedAt,
                    summary: "설정 파일에 활성화된 연결이 없습니다.",
                    health: .disabled,
                    lastAttemptAt: attemptedAt
                )
            connection.duplicateCount = duplicateCounts[source] ?? 0
            return connection
        }
    }
}
