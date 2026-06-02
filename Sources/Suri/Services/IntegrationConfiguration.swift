import Foundation

struct IntegrationConfiguration: Codable {
    var slack: SlackIntegrationConfiguration?
    var gitLab: GitLabIntegrationConfiguration?
    var github: GitHubIntegrationConfiguration?
    var jira: JiraIntegrationConfiguration?
    var email: DirectoryIntegrationConfiguration?
    var notes: DirectoryIntegrationConfiguration?

    static var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("Suri", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("integrations.json")
    }

    static func load() throws -> IntegrationConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(IntegrationConfiguration.self, from: data)
    }

    static func writeSampleIfNeeded() throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try sampleJSON.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
        }

        return fileURL
    }

    static let sampleJSON = """
    {
      "slack": {
        "enabled": true,
        "mode": "agentSlack",
        "query": "",
        "workspace": "",
        "count": 20,
        "importantOnly": false,
        "includeLater": true,
        "lookbackHours": 72,
        "codexImportanceEnabled": true,
        "codexTimeoutSeconds": 30
      },
      "gitLab": {
        "enabled": false,
        "baseURL": "https://gitlab.com",
        "privateToken": "glpat-your-token",
        "scope": "reviews_for_me",
        "projectIDs": []
      },
      "github": {
        "enabled": true,
        "mode": "ghCLI",
        "token": "",
        "owner": "",
        "repos": [],
        "count": 30,
        "includePullRequests": true,
        "includeIssues": true
      },
      "jira": {
        "enabled": false,
        "baseURL": "https://your-domain.atlassian.net",
        "email": "you@example.com",
        "apiToken": "your-api-token",
        "jql": "assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC"
      },
      "email": {
        "enabled": false,
        "directory": "~/Documents/SuriEmail"
      },
      "notes": {
        "enabled": false,
        "directory": "~/Documents/SuriNotes"
      }
    }
    """
}

struct SlackIntegrationConfiguration: Codable {
    var enabled: Bool?
    var mode: SlackIntegrationMode?
    var token: String?
    var query: String?
    var workspace: String?
    var count: Int?
    var importantOnly: Bool?
    var includeLater: Bool?
    var lookbackHours: Double?
    var codexImportanceEnabled: Bool?
    var codexTimeoutSeconds: Double?
}

enum SlackIntegrationMode: String, Codable {
    case agentSlack
    case webAPI
}

struct GitLabIntegrationConfiguration: Codable {
    var enabled: Bool?
    var baseURL: String
    var privateToken: String
    var scope: String?
    var projectIDs: [String]?
}

struct GitHubIntegrationConfiguration: Codable {
    var enabled: Bool?
    var mode: GitHubIntegrationMode?
    var token: String?
    var owner: String?
    var repos: [String]?
    var count: Int?
    var includePullRequests: Bool?
    var includeIssues: Bool?
}

enum GitHubIntegrationMode: String, Codable {
    case ghCLI
    case webAPI
}

struct JiraIntegrationConfiguration: Codable {
    var enabled: Bool?
    var baseURL: String
    var email: String
    var apiToken: String
    var jql: String?
}

struct DirectoryIntegrationConfiguration: Codable {
    var enabled: Bool?
    var directory: String
}

extension DirectoryIntegrationConfiguration {
    var directoryURL: URL {
        URL(fileURLWithPath: directory.expandingTildeInPath, isDirectory: true)
    }
}
