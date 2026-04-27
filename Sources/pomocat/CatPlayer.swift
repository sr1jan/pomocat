import AppKit
import AVKit
import AVFoundation

// AVPlayerView (the high-level wrapper) renders against an opaque background
// even when the source video has alpha. To get true transparency we drop down
// to AVPlayerLayer directly. Use layer-BACKED mode (just wantsLayer=true), not
// layer-hosting (manual self.layer assignment) — layer-hosting prevents AppKit
// from auto-resizing the root layer when the view resizes, which made
// AVPlayerLayer's videoGravity calculation behave like .resizeAspectFill on
// screens whose aspect didn't match the source video.
final class CatPlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
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

    // The cat sits on the floor of the source frame (paws ~4px from the bottom
    // edge of the 1920x1080 source). With centered .resizeAspect on screens
    // narrower than 16:9 the cat ends up "floating" with empty letterbox below
    // the paws — reads visually as cropped paws. Bottom-aligning the layer puts
    // the empty letterbox above the cat's head instead, so the cat looks
    // grounded on every aspect ratio.
    private static let sourceAspect: CGFloat = 16.0 / 9.0

    override func layout() {
        super.layout()
        let view = self.bounds
        let videoAspect = Self.sourceAspect
        let viewAspect = view.width / view.height
        if videoAspect > viewAspect {
            // Source is wider than view: width-fit, bottom-align (letterbox at top).
            let h = view.width / videoAspect
            playerLayer.frame = CGRect(x: 0, y: 0, width: view.width, height: h)
        } else {
            // Source is taller (or matches): height-fit, center horizontally.
            let w = view.height * videoAspect
            playerLayer.frame = CGRect(x: (view.width - w) / 2, y: 0, width: w, height: view.height)
        }
    }
}

final class CatPlayer: NSObject {
    // Exposed so callers can attach N CatPlayerViews to the same player —
    // required for multi-monitor where every screen renders the same playback.
    let avPlayer: AVPlayer
    private let item: AVPlayerItem

    init(assetURL: URL) {
        self.item = AVPlayerItem(url: assetURL)
        self.avPlayer = AVPlayer(playerItem: item)
        self.avPlayer.isMuted = true
        self.avPlayer.actionAtItemEnd = .none

        super.init()

        // Diagnostic KVO — surface silent AVFoundation load failures (e.g. unsupported codec).
        item.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        avPlayer.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)

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
        avPlayer.seek(to: .zero)
        avPlayer.play()
    }

    func play() { avPlayer.play() }
    func pause() { avPlayer.pause() }
}
