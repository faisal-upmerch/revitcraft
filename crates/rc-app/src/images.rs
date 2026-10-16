//! Project images (Insert > Import/Link Image) as egui textures, decoded once per asset.

use eframe::egui;
use rc_core::model::{Id, ImageAsset, Project};
use std::cell::RefCell;
use std::collections::HashMap;

thread_local! {
    /// Asset id → (data length, texture). The length catches an asset replaced under its id.
    static TEX: RefCell<HashMap<Id, (usize, egui::TextureHandle)>> = RefCell::new(HashMap::new());
}

/// Uploads textures for the project's images that are not loaded yet.
pub fn sync(ctx: &egui::Context, p: &Project) {
    TEX.with(|t| {
        let mut t = t.borrow_mut();
        for a in &p.images {
            if t.get(&a.id).is_some_and(|(n, _)| *n == a.data.len()) {
                continue;
            }
            if let Some(rgb) = a.rgb() {
                let img = egui::ColorImage::from_rgb([a.width as usize, a.height as usize], &rgb);
                let tex = ctx.load_texture(format!("project-image-{}", a.id), img, egui::TextureOptions::LINEAR);
                t.insert(a.id, (a.data.len(), tex));
            }
        }
    });
}

pub fn texture(asset: Id) -> Option<egui::TextureId> {
    TEX.with(|t| t.borrow().get(&asset).map(|(_, h)| h.id()))
}

/// Reads an image file into an asset: transparent pixels go white, and very large images are
/// scaled to at most 2048 pixels on their long side.
pub fn load_file(path: &std::path::Path, id: Id) -> Result<ImageAsset, String> {
    let img = image::open(path).map_err(|e| format!("The image could not be read: {e}"))?;
    let img = if img.width().max(img.height()) > 2048 { img.thumbnail(2048, 2048) } else { img };
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    let mut rgb = Vec::with_capacity((w * h * 3) as usize);
    for px in rgba.pixels() {
        let a = px[3] as u32;
        for k in 0..3 {
            rgb.push(((px[k] as u32 * a + 255 * (255 - a)) / 255) as u8);
        }
    }
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| "Image".into());
    Ok(ImageAsset::from_rgb(id, &name, w, h, &rgb))
}
