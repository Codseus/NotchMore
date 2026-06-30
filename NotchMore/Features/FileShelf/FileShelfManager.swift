import SwiftUI
import UniformTypeIdentifiers

struct ShelfFile: Identifiable, Equatable, Codable {
    let id: UUID
    let urlBookmark: Data
    let name: String
    let type: FileType
    private let iconData: Data?
    
    enum FileType: String, Codable {
        case image
        case document
        case folder
        case other
    }
    
    static func == (lhs: ShelfFile, rhs: ShelfFile) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Resolved URL from bookmark data
    var url: URL {
        var isStale = false
        return (try? URL(resolvingBookmarkData: urlBookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)) ?? URL(fileURLWithPath: "/")
    }
    
    // NSImage icon decoded from stored data
    var icon: NSImage? {
        guard let data = iconData else { return nil }
        return NSImage(data: data)
    }
    
    init(url: URL) {
        self.id = UUID()
        self.urlBookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        self.name = url.lastPathComponent
        
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        
        if isDirectory {
            self.type = .folder
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            self.iconData = icon.tiffRepresentation
        } else {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "pdf"]
            let ext = url.pathExtension.lowercased()
            
            if imageExtensions.contains(ext) {
                self.type = .image
                if let image = NSImage(contentsOf: url),
                    let thumb = image.thumbnail(maxSize: NotchConstants.fileShelfThumbnailSize)
                {
                    self.iconData = thumb.tiffRepresentation
                } else {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    self.iconData = icon.tiffRepresentation
                }
            } else if ["txt", "doc", "docx", "pdf", "pages"].contains(ext) {
                self.type = .document
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                self.iconData = icon.tiffRepresentation
            } else {
                self.type = .other
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                self.iconData = icon.tiffRepresentation
            }
        }
    }
}

class FileShelfManager: ObservableObject {
    @Published var shelfFiles: [ShelfFile] = []
    
    private static let storageKey = "fileShelfItems"
    
    init() {
        loadFiles()
    }
    
    func addFile(url: URL) {
        // Check if file already exists by name
        if shelfFiles.contains(where: { $0.name == url.lastPathComponent }) {
            return
        }
        
        let newFile = ShelfFile(url: url)
        DispatchQueue.main.async {
            self.shelfFiles.insert(newFile, at: 0)
            if self.shelfFiles.count > NotchConstants.maxFileShelfItems {
                self.shelfFiles.removeLast()
            }
            self.saveFiles()
        }
    }
    
    func removeFile(_ file: ShelfFile) {
        DispatchQueue.main.async {
            self.shelfFiles.removeAll(where: { $0.id == file.id })
            self.saveFiles()
        }
    }

    func removeFiles(_ files: [ShelfFile]) {
        let ids = Set(files.map(\.id))
        DispatchQueue.main.async {
            self.shelfFiles.removeAll(where: { ids.contains($0.id) })
            self.saveFiles()
        }
    }
    
    func clearAll() {
        DispatchQueue.main.async {
            self.shelfFiles.removeAll()
            self.saveFiles()
        }
    }
    
    func openFile(_ file: ShelfFile) {
        NSWorkspace.shared.open(file.url)
    }

    func copyFile(_ file: ShelfFile) {
        copyFiles([file])
    }

    func copyFiles(_ files: [ShelfFile]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0.url as NSURL })
    }

    func copyPath(_ file: ShelfFile) {
        copyPaths([file])
    }

    func copyPaths(_ files: [ShelfFile]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(files.map(\.url.path).joined(separator: "\n"), forType: .string)
    }
    
    // MARK: - Persistence
    
    private func saveFiles() {
        if let data = try? JSONEncoder().encode(shelfFiles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    private func loadFiles() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ShelfFile].self, from: data) {
            shelfFiles = decoded
        }
    }
}
