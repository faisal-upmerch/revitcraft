//! The family editor: a separate editing environment for loadable families. Custom families
//! are built from reference planes (driven by labelled and EQ dimensions) and solid/void
//! forms whose sketch points lock to those planes; template families expose their
//! parameters and types.

use crate::app::App;
use crate::canvas::{self, Cam2, Xf};
use crate::icons::{self, Icon};
use crate::render3d::{self, Camera, DrawSettings};
use crate::style;
use eframe::egui::{self, Color32, Pos2, Rect, Sense, Stroke, pos2, vec2};
use glam::DVec3;
use rc_core::family_def::{self, Axis, DimDef, FamilyDef, Form, FormDef, Loc, RefPlaneDef, SketchPlane, SketchPt, SymLine};
use rc_core::family_params::Resolver;
use rc_core::geom::DVec2;
use rc_core::model::*;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FeView {
    Plan,
    Front,
    Right,
    ThreeD,
    Ceiling,
    Back,
    Left,
}

impl FeView {
    pub fn label(self) -> &'static str {
        match self {
            FeView::Plan | FeView::Ceiling => "Ref. Level",
            FeView::Front => "Front",
            FeView::Right => "Right",
            FeView::Back => "Back",
            FeView::Left => "Left",
            FeView::ThreeD => "View 1",
        }
    }
    fn sketch_plane(self) -> Option<SketchPlane> {
        match self {
            FeView::Plan | FeView::Ceiling => Some(SketchPlane::XY),
            FeView::Front | FeView::Back => Some(SketchPlane::XZ),
            FeView::Right | FeView::Left => Some(SketchPlane::YZ),
            FeView::ThreeD => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FeTool {
    Select,
    RefPlane,
    Dimension,
    Extrusion,
    Blend,
    Revolve,
    Sweep,
    SweptBlend,
    SymbolicLine,
    ModelLine,
    RefLine,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FeSel {
    None,
    Plane(u32),
    Dim(usize),
    Form(usize),
    Sym(usize),
    /// A model or reference line.
    Line(usize),
}

pub struct FamilyEditor {
    pub family_id: Option<Id>,
    pub family: Family,
    pub view: FeView,
    pub type_idx: usize,
    pub tool: FeTool,
    pub void_mode: bool,
    pub pts: Vec<SketchPt>,
    /// Blend: the finished bottom profile while the top is sketched.
    pub blend_bottom: Option<Vec<SketchPt>>,
    pub dim_planes: Vec<u32>,
    pub sel: FeSel,
    pub cams: BTreeMap<u8, Cam2>,
    pub cam3d: Option<Camera>,
    pub undo: Vec<Family>,
    pub redo: Vec<Family>,
    pub dirty: bool,
    /// Family Types: the selected parameter row, its search text and the open sub-dialogs.
    pub param_sel: Option<String>,
    pub param_filter: String,
    pub param_dialog: Option<ParamDialog>,
    /// Esc ended the line chain: the sketch stays, without a rubber band until the next click.
    pub chain_ended: bool,
    /// Sweep: the finished path while its profile is sketched.
    pub sweep_path: Option<Vec<SketchPt>>,
    /// Swept Blend: the finished first profile while the second is sketched.
    pub sb_profile1: Option<Vec<DVec2>>,
    /// Go To View is open with these views to choose from.
    pub goto_view: Vec<FeView>,
    /// New Type (false) or Rename Type (true), with the name being typed.
    pub type_name_dialog: Option<(bool, String)>,
    pub message: Option<String>,
    pub scene_key: u64,
    /// Model In-place: finishing places the family's one instance in the project.
    pub in_place: Option<Id>,
    /// The family's open views (view tabs).
    pub open_views: Vec<FeView>,
    /// Extrusion Depth while sketching.
    pub depth: f64,
    /// The closed profile waiting for Finish Edit Mode.
    pub closed: bool,
    /// Family Types is open: the family as it was (Cancel restores it).
    pub types_dialog: Option<Family>,
    pub category_dialog: bool,
    pub category_pick: Option<Category>,
}

pub fn open(app: &mut App, family_id: Id) {
    let Some(f) = app.doc.data.family(family_id).cloned() else { return };
    let mut fe = FamilyEditor::new(Some(family_id), f);
    if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial {
        fe.depth = 304.8;
    }
    app.family_editor = Some(fe);
    app.ribbon_tab = crate::ribbon::Tab::Create;
}

pub fn new_custom(app: &mut App, name: &str) {
    new_family(app, name, Category::GenericModels, None);
}

/// A new family of `category` in the editor; `in_place` (a level) makes it an in-place
/// family placed in the project when finished.
pub fn new_family(app: &mut App, name: &str, category: Category, in_place: Option<Id>) {
    // As the reference app's family templates: the origin planes and Default Elevation.
    let params = vec![FamilyParameter { name: "Default Elevation".into(), kind: ParamKind::Length, instance: true, formula: String::new(), group: "Constraints".into(), built_in: true, default: "0".into(), reporting: false }];
    let fam = Family {
        id: 0,
        name: rc_core::edit::unique_name(app.doc.data.families.iter().map(|f| f.name.clone()), name),
        category,
        template: FamilyTemplate::Custom,
        params,
        types: vec![FamilyType { id: 0, name: "Type 1".into(), values: BTreeMap::new() }],
        definition: Some(family_def::empty_template()),
    };
    let mut fe = FamilyEditor::new(None, fam);
    fe.dirty = true;
    fe.in_place = in_place;
    if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial {
        fe.depth = 304.8;
    }
    app.family_editor = Some(fe);
    app.ribbon_tab = crate::ribbon::Tab::Create;
}

impl FamilyEditor {
    fn new(family_id: Option<Id>, family: Family) -> FamilyEditor {
        let custom = family.template == FamilyTemplate::Custom;
        FamilyEditor {
            family_id,
            family,
            view: if custom { FeView::Plan } else { FeView::ThreeD },
            type_idx: 0,
            tool: FeTool::Select,
            void_mode: false,
            pts: Vec::new(),
            blend_bottom: None,
            dim_planes: Vec::new(),
            sel: FeSel::None,
            cams: BTreeMap::new(),
            cam3d: None,
            undo: Vec::new(),
            redo: Vec::new(),
            dirty: false,
            in_place: None,
            open_views: vec![if custom { FeView::Plan } else { FeView::ThreeD }],
            depth: 250.0,
            closed: false,
            types_dialog: None,
            category_dialog: false,
            category_pick: None,
            param_sel: None,
            sweep_path: None,
            chain_ended: false,
            goto_view: Vec::new(),
            sb_profile1: None,
            param_filter: String::new(),
            param_dialog: None,
            type_name_dialog: None,
            message: None,
            scene_key: 1,
        }
    }

    fn checkpoint(&mut self) {
        self.undo.push(self.family.clone());
        if self.undo.len() > 60 {
            self.undo.remove(0);
        }
        self.redo.clear();
        self.dirty = true;
        self.scene_key += 1;
    }

    fn def(&self) -> Option<&FamilyDef> {
        self.family.definition.as_ref()
    }

    fn ftype(&self) -> &FamilyType {
        let k = self.type_idx.min(self.family.types.len().saturating_sub(1));
        &self.family.types[k]
    }

    /// Solved reference plane positions for the current type (falls back to defaults on error).
    fn solved(&self) -> (family_def::Solved, Option<String>) {
        let Some(def) = self.def() else { return (Default::default(), None) };
        let r = Resolver::for_type(&self.family, self.ftype());
        match def.solve(&|name| r.number(name).ok()) {
            Ok(s) => (s, None),
            Err(e) => (def.planes.iter().map(|p| (p.id, p.default)).collect(), Some(e)),
        }
    }

    fn mesh(&self, p: &Project) -> rc_core::mesh::MeshSet {
        match self.def() {
            Some(def) => {
                let (solved, _) = self.solved();
                let r = Resolver::for_type(&self.family, self.ftype());
                let mat = |m: &str| if self.family.param(m).is_some() { r.text(m, "Default") } else if m.is_empty() { "Default".to_string() } else { m.to_string() };
                let vis = |n: &str| r.yes_no(n, true);
                let _ = p;
                def.build(&solved, &mat, &vis)
            }
            None => rc_core::build3d::family_type_preview(&self.family, self.ftype()),
        }
    }
}

// ---------------------------------------------------------------- coordinates

/// (horizontal axis, vertical axis) of a 2D family view.
fn view_axes(v: FeView) -> (Axis, Axis) {
    match v {
        FeView::Plan | FeView::Ceiling => (Axis::X, Axis::Y),
        FeView::Front | FeView::Back => (Axis::X, Axis::Z),
        FeView::Right | FeView::Left => (Axis::Y, Axis::Z),
        FeView::ThreeD => (Axis::X, Axis::Y),
    }
}

fn loc_value(l: Loc, s: &family_def::Solved) -> f64 {
    family_def::loc(l, s)
}

fn pt2(p: SketchPt, s: &family_def::Solved) -> DVec2 {
    DVec2::new(loc_value(p.a, s), loc_value(p.b, s))
}

/// Snaps a coordinate to a plane of `axis` within `tol`, returning a plane-locked Loc.
fn snap_loc(def: &FamilyDef, solved: &family_def::Solved, axis: Axis, v: f64, tol: f64) -> Loc {
    def.planes
        .iter()
        .filter(|p| p.axis == axis)
        .map(|p| (p.id, (solved.get(&p.id).copied().unwrap_or(p.default) - v).abs()))
        .filter(|(_, d)| *d <= tol)
        .min_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(id, _)| Loc::Plane(id))
        .unwrap_or(Loc::Value((v / 10.0).round() * 10.0))
}

// ---------------------------------------------------------------- UI

/// Shows the family editor in place of the project UI. Returns the editor to keep it open.
// ---------------------------------------------------------------- the editor in the main window

/// What the status bar shows while the family editor is open.
pub fn status_text(app: &App) -> String {
    app.family_editor.as_ref().map(|fe| {
        let (_, err) = fe.solved();
        err.or(fe.message.clone()).unwrap_or_else(|| prompt(fe, app.opts.draw_mode))
    }).unwrap_or_default()
}

/// The view area: tabs of the open family views and the active view.
pub fn view_area(app: &mut App, ui: &mut egui::Ui) {
    let Some(mut fe) = app.family_editor.take() else { return };
    if fe.open_views.is_empty() {
        fe.open_views.push(fe.view);
    }
    // View tabs, as the reference app shows the family's open views.
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
        let mut close: Option<FeView> = None;
        for v in fe.open_views.clone() {
            let label = v.label();
            let w = ui.painter().layout_no_wrap(label.to_string(), style::font(12.0), Color32::BLACK).size().x + 44.0;
            let (r, resp) = ui.allocate_exact_size(vec2(w.max(90.0), 21.0), Sense::click());
            let active = fe.view == v;
            ui.painter().rect_filled(r, 0.0, if active { style::field() } else { style::tab_idle() });
            ui.painter().rect_stroke(r, 0.0, Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
            icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(5.0, 3.0), vec2(15.0, 15.0)), if v == FeView::ThreeD { Icon::View3D } else if matches!(v, FeView::Plan | FeView::Ceiling) { Icon::FloorPlan } else { Icon::Elevation }, true);
            ui.painter().text(r.left_center() + vec2(24.0, 0.0), egui::Align2::LEFT_CENTER, label, style::font(12.0), style::text());
            let xr = Rect::from_center_size(r.right_center() - vec2(11.0, 0.0), vec2(14.0, 14.0));
            let x_hover = ui.rect_contains_pointer(xr);
            let c = xr.center();
            let ink = Stroke::new(1.1, if x_hover { style::ERROR } else { style::text() });
            ui.painter().line_segment([c + vec2(-4.0, -4.0), c + vec2(4.0, 4.0)], ink);
            ui.painter().line_segment([c + vec2(4.0, -4.0), c + vec2(-4.0, 4.0)], ink);
            if resp.clicked() {
                if x_hover {
                    close = Some(v);
                } else {
                    fe.view = v;
                    fe.pts.clear();
                }
            }
        }
        if let Some(v) = close {
            if fe.open_views.len() > 1 {
                fe.open_views.retain(|x| *x != v);
                if fe.view == v {
                    fe.view = fe.open_views[0];
                }
            }
        }
    });
    if fe.view == FeView::ThreeD || fe.def().is_none() {
        preview_3d(app, &mut fe, ui);
    } else {
        canvas_2d(app, &mut fe, ui);
    }
    // Keyboard.
    if !ui.ctx().egui_wants_keyboard_input() {
        if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            // In sketch mode Esc ends the chain but keeps the sketch; only Finish or Cancel
            // Edit Mode leave it.
            let sketching = matches!(fe.tool, FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SweptBlend);
            if sketching {
                fe.chain_ended = true;
            } else if !fe.pts.is_empty() || !fe.dim_planes.is_empty() {
                fe.pts.clear();
                fe.dim_planes.clear();
            } else if fe.tool != FeTool::Select {
                cancel_sketch(&mut fe);
            } else {
                fe.sel = FeSel::None;
            }
        }
        if ui.input(|i| i.key_pressed(egui::Key::Delete)) {
            delete_selected(&mut fe);
        }
        if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Z)) {
            undo(&mut fe);
        }
    }
    app.family_editor = Some(fe);
    family_types_dialog(app, ui.ctx());
    family_category_dialog(app, ui.ctx());
    goto_view_dialog(app, ui.ctx());
}

pub fn undo(fe: &mut FamilyEditor) {
    if let Some(prev) = fe.undo.pop() {
        fe.redo.push(std::mem::replace(&mut fe.family, prev));
        fe.scene_key += 1;
    }
}

pub fn redo(fe: &mut FamilyEditor) {
    if let Some(next) = fe.redo.pop() {
        fe.undo.push(std::mem::replace(&mut fe.family, next));
        fe.scene_key += 1;
    }
}

