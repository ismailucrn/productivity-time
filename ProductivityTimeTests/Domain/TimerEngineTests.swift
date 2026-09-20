import XCTest
@testable import ProductivityTime

@MainActor
final class TimerEngineTests: XCTestCase {
    func testStopwatchPauseAccumulatesElapsedTimeWithoutCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)

        XCTAssertEqual(engine.start(), .stateChanged(.running))
        clock.advance(by: .seconds(25))

        XCTAssertEqual(engine.pause(), .stateChanged(.paused))
        XCTAssertEqual(engine.displayDuration, .seconds(25))
    }

    func testRunningStopwatchResetAfterElapsedTimeEmitsOneCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(25))

        let transition = engine.reset()

        XCTAssertEqual(transition, .completion(TimerCompletion(duration: .seconds(25), completedAt: date(after: 25))))
        XCTAssertEqual(engine.state, .idle)
    }

    func testPausedStopwatchResetAfterElapsedTimeEmitsOneCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(25))
        _ = engine.pause()

        let transition = engine.reset()

        XCTAssertEqual(transition, .completion(TimerCompletion(duration: .seconds(25), completedAt: date(after: 25))))
        XCTAssertEqual(engine.state, .idle)
    }

    func testIdleStopwatchResetDoesNotEmitCompletion() {
        let engine = TimerEngine(mode: .stopwatch, clock: makeClock())

        XCTAssertEqual(engine.reset(), .none)
    }

    func testZeroDurationStopwatchResetDoesNotEmitCompletion() {
        let engine = TimerEngine(mode: .stopwatch, clock: makeClock())
        _ = engine.start()

        XCTAssertEqual(engine.reset(), .none)
    }

    func testSecondStopwatchResetDoesNotEmitAnotherCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(25))

        _ = engine.reset()

        XCTAssertEqual(engine.reset(), .none)
    }

    func testRunningStopwatchCancelClearsElapsedTimeWithoutCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(25))

        XCTAssertEqual(engine.cancel(), .stateChanged(.idle))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.displayDuration, .zero)
    }

    func testPausedStopwatchCancelClearsElapsedTimeWithoutCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .stopwatch, clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(25))
        _ = engine.pause()

        XCTAssertEqual(engine.cancel(), .stateChanged(.idle))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.displayDuration, .zero)
    }

    func testTimerStartShowsConfiguredRemainingDuration() {
        let engine = TimerEngine(mode: .timer(configured: .seconds(60)), clock: makeClock())

        XCTAssertEqual(engine.start(), .stateChanged(.running))
        XCTAssertEqual(engine.displayDuration, .seconds(60))
    }

    func testTimerPausePreservesRemainingDurationWithoutCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(60)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(10))

        XCTAssertEqual(engine.pause(), .stateChanged(.paused))
        XCTAssertEqual(engine.displayDuration, .seconds(50))
        clock.advance(by: .seconds(20))
        XCTAssertEqual(engine.displayDuration, .seconds(50))
    }

    func testTimerResumeUsesRemainingDurationAsNewMonotonicDeadline() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(60)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(10))
        _ = engine.pause()
        clock.advance(by: .seconds(20))

        XCTAssertEqual(engine.resume(), .stateChanged(.running))
        clock.advance(by: .seconds(49))
        XCTAssertEqual(engine.completeIfDue(), .none)
        clock.advance(by: .seconds(1))

        XCTAssertEqual(engine.completeIfDue(), .completion(TimerCompletion(duration: .seconds(60), completedAt: date(after: 80))))
    }

    func testTimerResetDoesNotEmitCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(60)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(10))

        XCTAssertEqual(engine.reset(), .stateChanged(.idle))
        XCTAssertEqual(engine.displayDuration, .seconds(60))
    }

    func testTimerCancelDoesNotEmitCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(60)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(10))

        XCTAssertEqual(engine.cancel(), .stateChanged(.idle))
    }

    func testTimerPauseAfterDeadlineEmitsNaturalCompletionAndSuppressesLaterCallback() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(31))

        XCTAssertEqual(engine.pause(), .completion(TimerCompletion(duration: .seconds(30), completedAt: date(after: 30))))
        XCTAssertEqual(engine.completeIfDue(), .none)
    }

    func testTimerResetAfterDeadlineEmitsNaturalCompletionAndSuppressesLaterCallback() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(31))

        XCTAssertEqual(engine.reset(), .completion(TimerCompletion(duration: .seconds(30), completedAt: date(after: 30))))
        XCTAssertEqual(engine.completeIfDue(), .none)
    }

    func testTimerCancelAfterDeadlineEmitsNaturalCompletionAndSuppressesLaterCallback() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(31))

        XCTAssertEqual(engine.cancel(), .completion(TimerCompletion(duration: .seconds(30), completedAt: date(after: 30))))
        XCTAssertEqual(engine.completeIfDue(), .none)
    }

    func testTimerNaturalZeroEmitsConfiguredDurationWithIntendedDate() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(30))

        XCTAssertEqual(engine.completeIfDue(), .completion(TimerCompletion(duration: .seconds(30), completedAt: date(after: 30))))
        XCTAssertEqual(engine.displayDuration, .zero)
    }

    func testRepeatedTimerDeadlineCallbackDoesNotEmitAnotherCompletion() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(30))

        _ = engine.completeIfDue()

        XCTAssertEqual(engine.completeIfDue(), .none)
    }

    func testTimerAdvancedPastDeadlineEmitsOneCompletionAtIntendedDate() {
        let clock = makeClock()
        let engine = TimerEngine(mode: .timer(configured: .seconds(30)), clock: clock)
        _ = engine.start()
        clock.advance(by: .seconds(45))

        XCTAssertEqual(engine.completeIfDue(), .completion(TimerCompletion(duration: .seconds(30), completedAt: date(after: 30))))
    }

    private func makeClock() -> TestClock {
        TestClock(date: Date(timeIntervalSinceReferenceDate: 1_000))
    }

    private func date(after seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000 + seconds)
    }
}
