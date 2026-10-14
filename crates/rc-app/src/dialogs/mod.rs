//! Dialogs. Each is shown while its field in `Dialogs` is set.

mod settings;
mod type_props;
mod views;

use crate::app::App;
use crate::commands::Cmd;
use crate::icons::{self, Icon};
use crate::{actions, style};
use eframe::egui::{self, Sense, vec2};
use rc_core::model::*;
use rc_core::units::UnitSystem;
use std::collections::BTreeSet;

#[derive(Clone, Debug, PartialEq)]
pub enum Pending {
    New,
    Open,
    Sample,
    ImportIfc,
    OpenPath(String),
    Quit,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ExportKind {
    Dxf,
    Pdf,
    Image,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum PlanKind {
    Floor,
    Ceiling,
    Area,
}

#[derive(Clone, Debug, Default)]
pub struct PurgeState {
    pub checked: BTreeSet<String>,
    pub init: bool,
}

#[derive(Default)]
pub struct Dialogs {
    pub home: bool,
    pub new_project: bool,
    pub pending: Option<Pending>,
    pub import_warnings: Option<Vec<String>>,
    pub export: Option<ExportKind>,
    pub export_sel: BTreeSet<Id>,
    pub export_size: u32,
    pub options: bool,
    pub exit: bool,
    pub create_group: Option<String>,
    pub tag_all: bool,
    pub tag_all_cats: BTreeSet<Category>,
    pub view_templates: bool,
    pub vg: Option<Id>,
    pub new_plan: Option<PlanKind>,
    pub new_plan_sel: BTreeSet<Id>,
    pub new_schedule: Option<bool>,
    pub new_sheet: bool,
    pub place_view: Option<Id>,
    pub revisions: bool,
    pub materials: Option<Option<String>>,
    pub object_styles: bool,
    pub snaps: bool,
    pub project_info: bool,
    pub units: bool,
    pub purge: Option<PurgeState>,
    pub phases: bool,
    pub design_options: bool,
    pub sun: bool,
    pub links: bool,
    pub message: Option<(String, String)>,
    pub select_by_id: Option<String>,
    pub warnings: bool,
    pub shortcuts: Option<String>,
    pub view_range: Option<Id>,
    pub type_props: Option<Id>,
    pub type_props_assembly: bool,
    pub override_graphics: Option<Id>,
    pub new_family: bool,
    pub rename_view: Option<(Id, String)>,
    pub rename_type: Option<(Id, String)>,
    pub text_edit: Option<Id>,
    pub dim_text: Option<Id>,
    pub rename_element: Option<Id>,
    pub filter: bool,
    pub schedule_props: Option<(Id, usize)>,
    pub about: bool,
    /// OK/Cancel sessions: dialog key -> (undo depth when opened, last time shown).
    pub sessions: std::collections::HashMap<&'static str, (usize, f64)>,
}

/// Opens a dialog by name (command line `--dialog NAME`, used by screenshot checks).
pub fn open_by_name(app: &mut App, name: &str) {
    let d = &mut app.dialogs;
    match name {
        "home" => d.home = true,
        "new" => d.new_project = true,
        "options" => d.options = true,
        "materials" => d.materials = Some(None),
        "object-styles" => d.object_styles = true,
        "snaps" => d.snaps = true,
        "units" => d.units = true,
        "info" => d.project_info = true,
        "phases" => d.phases = true,
        "options-design" => d.design_options = true,
        "vg" => d.vg = app.active,
        "range" => d.view_range = app.active,
        "templates" => d.view_templates = true,
        "shortcuts" => d.shortcuts = Some(String::new()),
        "tag-all" => d.tag_all = true,
        "sheet" => d.new_sheet = true,
        "export" => d.export = Some(ExportKind::Pdf),
        "type" => {
            let t = app.doc.data.types_of(Category::Walls).find(|t| t.layers.len() > 2).map(|t| t.id);
            app.dialogs.type_props = t;
            app.dialogs.type_props_assembly = true;
        }
        "family" => {
            let f = app.doc.data.families.iter().find(|f| f.category == Category::Windows).map(|f| f.id);
            if let Some(f) = f {
                crate::family_editor::open(app, f);
            }
        }
        "new-family" => {
            crate::family_editor::new_custom(app, "Custom Family");
        }
        "purge" => d.purge = Some(Default::default()),
        "sun" => d.sun = true,
        _ => {}
    }
}

thread_local! {
    static CENTER: std::cell::Cell<egui::Pos2> = const { std::cell::Cell::new(egui::pos2(700.0, 420.0)) };
}

/// Dialog body colour (the standard Windows dialog grey).
pub fn dialog_fill() -> egui::Color32 {
    if style::is_dark() { egui::Color32::from_rgb(50, 53, 58) } else { egui::Color32::from_rgb(243, 243, 243) }
}

/// A dialog window: a small left-aligned title with the close cross, a grey body, opening
/// centred on the application window.
pub struct Dlg<'a> {
    title: String,
    win: egui::Window<'static>,
    open: Option<&'a mut bool>,
    resizable: bool,
}

fn window(title: &str) -> Dlg<'static> {
    let c = CENTER.with(|c| c.get());
    let win = egui::Window::new(title.to_string())
        .id(egui::Id::new(("dialog", title)))
        .collapsible(false)
        .resizable(true)
        .title_bar(false)
        .pivot(egui::Align2::CENTER_CENTER)
        .default_pos(c)
        .constrain(true)
        .frame(egui::Frame::new().fill(dialog_fill()).stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(150))).shadow(egui::Shadow { offset: [3, 4], blur: 14, spread: 0, color: egui::Color32::from_black_alpha(50) }));
    Dlg { title: title.to_string(), win, open: None, resizable: true }
}