/// Starts a tool (a form opens its sketch mode in a 2D view).
pub fn set_tool(fe: &mut FamilyEditor, t: FeTool, void: bool) {
    fe.tool = t;
    fe.void_mode = void;
    fe.pts.clear();
    fe.dim_planes.clear();
    fe.blend_bottom = None;
    fe.sweep_path = None;
    fe.sb_profile1 = None;
    fe.closed = false;
    fe.sel = FeSel::None;
    if t != FeTool::Select && fe.view == FeView::ThreeD {
        fe.view = FeView::Plan;
        if !fe.open_views.contains(&FeView::Plan) {
            fe.open_views.push(FeView::Plan);
        }
    }
}

/// Mode ✓: finishes the form being sketched.
pub fn finish(fe: &mut FamilyEditor) {
    finish_sketch(fe);
    if fe.pts.is_empty() && fe.blend_bottom.is_none() && fe.sweep_path.is_none() && fe.message.is_none() {
        fe.tool = FeTool::Select;
    }
}

/// Mode ✗: abandons the sketch.
pub fn cancel_sketch(fe: &mut FamilyEditor) {
    fe.chain_ended = false;
    fe.pts.clear();
    fe.blend_bottom = None;
    fe.sweep_path = None;
    fe.sb_profile1 = None;
    fe.goto_view.clear();
    fe.closed = false;
    fe.dim_planes.clear();
    fe.tool = FeTool::Select;
    fe.void_mode = false;
}

/// The family's views, as the reference app's Project Browser lists them.
fn pgrid(ui: &mut egui::Ui, id: &str, add: impl FnOnce(&mut egui::Ui)) {
    egui::Grid::new(id).num_columns(2).spacing(vec2(6.0, 3.0)).min_col_width(110.0).show(ui, add);
}

fn ro(ui: &mut egui::Ui, s: &str) {
    ui.label(egui::RichText::new(s).color(style::text_dim()));
}

/// The Properties palette: the family's parameters, the form being sketched or the selection.
pub fn properties_palette(app: &mut App, ui: &mut egui::Ui) {
    let Some(mut fe) = app.family_editor.take() else { return };
    style::palette_title(ui, "Properties");
    // Type selector: families have no type here, as in the reference app.
    egui::Frame::new().inner_margin(4).show(ui, |ui| {
        let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), 56.0), Sense::hover());
        ui.painter().rect_stroke(r, 0.0, Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
        icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(6.0, 6.0), vec2(44.0, 44.0)), Icon::FamilyTypes, true);
    });
    let sketching = matches!(fe.tool, FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SweptBlend);
    let header = if sketching {
        match fe.tool {
            FeTool::Blend => "Blend".to_string(),
            FeTool::Revolve => "Revolution".to_string(),
            FeTool::Sweep => "Sweep".to_string(),
            FeTool::SweptBlend => "Swept Blend".to_string(),
            _ => "Extrusion".to_string(),
        }
    } else {
        match fe.sel {
            FeSel::Form(k) => fe.def().and_then(|d| d.forms.get(k)).map(|f| f.form.kind_label().to_string()).unwrap_or_default(),
            FeSel::Plane(_) => "Reference Planes (1)".into(),
            FeSel::Dim(_) => "Dimensions (1)".into(),
            FeSel::Sym(_) => "Symbolic Lines (1)".into(),
            FeSel::Line(k) => if fe.def().and_then(|d| d.lines.get(k)).is_some_and(|l| l.reference) { "Reference Lines (1)".into() } else { "Model Lines (1)".into() },
            FeSel::None => format!("Family: {}", fe.family.category.label()),
        }
    };
    ui.horizontal(|ui| {
        ui.add_space(4.0);
        ui.label(header);
    });
    egui::ScrollArea::vertical().id_salt("fe-props").show(ui, |ui| {
        egui::Frame::new().inner_margin(egui::Margin { left: 4, right: 4, top: 2, bottom: 6 }).show(ui, |ui| {
            if sketching {
                sketch_properties(app, &mut fe, ui);
            } else {
                selection_properties(app, &mut fe, ui);
            }
        });
    });
    app.family_editor = Some(fe);
}

/// The form being sketched: its extents, visibility, material and solid/void.
fn sketch_properties(app: &App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let units = app.doc.data.units.clone();
    style::group_header_ui(ui, "Constraints", true);
    pgrid(ui, "fe-sk-c", |ui| {
        if fe.tool == FeTool::Extrusion {
            ui.label("Extrusion End");
            let mut s = units.length(fe.depth);
            if ui.add(egui::TextEdit::singleline(&mut s).desired_width(ui.available_width() - 4.0)).lost_focus() {
                if let Some(v) = units.parse(&s, ParamKind::Length) {
                    fe.depth = v;
                }
            }
            ui.end_row();
            ui.label("Extrusion Start");
            ro(ui, &units.length(0.0));
            ui.end_row();
        }
        ui.label("Work Plane");
        ro(ui, match fe.view {
            FeView::Plan | FeView::Ceiling | FeView::ThreeD => "Level : Ref. Level",
            FeView::Front | FeView::Back => "Reference Plane : Center (Front/Back)",
            FeView::Right | FeView::Left => "Reference Plane : Center (Left/Right)",
        });
        ui.end_row();
    });
    style::group_header_ui(ui, "Graphics", true);
    pgrid(ui, "fe-sk-g", |ui| {
        ui.label("Visible");
        ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, ""));
        ui.end_row();
    });
    style::group_header_ui(ui, "Materials and Finishes", true);
    pgrid(ui, "fe-sk-m", |ui| {
        ui.label("Material");
        ro(ui, "<By Category>");
        ui.end_row();
    });
    style::group_header_ui(ui, "Identity Data", true);
    pgrid(ui, "fe-sk-i", |ui| {
        ui.label("Subcategory");
        ro(ui, "<None>");
        ui.end_row();
        ui.label("Solid/Void");
        let mut void = fe.void_mode;
        egui::ComboBox::from_id_salt("fe-sv").selected_text(if void { "Void" } else { "Solid" }).width(ui.available_width() - 4.0).show_ui(ui, |ui| {
            ui.selectable_value(&mut void, false, "Solid");
            ui.selectable_value(&mut void, true, "Void");
        });
        fe.void_mode = void;
        ui.end_row();
    });
}

/// Family parameters, or the selected plane, dimension, form or line.
fn selection_properties(app: &App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let Some(def) = fe.def().cloned() else {
        family_parameters(fe, ui);
        return;
    };
    let length_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::Length).map(|p| p.name.clone()).collect();
    let yesno_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::YesNo).map(|p| p.name.clone()).collect();
    let mat_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::Material).map(|p| p.name.clone()).collect();
    let (solved, _) = fe.solved();
    let units = app.doc.data.units.clone();
    match fe.sel {
        FeSel::None => family_parameters(fe, ui),
        FeSel::Plane(id) => {
            let Some(p) = def.plane(id).cloned() else { return };
            let mut np = p.clone();
            style::group_header_ui(ui, "Constraints", true);
            pgrid(ui, "fe-rp-c", |ui| {
                ui.label("Wall Closure");
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                ui.end_row();
            });
            style::group_header_ui(ui, "Other", true);
            pgrid(ui, "fe-rp-o", |ui| {
                ui.label("Name");
                ui.add(egui::TextEdit::singleline(&mut np.name).desired_width(ui.available_width() - 4.0));
                ui.end_row();
                ui.label("Is Reference");
                ro(ui, if p.fixed { "Center (Left/Right)" } else { "Weak Reference" });
                ui.end_row();
                ui.label("Defines Origin");
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut p.fixed.clone(), ""));
                ui.end_row();
                ui.label("Position");
                ui.add_enabled_ui(!p.fixed, |ui| ui.add(egui::DragValue::new(&mut np.default).speed(5.0).suffix(" mm")));
                ui.end_row();
            });
            if np != p {
                fe.checkpoint();
                if let Some(x) = fe.family.definition.as_mut().and_then(|d| d.planes.iter_mut().find(|x| x.id == id)) {
                    *x = np;
                }
            }
        }
        FeSel::Dim(k) => {
            let Some(d) = def.dims.get(k).cloned() else { return };
            let mut nd = d.clone();
            style::group_header_ui(ui, "Other", true);
            pgrid(ui, "fe-dim", |ui| {
                ui.label("Label");
                egui::ComboBox::from_id_salt("fe-dim-label").selected_text(if nd.label.is_empty() { "<None>".to_string() } else { nd.label.clone() }).width(ui.available_width() - 4.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut nd.label, String::new(), "<None>");
                    for n in &length_params {
                        ui.selectable_value(&mut nd.label, n.clone(), n);
                    }
                });
                ui.end_row();
                ui.label("Equality");
                ui.add_enabled_ui(nd.planes.len() >= 3, |ui| crate::style::check(ui, &mut nd.equal, ""));
                ui.end_row();
                ui.label("Locked");
                crate::style::check(ui, &mut nd.locked, "");
                ui.end_row();
            });
            if nd != d {
                fe.checkpoint();
                fe.family.definition.as_mut().unwrap().dims[k] = nd;
            }
        }
        FeSel::Form(k) => {
            let Some(f) = def.forms.get(k).cloned() else { return };
            let mut nf = f.clone();
            style::group_header_ui(ui, "Constraints", true);
            pgrid(ui, "fe-f-c", |ui| match &mut nf.form {
                Form::Extrusion { plane, start, end, .. } => {
                    ui.label("Extrusion End");
                    loc_value_editor(ui, "fe-ee", &def, &solved, &units, end);
                    ui.end_row();
                    ui.label("Extrusion Start");
                    loc_value_editor(ui, "fe-es", &def, &solved, &units, start);
                    ui.end_row();
                    ui.label("Work Plane");
                    ro(ui, match plane {
                        SketchPlane::XY => "Level : Ref. Level",
                        SketchPlane::XZ => "Reference Plane : Center (Front/Back)",
                        SketchPlane::YZ => "Reference Plane : Center (Left/Right)",
                    });
                    ui.end_row();
                }
                Form::Blend { start, end, .. } => {
                    ui.label("Second End");
                    loc_value_editor(ui, "fe-be", &def, &solved, &units, end);
                    ui.end_row();
                    ui.label("First End");
                    loc_value_editor(ui, "fe-bs", &def, &solved, &units, start);
                    ui.end_row();
                }
                Form::Revolve { angle_deg, .. } => {
                    ui.label("End Angle");
                    ui.add(egui::DragValue::new(angle_deg).range(1.0..=360.0).suffix("°"));
                    ui.end_row();
                    ui.label("Start Angle");
                    ro(ui, "0.00°");
                    ui.end_row();
                }
                Form::SweptBlend { z, .. } => {
                    ui.label("Path Height");
                    loc_value_editor(ui, "fe-sbz", &def, &solved, &units, z);
                    ui.end_row();
                }
                Form::Sweep { z, width, height, profile, .. } => {
                    ui.label("Path Height");
                    loc_value_editor(ui, "fe-sz", &def, &solved, &units, z);
                    ui.end_row();
                    if !profile.is_empty() {
                        ui.label("Trajectory Segmentation");
                        ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                        ui.end_row();
                        ui.label("Maximum Segment Angle");
                        ro(ui, "15.00°");
                        ui.end_row();
                        return;
                    }
                    ui.label("Profile Width");
                    ui.add(egui::DragValue::new(width).speed(1.0).suffix(" mm"));
                    ui.end_row();
                    ui.label("Profile Height");
                    ui.add(egui::DragValue::new(height).speed(1.0).suffix(" mm"));
                    ui.end_row();
                }
            });
            style::group_header_ui(ui, "Graphics", true);
            pgrid(ui, "fe-f-g", |ui| {
                ui.label("Visible");
                ui.horizontal(|ui| {
                    if nf.visible.is_empty() {
                        ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, ""));
                    } else {
                        ro(ui, &format!("[{}]", nf.visible));
                    }
                    // Associate Family Parameter: a Yes/No parameter drives visibility.
                    egui::ComboBox::from_id_salt("fe-vis").selected_text("").width(18.0).show_ui(ui, |ui| {
                        ui.selectable_value(&mut nf.visible, String::new(), "<none>");
                        for n in &yesno_params {
                            ui.selectable_value(&mut nf.visible, n.clone(), n);
                        }
                    });
                });
                ui.end_row();
            });
            if !nf.void {
                style::group_header_ui(ui, "Materials and Finishes", true);
                pgrid(ui, "fe-f-m", |ui| {
                    ui.label("Material");
                    let shown = if nf.material.is_empty() || nf.material == "Material" && !mat_params.contains(&nf.material) { "<By Category>".to_string() } else if mat_params.contains(&nf.material) { format!("[{}]", nf.material) } else { nf.material.clone() };
                    egui::ComboBox::from_id_salt("fe-mat").selected_text(shown).width(ui.available_width() - 4.0).show_ui(ui, |ui| {
                        ui.selectable_value(&mut nf.material, String::new(), "<By Category>");
                        for n in &mat_params {
                            ui.selectable_value(&mut nf.material, n.clone(), format!("[{n}]"));
                        }
                        for m in &app.doc.data.materials {
                            ui.selectable_value(&mut nf.material, m.name.clone(), &m.name);
                        }
                    });
                    ui.end_row();
                });
            }
            style::group_header_ui(ui, "Identity Data", true);
            pgrid(ui, "fe-f-i", |ui| {
                ui.label("Subcategory");
                ro(ui, "<None>");
                ui.end_row();
                ui.label("Solid/Void");
                egui::ComboBox::from_id_salt("fe-f-sv").selected_text(if nf.void { "Void" } else { "Solid" }).width(ui.available_width() - 4.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut nf.void, false, "Solid");
                    ui.selectable_value(&mut nf.void, true, "Void");
                });
                ui.end_row();
            });
            if nf != f {
                fe.checkpoint();
                fe.family.definition.as_mut().unwrap().forms[k] = nf;
            }
        }
        FeSel::Line(k) => {
            let l = fe.def().and_then(|d| d.lines.get(k)).cloned();
            if let Some(l) = l {
                let (solved, _) = fe.solved();
                let (a, b) = l.ends(&solved);
                style::group_header_ui(ui, "Constraints", true);
                pgrid(ui, "fe-line-c", |ui| {
                    ui.label("Work Plane");
                    ro(ui, match l.plane {
                        SketchPlane::XY => "Level : Ref. Level",
                        SketchPlane::XZ => "Reference Plane : Center (Front/Back)",
                        SketchPlane::YZ => "Reference Plane : Center (Left/Right)",
                    });
                    ui.end_row();
                });
                style::group_header_ui(ui, "Graphics", true);
                pgrid(ui, "fe-line-g", |ui| {
                    ui.label("Visible");
                    ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, ""));
                    ui.end_row();
                });
                style::group_header_ui(ui, "Identity Data", true);
                pgrid(ui, "fe-line-i", |ui| {
                    ui.label("Subcategory");
                    ro(ui, if l.reference { "<None>" } else { "Generic Models" });
                    ui.end_row();
                    ui.label("Is Reference");
                    ro(ui, "Not a Reference");
                    ui.end_row();
                });
                style::group_header_ui(ui, "Dimensions", true);
                pgrid(ui, "fe-line-d", |ui| {
                    ui.label("Length");
                    ro(ui, &app.doc.data.units.length(a.distance(b)));
                    ui.end_row();
                });
            }
        }
        FeSel::Sym(_) => {
            style::group_header_ui(ui, "Graphics", true);
            pgrid(ui, "fe-sym", |ui| {
                ui.label("Subcategory");
                ro(ui, "<None>");
                ui.end_row();
            });
        }
    }
}

