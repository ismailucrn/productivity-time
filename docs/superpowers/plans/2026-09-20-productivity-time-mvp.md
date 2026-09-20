# Productivity Time MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native macOS 14+ productivity app with saved activities, one timer or stopwatch, durable local history, and idempotent Apple Notes delivery.

**Architecture:** A pure Swift state machine measures time from an injectable monotonic clock and emits completion events without depending on SwiftUI or persistence. SwiftData stores activities, active-session snapshots, completed sessions, and Notes delivery state; a serialized delivery coordinator performs local-first Apple Notes delivery. SwiftUI observes a composition-root app model while visible refresh work is capped at once per second and hidden stopwatch work uses no periodic task.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit lifecycle hooks where required, ContinuousClock, UserNotifications, NSAppleScript, Swift Testing/XCTest, Xcode, Git.

**Spec:** `docs/superpowers/specs/2026-09-20-productivity-time-mvp-design.md`

## Global Constraints

- Target macOS 14 and newer with a native single-window app.
- Use no third-party packages and perform no global package installation.
- Keep DerivedData, `.build`, caches, generated files, and test artifacts inside the repository.
- Allow exactly one active timer or stopwatch.
- Measure runtime duration from an injectable monotonic clock, never from UI ticks.
- A stopwatch creates a session only when reset with elapsed duration greater than zero.
- A timer creates a session only when it naturally reaches zero.
- Save a completed session locally before any notification or Apple Notes delivery.
- Make Notes retries idempotent with the session's full UUID and serialize Notes writes.
- Do not log credentials, note bodies, activity names, or session content.
- Defer Notion, OAuth, App Store distribution, analytics, menu-bar controls, and background helpers.
- Use TDD for behavior: observe a relevant failing test before adding production code.
- Application implementation and security-review agents use `gpt-5.6-terra` with high effort. Sol High is read-only and limited to orchestration advice.

## Review Focus

- Repeated deadline callbacks or retries must not create duplicate local sessions or duplicate Notes rows.
- Pause, cancel, window close, restore, and app termination must not accidentally satisfy completion semantics.
- Activity and note names containing quotes, Unicode, emoji, HTML, or AppleScript syntax must remain inert data.
- Sleep/wake and graceful quit must preserve duration semantics without per-second persistence.
- Permission denial and integration failures must preserve the local session and expose a recoverable failed state without private logs.

---

### Task 1: Align Agent Contracts and Scaffold the Native App

**Files:**
- Modify: `AGENTS.md`, `.codex/config.toml`, `.gitignore`
- Create: `.codex/agents/orchestration-advisor.toml`
- Modify: `.codex/agents/security-reviewer.toml`
- Update: the existing orchestration spec and plan to the same role matrix
- Create: `ProductivityTime.xcodeproj/project.pbxproj`
- Create: `ProductivityTime/App/ProductivityTimeApp.swift`, `AppModel.swift`, `ContentView.swift`
- Create: `ProductivityTime/Resources/ProductivityTime.entitlements`
- Create: `ProductivityTimeTests/AppLaunchTests.swift`

**Interfaces:**
- Produces application target `ProductivityTime` and test target `ProductivityTimeTests`.
- Produces `@MainActor final class AppModel: ObservableObject` as the composition root.
- Produces a read-only Sol High `orchestration_advisor`; all writers and the read-only security reviewer are Terra High.

- [ ] Update every repository contract so Notion is an explicit post-MVP requirement, Sol performs only orchestration advice, and Terra performs implementation and final security review.
- [ ] Validate all TOML with project-local Python and verify the exact five-role model/sandbox matrix.
- [ ] Write `AppLaunchTests.testAppModelStartsWithoutAnActiveSession` before the app target exists; run it and record the expected missing-target/type failure.
- [ ] Create a macOS 14 SwiftUI application with bundle identifier `com.ismailucrn.ProductivityTime`, Swift 6 mode, a `WindowGroup`, a minimal `ContentView`, and `AppModel.activeSession == nil`.
- [ ] Add the Apple Events usage string and entitlement file, but do not call Apple Notes yet.
- [ ] Run focused and complete tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `-derivedDataPath ./DerivedData`.
- [ ] Commit as `feat: scaffold native macOS application` and push the feature branch.

### Task 2: Implement the Monotonic Timer Domain

