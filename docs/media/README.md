# GitHub demo media

`productivity-time-demo.gif` is the animated README preview. `productivity-time-demo.mp4` is the higher quality version. Both are rendered from five real app screenshots with English captions.

To refresh them, build and launch the DEBUG-only, in-memory UI fixture, then capture the five walkthrough states manually into `.build/demo-captures/` as `01.png` through `05.png`. Capture order: activities, paused stopwatch, completed-session History, timer presets, mixed History. The fixture is opt-in and never stored with normal app data. Its delivery coordinator is a no-op and its credentials are in memory, so captures do not require secrets or write to Apple Notes or Notion. Captures stay in the ignored `.build` directory.

The project’s app target configuration does not define the `DEBUG` compilation condition by default, so include it explicitly when building the fixture:

```sh
xcodebuild \
  -project ProductivityTime.xcodeproj \
  -scheme ProductivityTime \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DemoDerivedData \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG \
  build
open -a .build/DemoDerivedData/Build/Products/Debug/ProductivityTime.app --args --ui-test-fixture mixed-history
```

The `mixed-history` fixture seeds the History view with one example Apple Notes success and one Notion failure. It is held in an in-memory SwiftData container and does not persist after the app quits.

To re-render the checked-in media after the manual captures are in place, run this from the repository root:

```sh
mkdir -p .build/swift-module-cache .build/clang-scanner-cache .build/sdk-module-cache
swift \
  -module-cache-path .build/swift-module-cache \
  -clang-scanner-module-cache-path .build/clang-scanner-cache \
  -sdk-module-cache-path .build/sdk-module-cache \
  scripts/render-github-demo.swift
```

The script writes 1200×850 frames in `.build/github-demo/`, plus both final files in this directory. It requires Swift with the macOS SDK and `ffmpeg` on `PATH`. The 20 second GIF is rendered at 12 fps and checked against an 8 MB size target; the MP4 uses H.264 with `yuv420p` for broad playback support.

Captions follow the app's current UI: named activities, stopwatch pause and resume, explicit completion to record a stopwatch, timer presets, and separate Apple Notes and Notion delivery status. The History scenes carry a small “Demo data” note because the displayed delivery states are fixture examples.