/// The family's own parameters (Family Category and Parameters), shown with nothing selected.
fn family_parameters(fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let hosted = fe.family.is_hosted();
    style::group_header_ui(ui, "Constraints", true);
    pgrid(ui, "fe-fam-c", |ui| {
        ui.label("Host");
        ro(ui, if hosted { "Wall" } else { "" });
        ui.end_row();
    });
    style::group_header_ui(ui, "Structural", true);
    pgrid(ui, "fe-fam-s", |ui| {
        ui.label("Can host rebar");
        ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
        ui.end_row();
    });
    style::group_header_ui(ui, "Mechanical", true);
    pgrid(ui, "fe-fam-m", |ui| {
        ui.label("Part Type");
        ro(ui, "Normal");
        ui.end_row();
    });
    style::group_header_ui(ui, "Identity Data", true);
    pgrid(ui, "fe-fam-i", |ui| {
        ui.label("Family Name");
        let mut n = fe.family.name.clone();
        if ui.add(egui::TextEdit::singleline(&mut n).desired_width(ui.available_width() - 4.0)).lost_focus() && n != fe.family.name && !n.trim().is_empty() {
            fe.checkpoint();
            fe.family.name = n;
        }
        ui.end_row();
    });
    style::group_header_ui(ui, "Other", true);
    pgrid(ui, "fe-fam-o", |ui| {
        for (name, on) in [("Work Plane-Based", false), ("Always vertical", true), ("Cut with Voids When Loaded", false), ("Shared", false), ("Room Calculation Point", false)] {
            ui.label(name);
            ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut on.clone(), ""));
            ui.end_row();
        }
    });
}

/// The options bar while sketching or placing in the family editor.
pub fn options_bar(app: &mut App, ui: &mut egui::Ui) {
    let Some(fe) = app.family_editor.as_ref() else { return };
    ui.horizontal_centered(|ui| {
        ui.add_space(6.0);
        let title = match fe.tool {
            FeTool::Select => "Modify".to_string(),
            FeTool::Extrusion => "Modify | Create Extrusion".into(),
            FeTool::Blend => "Modify | Create Blend Base Boundary".into(),
            FeTool::Revolve => "Modify | Create Revolve".into(),
            FeTool::Sweep | FeTool::SweptBlend => format!("Modify | {} > {}", if fe.tool == FeTool::Sweep { "Sweep" } else { "Swept Blend" }, if fe.sweep_path.is_none() { "Sketch Path" } else { "Edit Profile" }),
            FeTool::RefPlane => "Modify | Place Reference Plane".into(),
            FeTool::Dimension => "Modify | Place Dimensions".into(),
            FeTool::SymbolicLine => "Modify | Place Symbolic Lines".into(),
            FeTool::ModelLine => "Modify | Place Lines".into(),
            FeTool::RefLine => "Modify | Place Reference Lines".into(),
        };
        ui.label(title);
        if matches!(fe.tool, FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SweptBlend | FeTool::SymbolicLine | FeTool::ModelLine | FeTool::RefLine | FeTool::RefPlane) {
            ui.separator();
            crate::style::check(ui, &mut app.opts.chain, "Chain");
            ui.label("Offset:");
            ui.add_enabled_ui(false, |ui| ui.label("0"));
            ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, "Radius:"));
        }
    });
}

/// Family Types, modal as in the reference app; Cancel restores the family.
fn family_types_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut fe) = app.family_editor.take() else { return };
    if fe.types_dialog.is_none() {
        app.family_editor = Some(fe);
        return;
    }
    let (mut open, mut ok, mut cancel, mut apply) = (true, false, false, false);
    crate::dialogs::window_pub("Family Types").open(&mut open).resizable(false).default_width(640.0).show(ctx, |ui| {
        ui.set_width(640.0);
        family_types(app, &mut fe, ui);
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if crate::dialogs::dlg_button(ui, "Apply", false, true) {
                apply = true;
            }
            if crate::dialogs::dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if crate::dialogs::dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    param_properties_dialog(&mut fe, ctx);
    type_name_dialog(&mut fe, ctx);
    if apply {
        fe.types_dialog = Some(fe.family.clone());
    }
    if cancel || !open {
        if let Some(before) = fe.types_dialog.take() {
            fe.family = before;
            fe.scene_key += 1;
        }
    }
    if ok {
        fe.types_dialog = None;
    }
    app.family_editor = Some(fe);
}

/// A sweep path's profile plane: the middle of its first segment and the path's left normal.
fn sweep_frame(pp: &[DVec2]) -> (DVec2, DVec2) {
    let a = pp.first().copied().unwrap_or(DVec2::ZERO);
    let b = pp.get(1).copied().unwrap_or(a + DVec2::X);
    ((a + b) / 2.0, rc_core::geom::perp((b - a).normalize_or_zero()))
}

/// The profile plane being sketched: a sweep's is mid-way along its first segment, a swept
/// blend's first profile is at the path start and its second at the end.
fn profile_frame(tool: FeTool, second: bool, pp: &[DVec2]) -> (DVec2, DVec2) {
    let (mid, n) = sweep_frame(pp);
    match tool {
        FeTool::SweptBlend if second => (pp.get(1).copied().unwrap_or(mid), n),
        FeTool::SweptBlend => (pp.first().copied().unwrap_or(mid), n),
        _ => (mid, n),
    }
}

/// The elevations in which a sweep's profile plane is parallel to the screen.
fn profile_views(pp: &[DVec2]) -> Vec<FeView> {
    let a = pp.first().copied().unwrap_or(DVec2::ZERO);
    let d = pp.get(1).copied().unwrap_or(a + DVec2::X) - a;
    if d.x.abs() >= d.y.abs() { vec![FeView::Right, FeView::Left] } else { vec![FeView::Front, FeView::Back] }
}

/// Go To View: opens a view where the sweep's profile plane is parallel to the screen.
fn goto_view_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(fe) = app.family_editor.as_mut() else { return };
    if fe.goto_view.is_empty() {
        return;
    }
    let pick_id = egui::Id::new("fe-goto-pick");
    let mut pick: usize = ctx.memory(|m| m.data.get_temp(pick_id)).unwrap_or(0).min(fe.goto_view.len() - 1);
    let (mut open, mut go, mut cancel) = (true, false, false);
    crate::dialogs::window_pub("Go To View").open(&mut open).resizable(false).default_width(360.0).show(ctx, |ui| {
        ui.label("In order to edit the sketch, please open one of the following views
where the sketch appears parallel to the screen:");
        ui.add_space(4.0);
        egui::Frame::new().stroke(Stroke::new(1.0, style::border())).fill(style::field()).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.set_min_height(90.0);
            for (k, v) in fe.goto_view.iter().enumerate() {
                let r = ui.selectable_label(pick == k, format!("Elevation : {}", v.label()));
                if r.clicked() {
                    pick = k;
                }
                if r.double_clicked() {
                    go = true;
                }
            }
        });
        ui.add_space(6.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if crate::dialogs::dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if crate::dialogs::dlg_button(ui, "Open View", true, true) {
                go = true;
            }
        });
    });
    ctx.memory_mut(|m| m.data.insert_temp(pick_id, pick));
    if go {
        let v = fe.goto_view[pick];
        fe.view = v;
        fe.pts.clear();
        fe.closed = false;
        if !fe.open_views.contains(&v) {
            fe.open_views.push(v);
        }
        fe.goto_view.clear();
    } else if cancel || !open {
        fe.goto_view.clear();
    }
}

/// Family Category and Parameters: the category the family loads into.
fn family_category_dialog(app: &mut App, ctx: &egui::Context) {
    let Some(mut fe) = app.family_editor.take() else { return };
    if !fe.category_dialog {
        app.family_editor = Some(fe);
        return;
    }
    let mut cat = fe.category_pick.unwrap_or(fe.family.category);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    crate::dialogs::window_pub("Family Category and Parameters").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        ui.label(egui::RichText::new("Family Category").strong());
        egui::Frame::new().stroke(Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
            ui.set_min_width(340.0);
            let fixed = matches!(fe.family.category, Category::Doors | Category::Windows);
            for c in [Category::Casework, Category::Columns, Category::Furniture, Category::GenericModels, Category::PlumbingFixtures, Category::SpecialtyEquipment, Category::StructuralColumns, Category::StructuralFoundations] {
                ui.add_enabled_ui(!fixed, |ui| {
                    if ui.selectable_label(cat == c, c.label()).clicked() {
                        cat = c;
                    }
                });
            }
        });
        ui.add_space(6.0);
        ui.label(egui::RichText::new("Family Parameters").strong());
        egui::Grid::new("fe-fcp").num_columns(2).striped(true).show(ui, |ui| {
            for (name, on) in [("Work Plane-Based", false), ("Always vertical", true), ("Cut with Voids When Loaded", false), ("Shared", false), ("Room Calculation Point", false)] {
                ui.label(name);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut on.clone(), ""));
                ui.end_row();
            }
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if crate::dialogs::dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if crate::dialogs::dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    fe.category_pick = Some(cat);
    if ok && cat != fe.family.category {
        fe.checkpoint();
        fe.family.category = cat;
    }
    if ok || cancel || !open {
        fe.category_dialog = false;
        fe.category_pick = None;
    }
    app.family_editor = Some(fe);
}

/// Load into Project (optionally closing the editor), as the Family Editor panel does.
pub fn load(app: &mut App, close: bool) {
    let Some(fe) = app.family_editor.take() else { return };
    load_into_project(app, &fe);
    // An in-place family's single instance sits at the project origin on its level.
    if let Some(level) = fe.in_place {
        let fam = app.doc.data.families.iter().rev().find(|f| f.name == fe.family.name).and_then(|f| f.types.first().map(|t| t.id));
        if let Some(t) = fam {
            app.run("Model In-Place", |p| rc_core::edit::place_free(p, t, level, rc_core::geom::DVec2::ZERO, 0.0));
        }
        app.ribbon_tab = crate::ribbon::Tab::Architecture;
        return;
    }
    if close {
        app.ribbon_tab = crate::ribbon::Tab::Architecture;
    } else {
        let mut fe = fe;
        fe.dirty = false;
        app.family_editor = Some(fe);
    }
}

/// File > Close in the family editor.
pub fn close(app: &mut App) {
    if let Some(fe) = app.family_editor.take() {
        if fe.dirty {
            app.info(format!("Closed {} without loading the changes.", fe.family.name));
        }
        app.ribbon_tab = crate::ribbon::Tab::Architecture;
    }
}

fn prompt(fe: &FamilyEditor, mode: crate::tools::DrawMode) -> String {
    use crate::tools::DrawMode;
    let first = fe.pts.is_empty();
    match fe.tool {
        FeTool::Select => "Click to select, TAB for alternates, CTRL adds, SHIFT unselects.".into(),
        FeTool::RefPlane => if first { "Click to enter Reference Plane start point.".into() } else { "Click to enter Reference Plane end point.".into() },
        FeTool::Dimension => if fe.dim_planes.is_empty() { "Click on a reference to dimension.".into() } else { "Click on another reference, or click empty space to place the dimension.".into() },
        FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SweptBlend | FeTool::SymbolicLine if fe.closed => "The sketch is closed. Click Finish Edit Mode.".into(),
        FeTool::Sweep | FeTool::SweptBlend if fe.sweep_path.is_none() => if first { "Click to enter line start point.".into() } else { "Click to enter line end point.".into() },
        FeTool::ModelLine | FeTool::RefLine => if first { "Click to enter line start point.".into() } else { "Click to enter line end point.".into() },
        FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::SymbolicLine | FeTool::Sweep | FeTool::SweptBlend => match mode {
            DrawMode::Rect => if first { "Click to enter rectangle start point.".into() } else { "Click to enter rectangle end point.".into() },
            DrawMode::Circle => if first { "Click to enter circle center.".into() } else { "Click to enter circle radius.".into() },
            _ => if first { "Click to enter line start point.".into() } else { "Click to enter line end point.".into() },
        },
    }
}

