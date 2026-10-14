//! Visual theme: the light grey Revit-style chrome (grey tab row, near-white ribbon, green
//! contextual and teal sketch tabs), the platform UI font and the canvas feedback colours.

use eframe::egui::{self, Color32, CornerRadius, FontFamily, FontId, Margin, Stroke};
use std::sync::atomic::{AtomicBool, Ordering};

static DARK: AtomicBool = AtomicBool::new(false);
static FONTS_LOADED: AtomicBool = AtomicBool::new(false);

pub fn is_dark() -> bool {
    DARK.load(Ordering::Relaxed)
}

fn pick(light: Color32, dark: Color32) -> Color32 {
    if is_dark() { dark } else { light }
}

pub const ACCENT: Color32 = Color32::from_rgb(36, 124, 192);
/// Contextual "Modify | ..." tab.
pub const CONTEXT: Color32 = Color32::from_rgb(138, 186, 62);
/// Sketch-mode contextual tab ("Modify | Create Floor Boundary").
pub const SKETCH_TAB: Color32 = Color32::from_rgb(117, 209, 196);
pub const SELECT: Color32 = Color32::from_rgb(24, 84, 216);
pub const PRESELECT: Color32 = Color32::from_rgb(20, 50, 150);
/// Rubber-band previews of the element being drawn.
pub const PREVIEW: Color32 = Color32::from_rgb(70, 70, 70);
/// Snap glyphs (endpoint squares, intersection crosses, axis arrows).
pub const SNAP: Color32 = Color32::from_rgb(230, 0, 210);
/// Alignment / extension lines (light blue dash-dot).
pub const TRACK: Color32 = Color32::from_rgb(120, 170, 230);
/// Temporary and listening dimension text.
pub const TEMP_DIM: Color32 = Color32::from_rgb(10, 60, 220);
/// Temporary dimension lines.
pub const TEMP_DIM_LINE: Color32 = Color32::from_rgb(130, 170, 235);
/// Sketch lines.
pub const SKETCH: Color32 = Color32::from_rgb(220, 0, 160);
pub const REVEAL: Color32 = Color32::from_rgb(200, 0, 160);
pub const TEMP_HIDE: Color32 = Color32::from_rgb(0, 170, 170);
pub const ERROR: Color32 = Color32::from_rgb(200, 40, 40);

pub fn accent_light() -> Color32 {
    pick(Color32::from_rgb(204, 228, 247), Color32::from_rgb(30, 64, 96))
}
/// Title / tab row behind the ribbon.
pub fn chrome() -> Color32 {
    pick(Color32::from_rgb(217, 217, 217), Color32::from_rgb(46, 49, 54))
}
/// Ribbon body, options bar and status bar.
pub fn ribbon() -> Color32 {
    pick(Color32::from_rgb(245, 246, 246), Color32::from_rgb(56, 59, 65))
}
/// Ribbon body tint while a contextual tab is shown.
pub fn ribbon_tint(sketch: bool) -> Color32 {
    if sketch {
        pick(Color32::from_rgb(220, 239, 235), Color32::from_rgb(44, 66, 64))
    } else {
        pick(Color32::from_rgb(233, 239, 225), Color32::from_rgb(52, 64, 46))
    }
}
pub fn panel() -> Color32 {
    pick(Color32::from_rgb(245, 246, 246), Color32::from_rgb(52, 55, 60))
}
pub fn field() -> Color32 {
    pick(Color32::WHITE, Color32::from_rgb(40, 42, 46))
}
pub fn border() -> Color32 {
    pick(Color32::from_rgb(190, 192, 194), Color32::from_rgb(78, 82, 90))
}
/// Thin grid lines of the Properties palette.
pub fn grid_line() -> Color32 {
    pick(Color32::from_rgb(222, 224, 226), Color32::from_rgb(70, 73, 80))
}
pub fn text() -> Color32 {
    pick(Color32::from_rgb(20, 20, 20), Color32::from_rgb(225, 227, 230))
}
pub fn text_dim() -> Color32 {
    pick(Color32::from_rgb(128, 128, 128), Color32::from_rgb(150, 154, 160))
}
pub fn hover() -> Color32 {
    pick(Color32::from_rgb(229, 241, 251), Color32::from_rgb(64, 74, 88))
}
pub fn hover_stroke() -> Color32 {
    pick(Color32::from_rgb(160, 200, 235), Color32::from_rgb(90, 120, 150))
}
/// Group header band of the Properties palette.
pub fn group_header() -> Color32 {
    pick(Color32::from_rgb(229, 229, 229), Color32::from_rgb(64, 68, 74))
}
/// Palette title bars ("Properties", "Project Browser - Project1").
pub fn palette_title_fill() -> Color32 {
    pick(Color32::from_rgb(217, 217, 217), Color32::from_rgb(44, 47, 52))
}
/// View tab strip and inactive view tabs.
pub fn tab_idle() -> Color32 {
    pick(Color32::from_rgb(204, 204, 204), Color32::from_rgb(48, 51, 56))
}
/// View control bar at the bottom of each view.
pub fn view_bar() -> Color32 {
    pick(Color32::from_rgb(232, 234, 233), Color32::from_rgb(50, 53, 58))
}
pub fn icon_ink() -> Color32 {
    pick(Color32::from_rgb(58, 62, 70), Color32::from_rgb(210, 214, 220))
}

