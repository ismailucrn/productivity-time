# Productivity Time UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing macOS timer workflow easier to understand at a glance, clarify completion and cancellation actions, and present history and integration state with a native, accessible macOS interface.

**Architecture:** Keep the domain, persistence, timer semantics, and integration boundaries unchanged. Add a small pure presentation layer for repeatable labels and formatting, then reshape the existing SwiftUI views around native controls, semantic system colors, a dedicated Settings scene, and accessible state descriptions. Each slice is independently testable and preserves the current accessibility identifiers where doing so does not misrepresent the control.

**Tech Stack:** Swift 6, SwiftUI, AppKit only for the existing window-visibility bridge, XCTest/XCUIAutomation, Xcode Accessibility Inspector, optional Figma Remote MCP for visual comparison, and `mcp__cua_repl` for running-app inspection.

**Spec:** `docs/superpowers/specs/2026-09-20-productivity-time-mvp-design.md`

## Global Constraints

- Target macOS 14 and newer with the existing native single-window application and a dedicated system Settings scene.
- Preserve stopwatch completion only on reset with elapsed duration greater than zero.
- Preserve timer completion only when the timer naturally reaches zero.
- Do not change monotonic timekeeping, persistence schemas, notification scheduling, or delivery idempotency.
- Keep Apple Notes and Notion state independent; a visual status or retry action always refers to exactly one destination.
- Use SwiftUI and system controls, SF Symbols, semantic colors, system spacing, and the user-selected macOS accent color.
- Communicate selection, running state, success, and failure with text or symbols in addition to color.
- Keep credentials and private session content out of screenshots, logs, fixtures, and design files.
- Add no third-party dependencies and keep DerivedData and generated artifacts inside the repository.
- Use TDD for presentation behavior and compile UI tests after every SwiftUI slice.
- Preserve unrelated user changes and create one focused commit per completed task.

## Review Focus

- No selected activity: the detail pane explains how to proceed and the Start action remains unavailable.
- Active stopwatch: the UI clearly says that completing the session records it, while discarding does not.
- Active timer: canceling never looks like successful completion, and the configured duration remains understandable.
- Partial delivery: Apple Notes and Notion show separate states and only a failed destination exposes Retry.
- Narrow window, large accessibility text, keyboard-only navigation, dark appearance, reduced transparency, and increased contrast keep every primary action reachable and labeled.

## Visual Contract

- Sidebar width: 180–280 points, with activities as standard selectable rows and the add field anchored below the list.
- Detail pane: selected activity title, mode picker, large monospaced counter, state/supporting text, one prominent primary action, and context-specific secondary actions.
- Stopwatch secondary actions: `Complete Session` calls reset; `Discard` calls cancel and uses a destructive role.
- Timer secondary action: `Cancel Timer` calls cancel and uses a destructive role. Timer reset is not shown because it competes with cancel without adding a distinct user outcome.
- History rows: title and mode first, duration and completion date second, then independent Apple Notes and Notion status labels. Retry appears beside only the failed destination.
- Settings: Apple Notes and Notion are separate form sections in the standard macOS Settings window; test operations expose testing, success, and sanitized failure state.
- No gradients, custom window chrome, decorative bitmap assets, or fixed brand colors are introduced in this pass.

## Tool-Assisted Design and Review

- Before Task 2, use the Figma Remote MCP if the Figma connector is available. Create three 720×460 macOS frames named `Empty`, `Stopwatch Running`, and `Timer Paused`, using auto layout and system-like neutral materials. Do not upload real activity or session content; use `Writing`, `Reading`, and `Focus` fixtures.
- Ask Figma MCP for `get_screenshot` and `get_variable_defs` on the selected direction. Treat the result as spacing and hierarchy guidance, not generated production code.
- After Tasks 2, 3, 4, and 5, launch the local build and inspect it through `mcp__cua_repl` at the minimum window size and one wider size. Record discrepancies in the task review before committing.
- At Task 6, use Xcode Accessibility Inspector for labels, clipped text, contrast, keyboard focus, and the system accessibility settings listed in that task.
- Figma is a review aid and is not a build dependency. If the connector is unavailable, the Visual Contract above is the source of truth.

## Agent Ownership and Milestones

| Work | Owner | Write ownership |
|---|---|---|
| Tasks 1–3 | `macos_core_implementer` | Presentation types, timer UI, activity/sidebar UI, app scene composition, and related core/unit UI tests |
| Task 4 | `quality_implementer`, after Task 3 | Debug-only deterministic UI fixture, UI regression coverage, and history verification; it may apply targeted view fixes found by its tests |
| Task 5 | `integrations_implementer`, after Task 4 | Connection-test state, Notification permission boundary, Keychain-preserving settings behavior, Settings UI, and integration tests |
| Task 6 | `quality_implementer`, after Task 5 | Repository verification, accessibility checks, regression tests, and targeted verification fixes |
| Every reviewed milestone | `github_manager` | Inspect the staged diff and secret scan, create the focused commit, and push the current feature branch when authentication and network are available |
| Final review | `security_reviewer` | Read-only correctness, privacy, permissions, automation, leakage, injection, concurrency, persistence, regression, and missing-test review |

Before implementation, `github_manager` creates `feat/ui-refresh` from the verified current `main` head and pushes only that feature branch. It never commits or pushes implementation milestones directly to protected `main`, and it never force-pushes. All write tasks run sequentially because Tasks 2–5 touch shared SwiftUI composition or test targets. Each implementer reports changed files, exact verification commands and results, and remaining risks. Implementers do not stage broad directories or commit; after the orchestrator accepts a slice, `github_manager` stages only the exact files listed in that task, checks the staged diff for secrets and unrelated edits, commits, and pushes without force.

