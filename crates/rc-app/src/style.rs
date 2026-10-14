//! Visual theme: a flat, light (or dark) BIM-application look with a blue accent and green
//! contextual tabs.

use eframe::egui::{self, Color32, CornerRadius, Margin, Stroke};
use std::sync::atomic::{AtomicBool, Ordering};

static DARK: AtomicBool = AtomicBool::new(false);

pub fn is_dark() -> bool {
    DARK.load(Ordering::Relaxed)
}

fn pick(light: Color32, dark: Color32) -> Color32 {
    if is_dark() { dark } else { light }
}

pub const ACCENT: Color32 = Color32::from_rgb(6, 120, 200);
pub const CONTEXT: Color32 = Color32::from_rgb(70, 150, 60);
pub const SELECT: Color32 = Color32::from_rgb(20, 110, 255);
pub const PRESELECT: Color32 = Color32::from_rgb(40, 150, 255);
pub const PREVIEW: Color32 = Color32::from_rgb(0, 120, 230);
pub const SNAP: Color32 = Color32::from_rgb(230, 110, 0);
pub const TRACK: Color32 = Color32::from_rgb(30, 130, 230);
pub const TEMP_DIM: Color32 = Color32::from_rgb(20, 90, 200);
pub const REVEAL: Color32 = Color32::from_rgb(200, 0, 160);
pub const TEMP_HIDE: Color32 = Color32::from_rgb(0, 170, 170);
pub const ERROR: Color32 = Color32::from_rgb(200, 40, 40);

pub fn accent_light() -> Color32 {
    pick(Color32::from_rgb(214, 234, 252), Color32::from_rgb(30, 64, 96))
}
pub fn chrome() -> Color32 {
    pick(Color32::from_rgb(238, 239, 241), Color32::from_rgb(46, 49, 54))
}
pub fn ribbon() -> Color32 {
    pick(Color32::from_rgb(250, 250, 251), Color32::from_rgb(56, 59, 65))
}
pub fn panel() -> Color32 {
    pick(Color32::from_rgb(246, 247, 248), Color32::from_rgb(52, 55, 60))
}
pub fn field() -> Color32 {
    pick(Color32::WHITE, Color32::from_rgb(40, 42, 46))
}
pub fn border() -> Color32 {
    pick(Color32::from_rgb(206, 209, 214), Color32::from_rgb(78, 82, 90))
}
pub fn text() -> Color32 {
    pick(Color32::from_rgb(32, 34, 38), Color32::from_rgb(225, 227, 230))
}
pub fn text_dim() -> Color32 {
    pick(Color32::from_rgb(110, 114, 120), Color32::from_rgb(150, 154, 160))
}
pub fn hover() -> Color32 {
    pick(Color32::from_rgb(226, 236, 248), Color32::from_rgb(64, 74, 88))
}
pub fn group_header() -> Color32 {
    pick(Color32::from_rgb(228, 231, 236), Color32::from_rgb(64, 68, 74))
}
pub fn tab_idle() -> Color32 {
    pick(Color32::from_rgb(228, 230, 234), Color32::from_rgb(48, 51, 56))
}
pub fn icon_ink() -> Color32 {
    pick(Color32::from_rgb(58, 62, 70), Color32::from_rgb(210, 214, 220))
}

/// Canvas colour of drawing views (user option; white by default like most BIM tools).
pub fn canvas(black_background: bool) -> Color32 {
    if black_background { Color32::from_rgb(33, 40, 48) } else { Color32::WHITE }
}

