use std::sync::{Arc, Mutex};
use tauri::State;
use arboard::Clipboard;

use crate::db::{Database, ClipboardItem};
use crate::licensing::{LicenseManager, LicenseEntitlement};

pub type DbState = Arc<Mutex<Database>>;
pub type LicenseState = Arc<Mutex<LicenseManager>>;

// ── Clipboard history commands ──

#[tauri::command]
pub fn get_history(
    db: State<DbState>,
    search: Option<String>,
    content_type: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<ClipboardItem>, String> {
    let db = db.lock().map_err(|e| e.to_string())?;
    db.get_history(
        search.as_deref(),
        content_type.as_deref(),
        limit.unwrap_or(50),
        offset.unwrap_or(0),
    )
    .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn pin_item(db: State<DbState>, id: i64) -> Result<bool, String> {
    let db = db.lock().map_err(|e| e.to_string())?;
    db.toggle_pin(id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_item(db: State<DbState>, id: i64) -> Result<(), String> {
    let db = db.lock().map_err(|e| e.to_string())?;
    db.delete_item(id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn restore_to_clipboard(db: State<DbState>, id: i64) -> Result<(), String> {
    let db_guard = db.lock().map_err(|e| e.to_string())?;
    let item = db_guard.get_item(id)
        .map_err(|e| e.to_string())?
        .ok_or("Item not found")?;

    // Drop the DB lock before clipboard operations
    drop(db_guard);

    let mut clipboard = Clipboard::new().map_err(|e| format!("Clipboard error: {}", e))?;

    match item.content_type.as_str() {
        "image" => {
            if let Some(path) = &item.image_path {
                let img = image::open(path).map_err(|e| format!("Failed to open image: {}", e))?;
                let rgba = img.to_rgba8();
                let (w, h) = rgba.dimensions();
                let img_data = arboard::ImageData {
                    width: w as usize,
                    height: h as usize,
                    bytes: std::borrow::Cow::Owned(rgba.into_raw()),
                };
                clipboard.set_image(img_data).map_err(|e| format!("Clipboard error: {}", e))?;
            } else {
                return Err("Image path not found.".to_string());
            }
        }
        _ => {
            if let Some(text) = &item.text_value {
                clipboard.set_text(text).map_err(|e| format!("Clipboard error: {}", e))?;
            } else {
                return Err("No text value to restore.".to_string());
            }
        }
    }

    Ok(())
}

// ── Licensing commands ──

#[tauri::command]
pub fn get_license_status(license: State<LicenseState>) -> Result<LicenseEntitlement, String> {
    let lm = license.lock().map_err(|e| e.to_string())?;
    Ok(lm.current_entitlement())
}

#[tauri::command]
pub fn activate_license(license: State<LicenseState>, key: String) -> Result<(), String> {
    let mut lm = license.lock().map_err(|e| e.to_string())?;
    lm.activate(&key)?;
    // Validate right after activation
    lm.validate().map(|_| ())
}

#[tauri::command]
pub fn deactivate_license(license: State<LicenseState>) -> Result<(), String> {
    let mut lm = license.lock().map_err(|e| e.to_string())?;
    lm.deactivate()
}

#[tauri::command]
pub fn revalidate_license(license: State<LicenseState>) -> Result<LicenseEntitlement, String> {
    let mut lm = license.lock().map_err(|e| e.to_string())?;
    lm.validate()
}

#[tauri::command]
pub fn get_checkout_url(license: State<LicenseState>, cycle: String) -> Result<String, String> {
    let lm = license.lock().map_err(|e| e.to_string())?;
    lm.checkout_url(&cycle).ok_or("Checkout URL not configured.".to_string())
}

#[tauri::command]
pub fn get_customer_portal_url(license: State<LicenseState>) -> Result<String, String> {
    let lm = license.lock().map_err(|e| e.to_string())?;
    Ok(lm.customer_portal_url())
}
