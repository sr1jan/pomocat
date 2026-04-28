import AppKit

// stderr helper — must be declared before first use, since top-level
// code in main.swift runs sequentially.
extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        self.write(Data(string.utf8))
    }
}
var standardError = FileHandle.standardError

// Disable stdout buffering so log output is visible when run as a background
// process (where stdout isn't a TTY and would otherwise block-buffer).
setbuf(stdout, nil)

// Hold an activity token for the process lifetime so macOS App Nap doesn't
// throttle our 1Hz BreakScheduler tick during long work intervals when the app
// looks idle to the OS. .userInitiated allows normal system sleep but prevents
// App Nap. The token must be retained — releasing it ends the activity.
let activityToken = ProcessInfo.processInfo.beginActivity(
    options: .userInitiated,
    reason: "pomocat tracks active work time and triggers break overlays"
)
_ = activityToken  // silence "never used" — its job is to live as long as the app

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let assetURL = URL(fileURLWithPath: Config.assetPath,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

guard FileManager.default.fileExists(atPath: assetURL.path) else {
    print("pomocat: ERROR — asset not found at \(assetURL.path)", to: &standardError)
    exit(1)
}

// Per-screen overlay = window + player view + timer label + its own CatPlayer.
// AVPlayer only feeds pixels to one AVPlayerLayer at a time — sharing one
// player across N layers makes all-but-one screen render solid black. Each
// screen needs its own AVPlayer/AVPlayerItem; loop sync is good enough for a
// short looping clip without explicit time alignment.
struct Overlay {
    let window: CatWindow
    let view: CatPlayerView
    let label: TimerLabel
    let player: CatPlayer
}

// Keyed by CGDirectDisplayID (stable across reconnects of the same display)
// so we can diff against NSScreen.screens whenever the configuration changes.
// Snapshotting at startup leaves orphan windows when an external monitor
// disconnects — AppKit relocates them onto the remaining display and you get
// N cats stacked on one screen.
var overlays: [CGDirectDisplayID: Overlay] = [:]

// Tracks an in-progress break so a screen that attaches mid-break joins it
// instead of staying dark until the next cycle.
var currentBreakRemaining: TimeInterval? = nil

func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

func makeOverlay(for screen: NSScreen) -> Overlay {
    let window = CatWindow(for: screen)

    let player = CatPlayer(assetURL: assetURL)
    let view = CatPlayerView()
    view.frame = window.contentView!.bounds
    view.autoresizingMask = [.width, .height]
    view.playerLayer.player = player.avPlayer
    window.contentView?.addSubview(view)

    let label = TimerLabel(frame: NSRect(
        x: 80,
        y: window.contentView!.bounds.midY - 110,
        width: 600, height: 220
    ))
    // Force layer-backed mode so the label composites in the same layer tree as the
    // layer-hosting CatPlayerView; otherwise AppKit's auto-promotion can place this
    // label *under* the player layer regardless of addSubview order.
    label.wantsLayer = true
    window.contentView?.addSubview(label, positioned: .above, relativeTo: view)

    return Overlay(window: window, view: view, label: label, player: player)
}

func syncOverlays() {
    var present: Set<CGDirectDisplayID> = []
    for screen in NSScreen.screens {
        guard let id = displayID(of: screen) else { continue }
        present.insert(id)
        if let existing = overlays[id] {
            // Resolution or arrangement may have changed — re-pin to the screen frame.
            existing.window.setFrame(screen.frame, display: false)
        } else {
            let overlay = makeOverlay(for: screen)
            overlays[id] = overlay
            if let remaining = currentBreakRemaining {
                overlay.label.setRemaining(remaining)
                overlay.window.reveal()
                overlay.player.play()
            }
        }
    }
    for (id, overlay) in overlays where !present.contains(id) {
        overlay.player.pause()
        overlay.window.orderOut(nil)
        overlays.removeValue(forKey: id)
    }
    print("pomocat: \(overlays.count) screen(s) active")
}

syncOverlays()

NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main
) { _ in syncOverlays() }

// Real Pomodoro durations and idle source — Config defaults are 25m work, 5m
// break, 60s idle reset. Override either at the BreakScheduler init site for
// debug runs.
let scheduler = BreakScheduler()

scheduler.onBreakStart = {
    print("pomocat: break starting (\(Int(Config.breakDuration / 60))m)")
    currentBreakRemaining = Config.breakDuration
    overlays.values.forEach {
        $0.label.setRemaining(Config.breakDuration)
        $0.window.reveal()
        $0.player.play()
    }
}

scheduler.onBreakTick = { remaining in
    currentBreakRemaining = remaining
    overlays.values.forEach { $0.label.setRemaining(remaining) }
}

scheduler.onBreakEnd = {
    print("pomocat: break ending")
    currentBreakRemaining = nil
    overlays.values.forEach {
        $0.player.pause()
        $0.window.dismiss()
    }
}

scheduler.start()
print("pomocat: scheduler running (\(Int(Config.workDuration / 60))m work / \(Int(Config.breakDuration / 60))m break) — Ctrl-C to quit")

app.run()
