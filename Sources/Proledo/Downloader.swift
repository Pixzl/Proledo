import Foundation
import VideoToolbox

struct UserError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class Downloader {
    enum Event {
        case title(String)
        case progress(fraction: Double?, bytes: Int64?)
        case finished(file: URL, title: String?)
        case failed(String)
    }

    static let formatSelector =
        "bv*[ext=mp4][vcodec^=av01][height<=2160]/bv*[ext=mp4][vcodec^=avc1]/bv*[ext=mp4]/b[ext=mp4]"

    private var process: Process?
    private var infoProcess: Process?
    private var pollTimer: Timer?

    var isRunning: Bool { process?.isRunning ?? false }

    static func findYtDlp() -> URL? {
        findTool("yt-dlp", extra: [Storage.appSupport.appendingPathComponent("bin/yt-dlp").path])
    }

    static func findFfmpeg() -> URL? {
        findTool("ffmpeg", extra: [])
    }

    private static func findTool(_ name: String, extra: [String]) -> URL? {
        (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }

    func fetchInfo(urlString: String, preferLowFrameRate: Bool = false) async throws -> VideoInfo {
        guard let tool = Self.findYtDlp() else {
            throw UserError(message: L("yt-dlp nicht gefunden. Installieren mit: brew install yt-dlp"))
        }
        let process = Process()
        process.executableURL = tool
        process.arguments = ["-J", "--no-playlist", "--color", "never", urlString]
        process.environment = Self.environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        infoProcess = process
        defer { infoProcess = nil }

        let result: (Data, Data, Int32, Process.TerminationReason) = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try process.run() } catch { cont.resume(throwing: error); return }
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                cont.resume(returning: (outData, errBox.data, process.terminationStatus, process.terminationReason))
            }
        }

        let (data, errData, status, reason) = result
        if reason == .uncaughtSignal { throw CancellationError() }
        guard status == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UserError(message: Self.errorMessage(from: errData) ?? L("Video konnte nicht gelesen werden."))
        }
        if json["is_live"] as? Bool == true {
            throw UserError(message: L("Livestreams werden nicht unterstützt."))
        }

        let duration = json["duration"] as? Double
        let formats = json["formats"] as? [[String: Any]] ?? []
        return VideoInfo(
            url: urlString,
            title: json["title"] as? String ?? L("Unbenanntes Video"),
            channel: (json["channel"] ?? json["uploader"]) as? String,
            duration: duration,
            thumbnail: (json["thumbnail"] as? String).flatMap(URL.init(string:)),
            qualities: Self.qualities(from: formats, duration: duration, preferLowFrameRate: preferLowFrameRate)
        )
    }

    func cancelInfo() {
        if let infoProcess, infoProcess.isRunning { infoProcess.terminate() }
    }

    static func qualities(from formats: [[String: Any]], duration: Double?, preferLowFrameRate: Bool = false) -> [QualityOption] {
        let av1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)

        struct Candidate {
            let id: String, codec: String, short: Int, fps: Int?, bytes: Int64?, tbr: Double
        }
        let candidates: [Candidate] = formats.compactMap { f in
            guard f["ext"] as? String == "mp4",
                  let id = f["format_id"] as? String,
                  let vcodec = f["vcodec"] as? String,
                  (f["acodec"] as? String ?? "none") == "none",
                  let w = f["width"] as? Int, let h = f["height"] as? Int
            else { return nil }
            let codec: String
            if vcodec.hasPrefix("av01") && av1 { codec = "AV1" }
            else if vcodec.hasPrefix("avc1") { codec = "H.264" }
            else { return nil }
            let tbr = f["tbr"] as? Double ?? 0
            let size = (f["filesize"] as? NSNumber)?.int64Value
                ?? (f["filesize_approx"] as? NSNumber)?.int64Value
                ?? duration.map { Int64(tbr * 125 * $0) }
            return Candidate(id: id, codec: codec, short: min(w, h),
                             fps: (f["fps"] as? NSNumber)?.intValue, bytes: size, tbr: tbr)
        }

        func tier(_ short: Int) -> (rank: Int, label: String)? {
            switch short {
            case 2000...2200: return (2160, "4K")
            case 1400..<2000: return (1440, "1440p")
            case 1000..<1400: return (1080, "1080p")
            case 700..<1000: return (720, "720p")
            case 1..<700: return (480, "SD")
            default: return nil
            }
        }

        var best: [Int: (label: String, candidate: Candidate)] = [:]
        for c in candidates {
            guard let t = tier(c.short) else { continue }
            if let current = best[t.rank]?.candidate {
                let cFps = c.fps ?? 0, curFps = current.fps ?? 0
                let higher = (cFps, c.tbr) > (curFps, current.tbr)
                let fpsBetter: Bool
                if preferLowFrameRate && (cFps <= 30) != (curFps <= 30) {
                    fpsBetter = cFps <= 30
                } else {
                    fpsBetter = higher
                }
                let better =
                    (c.codec == "AV1" && current.codec != "AV1") ||
                    (c.codec == current.codec && fpsBetter)
                if !better { continue }
            }
            best[t.rank] = (t.label, c)
        }
        return best.keys.sorted(by: >).map { rank in
            let (label, c) = best[rank]!
            return QualityOption(id: c.id, label: label, codec: c.codec, fps: c.fps, bytes: c.bytes)
        }
    }

    func start(urlString: String, id: UUID, formatID: String?, range: ClosedRange<Double>?,
               estimatedBytes: Int64?, handler: @escaping (Event) -> Void) {
        guard let tool = Self.findYtDlp() else {
            handler(.failed(L("yt-dlp nicht gefunden. Installieren mit: brew install yt-dlp")))
            return
        }

        var args = [
            "--no-playlist", "--no-simulate", "--progress", "--newline", "--color", "never",
            "-f", formatID ?? Self.formatSelector,
            "-o", Storage.videosDir.appendingPathComponent("\(id.uuidString).%(ext)s").path,
            "--print", "before_dl:LPTITLE:%(title)s",
            "--print", "after_move:LPFILE:%(filepath)s",
            "--progress-template", "download:LPPROG:%(progress._percent_str)s|%(progress.downloaded_bytes)s",
        ]
        if let range {
            args += ["--download-sections", "*\(Int(range.lowerBound))-\(Int(range.upperBound.rounded(.up)))"]
        }
        args.append(urlString)

        let process = Process()
        process.executableURL = tool
        process.arguments = args
        process.environment = Self.environment

        let session = Session(estimatedBytes: estimatedBytes, handler: handler)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        out.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            DispatchQueue.main.async { session.stdout(data) }
        }
        err.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            DispatchQueue.main.async { session.stderr(data) }
        }
        process.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let restOut = out.fileHandleForReading.readDataToEndOfFile()
            let restErr = err.fileHandleForReading.readDataToEndOfFile()
            let status = p.terminationStatus
            let reason = p.terminationReason
            DispatchQueue.main.async {
                session.stdout(restOut + Data("\n".utf8))
                session.stderr(restErr + Data("\n".utf8))
                self?.process = nil
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                if reason == .uncaughtSignal {
                    Self.removeFiles(for: id)
                    return
                }
                session.finish(status: status)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            handler(.failed(String(format: L("yt-dlp konnte nicht gestartet werden: %@"), error.localizedDescription)))
            return
        }

        if range != nil {
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let bytes = Self.partialSize(for: id)
                    guard bytes > 0 else { return }
                    let fraction = estimatedBytes.flatMap { $0 > 0 ? min(Double(bytes) / Double($0), 0.99) : nil }
                    handler(.progress(fraction: fraction, bytes: bytes))
                }
            }
        }
    }

    func cancel() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    static func partialSize(for id: UUID) -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Storage.videosDir.path) else { return 0 }
        return files.filter { $0.hasPrefix(id.uuidString) }.reduce(0) { sum, name in
            let path = Storage.videosDir.appendingPathComponent(name).path
            return sum + ((try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func removeFiles(for id: UUID) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Storage.videosDir.path) else { return }
        for name in files where name.hasPrefix(id.uuidString) {
            try? fm.removeItem(at: Storage.videosDir.appendingPathComponent(name))
        }
    }

    static func errorMessage(from data: Data) -> String? {
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (lines.last(where: { $0.contains("ERROR") }) ?? lines.last)
            .map { $0.replacingOccurrences(of: "ERROR: ", with: "") }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

@MainActor
private final class Session {
    let handler: (Downloader.Event) -> Void
    let estimatedBytes: Int64?
    private var outBuffer = ""
    private var errBuffer = ""
    private var title: String?
    private var file: URL?
    private var errData = Data()

    init(estimatedBytes: Int64?, handler: @escaping (Downloader.Event) -> Void) {
        self.estimatedBytes = estimatedBytes
        self.handler = handler
    }

    func stdout(_ data: Data) {
        for line in lines(from: data, buffer: &outBuffer) { handle(line) }
    }

    func stderr(_ data: Data) {
        for line in lines(from: data, buffer: &errBuffer) {
            if line.hasPrefix("LP") { handle(line) } else { errData.append(Data((line + "\n").utf8)) }
        }
    }

    func finish(status: Int32) {
        if status == 0, let file, FileManager.default.fileExists(atPath: file.path) {
            handler(.finished(file: file, title: title))
        } else {
            handler(.failed(Downloader.errorMessage(from: errData) ?? String(format: L("Download fehlgeschlagen (Code %d)."), Int(status))))
        }
    }

    private func handle(_ line: String) {
        if line.hasPrefix("LPTITLE:") {
            let t = String(line.dropFirst("LPTITLE:".count))
            title = t
            handler(.title(t))
        } else if line.hasPrefix("LPFILE:") {
            file = URL(fileURLWithPath: String(line.dropFirst("LPFILE:".count)))
        } else if line.hasPrefix("LPPROG:") {
            let parts = line.dropFirst("LPPROG:".count).split(separator: "|", omittingEmptySubsequences: false)
            let percent = parts.first.flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
            let bytes = parts.count > 1 ? Int64(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            var fraction = percent.map { min(max($0 / 100, 0), 1) }
            if fraction == nil, let bytes, let estimatedBytes, estimatedBytes > 0 {
                fraction = min(Double(bytes) / Double(estimatedBytes), 0.99)
            }
            handler(.progress(fraction: fraction, bytes: bytes))
        }
    }

    private func lines(from data: Data, buffer: inout String) -> [String] {
        guard !data.isEmpty else { return [] }
        buffer += String(decoding: data, as: UTF8.self)
        var parts = buffer.components(separatedBy: CharacterSet.newlines)
        buffer = parts.removeLast()
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
