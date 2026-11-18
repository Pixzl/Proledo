import AppKit
import Foundation

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct VideoItem: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var sourceURL: String?
    var fileName: String
    var addedAt: Date
    var duration: Double?
    var fileSize: Int64?
    var ecoFileName: String?
    var ecoFileSize: Int64?
    var generated: Bool?
    var width: Int?
    var height: Int?
    var excludedFromRotation: Bool?
    var style: String?

    var fileURL: URL { Storage.videosDir.appendingPathComponent(fileName) }
    var ecoURL: URL? { ecoFileName.map { Storage.videosDir.appendingPathComponent($0) } }
    var hasSeparateEco: Bool { ecoFileName != nil && ecoFileName != fileName }
    var thumbnailURL: URL { Storage.videosDir.appendingPathComponent("\(id.uuidString).jpg") }
}

struct ScreenOptions: Codable, Equatable {
    var hideMenuBar = false
    var hideDock = false
    var idleCover = false
    var paused = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideMenuBar = try c.decodeIfPresent(Bool.self, forKey: .hideMenuBar) ?? false
        hideDock = try c.decodeIfPresent(Bool.self, forKey: .hideDock) ?? false
        idleCover = try c.decodeIfPresent(Bool.self, forKey: .idleCover) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }
}

struct Settings: Codable, Equatable {
    var assignments: [String: UUID] = [:]
    var screenOptions: [String: ScreenOptions] = [:]
    var pauseOnBattery = true
    var userPaused = false
    var powerSaving = false
    var rotatingScreens: [String] = []
    var rotationMinutes = 30
    var rotationStyle: String?
    var idleMinutes = 5

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try c.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? [:]
        screenOptions = try c.decodeIfPresent([String: ScreenOptions].self, forKey: .screenOptions) ?? [:]
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? true
        userPaused = try c.decodeIfPresent(Bool.self, forKey: .userPaused) ?? false
        powerSaving = try c.decodeIfPresent(Bool.self, forKey: .powerSaving) ?? false
        rotatingScreens = try c.decodeIfPresent([String].self, forKey: .rotatingScreens) ?? []
        rotationMinutes = try c.decodeIfPresent(Int.self, forKey: .rotationMinutes) ?? 30
        rotationStyle = try c.decodeIfPresent(String.self, forKey: .rotationStyle)
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 5
    }
}

struct ScreenInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let pixelSize: CGSize
    let frame: CGRect
}

struct QualityOption: Identifiable, Hashable {
    let id: String
    let label: String
    let codec: String
    let fps: Int?
    let bytes: Int64?
}

struct VideoInfo: Equatable {
    let url: String
    let title: String
    let channel: String?
    let duration: Double?
    let thumbnail: URL?
    let qualities: [QualityOption]
}

struct DownloadDraft: Equatable {
    var qualityID: String?
    var useRange = false
    var from = "0:00"
    var to = "10:00"
}

enum Storage {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Proledo", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            for old in ["ProLEDPaper", "LivePaper"] {
                let oldDir = base.appendingPathComponent(old, isDirectory: true)
                if fm.fileExists(atPath: oldDir.path) {
                    try? fm.moveItem(at: oldDir, to: dir)
                    break
                }
            }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let videosDir: URL = {
        let dir = appSupport.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let libraryFile = appSupport.appendingPathComponent("library.json")
    static let settingsFile = appSupport.appendingPathComponent("settings.json")

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func readableDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append(String(format: L("%d Std."), h)) }
        if m > 0 { parts.append(String(format: L("%d Min."), m)) }
        if sec > 0 && h == 0 { parts.append(String(format: L("%d Sek."), sec)) }
        return parts.isEmpty ? String(format: L("%d Sek."), 0) : parts.joined(separator: " ")
    }

    static func parseTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0 else { return nil }
            if index > 0 && value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var stableID: String? {
        guard let id = displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}
