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
// Force layer-backed mode so the label composites in the same layer tree as the
// layer-hosting CatPlayerView; otherwise AppKit's auto-promotion can place this
// label *under* the player layer regardless of addSubview order.
label.wantsLayer = true
// Debug harness: tick down from 5:00 in real time so we can visually verify
// the label updates. Real BreakScheduler integration is Task 16.
var remaining: TimeInterval = 300
label.setRemaining(remaining)
let tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    remaining -= 1
    label.setRemaining(remaining)
}
RunLoop.main.add(tick, forMode: .common)

// Add label above the player view in z-order. (The actual bug we just hit: this
// addSubview call was lost in an earlier edit, so the label was orphaned and
// invisible everywhere. The :positioned: variant is belt-and-suspenders against
// any future mixed layer-mode regression.)
window.contentView?.addSubview(label, positioned: .above, relativeTo: player.view)

window.reveal()
player.play()
print("fatcat: showing cat + countdown for 10s")

DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
    tick.invalidate()
    player.pause()
    window.dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
}

app.run()
