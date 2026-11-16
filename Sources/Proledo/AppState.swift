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
        startUpdateChecks()
    }

    func stop() {
        generatorCancel.set()
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
            launchAtLoginHint = String(format: L("Autostart ging nicht: %@"), error.localizedDescription)
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginHint = L("Bitte in Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben.")
        }
    }

    struct UpdateInfo: Equatable {
        let version: String
        let url: URL
    }

    static let repositoryURL = URL(string: "https://github.com/drieken/Proledo")!
    @Published private(set) var update: UpdateInfo?
    private var updateTimer: Timer?

    func startUpdateChecks() {
        Task { await checkForUpdates() }
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.checkForUpdates() }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    func checkForUpdates() async {
        guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let api = URL(string: "https://api.github.com/repos/drieken/Proledo/releases/latest"),
              let (data, _) = try? await URLSession.shared.data(from: api),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        update = Self.isNewer(latest, than: current) ? UpdateInfo(version: latest, url: page) : nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    var ytDlpAvailable: Bool { Downloader.findYtDlp() != nil }
    var ffmpegAvailable: Bool { Downloader.findFfmpeg() != nil }

    func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let id = screen.stableID else { return nil }
            let scale = screen.backingScaleFactor
            return ScreenInfo(
                id: id,
                name: screen.isBuiltIn ? L("MacBook-Display") : screen.localizedName,
                isBuiltIn: screen.isBuiltIn,
                pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                frame: screen.frame
            )
        }
        .sorted { $0.isBuiltIn && !$1.isBuiltIn }
    }

    func assignment(for screenID: String) -> UUID? {
        if isRotating(screenID) { return rotatingVideo(for: screenID) }
        return fixedAssignment(for: screenID)
    }

    func fixedAssignment(for screenID: String) -> UUID? {
        guard let id = settings.assignments[screenID],
              library.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func isRotating(_ screenID: String) -> Bool {
        settings.rotatingScreens.contains(screenID) && !library.isEmpty
    }

    private func rotatingVideo(for screenID: String) -> UUID? {
        guard !library.isEmpty else { return nil }
        let interval = Double(max(1, settings.rotationMinutes) * 60)
        let step = Int(Date().timeIntervalSince1970 / interval)
        let offset = screens.firstIndex { $0.id == screenID } ?? 0
        return library[(step + offset) % library.count].id
    }

    func assign(_ videoID: UUID?, to screenID: String) {
        var s = settings
        s.assignments[screenID] = videoID
        s.rotatingScreens.removeAll { $0 == screenID }
        settings = s
    }

    func setRotating(_ rotating: Bool, for screenID: String) {
        var s = settings
        s.rotatingScreens.removeAll { $0 == screenID }
        if rotating { s.rotatingScreens.append(screenID) }
        settings = s
    }

    func assignToAll(_ videoID: UUID?) {
        var s = settings
        for screen in screens { s.assignments[screen.id] = videoID }
        s.rotatingScreens = []
        settings = s
    }

    func rotateAll() {
        settings.rotatingScreens = screens.map(\.id)
    }

    private var rotationTimer: Timer?

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard screens.contains(where: { isRotating($0.id) }), library.count > 1 else { return }
        let interval = Double(max(1, settings.rotationMinutes) * 60)
        let now = Date().timeIntervalSince1970
        let next = Date(timeIntervalSince1970: (floor(now / interval) + 1) * interval + 0.5)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
                self?.applyAll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
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
        if settings.userPaused { return L("Pausiert") }
        if power.screensAsleep { return L("Bildschirm aus") }
        if power.locked { return L("Gesperrt") }
        if settings.pauseOnBattery && power.onBattery { return L("Pausiert im Akkubetrieb") }
        if power.lowPower { return L("Pausiert im Energiesparmodus") }
        return nil
    }

    func applyAll() {
        var desired: [String: URL] = [:]
        let screenIDs = Set(settings.assignments.keys).union(settings.rotatingScreens)
        for screenID in screenIDs {
            if let videoID = assignment(for: screenID), let item = library.first(where: { $0.id == videoID }) {
                let eco = settings.powerSaving ? item.ecoURL : nil
                desired[screenID] = eco ?? item.fileURL
            }
        }
        scheduleRotation()
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
            phase = .failed(L("Das ist kein gültiger Link."))
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
            return (nil, L("Zeiten bitte als m:ss oder h:mm:ss eingeben."))
        }
        let to = info.duration.map { min(rawTo, $0) } ?? rawTo
        if let duration = info.duration, from >= duration {
            return (nil, String(format: L("Der Anfang liegt hinter dem Videoende (%@)."), Format.duration(duration)))
        }
        if to <= from { return (nil, L("Das Ende muss nach dem Anfang liegen.")) }
        if to - from < 3 { return (nil, L("Der Ausschnitt sollte mindestens 3 Sekunden lang sein.")) }
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
        panel.allowsMultipleSelection = true
        panel.message = L("Video als Hintergrund wählen")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    @discardableResult
    func importFiles(_ urls: [URL]) -> Bool {
        let movies = urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .movie) == true
        }
        guard !movies.isEmpty else { return false }
        phase = .importing
        Task {
            for source in movies {
                let id = UUID()
                let target = Storage.videosDir.appendingPathComponent("\(id.uuidString).\(source.pathExtension.lowercased())")
                do {
                    try FileManager.default.copyItem(at: source, to: target)
                } catch {
                    phase = .failed(String(format: L("Kopieren fehlgeschlagen: %@"), error.localizedDescription))
                    return
                }
                await addToLibrary(id: id, file: target,
                                   title: source.deletingPathExtension().lastPathComponent, source: nil)
            }
        }
        return true
    }

    @discardableResult
    private func addToLibrary(id: UUID, file: URL, title: String, source: String?,
                              generated: Bool = false, updatesPhase: Bool = true) async -> Bool {
        let asset = AVURLAsset(url: file)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable else {
            try? FileManager.default.removeItem(at: file)
            if updatesPhase { phase = .failed(L("Dieses Videoformat kann der Mac nicht abspielen.")) }
            return false
        }
        let duration = (try? await asset.load(.duration)).map(\.seconds).flatMap { $0.isFinite ? $0 : nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value

        var item = VideoItem(id: id, title: title, sourceURL: source, fileName: file.lastPathComponent,
                             addedAt: Date(), duration: duration, fileSize: size)
        if generated { item.generated = true }
        if let image = await Self.makeThumbnail(asset: asset, duration: duration ?? 0, to: item.thumbnailURL) {
            thumbnails[id] = image
        }
        library.append(item)
        Storage.save(library, to: Storage.libraryFile)
        if updatesPhase { phase = .idle }
        processEcoQueue()

        if settings.assignments.isEmpty, let target = screens.first(where: \.isBuiltIn) ?? screens.first {
            assign(item.id, to: target.id)
        } else {
            applyAll()
        }
        return true
    }

    @Published var generatorOpen = false
    @Published var generatorOptions = TopoOptions()
    @Published var generatorScreenID: String?
    @Published private(set) var generatorPreview: NSImage?
    @Published private(set) var generatorProgress: Double?
    @Published private(set) var generatorStartedAt = Date()
    @Published private(set) var generatorError: String?
    private var previewTask: Task<Void, Never>?
    private var generateTask: Task<Void, Never>?
    private let generatorCancel = CancelFlag()

    var generatorScreen: ScreenInfo? {
        screens.first { $0.id == generatorScreenID } ?? screens.first
    }

    func generatorSize(for screen: ScreenInfo) -> (width: Int, height: Int) {
        let cap: CGFloat = settings.powerSaving ? 1440 : 2160
        let w = screen.pixelSize.width, h = screen.pixelSize.height
        let factor = min(1, cap / min(w, h))
        func even(_ v: CGFloat) -> Int { Int((v * factor / 2).rounded()) * 2 }
        return (even(w), even(h))
    }

    func openGenerator() {
        if generatorProgress != nil {
            generatorOpen = true
            return
        }
        if generatorScreenID == nil || !screens.contains(where: { $0.id == generatorScreenID }) {
            generatorScreenID = (screens.first { assignment(for: $0.id) == nil } ?? screens.first)?.id
        }
        generatorError = nil
        generatorOpen = true
        refreshGeneratorPreview()
    }

    func closeGenerator() {
        generatorOpen = false
        if generatorProgress == nil { generatorPreview = nil }
    }

    func shuffleGeneratorPattern() {
        generatorOptions.seed = TopoOptions.randomSeed()
    }

    func refreshGeneratorPreview() {
        guard generatorOpen, let screen = generatorScreen else { return }
        let ratio = screen.pixelSize.width / max(screen.pixelSize.height, 1)
        let short: CGFloat = 300
        let size = ratio >= 1 ? (Int(short * ratio), Int(short)) : (Int(short), Int(short / ratio))
        let options = generatorOptions
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                TopoGenerator(width: size.0, height: size.1, options: options).still(at: 0.2)
            }.value
            guard !Task.isCancelled, let self, let image else { return }
            self.generatorPreview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    func startGeneration() {
        guard generatorProgress == nil, let screen = generatorScreen else { return }
        let size = generatorSize(for: screen)
        let options = generatorOptions
        let id = UUID()
        let target = Storage.videosDir.appendingPathComponent("\(id.uuidString).mp4")
        let title = String(format: L("Höhenlinien · %@"), screen.name)
        generatorError = nil
        generatorProgress = 0
        generatorStartedAt = Date()
        generatorCancel.reset()
        let cancel = generatorCancel

        generateTask = Task { [weak self] in
            let ok = await Task.detached(priority: .utility) {
                TopoGenerator(width: size.width, height: size.height, options: options).renderVideo(
                    to: target,
                    progress: { value in Task { @MainActor in self?.generatorProgress = value } },
                    isCancelled: { cancel.isSet }
                )
            }.value
            guard let self else { return }
            if ok, await self.addToLibrary(id: id, file: target, title: title, source: nil,
                                           generated: true, updatesPhase: false) {
                self.assign(id, to: screen.id)
                self.generatorProgress = nil
                self.generatorOpen = false
                self.generatorPreview = nil
                self.generatorOptions.seed = TopoOptions.randomSeed()
            } else {
                try? FileManager.default.removeItem(at: target)
                self.generatorProgress = nil
                if !cancel.isSet { self.generatorError = L("Das Video konnte nicht erzeugt werden.") }
            }
            self.generateTask = nil
        }
    }

    func cancelGeneration() {
        generatorCancel.set()
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

    private var menuThumbnailCache: [UUID: NSImage] = [:]

    func menuThumbnail(for id: UUID) -> NSImage {
        if let cached = menuThumbnailCache[id] { return cached }
        let size = NSSize(width: 32, height: 18)
        let source = thumbnails[id]
        let image = NSImage(size: size, flipped: false) { rect in
            let clip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            clip.addClip()
            NSColor.black.setFill()
            rect.fill()
            if let source, source.size.width > 0, source.size.height > 0 {
                let scale = max(rect.width / source.size.width, rect.height / source.size.height)
                let drawn = NSSize(width: source.size.width * scale, height: source.size.height * scale)
                source.draw(in: NSRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
            }
            return true
        }
        if source != nil { menuThumbnailCache[id] = image }
        return image
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

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = library.firstIndex(where: { $0.id == id }),
              library[index].title != trimmed else { return }
        library[index].title = trimmed
        Storage.save(library, to: Storage.libraryFile)
    }

    func delete(_ item: VideoItem) {
        library.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        Storage.save(library, to: Storage.libraryFile)
        var s = settings
        s.assignments = s.assignments.filter { $0.value != item.id }
        settings = s
        applyAll()
        let fm = FileManager.default
        let safeTitle = item.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let named = Storage.videosDir.appendingPathComponent(
            "\(safeTitle.isEmpty ? item.id.uuidString : safeTitle).\(item.fileURL.pathExtension)")
        let toTrash = (try? fm.moveItem(at: item.fileURL, to: named)) != nil ? named : item.fileURL
        if (try? fm.trashItem(at: toTrash, resultingItemURL: nil)) == nil {
            try? fm.removeItem(at: toTrash)
        }
        try? fm.removeItem(at: item.thumbnailURL)
        if item.hasSeparateEco, let eco = item.ecoURL { try? fm.removeItem(at: eco) }
    }

    func revealInFinder(_ item: VideoItem? = nil) {
        NSWorkspace.shared.activateFileViewerSelecting([item?.fileURL ?? Storage.videosDir])
    }
}
