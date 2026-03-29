import AppKit
import Foundation

enum NotchConstants {
    // Base panel dimensions used before dynamic screen scaling.
    static let basePanelWidth: CGFloat = 305
    static let basePanelHeight: CGFloat = 305

    // Width of the notch hover trigger zone
    static let notchTriggerWidth: CGFloat = 200

    // Extra pixels below the notch for hover detection
    static let hoverPadding: CGFloat = 5

    // Maximum clipboard history items
    static let maxClipboardItems = 50

    // Maximum file shelf items
    static let maxFileShelfItems = 20

    // Thumbnail max size for artwork
    static let artworkThumbnailSize: CGFloat = 200

    // Thumbnail max size for clipboard images
    static let clipboardThumbnailSize: CGFloat = 200

    // Thumbnail max size for file shelf icons
    static let fileShelfThumbnailSize: CGFloat = 128

    // Album art display size
    static let albumArtSize: CGFloat = 70
}

enum NotchLayout {
    static let sectionSpacing: CGFloat = 10
    static let expandedSafeAreaInset: CGFloat = 15
    static let maxExpandedWidthRatio: CGFloat = 0.5

    static func contentHorizontalInset(for sectionCount: Int) -> CGFloat {
        sectionCount >= 3 ? 10 : 0
    }

    static func panelSectionCount(enableFileShelf: Bool, showClipboard: Bool) -> Int {
        var count = 1  // Media panel
        if enableFileShelf { count += 1 }
        if showClipboard { count += 1 }
        return count
    }

    static func scaledMetrics(
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        sectionCount: Int,
        screenWidth: CGFloat
    ) -> (
        panelWidth: CGFloat, panelHeight: CGFloat, totalWidth: CGFloat, totalHeight: CGFloat,
        scale: CGFloat, contentHorizontalInset: CGFloat
    ) {
        let safeSectionCount: Int = max(1, sectionCount)
        let spacingTotal: CGFloat = CGFloat(safeSectionCount - 1) * sectionSpacing
        let contentHorizontalInset = contentHorizontalInset(for: safeSectionCount)

        // DynamicNotchKit caps expanded notch width around half screen.
        // Keep content width under that cap minus framework side insets.
        let maxExpandedWidth = max(320, floor(screenWidth * maxExpandedWidthRatio))
        let maxContentWidth = max(240, maxExpandedWidth - (expandedSafeAreaInset * 2))
        let availablePanelWidth = max(
            80,
            (maxContentWidth - spacingTotal - (contentHorizontalInset * 2))
                / CGFloat(safeSectionCount))

        let scale = min(1, availablePanelWidth / max(panelWidth, 1))
        let scaledPanelWidth = floor(panelWidth * scale)
        let scaledPanelHeight = floor(panelHeight * scale)
        let scaledTotalWidth =
            (scaledPanelWidth * CGFloat(safeSectionCount)) + spacingTotal
            + (contentHorizontalInset * 2)

        return (
            panelWidth: scaledPanelWidth,
            panelHeight: scaledPanelHeight,
            totalWidth: scaledTotalWidth,
            totalHeight: scaledPanelHeight,
            scale: scale,
            contentHorizontalInset: contentHorizontalInset
        )
    }
}
