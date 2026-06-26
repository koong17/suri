import Foundation

struct IntegrationConfiguration: Codable {
    var slack: SlackIntegrationConfiguration? = nil
    var gitLab: GitLabIntegrationConfiguration? = nil
    var github: GitHubIntegrationConfiguration? = nil
    var jira: JiraIntegrationConfiguration? = nil
    var email: EmailIntegrationConfiguration? = nil
    var notes: DirectoryIntegrationConfiguration? = nil

    static var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("Suri", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("integrations.json")
    }

    static var gmailClientSecretFileURL: URL {
        directoryURL.appendingPathComponent("google-client-secret.json")
    }

    static var googleCredentialsFileURL: URL {
        directoryURL.appendingPathComponent("credentials.json")
    }

    static func load() throws -> IntegrationConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(IntegrationConfiguration.self, from: data)
    }

    static func save(_ configuration: IntegrationConfiguration) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(configuration)
        let encodedObject = try JSONSerialization.jsonObject(with: encodedData) as? [String: Any] ?? [:]
        let existingObject = try existingJSONObject()
        let mergedObject = mergingJSON(existingObject, with: encodedObject)
        let data = try JSONSerialization.data(withJSONObject: mergedObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func existingJSONObject() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func mergingJSON(_ existing: [String: Any], with updates: [String: Any]) -> [String: Any] {
        var result = existing
        for (key, value) in updates {
            if let existingValue = result[key] as? [String: Any],
               let updateValue = value as? [String: Any] {
                result[key] = mergingJSON(existingValue, with: updateValue)
            } else {
                result[key] = value
            }
        }
        return result
    }

    static func writeSampleIfNeeded() throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try sampleJSON.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
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
        "jql": "(assignee = currentUser() OR reporter = currentUser() OR creator = currentUser() OR watcher = currentUser()) AND statusCategory != Done ORDER BY updated DESC"
      },
      "email": {
        "enabled": false,
        "mode": "local",
        "directory": "~/Documents/SuriEmail",
        "gmail": {
          "clientID": "",
          "clientSecret": "",
          "clientSecretFile": "~/Library/Application Support/Suri/google-client-secret.json",
          "query": "in:inbox newer_than:7d",
          "count": 30
        }
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

struct EmailIntegrationConfiguration: Codable {
    var enabled: Bool?
    var mode: EmailIntegrationMode?
    var directory: String?
    var gmail: GmailIntegrationConfiguration?
}

enum EmailIntegrationMode: String, Codable {
    case local
    case gmail
}

struct GmailIntegrationConfiguration: Codable {
    var clientID: String? = nil
    var clientSecret: String? = nil
    var clientSecretFile: String? = nil
    var query: String? = nil
    var count: Int? = nil
}

struct DirectoryIntegrationConfiguration: Codable {
    var enabled: Bool?
    var directory: String
}

extension EmailIntegrationConfiguration {
    var directoryURL: URL {
        URL(fileURLWithPath: (directory ?? "~/Documents/SuriEmail").expandingTildeInPath, isDirectory: true)
    }
}

extension DirectoryIntegrationConfiguration {
    var directoryURL: URL {
        URL(fileURLWithPath: directory.expandingTildeInPath, isDirectory: true)
    }
}
