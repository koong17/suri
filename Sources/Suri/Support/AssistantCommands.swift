import SwiftUI

struct AssistantCommandHandlers {
    var syncSources: () -> Void
    var createReminder: () -> Void
    var markSelectedReviewed: () -> Void
    var toggleInspector: () -> Void
}

private struct AssistantCommandHandlersKey: FocusedValueKey {
    typealias Value = AssistantCommandHandlers
}

extension FocusedValues {
    var assistantCommandHandlers: AssistantCommandHandlers? {
        get { self[AssistantCommandHandlersKey.self] }
        set { self[AssistantCommandHandlersKey.self] = newValue }
    }
}

struct AssistantCommands: Commands {
    @FocusedValue(\.assistantCommandHandlers) private var handlers

    var body: some Commands {
        CommandMenu("Assistant") {
            Button("Sync Sources") {
                handlers?.syncSources()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(handlers == nil)

            Button("New Reminder") {
                handlers?.createReminder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(handlers == nil)

            Button("Mark Current Item Reviewed") {
                handlers?.markSelectedReviewed()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(handlers == nil)

            Divider()

            Button("Toggle Inspector") {
                handlers?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(handlers == nil)
        }
    }
}
