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
