# Productivity Time MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native macOS 14+ productivity app with saved activities, one timer or stopwatch, durable local history, and independent idempotent Apple Notes and Notion delivery.

**Architecture:** A pure Swift state machine measures time from an injectable monotonic clock and emits completion events without depending on SwiftUI or persistence. SwiftData stores activities, active-session snapshots, completed sessions, and one durable delivery record per destination; a serialized delivery coordinator performs local-first Apple Notes and Notion delivery with independent recovery. SwiftUI observes a composition-root app model while visible refresh work is capped at once per second and hidden stopwatch work uses no periodic task.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit lifecycle hooks where required, ContinuousClock, UserNotifications, NSAppleScript, Security Keychain APIs, URLSession, Swift Testing/XCTest, Xcode, Git.

**Spec:** `docs/superpowers/specs/2026-09-20-productivity-time-mvp-design.md`

## Global Constraints

- Target macOS 14 and newer with a native single-window app.
- Use no third-party packages and perform no global package installation.
- Keep DerivedData, `.build`, caches, generated files, and test artifacts inside the repository.
- Allow exactly one active timer or stopwatch.
- Measure runtime duration from an injectable monotonic clock, never from UI ticks.
- A stopwatch creates a session only when reset with elapsed duration greater than zero.
- A timer creates a session only when it naturally reaches zero.
- Save a completed session locally before any notification, Apple Notes, or Notion delivery.
- Maintain independent durable Apple Notes and Notion delivery records for every session; partial success, failure, retry, and recovery affect only the chosen destination.
- Make Apple Notes retries idempotent with the session's full UUID marker and serialize Notes writes.
- Query Notion by the stable session UUID before creating a page; after any ambiguous create result, query again and never blindly repeat a POST.
- Store the Notion internal-integration token only in Keychain; store only the non-secret data-source ID in preferences.
- Do not log credentials, request or response bodies, note bodies, activity names, or session content.
- Defer OAuth, hosted callbacks, App Store distribution, analytics, menu-bar controls, and background helpers.
- Use TDD for behavior: observe a relevant failing test before adding production code.
- Application implementation and security-review agents use `gpt-5.6-terra` with high effort. Sol High is read-only and limited to orchestration advice.

## Review Focus

- Repeated deadline callbacks or retries must not create duplicate local sessions, duplicate Notes rows, or duplicate Notion pages.
- Pause, cancel, window close, restore, and app termination must not accidentally satisfy completion semantics.
- Activity and note names containing quotes, Unicode, emoji, HTML, or AppleScript syntax must remain inert data.
- Sleep/wake and graceful quit must preserve duration semantics without per-second persistence.
- Permission, authorization, schema, or integration failures must preserve the local session, keep the other destination's state intact, and expose a recoverable failed state without private logs.

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

- [ ] Update every repository contract so both Apple Notes and Notion are MVP destinations, Sol performs only orchestration advice, and Terra performs implementation and final security review.
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
- Produces activity CRUD; completed-session save; active snapshot save/load; and durable delivery-record support that Task 5A extends to independently tracked destinations.
- Produces in-memory and application SwiftData containers.

- [ ] Write and fail in-memory tests for case-insensitive activity uniqueness, rename conflict, active-activity deletion refusal, and immutable historical title snapshots.
- [ ] Implement activity records and typed conflict/validation errors.
- [ ] Write and fail tests for stable UUID storage, duplicate UUID rejection, default `.pending`, legal delivery transitions, and restart fetch of recoverable records.
- [ ] Implement the completed-session record and durable delivery baseline, leaving no external delivery in this task.
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

### Task 5A: Add Per-Destination Durable Outbox (macOS Core Implementer)

**Files:**
- Modify: `ProductivityTime/Persistence/SessionRecord.swift`, `SwiftDataStore.swift`, `SessionRepository.swift`
- Create: `ProductivityTime/Persistence/DeliveryDestination.swift`, `DestinationDeliveryRecord.swift`
- Modify: `ProductivityTime/App/AppModel.swift`, `AppLifecycleController.swift`
- Create: `ProductivityTimeTests/Persistence/DestinationDeliveryStoreTests.swift`

**Interfaces:**
- `DeliveryDestination` exposes `.appleNotes` and `.notion`.
- `DestinationDeliveryRecord` stores `sessionID`, `destination`, `pending|delivering|delivered|failed`, and a sanitized optional error category.
- `SessionRepository` exposes atomic destination-specific fetch, claim, success, failure, retry, and cold-launch interrupted-delivery recovery operations.

