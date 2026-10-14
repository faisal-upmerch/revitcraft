//! The Home screen: a full-window page with Models/Families actions on the left and the
//! recent projects as thumbnail cards, shown at start-up and from the Home button.

use crate::app::App;
use crate::icons::{self, Icon};
use crate::style;
use eframe::egui::{self, Color32, Rect, Sense, Stroke, pos2, vec2};
use std::path::{Path, PathBuf};

/// Where the thumbnail of a project file is cached.
pub fn thumb_path(project: &Path) -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let mut h: u64 = 0xcbf29ce484222325;
    for b in project.to_string_lossy().to_lowercase().bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    base.join("RevitCraft").join("thumbs").join(format!("{h:016x}.thumb"))
}

/// Renders the active view small and stores it as the project's thumbnail (like the
/// preview a model keeps of the view that was active when it was saved).
pub fn write_thumb(app: &mut App, project: &Path) {
    let Some(view) = app.active_view().cloned() else { return };
    let img = if matches!(view.kind, rc_core::model::ViewKind::ThreeD { .. }) {
        crate::view3d::render_image(app, view.id, 300, 210)
    } else {
        crate::dialogs::raster_2d(app, &view, 300)
    };
    let Some(img) = img else { return };
    let path = thumb_path(project);
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let mut bytes = Vec::with_capacity(8 + img.rgb.len());
    bytes.extend_from_slice(&img.width.to_le_bytes());
    bytes.extend_from_slice(&img.height.to_le_bytes());
    bytes.extend_from_slice(&img.rgb);
    let _ = std::fs::write(path, bytes);
    app.thumbs.remove(&project.display().to_string());
}

fn load_thumb(project: &Path) -> Option<egui::ColorImage> {
    let b = std::fs::read(thumb_path(project)).ok()?;
    if b.len() < 8 {
        return None;
    }
    let w = u32::from_le_bytes(b[0..4].try_into().ok()?) as usize;
    let h = u32::from_le_bytes(b[4..8].try_into().ok()?) as usize;
    let rgb = &b[8..];
    if rgb.len() < w * h * 3 {
        return None;
    }
    Some(egui::ColorImage::from_rgb([w, h], &rgb[..w * h * 3]))
}

/// "9/26/26, 6:11 AM" style date of a file's last change.
fn modified_label(path: &Path) -> String {
    let Ok(t) = std::fs::metadata(path).and_then(|m| m.modified()) else { return String::new() };
    let secs = t.duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let days = (secs / 86400) as i64;
    let rem = secs % 86400;
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    let (hh, mm) = (rem / 3600, rem % 3600 / 60);
    let (h12, ampm) = match hh {
        0 => (12, "AM"),
        1..=11 => (hh, "AM"),
        12 => (12, "PM"),
        _ => (hh - 12, "PM"),
    };
    format!("{m}/{d}/{:02}, {h12}:{mm:02} {ampm}", y % 100)
}

fn side_button(ui: &mut egui::Ui, label: &str) -> bool {
    let (r, resp) = ui.allocate_exact_size(vec2(150.0, 26.0), Sense::click());
    let p = ui.painter();
    p.rect_filled(r, 3.0, if resp.hovered() { style::hover() } else { Color32::WHITE });
    p.rect_stroke(r, 3.0, Stroke::new(1.0, Color32::from_gray(170)), egui::StrokeKind::Inside);
    p.text(r.center(), egui::Align2::CENTER_CENTER, label, style::font(12.5), style::text());
    resp.clicked()
}

