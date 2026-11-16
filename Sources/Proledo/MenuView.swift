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
                if state.library.isEmpty && state.generatorProgress == nil {
                    WelcomeCard()
                }
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

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(compact ? .caption.weight(.medium) : .callout.weight(prominent ? .semibold : .medium))
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 4 : 6)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(
                    Capsule().fill(prominent
                        ? Color.accentColor.opacity(hovering ? 0.88 : 1)
                        : Color.primary.opacity(hovering ? 0.13 : 0.08))
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

private struct ActionTile: View {
    let icon: String
    let colors: [Color]
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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

private struct WelcomeCard: View {
    var body: some View {
        Card(title: L("Willkommen")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Proledo hält dein OLED-Display in Bewegung, damit sich nichts einbrennt."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                step(1, L("Füge unten ein Video hinzu: per YouTube-Link, als eigene Datei oder selbst erzeugt."))
                step(2, L("Wähle unter „Monitore“, wo es laufen soll."))
                step(3, L("Blende bei Bedarf Menüleiste und Dock aus."))
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    private var status: (text: String, color: Color) {
        if let progress = state.generatorProgress, !state.generatorOpen {
            return (String(format: L("Hintergrund wird erzeugt · %d %%"), Int(progress * 100)), .blue)
        }
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
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .shadow(color: status.color.opacity(0.8), radius: 3)
                    Text(status.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(status.color.opacity(0.12)))
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
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("YouTube-Link einfügen"), text: $urlText)
                    .textFieldStyle(.plain)
                    .focused($linkFocused)
                    .onSubmit { if canGo { state.loadInfo(urlText) } }
                    .disabled(isLoading)
                if !isLoading {
                    if urlText.isEmpty {
                        Button {
                            if let text = NSPasteboard.general.string(forType: .string) {
                                urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                state.loadInfo(urlText)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("Link aus der Zwischenablage einfügen und prüfen"))
                    } else {
                        Button {
                            urlText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(linkFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                                  lineWidth: linkFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: linkFocused)

            Button {
                if isLoading { state.cancelAdd() } else { state.loadInfo(urlText) }
            } label: {
                ZStack {
                    Circle().fill(canGo || isLoading ? Color.accentColor : Color.primary.opacity(0.1))
                    if isLoading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canGo ? Color.white : Color.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canGo && !isLoading)
            .help(isLoading ? L("Abbrechen") : L("Weiter"))
            .animation(.easeOut(duration: 0.15), value: canGo)
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

        HStack(spacing: 8) {
            ActionTile(icon: "folder.fill",
                       colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.15, green: 0.4, blue: 0.95)],
                       title: L("Eigene Datei"),
                       subtitle: L("Vom Mac")) {
                state.importLocalFile()
            }
            if let progress = state.generatorProgress {
                ActionTile(icon: "sparkles",
                           colors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.95, green: 0.4, blue: 0.7)],
                           title: L("Wird erzeugt"),
                           subtitle: "\(Int(progress * 100)) %") {
                    state.openGenerator()
                }
            } else {
                ActionTile(icon: "sparkles",
                           colors: [Color(red: 0.55, green: 0.38, blue: 1.0), Color(red: 0.95, green: 0.4, blue: 0.7)],
                           title: L("Selbst erzeugen"),
                           subtitle: L("Höhenlinien-Loop")) {
                    state.openGenerator()
                }
            }
        }
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
                    .buttonStyle(PillButtonStyle())
                Button {
                    state.startDownload(info)
                } label: {
                    Label(L("Laden"), systemImage: "arrow.down")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
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
            .help(busy ? L("Im Hintergrund weiterrechnen") : L("Schließen"))
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
                    .buttonStyle(PillButtonStyle())
                Button {
                    state.startGeneration()
                } label: {
                    Label(L("Erzeugen"), systemImage: "sparkles")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
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
                    .buttonStyle(PillButtonStyle(compact: true))
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
                    Text(L("Für alle")).font(.caption)
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
                    Label(L("Wechsel alle"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
            HintText(text: L("Ausgeblendete Leisten kommen zurück, sobald die Maus an den Rand fährt."),
                     icon: "info.circle")
        }
    }
}

private struct ScreenMap: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedID: String?

    var body: some View {
        GeometryReader { geo in
            let union = state.screens.reduce(CGRect.null) { $0.union($1.frame) }
            let pad: CGFloat = 4
            let scale = min((geo.size.width - 2 * pad) / max(union.width, 1),
                            (geo.size.height - 2 * pad) / max(union.height, 1))
            let originX = (geo.size.width - union.width * scale) / 2
            let originY = (geo.size.height - union.height * scale) / 2
            ZStack(alignment: .topLeading) {
                ForEach(state.screens) { screen in
                    let gap: CGFloat = 5
                    let width = max(screen.frame.width * scale - gap, 8)
                    let height = max(screen.frame.height * scale - gap, 8)
                    ScreenTile(screen: screen, selected: screen.id == selectedID)
                        .frame(width: width, height: height)
                        .offset(x: originX + (screen.frame.minX - union.minX) * scale + gap / 2,
                                y: originY + (union.maxY - screen.frame.maxY) * scale + gap / 2)
                        .onTapGesture { selectedID = screen.id }
                }
            }
        }
        .frame(height: 118)
        .padding(.vertical, 2)
    }
}

private struct ScreenTile: View {
    @EnvironmentObject private var state: AppState
    let screen: ScreenInfo
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let video = state.assignment(for: screen.id)
        let options = state.options(for: screen.id)
        ZStack {
            if let video, let image = state.thumbnails[video] {
                Color.black
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.1)
                Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            VStack(spacing: 0) {
                if options.hideMenuBar {
                    Rectangle().fill(.black).frame(height: 3)
                } else {
                    Rectangle().fill(.white.opacity(0.35)).frame(height: 2)
                }
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(hovering ? 0.45 : 0.2),
                              lineWidth: selected ? 2.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if state.isRotating(screen.id) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.65)))
                    .padding(4)
            }
        }
        .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(screen.name)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct ScreenDetail: View {
    @EnvironmentObject private var state: AppState
    let screen: ScreenInfo

    private var assigned: VideoItem? {
        state.assignment(for: screen.id).flatMap { id in state.library.first { $0.id == id } }
    }

    private var rotating: Bool { state.isRotating(screen.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: screen.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(screen.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Menu {
                Toggle(isOn: choice(nil)) {
                    Label(L("Aus"), systemImage: "nosign")
                }
                Toggle(isOn: rotatingBinding) {
                    Label(L("Alle abwechselnd"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(state.library.count < 2)
                if !state.library.isEmpty { Divider() }
                ForEach(state.library) { item in
                    Toggle(isOn: choice(item.id)) {
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(nsImage: state.menuThumbnail(for: item.id))
                        }
                    }
                }
            } label: {
                if rotating {
                    Label(String(format: L("Abwechselnd · %@"), assigned?.title ?? ""),
                          systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(assigned?.title ?? L("Aus"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(state.library.isEmpty)

            HStack(spacing: 6) {
                BarToggle(title: L("Menüleiste"), icon: "menubar.rectangle",
                          help: L("Menüleiste auf diesem Monitor ausblenden"),
                          isOn: optionBinding(\.hideMenuBar))
                BarToggle(title: L("Dock"), icon: "dock.rectangle",
                          help: L("Dock auf diesem Monitor ausblenden (wirkt, wenn das Dock dort ist)"),
                          isOn: optionBinding(\.hideDock))
                Spacer()
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

    private var rotatingBinding: Binding<Bool> {
        Binding(get: { rotating }, set: { state.setRotating($0, for: screen.id) })
    }

    private func choice(_ id: UUID?) -> Binding<Bool> {
        Binding(
            get: { !rotating && state.fixedAssignment(for: screen.id) == id },
            set: { if $0 { state.assign(id, to: screen.id) } }
        )
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
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
            .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeOut(duration: 0.15), value: isOn)
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
                    } else if usedOn > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 14))
                            .padding(5)
                            .help(usedOn == 1 ? L("Läuft auf 1 Monitor") : String(format: L("Läuft auf %d Monitoren"), usedOn))
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
                HintText(text: hint, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if let update = state.update {
                Button {
                    NSWorkspace.shared.open(update.url)
                } label: {
                    Label(String(format: L("Update auf %@ verfügbar"), update.version), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            HStack(spacing: 10) {
                Text("Proledo \(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if state.settings.powerSaving {
                    Label(L("Stromsparmodus"), systemImage: "leaf.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Spacer()
                Menu {
                    Toggle(L("Beim Anmelden starten"), isOn: loginBinding)
                    Toggle(L("Im Akkubetrieb pausieren"), isOn: $state.settings.pauseOnBattery)
                    Toggle(L("Stromsparmodus (30 fps, max. 1440p)"), isOn: $state.settings.powerSaving)
                    Divider()
                    Button(L("Videoordner öffnen")) { state.revealInFinder() }
                    Button(L("Proledo auf GitHub")) { NSWorkspace.shared.open(AppState.repositoryURL) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Einstellungen"))
                Button(L("Beenden")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(PillButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 4)
    }
}
