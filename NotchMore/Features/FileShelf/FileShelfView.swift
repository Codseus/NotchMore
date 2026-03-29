import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var fileShelfManager: FileShelfManager
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    @State private var hoveredFileId: UUID?
    @State private var isDropTargetActive = false
    @State private var searchQuery: String = ""

    private let gridColumnCount = 3
    private let gridSpacing: CGFloat = 8
    private let gridHorizontalPadding: CGFloat = 12

    var filteredFiles: [ShelfFile] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return fileShelfManager.shelfFiles
        }
        return fileShelfManager.shelfFiles.filter { file in
            file.name.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

            GeometryReader { geo in
                let availableWidth = max(
                    0,
                    geo.size.width - (gridHorizontalPadding * 2)
                        - (gridSpacing * CGFloat(gridColumnCount - 1)))
                let itemWidth = max(64, floor(availableWidth / CGFloat(gridColumnCount)))
                let gridColumns = Array(
                    repeating: GridItem(.fixed(itemWidth), spacing: gridSpacing),
                    count: gridColumnCount)

                ScrollView(.vertical, showsIndicators: true) {
                    if fileShelfManager.shelfFiles.isEmpty {
                        FileShelfEmptyState(text: "Drop files here")
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else if filteredFiles.isEmpty {
                        FileShelfEmptyState(text: "No files match \"\(searchQuery)\"")
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                            ForEach(filteredFiles) { file in
                                FileShelfItemView(
                                    file: file,
                                    itemWidth: itemWidth,
                                    isHovered: hoveredFileId == file.id,
                                    onDelete: {
                                        fileShelfManager.removeFile(file)
                                    },
                                    onOpen: {
                                        fileShelfManager.openFile(file)
                                    }
                                )
                                .onHover { hovering in
                                    hoveredFileId = hovering ? file.id : nil
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isDropTargetActive
                            ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                            : AnyShapeStyle(Color.clear))
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargetActive) { providers in
                handleDrop(providers: providers)
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: panelWidth)
        .animation(.easeInOut(duration: 0.2), value: panelHeight)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Quick Access", systemImage: "folder.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            searchField

            if !fileShelfManager.shelfFiles.isEmpty {
                Button(action: { fileShelfManager.clearAll() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                }
                .buttonStyle(.plain)
                .help("Clear all")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .regular))
                .frame(width: 84)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.7)
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
                if let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    fileShelfManager.addFile(url: url)
                }
            }
        }
        return true
    }
}

struct FileShelfEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.tertiary)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
    }
}

struct FileShelfItemView: View {
    let file: ShelfFile
    let itemWidth: CGFloat
    let isHovered: Bool
    let onDelete: () -> Void
    let onOpen: () -> Void
    @State private var isDragging = false

    private var iconSize: CGFloat {
        min(68, max(36, itemWidth * 0.62))
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                fileIcon

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
            }

            Text(file.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: max(48, itemWidth - 8))
        }
        .frame(width: itemWidth)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered ? Color.white.opacity(0.16) : Color.clear, lineWidth: 0.7)
        )
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .onTapGesture(count: 2) {
            onOpen()
        }
        .onDrag {
            isDragging = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isDragging = false
            }
            return NSItemProvider(object: file.url as NSURL)
        }
        .help("Double-click to open")
    }

    private var fileIcon: some View {
        Group {
            if let icon = file.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        )
    }
}
