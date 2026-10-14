//! The 2D view canvas used by plans, sections, elevations, drafting views and legends:
//! navigation, painting, highlighting, selection (pick, Tab cycling, window/crossing),
//! drag-move, grips, temporary dimensions, snapping and the right-click menu.

use crate::app::App;
use crate::commands::Cmd;
use crate::snap::{self, SnapGeom, SnapInput, SnapKind, SnapResult};
use crate::tools::{Seg, ToolKind};
use crate::{actions, canvas_tools, grips, style};
use eframe::egui::{self, Color32, Pos2, Rect, Sense, Stroke, pos2, vec2};
use rc_core::geom::{self, DVec2};
use rc_core::model::*;
use rc_core::plan::{self, Anchor, Dash, Drawing, Prim};
use std::collections::HashSet;
use std::rc::Rc;

#[derive(Clone, Copy, Debug)]
pub struct Cam2 {
    pub center: DVec2,
    /// Screen points per model millimetre.
    pub zoom: f64,
    pub fitted: bool,
}

impl Default for Cam2 {
    fn default() -> Self {
        Cam2 { center: DVec2::new(5000.0, 4000.0), zoom: 0.05, fitted: false }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Xf {
    pub rect: Rect,
    pub center: DVec2,
    pub zoom: f64,
    /// View scale denominator (100 = 1:100).
    pub scale: f64,
    pub thin: bool,
}

impl Xf {
    pub fn s(&self, w: DVec2) -> Pos2 {
        pos2(self.rect.center().x + ((w.x - self.center.x) * self.zoom) as f32, self.rect.center().y - ((w.y - self.center.y) * self.zoom) as f32)
    }
    pub fn w(&self, s: Pos2) -> DVec2 {
        DVec2::new(self.center.x + (s.x - self.rect.center().x) as f64 / self.zoom, self.center.y - (s.y - self.rect.center().y) as f64 / self.zoom)
    }
    /// Pixel width for a line weight in paper millimetres.
    pub fn px(&self, paper_mm: f32) -> f32 {
        if self.thin {
            return 1.0;
        }
        (paper_mm as f64 * self.scale * self.zoom * 1.4).clamp(0.8, 6.0) as f32
    }
    pub fn text_px(&self, paper_mm: f32) -> f32 {
        (paper_mm as f64 * self.scale * self.zoom) as f32
    }
    /// Model length of `px` screen pixels.
    pub fn len(&self, px: f32) -> f64 {
        px as f64 / self.zoom
    }
}

#[derive(Clone, Debug)]
pub enum Drag {
    Window { start: DVec2 },
    Move { start: DVec2, ids: Vec<Id> },
    Grip { id: Id, grip: grips::GripKind, start: DVec2 },
    SketchVertex { ends: Vec<(usize, bool)>, start: DVec2 },
    ZoomRegion { start: DVec2 },
}

#[derive(Clone, Debug)]
pub struct TempDimEdit {
    pub id: Id,
    pub index: usize,
    pub text: String,
    pub focus: bool,
}

#[derive(Default)]
pub struct Interact {
    pub cursor: Option<DVec2>,
    pub snap: Option<SnapResult>,
    pub point: Option<DVec2>,
    pub drag: Option<Drag>,
    pub hover: Option<Id>,
    pub hover_seg: Option<usize>,
    pub tab_pressed: bool,
    pub tab_index: usize,
    pub tab_at: Option<DVec2>,
    pub temp_dim_edit: Option<TempDimEdit>,
    pub measure: Option<(DVec2, DVec2)>,
    pub xf: Option<Xf>,
    pub view: Option<Id>,
    pub prompt: String,
    pub hover_grip: Option<grips::GripKind>,
    /// Text being typed for a new text note: (position, text, needs focus).
    pub text_input: Option<(DVec2, String, bool)>,
    /// Enter was pressed with a typed value: treat it as a click at the computed point.
    pub pending_enter: bool,
}

pub fn canvas_bg(app: &App) -> Color32 {
    style::canvas(app.settings.black_canvas)
}

/// Ink colour adjusted for a black canvas (black lines become white).
pub fn ink(app: &App, rgb: [u8; 3]) -> Color32 {
    if app.settings.black_canvas && rgb[0] < 70 && rgb[1] < 70 && rgb[2] < 70 {
        Color32::from_rgb(235, 235, 235)
    } else {
        Color32::from_rgb(rgb[0], rgb[1], rgb[2])
    }
}

pub fn is_plan(v: &View) -> bool {
    v.plan_level().is_some()
}

// ---------------------------------------------------------------- painting

fn dash_pattern(dash: Dash, xf: &Xf) -> (Vec<f32>, Vec<f32>) {
    let unit = ((xf.scale * xf.zoom) as f32 * 1.2).clamp(2.0, 8.0);
    match dash {
        Dash::Solid => (vec![], vec![]),
        Dash::Dashed => (vec![unit * 2.5], vec![unit * 1.2]),
        Dash::DashDot => (vec![unit * 4.0, unit * 0.4], vec![unit * 1.0, unit * 1.0]),
        Dash::Dotted => (vec![unit * 0.4], vec![unit * 0.9]),
    }
}

pub fn paint_polyline(painter: &egui::Painter, pts: &[Pos2], closed: bool, stroke: Stroke, dash: Dash, xf: &Xf) {
    if pts.len() < 2 {
        return;
    }
    let mut v = pts.to_vec();
    if closed {
        v.push(v[0]);
    }
    if dash == Dash::Solid {
        painter.add(egui::Shape::line(v, stroke));
    } else {
        let (d, g) = dash_pattern(dash, xf);
        let mut shapes = Vec::new();
        egui::Shape::dashed_line_many_with_offset(&v, stroke, &d, &g, 0.0, &mut shapes);
        painter.extend(shapes);
    }
}

pub fn paint_text(painter: &egui::Painter, pos: Pos2, text: &str, h: f32, color: Color32, anchor: Anchor, angle: f32) {
    if h < 3.0 || text.is_empty() {
        return;
    }
    let galley = painter.layout_no_wrap(text.to_string(), egui::FontId::proportional(h.min(96.0)), color);
    let align = match anchor {
        Anchor::Center => egui::Align2::CENTER_CENTER,
        Anchor::Left => egui::Align2::LEFT_BOTTOM,
    };
    let a = align.pos_in_rect(&galley.rect).to_vec2();
    let shape = egui::epaint::TextShape::new(pos - a, galley, color).with_angle_and_anchor(-angle, align);
    painter.add(shape);
}

/// Paints drawing primitives. `style_of` returns (colour override, extra width, skip).
pub fn paint_prims(painter: &egui::Painter, prims: &[(Option<Id>, Prim)], xf: &Xf, color_of: &dyn Fn(Option<Id>, [u8; 3]) -> Option<Color32>) {
    let clip = painter.clip_rect().expand(40.0);
    for (id, prim) in prims {
        match prim {
            Prim::Fill { tris, color } => {
                let Some(c) = color_of(*id, [color[0], color[1], color[2]]) else { continue };
                let c = Color32::from_rgba_unmultiplied(c.r(), c.g(), c.b(), color[3]);
                let mut mesh = egui::Mesh::default();
                for t in tris {
                    let p = [xf.s(t[0]), xf.s(t[1]), xf.s(t[2])];
                    if !p.iter().any(|q| clip.contains(*q)) && !Rect::from_points(&p).intersects(clip) {
                        continue;
                    }
                    let i = mesh.vertices.len() as u32;
                    for q in p {
                        mesh.colored_vertex(q, c);
                    }
                    mesh.add_triangle(i, i + 1, i + 2);
                }
                if !mesh.is_empty() {
                    painter.add(egui::Shape::mesh(mesh));
                }
            }
            Prim::Line { pts, closed, stroke } => {
                let Some(c) = color_of(*id, stroke.color) else { continue };
                let v: Vec<Pos2> = pts.iter().map(|q| xf.s(*q)).collect();
                if !Rect::from_points(&v).intersects(clip) {
                    continue;
                }
                paint_polyline(painter, &v, *closed, Stroke::new(xf.px(stroke.width), c), stroke.dash, xf);
            }
            Prim::Text { pos, text, size, color, anchor, angle } => {
                let Some(c) = color_of(*id, *color) else { continue };
                let p = xf.s(*pos);
                if !clip.contains(p) {
                    continue;
                }
                paint_text(painter, p, text, xf.text_px(*size), c, *anchor, *angle);
            }
        }
    }
}

/// Paints the prims of `ids` as a highlight (selection/preselection).
fn paint_highlight(painter: &egui::Painter, d: &Drawing, ids: &HashSet<Id>, xf: &Xf, color: Color32, offset: DVec2) {
    for (id, prim) in &d.prims {
        let Some(id) = id else { continue };
        if !ids.contains(id) {
            continue;
        }
        match prim {
            Prim::Line { pts, closed, stroke } => {
                let v: Vec<Pos2> = pts.iter().map(|q| xf.s(*q + offset)).collect();
                let w = (xf.px(stroke.width) + 1.2).max(2.0);
                paint_polyline(painter, &v, *closed, Stroke::new(w, color), Dash::Solid, xf);
            }
            Prim::Fill { tris, .. } => {
                let mut mesh = egui::Mesh::default();
                let c = Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), 60);
                for t in tris {
                    let i = mesh.vertices.len() as u32;
                    for q in t {
                        mesh.colored_vertex(xf.s(*q + offset), c);
                    }
                    mesh.add_triangle(i, i + 1, i + 2);
                }
                painter.add(egui::Shape::mesh(mesh));
            }
            Prim::Text { pos, text, size, anchor, angle, .. } => {
                paint_text(painter, xf.s(*pos + offset), text, xf.text_px(*size), color, *anchor, *angle);
            }
        }
    }
}

