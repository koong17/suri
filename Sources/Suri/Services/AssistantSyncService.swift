import Foundation

@MainActor
struct AssistantSyncService {
    func sync(preferences: SyncPreferences) async -> AssistantSyncResult {
        do {
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
                    sources.append(snapshot.connection)
                    notes += snapshot.notes
                } catch {
                    errors.append("\(provider.source.title): \(error.localizedDescription)")
                    sources.append(disconnectedSource(provider.source, error: error))
                }
            }

            return AssistantSyncResult(
                tasks: tasks.sortedForAssistant(),
                sources: completeSources(from: sources),
                notes: notes.sortedByCapturedDateDescending(),
                providerErrors: errors,
                usedFallback: false,
                syncedAt: .now
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
            sources: completeSources(from: []),
            notes: [],
            providerErrors: errors,
            usedFallback: true,
            syncedAt: .now
        )
    }

    private func disconnectedSource(_ source: WorkSource, error: Error) -> SourceConnection {
        SourceConnection(
            source: source,
            isConnected: false,
            unreadCount: 0,
            lastActivity: .now,
            summary: error.localizedDescription
        )
    }

    private func completeSources(from sources: [SourceConnection]) -> [SourceConnection] {
        WorkSource.allCases.map { source in
            sources.first { $0.source == source }
                ?? SourceConnection(
                    source: source,
                    isConnected: false,
                    unreadCount: 0,
                    lastActivity: .now,
                    summary: "설정 파일에 활성화된 연결이 없습니다."
                )
        }
    }
}
