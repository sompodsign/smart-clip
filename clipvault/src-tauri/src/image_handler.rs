use std::path::PathBuf;
use image::{ImageBuffer, RgbaImage, imageops::FilterType};
use log::info;

const THUMB_SIZE: u32 = 100;

/// Save a raw RGBA image to disk and generate a thumbnail.
/// Returns (full_image_path, thumbnail_path).
pub fn save_image(
    raw_bytes: &[u8],
    width: usize,
    height: usize,
    images_dir: &PathBuf,
    hash: &str,
) -> Result<(String, String), String> {
    std::fs::create_dir_all(images_dir).map_err(|e| format!("Failed to create images dir: {}", e))?;

    // Create image from raw RGBA bytes
    let img: RgbaImage = ImageBuffer::from_raw(width as u32, height as u32, raw_bytes.to_vec())
        .ok_or_else(|| "Failed to create image from raw bytes".to_string())?;

    // Save full image
    let image_filename = format!("{}.png", &hash[..16]);
    let image_path = images_dir.join(&image_filename);
    img.save(&image_path)
        .map_err(|e| format!("Failed to save image: {}", e))?;

    // Generate and save thumbnail (100x100)
    let thumb = image::imageops::resize(&img, THUMB_SIZE, THUMB_SIZE, FilterType::Lanczos3);
    let thumb_filename = format!("{}_thumb.png", &hash[..16]);
    let thumb_path = images_dir.join(&thumb_filename);
    thumb.save(&thumb_path)
        .map_err(|e| format!("Failed to save thumbnail: {}", e))?;

    info!("Saved image: {} and thumbnail: {}", image_filename, thumb_filename);

    Ok((
        image_path.to_string_lossy().to_string(),
        thumb_path.to_string_lossy().to_string(),
    ))
}
