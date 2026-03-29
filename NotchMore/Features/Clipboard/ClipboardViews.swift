import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    @State private var searchQuery: String = ""
    @State private var hoveredItemId: UUID?
    @State private var selectedCategory: ClipboardCategory = .all

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)

            searchField
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
                                onDelete: { clipboardManager.deleteItem(item: item) },
                                onPin: { clipboardManager.togglePin(item: item) }
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
        .animation(.easeInOut(duration: 0.2), value: panelWidth)
        .animation(.easeInOut(duration: 0.2), value: panelHeight)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search clipboard", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        )
    }

    private func countForCategory(_ category: ClipboardCategory) -> Int {
        if category == .all { return clipboardManager.history.count }
        return clipboardManager.history.filter { $0.category == category }.count
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
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.10),
                        lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Clipboard Item Row

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void

    var body: some View {
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

            if isHovered {
                HStack(spacing: 4) {
                    ClipboardActionButton(
                        systemName: item.isPinned ? "pin.slash" : "pin", tint: .yellow,
                        action: onPin)
                    ClipboardActionButton(systemName: "doc.on.doc", tint: .primary, action: onCopy)
                    ClipboardActionButton(systemName: "trash", tint: .red, action: onDelete)
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
        .onTapGesture {
            onCopy()
        }
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
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
    }
}