**Files:**
- Create: `ProductivityTime/Domain/ActivityName.swift`, `TimerMode.swift`, `TimerState.swift`, `TimerEngine.swift`, `MonotonicClock.swift`
- Create: `ProductivityTimeTests/Domain/ActivityNameTests.swift`, `TimerEngineTests.swift`
- Create: `ProductivityTimeTests/TestSupport/TestClock.swift`

**Interfaces:**
- `ActivityName.init(_:)` trims and validates 1...80 characters.
- `TimerMode` exposes `.stopwatch` and `.timer(configured: Duration)`.
- `TimerEngine` exposes start, pause, resume, reset, cancel, display-state, and deadline-completion transitions.
- A `TimerTransition.completion` value is the only domain path that can create a session.

- [ ] Write and fail tests for trimming, empty/81-character rejection, 80-character acceptance, Unicode, and emoji.
- [ ] Implement only enough `ActivityName` behavior to pass.
- [ ] Write and fail stopwatch tests: pause produces no completion; running or paused reset after 25 seconds produces one 25-second completion; idle/zero/second reset produces none.
- [ ] Implement stopwatch state from accumulated duration plus the current monotonic segment; add no repeating timer.
- [ ] Write and fail timer tests for start, pause, resume, reset/cancel, natural zero, repeated deadline callback, and clock advancement past the deadline.
- [ ] Implement timer completion so only the first natural zero emits the configured duration and intended completion date.
- [ ] Run the complete suite, commit as `feat: add monotonic timer domain`, and push.

### Task 3: Add SwiftData Persistence and the Durable Outbox

**Files:**
- Create: `ProductivityTime/Persistence/ActivityRecord.swift`, `SessionRecord.swift`, `ActiveSessionRecord.swift`, `SwiftDataStore.swift`, `SessionRepository.swift`
- Create: `ProductivityTimeTests/Persistence/SwiftDataStoreTests.swift`

**Interfaces:**
- Produces domain values `Activity`, `CompletedSession`, `ActiveSessionSnapshot`, and `DeliveryState`.
- Produces activity CRUD; completed-session save; active snapshot save/load; pending fetch; and delivery-state updates.
- Produces in-memory and application SwiftData containers.

- [ ] Write and fail in-memory tests for case-insensitive activity uniqueness, rename conflict, active-activity deletion refusal, and immutable historical title snapshots.
- [ ] Implement activity records and typed conflict/validation errors.
- [ ] Write and fail tests for stable UUID storage, duplicate UUID rejection, default `.pending`, legal delivery transitions, and restart fetch of pending/failed records.
- [ ] Implement the completed-session record and durable delivery state.
- [ ] Write and fail snapshot tests proving graceful quit stores paused duration, closed-process time is ignored, resume uses stored duration, and discard creates no session.
- [ ] Implement single active-snapshot replacement and deletion.
- [ ] Run the complete suite, commit as `feat: persist activities and completed sessions`, and push.

### Task 4: Build the Single-Window SwiftUI Workflow

**Files:**
- Modify: `ProductivityTime/App/AppModel.swift`, `ContentView.swift`
- Create: `ProductivityTime/App/AppLifecycleController.swift`
- Create: `ProductivityTime/Features/Activities/ActivityListView.swift`
- Create: `ProductivityTime/Features/Timer/TimerPanelView.swift`
- Create: `ProductivityTime/Features/History/HistoryView.swift`
- Create: `ProductivityTime/Features/Settings/SettingsView.swift`
- Create: `ProductivityTimeTests/App/AppModelTests.swift`
- Create: `ProductivityTimeUITests/ProductivityTimeUITests.swift`

**Interfaces:**
- `AppModel` composes the timer engine, repository, refresh scheduler, and later integration protocols.
- Views bind to state/commands only; views own no timekeeping or persistence behavior.
- Accessibility identifiers cover activity list/add, both modes, duration, primary/reset actions, history/retry, and restore resume/discard.

- [ ] Write and fail AppModel tests proving one-active-session enforcement, pause without persistence, stopwatch-reset persistence, and timer-reset non-persistence.
- [ ] Implement the minimal command layer.
- [ ] Write and fail injected-scheduler tests: visible counters refresh at one second, hidden stopwatch has no refresh, hidden timer keeps only its deadline task, and refresh never writes persistence.
- [ ] Implement lifecycle and graceful-quit snapshot behavior.
- [ ] Build native activity, timer, history, and settings views without continuous animation.
- [ ] Add UI tests for activity creation, stopwatch pause/reset history semantics, timer cancel semantics, restore, keyboard focus, and accessibility labels.
- [ ] Run unit/UI tests, commit as `feat: add activity and timer workflow`, and push.

