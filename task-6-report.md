# Task 6 follow-up: stopwatch outcome copy

## Changes

- `ProductivityTime/Features/Timer/TimerPanelView.swift`: show concise guidance while a stopwatch session is active: “Complete to record this session. Discard to cancel without saving.” Existing actions and timer behavior are unchanged.
- `ProductivityTimeUITests/ProductivityTimeUITests.swift`: assert that the guidance is visible for an active stopwatch.

## Verification

- `git diff --check` — passed with no output.
- `rg -n "Complete to record this session\\. Discard to cancel without saving\\." ProductivityTime/Features/Timer/TimerPanelView.swift ProductivityTimeUITests/ProductivityTimeUITests.swift` — found the view copy at line 32 and its UI assertion at line 103.
- Focused UI test command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:ProductivityTimeUITests/ProductivityTimeUITests/testTimerPanelExplainsEmptyStateAndContextualActions CODE_SIGNING_ALLOWED=NO`
  — exited 133 before reporting a test result. Xcode reported that CoreSimulatorService was unavailable and sandboxing prevented opening its CoreSimulator log in the user Library. The new assertion did not run.
- Build-for-testing command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project ProductivityTime.xcodeproj -scheme ProductivityTime -destination 'platform=macOS' -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO`
  — exited 65. Compilation failed because `SwiftDataMacros.PersistentModelMacro` produced a malformed response from `swift-plugin-server`, causing dependent `PersistentModel` conformance errors.

## Remaining risk

The focused UI assertion and app build could not be verified in this environment due to Xcode/CoreSimulator and SwiftData macro-plugin failures. No timer or stopwatch action implementation was changed.