impl<'a> Dlg<'a> {
    pub fn open<'b>(self, open: &'b mut bool) -> Dlg<'b> {
        Dlg { title: self.title, win: self.win, open: Some(open), resizable: self.resizable }
    }
    pub fn default_width(mut self, w: f32) -> Self {
        self.win = self.win.default_width(w);
        self
    }
    pub fn default_size(mut self, s: impl Into<egui::Vec2>) -> Self {
        self.win = self.win.default_size(s);
        self
    }
    pub fn resizable(mut self, r: bool) -> Self {
        self.win = self.win.resizable(r);
        self.resizable = r;
        self
    }
    pub fn default_pos(mut self, p: impl Into<egui::Pos2>) -> Self {
        self.win = self.win.default_pos(p);
        self
    }

    pub fn show<R>(self, ctx: &egui::Context, add_contents: impl FnOnce(&mut egui::Ui) -> R) -> Option<R> {
        if self.open.as_ref().is_some_and(|o| !**o) {
            return None;
        }
        let title = self.title.clone();
        let mut close = false;
        const BAR: f32 = 30.0;
        let resizable = self.resizable;
        let r = self.win.show(ctx, |ui| {
            if resizable && !ui.is_sizing_pass() {
                ui.set_min_width(ui.available_width());
            }
            let top = ui.min_rect().top();
            ui.add_space(BAR);
            let inner = egui::Frame::new().inner_margin(egui::Margin { left: 12, right: 12, top: 4, bottom: 12 }).show(ui, add_contents).inner;
            // Title bar across the final width.
            let w = ui.min_rect().width();
            let bar = egui::Rect::from_min_size(egui::pos2(ui.min_rect().left(), top), vec2(w, BAR));
            let p = ui.painter();
            p.rect_filled(bar, 0.0, if style::is_dark() { egui::Color32::from_rgb(44, 47, 52) } else { egui::Color32::WHITE });
            p.text(bar.left_center() + vec2(10.0, 0.0), egui::Align2::LEFT_CENTER, &title, style::font(12.0), style::text());
            let x = egui::Rect::from_center_size(bar.right_center() - vec2(22.0, 0.0), vec2(44.0, BAR));
            let resp = ui.interact(x, ui.id().with("dlg-close"), Sense::click());
            if resp.hovered() {
                ui.painter().rect_filled(x, 0.0, egui::Color32::from_rgb(232, 17, 35));
            }
            let c = x.center();
            let ink = egui::Stroke::new(1.1, if resp.hovered() { egui::Color32::WHITE } else { style::text() });
            ui.painter().line_segment([c + vec2(-5.0, -5.0), c + vec2(5.0, 5.0)], ink);
            ui.painter().line_segment([c + vec2(5.0, -5.0), c + vec2(-5.0, 5.0)], ink);
            if resp.clicked() || ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                close = true;
            }
            inner
        });
        if close {
            if let Some(o) = self.open {
                *o = false;
            }
        }
        r.and_then(|r| r.inner)
    }
}

/// Discards a dialog's changes when it is closed with the cross (same as Cancel).
pub fn session_cancel(app: &mut App, key: &'static str) {
    if let Some((depth, _)) = app.dialogs.sessions.remove(key) {
        app.doc.rollback_to(depth);
    }
}

/// The column header row of a dialog table.
pub fn table_header(ui: &mut egui::Ui, cols: &[&str]) {
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), 21.0), Sense::hover());
    let p = ui.painter();
    p.rect_filled(r, 0.0, if style::is_dark() { egui::Color32::from_rgb(60, 63, 68) } else { egui::Color32::from_rgb(246, 246, 246) });
    p.line_segment([r.left_bottom(), r.right_bottom()], egui::Stroke::new(1.0, egui::Color32::from_gray(190)));
    let first = (r.width() * 0.46).floor().clamp(80.0, 200.0) + 1.0;
    let widths: Vec<f32> = if cols.len() == 2 { vec![first, r.width() - first] } else { vec![r.width() / cols.len() as f32; cols.len()] };
    let mut x = r.left();
    for (k, c) in cols.iter().enumerate() {
        let cell = egui::Rect::from_min_size(egui::pos2(x, r.top()), vec2(widths[k], r.height()));
        p.text(cell.center(), egui::Align2::CENTER_CENTER, *c, style::font(12.0), style::text());
        if k + 1 < cols.len() {
            p.line_segment([cell.right_top(), cell.right_bottom()], egui::Stroke::new(1.0, egui::Color32::from_gray(200)));
        }
        x += widths[k];
    }
}

/// A dialog push button (white face, grey border; the default button has a blue border).
pub fn dlg_button(ui: &mut egui::Ui, label: &str, default: bool, enabled: bool) -> bool {
    let (r, resp) = ui.allocate_exact_size(vec2(78.0, 24.0), if enabled { Sense::click() } else { Sense::hover() });
    let fill = if !enabled {
        egui::Color32::from_rgb(245, 245, 245)
    } else if resp.is_pointer_button_down_on() {
        egui::Color32::from_rgb(204, 228, 247)
    } else if resp.hovered() {
        egui::Color32::from_rgb(229, 241, 251)
    } else {
        egui::Color32::from_rgb(253, 253, 253)
    };
    ui.painter().rect_filled(r, 3.0, fill);
    let border = if default && enabled { egui::Color32::from_rgb(0, 120, 215) } else { egui::Color32::from_gray(190) };
    ui.painter().rect_stroke(r, 3.0, egui::Stroke::new(if default && enabled { 1.5 } else { 1.0 }, border), egui::StrokeKind::Inside);
    ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, label, style::font(12.0), if enabled { style::text() } else { style::text_dim() });
    enabled && resp.clicked()
}

