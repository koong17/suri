import Foundation

struct GitHubClient: WorkItemProvider {
    let configuration: GitHubIntegrationConfiguration

    var source: WorkSource { .github }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard configuration.mode ?? .ghCLI == .ghCLI else {
            throw ServiceClientError.serviceMessage("GitHub webAPI 모드는 아직 지원하지 않습니다. gh auth login 후 mode를 ghCLI로 사용하세요.")
        }

        var tasks: [AssistantTask] = []

        if configuration.includePullRequests != false {
            tasks += try await fetchPullRequestReviewTasks()
        }

        if configuration.includeIssues != false {
            tasks += try await fetchAssignedIssueTasks()
        }

        return ProviderSnapshot(
            tasks: tasks.sortedForAssistant(),
            connection: SourceConnection(
                source: .github,
                isConnected: true,
                unreadCount: tasks.count,
                lastActivity: .now,
                summary: "GitHub CLI 로그인으로 리뷰 요청 PR과 담당 이슈를 확인했습니다."
            )
        )
    }

    private func fetchPullRequestReviewTasks() async throws -> [AssistantTask] {
        var arguments = [
            "search",
            "prs",
            "--review-requested",
            "@me",
            "--state",
            "open",
            "--sort",
            "updated",
            "--order",
            "desc",
            "--json",
            "title,url,repository,author,updatedAt,createdAt,isDraft,number,body",
            "--limit",
            "\(resultLimit)"
        ]
        arguments += repositoryScopeArguments

        let data = try await runGitHubCLI(arguments: arguments)
        let items = try JSONDecoder.github.decode([GitHubPullRequest].self, from: data)

        return items.map { pullRequest in
            AssistantTask(
                title: pullRequest.title,
                source: .github,
                dueDate: TaskExtractor.inferredDueDate(from: pullRequest.searchableText),
                priority: pullRequest.isDraft == true ? .normal : .high,
                status: .waiting,
                context: pullRequest.body?.nilIfEmpty ?? "GitHub pull request 리뷰 요청입니다.",
                owner: pullRequest.author?.displayName ?? "GitHub",
                requiresUserReview: true,
                recommendedAction: "변경 범위와 CI 상태를 확인한 뒤 리뷰 코멘트를 남기거나 승인 여부를 결정",
                metadata: [
                    MetadataItem(label: "PR", value: "#\(pullRequest.number)"),
                    MetadataItem(label: "Repository", value: pullRequest.repository.displayName),
                    MetadataItem(label: "URL", value: pullRequest.url)
                ]
            )
        }
    }

    private func fetchAssignedIssueTasks() async throws -> [AssistantTask] {
        var arguments = [
            "search",
            "issues",
            "--assignee",
            "@me",
            "--state",
            "open",
            "--sort",
            "updated",
            "--order",
            "desc",
            "--json",
            "title,url,repository,author,updatedAt,createdAt,number,body,labels",
            "--limit",
            "\(resultLimit)"
        ]
        arguments += repositoryScopeArguments

        let data = try await runGitHubCLI(arguments: arguments)
        let items = try JSONDecoder.github.decode([GitHubIssue].self, from: data)

        return items.map { issue in
            let searchableText = issue.searchableText
            return AssistantTask(
                title: issue.title,
                source: .github,
                dueDate: TaskExtractor.inferredDueDate(from: searchableText, fallbackHours: 72),
                priority: TaskExtractor.priority(from: searchableText, default: .normal),
                status: .open,
                context: issue.body?.nilIfEmpty ?? "GitHub issue가 나에게 할당되어 있습니다.",
                owner: issue.author?.displayName ?? "GitHub",
                requiresUserReview: TaskExtractor.requiresReview(from: searchableText),
                recommendedAction: "이슈 상태, 마감, blocker를 확인하고 필요한 업데이트를 남기기",
                metadata: [
                    MetadataItem(label: "Issue", value: "#\(issue.number)"),
                    MetadataItem(label: "Repository", value: issue.repository.displayName),
                    MetadataItem(label: "URL", value: issue.url)
                ]
            )
        }
    }

    private var resultLimit: Int {
        min(max(configuration.count ?? 30, 1), 100)
    }

    private var repositoryScopeArguments: [String] {
        var arguments: [String] = []

        if let owner = configuration.owner?.nilIfEmpty {
            arguments += ["--owner", owner]
        }

        for repo in configuration.repos?.compactMap(\.nilIfEmpty) ?? [] {
            arguments += ["--repo", repo]
        }

        return arguments
    }

    private func runGitHubCLI(arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + arguments

            var environment = ProcessInfo.processInfo.environment
            if let token = configuration.token?.nilIfEmpty {
                environment["GH_TOKEN"] = token
                environment["GITHUB_TOKEN"] = token
            }
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ServiceClientError.serviceMessage("gh 실행 실패: \(error.localizedDescription)"))
                return
            }

            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?.nilIfEmpty

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: ServiceClientError.serviceMessage(errorMessage ?? "gh 종료 코드 \(process.terminationStatus)"))
                    return
                }

                continuation.resume(returning: output)
            }
        }
    }
}

private struct GitHubPullRequest: Decodable {
    var title: String
    var url: String
    var repository: GitHubRepository
    var author: GitHubActor?
    var updatedAt: Date?
    var createdAt: Date?
    var isDraft: Bool?
    var number: Int
    var body: String?

    var searchableText: String {
        [title, body].compactMap { $0 }.joined(separator: "\n")
    }
}

private struct GitHubIssue: Decodable {
    var title: String
    var url: String
    var repository: GitHubRepository
    var author: GitHubActor?
    var updatedAt: Date?
    var createdAt: Date?
    var number: Int
    var body: String?
    var labels: [GitHubLabel]?

    var searchableText: String {
        [title, body, labels?.map(\.name).joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

private struct GitHubRepository: Decodable {
    var name: String?
    var nameWithOwner: String?
    var fullName: String?

    var displayName: String {
        nameWithOwner ?? fullName ?? name ?? "GitHub"
    }
}

private struct GitHubActor: Decodable {
    var login: String?
    var name: String?

    var displayName: String {
        name?.nilIfEmpty ?? login ?? "GitHub"
    }
}

private struct GitHubLabel: Decodable {
    var name: String
}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
