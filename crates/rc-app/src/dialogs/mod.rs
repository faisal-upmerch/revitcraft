//! Dialogs. Each is shown while its field in `Dialogs` is set.

mod manage;
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
    /// DWG/DXF export: layer naming.
    pub dxf_layers: rc_core::dxf::LayerStandard,
    /// PDF export / print settings.
    pub print: rc_core::sheet::PrintSettings,
    pub pdf_separate: bool,
    /// File > Print, Print Setup and Print Preview.
    pub print_dialog: bool,
    pub print_selected: bool,
    pub print_setup: bool,
    pub print_preview: Option<Id>,
    /// Model Text's Edit Text dialog.
    pub model_text: Option<String>,
    /// The Level tool's Plan View Types.
    pub plan_view_types: bool,
    pub starting_view: bool,
    /// Rebar Cover Settings.
    pub rebar_cover: bool,
    /// Rendering (View > Render).
    pub render: Option<Box<RenderState>>,
    /// Insert Views from File: the source project and its views.
    pub insert_views: Option<Box<InsertViewsState>>,
    /// Edit Shared Parameters.
    pub shared_params: Option<Box<SharedParamsState>>,
    /// Transfer Project Standards: the source project and what to copy.
    pub transfer: Option<Box<TransferState>>,
    /// Location, Weather and Site.
    pub location: bool,
    /// The tab Location opens on (Rotate True North opens Site).
    pub location_tab: u8,
    /// Specify Coordinates at Point: the point and its N/S, E/W, Elevation and angle texts.
    pub specify_coords: Option<(rc_core::geom::DVec3, [String; 4])>,
    pub options: bool,
    pub exit: bool,
    pub create_group: Option<String>,
    /// Work Plane > Set.
    pub work_plane: bool,
    /// The stair sketch's Railing dialog.
    pub stair_railing: bool,
    /// "Cancel Editing Stair Element" confirmation.
    pub cancel_stair: bool,
    /// Connect Levels for the stair being sketched.
    pub connect_levels: bool,
    /// Lowest Level Notice for a new footprint roof: the level offered.
    pub lowest_level: Option<Id>,
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
    /// Model In-place: (step, category, name).
    pub in_place: Option<(u8, Category, String)>,
    pub rename_view: Option<(Id, String)>,
    pub rename_type: Option<(Id, String)>,
    pub text_edit: Option<Id>,
    pub dim_text: Option<Id>,
    pub rename_element: Option<Id>,
    pub filter: bool,
    pub schedule_props: Option<(Id, usize)>,
    pub project_params: bool,
    /// Parameter Properties: index being modified (None = new) and the edited parameter.
    pub param_edit: Option<(Option<usize>, ProjectParameter)>,
    /// Filters dialog with the selected filter.
    pub filters: Option<Option<Id>>,
    pub line_styles: bool,
    pub save_selection: Option<String>,
    /// Saved selections list: false = Load, true = Edit.
    pub selection_sets: Option<bool>,
    pub find_replace: Option<manage::FindReplace>,
    pub global_params: bool,
    /// Keynotes dialog for a keynote tag.
    pub keynote_pick: Option<Id>,
    pub keynoting: bool,
    /// Sheet whose guide grid / title block is being edited.
    pub guide_grid: Option<Id>,
    pub title_block: Option<Id>,
    pub global_new: Option<GlobalParameter>,
    pub about: bool,
    pub save_reminder: bool,
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
        "params" => d.project_params = true,
        "filters" => d.filters = Some(app.doc.data.filters.first().map(|f| f.id)),
        "line-styles" => d.line_styles = true,
        "globals" => d.global_params = true,
        "keynoting" => d.keynoting = true,
        "find" => d.find_replace = Some(Default::default()),
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

/// A dialog window in the reference app's style (for other modules).
pub fn window_pub(title: &str) -> Dlg<'static> {
    window(title)
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
    work_plane(app, ctx);
    lowest_level_notice(app, ctx);
    stair_railing_dialog(app, ctx);
    cancel_stair_dialog(app, ctx);
    connect_levels_dialog(app, ctx);
    print_dialog(app, ctx);
    print_setup_dialog(app, ctx);
    print_preview(app, ctx);
    model_text_dialog(app, ctx);
    plan_view_types_dialog(app, ctx);
    starting_view_dialog(app, ctx);
    transfer_dialog(app, ctx);
    shared_params_dialog(app, ctx);
    insert_views_dialog(app, ctx);
    render_dialog(app, ctx);
    rebar_cover_dialog(app, ctx);
    location_dialog(app, ctx);
    specify_coords_dialog(app, ctx);
    new_family_dialog(app, ctx);
    in_place_dialog(app, ctx);
    work_plane_viewer(app, ctx);
    tag_all(app, ctx);
    renames(app, ctx);
    filter(app, ctx);
    select_by_id(app, ctx);
    warnings(app, ctx);
    about(app, ctx);
    save_reminder(app, ctx);
    settings::show(app, ctx);
    manage::show(app, ctx);
    views::show(app, ctx);
    type_props::show(app, ctx);
}

// ---------------------------------------------------------------- start

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
                if let Some(path) = crate::files::FileDialog::new().add_filter("IFC", &["ifc"]).pick_file() {
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
                } else if crate::style::check(ui, &mut on, label).changed() {
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
        if kind == ExportKind::Dxf {
            // The reference app's export setup: layers named by a CAD standard.
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                ui.label("Layers:");
                let mut s = app.dialogs.dxf_layers;
                egui::ComboBox::from_id_salt("dxf-layers").selected_text(s.label()).width(300.0).show_ui(ui, |ui| {
                    for l in rc_core::dxf::LayerStandard::ALL {
                        ui.selectable_value(&mut s, l, l.label());
                    }
                });
                app.dialogs.dxf_layers = s;
            });
        }
        if kind == ExportKind::Pdf {
            // The reference app's PDF export settings.
            ui.add_space(4.0);
            ui.label(egui::RichText::new("File").strong());
            ui.radio_value(&mut app.dialogs.pdf_separate, false, "Combine multiple selected views and sheets into a single file");
            ui.radio_value(&mut app.dialogs.pdf_separate, true, "Create separate files");
            print_settings_ui(ui, &mut app.dialogs.print);
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

/// Paper, zoom, colors and options of printing and PDF export (the reference app's Print Setup).
fn print_settings_ui(ui: &mut egui::Ui, st: &mut rc_core::sheet::PrintSettings) {
    {
        {
            ui.label(egui::RichText::new("Paper Format").strong());
            ui.horizontal(|ui| {
                if ui.radio(st.paper.is_none(), "Use sheet size").clicked() {
                    st.paper = None;
                }
                if ui.radio(st.paper.is_some(), "Choose paper size:").clicked() && st.paper.is_none() {
                    st.paper = Some(SheetSize::A3);
                }
                ui.add_enabled_ui(st.paper.is_some(), |ui| {
                    let mut sz = st.paper.unwrap_or(SheetSize::A3);
                    egui::ComboBox::from_id_salt("pdf-paper").selected_text(sz.label()).width(90.0).show_ui(ui, |ui| {
                        for s in SheetSize::ALL {
                            ui.selectable_value(&mut sz, s, s.label());
                        }
                    });
                    if st.paper.is_some() {
                        st.paper = Some(sz);
                    }
                });
            });
            ui.add_enabled_ui(st.paper.is_some(), |ui| {
                ui.horizontal(|ui| {
                    ui.label("Orientation:");
                    ui.radio_value(&mut st.landscape, false, "Portrait");
                    ui.radio_value(&mut st.landscape, true, "Landscape");
                });
                ui.horizontal(|ui| {
                    ui.label("Zoom:");
                    ui.radio_value(&mut st.fit_to_page, true, "Fit to page");
                    ui.radio_value(&mut st.fit_to_page, false, "Zoom: 100% size");
                });
            });
            ui.horizontal(|ui| {
                ui.label("Colors:");
                egui::ComboBox::from_id_salt("pdf-colors").selected_text(st.colors.label()).width(110.0).show_ui(ui, |ui| {
                    for c in rc_core::sheet::PrintColors::ALL {
                        ui.selectable_value(&mut st.colors, c, c.label());
                    }
                });
            });
            ui.label(egui::RichText::new("Options").strong());
            crate::style::check(ui, &mut st.hide_ref_planes, "Hide ref/work planes");
            crate::style::check(ui, &mut st.hide_scope_boxes, "Hide scope boxes");
        }
    }
}

/// The Level tool's Plan View Types: which plans each new level gets.
fn plan_view_types_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.plan_view_types {
        return;
    }
    let id = egui::Id::new("plan-view-types");
    let mut pick: (bool, bool) = ctx.data(|m| m.get_temp(id)).unwrap_or(app.opts.level_plan_types);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Plan View Types").open(&mut open).resizable(false).default_width(280.0).show(ctx, |ui| {
        ui.label("Select view types to create:");
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
            ui.set_min_width(250.0);
            if ui.selectable_label(pick.1, "Ceiling Plan").clicked() {
                pick.1 = !pick.1;
            }
            if ui.selectable_label(pick.0, "Floor Plan").clicked() {
                pick.0 = !pick.0;
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, pick.0 || pick.1) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(id, pick));
    if ok {
        app.opts.level_plan_types = pick;
    }
    if ok || cancel || !open {
        app.dialogs.plan_view_types = false;
        ctx.data_mut(|m| m.remove::<(bool, bool)>(id));
    }
}