// ---------------------------------------------------------------- camera

pub fn fit(app: &mut App, view: Id, rect: Rect) {
    let d = app.drawing(view);
    let (mn, mx) = d.bounds().unwrap_or((DVec2::new(-2000.0, -2000.0), DVec2::new(12000.0, 10000.0)));
    let size = (mx - mn).max(DVec2::splat(2000.0)) * 1.12;
    let zoom = (rect.width() as f64 / size.x).min(rect.height() as f64 / size.y).max(1e-5);
    app.cams.insert(view, Cam2 { center: (mn + mx) / 2.0, zoom, fitted: true });
}

fn navigate(app: &mut App, ui: &egui::Ui, resp: &egui::Response, rect: Rect, view: Id, scale: f64) {
    let mut cam = app.cams.get(&view).copied().unwrap_or_default();
    if let Some(hover) = resp.hover_pos() {
        let scroll = ui.input(|i| i.smooth_scroll_delta.y);
        let zoom_delta = ui.input(|i| i.zoom_delta());
        let factor = (scroll as f64 * 0.0028).exp() * zoom_delta as f64;
        if (factor - 1.0).abs() > 1e-6 {
            let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale, thin: false };
            let before = xf.w(hover);
            cam.zoom = (cam.zoom * factor).clamp(1e-5, 50.0);
            let xf2 = Xf { rect, center: cam.center, zoom: cam.zoom, scale, thin: false };
            cam.center += before - xf2.w(hover);
        }
    }
    if resp.dragged_by(egui::PointerButton::Middle) || resp.dragged_by(egui::PointerButton::Secondary) {
        let d = resp.drag_delta();
        cam.center += DVec2::new(-d.x as f64, d.y as f64) / cam.zoom;
    }
    if resp.double_clicked_by(egui::PointerButton::Middle) {
        cam.fitted = false;
    }
    app.cams.insert(view, cam);
}

// ---------------------------------------------------------------- picking

/// Elements under `pt`, nearest first, respecting selection options and edit modes.
pub fn pick_candidates(app: &App, view: &View, d: &Drawing, pt: DVec2, tol: f64) -> Vec<Id> {
    let mut scored: Vec<(f64, Id)> = Vec::new();
    let push = |score: f64, id: Id, scored: &mut Vec<(f64, Id)>| {
        if let Some(s) = scored.iter_mut().find(|s| s.1 == id) {
            s.0 = s.0.min(score);
        } else {
            scored.push((score, id));
        }
    };
    for (id, prim) in &d.prims {
        let Some(id) = *id else { continue };
        let score = match prim {
            Prim::Line { pts, closed, .. } => {
                let n = pts.len();
                let mut dmin = f64::MAX;
                for k in 0..n.saturating_sub(1) {
                    dmin = dmin.min(geom::distance_to_segment(pts[k], pts[k + 1], pt));
                }
                if *closed && n > 2 {
                    dmin = dmin.min(geom::distance_to_segment(pts[n - 1], pts[0], pt));
                }
                dmin
            }
            Prim::Fill { tris, .. } => {
                if tris.iter().any(|t| geom::contains(&t[..], pt)) {
                    tol * 0.7
                } else {
                    f64::MAX
                }
            }
            Prim::Text { pos, text, size, .. } => {
                let h = *size as f64 * view.scale;
                let w = text.chars().count() as f64 * h * 0.55;
                if (pt.x - pos.x).abs() <= w / 2.0 + tol && (pt.y - pos.y).abs() <= h / 2.0 + tol { tol * 0.3 } else { f64::MAX }
            }
        };
        if score <= tol {
            push(score, id, &mut scored);
        }
    }
    if is_plan(view) {
        let fp = app.footprints();
        for id in plan::pick_all(&app.doc.data, view, &fp, pt, tol) {
            push(tol * 0.85, id, &mut scored);
        }
    }
    scored.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut out = Vec::new();
    for (_, id) in scored {
        let id = selectable_id(app, view, id);
        if let Some(id) = id {
            if !out.contains(&id) {
                out.push(id);
            }
        }
    }
    out
}

