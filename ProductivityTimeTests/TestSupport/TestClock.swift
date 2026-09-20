import Foundation
@testable import ProductivityTime

final class TestClock: MonotonicClock {
    private(set) var now: Duration
    private(set) var date: Date

    init(now: Duration = .zero, date: Date) {
        self.now = now
        self.date = date
    }

    func advance(by duration: Duration) {
        now += duration
        date = date.addingTimeInterval(duration.timeInterval)
    }
}