/// Starts (or continues) an OK/Cancel session for a dialog: remembers the undo depth when the
/// dialog first appears so Cancel can discard and OK can group its changes.
pub fn session_begin(app: &mut App, key: &'static str) -> usize {
    let now = app.now;
    let depth = app.doc.undo_depth();
    let e = app.dialogs.sessions.entry(key).or_insert((depth, now));
    if now - e.1 > 0.75 {
        *e = (depth, now);
    } else {
        e.1 = now;
    }
    e.0
}

/// What the footer asked for.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Footer {
    None,
    Ok,
    Cancel,
}

/// The OK / Cancel / Apply row. Edits take effect as they are made (so the views update
/// live); OK keeps them as one undo step, Cancel discards them, Apply keeps them and stays open.
pub fn footer(ui: &mut egui::Ui, app: &mut App, key: &'static str, title: &str) -> Footer {
    let depth = session_begin(app, key);
    let changed = app.doc.undo_depth() != depth;
    let mut out = Footer::None;
    ui.add_space(8.0);
    ui.horizontal(|ui| {
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Apply", false, changed) {
                app.doc.squash_since(depth, title);
                let d = app.doc.undo_depth();
                app.dialogs.sessions.insert(key, (d, app.now));
            }
            if dlg_button(ui, "Cancel", false, true) {
                out = Footer::Cancel;
            }
            if dlg_button(ui, "OK", true, true) {
                out = Footer::Ok;
            }
        });
    });
    match out {
        Footer::Ok => app.doc.squash_since(depth, title),
        Footer::Cancel => app.doc.rollback_to(depth),
        Footer::None => {}
    }
    if out != Footer::None {
        app.dialogs.sessions.remove(key);
    }
    out
}

pub fn show(app: &mut App, ctx: &egui::Context) {
    CENTER.with(|c| c.set(ctx.content_rect().center()));
    home(app, ctx);
    new_project(app, ctx);
    pending(app, ctx);
    if let Some(w) = app.dialogs.import_warnings.clone() {
        let mut open = true;
        window("Import Warnings").open(&mut open).default_width(520.0).show(ctx, |ui| {
            egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
                for line in &w {
                    ui.label(format!("• {line}"));
                }
            });
        });
        if !open {
            app.dialogs.import_warnings = None;
        }
    }
    if app.dialogs.exit {
        app.dialogs.exit = false;
        if app.confirm_discard(Pending::Quit) {
            app.quit_requested = true;
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
    if let Some((title, text)) = app.dialogs.message.clone() {
        let mut open = true;
        window(&title).open(&mut open).show(ctx, |ui| {
            ui.add(egui::TextEdit::multiline(&mut text.clone()).desired_width(380.0));
        });
        if !open {
            app.dialogs.message = None;
        }
    }
    export_dialog(app, ctx);
    create_group(app, ctx);
    tag_all(app, ctx);
    renames(app, ctx);
    filter(app, ctx);
    select_by_id(app, ctx);
    warnings(app, ctx);
    about(app, ctx);
    settings::show(app, ctx);
    views::show(app, ctx);
    type_props::show(app, ctx);
}

// ---------------------------------------------------------------- start

fn tile(ui: &mut egui::Ui, icon: Icon, title: &str, sub: &str) -> bool {
    let (r, resp) = ui.allocate_exact_size(vec2(200.0, 64.0), Sense::click());
    ui.painter().rect_filled(r, 4.0, if resp.hovered() { style::hover() } else { style::field() });
    ui.painter().rect_stroke(r, 4.0, egui::Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    icons::paint(ui.painter(), egui::Rect::from_min_size(r.min + vec2(10.0, 14.0), vec2(36.0, 36.0)), icon, true);
    ui.painter().text(r.min + vec2(56.0, 16.0), egui::Align2::LEFT_TOP, title, egui::FontId::proportional(13.5), style::text());
    ui.painter().text(r.min + vec2(56.0, 36.0), egui::Align2::LEFT_TOP, sub, egui::FontId::proportional(11.0), style::text_dim());
    resp.clicked()
}

fn home(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.home {
        return;
    }
    let mut open = true;
    let mut close = false;
    egui::Window::new("RevitCraft — Home").collapsible(false).resizable(false).anchor(egui::Align2::CENTER_CENTER, vec2(0.0, 0.0)).open(&mut open).show(ctx, |ui| {
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.heading("Models");
                ui.add_space(6.0);
                if tile(ui, Icon::New, "New (Metric)", "Millimetres, metric template") {
                    app.new_project(UnitSystem::Metric);
                    close = true;
                }
                if tile(ui, Icon::New, "New (Imperial)", "Feet and inches template") {
                    app.new_project(UnitSystem::Imperial);
                    close = true;
                }
                if tile(ui, Icon::Open, "Open...", "Project (.rcx) or IFC model") {
                    close = true;
                    app.open_dialog();
                }
                if tile(ui, Icon::Home, "Sample Project", "A small house to explore") {
                    app.open_sample();
                    close = true;
                }
                ui.add_space(8.0);
                ui.heading("Families");
                ui.add_space(6.0);
                if tile(ui, Icon::FamilyTypes, "New Family...", "Parametric family editor") {
                    close = true;
                    crate::family_editor::new_custom(app, "Custom Family");
                }
            });
            ui.add_space(16.0);
            ui.vertical(|ui| {
                ui.set_width(340.0);
                ui.heading("Recent");
                ui.add_space(6.0);
                if app.settings.recent.is_empty() {
                    ui.label(egui::RichText::new("Projects you open or save appear here.").color(style::text_dim()));
                }
                for r in app.settings.recent.clone() {
                    let name = std::path::Path::new(&r).file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or(r.clone());
                    if tile(ui, Icon::Save, &name, &truncate(&r, 46)) {
                        app.open_path(std::path::Path::new(&r));
                        close = true;
                    }
                }
            });
        });
    });
    if !open || close {
        app.dialogs.home = false;
    }
}