pub fn apply(ctx: &egui::Context, dark: bool) {
    DARK.store(dark, Ordering::Relaxed);
    ctx.set_visuals(if dark { egui::Visuals::dark() } else { egui::Visuals::light() });
    let mut style = (*ctx.global_style()).clone();
    style.spacing.item_spacing = egui::vec2(6.0, 4.0);
    style.spacing.button_padding = egui::vec2(6.0, 3.0);
    style.spacing.interact_size.y = 20.0;
    style.spacing.combo_height = 320.0;
    style.visuals.panel_fill = panel();
    style.visuals.window_fill = pick(Color32::from_rgb(250, 250, 251), Color32::from_rgb(50, 53, 58));
    style.visuals.extreme_bg_color = field();
    style.visuals.faint_bg_color = pick(Color32::from_rgb(244, 246, 249), Color32::from_rgb(58, 61, 66));
    style.visuals.selection.bg_fill = accent_light();
    style.visuals.selection.stroke = Stroke::new(1.0, ACCENT);
    style.visuals.hyperlink_color = ACCENT;
    style.visuals.window_corner_radius = CornerRadius::same(4);
    style.visuals.window_stroke = Stroke::new(1.0, border());
    style.visuals.override_text_color = Some(text());
    for w in [&mut style.visuals.widgets.inactive, &mut style.visuals.widgets.hovered, &mut style.visuals.widgets.active, &mut style.visuals.widgets.noninteractive, &mut style.visuals.widgets.open] {
        w.corner_radius = CornerRadius::same(2);
    }
    style.visuals.widgets.inactive.weak_bg_fill = pick(Color32::from_rgb(240, 241, 243), Color32::from_rgb(64, 67, 73));
    style.visuals.widgets.inactive.bg_fill = pick(Color32::from_rgb(240, 241, 243), Color32::from_rgb(64, 67, 73));
    style.visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, border());
    style.visuals.widgets.hovered.weak_bg_fill = hover();
    style.visuals.widgets.hovered.bg_fill = hover();
    style.visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, ACCENT);
    style.visuals.widgets.active.weak_bg_fill = accent_light();
    style.visuals.widgets.active.bg_fill = accent_light();
    style.visuals.widgets.noninteractive.bg_stroke = Stroke::new(1.0, border());
    style.text_styles.insert(egui::TextStyle::Body, egui::FontId::proportional(12.5));
    style.text_styles.insert(egui::TextStyle::Button, egui::FontId::proportional(12.5));
    style.text_styles.insert(egui::TextStyle::Small, egui::FontId::proportional(10.5));
    style.text_styles.insert(egui::TextStyle::Heading, egui::FontId::proportional(16.0));
    ctx.set_global_style(style);
}

pub fn ribbon_frame() -> egui::Frame {
    egui::Frame::new().fill(ribbon()).inner_margin(Margin { left: 4, right: 4, top: 0, bottom: 2 }).stroke(Stroke::new(1.0, border()))
}

pub fn bar_frame() -> egui::Frame {
    egui::Frame::new().fill(chrome()).inner_margin(Margin::symmetric(6, 2)).stroke(Stroke::new(1.0, border()))
}

pub fn side_frame() -> egui::Frame {
    egui::Frame::new().fill(panel()).inner_margin(Margin::same(0)).stroke(Stroke::new(1.0, border()))
}

pub fn canvas_frame() -> egui::Frame {
    egui::Frame::new().fill(chrome()).inner_margin(Margin::same(0))
}

/// A palette title bar ("Properties", "Project Browser - Project1").
pub fn palette_title(ui: &mut egui::Ui, text: &str) -> egui::Response {
    let resp = egui::Frame::new()
        .fill(pick(Color32::from_rgb(232, 234, 238), Color32::from_rgb(44, 47, 52)))
        .inner_margin(Margin::symmetric(8, 4))
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.label(egui::RichText::new(text).strong().size(12.5));
        });
    resp.response
}

/// A collapsible group header in the Properties palette.
pub fn group_header_ui(ui: &mut egui::Ui, label: &str, open: bool) -> egui::Response {
    let (rect, resp) = ui.allocate_exact_size(egui::vec2(ui.available_width(), 20.0), egui::Sense::click());
    let p = ui.painter();
    p.rect_filled(rect, 0.0, group_header());
    let c = rect.left_center() + egui::vec2(9.0, 0.0);
    let tri = if open {
        vec![c + egui::vec2(-4.0, -2.0), c + egui::vec2(4.0, -2.0), c + egui::vec2(0.0, 3.0)]
    } else {
        vec![c + egui::vec2(-2.0, -4.0), c + egui::vec2(3.0, 0.0), c + egui::vec2(-2.0, 4.0)]
    };
    p.add(egui::Shape::convex_polygon(tri, text_dim(), Stroke::NONE));
    p.text(rect.left_center() + egui::vec2(18.0, 0.0), egui::Align2::LEFT_CENTER, label, egui::FontId::proportional(12.0), text());
    resp
}

pub fn header(ui: &mut egui::Ui, text: &str) {
    egui::Frame::new().fill(group_header()).inner_margin(Margin::symmetric(6, 3)).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.label(egui::RichText::new(text).strong());
    });
}
