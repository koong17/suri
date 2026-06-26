import SwiftUI

struct SettingsView: View {
    @AppStorage(PreferenceKeys.dailyBriefingEnabled) private var dailyBriefingEnabled = true
    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.notificationLeadTimeRaw) private var notificationLeadTimeRaw = NotificationLeadTime.oneDay.rawValue
    @AppStorage(PreferenceKeys.dueSoonHours) private var dueSoonHours = 24.0
    @AppStorage(PreferenceKeys.autoSyncEnabled) private var autoSyncEnabled = true
    @AppStorage(PreferenceKeys.syncIntervalMinutes) private var syncIntervalMinutes = 5.0
    @AppStorage(PreferenceKeys.quietHoursEnabled) private var quietHoursEnabled = true
    @AppStorage(PreferenceKeys.slackEnabled) private var slackEnabled = true
    @AppStorage(PreferenceKeys.emailEnabled) private var emailEnabled = true
    @AppStorage(PreferenceKeys.gitLabEnabled) private var gitLabEnabled = true
    @AppStorage(PreferenceKeys.githubEnabled) private var githubEnabled = true
    @AppStorage(PreferenceKeys.jiraEnabled) private var jiraEnabled = true
    @AppStorage(PreferenceKeys.notesEnabled) private var notesEnabled = true
    @State private var configStatusMessage: String?
    @State private var gmailStatusMessage: String?
    @State private var isAuthorizingGmail = false

    var body: some View {
        TabView {
            Form {
                Section("브리핑") {
                    Toggle("매일 업무 브리핑 받기", isOn: $dailyBriefingEnabled)
                    Toggle("확인/기한 알림 받기", isOn: $notificationsEnabled)
                    Toggle("앱 활성화 시 자동 동기화", isOn: $autoSyncEnabled)

                    Picker("기본 알림 시점", selection: $notificationLeadTimeRaw) {
                        ForEach(NotificationLeadTime.allCases) { leadTime in
                            Text(leadTime.title)
                                .tag(leadTime.rawValue)
                        }
                    }

                    Stepper(value: $dueSoonHours, in: 1...120, step: 1) {
                        Text("임박 기준: \(Int(dueSoonHours))시간")
                    }

                    Stepper(value: $syncIntervalMinutes, in: 1...60, step: 1) {
                        Text("자동 동기화 간격: \(Int(syncIntervalMinutes))분")
                    }

                    Toggle("조용한 시간 적용", isOn: $quietHoursEnabled)
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("업무 소스") {
                    Toggle("Slack", isOn: $slackEnabled)
                    Toggle("Email", isOn: $emailEnabled)
                    Toggle("GitLab", isOn: $gitLabEnabled)
                    Toggle("GitHub", isOn: $githubEnabled)
                    Toggle("Jira", isOn: $jiraEnabled)
                    Toggle("Notes", isOn: $notesEnabled)
                }
            }
            .tabItem {
                Label("Sources", systemImage: "point.3.connected.trianglepath.dotted")
            }

            Form {
                Section("연동 설정 파일") {
                    Text(IntegrationConfiguration.fileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("샘플 설정 파일 생성") {
                        createSampleConfiguration()
                    }

                    Button("설정 폴더 열기") {
                        openConfigurationFolder()
                    }

                    if let configStatusMessage {
                        Text(configStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Gmail") {
                    Button {
                        authorizeGmail()
                    } label: {
                        Label(isAuthorizingGmail ? "Gmail 로그인 대기 중" : "Gmail 로그인", systemImage: "envelope.badge")
                    }
                    .disabled(isAuthorizingGmail)

                    Text("Google Cloud에서 받은 Desktop OAuth JSON을 아래 위치에 둔 뒤 로그인하세요. 완료되면 email.mode가 gmail로 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(IntegrationConfiguration.gmailClientSecretFileURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if let gmailStatusMessage {
                        Text(gmailStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem {
                Label("Integrations", systemImage: "key")
            }
        }
        .frame(width: 560, height: 420)
        .scenePadding()
    }

    private func createSampleConfiguration() {
        do {
            let url = try IntegrationConfiguration.writeSampleIfNeeded()
            configStatusMessage = "생성됨: \(url.path)"
        } catch {
            configStatusMessage = "생성 실패: \(error.localizedDescription)"
        }
    }

    private func openConfigurationFolder() {
        do {
            try FileManager.default.createDirectory(
                at: IntegrationConfiguration.directoryURL,
                withIntermediateDirectories: true
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [IntegrationConfiguration.directoryURL.path]
            try process.run()
            configStatusMessage = "설정 폴더를 열었습니다."
        } catch {
            configStatusMessage = "설정 폴더 열기 실패: \(error.localizedDescription)"
        }
    }

    private func authorizeGmail() {
        isAuthorizingGmail = true
        gmailStatusMessage = "브라우저에서 Google 로그인을 완료하세요."

        Task {
            do {
                var configuration = try IntegrationConfiguration.load() ?? IntegrationConfiguration()
                var email = configuration.email ?? EmailIntegrationConfiguration(
                    enabled: true,
                    mode: .gmail,
                    directory: "~/Documents/SuriEmail",
                    gmail: GmailIntegrationConfiguration()
                )
                var gmail = email.gmail ?? GmailIntegrationConfiguration()
                if gmail.query?.nilIfEmpty == nil {
                    gmail.query = "in:inbox newer_than:7d"
                }
                if gmail.count == nil {
                    gmail.count = 30
                }

                try await GmailOAuthService().authorize(configuration: gmail)
                email.enabled = true
                email.mode = .gmail
                email.gmail = gmail
                configuration.email = email
                try IntegrationConfiguration.save(configuration)

                await MainActor.run {
                    gmailStatusMessage = "Gmail 로그인 완료. Email 소스가 Gmail 모드로 저장되었습니다."
                    isAuthorizingGmail = false
                }
            } catch {
                await MainActor.run {
                    gmailStatusMessage = "Gmail 로그인 실패: \(error.localizedDescription)"
                    isAuthorizingGmail = false
                }
            }
        }
    }
}
