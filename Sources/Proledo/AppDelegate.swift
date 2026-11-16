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
    @objc private func quickToggleLogin() { state.setLaunchAtLogin(!state.launchAtLogin) }
    @objc private func quickOpenFolder() { state.revealInFinder() }

    private func updateIcon() {
        let playing = state.pauseReason == nil && state.activeScreenCount > 0
        statusItem?.button?.image = Self.statusImage(playing: playing)
    }

    static func statusImage(playing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2.75, dy: 2.75))
            ring.lineWidth = 2
            ring.stroke()
            if playing {
                NSBezierPath(ovalIn: NSRect(x: rect.midX - 2.25, y: rect.midY - 2.25, width: 4.5, height: 4.5)).fill()
            }
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
