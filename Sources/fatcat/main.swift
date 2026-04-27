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