- [ ] Write and fail storage tests proving a newly saved completed session creates two pending destination records with the same stable session UUID.
- [ ] Implement a uniqueness constraint on `(sessionID, destination)` and a migration-safe replacement for the single-destination delivery state.
- [ ] Write and fail transition tests proving Apple Notes delivered plus Notion failed is representable, retrying Notion leaves Apple Notes delivered, and no destination can transition out of delivered.
- [ ] Implement atomic destination-specific claim/success/failure/retry APIs with sanitized error categories; prevent concurrent claims of the same record.
- [ ] Write and fail cold-launch recovery tests proving only interrupted `.delivering` records become pending/failed-retryable, while live delivery is not requeued and the other destination is unchanged.
- [ ] Implement one cold-launch recovery call before any delivery and no polling or per-tick persistence.
- [ ] Run the complete suite, commit as `feat: add per-destination delivery outbox`, and push.

### Task 5B: Implement Apple Notes, Notion, and Notifications (Integrations Implementer)

**Files:**
- Create: `ProductivityTime/Integrations/Notifications/NotificationScheduler.swift`
- Create: `ProductivityTime/Integrations/Notes/NotesSessionSink.swift`, `AppleNotesAdapter.swift`, `NotesLineFormatter.swift`
- Create: `ProductivityTime/Integrations/Notion/NotionSessionSink.swift`, `NotionAPIClient.swift`, `NotionConfiguration.swift`, `KeychainNotionCredentialStore.swift`
- Create: `ProductivityTime/Integrations/Delivery/DeliveryCoordinator.swift`
- Modify: `ProductivityTime/Resources/ProductivityTime.entitlements`
- Create: integration tests under `ProductivityTimeTests/Integrations/`

**Interfaces:**
- `NotesSessionSink.deliver(_:to:)` and `testConnection(to:)` are async and Sendable.
- `NotionSessionSink.deliver(_:configuration:)` and `testConnection(configuration:)` are async and Sendable; `NotionConfiguration` contains only non-secret data-source/schema configuration.
- `NotionCredentialStore` writes and reads only the user-supplied token from Keychain.
- `NotesLineFormatter` returns title, mode, `HH:mm:ss`, and local date/time.
- Serialized `DeliveryCoordinator` exposes `deliverPending(destination:)` and `retry(sessionID:destination:)`.

- [ ] Write and fail pure Notes formatter tests using fixed locale/calendar/time zone and hostile quotes, slashes, `<>&`, Unicode, and emoji; implement deterministic formatting without executable AppleScript interpolation.
- [ ] Write and fail AppleScript boundary tests proving source is constant, hostile values are Apple event data, duplicate line suppression works, and permission, note lookup, or script failures map to typed sanitized errors.
- [ ] Implement fixed-handler parameterized Apple Notes lookup, configured-name fallback, default-account creation, duplicate line scan, and serialized one-line append.
- [ ] Write and fail Keychain tests through an injectable credential-store protocol proving tokens never enter preferences, logs, request descriptions, or test failure output; implement the Security Keychain adapter without global installation or secret fixtures.
- [ ] Write and fail Notion client tests using a `URLProtocol` stub: query by stable UUID occurs before create; an existing UUID produces no create; normal create contains title/mode/duration/date/UUID; and definitive authorization, schema, and data-source failures are typed and sanitized.
- [ ] Implement `URLSession` Notion requests with Authorization data obtained only at request execution, the configured data-source ID from preferences, and validated schema mapping.
- [ ] Write and fail ambiguous-POST tests for timeout/disconnect and uncertain response after a possible acceptance; implement re-query-by-UUID before any subsequent create and prohibit blind POST retry.
- [ ] Write and fail coordinator tests for independent local pending, claim, success/failure, launch/manual retry, serialized same-destination writes, partial success, and duplicate-success handling; implement the serial coordinator against Task 5A APIs.
- [ ] Write and fail notification tests for timer schedule/pause/reset/resume and authorization denial; implement without blocking local completion.
- [ ] Run all tests, commit as `feat: add Apple Notes and Notion delivery adapters`, and push.

### Task 5C: Compose Delivery and Destination-Specific UI (macOS Core Implementer)

