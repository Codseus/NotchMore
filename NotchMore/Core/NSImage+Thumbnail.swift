import AppKit

extension NSImage {
    func thumbnail(maxSize: CGFloat) -> NSImage {
        let originalSize = self.size
        guard originalSize.width > maxSize || originalSize.height > maxSize else {
            return self
        }
        
        let aspectRatio = originalSize.width / originalSize.height
        let newSize: NSSize
        
        if aspectRatio > 1 {
            newSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }
        
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize))
        thumbnail.unlockFocus()
        
        return thumbnail
    }
}
