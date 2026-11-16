import AppKit
import AVFoundation

@MainActor
final class DesktopVideoWindow: NSWindow {
    private struct Playback: @unchecked Sendable {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
    }

    private var current: Playback?
    private var readyObservation: NSKeyValueObservation?
    private var wantsPlaying = false
    private(set) var videoURL: URL?

    var onVisibilityChange: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        alphaValue = 0

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view

        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onVisibilityChange?() }
        }
    }

    var currentPlayer: AVPlayer? { current?.player }

    var isVisibleOnScreen: Bool { occlusionState.contains(.visible) }

    func show(videoURL url: URL) {
        guard url != videoURL, let root = contentView?.layer else { return }
        videoURL = url

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        let layer = AVPlayerLayer(player: player)
        layer.frame = root.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = .resizeAspectFill
        layer.opacity = 0
        root.addSublayer(layer)

        let previous = current
        current = Playback(player: player, looper: looper, layer: layer)
        if wantsPlaying { player.play() }

        readyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] observed, _ in
            guard observed.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self, self.current?.layer === observed else { return }
                self.readyObservation = nil
                self.crossfade(to: observed, removing: previous)
            }
        }
    }

    private func crossfade(to layer: AVPlayerLayer, removing previous: Playback?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(previous == nil ? 0.01 : 0.9)
        CATransaction.setCompletionBlock {
            previous?.player.pause()
            previous?.looper.disableLooping()
            previous?.layer.removeFromSuperlayer()
        }
        layer.opacity = 1
        CATransaction.commit()

        if alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.8; animator().alphaValue = 1 }
        }
    }

    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        guard let player = current?.player else { return }
        if playing {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
        }
    }

    func fadeOutAndClose() {
        readyObservation = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                self.stop()
                self.orderOut(nil)
                self.close()
            }
        }
    }

    func stop() {
        readyObservation = nil
        current?.player.pause()
        current?.looper.disableLooping()
        current?.layer.removeFromSuperlayer()
        current = nil
        videoURL = nil
    }
}