/// Rebar Cover Settings: the cover from concrete faces to the bars.
fn rebar_cover_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.rebar_cover {
        return;
    }
    let id = egui::Id::new("rebar-cover");
    let mut text: String = ctx.data(|m| m.get_temp(id)).unwrap_or_else(|| app.doc.data.units.length(rc_core::rebar::cover(&app.doc.data)));
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Rebar Cover Settings").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        egui::Grid::new("cover-grid").num_columns(2).striped(true).spacing(vec2(16.0, 6.0)).show(ui, |ui| {
            ui.label(egui::RichText::new("Description").strong());
            ui.label(egui::RichText::new("Setting").strong());
            ui.end_row();
            ui.label("Rebar Cover");
            ui.add(egui::TextEdit::singleline(&mut text).desired_width(100.0));
            ui.end_row();
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        match app.doc.data.units.parse(&text, ParamKind::Length) {
            Some(v) if v > 0.0 => {
                app.run("Rebar Cover Settings", |p| {
                    p.rebar_cover = v;
                    Ok(())
                });
            }
            _ => {
                app.error("Enter a positive length for the cover.");
                ok = false;
            }
        }
    }
    if ok || cancel || !open {
        app.dialogs.rebar_cover = false;
        ctx.data_mut(|m| m.remove::<String>(id));
    } else {
        ctx.data_mut(|m| m.insert_temp(id, text));
    }
}

pub struct RenderState {
    /// Draft, Low, Medium, High, Best.
    pub quality: u8,
    /// Output resolution: Printer (dpi) rather than Screen.
    pub printer: bool,
    pub dpi: u32,
    pub image: Option<rc_core::pdf::Image>,
    pub texture: Option<egui::TextureHandle>,
}

const RENDER_QUALITY: [&str; 5] = ["Draft", "Low", "Medium", "High", "Best"];

/// The image size a render produces: the screen size scaled by quality, or a 10" x 6.25"
/// print at the chosen dpi.
fn render_size(st: &RenderState) -> (u32, u32) {
    if st.printer {
        (st.dpi * 10, st.dpi * 10 * 5 / 8)
    } else {
        let k = [0.5, 0.75, 1.0, 1.5, 2.0][st.quality.min(4) as usize];
        ((1280.0 * k) as u32, (800.0 * k) as u32)
    }
}

/// Rendering: renders the active 3D view; Save to Project or Export the image.
fn render_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.render.take() else { return };
    let Some(view) = app.active.filter(|v| app.doc.data.view(*v).is_some_and(|v| matches!(v.kind, ViewKind::ThreeD { .. }))) else {
        app.error("Rendering works in a 3D view.");
        return;
    };
    let (mut open, mut go, mut save, mut export) = (true, false, false, false);
    window("Rendering").open(&mut open).resizable(false).default_width(330.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            if dlg_button(ui, "Render", true, true) {
                go = true;
            }
            crate::style::check(ui, &mut false, "Region");
        });
        manage::group(ui, "Quality", |ui| {
            ui.horizontal(|ui| {
                ui.label("Setting:");
                egui::ComboBox::from_id_salt("render-q").selected_text(RENDER_QUALITY[st.quality.min(4) as usize]).width(150.0).show_ui(ui, |ui| {
                    for (k, q) in RENDER_QUALITY.iter().enumerate() {
                        ui.selectable_value(&mut st.quality, k as u8, *q);
                    }
                });
            });
        });
        manage::group(ui, "Output Settings", |ui| {
            ui.horizontal(|ui| {
                ui.label("Resolution:");
                ui.radio_value(&mut st.printer, false, "Screen");
                ui.radio_value(&mut st.printer, true, "Printer");
                ui.add_enabled_ui(st.printer, |ui| {
                    egui::ComboBox::from_id_salt("render-dpi").selected_text(format!("{} DPI", st.dpi)).width(80.0).show_ui(ui, |ui| {
                        for d in [75u32, 150, 300, 600] {
                            ui.selectable_value(&mut st.dpi, d, format!("{d} DPI"));
                        }
                    });
                });
            });
            let (w, h) = render_size(&st);
            ui.label(format!("Width: {w} pixels    Height: {h} pixels"));
        });
        manage::group(ui, "Lighting", |ui| {
            ui.horizontal(|ui| {
                ui.label("Scheme:");
                ui.add_enabled_ui(false, |ui| {
                    egui::ComboBox::from_id_salt("render-light").selected_text("Exterior: Sun only").width(180.0).show_ui(ui, |_| {});
                });
            });
            ui.label(format!("Sun Setting: azimuth {:.0}°, altitude {:.0}°", app.doc.data.sun.azimuth, app.doc.data.sun.altitude));
        });
        manage::group(ui, "Background", |ui| {
            ui.horizontal(|ui| {
                ui.label("Style:");
                ui.add_enabled_ui(false, |ui| {
                    egui::ComboBox::from_id_salt("render-bg").selected_text("Sky: Few Clouds").width(180.0).show_ui(ui, |_| {});
                });
            });
        });
        manage::group(ui, "Image", |ui| {
            ui.horizontal(|ui| {
                if dlg_button(ui, "Save to Project...", false, st.image.is_some()) {
                    save = true;
                }
                if dlg_button(ui, "Export...", false, st.image.is_some()) {
                    export = true;
                }
            });
        });
        if let Some(t) = &st.texture {
            let size = t.size_vec2();
            let w = ui.available_width();
            ui.add(egui::Image::new((t.id(), vec2(w, w * size.y / size.x.max(1.0)))));
        }
    });
    if go {
        let (w, h) = render_size(&st);
        match crate::view3d::render_realistic(app, view, w, h) {
            Some(img) => {
                let ci = egui::ColorImage::from_rgb([img.width as usize, img.height as usize], &img.rgb);
                st.texture = Some(ctx.load_texture("rendering", ci, egui::TextureOptions::LINEAR));
                st.image = Some(img);
            }
            None => app.error("The view could not be rendered."),
        }
    }
    if save {
        if let Some(img) = &st.image {
            // A drafting view holding the rendering, as the reference app keeps renderings.
            let base = app.doc.data.view(view).map(|v| v.name.clone()).unwrap_or_default();
            let (w, h, rgb) = (img.width, img.height, img.rgb.clone());
            let made = app.run("Save Rendering to Project", |p| {
                let name = rc_core::edit::unique_name(p.views.iter().map(|v| v.name.clone()), &format!("{base}_1"));
                let asset = p.new_id();
                p.images.push(rc_core::model::ImageAsset::from_rgb(asset, &name, w, h, &rgb));
                let vid = p.new_id();
                p.views.push(View::new(vid, name, 1.0, ViewKind::Drafting));
                rc_core::edit::add_image(p, vid, asset, rc_core::geom::DVec2::ZERO, w as f64 * 0.25)?;
                Ok(vid)
            });
            if made.is_some() {
                app.info("The rendering was saved to the project as a drafting view.");
            }
        }
    }
    if export {
        if let Some(img) = &st.image {
            if let Some(mut path) = crate::files::FileDialog::new().add_filter("PNG image", &["png"]).set_file_name("Rendering.png").save_file() {
                if path.extension().is_none() {
                    path.set_extension("png");
                }
                match std::fs::write(&path, rc_core::png::encode(img.width, img.height, 3, &img.rgb)) {
                    Ok(()) => app.info(format!("Exported {}", path.display())),
                    Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
                }
            }
        }
    }
    if open {
        app.dialogs.render = Some(st);
    }
}

pub struct InsertViewsState {
    pub src: rc_core::model::Project,
    pub views: Vec<(Id, String)>,
    pub checks: Vec<bool>,
}

/// Insert Views: pick the drafting views, legends and schedules to copy in.
fn insert_views_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.insert_views.take() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Insert Views").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Views:");
            egui::ComboBox::from_id_salt("iv-filter").selected_text("Show all views and sheets").width(260.0).show_ui(ui, |ui| {
                let _ = ui.selectable_label(true, "Show all views and sheets");
            });
        });
        ui.add_space(4.0);
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::vertical().max_height(300.0).show(ui, |ui| {
                for (k, (_, name)) in st.views.iter().enumerate() {
                    crate::style::check(ui, &mut st.checks[k], name.as_str());
                }
            });
        });
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            if ui.button("Check All").clicked() {
                st.checks.iter_mut().for_each(|c| *c = true);
            }
            if ui.button("Check None").clicked() {
                st.checks.iter_mut().for_each(|c| *c = false);
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, st.checks.iter().any(|c| *c)) {
                ok = true;
            }
        });
    });
    if ok {
        let ids: Vec<Id> = st.views.iter().zip(&st.checks).filter(|(_, c)| **c).map(|(v, _)| v.0).collect();
        let src = &st.src;
        let mut made = Vec::new();
        app.run("Insert Views from File", |p| {
            made = rc_core::transfer::insert_views(p, src, &ids);
            Ok(())
        });
        app.info(format!("Inserted {} view(s).", made.len()));
        return;
    }
    if !(cancel || !open) {
        app.dialogs.insert_views = Some(st);
    }
}

