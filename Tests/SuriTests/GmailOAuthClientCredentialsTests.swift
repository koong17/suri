import Foundation
import Testing
@testable import Suri

struct GmailOAuthClientCredentialsTests {
    @Test
    func resolvesDownloadedDesktopClientSecretFile() throws {
        let fileURL = try temporaryFile(named: "google-client-secret.json")
        try """
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "client_secret": "desktop-secret"
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let credentials = try GmailOAuthClientCredentials.resolve(
            configuration: GmailIntegrationConfiguration(),
            candidateFiles: [fileURL]
        )

        #expect(credentials.clientID == "desktop-client.apps.googleusercontent.com")
        #expect(credentials.clientSecret == "desktop-secret")
        #expect(credentials.sourceDescription == fileURL.path)
    }

    @Test
    func resolvesLorekeeperStyleGoogleCredentialsFile() throws {
        let fileURL = try temporaryFile(named: "credentials.json")
        try """
        {
          "google": {
            "client_id": "google-client.apps.googleusercontent.com",
            "client_secret": "google-secret"
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let credentials = try GmailOAuthClientCredentials.resolve(
            configuration: GmailIntegrationConfiguration(),
            candidateFiles: [fileURL]
        )

        #expect(credentials.clientID == "google-client.apps.googleusercontent.com")
        #expect(credentials.clientSecret == "google-secret")
    }

    @Test
    func explicitConfigurationWinsOverFile() throws {
        let fileURL = try temporaryFile(named: "google-client-secret.json")
        try """
        {
          "installed": {
            "client_id": "file-client.apps.googleusercontent.com",
            "client_secret": "file-secret"
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let credentials = try GmailOAuthClientCredentials.resolve(
            configuration: GmailIntegrationConfiguration(
                clientID: "config-client.apps.googleusercontent.com",
                clientSecret: "config-secret"
            ),
            candidateFiles: [fileURL]
        )

        #expect(credentials.clientID == "config-client.apps.googleusercontent.com")
        #expect(credentials.clientSecret == "config-secret")
        #expect(credentials.sourceDescription == "integrations.json")
    }

    @Test
    func doesNotUseWebClientSecretFileForLoopbackOAuth() throws {
        let fileURL = try temporaryFile(named: "google-client-secret.json")
        try """
        {
          "web": {
            "client_id": "web-client.apps.googleusercontent.com",
            "client_secret": "web-secret"
          }
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(throws: ServiceClientError.self) {
            _ = try GmailOAuthClientCredentials.resolve(
                configuration: GmailIntegrationConfiguration(),
                candidateFiles: [fileURL]
            )
        }
    }

    private func temporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suri-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
}
