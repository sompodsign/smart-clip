import AppKit
import os

/// Handles saving clipboard images to disk and generating thumbnails.
enum ImageService {
    private static let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Image")

    static func saveImage(data: Data, hash: String, directory: URL) -> (String, String)? {
        guard let image = NSImage(data: data) else {
            logger.error("Failed to create NSImage from data")
            return nil
        }

        let hashPrefix = String(hash.prefix(16))

        let imagePath = directory.appendingPathComponent("\(hashPrefix).png")
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            logger.error("Failed to convert image to PNG")
            return nil
        }

        do {
            try pngData.write(to: imagePath)
        } catch {
            logger.error("Failed to write image: \(error)")
            return nil
        }

        let thumbSize = Constants.thumbnailSize
        let thumbPath = directory.appendingPathComponent("\(hashPrefix)_thumb.png")

        let thumbImage = NSImage(size: NSSize(width: thumbSize, height: thumbSize))
        thumbImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: thumbSize, height: thumbSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        thumbImage.unlockFocus()

        if let thumbTiff = thumbImage.tiffRepresentation,
           let thumbBitmap = NSBitmapImageRep(data: thumbTiff),
           let thumbPng = thumbBitmap.representation(using: .png, properties: [:]) {
            do { try thumbPng.write(to: thumbPath) } catch {
                logger.error("Failed to write thumbnail: \(error)")
                return nil
            }
        }

        logger.info("Saved image: \(hashPrefix).png and thumbnail")
        return (imagePath.path, thumbPath.path)
    }
}
