# fatcat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS background app that displays a transparent video of a fat orange cat over the screen for a 5-minute Pomodoro break after 25 minutes of active work.

**Architecture:** Single-file SwiftPM executable. Six small Swift files: `Config` (constants), `BreakScheduler` (1Hz state machine, idle-aware), `CatWindow` (transparent screen-saver-level NSWindow), `CatPlayer` (looping AVPlayer), `TimerLabel` (big white M:SS countdown), `main.swift` (wiring, fans out across `NSScreen.screens`). The cat is real footage with the background removed (rembg) and re-encoded as HEVC-with-alpha so AVPlayer can render it transparently.

**Tech Stack:**
- Swift 5.9+ on macOS 13+ (AppKit + AVKit + Combine)
- SwiftPM (no Xcode project)
- yt-dlp + ffmpeg + rembg (Python) for the asset pipeline
- git-lfs for committing the `cat.mov` asset
- XCTest for unit tests

**Reference:** [Design spec](../specs/2026-04-27-fat-cat-break-app-design.md)

---

## File Structure

| File | Responsibility | Created in task |
|---|---|---|
| `Package.swift` | SwiftPM manifest, executable target `fatcat`, test target `fatcatTests` | Task 1 |
| `Sources/fatcat/main.swift` | Entry point, wiring, fan-out across screens, App Nap | Task 1, expanded in Tasks 11, 16, 17, 18 |
| `Sources/fatcat/Config.swift` | All tunable constants (durations, asset path, poll rate) | Task 2 |
| `Sources/fatcat/BreakScheduler.swift` | 1Hz state machine, idle-aware accumulator, callback fan-out. `realIdleSource` and `realTimer` helpers live here. | Task 3 (skeleton), 4–9 (TDD logic) |
| `Sources/fatcat/CatWindow.swift` | Transparent borderless `NSWindow` subclass at `.screenSaver` level | Task 10 |
| `Sources/fatcat/TimerLabel.swift` | Styled `NSTextField` showing `M:SS` countdown | Task 11 |
| `Sources/fatcat/CatPlayer.swift` | Wraps `AVPlayer` + `AVPlayerView`, loops the cat video | Task 15 |
| `Tests/fatcatTests/BreakSchedulerTests.swift` | 6 unit tests with synthetic clock + idle source | Tasks 4–9 |
| `scripts/make-cat-asset.sh` | YouTube → frames → rembg → HEVC-with-alpha pipeline | Task 12 |
| `Assets/cat.mov` | Alpha-HEVC video (LFS-tracked) | Tasks 13, 14 |
| `.gitignore` | `.build/`, `.swiftpm/`, `frames/`, `masked/`, `raw_clip.mp4` | Task 1 |
| `.gitattributes` | `*.mov filter=lfs diff=lfs merge=lfs -text` | Task 14 |
| `README.md` | Usage, install, limitations, Login Items setup | Task 18 |

---

## Task 1: SwiftPM scaffold

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Package.swift`
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`
- Create: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/PlaceholderTests.swift`
- Create: `/Users/neodurden/fun/fatcat/.gitignore`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "fatcat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "fatcat", path: "Sources/fatcat"),
        .testTarget(name: "fatcatTests", dependencies: ["fatcat"], path: "Tests/fatcatTests"),
    ]
)
```

- [ ] **Step 2: Create `Sources/fatcat/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
print("fatcat: scaffold running, press ctrl-c to exit")
app.run()
```

- [ ] **Step 3: Create `Tests/fatcatTests/PlaceholderTests.swift`** (so `swift test` doesn't error)

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func test_placeholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Create `.gitignore`**

```
.build/
.swiftpm/
DerivedData/
frames/
masked/
raw_clip.mp4
.DS_Store
```

- [ ] **Step 5: Build and run, verify scaffold works**

Run from `/Users/neodurden/fun/fatcat`:
```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`

```bash
swift test 2>&1 | tail -5
```
Expected: `Test Suite 'All tests' passed`

```bash
timeout 3 swift run fatcat; echo "exit=$?"
```
Expected: `fatcat: scaffold running, press ctrl-c to exit` printed, then exit code `124` (timeout) — proves the app stays running.

- [ ] **Step 6: Commit**

```bash
cd /Users/neodurden/fun/fatcat
git add Package.swift Sources/ Tests/ .gitignore
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: SwiftPM scaffold with running NSApp loop"
```

---

## Task 2: Config

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/Config.swift`

- [ ] **Step 1: Create `Config.swift`**

```swift
import Foundation

enum Config {
    static let workDuration: TimeInterval = 25 * 60        // 25 min of activity (Pomodoro)
    static let breakDuration: TimeInterval = 5 * 60        // 5 min cat (Pomodoro short break)
    static let idleResetThreshold: TimeInterval = 60       // 1 min idle = pause
    static let assetPath: String = "Assets/cat.mov"        // relative to launch dir
    static let pollInterval: TimeInterval = 1.0            // tick rate
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/fatcat/Config.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: Config with Pomodoro 25/5 defaults"
```

---

## Task 3: BreakScheduler skeleton + helpers

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Create `BreakScheduler.swift` with helpers and an empty class**

```swift
import Foundation
import Combine
import CoreGraphics

func realIdleSource() -> TimeInterval {
    // CGEventType raw value 0 means "any/null event" — returns time since the last event of any kind.
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: 0)!)
}

