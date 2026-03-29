import SwiftUI
import AppKit

enum ClipboardItemType: Codable {
    case text(String)
    case image(Data, name: String?)
    case file(URL)
    
    enum CodingKeys: String, CodingKey {
        case type, textValue, imageData, imageName, fileURL
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .textValue)
            self = .text(text)
        case "image":
            let data = try container.decode(Data.self, forKey: .imageData)
            let name = try container.decodeIfPresent(String.self, forKey: .imageName)
            self = .image(data, name: name)
        case "file":
            let url = try container.decode(URL.self, forKey: .fileURL)
            self = .file(url)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .textValue)
        case .image(let data, let name):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .imageData)
            try container.encodeIfPresent(name, forKey: .imageName)
        case .file(let url):
            try container.encode("file", forKey: .type)
            try container.encode(url, forKey: .fileURL)
        }
    }
}

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    var isPinned: Bool
    
    init(type: ClipboardItemType, timestamp: Date = Date(), isPinned: Bool = false) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.isPinned = isPinned
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    var displayName: String {
        switch type {
        case .text(let text):
            return String(text.prefix(50))
        case .image(_, let name):
            return name ?? "Image"
        case .file(let url):
            return url.lastPathComponent
        }
    }
    
    // Returns the NSImage for image items (decoded from stored Data)
    var nsImage: NSImage? {
        if case .image(let data, _) = type {
            return NSImage(data: data)
        }
        return nil
    }
    
    // Relative time description 
    var relativeTimeString: String {
        let interval = -timestamp.timeIntervalSinceNow
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
    
    var category: ClipboardCategory {
        switch type {
        case .text: return .text
        case .image: return .image
        case .file: return .file
        }
    }
}

enum ClipboardCategory: String, CaseIterable {
    case all = "All"
    case text = "Text"
    case image = "Images"
    case file = "Files"
}

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var isMonitoringEnabled = false

    private static let storageKey = "clipboardHistory"
    private static let historyLimitKey = "clipboardHistoryLimit"
    private static let defaultHistoryLimit = 10

    init() {
        lastChangeCount = pasteboard.changeCount
        loadHistory()
        enforceHistoryLimit()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        // Ignore clipboard changes that happened while monitoring was disabled.
        lastChangeCount = pasteboard.changeCount
        enforceHistoryLimit()
        isMonitoringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        isMonitoringEnabled = false
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        guard isMonitoringEnabled else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let url = urls[0]
            
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "svg"]
            let fileExtension = url.pathExtension.lowercased()
            
            if imageExtensions.contains(fileExtension), let image = NSImage(contentsOf: url) {
                let thumbnail = image.thumbnail(maxSize: NotchConstants.clipboardThumbnailSize)
                let imageData = thumbnail.tiffRepresentation ?? Data()
                let newItem = ClipboardItem(type: .image(imageData, name: url.lastPathComponent))
                addItem(newItem)
                return
            } else {
                let newItem = ClipboardItem(type: .file(url))
                DispatchQueue.main.async {
                    guard self.isMonitoringEnabled else { return }
                    if let firstItem = self.history.first(where: { !$0.isPinned }),
                       case .file(let existingURL) = firstItem.type,
                       existingURL == url {
                        return
                    }
                    self.insertItem(newItem)
                }
                return
            }
        }
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let thumbnail = image.thumbnail(maxSize: NotchConstants.clipboardThumbnailSize)
            let imageData = thumbnail.tiffRepresentation ?? Data()
            let newItem = ClipboardItem(type: .image(imageData, name: nil))
            addItem(newItem)
            return
        }
        
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newItem = ClipboardItem(type: .text(text))
            DispatchQueue.main.async {
                guard self.isMonitoringEnabled else { return }
                if let firstItem = self.history.first(where: { !$0.isPinned }),
                   case .text(let existingText) = firstItem.type,
                   existingText == text {
                    return
                }
                self.insertItem(newItem)
            }
        }
    }
    
    private func addItem(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            guard self.isMonitoringEnabled else { return }
            if !self.history.contains(where: { historyItem in
                if case .image = historyItem.type, historyItem.timestamp.timeIntervalSinceNow > -0.5 {
                    return true
                }
                return false
            }) {
                self.insertItem(item)
            }
        }
    }
    
    private func insertItem(_ item: ClipboardItem) {
        // Insert after pinned items
        let insertIndex = history.firstIndex(where: { !$0.isPinned }) ?? history.count
        history.insert(item, at: insertIndex)
        enforceHistoryLimit()
        saveHistory()
    }

    private var historyLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.historyLimitKey)
        let raw = stored == 0 ? Self.defaultHistoryLimit : stored
        return Self.normalizedLimit(raw)
    }

    private static func normalizedLimit(_ value: Int) -> Int {
        let clamped = max(10, min(50, value))
        return ((clamped + 5) / 10) * 10
    }

    private func enforceHistoryLimit() {
        let limit = historyLimit
        while history.filter({ !$0.isPinned }).count > limit {
            if let lastUnpinnedIndex = history.lastIndex(where: { !$0.isPinned }) {
                history.remove(at: lastUnpinnedIndex)
            } else {
                break
            }
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.type {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, _):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        }
        lastChangeCount = pasteboard.changeCount
    }

    func deleteItem(item: ClipboardItem) {
        DispatchQueue.main.async {
            self.history.removeAll(where: { $0.id == item.id })
            self.saveHistory()
        }
    }
    
    func togglePin(item: ClipboardItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()
            // pinned items first
            let pinned = history.filter { $0.isPinned }
            let unpinned = history.filter { !$0.isPinned }
            history = pinned + unpinned
            saveHistory()
        }
    }
    
    // MARK: - Persistence 
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            history = decoded
        }
    }

    deinit {
        stopMonitoring()
    }
}
