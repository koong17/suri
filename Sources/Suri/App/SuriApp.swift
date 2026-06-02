import SwiftUI

@main
struct SuriApp: App {
    var body: some Scene {
        WindowGroup("Suri") {
            ContentView()
                .frame(minWidth: 1_180, minHeight: 680)
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            AssistantCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
