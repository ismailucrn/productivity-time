import Foundation

enum DeliveryStatusRole: Equatable {
    case neutral
    case progress
    case success
    case failure
}

struct DeliveryStatusPresentation: Equatable {
    let text: String
    let systemImage: String
    let role: DeliveryStatusRole
    let canRetry: Bool

    static func make(from record: DestinationDelivery?) -> Self {
        switch record?.phase {
        case .delivering:
            .init(text: "Delivering", systemImage: "arrow.triangle.2.circlepath", role: .progress, canRetry: false)
        case .delivered:
            .init(text: "Delivered", systemImage: "checkmark.circle.fill", role: .success, canRetry: false)
        case .failed:
            .init(text: "Failed", systemImage: "exclamationmark.triangle.fill", role: .failure, canRetry: true)
        case .pending, nil:
            .init(text: "Pending", systemImage: "clock", role: .neutral, canRetry: false)
        }
    }
}

enum SessionPresentation {
    static func clockText(for duration: Duration) -> String {
        let total = max(0, Int(duration.timeInterval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
    }

    static func compactDurationText(for duration: Duration) -> String {
        let total = max(0, Int(duration.timeInterval.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total / 60) % 60
        if hours > 0 { return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(total) sec"
    }

    static func modeText(_ mode: SessionMode) -> String {
        mode == .timer ? "Timer" : "Stopwatch"
    }

    static func timerStateText(_ state: TimerState) -> String {
        switch state {
        case .idle: "Ready"
        case .running: "Running"
        case .paused: "Paused"
        }
    }
}

enum TimerSecondaryAction: Equatable {
    case completeSession
    case discard
    case cancelTimer
}

enum TimerPanelPresentation {
    static func configuredMinutes(from duration: Duration?, fallback: Int) -> Int {
        guard let duration else { return fallback }
        return min(1_440, max(1, Int((duration.timeInterval / 60).rounded())))
    }

    static func secondaryActions(for mode: SessionMode?) -> [TimerSecondaryAction] {
        switch mode {
        case .stopwatch: [.completeSession, .discard]
        case .timer: [.cancelTimer]
        case nil: []
        }
    }
}
