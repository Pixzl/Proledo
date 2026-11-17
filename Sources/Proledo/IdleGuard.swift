import AppKit
import AVFoundation

@MainActor
final class IdleGuard {
    var onChange: (() -> Void)?

    private var covers: [String: CoverWindow] = [:]
    private var timer: Timer?
    private var screenIDs: Set<String> = []
    private var minutes = 5
    private var videoAllowed = true
    private var players: (String) -> AVPlayer? = { _ in nil }
    private(set) var active = false

    var coveredScreens: Set<String> { active ? screenIDs : [] }

    func apply(screens: Set<String>, minutes: Int, videoAllowed: Bool, players: @escaping (String) -> AVPlayer?) {
        let changed = screens != screenIDs || minutes != self.minutes || videoAllowed != self.videoAllowed
        screenIDs = screens
        self.minutes = max(1, minutes)
        self.videoAllowed = videoAllowed
        self.players = players
        if screens.isEmpty {
            deactivate(animated: false)
            stopTimer()
            return
        }
        if active && changed { refreshCovers() }
        if timer == nil { startTimer(interval: 1) }
    }

    func refreshPlayers() {
        guard active else { return }
        for (id, cover) in covers { cover.show(player: videoAllowed ? players(id) : nil) }
    }

    func tearDown() {
        stopTimer()
        deactivate(animated: false)
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if !active && idle >= Double(minutes * 60) {
            activate()
        } else if active && idle < 1 {
            deactivate(animated: true)
        }
    }

    private func activate() {
        active = true
        refreshCovers()
        startTimer(interval: 0.2)
        onChange?()
    }

    private func refreshCovers() {
        var seen = Set<String>()
        for screen in NSScreen.screens {
            guard let id = screen.stableID, screenIDs.contains(id) else { continue }
            seen.insert(id)
            let cover = covers[id] ?? CoverWindow(screen: screen)
            if covers[id] == nil {
                covers[id] = cover
                cover.alphaValue = 0
                cover.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 2; cover.animator().alphaValue = 1 }
            }
            if cover.frame != screen.frame { cover.setFrame(screen.frame, display: true) }
            cover.show(player: videoAllowed ? players(id) : nil)
        }
        for (id, cover) in covers where !seen.contains(id) {
            cover.orderOut(nil)
            cover.close()
            covers[id] = nil
        }
    }

    private func deactivate(animated: Bool) {
        guard active || !covers.isEmpty else { return }
        active = false
        let closing = covers
        covers.removeAll()
        for cover in closing.values {
            if animated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; cover.animator().alphaValue = 0 }) {
                    MainActor.assumeIsolated {
                        cover.orderOut(nil)
                        cover.close()
                    }
                }
            } else {
                cover.orderOut(nil)
                cover.close()
            }
        }
        if timer != nil && !screenIDs.isEmpty { startTimer(interval: 1) }
        onChange?()
    }
}

@MainActor
private final class CoverWindow: NSWindow {
    private let videoLayer = AVPlayerLayer()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.frame = view.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(videoLayer)
        contentView = view
    }

    func show(player: AVPlayer?) {
        if videoLayer.player !== player { videoLayer.player = player }
        videoLayer.isHidden = player == nil
    }
}
