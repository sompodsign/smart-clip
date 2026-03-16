import Foundation
import AppKit
import os

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""
    @Published var activeFilter: String = "all"
    @Published var license: LicenseEntitlement = .free()
    @Published var maxItems: Int64 = Constants.defaultMaxItems
    @Published var plainTextOnly: Bool = false
    @Published var copiedItemId: Int64? = nil

    /// Called by AppDelegate to wire up panel dismissal
    var onDismiss: (() -> Void)?

    private let databaseService: DatabaseService
    private let licenseService: LicenseService
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ViewModel")

    init(databaseService: DatabaseService, licenseService: LicenseService) {
        self.databaseService = databaseService
        self.licenseService = licenseService
        maxItems = databaseService.maxItems
        plainTextOnly = databaseService.plainTextOnly
        license = licenseService.currentEntitlement()
        refreshHistory()
    }

    func refreshHistory() {
        let filter = activeFilter == "all" ? nil : activeFilter
        let search = searchQuery.isEmpty ? nil : searchQuery
        let db = databaseService
        Task.detached(priority: .userInitiated) {
            do {
                let fetched = try db.getHistory(search: search, contentType: filter)
                await MainActor.run { [weak self] in self?.items = fetched }
            } catch { }
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.contentType {
        case "image":
            if let path = item.imagePath, let image = NSImage(contentsOfFile: path) { pb.writeObjects([image]) }
        default:
            if let text = item.textValue {
                if !plainTextOnly, let html = item.htmlValue {
                    pb.setString(html, forType: .html)
                    pb.setString(text, forType: .string)
                } else { pb.setString(text, forType: .string) }
            }
        }

        // Close the panel after copying
        onDismiss?()
    }

    func dismissPanel() {
        onDismiss?()
    }

    func togglePin(id: Int64) {
        do { _ = try databaseService.togglePin(id: id); refreshHistory() }
        catch { logger.error("Failed to toggle pin: \(error)") }
    }

    func deleteItem(id: Int64) {
        do { try databaseService.deleteItem(id: id); refreshHistory() }
        catch { logger.error("Failed to delete item: \(error)") }
    }

    func updateSearch(_ query: String) { searchQuery = query; refreshHistory() }
    func setFilter(_ filter: String) { activeFilter = filter; refreshHistory() }

    func updateMaxItems(_ value: Int64) {
        maxItems = value
        do {
            try databaseService.setSetting(key: "max_items", value: String(value))
            try databaseService.enforceLimit(value)
            refreshHistory()
        } catch { logger.error("Failed to set max items: \(error)") }
    }

    func togglePlainTextOnly() {
        plainTextOnly.toggle()
        do { try databaseService.setSetting(key: "plain_text_only", value: plainTextOnly ? "true" : "false") }
        catch { logger.error("Failed to set plain text only: \(error)") }
    }

    func refreshLicenseStatus() { license = licenseService.currentEntitlement() }

    func activateLicense(key: String) async throws {
        try await licenseService.activate(key: key)
        license = licenseService.currentEntitlement()
    }

    func deactivateLicense() async throws {
        try await licenseService.deactivate()
        license = licenseService.currentEntitlement()
        refreshHistory()
    }

    func revalidateLicense() async -> LicenseEntitlement {
        let result = await licenseService.validate()
        license = result
        return result
    }

    func checkoutUrl(cycle: String) -> String? { licenseService.checkoutUrl(cycle: cycle) }
    var customerPortalUrl: String { licenseService.customerPortalUrl }
    var isPro: Bool { license.isUnlimited }
    var itemCount: Int { items.count }
}
