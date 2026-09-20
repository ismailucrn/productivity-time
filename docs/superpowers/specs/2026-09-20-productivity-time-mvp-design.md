# Productivity Time MVP Design

## Purpose

Productivity Time is a lightweight native macOS application for tracking focused activities with either a stopwatch or a countdown timer. The MVP prioritizes instant interaction, correct session semantics, low idle energy use, and reliable local delivery to Apple Notes.

The application is for local personal use. It is not an App Store product in this phase.

## Product Decisions

- Support macOS 14 and newer.
- Use a normal single-window macOS application, not a menu-bar application.
- Let users create, rename, delete, and select saved activities such as Study, Reading, or Rest.
- Allow only one active timer or stopwatch at a time.
- Show a simple local history with title, mode, duration, completion date, and Apple Notes delivery state.
- Do not include charts, analytics, cloud sync, telemetry, login items, or a background helper.
- Defer Notion from the MVP. It remains a required post-MVP integration and will use a Keychain-stored token and the Notion REST API.

## Technology Stack

- Swift 6
- SwiftUI for the application interface
- AppKit only for macOS lifecycle behavior that SwiftUI cannot express cleanly
- SwiftData for local persistence
- `ContinuousClock` through an injectable clock abstraction for monotonic runtime measurement
- UserNotifications for timer completion notifications and the system notification sound
- `NSAppleScript` with a fixed handler and parameterized values for Apple Notes automation
- Swift Testing or XCTest for unit and integration tests
- Xcode project with no third-party packages

All build products, DerivedData, caches, test artifacts, and scripting environments must stay inside the repository. Full Xcode is the one machine-level prerequisite and will be installed manually by the user.

## User Experience

The main window contains an activity list and a focused timer panel. A user selects an activity, chooses Timer or Stopwatch, and starts it. Timer mode offers 5, 25, and 50 minute presets plus a custom whole-minute value from 1 through 1440.

Activity names are trimmed, contain 1 through 80 characters, and are unique using case-insensitive comparison. Renaming or deleting an activity never changes the title snapshot stored in completed sessions. An active activity cannot be deleted.

The history view is read-only in the MVP. It shows completed sessions newest first and exposes Retry for a failed Apple Notes delivery. Settings contain the Apple Notes target name, which defaults to `Productivity Time Sessions`, notification permission state, and an Apple Notes connection test.

Closing the main window leaves the application and active counter running. Quitting with Command-Q saves the active session as paused. Time spent while the process is not running does not count. On the next launch, the user can resume or discard the saved session.

## Timekeeping Semantics

The timer domain is a state machine independent of SwiftUI. UI refresh ticks never determine elapsed time.

### Stopwatch

- Start begins monotonic measurement.
- Pause accumulates the monotonic interval and creates no completed session.
- Resume starts a new monotonic interval from the accumulated duration.
- Reset creates exactly one completed session when elapsed duration is greater than zero, whether the stopwatch is running or paused.
- Reset returns the stopwatch to idle after the session is saved.
- Stop, pause, window close, application termination, or restoration never creates a session.

### Timer

- Start records the configured duration and calculates a monotonic deadline.
- Pause stores the monotonic remaining duration and creates no session.
- Resume creates a new monotonic deadline from the stored remaining duration.
- Reaching zero naturally creates exactly one completed session.
- Reset or cancel creates no session.
- If the machine sleeps while the app is alive, `ContinuousClock` advances and the timer completes when the system resumes processing. The recorded completion date is the intended wall-clock deadline rather than the later wake time.
- Quitting pauses and stores the remaining duration. Time while the process is closed does not count.

## Energy Model

- The visible counter refreshes at most once per second.
- A hidden stopwatch has no periodic task.
- A running timer has one suspended task waiting for its deadline and one scheduled user notification.
- No polling loop checks Apple Notes delivery.
- Persistence is updated on state transitions and lifecycle events, never once per display tick.
- The application does not request an idle-sleep assertion or keep the Mac awake.
- Integration work runs off the main actor and only after a session is committed locally.

## Data Model and Interfaces

`Activity` stores a UUID, validated name, and creation date.

`Session` stores a stable UUID, activity-title snapshot, `timer` or `stopwatch` mode, duration in whole seconds, completion date, and Apple Notes delivery state. Delivery states are `pending`, `delivering`, `delivered`, and `failed` with a sanitized optional error category.

`ActiveSessionSnapshot` stores the activity identifier and title, mode, configured duration when applicable, accumulated or remaining duration, and paused/running state needed for graceful lifecycle restoration.

