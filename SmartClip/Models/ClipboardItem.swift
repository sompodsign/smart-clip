import Foundation
import GRDB

/// Represents a single clipboard history item stored in the database.
/// Schema matches the existing Tauri/Rust `clipboard_items` table for backward compatibility.
struct ClipboardItem: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"

    var id: Int64?
    var contentType: String
    var textValue: String?
    var htmlValue: String?
    var imagePath: String?
    var thumbPath: String?
    var hash: String
    var pinned: Bool
    var createdAt: Int64
    var appSource: String?

    enum Columns: String, ColumnExpression {
        case id, contentType = "content_type", textValue = "text_value"
        case htmlValue = "html_value", imagePath = "image_path", thumbPath = "thumb_path"
        case hash, pinned, createdAt = "created_at", appSource = "app_source"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case textValue = "text_value"
        case htmlValue = "html_value"
        case imagePath = "image_path"
        case thumbPath = "thumb_path"
        case hash, pinned
        case createdAt = "created_at"
        case appSource = "app_source"
    }

    var preview: String {
        if contentType == "image" { return "📷 Image" }
        return textValue?.prefix(200).description ?? ""
    }

    var timeAgo: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NewClipboardItem {
    var contentType: String
    var textValue: String?
    var htmlValue: String?
    var imagePath: String?
    var thumbPath: String?
    var hash: String
    var appSource: String?
}