### Milestone 0: Create and Verify the Feature Branch

`github_manager` runs this before any implementation agent writes product code:

```bash
git status --short
git branch --show-current
git switch -c feat/ui-refresh
git branch --show-current
git add docs/superpowers/plans/2026-09-22-productivity-time-ui-refresh.md
git diff --cached --check
git diff --cached -- docs/superpowers/plans/2026-09-22-productivity-time-ui-refresh.md
git commit -m "docs: plan productivity UI refresh"
git push -u origin feat/ui-refresh
```

The first status must contain no unexplained changes, and the final branch output must be exactly `feat/ui-refresh`. If that branch already exists, `github_manager` verifies its head and uses `git switch feat/ui-refresh` instead of creating a second branch. The staged diff must contain only this reviewed plan and no credentials or private content. No later milestone pushes unless `git branch --show-current` still reports `feat/ui-refresh`.

---

### Task 1: Add Pure Presentation Values

**Files:**
- Create: `ProductivityTime/Features/Shared/SessionPresentation.swift`
- Create: `ProductivityTimeTests/Features/SessionPresentationTests.swift`
- Modify: `ProductivityTime.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `Duration`, `SessionMode`, `TimerState`, `DestinationDelivery`, and `DeliveryPhase` from the existing domain and delivery layers.
- Produces: `SessionPresentation.clockText(for:)`, `SessionPresentation.compactDurationText(for:)`, `SessionPresentation.modeText(_:)`, `SessionPresentation.timerStateText(_:)`, `TimerPanelPresentation.configuredMinutes(from:fallback:)`, `TimerPanelPresentation.secondaryActions(for:)`, and `DeliveryStatusPresentation.make(from:)`.

- [ ] **Step 1: Write formatting tests that pin zero, multi-hour, and negative display behavior**

```swift
import XCTest
@testable import ProductivityTime

final class SessionPresentationTests: XCTestCase {
    func testClockTextUsesStableTwoDigitFieldsAndClampsNegativeValues() {
        XCTAssertEqual(SessionPresentation.clockText(for: .zero), "00:00:00")
        XCTAssertEqual(SessionPresentation.clockText(for: .seconds(3_661)), "01:01:01")
        XCTAssertEqual(SessionPresentation.clockText(for: .seconds(-4)), "00:00:00")
    }

    func testCompactDurationAvoidsRawFloatingPointOutput() {
        XCTAssertEqual(SessionPresentation.compactDurationText(for: .seconds(45)), "45 sec")
        XCTAssertEqual(SessionPresentation.compactDurationText(for: .seconds(3_900)), "1 hr 5 min")
    }

    func testTimerPresentationRestoresCustomDurationAndContextualActions() {
        XCTAssertEqual(TimerPanelPresentation.configuredMinutes(from: .seconds(3_000), fallback: 25), 50)
        XCTAssertEqual(TimerPanelPresentation.configuredMinutes(from: nil, fallback: 25), 25)
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: .stopwatch), [.completeSession, .discard])
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: .timer), [.cancelTimer])
        XCTAssertEqual(TimerPanelPresentation.secondaryActions(for: nil), [])
    }
}
```

- [ ] **Step 2: Run the focused test and verify the new type is missing**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:ProductivityTimeTests/SessionPresentationTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `SessionPresentation` does not exist.

- [ ] **Step 3: Add delivery-state tests that require text and symbols rather than color-only meaning**

```swift
func testDeliveryPresentationKeepsDestinationsIndependentlyReadable() {
    let failed = DestinationDelivery(
        sessionID: UUID(),
        destination: .notion,
        phase: .failed,
        errorCategory: "network",
        retryNotBefore: nil
    )

    XCTAssertEqual(
        DeliveryStatusPresentation.make(from: failed),
        DeliveryStatusPresentation(text: "Failed", systemImage: "exclamationmark.triangle.fill", role: .failure, canRetry: true)
    )
    XCTAssertEqual(DeliveryStatusPresentation.make(from: nil).text, "Pending")
    XCTAssertFalse(DeliveryStatusPresentation.make(from: nil).canRetry)
}
```

- [ ] **Step 4: Implement the pure presentation API**

```swift
enum DeliveryStatusRole: Equatable { case neutral, progress, success, failure }

struct DeliveryStatusPresentation: Equatable {
    let text: String
    let systemImage: String
    let role: DeliveryStatusRole
    let canRetry: Bool

