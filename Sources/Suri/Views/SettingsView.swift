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
    @AppStorage(PreferenceKeys.jiraEnabled) private var jiraEnabled = true
    @AppStorage(PreferenceKeys.notesEnabled) private var notesEnabled = true
    @State private var configStatusMessage: String?

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

                    if let configStatusMessage {
                        Text(configStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem {
                Label("Integrations", systemImage: "key")
            }
        }
        .frame(width: 560, height: 360)
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
}