/// The screen transform of a 2D family view. Back and Left look the other way, so their
/// horizontal axis runs mirrored (model coordinates stay as they are).
struct ViewXf {
    xf: Xf,
    flip: bool,
    zoom: f64,
}

impl ViewXf {
    fn s(&self, w: DVec2) -> Pos2 {
        self.xf.s(if self.flip { DVec2::new(-w.x, w.y) } else { w })
    }
    fn w(&self, s: Pos2) -> DVec2 {
        let w = self.xf.w(s);
        if self.flip { DVec2::new(-w.x, w.y) } else { w }
    }
    fn len(&self, px: f32) -> f64 {
        self.xf.len(px)
    }
}

fn canvas_2d(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    let key = fe.view as u8;
    let mut cam = fe.cams.get(&key).copied().unwrap_or(Cam2 { center: DVec2::ZERO, zoom: 0.18, fitted: true });
    if !cam.fitted {
        cam = Cam2 { center: DVec2::ZERO, zoom: 0.18, fitted: true };
    }
    if let Some(h) = resp.hover_pos() {
        let f = (ui.input(|i| i.smooth_scroll_delta.y) as f64 * 0.0028).exp() * ui.input(|i| i.zoom_delta()) as f64;
        if (f - 1.0).abs() > 1e-6 {
            let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 20.0, thin: false };
            let before = xf.w(h);
            cam.zoom = (cam.zoom * f).clamp(0.005, 20.0);
            let xf2 = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 20.0, thin: false };
            cam.center += before - xf2.w(h);
        }
    }
    if resp.dragged_by(egui::PointerButton::Middle) || resp.dragged_by(egui::PointerButton::Secondary) {
        let d = resp.drag_delta();
        cam.center += DVec2::new(-d.x as f64, d.y as f64) / cam.zoom;
    }
    fe.cams.insert(key, cam);
    let xf = ViewXf { xf: Xf { rect, center: cam.center, zoom: cam.zoom, scale: 20.0, thin: false }, flip: matches!(fe.view, FeView::Back | FeView::Left), zoom: cam.zoom };
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 0.0, Color32::WHITE);
    let Some(def) = fe.def().cloned() else { return };
    let (solved, _) = fe.solved();
    let (ha, va) = view_axes(fe.view);
    let cursor = resp.hover_pos().map(|s| xf.w(s));
    let tol = xf.len(8.0);
    let ext = 1e6;
    let green = Color32::from_rgb(40, 150, 70);
    let mut hover_plane: Option<u32> = None;
    // Forms: projected edges.
    let mesh = fe.mesh(&app.doc.data);
    let to2 = |q: DVec3| -> DVec2 {
        match fe.view {
            FeView::Plan | FeView::Ceiling => DVec2::new(q.x, q.y),
            FeView::Front | FeView::Back => DVec2::new(q.x, q.z),
            _ => DVec2::new(q.y, q.z),
        }
    };
    for m in mesh.by_material.values() {
        let mut shape = egui::Mesh::default();
        for tri in m.indices.chunks(3) {
            let i = shape.vertices.len() as u32;
            for k in 0..3 {
                shape.colored_vertex(xf.s(to2(m.positions[tri[k] as usize])), Color32::from_rgba_unmultiplied(150, 160, 175, 40));
            }
            shape.add_triangle(i, i + 1, i + 2);
        }
        painter.add(egui::Shape::mesh(shape));
    }
    // Selected form outline.
    if let FeSel::Form(k) = fe.sel {
        if let Some(f) = def.forms.get(k) {
            // The form's edges: mesh edges on the boundary or between faces meeting at an angle
            // (curved faces stay smooth), projected into the view; edges seen end-on vanish.
            let set = family_def::form_mesh(&f.form, &solved, "x");
            type K = (i64, i64, i64);
            let key = |p: DVec3| ((p.x * 4.0).round() as i64, (p.y * 4.0).round() as i64, (p.z * 4.0).round() as i64);
            let mut edges: std::collections::HashMap<(K, K), (DVec3, DVec3, Vec<DVec3>)> = std::collections::HashMap::new();
            for m in set.by_material.values() {
                for tri in m.indices.chunks(3) {
                    let v: Vec<DVec3> = (0..3).map(|j| m.positions[tri[j] as usize]).collect();
                    let n = (v[1] - v[0]).cross(v[2] - v[0]);
                    if n.length() < 1e-9 {
                        continue;
                    }
                    for k in 0..3 {
                        let (a, b) = (v[k], v[(k + 1) % 3]);
                        let (ka, kb) = (key(a), key(b));
                        let e = if ka < kb { (ka, kb) } else { (kb, ka) };
                        edges.entry(e).or_insert((a, b, Vec::new())).2.push(n.normalize());
                    }
                }
            }
            let mut drawn: std::collections::HashSet<((i64, i64), (i64, i64))> = std::collections::HashSet::new();
            for (a, b, normals) in edges.into_values() {
                let sharp = normals.len() != 2 || normals[0].dot(normals[1]) < 0.94;
                let (pa, pb) = (to2(a), to2(b));
                if !sharp || pa.distance(pb) < 1e-3 {
                    continue;
                }
                let k2 = |p: DVec2| ((p.x * 4.0).round() as i64, (p.y * 4.0).round() as i64);
                let (ka, kb) = (k2(pa), k2(pb));
                if drawn.insert(if ka < kb { (ka, kb) } else { (kb, ka) }) {
                    painter.line_segment([xf.s(pa), xf.s(pb)], Stroke::new(1.6, style::SELECT));
                }
            }
        }
    }
    // Reference planes.
    for p in &def.planes {
        let v = solved.get(&p.id).copied().unwrap_or(p.default);
        let (a, b) = if p.axis == ha {
            (DVec2::new(v, -ext), DVec2::new(v, ext))
        } else if p.axis == va {
            (DVec2::new(-ext, v), DVec2::new(ext, v))
        } else {
            continue;
        };
        let near = cursor.is_some_and(|c| if p.axis == ha { (c.x - v).abs() < tol } else { (c.y - v).abs() < tol });
        if near && hover_plane.is_none() {
            hover_plane = Some(p.id);
        }
        let selected = fe.sel == FeSel::Plane(p.id) || fe.dim_planes.contains(&p.id);
        // In elevations the reference level is a level: a finite dash-dot line ending in a
        // target head with its name above and elevation below.
        if p.axis == Axis::Z && va == Axis::Z && p.name == "Ref. Level" {
            let col = if selected { style::SELECT } else if near { style::PRESELECT } else { Color32::from_rgb(20, 20, 20) };
            // Past the family geometry on both sides.
            let (u0, u1) = mesh.by_material.values().flat_map(|m| m.positions.iter()).map(|q| to2(*q).x).fold((-1200.0f64, 1200.0f64), |(a, b), x| (a.min(x - 600.0), b.max(x + 600.0)));
            let (sa, sb) = (xf.s(DVec2::new(u0, v)), xf.s(DVec2::new(u1, v)));
            let (l, r) = if sa.x < sb.x { (sa, sb) } else { (sb, sa) };
            canvas::paint_polyline(&painter, &[l, r], false, Stroke::new(1.0, col), rc_core::plan::Dash::DashDot, &xf.xf);
            let rad = 7.0;
            let c = r + vec2(rad, 0.0);
            painter.circle_stroke(c, rad, Stroke::new(1.0, col));
            for q in [0.0f32, 2.0] {
                let mut pts = vec![c];
                for k in 0..=8 {
                    let t = (q + k as f32 / 8.0) * std::f32::consts::FRAC_PI_2;
                    pts.push(c + vec2(t.cos(), -t.sin()) * rad);
                }
                painter.add(egui::Shape::convex_polygon(pts, col, Stroke::NONE));
            }
            let size = 12.0;
            let x = c.x - rad * 1.5;
            painter.text(pos2(x, c.y - 3.0), egui::Align2::RIGHT_BOTTOM, &p.name, egui::FontId::proportional(size), col);
            painter.text(pos2(x, c.y + 3.0), egui::Align2::RIGHT_TOP, app.doc.data.units.length(v), egui::FontId::proportional(size), col);
            continue;
        }
        // Halftone while sketching, as the reference app shows everything but the sketch.
        let idle = if matches!(fe.tool, FeTool::Select | FeTool::Dimension | FeTool::RefPlane) { green } else { Color32::from_rgb(170, 200, 178) };
        let col = if selected { style::SELECT } else if near { style::PRESELECT } else { idle };
        canvas::paint_polyline(&painter, &[xf.s(a), xf.s(b)], false, Stroke::new(1.0, col), rc_core::plan::Dash::DashDot, &xf.xf);
        // Plane names show only on the selected or highlighted plane.
        if !p.name.is_empty() && (selected || near) {
            let lp = if p.axis == ha { xf.s(DVec2::new(v, 0.0)) } else { xf.s(DVec2::new(0.0, v)) };
            let lp = if p.axis == ha { pos2(lp.x + 4.0, rect.top() + 14.0) } else { pos2(rect.left() + 6.0, lp.y - 4.0) };
            painter.text(lp, if p.axis == ha { egui::Align2::LEFT_TOP } else { egui::Align2::LEFT_BOTTOM }, &p.name, egui::FontId::proportional(11.0), col);
        }
    }
    // Dimensions.
    let mut hover_dim: Option<usize> = None;
    for (k, d) in def.dims.iter().enumerate() {
        let planes: Vec<&RefPlaneDef> = d.planes.iter().filter_map(|id| def.plane(*id)).collect();
        if planes.len() < 2 || planes[0].axis != ha && planes[0].axis != va {
            continue;
        }
        let horiz = planes[0].axis == ha;
        let vals: Vec<f64> = planes.iter().map(|p| solved.get(&p.id).copied().unwrap_or(p.default)).collect();
        // Dimension line placed outside the drawing, stacked per dimension.
        let off = -(900.0 + 260.0 * k as f64);
        let pts: Vec<Pos2> = vals.iter().map(|v| if horiz { xf.s(DVec2::new(*v, off)) } else { xf.s(DVec2::new(off, *v)) }).collect();
        let selected = fe.sel == FeSel::Dim(k);
        let near = cursor.is_some_and(|c| if horiz { (c.y - off).abs() < tol && c.x >= vals.iter().cloned().fold(f64::MAX, f64::min) && c.x <= vals.iter().cloned().fold(f64::MIN, f64::max) } else { (c.x - off).abs() < tol });
        if near {
            hover_dim = Some(k);
        }
        let col = if selected { style::SELECT } else if near { style::PRESELECT } else { Color32::from_rgb(30, 30, 30) };
        painter.line_segment([pts[0], *pts.last().unwrap()], Stroke::new(1.0, col));
        for q in &pts {
            painter.line_segment([*q + vec2(-4.0, 4.0), *q + vec2(4.0, -4.0)], Stroke::new(1.4, col));
        }
        for w in pts.windows(2).zip(vals.windows(2)) {
            let (sp, vv) = w;
            let mid = sp[0] + (sp[1] - sp[0]) / 2.0 + if horiz { vec2(0.0, -9.0) } else { vec2(-9.0, 0.0) };
            if !d.label.is_empty() && !d.equal {
                continue;
            }
            let text = if d.equal { "EQ".to_string() } else { app.doc.data.units.length((vv[1] - vv[0]).abs()) };
            painter.text(mid, if horiz { egui::Align2::CENTER_CENTER } else { egui::Align2::RIGHT_CENTER }, text, egui::FontId::proportional(11.0), col);
        }
        if !d.label.is_empty() {
            let mid = pts[0] + (*pts.last().unwrap() - pts[0]) / 2.0 + if horiz { vec2(0.0, -10.0) } else { vec2(-10.0, 0.0) };
            painter.text(mid, if horiz { egui::Align2::CENTER_CENTER } else { egui::Align2::RIGHT_CENTER }, format!("{} = {}", d.label, app.doc.data.units.length((vals[vals.len() - 1] - vals[0]).abs())), egui::FontId::proportional(11.5), Color32::from_rgb(20, 80, 180));
        }
        if d.locked {
            painter.text(pts[0] + vec2(-14.0, 0.0), egui::Align2::CENTER_CENTER, "🔒", egui::FontId::proportional(10.0), col);
        }
    }
    // Model lines (black) and reference lines (green), on their work planes, in every view.
    for (k, l) in def.lines.iter().enumerate() {
        let (a, b) = l.ends(&solved);
        let (a, b) = (to2(a), to2(b));
        if a.distance(b) < 1e-6 {
            continue;
        }
        let selected = fe.sel == FeSel::Line(k);
        let col = if selected { style::SELECT } else if l.reference { green } else { Color32::BLACK };
        painter.line_segment([xf.s(a), xf.s(b)], Stroke::new(if selected { 2.0 } else { 1.2 }, col));
    }
    // Symbolic lines (plan).
    if matches!(fe.view, FeView::Plan | FeView::Ceiling) {
        for (k, l) in def.symbolic.iter().enumerate() {
            let (a, b) = (pt2(l.a, &solved), pt2(l.b, &solved));
            painter.line_segment([xf.s(a), xf.s(b)], Stroke::new(if fe.sel == FeSel::Sym(k) { 2.0 } else { 1.2 }, if fe.sel == FeSel::Sym(k) { style::SELECT } else { Color32::BLACK }));
        }
    }
    // Snapped sketch point under the cursor.
    let snapped = cursor.map(|c| SketchPt { a: snap_loc(&def, &solved, ha, c.x, tol), b: snap_loc(&def, &solved, va, c.y, tol) });
    let snap_pos = snapped.map(|s| pt2(s, &solved));
    if fe.tool != FeTool::Select && fe.tool != FeTool::Dimension {
        if let (Some(sp), Some(s)) = (snap_pos, snapped) {
            let locked = matches!(s.a, Loc::Plane(_)) as u8 + matches!(s.b, Loc::Plane(_)) as u8;
            let col = if locked > 0 { style::SNAP } else { style::PREVIEW };
            painter.rect_stroke(Rect::from_center_size(xf.s(sp), vec2(9.0, 9.0)), 0.0, Stroke::new(1.5, col), egui::StrokeKind::Middle);
        }
        // Sweep: the finished path (halftone) and the profile plane across its first segment.
        if let Some(path) = fe.sweep_path.as_ref().filter(|_| matches!(fe.tool, FeTool::Sweep | FeTool::SweptBlend)) {
            let pp: Vec<DVec2> = path.iter().map(|p| pt2(*p, &solved)).collect();
            if pp.len() >= 2 {
                let half = Color32::from_rgb(232, 150, 210);
                let red = Color32::from_rgb(220, 30, 30);
                let line: Vec<Pos2> = pp.iter().map(|q| xf.s(to2(DVec3::new(q.x, q.y, 0.0)))).collect();
                painter.add(egui::Shape::line(line, Stroke::new(1.5, half)));
                let (o, n) = profile_frame(fe.tool, fe.sb_profile1.is_some(), &pp);
                // Swept Blend: the finished first profile, halftone, at the path start.
                if let Some(p1) = fe.sb_profile1.as_ref() {
                    let a = pp[0];
                    let ring: Vec<Pos2> = p1.iter().map(|q| { let w = a + n * q.x; xf.s(to2(DVec3::new(w.x, w.y, q.y))) }).collect();
                    painter.add(egui::Shape::closed_line(ring, Stroke::new(1.5, half)));
                }
                if matches!(fe.view, FeView::Plan | FeView::Ceiling) {
                    painter.line_segment([xf.s(o - n * 300.0), xf.s(o + n * 300.0)], Stroke::new(1.5, red));
                    painter.circle_filled(xf.s(o), 3.5, red);
                } else {
                    let c = xf.s(to2(DVec3::new(o.x, o.y, 0.0)));
                    painter.line_segment([c - vec2(9.0, 0.0), c + vec2(9.0, 0.0)], Stroke::new(1.5, red));
                    painter.line_segment([c - vec2(0.0, 9.0), c + vec2(0.0, 9.0)], Stroke::new(1.5, red));
                    painter.circle_filled(c, 3.0, red);
                }
            }
        }
        // Current sketch (magenta, as sketch lines are).
        let color = if fe.void_mode { Color32::from_rgb(230, 120, 30) } else { Color32::from_rgb(220, 0, 160) };
        let placed: Vec<Pos2> = fe.pts.iter().map(|p| xf.s(pt2(*p, &solved))).collect();
        if fe.closed {
            painter.add(egui::Shape::closed_line(placed, Stroke::new(1.8, color)));
        } else {
            match (app.opts.draw_mode, fe.pts.first().map(|p| pt2(*p, &solved)), snap_pos) {
                (crate::tools::DrawMode::Rect, Some(a), Some(b)) if fe.pts.len() == 1 => {
                    let r = Rect::from_two_pos(xf.s(a), xf.s(b));
                    painter.rect_stroke(r, 0.0, Stroke::new(1.8, color), egui::StrokeKind::Middle);
                }
                (crate::tools::DrawMode::Circle, Some(c), Some(b)) if fe.pts.len() == 1 => {
                    painter.circle_stroke(xf.s(c), (c.distance(b) * xf.zoom) as f32, Stroke::new(1.8, color));
                }
                _ => {
                    let pts: Vec<Pos2> = placed.into_iter().chain(snap_pos.filter(|_| !fe.chain_ended).map(|p| xf.s(p))).collect();
                    painter.add(egui::Shape::line(pts, Stroke::new(1.8, color)));
                }
            }
        }
        if let Some(bottom) = &fe.blend_bottom {
            let v: Vec<Pos2> = bottom.iter().map(|p| xf.s(pt2(*p, &solved))).collect();
            painter.add(egui::Shape::closed_line(v, Stroke::new(1.2, color.gamma_multiply(0.6))));
        }
    }
    let clicked = resp.clicked_by(egui::PointerButton::Primary);
    match fe.tool {
        FeTool::Select => {
            if clicked {
                fe.sel = if let Some(d) = hover_dim {
                    FeSel::Dim(d)
                } else if let Some(p) = hover_plane {
                    FeSel::Plane(p)
                } else {
                    // Forms under the cursor (projected triangles).
                    let mut hit = FeSel::None;
                    if let Some(c) = cursor {
                        for (k, f) in def.forms.iter().enumerate().rev() {
                            let set = family_def::form_mesh(&f.form, &solved, "x");
                            let inside = set.by_material.values().any(|m| {
                                m.indices.chunks(3).any(|t| {
                                    let tri: Vec<DVec2> = (0..3).map(|j| to2(m.positions[t[j] as usize])).collect();
                                    rc_core::geom::contains(&tri, c)
                                })
                            });
                            if inside {
                                hit = FeSel::Form(k);
                                break;
                            }
                        }
                        if hit == FeSel::None {
                            for (k, l) in def.lines.iter().enumerate() {
                                let (a, b) = l.ends(&solved);
                                let (a, b) = (to2(a), to2(b));
                                if a.distance(b) > 1e-6 && rc_core::geom::distance_to_segment(a, b, c) < tol {
                                    hit = FeSel::Line(k);
                                }
                            }
                        }
                        if hit == FeSel::None && matches!(fe.view, FeView::Plan | FeView::Ceiling) {
                            for (k, l) in def.symbolic.iter().enumerate() {
                                if rc_core::geom::distance_to_segment(pt2(l.a, &solved), pt2(l.b, &solved), c) < tol {
                                    hit = FeSel::Sym(k);
                                }
                            }
                        }
                    }
                    hit
                };
            }
            // Drag a free reference plane.
            if let (FeSel::Plane(id), true) = (fe.sel, resp.dragged_by(egui::PointerButton::Primary)) {
                if let Some(c) = cursor {
                    let axis = def.plane(id).map(|p| p.axis);
                    let driven = def.dims.iter().any(|d| d.planes.contains(&id) && (!d.label.is_empty() || d.locked || d.equal));
                    if let (Some(axis), false) = (axis, def.plane(id).is_some_and(|p| p.fixed)) {
                        let v = if axis == ha { c.x } else { c.y };
                        if resp.drag_started() {
                            fe.checkpoint();
                        }
                        if let Some(p) = fe.family.definition.as_mut().and_then(|d| d.planes.iter_mut().find(|p| p.id == id)) {
                            p.default = (v / 5.0).round() * 5.0;
                        }
                        if driven {
                            fe.message = Some("This plane is driven by a dimension; its position follows the parameters.".into());
                        }
                    }
                }
            }
        }
        FeTool::RefPlane => {
            if let (true, Some(c)) = (clicked, cursor) {
                if fe.pts.is_empty() {
                    fe.pts.push(SketchPt { a: Loc::Value(c.x), b: Loc::Value(c.y) });
                } else {
                    let a = pt2(fe.pts[0], &solved);
                    let d = c - a;
                    let vertical = d.y.abs() > d.x.abs();
                    let (axis, pos) = if vertical { (ha, (a.x + c.x) / 2.0) } else { (va, (a.y + c.y) / 2.0) };
                    fe.checkpoint();
                    if let Some(def) = fe.family.definition.as_mut() {
                        let id = def.next_plane_id();
                        def.planes.push(RefPlaneDef { id, name: String::new(), axis, default: (pos / 5.0).round() * 5.0, fixed: false });
                        fe.sel = FeSel::Plane(id);
                    }
                    fe.pts.clear();
                }
            }
        }
        FeTool::Dimension => {
            if clicked {
                match hover_plane {
                    Some(p) => {
                        let axis = def.plane(p).map(|x| x.axis);
                        let first_axis = fe.dim_planes.first().and_then(|f| def.plane(*f)).map(|x| x.axis);
                        if first_axis.is_none() || first_axis == axis {
                            if !fe.dim_planes.contains(&p) {
                                fe.dim_planes.push(p);
                            }
                        } else {
                            fe.message = Some("Dimension references must be parallel planes.".into());
                        }
                    }
                    None => {
                        if fe.dim_planes.len() >= 2 {
                            let mut planes = fe.dim_planes.clone();
                            planes.sort_by(|a, b| solved.get(a).copied().unwrap_or(0.0).total_cmp(&solved.get(b).copied().unwrap_or(0.0)));
                            fe.checkpoint();
                            if let Some(def) = fe.family.definition.as_mut() {
                                def.dims.push(DimDef { planes, label: String::new(), equal: false, locked: false });
                                fe.sel = FeSel::Dim(def.dims.len() - 1);
                            }
                            fe.dim_planes.clear();
                        }
                    }
                }
            }
        }
        FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SweptBlend | FeTool::SymbolicLine | FeTool::ModelLine | FeTool::RefLine => {
            let mode = app.opts.draw_mode;
            let profile = matches!(fe.tool, FeTool::Extrusion | FeTool::Blend | FeTool::Revolve) || (matches!(fe.tool, FeTool::Sweep | FeTool::SweptBlend) && fe.sweep_path.is_some());
            if let (true, Some(s), false) = (clicked, snapped, fe.closed) {
                let close = fe.pts.len() >= 3 && fe.pts.first().is_some_and(|f| pt2(*f, &solved).distance(pt2(s, &solved)) < tol) && (!matches!(fe.tool, FeTool::Sweep | FeTool::SweptBlend) || fe.sweep_path.is_some());
                if profile && mode == crate::tools::DrawMode::Rect && fe.pts.len() == 1 {
                    // Rectangle: its corners keep the plane locks of both clicks.
                    let a = fe.pts[0];
                    fe.pts = vec![a, SketchPt { a: s.a, b: a.b }, s, SketchPt { a: a.a, b: s.b }];
                    fe.closed = true;
                } else if profile && mode == crate::tools::DrawMode::Circle && fe.pts.len() == 1 {
                    let c = pt2(fe.pts[0], &solved);
                    let r = c.distance(pt2(s, &solved));
                    if r > 1.0 {
                        fe.pts = (0..32)
                            .map(|k| {
                                let t = k as f64 / 32.0 * std::f64::consts::TAU;
                                SketchPt { a: Loc::Value(c.x + r * t.cos()), b: Loc::Value(c.y + r * t.sin()) }
                            })
                            .collect();
                        fe.closed = true;
                    }
                } else if close {
                    fe.closed = true;
                } else {
                    fe.chain_ended = false;
                    fe.pts.push(s);
                    if matches!(fe.tool, FeTool::SymbolicLine | FeTool::ModelLine | FeTool::RefLine) && fe.pts.len() == 2 {
                        fe.checkpoint();
                        let (a, b) = (fe.pts[0], fe.pts[1]);
                        let (tool, plane) = (fe.tool, fe.view.sketch_plane().unwrap_or(SketchPlane::XY));
                        if let Some(def) = fe.family.definition.as_mut() {
                            match tool {
                                FeTool::SymbolicLine => def.symbolic.push(SymLine { a, b }),
                                _ => def.lines.push(family_def::FamLine { plane, a, b, reference: tool == FeTool::RefLine }),
                            }
                        }
                        // Chain: the next line starts where this one ended.
                        fe.pts = if app.opts.chain { vec![b] } else { Vec::new() };
                    }
                }
            }
        }
    }
}

