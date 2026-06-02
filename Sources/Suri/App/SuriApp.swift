import SwiftUI

@main
struct SuriApp: App {
    var body: some Scene {
        WindowGroup("Suri") {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1160, height: 760)
        .commands {
            AssistantCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