/// Maps a picked id to what gets selected (group members select their group), or None when
/// it may not be selected now.
pub fn selectable_id(app: &App, view: &View, id: Id) -> Option<Id> {
    if let Some(e) = app.el(id) {
        if temp_hidden(app, view.id, e) {
            return None;
        }
        if e.pinned && !app.settings.select_pinned {
            return None;
        }
        if let Some((g, _)) = &app.group_edit {
            return (e.group == Some(*g)).then_some(id);
        }
        if let Some(g) = e.group {
            if app.el(g).is_some() {
                return Some(g);
            }
        }
        if let Some(opt) = e.design_option {
            if app.active_option.is_some() && app.active_option != Some(opt) {
                return None;
            }
        }
        if e.view.is_some_and(|v| v != view.id) {
            return None;
        }
        return Some(id);
    }
    // View markers (sections, elevations, callouts) and this view's crop region.
    app.doc.data.view(id).map(|_| id)
}

pub fn temp_hidden(app: &App, view: Id, e: &Element) -> bool {
    app.temp_hide.get(&view).is_some_and(|t| t.hides(e.id, e.category()))
}

// ---------------------------------------------------------------- snapping

pub fn snap_geom(app: &mut App, view_id: Id) -> Rc<SnapGeom> {
    if let Some(g) = app.cache.snap.get(&view_id) {
        return g.clone();
    }
    let d = app.drawing(view_id);
    let mut g = SnapGeom::default();
    for (id, prim) in &d.prims {
        if let Prim::Line { pts, closed, .. } = prim {
            // Long tessellated arcs only snap through their model arcs (below).
            if pts.len() > 24 && !closed {
                continue;
            }
            g.add_polyline(pts, *closed, *id);
        }
    }
    let p = &app.doc.data;
    if let Some(view) = p.view(view_id) {
        if let Some(level) = view.plan_level() {
            for e in &p.elements {
                if !e.view.is_none_or(|v| v == view_id) {
                    continue;
                }
                match &e.kind {
                    ElementKind::Wall(w) if w.base_level == level => match w.arc() {
                        Some(a) => g.arcs.push((a, Some(e.id))),
                        None => g.segs.push((w.start, w.end, Some(e.id))),
                    },
                    ElementKind::Grid(gr) => {
                        if let Some(a) = gr.arc_mid.and_then(|m| geom::Arc2::through(gr.start, m, gr.end)) {
                            g.arcs.push((a, Some(e.id)));
                        }
                    }
                    ElementKind::Line(l) => {
                        if let (Some(m), 2) = (l.arc_mid, l.pts.len()) {
                            if let Some(a) = geom::Arc2::through(l.pts[0], m, l.pts[1]) {
                                g.arcs.push((a, Some(e.id)));
                            }
                        }
                    }
                    ElementKind::Instance(i) if i.level == level && i.host.is_none() => {
                        g.points.push((rc_core::analysis::instance_location(p, i), Some(e.id)));
                    }
                    _ => {}
                }
            }
        }
    }
    let g = Rc::new(g);
    app.cache.snap.insert(view_id, g.clone());
    g
}

/// Snaps the cursor for the active tool; `reference` is the last picked point.
pub fn snap_point(app: &mut App, view: Id, cursor: DVec2, xf: &Xf, reference: Option<DVec2>, ortho: bool) -> SnapResult {
    let base = snap_geom(app, view);
    let extra: Vec<Seg> = app.sketch.as_ref().filter(|s| s.view == view).map(|s| s.segs.clone()).unwrap_or_default();
    let geom_owned;
    let g: &SnapGeom = if extra.is_empty() {
        &base
    } else {
        let mut g2 = (*base).clone();
        for s in &extra {
            match s {
                Seg::Line(a, b) => g2.segs.push((*a, *b, None)),
                Seg::Arc(..) => {
                    if let Some(a) = s.arc() {
                        g2.arcs.push((a, None));
                    }
                }
            }
        }
        geom_owned = g2;
        &geom_owned
    };
    let imperial = app.doc.data.units.system == rc_core::units::UnitSystem::Imperial;
    let settings = app.settings.snaps.clone();
    let inp = SnapInput { geom: g, cursor, tol: xf.len(10.0), zoom: xf.zoom, reference, ortho, settings: &settings, over: app.snap_override, imperial };
    snap::snap(&inp)
}

fn paint_snap(painter: &egui::Painter, xf: &Xf, s: &SnapResult) {
    let c = style::SNAP;
    let st = Stroke::new(1.8, c);
    for (a, b) in &s.guides {
        let (pa, pb) = (xf.s(*a), xf.s(*b));
        painter.extend(egui::Shape::dashed_line(&[pa, pb], Stroke::new(1.0, style::TRACK), 6.0, 4.0));
    }
    let p = xf.s(s.point);
    let r = 6.0;
    match s.kind {
        SnapKind::Endpoint => {
            painter.rect_stroke(Rect::from_center_size(p, vec2(r * 2.0, r * 2.0)), 0.0, st, egui::StrokeKind::Middle);
        }
        SnapKind::Midpoint => {
            painter.add(egui::Shape::closed_line(vec![p + vec2(0.0, -r), p + vec2(r, r * 0.8), p + vec2(-r, r * 0.8)], st));
        }
        SnapKind::Center => {
            painter.circle_stroke(p, r, st);
            painter.line_segment([p + vec2(-3.0, 0.0), p + vec2(3.0, 0.0)], st);
        }
        SnapKind::Intersection => {
            painter.line_segment([p + vec2(-r, -r), p + vec2(r, r)], st);
            painter.line_segment([p + vec2(r, -r), p + vec2(-r, r)], st);
        }
        SnapKind::Perpendicular => {
            painter.line_segment([p + vec2(-r, r), p + vec2(r, r)], st);
            painter.line_segment([p + vec2(-r * 0.2, r), p + vec2(-r * 0.2, -r)], st);
            painter.line_segment([p + vec2(-r * 0.2, r * 0.2), p + vec2(r * 0.4, r * 0.2)], st);
        }
        SnapKind::Tangent => {
            painter.circle_stroke(p + vec2(0.0, 3.0), r * 0.7, st);
            painter.line_segment([p + vec2(-r, -r * 0.5), p + vec2(r, -r * 0.5)], st);
        }
        SnapKind::Quadrant => {
            painter.add(egui::Shape::closed_line(vec![p + vec2(0.0, -r), p + vec2(r, 0.0), p + vec2(0.0, r), p + vec2(-r, 0.0)], st));
        }
        SnapKind::Nearest => {
            painter.add(egui::Shape::closed_line(vec![p + vec2(-r, -r), p + vec2(r, -r), p + vec2(-r, r), p + vec2(r, r)], st));
        }
        SnapKind::Alignment | SnapKind::Extension | SnapKind::Angle => {
            painter.line_segment([p + vec2(-4.0, -4.0), p + vec2(4.0, 4.0)], Stroke::new(1.4, style::TRACK));
            painter.line_segment([p + vec2(4.0, -4.0), p + vec2(-4.0, 4.0)], Stroke::new(1.4, style::TRACK));
        }
        SnapKind::Free => {}
    }
    if !matches!(s.kind, SnapKind::Free | SnapKind::Angle) {
        let label = s.kind.label();
        let pos = p + vec2(12.0, 12.0);
        let galley = painter.layout_no_wrap(label.to_string(), egui::FontId::proportional(11.0), Color32::from_gray(30));
        let bg = Rect::from_min_size(pos, galley.size()).expand(3.0);
        painter.rect_filled(bg, 2.0, Color32::from_rgb(255, 255, 225));
        painter.rect_stroke(bg, 2.0, Stroke::new(1.0, Color32::from_gray(140)), egui::StrokeKind::Inside);
        painter.galley(pos, galley, Color32::from_gray(30));
    }
}

