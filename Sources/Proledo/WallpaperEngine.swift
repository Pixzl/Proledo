import AppKit
import AVFoundation

@MainActor
final class WallpaperEngine {
    private var windows: [String: DesktopVideoWindow] = [:]
    private var desired: [String: URL] = [:]
    private var playbackAllowed = true

    var screensWithStrips: Set<String> = []
    var onPlayersChanged: (() -> Void)?

    func player(for screenID: String) -> AVPlayer? {
        windows[screenID]?.currentPlayer
    }

    func apply(desired: [String: URL], playbackAllowed: Bool) {
        self.desired = desired
        self.playbackAllowed = playbackAllowed
        rebuild()
    }

    func rebuild() {
        var connected = Set<String>()
        for screen in NSScreen.screens {
            guard let id = screen.stableID else { continue }
            connected.insert(id)

            guard let url = desired[id] else {
                closeWindow(id)
                continue
            }
            let window = windows[id] ?? makeWindow(id: id, screen: screen)
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
            }
            window.show(videoURL: url)
            if !window.isVisible { window.orderFrontRegardless() }
        }
        for id in windows.keys where !connected.contains(id) {
            closeWindow(id)
        }
        updatePlayback()
    }

    func updatePlayback() {
        for (id, window) in windows {
            let visible = window.isVisibleOnScreen || screensWithStrips.contains(id)
            window.setPlaying(playbackAllowed && visible)
        }
    }

    func tearDown() {
        for window in windows.values {
            window.stop()
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func makeWindow(id: String, screen: NSScreen) -> DesktopVideoWindow {
        let window = DesktopVideoWindow(screen: screen)
        window.onVisibilityChange = { [weak self] in self?.updatePlayback() }
        window.onPlayerChange = { [weak self] in self?.onPlayersChanged?() }
        windows[id] = window
        return window
    }

    private func closeWindow(_ id: String) {
        guard let window = windows.removeValue(forKey: id) else { return }
        window.fadeOutAndClose()
    }
}
