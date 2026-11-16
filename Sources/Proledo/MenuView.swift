import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView()
            if state.generatorOpen {
                GeneratorCard()
            } else {
                AddVideoCard()
                ScreensCard()
                if !state.library.isEmpty {
                    LibraryCard()
                }
            }
            FooterView()
        }
        .padding(12)
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

private struct Card<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

extension Card where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

private struct Thumb: View {
    let image: NSImage?
    var width: CGFloat = 64
    var height: CGFloat = 36
    var radius: CGFloat = 6

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "film")
                    .font(.system(size: min(width, height) * 0.35))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
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

    private var status: (text: String, color: Color) {
        if let reason = state.pauseReason { return (reason, .orange) }
        let count = state.activeScreenCount
        if count == 0 { return (L("Kein Video aktiv"), .secondary) }
        return (count == 1 ? L("Läuft auf 1 Monitor") : String(format: L("Läuft auf %d Monitoren"), count), .green)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Proledo").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                    Text(status.text).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                state.togglePause()
            } label: {
                Image(systemName: state.settings.userPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(state.settings.userPaused ? L("Wiedergabe fortsetzen") : L("Wiedergabe pausieren"))
        }
        .padding(.horizontal, 2)
    }
}

private struct AddVideoCard: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText = ""

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

    @ViewBuilder
    private var linkField: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField(L("YouTube-Link einfügen"), text: $urlText)
                    .textFieldStyle(.plain)
                    .onSubmit { state.loadInfo(urlText) }
                    .disabled(isLoading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

            if isLoading {
                ProgressView().controlSize(.small).frame(width: 28)
                Button(L("Abbrechen")) { state.cancelAdd() }
            } else {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.loadInfo(urlText)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help(L("Link aus der Zwischenablage einfügen und prüfen"))

                Button(L("Weiter")) { state.loadInfo(urlText) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
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

        HStack(spacing: 14) {
            Button {
                state.importLocalFile()
            } label: {
                Label(L("Eigene Videodatei wählen…"), systemImage: "folder")
            }
            Button {
                state.openGenerator()
            } label: {
                Label(L("Hintergrund erzeugen…"), systemImage: "sparkles")
            }
            .disabled(state.generatorOpen)
        }
        .buttonStyle(.link)
        .font(.caption)
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
                Button {
                    state.startDownload(info)
                } label: {
                    Label(L("Laden"), systemImage: "arrow.down.circle.fill")
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
            Button {
                state.closeGenerator()
            } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .help(L("Schließen"))
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

    private var preview: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Color.black
                if let image = state.generatorPreview {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !busy {
                Button {
                    state.shuffleGeneratorPattern()
                } label: {
                    Label(L("Neues Muster"), systemImage: "shuffle")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    ForEach(TopoOptions.Density.allCases) { Text(L($0.rawValue)).tag($0) }
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
            row(L("Linien")) {
                Picker("", selection: $state.generatorOptions.lines) {
                    ForEach(TopoOptions.Lines.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
                Button {
                    state.startGeneration()
                } label: {
                    Label(L("Erzeugen"), systemImage: "sparkles")
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
                .frame(width: 64, alignment: .leading)
            content()
        }
    }

    private func estimatedBytes(_ size: (width: Int, height: Int)) -> Int64 {
        let scale = Double(min(size.width, size.height)) / 1440
        let bitRate = 9_000_000 * pow(scale, 1.5)
        return Int64(bitRate * Double(state.generatorOptions.seconds) / 8 * 0.95)
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

    var body: some View {
        Card(title: L("Monitore")) {
            if !state.library.isEmpty {
                Menu {
                    ForEach(state.library) { item in
                        Button(item.title) { state.assignToAll(item.id) }
                    }
                    Divider()
                    Button(L("Alle aus")) { state.assignToAll(nil) }
                } label: {
                    Text(L("Für alle")).font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } content: {
            VStack(spacing: 12) {
                ForEach(state.screens) { screen in
                    ScreenRow(screen: screen)
                    if screen.id != state.screens.last?.id { Divider() }
                }
            }
            if state.library.isEmpty {
                HintText(text: L("Füge oben ein Video hinzu, dann kannst du es hier jedem Monitor zuordnen."))
            }
            HintText(text: L("Ausgeblendete Leisten kommen zurück, sobald die Maus an den Rand fährt."),
                     icon: "info.circle")
        }
    }
}

private struct ScreenRow: View {
    @EnvironmentObject private var state: AppState
    let screen: ScreenInfo

    private var assigned: VideoItem? {
        state.assignment(for: screen.id).flatMap { id in state.library.first { $0.id == id } }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MonitorPreview(screen: screen, image: assigned.flatMap { state.thumbnails[$0.id] },
                           active: assigned != nil)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screen.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Picker("", selection: videoBinding) {
                        Text(L("Aus")).tag(UUID?.none)
                        if !state.library.isEmpty { Divider() }
                        ForEach(state.library) { item in
                            Text(item.title).tag(Optional(item.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .disabled(state.library.isEmpty)
                }
                HStack(spacing: 6) {
                    BarToggle(title: L("Menüleiste"), icon: "menubar.rectangle",
                              help: L("Menüleiste auf diesem Monitor ausblenden"),
                              isOn: optionBinding(\.hideMenuBar))
                    BarToggle(title: L("Dock"), icon: "dock.rectangle",
                              help: L("Dock auf diesem Monitor ausblenden (wirkt, wenn das Dock dort ist)"),
                              isOn: optionBinding(\.hideDock))
                }
            }
        }
    }

    private var subtitle: String {
        let w = Int(screen.pixelSize.width), h = Int(screen.pixelSize.height)
        var parts = ["\(w) × \(h)"]
        if h > w { parts.append(L("hochkant")) }
        if screen.isBuiltIn { parts.append("OLED") }
        return parts.joined(separator: " · ")
    }

    private var videoBinding: Binding<UUID?> {
        Binding(get: { state.assignment(for: screen.id) },
                set: { state.assign($0, to: screen.id) })
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

private struct MonitorPreview: View {
    let screen: ScreenInfo
    let image: NSImage?
    let active: Bool

    var body: some View {
        let box: CGFloat = 46
        let ratio = screen.pixelSize.width / max(screen.pixelSize.height, 1)
        let size = ratio >= 1 ? CGSize(width: box, height: box / ratio) : CGSize(width: box * ratio, height: box)

        ZStack {
            if let image, active {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black.opacity(0.85)
                Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
        )
        .frame(width: box, height: box)
    }
}

private struct BarToggle: View {
    let title: String
    let icon: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "eye.slash" : icon)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
            .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct LibraryCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: L("Bibliothek")) {
            Text("\(state.library.count) · \(Format.bytes(state.librarySize))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        } content: {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(state.library) { item in
                        LibraryRow(item: item)
                    }
                }
            }
            .frame(maxHeight: 170)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LibraryRow: View {
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
        HStack(spacing: 10) {
            Thumb(image: state.thumbnails[item.id])
            VStack(alignment: .leading, spacing: 2) {
                if editing {
                    TextField(L("Name"), text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .focused($titleFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { editing = false }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused && editing { commitRename() }
                        }
                } else {
                    Text(item.title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(L("Doppelklick zum Umbenennen"))
                        .onTapGesture(count: 2, perform: startRename)
                }
                if state.convertingID == item.id {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(L("Sparsame Version wird erstellt…"))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(details).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if editing {
                EmptyView()
            } else if hovering {
                HStack(spacing: 8) {
                    Button(action: startRename) {
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Umbenennen"))
                    Button {
                        state.delete(item)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("Video löschen"))
                }
            } else if usedOn > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(usedOn == 1 ? L("Läuft auf 1 Monitor") : String(format: L("Läuft auf %d Monitoren"), usedOn))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Auf allen Monitoren zeigen")) { state.assignToAll(item.id) }
            ForEach(state.screens) { screen in
                Button(String(format: L("Auf %@ zeigen"), screen.name)) { state.assign(item.id, to: screen.id) }
            }
            Divider()
            Button(L("Umbenennen…"), action: startRename)
            Button(L("Im Finder zeigen")) { state.revealInFinder(item) }
            Button(L("Löschen"), role: .destructive) { state.delete(item) }
        }
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
        if let d = item.duration { parts.append(Format.duration(d)) }
        if let s = item.fileSize { parts.append(Format.bytes(s)) }
        parts.append(item.generated == true ? L("Erzeugt") : item.sourceURL == nil ? L("Datei") : "YouTube")
        if state.settings.powerSaving && item.ecoFileName != nil { parts.append(L("sparsam")) }
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(L("Beim Anmelden starten"), isOn: loginBinding)
                Toggle(L("Im Akkubetrieb pausieren"), isOn: $state.settings.pauseOnBattery)
                Toggle(L("Stromsparmodus (30 fps, max. 1440p)"), isOn: $state.settings.powerSaving)
                    .help(L("Erstellt von jedem Video einmalig eine sparsame Kopie und spielt diese ab. Das Original bleibt erhalten."))
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            if let hint = state.launchAtLoginHint {
                HintText(text: hint, color: .orange, icon: "exclamationmark.triangle.fill")
            }

            HStack {
                Text("Proledo \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    state.revealInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(L("Videoordner im Finder öffnen"))
                Button(L("Beenden")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }
}
