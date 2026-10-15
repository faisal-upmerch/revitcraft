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
}

impl FeView {
    fn label(self) -> &'static str {
        match self {
            FeView::Plan => "Ref. Level",
            FeView::Front => "Front",
            FeView::Right => "Right",
            FeView::ThreeD => "{3D}",
        }
    }
    fn sketch_plane(self) -> Option<SketchPlane> {
        match self {
            FeView::Plan => Some(SketchPlane::XY),
            FeView::Front => Some(SketchPlane::XZ),
            FeView::Right => Some(SketchPlane::YZ),
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
    SymbolicLine,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FeSel {
    None,
    Plane(u32),
    Dim(usize),
    Form(usize),
    Sym(usize),
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
    pub show_types: bool,
    pub new_param: (String, ParamKind, bool, String),
    pub message: Option<String>,
    pub scene_key: u64,
}

pub fn open(app: &mut App, family_id: Id) {
    let Some(f) = app.doc.data.family(family_id).cloned() else { return };
    app.family_editor = Some(FamilyEditor::new(Some(family_id), f));
}

pub fn new_custom(app: &mut App, name: &str) {
    let params = rc_core::library::template_params(FamilyTemplate::Custom);
    let fam = Family {
        id: 0,
        name: rc_core::edit::unique_name(app.doc.data.families.iter().map(|f| f.name.clone()), name),
        category: Category::GenericModels,
        template: FamilyTemplate::Custom,
        params,
        types: vec![FamilyType { id: 0, name: "Type 1".into(), values: BTreeMap::new() }],
        definition: Some(family_def::generic_template()),
    };
    let mut fe = FamilyEditor::new(None, fam);
    fe.dirty = true;
    app.family_editor = Some(fe);
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
            show_types: !custom,
            new_param: (String::new(), ParamKind::Length, false, "Dimensions".into()),
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
        FeView::Plan => (Axis::X, Axis::Y),
        FeView::Front => (Axis::X, Axis::Z),
        FeView::Right => (Axis::Y, Axis::Z),
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
pub fn show(app: &mut App, mut fe: FamilyEditor, ui: &mut egui::Ui) -> Option<FamilyEditor> {
    let mut close = false;
    let mut load = false;
    // Toolbar.
    egui::Panel::top("fe-ribbon").frame(style::ribbon_frame()).show(ui, |ui| {
        ui.add_space(4.0);
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new(format!("Family Editor — {}", fe.family.name)).strong().size(14.0));
            ui.label(egui::RichText::new(format!("({}, {})", fe.family.category.label(), fe.family.template.label())).color(style::text_dim()));
            if fe.dirty {
                ui.label(egui::RichText::new("modified").color(style::text_dim()).italics());
            }
        });
        ui.add_space(4.0);
        ui.horizontal(|ui| {
            let custom = fe.def().is_some();
            let tool_btn = |ui: &mut egui::Ui, fe: &mut FamilyEditor, icon: Icon, label: &str, t: FeTool, enabled: bool| {
                let on = fe.tool == t;
                if big(ui, icon, label, on, enabled) {
                    fe.tool = t;
                    fe.pts.clear();
                    fe.dim_planes.clear();
                    fe.blend_bottom = None;
                    if t != FeTool::Select && fe.view == FeView::ThreeD {
                        fe.view = FeView::Plan;
                    }
                }
            };
            tool_btn(ui, &mut fe, Icon::Modify, "Modify", FeTool::Select, true);
            ui.separator();
            tool_btn(ui, &mut fe, Icon::RefPlane, "Reference Plane", FeTool::RefPlane, custom);
            tool_btn(ui, &mut fe, Icon::DimAligned, "Aligned Dimension", FeTool::Dimension, custom);
            ui.separator();
            tool_btn(ui, &mut fe, Icon::Extrusion, "Extrusion", FeTool::Extrusion, custom);
            tool_btn(ui, &mut fe, Icon::Blend, "Blend", FeTool::Blend, custom);
            tool_btn(ui, &mut fe, Icon::Revolve, "Revolve", FeTool::Revolve, custom);
            tool_btn(ui, &mut fe, Icon::Sweep, "Sweep", FeTool::Sweep, custom);
            if big(ui, Icon::VoidForm, "Void Forms", fe.void_mode, custom) {
                fe.void_mode = !fe.void_mode;
            }
            tool_btn(ui, &mut fe, Icon::DetailLine, "Symbolic Line", FeTool::SymbolicLine, custom);
            ui.separator();
            if big(ui, Icon::FamilyTypes, "Family Types", fe.show_types, true) {
                fe.show_types = !fe.show_types;
            }
            ui.vertical(|ui| {
                ui.label("Category:");
                let mut cat = fe.family.category;
                egui::ComboBox::from_id_salt("fe-cat").selected_text(cat.label()).width(150.0).show_ui(ui, |ui| {
                    for c in [Category::GenericModels, Category::Furniture, Category::Casework, Category::PlumbingFixtures, Category::SpecialtyEquipment, Category::Columns, Category::StructuralColumns, Category::StructuralFoundations] {
                        ui.selectable_value(&mut cat, c, c.label());
                    }
                });
                if cat != fe.family.category && !matches!(fe.family.category, Category::Doors | Category::Windows) {
                    fe.checkpoint();
                    fe.family.category = cat;
                }
            });
            ui.separator();
            if big(ui, Icon::Undo, "Undo", false, !fe.undo.is_empty()) {
                if let Some(prev) = fe.undo.pop() {
                    fe.redo.push(std::mem::replace(&mut fe.family, prev));
                    fe.scene_key += 1;
                }
            }
            if big(ui, Icon::Redo, "Redo", false, !fe.redo.is_empty()) {
                if let Some(next) = fe.redo.pop() {
                    fe.undo.push(std::mem::replace(&mut fe.family, next));
                    fe.scene_key += 1;
                }
            }
            ui.separator();
            if big(ui, Icon::LoadIntoProject, "Load into Project and Close", false, true) {
                load = true;
            }
            if big(ui, Icon::Save, "Save As...", false, true) {
                let path = crate::files::FileDialog::new().add_filter("RevitCraft Family", &[rc_core::io::FAMILY_EXTENSION]).set_file_name(format!("{}.rcfa", fe.family.name)).save_file();
                if let Some(mut path) = path {
                    if path.extension().is_none() {
                        path.set_extension(rc_core::io::FAMILY_EXTENSION);
                    }
                    match rc_core::io::save_family(&app.doc.data, &fe.family, &path) {
                        Ok(()) => app.info(format!("Saved {}", path.display())),
                        Err(e) => app.error(e),
                    }
                }
            }
            if big(ui, Icon::Close, "Close", false, true) {
                close = true;
            }
        });
        ui.add_space(4.0);
    });
    egui::Panel::bottom("fe-status").frame(style::bar_frame()).exact_size(26.0).show(ui, |ui| {
        ui.horizontal_centered(|ui| {
            let (_, err) = fe.solved();
            if let Some(e) = err.or(fe.message.clone()) {
                ui.colored_label(style::ERROR, e);
            } else {
                ui.label(prompt(&fe));
            }
        });
    });
    egui::Panel::left("fe-props").resizable(true).default_size(270.0).frame(style::side_frame()).show(ui, |ui| {
        style::palette_title(ui, "Properties");
        egui::ScrollArea::vertical().id_salt("fe-props-scroll").show(ui, |ui| {
            egui::Frame::new().inner_margin(6).show(ui, |ui| properties(app, &mut fe, ui));
        });
    });
    if fe.show_types {
        egui::Panel::right("fe-types").resizable(true).default_size(380.0).frame(style::side_frame()).show(ui, |ui| {
            style::palette_title(ui, "Family Types");
            egui::ScrollArea::vertical().id_salt("fe-types-scroll").show(ui, |ui| {
                egui::Frame::new().inner_margin(6).show(ui, |ui| family_types(app, &mut fe, ui));
            });
        });
    }
    egui::CentralPanel::default().frame(style::canvas_frame()).show(ui, |ui| {
        ui.horizontal(|ui| {
            for v in [FeView::Plan, FeView::Front, FeView::Right, FeView::ThreeD] {
                if ui.selectable_label(fe.view == v, v.label()).clicked() {
                    fe.view = v;
                    fe.pts.clear();
                }
            }
            ui.separator();
            ui.label("Type:");
            let names: Vec<String> = fe.family.types.iter().map(|t| t.name.clone()).collect();
            egui::ComboBox::from_id_salt("fe-cur-type").selected_text(names.get(fe.type_idx).cloned().unwrap_or_default()).show_ui(ui, |ui| {
                for (k, n) in names.iter().enumerate() {
                    if ui.selectable_label(fe.type_idx == k, n).clicked() {
                        fe.type_idx = k;
                        fe.scene_key += 1;
                    }
                }
            });
        });
        if fe.view == FeView::ThreeD || fe.def().is_none() {
            preview_3d(app, &mut fe, ui);
        } else {
            canvas_2d(app, &mut fe, ui);
        }
    });
    // Keyboard.
    if !ui.ctx().egui_wants_keyboard_input() {
        if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            if !fe.pts.is_empty() || !fe.dim_planes.is_empty() {
                fe.pts.clear();
                fe.dim_planes.clear();
                fe.blend_bottom = None;
            } else {
                fe.tool = FeTool::Select;
            }
        }
        if ui.input(|i| i.key_pressed(egui::Key::Delete)) {
            delete_selected(&mut fe);
        }
        if ui.input(|i| i.key_pressed(egui::Key::Enter)) {
            finish_sketch(&mut fe);
        }
        if ui.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Z)) {
            if let Some(prev) = fe.undo.pop() {
                fe.redo.push(std::mem::replace(&mut fe.family, prev));
                fe.scene_key += 1;
            }
        }
    }
    if load {
        load_into_project(app, &fe);
        return None;
    }
    if close {
        if fe.dirty {
            app.info("Closed the family editor without loading the changes.");
        }
        return None;
    }
    Some(fe)
}

