import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView()
                .padding(.bottom, 12)
            Divider()
            if state.generatorOpen {
                GeneratorCard()
                    .padding(.vertical, 12)
            } else {
                AddVideoCard()
                    .padding(.vertical, 12)
                Divider()
                ScreensCard()
                    .padding(.vertical, 12)
                if !state.library.isEmpty {
                    Divider()
                    LibraryCard()
                        .padding(.vertical, 12)
                }
            }
            Divider()
            FooterView()
                .padding(.top, 8)
        }
        .padding(14)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SwitchRow: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .help(help)
    }
}

private struct Card<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Card where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

private struct HintText: View {
    let text: String
    var color: Color = .secondary
    var icon: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(color)
        .textSelection(.enabled)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    private var status: String {
        if let progress = state.generatorProgress, !state.generatorOpen {
            return String(format: L("Hintergrund wird erzeugt · %d %%"), Int(progress * 100))
        }
        if let reason = state.pauseReason { return reason }
        let count = state.activeScreenCount
        if count == 0 { return L("Kein Video aktiv") }
        return count == 1 ? L("Läuft auf 1 Monitor") : String(format: L("Läuft auf %d Monitoren"), count)
    }

    private var playing: Binding<Bool> {
        Binding(get: { !state.settings.userPaused }, set: { state.settings.userPaused = !$0 })
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Proledo").font(.system(size: 13, weight: .semibold))
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: playing)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(state.settings.userPaused ? L("Wiedergabe fortsetzen") : L("Wiedergabe pausieren"))
        }
    }
}