Domain and integration boundaries are expressed by small protocols:

```swift
protocol MonotonicClock: Sendable {
    associatedtype Instant: InstantProtocol
    var now: Instant { get }
    func sleep(until deadline: Instant) async throws
}

@MainActor
protocol SessionRepository {
    func saveCompleted(_ session: CompletedSession) throws
    func saveActive(_ snapshot: ActiveSessionSnapshot?) throws
}

protocol NotesSessionSink: Sendable {
    func deliver(_ session: CompletedSession, to noteName: String) async throws
    func testConnection(to noteName: String) async throws
}

protocol NotificationScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func scheduleTimerCompletion(sessionID: UUID, title: String, at date: Date) async throws
    func cancelTimerCompletion(sessionID: UUID) async
}
```

Pure value types bridge the domain and SwiftData models so domain tests do not require a database or UI runtime.

## Completion Data Flow

1. A domain transition returns a single `CompletionEvent`.
2. The application creates a `CompletedSession` with a UUID and saves it locally.
3. The UI reflects the saved session immediately.
4. A serialized delivery coordinator marks the Notes state as delivering.
5. Apple Notes delivery succeeds and becomes delivered, or fails and becomes failed without deleting the session.
6. Failed items retry only on app launch, a successful connection test, or an explicit Retry command.

This local-first ordering prevents data loss and provides a durable outbox without keeping a background polling loop alive.

## Apple Notes Integration

The app finds or creates one note in the default Notes account with the configured name. The default name is `Productivity Time Sessions`. Each completed session appends one line containing:

```text
Title — Mode — Duration — Local date and time — PT:<full-session-UUID>
```

The full stable identifier is an intentional machine marker. Before appending, the adapter reads the target note body and checks for that marker. If it already exists, delivery returns success without appending. This makes explicit retries idempotent.

The AppleScript source is fixed application code. Activity titles, formatted dates, note names, identifiers, and durations are passed as Apple event handler arguments and escaped as data; none are interpolated into executable script text. Notes writes are serialized to avoid concurrent read-modify-write races.

The app includes `NSAppleEventsUsageDescription` and the Apple Events hardened-runtime entitlement. Permission denial, a missing Notes application, a deleted target note, or a script error becomes a sanitized delivery failure. If a stored Notes identifier becomes invalid, the adapter finds or recreates the note by configured name.

## Error Handling and Privacy

- Tokens, credentials, note bodies, activity names, and session details are never written to diagnostic logs.
- User-facing errors identify the category and recovery action without exposing script source or private note content.
- A denied Automation permission remains visible in Settings with guidance to macOS System Settings.
- Notification denial does not block timer completion or Apple Notes delivery.
- Persistence failure prevents external delivery because there is no durable local session to identify.
- App termination cancels in-memory tasks only after saving a paused snapshot when possible.

## Verification

Deterministic tests use a fake monotonic clock. They cover start, pause, resume, reset, zero completion, cancellation, repeated completion signals, sleep/wake advancement, and graceful restoration. In-memory SwiftData tests cover activity rules, session title snapshots, and delivery-state transitions.

The Notes boundary is tested with a fake adapter for permission denial, note lookup failure, partial delivery failure, retry, and duplicate UUID suppression. A separate manual smoke test covers the real macOS Automation prompt, note creation, append, and retry behavior.

SwiftUI tests cover activity management, mode selection, duration entry, history, Retry, restore/discard, keyboard navigation, and accessibility labels. Release verification checks that the application launches promptly, has no sustained idle CPU work, and produces no periodic wakeups for a hidden stopwatch.

## Agent and Git Workflow

The primary session remains the orchestrator. A read-only Sol High `orchestration_advisor` reviews decomposition and integration decisions but never writes product code or performs the security review. The macOS core, integrations, quality, and read-only security-review roles all use Terra High.

Implementation tasks run sequentially unless their write ownership is provably disjoint. Each task uses test-driven development, a focused commit, a task-level review, and a branch push at an important milestone. Final completion requires repository-level verification followed by a read-only Terra High security and correctness review.

## Out of Scope

- Notion implementation
- OAuth or a hosted callback service
- Mac App Store sandbox compatibility
- Signing, notarization, or public distribution
- Charts, productivity scores, streaks, tagging, search, export, or session editing
- Menu-bar controls, global keyboard shortcuts, widgets, launch-at-login, or helper processes
- iCloud or multi-device synchronization