/// Canvas colour of drawing views (user option; white by default).
pub fn canvas(black_background: bool) -> Color32 {
    if black_background { Color32::from_rgb(33, 40, 48) } else { Color32::WHITE }
}

/// The bold UI font (Segoe UI Bold when available).
pub fn bold(size: f32) -> FontId {
    FontId::new(size, FontFamily::Name("bold".into()))
}

/// The regular UI font.
pub fn font(size: f32) -> FontId {
    FontId::proportional(size)
}

/// Uses the platform UI font (Segoe UI on Windows) so the chrome reads like other Windows
/// BIM tools; falls back to egui's bundled fonts elsewhere.
fn install_fonts(ctx: &egui::Context) {
    if FONTS_LOADED.swap(true, Ordering::Relaxed) {
        return;
    }
    let mut fonts = egui::FontDefinitions::default();
    let dirs: Vec<std::path::PathBuf> = match std::env::var_os("WINDIR") {
        Some(w) => vec![std::path::PathBuf::from(w).join("Fonts")],
        None => vec![],
    };
    let load = |names: &[&str]| -> Option<Vec<u8>> {
        for d in &dirs {
            for n in names {
                if let Ok(b) = std::fs::read(d.join(n)) {
                    return Some(b);
                }
            }
        }
        None
    };
    let regular = load(&["segoeui.ttf"]);
    let bold = load(&["segoeuib.ttf"]);
    let default_prop = fonts.families.get(&FontFamily::Proportional).cloned().unwrap_or_default();
    if let Some(r) = regular {
        fonts.font_data.insert("ui".into(), egui::FontData::from_owned(r).into());
        fonts.families.entry(FontFamily::Proportional).or_default().insert(0, "ui".into());
    }
    let mut bold_family = default_prop;
    if let Some(b) = bold {
        fonts.font_data.insert("ui-bold".into(), egui::FontData::from_owned(b).into());
        bold_family.insert(0, "ui-bold".into());
    } else if fonts.font_data.contains_key("ui") {
        bold_family.insert(0, "ui".into());
    }
    fonts.families.insert(FontFamily::Name("bold".into()), bold_family);
    ctx.set_fonts(fonts);
}

