import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    @State private var searchQuery: String = ""
    @State private var hoveredItemId: UUID?
    @State private var selectedCategory: ClipboardCategory = .all
    @State private var previewedItemID: UUID?

    var filteredHistory: [ClipboardItem] {
        var items = clipboardManager.history

        if selectedCategory != .all {
            items = items.filter { $0.category == selectedCategory }
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            items = items.filter { item in
                item.displayName.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }

        return items
    }

    private var hasUnpinnedHistoryItems: Bool {
        clipboardManager.history.contains { !$0.isPinned }
    }

    private var previewedItem: ClipboardItem? {
        guard let previewedItemID else { return nil }
        return clipboardManager.history.first { $0.id == previewedItemID }
    }

    var body: some View {
        Group {
            if let item = previewedItem {
                ClipboardItemPreviewView(
                    item: item,
                    onBack: { previewedItemID = nil },
                    onCopy: { clipboardManager.copyToClipboard(item: item) },
                    onOCR: { clipboardManager.copyOCRText(from: item) }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                historyContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: previewedItemID)
        .animation(.easeInOut(duration: 0.2), value: panelWidth)
        .animation(.easeInOut(duration: 0.2), value: panelHeight)
        .onChange(of: clipboardManager.history.map(\.id)) { _, ids in
            if let previewedItemID, !ids.contains(previewedItemID) {
                self.previewedItemID = nil
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)

            searchToolbar
                .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredHistory.isEmpty {
                        ClipboardEmptyStateView(
                            isSearchActive: !searchQuery.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                    } else {
                        ForEach(filteredHistory) { item in
                            ClipboardItemRow(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                onCopy: { clipboardManager.copyToClipboard(item: item) },
                                onOCR: { clipboardManager.copyOCRText(from: item) },
                                onDelete: { clipboardManager.deleteItem(item: item) },
                                onPin: { clipboardManager.togglePin(item: item) },
                                onOpen: { openItem(item) }
                            )
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredItemId = hovering ? item.id : nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            categoryFilter
                .padding(.horizontal, 14)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClipboardCategory.allCases, id: \.self) { category in
                    ClipboardCategoryChip(
                        title: category.rawValue,
                        count: countForCategory(category),
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var searchToolbar: some View {
        HStack(spacing: 8) {
            searchField

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    clipboardManager.deleteAllItems()
                    hoveredItemId = nil
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(
                NotchIconButtonStyle(
                    size: 24,
                    cornerRadius: 6,
                    tint: .secondary
                )
            )
            .disabled(!hasUnpinnedHistoryItems)
            .opacity(hasUnpinnedHistoryItems ? 1 : 0.42)
            .help("Delete Unpinned Clipboard History")
        }
    }

    private var searchField: some View {
        NotchSearchField(placeholder: "Search clipboard", text: $searchQuery)
            .frame(maxWidth: .infinity)
    }

    private func countForCategory(_ category: ClipboardCategory) -> Int {
        if category == .all { return clipboardManager.history.count }
        return clipboardManager.history.filter { $0.category == category }.count
    }

    private func openItem(_ item: ClipboardItem) {
        switch item.type {
        case .text, .image:
            previewedItemID = item.id
        case .file:
            clipboardManager.copyToClipboard(item: item)
        }
    }
}

// MARK: - Supporting Views

struct ClipboardCategoryChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
        .buttonStyle(NotchPillButtonStyle(height: 24, tint: .primary, isActive: isSelected))
    }
}

struct ClipboardEmptyStateView: View {
    let isSearchActive: Bool

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: isSearchActive ? "magnifyingglass" : "tray")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text(isSearchActive ? "No matching clipboard items" : "Clipboard is empty")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(
                isSearchActive
                    ? "Try another keyword" : "Copied text, images, and files appear here"
            )
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct ClipboardItemPreviewView: View {
    let item: ClipboardItem
    let onBack: () -> Void
    let onCopy: () -> Void
    let onOCR: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(NotchIconButtonStyle(size: 26, cornerRadius: 7))
                .help("Back to Clipboard History")

                VStack(alignment: .leading, spacing: 1) {
                    Text(previewTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(item.relativeTimeString)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if item.category == .image {
                    Button(action: onOCR) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(NotchIconButtonStyle(size: 26, cornerRadius: 7))
                    .help("Copy Text from Image")
                }

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(NotchIconButtonStyle(size: 26, cornerRadius: 7))
                .help("Copy")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.type {
        case .text(let text):
            SelectableClipboardTextView(text: text)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )

        case .image(let data, _):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
            } else {
                ContentUnavailableView("Preview Unavailable", systemImage: "photo")
            }

        case .file:
            EmptyView()
        }
    }

    private var previewTitle: String {
        switch item.type {
        case .text:
            return "Text Preview"
        case .image(_, let name):
            return name ?? "Image Preview"
        case .file(let url):
            return url.lastPathComponent
        }
    }
}

private struct SelectableClipboardTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ClipboardPreviewTextView()
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ClipboardPreviewTextView,
              textView.string != text
        else { return }
        textView.string = text
    }
}

private final class ClipboardPreviewTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c"
        {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Clipboard Item Row

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let onCopy: () -> Void
    let onOCR: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    itemPreview

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName)
                            .font(.system(size: 12, weight: item.isPinned ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color.yellow.opacity(0.85))
                            }

                            Text(item.relativeTimeString)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        ClipboardActionButton(
                            systemName: item.isPinned ? "pin.slash" : "pin", tint: .yellow,
                            action: onPin)
                        ClipboardActionButton(
                            systemName: "doc.on.doc", tint: .primary, action: onCopy)
                        ClipboardActionButton(systemName: "trash", tint: .red, action: onDelete)
                    }

                    if item.category == .image {
                        Button(action: onOCR) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("OCR")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(NotchPillButtonStyle(width: 74, height: 20))
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isHovered
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(item.isPinned ? Color.white.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isHovered ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.7)
        )
        .scaleEffect(isHovered ? 1.005 : 1)
        .shadow(color: Color.black.opacity(isHovered ? 0.14 : 0), radius: 4, x: 0, y: 2)
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var itemPreview: some View {
        Group {
            switch item.type {
            case .text:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            case .image(let data, _):
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackIcon(systemName: "photo")
                }

            case .file(let url):
                let isDirectory =
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                fallbackIcon(systemName: isDirectory ? "folder.fill" : "doc.fill")
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        )
    }

    private func fallbackIcon(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct ClipboardActionButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(
            NotchIconButtonStyle(
                size: 22,
                cornerRadius: 6,
                tint: tint,
                isDestructive: tint == .red
            )
        )
    }
}