    static func make(from record: DestinationDelivery?) -> Self {
        switch record?.phase {
        case .delivering: .init(text: "Delivering", systemImage: "arrow.triangle.2.circlepath", role: .progress, canRetry: false)
        case .delivered: .init(text: "Delivered", systemImage: "checkmark.circle.fill", role: .success, canRetry: false)
        case .failed: .init(text: "Failed", systemImage: "exclamationmark.triangle.fill", role: .failure, canRetry: true)
        case .pending, nil: .init(text: "Pending", systemImage: "clock", role: .neutral, canRetry: false)
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

    static func modeText(_ mode: SessionMode) -> String { mode == .timer ? "Timer" : "Stopwatch" }
    static func timerStateText(_ state: TimerState) -> String {
        switch state { case .idle: "Ready"; case .running: "Running"; case .paused: "Paused" }
    }
}

enum TimerSecondaryAction: Equatable { case completeSession, discard, cancelTimer }

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
```

- [ ] **Step 5: Add both files to their Xcode targets, rerun the focused test, and hand the reviewed slice to `github_manager`**

Expected: `SessionPresentationTests` PASS.

```bash
git add ProductivityTime/Features/Shared/SessionPresentation.swift ProductivityTimeTests/Features/SessionPresentationTests.swift ProductivityTime.xcodeproj/project.pbxproj
git commit -m "feat: add session presentation values"
git push origin feat/ui-refresh
```

---

### Task 2: Rebuild the Timer Detail Around the Current Task

**Files:**
- Modify: `ProductivityTime/Features/Timer/TimerPanelView.swift`
- Modify: `ProductivityTimeUITests/ProductivityTimeUITests.swift`

**Interfaces:**
- Consumes: Task 1 `SessionPresentation` functions and the existing `AppModel` timer actions.
- Produces: accessibility identifiers `timer.mode`, `timer.duration`, `timer.duration.display`, `timer.primary`, `timer.complete`, `timer.discard`, and `timer.cancel`; no domain API changes.

- [ ] **Step 1: Update the UI test contract for empty, stopwatch, and timer states**

```swift
func testTimerPanelExplainsEmptyStateAndContextualActions() {
    let app = XCUIApplication()
    app.launch()
    discardRestorableSessionIfNeeded(in: app)

    XCTAssertTrue(app.otherElements["timer.empty"].exists)
    XCTAssertFalse(app.buttons["timer.primary"].isEnabled)

    addActivity(named: "Writing \(UUID().uuidString)", in: app)
    XCTAssertTrue(app.segmentedControls["timer.mode"].exists)
    XCTAssertTrue(app.buttons["timer.primary"].isEnabled)
    app.buttons["timer.primary"].click()
    XCTAssertTrue(app.buttons["timer.complete"].exists)
    XCTAssertTrue(app.buttons["timer.discard"].exists)
}
```

In the existing `testWorkflowControlsExposeAccessibilityIdentifiers`, replace `timer.mode.stopwatch` and `timer.mode.timer` with `timer.mode`; replace `timer.reset` with `timer.complete`; remove the unconditional `history.retry` assertion because Retry is conditional on an individual failed delivery. Update `testStopwatchPauseAndResetAddsOneHistoryEntry` to click `timer.complete`.

- [ ] **Step 2: Build UI tests and verify the new accessibility contract fails to compile or does not match the current view**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds, while the new test would fail against the current UI because the empty-state and contextual identifiers are absent. Do not launch the unsigned UI test runner.

- [ ] **Step 3: Replace the two mode buttons with a labeled segmented picker and preserve mode changes only while idle**

```swift
Picker("Mode", selection: $isTimerMode) {
    Text("Stopwatch").tag(false)
    Text("Timer").tag(true)
}
.pickerStyle(.segmented)
.accessibilityIdentifier("timer.mode")
.disabled(model.activeSession != nil)
```

- [ ] **Step 4: Add selected-activity context, a large counter, and a real empty state**

```swift
if selectedActivity == nil && model.activeSession == nil {
    ContentUnavailableView(
        "Choose an Activity",
        systemImage: "cursorarrow.click.2",
        description: Text("Select or add an activity in the sidebar to begin.")
    )
    .accessibilityIdentifier("timer.empty")
} else {
    Text(model.activeSession?.title ?? selectedActivity?.name.value ?? "")
        .font(.title2.weight(.semibold))
    Text(SessionPresentation.clockText(for: model.displayedDuration))
        .font(.system(size: 56, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .contentTransition(.numericText())
        .accessibilityIdentifier("timer.duration.display")
}
```

Show `SessionPresentation.timerStateText` below the counter whenever a session is active. On `onAppear` and every active-session identity change, set `isTimerMode` from `model.activeSession?.mode` and set `minutes` through `TimerPanelPresentation.configuredMinutes(from:fallback:)`. A restored 50-minute or custom timer therefore shows the correct disabled mode and configured duration instead of the default 25 minutes.

- [ ] **Step 5: Make the primary action prominent and expose only actions that match the current mode**

```swift
Button(primaryTitle) { primaryAction() }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .accessibilityIdentifier("timer.primary")

if model.activeSession?.mode == .stopwatch {
    Button("Complete Session") { perform { try model.reset() } }
        .accessibilityIdentifier("timer.complete")
    Button("Discard", role: .destructive) { perform { try model.cancel() } }
        .accessibilityIdentifier("timer.discard")
} else if model.activeSession?.mode == .timer {
    Button("Cancel Timer", role: .destructive) { perform { try model.cancel() } }
        .accessibilityIdentifier("timer.cancel")
}
```

- [ ] **Step 6: Keep the 5, 25, and 50 minute presets, show the selected preset without color-only meaning, and retain the 1–1440 minute Stepper**

Use a checkmark plus the minute label for the selected preset and expose `"25 minutes, selected"` as its accessibility label. Disable duration editing while any session is active.

- [ ] **Step 7: Run the Task 1 tests and compile all UI tests, inspect the running view at 720×460 and 1000×640, then hand the exact files to `github_manager`**

```bash
git add ProductivityTime/Features/Timer/TimerPanelView.swift ProductivityTimeUITests/ProductivityTimeUITests.swift
git commit -m "feat: clarify timer workspace actions"
git push origin feat/ui-refresh
```

---

### Task 3: Refine the Sidebar and Native macOS Window Commands

**Files:**
- Modify: `ProductivityTime/Features/Activities/ActivityListView.swift`
- Modify: `ProductivityTime/App/AppModel.swift`
- Modify: `ProductivityTime/App/ContentView.swift`
- Modify: `ProductivityTime/App/ProductivityTimeApp.swift`
- Modify: `ProductivityTimeTests/App/AppModelTests.swift`
- Modify: `ProductivityTimeUITests/ProductivityTimeUITests.swift`

**Interfaces:**
- Consumes: existing repository `renameActivity(_:to:)` and `deleteActivity(_:)` behavior.
- Produces: `AppModel.renameActivity(_:to:)`, `AppModel.deleteActivity(_:)`, a single identified main `Window`, and a standard Settings scene reachable through the app menu and Command-Comma.

- [ ] **Step 1: Write failing model tests for rename, delete, selection cleanup, and active-activity protection**

```swift
func testRenameRefreshesActivitiesAndPreservesSelection() throws {
    let repository = InMemorySessionRepository()
    let model = AppModel(repository: repository, clock: TestClock(date: .now), refreshScheduler: TestRefreshScheduler())
    let activity = try model.createActivity(named: "Writing")
    model.selectActivity(activity.id)

    try model.renameActivity(activity.id, to: "Research")

    XCTAssertEqual(model.activities.first?.name.value, "Research")
    XCTAssertEqual(model.selectedActivityID, activity.id)
}

func testDeleteClearsSelectionAndRejectsTheActiveActivity() throws {
    let repository = InMemorySessionRepository()
    let model = AppModel(repository: repository, clock: TestClock(date: .now), refreshScheduler: TestRefreshScheduler())
    let first = try model.createActivity(named: "Writing")
    let second = try model.createActivity(named: "Reading")
    model.selectActivity(first.id)
    try model.deleteActivity(first.id)
    XCTAssertNil(model.selectedActivityID)
    XCTAssertEqual(model.activities.map(\.id), [second.id])

    model.selectActivity(second.id)
    try model.startStopwatch(for: second.id)
    XCTAssertThrowsError(try model.deleteActivity(second.id))
}
```

Use the test file's existing `InMemorySessionRepository` and add real in-memory rename/delete implementations to that fake. Run `AppModelTests`; expected: FAIL because both model methods are missing.

- [ ] **Step 2: Add the smallest model methods and keep repository validation authoritative**

```swift
func renameActivity(_ id: UUID, to rawName: String) throws {
    _ = try repository.renameActivity(id, to: ActivityName(rawName))
    activities = try repository.activities()
}

func deleteActivity(_ id: UUID) throws {
    guard activeSession?.activityID != id else { throw SessionRepositoryError.activityHasActiveSession }
    try repository.deleteActivity(id)
    activities = try repository.activities()
    if selectedActivityID == id { selectedActivityID = nil }
}
```

The model rejects active-session deletion before mutation, and the repository remains authoritative for duplicate or invalid names and persisted active-session constraints. The view records the thrown error through `model.record(error)`.

- [ ] **Step 3: Change UI assertions so Settings is absent from the main toolbar and activity menus are discoverable**

```swift
func testMainToolbarKeepsHistoryAndLeavesSettingsToTheAppMenu() {
    let app = XCUIApplication()
    app.launch()
    discardRestorableSessionIfNeeded(in: app)

    XCTAssertTrue(app.buttons["history.show"].exists)
    XCTAssertFalse(app.buttons["settings.show"].exists)
}

func testActivityContextMenuOffersRenameAndDelete() {
    let app = XCUIApplication()
    app.launch()
    discardRestorableSessionIfNeeded(in: app)
    let name = "Manage \(UUID().uuidString)"
    addActivity(named: name, in: app)
    app.staticTexts[name].rightClick()
    XCTAssertTrue(app.menuItems["Rename"].exists)
    XCTAssertTrue(app.menuItems["Delete"].exists)
}
```

- [ ] **Step 4: Convert activity rows to native labels and expose the active session without relying on tint**

```swift
Label {
    HStack {
        Text(activity.name.value)
        Spacer()
        if model.activeSession?.activityID == activity.id {
            Text("Running").font(.caption).foregroundStyle(.secondary)
        }
    }
} icon: {
    Image(systemName: model.activeSession?.activityID == activity.id ? "timer" : "circle")
}
.tag(activity.id)
.contextMenu {
    Button("Rename") { beginRename(activity) }
    Button("Delete", role: .destructive) { activityPendingDeletion = activity }
        .disabled(model.activeSession?.activityID == activity.id)
}
```

- [ ] **Step 5: Add explicit rename and delete confirmation flows**

Use a rename alert with a bound text field that calls `model.renameActivity(_:to:)`. Use a destructive confirmation alert that names the selected activity and calls `model.deleteActivity(_:)`. Add identifiers `activity.rename.name`, `activity.rename.confirm`, and `activity.delete.confirm`; never delete on the first context-menu click.

- [ ] **Step 6: Keep the add field below the list, add a visible section title, and constrain the sidebar width**

Apply `.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)`. The Add button remains reachable by Return, and an empty list shows `Add your first activity below.` above the input rather than obscuring it.

- [ ] **Step 7: Remove Settings sheet state and its custom outside-click dismissal path from `ContentView`**

Keep History as the sole sheet and use a labeled toolbar item:

```swift
Button { showingHistory = true } label: {
    Label("History", systemImage: "clock.arrow.circlepath")
}
.accessibilityIdentifier("history.show")
```

- [ ] **Step 8: Replace `WindowGroup` with one identified main window and add a standard Settings scene**

```swift
Window("Productivity Time", id: "main") {
    ContentView()
        .environmentObject(model)
        .task { startLifecycleIfNeeded() }
}

Settings {
    SettingsView()
        .environmentObject(model)
}

.commands {
    CommandGroup(replacing: .newItem) { }
}
```

Verify that the app menu exposes Settings, Command-Comma opens the Settings window, and the File menu has no New Window command. Keep lifecycle startup idempotent so opening Settings never starts recovery or delivery a second time.

- [ ] **Step 9: Run the unit suite, compile UI tests, inspect sidebar resizing and keyboard focus, then hand the exact files to `github_manager`**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:ProductivityTimeTests CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO
git add ProductivityTime/Features/Activities/ActivityListView.swift ProductivityTime/App/AppModel.swift ProductivityTime/App/ContentView.swift ProductivityTime/App/ProductivityTimeApp.swift ProductivityTimeTests/App/AppModelTests.swift ProductivityTimeUITests/ProductivityTimeUITests.swift
git commit -m "feat: adopt native macOS navigation"
git push origin feat/ui-refresh
```

---

### Task 4: Make History Scannable and Destination-Specific

**Files:**
- Create: `ProductivityTime/Debug/UITestAppModelFactory.swift`
- Modify: `ProductivityTime/Features/History/HistoryView.swift`
- Modify: `ProductivityTime/App/AppModel.swift`
- Modify: `ProductivityTime.xcodeproj/project.pbxproj`
- Modify: `ProductivityTimeUITests/ProductivityTimeUITests.swift`
- Test: `ProductivityTimeTests/Features/SessionPresentationTests.swift`

**Interfaces:**
- Consumes: Task 1 `SessionPresentation` and `DeliveryStatusPresentation`, plus `AppModel.deliveryRecord(for:destination:)` and `retryDelivery(sessionID:destination:)`.
- Produces: stable status identifiers `history.status.<destination>.<session UUID>`, retry identifiers `history.retry.<destination>.<session UUID>`, and a `#if DEBUG` launch fixture selected only by `--ui-test-fixture mixed-history`.

- [ ] **Step 1: Expand presentation tests for every delivery phase**

```swift
func testEveryDeliveryPhaseHasAReadableLabelAndRetryOnlyOnFailure() {
    let id = UUID()
    let values: [(DeliveryPhase, String, Bool)] = [
        (.pending, "Pending", false),
        (.delivering, "Delivering", false),
        (.delivered, "Delivered", false),
        (.failed, "Failed", true)
    ]

    for (phase, text, canRetry) in values {
        let record = DestinationDelivery(sessionID: id, destination: .appleNotes, phase: phase, errorCategory: nil, retryNotBefore: nil)
        let presentation = DeliveryStatusPresentation.make(from: record)
        XCTAssertEqual(presentation.text, text)
        XCTAssertEqual(presentation.canRetry, canRetry)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify any incomplete phase mapping fails**

Run the Task 1 focused test command. Expected: PASS only after all four phases satisfy the assertions.

- [ ] **Step 3: Add a deterministic, sanitized mixed-history launch fixture**

Use fixed UUID `11111111-2222-3333-4444-555555555555`, activity title `Writing`, a 25-minute timer session, Apple Notes delivered, and Notion failed with category `network`. The factory creates an in-memory `SwiftDataStore`, injects a no-op delivery coordinator and in-memory credential store, and loads the model before returning it:

```swift
#if DEBUG
@MainActor
enum UITestAppModelFactory {
    static let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func makeIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppModel? {
        guard arguments.contains("--ui-test-fixture"), arguments.contains("mixed-history") else { return nil }
        let store = try SwiftDataStore(container: SwiftDataStore.makeInMemoryContainer())
        let activity = try store.createActivity(named: ActivityName("Writing"), createdAt: Date(timeIntervalSince1970: 1_704_067_000))
        let session = CompletedSession(
            id: sessionID,
            activityID: activity.id,
            titleSnapshot: "Writing",
            mode: .timer,
            duration: .seconds(1_500),
            completedAt: Date(timeIntervalSince1970: 1_704_067_200),
            deliveryState: .pending
        )
        try store.saveCompleted(session)
        _ = try store.claimDelivery(sessionID: session.id, destination: .appleNotes, at: Date(timeIntervalSince1970: 1_704_067_201))
        try store.markDeliverySucceeded(sessionID: session.id, destination: .appleNotes)
        _ = try store.claimDelivery(sessionID: session.id, destination: .notion, at: Date(timeIntervalSince1970: 1_704_067_201))
        try store.markDeliveryFailed(sessionID: session.id, destination: .notion, errorCategory: "network", retryNotBefore: nil)
        let model = AppModel(
            repository: store,
            clock: ContinuousMonotonicClock(),
            refreshScheduler: TaskRefreshScheduler(),
            deliveryCoordinator: UITestNoopDeliveryCoordinator(),
            credentialStore: UITestMemoryCredentials()
        )
        try model.loadPersistedState()
        return model
    }
}

@MainActor private final class UITestNoopDeliveryCoordinator: DeliveryCoordinating {
    func deliverPending(destination: DeliveryDestination) async -> [DeliveryAttemptResult] { [] }
    func deliverAllPending() async -> [DeliveryAttemptResult] { [] }
    func retry(sessionID: UUID, destination: DeliveryDestination) async -> DeliveryAttemptResult {
        .init(sessionID: sessionID, destination: destination, outcome: .skipped)
    }
}

private final class UITestMemoryCredentials: NotionCredentialStore, @unchecked Sendable {
    func readToken() throws -> Data? { nil }
    func writeToken(_ token: Data) throws {}
    func removeToken() throws {}
}
#endif
```

At the start of `AppModel.applicationModel()`, return this model under `#if DEBUG` when requested. Production and ordinary Debug launches retain the existing application container and real coordinator.

- [ ] **Step 4: Write and run the signed fixture UI test when signing is available; always compile it in automation**

```swift
func testMixedHistoryShowsIndependentStatusAndOnlyFailedRetry() {
    let app = XCUIApplication()
    app.launchArguments += ["--ui-test-fixture", "mixed-history"]
    app.launch()
    app.buttons["history.show"].click()
    let id = "11111111-2222-3333-4444-555555555555"

    XCTAssertEqual(app.descendants(matching: .any)["history.status.appleNotes.\(id)"].label, "Apple Notes delivery status: Delivered")
    XCTAssertEqual(app.descendants(matching: .any)["history.status.notion.\(id)"].label, "Notion delivery status: Failed")
    XCTAssertFalse(app.buttons["history.retry.appleNotes.\(id)"].exists)
    XCTAssertTrue(app.buttons["history.retry.notion.\(id)"].exists)
}
```

- [ ] **Step 5: Replace the raw floating-point duration with mode, compact duration, and a localized completion date**

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(session.titleSnapshot).font(.headline)
    Text("\(SessionPresentation.modeText(session.mode)) · \(SessionPresentation.compactDurationText(for: session.duration))")
        .foregroundStyle(.secondary)
    Text(session.completedAt, format: .dateTime.day().month().year().hour().minute())
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 6: Render each destination as a labeled status and show Retry only for failure**

```swift
let presentation = DeliveryStatusPresentation.make(from: record)
Label(presentation.text, systemImage: presentation.systemImage)
    .accessibilityLabel("\(name) delivery status: \(presentation.text)")
    .accessibilityIdentifier("history.status.\(destination.rawValue).\(session.id.uuidString)")

if presentation.canRetry {
    Button("Retry") { model.retryDelivery(sessionID: session.id, destination: destination) }
        .accessibilityLabel("Retry \(name) delivery")
        .accessibilityIdentifier("history.retry.\(destination.rawValue).\(session.id.uuidString)")
}
```

Use semantic foreground styles for the role, but keep the label and symbol as the primary meaning.

- [ ] **Step 7: Improve the empty state copy without inventing data or actions**

Use `ContentUnavailableView("No Completed Sessions", systemImage: "clock", description: Text("Completed stopwatch and timer sessions will appear here."))`.

- [ ] **Step 8: Run focused and full unit tests, compile UI tests, inspect the deterministic mixed row, then hand the exact files to `github_manager`**

```bash
git add ProductivityTime/Debug/UITestAppModelFactory.swift ProductivityTime/Features/History/HistoryView.swift ProductivityTime/App/AppModel.swift ProductivityTime.xcodeproj/project.pbxproj ProductivityTimeTests/Features/SessionPresentationTests.swift ProductivityTimeUITests/ProductivityTimeUITests.swift
git commit -m "feat: improve session history presentation"
git push origin feat/ui-refresh
```

---

### Task 5: Show Connection Test Progress and Results in Settings

**Files:**
- Modify: `ProductivityTime/App/AppModel.swift`
- Modify: `ProductivityTime/Features/Settings/SettingsView.swift`
- Modify: `ProductivityTime/Integrations/Notifications/NotificationScheduler.swift`
- Modify: `ProductivityTimeTests/App/DeliveryCompositionTests.swift`
- Modify: `ProductivityTimeTests/App/AppModelTests.swift`
- Modify: `ProductivityTimeTests/Integrations/IntegrationAdapterTests.swift`
- Modify: `ProductivityTimeUITests/ProductivityTimeUITests.swift`

**Interfaces:**
- Produces: `enum ConnectionTestState: Equatable { case idle, testing, succeeded, failed }`.
- Produces: `enum NotificationAuthorizationState: Equatable, Sendable { case notDetermined, denied, authorized }` and `NotificationScheduling.authorizationState()`.
- Produces: `AppModel.notesConnectionTestState` and `AppModel.notionConnectionTestState` as read-only published state.
- Produces: `AppModel.testNotesConnection()` and `testNotionConnection()` return their in-flight `Task<Void, Never>`; repeated calls while one is running return the same operation and do not duplicate delivery attempts.
- Preserves: an empty token field leaves the existing Keychain token unchanged; token deletion occurs only through `removeNotionToken()`; token values never enter published state, labels, logs, or screenshots.

- [ ] **Step 1: Write model tests for testing, success, and sanitized failure state**

```swift
func testNotesConnectionPublishesProgressThenSuccess() async throws {
    let notes = SuspendedNotesSink()
    let model = AppModel(
        repository: CompositionRepository(),
        clock: TestClock(date: .now),
        refreshScheduler: CompositionRefreshScheduler(),
        deliveryCoordinator: CompositionCoordinator(),
        preferences: MemoryPreferences(),
        credentialStore: MemoryCredentials(),
        notesSink: notes,
        notionSink: SuccessfulNotionSink()
    )

    let operation = model.testNotesConnection()
    await notes.waitUntilTestStarted()
    XCTAssertEqual(model.notesConnectionTestState, .testing)

    await notes.finishSuccessfully()
    await operation.value
    XCTAssertEqual(model.notesConnectionTestState, .succeeded)
}

func testNotionConnectionFailurePublishesOnlySanitizedFailureState() async throws {
    let notion = FailingNotionSink(error: DeliveryError.authorization)
    let model = AppModel(
        repository: CompositionRepository(),
        clock: TestClock(date: .now),
        refreshScheduler: CompositionRefreshScheduler(),
        deliveryCoordinator: CompositionCoordinator(),
        preferences: MemoryPreferences(),
        credentialStore: MemoryCredentials(),
        notesSink: SuccessfulNotesSink(),
        notionSink: notion
    )

    let operation = model.testNotionConnection()
    await operation.value

    XCTAssertEqual(model.notionConnectionTestState, .failed)
    XCTAssertFalse(model.lastError?.contains("secret") == true)
}

func testRepeatedConnectionClicksShareOneOperationAndOneDeliveryAttempt() async throws {
    let notes = SuspendedNotesSink()
    let coordinator = CompositionCoordinator()
    let model = AppModel(
        repository: CompositionRepository(),
        clock: TestClock(date: .now),
        refreshScheduler: CompositionRefreshScheduler(),
        deliveryCoordinator: coordinator,
        preferences: MemoryPreferences(),
        credentialStore: MemoryCredentials(),
        notesSink: notes,
        notionSink: SuccessfulNotionSink()
    )

    let first = model.testNotesConnection()
    let second = model.testNotesConnection()
    await notes.waitUntilTestStarted()
    await notes.finishSuccessfully()
    await first.value
    await second.value

    let connectionCallCount = await notes.connectionCallCount
    XCTAssertEqual(connectionCallCount, 1)
    XCTAssertEqual(coordinator.destinations, [.appleNotes])
}
```

Add these deterministic sink doubles in the same test file:

```swift
private actor SuspendedNotesSink: NotesSessionSink {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var connectionCallCount = 0

    func deliver(_ session: CompletedSession, to target: NotesTarget) async throws -> DeliveryResult { .created }
    func testConnection(to target: NotesTarget) async throws {
        connectionCallCount += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilTestStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finishSuccessfully() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuccessfulNotionSink: NotionSessionSink {
    func deliver(_ session: CompletedSession, configuration: NotionConfiguration) async throws -> DeliveryResult { .created }
    func testConnection(configuration: NotionConfiguration) async throws {}
}

private actor FailingNotionSink: NotionSessionSink {
    let error: DeliveryError
    init(error: DeliveryError) { self.error = error }
    func deliver(_ session: CompletedSession, configuration: NotionConfiguration) async throws -> DeliveryResult { throw error }
    func testConnection(configuration: NotionConfiguration) async throws { throw error }
}
```

- [ ] **Step 2: Add failing tests for Keychain-preserving empty input, explicit removal, and notification state**

```swift
func testEmptyTokenInputPreservesStoredCredentialUntilExplicitRemoval() throws {
    let credentials = MemoryCredentials()
    let model = AppModel(
        repository: CompositionRepository(),
        clock: TestClock(date: .now),
        refreshScheduler: CompositionRefreshScheduler(),
        deliveryCoordinator: CompositionCoordinator(),
        preferences: MemoryPreferences(),
        credentialStore: credentials
    )

    try model.updateNotionToken("first-token")
    try model.updateNotionToken("   ")
    XCTAssertTrue(model.isNotionTokenConfigured)
    XCTAssertEqual(credentials.writeCount, 1)
    XCTAssertEqual(credentials.removeCount, 0)

    try model.updateNotionToken("replacement-token")
    XCTAssertEqual(credentials.writeCount, 2)
    try model.removeNotionToken()
    XCTAssertFalse(model.isNotionTokenConfigured)
    XCTAssertEqual(credentials.removeCount, 1)
}

func testRefreshingNotificationAuthorizationPublishesDeniedState() async {
    let notifications = RecordingNotificationScheduler(granted: false)
    let model = AppModel(
        repository: InMemorySessionRepository(),
        clock: TestClock(date: .now),
        refreshScheduler: TestRefreshScheduler(),
        notificationScheduler: notifications
    )

    await model.refreshNotificationAuthorizationState().value
    XCTAssertEqual(model.notificationAuthorizationState, .denied)
}
```

- [ ] **Step 3: Run the focused tests and verify the new state and credential semantics are missing**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:ProductivityTimeTests/DeliveryCompositionTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because connection-test state, notification authorization state, explicit token removal, and the updated empty-input semantics do not exist.

- [ ] **Step 4: Add independent, coalesced connection-test operations to `AppModel`**

```swift
enum ConnectionTestState: Equatable { case idle, testing, succeeded, failed }

@Published private(set) var notesConnectionTestState: ConnectionTestState = .idle
@Published private(set) var notionConnectionTestState: ConnectionTestState = .idle
private var notesConnectionTestTask: Task<Void, Never>?
private var notionConnectionTestTask: Task<Void, Never>?
```

Each method returns the existing task when its destination is already testing. Otherwise it sets only that destination to `.testing`, creates and stores one task, awaits the connection test and that destination's pending-delivery attempt, sets `.succeeded`, then clears the stored task. On error it sets `.failed`, calls the existing sanitized error recorder, and clears the task. Configuration changes reset only their related destination to `.idle`.

- [ ] **Step 5: Make empty token input preserve Keychain state and add explicit removal**

```swift
func updateNotionToken(_ rawValue: String) throws {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    do {
        try credentialStore.writeToken(Data(value.utf8))
        isNotionTokenConfigured = true
    } catch {
        lastError = "Notion token could not be updated. Check Keychain access and try again."
        throw error
    }
}

func removeNotionToken() throws {
    do {
        try credentialStore.removeToken()
        isNotionTokenConfigured = false
    } catch {
        lastError = "Notion token could not be updated. Check Keychain access and try again."
        throw error
    }
}
```

`SettingsView.saveNotionSettings()` always saves the data-source ID, calls `updateNotionToken` only when the trimmed field is nonempty, and clears the field after success. Its Remove button calls only `removeNotionToken()`.

- [ ] **Step 6: Extend the notification boundary and publish permission state**

```swift
enum NotificationAuthorizationState: Equatable, Sendable { case notDetermined, denied, authorized }

protocol NotificationCenterClient: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func add(_ request: TimerNotificationRequest) async throws
    func remove(identifiers: [String]) async
}

protocol NotificationScheduling: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func schedule(identifier: String, at deadline: Date, title: String) async throws
    func remove(identifier: String) async
}
```

Map macOS `UNAuthorizationStatus.authorized` and `.provisional` to `.authorized`; map `.denied` to `.denied`; map `.notDetermined` and `@unknown default` to `.notDetermined`. Add `@Published private(set) var notificationAuthorizationState` to `AppModel`, return an awaitable task from `refreshNotificationAuthorizationState()`, and update the same property after timer authorization requests. Update both existing notification test doubles for the new method.

- [ ] **Step 7: Recompose Settings into three clear sections with inline status**

```swift
Section("Apple Notes") {
    TextField("Target note", text: $notesTargetName)
    HStack {
        Button("Save") { saveNotesTarget() }
        Button("Test Connection") { model.testNotesConnection() }
            .disabled(model.notesConnectionTestState == .testing)
        connectionStatus(model.notesConnectionTestState)
    }
}
```

Use the same layout for Notion, keep `SecureField`, clear `notionToken` after save, and show only `Token configured` or `Token not configured`. `connectionStatus` uses ProgressView for testing, `checkmark.circle` plus `Connected` for success, and `exclamationmark.triangle` plus `Connection failed` for failure.

Add a Notifications section that calls `refreshNotificationAuthorizationState()` in `.task` and displays `Not requested`, `Allowed`, or `Denied` with a symbol. When denied, show concise guidance to enable notifications in System Settings; notification denial never disables local timers or external delivery.

- [ ] **Step 8: Add accessibility identifiers for all status values and compile UI tests**

Use `settings.notes.status`, `settings.notion.status`, and `settings.notifications.status`. Verify no accessibility value contains the Notion token or data-source response body.

- [ ] **Step 9: Run focused and full unit tests, inspect the Settings window at its natural size, then hand the exact files to `github_manager`**

```bash
git add ProductivityTime/App/AppModel.swift ProductivityTime/Features/Settings/SettingsView.swift ProductivityTime/Integrations/Notifications/NotificationScheduler.swift ProductivityTimeTests/App/DeliveryCompositionTests.swift ProductivityTimeTests/App/AppModelTests.swift ProductivityTimeTests/Integrations/IntegrationAdapterTests.swift ProductivityTimeUITests/ProductivityTimeUITests.swift
git commit -m "feat: surface integration connection state"
git push origin feat/ui-refresh
```

---

### Task 6: Accessibility, Regression, and Visual Verification

**Files:**
- Modify only when a verification finding requires it: `ProductivityTime/App/ContentView.swift`, `ProductivityTime/Features/Activities/ActivityListView.swift`, `ProductivityTime/Features/Timer/TimerPanelView.swift`, `ProductivityTime/Features/History/HistoryView.swift`, `ProductivityTime/Features/Settings/SettingsView.swift`
- Modify only when a regression assertion is needed: `ProductivityTimeUITests/ProductivityTimeUITests.swift`, `ProductivityTimeTests/Features/SessionPresentationTests.swift`, `ProductivityTimeTests/App/DeliveryCompositionTests.swift`

**Interfaces:**
- Consumes: all UI and presentation work from Tasks 1–5.
- Produces: no new product interface; this task closes visual, accessibility, build, privacy, and regression gates.

- [ ] **Step 1: Run the complete unit test target**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:ProductivityTimeTests CODE_SIGNING_ALLOWED=NO
```

Expected: all `ProductivityTimeTests` pass.

- [ ] **Step 2: Compile the app and UI test runner, then build Release**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project ProductivityTime.xcodeproj -scheme ProductivityTime -configuration Release -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: both commands exit 0. Do not launch the unsigned UI runner that previously triggered a misleading Gatekeeper alert.

- [ ] **Step 3: Run signed UI tests from Xcode when a valid local signing context is available**

Exercise activity creation, empty state, stopwatch start/pause/complete, timer start/cancel, history opening, Settings through Command-Comma, and restore/discard. Expected: all assertions pass and timer/stopwatch session semantics remain unchanged.

- [ ] **Step 4: Audit the five key screens with Accessibility Inspector**

Inspect no-activity, stopwatch running, timer paused, mixed delivery history, and Notion Settings. Run audit with VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency, and Differentiate Without Color. Expected: no unlabeled interactive element, clipped primary text, color-only state, unreachable button, or missing focus ring.

- [ ] **Step 5: Inspect visual behavior through `mcp__cua_repl`**

Check 720×460 and 1000×640 windows in light and dark appearance. Confirm the sidebar remains usable, the counter does not clip, history statuses align, the Settings window opens independently, and sheets do not hide a running counter state.

- [ ] **Step 6: Inspect the diff and repository for privacy and scope**

```bash
git diff --check
git status --short
git diff --stat
rg -n --hidden -g '!DerivedData/**' -g '!.git/**' '(secret|token|Authorization: Bearer|notionToken\s*=\s*"[^"\n]+")' .
```

Expected: no whitespace errors, generated files, credentials, captured private activity names, or unrelated modifications.

- [ ] **Step 7: Route material findings to the owning implementer, rerun Steps 1–6, request the required read-only security review, and hand an exact reviewed file list to `github_manager`**

The final review covers correctness, secrets, permissions, unsafe automation, data leakage, injection, concurrency, persistence, regressions, and missing tests. Every material finding receives a targeted fix, fresh verification, and a follow-up security review before completion.

`github_manager` first runs `git diff --name-only` and `git status --short`. It stages only the exact files changed to resolve accepted Task 6 findings, inspects `git diff --cached`, commits them as `fix: close UI refresh review findings`, verifies the active branch is `feat/ui-refresh`, and runs `git push origin feat/ui-refresh`. It must not stage a directory or any unchanged file from the fixed list of possible files above.

If verification produces no code or test change, do not create an empty commit; record the fresh command results in the final implementation report.
