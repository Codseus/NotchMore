import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var fileShelfManager: FileShelfManager
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    var onExternalInteraction: (() -> Void)?
    @State private var hoveredFileId: UUID?
    @State private var isDropTargetActive = false
    @State private var searchQuery: String = ""
    @State private var selectedFileIds: Set<UUID> = []

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
                                    isSelected: selectedFileIds.contains(file.id),
                                    onDelete: {
                                        let files = actionFiles(for: file)
                                        fileShelfManager.removeFiles(files)
                                        selectedFileIds.subtract(files.map(\.id))
                                    },
                                    onOpen: {
                                        for file in actionFiles(for: file) {
                                            fileShelfManager.openFile(file)
                                        }
                                    },
                                    onCopy: {
                                        fileShelfManager.copyFiles(actionFiles(for: file))
                                    },
                                    onCopyPath: {
                                        fileShelfManager.copyPaths(actionFiles(for: file))
                                    },
                                    onShare: {
                                        onExternalInteraction?()
                                        return actionFiles(for: file).map(\.url)
                                    },
                                    dragURLs: {
                                        actionFiles(for: file).map(\.url)
                                    },
                                    actionFileCount: {
                                        actionFiles(for: file).count
                                    },
                                    onSelect: {
                                        select(file)
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
        .onChange(of: fileShelfManager.shelfFiles.map(\.id)) { _, ids in
            selectedFileIds.formIntersection(Set(ids))
        }
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

    private func select(_ file: ShelfFile) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedFileIds.contains(file.id) {
                selectedFileIds.remove(file.id)
            } else {
                selectedFileIds.insert(file.id)
            }
        } else {
            selectedFileIds = [file.id]
        }
    }

    private func actionFiles(for file: ShelfFile) -> [ShelfFile] {
        let selectedFiles = fileShelfManager.shelfFiles.filter { selectedFileIds.contains($0.id) }
        if selectedFileIds.contains(file.id), !selectedFiles.isEmpty {
            return selectedFiles
        }
        return [file]
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
    let isSelected: Bool
    let onDelete: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onCopyPath: () -> Void
    let onShare: () -> [URL]
    let dragURLs: () -> [URL]
    let actionFileCount: () -> Int
    let onSelect: () -> Void
    @State private var isDragging = false
    @State private var shareRequestID: UUID?
    @State private var shareURLs: [URL] = []

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
                .fill(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.24))
                        : isHovered
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.72) : isHovered ? Color.white.opacity(0.16) : Color.clear,
                    lineWidth: isSelected ? 1.1 : 0.7
                )
        )
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .onTapGesture(count: 2) {
            onOpen()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .onDrag {
            isDragging = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isDragging = false
            }
            let urls = dragURLs()
            if urls.count == 1, let url = urls.first {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: FileShelfDragProvider(urls: urls))
        }
        .contextMenu {
            Button("Open") {
                onOpen()
            }

            Divider()

            Button("Copy") {
                onCopy()
            }

            if actionFileCount() == 1 {
                Button("Copy Path") {
                    onCopyPath()
                }
            }

            Button("Share") {
                shareURLs = onShare()
                shareRequestID = UUID()
            }

            Divider()

            Button("Remove from Shelf", role: .destructive) {
                onDelete()
            }
        }
        .overlay(
            FileShelfSharePickerAnchor(urls: shareURLs, requestID: shareRequestID)
                .allowsHitTesting(false)
        )
        .overlay {
            if isSelected {
                FileShelfMultiDragView(
                    urls: dragURLs(),
                    onOpen: onOpen,
                    onCopy: onCopy,
                    onCopyPath: onCopyPath,
                    onShare: onShare,
                    onDelete: onDelete,
                    onSelect: onSelect,
                    actionFileCount: actionFileCount,
                    onDragStateChange: { isDragging = $0 }
                )
            }
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

private final class FileShelfDragProvider: NSObject, NSItemProviderWriting {
    static var writableTypeIdentifiersForItemProvider: [String] {
        [
            UTType.fileURL.identifier,
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType("NSFilenamesPboardType").rawValue,
        ]
    }

    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
        super.init()
    }

    func loadData(
        withTypeIdentifier typeIdentifier: String,
        forItemProviderCompletionHandler completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        if typeIdentifier == NSPasteboard.PasteboardType("NSFilenamesPboardType").rawValue {
            do {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: urls.map(\.path),
                    format: .binary,
                    options: 0
                )
                completionHandler(data, nil)
            } catch {
                completionHandler(nil, error)
            }
            return nil
        }

        completionHandler(urls.first?.absoluteString.data(using: .utf8), nil)
        return nil
    }
}

