# fatcat — Design Spec

**Date:** 2026-04-27
**Status:** Approved (pending user review of this written spec)
**Inspired by:** [@birdabo tweet about a Japanese dev's break-reminder app](https://x.com/i/status/2048404010789687315)

## What we're building

A macOS background app that displays a transparent video of a fat orange cat over your screen every time you've worked for too long. The cat sits there for the whole break and then disappears. The video is real cat footage with the background removed, played as an HEVC-with-alpha clip on a screen-saver-level overlay window.

It's a personal weekend hack — small, charming, and runs forever in the background.

## Decisions

| Dimension | Choice | Why |
|---|---|---|
| Scope | Personal weekend hack on macOS | One evening of work, ~150 lines of Swift |
| Forcefulness | Screen-saver-level overlay, no input blocking | Matches the original; keyboard/mouse pass through to apps underneath |
| Trigger | Activity-aware via `CGEventSource.secondsSinceLastEventType` | "50 min of real work," not "50 min wall clock"; no permissions needed |
| Visuals | Wandering cat with transparency | Cat sits *on top of* your work, not in a tinted box |
| Cat content | Alpha-channel video clip, not sprites | Real cat footage — encodes natural walking/sitting/lounging behavior with no animation logic |
| Asset source | YouTube clip → `rembg` → HEVC-with-alpha | Free, fast, swappable without code changes |
| App shell | Single-file Swift CLI (SwiftPM executable) | No Xcode project, no `.app` bundle, no menu bar — minimum lift |

## Architecture

### Project layout

```
~/fun/fatcat/
├── Package.swift              # SwiftPM manifest, executable target "fatcat"
├── Sources/fatcat/
│   ├── main.swift             # Entry point: starts NSApp, wires components
│   ├── BreakScheduler.swift   # Idle-aware countdown to next break
│   ├── CatWindow.swift        # The transparent screen-saver-level NSWindow
│   ├── CatPlayer.swift        # AVPlayer setup + looping playback
│   ├── TimerLabel.swift       # The big white countdown text
│   └── Config.swift           # Tunable constants (durations, asset path)
├── Tests/fatcatTests/
│   └── BreakSchedulerTests.swift
├── Assets/
│   └── cat.mov                # Alpha-HEVC video, gitignored (built locally)
├── scripts/
│   └── make-cat-asset.sh      # YouTube clip → rembg → alpha-HEVC pipeline
├── .gitignore                 # ignores Assets/cat.mov, .build/, .swiftpm/, frames/, masked/, raw_clip.mp4
└── README.md
```

### Why six small files instead of one

- Each file has one job and fits in 30–50 lines
- Easy to hold in context when editing
- `BreakScheduler` is the only file with non-trivial logic — isolating it makes it unit-testable without an `NSWindow`
- `main.swift` is pure wiring — reading it shows the whole app at a glance

### Why a SwiftPM executable instead of a `.app` bundle

- `swift build` works out of the box, no Xcode project to maintain
- `import AppKit` and `import AVKit` work directly
- Suppress the dock icon with `NSApp.setActivationPolicy(.accessory)` in `main.swift` — replaces the role of an `Info.plist` `LSUIElement` flag

### Why the cat is in `Assets/`, not `Sources/fatcat/Resources/`

SwiftPM resource bundling forces `Bundle.module` lookups and adds boilerplate. For a personal hack, loading from a known relative path (resolved at launch) is dramatically simpler. The cost: the binary alone isn't redistributable — you also need the `Assets/` directory next to it. For personal use, fine.

## Components

### `Config.swift` (~15 lines)

A struct of constants. Single source of truth for every tunable value.

```swift
enum Config {
    static let workDuration: TimeInterval = 50 * 60        // 50 min of activity
    static let breakDuration: TimeInterval = 5 * 60        // 5 min cat
    static let idleResetThreshold: TimeInterval = 60       // 1 min idle = pause
    static let assetPath: String = "Assets/cat.mov"        // relative to launch dir
    static let pollInterval: TimeInterval = 1.0            // tick rate
}
```

Depends on: nothing.

### `BreakScheduler.swift` (~40 lines)

The only non-trivial logic in the app. Owns the work-time accumulator and decides when to fire a break.

```swift
final class BreakScheduler {
    var onBreakStart: (() -> Void)?
    var onBreakTick: ((TimeInterval) -> Void)?   // remaining seconds
    var onBreakEnd: (() -> Void)?

    init(
        workDuration: TimeInterval = Config.workDuration,
        breakDuration: TimeInterval = Config.breakDuration,
        idleResetThreshold: TimeInterval = Config.idleResetThreshold,
        pollInterval: TimeInterval = Config.pollInterval,
        idleSource: @escaping () -> TimeInterval = realIdleSource,
        scheduleTick: @escaping (TimeInterval, @escaping () -> Void) -> Cancellable = realTimer
    )

    func start()
}
```

Each tunable is its own argument with the `Config` enum value as its default. Production wiring just calls `BreakScheduler()`; tests override only the parameters they care about (e.g., `BreakScheduler(workDuration: 5, breakDuration: 3, idleSource: { 0 }, scheduleTick: testClock.schedule)`). Injecting individual values rather than `Config.Type` sidesteps Swift's enum-metatype limitation — you can't substitute an enum, but you can substitute its constants.

`realIdleSource` and `realTimer` are top-level functions defined alongside `BreakScheduler` in the same file. `realIdleSource` reads `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)`. `realTimer` schedules a `Timer.scheduledTimer(withTimeInterval:repeats:)` and returns a `Cancellable` that invalidates it on `cancel()`. Tests pass synthetic replacements.

Internal state: `accumulatedActiveSeconds: TimeInterval`, `breakRemaining: TimeInterval?` (non-nil means "currently in a break"), and the `Cancellable` returned by `scheduleTick`.

Per tick:
1. Read idle seconds via injected `idleSource`.
2. If mid-break: decrement `breakRemaining`, fire `onBreakTick`; if zero, fire `onBreakEnd` and reset.
3. Else if idle ≥ `idleResetThreshold`: do nothing (paused).
4. Else: add `pollInterval` to `accumulatedActiveSeconds`; if ≥ `workDuration`, fire `onBreakStart` and enter break mode.

Dependencies are injected to make the scheduler unit-testable (see Testing).

Depends on: `Config`, `CoreGraphics` (idle API in production source), `Foundation`.

### `CatWindow.swift` (~40 lines)

`NSWindow` subclass — the transparent fullscreen overlay. Pure container, no logic.

```swift
final class CatWindow: NSWindow {
    init(for screen: NSScreen)
    func reveal()    // fade in + bring to front
    func dismiss()   // fade out + order out
}
```

Configured at init:
- `styleMask = .borderless`
- `level = .screenSaver` (the magic line — punches through fullscreen apps)
- `isOpaque = false`, `backgroundColor = .clear`
- `ignoresMouseEvents = true` (clicks pass through to apps underneath)
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
- `hasShadow = false`

Subclass overrides `canBecomeKey` and `canBecomeMain` to `false` — never steal focus from the active app.

Depends on: `AppKit`.

### `CatPlayer.swift` (~30 lines)

Wraps `AVPlayer` + `AVPlayerView`. Loops the cat video forever while visible.

```swift
final class CatPlayer {
    let view: AVPlayerView    // add as subview to CatWindow
    init(assetURL: URL)
    func play()
    func pause()
}
```

Loops by observing `AVPlayerItem.didPlayToEndTimeNotification` and seeking to `.zero`. Setting `actionAtItemEnd = .none` alone does not loop — the player just halts at the end.

Depends on: `AVKit`, `AVFoundation`.

### `TimerLabel.swift` (~20 lines)

Big white `M:SS` countdown. Styled `NSTextField`.

```swift
final class TimerLabel: NSTextField {
    init(frame: NSRect)
    func setRemaining(_ seconds: TimeInterval)   // formats "M:SS"
}
```

Style: `NSFont.monospacedDigitSystemFont(ofSize: 180, weight: .bold)`, white text, no background, no border, not editable, not selectable.

Depends on: `AppKit`.

### `main.swift` (~30 lines) — the wiring

The whole app at a glance:

```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)               // no dock icon

// Hold a strong reference to keep App Nap from suspending us
let napActivity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .latencyCritical],
    reason: "fatcat scheduler must tick reliably"
)

let screen = NSScreen.main!
let assetURL = URL(fileURLWithPath: Config.assetPath,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

let scheduler = BreakScheduler()
let window = CatWindow(for: screen)
let player = CatPlayer(assetURL: assetURL)
let label  = TimerLabel(frame: NSRect(
    x: 80,
    y: screen.frame.midY - 100,
    width: 600, height: 220
))

player.view.frame = window.contentView!.bounds    // cat fills window
player.view.autoresizingMask = [.width, .height]
window.contentView?.addSubview(player.view)
window.contentView?.addSubview(label)             // timer overlaid on left side

scheduler.onBreakStart = { window.reveal(); player.play() }
scheduler.onBreakTick  = { label.setRemaining($0) }
scheduler.onBreakEnd   = { player.pause(); window.dismiss() }

scheduler.start()
app.run()
```

Closures over a delegate protocol because there is exactly one consumer of these callbacks. Closures save ~10 lines and read more linearly.

## Data flow

One state machine, two states, driven by a 1Hz timer:

```
         accumulated >= workDuration
             ┌──────────────────────────────────┐
             ▼                                  │
      [ working ]              [   in_break   ]
             │                                  ▲
             └──────────────────────────────────┘
              breakRemaining hits zero
```

Per second, in `working`:
- Read idle seconds.
- If idle ≥ 60s: do nothing (you're AFK).
- Else: increment `accumulatedActiveSeconds`. If it hits `workDuration`, transition to `in_break`.

Per second, in `in_break`:
- Decrement `breakRemaining`. Fire `onBreakTick(breakRemaining)`.
- If `breakRemaining` reaches 0: fire `onBreakEnd`, reset `accumulatedActiveSeconds` to 0, transition to `working`.

### Inputs

| Input | Source | Used for |
|---|---|---|
| Idle seconds | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)` | Pause work-time accumulator when AFK |
| Wall clock tick | `Timer.scheduledTimer` at 1Hz | Drive the state machine |
| Cat video frames | Pre-encoded `cat.mov` on disk | Display |

### Outputs

| Output | Destination |
|---|---|
| Cat overlay (visible/hidden) | Screen-saver-level `NSWindow` |
| Timer text (`M:SS`) | `NSTextField` overlaid on the window |

### Why no on-disk persistence

`accumulatedActiveSeconds` lives in memory. Quitting fatcat resets the timer. The alternative — persisting to a JSON file every tick — adds disk I/O, schema versioning, and corruption edge cases for negligible benefit on a personal app you launch once at login.

## Error handling

Principle: **fail loudly at startup, run silently after**. Don't wrap normal operation in try/catch ceremony.

### Failures we handle explicitly

| Failure | When | Behavior |
|---|---|---|
| `cat.mov` not found at configured path | startup | Print error including resolved absolute path, exit 1 |
| `AVPlayer` can't load `cat.mov` (wrong codec, corrupt) | startup | Observe `AVPlayer.status == .failed`, print `error.localizedDescription`, exit 1 |
| No main screen returned by `NSScreen.main` | startup | Print error, exit 1 — cleaner than crashing on `NSScreen.main!` |
| App Nap suspends the 1Hz timer | runtime | Preempt with `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: ...)` at startup; keep the returned token alive |
| `AVPlayer` fails mid-break | runtime | Log it, dismiss the window early, return to working state — never leave a stuck black overlay |

### Failures we deliberately don't handle

| Failure | Why not |
|---|---|
| Multi-monitor support | v1 ships single-main-screen. Documented in README; not a bug. |
| Display sleep mid-break | OS hides the window; our timer keeps ticking; break ends normally. No code needed. |
| Mac sleep mid-work | On wake, idle seconds is huge → trips the 60s threshold → accumulator stays paused. Self-correcting. |
| User force-quits mid-break | Next launch starts fresh in working state. No persistence to corrupt. |
| Lock screen overlap | Screen-saver-level windows order *below* the lock screen. Cat is hidden while locked. |

### What we don't add

- No retry loops. Missing asset → exit, don't spin.
- No structured error types. `print` to stderr is the right surface for a personal CLI.
- No log file. Terminal stderr is enough.
- No crash reporter. It's 150 lines.

### The App Nap gotcha

Without `beginActivity`, macOS can stretch our 1Hz timer to one tick every 30+ seconds because we have no visible UI 99.9% of the time — the textbook target for App Nap. The activity token must be held by a strong reference; `let _ = ProcessInfo.processInfo.beginActivity(...)` has no effect because ARC immediately releases it. We bind it to a top-level `let napActivity` in `main.swift`.

## Testing

One component is worth unit-testing; the rest you verify by running.

### Unit tests — `BreakScheduler` only

To make it testable, we inject the clock, the idle source, and the `Config` type. Tests pass a `TestConfig` with tiny durations (e.g., `workDuration = 5s`, `breakDuration = 3s`) so the assertions read naturally and run instantly.

| Test | Asserts |
|---|---|
| `accumulates_active_seconds_when_not_idle` | With `workDuration=10`, after 5 fake ticks at idle=0, accumulator = 5s, no break started |
| `pauses_accumulator_when_idle_above_threshold` | With `idleResetThreshold=60`, after 5 fake ticks at idle=120, accumulator stays at 0 |
| `fires_onBreakStart_when_workDuration_reached` | With `workDuration=5`, after exactly 5 ticks at idle=0, `onBreakStart` fires exactly once |
| `decrements_breakRemaining_during_break` | With `breakDuration=10`, after 3 ticks in break mode, `onBreakTick` last fired with `7` |
| `fires_onBreakEnd_and_resets_when_break_completes` | With `breakDuration=3`, after 3 ticks in break mode, `onBreakEnd` fires, accumulator = 0 |
| `transition_to_working_clears_breakRemaining` | After break ends, next tick goes through working-state path (verified by accumulator incrementing) |

Six tests, ~80 lines total. Run with `swift test`. They use a `TestClock` (records scheduled callbacks; advances time on demand) and a `TestIdleSource` (returns whatever value the test sets). No real time elapses; whole suite runs in milliseconds.

### What we don't unit-test

| Component | Why not |
|---|---|
| `CatWindow` | Mocking AppKit to assert "level was set to .screenSaver" tests the test, not the code. |
| `CatPlayer` | Same — wrapping `AVPlayer` in a stub tests our stubbing skill. |
| `TimerLabel` | A formatter and a font setting. |
| `main.swift` | Pure wiring; broken wiring is visible the first time you trigger a break. |

### Manual verification checklist (~3 minutes after every meaningful change)

1. **Launch from terminal:** `swift run fatcat`. App stays in foreground. No dock icon appears.
2. **Trigger a debug break immediately:** during dev, edit `Config.workDuration` to `10` in `Config.swift` and rebuild. Wait 10s. Cat appears. (Restore to `50 * 60` before shipping.)
3. **Cat overlay correctness:**
   - [ ] Visible on top of all apps including a fullscreen Safari window
   - [ ] Visible across Spaces (`Ctrl+→` to switch — cat follows)
   - [ ] Mouse clicks pass through to apps underneath (click a button under the cat — it should fire)
   - [ ] Window doesn't steal focus (active app's title bar stays focused)
   - [ ] Cat video loops smoothly with transparent background
4. **Timer correctness:** counts down from `5:00` to `0:00`, monospaced digits don't jitter.
5. **Break ends:** at `0:00`, cat fades out, app returns to working state.
6. **Idle pause:** with debug `workDuration=30`, leave keyboard idle for >60s — accumulator should pause (verify with a debug `print` of `accumulatedActiveSeconds`).

Once all six pass, restore real durations and add to Login Items.

### Asset pipeline testing

`scripts/make-cat-asset.sh` is verified by running it. It either succeeds (produces `Assets/cat.mov`) or fails with a clear stderr message. We don't unit-test shell scripts.

## Asset pipeline

The cat video is the only content this app has. `scripts/make-cat-asset.sh` builds it end-to-end. You run this once, or whenever you want a different cat.

### Inputs

- A YouTube URL of a fat orange cat
- Two timestamps marking a 5–15 second window: cat enters → cat sits → cat lounges (or any subset that loops well)
- Background as uncluttered as possible — `rembg` works on any background but cleaner = fewer artifacts

### Pipeline

```
   YouTube URL                                    Assets/cat.mov
        │                                                ▲
        │ 1. yt-dlp                                      │ 5. ffmpeg
        ▼                                                │    HEVC + alpha
   raw_clip.mp4    →   frames/0001.png        →   masked/0001.png
                       2. ffmpeg                  3. rembg
                       extract frames            background remove