pub struct SharedParamsState {
    pub path: String,
    pub file: rc_core::shared_params::SharedParamFile,
    pub group: Option<u32>,
    pub sel: Option<usize>,
    pub sub: Option<SharedSub>,
}

/// The small dialogs over Edit Shared Parameters.
#[derive(Clone)]
pub enum SharedSub {
    /// Parameter Properties: the parameter being edited (None = new), name, kind, tooltip.
    Param(Option<usize>, String, ParamKind, String),
    NewGroup(String),
    RenameGroup(String),
}

/// Edit Shared Parameters: the shared parameter file's groups and parameters.
fn shared_params_dialog(app: &mut App, ctx: &egui::Context) {
    use rc_core::shared_params::{SharedParam, SharedParamFile};
    let Some(mut st) = app.dialogs.shared_params.take() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Edit Shared Parameters").open(&mut open).resizable(false).default_width(520.0).show(ctx, |ui| {
        ui.label("Shared parameter file:");
        ui.horizontal(|ui| {
            ui.add(egui::TextEdit::singleline(&mut st.path).desired_width(300.0));
            if ui.button("Browse...").clicked() {
                if let Some(f) = crate::files::FileDialog::new().add_filter("Shared Parameter Files", &["txt"]).pick_file() {
                    match std::fs::read_to_string(&f).map_err(|e| e.to_string()).and_then(|t| SharedParamFile::parse(&t)) {
                        Ok(file) => {
                            st.path = f.display().to_string();
                            st.group = file.groups.first().map(|g| g.0);
                            st.file = file;
                            st.sel = None;
                        }
                        Err(e) => app.error(format!("The shared parameter file could not be read: {e}")),
                    }
                }
            }
            if ui.button("Create...").clicked() {
                if let Some(f) = crate::files::FileDialog::new().add_filter("Shared Parameter Files", &["txt"]).set_file_name("SharedParameters.txt").save_file() {
                    st.path = f.display().to_string();
                    st.file = SharedParamFile::default();
                    st.group = None;
                    st.sel = None;
                }
            }
        });
        ui.add_space(6.0);
        let has_file = !st.path.trim().is_empty();
        ui.add_enabled_ui(has_file, |ui| {
            ui.horizontal_top(|ui| {
                ui.vertical(|ui| {
                    ui.set_width(320.0);
                    ui.label("Parameter group:");
                    let gname = st.group.and_then(|g| st.file.groups.iter().find(|x| x.0 == g)).map(|x| x.1.clone()).unwrap_or_default();
                    egui::ComboBox::from_id_salt("sp-group").selected_text(gname).width(310.0).show_ui(ui, |ui| {
                        for (gid, name) in st.file.groups.clone() {
                            if ui.selectable_label(st.group == Some(gid), &name).clicked() {
                                st.group = Some(gid);
                                st.sel = None;
                            }
                        }
                    });
                    ui.add_space(4.0);
                    ui.label("Parameters:");
                    egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
                        ui.set_width(310.0);
                        ui.set_min_height(220.0);
                        egui::ScrollArea::vertical().max_height(220.0).show(ui, |ui| {
                            for (k, prm) in st.file.params.iter().enumerate() {
                                if Some(prm.group) == st.group && ui.selectable_label(st.sel == Some(k), &prm.name).clicked() {
                                    st.sel = Some(k);
                                }
                            }
                        });
                    });
                });
                ui.vertical(|ui| {
                    ui.label(egui::RichText::new("Parameters").strong());
                    let w = vec2(130.0, 22.0);
                    if ui.add_enabled(st.group.is_some(), egui::Button::new("New...").min_size(w)).clicked() {
                        st.sub = Some(SharedSub::Param(None, String::new(), ParamKind::Text, String::new()));
                    }
                    if ui.add_enabled(st.sel.is_some(), egui::Button::new("Properties...").min_size(w)).clicked() {
                        if let Some(k) = st.sel {
                            let prm = &st.file.params[k];
                            st.sub = Some(SharedSub::Param(Some(k), prm.name.clone(), prm.kind, prm.description.clone()));
                        }
                    }
                    if ui.add_enabled(st.sel.is_some(), egui::Button::new("Delete").min_size(w)).clicked() {
                        if let Some(k) = st.sel.take() {
                            st.file.params.remove(k);
                        }
                    }
                    ui.add_space(10.0);
                    ui.label(egui::RichText::new("Groups").strong());
                    if ui.add(egui::Button::new("New...").min_size(w)).clicked() {
                        st.sub = Some(SharedSub::NewGroup(String::new()));
                    }
                    if ui.add_enabled(st.group.is_some(), egui::Button::new("Rename...").min_size(w)).clicked() {
                        let name = st.group.and_then(|g| st.file.groups.iter().find(|x| x.0 == g)).map(|x| x.1.clone()).unwrap_or_default();
                        st.sub = Some(SharedSub::RenameGroup(name));
                    }
                    let empty = st.group.is_some_and(|g| !st.file.params.iter().any(|x| x.group == g));
                    if ui.add_enabled(empty, egui::Button::new("Delete").min_size(w)).on_disabled_hover_text("Only an empty group can be deleted.").clicked() {
                        if let Some(g) = st.group {
                            st.file.groups.retain(|x| x.0 != g);
                            st.group = st.file.groups.first().map(|x| x.0);
                        }
                    }
                });
            });
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            let _ = dlg_button(ui, "Help", false, false);
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    // Sub-dialogs.
    if let Some(sub) = st.sub.clone() {
        let (mut sopen, mut sok, mut scancel) = (true, false, false);
        let title = match &sub {
            SharedSub::Param(..) => "Parameter Properties",
            SharedSub::NewGroup(_) => "New Parameter Group",
            SharedSub::RenameGroup(_) => "Rename Parameter Group",
        };
        let mut next = sub.clone();
        window(title).open(&mut sopen).resizable(false).default_width(320.0).show(ctx, |ui| {
            match &mut next {
                SharedSub::Param(edit, name, kind, tip) => {
                    egui::Grid::new("sp-param").num_columns(2).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
                        ui.label("Name:");
                        ui.add(egui::TextEdit::singleline(name).desired_width(200.0));
                        ui.end_row();
                        ui.label("Discipline:");
                        ui.add_enabled_ui(false, |ui| {
                            egui::ComboBox::from_id_salt("sp-disc").selected_text("Common").width(200.0).show_ui(ui, |_| {});
                        });
                        ui.end_row();
                        ui.label("Type of Parameter:");
                        ui.add_enabled_ui(edit.is_none(), |ui| {
                            egui::ComboBox::from_id_salt("sp-kind").selected_text(kind.label()).width(200.0).show_ui(ui, |ui| {
                                for k in ParamKind::USER {
                                    ui.selectable_value(kind, k, k.label());
                                }
                            });
                        });
                        ui.end_row();
                        ui.label("Tooltip Description:");
                        ui.add(egui::TextEdit::singleline(tip).desired_width(200.0));
                        ui.end_row();
                    });
                }
                SharedSub::NewGroup(name) | SharedSub::RenameGroup(name) => {
                    ui.label("Name:");
                    ui.add(egui::TextEdit::singleline(name).desired_width(280.0));
                }
            }
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                if dlg_button(ui, "Cancel", false, true) {
                    scancel = true;
                }
                if dlg_button(ui, "OK", true, true) {
                    sok = true;
                }
            });
        });
        st.sub = Some(next.clone());
        if sok {
            let taken = |n: &str, skip: Option<usize>| st.file.params.iter().enumerate().any(|(k, x)| x.name == n && Some(k) != skip);
            match next {
                SharedSub::Param(_, ref name, ..) if name.trim().is_empty() => app.error("Enter a parameter name."),
                SharedSub::Param(edit, name, kind, tip) => {
                    let name = name.trim().to_string();
                    if taken(&name, edit) {
                        app.error(format!("A parameter named \"{name}\" already exists in the shared parameter file."));
                    } else {
                        match edit {
                            Some(k) => {
                                st.file.params[k].name = name;
                                st.file.params[k].description = tip;
                            }
                            None => {
                                st.file.params.push(SharedParam { guid: SharedParamFile::new_guid(), name, kind, group: st.group.unwrap_or(1), visible: true, description: tip, user_modifiable: true, hide_when_no_value: false });
                                st.sel = Some(st.file.params.len() - 1);
                            }
                        }
                        st.sub = None;
                    }
                }
                SharedSub::NewGroup(name) if !name.trim().is_empty() => {
                    let id = st.file.next_group_id();
                    st.file.groups.push((id, name.trim().to_string()));
                    st.group = Some(id);
                    st.sub = None;
                }
                SharedSub::RenameGroup(name) if !name.trim().is_empty() => {
                    if let Some(g) = st.group.and_then(|g| st.file.groups.iter_mut().find(|x| x.0 == g)) {
                        g.1 = name.trim().to_string();
                    }
                    st.sub = None;
                }
                _ => app.error("Enter a group name."),
            }
        } else if scancel || !sopen {
            st.sub = None;
        }
    }
    if ok {
        if !st.path.trim().is_empty() {
            match std::fs::write(&st.path, st.file.to_text()) {
                Ok(()) => {
                    app.settings.shared_params_path = st.path.clone();
                    app.settings_dirty = true;
                }
                Err(e) => {
                    app.error(format!("The shared parameter file could not be saved: {e}"));
                    app.dialogs.shared_params = Some(st);
                    return;
                }
            }
        }
        return;
    }
    if !(cancel || !open) {
        app.dialogs.shared_params = Some(st);
    }
}