fn big(ui: &mut egui::Ui, icon: Icon, label: &str, on: bool, enabled: bool) -> bool {
    let font = egui::FontId::proportional(11.0);
    let lines: Vec<&str> = if label.len() > 12 { label.splitn(2, ' ').collect() } else { vec![label] };
    let w = lines.iter().map(|l| ui.painter().layout_no_wrap(l.to_string(), font.clone(), Color32::BLACK).size().x).fold(0.0f32, f32::max) + 10.0;
    let (r, resp) = ui.allocate_exact_size(vec2(w.max(48.0), 66.0), if enabled { Sense::click() } else { Sense::hover() });
    if on {
        ui.painter().rect_filled(r, 3.0, style::accent_light());
    } else if resp.hovered() && enabled {
        ui.painter().rect_filled(r, 3.0, style::hover());
    }
    icons::paint(ui.painter(), Rect::from_center_size(pos2(r.center().x, r.top() + 18.0), vec2(28.0, 28.0)), icon, enabled);
    for (k, l) in lines.iter().enumerate() {
        ui.painter().text(pos2(r.center().x, r.top() + 38.0 + k as f32 * 12.0), egui::Align2::CENTER_TOP, l, font.clone(), if enabled { style::text() } else { style::text_dim() });
    }
    enabled && resp.clicked()
}

