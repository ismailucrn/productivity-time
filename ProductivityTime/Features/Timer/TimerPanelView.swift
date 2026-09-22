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
            if selectedActivity == nil && model.activeSession == nil {
                ContentUnavailableView(
                    "Choose an Activity",
                    systemImage: "cursorarrow.click.2",
                    description: Text("Select or add an activity in the sidebar to begin.")
                )
                .accessibilityIdentifier("timer.empty")
            } else {
                Text(model.activeSession?.title ?? selectedActivity?.name.value ?? "")
                    .font(.title2.weight(.semibold))
                Text(SessionPresentation.clockText(for: model.displayedDuration))
                    .font(.system(size: 56, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("timer.duration.display")
                if let activeSession = model.activeSession {
                    Text(SessionPresentation.timerStateText(activeSession.state))
                        .foregroundStyle(.secondary)
                }

                Picker("Mode", selection: $isTimerMode) {
                    Text("Stopwatch").tag(false)
                    Text("Timer").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("timer.mode")
                .disabled(model.activeSession != nil)

                if isTimerMode {
                    Stepper("Duration: \(minutes) minutes", value: $minutes, in: 1...1_440)
                        .accessibilityIdentifier("timer.duration")
                        .disabled(model.activeSession != nil)
                    HStack {
                        ForEach([5, 25, 50], id: \.self) { preset in
                            Button {
                                minutes = preset
                            } label: {
                                Label("\(preset) minutes", systemImage: minutes == preset ? "checkmark.circle.fill" : "circle")
                            }
                            .accessibilityLabel(minutes == preset ? "\(preset) minutes, selected" : "\(preset) minutes")
                            .disabled(model.activeSession != nil)
                        }
                    }
                }
            }
            HStack {
                Button(primaryTitle) { primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("timer.primary")
                    .disabled(model.activeSession == nil && model.selectedActivityID == nil)
                if model.activeSession?.mode == .stopwatch {
                    Button("Complete Session") { perform { try model.reset() } }
                        .accessibilityIdentifier("timer.complete")
                    Button("Discard", role: .destructive) { perform { try model.cancel() } }
                        .accessibilityIdentifier("timer.discard")
                } else if model.activeSession?.mode == .timer {
                    Button("Cancel Timer", role: .destructive) { perform { try model.cancel() } }
                        .accessibilityIdentifier("timer.cancel")
                }
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("timer.error")
            }
        }
        .padding(32)
        .background(WindowVisibilityAttachment(observer: windowVisibility))
        .onAppear {
            windowVisibility.bind(model: model)
            synchronizeActiveSessionConfiguration()
        }
        .onChange(of: model.activeSession?.id) { _, _ in
            synchronizeActiveSessionConfiguration()
        }
        .onDisappear { windowVisibility.stop() }
    }

    private var selectedActivity: Activity? {
        guard let selectedActivityID = model.selectedActivityID else { return nil }
        return model.activities.first { $0.id == selectedActivityID }
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

    private func synchronizeActiveSessionConfiguration() {
        guard let activeSession = model.activeSession else { return }
        isTimerMode = activeSession.mode == .timer
        minutes = TimerPanelPresentation.configuredMinutes(
            from: activeSession.configuredDuration,
            fallback: minutes
        )
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
