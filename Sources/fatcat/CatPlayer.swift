import AppKit
import AVKit
import AVFoundation

// AVPlayerView (the high-level wrapper) renders against an opaque background
// even when the source video has alpha. To get true transparency we have to
// drop down to AVPlayerLayer directly and tell it that the underlying pixel
// buffers are BGRA (which carries the alpha channel through to compositing).
final class CatPlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer = CALayer()
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.layer?.isOpaque = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        self.layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = self.bounds
    }
}

final class CatPlayer: NSObject {
    let view: CatPlayerView
    private let player: AVPlayer
    private let item: AVPlayerItem

    init(assetURL: URL) {
        self.item = AVPlayerItem(url: assetURL)
        self.player = AVPlayer(playerItem: item)
        self.player.isMuted = true
        self.player.actionAtItemEnd = .none

        self.view = CatPlayerView()
        self.view.playerLayer.player = self.player

        super.init()

        // Diagnostic KVO — surface silent AVFoundation load failures (e.g. unsupported codec).
        item.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        player.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(loop),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailed),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item
        )
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let p = object as? AVPlayerItem, keyPath == "status" {
            FileHandle.standardError.write(Data("CatPlayer: item.status=\(p.status.rawValue) error=\(p.error?.localizedDescription ?? "nil")\n".utf8))
        } else if let p = object as? AVPlayer, keyPath == "status" {
            FileHandle.standardError.write(Data("CatPlayer: player.status=\(p.status.rawValue) error=\(p.error?.localizedDescription ?? "nil")\n".utf8))
        }
    }

    @objc private func itemFailed(_ note: Notification) {
        let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
        FileHandle.standardError.write(Data("CatPlayer: itemFailed: \(String(describing: err))\n".utf8))
    }

    @objc private func loop() {
        player.seek(to: .zero)
        player.play()
    }

    func play() { player.play() }
    func pause() { player.pause() }
}