/// Draws a temporary (listening) dimension between two points with its value.
pub fn temp_dim(painter: &egui::Painter, xf: &Xf, a: DVec2, b: DVec2, text: &str, offset_px: f32) -> Rect {
    let (sa, sb) = (xf.s(a), xf.s(b));
    let d = (sb - sa).normalized();
    let n = vec2(-d.y, d.x);
    let off = n * offset_px;
    let (la, lb) = (sa + off, sb + off);
    let st = Stroke::new(1.0, style::TEMP_DIM);
    painter.line_segment([sa + n * 4.0, la + n * 4.0], st);
    painter.line_segment([sb + n * 4.0, lb + n * 4.0], st);
    painter.line_segment([la, lb], st);
    for q in [la, lb] {
        painter.line_segment([q - (d + n) * 3.5, q + (d + n) * 3.5], Stroke::new(1.4, style::TEMP_DIM));
    }
    let mid = la + (lb - la) / 2.0 + n * 9.0;
    let galley = painter.layout_no_wrap(text.to_string(), egui::FontId::proportional(12.0), style::TEMP_DIM);
    let r = Rect::from_center_size(mid, galley.size() + vec2(6.0, 2.0));
    painter.rect_filled(r, 2.0, Color32::from_rgba_unmultiplied(255, 255, 255, 230));
    painter.galley(r.min + vec2(3.0, 1.0), galley, style::TEMP_DIM);
    r
}

