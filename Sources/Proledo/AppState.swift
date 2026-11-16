import AppKit
import AVFoundation
import ServiceManagement
import UniformTypeIdentifiers

enum AddPhase: Equatable {
    case idle
    case loadingInfo
    case ready(VideoInfo)
    case downloading(title: String, fraction: Double?, bytes: Int64?)
    case importing
    case failed(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var library: [VideoItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    @Published private(set) var screens: [ScreenInfo] = []
    @Published private(set) var pauseReason: String?
    @Published var phase: AddPhase = .idle
    @Published private(set) var convertingID: UUID?
    @Published var draft = DownloadDraft()
    @Published private(set) var downloadStartedAt = Date()
    @Published private(set) var downloadIsClip = false
    @Published private(set) var downloadEstimate: Int64?
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            Storage.save(settings, to: Storage.settingsFile)
            applyAll()
            processEcoQueue()
        }
    }

    private let engine = WallpaperEngine()
    private let bars = BarOverlayController()
    private let downloader = Downloader()
    private let power = PowerMonitor()
    private var infoTask: Task<Void, Never>?

    init() {
        settings = Storage.load(Settings.self, from: Storage.settingsFile) ?? Settings()
        library = (Storage.load([VideoItem].self, from: Storage.libraryFile) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        for item in library {
            if let image = NSImage(contentsOf: item.thumbnailURL) { thumbnails[item.id] = image }
        }
    }

    func start() {
        power.onChange = { [weak self] in self?.applyAll() }
        engine.onPlayersChanged = { [weak self] in self?.applyBars() }
        power.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
                self?.applyAll()
            }
        }