/// Ends the current sketch and creates the form.
fn finish_sketch(fe: &mut FamilyEditor) {
    let Some(plane) = fe.view.sketch_plane() else { return };
    let void = fe.void_mode;
    let pts = std::mem::take(&mut fe.pts);
    fe.closed = false;
    fe.chain_ended = false;
    let n = fe.def().map(|d| d.forms.len()).unwrap_or(0) + 1;
    let form = match fe.tool {
        FeTool::Extrusion if pts.len() >= 3 => {
            // Extrude between the work plane's natural limits: Ref. Level → Top in plan, Front → Back
            // in front views, Left → Right in right views (falling back to fixed depths).
            let toward_viewer = match fe.view {
                FeView::Front | FeView::Left => -1.0,
                _ => 1.0,
            };
            let (start, end) = (Loc::Value(0.0), Loc::Value(fe.depth * toward_viewer));
            Some(Form::Extrusion { plane, profile: pts, start, end })
        }
        FeTool::Blend if pts.len() >= 3 => {
            if fe.blend_bottom.is_none() {
                fe.blend_bottom = Some(pts);
                return;
            }
            let bottom = fe.blend_bottom.take().unwrap();
            let def = fe.def().cloned().unwrap_or_default();
            let named = |n: &str| def.planes.iter().find(|p| p.name == n).map(|p| Loc::Plane(p.id));
            Some(Form::Blend { bottom, top: pts, start: named("Ref. Level").unwrap_or(Loc::Value(0.0)), end: named("Top").unwrap_or(Loc::Value(1000.0)) })
        }
        FeTool::Revolve if pts.len() >= 3 && plane == SketchPlane::XZ => {
            let def = fe.def().cloned().unwrap_or_default();
            let cx = def.planes.iter().find(|p| p.name == "Center (Left/Right)").map(|p| Loc::Plane(p.id)).unwrap_or(Loc::Value(0.0));
            Some(Form::Revolve { profile: pts, axis: SketchPt { a: cx, b: Loc::Value(0.0) }, angle_deg: 360.0 })
        }
        FeTool::Sweep | FeTool::SweptBlend if fe.sweep_path.is_none() => {
            // The path is done; its profile is sketched next, in a view across the path.
            if pts.len() < 2 || plane != SketchPlane::XY {
                fe.message = Some(if plane != SketchPlane::XY { "Sweep paths are sketched in the Ref. Level view.".into() } else { "Sketch the sweep path first.".into() });
                fe.pts = pts;
                return;
            }
            if fe.tool == FeTool::SweptBlend && pts.len() != 2 {
                fe.message = Some("A swept blend path must be a single line.".into());
                fe.pts = pts;
                return;
            }
            let (solved, _) = fe.solved();
            let pp: Vec<DVec2> = pts.iter().map(|p| pt2(*p, &solved)).collect();
            fe.goto_view = profile_views(&pp);
            fe.sweep_path = Some(pts);
            fe.message = None;
            return;
        }
        FeTool::Sweep | FeTool::SweptBlend => {
            if pts.len() < 3 || plane == SketchPlane::XY {
                fe.message = Some("Sketch a closed profile in a view where the profile plane is parallel to the screen.".into());
                if plane == SketchPlane::XY {
                    let (solved, _) = fe.solved();
                    let pp: Vec<DVec2> = fe.sweep_path.iter().flatten().map(|p| pt2(*p, &solved)).collect();
                    fe.goto_view = profile_views(&pp);
                }
                fe.pts = pts;
                return;
            }
            let path = fe.sweep_path.clone().unwrap_or_default();
            let (solved, _) = fe.solved();
            let pp: Vec<DVec2> = path.iter().map(|p| pt2(*p, &solved)).collect();
            let (o, n) = profile_frame(fe.tool, fe.sb_profile1.is_some(), &pp);
            // The view's horizontal axis in plan.
            let e = if plane == SketchPlane::XZ { DVec2::X } else { DVec2::Y };
            let profile: Vec<DVec2> = pts
                .iter()
                .map(|p| {
                    let q = pt2(*p, &solved);
                    DVec2::new((e * (q.x - o.dot(e))).dot(n), q.y)
                })
                .collect();
            if fe.tool == FeTool::SweptBlend && fe.sb_profile1.is_none() {
                // Profile 1 is done; Profile 2 is sketched at the path's end.
                fe.sb_profile1 = Some(profile);
                fe.message = None;
                return;
            }
            fe.sweep_path = None;
            match fe.sb_profile1.take() {
                Some(profile1) => Some(Form::SweptBlend { path, z: Loc::Value(0.0), profile1, profile2: profile }),
                None => Some(Form::Sweep { path, z: Loc::Value(0.0), width: 50.0, height: 50.0, profile }),
            }
        }
        FeTool::Revolve => {
            fe.message = Some("Revolves are sketched in the Front view.".into());
            None
        }
        _ => None,
    };
    if let Some(form) = form {
        let kind = form.kind_label();
        fe.checkpoint();
        if let Some(def) = fe.family.definition.as_mut() {
            def.forms.push(FormDef { name: format!("{}{} {}", if void { "Void " } else { "" }, kind, n), form, void, material: String::new(), visible: String::new() });
            fe.sel = FeSel::Form(def.forms.len() - 1);
        }
        fe.message = None;
    }
}

