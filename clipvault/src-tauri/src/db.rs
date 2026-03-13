use std::path::PathBuf;
use rusqlite::{Connection, params, Result as SqliteResult};
use serde::{Deserialize, Serialize};
use log::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardItem {
    pub id: i64,
    pub content_type: String,
    pub text_value: Option<String>,
    pub html_value: Option<String>,
    pub image_path: Option<String>,
    pub thumb_path: Option<String>,
    pub hash: String,
    pub pinned: bool,
    pub created_at: i64,
    pub app_source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewClipboardItem {
    pub content_type: String,
    pub text_value: Option<String>,
    pub html_value: Option<String>,
    pub image_path: Option<String>,
    pub thumb_path: Option<String>,
    pub hash: String,
    pub app_source: Option<String>,
}

pub struct Database {
    conn: Connection,
}

impl Database {
    pub fn new(app_data_dir: &PathBuf) -> SqliteResult<Self> {
        std::fs::create_dir_all(app_data_dir).ok();
        let db_path = app_data_dir.join("history.db");
        let conn = Connection::open(&db_path)?;

        // Enable WAL mode for concurrent reads
        conn.execute_batch("PRAGMA journal_mode=WAL;")?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS clipboard_items (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                content_type TEXT    NOT NULL,
                text_value   TEXT,
                image_path   TEXT,
                thumb_path   TEXT,
                hash         TEXT    NOT NULL,
                pinned       INTEGER NOT NULL DEFAULT 0,
                created_at   INTEGER NOT NULL,
                app_source   TEXT
            )",
            [],
        )?;

        // Index on hash for deduplication lookups
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_clipboard_hash ON clipboard_items(hash)",
            [],
        )?;

        // Settings table for user preferences
        conn.execute(
            "CREATE TABLE IF NOT EXISTS settings (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )",
            [],
        )?;

        info!("Database initialized at {:?}", db_path);

        // Migration: add html_value column if it doesn't exist
        let has_html_col: bool = conn
            .prepare("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name='html_value'")
            .and_then(|mut stmt| stmt.query_row([], |row| row.get::<_, i64>(0)))
            .map(|c| c > 0)
            .unwrap_or(false);
        if !has_html_col {
            conn.execute("ALTER TABLE clipboard_items ADD COLUMN html_value TEXT", []).ok();
            info!("Migrated: added html_value column");
        }

        Ok(Self { conn })
    }

    // ── Settings helpers ──

    /// Get a setting value by key.
    pub fn get_setting(&self, key: &str) -> SqliteResult<Option<String>> {
        let mut stmt = self.conn.prepare(
            "SELECT value FROM settings WHERE key = ?1"
        )?;
        let mut rows = stmt.query_map(params![key], |row| row.get(0))?;
        match rows.next() {
            Some(Ok(val)) => Ok(Some(val)),
            _ => Ok(None),
        }
    }

    /// Set a setting value (upsert).
    pub fn set_setting(&self, key: &str, value: &str) -> SqliteResult<()> {
        self.conn.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    /// Get the max items setting (defaults to 50).
    pub fn get_max_items(&self) -> i64 {
        self.get_setting("max_items")
            .ok()
            .flatten()
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(50)
    }

    /// Get the plain_text_only setting (defaults to false).
    pub fn get_plain_text_only(&self) -> bool {
        self.get_setting("plain_text_only")
            .ok()
            .flatten()
            .map(|v| v == "true")
            .unwrap_or(false)
    }

    /// Insert a new clipboard item. Returns the new row ID.
    pub fn insert(&self, item: &NewClipboardItem) -> SqliteResult<i64> {
        let now = chrono::Utc::now().timestamp();
        self.conn.execute(
            "INSERT INTO clipboard_items (content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?8)",
            params![
                item.content_type,
                item.text_value,
                item.html_value,
                item.image_path,
                item.thumb_path,
                item.hash,
                now,
                item.app_source,
            ],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Check if a hash already exists (for deduplication).
    /// If it exists, bump its created_at to now and return true.
    pub fn deduplicate(&self, hash: &str) -> SqliteResult<bool> {
        let now = chrono::Utc::now().timestamp();
        let updated = self.conn.execute(
            "UPDATE clipboard_items SET created_at = ?1 WHERE hash = ?2",
            params![now, hash],
        )?;
        Ok(updated > 0)
    }

    /// Get history items with optional search and type filter.
    pub fn get_history(
        &self,
        search: Option<&str>,
        content_type_filter: Option<&str>,
        limit: i64,
        offset: i64,
    ) -> SqliteResult<Vec<ClipboardItem>> {
        let mut query = String::from(
            "SELECT id, content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source
             FROM clipboard_items WHERE 1=1"
        );
        let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(search_term) = search {
            if !search_term.is_empty() {
                query.push_str(" AND text_value LIKE ?");
                param_values.push(Box::new(format!("%{}%", search_term)));
            }
        }

        if let Some(ct) = content_type_filter {
            if !ct.is_empty() && ct != "all" {
                query.push_str(" AND content_type = ?");
                param_values.push(Box::new(ct.to_string()));
            }
        }

        // Pinned items first, then by created_at descending
        query.push_str(" ORDER BY pinned DESC, created_at DESC LIMIT ? OFFSET ?");
        param_values.push(Box::new(limit));
        param_values.push(Box::new(offset));

        let params_refs: Vec<&dyn rusqlite::types::ToSql> =
            param_values.iter().map(|p| p.as_ref()).collect();

        let mut stmt = self.conn.prepare(&query)?;
        let items = stmt.query_map(params_refs.as_slice(), |row| {
            Ok(ClipboardItem {
                id: row.get(0)?,
                content_type: row.get(1)?,
                text_value: row.get(2)?,
                html_value: row.get(3)?,
                image_path: row.get(4)?,
                thumb_path: row.get(5)?,
                hash: row.get(6)?,
                pinned: row.get::<_, i32>(7)? != 0,
                created_at: row.get(8)?,
                app_source: row.get(9)?,
            })
        })?;

        items.collect()
    }

    /// Toggle pin status for an item.
    pub fn toggle_pin(&self, id: i64) -> SqliteResult<bool> {
        self.conn.execute(
            "UPDATE clipboard_items SET pinned = CASE WHEN pinned = 0 THEN 1 ELSE 0 END WHERE id = ?1",
            params![id],
        )?;

        let pinned: bool = self.conn.query_row(
            "SELECT pinned FROM clipboard_items WHERE id = ?1",
            params![id],
            |row| row.get::<_, i32>(0).map(|v| v != 0),
        )?;

        Ok(pinned)
    }

    /// Delete a single item by ID.
    pub fn delete_item(&self, id: i64) -> SqliteResult<()> {
        self.conn.execute(
            "DELETE FROM clipboard_items WHERE id = ?1",
            params![id],
        )?;
        Ok(())
    }

    /// Get total count of items (for free tier gating).
    pub fn count_items(&self) -> SqliteResult<i64> {
        self.conn.query_row(
            "SELECT COUNT(*) FROM clipboard_items",
            [],
            |row| row.get(0),
        )
    }

    /// Auto-cleanup: delete unpinned items older than `max_age_days` days.
    #[allow(dead_code)]
    pub fn cleanup_old_items(&self, max_age_days: i64) -> SqliteResult<usize> {
        let cutoff = chrono::Utc::now().timestamp() - (max_age_days * 86400);
        let deleted = self.conn.execute(
            "DELETE FROM clipboard_items WHERE pinned = 0 AND created_at < ?1",
            params![cutoff],
        )?;
        Ok(deleted)
    }

    /// Enforce max item count by deleting oldest unpinned entries.
    pub fn enforce_limit(&self, max_items: i64) -> SqliteResult<usize> {
        let count = self.count_items()?;
        if count <= max_items {
            return Ok(0);
        }

        let to_delete = count - max_items;
        let deleted = self.conn.execute(
            "DELETE FROM clipboard_items WHERE id IN (
                SELECT id FROM clipboard_items WHERE pinned = 0
                ORDER BY created_at ASC LIMIT ?1
            )",
            params![to_delete],
        )?;
        Ok(deleted)
    }

    /// Get a single item by ID.
    pub fn get_item(&self, id: i64) -> SqliteResult<Option<ClipboardItem>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, content_type, text_value, html_value, image_path, thumb_path, hash, pinned, created_at, app_source
             FROM clipboard_items WHERE id = ?1"
        )?;

        let mut items = stmt.query_map(params![id], |row| {
            Ok(ClipboardItem {
                id: row.get(0)?,
                content_type: row.get(1)?,
                text_value: row.get(2)?,
                html_value: row.get(3)?,
                image_path: row.get(4)?,
                thumb_path: row.get(5)?,
                hash: row.get(6)?,
                pinned: row.get::<_, i32>(7)? != 0,
                created_at: row.get(8)?,
                app_source: row.get(9)?,
            })
        })?;

        match items.next() {
            Some(Ok(item)) => Ok(Some(item)),
            _ => Ok(None),
        }
    }
}