pub struct TransferState {
    pub name: String,
    pub src: rc_core::model::Project,
    pub checks: Vec<bool>,
    /// The Duplicate Types list once OK found items the project already has.
    pub duplicates: Option<Vec<String>>,
}

/// Select Items To Copy, then Duplicate Types (Overwrite / New Only / Cancel).
fn transfer_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.transfer.take() else { return };
    let items = rc_core::transfer::STANDARDS;
    let chosen = |st: &TransferState| -> Vec<&'static str> { items.iter().zip(&st.checks).filter(|(_, c)| **c).map(|(i, _)| *i).collect() };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    let mut run: Option<bool> = None;
    if let Some(dups) = st.duplicates.clone() {
        window("Duplicate Types").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
            ui.label("The following types already exist in the destination project but are different:");
            egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
                ui.set_width(ui.available_width());
                egui::ScrollArea::vertical().max_height(200.0).show(ui, |ui| {
                    for d in &dups {
                        ui.label(d);
                    }
                });
            });
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                if dlg_button(ui, "Cancel", false, true) {
                    cancel = true;
                }
                if dlg_button(ui, "New Only", false, true) {
                    run = Some(false);
                }
                if dlg_button(ui, "Overwrite", true, true) {
                    run = Some(true);
                }
            });
        });
    } else {
        window("Select Items To Copy").open(&mut open).resizable(false).default_width(360.0).show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label("Copy from:");
                egui::ComboBox::from_id_salt("transfer-from").selected_text(&st.name).width(240.0).show_ui(ui, |ui| {
                    let _ = ui.selectable_label(true, &st.name);
                });
            });
            ui.add_space(4.0);
            egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
                ui.set_width(ui.available_width());
                egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
                    for (k, item) in items.iter().enumerate() {
                        crate::style::check(ui, &mut st.checks[k], *item);
                    }
                });
            });
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                if ui.button("Check All").clicked() {
                    st.checks.iter_mut().for_each(|c| *c = true);
                }
                if ui.button("Check None").clicked() {
                    st.checks.iter_mut().for_each(|c| *c = false);
                }
            });
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                if dlg_button(ui, "Cancel", false, true) {
                    cancel = true;
                }
                if dlg_button(ui, "OK", true, st.checks.iter().any(|c| *c)) {
                    ok = true;
                }
            });
        });
    }
    if ok {
        let dups = rc_core::transfer::duplicates(&app.doc.data, &st.src, &chosen(&st));
        if dups.is_empty() {
            run = Some(false);
        } else {
            st.duplicates = Some(dups);
        }
    }
    if let Some(overwrite) = run {
        let what = chosen(&st);
        let src = &st.src;
        let mut copied = 0;
        app.run("Transfer Project Standards", |p| {
            copied = rc_core::transfer::transfer_standards(p, src, &what, overwrite);
            Ok(())
        });
        app.info(format!("Copied {copied} item(s) from {}.", st.name));
        return;
    }
    if !(cancel || !open) {
        app.dialogs.transfer = Some(st);
    }
}

/// Starting View: the view shown when the project opens.
fn starting_view_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.starting_view {
        return;
    }
    let id = egui::Id::new("starting-view");
    let mut pick: Option<Id> = ctx.data(|m| m.get_temp(id)).unwrap_or(app.doc.data.starting_view);
    let label = |v: &View| format!("{}: {}", v.type_label(), v.name);
    let mut views: Vec<(Id, String)> = app.doc.data.views.iter().filter(|v| !v.is_template).map(|v| (v.id, label(v))).collect();
    views.sort_by(|a, b| a.1.cmp(&b.1));
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Starting View").open(&mut open).resizable(false).default_width(340.0).show(ctx, |ui| {
        ui.label("Specify the view that will be displayed when this project is opened:");
        ui.add_space(4.0);
        let current = pick.and_then(|p| views.iter().find(|v| v.0 == p)).map(|v| v.1.clone()).unwrap_or_else(|| "<Last Viewed>".into());
        egui::ComboBox::from_id_salt("starting-view-combo").selected_text(current).width(310.0).show_ui(ui, |ui| {
            ui.selectable_value(&mut pick, None, "<Last Viewed>");
            for (vid, name) in &views {
                ui.selectable_value(&mut pick, Some(*vid), name);
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(id, pick));
    if ok && pick != app.doc.data.starting_view {
        app.run("Starting View", |p| {
            p.starting_view = pick;
            Ok(())
        });
    }
    if ok || cancel || !open {
        app.dialogs.starting_view = false;
        ctx.data_mut(|m| m.remove::<Option<Id>>(id));
    }
}

/// Location, Weather and Site: the project's place on earth and its angle to true north.
fn location_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.location {
        return;
    }
    #[derive(Clone)]
    struct St {
        tab: u8,
        lat: String,
        lon: String,
        zone: f64,
        address: String,
        angle: String,
        east: bool,
    }
    let id = egui::Id::new("location-dialog");
    let p0 = &app.doc.data;
    let mut st: St = ctx.data(|m| m.get_temp(id)).unwrap_or_else(|| St {
        tab: app.dialogs.location_tab,
        lat: format!("{:.6}", p0.sun.latitude),
        lon: format!("{:.6}", p0.sun.longitude),
        zone: (p0.sun.longitude / 15.0).round(),
        address: p0.info.address.clone(),
        angle: format!("{:.2}", p0.true_north.abs()),
        east: p0.true_north >= 0.0,
    });
    // A few cities for "Default City List", as the reference app offers.
    const CITIES: [(&str, f64, f64, f64); 10] = [
        ("Boston, MA", 42.3584, -71.0598, -5.0),
        ("Chicago, IL", 41.8756, -87.6244, -6.0),
        ("Dubai, United Arab Emirates", 25.2697, 55.3094, 4.0),
        ("London, United Kingdom", 51.5072, -0.1276, 0.0),
        ("Los Angeles, CA", 34.0522, -118.2437, -8.0),
        ("New York, NY", 40.7128, -74.006, -5.0),
        ("Paris, France", 48.8566, 2.3522, 1.0),
        ("San Francisco, CA", 37.7749, -122.4194, -8.0),
        ("Sydney, Australia", -33.8688, 151.2093, 10.0),
        ("Tokyo, Japan", 35.6762, 139.6503, 9.0),
    ];
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Location Weather and Site").open(&mut open).resizable(false).default_width(470.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            for (k, t) in ["Location", "Weather", "Site"].iter().enumerate() {
                if ui.selectable_label(st.tab == k as u8, *t).clicked() {
                    st.tab = k as u8;
                }
            }
        });
        ui.separator();
        ui.set_min_height(230.0);
        match st.tab {
            0 => {
                ui.horizontal(|ui| {
                    ui.label("Define Location by:");
                    egui::ComboBox::from_id_salt("loc-by").selected_text("Default City List").width(200.0).show_ui(ui, |ui| {
                        let _ = ui.selectable_label(true, "Default City List");
                    });
                });
                ui.add_space(6.0);
                egui::Grid::new("loc-grid").num_columns(2).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
                    ui.label("City:");
                    let city = CITIES.iter().find(|c| (c.1 - st.lat.parse::<f64>().unwrap_or(f64::NAN)).abs() < 1e-3 && (c.2 - st.lon.parse::<f64>().unwrap_or(f64::NAN)).abs() < 1e-3).map(|c| c.0).unwrap_or("<User Defined>");
                    egui::ComboBox::from_id_salt("loc-city").selected_text(city).width(260.0).show_ui(ui, |ui| {
                        for c in CITIES {
                            if ui.selectable_label(c.0 == city, c.0).clicked() {
                                st.lat = format!("{:.6}", c.1);
                                st.lon = format!("{:.6}", c.2);
                                st.zone = c.3;
                            }
                        }
                    });
                    ui.end_row();
                    ui.label("Latitude:");
                    ui.add(egui::TextEdit::singleline(&mut st.lat).desired_width(120.0));
                    ui.end_row();
                    ui.label("Longitude:");
                    ui.add(egui::TextEdit::singleline(&mut st.lon).desired_width(120.0));
                    ui.end_row();
                    ui.label("Time Zone:");
                    let zl = |z: f64| format!("(UTC{}{:02}:00)", if z < 0.0 { "-" } else { "+" }, z.abs() as i32);
                    egui::ComboBox::from_id_salt("loc-zone").selected_text(zl(st.zone)).width(260.0).show_ui(ui, |ui| {
                        for z in -12..=14 {
                            ui.selectable_value(&mut st.zone, z as f64, zl(z as f64));
                        }
                    });
                    ui.end_row();
                    ui.label("Project Address:");
                    ui.add(egui::TextEdit::singleline(&mut st.address).desired_width(260.0));
                    ui.end_row();
                });
            }
            1 => {
                ui.label("Cooling Design Temperatures and Heating Design Temperature come from the");
                ui.label("closest weather station to the project location.");
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, "Use closest weather station"));
            }
            _ => {
                ui.label("Define a site for each unique location in this project.");
                egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
                    ui.set_width(ui.available_width());
                    let _ = ui.selectable_label(true, "Internal (current)");
                });
                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    ui.label("Angle from Project North to True North:");
                    ui.add(egui::TextEdit::singleline(&mut st.angle).desired_width(70.0));
                    ui.label("°");
                    egui::ComboBox::from_id_salt("loc-ew").selected_text(if st.east { "East" } else { "West" }).width(70.0).show_ui(ui, |ui| {
                        ui.selectable_value(&mut st.east, true, "East");
                        ui.selectable_value(&mut st.east, false, "West");
                    });
                });
            }
        }
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            let _ = dlg_button(ui, "Help", false, false);
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        let (lat, lon, ang) = (st.lat.trim().parse::<f64>(), st.lon.trim().parse::<f64>(), st.angle.trim().parse::<f64>());
        match (lat, lon, ang) {
            (Ok(lat), Ok(lon), Ok(ang)) if lat.abs() <= 90.0 && lon.abs() <= 180.0 => {
                let (addr, angle) = (st.address.clone(), if st.east { ang } else { -ang });
                app.run("Location", |p| {
                    p.sun.latitude = lat;
                    p.sun.longitude = lon;
                    p.info.address = addr;
                    p.true_north = angle;
                    Ok(())
                });
            }
            _ => {
                app.error("Enter a latitude between -90 and 90, a longitude between -180 and 180 and an angle in degrees.");
                ok = false;
            }
        }
    }
    if ok || cancel || !open {
        app.dialogs.location = false;
        ctx.data_mut(|m| m.remove::<St>(id));
    } else {
        ctx.data_mut(|m| m.insert_temp(id, st));
    }
}