fn delete_selected(fe: &mut FamilyEditor) {
    let sel = fe.sel;
    let Some(def) = fe.family.definition.clone() else { return };
    match sel {
        FeSel::Plane(id) => {
            if def.plane(id).is_some_and(|p| p.fixed) {
                fe.message = Some("Origin planes cannot be deleted.".into());
                return;
            }
            let used = def.forms.iter().any(|f| format!("{:?}", f.form).contains(&format!("Plane({id})")));
            if used {
                fe.message = Some("The plane is referenced by a form. Delete the form first.".into());
                return;
            }
            fe.checkpoint();
            let d = fe.family.definition.as_mut().unwrap();
            d.planes.retain(|p| p.id != id);
            d.dims.retain(|x| !x.planes.contains(&id));
        }
        FeSel::Dim(k) => {
            fe.checkpoint();
            fe.family.definition.as_mut().unwrap().dims.remove(k);
        }
        FeSel::Form(k) => {
            fe.checkpoint();
            fe.family.definition.as_mut().unwrap().forms.remove(k);
        }
        FeSel::Line(k) => {
            fe.checkpoint();
            fe.family.definition.as_mut().unwrap().lines.remove(k);
        }
        FeSel::Sym(k) => {
            fe.checkpoint();
            fe.family.definition.as_mut().unwrap().symbolic.remove(k);
        }
        FeSel::None => return,
    }
    fe.sel = FeSel::None;
}

/// An extent of a form: its length in project units, or the plane it is locked to.
fn loc_value_editor(ui: &mut egui::Ui, id: &str, def: &FamilyDef, solved: &family_def::Solved, units: &rc_core::units::Units, l: &mut Loc) -> bool {
    match l {
        Loc::Value(v) => {
            let key = egui::Id::new(("fe-loc", id));
            let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| units.length(*v));
            let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(ui.available_width() - 4.0));
            if r.has_focus() {
                ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
            }
            if r.lost_focus() {
                ui.memory_mut(|m| m.data.remove::<String>(key));
                if let Some(x) = units.parse(&s, ParamKind::Length) {
                    if (x - *v).abs() > 1e-9 {
                        *v = x;
                        return true;
                    }
                }
            }
            false
        }
        Loc::Plane(p) => {
            let v = solved.get(p).copied().unwrap_or(0.0);
            let name = def.plane(*p).map(|x| x.name.clone()).unwrap_or_default();
            ui.label(egui::RichText::new(units.length(v)).color(style::text_dim())).on_hover_text(format!("Locked to {name}"));
            false
        }
    }
}

#[allow(dead_code)]
fn loc_editor(ui: &mut egui::Ui, id: impl std::hash::Hash + std::fmt::Debug, def: &FamilyDef, axis: Axis, l: &mut Loc) -> bool {
    let mut changed = false;
    let label = match l {
        Loc::Plane(p) => def.plane(*p).map(|x| if x.name.is_empty() { format!("Plane {}", x.id) } else { x.name.clone() }).unwrap_or_default(),
        Loc::Value(v) => format!("{v:.0} mm"),
    };
    ui.horizontal(|ui| {
        egui::ComboBox::from_id_salt(id).selected_text(label).width(150.0).show_ui(ui, |ui| {
            for p in def.planes.iter().filter(|p| p.axis == axis) {
                let name = if p.name.is_empty() { format!("Plane {}", p.id) } else { p.name.clone() };
                if ui.selectable_label(*l == Loc::Plane(p.id), name).clicked() {
                    *l = Loc::Plane(p.id);
                    changed = true;
                }
            }
            if ui.selectable_label(matches!(l, Loc::Value(_)), "Fixed value").clicked() && !matches!(l, Loc::Value(_)) {
                *l = Loc::Value(0.0);
                changed = true;
            }
        });
        if let Loc::Value(v) = l {
            if ui.add(egui::DragValue::new(v).speed(5.0).suffix(" mm")).changed() {
                changed = true;
            }
        }
    });
    changed
}

/// Parameter Properties: a new family parameter, or the one being edited.
#[derive(Clone, Debug)]
pub struct ParamDialog {
    /// The parameter's name before editing (None = a new parameter).
    pub original: Option<String>,
    pub name: String,
    pub kind: ParamKind,
    pub instance: bool,
    pub group: String,
    pub reporting: bool,
}

const PARAM_GROUPS: [&str; 12] = ["Constraints", "Construction", "Data", "Dimensions", "General", "Graphics", "Identity Data", "Materials and Finishes", "Other", "Phasing", "Text", "Visibility"];

/// The small glyphs of the Family Types tool buttons (drawn here, not copied artwork).
#[derive(Clone, Copy, PartialEq)]
enum TypesGlyph {
    NewType,
    Rename,
    Delete,
    Edit,
    NewParam,
    Up,
    Down,
    SortAsc,
    SortDesc,
    Lookup,
}

fn glyph_button(ui: &mut egui::Ui, g: TypesGlyph, enabled: bool, tip: &str) -> bool {
    let (r, resp) = ui.allocate_exact_size(vec2(24.0, 22.0), if enabled { Sense::click() } else { Sense::hover() });
    let p = ui.painter();
    if enabled && resp.hovered() {
        p.rect_filled(r, 0.0, style::hover());
        p.rect_stroke(r, 0.0, Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    }
    let c = r.center();
    let ink = if enabled { style::text() } else { Color32::from_gray(175) };
    let blue = if enabled { Color32::from_rgb(40, 110, 200) } else { Color32::from_gray(185) };
    let red = if enabled { Color32::from_rgb(210, 40, 40) } else { Color32::from_gray(185) };
    let gold = if enabled { Color32::from_rgb(235, 170, 20) } else { Color32::from_gray(190) };
    let s = Stroke::new(1.2, ink);
    let page = |p: &egui::Painter| {
        let pr = Rect::from_center_size(c + vec2(-1.0, 1.0), vec2(10.0, 13.0));
        p.rect_filled(pr, 0.0, Color32::WHITE);
        p.rect_stroke(pr, 0.0, s, egui::StrokeKind::Inside);
    };
    let star = |p: &egui::Painter, at: Pos2| {
        for k in 0..4 {
            let a = k as f32 * std::f32::consts::FRAC_PI_4;
            let d = vec2(a.cos(), a.sin()) * 3.5;
            p.line_segment([at - d, at + d], Stroke::new(1.4, gold));
        }
    };
    let arrow = |p: &egui::Painter, up: bool| {
        let dy = if up { -1.0 } else { 1.0 };
        p.line_segment([c + vec2(0.0, -5.0 * dy), c + vec2(0.0, 5.0 * dy)], Stroke::new(1.6, blue));
        p.line_segment([c + vec2(0.0, 5.0 * dy), c + vec2(-4.0, 1.0 * dy)], Stroke::new(1.6, blue));
        p.line_segment([c + vec2(0.0, 5.0 * dy), c + vec2(4.0, 1.0 * dy)], Stroke::new(1.6, blue));
    };
    match g {
        TypesGlyph::NewType | TypesGlyph::NewParam => {
            page(p);
            if g == TypesGlyph::NewParam {
                p.text(c + vec2(-1.0, 2.0), egui::Align2::CENTER_CENTER, "P", style::bold(8.0), ink);
            }
            star(p, c + vec2(5.0, -5.0));
        }
        TypesGlyph::Rename => {
            p.text(c + vec2(-3.0, 0.0), egui::Align2::CENTER_CENTER, "AI", style::bold(10.0), ink);
            p.line_segment([c + vec2(6.0, -6.0), c + vec2(6.0, 6.0)], Stroke::new(1.2, blue));
        }
        TypesGlyph::Delete => {
            p.line_segment([c + vec2(-5.0, -5.0), c + vec2(5.0, 5.0)], Stroke::new(2.0, red));
            p.line_segment([c + vec2(5.0, -5.0), c + vec2(-5.0, 5.0)], Stroke::new(2.0, red));
        }
        TypesGlyph::Edit => {
            page(p);
            p.line_segment([c + vec2(-2.0, 6.0), c + vec2(6.0, -4.0)], Stroke::new(2.0, gold));
        }
        TypesGlyph::Up => arrow(p, true),
        TypesGlyph::Down => arrow(p, false),
        TypesGlyph::SortAsc | TypesGlyph::SortDesc => {
            let (a, b) = if g == TypesGlyph::SortAsc { ("A", "Z") } else { ("Z", "A") };
            p.text(c + vec2(-4.0, -4.0), egui::Align2::CENTER_CENTER, a, style::bold(7.5), ink);
            p.text(c + vec2(-4.0, 5.0), egui::Align2::CENTER_CENTER, b, style::bold(7.5), ink);
            p.line_segment([c + vec2(4.0, -6.0), c + vec2(4.0, 6.0)], Stroke::new(1.4, blue));
            p.line_segment([c + vec2(4.0, 6.0), c + vec2(1.5, 3.0)], Stroke::new(1.4, blue));
            p.line_segment([c + vec2(4.0, 6.0), c + vec2(6.5, 3.0)], Stroke::new(1.4, blue));
        }
        TypesGlyph::Lookup => {
            let t = Rect::from_center_size(c, vec2(14.0, 12.0));
            p.rect_filled(t, 0.0, Color32::WHITE);
            p.rect_stroke(t, 0.0, s, egui::StrokeKind::Inside);
            p.line_segment([pos2(t.left(), t.top() + 4.0), pos2(t.right(), t.top() + 4.0)], s);
            p.line_segment([pos2(t.left(), t.top() + 8.0), pos2(t.right(), t.top() + 8.0)], s);
            p.line_segment([pos2(t.left() + 5.0, t.top()), pos2(t.left() + 5.0, t.bottom())], s);
        }
    }
    let resp = resp.on_hover_text(tip);
    enabled && resp.clicked()
}

/// Renames a family parameter everywhere it is used: type values, formulas, labels and forms.
fn rename_param(fam: &mut Family, old: &str, new: &str) {
    let swap = |s: &str| -> String {
        // Whole-word replacement (parameter names may contain spaces, so match the full name).
        let mut out = String::new();
        let mut rest = s;
        while let Some(i) = rest.find(old) {
            let before = rest[..i].chars().last();
            let after = rest[i + old.len()..].chars().next();
            let word = |c: Option<char>| c.is_some_and(|c| c.is_alphanumeric() || c == '_');
            out.push_str(&rest[..i]);
            out.push_str(if word(before) || word(after) { old } else { new });
            rest = &rest[i + old.len()..];
        }
        out.push_str(rest);
        out
    };
    for p in &mut fam.params {
        if p.name == old {
            p.name = new.to_string();
        }
        p.formula = swap(&p.formula);
    }
    for t in &mut fam.types {
        if let Some(v) = t.values.remove(old) {
            t.values.insert(new.to_string(), v);
        }
    }
    if let Some(d) = fam.definition.as_mut() {
        for x in &mut d.dims {
            if x.label == old {
                x.label = new.to_string();
            }
        }
        for f in &mut d.forms {
            if f.material == old {
                f.material = new.to_string();
            }
            if f.visible == old {
                f.visible = new.to_string();
            }
        }
    }
}

/// Parameter Properties, over Family Types.
fn param_properties_dialog(fe: &mut FamilyEditor, ctx: &egui::Context) {
    let Some(mut d) = fe.param_dialog.clone() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    crate::dialogs::window_pub("Parameter Properties").open(&mut open).resizable(false).default_width(470.0).show(ctx, |ui| {
        ui.spacing_mut().item_spacing.y = 5.0;
        let group_box = |ui: &mut egui::Ui, title: &str, add: &mut dyn FnMut(&mut egui::Ui)| {
            ui.label(title);
            egui::Frame::new().stroke(Stroke::new(1.0, style::border())).inner_margin(8.0).show(ui, |ui| {
                ui.set_width(ui.available_width());
                add(ui);
            });
        };
        group_box(ui, "Parameter Type", &mut |ui| {
            let mut family = true;
            ui.radio_value(&mut family, true, "Family parameter");
            ui.label(egui::RichText::new("(Cannot appear in schedules or tags)").color(style::text_dim()));
            ui.add_enabled_ui(false, |ui| {
                ui.radio_value(&mut family, false, "Shared parameter");
                ui.label(egui::RichText::new("(Can be shared by multiple projects and families, exported to ODBC, and appear in schedules and tags)").color(style::text_dim()));
                ui.horizontal(|ui| {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let _ = ui.button("Export...");
                        let _ = ui.button("Select...");
                    });
                });
            });
        });
        group_box(ui, "Parameter Data", &mut |ui| {
            egui::Grid::new("fe-pp").num_columns(2).spacing(vec2(16.0, 6.0)).show(ui, |ui| {
                ui.vertical(|ui| {
                    ui.label("Name:");
                    let r = ui.add(egui::TextEdit::singleline(&mut d.name).desired_width(220.0));
                    if d.original.is_none() && d.name.is_empty() {
                        r.request_focus();
                    }
                    ui.label("Discipline:");
                    ui.add_enabled_ui(false, |ui| {
                        egui::ComboBox::from_id_salt("fe-pp-disc").selected_text("Common").width(220.0).show_ui(ui, |_| {});
                    });
                    ui.label("Type of Parameter:");
                    let fixed = d.original.is_some();
                    ui.add_enabled_ui(!fixed, |ui| {
                        egui::ComboBox::from_id_salt("fe-pp-kind").selected_text(d.kind.label()).width(220.0).show_ui(ui, |ui| {
                            for k in ParamKind::USER {
                                ui.selectable_value(&mut d.kind, k, k.label());
                            }
                        });
                    });
                    ui.label("Group parameter under:");
                    egui::ComboBox::from_id_salt("fe-pp-group").selected_text(&d.group).width(220.0).show_ui(ui, |ui| {
                        for g in PARAM_GROUPS {
                            ui.selectable_value(&mut d.group, g.to_string(), g);
                        }
                    });
                });
                ui.vertical(|ui| {
                    ui.add_space(14.0);
                    ui.radio_value(&mut d.instance, false, "Type");
                    ui.radio_value(&mut d.instance, true, "Instance");
                    ui.add_space(8.0);
                    ui.add_enabled_ui(d.instance && matches!(d.kind, ParamKind::Length | ParamKind::Angle), |ui| {
                        crate::style::check(ui, &mut d.reporting, "Reporting Parameter");
                    });
                    ui.label(egui::RichText::new("(Can be used to extract value\nfrom a geometric condition and\nreport it in a formula or as a\nschedulable parameter)").color(style::text_dim()).size(11.0));
                });
                ui.end_row();
            });
        });
        ui.label("Tooltip Description:");
        egui::Frame::new().stroke(Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.label(egui::RichText::new("<No tooltip description. Edit this parameter to write a custom tooltip. Custom tooltips have a limit of 250 characters.>").color(style::text_dim()));
        });
        ui.horizontal(|ui| {
            ui.add_enabled_ui(false, |ui| {
                let _ = ui.button("Edit Tooltip...");
            });
        });
        ui.add_space(4.0);
        ui.label(egui::RichText::new("How do I create family parameters?").color(Color32::from_rgb(0, 102, 204)));
        ui.add_space(6.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            let _ = crate::dialogs::dlg_button(ui, "Help", false, false);
            if crate::dialogs::dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if crate::dialogs::dlg_button(ui, "OK", true, true) || ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                ok = true;
            }
        });
    });
    if ok {
        let name = d.name.trim().to_string();
        let taken = fe.family.params.iter().any(|p| p.name == name && Some(&p.name) != d.original.as_ref());
        if name.is_empty() {
            fe.message = Some("The parameter name cannot be empty.".into());
            fe.param_dialog = Some(d);
            return;
        }
        if taken || name.contains(['[', ']', ':', '{', '}', '|', ';', '<', '>', '?', '`', '~']) {
            fe.message = Some(if taken { format!("Parameter name \"{name}\" is already in use.") } else { "Parameter names cannot contain any of these characters: \\ : { } [ ] | ; < > ? ` ~".into() });
            fe.param_dialog = Some(d);
            return;
        }
        fe.checkpoint();
        match d.original.clone() {
            Some(old) => {
                if old != name {
                    rename_param(&mut fe.family, &old, &name);
                }
                if let Some(p) = fe.family.params.iter_mut().find(|p| p.name == name) {
                    p.instance = d.instance;
                    p.group = d.group.clone();
                    p.reporting = d.reporting && d.instance;
                }
            }
            None => {
                let default = match d.kind {
                    ParamKind::YesNo => "Yes".to_string(),
                    ParamKind::Material => String::new(),
                    ParamKind::Text => String::new(),
                    _ => "0".to_string(),
                };
                fe.family.params.push(FamilyParameter { name: name.clone(), kind: d.kind, instance: d.instance, formula: String::new(), group: d.group.clone(), built_in: false, default, reporting: d.reporting && d.instance });
            }
        }
        fe.param_sel = Some(name);
        fe.message = None;
        fe.param_dialog = None;
    } else if cancel || !open {
        fe.param_dialog = None;
    } else {
        fe.param_dialog = Some(d);
    }
}