pub fn apply(ctx: &egui::Context, dark: bool) {
    DARK.store(dark, Ordering::Relaxed);
    install_fonts(ctx);
    ctx.set_visuals(if dark { egui::Visuals::dark() } else { egui::Visuals::light() });
    let mut style = (*ctx.global_style()).clone();
    style.spacing.item_spacing = egui::vec2(6.0, 3.0);
    style.spacing.button_padding = egui::vec2(6.0, 2.0);
    style.spacing.interact_size.y = 19.0;
    style.spacing.combo_height = 320.0;
    style.spacing.menu_margin = Margin::same(2);
    style.visuals.panel_fill = panel();
    style.visuals.window_fill = pick(Color32::from_rgb(250, 250, 250), Color32::from_rgb(50, 53, 58));
    style.visuals.extreme_bg_color = field();
    style.visuals.faint_bg_color = pick(Color32::from_rgb(247, 248, 249), Color32::from_rgb(58, 61, 66));
    style.visuals.selection.bg_fill = accent_light();
    style.visuals.selection.stroke = Stroke::new(1.0, ACCENT);
    style.visuals.hyperlink_color = ACCENT;
    style.visuals.window_corner_radius = CornerRadius::same(0);
    style.visuals.menu_corner_radius = CornerRadius::same(0);
    style.visuals.window_stroke = Stroke::new(1.0, border());
    style.visuals.window_shadow = egui::Shadow { offset: [2, 3], blur: 8, spread: 0, color: Color32::from_black_alpha(40) };
    style.visuals.popup_shadow = egui::Shadow { offset: [2, 2], blur: 4, spread: 0, color: Color32::from_black_alpha(40) };
    style.visuals.override_text_color = Some(text());
    for w in [&mut style.visuals.widgets.inactive, &mut style.visuals.widgets.hovered, &mut style.visuals.widgets.active, &mut style.visuals.widgets.noninteractive, &mut style.visuals.widgets.open] {
        w.corner_radius = CornerRadius::same(0);
        w.expansion = 0.0;
    }
    style.visuals.widgets.inactive.weak_bg_fill = pick(Color32::from_rgb(253, 253, 253), Color32::from_rgb(64, 67, 73));
    style.visuals.widgets.inactive.bg_fill = pick(Color32::from_rgb(253, 253, 253), Color32::from_rgb(64, 67, 73));
    style.visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, border());
    style.visuals.widgets.hovered.weak_bg_fill = hover();
    style.visuals.widgets.hovered.bg_fill = hover();
    style.visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, hover_stroke());
    style.visuals.widgets.active.weak_bg_fill = accent_light();
    style.visuals.widgets.active.bg_fill = accent_light();
    style.visuals.widgets.open.weak_bg_fill = accent_light();
    style.visuals.widgets.noninteractive.bg_stroke = Stroke::new(1.0, border());
    style.text_styles.insert(egui::TextStyle::Body, FontId::proportional(12.0));
    style.text_styles.insert(egui::TextStyle::Button, FontId::proportional(12.0));
    style.text_styles.insert(egui::TextStyle::Small, FontId::proportional(10.5));
    style.text_styles.insert(egui::TextStyle::Heading, FontId::proportional(15.0));
    ctx.set_global_style(style);
}

pub fn ribbon_frame() -> egui::Frame {
    egui::Frame::new().fill(chrome()).inner_margin(Margin::same(0))
}

pub fn bar_frame() -> egui::Frame {
    egui::Frame::new().fill(ribbon()).inner_margin(Margin::symmetric(6, 1)).stroke(Stroke::new(1.0, border()))
}

pub fn side_frame() -> egui::Frame {
    egui::Frame::new().fill(field()).inner_margin(Margin::same(0)).stroke(Stroke::new(1.0, border()))
}

pub fn canvas_frame() -> egui::Frame {
    egui::Frame::new().fill(tab_idle()).inner_margin(Margin::same(0))
}

