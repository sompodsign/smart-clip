import AppKit
import CryptoKit
import os

/// Monitors the system clipboard for changes via NSPasteboard polling.
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastTextHash: String?
    private var lastImageHash: String?

    private let databaseService: DatabaseService
    private let licenseService: LicenseService
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Clipboard")
    private let processingQueue = DispatchQueue(label: "com.smartclip.clipboard.processing", qos: .userInitiated)

    var onClipboardChange: (() -> Void)?

    init(databaseService: DatabaseService, licenseService: LicenseService) {
        self.databaseService = databaseService
        self.licenseService = licenseService
    }

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        logger.info("Clipboard monitoring started (interval: \(Constants.pollIntervalSeconds)s)")
        timer = Timer.scheduledTimer(withTimeInterval: Constants.pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Check available types first (cheap) before reading data
        let types = pb.types ?? []
        let hasImage = types.contains(.tiff) || types.contains(.png)

        if hasImage {
            // Read image data on main (NSPasteboard requires it), then process off-main
            guard let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png) else { return }
            processingQueue.async { [weak self] in
                guard let self else { return }
                let hash = self.sha256(imageData)
                if hash != self.lastImageHash {
                    self.lastImageHash = hash
                    self.handleImage(imageData, hash: hash)
                }
            }
        } else if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let html = pb.string(forType: .html)
            processingQueue.async { [weak self] in
                guard let self else { return }
                let hash = self.sha256(Data(text.utf8))
                if hash != self.lastTextHash {
                    self.lastTextHash = hash
                    self.handleText(text, html: html, hash: hash)
                }
            }
        }
    }

    private func handleText(_ text: String, html: String?, hash: String) {
        do {
            if try databaseService.deduplicate(hash: hash) {
                notifyChange()
                return
            }
            enforceItemLimits()
            let newItem = NewClipboardItem(contentType: "text", textValue: text, htmlValue: html, imagePath: nil, thumbPath: nil, hash: hash, appSource: nil)
            let id = try databaseService.insert(newItem)
            logger.info("Stored text entry (id=\(id), has_html=\(html != nil))")
            notifyChange()
        } catch {
            logger.error("Failed to insert text item: \(error)")
        }
    }

    private func handleImage(_ data: Data, hash: String) {
        do {
            if try databaseService.deduplicate(hash: hash) {
                notifyChange()
                return
            }
            enforceItemLimits()
            guard let (imagePath, thumbPath) = ImageService.saveImage(data: data, hash: hash, directory: databaseService.imagesDirectory) else {
                logger.warning("Failed to save clipboard image")
                return
            }
            let newItem = NewClipboardItem(contentType: "image", textValue: nil, htmlValue: nil, imagePath: imagePath, thumbPath: thumbPath, hash: hash, appSource: nil)
            let id = try databaseService.insert(newItem)
            logger.info("Stored image entry (id=\(id))")
            notifyChange()
        } catch {
            logger.error("Failed to insert image item: \(error)")
        }
    }

    private func enforceItemLimits() {
        let isPro = licenseService.currentEntitlement().isUnlimited
        do {
            if !isPro {
                let count = try databaseService.countItems()
                if count >= Constants.freeTierLimit {
                    try databaseService.enforceLimit(Constants.freeTierLimit - 1)
                }
            } else {
                let maxItems = databaseService.maxItems
                try databaseService.enforceLimit(maxItems - 1)
            }
        } catch {
            logger.error("Failed to enforce item limits: \(error)")
        }
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onClipboardChange?()
        }
    }
}
