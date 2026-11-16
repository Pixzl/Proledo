import AppKit
import AVFoundation

@MainActor
final class BarOverlayController {
    private enum Kind: String { case menuBar, dockBottom, dockLeft, dockRight }

    private struct Region: Equatable {
        let key: String
        let screenID: String
        let kind: Kind
        let rect: NSRect
        let screenFrame: NSRect
    }

    private var options: [String: ScreenOptions] = [:]
    private var playerProvider: (String) -> AVPlayer? = { _ in nil }
    private var strips: [String: StripWindow] = [:]
    private var regions: [Region] = []
    private var lastInside: [String: Date] = [:]
    private var timer: Timer?
    private var ticks = 0
    private var imageCache: [URL: NSImage] = [:]

    private let hideDelay: TimeInterval = 1.2

    func apply(options: [String: ScreenOptions], players: @escaping (String) -> AVPlayer?) {
        self.options = options
        self.playerProvider = players
        rebuild()
    }

    func tearDown() {
        timer?.invalidate()
        timer = nil
        for strip in strips.values { strip.orderOut(nil); strip.close() }
        strips.removeAll()
    }

    func rebuild() {
        regions = computeRegions()
        let wanted = Set(regions.map(\.key))

        for (key, strip) in strips where !wanted.contains(key) {
            strip.orderOut(nil)
            strip.close()
            strips[key] = nil
            lastInside[key] = nil
        }
        let screensByID = Dictionary(NSScreen.screens.compactMap { s in s.stableID.map { ($0, s) } },
                                     uniquingKeysWith: { a, _ in a })
        for region in regions {
            let isNew = strips[region.key] == nil
            let strip = strips[region.key] ?? StripWindow(rect: region.rect)
            if strip.frame != region.rect { strip.setFrame(region.rect, display: false) }

            let player = playerProvider(region.screenID)
            let image = player == nil ? screensByID[region.screenID].flatMap(desktopImage(for:)) : nil
            strip.show(player: player, image: image, screenFrame: region.screenFrame)

            if isNew {
                strips[region.key] = strip
                strip.orderFrontRegardless()
            }
        }

        if regions.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }

    private func desktopImage(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cached = imageCache[url] { return cached }
        let image = NSImage(contentsOf: url)
        imageCache[url] = image
        return image
    }

    private func computeRegions() -> [Region] {
        var result: [Region] = []
        let needsMenuBars = options.values.contains(where: \.hideMenuBar)
        let menuBars = needsMenuBars ? Self.menuBarFrames() : []

        for screen in NSScreen.screens {
            guard let id = screen.stableID, let opts = options[id] else { continue }
            let f = screen.frame, v = screen.visibleFrame
            func add(_ suffix: String, _ kind: Kind, _ rect: NSRect) {
                result.append(Region(key: "\(id)|\(suffix)", screenID: id, kind: kind, rect: rect, screenFrame: f))
            }

            if opts.hideMenuBar {
                let bar = menuBars.first { f.contains(NSPoint(x: $0.midX, y: $0.midY)) }
                let height = bar.map { f.maxY - $0.minY } ?? (f.maxY - v.maxY)
                if height >= 8 {
                    add("menu", .menuBar, NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height))
                }
            }
            if opts.hideDock {
                let bottom = v.minY - f.minY, left = v.minX - f.minX, right = f.maxX - v.maxX
                if bottom >= 8 { add("dockB", .dockBottom, NSRect(x: f.minX, y: f.minY, width: f.width, height: bottom)) }
                if left >= 8 { add("dockL", .dockLeft, NSRect(x: f.minX, y: v.minY, width: left, height: v.height)) }
                if right >= 8 { add("dockR", .dockRight, NSRect(x: v.maxX, y: v.minY, width: right, height: v.height)) }
            }
        }
        return result
    }

    private func tick() {
        ticks += 1
        if ticks % 10 == 0, computeRegions() != regions {
            rebuild()
            return
        }

        let mouse = NSEvent.mouseLocation
        let now = Date()
        var openMenus: [NSRect]?

        for region in regions {
            guard let strip = strips[region.key] else { continue }
            let hot = region.rect.insetBy(dx: -2, dy: -6).intersection(region.screenFrame.insetBy(dx: -1, dy: -1))
            if hot.contains(mouse) {
                lastInside[region.key] = now
                strip.setRevealed(true)
                continue
            }
            guard strip.revealed else { continue }

            if region.kind == .menuBar {
                if openMenus == nil { openMenus = Self.openMenuFrames() }
                if openMenus!.contains(where: { $0.intersects(region.screenFrame) }) {
                    lastInside[region.key] = now
                    continue
                }
            }
            if now.timeIntervalSince(lastInside[region.key] ?? .distantPast) > hideDelay {
                strip.setRevealed(false)
            }
        }
    }

    private static func openMenuFrames() -> [NSRect] {
        windowFrames(level: .popUpMenuWindow)
    }

    private static func menuBarFrames() -> [NSRect] {
        windowFrames(level: .mainMenuWindow).filter { $0.height <= 80 }
    }

    private static func windowFrames(level key: CGWindowLevelKey) -> [NSRect] {
        let level = Int(CGWindowLevelForKey(key))
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == level,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict)
            else { return nil }
            return NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
        }
    }
}

@MainActor
private final class StripWindow: NSWindow {
    private(set) var revealed = false
    private let videoLayer = AVPlayerLayer()
    private let imageLayer = CALayer()

    init(rect: NSRect) {
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(rect, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        videoLayer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(imageLayer)
        view.layer?.addSublayer(videoLayer)
        contentView = view
    }

    func show(player: AVPlayer?, image: NSImage?, screenFrame: NSRect) {
        let full = NSRect(x: screenFrame.minX - frame.minX, y: screenFrame.minY - frame.minY,
                          width: screenFrame.width, height: screenFrame.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = full
        imageLayer.frame = full
        if videoLayer.player !== player { videoLayer.player = player }
        videoLayer.isHidden = player == nil
        imageLayer.contents = player == nil ? image : nil
        imageLayer.contentsScale = backingScaleFactor
        CATransaction.commit()
    }

    func setRevealed(_ value: Bool) {
        guard value != revealed else { return }
        revealed = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = value ? 0.12 : 0.35
            animator().alphaValue = value ? 0 : 1
        }
    }
}