/// Specify Shared Coordinates: the clicked point's shared position and the angle to true north.
fn specify_coords_dialog(app: &mut App, ctx: &egui::Context) {
    let Some((pt, mut f)) = app.dialogs.specify_coords.clone() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Specify Shared Coordinates").open(&mut open).resizable(false).default_width(360.0).show(ctx, |ui| {
        ui.label("Relocate this project in Shared Coordinates by specifying known values at the current point.");
        ui.add_space(6.0);
        egui::Grid::new("spec-coords").num_columns(2).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
            for (k, l) in ["North/South:", "East/West:", "Elevation:", "Angle from Project North to True North (East):"].iter().enumerate() {
                ui.label(*l);
                ui.add(egui::TextEdit::singleline(&mut f[k]).desired_width(110.0));
                ui.end_row();
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        let u = app.doc.data.units.clone();
        let len = |t: &str| u.parse(t, ParamKind::Length);
        match (len(&f[0]), len(&f[1]), len(&f[2]), f[3].trim().trim_end_matches('°').parse::<f64>()) {
            (Some(n), Some(e), Some(z), Ok(a)) => {
                app.run("Specify Coordinates", |p| {
                    p.specify_shared(pt, n, e, z, a);
                    Ok(())
                });
                app.dialogs.specify_coords = None;
            }
            _ => app.error("Enter lengths for North/South, East/West and Elevation, and an angle in degrees."),
        }
    } else if cancel || !open {
        app.dialogs.specify_coords = None;
    } else {
        app.dialogs.specify_coords = Some((pt, f));
    }
}

/// Model Text's "Edit Text": the text to place (several lines allowed).
fn model_text_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut text) = app.dialogs.model_text.clone() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Edit Text").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        let r = ui.add(egui::TextEdit::multiline(&mut text).desired_rows(6).desired_width(350.0));
        if !r.has_focus() && text.is_empty() {
            r.request_focus();
        }
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, !text.trim().is_empty()) {
                ok = true;
            }
        });
    });
    if ok {
        app.dialogs.model_text = None;
        app.opts.model_text = text;
        app.set_tool(crate::tools::ToolKind::ModelText);
        return;
    }
    app.dialogs.model_text = if cancel || !open { None } else { Some(text) };
}

/// File > Print: printer (PDF), file, print range and settings, as in the reference app.
fn print_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.print_dialog {
        return;
    }
    let candidates: Vec<(Id, String)> = app
        .doc
        .data
        .views
        .iter()
        .filter(|v| !v.is_template && (matches!(v.kind, ViewKind::Sheet(_)) || (v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. }))))
        .map(|v| (v.id, match &v.kind {
            ViewKind::Sheet(s) => format!("Sheet: {} - {}", s.number, v.name),
            _ => format!("{}: {}", v.type_label(), v.name),
        }))
        .collect();
    let (mut open, mut ok, mut close, mut preview, mut setup) = (true, false, false, false, false);
    window("Print").open(&mut open).resizable(false).default_width(480.0).show(ctx, |ui| {
        ui.label(egui::RichText::new("Printer").strong());
        ui.horizontal(|ui| {
            ui.label("Name:");
            egui::ComboBox::from_id_salt("print-printer").selected_text("PDF (vector)").width(300.0).show_ui(ui, |ui| {
                let _ = ui.selectable_label(true, "PDF (vector)");
            });
        });
        ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, "Print to file"));
        ui.add_space(4.0);
        ui.label(egui::RichText::new("File").strong());
        ui.radio_value(&mut app.dialogs.pdf_separate, false, "Combine multiple selected views/sheets into a single file");
        ui.radio_value(&mut app.dialogs.pdf_separate, true, "Create separate files. View/sheet names will be appended to the specified name");
        ui.add_space(4.0);
        ui.label(egui::RichText::new("Print Range").strong());
        ui.radio_value(&mut app.dialogs.print_selected, false, "Current window");
        ui.radio_value(&mut app.dialogs.print_selected, true, "Selected views/sheets");
        if app.dialogs.print_selected {
            egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
                egui::ScrollArea::vertical().max_height(180.0).show(ui, |ui| {
                    ui.set_min_width(430.0);
                    for (id, label) in &candidates {
                        let mut on = app.dialogs.export_sel.contains(id);
                        if crate::style::check(ui, &mut on, label).changed() {
                            if on {
                                app.dialogs.export_sel.insert(*id);
                            } else {
                                app.dialogs.export_sel.remove(id);
                            }
                        }
                    }
                });
            });
        }
        ui.add_space(4.0);
        ui.label(egui::RichText::new("Settings").strong());
        ui.horizontal(|ui| {
            ui.label(format!("Default ({}, {})", app.dialogs.print.paper.map(|s| s.label()).unwrap_or("sheet size"), app.dialogs.print.colors.label()));
            if dlg_button(ui, "Setup...", false, true) {
                setup = true;
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Close", false, true) {
                close = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
            if dlg_button(ui, "Preview", false, true) {
                preview = true;
            }
        });
    });
    if setup {
        app.dialogs.print_setup = true;
    }
    if preview {
        app.dialogs.print_preview = app.active;
    }
    if ok {
        let ids: Vec<Id> = if app.dialogs.print_selected { app.dialogs.export_sel.iter().copied().collect() } else { app.active.into_iter().collect() };
        app.dialogs.print_dialog = false;
        app.dialogs.export_sel.clear();
        if ids.is_empty() {
            app.error("Select the views and sheets to print.");
        } else {
            export_pdf(app, &ids);
        }
    }
    if close || !open {
        app.dialogs.print_dialog = false;
    }
}

/// File > Print Setup.
fn print_setup_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.print_setup {
        return;
    }
    let id = egui::Id::new("print-setup-edit");
    let mut st: rc_core::sheet::PrintSettings = ctx.data(|m| m.get_temp(id)).unwrap_or_else(|| app.dialogs.print.clone());
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Print Setup").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Printer:");
            ui.label("PDF (vector)");
        });
        ui.horizontal(|ui| {
            ui.label("Name:");
            ui.label("<in-session>");
        });
        ui.separator();
        print_settings_ui(ui, &mut st);
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(id, st.clone()));
    if ok {
        app.dialogs.print = st;
    }
    if ok || cancel || !open {
        app.dialogs.print_setup = false;
        ctx.data_mut(|m| m.remove::<rc_core::sheet::PrintSettings>(id));
    }
}