/// The Name / Rename dialog for family types.
fn type_name_dialog(fe: &mut FamilyEditor, ctx: &egui::Context) {
    let Some((rename, mut name)) = fe.type_name_dialog.clone() else { return };
    let (mut open, mut ok, mut cancel) = (true, false, false);
    let old = fe.ftype().name.clone();
    crate::dialogs::window_pub(if rename { "Rename" } else { "Name" }).open(&mut open).resizable(false).default_width(330.0).show(ctx, |ui| {
        egui::Grid::new("fe-tn").num_columns(2).spacing(vec2(8.0, 8.0)).show(ui, |ui| {
            if rename {
                ui.label("Old Name:");
                ui.label(&old);
                ui.end_row();
            }
            ui.label(if rename { "New Name:" } else { "Name:" });
            let r = ui.add(egui::TextEdit::singleline(&mut name).desired_width(220.0));
            if !r.has_focus() && !ui.memory(|m| m.has_focus(r.id)) && ui.ctx().memory(|m| m.focused().is_none()) {
                r.request_focus();
            }
            ui.end_row();
        });
        ui.add_space(6.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if crate::dialogs::dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if crate::dialogs::dlg_button(ui, "OK", true, true) || ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                ok = true;
            }
        });
    });
    if ok {
        let n = name.trim().to_string();
        let taken = fe.family.types.iter().enumerate().any(|(k, t)| t.name == n && !(rename && k == fe.type_idx));
        if n.is_empty() || taken {
            fe.message = Some(if taken { format!("The name \"{n}\" is already in use.") } else { "The name cannot be empty.".into() });
            fe.type_name_dialog = Some((rename, name));
            return;
        }
        fe.checkpoint();
        if rename {
            let k = fe.type_idx;
            fe.family.types[k].name = n;
        } else {
            let base = fe.ftype().clone();
            fe.family.types.push(FamilyType { id: 0, name: n, values: base.values });
            fe.type_idx = fe.family.types.len() - 1;
        }
        fe.message = None;
        fe.type_name_dialog = None;
    } else if cancel || !open {
        fe.type_name_dialog = None;
    } else {
        fe.type_name_dialog = Some((rename, name));
    }
}

