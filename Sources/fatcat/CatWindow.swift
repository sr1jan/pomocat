import AppKit

final class CatWindow: NSWindow {
    init(for screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.setFrame(screen.frame, display: false)
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