/// File > Print Preview: the page as it will print.
fn print_preview(app: &mut App, ctx: &egui::Context) {
    let Some(view_id) = app.dialogs.print_preview else { return };
    let fp = app.footprints();
    let Some(view) = app.doc.data.view(view_id).cloned() else {
        app.dialogs.print_preview = None;
        return;
    };
    let Some((page, prims)) = rc_core::sheet::print_layout(&app.doc.data, &view, &fp, &app.dialogs.print) else {
        app.error("This view cannot be printed.");
        app.dialogs.print_preview = None;
        return;
    };
    let (mut open, mut print, mut close) = (true, false, false);
    window("Print Preview").open(&mut open).default_size(vec2(760.0, 600.0)).resizable(true).show(ctx, |ui| {
        ui.horizontal(|ui| {
            if dlg_button(ui, "Print...", false, true) {
                print = true;
            }
            if dlg_button(ui, "Close", false, true) {
                close = true;
            }
            ui.label(format!("{} x {} mm", page.x.round(), page.y.round()));
        });
        let avail = ui.available_size().max(vec2(400.0, 300.0));
        let (rect, _) = ui.allocate_exact_size(avail, egui::Sense::hover());
        ui.painter().rect_filled(rect, 0.0, egui::Color32::from_gray(128));
        let zoom = ((rect.width() as f64 - 24.0) / page.x).min((rect.height() as f64 - 24.0) / page.y);
        let xf = crate::canvas::Xf { rect, center: page / 2.0, zoom, scale: 1.0, thin: false };
        let painter = ui.painter_at(rect);
        painter.rect_filled(egui::Rect::from_two_pos(xf.s(rc_core::geom::DVec2::ZERO), xf.s(page)), 0.0, egui::Color32::WHITE);
        for prim in &prims {
            match prim {
                rc_core::sheet::SheetPrim::Line { pts, closed, width, color, dash, .. } => {
                    let v: Vec<egui::Pos2> = pts.iter().map(|q| xf.s(*q)).collect();
                    crate::canvas::paint_polyline(&painter, &v, *closed, egui::Stroke::new((*width as f64 * zoom) as f32 * 0.9 + 0.3, egui::Color32::from_rgb(color[0], color[1], color[2])), *dash, &xf);
                }
                rc_core::sheet::SheetPrim::Fill { tris, color, .. } => {
                    let mut mesh = egui::Mesh::default();
                    let c = egui::Color32::from_rgba_unmultiplied(color[0], color[1], color[2], color[3]);
                    for t in tris {
                        let i = mesh.vertices.len() as u32;
                        for q in t {
                            mesh.colored_vertex(xf.s(*q), c);
                        }
                        mesh.add_triangle(i, i + 1, i + 2);
                    }
                    painter.add(egui::Shape::mesh(mesh));
                }
                rc_core::sheet::SheetPrim::Text { pos, text, size, anchor, angle, bold, .. } => {
                    crate::canvas::paint_text_ex(&painter, xf.s(*pos), text, (*size as f64 * zoom) as f32, egui::Color32::BLACK, *anchor, *angle, *bold);
                }
                rc_core::sheet::SheetPrim::Picture { asset, min, max, .. } => {
                    if let Some(t) = crate::images::texture(*asset) {
                        painter.image(t, egui::Rect::from_two_pos(xf.s(*min), xf.s(*max)), egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)), egui::Color32::WHITE);
                    }
                }
                rc_core::sheet::SheetPrim::Image { min, max, .. } => {
                    painter.rect_filled(egui::Rect::from_two_pos(xf.s(*min), xf.s(*max)), 0.0, egui::Color32::from_gray(225));
                }
            }
        }
    });
    if print {
        app.dialogs.print_preview = None;
        app.dialogs.print_dialog = true;
    }
    if close || !open {
        app.dialogs.print_preview = None;
    }
}

fn safe_name(s: &str) -> String {
    s.chars().map(|c| if c.is_alphanumeric() || c == '-' || c == '_' || c == ' ' { c } else { '_' }).collect::<String>().trim().to_string()
}

fn export_dxf(app: &mut App, ids: &[Id]) {
    let layers = app.dialogs.dxf_layers;
    let fp = app.footprints();
    let p = app.doc.data.clone();
    if ids.len() == 1 {
        let v = p.view(ids[0]).unwrap();
        let Some(path) = crate::files::FileDialog::new().add_filter("DXF", &["dxf"]).set_file_name(format!("{}.dxf", safe_name(&v.name))).save_file() else { return };
        let text = match &v.kind {
            ViewKind::Sheet(_) => Some(rc_core::dxf::export_sheet_with(&p, v, &fp, layers)),
            _ => rc_core::dxf::export_view_with(&p, v, &fp, layers),
        };
        match text.map(|t| std::fs::write(&path, t)) {
            Some(Ok(())) => app.info(format!("Exported {}", path.display())),
            Some(Err(e)) => app.error(format!("Could not write {}: {e}", path.display())),
            None => app.error("This view cannot be exported to DXF."),
        }
        return;
    }
    let Some(dir) = crate::files::FileDialog::new().set_title("Choose a folder for the DXF files").pick_folder() else { return };
    let mut n = 0;
    for id in ids {
        let Some(v) = p.view(*id) else { continue };
        let text = match &v.kind {
            ViewKind::Sheet(s) => Some((rc_core::dxf::export_sheet_with(&p, v, &fp, layers), format!("{} - {}", s.number, v.name))),
            _ => rc_core::dxf::export_view_with(&p, v, &fp, layers).map(|t| (t, format!("{} - {}", v.type_label(), v.name))),
        };
        if let Some((t, name)) = text {
            if std::fs::write(dir.join(format!("{}.dxf", safe_name(&name))), t).is_ok() {
                n += 1;
            }
        }
    }
    app.info(format!("Exported {n} DXF file(s) to {}", dir.display()));
}

/// One PDF page per view or sheet, with the export settings applied.
fn pdf_pages(app: &mut App, ids: &[Id]) -> Vec<(String, rc_core::pdf::Page)> {
    let fp = app.footprints();
    let data = app.doc.data.clone();
    let settings = app.dialogs.print.clone();
    let mut pages = Vec::new();
    for id in ids {
        let Some(view) = data.view(*id).cloned() else { continue };
        match &view.kind {
            ViewKind::Sheet(s) => {
                let name = format!("{} - {}", s.number, view.name);
                let mut render = |vid: Id, w: u32, h: u32| crate::view3d::render_image(app, vid, w, h);
                pages.push((name, rc_core::sheet::to_pdf_page_with(&data, &view, &fp, &mut render, &settings)));
            }
            _ => {
                if let Some(pg) = rc_core::sheet::view_to_pdf_page_with(&data, &view, &fp, &settings) {
                    pages.push((format!("{} - {}", view.type_label(), view.name), pg));
                }
            }
        }
    }
    pages
}

fn export_pdf(app: &mut App, ids: &[Id]) {
    let combine = !app.dialogs.pdf_separate || ids.len() == 1;
    if combine {
        let Some(path) = crate::files::FileDialog::new().add_filter("PDF", &["pdf"]).set_file_name(format!("{}.pdf", safe_name(&app.doc.data.info.name))).save_file() else { return };
        let pages: Vec<rc_core::pdf::Page> = pdf_pages(app, ids).into_iter().map(|p| p.1).collect();
        if pages.is_empty() {
            app.error("Nothing to export.");
            return;
        }
        let bytes = rc_core::pdf::write(pages, &app.doc.data.info.name);
        match std::fs::write(&path, bytes) {
            Ok(()) => app.info(format!("Exported {}", path.display())),
            Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
        }
        return;
    }
    // Separate files, named after each view or sheet.
    let Some(dir) = crate::files::FileDialog::new().set_title("Choose a folder for the PDF files").pick_folder() else { return };
    let project = app.doc.data.info.name.clone();
    let mut n = 0;
    for (name, page) in pdf_pages(app, ids) {
        let file = dir.join(format!("{} - {}.pdf", safe_name(&project), safe_name(&name)));
        if std::fs::write(&file, rc_core::pdf::write(vec![page], &name)).is_ok() {
            n += 1;
        }
    }
    app.info(format!("Exported {n} PDF file(s) to {}", dir.display()));
}

