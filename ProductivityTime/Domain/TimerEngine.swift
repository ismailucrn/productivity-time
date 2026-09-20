import Foundation

@MainActor
final class TimerEngine {
    let mode: TimerMode
    private let clock: any MonotonicClock

    private(set) var state: TimerState = .idle
    private var stopwatchAccumulated: Duration = .zero
    private var stopwatchSegmentStartedAt: Duration?
    private var timerRemaining: Duration
    private var timerDeadline: Duration?
    private var timerCompletionDate: Date?

    init(mode: TimerMode, clock: any MonotonicClock) {
        self.mode = mode
        self.clock = clock

        switch mode {
        case .stopwatch:
            timerRemaining = .zero
        case let .timer(configured):
            timerRemaining = configured
        }
    }

    var displayDuration: Duration {
        switch mode {
        case .stopwatch:
            guard let stopwatchSegmentStartedAt else {
                return stopwatchAccumulated
            }
            return stopwatchAccumulated + (clock.now - stopwatchSegmentStartedAt)
        case .timer:
            guard let timerDeadline else {
                return timerRemaining
            }
            return max(.zero, timerDeadline - clock.now)
        }
    }

    func start() -> TimerTransition {
        guard state == .idle else {
            return .none
        }

        switch mode {
        case .stopwatch:
            stopwatchAccumulated = .zero
            stopwatchSegmentStartedAt = clock.now
        case let .timer(configured):
            timerRemaining = configured
            setTimerDeadline(for: configured)
        }
        state = .running
        return .stateChanged(.running)
    }

    func pause() -> TimerTransition {
        guard state == .running else {
            return .none
        }

        switch mode {
        case .stopwatch:
            stopwatchAccumulated = displayDuration
            stopwatchSegmentStartedAt = nil
        case .timer:
            if let completion = completeTimerIfDue() {
                return completion
            }
            timerRemaining = displayDuration
            timerDeadline = nil
            timerCompletionDate = nil
        }
        state = .paused
        return .stateChanged(.paused)
    }

    func resume() -> TimerTransition {
        guard state == .paused else {
            return .none
        }

        switch mode {
        case .stopwatch:
            stopwatchSegmentStartedAt = clock.now
        case .timer:
            setTimerDeadline(for: timerRemaining)
        }
        state = .running
        return .stateChanged(.running)
    }

    func reset() -> TimerTransition {
        switch mode {
        case .stopwatch:
            let elapsed = displayDuration
            let wasActive = state != .idle
            stopwatchAccumulated = .zero
            stopwatchSegmentStartedAt = nil
            state = .idle

            guard wasActive, elapsed > .zero else {
                return .none
            }
            return .completion(TimerCompletion(duration: elapsed, completedAt: clock.date))
        case let .timer(configured):
            if let completion = completeTimerIfDue() {
                return completion
            }
            guard state != .idle else {
                return .none
            }
            timerRemaining = configured
            timerDeadline = nil
            timerCompletionDate = nil
            state = .idle
            return .stateChanged(.idle)
        }
    }

    func cancel() -> TimerTransition {
        switch mode {
        case .stopwatch:
            guard state != .idle else {
                return .none
            }
            stopwatchAccumulated = .zero
            stopwatchSegmentStartedAt = nil
            state = .idle
            return .stateChanged(.idle)
        case .timer:
            return reset()
        }
    }

    func completeIfDue() -> TimerTransition {
        completeTimerIfDue() ?? .none
    }

    private func completeTimerIfDue() -> TimerTransition? {
        guard case let .timer(configured) = mode,
              state == .running,
              displayDuration <= .zero,
              let timerCompletionDate
        else {
            return nil
        }

        timerRemaining = .zero
        timerDeadline = nil
        self.timerCompletionDate = nil
        state = .idle
        return .completion(TimerCompletion(duration: configured, completedAt: timerCompletionDate))
    }

    private func setTimerDeadline(for duration: Duration) {
        timerDeadline = clock.now + duration
        timerCompletionDate = clock.date.addingTimeInterval(duration.timeInterval)
    }
}
