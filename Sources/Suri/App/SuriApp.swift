import SwiftUI

@main
struct SuriApp: App {
    var body: some Scene {
        WindowGroup("Suri") {
            ContentView()
                .frame(
                    minWidth: LayoutMetrics.minimumWindowSize.width,
                    minHeight: LayoutMetrics.minimumWindowSize.height
                )
        }
        .defaultSize(
            width: LayoutMetrics.defaultWindowSize.width,
            height: LayoutMetrics.defaultWindowSize.height
        )
        .commands {
            AssistantCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
