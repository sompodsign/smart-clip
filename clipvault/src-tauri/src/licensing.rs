use serde::{Deserialize, Serialize};
use log::{info, warn, error};
use chrono::Utc;

const KEYCHAIN_SERVICE: &str = "com.smartclip.app.license";
const KEYCHAIN_ACCOUNT: &str = "license_state_v2";
const API_BASE: &str = "https://api.lemonsqueezy.com";

// ── Types ──

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum LicenseTier {
    Free,
    ProActive,
    ProGrace,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicenseEntitlement {
    pub tier: LicenseTier,
    pub message: String,
    pub is_unlimited: bool,
    pub grace_expires_at: Option<i64>,
}

impl LicenseEntitlement {
    pub fn free() -> Self {
        Self {
            tier: LicenseTier::Free,
            message: "Free tier (5 clipboard items)".to_string(),
            is_unlimited: false,
            grace_expires_at: None,
        }
    }

    pub fn pro_active(grace_expires_at: Option<i64>) -> Self {
        Self {
            tier: LicenseTier::ProActive,
            message: "Pro Active".to_string(),
            is_unlimited: true,
            grace_expires_at,
        }
    }

    pub fn pro_grace(grace_expires_at: i64, remaining_days: i64) -> Self {
        Self {
            tier: LicenseTier::ProGrace,
            message: format!("Pro Grace ({} days left)", remaining_days),
            is_unlimited: true,
            grace_expires_at: Some(grace_expires_at),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum LicenseStatus {
    Active,
    Inactive,
    Expired,
    Disabled,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LicenseState {
    pub license_key: String,
    pub instance_id: String,
    pub last_validated_at: Option<i64>,
    pub grace_expires_at: Option<i64>,
    pub last_known_status: LicenseStatus,
}

#[derive(Debug, Clone)]
pub struct LicenseConfig {
    pub store_id: u64,
    pub product_id: u64,
    pub monthly_checkout_url: String,
    pub yearly_checkout_url: String,
    pub customer_portal_url: String,
    pub offline_grace_days: i64,
    pub validation_interval_hours: i64,
}

impl LicenseConfig {
    pub fn from_env() -> Self {
        // Use compile-time values (baked in by build.rs) with runtime fallback
        let env_or = |compile_val: Option<&str>, key: &str, default: &str| -> String {
            compile_val
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
                .or_else(|| std::env::var(key).ok().filter(|s| !s.is_empty()))
                .unwrap_or_else(|| default.to_string())
        };

        Self {
            store_id: env_or(option_env!("LS_STORE_ID"), "LS_STORE_ID", "0")
                .parse().unwrap_or(0),
            product_id: env_or(option_env!("LS_PRODUCT_ID"), "LS_PRODUCT_ID", "0")
                .parse().unwrap_or(0),
            monthly_checkout_url: env_or(
                option_env!("LS_MONTHLY_CHECKOUT_URL"), "LS_MONTHLY_CHECKOUT_URL", ""
            ),
            yearly_checkout_url: env_or(
                option_env!("LS_YEARLY_CHECKOUT_URL"), "LS_YEARLY_CHECKOUT_URL", ""
            ),
            customer_portal_url: env_or(
                option_env!("LS_CUSTOMER_PORTAL_URL"), "LS_CUSTOMER_PORTAL_URL",
                "https://app.lemonsqueezy.com/my-orders"
            ),
            offline_grace_days: env_or(
                option_env!("LS_OFFLINE_GRACE_DAYS"), "LS_OFFLINE_GRACE_DAYS", "7"
            ).parse().unwrap_or(7),
            validation_interval_hours: env_or(
                option_env!("LS_VALIDATION_INTERVAL_HOURS"), "LS_VALIDATION_INTERVAL_HOURS", "12"
            ).parse().unwrap_or(12),
        }
    }
}

// ── LicenseManager ──

pub struct LicenseManager {
    config: LicenseConfig,
    state: Option<LicenseState>,
}

impl LicenseManager {
    pub fn new(config: LicenseConfig) -> Self {
        let state = load_state_from_keychain();
        info!("LicenseManager initialized. Has stored state: {}", state.is_some());
        Self { config, state }
    }

    pub fn current_entitlement(&self) -> LicenseEntitlement {
        let now = Utc::now().timestamp();

        let state = match &self.state {
            Some(s) => s,
            None => return LicenseEntitlement::free(),
        };

        match state.last_known_status {
            LicenseStatus::Active => {
                if let Some(grace) = state.grace_expires_at {
                    if now > grace {
                        return LicenseEntitlement::free();
                    }
                }
                LicenseEntitlement::pro_active(state.grace_expires_at)
            }
            LicenseStatus::Unknown => {
                if let Some(grace) = state.grace_expires_at {
                    if now <= grace {
                        let remaining = ((grace - now) as f64 / 86400.0).ceil() as i64;
                        return LicenseEntitlement::pro_grace(grace, remaining.max(0));
                    }
                }
                LicenseEntitlement::free()
            }
            _ => LicenseEntitlement::free(),
        }
    }

    pub fn activate(&mut self, license_key: &str) -> Result<(), String> {
        let trimmed = license_key.trim();
        if trimmed.is_empty() {
            return Err("License key cannot be empty.".to_string());
        }

        let redacted = format!("***{}", &trimmed[trimmed.len().saturating_sub(4)..]);
        info!("Activating license key {}", redacted);

        let instance_name = get_hostname();

        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .map_err(|e| format!("HTTP client error: {}", e))?;

        let resp = client
            .post(format!("{}/v1/licenses/activate", API_BASE))
            .header("Accept", "application/json")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(format!(
                "license_key={}&instance_name={}",
                url_encode(trimmed),
                url_encode(&instance_name)
            ))
            .send()
            .map_err(|e| format!("Network error: {}", e))?;

        let body = resp.text().map_err(|e| format!("Response read error: {}", e))?;
        let payload: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| format!("Invalid JSON: {}", e))?;

        // Check for API error
        if let Some(err_val) = payload.get("error") {
            if let Some(err_str) = err_val.as_str() {
                if !err_str.is_empty() {
                    return Err(map_api_error(err_str));
                }
            }
        }

        let activated = payload.get("activated")
            .and_then(|v: &serde_json::Value| v.as_bool())
            .unwrap_or(false);
        if !activated {
            return Err("License activation was rejected.".to_string());
        }

        let instance = payload.get("instance")
            .ok_or("Missing instance in response.".to_string())?;
        let instance_id = instance.get("id")
            .and_then(|id: &serde_json::Value| {
                id.as_str().map(|s| s.to_string())
                    .or_else(|| id.as_i64().map(|n| n.to_string()))
            })
            .ok_or("Missing instance ID in response.".to_string())?;

        let now = Utc::now().timestamp();
        let grace = now + (self.config.offline_grace_days * 86400);

        let new_state = LicenseState {
            license_key: trimmed.to_string(),
            instance_id,
            last_validated_at: Some(now),
            grace_expires_at: Some(grace),
            last_known_status: LicenseStatus::Active,
        };

        save_state_to_keychain(&new_state);
        self.state = Some(new_state);

        info!("License activated successfully.");
        Ok(())
    }

    pub fn validate(&mut self) -> Result<LicenseEntitlement, String> {
        let state = match &self.state {
            Some(s) => s.clone(),
            None => return Ok(LicenseEntitlement::free()),
        };

        if state.license_key.is_empty() || state.instance_id.is_empty() {
            self.clear_state("missing_credentials");
            return Ok(LicenseEntitlement::free());
        }

        info!("Validating license...");

        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .map_err(|e| format!("HTTP client error: {}", e))?;

        let result = client
            .post(format!("{}/v1/licenses/validate", API_BASE))
            .header("Accept", "application/json")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(format!(
                "license_key={}&instance_id={}",
                url_encode(&state.license_key),
                url_encode(&state.instance_id)
            ))
            .send();

        match result {
            Err(e) => {
                warn!("Validation network error: {}", e);
                let now = Utc::now().timestamp();
                if let Some(grace) = state.grace_expires_at {
                    if now <= grace {
                        let mut s = state.clone();
                        s.last_known_status = LicenseStatus::Unknown;
                        save_state_to_keychain(&s);
                        self.state = Some(s);
                        let remaining = ((grace - now) as f64 / 86400.0).ceil() as i64;
                        return Ok(LicenseEntitlement::pro_grace(grace, remaining.max(0)));
                    }
                }
                self.clear_state("network_grace_expired");
                Err(format!("Network error: {}", e))
            }
            Ok(resp) => {
                let resp: reqwest::blocking::Response = resp;
                let body = resp.text().map_err(|e| format!("Response read error: {}", e))?;
                let payload: serde_json::Value = serde_json::from_str(&body)
                    .map_err(|e| format!("Invalid JSON: {}", e))?;

                // Check for API error
                if let Some(err_val) = payload.get("error") {
                    if let Some(err_str) = err_val.as_str() {
                        if !err_str.is_empty() {
                            self.clear_state("invalid");
                            return Err(map_api_error(err_str));
                        }
                    }
                }

                let valid = payload.get("valid")
                    .and_then(|v: &serde_json::Value| v.as_bool())
                    .unwrap_or(false);
                if !valid {
                    self.clear_state("invalid");
                    return Err("License validation failed.".to_string());
                }

                let license_key_obj: serde_json::Value = payload.get("license_key")
                    .cloned()
                    .unwrap_or(serde_json::Value::Null);

                let status_str = license_key_obj.get("status")
                    .and_then(|s: &serde_json::Value| s.as_str())
                    .unwrap_or("unknown")
                    .to_lowercase();

                let status = match status_str.as_str() {
                    "active" => LicenseStatus::Active,
                    "inactive" => LicenseStatus::Inactive,
                    "expired" => LicenseStatus::Expired,
                    "disabled" => LicenseStatus::Disabled,
                    _ => LicenseStatus::Unknown,
                };

                if status != LicenseStatus::Active {
                    self.clear_state(&status_str);
                    return Err(format!("License is {}.", status_str));
                }

                // Verify store and product ID
                if self.config.store_id > 0 && self.config.product_id > 0 {
                    let meta = payload.get("meta");
                    let store_id = meta
                        .and_then(|m: &serde_json::Value| m.get("store_id"))
                        .and_then(|v: &serde_json::Value| v.as_u64())
                        .or_else(|| license_key_obj.get("store_id").and_then(|v: &serde_json::Value| v.as_u64()));
                    let product_id = meta
                        .and_then(|m: &serde_json::Value| m.get("product_id"))
                        .and_then(|v: &serde_json::Value| v.as_u64())
                        .or_else(|| license_key_obj.get("product_id").and_then(|v: &serde_json::Value| v.as_u64()));

                    if store_id != Some(self.config.store_id) || product_id != Some(self.config.product_id) {
                        self.clear_state("product_mismatch");
                        return Err("This license key does not belong to ClipVault.".to_string());
                    }
                }

                let now = Utc::now().timestamp();
                let grace = now + (self.config.offline_grace_days * 86400);

                let new_state = LicenseState {
                    license_key: state.license_key,
                    instance_id: state.instance_id,
                    last_validated_at: Some(now),
                    grace_expires_at: Some(grace),
                    last_known_status: LicenseStatus::Active,
                };

                save_state_to_keychain(&new_state);
                self.state = Some(new_state);

                info!("Validation succeeded.");
                Ok(LicenseEntitlement::pro_active(Some(grace)))
            }
        }
    }

    pub fn deactivate(&mut self) -> Result<(), String> {
        let state = match &self.state {
            Some(s) => s.clone(),
            None => return Ok(()),
        };

        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .map_err(|e| format!("HTTP client error: {}", e))?;

        let remote_result = client
            .post(format!("{}/v1/licenses/deactivate", API_BASE))
            .header("Accept", "application/json")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(format!(
                "license_key={}&instance_id={}",
                url_encode(&state.license_key),
                url_encode(&state.instance_id)
            ))
            .send();

        let remote_error: Option<String> = match remote_result {
            Err(e) => Some(format!("Network error: {}", e)),
            Ok(resp) => {
                let resp: reqwest::blocking::Response = resp;
                let body = resp.text().unwrap_or_default();
                match serde_json::from_str::<serde_json::Value>(&body) {
                    Err(e) => Some(format!("Invalid response: {}", e)),
                    Ok(payload) => {
                        if let Some(err_val) = payload.get("error") {
                            if let Some(err_str) = err_val.as_str() {
                                if !err_str.is_empty() {
                                    Some(err_str.to_string())
                                } else {
                                    None
                                }
                            } else {
                                None
                            }
                        } else {
                            let deactivated = payload.get("deactivated")
                                .and_then(|v: &serde_json::Value| v.as_bool())
                                .unwrap_or(false);
                            if !deactivated {
                                Some("Deactivation was not confirmed.".to_string())
                            } else {
                                None
                            }
                        }
                    }
                }
            }
        };

        // Always clear local state
        self.clear_state("user_deactivated");

        if let Some(err) = remote_error {
            warn!("Remote deactivation error (local cleared): {}", err);
            Err(err)
        } else {
            info!("License deactivated.");
            Ok(())
        }
    }

    pub fn checkout_url(&self, cycle: &str) -> Option<String> {
        match cycle {
            "monthly" => {
                let url = &self.config.monthly_checkout_url;
                if url.is_empty() { None } else { Some(url.clone()) }
            }
            "yearly" => {
                let url = &self.config.yearly_checkout_url;
                if url.is_empty() { None } else { Some(url.clone()) }
            }
            _ => None,
        }
    }

    pub fn validation_interval_seconds(&self) -> u64 {
        (self.config.validation_interval_hours * 3600) as u64
    }

    fn clear_state(&mut self, reason: &str) {
        delete_state_from_keychain();
        self.state = None;
        info!("License state cleared. reason={}", reason);
    }

    pub fn customer_portal_url(&self) -> String {
        self.config.customer_portal_url.clone()
    }
}

// ── Keychain helpers ──

fn load_state_from_keychain() -> Option<LicenseState> {
    let entry = keyring::Entry::new(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT).ok()?;
    let raw = entry.get_password().ok()?;
    serde_json::from_str(&raw).ok()
}

fn save_state_to_keychain(state: &LicenseState) {
    if let Ok(entry) = keyring::Entry::new(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT) {
        if let Ok(json) = serde_json::to_string(state) {
            if let Err(e) = entry.set_password(&json) {
                error!("Failed to save license state to keychain: {}", e);
            }
        }
    }
}

fn delete_state_from_keychain() {
    if let Ok(entry) = keyring::Entry::new(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT) {
        let _ = entry.delete_credential();
    }
}

// ── Helpers ──

fn get_hostname() -> String {
    std::process::Command::new("hostname")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "ClipVault Mac".to_string())
}

fn url_encode(s: &str) -> String {
    s.chars().map(|c| {
        if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' || c == '~' {
            c.to_string()
        } else {
            format!("%{:02X}", c as u8)
        }
    }).collect()
}

fn map_api_error(msg: &str) -> String {
    let lower = msg.to_lowercase();
    if lower.contains("invalid") || lower.contains("not found") {
        "Invalid license key. Please check and try again.".to_string()
    } else if lower.contains("expired") {
        "This subscription has expired.".to_string()
    } else if lower.contains("disabled") {
        "This license key is disabled.".to_string()
    } else if lower.contains("inactive") {
        "This license key is inactive.".to_string()
    } else {
        msg.to_string()
    }
}