fn truncate(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        format!("…{}", s.chars().rev().take(n).collect::<Vec<_>>().into_iter().rev().collect::<String>())
    }
}

fn new_project(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.new_project {
        return;
    }
    let mut open = true;
    let mut choice: Option<UnitSystem> = None;
    window("New Project").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.label("Template file");
        let id = egui::Id::new("new-project-units");
        let mut sys: UnitSystem = ui.memory(|m| m.data.get_temp(id)).unwrap_or(UnitSystem::Metric);
        ui.radio_value(&mut sys, UnitSystem::Metric, "Metric template (millimetres, 1:100, A-series sheets)");
        ui.radio_value(&mut sys, UnitSystem::Imperial, "Imperial template (feet-inches, 1/8\" = 1'-0\", ARCH sheets)");
        ui.memory_mut(|m| m.data.insert_temp(id, sys));
        ui.add_space(6.0);
        ui.label(egui::RichText::new("Create new: Project").color(style::text_dim()));
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if ui.button("  OK  ").clicked() {
                choice = Some(sys);
            }
            if ui.button("Cancel").clicked() {
                app.dialogs.new_project = false;
            }
        });
    });
    if let Some(s) = choice {
        app.new_project(s);
        app.dialogs.new_project = false;
    }
    if !open {
        app.dialogs.new_project = false;
    }
}

fn pending(app: &mut App, ctx: &egui::Context) {
    let Some(action) = app.dialogs.pending.clone() else { return };
    let mut result: Option<bool> = None; // Some(true) = proceed after save/discard
    let mut cancel = false;
    egui::Window::new("RevitCraft").collapsible(false).resizable(false).anchor(egui::Align2::CENTER_CENTER, vec2(0.0, 0.0)).show(ctx, |ui| {
        let name = app.doc.path.as_ref().and_then(|p| p.file_name()).map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Project1".into());
        ui.horizontal(|ui| {
            let (r, _) = ui.allocate_exact_size(vec2(32.0, 32.0), Sense::hover());
            icons::paint(ui.painter(), r, Icon::Warnings, true);
            ui.label(format!("Do you want to save changes to {name}?"));
        });
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if ui.button("Yes").clicked() {
                if app.save() {
                    result = Some(true);
                }
            }
            if ui.button("No").clicked() {
                result = Some(true);
            }
            if ui.button("Cancel").clicked() {
                cancel = true;
            }
        });
    });
    if cancel {
        app.dialogs.pending = None;
    }
    if result == Some(true) {
        app.dialogs.pending = None;
        app.doc.dirty = false;
        match action {
            Pending::New => app.dialogs.new_project = true,
            Pending::Open => app.open_dialog(),
            Pending::Sample => app.open_sample(),
            Pending::ImportIfc => {
                if let Some(path) = rfd::FileDialog::new().add_filter("IFC", &["ifc"]).pick_file() {
                    app.import_ifc_path(&path);
                }
            }
            Pending::OpenPath(p) => app.open_path(std::path::Path::new(&p)),
            Pending::Quit => {
                app.quit_requested = true;
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }
        }
    }
}

// ---------------------------------------------------------------- export

fn export_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(kind) = app.dialogs.export else { return };
    let mut open = true;
    let title = match kind {
        ExportKind::Dxf => "DWG/DXF Export",
        ExportKind::Pdf => "PDF Export",
        ExportKind::Image => "Export Image",
    };
    if app.dialogs.export_size == 0 {
        app.dialogs.export_size = 2400;
    }
    let mut go = false;
    window(title).open(&mut open).default_width(460.0).show(ctx, |ui| {
        let p = &app.doc.data;
        let candidates: Vec<(Id, String, bool)> = p
            .views
            .iter()
            .filter(|v| !v.is_template)
            .filter(|v| match kind {
                ExportKind::Dxf => matches!(v.kind, ViewKind::Sheet(_)) || (v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. })),
                ExportKind::Pdf => matches!(v.kind, ViewKind::Sheet(_)) || (v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. })),
                ExportKind::Image => v.is_graphical(),
            })
            .map(|v| (v.id, format!("{}: {}", v.type_label(), match &v.kind {
                ViewKind::Sheet(s) => format!("{} - {}", s.number, v.name),
                _ => v.name.clone(),
            }), matches!(v.kind, ViewKind::Sheet(_))))
            .collect();
        if app.dialogs.export_sel.is_empty() {
            match kind {
                ExportKind::Image => {
                    if let Some(a) = app.active {
                        app.dialogs.export_sel.insert(a);
                    }
                }
                _ => {
                    for (id, _, sheet) in &candidates {
                        if *sheet {
                            app.dialogs.export_sel.insert(*id);
                        }
                    }
                    if app.dialogs.export_sel.is_empty() {
                        if let Some(a) = app.active {
                            app.dialogs.export_sel.insert(a);
                        }
                    }
                }
            }
        }
        ui.label(match kind {
            ExportKind::Image => "View to export:",
            _ => "Views and sheets to export:",
        });
        egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
            for (id, label, _) in &candidates {
                let mut on = app.dialogs.export_sel.contains(id);
                if kind == ExportKind::Image {
                    if ui.radio(on, label).clicked() {
                        app.dialogs.export_sel.clear();
                        app.dialogs.export_sel.insert(*id);
                    }
                } else if ui.checkbox(&mut on, label).changed() {
                    if on {
                        app.dialogs.export_sel.insert(*id);
                    } else {
                        app.dialogs.export_sel.remove(id);
                    }
                }
            }
        });
        if kind == ExportKind::Image {
            ui.horizontal(|ui| {
                ui.label("Width (pixels):");
                ui.add(egui::DragValue::new(&mut app.dialogs.export_size).range(200..=8000));
            });
        }
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            if ui.add_enabled(!app.dialogs.export_sel.is_empty(), egui::Button::new("Export...")).clicked() {
                go = true;
            }
            if ui.button("Cancel").clicked() {
                app.dialogs.export = None;
            }
        });
    });
    if !open {
        app.dialogs.export = None;
    }
    if go {
        let ids: Vec<Id> = app.dialogs.export_sel.iter().copied().collect();
        app.dialogs.export = None;
        app.dialogs.export_sel.clear();
        match kind {
            ExportKind::Dxf => export_dxf(app, &ids),
            ExportKind::Pdf => export_pdf(app, &ids),
            ExportKind::Image => export_image(app, ids[0]),
        }
    }
}

