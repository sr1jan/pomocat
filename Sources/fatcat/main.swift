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

// Debug harness: 1Hz countdown from 5:00 across all monitors. Real
// BreakScheduler integration is Task 16.
var remaining: TimeInterval = 300
overlays.forEach { $0.label.setRemaining(remaining) }
let tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    remaining -= 1
    overlays.forEach { $0.label.setRemaining(remaining) }
}
RunLoop.main.add(tick, forMode: .common)

overlays.forEach { $0.window.reveal() }
player.play()
print("fatcat: showing cat + countdown for 10s")

DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
    tick.invalidate()
    player.pause()
    overlays.forEach { $0.window.dismiss() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
}

app.run()