/// Rasterises a 2D drawing to RGB (simple scanline renderer for image export).
pub(crate) fn raster_2d(app: &mut App, view: &View, width: u32) -> Option<rc_core::pdf::Image> {
    let d = app.drawing(view.id);
    let (mn, mx) = d.bounds()?;
    let size = (mx - mn) * 1.06;
    let scale = width as f64 / size.x.max(1.0);
    let height = ((size.y * scale) as u32).clamp(16, 8000);
    let origin = (mn + mx) / 2.0 - size / 2.0;
    let mut img = tiny_raster::Canvas::new(width, height);
    for (_, prim) in &d.prims {
        match prim {
            rc_core::plan::Prim::Image { asset, min, max } => {
                // Nearest-pixel sampling of the image over its rectangle.
                let Some(a) = app.doc.data.images.iter().find(|a| a.id == *asset) else { continue };
                let Some(rgb) = a.rgb() else { continue };
                let (x0, x1) = ((min.x - origin.x) * scale, (max.x - origin.x) * scale);
                let (y0, y1) = ((size.y - (max.y - origin.y)) * scale, (size.y - (min.y - origin.y)) * scale);
                for y in (y0.max(0.0) as u32)..(y1.min(height as f64) as u32) {
                    for x in (x0.max(0.0) as u32)..(x1.min(width as f64) as u32) {
                        let u = (((x as f64 - x0) / (x1 - x0)) * a.width as f64) as u32;
                        let v = (((y as f64 - y0) / (y1 - y0)) * a.height as f64) as u32;
                        let si = ((v.min(a.height - 1) * a.width + u.min(a.width - 1)) * 3) as usize;
                        let di = ((y * width + x) * 3) as usize;
                        img.rgb[di..di + 3].copy_from_slice(&rgb[si..si + 3]);
                    }
                }
            }
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
    let Some(mut path) = crate::files::FileDialog::new().add_filter("PNG image", &["png"]).set_file_name(format!("{}.png", safe_name(&view.name))).save_file() else { return };
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

/// Connect Levels: the stair repeats storey by storey up to the chosen level.
fn connect_levels_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.connect_levels {
        return;
    }
    let p = &app.doc.data;
    let from = app.opts.stair_top.or_else(|| app.sketch.as_ref().and_then(|s| p.level_above(s.level).map(|l| l.0)));
    let from_z = from.map(|l| p.level_elevation(l)).unwrap_or(f64::MAX);
    let above: Vec<(Id, String)> = p.levels().iter().filter(|(_, l)| l.elevation > from_z + 1.0).map(|(id, l)| (*id, l.name.clone())).collect();
    let id = egui::Id::new("connect-levels");
    let mut pick: Option<Id> = ctx.data(|m| m.get_temp(id)).unwrap_or(app.opts.stair_multistory_top);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Connect Levels").open(&mut open).resizable(false).default_width(320.0).show(ctx, |ui| {
        if above.is_empty() {
            ui.label("There are no levels above the stair's top level to connect.");
        } else {
            ui.label("Repeat the stair up to:");
            egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
                ui.set_min_width(280.0);
                ui.selectable_value(&mut pick, None, "None (single storey)");
                for (l, n) in &above {
                    ui.selectable_value(&mut pick, Some(*l), n);
                }
            });
        }
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(id, pick));
    if ok {
        app.opts.stair_multistory_top = pick;
    }
    if ok || cancel || !open {
        app.dialogs.connect_levels = false;
        ctx.data_mut(|m| m.remove::<Option<Id>>(id));
    }
}

fn cancel_stair_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.cancel_stair {
        return;
    }
    let (mut open, mut yes, mut no) = (true, false, false);
    window("Cancel Editing Stair Element").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        ui.label(egui::RichText::new("You have chosen to cancel editing a stair element. Cancelling cannot be undone. Are you sure you want to cancel?").color(egui::Color32::from_rgb(0, 51, 153)).size(13.0));
        ui.add_space(10.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "No", false, true) {
                no = true;
            }
            if dlg_button(ui, "Yes", true, true) {
                yes = true;
            }
        });
    });
    if yes {
        app.sketch = None;
        app.tool = crate::tools::Tool::select();
    }
    if yes || no || !open {
        app.dialogs.cancel_stair = false;
    }
}

/// The stair's Railing dialog: railing type (or none) and its position.
fn stair_railing_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.stair_railing {
        return;
    }
    let types: Vec<(Id, String)> = app.doc.data.types_of(Category::Railings).map(|t| (t.id, t.name.clone())).collect();
    let id = egui::Id::new("stair-railing-choice");
    let mut choice: Option<Id> = ctx.data(|m| m.get_temp(id)).unwrap_or(app.opts.stair_railing);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Railing").open(&mut open).resizable(false).default_width(300.0).show(ctx, |ui| {
        let name = choice.and_then(|c| types.iter().find(|t| t.0 == c).map(|t| t.1.clone())).unwrap_or_else(|| "None".into());
        egui::ComboBox::from_id_salt("sr-type").selected_text(name).width(260.0).show_ui(ui, |ui| {
            ui.selectable_value(&mut choice, None, "None");
            for (t, n) in &types {
                ui.selectable_value(&mut choice, Some(*t), n);
            }
        });
        ui.add_space(6.0);
        ui.label("Position");
        let _ = ui.radio(true, "Treads");
        ui.add_enabled(false, egui::RadioButton::new(false, "Stringer"));
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(id, choice));
    if ok {
        app.opts.stair_railing = choice;
    }
    if ok || cancel || !open {
        app.dialogs.stair_railing = false;
        ctx.data_mut(|m| m.remove::<Option<Id>>(id));
    }
}

/// "You have created the Roof on the lowest level. Would you like to move it to: [level] ?"
fn lowest_level_notice(app: &mut App, ctx: &egui::Context) {
    let Some(mut target) = app.dialogs.lowest_level else { return };
    if app.sketch.as_ref().is_none_or(|s| s.kind != crate::tools::SketchKind::Roof) {
        app.dialogs.lowest_level = None;
        return;
    }
    let levels: Vec<(Id, String)> = app.doc.data.levels().iter().skip(1).map(|(id, l)| (*id, l.name.clone())).collect();
    let (mut open, mut yes, mut no) = (true, false, false);
    window("Lowest Level Notice").open(&mut open).resizable(false).default_width(360.0).show(ctx, |ui| {
        ui.label("You have created the Roof on the lowest level.");
        ui.horizontal(|ui| {
            ui.label("Would you like to move it to:");
            let name = levels.iter().find(|l| l.0 == target).map(|l| l.1.clone()).unwrap_or_default();
            egui::ComboBox::from_id_salt("lln-level").selected_text(name).width(110.0).show_ui(ui, |ui| {
                for (id, n) in &levels {
                    ui.selectable_value(&mut target, *id, n);
                }
            });
            ui.label("?");
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "No", false, true) {
                no = true;
            }
            if dlg_button(ui, "Yes", true, true) {
                yes = true;
            }
        });
    });
    if yes {
        if let Some(sk) = app.sketch.as_mut() {
            sk.level = target;
        }
    }
    app.dialogs.lowest_level = if yes || no || !open { None } else { Some(target) };
}

/// Family templates offered by New Family (all start from the generic template).
const FAMILY_TEMPLATES: [(&str, Category); 6] = [
    ("Generic Model", Category::GenericModels),
    ("Furniture", Category::Furniture),
    ("Casework", Category::Casework),
    ("Specialty Equipment", Category::SpecialtyEquipment),
    ("Plumbing Fixture", Category::PlumbingFixtures),
    ("Column", Category::Columns),
];

/// File > New > Family: choose a template.
fn new_family_dialog(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.new_family {
        return;
    }
    let sel_id = egui::Id::new("nf-template");
    let mut sel: usize = ctx.data(|m| m.get_temp(sel_id)).unwrap_or(0);
    let imperial = app.doc.data.units.system == rc_core::units::UnitSystem::Imperial;
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("New Family - Select Template File").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
        egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
            ui.set_min_width(380.0);
            for (k, (name, _)) in FAMILY_TEMPLATES.iter().enumerate() {
                let label = format!("{}{name}.rft", if imperial { "" } else { "Metric " });
                let r = ui.selectable_label(sel == k, label);
                if r.clicked() {
                    sel = k;
                }
                if r.double_clicked() {
                    ok = true;
                }
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "Open", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(sel_id, sel));
    if ok {
        let (name, cat) = FAMILY_TEMPLATES[sel];
        crate::family_editor::new_family(app, name, cat, None);
    }
    if ok || cancel || !open {
        app.dialogs.new_family = false;
    }
}

