import AppKit

@MainActor
final class AppLifecycleController: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var didStart = false

    func start(model: AppModel) throws {
        self.model = model
        guard !didStart else { return }
        // Recovery is lifecycle-owned so ordinary model construction never begins delivery recovery.
        try model.recoverInterruptedDeliveriesOnce()
        try model.loadPersistedState()
        didStart = true
    }

    func snapshotForTermination(model: AppModel) throws {
        try model.snapshotForGracefulQuit()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let model else { return }
        try? snapshotForTermination(model: model)
    }
}
