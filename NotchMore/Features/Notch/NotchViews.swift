import SwiftUI
import UniformTypeIdentifiers

// MARK: - Combined Notch

struct CombinedNotchView: View {
    @ObservedObject var mediaManager: MediaManager
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var fileShelfManager: FileShelfManager

    @AppStorage("enableFileShelf") private var enableFileShelf: Bool = false
    @AppStorage("enableClipboardHistory") private var enableClipboardHistory: Bool = false
    @State private var isPanelDropTargetActive: Bool = false
    let onOpenSettings: () -> Void
    var onHover: ((Bool) -> Void)?
    var onDropTargetChange: ((Bool) -> Void)?
    var onDropProviders: (([NSItemProvider]) -> Bool)?
    var onExternalInteraction: (() -> Void)?

    init(
        mediaManager: MediaManager,
        clipboardManager: ClipboardManager,
        fileShelfManager: FileShelfManager,
        previewScale: CGFloat = 1.0,
        onOpenSettings: @escaping () -> Void = {},
        onHover: ((Bool) -> Void)? = nil,
        onDropTargetChange: ((Bool) -> Void)? = nil,
        onDropProviders: (([NSItemProvider]) -> Bool)? = nil,
        onExternalInteraction: (() -> Void)? = nil
    ) {
        self.mediaManager = mediaManager
        self.clipboardManager = clipboardManager
        self.fileShelfManager = fileShelfManager
        self.onOpenSettings = onOpenSettings
        self.onHover = onHover
        self.onDropTargetChange = onDropTargetChange
        self.onDropProviders = onDropProviders
        self.onExternalInteraction = onExternalInteraction
    }

    private var sectionCount: Int {
        NotchLayout.panelSectionCount(
            enableFileShelf: enableFileShelf, showClipboard: enableClipboardHistory)
    }

    private var scaledLayout:
        (
            panelWidth: CGFloat, panelHeight: CGFloat, totalWidth: CGFloat, totalHeight: CGFloat,
            scale: CGFloat, contentHorizontalInset: CGFloat
        )
    {
        let basePanelWidth = NotchConstants.basePanelWidth
        let basePanelHeight = NotchConstants.basePanelHeight
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        return NotchLayout.scaledMetrics(
            panelWidth: basePanelWidth,
            panelHeight: basePanelHeight,
            sectionCount: sectionCount,
            screenWidth: screenWidth
        )
    }

    private var totalWidth: CGFloat {
        scaledLayout.totalWidth
    }

    private var totalHeight: CGFloat {
        scaledLayout.totalHeight
    }

    private var panelWidth: CGFloat {
        scaledLayout.panelWidth
    }

    private var panelHeight: CGFloat {
        scaledLayout.panelHeight
    }

    private var contentHorizontalInset: CGFloat {
        scaledLayout.contentHorizontalInset
    }

    private var sectionFillColor: Color {
        Color.white.opacity(0.055)
    }

    private func handlePanelDrop(providers: [NSItemProvider]) -> Bool {
        guard enableFileShelf, !providers.isEmpty else { return false }

        if let onDropProviders {
            return onDropProviders(providers)
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
                guard let url = Self.url(from: item) else { return }
                DispatchQueue.main.async {
                    fileShelfManager.addFile(url: url)
                }
            }
        }

        return true
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: NotchLayout.sectionSpacing) {
            if enableFileShelf {
                sectionContainer {
                    FileShelfView(
                        fileShelfManager: fileShelfManager,
                        panelWidth: panelWidth,
                        panelHeight: panelHeight,
                        onExternalInteraction: onExternalInteraction
                    )
                }
            }

            sectionContainer {
                ExpandedNotchView(
                    mediaManager: mediaManager,
                    panelWidth: panelWidth,
                    panelHeight: panelHeight,
                    onOpenSettings: onOpenSettings,
                )
            }

            if enableClipboardHistory {
                sectionContainer {
                    ClipboardHistoryView(
                        clipboardManager: clipboardManager,
                        panelWidth: panelWidth,
                        panelHeight: panelHeight
                    )
                }
            }
        }
        .padding(.horizontal, contentHorizontalInset)
        .padding(.top, 10)
        .frame(width: totalWidth, height: totalHeight)
        .contentShape(Rectangle())
        .overlay {
            if isPanelDropTargetActive && enableFileShelf {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .inset(by: 3)
                    .stroke(
                        Color.accentColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.2, dash: [8, 6])
                    )
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 0)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isPanelDropTargetActive) { providers in
            handlePanelDrop(providers: providers)
        }
        .onChange(of: isPanelDropTargetActive, initial: false) { oldValue, newValue in
            onDropTargetChange?(newValue)
        }
        .onHover { isHovering in
            onHover?(isHovering)
        }
    }

    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(sectionFillColor)
            )
    }
}

