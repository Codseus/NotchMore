import AppKit
import SwiftUI

@MainActor
final class TriggerZonePreviewManager {
    static let shared = TriggerZonePreviewManager()

    private var windows: [NSWindow] = []
    private var hideWorkItem: DispatchWorkItem?

    func show(width: CGFloat, height: CGFloat) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if windows.count != NSScreen.screens.count {
            rebuildWindows()
        }

        for (index, screen) in NSScreen.screens.enumerated() {
            guard windows.indices.contains(index) else { continue }
            let window = windows[index]
            window.setFrame(Self.triggerFrame(on: screen, width: width, height: height), display: true)
            window.orderFrontRegardless()
        }
    }

    func showTemporarily(width: CGFloat, height: CGFloat, duration: TimeInterval = 1.5) {
        show(width: width, height: height)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hide()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        for window in windows {
            window.orderOut(nil)
        }
    }

    static func triggerFrame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
        let clampedWidth = max(80, min(screen.frame.width, width))
        let clampedHeight = max(1, min(120, height))
        let x = screen.frame.midX - (clampedWidth / 2)
        let y = screen.frame.maxY - menuBarHeight - clampedHeight
        return NSRect(x: x, y: y, width: clampedWidth, height: menuBarHeight + clampedHeight)
    }

    private func rebuildWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: Self.triggerFrame(
                    on: screen,
                    width: NotchConstants.defaultTriggerWidth,
                    height: NotchConstants.defaultTriggerHeight
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            window.contentView = NSHostingView(rootView: TriggerZonePreviewView())
            windows.append(window)
        }
    }
}

private struct TriggerZonePreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            )
            .overlay(alignment: .bottom) {
                Text("Notch Trigger Zone")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .padding(.bottom, 8)
            }
    }
}
