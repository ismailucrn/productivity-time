import SwiftUI

@main
struct ProductivityTimeApp: App {
    @StateObject private var model = AppModel.applicationModel()
    @NSApplicationDelegateAdaptor(AppLifecycleController.self) private var lifecycle

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task { try? lifecycle.start(model: model) }
        }
    }
}
