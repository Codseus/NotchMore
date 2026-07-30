import SwiftUI
import AppKit
import Vision

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
    private var screenshotFolderSource: DispatchSourceFileSystemObject?
    private var screenshotFolderDescriptor: CInt = -1
    private var screenshotFolderURL: URL?
    private var recentlyHandledScreenshotPaths = Set<String>()
    private let screenshotQueue = DispatchQueue(label: "codseus.NotchMore.screenshotMonitor")
    private var pendingScreenshotScanWorkItem: DispatchWorkItem?

    private static let storageKey = "clipboardHistory"
    private static let historyLimitKey = "clipboardHistoryLimit"
    private static let defaultHistoryLimit = 10
    private static let screenshotImageExtensions = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp"
    ]
    private static let storedImageMaxSize: CGFloat = 1400

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

    func updateScreenshotMonitoring(isEnabled: Bool) {
        stopScreenshotMonitoring()
        guard isEnabled else { return }
        startScreenshotMonitoring()
    }

    private func checkClipboard() {
        guard isMonitoringEnabled else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let url = urls[0]
            
            let fileExtension = url.pathExtension.lowercased()
            
            if Self.screenshotImageExtensions.contains(fileExtension) || fileExtension == "svg",
               let image = NSImage(contentsOf: url) {
                let imageData = storedImageData(from: image)
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
            let imageData = storedImageData(from: image)
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

    private func storedImageData(from image: NSImage) -> Data {
        let image = image.thumbnail(maxSize: Self.storedImageMaxSize) ?? image
        return image.normalizedCGImage.flatMap { cgImage in
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .png, properties: [:])
        } ?? image.tiffRepresentation ?? Data()
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

    func copyOCRText(from item: ClipboardItem) {
        guard case .image(let data, _) = item.type, let image = NSImage(data: data) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let text = Self.recognizedText(from: image), !text.isEmpty else { return }

            DispatchQueue.main.async {
                self?.copyTextToClipboardAndHistory(text)
            }
        }
    }

    private func copyTextToClipboardAndHistory(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        insertItem(ClipboardItem(type: .text(text)))
    }

    func deleteItem(item: ClipboardItem) {
        DispatchQueue.main.async {
            self.history.removeAll(where: { $0.id == item.id })
            self.saveHistory()
        }
    }

    func deleteAllItems() {
        DispatchQueue.main.async {
            self.history.removeAll(where: { !$0.isPinned })
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

    private func startScreenshotMonitoring() {
        guard screenshotFolderSource == nil else { return }
        let folderURL = Self.currentScreenshotFolderURL()
        screenshotFolderURL = folderURL

        let descriptor = open(folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        screenshotFolderDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: screenshotQueue
        )
        source.setEventHandler { [weak self] in
            self?.handleScreenshotFolderChanged()
        }
        source.setCancelHandler { [weak self] in
            close(descriptor)
            DispatchQueue.main.async {
                guard self?.screenshotFolderDescriptor == descriptor else { return }
                self?.screenshotFolderDescriptor = -1
            }
        }
        screenshotFolderSource = source
        source.resume()
    }

    private func stopScreenshotMonitoring() {
        pendingScreenshotScanWorkItem?.cancel()
        pendingScreenshotScanWorkItem = nil
        screenshotFolderSource?.cancel()
        screenshotFolderSource = nil
        screenshotFolderURL = nil
        screenshotQueue.async { [weak self] in
            self?.recentlyHandledScreenshotPaths.removeAll()
        }
    }

    private func handleScreenshotFolderChanged() {
        guard let folderURL = screenshotFolderURL else { return }

        pendingScreenshotScanWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.copyRecentScreenshotIfNeeded(in: folderURL)
        }
        pendingScreenshotScanWorkItem = workItem
        screenshotQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func copyRecentScreenshotIfNeeded(in folderURL: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        let candidates = files.compactMap { url -> (url: URL, date: Date)? in
            guard Self.screenshotImageExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            guard Self.looksLikeScreenshotFile(url) else { return nil }
            guard !recentlyHandledScreenshotPaths.contains(url.path) else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true, let date = values?.contentModificationDate else {
                return nil
            }
            guard now.timeIntervalSince(date) <= 8 else { return nil }
            return (url, date)
        }

        guard let newest = candidates.max(by: { $0.date < $1.date })?.url else { return }
        recentlyHandledScreenshotPaths.insert(newest.path)
        if recentlyHandledScreenshotPaths.count > 40 {
            recentlyHandledScreenshotPaths.removeAll(keepingCapacity: true)
            recentlyHandledScreenshotPaths.insert(newest.path)
        }

        guard let image = NSImage(contentsOf: newest) else { return }
        let data = storedImageData(from: image)
        guard !data.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pasteboard.clearContents()
            if let copiedImage = NSImage(data: data) {
                self.pasteboard.writeObjects([copiedImage])
            }
            self.lastChangeCount = self.pasteboard.changeCount
            self.insertItem(ClipboardItem(type: .image(data, name: newest.lastPathComponent)))
        }
    }

    private static func currentScreenshotFolderURL() -> URL {
        if let location = CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String,
           !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: location).expandingTildeInPath)
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private static func looksLikeScreenshotFile(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name.hasPrefix("screenshot")
            || name.hasPrefix("screen shot")
            || name.hasPrefix("ekran resmi")
    }

    private static func recognizedText(from image: NSImage) -> String? {
        guard let cgImage = image.normalizedCGImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let lines = request.results?.compactMap { observation in
                observation.topCandidates(1).first?.string
            } ?? []
            return lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    deinit {
        stopMonitoring()
        stopScreenshotMonitoring()
    }
}
