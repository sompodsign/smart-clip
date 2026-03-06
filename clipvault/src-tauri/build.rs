use std::path::Path;

fn main() {
    // Load .env at compile time and set values as cargo env vars
    // so they can be read with option_env!() in the source code.
    let env_path = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join(".env");

    if env_path.exists() {
        for item in dotenvy::from_path_iter(&env_path).unwrap() {
            if let Ok((key, value)) = item {
                if key.starts_with("LS_") {
                    println!("cargo:rustc-env={}={}", key, value);
                }
            }
        }
        println!("cargo:rerun-if-changed={}", env_path.display());
    }

    tauri_build::build();
}