/// A palette title bar ("Properties", "Project Browser - Project1") with the close cross.
/// Returns true when the cross was clicked.
pub fn palette_title(ui: &mut egui::Ui, title: &str) -> bool {
    let (rect, _) = ui.allocate_exact_size(egui::vec2(ui.available_width(), 18.0), egui::Sense::hover());
    let p = ui.painter();
    p.rect_filled(rect, 0.0, palette_title_fill());
    p.text(rect.left_center() + egui::vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, title, font(12.0), text_color_title());
    let x = egui::Rect::from_center_size(rect.right_center() - egui::vec2(10.0, 0.0), egui::vec2(16.0, 16.0));
    let resp = ui.interact(x, ui.id().with(("palette-close", title)), egui::Sense::click());
    if resp.hovered() {
        p.rect_filled(x, 0.0, hover());
    }
    let c = x.center();
    let st = Stroke::new(1.2, text());
    p.line_segment([c + egui::vec2(-4.0, -4.0), c + egui::vec2(4.0, 4.0)], st);
    p.line_segment([c + egui::vec2(4.0, -4.0), c + egui::vec2(-4.0, 4.0)], st);
    resp.clicked()
}

fn text_color_title() -> Color32 {
    pick(Color32::from_rgb(40, 40, 40), Color32::from_rgb(220, 220, 220))
}

/// A collapsible group header in the Properties palette: bold label on a grey band with the
/// collapse chevron at the right.
pub fn group_header_ui(ui: &mut egui::Ui, label: &str, open: bool) -> egui::Response {
    let (rect, resp) = ui.allocate_exact_size(egui::vec2(ui.available_width(), 18.0), egui::Sense::click());
    let p = ui.painter();
    p.rect_filled(rect, 0.0, group_header());
    p.text(rect.left_center() + egui::vec2(3.0, 0.0), egui::Align2::LEFT_CENTER, label, bold(12.0), text());
    let c = rect.right_center() - egui::vec2(10.0, 0.0);
    let st = Stroke::new(1.0, text_dim());
    if open {
        p.line_segment([c + egui::vec2(-3.5, 2.0), c + egui::vec2(0.0, -1.5)], st);
        p.line_segment([c + egui::vec2(0.0, -1.5), c + egui::vec2(3.5, 2.0)], st);
    } else {
        p.line_segment([c + egui::vec2(-3.5, -1.5), c + egui::vec2(0.0, 2.0)], st);
        p.line_segment([c + egui::vec2(0.0, 2.0), c + egui::vec2(3.5, -1.5)], st);
    }
    resp
}

/// A parameter group band in dialogs (steel blue, bold label), as in Type Properties.
pub fn header(ui: &mut egui::Ui, text: &str) {
    let (r, _) = ui.allocate_exact_size(egui::vec2(ui.available_width(), 19.0), egui::Sense::hover());
    let fill = pick(Color32::from_rgb(157, 184, 217), Color32::from_rgb(60, 80, 110));
    ui.painter().rect_filled(r, 0.0, fill);
    ui.painter().text(r.left_center() + egui::vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, text, bold(12.0), pick(Color32::from_rgb(16, 24, 40), Color32::WHITE));
}

/// A small light-yellow-free Windows tooltip box (white with a grey border) at `pos`.
pub fn canvas_tooltip(painter: &egui::Painter, pos: egui::Pos2, text: &str) -> egui::Rect {
    let galley = painter.layout(text.to_string(), font(11.5), Color32::from_gray(40), 320.0);
    let bg = egui::Rect::from_min_size(pos, galley.size()).expand2(egui::vec2(4.0, 2.0)).translate(egui::vec2(4.0, 2.0));
    painter.rect_filled(bg.translate(egui::vec2(1.5, 1.5)), 0.0, Color32::from_black_alpha(30));
    painter.rect_filled(bg, 0.0, Color32::from_rgb(252, 252, 252));
    painter.rect_stroke(bg, 0.0, Stroke::new(1.0, Color32::from_gray(150)), egui::StrokeKind::Inside);
    painter.galley(bg.min + egui::vec2(4.0, 2.0), galley, Color32::from_gray(40));
    bg
}