/// The Family Types table: types, then each group's parameters with Value, Formula and Lock.
fn family_types(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let units = app.doc.data.units.clone();
    // Type name row with New Type, Rename Type and Delete Type.
    ui.horizontal(|ui| {
        ui.label("Type name:");
        let names: Vec<String> = fe.family.types.iter().map(|t| t.name.clone()).collect();
        egui::ComboBox::from_id_salt("fe-types").selected_text(names.get(fe.type_idx).cloned().unwrap_or_default()).width(ui.available_width() - 92.0).show_ui(ui, |ui| {
            for (k, n) in names.iter().enumerate() {
                if ui.selectable_label(fe.type_idx == k, n).clicked() {
                    fe.type_idx = k;
                    fe.scene_key += 1;
                }
            }
        });
        if glyph_button(ui, TypesGlyph::NewType, true, "New Type") {
            let name = rc_core::edit::unique_name(fe.family.types.iter().map(|t| t.name.clone()), &format!("{} 2", fe.ftype().name));
            fe.type_name_dialog = Some((false, name));
        }
        if glyph_button(ui, TypesGlyph::Rename, true, "Rename Type") {
            fe.type_name_dialog = Some((true, fe.ftype().name.clone()));
        }
        if glyph_button(ui, TypesGlyph::Delete, fe.family.types.len() > 1, "Delete Type") {
            fe.checkpoint();
            let k = fe.type_idx;
            fe.family.types.remove(k);
            fe.type_idx = 0;
        }
    });
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        let (r, _) = ui.allocate_exact_size(vec2(16.0, 16.0), Sense::hover());
        icons::paint(ui.painter(), r, Icon::Search, true);
        ui.add(egui::TextEdit::singleline(&mut fe.param_filter).hint_text("Search parameters").desired_width(ui.available_width()));
    });
    ui.add_space(4.0);
    // Parameters table.
    let r = Resolver::for_type(&fe.family, fe.ftype());
    let params = fe.family.params.clone();
    let filter = fe.param_filter.trim().to_lowercase();
    let mut set_value: Option<(String, String)> = None;
    let mut set_formula: Option<(String, String)> = None;
    let mut edit: Option<String> = None;
    let mut groups: Vec<(String, Vec<FamilyParameter>)> = Vec::new();
    for p in params.into_iter().filter(|p| filter.is_empty() || p.name.to_lowercase().contains(&filter)) {
        match groups.iter_mut().find(|g| g.0 == p.group) {
            Some(g) => g.1.push(p),
            None => groups.push((p.group.clone(), vec![p])),
        }
    }
    groups.sort_by_key(|g| PARAM_GROUPS.iter().position(|x| *x == g.0).unwrap_or(99));
    let w = ui.available_width();
    let cols = [w * 0.34, w * 0.25, w * 0.31, w * 0.10];
    let row_h = 22.0;
    let grid = Stroke::new(1.0, Color32::from_gray(205));
    let cell = |r: Rect, k: usize| -> Rect {
        let x0 = r.left() + cols[..k].iter().sum::<f32>();
        Rect::from_min_size(pos2(x0, r.top()), vec2(cols[k], r.height()))
    };
    // Header.
    let (hr, _) = ui.allocate_exact_size(vec2(w, row_h), Sense::hover());
    ui.painter().rect_filled(hr, 0.0, style::tab_idle());
    for (k, t) in ["Parameter", "Value", "Formula", "Lock"].iter().enumerate() {
        let c = cell(hr, k);
        ui.painter().rect_stroke(c, 0.0, grid, egui::StrokeKind::Inside);
        ui.painter().text(c.left_center() + vec2(6.0, 0.0), egui::Align2::LEFT_CENTER, *t, style::font(12.0), style::text());
    }
    let mut param_sel = fe.param_sel.clone();
    egui::ScrollArea::vertical().max_height(360.0).min_scrolled_height(360.0).auto_shrink([false, false]).id_salt("fe-types-table").show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 0.0;
        for (g, ps) in groups {
            let open_id = egui::Id::new(("fe-types-group", g.clone()));
            let mut open: bool = ui.memory(|m| m.data.get_temp(open_id)).unwrap_or(true);
            let (gr, gresp) = ui.allocate_exact_size(vec2(w, row_h), Sense::click());
            ui.painter().rect_filled(gr, 0.0, Color32::from_gray(236));
            ui.painter().rect_stroke(gr, 0.0, grid, egui::StrokeKind::Inside);
            ui.painter().text(gr.left_center() + vec2(6.0, 0.0), egui::Align2::LEFT_CENTER, &g, style::bold(12.0), style::text());
            // Collapse chevron at the right, as the group rows show.
            let c = gr.right_center() - vec2(12.0, 0.0);
            let d = if open { -1.0 } else { 1.0 };
            ui.painter().line_segment([c + vec2(-4.0, 2.0 * -d), c + vec2(0.0, 2.0 * d)], Stroke::new(1.2, style::text()));
            ui.painter().line_segment([c + vec2(0.0, 2.0 * d), c + vec2(4.0, 2.0 * -d)], Stroke::new(1.2, style::text()));
            if gresp.clicked() {
                open = !open;
                ui.memory_mut(|m| m.data.insert_temp(open_id, open));
            }
            if !open {
                continue;
            }
            for p in ps {
                let (rr, rresp) = ui.allocate_exact_size(vec2(w, row_h), Sense::click());
                let selected = param_sel.as_deref() == Some(p.name.as_str());
                let name_cell = cell(rr, 0);
                ui.painter().rect_filled(name_cell, 0.0, if selected { style::accent_light() } else { style::field() });
                for k in 0..4 {
                    ui.painter().rect_stroke(cell(rr, k), 0.0, grid, egui::StrokeKind::Inside);
                }
                let tag = if p.instance { " (default)" } else { "" };
                let label = if p.reporting { format!("{}{} (Report)", p.name, tag) } else { format!("{}{}", p.name, tag) };
                ui.painter().with_clip_rect(name_cell).text(name_cell.left_center() + vec2(6.0, 0.0), egui::Align2::LEFT_CENTER, label, style::font(12.0), style::text());
                if rresp.clicked() {
                    param_sel = Some(p.name.clone());
                }
                if rresp.double_clicked() && !p.built_in {
                    edit = Some(p.name.clone());
                }
                // Value.
                let vc = cell(rr, 1).shrink2(vec2(3.0, 2.0));
                // Lengths in project units, as the table shows them.
                let shown = match (p.kind, r.number(&p.name)) {
                    (ParamKind::Length, Ok(v)) => units.length(v),
                    _ => r.display(&p),
                };
                if !p.formula.is_empty() || p.reporting {
                    ui.painter().text(vc.left_center() + vec2(3.0, 0.0), egui::Align2::LEFT_CENTER, &shown, style::font(12.0), style::text_dim());
                } else if p.kind == ParamKind::YesNo {
                    let mut b = r.yes_no(&p.name, false);
                    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(Rect::from_center_size(vc.center(), vec2(14.0, 14.0))));
                    if crate::style::check(&mut child, &mut b, "").changed() {
                        set_value = Some((p.name.clone(), if b { "Yes".into() } else { "No".into() }));
                    }
                } else if p.kind == ParamKind::Material {
                    let cur = r.text(&p.name, "");
                    let mut v = cur.clone();
                    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(vc));
                    egui::ComboBox::from_id_salt(("fe-pm", &p.name)).selected_text(if v.is_empty() { "<By Category>" } else { &v }).width(vc.width()).show_ui(&mut child, |ui| {
                        ui.selectable_value(&mut v, String::new(), "<By Category>");
                        for m in &app.doc.data.materials {
                            ui.selectable_value(&mut v, m.name.clone(), &m.name);
                        }
                    });
                    if v != cur {
                        set_value = Some((p.name.clone(), v));
                    }
                } else {
                    let key = egui::Id::new(("fe-pv", fe.type_idx, p.name.clone()));
                    let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| shown.clone());
                    let resp = ui.put(vc, egui::TextEdit::singleline(&mut s).frame(egui::Frame::NONE).desired_width(vc.width()));
                    if resp.has_focus() {
                        ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
                    }
                    if resp.lost_focus() {
                        ui.memory_mut(|m| m.data.remove::<String>(key));
                        if s != shown {
                            set_value = Some((p.name.clone(), s));
                        }
                    }
                }
                // Formula: "=" then the expression.
                let fc = cell(rr, 2).shrink2(vec2(3.0, 2.0));
                ui.painter().text(fc.left_center() + vec2(2.0, 0.0), egui::Align2::LEFT_CENTER, "=", style::font(12.0), style::text());
                if !p.reporting {
                    let fkey = egui::Id::new(("fe-pf", p.name.clone()));
                    let mut f: String = ui.memory(|m| m.data.get_temp(fkey)).unwrap_or_else(|| p.formula.clone());
                    let frect = Rect::from_min_max(fc.min + vec2(14.0, 0.0), fc.max);
                    let fr = ui.put(frect, egui::TextEdit::singleline(&mut f).frame(egui::Frame::NONE).desired_width(frect.width()));
                    if fr.has_focus() {
                        ui.memory_mut(|m| m.data.insert_temp(fkey, f.clone()));
                    }
                    if fr.lost_focus() {
                        ui.memory_mut(|m| m.data.remove::<String>(fkey));
                        if f != p.formula {
                            set_formula = Some((p.name.clone(), f));
                        }
                    }
                }
                // Lock: lengths and angles can be locked (dimension-driven parameters).
                if matches!(p.kind, ParamKind::Length | ParamKind::Angle) && p.formula.is_empty() && !p.reporting {
                    let lc = cell(rr, 3);
                    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(Rect::from_center_size(lc.center(), vec2(14.0, 14.0))));
                    child.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                }
            }
        }
    });
    drop(r);
    fe.param_sel = param_sel;
    // Parameter tools.
    let sel = fe.param_sel.clone().filter(|n| fe.family.param(n).is_some());
    let editable = sel.as_ref().and_then(|n| fe.family.param(n)).is_some_and(|p| !p.built_in);
    let mut delete = false;
    let mut mv: i32 = 0;
    let mut sort: Option<bool> = None;
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 2.0;
        if glyph_button(ui, TypesGlyph::Edit, editable, "Edit Parameter") {
            edit = sel.clone();
        }
        if glyph_button(ui, TypesGlyph::NewParam, true, "New Parameter") {
            fe.param_dialog = Some(ParamDialog { original: None, name: String::new(), kind: ParamKind::Length, instance: false, group: "Dimensions".into(), reporting: false });
        }
        if glyph_button(ui, TypesGlyph::Delete, editable, "Delete Parameter") {
            delete = true;
        }
        ui.add_space(8.0);
        if glyph_button(ui, TypesGlyph::Up, sel.is_some(), "Move Parameter Up") {
            mv = -1;
        }
        if glyph_button(ui, TypesGlyph::Down, sel.is_some(), "Move Parameter Down") {
            mv = 1;
        }
        ui.add_space(8.0);
        if glyph_button(ui, TypesGlyph::SortAsc, true, "Sort Parameters Ascending") {
            sort = Some(true);
        }
        if glyph_button(ui, TypesGlyph::SortDesc, true, "Sort Parameters Descending") {
            sort = Some(false);
        }
        ui.add_space(8.0);
        let _ = glyph_button(ui, TypesGlyph::Lookup, false, "Manage Lookup Tables");
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.label(egui::RichText::new("How do I manage family types?").color(Color32::from_rgb(0, 102, 204)));
        });
    });
    if let Some(n) = edit {
        if let Some(p) = fe.family.param(&n).filter(|p| !p.built_in) {
            fe.param_dialog = Some(ParamDialog { original: Some(n.clone()), name: n, kind: p.kind, instance: p.instance, group: p.group.clone(), reporting: p.reporting });
        }
    }
    if let Some(n) = sel.clone().filter(|_| delete) {
        let used = fe.def().is_some_and(|d| d.dims.iter().any(|x| x.label == n) || d.forms.iter().any(|f| f.material == n || f.visible == n));
        let in_formula = fe.family.params.iter().any(|p| p.name != n && p.formula.contains(n.as_str()));
        if used || in_formula {
            fe.message = Some(format!("\"{n}\" is used by a dimension label, form or formula. Remove those first."));
        } else {
            fe.checkpoint();
            fe.family.params.retain(|p| p.name != n);
            fe.param_sel = None;
        }
    }
    if let (Some(n), true) = (sel.clone(), mv != 0) {
        if let Some(i) = fe.family.params.iter().position(|p| p.name == n) {
            let g = fe.family.params[i].group.clone();
            let j = if mv < 0 { fe.family.params[..i].iter().rposition(|p| p.group == g) } else { fe.family.params[i + 1..].iter().position(|p| p.group == g).map(|k| i + 1 + k) };
            if let Some(j) = j {
                fe.checkpoint();
                fe.family.params.swap(i, j);
            }
        }
    }
    if let Some(asc) = sort {
        fe.checkpoint();
        fe.family.params.sort_by(|a, b| {
            let o = a.name.to_lowercase().cmp(&b.name.to_lowercase());
            if asc { o } else { o.reverse() }
        });
    }
    if let Some((n, v)) = set_value {
        let kind = fe.family.param(&n).map(|p| p.kind).unwrap_or(ParamKind::Text);
        let stored = match kind {
            ParamKind::Length => units.parse(&v, ParamKind::Length).map(rc_core::units::to_stored).ok_or_else(|| format!("'{v}' is not a valid length.")),
            ParamKind::Angle | ParamKind::Slope | ParamKind::Number | ParamKind::Integer | ParamKind::Currency => v.trim().parse::<f64>().map(rc_core::units::to_stored).map_err(|e| e.to_string()),
            _ => Ok(v),
        };
        match stored {
            Ok(s) => {
                fe.checkpoint();
                let k = fe.type_idx;
                fe.family.types[k].values.insert(n, s);
            }
            Err(e) => fe.message = Some(e),
        }
    }
    if let Some((n, f)) = set_formula {
        match rc_core::family_params::validate_formula(&fe.family, &n, &f) {
            Ok(()) => {
                fe.checkpoint();
                if let Some(p) = fe.family.params.iter_mut().find(|p| p.name == n) {
                    p.formula = f;
                }
                fe.message = None;
            }
            Err(e) => fe.message = Some(e),
        }
    }
}

fn preview_3d(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    let set = fe.mesh(&app.doc.data);
    let bounds = set.bounds();
    let mut cam = fe.cam3d.unwrap_or_else(|| render3d::frame_bounds(bounds, crate::view3d::HOME_DIR, false));
    // As in project 3D views: Shift + middle drag orbits, middle drag pans, the wheel zooms.
    let shift = ui.input(|i| i.modifiers.shift);
    if resp.dragged_by(egui::PointerButton::Middle) && !shift {
        let d = resp.drag_delta();
        let fwd = (cam.target - cam.eye).normalize();
        let right = fwd.cross(DVec3::Z).normalize_or_zero();
        let up = right.cross(fwd);
        let k = cam.ortho_height / rect.height().max(1.0) as f64;
        let mv = (-right * d.x as f64 + up * d.y as f64) * k;
        cam.eye += mv;
        cam.target += mv;
    }
    if resp.dragged_by(egui::PointerButton::Middle) && shift {
        let d = resp.drag_delta();
        let off = cam.eye - cam.target;
        let r = off.length();
        let mut yaw = off.y.atan2(off.x);
        let mut pitch = (off.z / r).clamp(-1.0, 1.0).asin();
        yaw -= d.x as f64 * 0.01;
        pitch = (pitch + d.y as f64 * 0.01).clamp(-1.5, 1.5);
        cam.eye = cam.target + DVec3::new(yaw.cos() * pitch.cos(), yaw.sin() * pitch.cos(), pitch.sin()) * r;
    }
    if resp.hovered() {
        let f = (-(ui.input(|i| i.smooth_scroll_delta.y) as f64) * 0.002).exp();
        if (f - 1.0).abs() > 1e-6 {
            cam.ortho_height *= f;
            cam.eye = cam.target + (cam.eye - cam.target) * f;
        }
    }
    fe.cam3d = Some(cam);
    let Some(renderer) = app.renderer.as_mut() else {
        ui.painter().text(rect.center(), egui::Align2::CENTER_CENTER, "No GPU available for the 3D preview.", egui::FontId::proportional(13.0), style::text_dim());
        return;
    };
    let scene = renderer.upload(&app.doc.data, vec![(0, set)], &Default::default(), (fe.scene_key, 0), &Default::default(), &Default::default());
    let ppp = ui.ctx().pixels_per_point();
    let size = [(rect.width() * ppp) as u32, (rect.height() * ppp) as u32];
    let settings = DrawSettings { style: VisualStyle::Shaded, shadows: false, sun: DVec3::new(0.4, -0.6, 0.9), section_box: None, background: [0.95, 0.96, 0.98] };
    let tex = renderer.render_view(u32::MAX - 3, size, &scene, &cam, &settings);
    ui.painter().image(tex, rect, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
}

fn load_into_project(app: &mut App, fe: &FamilyEditor) {
    let mut fam = fe.family.clone();
    let existing = fe.family_id.filter(|id| app.doc.data.family(*id).is_some());
    let name = fam.name.clone();
    let r = app.run("Load Family", |p| {
        match existing {
            Some(fid) => {
                fam.id = fid;
                for t in &mut fam.types {
                    if t.id == 0 {
                        t.id = p.new_id();
                    }
                }
                // Instances of removed types switch to the first type.
                let ids: Vec<Id> = fam.types.iter().map(|t| t.id).collect();
                let first = ids[0];
                for e in &mut p.elements {
                    if let ElementKind::Instance(i) = &mut e.kind {
                        if i.family_id == fid && !ids.contains(&i.type_id) {
                            i.type_id = first;
                        }
                        if i.family_id == fid {
                            i.category = fam.category;
                        }
                    }
                }
                if let Some(f) = p.family_mut(fid) {
                    *f = fam;
                }
                Ok(fid)
            }
            None => Ok(rc_core::edit::load_family(p, fam)),
        }
    });
    if let Some(fid) = r {
        app.info(format!("Loaded family '{name}' into the project."));
        if let Some(t) = app.doc.data.family(fid).and_then(|f| f.types.first()).map(|t| t.id) {
            let cat = app.doc.data.family(fid).map(|f| f.category);
            if !matches!(cat, Some(Category::Doors | Category::Windows)) {
                app.opts.component_type = t;
            }
        }
    }
}

/// Save in the family editor saves the family file (.rcfa).
pub fn save_family(app: &mut App) {
    let Some(name) = app.family_editor.as_ref().map(|fe| fe.family.name.clone()) else { return };
    let path = crate::files::FileDialog::new().add_filter("RevitCraft Family", &[rc_core::io::FAMILY_EXTENSION]).set_file_name(format!("{name}.{}", rc_core::io::FAMILY_EXTENSION)).save_file();
    let Some(mut path) = path else { return };
    if path.extension().is_none() {
        path.set_extension(rc_core::io::FAMILY_EXTENSION);
    }
    let Some(fe) = app.family_editor.as_ref() else { return };
    match rc_core::io::save_family(&app.doc.data, &fe.family, &path) {
        Ok(()) => app.info(format!("Saved {}", path.display())),
        Err(e) => app.error(e),
    }
}
