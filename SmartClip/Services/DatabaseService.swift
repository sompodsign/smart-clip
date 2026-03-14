import Foundation
import GRDB
import os

/// Manages the SQLite database using GRDB.
/// Schema is backward-compatible with the existing Tauri/Rust `history.db`.
final class DatabaseService {
    private var dbPool: DatabasePool?
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Database")

    private var dbPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(Constants.bundleIdentifier)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("history.db")
    }

    var imagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imagesDir = appSupport.appendingPathComponent(Constants.bundleIdentifier).appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        return imagesDir
    }

    init() {
        do {
            dbPool = try DatabasePool(path: dbPath.path)
            try migrate()
            logger.info("Database initialized at \(self.dbPath.path)")
        } catch {
            logger.error("Failed to initialize database: \(error)")
        }
    }

    private func migrate() throws {
        guard let db = dbPool else { return }
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_items (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    content_type TEXT    NOT NULL,
                    text_value   TEXT,
                    html_value   TEXT,
                    image_path   TEXT,
                    thumb_path   TEXT,
                    hash         TEXT    NOT NULL,
                    pinned       INTEGER NOT NULL DEFAULT 0,
                    created_at   INTEGER NOT NULL,
                    app_source   TEXT
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_hash ON clipboard_items(hash)")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS settings (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
            """)
        }
    }

    func insert(_ item: NewClipboardItem) throws -> Int64 {
        guard let db = dbPool else { throw DatabaseError(message: "Database not initialized") }
        let now = Int64(Date().timeIntervalSince1970)
        return try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clipboard_items (content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source)
                    VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
                """,
                arguments: [item.contentType, item.textValue, item.htmlValue, item.imagePath, item.thumbPath, item.hash, now, item.appSource]
            )
            return db.lastInsertedRowID
        }
    }

    func deduplicate(hash: String) throws -> Bool {
        guard let db = dbPool else { return false }
        let now = Int64(Date().timeIntervalSince1970)
        return try db.write { db in
            let exists = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items WHERE hash = ?", arguments: [hash]) ?? 0
            guard exists > 0 else { return false }
            try db.execute(sql: "UPDATE clipboard_items SET created_at = ? WHERE hash = ?", arguments: [now, hash])
            return true
        }
    }

    func getHistory(search: String? = nil, contentType: String? = nil, limit: Int64 = 50, offset: Int64 = 0) throws -> [ClipboardItem] {
        guard let db = dbPool else { return [] }
        return try db.read { db in
            var sql = "SELECT id, content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source FROM clipboard_items WHERE 1=1"
            var arguments: [DatabaseValueConvertible?] = []

            if let search = search, !search.isEmpty {
                sql += " AND text_value LIKE ?"
                arguments.append("%\(search)%")
            }
            if let ct = contentType, !ct.isEmpty, ct != "all" {
                sql += " AND content_type = ?"
                arguments.append(ct)
            }
            sql += " ORDER BY pinned DESC, created_at DESC LIMIT ? OFFSET ?"
            arguments.append(limit)
            arguments.append(offset)

            let statement = try db.makeStatement(sql: sql)
            let stmtArgs = StatementArguments(arguments.map { $0 as DatabaseValueConvertible? })
            return try ClipboardItem.fetchAll(statement, arguments: stmtArgs)
        }
    }

    func getItem(id: Int64) throws -> ClipboardItem? {
        guard let db = dbPool else { return nil }
        return try db.read { db in
            try ClipboardItem.fetchOne(db, sql: "SELECT id, content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source FROM clipboard_items WHERE id = ?", arguments: [id])
        }
    }

    func togglePin(id: Int64) throws -> Bool {
        guard let db = dbPool else { throw DatabaseError(message: "Database not initialized") }
        return try db.write { db in
            try db.execute(sql: "UPDATE clipboard_items SET pinned = CASE WHEN pinned = 0 THEN 1 ELSE 0 END WHERE id = ?", arguments: [id])
            let row = try Row.fetchOne(db, sql: "SELECT pinned FROM clipboard_items WHERE id = ?", arguments: [id])
            return row?["pinned"] as? Int64 != 0
        }
    }

    func deleteItem(id: Int64) throws {
        guard let db = dbPool else { return }
        try db.write { db in
            try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id])
        }
    }

    func countItems() throws -> Int64 {
        guard let db = dbPool else { return 0 }
        return try db.read { db in
            try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items") ?? 0
        }
    }

    func enforceLimit(_ maxItems: Int64) throws {
        guard let db = dbPool else { return }
        try db.write { db in
            let count = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items") ?? 0
            guard count > maxItems else { return }
            let toDelete = count - maxItems
            try db.execute(sql: """
                DELETE FROM clipboard_items WHERE id IN (
                    SELECT id FROM clipboard_items WHERE pinned = 0
                    ORDER BY created_at ASC LIMIT ?
                )
            """, arguments: [toDelete])
        }
    }

    func getSetting(key: String) -> String? {
        guard let db = dbPool else { return nil }
        return try? db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    func setSetting(key: String, value: String) throws {
        guard let db = dbPool else { return }
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, arguments: [key, value])
        }
    }

    var maxItems: Int64 {
        Int64(getSetting(key: "max_items") ?? "") ?? Constants.defaultMaxItems
    }

    var plainTextOnly: Bool {
        getSetting(key: "plain_text_only") == "true"
    }
}

struct DatabaseError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