// ---------------------------------------------------------------- the view

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    let is_active = app.active == Some(view_id);
    if !app.cams.get(&view_id).is_some_and(|c| c.fitted) {
        fit(app, view_id, rect);
    }
    navigate(app, ui, &resp, rect, view_id, view.scale);
    let cam = app.cams[&view_id];
    let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: view.scale, thin: app.thin_lines };
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 0.0, canvas_bg(app));
    let drawing = app.drawing(view_id);

    // ---- model graphics
    let temp = app.temp_hide.get(&view_id).cloned();
    let group = app.group_edit.as_ref().map(|g| g.0);
    let index = app.cache.index.clone();
    let black = app.settings.black_canvas;
    {
        let p = &app.doc.data;
        let color_of = |id: Option<Id>, rgb: [u8; 3]| -> Option<Color32> {
            if let Some(e) = id.and_then(|i| index.get(&i)).and_then(|i| p.elements.get(*i)) {
                if temp.as_ref().is_some_and(|t| t.hides(e.id, e.category())) {
                    return None;
                }
                if let Some(g) = group {
                    if e.group != Some(g) && e.id != g {
                        return Some(Color32::from_gray(185));
                    }
                }
            }
            Some(if black && rgb[0] < 70 && rgb[1] < 70 && rgb[2] < 70 { Color32::from_rgb(235, 235, 235) } else { Color32::from_rgb(rgb[0], rgb[1], rgb[2]) })
        };
        let clip_painter = match drawing.crop {
            Some((a, b)) if view.crop_active => painter.with_clip_rect(Rect::from_two_pos(xf.s(a), xf.s(b)).intersect(rect)),
            _ => painter.clone(),
        };
        paint_prims(&clip_painter, &drawing.prims, &xf, &color_of);
    }

    // Reveal hidden elements (magenta) and the view border colours.
    let revealing = app.reveal_hidden.contains(&view_id);
    if revealing {
        let rev = app.revealed_drawing(view_id);
        let visible: HashSet<Id> = drawing.prims.iter().filter_map(|(id, _)| *id).collect();
        let hidden: HashSet<Id> = rev.prims.iter().filter_map(|(id, _)| *id).filter(|id| !visible.contains(id)).collect();
        paint_highlight(&painter, &rev, &hidden, &xf, style::REVEAL, DVec2::ZERO);
        painter.rect_stroke(rect.shrink(2.0), 0.0, Stroke::new(3.0, style::REVEAL), egui::StrokeKind::Inside);
        painter.text(rect.right_top() + vec2(-10.0, 8.0), egui::Align2::RIGHT_TOP, "Reveal Hidden Elements", egui::FontId::proportional(13.0), style::REVEAL);
    } else if temp.as_ref().is_some_and(|t| t.is_active()) {
        painter.rect_stroke(rect.shrink(2.0), 0.0, Stroke::new(3.0, style::TEMP_HIDE), egui::StrokeKind::Inside);
        painter.text(rect.right_top() + vec2(-10.0, 8.0), egui::Align2::RIGHT_TOP, "Temporary Hide/Isolate", egui::FontId::proportional(13.0), style::TEMP_HIDE);
    }
    if let Some((g, _)) = &app.group_edit {
        painter.rect_stroke(rect.shrink(2.0), 0.0, Stroke::new(3.0, Color32::from_rgb(230, 170, 0)), egui::StrokeKind::Inside);
        let name = app.doc.data.type_name_of(app.el(*g).cloned().as_ref().unwrap_or(&Element::new(0, ElementKind::Level(Level::default()))));
        painter.text(rect.left_top() + vec2(10.0, 8.0), egui::Align2::LEFT_TOP, format!("Edit Group: {name}"), egui::FontId::proportional(13.0), Color32::from_rgb(180, 120, 0));
    }
    // Crop region.
    if view.crop_visible {
        if let Some((a, b)) = view.crop {
            let r = Rect::from_two_pos(xf.s(a), xf.s(b));
            let sel = app.selection.contains(&view_id);
            painter.rect_stroke(r, 0.0, Stroke::new(if sel { 2.0 } else { 1.0 }, if sel { style::SELECT } else { ink(app, [40, 40, 40]) }), egui::StrokeKind::Middle);
        }
    }

    // ---- selection and preselection highlights
    let sel: HashSet<Id> = app.selection.iter().copied().collect();
    let mut sel_draw = sel.clone();
    // Group instances highlight through their members.
    for e in app.doc.data.elements.iter().filter(|e| e.group.is_some_and(|g| sel.contains(&g))) {
        sel_draw.insert(e.id);
    }
    let move_offset = match (&app.interact.drag, app.interact.point) {
        (Some(Drag::Move { start, .. }), Some(pt)) if is_active => pt - *start,
        _ => DVec2::ZERO,
    };
    if move_offset != DVec2::ZERO {
        paint_highlight(&painter, &drawing, &sel_draw, &xf, Color32::from_rgba_unmultiplied(20, 110, 255, 120), DVec2::ZERO);
    }
    paint_highlight(&painter, &drawing, &sel_draw, &xf, style::SELECT, move_offset);
    if is_plan(&view) {
        // Rooms and areas highlight their boundary.
        let fp = app.footprints();
        for id in &app.selection {
            if let Some(e) = app.el(*id) {
                if matches!(e.kind, ElementKind::Room(_) | ElementKind::Area(_)) {
                    for o in plan::element_outline(&app.doc.data, e, &fp) {
                        let pts: Vec<Pos2> = o.iter().map(|q| xf.s(*q + move_offset)).collect();
                        paint_polyline(&painter, &pts, true, Stroke::new(2.0, style::SELECT), Dash::Solid, &xf);
                    }
                }
            }
        }
    }
    if is_active {
        if let Some(h) = app.interact.hover.filter(|h| !sel.contains(h)) {
            let mut ids: HashSet<Id> = [h].into_iter().collect();
            for e in app.doc.data.elements.iter().filter(|e| e.group == Some(h)) {
                ids.insert(e.id);
            }
            paint_highlight(&painter, &drawing, &ids, &xf, style::PRESELECT, DVec2::ZERO);
            if is_plan(&view) {
                if let Some(e) = app.el(h) {
                    if matches!(e.kind, ElementKind::Room(_) | ElementKind::Area(_)) {
                        let fp = app.footprints();
                        for o in plan::element_outline(&app.doc.data, e, &fp) {
                            let pts: Vec<Pos2> = o.iter().map(|q| xf.s(*q)).collect();
                            paint_polyline(&painter, &pts, true, Stroke::new(1.5, style::PRESELECT), Dash::Dashed, &xf);
                        }
                    }
                }
            }
        }
    }

    // ---- sketch overlay (magenta boundary lines)
    if let Some(sk) = app.sketch.as_ref().filter(|s| s.view == view_id) {
        for (k, s) in sk.segs.iter().enumerate() {
            let pts: Vec<Pos2> = s.points().iter().map(|q| xf.s(*q)).collect();
            let selected = sk.selected.contains(&k);
            let hovered = is_active && app.interact.hover_seg == Some(k);
            let color = if selected { style::SELECT } else if hovered { style::PRESELECT } else { Color32::from_rgb(220, 0, 160) };
            paint_polyline(&painter, &pts, false, Stroke::new(2.0, color), Dash::Solid, &xf);
            if sk.kind.is_roof() && sk.slopes.get(k).copied().unwrap_or(true) {
                // Slope-defining edge: a small triangle marker.
                let mid = xf.s((s.start() + s.end()) / 2.0);
                let d = (xf.s(s.end()) - xf.s(s.start())).normalized();
                let n = vec2(-d.y, d.x);
                painter.add(egui::Shape::convex_polygon(vec![mid + n * 4.0 - d * 6.0, mid + n * 4.0 + d * 6.0, mid + n * 12.0], Color32::from_rgb(220, 0, 160), Stroke::NONE));
            }
        }
    }

    // Measure result.
    if let Some((a, b)) = app.interact.measure.filter(|_| is_active) {
        let txt = app.doc.data.units.length(a.distance(b));
        temp_dim(&painter, &xf, a, b, &txt, 14.0);
    }

    if !is_active {
        return;
    }
    app.interact.view = Some(view_id);
    app.interact.xf = Some(xf);

    // ---- cursor and snapping
    let cursor = resp.hover_pos().map(|s| xf.w(s));
    app.interact.cursor = cursor;
    let shift = ui.input(|i| i.modifiers.shift);
    let ctrl = ui.input(|i| i.modifiers.command || i.modifiers.ctrl);
    let tool_kind = app.tool.kind;
    let wants_snap = !app.tool.is_select() || matches!(app.interact.drag, Some(Drag::Move { .. }) | Some(Drag::Grip { .. }) | Some(Drag::SketchVertex { .. }));
    let reference = canvas_tools::reference_point(app);
    let mut snapped: Option<SnapResult> = None;
    if let (Some(c), true) = (cursor, wants_snap) {
        let refp = match &app.interact.drag {
            Some(Drag::Move { start, .. }) | Some(Drag::Grip { start, .. }) | Some(Drag::SketchVertex { start, .. }) => Some(*start),
            _ => reference,
        };
        let s = snap_point(app, view_id, c, &xf, refp, shift);
        snapped = Some(s);
    }
    let mut point = snapped.as_ref().map(|s| s.point).or(cursor);
    // Listening dimension: typed length along the rubber band.
    if let (Some(r), Some(pt)) = (reference, point) {
        if !app.typed.trim().is_empty() {
            if let Some(len) = parse_typed(app, &app.typed) {
                let d = (pt - r).normalize_or_zero();
                if d != DVec2::ZERO {
                    point = Some(r + d * len);
                }
            }
        }
    }
    app.interact.snap = snapped.clone();
    app.interact.point = point;

    if app.tool.is_select() && app.sketch.as_ref().is_none_or(|s| s.view != view_id) {
        select_mode(app, ui, &resp, &painter, &xf, &view, &drawing, cursor, ctrl, shift);
    } else if app.tool.is_select() {
        sketch_select_mode(app, ui, &resp, &xf, view_id, cursor, ctrl);
    } else {
        let clicked = resp.clicked_by(egui::PointerButton::Primary);
        canvas_tools::handle(app, ui, &resp, &painter, &xf, &view, &drawing, cursor, point, clicked);
    }
    if let Some(s) = &app.interact.snap {
        if wants_snap {
            paint_snap(&painter, &xf, s);
        }
    }
    // Typed value box.
    if !app.typed.is_empty() {
        if let Some(c) = resp.hover_pos() {
            let r = Rect::from_min_size(c + vec2(16.0, -30.0), vec2(90.0, 20.0));
            painter.rect_filled(r, 2.0, Color32::WHITE);
            painter.rect_stroke(r, 2.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Inside);
            painter.text(r.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, &app.typed, egui::FontId::proportional(12.0), Color32::BLACK);
        }
    }
    // Snap override indicator.
    if let Some(o) = app.snap_override {
        let t = match o {
            crate::snap::Override::Off => "Snaps off".to_string(),
            crate::snap::Override::Only(k) => format!("Snap: {}", k.label()),
        };
        painter.text(rect.left_bottom() + vec2(10.0, -10.0), egui::Align2::LEFT_BOTTOM, t, egui::FontId::proportional(12.0), style::SNAP);
    }
    let _ = tool_kind;

    // ---- right-click menu
    context_menu(app, &resp, &view);
}

