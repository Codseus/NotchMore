import SwiftUI

struct DockPreviewView: View {
    @ObservedObject var manager = DockPreviewManager.shared
    @State private var hoveredWindowID: CGWindowID?

    private let cardWidth: CGFloat = 180
    private let previewHeight: CGFloat = 104
    private let spacing: CGFloat = 12
    private let sidePadding: CGFloat = 14
    private var cardOuterWidth: CGFloat { cardWidth + 16 }

    private var visibleWindows: [DockPreviewManager.PreviewWindow] {
        Array(manager.windows.prefix(8))
    }

    private var contentWidth: CGFloat {
        let count = max(1, visibleWindows.count)
        return CGFloat(count) * cardOuterWidth + CGFloat(max(0, count - 1)) * spacing + sidePadding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon = manager.hoveredAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }

                Text(manager.hoveredAppName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if manager.windows.count > visibleWindows.count {
                    Text("+\(manager.windows.count - visibleWindows.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HeaderActionButton(systemName: "power", action: manager.quitHoveredApplication)
                    .help("Quit \(manager.hoveredAppName)")
            }
            .padding(.horizontal, sidePadding)
            .padding(.top, 12)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(visibleWindows) { window in
                    DockPreviewCard(
                        window: window,
                        isHovered: hoveredWindowID == window.id,
                        width: cardWidth,
                        previewHeight: previewHeight,
                        onActivate: { manager.activate(window) },
                        onClose: { manager.close(window) },
                        onMinimize: { manager.minimize(window) },
                        onZoom: { manager.zoom(window) }
                    )
                    .onHover { hovering in
                        hoveredWindowID = hovering ? window.id : nil
                    }
                }
            }
            .padding(.horizontal, sidePadding)
            .padding(.bottom, 12)
        }
        .frame(width: min(contentWidth, (NSScreen.main?.visibleFrame.width ?? 1200) * 0.9))
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

private struct HeaderActionButton: View {
    let systemName: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.red.opacity(isHovered ? 0.95 : 0.82))
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.12 : 1)
        .brightness(isHovered ? 0.08 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DockPreviewCard: View {
    let window: DockPreviewManager.PreviewWindow
    let isHovered: Bool
    let width: CGFloat
    let previewHeight: CGFloat
    let onActivate: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onZoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                WindowActionButton(color: .red, systemName: "xmark", action: onClose)
                WindowActionButton(color: .yellow, systemName: "minus", action: onMinimize)
                WindowActionButton(color: .green, systemName: "arrow.up.left.and.arrow.down.right", action: onZoom)
                Spacer(minLength: 0)
            }
            .opacity(isHovered ? 1 : 0.68)

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(isHovered ? 0.28 : 0.2))

                if let snapshot = window.snapshot {
                    Image(nsImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "app.window")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: width, height: previewHeight)

            Text(window.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, height: 32, alignment: .topLeading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isHovered ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.025 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
    }
}

private struct WindowActionButton: View {
    let color: Color
    let systemName: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isHovered ? 0.5 : 0), lineWidth: 1)
                    )
                Image(systemName: systemName)
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundColor(.black.opacity(isHovered ? 0.78 : 0.62))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.18 : 1)
        .brightness(isHovered ? 0.08 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
