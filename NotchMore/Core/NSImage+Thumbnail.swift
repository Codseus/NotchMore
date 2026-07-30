import AppKit

extension NSImage {
    func thumbnail(maxSize: CGFloat) -> NSImage? {
        guard let source = normalizedCGImage else { return nil }

        let originalSize = NSSize(width: source.width, height: source.height)
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
        
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: source.bitsPerComponent,
            bytesPerRow: 0,
            space: source.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(origin: .zero, size: newSize))
        guard let resized = context.makeImage() else { return nil }

        let thumbnail = NSImage(cgImage: resized, size: newSize)
        return thumbnail
    }

    var hasRenderableImage: Bool {
        normalizedCGImage != nil
    }

    var normalizedCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        if let image = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return image
        }

        if let representation = bestRepresentation(for: proposedRect, context: nil, hints: nil),
           let image = representation.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return image
        }

        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else { return nil }

        return bitmap.cgImage
    }
}
