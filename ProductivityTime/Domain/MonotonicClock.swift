import Foundation

protocol MonotonicClock: AnyObject {
    var now: Duration { get }
    var date: Date { get }
}

final class ContinuousMonotonicClock: MonotonicClock {
    private let clock: ContinuousClock
    private let referenceInstant: ContinuousClock.Instant

    init() {
        let clock = ContinuousClock()
        self.clock = clock
        referenceInstant = clock.now
    }

    var now: Duration {
        referenceInstant.duration(to: clock.now)
    }

    var date: Date {
        Date()
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
