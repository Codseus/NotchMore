import AppKit
import DynamicNotchKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NotchPanelController {
    private let mediaManager: MediaManager
    private let clipboardManager: ClipboardManager
    private let fileShelfManager: FileShelfManager
    private let onOpenSettings: () -> Void
    private let isFileShelfEnabled: () -> Bool
    private let isClipboardEnabled: () -> Bool
    private let hoverDelay: () -> Double

    private var dynamicNotch: DynamicNotch<CombinedNotchView, EmptyView, EmptyView>?
    private var isDynamicNotchVisible = false
    private var isDraggingOverTrigger = false
    private var isDraggingOverPanel = false
    private var isDragSessionActive = false
    private var triggerWindows: [NSWindow] = []
    private var isHoveringTrigger = false
    private var isHoveringPanel = false
    private var pendingHideWorkItem: DispatchWorkItem?
    private var pendingDragEndWorkItem: DispatchWorkItem?
    private var hoverValidationTimer: Timer?
    private var visibilityTask: Task<Void, Never>?
    private var wantsNotchVisible = false
    private var keepVisibleUntil: Date?

    private let hideGracePeriod: TimeInterval = 0.3
    private let dragSessionGracePeriod: TimeInterval = 0.8
    private let hoverValidationInterval: TimeInterval = 0.12
    private let visiblePanelHitTestPadding: CGFloat = 8
    private let externalInteractionHoldDuration: TimeInterval = 10

    init(
        mediaManager: MediaManager,
        clipboardManager: ClipboardManager,
        fileShelfManager: FileShelfManager,
        onOpenSettings: @escaping () -> Void,
        isFileShelfEnabled: @escaping () -> Bool,
        isClipboardEnabled: @escaping () -> Bool,
        hoverDelay: @escaping () -> Double
    ) {
        self.mediaManager = mediaManager
        self.clipboardManager = clipboardManager
        self.fileShelfManager = fileShelfManager
        self.onOpenSettings = onOpenSettings
        self.isFileShelfEnabled = isFileShelfEnabled
        self.isClipboardEnabled = isClipboardEnabled
        self.hoverDelay = hoverDelay
    }

    func showNotch() {
        wantsNotchVisible = true
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        startHoverValidationTimer()

        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.configureNotchWindowLevel()
            if !isDynamicNotchVisible {
                isDynamicNotchVisible = true
                await dynamicNotch?.expand()
            }
            guard !Task.isCancelled, wantsNotchVisible else { return }
            self.configureNotchWindowLevel()
        }
    }

    func hideNotch() {
        wantsNotchVisible = false
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        dynamicNotch?.windowController?.window?.ignoresMouseEvents = false
        scheduleDragSessionEnd()

        visibilityTask?.cancel()
        visibilityTask = Task { @MainActor [weak self] in
            guard let self, self.isDynamicNotchVisible else { return }
            await dynamicNotch?.hide()
            guard !Task.isCancelled, !wantsNotchVisible else { return }
            self.isDynamicNotchVisible = false
            self.stopHoverValidationTimer()
        }

    }

    private var shouldKeepNotchVisible: Bool {
        isHoveringTrigger || isHoveringPanel || isDraggingOverTrigger || isDraggingOverPanel
            || isDragSessionActive || isExternalInteractionActive
    }

    private var isExternalInteractionActive: Bool {
        guard let keepVisibleUntil else { return false }
        return keepVisibleUntil > Date()
    }

    private func holdForExternalInteraction(duration: TimeInterval? = nil) {
        keepVisibleUntil = Date().addingTimeInterval(duration ?? externalInteractionHoldDuration)
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        showNotch()
    }

    private func evaluateHoverState() {
        if shouldKeepNotchVisible {
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
            showNotch()
        } else {
            guard isDynamicNotchVisible else { return }
            guard pendingHideWorkItem == nil else { return }

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshPointerHoverState()
                    if !self.shouldKeepNotchVisible {
                        self.hideNotch()
                    }
                    self.pendingHideWorkItem = nil
                }
            }
            pendingHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + hideGracePeriod, execute: workItem)
        }
    }

    private func triggerHoverChanged(_ isHovering: Bool) {
        isHoveringTrigger = isHovering
        evaluateHoverState()
    }

    private func panelHoverChanged(_ isHovering: Bool) {
        isHoveringPanel = isHovering
        evaluateHoverState()
    }

    private func triggerDraggingChanged(_ isDragging: Bool) {
        isDraggingOverTrigger = isDragging
        if isDragging {
            beginDragSession()
            isHoveringTrigger = false
        } else {
            scheduleDragSessionEnd()
        }
        configureNotchWindowLevel()
        evaluateHoverState()
    }

    private func panelDraggingChanged(_ isDragging: Bool) {
        isDraggingOverPanel = isDragging
        if isDragging {
            beginDragSession()
        } else {
            scheduleDragSessionEnd()
        }
        configureNotchWindowLevel()
        evaluateHoverState()
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard isFileShelfEnabled(), !providers.isEmpty else {
            isDraggingOverTrigger = false
            isDraggingOverPanel = false
            endDragSession()
            configureNotchWindowLevel()
            evaluateHoverState()
            return false
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                [weak self] item, _ in
                guard let url = Self.url(from: item) else { return }
                DispatchQueue.main.async {
                    self?.fileShelfManager.addFile(url: url)
                }
            }
        }

        isDraggingOverTrigger = false
        isDraggingOverPanel = false
        endDragSession()
        configureNotchWindowLevel()
        showNotch()
        return true
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
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

    func start() {
        rebuildDynamicNotch()
        setupTriggerWindows()
    }

    func updateContentWindowFrame() {
        stopHoverValidationTimer()
        hideNotch()
        rebuildDynamicNotch()
    }

    private func configureNotchWindowLevel() {
        guard let window = dynamicNotch?.windowController?.window else { return }

        let shouldLetTriggerHandleDrag =
            isDraggingOverTrigger
            && !isDraggingOverPanel
            && isPointerOverTrigger()
        window.level = isDragSessionActive ? .statusBar : .screenSaver
        window.ignoresMouseEvents = shouldLetTriggerHandleDrag
    }

    private func beginDragSession() {
        pendingDragEndWorkItem?.cancel()
        pendingDragEndWorkItem = nil
        isDragSessionActive = true
    }

    private func scheduleDragSessionEnd() {
        pendingDragEndWorkItem?.cancel()

        guard !isDraggingOverTrigger, !isDraggingOverPanel else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isDraggingOverTrigger, !self.isDraggingOverPanel else {
                    return
                }
                self.endDragSession()
                self.configureNotchWindowLevel()
                self.evaluateHoverState()
            }
        }
        pendingDragEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dragSessionGracePeriod, execute: workItem)
    }

    private func endDragSession() {
        pendingDragEndWorkItem?.cancel()
        pendingDragEndWorkItem = nil
        isDragSessionActive = false
        dynamicNotch?.windowController?.window?.ignoresMouseEvents = false
    }

    private func isPointerOverTrigger() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        return triggerWindows.contains { window in
            window.isVisible && window.frame.contains(mouseLocation)
        }
    }

    private func startHoverValidationTimer() {
        guard hoverValidationTimer == nil else { return }
        hoverValidationTimer = Timer.scheduledTimer(
            withTimeInterval: hoverValidationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPointerHoverState()
            }
        }
    }

    private func stopHoverValidationTimer() {
        hoverValidationTimer?.invalidate()
        hoverValidationTimer = nil
    }

    private func refreshPointerHoverState() {
        guard isDynamicNotchVisible else { return }

        configureNotchWindowLevel()

        let mouseLocation = NSEvent.mouseLocation
        let isActuallyHoveringTrigger =
            !isDraggingOverTrigger
            && isPointerOverTrigger()
        let panelWindow = dynamicNotch?.windowController?.window
        let visiblePanelFrame = panelWindow?.screen.map(visiblePanelInteractionFrame(on:))
        let isActuallyHoveringPanel = panelWindow?.isVisible == true
            && visiblePanelFrame?.contains(mouseLocation) == true

        guard isActuallyHoveringTrigger != isHoveringTrigger
            || isActuallyHoveringPanel != isHoveringPanel
        else { return }

        isHoveringTrigger = isActuallyHoveringTrigger
        isHoveringPanel = isActuallyHoveringPanel
        evaluateHoverState()
    }

    private func visiblePanelInteractionFrame(on screen: NSScreen) -> NSRect {
        let sectionCount = NotchLayout.panelSectionCount(
            enableFileShelf: isFileShelfEnabled(),
            showClipboard: isClipboardEnabled()
        )
        let metrics = NotchLayout.scaledMetrics(
            panelWidth: NotchConstants.basePanelWidth,
            panelHeight: NotchConstants.basePanelHeight,
            sectionCount: sectionCount,
            screenWidth: screen.visibleFrame.width
        )
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
        let contentWidth = metrics.totalWidth
            + (NotchLayout.expandedSafeAreaInset * 2)
            + 30
            + (visiblePanelHitTestPadding * 2)
        let contentHeight = menuBarHeight
            + metrics.totalHeight
            + NotchLayout.expandedSafeAreaInset
            + (visiblePanelHitTestPadding * 2)
        let origin = NSPoint(
            x: screen.frame.midX - (contentWidth / 2),
            y: screen.frame.maxY - contentHeight
        )
        return NSRect(origin: origin, size: NSSize(width: contentWidth, height: contentHeight))
    }

    private func setupTriggerWindows() {
        for window in triggerWindows {
            window.orderOut(nil)
        }
        triggerWindows.removeAll()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: triggerFrameWithPadding(on: screen),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            window.contentView = NSHostingView(
                rootView: TriggerAreaView(
                    onHoverChange: { [weak self] isHovering in
                        self?.triggerHoverChanged(isHovering)
                    },
                    onDragging: { [weak self] isDragging in
                        self?.triggerDraggingChanged(isDragging)
                    },
                    onDropProviders: { [weak self] providers in
                        self?.handleDroppedProviders(providers) ?? false
                    }
                )
            )
            window.orderFrontRegardless()
            triggerWindows.append(window)
        }
    }

    private func rebuildDynamicNotch() {
        let combinedView = CombinedNotchView(
            mediaManager: mediaManager,
            clipboardManager: clipboardManager,
            fileShelfManager: fileShelfManager,
            onOpenSettings: { [weak self] in
                self?.onOpenSettings()
            },
            onHover: { [weak self] isHovering in
                self?.panelHoverChanged(isHovering)
            },
            onDropTargetChange: { [weak self] isTargeted in
                self?.panelDraggingChanged(isTargeted)
            },
            onDropProviders: { [weak self] providers in
                self?.handleDroppedProviders(providers) ?? false
            },
            onExternalInteraction: { [weak self] in
                self?.holdForExternalInteraction()
            }
        )
        dynamicNotch = DynamicNotch(hoverBehavior: []) {
            combinedView
        }
    }

    private func triggerFrameWithPadding(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
        let NotchMore = screenFrame.maxY - menuBarHeight
        let notchWidth = NotchConstants.notchTriggerWidth
        let notchX = screenFrame.minX + (screenFrame.width - notchWidth) / 2
        let base = NSRect(x: notchX, y: NotchMore, width: notchWidth, height: menuBarHeight)
        return NSRect(
            x: base.origin.x - 10,
            y: base.origin.y - NotchConstants.hoverPadding,
            width: base.width + 20,
            height: base.height + NotchConstants.hoverPadding
        )
    }

    struct TriggerAreaView: View {
        var onHoverChange: (Bool) -> Void
        var onDragging: (Bool) -> Void
        var onDropProviders: ([NSItemProvider]) -> Bool
        @State private var isDropTargeted: Bool = false

        var body: some View {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    onHoverChange(isHovering)
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    let didAccept = onDropProviders(providers)
                    onDragging(false)
                    return didAccept
                }
                .onChange(of: isDropTargeted, initial: false) { _, isTargeted in
                    onDragging(isTargeted)
                }
        }
    }
}
