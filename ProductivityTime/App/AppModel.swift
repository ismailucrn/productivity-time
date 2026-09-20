import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var activeSession: Any?

    init() {
        activeSession = nil
    }
}
