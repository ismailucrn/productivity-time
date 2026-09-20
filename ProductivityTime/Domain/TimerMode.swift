enum TimerMode: Equatable, Sendable {
    case stopwatch
    case timer(configured: Duration)
}