**Files:**
- Modify: `ProductivityTime/App/AppModel.swift`, `ContentView.swift`, `AppLifecycleController.swift`
- Modify: `ProductivityTime/Features/History/HistoryView.swift`, `ProductivityTime/Features/Settings/SettingsView.swift`
- Modify: `ProductivityTimeTests/App/AppModelTests.swift`, `ProductivityTimeUITests/ProductivityTimeUITests.swift`
- Create: `ProductivityTimeTests/App/DeliveryCompositionTests.swift`

**Interfaces:**
- Completed-session composition performs local save, UI update, notification scheduling, then independently scheduled destination delivery; persistence failure reaches no external boundary.
- History exposes each destination's state and Retry only for that failed destination.
- Settings persists Apple Notes target name and Notion data-source ID as non-secret preferences, writes the Notion token only through `NotionCredentialStore`, and exposes destination-specific connection/schema tests.

- [ ] Write and fail composition tests proving a local completed session creates both outbox records before either adapter is invoked; a persistence failure invokes neither adapter nor notification scheduler.
- [ ] Implement completion and cold-launch composition so recovery runs exactly once before either destination delivery, while in-memory tasks are cancelled only after lifecycle persistence.
- [ ] Write and fail view-model/UI tests proving history can show Apple Notes delivered while Notion failed, retrying Notion does not call Apple Notes, and inaccessible Retry controls describe the blocked reason.
- [ ] Implement separate destination status and Retry controls with accessibility labels, keyboard reachability, and no timer work in views.
- [ ] Write and fail settings tests for trimmed Notes target names, a Keychain-only Notion token update/removal, non-secret data-source persistence, and successful destination-specific connection/schema tests triggering only that destination's retry.
- [ ] Implement Settings errors as sanitized actionable copy; never display or log the token.
- [ ] Run the complete suite, commit as `feat: compose dual delivery workflow`, and push.

### Task 6: Complete Dual-Delivery Recovery, Accessibility, Privacy, and Energy Verification

**Files:**
- Modify: settings/history/app-model/UI-test files as required by test findings
- Create: `ProductivityTimeTests/App/RecoveryTests.swift`, `PrivacyLoggingTests.swift`
- Create: `docs/testing/manual-mvp-checklist.md`

**Interfaces:**
- Settings manages non-secret destination preferences and Keychain-mediated token commands without exposing the secret.
- History exposes independent Apple Notes and Notion delivery state and Retry for each failed destination.
- The manual checklist records real Automation, Notion schema/connection, notification, privacy, accessibility, and energy evidence.

- [ ] Write and fail recovery tests for Apple Notes delivered/Notion failed, Notion delivered/Apple Notes failed, interrupted delivery recovery after restart, and retry of each destination without resending the other.
- [ ] Implement only the targeted fixes required for these recovery tests; preserve no-polling and no-per-tick-persistence behavior.
- [ ] Write and pass privacy-log tests proving only stable error categories are recorded, never Keychain tokens, Authorization headers, Notion bodies, AppleScript dictionaries, note bodies, or session values.
- [ ] Complete UI tests for keyboard operation, labels, disabled-state explanations, independent Retry actions, and non-color/non-sound completion feedback.
- [ ] Manually verify Automation permission/denial, note creation, one append and UUID deduplication, Notion token storage, schema/connection failure guidance, query-before-create, ambiguous-create re-query behavior, one-page UUID deduplication, destination-specific retry, closed-window notification, completion semantics, Console privacy, idle CPU, and hidden-stopwatch wakeups.
- [ ] Run full Debug tests and unsigned Release build with repository-local DerivedData, followed by `git diff --check` and secret/unrelated-file inspection.
- [ ] Commit as `test: verify dual-delivery productivity timer MVP` and push.

### Task 7: Final Terra Security Review and Handoff

**Files:**
- Modify only when an accepted finding needs a targeted test-first fix.

**Interfaces:**
- Consumes the branch diff, test evidence, manual checklist, and SDD ledger.
- Produces a severity-ordered read-only review and residual-risk report.

- [ ] Dispatch the read-only Terra High security reviewer over the whole branch for semantics, monotonic timing, duplicates, per-destination recovery, concurrency, SwiftData safety, AppleScript injection, Notion request/idempotency safety, Keychain handling, permissions, privacy, accessibility, energy, and missing tests.
- [ ] If findings exist, send the complete list to one Terra High fixer, require regression tests first, and create one review-fix commit.
- [ ] Run one scoped Terra High re-review and repository-level verification.
- [ ] Inspect committed content for secrets and unrelated changes, push without force, and prepare the PR handoff with exact evidence and residual manual dependencies.
