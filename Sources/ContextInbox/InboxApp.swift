import SwiftUI

/// Started from main.swift (not `@main`) so the headless roles can run without any UI.
struct InboxApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("ContextInbox", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 680, minHeight: 440)
        }
        .defaultSize(width: 880, height: 620)

        Settings {
            SettingsView(model: model)
        }
    }
}