### Task 5: Add Notifications and Idempotent Apple Notes Delivery

**Files:**
- Create: `ProductivityTime/Integrations/Notifications/NotificationScheduler.swift`
- Create: `ProductivityTime/Integrations/Notes/NotesSessionSink.swift`, `AppleNotesAdapter.swift`, `NotesLineFormatter.swift`
- Create: `ProductivityTime/Integrations/Delivery/DeliveryCoordinator.swift`
- Modify: `ProductivityTime/App/AppModel.swift`, `ProductivityTime/Resources/ProductivityTime.entitlements`
- Create: integration tests under `ProductivityTimeTests/Integrations/`

**Interfaces:**
- `NotesSessionSink.deliver(_:to:)` and `testConnection(to:)` are async and Sendable.
- `NotesLineFormatter` returns title, mode, `HH:mm:ss`, local date/time, and `PT:<full UUID>`.
- Serialized `DeliveryCoordinator` exposes `deliverPending()` and `retry(sessionID:)`.

- [ ] Write and fail pure formatter tests using fixed locale/calendar/time zone and hostile quotes, slashes, `<>&`, Unicode, and emoji.
- [ ] Implement deterministic display formatting without building executable AppleScript source.
- [ ] Write and fail coordinator tests for local pending state, delivery/failure transitions, launch/manual retry, serialized writes, and duplicate-success handling.
- [ ] Implement a serial actor coordinator and sanitized error categories.
- [ ] Write boundary tests proving script source is constant and hostile values are Apple event data; map permission, Notes lookup, and script failures to typed errors.
- [ ] Implement note identifier lookup, name fallback, default-account creation, full UUID marker check, and one-line append.
- [ ] Write and fail notification tests for timer schedule/pause/reset/resume and authorization denial; implement without blocking local completion.
- [ ] Integrate strict ordering: local save, UI update, notification, then Notes delivery; persistence failure calls no external boundary.
- [ ] Run all tests, commit as `feat: deliver completed sessions to Apple Notes`, and push.

### Task 6: Complete Recovery, Accessibility, Privacy, and Energy Verification

**Files:**
- Modify: settings/history/app-model/UI-test files
- Create: `ProductivityTimeTests/App/RecoveryTests.swift`, `PrivacyLoggingTests.swift`
- Create: `docs/testing/manual-mvp-checklist.md`

**Interfaces:**
- Settings persists a non-secret Notes target name, shows permission state, and tests the connection.
- History exposes Retry only for failed deliveries.
- The manual checklist records real Automation, Notes, notification, and energy evidence.

- [ ] Write and fail settings/recovery tests for the default and trimmed custom note names, connection-triggered retry, denial guidance, resume, and discard.
- [ ] Implement settings in non-secret preferences and restoration behavior.
- [ ] Write and pass privacy-log tests proving only stable error categories are recorded, never private values or AppleScript dictionaries.
- [ ] Complete UI tests for keyboard operation, labels, disabled-state explanations, and non-color/non-sound completion feedback.
- [ ] Manually verify Automation permission/denial, note creation, one append, retry, UUID deduplication, closed-window notification, completion semantics, Console privacy, idle CPU, and hidden-stopwatch wakeups.
- [ ] Run full Debug tests and unsigned Release build with repository-local DerivedData, followed by `git diff --check` and secret/unrelated-file inspection.
- [ ] Commit as `test: verify productivity timer MVP` and push.

### Task 7: Final Terra Security Review and Handoff

**Files:**
- Modify only when an accepted finding needs a targeted test-first fix.

**Interfaces:**
- Consumes the branch diff, test evidence, manual checklist, and SDD ledger.
- Produces a severity-ordered read-only review and residual-risk report.

- [ ] Dispatch the read-only Terra High security reviewer over the whole branch for semantics, monotonic timing, duplicates, concurrency, SwiftData safety, AppleScript injection, permissions, privacy, accessibility, energy, and missing tests.
- [ ] If findings exist, send the complete list to one Terra High fixer, require regression tests first, and create one review-fix commit.
- [ ] Run one scoped Terra High re-review and repository-level verification.
- [ ] Inspect committed content for secrets and unrelated changes, push without force, and prepare the PR handoff with exact evidence and residual manual dependencies.