private struct FileShelfMultiDragView: NSViewRepresentable {
    let urls: [URL]
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onCopyPath: () -> Void
    let onShare: () -> [URL]
    let onDelete: () -> Void
    let onSelect: () -> Void
    let actionFileCount: () -> Int
    let onDragStateChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MultiFileDragSourceView()
        view.urls = urls
        view.onOpen = onOpen
        view.onCopy = onCopy
        view.onCopyPath = onCopyPath
        view.onShare = onShare
        view.onDelete = onDelete
        view.onSelect = onSelect
        view.actionFileCount = actionFileCount
        view.onDragStateChange = onDragStateChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MultiFileDragSourceView else { return }
        view.urls = urls
        view.onOpen = onOpen
        view.onCopy = onCopy
        view.onCopyPath = onCopyPath
        view.onShare = onShare
        view.onDelete = onDelete
        view.onSelect = onSelect
        view.actionFileCount = actionFileCount
        view.onDragStateChange = onDragStateChange
    }
}

private final class MultiFileDragSourceView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCopyPath: () -> Void = {}
    var onShare: () -> [URL] = { [] }
    var onDelete: () -> Void = {}
    var onSelect: () -> Void = {}
    var actionFileCount: () -> Int = { 1 }
    var onDragStateChange: (Bool) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        urls.count > 1 ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard urls.count > 1, let mouseDownEvent else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let draggingItems = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let size = NSSize(width: 48, height: 48)
            let frame = NSRect(
                x: localPoint.x - size.width / 2,
                y: localPoint.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }

        self.mouseDownEvent = nil
        didStartDrag = true
        onDragStateChange(true)
        beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag {
            onSelect()
        }
        mouseDownEvent = nil
        didStartDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open", action: #selector(openSelected), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copySelected), keyEquivalent: ""))
        if actionFileCount() == 1 {
            menu.addItem(NSMenuItem(title: "Copy Path", action: #selector(copyPathSelected), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Share", action: #selector(shareSelected), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Remove from Shelf", action: #selector(deleteSelected), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragStateChange(false)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    @objc private func openSelected() {
        onOpen()
    }

    @objc private func copySelected() {
        onCopy()
    }

    @objc private func copyPathSelected() {
        onCopyPath()
    }

    @objc private func shareSelected() {
        let urls = onShare()
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        let rect = bounds.isEmpty ? NSRect(x: 0, y: 0, width: 1, height: 1) : bounds
        picker.show(relativeTo: rect, of: self, preferredEdge: .minY)
    }

    @objc private func deleteSelected() {
        onDelete()
    }
}

private struct FileShelfSharePickerAnchor: NSViewRepresentable {
    let urls: [URL]
    let requestID: UUID?

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let requestID, !urls.isEmpty, context.coordinator.lastRequestID != requestID else {
            return
        }
        context.coordinator.lastRequestID = requestID

        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: urls)
            let rect = nsView.bounds.isEmpty
                ? NSRect(x: 0, y: 0, width: 1, height: 1)
                : nsView.bounds
            picker.show(relativeTo: rect, of: nsView, preferredEdge: .minY)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastRequestID: UUID?
    }
}