fn safe_name(s: &str) -> String {
    s.chars().map(|c| if c.is_alphanumeric() || c == '-' || c == '_' || c == ' ' { c } else { '_' }).collect::<String>().trim().to_string()
}

fn export_dxf(app: &mut App, ids: &[Id]) {
    let fp = app.footprints();
    let p = app.doc.data.clone();
    if ids.len() == 1 {
        let v = p.view(ids[0]).unwrap();
        let Some(path) = rfd::FileDialog::new().add_filter("DXF", &["dxf"]).set_file_name(format!("{}.dxf", safe_name(&v.name))).save_file() else { return };
        let text = match &v.kind {
            ViewKind::Sheet(_) => Some(rc_core::dxf::export_sheet(&p, v, &fp)),
            _ => rc_core::dxf::export_view(&p, v, &fp),
        };
        match text.map(|t| std::fs::write(&path, t)) {
            Some(Ok(())) => app.info(format!("Exported {}", path.display())),
            Some(Err(e)) => app.error(format!("Could not write {}: {e}", path.display())),
            None => app.error("This view cannot be exported to DXF."),
        }
        return;
    }
    let Some(dir) = rfd::FileDialog::new().set_title("Choose a folder for the DXF files").pick_folder() else { return };
    let mut n = 0;
    for id in ids {
        let Some(v) = p.view(*id) else { continue };
        let text = match &v.kind {
            ViewKind::Sheet(s) => Some((rc_core::dxf::export_sheet(&p, v, &fp), format!("{} - {}", s.number, v.name))),
            _ => rc_core::dxf::export_view(&p, v, &fp).map(|t| (t, format!("{} - {}", v.type_label(), v.name))),
        };
        if let Some((t, name)) = text {
            if std::fs::write(dir.join(format!("{}.dxf", safe_name(&name))), t).is_ok() {
                n += 1;
            }
        }
    }
    app.info(format!("Exported {n} DXF file(s) to {}", dir.display()));
}

fn export_pdf(app: &mut App, ids: &[Id]) {
    let Some(path) = rfd::FileDialog::new().add_filter("PDF", &["pdf"]).set_file_name("Sheets.pdf").save_file() else { return };
    let fp = app.footprints();
    let data = app.doc.data.clone();
    let mut pages = Vec::new();
    for id in ids {
        let Some(view) = data.view(*id).cloned() else { continue };
        match &view.kind {
            ViewKind::Sheet(_) => {
                let mut render = |vid: Id, w: u32, h: u32| crate::view3d::render_image(app, vid, w, h);
                pages.push(rc_core::sheet::to_pdf_page(&data, &view, &fp, &mut render));
            }
            _ => {
                if let Some(pg) = rc_core::sheet::view_to_pdf_page(&data, &view, &fp) {
                    pages.push(pg);
                }
            }
        }
    }
    if pages.is_empty() {
        app.error("Nothing to export.");
        return;
    }
    let bytes = rc_core::pdf::write(pages, &data.info.name);
    match std::fs::write(&path, bytes) {
        Ok(()) => app.info(format!("Exported {}", path.display())),
        Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
    }
}

/// Rasterises a 2D drawing to RGB (simple scanline renderer for image export).
fn raster_2d(app: &mut App, view: &View, width: u32) -> Option<rc_core::pdf::Image> {
    let d = app.drawing(view.id);
    let (mn, mx) = d.bounds()?;
    let size = (mx - mn) * 1.06;
    let scale = width as f64 / size.x.max(1.0);
    let height = ((size.y * scale) as u32).clamp(16, 8000);
    let origin = (mn + mx) / 2.0 - size / 2.0;
    let mut img = tiny_raster::Canvas::new(width, height);
    for (_, prim) in &d.prims {
        match prim {
            rc_core::plan::Prim::Fill { tris, color } => {
                for t in tris {
                    let pts: Vec<(f64, f64)> = t.iter().map(|q| ((q.x - origin.x) * scale, (size.y - (q.y - origin.y)) * scale)).collect();
                    img.fill_tri(&pts, *color);
                }
            }
            rc_core::plan::Prim::Line { pts, closed, stroke } => {
                let w = (stroke.width as f64 * view.scale * scale).clamp(1.0, 6.0);
                let mut v: Vec<(f64, f64)> = pts.iter().map(|q| ((q.x - origin.x) * scale, (size.y - (q.y - origin.y)) * scale)).collect();
                if *closed && !v.is_empty() {
                    v.push(v[0]);
                }
                for s in v.windows(2) {
                    img.line(s[0], s[1], w, stroke.color);
                }
            }
            rc_core::plan::Prim::Text { .. } => {}
        }
    }
    Some(rc_core::pdf::Image { width, height, rgb: img.rgb })
}