fn parse_typed(app: &App, s: &str) -> Option<f64> {
    app.doc.data.units.parse(s.trim(), ParamKind::Length).filter(|v| *v > 0.0)
}

fn select_mode(app: &mut App, ui: &egui::Ui, resp: &egui::Response, painter: &egui::Painter, xf: &Xf, view: &View, drawing: &Drawing, cursor: Option<DVec2>, ctrl: bool, shift: bool) {
    let tol = xf.len(7.0);
    // Grips and controls of the selection take precedence over picking.
    let grip_list = grips::grips(app, view, xf);
    let mut grip_hover: Option<(grips::GripKind, Id, DVec2)> = None;
    if let (Some(c), None) = (cursor, &app.interact.drag) {
        for g in &grip_list {
            if xf.s(g.pos).distance(xf.s(c)) <= 7.0 {
                grip_hover = Some((g.kind.clone(), g.id, g.pos));
                break;
            }
        }
    }
    app.interact.hover_grip = grip_hover.as_ref().map(|g| g.0.clone());
    grips::paint(painter, xf, &grip_list, app.interact.hover_grip.as_ref());

    // Temporary dimensions (editable).
    let temp_dims = if app.interact.drag.is_none() { crate::tempdims::compute(app, view, xf) } else { vec![] };
    let mut tdim_hit: Option<usize> = None;
    for (k, td) in temp_dims.iter().enumerate() {
        let txt = app.doc.data.units.length(td.value);
        let r = temp_dim(painter, xf, td.a, td.b, &txt, td.offset_px);
        if let Some(c) = cursor {
            if r.contains(xf.s(c)) {
                tdim_hit = Some(k);
                painter.rect_stroke(r, 2.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Outside);
            }
        }
    }
    crate::tempdims::editor(app, ui, xf, &temp_dims);

    // Hover with Tab cycling.
    if app.interact.drag.is_none() {
        let cands = match cursor {
            Some(c) => {
                if app.reveal_hidden.contains(&view.id) {
                    let rev = app.revealed_drawing(view.id);
                    pick_candidates(app, view, &rev, c, tol)
                } else {
                    pick_candidates(app, view, drawing, c, tol)
                }
            }
            None => vec![],
        };
        if let Some(c) = cursor {
            if app.interact.tab_at.is_some_and(|t| t.distance(c) > tol * 2.0) {
                app.interact.tab_index = 0;
                app.interact.tab_at = None;
            }
            if app.interact.tab_pressed && !cands.is_empty() {
                app.interact.tab_index = (app.interact.tab_index + 1) % cands.len();
                app.interact.tab_at = Some(c);
            }
        }
        app.interact.tab_pressed = false;
        app.interact.hover = if grip_hover.is_some() || tdim_hit.is_some() { None } else { cands.get(app.interact.tab_index.min(cands.len().saturating_sub(1))).copied() };
        if !cands.is_empty() {
            let h = app.interact.hover;
            app.interact.prompt = h.map(|h| describe(app, h)).unwrap_or_default();
            if cands.len() > 1 {
                app.interact.prompt.push_str("  (Tab to cycle)");
            }
        } else {
            app.interact.prompt = "Click to select, Tab for alternates, Ctrl adds, Shift removes. Drag right for window, left for crossing selection.".into();
        }
    }

    // Temp dim text click starts editing.
    if resp.clicked_by(egui::PointerButton::Primary) {
        if let Some(k) = tdim_hit {
            let id = app.selection.first().copied().unwrap_or(0);
            let v = temp_dims[k].value;
            app.interact.temp_dim_edit = Some(TempDimEdit { id, index: k, text: app.doc.data.units.length(v), focus: true });
            return;
        }
    }

    // Drags.
    if resp.drag_started_by(egui::PointerButton::Primary) {
        let press = ui.input(|i| i.pointer.press_origin()).map(|p| xf.w(p)).or(cursor);
        if let Some(start) = press {
            if let Some((kind, id, pos)) = grip_hover.clone() {
                app.interact.drag = Some(Drag::Grip { id, grip: kind, start: pos });
            } else {
                let under = pick_candidates(app, view, drawing, start, tol).first().copied();
                match under {
                    Some(h) if app.selection.contains(&h) || app.settings.drag_on_selection => {
                        if !app.selection.contains(&h) {
                            app.select(vec![h]);
                        }
                        let movable = app.selection.iter().all(|id| app.el(*id).is_some_and(|e| !e.pinned));
                        if movable && is_plan(view) || app.selection.iter().all(|id| app.el(*id).is_some_and(|e| e.view == Some(view.id))) {
                            app.interact.drag = Some(Drag::Move { start, ids: app.selection.clone() });
                        } else if !movable {
                            app.error("Pinned elements cannot be moved. Unpin them first (UP).");
                        }
                    }
                    _ => app.interact.drag = Some(Drag::Window { start }),
                }
            }
        }
    }
    match app.interact.drag.clone() {
        Some(Drag::Window { start }) => {
            if let Some(c) = cursor {
                let (a, b) = (xf.s(start), xf.s(c));
                let crossing = b.x < a.x;
                let r = Rect::from_two_pos(a, b);
                painter.rect_filled(r, 0.0, if crossing { Color32::from_rgba_unmultiplied(60, 200, 90, 30) } else { Color32::from_rgba_unmultiplied(40, 120, 255, 30) });
                let st = Stroke::new(1.0, style::ACCENT);
                if crossing {
                    painter.extend(egui::Shape::dashed_line(&[r.left_top(), r.right_top(), r.right_bottom(), r.left_bottom(), r.left_top()], st, 5.0, 3.0));
                } else {
                    painter.rect_stroke(r, 0.0, st, egui::StrokeKind::Middle);
                }
                if resp.drag_stopped() {
                    let ids = window_select(app, view, drawing, start, c, crossing);
                    let mut sel = if ctrl || shift { app.selection.clone() } else { vec![] };
                    for id in ids {
                        if shift {
                            sel.retain(|s| *s != id);
                        } else if !sel.contains(&id) {
                            sel.push(id);
                        }
                    }
                    app.select(sel);
                    app.interact.drag = None;
                }
            }
        }
        Some(Drag::Move { start, ids }) => {
            if resp.drag_stopped() {
                if let Some(pt) = app.interact.point {
                    let delta = pt - start;
                    if delta.length() > 1e-6 {
                        if ctrl {
                            let ids2 = ids.clone();
                            if let Some(new) = app.run("Copy", |p| Ok(rc_core::edit::copy_elements(p, &ids2, delta))) {
                                app.select(new);
                            }
                        } else {
                            let ids2 = ids.clone();
                            app.run("Move", |p| {
                                rc_core::edit::move_elements(p, &ids2, delta);
                                Ok(())
                            });
                        }
                    }
                }
                app.interact.drag = None;
            } else if let Some(pt) = app.interact.point {
                crate::canvas::temp_dim(painter, xf, start, pt, &app.doc.data.units.length(start.distance(pt)), -18.0);
            }
        }
        Some(Drag::Grip { id, grip, start }) => {
            if let Some(pt) = app.interact.point {
                grips::preview(app, painter, xf, view, id, &grip, start, pt);
                if resp.drag_stopped() {
                    grips::apply(app, view, id, &grip, start, pt);
                    app.interact.drag = None;
                }
            }
        }
        _ => {}
    }
    if app.interact.drag.is_some() {
        return;
    }

    // Grip controls (flip arrows, bubbles, locks) are clicks.
    if resp.clicked_by(egui::PointerButton::Primary) {
        if let Some((kind, id, _)) = &grip_hover {
            if grips::click(app, view, *id, kind) {
                return;
            }
        }
    }
    if resp.double_clicked_by(egui::PointerButton::Primary) {
        if let Some(h) = app.interact.hover {
            double_click(app, h);
            return;
        }
    }
    if resp.clicked_by(egui::PointerButton::Primary) {
        match app.interact.hover {
            Some(h) if ctrl => {
                let mut s = app.selection.clone();
                if !s.contains(&h) {
                    s.push(h);
                }
                app.select(s);
            }
            Some(h) if shift => {
                let mut s = app.selection.clone();
                s.retain(|x| *x != h);
                app.select(s);
            }
            Some(h) => app.select(vec![h]),
            None if !ctrl && !shift => {
                if !app.selection.is_empty() {
                    app.select(vec![]);
                }
            }
            None => {}
        }
        app.interact.tab_index = 0;
    }
}