        refreshScreens()
        applyAll()
        processEcoQueue()
    }

    func stop() {
        downloader.cancel()
        downloader.cancelInfo()
        engine.tearDown()
        bars.tearDown()
    }

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginHint: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginHint = nil
        } catch {
            launchAtLoginHint = "Autostart ging nicht: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginHint = "Bitte in Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben."
        }
    }

    var ytDlpAvailable: Bool { Downloader.findYtDlp() != nil }
    var ffmpegAvailable: Bool { Downloader.findFfmpeg() != nil }

    func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let id = screen.stableID else { return nil }
            let scale = screen.backingScaleFactor
            return ScreenInfo(
                id: id,
                name: screen.isBuiltIn ? "MacBook-Display" : screen.localizedName,
                isBuiltIn: screen.isBuiltIn,
                pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
            )
        }
        .sorted { $0.isBuiltIn && !$1.isBuiltIn }
    }

    func assignment(for screenID: String) -> UUID? {
        guard let id = settings.assignments[screenID],
              library.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func assign(_ videoID: UUID?, to screenID: String) {
        settings.assignments[screenID] = videoID
    }

    func assignToAll(_ videoID: UUID?) {
        var s = settings
        for screen in screens { s.assignments[screen.id] = videoID }
        settings = s
    }

    func options(for screenID: String) -> ScreenOptions {
        settings.screenOptions[screenID] ?? ScreenOptions()
    }

    func setOptions(_ options: ScreenOptions, for screenID: String) {
        settings.screenOptions[screenID] = options == ScreenOptions() ? nil : options
    }

    var activeScreenCount: Int {
        screens.filter { assignment(for: $0.id) != nil }.count
    }

    func togglePause() {
        settings.userPaused.toggle()
    }

    private func currentPauseReason() -> String? {
        if settings.userPaused { return "Pausiert" }
        if power.screensAsleep { return "Bildschirm aus" }
        if power.locked { return "Gesperrt" }
        if settings.pauseOnBattery && power.onBattery { return "Pausiert im Akkubetrieb" }
        if power.lowPower { return "Pausiert im Energiesparmodus" }
        return nil
    }

    func applyAll() {
        var desired: [String: URL] = [:]
        for (screenID, videoID) in settings.assignments {
            if let item = library.first(where: { $0.id == videoID }) {
                let eco = settings.powerSaving ? item.ecoURL : nil
                desired[screenID] = eco ?? item.fileURL
            }
        }
        pauseReason = currentPauseReason()
        engine.screensWithStrips = Set(settings.screenOptions.filter { $0.value.hideMenuBar || $0.value.hideDock }.keys)
        engine.apply(desired: desired, playbackAllowed: pauseReason == nil)
        applyBars()
    }

    private func applyBars() {
        bars.apply(options: settings.screenOptions) { [weak self] id in self?.engine.player(for: id) }
    }

    func loadInfo(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme, scheme.hasPrefix("http"), url.host != nil else {
            phase = .failed("Das ist kein gültiger Link.")
            return
        }
        phase = .loadingInfo
        infoTask = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await self.downloader.fetchInfo(urlString: text, preferLowFrameRate: self.settings.powerSaving)
                guard self.phase == .loadingInfo else { return }
                self.draft = self.defaultDraft(for: info)
                self.phase = .ready(info)
            } catch is CancellationError {
            } catch {
                if self.phase == .loadingInfo { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func defaultDraft(for info: VideoInfo) -> DownloadDraft {
        var draft = DownloadDraft()
        draft.qualityID = settings.powerSaving
            ? (info.qualities.first { $0.label != "4K" } ?? info.qualities.first)?.id
            : info.qualities.first?.id
        let duration = info.duration ?? 0
        if duration > 20 * 60 {
            draft.useRange = true
            draft.from = "0:00"
            draft.to = "10:00"
        } else {
            draft.useRange = false
            draft.from = "0:00"
            draft.to = Format.duration(duration)
        }
        return draft
    }

    func selectedQuality(in info: VideoInfo) -> QualityOption? {
        info.qualities.first { $0.id == draft.qualityID } ?? info.qualities.first
    }

    func validatedRange(for info: VideoInfo) -> (range: ClosedRange<Double>?, error: String?) {
        guard draft.useRange else { return (nil, nil) }
        guard let from = Format.parseTime(draft.from), let rawTo = Format.parseTime(draft.to) else {
            return (nil, "Zeiten bitte als m:ss oder h:mm:ss eingeben.")
        }
        let to = info.duration.map { min(rawTo, $0) } ?? rawTo
        if let duration = info.duration, from >= duration {
            return (nil, "Der Anfang liegt hinter dem Videoende (\(Format.duration(duration))).")
        }
        if to <= from { return (nil, "Das Ende muss nach dem Anfang liegen.") }
        if to - from < 3 { return (nil, "Der Ausschnitt sollte mindestens 3 Sekunden lang sein.") }
        return (from...to, nil)
    }

    func estimatedBytes(for quality: QualityOption?, in info: VideoInfo) -> Int64? {
        guard let bytes = quality?.bytes else { return nil }
        guard let range = validatedRange(for: info).range, let duration = info.duration, duration > 0 else {
            return bytes
        }
        return Int64(Double(bytes) * (range.upperBound - range.lowerBound) / duration)
    }

    func startDownload(_ info: VideoInfo) {
        let check = validatedRange(for: info)
        guard check.error == nil, !downloader.isRunning else { return }
        if check.range != nil && !ffmpegAvailable { return }

        let quality = selectedQuality(in: info)
        let estimate = estimatedBytes(for: quality, in: info)
        let id = UUID()
        downloadStartedAt = Date()
        downloadIsClip = check.range != nil
        downloadEstimate = estimate
        phase = .downloading(title: info.title, fraction: nil, bytes: nil)

        downloader.start(urlString: info.url, id: id, formatID: quality?.id, range: check.range,
                         estimatedBytes: estimate) { [weak self] event in
            guard let self, case .downloading(let title, let fraction, let bytes) = self.phase else { return }
            switch event {
            case .title:
                break
            case .progress(let newFraction, let newBytes):
                self.phase = .downloading(title: title, fraction: newFraction ?? fraction, bytes: newBytes ?? bytes)
            case .finished(let file, _):
                self.phase = .importing
                Task { await self.addToLibrary(id: id, file: file, title: info.title, source: info.url) }
            case .failed(let message):
                Downloader.removeFiles(for: id)
                self.phase = .failed(message)
            }
        }
    }

    func cancelAdd() {
        infoTask?.cancel()
        downloader.cancelInfo()
        downloader.cancel()
        phase = .idle
    }

    func importLocalFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Video als Hintergrund wählen"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let id = UUID()
        let target = Storage.videosDir.appendingPathComponent("\(id.uuidString).\(source.pathExtension.lowercased())")
        phase = .importing
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            phase = .failed("Kopieren fehlgeschlagen: \(error.localizedDescription)")
            return
        }
        Task {
            await addToLibrary(id: id, file: target,
                               title: source.deletingPathExtension().lastPathComponent, source: nil)
        }
    }

    private func addToLibrary(id: UUID, file: URL, title: String, source: String?) async {
        let asset = AVURLAsset(url: file)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable else {
            try? FileManager.default.removeItem(at: file)
            phase = .failed("Dieses Videoformat kann der Mac nicht abspielen.")
            return
        }
        let duration = (try? await asset.load(.duration)).map(\.seconds).flatMap { $0.isFinite ? $0 : nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value

        let item = VideoItem(id: id, title: title, sourceURL: source, fileName: file.lastPathComponent,
                             addedAt: Date(), duration: duration, fileSize: size)
        if let image = await Self.makeThumbnail(asset: asset, duration: duration ?? 0, to: item.thumbnailURL) {
            thumbnails[id] = image
        }
        library.append(item)
        Storage.save(library, to: Storage.libraryFile)
        phase = .idle
        processEcoQueue()

        if settings.assignments.isEmpty, let target = screens.first(where: \.isBuiltIn) ?? screens.first {
            assign(item.id, to: target.id)
        } else {
            applyAll()
        }
    }

    private static func makeThumbnail(asset: AVURLAsset, duration: Double, to url: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 360, height: 360)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: min(duration * 0.2, 10), preferredTimescale: 600)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: url)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    var librarySize: Int64 {
        library.reduce(0) { $0 + ($1.fileSize ?? 0) + ($1.hasSeparateEco ? ($1.ecoFileSize ?? 0) : 0) }
    }

    private var ecoTask: Task<Void, Never>?
    private var ecoFailed: Set<UUID> = []

    func processEcoQueue() {
        guard settings.powerSaving, ecoTask == nil,
              let item = library.first(where: { $0.ecoFileName == nil && !ecoFailed.contains($0.id) })
        else { return }
        convertingID = item.id
        let target = Storage.videosDir.appendingPathComponent("\(item.id.uuidString)-eco.mp4")
        ecoTask = Task { [weak self] in
            let result = await EcoConverter.convert(source: item.fileURL, to: target)
            guard let self else { return }
            self.ecoTask = nil
            self.convertingID = nil
            guard let index = self.library.firstIndex(where: { $0.id == item.id }) else {
                try? FileManager.default.removeItem(at: target)
                self.processEcoQueue()
                return
            }
            switch result {
            case .converted(let url):
                self.library[index].ecoFileName = url.lastPathComponent
                self.library[index].ecoFileSize =
                    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            case .notNeeded:
                self.library[index].ecoFileName = item.fileName
            case .failed:
                self.ecoFailed.insert(item.id)
            }
            Storage.save(self.library, to: Storage.libraryFile)
            self.applyAll()
            self.processEcoQueue()
        }
    }

    func delete(_ item: VideoItem) {
        library.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        Storage.save(library, to: Storage.libraryFile)
        var s = settings
        s.assignments = s.assignments.filter { $0.value != item.id }
        settings = s
        applyAll()
        try? FileManager.default.removeItem(at: item.fileURL)
        try? FileManager.default.removeItem(at: item.thumbnailURL)
        if item.hasSeparateEco, let eco = item.ecoURL { try? FileManager.default.removeItem(at: eco) }
    }

    func revealInFinder(_ item: VideoItem? = nil) {
        NSWorkspace.shared.activateFileViewerSelecting([item?.fileURL ?? Storage.videosDir])
    }
}
