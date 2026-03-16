import AppKit

/// Thread-safe in-memory image cache backed by NSCache.
/// Prevents repeated disk I/O when SwiftUI re-evaluates ItemCard bodies during hover.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        cache.countLimit = 200
    }

    /// Synchronous cache-first image lookup. Returns cached image or loads from disk and caches.
    func image(for path: String) -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        let cost = image.tiffRepresentation?.count ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Async image loader — loads from cache or disk off the main thread.
    func loadImageAsync(for path: String) async -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        return await withCheckedContinuation { continuation in
            let pathCopy = path  // capture String (Sendable) instead of NSString
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                guard let image = NSImage(contentsOfFile: pathCopy) else {
                    continuation.resume(returning: nil)
                    return
                }
                let cost = image.tiffRepresentation?.count ?? 0
                self.cache.setObject(image, forKey: pathCopy as NSString, cost: cost)
                continuation.resume(returning: image)
            }
        }
    }
}
