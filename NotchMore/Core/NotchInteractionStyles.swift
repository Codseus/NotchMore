import AppKit
import SwiftUI

struct NotchIconButtonStyle: ButtonStyle {
    var size: CGFloat = 24
    var cornerRadius: CGFloat = 7
    var tint: Color = .primary
    var isActive: Bool = false
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        NotchIconButtonBody(
            configuration: configuration,
            size: size,
            cornerRadius: cornerRadius,
            tint: tint,
            isActive: isActive,
            isDestructive: isDestructive
        )
    }
}

private struct NotchIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let size: CGFloat
    let cornerRadius: CGFloat
    let tint: Color
    let isActive: Bool
    let isDestructive: Bool

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundStyle)
            .frame(width: size, height: size)
            .background(backgroundShape)
            .overlay(borderShape)
            .scaleEffect(configuration.isPressed ? 0.90 : isHovered ? 1.06 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : isHovered ? 0.04 : 0)
            .shadow(
                color: Color.black.opacity(isHovered && !configuration.isPressed ? 0.18 : 0),
                radius: 5,
                x: 0,
                y: 2
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.13, dampingFraction: 0.62), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
    }

    private var foregroundStyle: Color {
        if isDestructive {
            return .red
        }
        if isActive {
            return tint
        }
        return tint.opacity(isHovered ? 0.95 : 0.72)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundStyle)
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isActive
                    ? tint.opacity(configuration.isPressed ? 0.46 : 0.30)
                    : Color.white.opacity(isHovered ? 0.24 : 0.10),
                lineWidth: 0.8
            )
    }

    private var backgroundStyle: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(tint.opacity(configuration.isPressed ? 0.22 : isHovered ? 0.18 : 0.13))
        }
        if configuration.isPressed {
            return AnyShapeStyle(Color.white.opacity(0.22))
        }
        if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.15))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

struct NotchPillButtonStyle: ButtonStyle {
    var width: CGFloat? = nil
    var height: CGFloat = 24
    var tint: Color = .primary
    var isActive: Bool = false
    var fillsAvailableWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        NotchPillButtonBody(
            configuration: configuration,
            width: width,
            height: height,
            tint: tint,
            isActive: isActive,
            fillsAvailableWidth: fillsAvailableWidth
        )
    }
}

private struct NotchPillButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let width: CGFloat?
    let height: CGFloat
    let tint: Color
    let isActive: Bool
    let fillsAvailableWidth: Bool

    @State private var isHovered = false

    var body: some View {
        sizedLabel
            .padding(.horizontal, width == nil ? 9 : 0)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isActive ? tint.opacity(0.30) : Color.white.opacity(isHovered ? 0.24 : 0.10),
                        lineWidth: 0.8
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : isHovered ? 1.03 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : isHovered ? 0.04 : 0)
            .contentShape(Capsule(style: .continuous))
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.13, dampingFraction: 0.65), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
    }

    @ViewBuilder
    private var sizedLabel: some View {
        if fillsAvailableWidth {
            configuration.label
                .foregroundStyle(tint.opacity(isHovered || isActive ? 1.0 : 0.78))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        } else {
            configuration.label
                .foregroundStyle(tint.opacity(isHovered || isActive ? 1.0 : 0.78))
                .frame(width: width, height: height)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(tint.opacity(configuration.isPressed ? 0.22 : isHovered ? 0.18 : 0.12))
        }
        if configuration.isPressed {
            return AnyShapeStyle(Color.white.opacity(0.20))
        }
        if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.14))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

extension View {
    func resetArrowCursorOnHover() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }
}
