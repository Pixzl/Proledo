import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var iconSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        state.start()
        setUpStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Proledo"
        statusItem = item

        let host = NSHostingController(rootView: MenuView().environmentObject(state))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        updateIcon()
        iconSubscription = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQuickMenu() {
        guard let button = statusItem?.button else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        let pause = menu.addItem(withTitle: state.settings.userPaused ? "Fortsetzen" : "Pausieren",
                                 action: #selector(quickTogglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(.separator())
        let saving = menu.addItem(withTitle: "Stromsparmodus", action: #selector(quickTogglePowerSaving), keyEquivalent: "")
        saving.target = self
        saving.state = state.settings.powerSaving ? .on : .off
        let login = menu.addItem(withTitle: "Beim Anmelden starten", action: #selector(quickToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = state.launchAtLogin ? .on : .off
        let folder = menu.addItem(withTitle: "Videoordner öffnen", action: #selector(quickOpenFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Proledo beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func quickTogglePause() { state.togglePause() }
    @objc private func quickTogglePowerSaving() { state.settings.powerSaving.toggle() }
    @objc private func quickToggleLogin() { state.setLaunchAtLogin(!state.launchAtLogin) }
    @objc private func quickOpenFolder() { state.revealInFinder() }

    private func updateIcon() {
        let playing = state.pauseReason == nil && state.activeScreenCount > 0
        statusItem?.button?.image = Self.statusImage(playing: playing)
    }

    static func statusImage(playing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 5.75, width: 14.5, height: 10.5), xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1.5
            frame.stroke()
            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 6, y: 2))
            stand.line(to: NSPoint(x: 12, y: 2))
            stand.move(to: NSPoint(x: 9, y: 2))
            stand.line(to: NSPoint(x: 9, y: 5))
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.stroke()
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 4.75, y: 10.25))
            wave.curve(to: NSPoint(x: 9, y: 11), controlPoint1: NSPoint(x: 6.25, y: 13.25), controlPoint2: NSPoint(x: 7.5, y: 13.25))
            wave.curve(to: NSPoint(x: 13.25, y: 11.75), controlPoint1: NSPoint(x: 10.5, y: 8.75), controlPoint2: NSPoint(x: 11.75, y: 8.75))
            wave.lineWidth = 1.5
            wave.lineCapStyle = .round
            NSColor.black.withAlphaComponent(playing ? 1 : 0.4).set()
            wave.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = playing ? "Proledo – Video läuft" : "Proledo"
        return image
    }

    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