/// Model In-place: Family Category and Parameters, then the name, then the editor.
fn in_place_dialog(app: &mut App, ctx: &egui::Context) {
    let Some((step, mut cat, mut name)) = app.dialogs.in_place.clone() else { return };
    let cats = [Category::Casework, Category::Columns, Category::Furniture, Category::GenericModels, Category::PlumbingFixtures, Category::SpecialtyEquipment];
    let (mut open, mut ok, mut cancel) = (true, false, false);
    if step == 0 {
        window("Family Category and Parameters").open(&mut open).resizable(false).default_width(340.0).show(ctx, |ui| {
            ui.label(egui::RichText::new("Family Category").strong());
            egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
                ui.set_min_width(300.0);
                for c in cats {
                    let r = ui.selectable_label(cat == c, c.label());
                    if r.clicked() {
                        cat = c;
                    }
                    if r.double_clicked() {
                        ok = true;
                    }
                }
            });
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                if dlg_button(ui, "Cancel", false, true) {
                    cancel = true;
                }
                if dlg_button(ui, "OK", true, true) {
                    ok = true;
                }
            });
        });
        app.dialogs.in_place = if cancel || !open { None } else if ok { Some((1, cat, name)) } else { Some((0, cat, name)) };
        return;
    }
    window("Name").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Name:");
            ui.add(egui::TextEdit::singleline(&mut name).desired_width(220.0));
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, !name.trim().is_empty()) {
                ok = true;
            }
        });
    });
    if ok {
        app.dialogs.in_place = None;
        let level = app.active_level().or_else(|| app.doc.data.levels().first().map(|l| l.0));
        if let Some(level) = level {
            crate::family_editor::new_family(app, name.trim(), cat, Some(level));
        }
        return;
    }
    app.dialogs.in_place = if cancel || !open { None } else { Some((1, cat, name)) };
}

/// The reference app's Work Plane dialog: the current plane, and a new one by name.
fn work_plane(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.work_plane {
        return;
    }
    let Some(view_id) = app.active else {
        app.dialogs.work_plane = false;
        return;
    };
    use crate::app::WorkPlaneRef;
    let p = &app.doc.data;
    let mut planes: Vec<(String, WorkPlaneRef)> = p.levels().iter().map(|(id, l)| (format!("Level : {}", l.name), WorkPlaneRef::Level(*id))).collect();
    for e in &p.elements {
        if let ElementKind::RefPlane(r) = &e.kind {
            if !r.name.is_empty() {
                planes.push((format!("Reference Plane : {}", r.name), WorkPlaneRef::RefPlane(e.id)));
            }
        }
    }
    let current = app.work_planes.get(&view_id).copied().or_else(|| app.doc.data.view(view_id).and_then(|v| v.plan_level()).map(WorkPlaneRef::Level));
    let name_of = |w: Option<WorkPlaneRef>| w.and_then(|w| planes.iter().find(|(_, x)| *x == w).map(|(n, _)| n.clone())).unwrap_or_else(|| "<not associated>".into());
    let pick_id = egui::Id::new("wp-choice");
    let mut choice: usize = ctx.data(|m| m.get_temp(pick_id)).unwrap_or_else(|| planes.iter().position(|(_, w)| Some(*w) == current).unwrap_or(0));
    let mut open = true;
    let (mut ok, mut cancel, mut show) = (false, false, false);
    window("Work Plane").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        ui.label(egui::RichText::new("Current Work Plane").strong());
        ui.horizontal(|ui| {
            ui.label("Name:");
            ui.label(name_of(current));
        });
        ui.horizontal(|ui| {
            if dlg_button(ui, "Show", false, true) {
                show = true;
            }
            let _ = dlg_button(ui, "Dissociate", false, false);
        });
        ui.separator();
        ui.label(egui::RichText::new("Specify a new Work Plane").strong());
        ui.horizontal(|ui| {
            let _ = ui.radio(true, "Name");
            egui::ComboBox::from_id_salt("wp-name").width(240.0).selected_text(planes.get(choice).map(|x| x.0.clone()).unwrap_or_default()).show_ui(ui, |ui| {
                for (k, (n, _)) in planes.iter().enumerate() {
                    ui.selectable_value(&mut choice, k, n);
                }
            });
        });
        ui.add_enabled(false, egui::RadioButton::new(false, "Pick a plane"));
        ui.add_enabled(false, egui::RadioButton::new(false, "Pick a line and use the work plane it was sketched in"));
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    ctx.data_mut(|m| m.insert_temp(pick_id, choice));
    if show {
        app.show_work_plane.insert(view_id);
    }
    if ok {
        if let Some((n, w)) = planes.get(choice).cloned() {
            app.work_planes.insert(view_id, w);
            app.info(format!("Work plane: {n}."));
        }
    }
    if ok || cancel || !open {
        app.dialogs.work_plane = false;
        ctx.data_mut(|m| m.remove::<usize>(pick_id));
    }
}

/// Work Plane > Viewer: a floating window showing the current work plane's view, fitted.
fn work_plane_viewer(app: &mut App, ctx: &egui::Context) {
    let Some(view_id) = app.work_plane_viewer else { return };
    let Some(view) = app.doc.data.view(view_id).cloned() else {
        app.work_plane_viewer = None;
        return;
    };
    let drawing = app.drawing(view_id);
    let mut open = true;
    window("Workplane Viewer").open(&mut open).default_size(vec2(420.0, 320.0)).resizable(true).show(ctx, |ui| {
        let (rect, _) = ui.allocate_exact_size(ui.available_size().max(vec2(300.0, 220.0)), egui::Sense::hover());
        ui.painter().rect_filled(rect, 0.0, egui::Color32::WHITE);
        if let Some((mn, mx)) = drawing.bounds() {
            let size = (mx - mn).max(rc_core::geom::DVec2::splat(1.0));
            let zoom = ((rect.width() as f64 - 20.0) / size.x).min((rect.height() as f64 - 20.0) / size.y);
            let xf = crate::canvas::Xf { rect, center: (mn + mx) / 2.0, zoom, scale: view.scale, thin: app.thin_lines };
            crate::canvas::paint_prims(&ui.painter_at(rect), &drawing.prims, &xf, &|_, rgb| Some(egui::Color32::from_rgb(rgb[0], rgb[1], rgb[2])));
        }
    });
    if !open {
        app.work_plane_viewer = None;
    }
}

fn create_group(app: &mut App, ctx: &egui::Context) {
    let Some(mut name) = app.dialogs.create_group.clone() else { return };
    let mut open = true;
    let mut ok = false;
    let mut cancel = false;
    // The group type follows the selection: detail elements make a detail group.
    let detail_only = !app.selection.is_empty() && app.selection.iter().all(|id| app.el(*id).is_some_and(|e| e.view.is_some()));
    let edit_id = egui::Id::new("create-group-edit");
    window("Create Group").open(&mut open).resizable(false).show(ctx, |ui| {
        let mut open_editor: bool = ui.memory(|m| m.data.get_temp(edit_id)).unwrap_or(false);
        egui::Grid::new("cg").num_columns(2).spacing(vec2(8.0, 6.0)).show(ui, |ui| {
            ui.label("Name:");
            ui.add(egui::TextEdit::singleline(&mut name).desired_width(220.0));
            ui.end_row();
            ui.label("Group Type:");
            ui.horizontal(|ui| {
                let _ = ui.add_enabled(!detail_only, egui::RadioButton::new(!detail_only, "Model"));
                let _ = ui.add_enabled(detail_only, egui::RadioButton::new(detail_only, "Detail"));
            });
            ui.end_row();
        });
        crate::style::check(ui, &mut open_editor, "Open in group editor");
        ui.memory_mut(|m| m.data.insert_temp(edit_id, open_editor));
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    app.dialogs.create_group = if open && !ok && !cancel { Some(name.clone()) } else { None };
    if ok {
        let ids = app.selection.clone();
        if let Some(g) = app.run("Create Group", |p| rc_core::edit::create_group(p, &ids, name.trim())) {
            app.select(vec![g]);
            if ctx.memory(|m| m.data.get_temp::<bool>(edit_id)).unwrap_or(false) {
                actions::exec(app, Cmd::EditGroup);
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
                if crate::style::check(ui, &mut on, format!("{} Tags", c.singular())).changed() {
                    if on {
                        app.dialogs.tag_all_cats.insert(c);
                    } else {
                        app.dialogs.tag_all_cats.remove(&c);
                    }
                }
            }
        });
        crate::style::check(ui, &mut app.opts.tag_leader, "Leader");
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
                if crate::style::check(ui, &mut on, k).changed() {
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

/// "You have not saved your project recently. What do you want to do?"
fn save_reminder(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.save_reminder {
        return;
    }
    let mut open = true;
    let mut choice = 0;
    window("Project Not Saved Recently").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.set_width(270.0);
        ui.label(egui::RichText::new("You have not saved your project recently.\nWhat do you want to do?").size(14.0).color(egui::Color32::from_rgb(0, 51, 153)));
        ui.add_space(10.0);
        for (k, label) in [(1, "Save the project"), (2, "Save the project and set reminder intervals"), (3, "Do not save and set reminder intervals")] {
            let r = ui.add(egui::Button::new(egui::RichText::new(format!("\u{2192}  {label}")).color(egui::Color32::from_rgb(0, 102, 204))).frame(false).wrap());
            if r.clicked() {
                choice = k;
            }
        }
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if dlg_button(ui, "Cancel", false, true) {
                choice = 4;
            }
        });
    });
    if choice == 1 || choice == 2 {
        app.save();
    }
    if choice == 2 || choice == 3 {
        app.dialogs.options = true;
    }
    if choice != 0 || !open {
        app.dialogs.save_reminder = false;
        app.save_reminder_at = app.now;
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
