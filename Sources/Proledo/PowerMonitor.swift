import AppKit
import IOKit.ps

extension Notification.Name {
    static let lpPowerSourceChanged = Notification.Name("ProledoPowerSourceChanged")
}

@MainActor
final class PowerMonitor {
    var onChange: (() -> Void)?

    private(set) var onBattery = false
    private(set) var screensAsleep = false
    private(set) var locked = false
    var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private var runLoopSource: CFRunLoopSource?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        onBattery = Self.readOnBattery()

        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .lpPowerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        observe(NotificationCenter.default, .lpPowerSourceChanged) { $0.onBattery = Self.readOnBattery() }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { _ in }

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }

        let dnc = DistributedNotificationCenter.default()
        observe(dnc, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ update: @escaping (PowerMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?()
            }
        }
        tokens.append((center, token))
    }

    static func readOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
