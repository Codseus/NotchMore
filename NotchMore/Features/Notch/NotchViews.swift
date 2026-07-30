import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Combined Notch

struct CombinedNotchView: View {
    @ObservedObject var mediaManager: MediaManager
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var fileShelfManager: FileShelfManager

    @AppStorage("enableFileShelf") private var enableFileShelf: Bool = false
    @AppStorage("enableClipboardHistory") private var enableClipboardHistory: Bool = false
    @AppStorage("enableAirDropSupport") private var enableAirDropSupport: Bool = false
    @AppStorage("enableLocalSendSupport") private var enableLocalSendSupport: Bool = false
    @State private var isPanelDropTargetActive: Bool = false
    @State private var activeDropDestination: DropDestination = .fileShelf
    @State private var dropResetToken = UUID()
    @State private var dropOverlaySuppressionToken: UUID?
    @State private var isMirrorActive: Bool = false
    @State private var isRequestingCameraPermission: Bool = false
    let onOpenSettings: () -> Void
    var onMirrorActiveChange: ((Bool) -> Void)?
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
        onMirrorActiveChange: ((Bool) -> Void)? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onDropTargetChange: ((Bool) -> Void)? = nil,
        onDropProviders: (([NSItemProvider]) -> Bool)? = nil,
        onExternalInteraction: (() -> Void)? = nil
    ) {
        self.mediaManager = mediaManager
        self.clipboardManager = clipboardManager
        self.fileShelfManager = fileShelfManager
        self.onOpenSettings = onOpenSettings
        self.onMirrorActiveChange = onMirrorActiveChange
        self.onHover = onHover
        self.onDropTargetChange = onDropTargetChange
        self.onDropProviders = onDropProviders
        self.onExternalInteraction = onExternalInteraction
    }

    private var sectionCount: Int {
        if isMirrorActive {
            return 1
        }
        return NotchLayout.panelSectionCount(
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

    fileprivate enum DropDestination: String, Identifiable {
        case fileShelf
        case airDrop
        case localSend

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fileShelf:
                return "File Shelf"
            case .airDrop:
                return "AirDrop"
            case .localSend:
                return "LocalSend"
            }
        }

        var systemImage: String {
            switch self {
            case .fileShelf:
                return "folder.badge.plus"
            case .airDrop:
                return "airplayaudio"
            case .localSend:
                return "network"
            }
        }
    }

    private var dropDestinations: [DropDestination] {
        guard enableFileShelf else { return [] }

        var destinations: [DropDestination] = [.fileShelf]
        if enableAirDropSupport {
            destinations.append(.airDrop)
        }
        if enableLocalSendSupport {
            destinations.append(.localSend)
        }
        return destinations
    }

    private func handlePanelDrop(
        providers: [NSItemProvider],
        destination explicitDestination: DropDestination? = nil
    ) -> Bool {
        guard enableFileShelf, !providers.isEmpty else { return false }

        switch explicitDestination ?? currentDropDestination {
        case .airDrop:
            AirDropManager.loadURLs(from: providers) { urls in
                AirDropManager.send(urls: urls)
            }
            return true
        case .localSend:
            AirDropManager.loadURLs(from: providers) { urls in
                LocalSendManager.send(urls: urls)
            }
            return true
        case .fileShelf:
            if let onDropProviders {
                return onDropProviders(providers)
            }

            AirDropManager.loadURLs(from: providers) { urls in
                for url in urls {
                    fileShelfManager.addFile(url: url)
                }
            }
            return true
        }
    }

    private var currentDropDestination: DropDestination {
        let destinations = dropDestinations
        guard destinations.count > 1 else { return .fileShelf }
        return activeDropDestination
    }

    private func dropDestination(atRelativeX relativeX: CGFloat) -> DropDestination {
        let destinations = dropDestinations
        guard destinations.count > 1 else { return .fileShelf }

        let relativeX = max(0, min(totalWidth, relativeX))
        let slotWidth = totalWidth / CGFloat(destinations.count)
        let index = min(destinations.count - 1, max(0, Int(relativeX / slotWidth)))
        return destinations[index]
    }

    private func markPanelDropActive(at location: CGPoint) {
        guard dropOverlaySuppressionToken == nil else { return }
        isPanelDropTargetActive = true
        activeDropDestination = dropDestination(atRelativeX: location.x)
        scheduleDropStateReset()
    }

    private func resetPanelDropState() {
        isPanelDropTargetActive = false
        activeDropDestination = .fileShelf
        dropResetToken = UUID()
    }

    private func scheduleDropStateReset() {
        let token = UUID()
        dropResetToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard dropResetToken == token else { return }
            resetPanelDropState()
        }
    }

    private func hideDropOverlayAfterSuccessfulDrop() {
        let token = UUID()
        dropOverlaySuppressionToken = token
        resetPanelDropState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard dropOverlaySuppressionToken == token else { return }
            dropOverlaySuppressionToken = nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: NotchLayout.sectionSpacing) {
            if isMirrorActive {
                sectionContainer {
                    MirrorNotchView(
                        panelWidth: panelWidth,
                        panelHeight: panelHeight,
                        onClose: { isMirrorActive = false }
                    )
                }
            } else {
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
                        onOpenMirror: openMirror
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
        }
        .padding(.horizontal, contentHorizontalInset)
        .padding(.top, 10)
        .frame(width: totalWidth, height: totalHeight)
        .contentShape(Rectangle())
        .overlay {
            if isPanelDropTargetActive && enableFileShelf && dropOverlaySuppressionToken == nil {
                dropOverlay
            }
        }
        .onDrop(
            of: [.fileURL],
            delegate: NotchPanelDropDelegate(
                isTargeted: $isPanelDropTargetActive,
                activeDestination: $activeDropDestination,
                onDragLocation: { location in
                    markPanelDropActive(at: location)
                },
                destinationForLocation: { location in
                    dropDestination(atRelativeX: location.x)
                },
                performDrop: { providers, destination in
                    handlePanelDrop(providers: providers, destination: destination)
                },
                resetDropState: {
                    resetPanelDropState()
                },
                hideDropOverlayAfterSuccessfulDrop: {
                    hideDropOverlayAfterSuccessfulDrop()
                }
            )
        )
        .onChange(of: isPanelDropTargetActive, initial: false) { oldValue, newValue in
            if !newValue {
                activeDropDestination = .fileShelf
                dropResetToken = UUID()
            }
            onDropTargetChange?(newValue)
        }
        .onHover { isHovering in
            if isHovering {
                NSCursor.arrow.set()
            }
            onHover?(isHovering)
        }
        .onChange(of: isMirrorActive, initial: true) { _, active in
            onMirrorActiveChange?(active)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if dropDestinations.count > 1 {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.74))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    ForEach(dropDestinations) { destination in
                        dropZoneLabel(
                            title: destination.title,
                            systemImage: destination.systemImage,
                            isActive: destination == currentDropDestination
                        )
                    }
                }
                .padding(.horizontal, contentHorizontalInset)
                .padding(.top, 10)
            }
            .frame(width: totalWidth, height: totalHeight)
            .allowsHitTesting(false)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.74))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.75), lineWidth: 1.4)
                    )

                dropZoneLabel(
                    title: "File Shelf",
                    systemImage: "folder.badge.plus",
                    isActive: true
                )
                .padding(.horizontal, contentHorizontalInset)
                .padding(.top, 10)
            }
            .frame(width: totalWidth, height: totalHeight)
            .allowsHitTesting(false)
        }
    }

    private func dropZoneLabel(title: String, systemImage: String, isActive: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: isActive ? 26 : 22, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isActive ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.12),
                    lineWidth: isActive ? 1.4 : 0.8
                )
        )
        .shadow(color: isActive ? Color.accentColor.opacity(0.22) : Color.clear, radius: 6, x: 0, y: 0)
    }

    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(sectionFillColor)
            )
    }

    private func openMirror() {
        guard !isRequestingCameraPermission else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized, .denied, .restricted:
            isMirrorActive = true
        case .notDetermined:
            isRequestingCameraPermission = true
            PermissionManager.requestCameraAccess { _ in
                isRequestingCameraPermission = false
                isMirrorActive = true
            }
        @unknown default:
            isMirrorActive = true
        }
    }
}