fn prompt(fe: &FamilyEditor) -> String {
    match fe.tool {
        FeTool::Select => "Select reference planes, dimensions or forms. Drag a reference plane to move it (when not driven by a dimension).".into(),
        FeTool::RefPlane => "Click the start and end of the reference plane. Vertical lines make left/right planes, horizontal lines front/back or level planes.".into(),
        FeTool::Dimension => format!("Pick parallel reference planes ({} picked); click empty space to place the dimension.", fe.dim_planes.len()),
        FeTool::Extrusion => "Sketch the profile: click corners (they lock to reference planes). Click the first point or press Enter to finish.".into(),
        FeTool::Blend => {
            if fe.blend_bottom.is_none() {
                "Blend: sketch the base profile (closed), then press Enter.".into()
            } else {
                "Blend: sketch the top profile, then press Enter.".into()
            }
        }
        FeTool::Revolve => "Revolve (Front view): sketch the profile, press Enter; it revolves about the Center (Left/Right) plane.".into(),
        FeTool::Sweep => "Sweep (Ref. Level): click the path points, press Enter to sweep a rectangular profile along it.".into(),
        FeTool::SymbolicLine => "Click the start and end of a plan symbolic line.".into(),
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
    let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 20.0, thin: false };
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
            FeView::Plan => DVec2::new(q.x, q.y),
            FeView::Front => DVec2::new(q.x, q.z),
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
            let set = family_def::form_mesh(&f.form, &solved, "x");
            for m in set.by_material.values() {
                for tri in m.indices.chunks(3) {
                    let v: Vec<Pos2> = (0..3).map(|j| xf.s(to2(m.positions[tri[j] as usize]))).collect();
                    painter.add(egui::Shape::closed_line(v, Stroke::new(1.0, style::SELECT)));
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
        let col = if selected { style::SELECT } else if near { style::PRESELECT } else { green };
        canvas::paint_polyline(&painter, &[xf.s(a), xf.s(b)], false, Stroke::new(if p.fixed { 1.6 } else { 1.0 }, col), rc_core::plan::Dash::DashDot, &xf);
        if !p.name.is_empty() {
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
    // Symbolic lines (plan).
    if fe.view == FeView::Plan {
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
        // Current sketch.
        let pts: Vec<Pos2> = fe.pts.iter().map(|p| xf.s(pt2(*p, &solved))).chain(snap_pos.map(|p| xf.s(p))).collect();
        let color = if fe.void_mode { Color32::from_rgb(230, 120, 30) } else { Color32::from_rgb(220, 0, 160) };
        painter.add(egui::Shape::line(pts, Stroke::new(1.8, color)));
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
                        if hit == FeSel::None && fe.view == FeView::Plan {
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
        FeTool::Extrusion | FeTool::Blend | FeTool::Revolve | FeTool::Sweep | FeTool::SymbolicLine => {
            if let (true, Some(s)) = (clicked, snapped) {
                let close = fe.pts.len() >= 3 && fe.pts.first().is_some_and(|f| pt2(*f, &solved).distance(pt2(s, &solved)) < tol) && fe.tool != FeTool::Sweep;
                if close {
                    finish_sketch(fe);
                } else {
                    fe.pts.push(s);
                    if fe.tool == FeTool::SymbolicLine && fe.pts.len() == 2 {
                        fe.checkpoint();
                        let (a, b) = (fe.pts[0], fe.pts[1]);
                        if let Some(def) = fe.family.definition.as_mut() {
                            def.symbolic.push(SymLine { a, b });
                        }
                        fe.pts.clear();
                    }
                }
            }
        }
    }
    // Axis labels.
    painter.text(rect.left_bottom() + vec2(10.0, -8.0), egui::Align2::LEFT_BOTTOM, format!("{} view   (horizontal: {:?}, vertical: {:?})", fe.view.label(), ha, va), egui::FontId::proportional(11.0), style::text_dim());
}

/// Ends the current sketch and creates the form.
fn finish_sketch(fe: &mut FamilyEditor) {
    let Some(plane) = fe.view.sketch_plane() else { return };
    let void = fe.void_mode;
    let pts = std::mem::take(&mut fe.pts);
    let n = fe.def().map(|d| d.forms.len()).unwrap_or(0) + 1;
    let form = match fe.tool {
        FeTool::Extrusion if pts.len() >= 3 => {
            // Extrude between the work plane's natural limits: Ref. Level → Top in plan, Front → Back
            // in front views, Left → Right in right views (falling back to fixed depths).
            let def = fe.def().cloned().unwrap_or_default();
            let named = |n: &str| def.planes.iter().find(|p| p.name == n).map(|p| Loc::Plane(p.id));
            let (start, end) = match plane {
                SketchPlane::XY => (named("Ref. Level").unwrap_or(Loc::Value(0.0)), named("Top").unwrap_or(Loc::Value(1000.0))),
                SketchPlane::XZ => (named("Front").unwrap_or(Loc::Value(-250.0)), named("Back").unwrap_or(Loc::Value(250.0))),
                SketchPlane::YZ => (named("Left").unwrap_or(Loc::Value(-250.0)), named("Right").unwrap_or(Loc::Value(250.0))),
            };
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
        FeTool::Sweep if pts.len() >= 2 && plane == SketchPlane::XY => Some(Form::Sweep { path: pts, z: Loc::Value(0.0), width: 50.0, height: 50.0 }),
        FeTool::Revolve => {
            fe.message = Some("Revolves are sketched in the Front view.".into());
            None
        }
        FeTool::Sweep => {
            fe.message = Some("Sweep paths are sketched in the Ref. Level view.".into());
            None
        }
        _ => None,
    };
    if let Some(form) = form {
        let kind = form.kind_label();
        fe.checkpoint();
        if let Some(def) = fe.family.definition.as_mut() {
            def.forms.push(FormDef { name: format!("{}{} {}", if void { "Void " } else { "" }, kind, n), form, void, material: if void { String::new() } else { "Material".into() }, visible: String::new() });
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
        FeSel::Sym(k) => {
            fe.checkpoint();
            fe.family.definition.as_mut().unwrap().symbolic.remove(k);
        }
        FeSel::None => return,
    }
    fe.sel = FeSel::None;
}

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

fn properties(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let Some(def) = fe.def().cloned() else {
        ui.label(egui::RichText::new("This family is built from a parametric template. Edit its parameters and types in Family Types; geometry follows the parameters.").color(style::text_dim()));
        return;
    };
    let length_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::Length).map(|p| p.name.clone()).collect();
    let yesno_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::YesNo).map(|p| p.name.clone()).collect();
    let mat_params: Vec<String> = fe.family.params.iter().filter(|p| p.kind == ParamKind::Material).map(|p| p.name.clone()).collect();
    match fe.sel {
        FeSel::None => {
            ui.label(egui::RichText::new("Family").strong());
            ui.horizontal(|ui| {
                ui.label("Name:");
                let mut n = fe.family.name.clone();
                if ui.text_edit_singleline(&mut n).lost_focus() && n != fe.family.name && !n.trim().is_empty() {
                    fe.checkpoint();
                    fe.family.name = n;
                }
            });
            ui.label(format!("Reference planes: {}", def.planes.len()));
            ui.label(format!("Dimensions: {}", def.dims.len()));
            ui.label(format!("Forms: {}", def.forms.len()));
            ui.add_space(6.0);
            ui.label(egui::RichText::new("Tip: lock sketch corners to reference planes, then label dimensions between those planes with parameters to make the family flex.").color(style::text_dim()));
        }
        FeSel::Plane(id) => {
            let Some(p) = def.plane(id).cloned() else { return };
            ui.label(egui::RichText::new("Reference Plane").strong());
            let mut np = p.clone();
            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(&mut np.name);
            });
            ui.label(format!("Orientation: {:?} plane", p.axis));
            ui.add_enabled_ui(!p.fixed, |ui| {
                ui.horizontal(|ui| {
                    ui.label("Position:");
                    ui.add(egui::DragValue::new(&mut np.default).speed(5.0).suffix(" mm"));
                });
            });
            if p.fixed {
                ui.label(egui::RichText::new("Defines origin (fixed).").color(style::text_dim()));
            }
            if np != p {
                fe.checkpoint();
                if let Some(x) = fe.family.definition.as_mut().and_then(|d| d.planes.iter_mut().find(|x| x.id == id)) {
                    *x = np;
                }
            }
        }
        FeSel::Dim(k) => {
            let Some(d) = def.dims.get(k).cloned() else { return };
            ui.label(egui::RichText::new("Dimension").strong());
            let mut nd = d.clone();
            ui.horizontal(|ui| {
                ui.label("Label:");
                egui::ComboBox::from_id_salt("fe-dim-label").selected_text(if nd.label.is_empty() { "<None>".to_string() } else { nd.label.clone() }).show_ui(ui, |ui| {
                    ui.selectable_value(&mut nd.label, String::new(), "<None>");
                    for n in &length_params {
                        ui.selectable_value(&mut nd.label, n.clone(), n);
                    }
                });
            });
            ui.add_enabled(nd.planes.len() >= 3, egui::Checkbox::new(&mut nd.equal, "Equality (EQ)"));
            ui.checkbox(&mut nd.locked, "Locked");
            if ui.button("Create Parameter for Label...").clicked() {
                fe.show_types = true;
                fe.new_param = (String::new(), ParamKind::Length, false, "Dimensions".into());
            }
            if nd != d {
                fe.checkpoint();
                fe.family.definition.as_mut().unwrap().dims[k] = nd;
            }
        }
        FeSel::Form(k) => {
            let Some(f) = def.forms.get(k).cloned() else { return };
            ui.label(egui::RichText::new(format!("{}{}", if f.void { "Void " } else { "" }, f.form.kind_label())).strong());
            let mut nf = f.clone();
            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(&mut nf.name);
            });
            ui.checkbox(&mut nf.void, "Void (cuts solids)");
            if !nf.void {
                ui.horizontal(|ui| {
                    ui.label("Material:");
                    egui::ComboBox::from_id_salt("fe-mat").selected_text(&nf.material).show_ui(ui, |ui| {
                        for n in &mat_params {
                            ui.selectable_value(&mut nf.material, n.clone(), format!("[{n}]"));
                        }
                        for m in &app.doc.data.materials {
                            ui.selectable_value(&mut nf.material, m.name.clone(), &m.name);
                        }
                    });
                });
            }
            ui.horizontal(|ui| {
                ui.label("Visible:");
                egui::ComboBox::from_id_salt("fe-vis").selected_text(if nf.visible.is_empty() { "Always".to_string() } else { nf.visible.clone() }).show_ui(ui, |ui| {
                    ui.selectable_value(&mut nf.visible, String::new(), "Always");
                    for n in &yesno_params {
                        ui.selectable_value(&mut nf.visible, n.clone(), n);
                    }
                });
            });
            match &mut nf.form {
                Form::Extrusion { plane, start, end, .. } => {
                    let (_, _, axis) = plane.axes();
                    ui.label(format!("Work plane: {}", plane.label()));
                    ui.label("Extrusion start:");
                    loc_editor(ui, "fe-es", &def, axis, start);
                    ui.label("Extrusion end:");
                    loc_editor(ui, "fe-ee", &def, axis, end);
                }
                Form::Blend { start, end, .. } => {
                    ui.label("Base:");
                    loc_editor(ui, "fe-bs", &def, Axis::Z, start);
                    ui.label("Top:");
                    loc_editor(ui, "fe-be", &def, Axis::Z, end);
                }
                Form::Revolve { angle_deg, .. } => {
                    ui.horizontal(|ui| {
                        ui.label("Angle:");
                        ui.add(egui::DragValue::new(angle_deg).range(1.0..=360.0).suffix("°"));
                    });
                }
                Form::Sweep { z, width, height, .. } => {
                    ui.label("Path height:");
                    loc_editor(ui, "fe-sz", &def, Axis::Z, z);
                    ui.horizontal(|ui| {
                        ui.label("Profile:");
                        ui.add(egui::DragValue::new(width).speed(1.0).suffix(" mm"));
                        ui.label("x");
                        ui.add(egui::DragValue::new(height).speed(1.0).suffix(" mm"));
                    });
                }
            }
            if nf != f {
                fe.checkpoint();
                fe.family.definition.as_mut().unwrap().forms[k] = nf;
            }
        }
        FeSel::Sym(_) => {
            ui.label(egui::RichText::new("Symbolic Line").strong());
            ui.label("Shown in plan views of projects instead of the cut geometry.");
        }
    }
    if fe.sel != FeSel::None && ui.button("Delete").clicked() {
        delete_selected(fe);
    }
}