mod tiny_raster {
    pub struct Canvas {
        pub w: u32,
        pub h: u32,
        pub rgb: Vec<u8>,
    }
    impl Canvas {
        pub fn new(w: u32, h: u32) -> Canvas {
            Canvas { w, h, rgb: vec![255; (w * h * 3) as usize] }
        }
        fn blend(&mut self, x: i64, y: i64, c: [u8; 3], a: f64) {
            if x < 0 || y < 0 || x >= self.w as i64 || y >= self.h as i64 {
                return;
            }
            let i = ((y as u32 * self.w + x as u32) * 3) as usize;
            for k in 0..3 {
                self.rgb[i + k] = (self.rgb[i + k] as f64 * (1.0 - a) + c[k] as f64 * a).round() as u8;
            }
        }
        pub fn line(&mut self, a: (f64, f64), b: (f64, f64), w: f64, c: [u8; 3]) {
            let len = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt();
            let steps = (len * 2.0).ceil().max(1.0) as i64;
            let r = (w / 2.0).max(0.5);
            for s in 0..=steps {
                let t = s as f64 / steps as f64;
                let (x, y) = (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t);
                let ri = r.ceil() as i64;
                for dy in -ri..=ri {
                    for dx in -ri..=ri {
                        let d = ((dx as f64).powi(2) + (dy as f64).powi(2)).sqrt();
                        if d <= r {
                            self.blend(x as i64 + dx, y as i64 + dy, c, (r + 0.5 - d).clamp(0.0, 1.0));
                        }
                    }
                }
            }
        }
        pub fn fill_tri(&mut self, p: &[(f64, f64)], c: [u8; 4]) {
            if p.len() < 3 || c[3] == 0 {
                return;
            }
            let (minx, maxx) = (p.iter().map(|q| q.0).fold(f64::MAX, f64::min).floor() as i64, p.iter().map(|q| q.0).fold(f64::MIN, f64::max).ceil() as i64);
            let (miny, maxy) = (p.iter().map(|q| q.1).fold(f64::MAX, f64::min).floor() as i64, p.iter().map(|q| q.1).fold(f64::MIN, f64::max).ceil() as i64);
            let edge = |a: (f64, f64), b: (f64, f64), x: f64, y: f64| (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0);
            let area = edge(p[0], p[1], p[2].0, p[2].1);
            if area.abs() < 1e-9 {
                return;
            }
            for y in miny.max(0)..=maxy.min(self.h as i64 - 1) {
                for x in minx.max(0)..=maxx.min(self.w as i64 - 1) {
                    let (fx, fy) = (x as f64 + 0.5, y as f64 + 0.5);
                    let w0 = edge(p[1], p[2], fx, fy) / area;
                    let w1 = edge(p[2], p[0], fx, fy) / area;
                    let w2 = edge(p[0], p[1], fx, fy) / area;
                    if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                        self.blend(x, y, [c[0], c[1], c[2]], c[3] as f64 / 255.0);
                    }
                }
            }
        }
    }
}

fn export_image(app: &mut App, id: Id) {
    let Some(view) = app.doc.data.view(id).cloned() else { return };
    let w = app.dialogs.export_size.max(200);
    let img = if matches!(view.kind, ViewKind::ThreeD { .. }) {
        let h = (w as f64 * 0.625) as u32;
        crate::view3d::render_image(app, id, w, h)
    } else {
        raster_2d(app, &view, w)
    };
    let Some(img) = img else {
        app.error("This view could not be rendered.");
        return;
    };
    let Some(mut path) = rfd::FileDialog::new().add_filter("PNG image", &["png"]).set_file_name(format!("{}.png", safe_name(&view.name))).save_file() else { return };
    if path.extension().is_none() {
        path.set_extension("png");
    }
    let png = rc_core::png::encode(img.width, img.height, 3, &img.rgb);
    match std::fs::write(&path, png) {
        Ok(()) => app.info(format!("Exported {} ({} x {} px)", path.display(), img.width, img.height)),
        Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
    }
}

// ---------------------------------------------------------------- small dialogs

fn create_group(app: &mut App, ctx: &egui::Context) {
    let Some(mut name) = app.dialogs.create_group.clone() else { return };
    let mut open = true;
    let mut ok = false;
    window("Create Model Group").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Name:");
            ui.text_edit_singleline(&mut name);
        });
        if ui.button("OK").clicked() {
            ok = true;
        }
    });
    app.dialogs.create_group = if open && !ok { Some(name.clone()) } else { None };
    if ok {
        let ids = app.selection.clone();
        if let Some(g) = app.run("Create Group", |p| {
            let t = rc_core::edit::create_group(p, &ids, &name)?;
            let inst = p.elements.iter().find(|e| matches!(&e.kind, ElementKind::GroupInstance(gi) if gi.type_id == t)).map(|e| e.id);
            Ok(inst)
        }) {
            if let Some(g) = g {
                app.select(vec![g]);
            }
        }
    }
}