private struct NotchPanelDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    @Binding var activeDestination: CombinedNotchView.DropDestination

    let onDragLocation: (CGPoint) -> Void
    let destinationForLocation: (CGPoint) -> CombinedNotchView.DropDestination
    let performDrop: ([NSItemProvider], CombinedNotchView.DropDestination) -> Bool
    let resetDropState: () -> Void
    let hideDropOverlayAfterSuccessfulDrop: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL.identifier])
    }

    func dropEntered(info: DropInfo) {
        updateTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(info: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        resetDropState()
    }

    func performDrop(info: DropInfo) -> Bool {
        let destination = destinationForLocation(info.location)
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        hideDropOverlayAfterSuccessfulDrop()
        return performDrop(providers, destination)
    }

    private func updateTarget(info: DropInfo) {
        onDragLocation(info.location)
    }
}

// MARK: - Media Panel

struct ExpandedNotchView: View {
    @ObservedObject var mediaManager: MediaManager
    @ObservedObject private var desktopCleaner = DesktopCleanerManager.shared
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let onOpenSettings: () -> Void
    let onOpenMirror: () -> Void

    init(
        mediaManager: MediaManager,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        onOpenSettings: @escaping () -> Void = {},
        onOpenMirror: @escaping () -> Void = {},
    ) {
        self.mediaManager = mediaManager
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.onOpenSettings = onOpenSettings
        self.onOpenMirror = onOpenMirror
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
            }
            .buttonStyle(NotchIconButtonStyle(size: 24, cornerRadius: 7))
            .help("Open Settings")

