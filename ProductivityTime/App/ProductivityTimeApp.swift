import SwiftUI

@main
struct ProductivityTimeApp: App {
    @StateObject private var model = AppModel.applicationModel()
    @NSApplicationDelegateAdaptor(AppLifecycleController.self) private var lifecycle

    var body: some Scene {
        Window("Productivity Time", id: "main") {
            ContentView()
                .environmentObject(model)
                .task { startLifecycleIfNeeded() }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }

    private func startLifecycleIfNeeded() {
        do {
            try lifecycle.start(model: model)
        } catch {
            model.record(error)
        }
    }
}