fn sketch_select_mode(app: &mut App, ui: &egui::Ui, resp: &egui::Response, xf: &Xf, view_id: Id, cursor: Option<DVec2>, ctrl: bool) {
    let tol = xf.len(7.0);
    let Some(sk) = app.sketch.as_ref() else { return };
    let hover = cursor.and_then(|c| {
        sk.segs.iter().enumerate().map(|(k, s)| (s.distance_to(c), k)).filter(|(d, _)| *d <= tol).min_by(|a, b| a.0.total_cmp(&b.0)).map(|x| x.1)
    });
    app.interact.hover_seg = hover;
    app.interact.prompt = "Sketch mode: select lines to edit or delete them, drag endpoints, or pick a draw tool. Click Finish (✓) when done.".into();
    // Dragging a vertex moves every segment end there.
    if resp.drag_started_by(egui::PointerButton::Primary) {
        if let Some(c) = ui.input(|i| i.pointer.press_origin()).map(|p| xf.w(p)) {
            let ends: Vec<(usize, bool)> = sk
                .segs
                .iter()
                .enumerate()
                .flat_map(|(k, s)| [(k, true, s.start()), (k, false, s.end())])
                .filter(|(_, _, q)| q.distance(c) <= tol)
                .map(|(k, st, _)| (k, st))
                .collect();
            if let Some(&(k, st)) = ends.first() {
                let q = if st { sk.segs[k].start() } else { sk.segs[k].end() };
                app.interact.drag = Some(Drag::SketchVertex { ends, start: q });
            }
        }
    }
    if let Some(Drag::SketchVertex { ends, .. }) = app.interact.drag.clone() {
        if let (Some(pt), Some(sk)) = (app.interact.point, app.sketch.as_mut()) {
            for (k, st) in &ends {
                let s = &mut sk.segs[*k];
                *s = match *s {
                    Seg::Line(a, b) => {
                        if *st {
                            Seg::Line(pt, b)
                        } else {
                            Seg::Line(a, pt)
                        }
                    }
                    Seg::Arc(a, m, b) => {
                        if *st {
                            Seg::Arc(pt, m, b)
                        } else {
                            Seg::Arc(a, m, pt)
                        }
                    }
                };
            }
        }
        if resp.drag_stopped() {
            app.interact.drag = None;
        }
        return;
    }
    if resp.clicked_by(egui::PointerButton::Primary) {
        if let Some(sk) = app.sketch.as_mut() {
            match hover {
                Some(k) if ctrl => {
                    if !sk.selected.contains(&k) {
                        sk.selected.push(k);
                    }
                }
                Some(k) => sk.selected = vec![k],
                None => sk.selected.clear(),
            }
        }
    }
    let _ = view_id;
}