            Button {
                desktopCleaner.toggle()
            } label: {
                Image(systemName: desktopCleaner.isDesktopClean ? "desktopcomputer.trianglebadge.exclamationmark" : "desktopcomputer")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(
                NotchIconButtonStyle(
                    size: 24,
                    cornerRadius: 7,
                    tint: .primary,
                    isActive: desktopCleaner.isDesktopClean
                )
            )
            .help(desktopCleaner.isDesktopClean ? "Show Desktop Icons" : "Clean Desktop")

            Button {
                onOpenMirror()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(NotchIconButtonStyle(size: 24, cornerRadius: 7))
            .help("Open Mirror")

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
            }
            .buttonStyle(NotchIconButtonStyle(size: 24, cornerRadius: 7))

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

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(NotchPillButtonStyle(height: 26, fillsAvailableWidth: true))
    }
}

// MARK: - Mirror

struct MirrorNotchView: View {
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let onClose: () -> Void

    @State private var cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch cameraPermission {
                case .authorized:
                    CameraPreviewView()
                case .notDetermined:
                    permissionView
                case .denied, .restricted:
                    unavailableView(
                        title: "Camera Access Needed",
                        message: "Enable camera access in System Settings to use Mirror."
                    )
                @unknown default:
                    unavailableView(
                        title: "Camera Unavailable",
                        message: "NotchMore could not access the camera."
                    )
                }
            }
            .frame(width: panelWidth, height: panelHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(NotchIconButtonStyle(size: 28, cornerRadius: 14))
            .padding(12)
            .help("Close Mirror")
        }
        .frame(width: panelWidth, height: panelHeight)
        .onAppear {
            refreshCameraPermission()
        }
    }

    private var permissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("Open Mirror")
                .font(.system(size: 15, weight: .semibold))

            Text("Camera access is needed for the live mirror preview.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)

            Button {
                requestCameraPermission()
            } label: {
                Text("Allow Camera")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(NotchPillButtonStyle(height: 28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(title: String, message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            Button {
                PermissionManager.openSettings(for: .camera)
            } label: {
                Text("Open Settings")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(NotchPillButtonStyle(height: 28))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshCameraPermission() {
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func requestCameraPermissionIfNeeded(force: Bool = false) {
        requestCameraPermission()
    }

    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = status

        guard status == .notDetermined else {
            if status == .denied || status == .restricted {
                PermissionManager.openSettings(for: .camera)
            }
            return
        }

        PermissionManager.requestCameraAccess { _ in
            refreshCameraPermission()
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = context.coordinator.session
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = context.coordinator.session
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.previewLayer.session = nil
    }

    final class Coordinator {
        let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "codseus.NotchMore.cameraPreview")
        private var isConfigured = false

        func start() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.isConfigured {
                    self.configureSession()
                }
                guard self.isConfigured, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        private func configureSession() {
            session.beginConfiguration()
            session.sessionPreset = .medium
            defer { session.commitConfiguration() }

            let device =
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)

            guard let device, let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else { return }

            session.addInput(input)
            isConfigured = true
        }
    }
}

final class CameraPreviewNSView: NSView {
    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
    }
}