// MARK: - Media Panel

struct ExpandedNotchView: View {
    @ObservedObject var mediaManager: MediaManager
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let onOpenSettings: () -> Void

    init(
        mediaManager: MediaManager,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        onOpenSettings: @escaping () -> Void = {},
    ) {
        self.mediaManager = mediaManager
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.onOpenSettings = onOpenSettings
    }

    private var hasMedia: Bool {
        mediaManager.isPlaying || mediaManager.currentTrackTitle != "Not Playing"
    }

    private var albumArtSize: CGFloat {
        min(84, max(48, panelHeight * 0.30))
    }

    private var horizontalPadding: CGFloat {
        min(22, max(14, panelWidth * 0.06))
    }

    private var verticalPadding: CGFloat {
        min(18, max(12, panelHeight * 0.06))
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(mediaManager.volume) },
            set: { newValue in
                mediaManager.volume = Float(newValue)
                mediaManager.setVolume(Float(newValue))
            }
        )
    }

    private var progressValue: Double {
        max(0, min(1, Double(mediaManager.trackProgress)))
    }

    @State private var isScrubbingProgress = false
    @State private var scrubProgress: Double = 0

    private var displayedProgress: Double {
        isScrubbingProgress ? scrubProgress : progressValue
    }

    private var displayedElapsed: Double {
        max(0, min(mediaManager.trackDuration * displayedProgress, mediaManager.trackDuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, horizontalPadding)
                .padding(.top, verticalPadding)
                .padding(.bottom, 10)

            Group {
                if hasMedia {
                    activeMediaView
                } else {
                    idleMediaView
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: panelWidth)
        .animation(.easeInOut(duration: 0.2), value: panelHeight)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .help("Open Settings")

            Spacer(minLength: 0)
            Label {
                Text(hasMedia ? (mediaManager.isPlaying ? "Now Playing" : "Paused") : "Media")
                    .font(.system(size: 10, weight: .semibold)).lineLimit(1)
            } icon: {
                if hasMedia, let icon = mediaManager.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: hasMedia ? "waveform" : "music.note")
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )

        }
    }

    private var activeMediaView: some View {
        VStack(spacing: 8, ) {
            HStack {
                albumArtwork
                Spacer(minLength: 0)
                VStack(alignment: .center) {
                    Text(mediaManager.sourceName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.bottom, 1)

                    Text(mediaManager.currentTrackTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    Text(mediaManager.currentTrackArtist)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                seekableProgressBar
                Spacer(minLength: 0)
                HStack {
                    Text(formatTime(displayedElapsed))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text(formatTime(mediaManager.trackDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                playbackControls
                    .padding(.top, 6)
                Spacer(minLength: 0)
                volumeControls
                    .padding(.top, 10)
                    .padding(.bottom, verticalPadding)
            }

        }
    }

    private var seekableProgressBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 10)

                Capsule()
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: CGFloat(displayedProgress) * width, height: 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard mediaManager.trackDuration > 0 else { return }
                        isScrubbingProgress = true
                        let ratio = max(0, min(1, value.location.x / width))
                        scrubProgress = ratio
                        mediaManager.setTime(seconds: mediaManager.trackDuration * ratio)
                    }
                    .onEnded { _ in
                        isScrubbingProgress = false
                    }
            )
        }
        .frame(height: 8)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private var albumArtwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = mediaManager.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)

                        Image(systemName: "music.note")
                            .font(.system(size: albumArtSize * 0.50, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let icon = mediaManager.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.regularMaterial)
                            .frame(width: 28, height: 28)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
                    )
                    .padding(4)
            }
        }
        .frame(width: albumArtSize, height: albumArtSize)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
        )
    }

    private var idleMediaView: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "music.quarternote.3")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Media Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Play audio to control it here")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            NotchMediaControlButton(action: mediaManager.previousTrack, icon: "backward.fill")

            NotchMediaControlButton(
                action: mediaManager.playPause,
                icon: mediaManager.isPlaying ? "pause.fill" : "play.fill")

            NotchMediaControlButton(action: mediaManager.nextTrack, icon: "forward.fill")
        }
        .frame(maxWidth: .infinity)
    }

    private var volumeControls: some View {
        HStack(spacing: 10) {
            Button(action: mediaManager.toggleMute) {
                Image(
                    systemName: mediaManager.volume > 0
                        ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            }
            .buttonStyle(.plain)

            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.small)
                .tint(.primary)
        }
    }
}

// MARK: - Reusable Controls

struct NotchMediaControlButton: View {
    let action: () -> Void
    let icon: String

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.18 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.24 : 0.12), lineWidth: 0.8)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}