fn window_select(app: &App, view: &View, d: &Drawing, a: DVec2, b: DVec2, crossing: bool) -> Vec<Id> {
    let (mn, mx) = (a.min(b), a.max(b));
    let inside = |q: DVec2| q.x >= mn.x && q.x <= mx.x && q.y >= mn.y && q.y <= mx.y;
    let mut ids: Vec<Id> = Vec::new();
    if is_plan(view) {
        let fp = app.footprints();
        ids = plan::select_in_rect(&app.doc.data, view, &fp, a, b, crossing);
    }
    // Annotation and section/elevation geometry from the drawing.
    let mut all_in: std::collections::HashMap<Id, bool> = std::collections::HashMap::new();
    for (id, prim) in &d.prims {
        let Some(id) = id else { continue };
        let pts: Vec<DVec2> = match prim {
            Prim::Line { pts, .. } => pts.clone(),
            Prim::Fill { tris, .. } => tris.iter().flatten().copied().collect(),
            Prim::Text { pos, .. } => vec![*pos],
        };
        let any = pts.iter().any(|q| inside(*q));
        let all = pts.iter().all(|q| inside(*q));
        let e = all_in.entry(*id).or_insert(true);
        if crossing {
            if any {
                *e = *e && true;
            } else {
                // Track that some prim is not inside (doesn't exclude for crossing).
            }
            if any && !ids.contains(id) {
                ids.push(*id);
            }
        } else {
            *e = *e && all;
        }
    }
    if !crossing {
        for (id, ok) in all_in {
            if ok && !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    let mut out = Vec::new();
    for id in ids {
        if app.doc.data.view(id).is_some() && id == view.id {
            continue;
        }
        if let Some(s) = selectable_id(app, view, id) {
            if !out.contains(&s) {
                out.push(s);
            }
        }
    }
    out
}

pub fn describe(app: &App, id: Id) -> String {
    if let Some(e) = app.el(id) {
        let name = app.doc.data.display_name(e);
        let cat = e.category().label();
        return format!("{cat} : {name}");
    }
    if let Some(v) = app.doc.data.view(id) {
        return format!("Views : {} : {}", v.type_label(), v.name);
    }
    String::new()
}

fn double_click(app: &mut App, id: Id) {
    if let Some(e) = app.el(id).cloned() {
        app.select(vec![id]);
        match &e.kind {
            ElementKind::Floor(_) | ElementKind::Ceiling(_) | ElementKind::Region(_) => actions::exec(app, Cmd::EditBoundary),
            ElementKind::Roof(r) if r.kind == RoofKind::Footprint => actions::exec(app, Cmd::EditBoundary),
            ElementKind::GroupInstance(_) => actions::exec(app, Cmd::EditGroup),
            ElementKind::Instance(_) => actions::exec(app, Cmd::EditFamily),
            ElementKind::Text(_) => app.dialogs.text_edit = Some(id),
            ElementKind::Dimension(_) => app.dialogs.dim_text = Some(id),
            ElementKind::Room(_) | ElementKind::Area(_) | ElementKind::Tag(_) => app.dialogs.rename_element = Some(id),
            _ => {}
        }
        return;
    }
    if app.doc.data.view(id).is_some() && app.active != Some(id) {
        app.open_view(id);
    }
}

fn context_menu(app: &mut App, resp: &egui::Response, view: &View) {
    let mut run: Option<Cmd> = None;
    let sc = app.settings.shortcuts.clone();
    resp.context_menu(|ui| {
        ui.set_min_width(220.0);
        let item = |ui: &mut egui::Ui, label: &str, cmd: Cmd, run: &mut Option<Cmd>| {
            let keys = sc.keys(cmd);
            let text = if keys.is_empty() { label.to_string() } else { format!("{label}    {keys}") };
            if ui.button(text).clicked() {
                *run = Some(cmd);
                ui.close();
            }
        };
        if !app.tool.is_select() || app.sketch.is_some() {
            if ui.button("Cancel").clicked() {
                app.cancel();
                ui.close();
            }
        }
        if let Some(last) = app.last_cmd {
            let label = format!("Repeat [{}]", last.info().label);
            if ui.button(label).clicked() {
                run = Some(last);
                ui.close();
            }
        }
        if !app.recent_cmds.is_empty() {
            ui.menu_button("Recent Commands", |ui| {
                for c in app.recent_cmds.clone().into_iter().rev().take(8) {
                    if ui.button(c.info().label).clicked() {
                        run = Some(c);
                        ui.close();
                    }
                }
            });
        }
        ui.separator();
        if !app.selection.is_empty() {
            item(ui, "Delete", Cmd::Delete, &mut run);
            item(ui, "Create Similar", Cmd::CreateSimilar, &mut run);
            if app.selection.len() == 1 && app.el(app.selection[0]).is_some_and(|e| matches!(e.kind, ElementKind::Instance(_))) {
                item(ui, "Edit Family", Cmd::EditFamily, &mut run);
            }
            if app.selection.iter().any(|id| app.doc.data.view(*id).is_some()) {
                item(ui, "Go to View", Cmd::GoToView, &mut run);
            }
            ui.menu_button("Hide in View", |ui| {
                item(ui, "Elements", Cmd::HideElements, &mut run);
                item(ui, "Category", Cmd::HideCategory, &mut run);
            });
            item(ui, "Override Graphics in View...", Cmd::OverrideElements, &mut run);
            ui.menu_button("Select All Instances", |ui| {
                item(ui, "Visible in View", Cmd::SelectAllVisible, &mut run);
                item(ui, "In Entire Project", Cmd::SelectAllProject, &mut run);
            });
            ui.separator();
        }
        if ui.button("Select Previous").clicked() {
            let prev = app.prev_selection.clone();
            app.select(prev);
            ui.close();
        }
        ui.separator();
        item(ui, "Zoom In Region", Cmd::ZoomRegion, &mut run);
        item(ui, "Zoom Out (2x)", Cmd::ZoomOut, &mut run);
        item(ui, "Zoom To Fit", Cmd::ZoomFit, &mut run);
        ui.separator();
        item(ui, "Properties", Cmd::ToggleProperties, &mut run);
        if view.is_graphical() {
            item(ui, "View Range...", Cmd::ViewRange, &mut run);
        }
    });
    if let Some(c) = run {
        actions::exec(app, c);
    }
}

// ---------------------------------------------------------------- keys routed from the app

/// Enter: finishes chains and sketches, applies typed values.
pub fn enter(app: &mut App) {
    if app.interact.temp_dim_edit.is_some() {
        return;
    }
    if !app.tool.is_select() {
        canvas_tools::enter(app);
        return;
    }
    if app.sketch.is_some() {
        actions::exec(app, Cmd::FinishSketch);
    }
}

/// Space: flips/rotates the element being placed or the selection.
pub fn space(app: &mut App) {
    match app.tool.kind {
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting | ToolKind::PlaceGroup | ToolKind::Text | ToolKind::Symbol => {
            app.opts.rotation = (app.opts.rotation + 90.0) % 360.0;
        }
        ToolKind::Wall => {
            // Flip the location line side for the next segment.
            app.opts.offset = -app.opts.offset;
        }
        ToolKind::Door | ToolKind::Window => app.opts.place_flip = !app.opts.place_flip,
        ToolKind::Select => {
            let ids = app.selection.clone();
            if ids.is_empty() {
                return;
            }
            app.run("Flip", |p| {
                for id in &ids {
                    match p.element_mut(*id).map(|e| &mut e.kind) {
                        Some(ElementKind::Instance(i)) if i.host.is_some() => i.flip_facing = !i.flip_facing,
                        Some(ElementKind::Instance(i)) => i.rotation_deg = (i.rotation_deg + 90.0) % 360.0,
                        Some(ElementKind::Wall(w)) => w.flipped = !w.flipped,
                        _ => {}
                    }
                }
                Ok(())
            });
        }
        _ => {}
    }
}

/// Arrow keys nudge the selection by a small screen distance (Shift: larger).
pub fn nudge(app: &mut App, dir: DVec2, big: bool) {
    let Some(xf) = app.interact.xf else { return };
    if app.selection.is_empty() || !app.tool.is_select() {
        return;
    }
    let step = crate::snap::length_increment(xf.zoom, app.doc.data.units.system == rc_core::units::UnitSystem::Imperial) * if big { 10.0 } else { 1.0 };
    let ids = app.selection.clone();
    app.run("Nudge", |p| {
        rc_core::edit::move_elements(p, &ids, dir * step);
        Ok(())
    });
}
