#![allow(unexpected_cfgs)]

mod db;
mod clipboard;
mod image_handler;
mod licensing;
mod commands;

#[cfg(target_os = "macos")]
#[macro_use]
extern crate objc;

use std::sync::{Arc, Mutex};
use tauri::{
    Manager,
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    menu::{MenuBuilder, MenuItemBuilder},
};
use log::info;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Load .env file for licensing config
    dotenvy::dotenv().ok();
    env_logger::init();

    // Shared timestamp to debounce tray toggle vs focus-loss race
    let last_toggle: Arc<Mutex<std::time::Instant>> = Arc::new(Mutex::new(
        std::time::Instant::now() - std::time::Duration::from_secs(1)
    ));

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
            info!("SmartClip starting...");

            // -- Data directories --
            let app_data_dir = app.path().app_data_dir()
                .expect("Failed to resolve app data directory");
            let images_dir = app_data_dir.join("images");

            // -- Initialize database --
            let database = db::Database::new(&app_data_dir)
                .expect("Failed to initialize database");
            let db = Arc::new(Mutex::new(database));
            app.manage(db.clone() as commands::DbState);

            // -- Initialize licensing --
            let config = licensing::LicenseConfig::from_env();
            let mut license_manager = licensing::LicenseManager::new(config);

            // Validate on startup
            match license_manager.validate() {
                Ok(ent) => info!("Startup license check: {}", ent.message),
                Err(e) => info!("Startup license check failed: {}", e),
            }

            let validation_interval = license_manager.validation_interval_seconds();
            let lm = Arc::new(Mutex::new(license_manager));
            app.manage(lm.clone() as commands::LicenseState);

            // -- Start periodic license validation --
            let lm_timer = lm.clone();
            std::thread::spawn(move || {
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(validation_interval));
                    if let Ok(mut lm) = lm_timer.lock() {
                        match lm.validate() {
                            Ok(ent) => info!("Periodic validation: {}", ent.message),
                            Err(e) => info!("Periodic validation failed: {}", e),
                        }
                    }
                }
            });

            // -- System tray (menu bar icon) --
            let quit = MenuItemBuilder::with_id("quit", "Quit SmartClip").build(app)?;
            let menu = MenuBuilder::new(app)
                .item(&quit)
                .build()?;

            let tray_icon_bytes = include_bytes!("../icons/tray-icon.png");
            let tray_icon = tauri::image::Image::from_bytes(tray_icon_bytes)
                .unwrap_or_else(|_| app.default_window_icon().unwrap().clone());

            let last_toggle_tray = last_toggle.clone();
            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .show_menu_on_left_click(false)  // We handle left-click ourselves
                .tooltip("SmartClip")
                .icon_as_template(true)
                .icon(tray_icon)
                .on_menu_event(|app, event| {
                    if event.id().as_ref() == "quit" {
                        app.exit(0);
                    }
                })
                .on_tray_icon_event(move |tray, event| {
                    // Toggle panel on left-click of the tray icon
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        rect,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            // Record toggle timestamp to prevent focus-loss from re-hiding
                            if let Ok(mut ts) = last_toggle_tray.lock() {
                                *ts = std::time::Instant::now();
                            }

                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                // Get scale factor for coordinate conversion
                                let scale = window.scale_factor().unwrap_or(2.0);
                                let panel_width = 340.0_f64;

                                // Convert tray icon rect to logical coordinates
                                let (tray_x, tray_y) = match rect.position {
                                    tauri::Position::Physical(p) => (p.x as f64 / scale, p.y as f64 / scale),
                                    tauri::Position::Logical(l) => (l.x, l.y),
                                };
                                let (tray_w, tray_h) = match rect.size {
                                    tauri::Size::Physical(p) => (p.width as f64 / scale, p.height as f64 / scale),
                                    tauri::Size::Logical(l) => (l.width, l.height),
                                };

                                let tray_center_x = tray_x + (tray_w / 2.0);
                                let panel_x = tray_center_x - (panel_width / 2.0);
                                let panel_y = tray_y + tray_h + 4.0;

                                // Use LogicalPosition for correct multi-display placement
                                let _ = window.set_position(tauri::Position::Logical(
                                    tauri::LogicalPosition {
                                        x: panel_x,
                                        y: panel_y,
                                    },
                                ));

                                // Show AFTER position is set
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // -- Hide window when it loses focus (click outside) --
            // With debounce to prevent hiding immediately after tray toggle
            // (mouse is on tray icon, not our panel, so macOS fires Focused(false))
            let window = app.get_webview_window("main").unwrap();
            let window_clone = window.clone();
            let last_toggle_focus = last_toggle.clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::Focused(false) = event {
                    // Don't hide if we just toggled via tray (within 500ms)
                    if let Ok(ts) = last_toggle_focus.lock() {
                        if ts.elapsed() < std::time::Duration::from_millis(500) {
                            return;
                        }
                    }
                    let _ = window_clone.hide();
                }
            });

            // -- macOS: hide from Dock + transparent window for rounded corners --
            #[cfg(target_os = "macos")]
            #[allow(deprecated)]
            {
                use cocoa::appkit::{NSWindow, NSColor};
                use cocoa::base::{id, NO};

                app.set_activation_policy(tauri::ActivationPolicy::Accessory);

                // Make the native NSWindow transparent
                let ns_window = window.ns_window().unwrap() as id;
                unsafe {
                    ns_window.setOpaque_(NO);
                    let clear = NSColor::clearColor(cocoa::base::nil);
                    ns_window.setBackgroundColor_(clear);
                    // Also remove the window shadow for a cleaner look
                    ns_window.setHasShadow_(NO);
                }

                // Make the WKWebView background transparent too
                let _ = window.with_webview(|wv| {
                    unsafe {
                        let wv_obj: id = wv.inner() as *mut _ as id;
                        let key = std::ffi::CStr::from_bytes_with_nul(b"drawsBackground\0").unwrap();
                        let ns_key: id = objc::msg_send![objc::class!(NSString), stringWithUTF8String: key.as_ptr()];
                        let no_val: id = objc::msg_send![objc::class!(NSNumber), numberWithBool: false];
                        let _: () = objc::msg_send![wv_obj, setValue: no_val forKey: ns_key];
                    }
                });
            }

            // -- Start clipboard polling --
            clipboard::start_polling(
                app.handle().clone(),
                db,
                images_dir,
                lm,
            );

            info!("SmartClip ready (menu bar mode).");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_history,
            commands::pin_item,
            commands::delete_item,
            commands::restore_to_clipboard,
            commands::get_license_status,
            commands::activate_license,
            commands::deactivate_license,
            commands::revalidate_license,
            commands::get_checkout_url,
            commands::get_customer_portal_url,
        ])
        .run(tauri::generate_context!())
        .expect("error while running ClipVault");
}
