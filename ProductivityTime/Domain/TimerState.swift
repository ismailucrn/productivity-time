import Foundation

enum TimerState: Equatable, Sendable {
    case idle
    case running
    case paused
}

struct TimerCompletion: Equatable, Sendable {
    let duration: Duration
    let completedAt: Date
}

enum TimerTransition: Equatable, Sendable {
    case none
    case stateChanged(TimerState)
    case completion(TimerCompletion)
}