func realTimer(interval: TimeInterval, _ callback: @escaping () -> Void) -> AnyCancellable {
    let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in callback() }
    RunLoop.main.add(timer, forMode: .common)
    return AnyCancellable { timer.invalidate() }
}

final class BreakScheduler {
    var onBreakStart: (() -> Void)?
    var onBreakTick: ((TimeInterval) -> Void)?
    var onBreakEnd: (() -> Void)?

    private let workDuration: TimeInterval
    private let breakDuration: TimeInterval
    private let idleResetThreshold: TimeInterval
    private let pollInterval: TimeInterval
    private let idleSource: () -> TimeInterval
    private let scheduleTick: (TimeInterval, @escaping () -> Void) -> AnyCancellable

    private var accumulatedActiveSeconds: TimeInterval = 0
    private var breakRemaining: TimeInterval? = nil
    private var ticker: AnyCancellable? = nil

    init(
        workDuration: TimeInterval = Config.workDuration,
        breakDuration: TimeInterval = Config.breakDuration,
        idleResetThreshold: TimeInterval = Config.idleResetThreshold,
        pollInterval: TimeInterval = Config.pollInterval,
        idleSource: @escaping () -> TimeInterval = realIdleSource,
        scheduleTick: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable = realTimer
    ) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.idleResetThreshold = idleResetThreshold
        self.pollInterval = pollInterval
        self.idleSource = idleSource
        self.scheduleTick = scheduleTick
    }

    func start() {
        ticker = scheduleTick(pollInterval) { [weak self] in self?.tick() }
    }

    func tick() {
        // To be implemented in Tasks 4-9 via TDD
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: BreakScheduler skeleton with realIdleSource/realTimer helpers"
```

---

## Task 4: TDD test 1 — accumulates active seconds when not idle

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/PlaceholderTests.swift` → rename to `BreakSchedulerTests.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Delete placeholder test, create `BreakSchedulerTests.swift` with the first test and the `TestClock` + `TestIdleSource` infrastructure**

```bash
rm /Users/neodurden/fun/fatcat/Tests/fatcatTests/PlaceholderTests.swift
```

Write `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`:

```swift
import XCTest
import Combine
@testable import fatcat

final class TestClock {
    private(set) var callback: (() -> Void)?

    func schedule(_ interval: TimeInterval, _ callback: @escaping () -> Void) -> AnyCancellable {
        self.callback = callback
        return AnyCancellable { [weak self] in self?.callback = nil }
    }

    func advance(ticks: Int) {
        for _ in 0..<ticks { callback?() }
    }
}

final class TestIdleSource {
    var seconds: TimeInterval = 0
    func read() -> TimeInterval { seconds }
}

final class BreakSchedulerTests: XCTestCase {
    func test_accumulates_active_seconds_when_not_idle() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 0

        var startCount = 0
        let scheduler = BreakScheduler(
            workDuration: 10,
            breakDuration: 3,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.onBreakStart = { startCount += 1 }
        scheduler.start()

        clock.advance(ticks: 5)

        XCTAssertEqual(startCount, 0, "Should not have started a break yet")
    }
}
```

- [ ] **Step 2: Run test, verify it fails (because tick() is empty so no logic runs — test passes trivially? Let me check)**

```bash
swift test --filter BreakSchedulerTests.test_accumulates 2>&1 | tail -10
```

Expected: This actually passes vacuously — `tick()` does nothing, so `startCount` is 0 and the assertion holds. To make this a meaningful failing test, add an assertion that we *did* tick (verify accumulator state via a stronger test below). Update the test to also assert "after enough ticks, a break *would* fire if we ran long enough" — but that requires implementing tick first.

A cleaner approach: combine this test with the next one (Task 5) so we have a falsifiable assertion immediately. Or, expose `accumulatedActiveSeconds` for testing. Let me expose it.

Update `BreakScheduler.swift`: change `private var accumulatedActiveSeconds` to `private(set) var accumulatedActiveSeconds`.

Update the test to assert:
```swift
        XCTAssertEqual(scheduler.accumulatedActiveSeconds, 5, "Should accumulate 5 seconds of active time")
```

- [ ] **Step 3: Run test, verify it now fails**

```bash
swift test --filter BreakSchedulerTests.test_accumulates 2>&1 | tail -10
```
Expected: FAIL with `XCTAssertEqual failed: ("0.0") is not equal to ("5.0")`.

- [ ] **Step 4: Implement minimal `tick()` to make it pass**

In `BreakScheduler.swift`, replace `func tick() { }` body:

```swift
    func tick() {
        accumulatedActiveSeconds += pollInterval
    }
```

- [ ] **Step 5: Run test, verify it passes**

```bash
swift test --filter BreakSchedulerTests.test_accumulates 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler accumulates active seconds when not idle"
```

---

## Task 5: TDD test 2 — pauses accumulator when idle above threshold

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Add the failing test**

Append to `BreakSchedulerTests.swift`:

```swift
    func test_pauses_accumulator_when_idle_above_threshold() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 120  // way above threshold

        let scheduler = BreakScheduler(
            workDuration: 10,
            breakDuration: 3,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.start()

        clock.advance(ticks: 5)

        XCTAssertEqual(scheduler.accumulatedActiveSeconds, 0, "Should not accumulate while idle")
    }
```

- [ ] **Step 2: Run test, verify it fails**

```bash
swift test --filter BreakSchedulerTests.test_pauses 2>&1 | tail -10
```
Expected: FAIL with `("5.0") is not equal to ("0.0")`.

- [ ] **Step 3: Implement idle check**

In `BreakScheduler.swift`, replace `tick()`:

```swift
    func tick() {
        let idle = idleSource()
        if idle >= idleResetThreshold {
            return
        }
        accumulatedActiveSeconds += pollInterval
    }
```

- [ ] **Step 4: Run all BreakScheduler tests**

```bash
swift test --filter BreakSchedulerTests 2>&1 | tail -10
```
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler pauses accumulator when idle above threshold"
```

---

## Task 6: TDD test 3 — fires onBreakStart when workDuration reached

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Add the failing test**

Append to `BreakSchedulerTests.swift`:

```swift
    func test_fires_onBreakStart_when_workDuration_reached() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 0

        var startCount = 0
        let scheduler = BreakScheduler(
            workDuration: 5,
            breakDuration: 3,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.onBreakStart = { startCount += 1 }
        scheduler.start()

        clock.advance(ticks: 5)
        XCTAssertEqual(startCount, 1, "Should fire onBreakStart exactly once at workDuration")

        clock.advance(ticks: 1)
        XCTAssertEqual(startCount, 1, "Should not fire again on subsequent ticks while in break")
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
swift test --filter BreakSchedulerTests.test_fires_onBreakStart 2>&1 | tail -10
```
Expected: FAIL with `("0") is not equal to ("1")`.

- [ ] **Step 3: Implement transition to break state**

In `BreakScheduler.swift`, replace `tick()`:

```swift
    func tick() {
        if breakRemaining != nil {
            // In break — handled in Task 7
            return
        }
        let idle = idleSource()
        if idle >= idleResetThreshold {
            return
        }
        accumulatedActiveSeconds += pollInterval
        if accumulatedActiveSeconds >= workDuration {
            breakRemaining = breakDuration
            onBreakStart?()
        }
    }
```

- [ ] **Step 4: Run all tests**

```bash
swift test --filter BreakSchedulerTests 2>&1 | tail -10
```
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler fires onBreakStart at workDuration"
```

---

## Task 7: TDD test 4 — decrements breakRemaining during break

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Add the failing test**

Append to `BreakSchedulerTests.swift`:

```swift
    func test_decrements_breakRemaining_during_break() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 0

        var lastTickValue: TimeInterval? = nil
        let scheduler = BreakScheduler(
            workDuration: 1,           // tiny so we enter break after 1 tick
            breakDuration: 10,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.onBreakTick = { lastTickValue = $0 }
        scheduler.start()

        clock.advance(ticks: 1)        // triggers onBreakStart, enters break
        clock.advance(ticks: 3)        // 3 break ticks: 10 → 9 → 8 → 7

        XCTAssertEqual(lastTickValue, 7, "Last onBreakTick should fire with 7 (10 - 3)")
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
swift test --filter BreakSchedulerTests.test_decrements 2>&1 | tail -10
```
Expected: FAIL with `("nil") is not equal to ("Optional(7.0)")`.

- [ ] **Step 3: Implement break-tick decrement**

In `BreakScheduler.swift`, replace `tick()`:

```swift
    func tick() {
        if var remaining = breakRemaining {
            remaining -= pollInterval
            if remaining <= 0 {
                // Handled in Task 8
                return
            }
            breakRemaining = remaining
            onBreakTick?(remaining)
            return
        }
        let idle = idleSource()
        if idle >= idleResetThreshold {
            return
        }
        accumulatedActiveSeconds += pollInterval
        if accumulatedActiveSeconds >= workDuration {
            breakRemaining = breakDuration
            onBreakStart?()
        }
    }
```

- [ ] **Step 4: Run all tests**

```bash
swift test --filter BreakSchedulerTests 2>&1 | tail -10
```
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler decrements breakRemaining during break"
```

---

## Task 8: TDD test 5 — fires onBreakEnd and resets at break completion

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/BreakScheduler.swift`

- [ ] **Step 1: Add the failing test**

Append to `BreakSchedulerTests.swift`:

```swift
    func test_fires_onBreakEnd_and_resets_when_break_completes() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 0

        var endCount = 0
        let scheduler = BreakScheduler(
            workDuration: 1,
            breakDuration: 3,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.onBreakEnd = { endCount += 1 }
        scheduler.start()

        clock.advance(ticks: 1)        // enter break, breakRemaining=3
        clock.advance(ticks: 3)        // 3 → 2 → 1 → 0 (onBreakEnd fires on the 0 tick)

        XCTAssertEqual(endCount, 1, "onBreakEnd should fire exactly once")
        XCTAssertEqual(scheduler.accumulatedActiveSeconds, 0, "Accumulator should reset to 0")
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
swift test --filter BreakSchedulerTests.test_fires_onBreakEnd 2>&1 | tail -10
```
Expected: FAIL with `("0") is not equal to ("1")`.

- [ ] **Step 3: Implement break-end transition**

In `BreakScheduler.swift`, replace `tick()`:

```swift
    func tick() {
        if var remaining = breakRemaining {
            remaining -= pollInterval
            if remaining <= 0 {
                breakRemaining = nil
                accumulatedActiveSeconds = 0
                onBreakEnd?()
                return
            }
            breakRemaining = remaining
            onBreakTick?(remaining)
            return
        }
        let idle = idleSource()
        if idle >= idleResetThreshold {
            return
        }
        accumulatedActiveSeconds += pollInterval
        if accumulatedActiveSeconds >= workDuration {
            breakRemaining = breakDuration
            onBreakStart?()
        }
    }
```

- [ ] **Step 4: Run all tests**

```bash
swift test --filter BreakSchedulerTests 2>&1 | tail -10
```
Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift Sources/fatcat/BreakScheduler.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler fires onBreakEnd and resets accumulator"
```

---

## Task 9: TDD test 6 — transition to working state allows new accumulation

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Tests/fatcatTests/BreakSchedulerTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `BreakSchedulerTests.swift`:

```swift
    func test_transition_to_working_clears_breakRemaining() {
        let clock = TestClock()
        let idle = TestIdleSource()
        idle.seconds = 0

        let scheduler = BreakScheduler(
            workDuration: 1,
            breakDuration: 3,
            idleResetThreshold: 60,
            pollInterval: 1,
            idleSource: idle.read,
            scheduleTick: clock.schedule
        )
        scheduler.start()

        clock.advance(ticks: 1)        // enter break
        clock.advance(ticks: 3)        // exit break, accumulator reset to 0
        clock.advance(ticks: 1)        // back in working state, accumulate 1s

        XCTAssertEqual(scheduler.accumulatedActiveSeconds, 1, "Should be back in working state, accumulating again")
    }
```

- [ ] **Step 2: Run, verify it passes (logic from Task 8 already supports this)**

```bash
swift test --filter BreakSchedulerTests.test_transition 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 3: Run all 6 BreakScheduler tests**

```bash
swift test --filter BreakSchedulerTests 2>&1 | tail -15
```
Expected: 6 PASS, 0 FAIL.

- [ ] **Step 4: Commit**

```bash
git add Tests/fatcatTests/BreakSchedulerTests.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "test: BreakScheduler returns to working state after break ends"
```

---

## Task 10: CatWindow with placeholder background

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/CatWindow.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`

- [ ] **Step 1: Create `CatWindow.swift`**

```swift
import AppKit

final class CatWindow: NSWindow {
    init(for screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.alphaValue = 0
        // Debug: semi-transparent red so we can see the window during dev
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.red.withAlphaComponent(0.4).cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func reveal() {
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            self.animator().alphaValue = 1.0
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
```

- [ ] **Step 2: Update `main.swift` to reveal a CatWindow for 5 seconds at startup**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = CatWindow(for: NSScreen.main!)
window.reveal()
print("fatcat: showing red placeholder for 5s, then dismissing")

DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
    window.dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        print("fatcat: done, exiting")
        exit(0)
    }
}

app.run()
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 4: Run and eyeball-verify**

```bash
swift run fatcat
```

Verify visually:
- A semi-transparent red rectangle covers the entire main screen for 5 seconds
- The red overlay sits on top of all apps including a fullscreen window (open Safari fullscreen first to verify)
- Mouse clicks pass through (try clicking a button under it — should fire)
- Active app's title bar stays focused (no focus theft)
- After 5 seconds, the red fades out and the app exits

If any check fails, debug before committing.

- [ ] **Step 5: Commit**

```bash
git add Sources/fatcat/CatWindow.swift Sources/fatcat/main.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: CatWindow transparent screen-saver-level overlay (placeholder bg)"
```

---

## Task 11: TimerLabel overlaid on the window

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/TimerLabel.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`

- [ ] **Step 1: Create `TimerLabel.swift`**

```swift
import AppKit

final class TimerLabel: NSTextField {
    init(frame: NSRect) {
        super.init(frame: frame)
        self.isEditable = false
        self.isSelectable = false
        self.isBordered = false
        self.drawsBackground = false
        self.textColor = .white
        self.font = NSFont.monospacedDigitSystemFont(ofSize: 180, weight: .bold)
        self.alignment = .left
        self.stringValue = "0:00"
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func setRemaining(_ seconds: TimeInterval) {
        let total = Int(seconds.rounded(.up))
        let m = total / 60
        let s = total % 60
        self.stringValue = String(format: "%d:%02d", m, s)
    }
}
```

- [ ] **Step 2: Update `main.swift` to overlay a hard-coded `5:00` label**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!
let window = CatWindow(for: screen)

let label = TimerLabel(frame: NSRect(
    x: 80,
    y: window.contentView!.bounds.midY - 110,
    width: 600, height: 220
))
label.setRemaining(300)  // 5:00
window.contentView?.addSubview(label)

window.reveal()
print("fatcat: showing red placeholder + 5:00 label for 5s")

DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
    window.dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
}

app.run()
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 4: Run and eyeball-verify**

```bash
swift run fatcat
```

Verify:
- Red overlay appears as before
- A big white `5:00` text appears on the left side, vertically centered
- Text is monospaced and bold (~180pt)
- After 5s, fades out and exits

- [ ] **Step 5: Commit**

```bash
git add Sources/fatcat/TimerLabel.swift Sources/fatcat/main.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: TimerLabel with monospaced 180pt M:SS countdown text"
```

---

## Task 12: Asset pipeline script

**Files:**
- Create: `/Users/neodurden/fun/fatcat/scripts/make-cat-asset.sh`

- [ ] **Step 1: Create the script**

```bash
mkdir -p /Users/neodurden/fun/fatcat/scripts
```

Write `/Users/neodurden/fun/fatcat/scripts/make-cat-asset.sh`:

```bash
#!/usr/bin/env bash
# make-cat-asset.sh — Build Assets/cat.mov from a YouTube clip.
#
# Usage:
#   scripts/make-cat-asset.sh <youtube_url> <start> <end>
# Example:
#   scripts/make-cat-asset.sh "https://youtu.be/abc123" "0:30" "0:42"
#
# Dependencies:
#   - yt-dlp     (brew install yt-dlp)
#   - ffmpeg     (brew install ffmpeg)
#   - rembg      (pipx install rembg)
#
# Output: Assets/cat.mov (HEVC + alpha channel)

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <youtube_url> <start> <end>" >&2
  echo "example: $0 'https://youtu.be/abc123' '0:30' '0:42'" >&2
  exit 1
fi

URL="$1"
START="$2"
END="$3"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Assets

# Clean any previous run
rm -rf raw_clip.mp4 frames masked
mkdir -p frames masked

echo "==> [1/5] yt-dlp: downloading clip ${START}-${END}"
yt-dlp -f "bv[height<=1080][ext=mp4]" \
  --download-sections "*${START}-${END}" \
  -o raw_clip.mp4 "$URL"

echo "==> [2/5] ffmpeg: extracting frames at 30fps"
ffmpeg -loglevel error -i raw_clip.mp4 -r 30 frames/%04d.png

echo "==> [3/5] rembg: removing background from each frame"
for f in frames/*.png; do
  rembg i "$f" "masked/$(basename "$f")"
done

echo "==> [4/5] ffmpeg: encoding HEVC with alpha"
ffmpeg -loglevel error -y -framerate 30 -i masked/%04d.png \
  -c:v hevc_videotoolbox \
  -alpha_quality 0.75 \
  -tag:v hvc1 \
  -pix_fmt yuva420p \
  Assets/cat.mov

echo "==> [5/5] verifying alpha channel"
PIX=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=nw=1:nk=1 Assets/cat.mov)
if [[ "$PIX" != "yuva420p" ]]; then
  echo "ERROR: expected pix_fmt=yuva420p but got '$PIX' — alpha channel missing!" >&2
  exit 1
fi

echo "Done. Assets/cat.mov created with alpha. ($(ls -lh Assets/cat.mov | awk '{print $5}'))"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/neodurden/fun/fatcat/scripts/make-cat-asset.sh
```

- [ ] **Step 3: Verify dependencies are available (don't run yet — just check they exist)**

```bash
which yt-dlp /opt/homebrew/bin/yt-dlp 2>&1 | head -2
which ffmpeg /opt/homebrew/bin/ffmpeg 2>&1 | head -2
which rembg 2>&1 | head -2 || echo "rembg not installed yet — will install in Task 13"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/make-cat-asset.sh
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: asset pipeline script (yt-dlp + rembg + HEVC-alpha)"
```

---

## Task 13: Source the cat.mov asset (manual)

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Assets/cat.mov` (via the pipeline script)

This task requires human judgment for choosing the YouTube clip. The agent should ASK the user for input rather than picking one autonomously.

- [ ] **Step 1: Install rembg if not already installed**

```bash
which rembg || pipx install rembg
```

If `pipx` itself is missing: `brew install pipx && pipx ensurepath` first.

- [ ] **Step 2: Ask the user for a YouTube URL + timestamps**

Present this prompt to the user verbatim:

> "I need a YouTube clip of a fat orange cat to use as the asset. Suggested search terms: 'fat orange cat sitting', 'chunky cat lounging', 'cat walks across desk'. Find a 5–15 second window where the cat is on a relatively clean background with the camera locked off (no panning).
>
> Reply with: `<youtube_url> <start> <end>` — for example:
> `https://youtu.be/abc123 0:30 0:42`"

WAIT for the user's reply. Do not invent a URL.

- [ ] **Step 3: Run the asset pipeline with the user's input**

```bash
cd /Users/neodurden/fun/fatcat
scripts/make-cat-asset.sh "<USER_URL>" "<USER_START>" "<USER_END>"
```

Expected final output: `Done. Assets/cat.mov created with alpha. (X.XM)`

- [ ] **Step 4: Smoke-test the asset**

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt,width,height,codec_name,duration -of default Assets/cat.mov
```
Expected: `codec_name=hevc`, `pix_fmt=yuva420p`, sensible width/height/duration.

```bash
open Assets/cat.mov
```

Eyeball-verify in QuickTime: cat is visible, background is transparent (you should see a checkered transparency pattern, not solid black/white).

If the cat looks bad (clipped edges, wrong segmentation, jittery mask), iterate on this task: try different timestamps or a different YouTube URL. Re-run the script.

- [ ] **Step 5: Do NOT commit yet**

The asset goes in via git-lfs in Task 14. Leave `Assets/cat.mov` uncommitted for now.

---

## Task 14: Set up git-lfs and commit cat.mov

**Files:**
- Create: `/Users/neodurden/fun/fatcat/.gitattributes`
- Add (via LFS): `/Users/neodurden/fun/fatcat/Assets/cat.mov`

- [ ] **Step 1: Install git-lfs**

```bash
which git-lfs || brew install git-lfs
git lfs install   # one-time global hook setup
```
Expected final line: `Git LFS initialized.`

- [ ] **Step 2: Track *.mov via LFS**

```bash
cd /Users/neodurden/fun/fatcat
git lfs track "*.mov"
cat .gitattributes
```
Expected `.gitattributes` content: `*.mov filter=lfs diff=lfs merge=lfs -text`

- [ ] **Step 3: Commit `.gitattributes`**

```bash
git add .gitattributes
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "chore: track *.mov via git-lfs"
```

- [ ] **Step 4: Add and commit the cat asset (routed through LFS)**

```bash
git add Assets/cat.mov
git ls-files --stage Assets/cat.mov   # verify mode 100644 and the SHA points to a small LFS pointer file
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: add cat.mov asset (via git-lfs)"
```

- [ ] **Step 5: Verify the LFS pointer**

```bash
git show HEAD:Assets/cat.mov | head -3
```
Expected output:
```
version https://git-lfs.github.com/spec/v1
oid sha256:...
size <bytes>
```
(NOT raw video bytes — if you see binary garbage, LFS isn't routing the file.)

---

## Task 15: CatPlayer — load and loop the cat video

**Files:**
- Create: `/Users/neodurden/fun/fatcat/Sources/fatcat/CatPlayer.swift`
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/CatWindow.swift` (remove debug red bg)
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`

- [ ] **Step 1: Create `CatPlayer.swift`**

```swift
import AppKit
import AVKit
import AVFoundation

final class CatPlayer {
    let view: AVPlayerView
    private let player: AVPlayer

    init(assetURL: URL) {
        let item = AVPlayerItem(url: assetURL)
        self.player = AVPlayer(playerItem: item)
        self.player.isMuted = true
        self.player.actionAtItemEnd = .none

        self.view = AVPlayerView()
        self.view.player = self.player
        self.view.controlsStyle = .none
        self.view.showsFullScreenToggleButton = false
        self.view.videoGravity = .resizeAspect
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor

        NotificationCenter.default.addObserver(
            self, selector: #selector(loop),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
    }

    @objc private func loop() {
        player.seek(to: .zero)
        player.play()
    }

    func play() { player.play() }
    func pause() { player.pause() }
}
```

- [ ] **Step 2: Remove the debug red background from `CatWindow.swift`**

In `CatWindow.swift`, delete these two lines:
```swift
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.red.withAlphaComponent(0.4).cgColor
```

- [ ] **Step 3: Update `main.swift` to add the cat player to the window**

Replace `main.swift`:

```swift
import AppKit

// stderr helper — must be declared before first use, since top-level
// code in main.swift runs sequentially.
extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        self.write(Data(string.utf8))
    }
}
var standardError = FileHandle.standardError

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!
let window = CatWindow(for: screen)

let assetURL = URL(fileURLWithPath: Config.assetPath,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

guard FileManager.default.fileExists(atPath: assetURL.path) else {
    print("fatcat: ERROR — asset not found at \(assetURL.path)", to: &standardError)
    exit(1)
}

let player = CatPlayer(assetURL: assetURL)
player.view.frame = window.contentView!.bounds
player.view.autoresizingMask = [.width, .height]
window.contentView?.addSubview(player.view)

let label = TimerLabel(frame: NSRect(
    x: 80,
    y: window.contentView!.bounds.midY - 110,
    width: 600, height: 220
))
label.setRemaining(300)
window.contentView?.addSubview(label)

window.reveal()
player.play()
print("fatcat: showing cat + 5:00 label for 10s")

DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
    player.pause()
    window.dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
}

app.run()
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/neodurden/fun/fatcat
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 5: Run and eyeball-verify**

```bash
swift run fatcat
```

Verify:
- The cat appears with a transparent background — your desktop is visible around the cat's silhouette
- The cat loops (if your clip is shorter than 10s, it should restart and play again)
- The big white `5:00` label is overlaid on the left
- After 10s, fades out, app exits

If the cat is opaque (you can't see your desktop around it), the asset's alpha channel was lost — re-run Task 13's stage 5 verification.
If the AVPlayerView is solid black, the `hvc1` tag is wrong — re-run Task 13's pipeline.

- [ ] **Step 6: Commit**

```bash
git add Sources/fatcat/CatPlayer.swift Sources/fatcat/CatWindow.swift Sources/fatcat/main.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: CatPlayer with looping HEVC-alpha video, drop debug bg"
```

---

## Task 16: Wire BreakScheduler to UI (single screen, debug duration)

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/Config.swift` (debug-tweak workDuration)
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`

- [ ] **Step 1: Temporarily set `workDuration = 10` in `Config.swift` for testing**

In `Config.swift`, change:
```swift
    static let workDuration: TimeInterval = 25 * 60        // 25 min of activity (Pomodoro)
```
to:
```swift
    static let workDuration: TimeInterval = 10             // DEBUG — restore to 25 * 60 before shipping
```

- [ ] **Step 2: Replace `main.swift` with the full wired version (single screen for now)**

```swift
import AppKit
import Darwin

var standardError = FileHandle.standardError
extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        self.write(Data(string.utf8))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let assetURL = URL(fileURLWithPath: Config.assetPath,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

guard FileManager.default.fileExists(atPath: assetURL.path) else {
    print("fatcat: ERROR — asset not found at \(assetURL.path)", to: &standardError)
    exit(1)
}

guard let screen = NSScreen.main else {
    print("fatcat: ERROR — NSScreen.main returned nil", to: &standardError)
    exit(1)
}

let window = CatWindow(for: screen)
let player = CatPlayer(assetURL: assetURL)
let label  = TimerLabel(frame: NSRect(
    x: 80,
    y: window.contentView!.bounds.midY - 110,
    width: 600, height: 220
))
player.view.frame = window.contentView!.bounds
player.view.autoresizingMask = [.width, .height]
window.contentView?.addSubview(player.view)
window.contentView?.addSubview(label)

let scheduler = BreakScheduler()
scheduler.onBreakStart = {
    label.setRemaining(Config.breakDuration)
    window.reveal()
    player.play()
    print("fatcat: break started")
}
scheduler.onBreakTick = { remaining in
    label.setRemaining(remaining)
}
scheduler.onBreakEnd = {
    player.pause()
    window.dismiss()
    print("fatcat: break ended")
}

scheduler.start()
print("fatcat: scheduler running, workDuration=\(Config.workDuration)s, breakDuration=\(Config.breakDuration)s")
app.run()
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 4: Run and eyeball-verify the full lifecycle**

```bash
swift run fatcat
```

Verify (don't touch keyboard/mouse aggressively; small movements OK):
- After 10 seconds: cat appears with `5:00` label
- Label counts down `4:59 → 4:58 → ... → 0:00`
- At `0:00`: cat fades out, console prints `break ended`
- After another 10 seconds of activity: cat appears again

ctrl-c to exit when satisfied.

If the cat doesn't appear after 10s of typing, check the App Nap mitigation in Task 18 (will be added next).
If the timer label doesn't update, check that `onBreakTick` is wired and the label is using `setRemaining`.

- [ ] **Step 5: Commit**

```bash
git add Sources/fatcat/Config.swift Sources/fatcat/main.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: wire BreakScheduler to CatWindow/Player/Label (single screen, debug 10s)"
```

---

## Task 17: Multi-monitor fan-out

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift`

- [ ] **Step 1: Replace the single-screen wiring with a per-screen fan-out**

In `main.swift`, replace the section starting from `guard let screen = NSScreen.main` through `scheduler.onBreakEnd = { ... }` with:

```swift
let screens = NSScreen.screens
guard !screens.isEmpty else {
    print("fatcat: ERROR — no screens attached", to: &standardError)
    exit(1)
}

struct Display {
    let window: CatWindow
    let player: CatPlayer
    let label: TimerLabel
}

let displays: [Display] = screens.map { screen in
    let window = CatWindow(for: screen)
    let player = CatPlayer(assetURL: assetURL)
    let label  = TimerLabel(frame: NSRect(
        x: 80,
        y: window.contentView!.bounds.midY - 110,
        width: 600, height: 220
    ))
    player.view.frame = window.contentView!.bounds
    player.view.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(player.view)
    window.contentView?.addSubview(label)
    return Display(window: window, player: player, label: label)
}

print("fatcat: \(displays.count) display(s) attached")

let scheduler = BreakScheduler()
scheduler.onBreakStart = {
    displays.forEach { $0.label.setRemaining(Config.breakDuration); $0.window.reveal(); $0.player.play() }
    print("fatcat: break started on all displays")
}
scheduler.onBreakTick = { remaining in
    displays.forEach { $0.label.setRemaining(remaining) }
}
scheduler.onBreakEnd = {
    displays.forEach { $0.player.pause(); $0.window.dismiss() }
    print("fatcat: break ended")
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Run and eyeball-verify**

```bash
swift run fatcat
```

Verify:
- Console prints `N display(s) attached` matching your monitor count
- After 10s of activity: cat appears on EVERY monitor at the same time, not just the main one
- All timers count down in lockstep
- All cats fade out at `0:00`

If you only have one monitor, this still works — just verifies the fan-out doesn't break the single-screen case.

- [ ] **Step 4: Commit**

```bash
git add Sources/fatcat/main.swift
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: fan out cat overlay across all attached screens"
```

---

## Task 18: App Nap mitigation, restore real durations, README, ship

**Files:**
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/main.swift` (App Nap)
- Modify: `/Users/neodurden/fun/fatcat/Sources/fatcat/Config.swift` (real durations)
- Create: `/Users/neodurden/fun/fatcat/README.md`

- [ ] **Step 1: Add App Nap mitigation to `main.swift`**

In `main.swift`, just after `app.setActivationPolicy(.accessory)`, add:

```swift
// Hold a strong reference to keep App Nap from suspending us.
// Without this, our 1Hz timer can stretch to one tick per 30+ seconds
// because we have no visible UI 99.9% of the time.
let napActivity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .latencyCritical],
    reason: "fatcat scheduler must tick reliably"
)
_ = napActivity   // silence unused-variable warning; ARC keeps it alive via the let binding above
```

- [ ] **Step 2: Restore real durations in `Config.swift`**

Change:
```swift
    static let workDuration: TimeInterval = 10             // DEBUG — restore to 25 * 60 before shipping
```
back to:
```swift
    static let workDuration: TimeInterval = 25 * 60        // 25 min of activity (Pomodoro)
```

- [ ] **Step 3: Create `README.md`**

Write `/Users/neodurden/fun/fatcat/README.md`:

````markdown
# fatcat

A macOS background app that displays a transparent video of a fat orange cat over your screen for a 5-minute break after 25 minutes of active work (Pomodoro). Inspired by [@birdabo's tweet](https://x.com/i/status/2048404010789687315) about a Japanese dev's break-reminder app.

## Setup

```bash
# 1. Clone (with git-lfs to fetch cat.mov)
brew install git-lfs
git lfs install
git clone <repo-url> ~/fun/fatcat
cd ~/fun/fatcat

# 2. Build and run
swift run fatcat
```

## Building your own cat

Replace `Assets/cat.mov` with your own:

```bash
brew install yt-dlp ffmpeg
pipx install rembg
scripts/make-cat-asset.sh "<youtube_url>" "<start>" "<end>"
# e.g. scripts/make-cat-asset.sh "https://youtu.be/abc123" "0:30" "0:42"
```

## Add to Login Items

To launch fatcat at login:

1. Build a release binary:
   ```bash
   swift build -c release
   ```
2. The binary is at `.build/release/fatcat`. The app loads `Assets/cat.mov` from the **current working directory**, so wrap it in a launcher script that `cd`s to the repo first.
3. Save this as `~/bin/fatcat-launcher.sh`:
   ```bash
   #!/usr/bin/env bash
   cd ~/fun/fatcat
   exec ./.build/release/fatcat
   ```
   `chmod +x ~/bin/fatcat-launcher.sh`
4. **System Settings → General → Login Items → Open at Login → +** → choose `fatcat-launcher.sh`.

## Limitations

- **macOS-only.** Uses AppKit, AVKit, and Combine — no Linux/Windows support.
- **Hot-plug monitor reconfiguration not supported.** `NSScreen.screens` is snapshotted at startup. Restart fatcat after plugging/unplugging monitors.
- **No persistence.** Quitting fatcat resets the work-time accumulator.
- **No menu bar UI.** Tunables live in `Config.swift`; edit and rebuild to change durations.

## Architecture

See [`docs/superpowers/specs/2026-04-27-fat-cat-break-app-design.md`](docs/superpowers/specs/2026-04-27-fat-cat-break-app-design.md).
````

- [ ] **Step 4: Verify build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 5: Run the full unit test suite one last time**

```bash
swift test 2>&1 | tail -10
```
Expected: 6 tests passing.

- [ ] **Step 6: Final manual verification (the 6-step checklist from the spec)**

Run from `~/fun/fatcat`:

```bash
swift run fatcat
```

Then verify (this will take ~30 minutes of real work to trigger a real break — for faster verification, briefly drop `Config.workDuration` to 30s, rebuild, verify, then restore):

- [ ] App stays in foreground (no exit), no dock icon appears
- [ ] After workDuration of activity (or 30s in debug mode): cat appears on ALL monitors
- [ ] Cat is visible on top of fullscreen Safari window
- [ ] Cat follows you across Spaces (`Ctrl+→`)
- [ ] Mouse clicks pass through to apps underneath
- [ ] Cat video loops smoothly with transparent background
- [ ] Timer counts down `5:00 → 0:00`, monospaced digits don't jitter
- [ ] At `0:00`: cat fades out
- [ ] Idle pause: with debug `workDuration=30`, leave keyboard idle for >60s — accumulator pauses (verify with a debug `print` inside `tick()` if needed)
- [ ] App stays running and reliable for >1 hour without App Nap stretching the timer

If all checks pass, restore `Config.workDuration = 25 * 60` (if you tweaked it for verification) and commit.

- [ ] **Step 7: Commit**

```bash
git add Sources/fatcat/main.swift Sources/fatcat/Config.swift README.md
git -c user.name="Srijan" -c user.email="srijan@deepreel.com" commit -m "feat: App Nap mitigation, real Pomodoro durations, README"
```

- [ ] **Step 8: (Optional) Set up Login Items per the README so fatcat launches at login**

This is a manual step — do it via System Settings, not in code.

---

## Done

The app is shipped to your own Mac. The Pomodoro timer ticks; every 25 minutes a fat orange cat invades every monitor for 5 minutes. The whole thing is ~150 lines of Swift, ~80 lines of tests, ~50 lines of asset-pipeline shell, and one cat video.

Future enhancements (out of scope for v1, see spec):
- Menu bar UI with pause/resume/quit
- Hot-plug monitor reconfiguration
- Configurable durations via UI
- Multiple cat videos rotating per break
- Sound on entry/exit
- Code signing + notarization for redistribution
