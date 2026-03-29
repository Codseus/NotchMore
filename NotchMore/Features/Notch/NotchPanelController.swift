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
    private var isDraggingItem = false
    private var triggerWindows: [NSWindow] = []
    private var isHoveringTrigger = false
    private var isHoveringPanel = false
    private var pendingHideWorkItem: DispatchWorkItem?

    private let hideGracePeriod: TimeInterval = 0.3

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
        Task { @MainActor in
            if isDraggingItem {
                dynamicNotch?.windowController?.window?.level = .statusBar
            } else {
                dynamicNotch?.windowController?.window?.level = .screenSaver
            }
            if !isDynamicNotchVisible {
                isDynamicNotchVisible = true
                await dynamicNotch?.expand()
            }
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
        }
    }

    func hideNotch() {
        Task { @MainActor in
            guard isDynamicNotchVisible else { return }
            await dynamicNotch?.hide()
            isDynamicNotchVisible = false
        }

    }

    private func evaluateHoverState() {
        let shouldShow =
            isHoveringTrigger || (isDynamicNotchVisible && isHoveringPanel) || isDraggingItem

        if shouldShow {
            pendingHideWorkItem?.cancel()
            pendingHideWorkItem = nil
            showNotch()
        } else {
            guard isDynamicNotchVisible else { return }
            guard pendingHideWorkItem == nil else { return }

            let workItem = DispatchWorkItem { [weak self] in
                self?.hideNotch()
                self?.pendingHideWorkItem = nil
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

    private func draggingChanged(_ isDragging: Bool) {
        isDraggingItem = isDragging
        evaluateHoverState()
    }

    func start() {
        rebuildDynamicNotch()
        setupTriggerWindows()
    }

    func updateContentWindowFrame() {
        hideNotch()
        rebuildDynamicNotch()
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
                        self?.draggingChanged(isDragging)
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
                self?.draggingChanged(isTargeted)
            }
        )
        dynamicNotch = DynamicNotch {
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
        @State private var isDropTargeted: Bool = false

        var body: some View {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    onHoverChange(isHovering)
                }.dropDestination(for: URL.self) { items, location in
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        onHoverChange(true)
                        onDragging(true)
                    } else {
                        onHoverChange(false)
                        onDragging(false)

                    }
                }
        }
    }
}
