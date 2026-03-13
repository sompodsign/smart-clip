use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use arboard::Clipboard;
use sha2::{Sha256, Digest};
use log::{info, warn, error};
use tauri::{AppHandle, Emitter};

use crate::db::{Database, NewClipboardItem};
use crate::image_handler;
use crate::licensing::LicenseManager;

const POLL_INTERVAL_MS: u64 = 500;
const FREE_TIER_LIMIT: i64 = 5;

#[derive(Clone, serde::Serialize)]
pub struct ClipboardChangeEvent {
    pub item_id: i64,
    pub content_type: String,
}

pub fn start_polling(
    app_handle: AppHandle,
    db: Arc<Mutex<Database>>,
    images_dir: PathBuf,
    license_manager: Arc<Mutex<LicenseManager>>,
) {
    std::thread::spawn(move || {
        let mut clipboard = match Clipboard::new() {
            Ok(c) => c,
            Err(e) => {
                error!("Failed to open clipboard: {}", e);
                return;
            }
        };

        let mut last_text_hash: Option<String> = None;
        let mut last_image_hash: Option<String> = None;

        info!("Clipboard polling started (interval: {}ms)", POLL_INTERVAL_MS);

        loop {
            std::thread::sleep(std::time::Duration::from_millis(POLL_INTERVAL_MS));

            // Check text clipboard
            if let Ok(text) = clipboard.get_text() {
                if !text.trim().is_empty() {
                    let hash = compute_hash(text.as_bytes());
                    if last_text_hash.as_deref() != Some(&hash) {
                        last_text_hash = Some(hash.clone());

                        // Also capture HTML content if available (for rich text)
                        let html_content = clipboard.get().html().ok().filter(|h: &String| !h.trim().is_empty());

                        handle_text_entry(&app_handle, &db, &license_manager, &text, html_content.as_deref(), &hash);
                    }
                }
            }

            // Check image clipboard
            if let Ok(img_data) = clipboard.get_image() {
                let raw_bytes: Vec<u8> = img_data.bytes.to_vec();
                let hash = compute_hash(&raw_bytes);
                if last_image_hash.as_deref() != Some(&hash) {
                    last_image_hash = Some(hash.clone());
                    handle_image_entry(
                        &app_handle, &db, &license_manager,
                        &raw_bytes, img_data.width, img_data.height,
                        &images_dir, &hash,
                    );
                }
            }
        }
    });
}

fn handle_text_entry(
    app_handle: &AppHandle,
    db: &Arc<Mutex<Database>>,
    license_manager: &Arc<Mutex<LicenseManager>>,
    text: &str,
    html_content: Option<&str>,
    hash: &str,
) {
    let db = db.lock().unwrap();

    // Dedup: if already exists, bump timestamp
    if let Ok(true) = db.deduplicate(hash) {
        let _ = app_handle.emit("clipboard-change", ClipboardChangeEvent {
            item_id: 0,
            content_type: "text".to_string(),
        });
        return;
    }

    // Enforce item limits
    if !is_pro(&license_manager) {
        if let Ok(count) = db.count_items() {
            if count >= FREE_TIER_LIMIT {
                // Enforce limit — remove oldest unpinned
                let _ = db.enforce_limit(FREE_TIER_LIMIT - 1);
            }
        }
    } else {
        // Pro users: enforce the user-configured max items limit
        let max_items = db.get_max_items();
        let _ = db.enforce_limit(max_items - 1);
    }

    // Detect content type
    let content_type = detect_text_type(text);

    let new_item = NewClipboardItem {
        content_type: content_type.to_string(),
        text_value: Some(text.to_string()),
        html_value: html_content.map(|h| h.to_string()),
        image_path: None,
        thumb_path: None,
        hash: hash.to_string(),
        app_source: None,
    };

    match db.insert(&new_item) {
        Ok(id) => {
            info!("Stored {} entry (id={}, has_html={})", content_type, id, html_content.is_some());
            let _ = app_handle.emit("clipboard-change", ClipboardChangeEvent {
                item_id: id,
                content_type: content_type.to_string(),
            });
        }
        Err(e) => error!("Failed to insert clipboard item: {}", e),
    }
}

fn handle_image_entry(
    app_handle: &AppHandle,
    db: &Arc<Mutex<Database>>,
    license_manager: &Arc<Mutex<LicenseManager>>,
    raw_bytes: &[u8],
    width: usize,
    height: usize,
    images_dir: &PathBuf,
    hash: &str,
) {
    let db = db.lock().unwrap();

    // Dedup
    if let Ok(true) = db.deduplicate(hash) {
        let _ = app_handle.emit("clipboard-change", ClipboardChangeEvent {
            item_id: 0,
            content_type: "image".to_string(),
        });
        return;
    }

    // Enforce item limits
    if !is_pro(&license_manager) {
        if let Ok(count) = db.count_items() {
            if count >= FREE_TIER_LIMIT {
                let _ = db.enforce_limit(FREE_TIER_LIMIT - 1);
            }
        }
    } else {
        // Pro users: enforce the user-configured max items limit
        let max_items = db.get_max_items();
        let _ = db.enforce_limit(max_items - 1);
    }

    // Save image + thumbnail
    match image_handler::save_image(raw_bytes, width, height, images_dir, hash) {
        Ok((image_path, thumb_path)) => {
            let new_item = NewClipboardItem {
                content_type: "image".to_string(),
                text_value: None,
                html_value: None,
                image_path: Some(image_path),
                thumb_path: Some(thumb_path),
                hash: hash.to_string(),
                app_source: None,
            };

            match db.insert(&new_item) {
                Ok(id) => {
                    info!("Stored image entry (id={})", id);
                    let _ = app_handle.emit("clipboard-change", ClipboardChangeEvent {
                        item_id: id,
                        content_type: "image".to_string(),
                    });
                }
                Err(e) => error!("Failed to insert image item: {}", e),
            }
        }
        Err(e) => warn!("Failed to save clipboard image: {}", e),
    }
}

fn detect_text_type(_text: &str) -> &str {
    "text"
}

fn compute_hash(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

fn is_pro(license_manager: &Arc<Mutex<LicenseManager>>) -> bool {
    if let Ok(lm) = license_manager.lock() {
        lm.current_entitlement().is_unlimited
    } else {
        false
    }
}