fn tag_all(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.tag_all {
        return;
    }
    let mut open = true;
    let mut ok = false;
    if app.dialogs.tag_all_cats.is_empty() {
        app.dialogs.tag_all_cats = [Category::Doors, Category::Windows, Category::Rooms].into_iter().collect();
    }
    window("Tag All Not Tagged").open(&mut open).default_width(360.0).show(ctx, |ui| {
        ui.label("Select the categories to tag in the active view:");
        egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
            for c in [Category::Doors, Category::Windows, Category::Rooms, Category::Areas, Category::Walls, Category::Furniture, Category::Casework, Category::PlumbingFixtures, Category::GenericModels, Category::StructuralColumns, Category::StructuralFraming] {
                let mut on = app.dialogs.tag_all_cats.contains(&c);
                if ui.checkbox(&mut on, format!("{} Tags", c.singular())).changed() {
                    if on {
                        app.dialogs.tag_all_cats.insert(c);
                    } else {
                        app.dialogs.tag_all_cats.remove(&c);
                    }
                }
            }
        });
        ui.checkbox(&mut app.opts.tag_leader, "Leader");
        if ui.button("OK").clicked() {
            ok = true;
        }
    });
    if ok {
        if let Some(v) = app.active {
            let cats: Vec<Category> = app.dialogs.tag_all_cats.iter().copied().collect();
            if let Some(n) = app.run("Tag All", |p| rc_core::edit::tag_all(p, v, &cats)) {
                app.info(format!("Added {n} tag(s)."));
            }
        }
    }
    if !open || ok {
        app.dialogs.tag_all = false;
    }
}

fn renames(app: &mut App, ctx: &egui::Context) {
    if let Some((id, mut name)) = app.dialogs.rename_view.clone() {
        let mut open = true;
        let mut ok = false;
        window("Rename View").open(&mut open).resizable(false).show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(&mut name);
            });
            if ui.button("OK").clicked() {
                ok = true;
            }
        });
        app.dialogs.rename_view = if open && !ok { Some((id, name.clone())) } else { None };
        if ok {
            app.run("Rename View", |p| rc_core::edit::rename_view(p, id, &name));
        }
    }
    if let Some((id, mut name)) = app.dialogs.rename_type.clone() {
        let mut open = true;
        let mut ok = false;
        window("Rename Type").open(&mut open).resizable(false).show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label("New name:");
                ui.text_edit_singleline(&mut name);
            });
            if ui.button("OK").clicked() {
                ok = true;
            }
        });
        app.dialogs.rename_type = if open && !ok { Some((id, name.clone())) } else { None };
        if ok {
            app.run("Rename Type", |p| {
                if let Some(t) = p.sys_type_mut(id) {
                    t.name = name.clone();
                    return Ok(());
                }
                for f in &mut p.families {
                    if let Some(t) = f.types.iter_mut().find(|t| t.id == id) {
                        t.name = name.clone();
                        return Ok(());
                    }
                }
                Err("Type not found.".into())
            });
        }
    }
    if let Some(id) = app.dialogs.text_edit {
        let key = egui::Id::new(("text-edit", id));
        let current = match app.el(id).map(|e| &e.kind) {
            Some(ElementKind::Text(t)) => t.text.clone(),
            _ => {
                app.dialogs.text_edit = None;
                return;
            }
        };
        let mut text: String = ctx.memory(|m| m.data.get_temp(key)).unwrap_or(current);
        let mut open = true;
        let mut ok = false;
        window("Edit Text").open(&mut open).show(ctx, |ui| {
            ui.add(egui::TextEdit::multiline(&mut text).desired_width(320.0).desired_rows(4));
            if ui.button("OK").clicked() {
                ok = true;
            }
        });
        ctx.memory_mut(|m| m.data.insert_temp(key, text.clone()));
        if ok {
            app.run("Edit Text", |p| {
                if let Some(ElementKind::Text(t)) = p.element_mut(id).map(|e| &mut e.kind) {
                    t.text = text.clone();
                }
                Ok(())
            });
        }
        if ok || !open {
            app.dialogs.text_edit = None;
            ctx.memory_mut(|m| m.data.remove::<String>(key));
        }
    }
    if let Some(id) = app.dialogs.dim_text {
        let Some(ElementKind::Dimension(d)) = app.el(id).map(|e| e.kind.clone()) else {
            app.dialogs.dim_text = None;
            return;
        };
        let key = egui::Id::new(("dim-text", id));
        let mut st: (String, String, String) = ctx.memory(|m| m.data.get_temp(key)).unwrap_or((d.text_override.clone(), d.prefix.clone(), d.suffix.clone()));
        let mut open = true;
        let mut ok = false;
        window("Dimension Text").open(&mut open).resizable(false).show(ctx, |ui| {
            egui::Grid::new("dimtext").num_columns(2).show(ui, |ui| {
                ui.label("Replace with text:");
                ui.text_edit_singleline(&mut st.0);
                ui.end_row();
                ui.label("Prefix:");
                ui.text_edit_singleline(&mut st.1);
                ui.end_row();
                ui.label("Suffix:");
                ui.text_edit_singleline(&mut st.2);
                ui.end_row();
            });
            if ui.button("OK").clicked() {
                ok = true;
            }
        });
        ctx.memory_mut(|m| m.data.insert_temp(key, st.clone()));
        if ok {
            app.run("Dimension Text", |p| {
                if let Some(ElementKind::Dimension(d)) = p.element_mut(id).map(|e| &mut e.kind) {
                    d.text_override = st.0.clone();
                    d.prefix = st.1.clone();
                    d.suffix = st.2.clone();
                }
                Ok(())
            });
        }
        if ok || !open {
            app.dialogs.dim_text = None;
            ctx.memory_mut(|m| m.data.remove::<(String, String, String)>(key));
        }
    }
    if let Some(id) = app.dialogs.rename_element {
        // Rooms/areas: name and number; tags: the room they tag.
        let target = match app.el(id).map(|e| &e.kind) {
            Some(ElementKind::Tag(t)) => t.host,
            _ => id,
        };
        let (name, number) = match app.el(target).map(|e| &e.kind) {
            Some(ElementKind::Room(r)) => (r.name.clone(), r.number.clone()),
            Some(ElementKind::Area(a)) => (a.name.clone(), a.number.clone()),
            _ => {
                app.dialogs.rename_element = None;
                return;
            }
        };
        let key = egui::Id::new(("rename-el", id));
        let mut st: (String, String) = ctx.memory(|m| m.data.get_temp(key)).unwrap_or((name, number));
        let mut open = true;
        let mut ok = false;
        window("Room").open(&mut open).resizable(false).show(ctx, |ui| {
            egui::Grid::new("room-name").num_columns(2).show(ui, |ui| {
                ui.label("Name:");
                ui.text_edit_singleline(&mut st.0);
                ui.end_row();
                ui.label("Number:");
                ui.text_edit_singleline(&mut st.1);
                ui.end_row();
            });
            if ui.button("OK").clicked() {
                ok = true;
            }
        });
        ctx.memory_mut(|m| m.data.insert_temp(key, st.clone()));
        if ok {
            app.run("Rename", |p| {
                match p.element_mut(target).map(|e| &mut e.kind) {
                    Some(ElementKind::Room(r)) => {
                        r.name = st.0.clone();
                        r.number = st.1.clone();
                    }
                    Some(ElementKind::Area(a)) => {
                        a.name = st.0.clone();
                        a.number = st.1.clone();
                    }
                    _ => {}
                }
                Ok(())
            });
        }
        if ok || !open {
            app.dialogs.rename_element = None;
            ctx.memory_mut(|m| m.data.remove::<(String, String)>(key));
        }
    }
}