fn family_types(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let units = app.doc.data.units.clone();
    // Types row.
    ui.horizontal(|ui| {
        ui.label("Type name:");
        let names: Vec<String> = fe.family.types.iter().map(|t| t.name.clone()).collect();
        egui::ComboBox::from_id_salt("fe-types").selected_text(names.get(fe.type_idx).cloned().unwrap_or_default()).width(160.0).show_ui(ui, |ui| {
            for (k, n) in names.iter().enumerate() {
                if ui.selectable_label(fe.type_idx == k, n).clicked() {
                    fe.type_idx = k;
                    fe.scene_key += 1;
                }
            }
        });
    });
    ui.horizontal(|ui| {
        if ui.button("New...").clicked() {
            fe.checkpoint();
            let base = fe.ftype().clone();
            let name = rc_core::edit::unique_name(fe.family.types.iter().map(|t| t.name.clone()), &format!("{} 2", base.name));
            fe.family.types.push(FamilyType { id: 0, name, values: base.values });
            fe.type_idx = fe.family.types.len() - 1;
        }
        let key = egui::Id::new("fe-type-rename");
        let mut name: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| fe.ftype().name.clone());
        let r = ui.add(egui::TextEdit::singleline(&mut name).desired_width(120.0));
        if r.has_focus() {
            ui.memory_mut(|m| m.data.insert_temp(key, name.clone()));
        }
        if r.lost_focus() {
            ui.memory_mut(|m| m.data.remove::<String>(key));
            if name != fe.ftype().name && !name.trim().is_empty() {
                fe.checkpoint();
                let k = fe.type_idx;
                fe.family.types[k].name = name;
            }
        }
        if ui.add_enabled(fe.family.types.len() > 1, egui::Button::new("Delete")).clicked() {
            fe.checkpoint();
            let k = fe.type_idx;
            fe.family.types.remove(k);
            fe.type_idx = 0;
        }
    });
    ui.separator();
    // Parameters table.
    let r = Resolver::for_type(&fe.family, fe.ftype());
    let params = fe.family.params.clone();
    let mut set_value: Option<(String, String)> = None;
    let mut set_formula: Option<(String, String)> = None;
    let mut remove: Option<String> = None;
    let mut groups: Vec<(String, Vec<FamilyParameter>)> = Vec::new();
    for p in params {
        match groups.iter_mut().find(|g| g.0 == p.group) {
            Some(g) => g.1.push(p),
            None => groups.push((p.group.clone(), vec![p])),
        }
    }
    for (g, ps) in groups {
        style::header(ui, &g);
        egui::Grid::new(("fe-params", &g)).num_columns(4).striped(true).spacing(vec2(6.0, 3.0)).show(ui, |ui| {
            for p in ps {
                let tag = if p.instance { " (default)" } else { "" };
                ui.label(format!("{}{}", p.name, tag));
                let shown = r.display(&p);
                if !p.formula.is_empty() {
                    ui.label(egui::RichText::new(&shown).color(style::text_dim()));
                } else if p.kind == ParamKind::YesNo {
                    let mut b = r.yes_no(&p.name, false);
                    if ui.checkbox(&mut b, "").changed() {
                        set_value = Some((p.name.clone(), if b { "Yes".into() } else { "No".into() }));
                    }
                } else if p.kind == ParamKind::Material {
                    let cur = r.text(&p.name, "");
                    let mut v = cur.clone();
                    egui::ComboBox::from_id_salt(("fe-pm", &p.name)).selected_text(&v).width(110.0).show_ui(ui, |ui| {
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
                    let resp = ui.add(egui::TextEdit::singleline(&mut s).desired_width(100.0));
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
                let fkey = egui::Id::new(("fe-pf", p.name.clone()));
                let mut f: String = ui.memory(|m| m.data.get_temp(fkey)).unwrap_or_else(|| p.formula.clone());
                let fr = ui.add(egui::TextEdit::singleline(&mut f).hint_text("= formula").desired_width(110.0));
                if fr.has_focus() {
                    ui.memory_mut(|m| m.data.insert_temp(fkey, f.clone()));
                }
                if fr.lost_focus() {
                    ui.memory_mut(|m| m.data.remove::<String>(fkey));
                    if f != p.formula {
                        set_formula = Some((p.name.clone(), f));
                    }
                }
                if !p.built_in {
                    if ui.small_button("✕").on_hover_text("Remove parameter").clicked() {
                        remove = Some(p.name.clone());
                    }
                } else {
                    ui.label("");
                }
                ui.end_row();
            }
        });
    }
    if let Some((n, v)) = set_value {
        let kind = fe.family.param(&n).map(|p| p.kind).unwrap_or(ParamKind::Text);
        let stored = match kind {
            ParamKind::Length => units.parse(&v, ParamKind::Length).map(rc_core::units::to_stored).ok_or_else(|| format!("'{v}' is not a valid length.")),
            ParamKind::Angle | ParamKind::Number | ParamKind::Integer | ParamKind::Currency => v.trim().parse::<f64>().map(rc_core::units::to_stored).map_err(|e| e.to_string()),
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
    if let Some(n) = remove {
        let used = fe.def().is_some_and(|d| d.dims.iter().any(|x| x.label == n) || d.forms.iter().any(|f| f.material == n || f.visible == n));
        if used {
            fe.message = Some(format!("'{n}' is used by a dimension label or form. Remove those first."));
        } else {
            fe.checkpoint();
            fe.family.params.retain(|p| p.name != n);
        }
    }
    ui.separator();
    ui.label(egui::RichText::new("New parameter").strong());
    let (mut name, mut kind, mut inst, mut group) = fe.new_param.clone();
    egui::Grid::new("fe-newp").num_columns(2).show(ui, |ui| {
        ui.label("Name:");
        ui.text_edit_singleline(&mut name);
        ui.end_row();
        ui.label("Type of parameter:");
        egui::ComboBox::from_id_salt("fe-np-kind").selected_text(kind.label()).show_ui(ui, |ui| {
            for k in ParamKind::USER {
                ui.selectable_value(&mut kind, k, k.label());
            }
        });
        ui.end_row();
        ui.label("Group:");
        egui::ComboBox::from_id_salt("fe-np-group").selected_text(&group).show_ui(ui, |ui| {
            for g in ["Dimensions", "Materials and Finishes", "Construction", "Graphics", "Identity Data", "Other"] {
                ui.selectable_value(&mut group, g.to_string(), g);
            }
        });
        ui.end_row();
        ui.label("");
        ui.horizontal(|ui| {
            ui.radio_value(&mut inst, false, "Type");
            ui.radio_value(&mut inst, true, "Instance");
        });
        ui.end_row();
    });
    if ui.add_enabled(!name.trim().is_empty(), egui::Button::new("Add Parameter")).clicked() {
        if fe.family.param(name.trim()).is_some() {
            fe.message = Some(format!("A parameter named '{}' already exists.", name.trim()));
        } else {
            fe.checkpoint();
            let default = match kind {
                ParamKind::Length => "1000".to_string(),
                ParamKind::YesNo => "Yes".to_string(),
                ParamKind::Material => "Default".to_string(),
                ParamKind::Text => String::new(),
                _ => "0".to_string(),
            };
            fe.family.params.push(FamilyParameter { name: name.trim().to_string(), kind, instance: inst, formula: String::new(), group: group.clone(), built_in: false, default, reporting: false });
            name.clear();
        }
    }
    fe.new_param = (name, kind, inst, group);
}

fn preview_3d(app: &mut App, fe: &mut FamilyEditor, ui: &mut egui::Ui) {
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    let set = fe.mesh(&app.doc.data);
    let bounds = set.bounds();
    let mut cam = fe.cam3d.unwrap_or_else(|| render3d::frame_bounds(bounds, DVec3::new(-0.7, -1.0, 0.6), false));
    if resp.dragged_by(egui::PointerButton::Primary) {
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
    ui.painter().text(rect.left_bottom() + vec2(10.0, -8.0), egui::Align2::LEFT_BOTTOM, format!("{} — {}: drag to orbit, wheel to zoom", fe.family.name, fe.ftype().name), egui::FontId::proportional(11.0), style::text_dim());
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