fn side_label(ui: &mut egui::Ui, text: &str) {
    ui.add_space(14.0);
    ui.label(egui::RichText::new(text).size(11.5).color(style::text_dim()));
    ui.add_space(4.0);
}

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    let ctx = ui.ctx().clone();
    let mut close = false;
    egui::Panel::left("home-side").exact_size(200.0).frame(egui::Frame::new().fill(Color32::from_rgb(240, 240, 240)).inner_margin(egui::Margin { left: 24, right: 12, top: 20, bottom: 16 })).show(ui, |ui| {
        ui.label(egui::RichText::new("RevitCraft").font(style::bold(22.0)));
        side_label(ui, "Models");
        if side_button(ui, "Open ...") {
            close = true;
            if app.confirm_discard(crate::dialogs::Pending::Open) {
                app.open_dialog();
            }
        }
        ui.add_space(6.0);
        if side_button(ui, "New ...") {
            close = true;
            app.dialogs.new_project = true;
        }
        side_label(ui, "Families");
        if side_button(ui, "Open ...") {
            close = true;
            crate::actions::exec(app, crate::commands::Cmd::LoadFamily);
        }
        ui.add_space(6.0);
        if side_button(ui, "New ...") {
            close = true;
            crate::family_editor::new_custom(app, "Custom Family");
        }
        ui.add_space(24.0);
        let (r, _) = ui.allocate_exact_size(vec2(ui.available_width() + 12.0, 30.0), Sense::hover());
        ui.painter().rect_filled(r.translate(vec2(-24.0, 0.0)).expand2(vec2(12.0, 0.0)), 0.0, Color32::WHITE);
        ui.painter().text(r.left_center() + vec2(0.0, 0.0), egui::Align2::LEFT_CENTER, "Recent", style::font(13.0), style::text());
        ui.with_layout(egui::Layout::bottom_up(egui::Align::Min), |ui| {
            ui.add_space(4.0);
            for (label, which) in [("Keyboard shortcuts", 2), ("Sample project", 1)] {
                if ui.add(egui::Button::new(egui::RichText::new(label).color(style::ACCENT)).frame(false)).clicked() {
                    close = true;
                    match which {
                        1 => {
                            if app.confirm_discard(crate::dialogs::Pending::Sample) {
                                app.open_sample();
                            }
                        }
                        _ => crate::actions::exec(app, crate::commands::Cmd::KeyboardShortcuts),
                    }
                }
            }
        });
    });
    egui::CentralPanel::default().frame(egui::Frame::new().fill(Color32::WHITE).inner_margin(egui::Margin { left: 28, right: 28, top: 22, bottom: 16 })).show(ui, |ui| {
        ui.label(egui::RichText::new("Recent").size(20.0));
        ui.add_space(10.0);
        let search_id = egui::Id::new("home-search");
        let mut search: String = ui.memory(|m| m.data.get_temp(search_id)).unwrap_or_default();
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new("Sort by").color(style::text_dim()));
            ui.label("Date modified");
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                egui::Frame::new().stroke(Stroke::new(1.0, Color32::from_gray(170))).inner_margin(egui::Margin::symmetric(4, 2)).show(ui, |ui| {
                    ui.add(egui::TextEdit::singleline(&mut search).hint_text("Search for recent files").desired_width(260.0).frame(egui::Frame::NONE));
                });
            });
        });
        ui.memory_mut(|m| m.data.insert_temp(search_id, search.clone()));
        ui.add_space(12.0);
        let mut recent: Vec<String> = app.settings.recent.iter().filter(|r| search.is_empty() || r.to_lowercase().contains(&search.to_lowercase())).cloned().collect();
        recent.sort_by_key(|r| std::cmp::Reverse(std::fs::metadata(r).and_then(|m| m.modified()).ok()));
        if recent.is_empty() {
            ui.label(egui::RichText::new("Projects you open or save appear here.").color(style::text_dim()));
        }
        egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
            let (cw, ch, gap) = (160.0, 206.0, 14.0);
            let cols = ((ui.available_width() + gap) / (cw + gap)).floor().max(1.0) as usize;
            for row in recent.chunks(cols) {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = gap;
                    for r in row {
                        let path = PathBuf::from(r);
                        let (rect, resp) = ui.allocate_exact_size(vec2(cw, ch), Sense::click());
                        let p = ui.painter();
                        p.rect_filled(rect, 2.0, if resp.hovered() { Color32::from_rgb(229, 241, 251) } else { Color32::from_rgb(236, 236, 236) });
                        let thumb = Rect::from_min_size(rect.min + vec2(8.0, 8.0), vec2(cw - 16.0, 110.0));
                        p.rect_filled(thumb, 0.0, Color32::WHITE);
                        let key = r.clone();
                        if !app.thumbs.contains_key(&key) {
                            let tex = load_thumb(&path).map(|img| ctx.load_texture(format!("thumb-{key}"), img, egui::TextureOptions::LINEAR));
                            app.thumbs.insert(key.clone(), tex);
                        }
                        match app.thumbs.get(&key).and_then(|t| t.as_ref()) {
                            Some(tex) => {
                                let s = tex.size_vec2();
                                let k = (thumb.width() / s.x).min(thumb.height() / s.y);
                                let img_r = Rect::from_center_size(thumb.center(), s * k);
                                ui.painter().image(tex.id(), img_r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                            }
                            None => icons::paint(ui.painter(), Rect::from_center_size(thumb.center(), vec2(40.0, 40.0)), Icon::FloorPlan, true),
                        }
                        let p = ui.painter();
                        icons::paint(p, Rect::from_min_size(pos2(rect.left() + 8.0, thumb.bottom() + 8.0), vec2(14.0, 14.0)), Icon::Save, true);
                        let name = path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
                        let galley = p.layout(name, style::font(12.5), style::text(), cw - 20.0);
                        p.galley(pos2(rect.left() + 10.0, thumb.bottom() + 26.0), galley, style::text());
                        p.text(pos2(rect.left() + 10.0, rect.bottom() - 12.0), egui::Align2::LEFT_CENTER, modified_label(&path), style::font(11.0), style::text_dim());
                        let resp = resp.on_hover_text(format!("Saved path\n{r}"));
                        if resp.clicked() {
                            close = true;
                            if app.confirm_discard(crate::dialogs::Pending::OpenPath(r.clone())) {
                                app.open_path(&path);
                            }
                        }
                    }
                });
                ui.add_space(gap);
            }
        });
    });
    if close {
        app.dialogs.home = false;
    }
    if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
        app.dialogs.home = false;
    }
}