fn filter(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.filter {
        return;
    }
    let mut open = true;
    let mut counts: std::collections::BTreeMap<String, Vec<Id>> = std::collections::BTreeMap::new();
    for id in &app.selection {
        let key = match app.el(*id) {
            Some(e) => e.category().label().to_string(),
            None => "Views".to_string(),
        };
        counts.entry(key).or_default().push(*id);
    }
    let key = egui::Id::new("filter-checked");
    let mut checked: BTreeSet<String> = ctx.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| counts.keys().cloned().collect());
    let mut ok = false;
    window("Filter").open(&mut open).default_width(320.0).show(ctx, |ui| {
        egui::Grid::new("filter-grid").num_columns(2).striped(true).show(ui, |ui| {
            ui.label(egui::RichText::new("Category").strong());
            ui.label(egui::RichText::new("Count").strong());
            ui.end_row();
            for (k, ids) in &counts {
                let mut on = checked.contains(k);
                if ui.checkbox(&mut on, k).changed() {
                    if on {
                        checked.insert(k.clone());
                    } else {
                        checked.remove(k);
                    }
                }
                ui.label(ids.len().to_string());
                ui.end_row();
            }
        });
        ui.horizontal(|ui| {
            if ui.button("Check All").clicked() {
                checked = counts.keys().cloned().collect();
            }
            if ui.button("Check None").clicked() {
                checked.clear();
            }
        });
        ui.label(format!("Total selected items: {}", counts.iter().filter(|(k, _)| checked.contains(*k)).map(|(_, v)| v.len()).sum::<usize>()));
        if ui.button("OK").clicked() {
            ok = true;
        }
    });
    ctx.memory_mut(|m| m.data.insert_temp(key, checked.clone()));
    if ok {
        let ids: Vec<Id> = counts.iter().filter(|(k, _)| checked.contains(*k)).flat_map(|(_, v)| v.clone()).collect();
        app.select(ids);
    }
    if ok || !open {
        app.dialogs.filter = false;
        ctx.memory_mut(|m| m.data.remove::<BTreeSet<String>>(key));
    }
}

fn select_by_id(app: &mut App, ctx: &egui::Context) {
    let Some(mut text) = app.dialogs.select_by_id.clone() else { return };
    let mut open = true;
    let mut ok = false;
    window("Select Elements by ID").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.label("IDs of selection (separate with ; or ,):");
        ui.text_edit_singleline(&mut text);
        if ui.button("OK").clicked() {
            ok = true;
        }
    });
    app.dialogs.select_by_id = if open && !ok { Some(text.clone()) } else { None };
    if ok {
        let ids: Vec<Id> = text.split([';', ',', ' ']).filter_map(|s| s.trim().parse().ok()).filter(|id| app.doc.data.element(*id).is_some()).collect();
        if ids.is_empty() {
            app.error("No elements with those IDs.");
        } else {
            app.select(ids);
        }
    }
}

fn warnings(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.warnings {
        return;
    }
    let mut open = true;
    window("Warnings").open(&mut open).default_width(520.0).show(ctx, |ui| {
        if app.warnings.is_empty() {
            ui.label("There are no warnings in this session.");
        }
        egui::ScrollArea::vertical().max_height(360.0).show(ui, |ui| {
            for w in app.warnings.iter().rev() {
                ui.horizontal_wrapped(|ui| {
                    let (r, _) = ui.allocate_exact_size(vec2(14.0, 14.0), Sense::hover());
                    icons::paint(ui.painter(), r, Icon::Warnings, true);
                    ui.label(w);
                });
                ui.separator();
            }
        });
        if ui.button("Clear").clicked() {
            app.warnings.clear();
        }
    });
    if !open {
        app.dialogs.warnings = false;
    }
}

fn about(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.about {
        return;
    }
    let mut open = true;
    window("About RevitCraft").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.heading("RevitCraft");
        ui.label("An open BIM authoring application: walls, doors, windows, floors, roofs, ceilings, stairs, structure, rooms and areas, parametric families, schedules, sheets, IFC/DXF/PDF exchange.");
        ui.add_space(4.0);
        ui.label(egui::RichText::new("Keyboard: two-letter shortcuts (WA wall, DR door, DI dimension...). Press KS to see them all.").color(style::text_dim()));
        if ui.button("Keyboard Shortcuts...").clicked() {
            actions::exec(app, Cmd::KeyboardShortcuts);
        }
    });
    if !open {
        app.dialogs.about = false;
    }
}
