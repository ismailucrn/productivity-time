import AppKit
import Combine
import SwiftUI

struct TimerPanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTimerMode = false
    @State private var minutes = 25
    @StateObject private var windowVisibility = WindowVisibilityObserver()

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Stopwatch") { isTimerMode = false }
                    .accessibilityIdentifier("timer.mode.stopwatch")
                    .buttonStyle(.borderedProminent)
                Button("Timer") { isTimerMode = true }
                    .accessibilityIdentifier("timer.mode.timer")
            }
            if isTimerMode {
                Stepper("Duration: \(minutes) minutes", value: $minutes, in: 1...1_440)
                    .accessibilityIdentifier("timer.duration")
                HStack {
                    ForEach([5, 25, 50], id: \.self) { preset in
                        Button("\(preset)m") { minutes = preset }
                    }
                }
            }
            Text(durationText(model.displayedDuration))
                .font(.system(size: 46, design: .monospaced))
                .accessibilityIdentifier("timer.duration.display")
            HStack {
                Button(primaryTitle) { primaryAction() }
                    .accessibilityIdentifier("timer.primary")
                    .disabled(model.activeSession == nil && model.selectedActivityID == nil)
                Button("Reset") { perform { try model.reset() } }
                    .accessibilityIdentifier("timer.reset")
                    .disabled(model.activeSession == nil)
                Button("Cancel") { perform { try model.cancel() } }
                    .accessibilityIdentifier("timer.cancel")
                    .disabled(model.activeSession == nil)
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("timer.error")
            }
        }
        .padding(32)
        .background(WindowVisibilityAttachment(observer: windowVisibility))
        .onAppear { windowVisibility.bind(model: model) }
        .onDisappear { windowVisibility.stop() }
    }

    private var primaryTitle: String {
        switch model.activeSession?.state {
        case .running: "Pause"
        case .paused: "Resume"
        default: "Start"
        }
    }

    private func primaryAction() {
        do {
            switch model.activeSession?.state {
            case .running: try model.pause()
            case .paused: try model.resume()
            default:
                guard let activityID = model.selectedActivityID else { return }
                if isTimerMode { try model.startTimer(for: activityID, duration: .seconds(minutes * 60)) }
                else { try model.startStopwatch(for: activityID) }
            }
        } catch {
            model.record(error)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            model.record(error)
        }
    }

    private func durationText(_ duration: Duration) -> String {
        let total = max(0, Int(duration.timeInterval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

@MainActor
struct WindowVisibilityState: Equatable {
    let appIsActive: Bool
    let windowIsKey: Bool
    let windowIsVisible: Bool
    let windowIsMiniaturized: Bool
    let windowIsOccluded: Bool
    let isObscuredBySheet: Bool

    var keepsCounterVisible: Bool {
        appIsActive && windowIsKey && windowIsVisible && !windowIsMiniaturized && !windowIsOccluded && !isObscuredBySheet
    }

    static let visible = WindowVisibilityState(appIsActive: true, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: false, isObscuredBySheet: false)
    static let inactive = WindowVisibilityState(appIsActive: false, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: false, isObscuredBySheet: false)
    static let occluded = WindowVisibilityState(appIsActive: true, windowIsKey: true, windowIsVisible: true, windowIsMiniaturized: false, windowIsOccluded: true, isObscuredBySheet: false)
    static let hidden = WindowVisibilityState(appIsActive: false, windowIsKey: false, windowIsVisible: false, windowIsMiniaturized: false, windowIsOccluded: true, isObscuredBySheet: false)

    static func fromSystem(window: NSWindow?) -> WindowVisibilityState {
        guard let window else { return .hidden }
        return WindowVisibilityState(
            appIsActive: NSApp.isActive,
            windowIsKey: window.isKeyWindow,
            windowIsVisible: window.isVisible,
            windowIsMiniaturized: window.isMiniaturized,
            windowIsOccluded: !window.occlusionState.contains(.visible),
            isObscuredBySheet: window.attachedSheet != nil
        )
    }
}

@MainActor
final class WindowVisibilityObserver: ObservableObject {
    private weak var model: AppModel?
    private weak var window: NSWindow?
    private var notificationTokens: [NSObjectProtocol] = []
    private let stateProvider: @MainActor (NSWindow?) -> WindowVisibilityState

    init(_ stateProvider: @escaping @MainActor (NSWindow?) -> WindowVisibilityState = WindowVisibilityState.fromSystem) {
        self.stateProvider = stateProvider
    }

    isolated deinit {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
    }

    func bind(model: AppModel) {
        self.model = model
        updateFromSystemState()
    }

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        removeNotifications()
        self.window = window
        guard window != nil else {
            update(state: .hidden)
            return
        }

        let center = NotificationCenter.default
        let appNames: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ]
        let windowNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willBeginSheetNotification,
            NSWindow.didEndSheetNotification
        ]
        notificationTokens = appNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateFromSystemState() }
            }
        }
        notificationTokens += windowNames.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateFromSystemState() }
            }
        }
        updateFromSystemState()
    }

    func stop() {
        removeNotifications()
        window = nil
        update(state: .hidden)
    }

    func update(state: WindowVisibilityState) {
        model?.setCounterVisible(state.keepsCounterVisible)
    }

    private func updateFromSystemState() {
        update(state: stateProvider(window))
    }

    private func removeNotifications() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }
}

private struct WindowVisibilityAttachment: NSViewRepresentable {
    let observer: WindowVisibilityObserver

    func makeNSView(context: Context) -> VisibilityAttachmentView {
        VisibilityAttachmentView(observer: observer)
    }

    func updateNSView(_ nsView: VisibilityAttachmentView, context: Context) {
        nsView.observer = observer
        observer.attach(to: nsView.window)
    }
}

private final class VisibilityAttachmentView: NSView {
    weak var observer: WindowVisibilityObserver?

    init(observer: WindowVisibilityObserver) {
        self.observer = observer
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observer?.attach(to: window)
    }
}