private struct AddVideoCard: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText = ""
    @FocusState private var linkFocused: Bool

    var body: some View {
        Card(title: L("Video hinzufügen")) {
            switch state.phase {
            case .idle, .failed, .loadingInfo:
                linkField
            case .ready(let info):
                ReadyView(info: info)
            case .downloading(let title, let fraction, let bytes):
                progressView(title: title, fraction: fraction, bytes: bytes)
            case .importing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Video wird vorbereitet…")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isLoading: Bool { state.phase == .loadingInfo }

    private var canGo: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    @ViewBuilder
    private var linkField: some View {
        HStack(spacing: 6) {
            TextField(L("YouTube-Link einfügen"), text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canGo { state.loadInfo(urlText) } }
                .disabled(isLoading)
            if isLoading {
                ProgressView().controlSize(.small)
                Button {
                    state.cancelAdd()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Abbrechen"))
            } else if canGo {
                Button {
                    state.loadInfo(urlText)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)
                .help(L("Weiter"))
            } else {
                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.loadInfo(urlText)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Link aus der Zwischenablage einfügen und prüfen"))
            }
        }

        if isLoading {
            HintText(text: L("Video-Infos werden geladen…"))
        } else if case .failed(let message) = state.phase {
            HintText(text: message, color: .red, icon: "exclamationmark.triangle.fill")
        }
        if !state.ytDlpAvailable {
            HintText(text: L("yt-dlp fehlt. Installieren mit: brew install yt-dlp"), color: .orange,
                     icon: "exclamationmark.triangle.fill")
        }

        VStack(spacing: 0) {
            MenuRow(icon: "folder", title: L("Eigene Videodatei wählen…")) {
                state.importLocalFile()
            }
            if let progress = state.generatorProgress {
                MenuRow(icon: "scribble.variable",
                        title: String(format: L("Wird erzeugt · %d %%"), Int(progress * 100))) {
                    state.openGenerator()
                }
            } else {
                MenuRow(icon: "scribble.variable", title: L("Hintergrund erzeugen…")) {
                    state.openGenerator()
                }
            }
        }
        .padding(.horizontal, -6)
    }

    private func progressView(title: String, fraction: Double?, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    state.cancelAdd()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Download abbrechen"))
            }
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(progressText(fraction: fraction, bytes: bytes, now: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressText(fraction: Double?, bytes: Int64?, now: Date) -> String {
        var parts: [String] = []
        if let fraction { parts.append("\(Int(fraction * 100)) %") }
        if let bytes, bytes > 0 {
            if state.downloadIsClip, let estimate = state.downloadEstimate {
                parts.append(String(format: L("%@ von ≈ %@"), Format.bytes(bytes), Format.bytes(estimate)))
            } else {
                parts.append(Format.bytes(bytes))
            }
        }
        if parts.isEmpty {
            let elapsed = Format.duration(max(0, now.timeIntervalSince(state.downloadStartedAt)))
            return (state.downloadIsClip ? L("Ausschnitt wird geladen und geschnitten") : L("Download startet")) + " · \(elapsed)"
        }
        return parts.joined(separator: " · ")
    }
}

private struct ReadyView: View {
    @EnvironmentObject private var state: AppState
    let info: VideoInfo

    var body: some View {
        let check = state.validatedRange(for: info)
        let quality = state.selectedQuality(in: info)
        let estimate = state.estimatedBytes(for: quality, in: info)
        let needsFfmpeg = state.draft.useRange && !state.ffmpegAvailable

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: info.thumbnail) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.primary.opacity(0.08)
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title).font(.callout.weight(.medium)).lineLimit(2)
                    Text([info.channel, info.duration.map(Format.duration)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Divider()

            HStack {
                Text(L("Qualität")).font(.callout)
                Spacer()
                if info.qualities.isEmpty {
                    Text(L("Automatisch")).font(.callout).foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $state.draft.qualityID) {
                        ForEach(info.qualities) { q in
                            Text(qualityLabel(q)).tag(Optional(q.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $state.draft.useRange) {
                    Text(L("Nur einen Ausschnitt laden")).font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if state.draft.useRange {
                    HStack(spacing: 6) {
                        Text(L("Von")).font(.callout).foregroundStyle(.secondary)
                        timeField($state.draft.from)
                        Text(L("bis")).font(.callout).foregroundStyle(.secondary)
                        timeField($state.draft.to)
                        Spacer()
                        if let range = check.range {
                            Text("= \(Format.readableDuration(range.upperBound - range.lowerBound))")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help(L("Länge des Ausschnitts"))
                        }
                    }
                    if let error = check.error {
                        HintText(text: error, color: .red, icon: "exclamationmark.triangle.fill")
                    }
                    if needsFfmpeg {
                        HintText(text: L("Für Ausschnitte wird ffmpeg benötigt: brew install ffmpeg"),
                                 color: .orange, icon: "exclamationmark.triangle.fill")
                    }
                }
            }

            if let estimate, estimate > 2_000_000_000 {
                HintText(text: L("Ziemlich groß. Ein kürzerer Ausschnitt oder eine kleinere Qualität spart Platz."),
                         color: .orange, icon: "externaldrive.badge.exclamationmark")
            }

            Divider()

            HStack {
                if let estimate {
                    Text("≈ \(Format.bytes(estimate))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Abbrechen")) { state.cancelAdd() }
                    .buttonStyle(.bordered)
                Button {
                    state.startDownload(info)
                } label: {
                    Text(L("Laden"))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(check.error != nil || needsFfmpeg)
            }
        }
    }

    private func timeField(_ text: Binding<String>) -> some View {
        TextField("0:00", text: text)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 72)
    }

    private func qualityLabel(_ q: QualityOption) -> String {
        var parts = [q.label, q.codec]
        if let fps = q.fps, fps > 30 { parts.append("\(fps) fps") }
        if let bytes = state.estimatedBytes(for: q, in: info) { parts.append("≈ \(Format.bytes(bytes))") }
        return parts.joined(separator: " · ")
    }
}

private struct GeneratorCard: View {
    @EnvironmentObject private var state: AppState

    private var busy: Bool { state.generatorProgress != nil }

    var body: some View {
        Card(title: L("Hintergrund erzeugen")) {
            HStack(spacing: 10) {
                if !busy {
                    Button {
                        state.shuffleGeneratorPattern()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Neues Muster"))
                }
                Button {
                    state.closeGenerator()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(busy ? L("Im Hintergrund weiterrechnen") : L("Schließen"))
            }
            .foregroundStyle(.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                preview
                if let progress = state.generatorProgress {
                    progressView(progress)
                } else {
                    controls
                }
            }
        }
        .onChange(of: state.generatorOptions) { _, _ in state.refreshGeneratorPreview() }
        .onChange(of: state.generatorScreenID) { _, _ in state.refreshGeneratorPreview() }
    }

    private var previewRatio: CGFloat {
        guard let screen = state.generatorScreen, screen.pixelSize.height > 0 else { return 16 / 9 }
        return screen.pixelSize.width / screen.pixelSize.height
    }

    private var preview: some View {
        Color.black
            .aspectRatio(previewRatio, contentMode: .fit)
            .overlay {
                if let image = state.generatorPreview {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: 190)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(L("Stil")) {
                Picker("", selection: $state.generatorOptions.style) {
                    ForEach(TopoOptions.Style.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            row(L("Monitor")) {
                Picker("", selection: $state.generatorScreenID) {
                    ForEach(state.screens) { screen in
                        Text(screen.name).tag(Optional(screen.id))
                    }
                }
                .labelsHidden()
            }
            row(L("Dichte")) {
                Picker("", selection: $state.generatorOptions.density) {
                    ForEach(TopoOptions.Density.allCases) { Text(densityLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            row(L("Tempo")) {
                Picker("", selection: $state.generatorOptions.speed) {
                    ForEach(TopoOptions.Speed.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if state.generatorOptions.style == .contours {
                row(L("Linien")) {
                    Picker("", selection: $state.generatorOptions.lines) {
                        ForEach(TopoOptions.Lines.allCases) { Text(L($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            } else {
                row(L("Milchstraße")) {
                    Toggle("", isOn: $state.generatorOptions.milkyWay)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            row(L("Länge")) {
                Picker("", selection: $state.generatorOptions.seconds) {
                    ForEach([60, 120, 300], id: \.self) { Text(Format.readableDuration(Double($0))).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let screen = state.generatorScreen {
                let size = state.generatorSize(for: screen)
                HintText(text: String(format: L("%d × %d · nahtlose Schleife · ≈ %@"), size.width, size.height,
                                      Format.bytes(estimatedBytes(size))))
            }
            if let error = state.generatorError {
                HintText(text: error, color: .red, icon: "exclamationmark.triangle.fill")
            }

            HStack {
                Spacer()
                Button(L("Abbrechen")) { state.closeGenerator() }
                    .buttonStyle(.bordered)
                Button {
                    state.startGeneration()
                } label: {
                    Text(L("Erzeugen"))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            content()
        }
    }

    private func estimatedBytes(_ size: (width: Int, height: Int)) -> Int64 {
        let factor = state.generatorOptions.style == .stars ? 1.3 : 1.0
        let bitRate = Double(Wallpaper.bitRate(width: size.width, height: size.height, factor: factor))
        return Int64(bitRate * Double(state.generatorOptions.seconds) / 8 * 0.95)
    }

    private func densityLabel(_ density: TopoOptions.Density) -> String {
        guard state.generatorOptions.style == .stars else { return L(density.rawValue) }
        switch density {
        case .loose: return L("Wenige")
        case .normal: return L("Normal")
        case .dense: return L("Viele")
        }
    }

    private func progressView(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress)
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(progressText(progress, now: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Abbrechen")) { state.cancelGeneration() }
                    .controlSize(.small)
            }
        }
    }

    private func progressText(_ progress: Double, now: Date) -> String {
        let percent = "\(Int(progress * 100)) %"
        guard progress > 0.03 else { return "\(percent) · " + L("wird berechnet…") }
        let elapsed = now.timeIntervalSince(state.generatorStartedAt)
        let remaining = max(0, elapsed / progress * (1 - progress))
        return "\(percent) · " + String(format: L("noch ca. %@"), Format.readableDuration(max(remaining, 1)))
    }
}

private struct ScreensCard: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedID: String?

    private var selected: ScreenInfo? {
        state.screens.first { $0.id == selectedID } ?? state.screens.first
    }

    private var anyRotating: Bool {
        state.screens.contains { state.isRotating($0.id) }
    }

    var body: some View {
        Card(title: L("Monitore")) {
            if !state.library.isEmpty {
                Menu {
                    Button(L("Alle abwechselnd")) { state.rotateAll() }
                        .disabled(state.library.count < 2)
                    Divider()
                    ForEach(state.library) { item in
                        Button(item.title) { state.assignToAll(item.id) }
                    }
                    Divider()
                    Button(L("Alle aus")) { state.assignToAll(nil) }
                } label: {
                    Text(L("Für alle"))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } content: {
            if state.screens.count > 1 {
                ScreenMap(selectedID: Binding(get: { selected?.id }, set: { selectedID = $0 }))
            }
            if let screen = selected {
                ScreenDetail(screen: screen)
            }
            if anyRotating {
                HStack {
                    Text(L("Wechsel alle"))
                    Spacer()
                    Picker("", selection: $state.settings.rotationMinutes) {
                        ForEach([10, 30, 60, 120], id: \.self) { minutes in
                            Text(Format.readableDuration(Double(minutes * 60))).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if state.library.isEmpty {
                Text(L("Füge oben ein Video hinzu, dann kannst du es hier jedem Monitor zuordnen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScreenMap: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedID: String?

    var body: some View {
        GeometryReader { geo in
            let union = state.screens.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = min(geo.size.width / max(union.width, 1), geo.size.height / max(union.height, 1))
            let originX = (geo.size.width - union.width * scale) / 2
            let originY = (geo.size.height - union.height * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(state.screens) { screen in
                    let gap: CGFloat = 4
                    ScreenTile(screen: screen, selected: screen.id == selectedID)
                        .frame(width: max(screen.frame.width * scale - gap, 8),
                               height: max(screen.frame.height * scale - gap, 8))
                        .offset(x: originX + (screen.frame.minX - union.minX) * scale + gap / 2,
                                y: originY + (union.maxY - screen.frame.maxY) * scale + gap / 2)
                        .onTapGesture { selectedID = screen.id }
                }
            }
        }
        .frame(height: 104)
    }
}

private struct ScreenTile: View {
    @EnvironmentObject private var state: AppState
    let screen: ScreenInfo
    let selected: Bool

    var body: some View {
        Color.black
            .overlay {
                if let video = state.assignment(for: screen.id), let image = state.thumbnails[video] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.25),
                              lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if state.isRotating(screen.id) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .help(screen.name)
    }
}

private enum VideoChoice: Hashable {
    case off
    case rotate
    case video(UUID)
}

private struct ScreenDetail: View {
    @EnvironmentObject private var state: AppState
    let screen: ScreenInfo

    private var selection: Binding<VideoChoice> {
        Binding(
            get: {
                if state.isRotating(screen.id) { return .rotate }
                if let id = state.fixedAssignment(for: screen.id) { return .video(id) }
                return .off
            },
            set: { choice in
                switch choice {
                case .off: state.assign(nil, to: screen.id)
                case .rotate: state.setRotating(true, for: screen.id)
                case .video(let id): state.assign(id, to: screen.id)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(screen.name).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("", selection: selection) {
                    Text(L("Aus")).tag(VideoChoice.off)
                    if state.library.count > 1 {
                        Text(L("Alle abwechselnd")).tag(VideoChoice.rotate)
                    }
                    if !state.library.isEmpty { Divider() }
                    ForEach(state.library) { item in
                        Text(item.title).tag(VideoChoice.video(item.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                .disabled(state.library.isEmpty)
            }
            SwitchRow(title: L("Menüleiste ausblenden"),
                      help: L("Ausgeblendete Leisten kommen zurück, sobald die Maus an den Rand fährt."),
                      isOn: optionBinding(\.hideMenuBar))
            SwitchRow(title: L("Dock ausblenden"),
                      help: L("Dock auf diesem Monitor ausblenden (wirkt, wenn das Dock dort ist)"),
                      isOn: optionBinding(\.hideDock))
        }
    }

    private var subtitle: String {
        let w = Int(screen.pixelSize.width), h = Int(screen.pixelSize.height)
        var parts = ["\(w) × \(h)"]
        if h > w { parts.append(L("hochkant")) }
        return parts.joined(separator: " · ")
    }

    private func optionBinding(_ keyPath: WritableKeyPath<ScreenOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { state.options(for: screen.id)[keyPath: keyPath] },
            set: { value in
                var options = state.options(for: screen.id)
                options[keyPath: keyPath] = value
                state.setOptions(options, for: screen.id)
            }
        )
    }
}

private struct LibraryCard: View {
    @EnvironmentObject private var state: AppState

    private let columns = [GridItem(.flexible(), spacing: 10, alignment: .top),
                           GridItem(.flexible(), spacing: 10, alignment: .top)]

    var body: some View {
        Card(title: L("Bibliothek")) {
            Text("\(state.library.count) · \(Format.bytes(state.librarySize))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        } content: {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(state.library) { item in
                        LibraryTile(item: item)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 250)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LibraryTile: View {
    @EnvironmentObject private var state: AppState
    let item: VideoItem
    @State private var hovering = false
    @State private var editing = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    private var usedOn: Int {
        state.screens.filter { state.assignment(for: $0.id) == item.id }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.black
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if let image = state.thumbnails[item.id] {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if hovering && !editing {
                        HStack(spacing: 2) {
                            iconButton("pencil", help: L("Umbenennen"), action: startRename)
                            iconButton("trash", help: L("In den Papierkorb legen")) { state.delete(item) }
                        }
                        .padding(4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if state.convertingID == item.id {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text(L("Sparsame Version wird erstellt…")).lineLimit(1)
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(4)
                    } else if let duration = item.duration {
                        Text(Format.duration(duration))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.65)))
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(hovering ? 0.3 : 0.1))
                )

            if editing {
                TextField(L("Name"), text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($titleFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { editing = false }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused && editing { commitRename() }
                    }
            } else {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(L("Doppelklick zum Umbenennen"))
                    .onTapGesture(count: 2, perform: startRename)
            }
            Text(details)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button(L("Auf allen Monitoren zeigen")) { state.assignToAll(item.id) }
            ForEach(state.screens) { screen in
                Button(String(format: L("Auf %@ zeigen"), screen.name)) { state.assign(item.id, to: screen.id) }
            }
            Divider()
            Toggle(L("Beim Abwechseln verwenden"), isOn: Binding(
                get: { item.excludedFromRotation != true },
                set: { state.setInRotation($0, for: item.id) }
            ))
            Divider()
            Button(L("Umbenennen…"), action: startRename)
            Button(L("Im Finder zeigen")) { state.revealInFinder(item) }
            Button(L("In den Papierkorb legen"), role: .destructive) { state.delete(item) }
        }
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.black.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func startRename() {
        draftTitle = item.title
        editing = true
        DispatchQueue.main.async { titleFocused = true }
    }

    private func commitRename() {
        state.rename(item.id, to: draftTitle)
        editing = false
    }

    private var details: String {
        var parts: [String] = []
        if let s = item.fileSize { parts.append(Format.bytes(s)) }
        parts.append(item.generated == true ? L("Erzeugt") : item.sourceURL == nil ? L("Datei") : "YouTube")
        if state.settings.powerSaving && item.ecoFileName != nil { parts.append(L("sparsam")) }
        if usedOn > 0 { parts.append(L("läuft")) }
        return parts.joined(separator: " · ")
    }
}

private struct FooterView: View {
    @EnvironmentObject private var state: AppState

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hint = state.launchAtLoginHint {
                HintText(text: hint, color: .orange)
            }
            if let update = state.update {
                Button(String(format: L("Update auf %@ verfügbar"), update.version)) {
                    NSWorkspace.shared.open(update.url)
                }
                .buttonStyle(.link)
            }
            HStack(spacing: 12) {
                Menu {
                    Toggle(L("Beim Anmelden starten"), isOn: loginBinding)
                    Toggle(L("Im Akkubetrieb pausieren"), isOn: $state.settings.pauseOnBattery)
                    Toggle(L("Stromsparmodus (30 fps, max. 1440p)"), isOn: $state.settings.powerSaving)
                    Divider()
                    Button(L("Videoordner öffnen")) { state.revealInFinder() }
                    Button(L("Proledo auf GitHub")) { NSWorkspace.shared.open(AppState.repositoryURL) }
                } label: {
                    Text(L("Einstellungen"))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button(L("Beenden")) { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
        }
    }
}