```

#### Stage 1 — Download just the clip we need

```bash
yt-dlp -f "bv[height<=1080][ext=mp4]" \
  --download-sections "*${START}-${END}" \
  -o raw_clip.mp4 "$YOUTUBE_URL"
```

Pulls only the chosen window, video-only. `--download-sections` is the key flag — without it, yt-dlp grabs the full video.

#### Stage 2 — Explode to PNG frames

```bash
mkdir -p frames
ffmpeg -i raw_clip.mp4 -r 30 frames/%04d.png
```

Force 30fps for predictable frame count and lighter output.

#### Stage 3 — Background-remove every frame

```bash
mkdir -p masked
for f in frames/*.png; do
  rembg i "$f" "masked/$(basename "$f")"
done
```

`rembg` is a Python tool (`pipx install rembg`). One model invocation per frame, ~0.3s each on Apple Silicon. A 10s @30fps clip = 300 frames = ~90s wall time. Output is RGBA PNG with the cat segmented out.

#### Stages 4 + 5 — Reassemble as HEVC with alpha

```bash
ffmpeg -framerate 30 -i masked/%04d.png \
  -c:v hevc_videotoolbox \
  -alpha_quality 0.75 \
  -tag:v hvc1 \
  -pix_fmt yuva420p \
  Assets/cat.mov
```

Three flags that all matter:
- `hevc_videotoolbox` — Apple's hardware encoder. Required for HEVC-with-alpha on macOS.
- `-tag:v hvc1` — without this, AVFoundation refuses to play the file. ffmpeg defaults to `hev1`, which AVPlayer rejects even though it's valid HEVC.
- `-alpha_quality 0.75` — turns alpha encoding on. Without it, the alpha channel is silently dropped and you get an opaque cat.

### Smoke test before integrating

```bash
# Quick visual check
open Assets/cat.mov

# Verify alpha channel actually present
ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt Assets/cat.mov
# Expect: pix_fmt=yuva420p   (the "a" is the alpha plane)
```

If `pix_fmt` doesn't include an `a`, the encode silently dropped alpha — re-run stage 5 with the flags above.

### Sourcing tips for the YouTube clip

- Search terms that work: "fat orange cat sitting", "chunky cat lounging", "cat walks across desk"
- Aim for **camera locked off** (no panning) — moving backgrounds are harder for `rembg` to segment cleanly
- A clip with a single continuous shot of the same cat is way better than a montage
- Resolution ≥720p; rembg quality scales with input resolution
- Avoid clips with text/watermarks — they'll get masked oddly

### Iteration story

When the cat looks bad, iterate on stage 1 (different timestamps or different video) and stage 3 (try `rembg i -m u2netp` or `-m isnet-general-use` for different segmentation models). Re-run the pipeline; the Swift app reads the same path and picks up the new cat with no rebuild.

### The `hvc1` vs `hev1` gotcha

Both tags identify HEVC bitstreams; they differ only in how parameter sets are stored. AVFoundation only accepts `hvc1`, but ffmpeg defaults to `hev1`. Files with `hev1` open fine in QuickTime (which uses a more permissive code path) but produce a mysterious black `AVPlayerView` in the app. If you ever see "the video plays in QuickTime but not in my app," this is almost always why.

## Out of scope for v1

These are deliberate non-goals — they are reasonable extensions but would expand the project beyond a weekend hack.

- **Menu bar UI** with pause/resume/quit/Settings — natural v2; the overlay code is unchanged
- **Multi-monitor support** — one `CatWindow` per `NSScreen`, with the cat picking which screen to wander on
- **Configurable durations via UI** — currently requires editing `Config.swift` and rebuilding
- **Persistence** of work-time accumulator across launches
- **Multiple cat videos** that rotate per break
- **Sound** (purr, meow on entry/exit)
- **Code signing / notarization / Sparkle auto-update** — only matters if redistributing
- **Cross-platform support** — single-platform (macOS) on purpose

## Implementation order (preview for the writing-plans step)

1. SwiftPM scaffold (`Package.swift`, empty `main.swift`, `swift run` succeeds with a no-op)
2. `Config.swift` + `BreakScheduler.swift` + unit tests passing
3. `CatWindow.swift` — verify visually with a placeholder background color
4. `TimerLabel.swift` overlaid on the window — verify with hard-coded `5:00`
5. Asset pipeline script — produce a working `cat.mov` from a chosen YouTube URL
6. `CatPlayer.swift` — verify cat plays and loops with transparency in the window
7. Wire everything in `main.swift` — full lifecycle works end-to-end with `workDuration = 10`
8. Restore real durations, run the manual verification checklist, add to Login Items

The writing-plans skill will turn this into a sequenced task list with explicit completion criteria.
