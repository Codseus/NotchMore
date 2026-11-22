import AppKit
import Foundation

enum NotchConstants {
    // Base panel dimensions used before dynamic screen scaling.
    static let basePanelWidth: CGFloat = 305
    static let basePanelHeight: CGFloat = 280

    // Default notch hover trigger zone size
    static let defaultTriggerWidth: CGFloat = 200

    // Default pixels below the menu bar for hover detection
    static let defaultTriggerHeight: CGFloat = 5

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

    static func utilityBarTopPadding(panelHeight: CGFloat) -> CGFloat {
        min(14, max(10, panelHeight * 0.05))
    }

    static func utilityBarHeight(panelHeight: CGFloat) -> CGFloat {
        utilityBarTopPadding(panelHeight: panelHeight) + 24 + 8
    }

    static func panelSectionCount(
        showNowPlaying: Bool, enableFileShelf: Bool, showClipboard: Bool, showTodoList: Bool
    ) -> Int {
        [showNowPlaying, enableFileShelf, showClipboard, showTodoList].filter { $0 }.count
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

        // Keep the expanded height stable as sections are enabled or disabled.
        // Three sections are the most constrained layout, so use that scale as
        // the common height reference while allowing each section's width to adapt.
        let heightReferenceSectionCount: CGFloat = 3
        let heightReferenceSpacing = (heightReferenceSectionCount - 1) * sectionSpacing
        let heightReferenceInset = NotchLayout.contentHorizontalInset(
            for: Int(heightReferenceSectionCount)
        )
        let heightReferencePanelWidth = max(
            80,
            (maxContentWidth - heightReferenceSpacing - (heightReferenceInset * 2))
                / heightReferenceSectionCount
        )
        let heightScale = min(1, heightReferencePanelWidth / max(panelWidth, 1))
        let scaledPanelHeight = floor(panelHeight * heightScale)
        let scaledTotalWidth =
            (scaledPanelWidth * CGFloat(safeSectionCount)) + spacingTotal
            + (contentHorizontalInset * 2)

        return (
            panelWidth: scaledPanelWidth,
            panelHeight: scaledPanelHeight,
            totalWidth: scaledTotalWidth,
            totalHeight: sectionCount == 0
                ? utilityBarHeight(panelHeight: scaledPanelHeight) : scaledPanelHeight,
            scale: scale,
            contentHorizontalInset: contentHorizontalInset
        )
    }
}
