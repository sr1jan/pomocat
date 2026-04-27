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
    reason: "fatcat tracks active work time and triggers break overlays"
)
_ = activityToken  // silence "never used" — its job is to live as long as the app

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let assetURL = URL(fileURLWithPath: Config.assetPath,
                   relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

guard FileManager.default.fileExists(atPath: assetURL.path) else {
    print("fatcat: ERROR — asset not found at \(assetURL.path)", to: &standardError)
    exit(1)
}

// One shared AVPlayer drives N AVPlayerLayers — multi-monitor sync for free.
let player = CatPlayer(assetURL: assetURL)

// Per-screen overlay = window + player view + timer label. We snapshot the
// screen list at startup; hot-plug handling is a future concern.
struct Overlay {
    let window: CatWindow
    let view: CatPlayerView
    let label: TimerLabel
}

let overlays: [Overlay] = NSScreen.screens.map { screen in
    let window = CatWindow(for: screen)

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

    return Overlay(window: window, view: view, label: label)
}

print("fatcat: \(overlays.count) screen(s)")

// Real Pomodoro durations and idle source — Config defaults are 25m work, 5m
// break, 60s idle reset. Override either at the BreakScheduler init site for
// debug runs.
let scheduler = BreakScheduler()

scheduler.onBreakStart = {
    print("fatcat: break starting (\(Int(Config.breakDuration / 60))m)")
    overlays.forEach {
        $0.label.setRemaining(Config.breakDuration)
        $0.window.reveal()
    }
    player.play()
}

scheduler.onBreakTick = { remaining in
    overlays.forEach { $0.label.setRemaining(remaining) }
}

scheduler.onBreakEnd = {
    print("fatcat: break ending")
    player.pause()
    overlays.forEach { $0.window.dismiss() }
}

scheduler.start()
print("fatcat: scheduler running (\(Int(Config.workDuration / 60))m work / \(Int(Config.breakDuration / 60))m break) — Ctrl-C to quit")

app.run()
