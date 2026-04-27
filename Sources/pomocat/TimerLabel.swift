import AppKit

final class TimerLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEditable = false
        self.isSelectable = false
        self.isBordered = false
        self.drawsBackground = false
        self.textColor = .white
        self.font = NSFont.monospacedDigitSystemFont(ofSize: 180, weight: .bold)
        self.alignment = .left
        self.stringValue = "0:00"

        // Dark shadow so white text stays readable over light app windows.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 12
        self.shadow = shadow
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func setRemaining(_ seconds: TimeInterval) {
        let total = Int(seconds.rounded(.up))
        let m = total / 60
        let s = total % 60
        self.stringValue = String(format: "%d:%02d", m, s)
    }
}
