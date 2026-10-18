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

/// Pan/zoom history of one 2D view (Previous/Next Pan/Zoom).
#[derive(Clone, Debug, Default)]
pub struct NavHistory {
    pub back: Vec<Cam2>,
    pub fwd: Vec<Cam2>,
    /// The last camera that stayed still long enough to count as a step.
    pub settled: Option<Cam2>,
    /// When the camera last moved away from `settled`.
    pub moving_since: Option<f64>,
}

fn same_cam(a: &Cam2, b: &Cam2) -> bool {
    a.center.distance(b.center) < 1e-6 && (a.zoom - b.zoom).abs() < 1e-12
}

/// Records settled cameras so Previous/Next Pan/Zoom can step through them.
fn track_history(app: &mut App, ctx: &egui::Context, view: Id) {
    let Some(cam) = app.cams.get(&view).copied() else { return };
    let now = app.now;
    let h = app.nav_history.entry(view).or_default();
    let Some(settled) = h.settled else {
        h.settled = Some(cam);
        return;
    };
    if same_cam(&settled, &cam) {
        h.moving_since = None;
        return;
    }
    let since = *h.moving_since.get_or_insert(now);
    if now - since > 0.5 {
        h.back.push(settled);
        h.fwd.clear();
        h.settled = Some(cam);
        h.moving_since = None;
    } else {
        ctx.request_repaint_after(std::time::Duration::from_millis(550));
    }
}

/// Steps back (or forward) through a view's pan/zoom history.
pub fn history_step(app: &mut App, view: Id, back: bool) {
    let Some(cam) = app.cams.get(&view).copied() else { return };
    let h = app.nav_history.entry(view).or_default();
    let target = if back { h.back.pop() } else { h.fwd.pop() };
    if let Some(t) = target {
        if back { h.fwd.push(cam) } else { h.back.push(cam) }
        h.settled = Some(t);
        h.moving_since = None;
        app.cams.insert(view, Cam2 { fitted: true, ..t });
    }
}

pub fn can_step(app: &App, view: Id, back: bool) -> bool {
    app.nav_history.get(&view).is_some_and(|h| if back { !h.back.is_empty() } else { !h.fwd.is_empty() })
}

fn wheel_on(ui: &egui::Ui, view: Id) -> bool {
    crate::wheel::load(ui, view).on
}

/// Runs the 2D Wheel: it floats under the cursor; pressing ZOOM, PAN or REWIND and dragging
/// navigates the view.
fn wheel_2d(app: &mut App, ui: &egui::Ui, resp: &egui::Response, rect: Rect, view: Id, scale: f64, cam: &mut Cam2) {
    use crate::wheel::{self, Wedge};
    let mut st = wheel::load(ui, view);
    if !st.on {
        return;
    }
    let Some(p) = ui.input(|i| i.pointer.latest_pos()).filter(|p| rect.contains(*p)) else { return };
    // The wheel appears under the cursor once it has left the navigation bar.
    if st.center.is_none() && p.x > rect.right() - 60.0 {
        return;
    }
    let c = if st.drag.is_some() { st.center.unwrap_or(p) } else { wheel::follow(&mut st, p) };
    if resp.drag_started_by(egui::PointerButton::Primary) || (resp.clicked_by(egui::PointerButton::Primary) && st.drag.is_none()) {
        let press = ui.input(|i| i.pointer.press_origin()).unwrap_or(p);
        if wheel::on_close(c, press) {
            st = wheel::WheelState::default();
            wheel::store(ui, view, st);
            return;
        }
        st.drag = wheel::wedge_at(false, c, press);
        st.accum = 0.0;
        // Wheel moves are history steps right away (Rewind goes back to them).
        if st.drag.is_some_and(|w| w != Wedge::Rewind) {
            let h = app.nav_history.entry(view).or_default();
            if h.back.last().is_none_or(|b| !same_cam(b, cam)) {
                h.back.push(*cam);
                h.fwd.clear();
            }
        }
    }
    if resp.dragged_by(egui::PointerButton::Primary) {
        let d = resp.drag_delta();
        match st.drag {
            Some(Wedge::Zoom) => {
                let factor = (-d.y as f64 * 0.01).exp();
                let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale, thin: false };
                let pivot = xf.w(c);
                cam.zoom = (cam.zoom * factor).clamp(1e-5, 50.0);
                let xf2 = Xf { rect, center: cam.center, zoom: cam.zoom, scale, thin: false };
                cam.center += pivot - xf2.w(c);
            }
            Some(Wedge::Pan) => {
                cam.center += DVec2::new(-d.x as f64, d.y as f64) / cam.zoom;
                st.center = Some(c + d);
            }
            Some(Wedge::Rewind) => {
                st.accum += d.x;
                if st.accum.abs() > 40.0 {
                    app.cams.insert(view, *cam);
                    history_step(app, view, st.accum < 0.0);
                    if let Some(n) = app.cams.get(&view) {
                        *cam = *n;
                    }
                    st.accum = 0.0;
                }
            }
            _ => {}
        }
    }
    if resp.drag_stopped() || ui.input(|i| i.pointer.any_released()) {
        if st.drag.is_some() {
            let h = app.nav_history.entry(view).or_default();
            h.settled = Some(*cam);
            h.moving_since = None;
        }
        st.drag = None;
    }
    wheel::store(ui, view, st);
}

/// The navigation bar at the top right of 2D views: the 2D wheel (pan) and the zoom tools.
fn nav_bar_2d(app: &mut App, ui: &mut egui::Ui, rect: Rect, view: Id) {
    let area = Rect::from_min_size(rect.right_top() + vec2(-34.0, 8.0), vec2(26.0, 62.0));
    let p = ui.painter();
    p.rect_filled(area, 3.0, Color32::from_rgba_unmultiplied(244, 246, 248, 235));
    p.rect_stroke(area, 3.0, Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    let pan_on = wheel_on(ui, view);
    // 2D wheel.
    let r = Rect::from_min_size(area.min + vec2(2.0, 3.0), vec2(22.0, 22.0));
    let resp = ui.interact(r, egui::Id::new(("nav2d-wheel", view)), Sense::click());
    if pan_on {
        ui.painter().rect_filled(r, 2.0, style::accent_light());
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 2.0, style::hover());
    }
    let c = r.center();
    ui.painter().circle_stroke(c, 8.0, Stroke::new(2.2, Color32::from_rgb(120, 126, 136)));
    ui.painter().circle_stroke(c, 8.0, Stroke::new(1.0, Color32::from_rgb(70, 76, 86)));
    ui.painter().text(c, egui::Align2::CENTER_CENTER, "2D", style::font(7.5), Color32::from_rgb(40, 90, 170));
    if resp.clicked() {
        crate::wheel::store(ui, view, crate::wheel::WheelState { on: !pan_on, ..Default::default() });
    }
    resp.on_hover_text("2D Wheel: Zoom, Pan and Rewind under the cursor (Esc closes)");
    let sep_y = area.top() + 30.0;
    ui.painter().line_segment([pos2(area.left() + 4.0, sep_y), pos2(area.right() - 4.0, sep_y)], Stroke::new(1.0, style::border()));
    // Zoom: click = Zoom In Region, arrow = menu.
    let r = Rect::from_min_size(pos2(area.left() + 2.0, sep_y + 2.0), vec2(22.0, 28.0));
    let resp = ui.interact(r, egui::Id::new(("nav2d-zoom", view)), Sense::click());
    if resp.hovered() {
        ui.painter().rect_filled(r, 2.0, style::hover());
    }
    crate::icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(3.0, 1.0), vec2(16.0, 16.0)), crate::icons::Icon::ZoomRegion, true);
    let a = pos2(r.center().x, r.bottom() - 6.0);
    ui.painter().add(egui::Shape::convex_polygon(vec![a + vec2(-3.0, -1.5), a + vec2(3.0, -1.5), a + vec2(0.0, 1.5)], style::text(), Stroke::NONE));
    let on_arrow = ui.input(|i| i.pointer.interact_pos()).is_some_and(|p| p.y > r.bottom() - 11.0);
    let toggle = if resp.clicked() && on_arrow {
        Some(egui::SetOpenCommand::Toggle)
    } else {
        if resp.clicked() {
            actions::exec(app, Cmd::ZoomRegion);
        }
        None
    };
    let resp = resp.on_hover_text("Zoom In Region (arrow: more zoom tools)");
    egui::Popup::menu(&resp).open_memory(toggle).close_behavior(egui::PopupCloseBehavior::CloseOnClick).show(|ui| {
        ui.set_min_width(170.0);
        for (label, cmd) in [("Zoom In Region", Cmd::ZoomRegion), ("Zoom Out (2x)", Cmd::ZoomOut), ("Zoom To Fit", Cmd::ZoomFit), ("Previous Pan/Zoom", Cmd::PrevPanZoom), ("Next Pan/Zoom", Cmd::NextPanZoom)] {
            if ui.add_enabled(actions::enabled(app, cmd), egui::Button::new(label).frame(false)).clicked() {
                actions::exec(app, cmd);
            }
        }
    });
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
    /// Pixel width for a line weight in paper millimetres. Like the reference app, weights
    /// map to fixed screen widths that do not change with zoom (thin lines 1 px, cut walls ~2.5 px).
    pub fn px(&self, paper_mm: f32) -> f32 {
        if self.thin {
            return 1.0;
        }
        (paper_mm * 5.0).clamp(1.0, 4.0)
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
    /// Element under the cursor in a 3D view (blue edges).
    pub hover3d: Option<Id>,
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
    /// Enter pressed while drawing a spline: finish it.
    pub finish_spline: bool,
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

/// Snaps a font size to a small set of sizes (fewer glyph rasterisations while zooming).
fn quantize_font(h: f32) -> f32 {
    let step = if h < 10.0 { 1.0 } else if h < 24.0 { 2.0 } else if h < 48.0 { 4.0 } else { 8.0 };
    (h / step).round().max(1.0) * step
}

#[allow(clippy::too_many_arguments)]
pub fn paint_text_ex(painter: &egui::Painter, pos: Pos2, text: &str, h: f32, color: Color32, anchor: Anchor, angle: f32, bold: bool) {
    if h < 1.5 || text.is_empty() {
        return;
    }
    let h = quantize_font(h.min(96.0));
    let font = if bold { style::bold(h) } else { egui::FontId::proportional(h) };
    let galley = painter.layout_no_wrap(text.to_string(), font, color);
    let align = match anchor {
        Anchor::Center => egui::Align2::CENTER_CENTER,
        Anchor::Left => egui::Align2::LEFT_BOTTOM,
        Anchor::Right => egui::Align2::RIGHT_BOTTOM,
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
            Prim::Image { asset, min, max } => {
                let r = egui::Rect::from_two_pos(xf.s(*min), xf.s(*max));
                if !clip.intersects(r) {
                    continue;
                }
                match crate::images::texture(*asset) {
                    Some(t) => {
                        painter.image(t, r, egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)), Color32::WHITE);
                    }
                    None => {
                        let s = Stroke::new(1.0, Color32::from_gray(150));
                        painter.rect_stroke(r, 0.0, s, egui::StrokeKind::Inside);
                        painter.line_segment([r.left_top(), r.right_bottom()], s);
                        painter.line_segment([r.right_top(), r.left_bottom()], s);
                    }
                }
            }
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
            Prim::Text { pos, text, size, color, anchor, angle, bold } => {
                let Some(c) = color_of(*id, *color) else { continue };
                let p = xf.s(*pos);
                if !clip.contains(p) {
                    continue;
                }
                paint_text_ex(painter, p, text, xf.text_px(*size), c, *anchor, *angle, *bold);
            }
        }
    }
}

/// Paints the prims of `ids` as a highlight (selection/preselection).
/// The selection blue for areas: over white it comes out as the reference app's (125, 146, 202).
const SELECT_FILL: Color32 = Color32::from_rgba_unmultiplied_const(19, 57, 159, 140);

/// Selected walls cut by a plan view fill solid selection blue between their openings, as the
/// reference app shows them (their cut patterns and outlines turn blue over it).
fn paint_selected_wall_fills(app: &App, painter: &egui::Painter, xf: &Xf, view: &View, ids: &HashSet<Id>, offset: DVec2) {
    let ViewKind::FloorPlan { level, cut_height, .. } = view.kind else { return };
    let p = &app.doc.data;
    let selected: Vec<(Id, &Wall)> = p.walls().filter(|(e, _)| ids.contains(&e.id)).map(|(e, w)| (e.id, w)).collect();
    if selected.is_empty() {
        return;
    }
    let cut_z = p.level_elevation(level) + cut_height;
    let footprints = rc_core::analysis::wall_footprints(p);
    // The part of a polygon where f >= 0 (f linear).
    let clip = |poly: &[DVec2], f: &dyn Fn(DVec2) -> f64| -> Vec<DVec2> {
        let mut out = Vec::new();
        for k in 0..poly.len() {
            let (a, b) = (poly[k], poly[(k + 1) % poly.len()]);
            let (fa, fb) = (f(a), f(b));
            if fa >= 0.0 {
                out.push(a);
            }
            if (fa >= 0.0) != (fb >= 0.0) {
                out.push(a + (b - a) * (fa / (fa - fb)));
            }
        }
        out
    };
    for (id, w) in selected {
        if rc_core::analysis::wall_base_z(p, w) > cut_z || rc_core::build3d::wall_top_extent(p, w) < cut_z {
            continue;
        }
        let Some(fp) = footprints.get(&id) else { continue };
        let mut poly = fp.polygon();
        // Ends running into another wall (T-junctions) stop at that wall's face.
        for end in [w.start, w.end] {
            for (oe, ow) in p.walls().filter(|(e, ow)| e.id != id && ow.arc().is_none()) {
                let Some(of) = footprints.get(&oe.id) else { continue };
                // Only T-junctions: at L corners the mitred ends meet and stay whole.
                let corner = end.distance(ow.start).min(end.distance(ow.end)) < rc_core::analysis::wall_thickness(p, ow) + 1.0;
                if corner || !rc_core::geom::contains(&of.polygon(), end) {
                    continue;
                }
                let (n2, h2) = (ow.normal(), rc_core::analysis::wall_thickness(p, ow) / 2.0);
                let mid = (w.start + w.end) / 2.0;
                let side = if (mid - ow.start).dot(n2) >= 0.0 { 1.0 } else { -1.0 };
                let clipped = clip(&poly, &|q| side * (q - ow.start).dot(n2) - h2);
                if clipped.len() >= 3 {
                    poly = clipped;
                }
            }
        }
        let mut pieces = vec![poly.clone()];
        if fp.straight {
            let dir = (w.end - w.start).normalize_or_zero();
            let u = move |q: DVec2| (q - w.start).dot(dir);
            let mut openings: Vec<(f64, f64)> = rc_core::build3d::wall_openings(p, id, w).into_iter().filter(|(_, _, z0, z1)| *z0 <= cut_z && cut_z <= *z1).map(|(u0, u1, _, _)| (u0, u1)).collect();
            openings.sort_by(|a, b| a.0.total_cmp(&b.0));
            if !openings.is_empty() {
                pieces.clear();
                let mut from = f64::MIN;
                for (u0, u1) in openings.iter().copied().chain(std::iter::once((f64::MAX, f64::MAX))) {
                    let piece = clip(&clip(&poly, &|q| u(q) - from), &|q| u0 - u(q));
                    if piece.len() >= 3 {
                        pieces.push(piece);
                    }
                    from = from.max(u1);
                }
            }
        }
        for piece in pieces {
            let mut mesh = egui::Mesh::default();
            for q in &piece {
                mesh.colored_vertex(xf.s(*q + offset), SELECT_FILL);
            }
            for t in rc_core::geom::triangulate(&piece) {
                mesh.add_triangle(t[0] as u32, t[1] as u32, t[2] as u32);
            }
            painter.add(egui::Shape::mesh(mesh));
        }
    }
}

fn paint_highlight(painter: &egui::Painter, d: &Drawing, ids: &HashSet<Id>, xf: &Xf, color: Color32, offset: DVec2) {
    for (id, prim) in &d.prims {
        let Some(id) = id else { continue };
        if !ids.contains(id) {
            continue;
        }
        match prim {
            Prim::Image { min, max, .. } => {
                painter.rect_stroke(egui::Rect::from_two_pos(xf.s(*min + offset), xf.s(*max + offset)), 0.0, Stroke::new(2.0, color), egui::StrokeKind::Middle);
            }
            Prim::Line { pts, closed, stroke } => {
                let v: Vec<Pos2> = pts.iter().map(|q| xf.s(*q + offset)).collect();
                // Outlines get heavier; thin pattern lines stay thin so the fill reads as one tone.
                let w = if xf.px(stroke.width) < 1.0 { 1.0 } else { (xf.px(stroke.width) + 1.2).max(2.0) };
                paint_polyline(painter, &v, *closed, Stroke::new(w, color), Dash::Solid, xf);
            }
            Prim::Fill { tris, .. } => {
                let mut mesh = egui::Mesh::default();
                // The selection blue over white comes out as the reference app's (125, 146, 202).
                let c = if color == style::SELECT { SELECT_FILL } else { Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), 60) };
                for t in tris {
                    let i = mesh.vertices.len() as u32;
                    for q in t {
                        mesh.colored_vertex(xf.s(*q + offset), c);
                    }
                    mesh.add_triangle(i, i + 1, i + 2);
                }
                painter.add(egui::Shape::mesh(mesh));
            }
            Prim::Text { pos, text, size, anchor, angle, bold, .. } => {
                paint_text_ex(painter, xf.s(*pos + offset), text, xf.text_px(*size), color, *anchor, *angle, *bold);
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
    wheel_2d(app, ui, resp, rect, view, scale, &mut cam);
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
    if resp.dragged_by(egui::PointerButton::Middle) {
        let d = resp.drag_delta();
        cam.center += DVec2::new(-d.x as f64, d.y as f64) / cam.zoom;
        // The pan cursor while the middle button drags.
        resp.ctx.set_cursor_icon(egui::CursorIcon::Move);
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
            Prim::Image { min, max, .. } => {
                if pt.x >= min.x && pt.x <= max.x && pt.y >= min.y && pt.y <= max.y { tol * 0.8 } else { f64::MAX }
            }
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
    if let Some(shapes) = app.cache.picks.get(&view.id) {
        for s in shapes.iter() {
            if pt.x < s.min.x - tol || pt.y < s.min.y - tol || pt.x > s.max.x + tol || pt.y > s.max.y + tol {
                continue;
            }
            if s.hit(pt, tol) {
                push(tol * 0.6 + s.prio as f64 * tol * 0.04, s.id, &mut scored);
            }
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

/// A plan element's pick outlines (computed once per model change).
pub struct PickShape {
    pub id: Id,
    pub prio: i32,
    pub outlines: Vec<Vec<DVec2>>,
    /// Closed outlines that pick from inside (walls, rooms, components...).
    pub fill: bool,
    pub open: bool,
    pub min: DVec2,
    pub max: DVec2,
}

impl PickShape {
    pub fn hit(&self, pt: DVec2, tol: f64) -> bool {
        self.outlines.iter().any(|o| {
            let n = o.len();
            let edge = (0..n.saturating_sub(1)).any(|k| geom::distance_to_segment(o[k], o[k + 1], pt) <= tol)
                || (!self.open && n > 2 && geom::distance_to_segment(o[n - 1], o[0], pt) <= tol);
            edge || (self.fill && n > 2 && geom::contains(o, pt))
        })
    }
}

/// Builds the plan pick outlines of a view (no-op when cached).
pub fn ensure_picks(app: &mut App, view_id: Id) {
    if app.cache.picks.contains_key(&view_id) {
        return;
    }
    let fp = app.footprints();
    let p = &app.doc.data;
    let mut out = Vec::new();
    if let Some(view) = p.view(view_id).filter(|v| is_plan(v)) {
        let index = app.cache.index.clone();
        let get = |id: Id| index.get(&id).and_then(|i| p.elements.get(*i));
        let priority = |c: Category| match c {
            Category::Dimensions | Category::Tags | Category::TextNotes | Category::Symbols => 0,
            Category::Doors | Category::Windows => 1,
            Category::Furniture | Category::Casework | Category::PlumbingFixtures | Category::SpecialtyEquipment | Category::GenericModels => 2,
            Category::Columns | Category::StructuralColumns | Category::StructuralFraming | Category::StructuralFoundations => 2,
            Category::Grids | Category::ReferencePlanes | Category::Lines | Category::RoomSeparation | Category::AreaBoundary | Category::Railings | Category::Stairs => 3,
            Category::Walls | Category::Groups => 4,
            Category::Rooms | Category::Areas => 5,
            Category::FilledRegions | Category::ImportedCad | Category::Roofs | Category::Ceilings | Category::ShaftOpenings => 6,
            Category::Floors => 7,
            _ => 8,
        };
        for e in &p.elements {
            if matches!(e.kind, ElementKind::GroupInstance(_)) {
                continue;
            }
            let target = e.group.and_then(get).unwrap_or(e);
            let shown = if target.id != e.id { plan::in_plan(p, view, target) && rc_core::analysis::visible_in(p, view, e) } else { plan::in_plan(p, view, e) };
            if !shown {
                continue;
            }
            let c = e.category();
            let outlines: Vec<Vec<DVec2>> = plan::element_outline(p, e, &fp).into_iter().filter(|o| !o.is_empty()).collect();
            if outlines.is_empty() {
                continue;
            }
            let open = matches!(
                e.kind,
                ElementKind::Line(_) | ElementKind::Grid(_) | ElementKind::RefPlane(_) | ElementKind::Railing(_) | ElementKind::RoomSeparation(_) | ElementKind::AreaBoundary(_) | ElementKind::Dimension(_) | ElementKind::WallFoundation(_)
            );
            let fill = !open && !matches!(c, Category::Floors | Category::Roofs | Category::Ceilings | Category::FilledRegions | Category::ImportedCad);
            let (min, max) = geom::bounds(outlines.iter().flatten().copied());
            out.push(PickShape { id: target.id, prio: if target.id != e.id { priority(Category::Groups) } else { priority(c) }, outlines, fill, open, min, max });
        }
    }
    app.cache.picks.insert(view_id, Rc::new(out));
}

/// Cached outlines of one element in a plan view (room/area boundaries for highlighting).
fn cached_outlines(app: &App, view: Id, id: Id) -> Vec<Vec<DVec2>> {
    app.cache.picks.get(&view).and_then(|v| v.iter().find(|s| s.id == id).map(|s| s.outlines.clone())).unwrap_or_default()
}

/// Maps a picked id to what gets selected (group members select their group), or None when
/// it may not be selected now.
pub fn selectable_id(app: &App, view: &View, id: Id) -> Option<Id> {
    if !app.show_mass && app.el(id).is_some_and(|e| matches!(e.kind, ElementKind::Mass(_))) {
        return None;
    }
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
                    ElementKind::Wall(w) if w.base_level == level => {
                        match w.arc() {
                            Some(a) => g.arcs.push((a, Some(e.id))),
                            None => g.segs.push((w.start, w.end, Some(e.id))),
                        }
                        g.ends.push((w.start, Some(e.id)));
                        g.ends.push((w.end, Some(e.id)));
                    }
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

/// A sketch slope arrow: a line from tail to head with an open arrowhead.
pub fn paint_slope_arrow(painter: &egui::Painter, xf: &Xf, a: DVec2, b: DVec2, color: Color32) {
    let (pa, pb) = (xf.s(a), xf.s(b));
    if pa.distance(pb) < 2.0 {
        return;
    }
    painter.line_segment([pa, pb], Stroke::new(2.0, color));
    let d = (pb - pa).normalized();
    let n = vec2(-d.y, d.x);
    painter.line_segment([pb, pb - d * 12.0 + n * 6.0], Stroke::new(2.0, color));
    painter.line_segment([pb, pb - d * 12.0 - n * 6.0], Stroke::new(2.0, color));
}

/// The work plane grid of a plan (its level): light-blue lines at the grid spacing over the
/// model extents.
fn paint_work_plane_grid(app: &App, painter: &egui::Painter, xf: &Xf, d: &Drawing) {
    let spacing = if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { 3048.0 } else { 3000.0 };
    let Some((mn, mx)) = d.bounds() else { return };
    let (x0, y0) = ((mn.x / spacing).floor() * spacing - spacing, (mn.y / spacing).floor() * spacing - spacing);
    let (x1, y1) = ((mx.x / spacing).ceil() * spacing + spacing, (mx.y / spacing).ceil() * spacing + spacing);
    // As the reference app: a translucent plane with dashed grid lines and a solid border.
    painter.rect_filled(Rect::from_two_pos(xf.s(DVec2::new(x0, y0)), xf.s(DVec2::new(x1, y1))), 0.0, Color32::from_rgba_unmultiplied(110, 170, 235, 38));
    let st = Stroke::new(1.0, Color32::from_rgba_unmultiplied(80, 150, 230, 170));
    let mut x = x0;
    while x <= x1 + 1.0 {
        painter.extend(egui::Shape::dashed_line(&[xf.s(DVec2::new(x, y0)), xf.s(DVec2::new(x, y1))], st, 6.0, 4.0));
        x += spacing;
    }
    let mut y = y0;
    while y <= y1 + 1.0 {
        painter.extend(egui::Shape::dashed_line(&[xf.s(DVec2::new(x0, y)), xf.s(DVec2::new(x1, y))], st, 6.0, 4.0));
        y += spacing;
    }
    painter.rect_stroke(Rect::from_two_pos(xf.s(DVec2::new(x0, y0)), xf.s(DVec2::new(x1, y1))), 0.0, Stroke::new(1.5, Color32::from_rgb(60, 130, 220)), egui::StrokeKind::Middle);
}

/// The canvas cursor as the reference app shows it: a crosshair while drawing, placing or
/// dragging an end; the arrow with a move glyph in Move and Copy; the system's own otherwise
/// (and "not allowed" where a hosted element cannot go, set by the tool).
fn paint_cursor(app: &App, ui: &egui::Ui, resp: &egui::Response, painter: &egui::Painter) {
    let Some(c) = resp.hover_pos() else { return };
    let kind = app.tool.kind;
    let modify = matches!(
        kind,
        ToolKind::Move | ToolKind::Copy | ToolKind::Rotate | ToolKind::Align | ToolKind::Offset | ToolKind::MirrorPick | ToolKind::MirrorDraw | ToolKind::Array | ToolKind::Scale | ToolKind::TrimCorner | ToolKind::TrimSingle | ToolKind::TrimMulti | ToolKind::Split | ToolKind::SplitGap
    );
    let end_drag = matches!(app.interact.drag, Some(Drag::Grip { .. }) | Some(Drag::SketchVertex { .. }));
    let not_allowed = ui.ctx().output(|o| o.cursor_icon) == egui::CursorIcon::NotAllowed;
    if matches!(kind, ToolKind::Move | ToolKind::Copy) {
        paint_move_glyph(painter, c + vec2(13.0, 15.0));
    } else if app.tool.is_select() && app.interact.drag.is_none() && app.interact.hover_grip.is_none() && app.interact.hover.is_some_and(|h| app.selection.contains(&h)) {
        // Over a selected element the pointer becomes the four-way move arrow.
        ui.ctx().set_cursor_icon(egui::CursorIcon::Move);
    } else if (!app.tool.is_select() && !modify && !not_allowed) || end_drag {
        ui.ctx().set_cursor_icon(egui::CursorIcon::None);
        paint_crosshair(painter, c);
    }
}

/// The reference app's drawing cursor: four short grey arms around a small gap and a centre dot.
pub fn paint_crosshair(painter: &egui::Painter, c: Pos2) {
    let (gap, arm) = (2.5, 7.0);
    let halo = Stroke::new(3.4, Color32::from_rgba_unmultiplied(255, 255, 255, 170));
    let ink = Stroke::new(1.6, Color32::from_rgb(78, 78, 78));
    for st in [halo, ink] {
        for d in [vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0)] {
            painter.line_segment([c + d * gap, c + d * (gap + arm)], st);
        }
    }
    painter.circle_filled(c, 0.8, Color32::from_rgb(78, 78, 78));
}

/// The small four-way arrow beside the pointer in Move and Copy.
fn paint_move_glyph(painter: &egui::Painter, c: Pos2) {
    let r = 6.0;
    for (st, fill) in [(Stroke::new(3.0, Color32::WHITE), Color32::WHITE), (Stroke::new(1.2, Color32::BLACK), Color32::BLACK)] {
        painter.line_segment([c - vec2(r, 0.0), c + vec2(r, 0.0)], st);
        painter.line_segment([c - vec2(0.0, r), c + vec2(0.0, r)], st);
        for d in [vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0)] {
            let n = vec2(-d.y, d.x);
            let tip = c + d * (r + 2.0);
            painter.add(egui::Shape::convex_polygon(vec![tip, tip - d * 3.5 + n * 2.6, tip - d * 3.5 - n * 2.6], fill, Stroke::new(st.width - 1.0, st.color)));
        }
    }
}

/// A light-blue dashed reference line (the location line of a snapped element).
pub fn reference_line(painter: &egui::Painter, a: Pos2, b: Pos2) {
    painter.extend(egui::Shape::dashed_line(&[a, b], Stroke::new(1.0, style::TRACK), 5.0, 4.0));
}

/// A light-blue dash-dot tracking line.
pub fn track_line(painter: &egui::Painter, a: Pos2, b: Pos2) {
    painter.extend(egui::Shape::dashed_line_with_offset(&[a, b], Stroke::new(1.0, style::TRACK), &[12.0, 2.0], &[3.0, 3.0], 0.0));
}

/// Is the angle-snap guide horizontal or vertical? Returns the label for the snap tooltip.
pub fn axis_label(s: &SnapResult) -> Option<&'static str> {
    if s.kind != SnapKind::Angle {
        return None;
    }
    let (a, b) = s.guides.first()?;
    let d = (*b - *a).normalize_or_zero();
    if d.y.abs() < 1e-6 && d.x.abs() > 0.5 {
        Some("Horizontal")
    } else if d.x.abs() < 1e-6 && d.y.abs() > 0.5 {
        Some("Vertical")
    } else {
        None
    }
}

fn paint_snap(painter: &egui::Painter, xf: &Xf, s: &SnapResult) {
    let c = style::SNAP;
    let st = Stroke::new(1.6, c);
    let axis = axis_label(s);
    for (a, b) in &s.guides {
        let (pa, pb) = (xf.s(*a), xf.s(*b));
        if axis.is_some() {
            // Axis tracking runs across the whole view, like the reference app.
            let d = (pb - pa).normalized();
            let span = xf.rect.width().max(xf.rect.height()) * 2.0;
            track_line(painter, pa - d * span, pa + d * span);
        } else {
            track_line(painter, pa, pb);
        }
    }
    let p = xf.s(s.point);
    let r = 5.0;
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
        SnapKind::Angle if axis.is_some() => {
            // A hollow double arrow along the axis: two shaft lines and open heads.
            let d = if axis == Some("Horizontal") { vec2(1.0, 0.0) } else { vec2(0.0, 1.0) };
            let n = vec2(-d.y, d.x);
            let st = Stroke::new(1.3, c);
            let (len, head, w) = (9.0, 4.0, 4.5);
            for side in [1.0f32, -1.0] {
                painter.line_segment([p - d * (len - head) + n * 1.4 * side, p + d * (len - head) + n * 1.4 * side], st);
            }
            for sgn in [1.0f32, -1.0] {
                let tip = p + d * len * sgn;
                let base = tip - d * head * sgn;
                painter.add(egui::Shape::closed_line(vec![tip, base + n * w, base + n * 1.4, base - n * 1.4, base - n * w], st));
            }
        }
        SnapKind::Alignment | SnapKind::Extension => {
            painter.line_segment([p + vec2(-4.0, -4.0), p + vec2(4.0, 4.0)], st);
            painter.line_segment([p + vec2(4.0, -4.0), p + vec2(-4.0, 4.0)], st);
        }
        SnapKind::Angle | SnapKind::Free => {}
    }
    let label = match s.kind {
        SnapKind::Free => None,
        SnapKind::Angle => axis,
        // The drawing direction crossing another point's alignment, worded as the reference app.
        SnapKind::Extension if s.guides.len() == 2 => {
            let d = (s.guides[1].1 - s.guides[1].0).normalize_or_zero();
            Some(if d.y.abs() < 1e-6 { "Horizontal and Extension" } else if d.x.abs() < 1e-6 { "Vertical and Extension" } else { "Extension" })
        }
        k => Some(k.label()),
    };
    if let Some(label) = label {
        style::canvas_tooltip(painter, p + vec2(8.0, 12.0), label);
    }
}

/// A room's boundary with the two diagonal reference lines across its extents.
pub fn paint_room_reference(painter: &egui::Painter, xf: &Xf, poly: &[DVec2], color: Color32) {
    if poly.len() < 3 {
        return;
    }
    let st = Stroke::new(1.5, color);
    painter.add(egui::Shape::closed_line(poly.iter().map(|q| xf.s(*q)).collect(), st));
    let (mn, mx) = rc_core::geom::bounds(poly.iter().copied());
    let thin = Stroke::new(1.0, color);
    painter.line_segment([xf.s(mn), xf.s(mx)], thin);
    painter.line_segment([xf.s(DVec2::new(mn.x, mx.y)), xf.s(DVec2::new(mx.x, mn.y))], thin);
}

/// The small dimension glyph that turns a temporary dimension into a permanent one.
fn paint_make_permanent(painter: &egui::Painter, r: Rect, hot: bool) {
    if hot {
        painter.rect_filled(r.expand(1.0), 0.0, style::hover());
        painter.rect_stroke(r.expand(1.0), 0.0, Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    }
    let c = style::TEMP_DIM;
    let st = Stroke::new(1.2, c);
    let (l, rr, y) = (r.left() + 2.0, r.right() - 2.0, r.center().y);
    painter.line_segment([pos2(l, r.top() + 2.0), pos2(l, r.bottom() - 2.0)], st);
    painter.line_segment([pos2(rr, r.top() + 2.0), pos2(rr, r.bottom() - 2.0)], st);
    painter.line_segment([pos2(l, y), pos2(rr, y)], st);
}

/// Draws a temporary (listening) dimension between two points with its value.
pub fn temp_dim(painter: &egui::Painter, xf: &Xf, a: DVec2, b: DVec2, text: &str, offset_px: f32) -> Rect {
    temp_dim_ex(painter, xf, a, b, text, offset_px, false)
}

/// Temporary dimension: thin light-blue witness and dimension lines, blue text along the line
/// (bold for the listening dimension of the element being drawn).
pub fn temp_dim_ex(painter: &egui::Painter, xf: &Xf, a: DVec2, b: DVec2, text: &str, offset_px: f32, bold: bool) -> Rect {
    let (sa, sb) = (xf.s(a), xf.s(b));
    if sa.distance(sb) < 1.0 {
        return Rect::NOTHING;
    }
    let d = (sb - sa).normalized();
    let n = vec2(-d.y, d.x);
    let off = n * offset_px;
    let (la, lb) = (sa + off, sb + off);
    let st = Stroke::new(1.0, style::TEMP_DIM_LINE);
    let gap = if offset_px.abs() > 4.0 { n * offset_px.signum() * 3.0 } else { vec2(0.0, 0.0) };
    let ext = n * offset_px.signum() * 3.0;
    painter.line_segment([sa + gap, la + ext], st);
    painter.line_segment([sb + gap, lb + ext], st);
    painter.line_segment([la, lb], st);
    for q in [la, lb] {
        painter.line_segment([q - (d + n) * 3.0, q + (d + n) * 3.0], st);
    }
    // Text reads along the dimension, from the bottom or the right.
    let mut ang = d.y.atan2(d.x);
    if ang > std::f32::consts::FRAC_PI_2 + 0.01 {
        ang -= std::f32::consts::PI;
    } else if ang < -std::f32::consts::FRAC_PI_2 + 0.01 {
        ang += std::f32::consts::PI;
    }
    let font = if bold { style::bold(12.0) } else { style::font(12.0) };
    let galley = painter.layout_no_wrap(text.to_string(), font, style::TEMP_DIM);
    let size = galley.size();
    let along = vec2(ang.cos(), ang.sin());
    let down = vec2(-along.y, along.x);
    let outward = if offset_px.abs() > 0.1 { n * offset_px.signum() } else { -down };
    let mid = la + (lb - la) / 2.0 + outward * (size.y / 2.0 + 1.0);
    let origin = mid - along * (size.x / 2.0) - down * (size.y / 2.0);
    let corners = [origin, origin + along * size.x, origin + along * size.x + down * size.y, origin + down * size.y];
    let mut bb = Rect::NOTHING;
    for c in corners {
        bb.extend_with(c);
    }
    painter.add(egui::Shape::convex_polygon(
        vec![corners[0] - along * 2.0 - down * 1.0, corners[1] + along * 2.0 - down * 1.0, corners[2] + along * 2.0 + down * 1.0, corners[3] - along * 2.0 + down * 1.0],
        Color32::from_rgba_unmultiplied(255, 255, 255, 200),
        Stroke::NONE,
    ));
    painter.add(egui::epaint::TextShape::new(origin, galley, style::TEMP_DIM).with_angle(ang));
    bb.expand(2.0)
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
    track_history(app, ui.ctx(), view_id);
    let cam = app.cams[&view_id];
    let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: view.scale, thin: app.thin_lines };
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 0.0, canvas_bg(app));
    let drawing = app.drawing(view_id);
    ensure_picks(app, view_id);

    // ---- model graphics
    let temp = app.temp_hide.get(&view_id).cloned();
    let group = app.group_edit.as_ref().map(|g| g.0);
    let index = app.cache.index.clone();
    let black = app.settings.black_canvas;
    {
        let p = &app.doc.data;
        let show_mass = app.show_mass;
        // While sketching, everything else in the view is halftone, as in the reference app.
        let sketching = app.sketch.as_ref().is_some_and(|s| s.view == view_id);
        let color_of = |id: Option<Id>, rgb: [u8; 3]| -> Option<Color32> {
            if sketching {
                let h = |c: u8| ((c as u16 + 255) / 2) as u8;
                if id.and_then(|i| index.get(&i)).and_then(|i| p.elements.get(*i)).is_some_and(|e| temp.as_ref().is_some_and(|t| t.hides(e.id, e.category()))) {
                    return None;
                }
                return Some(Color32::from_rgb(h(rgb[0]), h(rgb[1]), h(rgb[2])));
            }
            if let Some(e) = id.and_then(|i| index.get(&i)).and_then(|i| p.elements.get(*i)) {
                if temp.as_ref().is_some_and(|t| t.hides(e.id, e.category())) {
                    return None;
                }
                if !show_mass && matches!(e.kind, ElementKind::Mass(_)) {
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
            let sel = app.selection.contains(&view_id);
            let stroke = Stroke::new(if sel { 2.0 } else { 1.0 }, if sel { style::SELECT } else { ink(app, [40, 40, 40]) });
            if view.crop_shape.len() >= 3 {
                painter.add(egui::Shape::closed_line(view.crop_shape.iter().map(|q| xf.s(*q)).collect(), stroke));
            } else {
                painter.rect_stroke(Rect::from_two_pos(xf.s(a), xf.s(b)), 0.0, stroke, egui::StrokeKind::Middle);
            }
        }
    }

    // ---- selection and preselection highlights
    let sel: HashSet<Id> = app.selection.iter().copied().collect();
    let mut sel_draw = sel.clone();
    // Group instances highlight through their members.
    for e in app.doc.data.elements.iter().filter(|e| e.group.is_some_and(|g| sel.contains(&g))) {
        sel_draw.insert(e.id);
    }
    let hosted = crate::tempdims::hosted_drag(app);
    let move_offset = match (&app.interact.drag, app.interact.point) {
        // Doors and windows slide along their host.
        (Some(Drag::Move { .. }), Some(_)) if is_active && hosted.is_some() => hosted.map(|h| h.2).unwrap_or_default(),
        (Some(Drag::Move { start, .. }), Some(pt)) if is_active => pt - *start,
        _ => DVec2::ZERO,
    };
    if move_offset != DVec2::ZERO {
        paint_highlight(&painter, &drawing, &sel_draw, &xf, Color32::from_rgba_unmultiplied(20, 110, 255, 120), DVec2::ZERO);
    }
    paint_selected_wall_fills(app, &painter, &xf, &view, &sel_draw, move_offset);
    paint_highlight(&painter, &drawing, &sel_draw, &xf, style::SELECT, move_offset);
    if is_plan(&view) {
        // Rooms and areas highlight their boundary.
        let _fp = app.footprints();
        for id in &app.selection {
            if let Some(e) = app.el(*id) {
                if matches!(e.kind, ElementKind::Room(_) | ElementKind::Area(_)) {
                    for o in cached_outlines(app, view_id, *id) {
                        let moved: Vec<DVec2> = o.iter().map(|q| *q + move_offset).collect();
                        paint_room_reference(&painter, &xf, &moved, style::SELECT);
                    }
                }
                // Selected floors and ceilings show a translucent blue fill.
                let boundary = match &e.kind {
                    ElementKind::Floor(f) => Some(f.boundary.clone()),
                    ElementKind::Ceiling(c) => Some(c.boundary.clone()),
                    _ => None,
                };
                if let Some(b) = boundary {
                    let mut mesh = egui::Mesh::default();
                    let fill = Color32::from_rgba_unmultiplied(70, 120, 220, 70);
                    for [i, j, k] in rc_core::geom::triangulate(&b) {
                        let n = mesh.vertices.len() as u32;
                        for q in [b[i], b[j], b[k]] {
                            mesh.colored_vertex(xf.s(q + move_offset), fill);
                        }
                        mesh.add_triangle(n, n + 1, n + 2);
                    }
                    painter.add(egui::Shape::mesh(mesh));
                }
            }
        }
    }
    if !app.boundary_highlight.is_empty() {
        paint_highlight(&painter, &drawing, &app.boundary_highlight, &xf, Color32::from_rgb(255, 150, 40), DVec2::ZERO);
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
                        for o in cached_outlines(app, view_id, h) {
                            paint_room_reference(&painter, &xf, &o, style::PRESELECT);
                        }
                    }
                }
            }
        }
    }

    // ---- sketch overlay (magenta boundary lines)
    if let Some(sk) = app.sketch.as_ref().filter(|s| s.view == view_id) {
        // Stair runs show as the stair they make: run outlines, risers and landings.
        if let Some(st) = crate::canvas_tools::sketch_stair(app).filter(|s| !s.runs.is_empty()) {
            let lay = rc_core::build3d::stair_layout(&app.doc.data, &st);
            let ink = Stroke::new(1.5, style::SKETCH);
            for (run, risers, first, _) in &lay.runs {
                let len = run.start.distance(run.end);
                let d = (run.end - run.start).normalize_or_zero();
                let n = rc_core::geom::perp(d) * (run.width / 2.0);
                painter.add(egui::Shape::closed_line(vec![xf.s(run.start - n), xf.s(run.end - n), xf.s(run.end + n), xf.s(run.start + n)], ink));
                let going = rc_core::build3d::run_going(len, *risers);
                for j in 0..*risers {
                    let q = run.start + d * (j as f64 * going);
                    painter.line_segment([xf.s(q - n), xf.s(q + n)], Stroke::new(1.0, style::SKETCH));
                }
                // Riser numbers at the run ends and the blue path with its arrow, as in the
                // reference app's stair edit mode.
                let font = egui::FontId::new(10.0, egui::FontFamily::Name("bold".into()));
                let out = rc_core::geom::perp(d).normalize_or_zero() * xf.len(4.0);
                painter.text(xf.s(run.start + n + out), egui::Align2::RIGHT_BOTTOM, (first + 1).to_string(), font.clone(), Color32::BLACK);
                painter.text(xf.s(run.end + n + out), egui::Align2::RIGHT_BOTTOM, (first + risers).to_string(), font, Color32::BLACK);
                let blue = Stroke::new(1.0, Color32::from_rgb(60, 60, 220));
                let (pa, pb) = (xf.s(run.start), xf.s(run.end));
                painter.line_segment([pa, pb], blue);
                let u = (pb - pa).normalized();
                let side = vec2(-u.y, u.x);
                painter.line_segment([pb, pb - u * 8.0 + side * 4.0], blue);
                painter.line_segment([pb, pb - u * 8.0 - side * 4.0], blue);
            }
            for (poly, _) in &lay.landings {
                painter.add(egui::Shape::closed_line(poly.iter().map(|q| xf.s(*q)).collect(), ink));
            }
        }
        // Ramp runs show as the ramp they make: run outlines and landings.
        if let Some(rm) = crate::canvas_tools::sketch_ramp(app).filter(|r| !r.runs.is_empty()) {
            let lay = rc_core::build3d::ramp_layout(&app.doc.data, &rm);
            let ink = Stroke::new(1.5, style::SKETCH);
            for (run, ..) in &lay.runs {
                let n = rc_core::geom::perp((run.end - run.start).normalize_or_zero()) * (run.width / 2.0);
                painter.add(egui::Shape::closed_line(vec![xf.s(run.start - n), xf.s(run.end - n), xf.s(run.end + n), xf.s(run.start + n)], ink));
            }
            for (poly, _) in &lay.landings {
                painter.add(egui::Shape::closed_line(poly.iter().map(|q| xf.s(*q)).collect(), ink));
            }
        }
        let stair = matches!(sk.kind, crate::tools::SketchKind::Stair | crate::tools::SketchKind::Ramp);
        for (k, s) in sk.segs.iter().enumerate() {
            if stair {
                // The run path is drawn above; picked or hovered runs highlight.
                let color = if sk.selected.contains(&k) { Some(style::SELECT) } else if is_active && app.interact.hover_seg == Some(k) { Some(style::PRESELECT) } else { None };
                if let Some(color) = color {
                    painter.line_segment([xf.s(s.start()), xf.s(s.end())], Stroke::new(2.0, color));
                }
                continue;
            }
            let pts: Vec<Pos2> = s.points().iter().map(|q| xf.s(*q)).collect();
            let selected = sk.selected.contains(&k);
            let hovered = is_active && app.interact.hover_seg == Some(k);
            let color = if selected { style::SELECT } else if hovered { style::PRESELECT } else { style::SKETCH };
            paint_polyline(&painter, &pts, false, Stroke::new(2.0, color), Dash::Solid, &xf);
            // The span direction symbol sits on the span edge of floor sketches.
            let floor = matches!(sk.kind, crate::tools::SketchKind::Floor { .. } | crate::tools::SketchKind::EditFloor(_));
            if floor && sk.span_edge.unwrap_or(0) == k && matches!(s, crate::tools::Seg::Line(..)) {
                let (a, b) = (xf.s(s.start()), xf.s(s.end()));
                let d = (b - a).normalized();
                let n = vec2(-d.y, d.x);
                let m = a + (b - a) * 0.5 + n * 9.0;
                for off in [-3.0f32, 3.0] {
                    painter.line_segment([m + n * off - d * 12.0, m + n * off + d * 12.0], Stroke::new(1.5, style::SKETCH));
                }
                for sgn in [-1.0f32, 1.0] {
                    let tip = m + d * (16.0 * sgn);
                    painter.add(egui::Shape::convex_polygon(vec![tip, tip - d * (6.0 * sgn) + n * 4.0, tip - d * (6.0 * sgn) - n * 4.0], style::SKETCH, Stroke::NONE));
                }
            }
            if sk.kind.is_roof() && sk.slopes.get(k).copied().unwrap_or(true) {
                // Slope-defining edge: a small triangle marker.
                let mid = xf.s((s.start() + s.end()) / 2.0);
                let d = (xf.s(s.end()) - xf.s(s.start())).normalized();
                let n = vec2(-d.y, d.x);
                painter.add(egui::Shape::convex_polygon(vec![mid + n * 4.0 - d * 6.0, mid + n * 4.0 + d * 6.0, mid + n * 12.0], style::SKETCH, Stroke::NONE));
            }
        }
    }

    if let Some((a, b)) = app.sketch.as_ref().filter(|s| s.view == view_id).and_then(|s| s.slope_arrow) {
        paint_slope_arrow(&painter, &xf, a, b, style::SKETCH);
    }
    // The work plane grid (Show).
    if app.show_work_plane.contains(&view_id) && is_plan(&view) {
        paint_work_plane_grid(app, &painter, &xf, &drawing);
    }

    // Measure result.
    if let Some((a, b)) = app.interact.measure.filter(|_| is_active) {
        let txt = app.doc.data.units.length(a.distance(b));
        temp_dim(&painter, &xf, a, b, &txt, 14.0);
    }

    if app.settings.show_navbar {
        nav_bar_2d(app, ui, rect, view_id);
    }
    if !is_active {
        return;
    }
    app.interact.view = Some(view_id);
    app.interact.xf = Some(xf);
    if wheel_on(ui, view_id) {
        let st = crate::wheel::load(ui, view_id);
        if let (Some(c), Some(p)) = (st.center, ui.input(|i| i.pointer.latest_pos())) {
            let hot = st.drag.or_else(|| crate::wheel::wedge_at(false, c, p));
            crate::wheel::paint(&painter, c, false, hot, st.drag);
            app.interact.prompt = crate::wheel::prompt(hot).into();
        }
        if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            crate::wheel::store(ui, view_id, Default::default());
        }
        ui.ctx().request_repaint();
        return;
    }

    // ---- cursor and snapping
    let cursor = resp.hover_pos().map(|s| xf.w(s));
    app.interact.cursor = cursor;
    let shift = ui.input(|i| i.modifiers.shift);
    let ctrl = ui.input(|i| i.modifiers.command || i.modifiers.ctrl);
    let tool_kind = app.tool.kind;
    // Hosted and click-inside tools work from the raw cursor and show no snaps.
    let cursor_tool = matches!(tool_kind, ToolKind::Door | ToolKind::Window | ToolKind::Room | ToolKind::Area | ToolKind::CeilingAuto | ToolKind::RoomTag | ToolKind::AreaTag | ToolKind::Tag | ToolKind::TopoPoints)
        || (tool_kind.uses_draw_modes() && app.opts.draw_mode.is_pick() && canvas_tools::draw_modes(app).contains(&app.opts.draw_mode));
    let wants_snap = (!app.tool.is_select() && !cursor_tool) || matches!(app.interact.drag, Some(Drag::Move { .. }) | Some(Drag::Grip { .. }) | Some(Drag::SketchVertex { .. }));
    let reference = canvas_tools::reference_point(app);
    let mut snapped: Option<SnapResult> = None;
    if let (Some(c), true) = (cursor, wants_snap) {
        let refp = match &app.interact.drag {
            Some(Drag::Grip { id, grip: grips::GripKind::WallEnd(at_start), .. }) => app.doc.data.wall(*id).map(|w| if *at_start { w.end } else { w.start }),
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
    if let Some(s) = app.interact.snap.clone() {
        // A door or window sliding along its wall shows no snap, only its dimensions.
        if wants_snap && crate::tempdims::hosted_drag(app).is_none() {
            // As in the reference app, the element being snapped to shows its location line
            // as a light-blue dashed reference.
            if !matches!(s.kind, SnapKind::Free | SnapKind::Angle) {
                if let Some(w) = s.target.and_then(|id| app.doc.data.wall(id)) {
                    let pts: Vec<Pos2> = rc_core::analysis::wall_path(w).iter().map(|q| xf.s(*q)).collect();
                    for seg in pts.windows(2) {
                        reference_line(&painter, seg[0], seg[1]);
                    }
                }
            }
            paint_snap(&painter, &xf, &s);
        }
    }
    // The tool's prompt follows the cursor when it rests and nothing is snapped.
    let no_tip = ui.ctx().data_mut(|m| m.remove_temp::<bool>(egui::Id::new("no-prompt-tip"))).unwrap_or(false);
    if !no_tip && !app.tool.is_select() && app.interact.snap.as_ref().is_none_or(|s| s.kind == SnapKind::Free) && app.typed.is_empty() {
        if let Some(c) = resp.hover_pos() {
            let still = ui.input(|i| i.pointer.time_since_last_movement());
            if still > 0.35 && !app.interact.prompt.is_empty() {
                style::canvas_tooltip(&painter, c + vec2(12.0, 16.0), &app.interact.prompt);
            } else if still <= 0.35 {
                ui.ctx().request_repaint_after(std::time::Duration::from_millis(400));
            }
        }
    }
    // Typed value box.
    if !app.typed.is_empty() {
        if let Some(c) = resp.hover_pos() {
            let r = Rect::from_min_size(c + vec2(16.0, -34.0), vec2(96.0, 19.0));
            painter.rect_filled(r, 0.0, Color32::WHITE);
            painter.rect_stroke(r, 0.0, Stroke::new(1.0, Color32::from_gray(170)), egui::StrokeKind::Inside);
            painter.line_segment([r.left_bottom(), r.right_bottom()], Stroke::new(1.5, style::TEMP_DIM));
            let t = painter.text(r.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, &app.typed, style::bold(12.0), Color32::BLACK);
            painter.line_segment([pos2(t.right() + 1.0, r.top() + 3.0), pos2(t.right() + 1.0, r.bottom() - 3.0)], Stroke::new(1.0, Color32::BLACK));
            style::canvas_tooltip(&painter, r.left_bottom() + vec2(0.0, 6.0), "Please enter a length");
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
    paint_cursor(app, ui, &resp, &painter);

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
    let temp_dims = crate::tempdims::compute(app, view, xf);
    let mut tdim_hit: Option<usize> = None;
    let mut perm_hit: Option<usize> = None;
    for (k, td) in temp_dims.iter().enumerate() {
        if let Some((c, size, angle)) = td.perm {
            // A permanent dimension's value: editable where it is drawn.
            let (w, h) = (size.x as f32 / xf.len(1.0) as f32, size.y as f32 / xf.len(1.0) as f32);
            let r = Rect::from_center_size(xf.s(c), if angle.abs() > 1.0 { vec2(h, w) } else { vec2(w, h) });
            if cursor.is_some_and(|q| r.contains(xf.s(q))) && app.interact.temp_dim_edit.is_none() {
                tdim_hit = Some(k);
                painter.rect_stroke(r, 2.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Outside);
            }
            continue;
        }
        let txt = app.doc.data.units.length(td.value);
        let r = temp_dim(painter, xf, td.a, td.b, &txt, td.offset_px);
        // "Make this temporary dimension permanent" control beside the value.
        let (sa, sb) = (xf.s(td.a), xf.s(td.b));
        let d = (sb - sa).normalized();
        let n = vec2(-d.y, d.x) * if td.offset_px < 0.0 { -1.0 } else { 1.0 };
        let mid = sa + (sb - sa) / 2.0 + vec2(-d.y, d.x) * td.offset_px;
        let icon = Rect::from_center_size(mid + n * (r.height().min(r.width()) / 2.0 + 14.0) + d * 0.0, vec2(16.0, 12.0));
        let hot = cursor.is_some_and(|c| icon.contains(xf.s(c)));
        paint_make_permanent(painter, icon, hot);
        if let Some(c) = cursor {
            if hot {
                perm_hit = Some(k);
                style::canvas_tooltip(painter, icon.right_bottom() + vec2(4.0, 4.0), "Make this temporary dimension permanent");
            } else if r.contains(xf.s(c)) {
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
        app.interact.hover = if grip_hover.is_some() || tdim_hit.is_some() || perm_hit.is_some() { None } else { cands.get(app.interact.tab_index.min(cands.len().saturating_sub(1))).copied() };
        // Over a selected element that can be dragged the cursor becomes the move cursor.
        if let Some(h) = app.interact.hover {
            if app.selection.contains(&h) && app.el(h).is_some_and(|e| !e.pinned) {
                ui.ctx().set_cursor_icon(egui::CursorIcon::Move);
            }
        }
        if !cands.is_empty() {
            let h = app.interact.hover;
            app.interact.prompt = h.map(|h| describe(app, h)).unwrap_or_default();
            // The element name follows the cursor after a short pause, like a tooltip.
            if let (Some(h), Some(pos)) = (h, resp.hover_pos()) {
                let still = ui.input(|i| i.pointer.time_since_last_movement());
                if still > 0.35 && app.interact.drag.is_none() {
                    style::canvas_tooltip(painter, pos + vec2(12.0, 16.0), &describe(app, h));
                } else {
                    ui.ctx().request_repaint_after(std::time::Duration::from_millis(400));
                }
            }
        } else {
            app.interact.prompt = "Click to select, TAB for alternates, CTRL adds, SHIFT unselects.".into();
            // Over empty canvas the reference app shows the same hint beside a resting cursor.
            if let Some(pos) = resp.hover_pos() {
                let still = ui.input(|i| i.pointer.time_since_last_movement());
                if still > 0.35 && app.interact.drag.is_none() && grip_hover.is_none() && tdim_hit.is_none() && perm_hit.is_none() {
                    style::canvas_tooltip(painter, pos + vec2(12.0, 16.0), &app.interact.prompt);
                } else if still <= 0.35 {
                    ui.ctx().request_repaint_after(std::time::Duration::from_millis(400));
                }
            }
        }
    }

    // Temp dim text click starts editing; the icon makes the dimension permanent.
    if resp.clicked_by(egui::PointerButton::Primary) {
        if let Some(k) = perm_hit {
            let td = temp_dims[k].clone();
            let id = app.selection.first().copied();
            let part = match id.and_then(|i| app.el(i)).map(|e| &e.kind) {
                Some(ElementKind::Wall(_)) => RefPart::WallCenter,
                Some(ElementKind::Grid(_)) => RefPart::GridLine,
                Some(ElementKind::RefPlane(_)) => RefPart::RefPlane,
                Some(ElementKind::Instance(_)) => RefPart::InstanceCenter,
                _ => RefPart::Point,
            };
            let element = if part == RefPart::Point { None } else { id };
            let refs = vec![DimRef { element: None, part: RefPart::Point, point: td.a }, DimRef { element, part, point: td.b }];
            let (sa, sb) = (xf.s(td.a), xf.s(td.b));
            let d = (sb - sa).normalized();
            let line_point = xf.w(sa + (sb - sa) / 2.0 + vec2(-d.y, d.x) * td.offset_px);
            let vid = view.id;
            app.run("Make Dimension Permanent", |p| rc_core::edit::add_dimension(p, vid, refs, td.b - td.a, line_point));
            return;
        }
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
            // The grip under the press, even when the pointer has already moved on.
            let pressed_grip = grip_list.iter().find(|g| xf.s(g.pos).distance(xf.s(start)) <= 7.0).map(|g| (g.kind.clone(), g.id, g.pos));
            if let Some((kind, id, pos)) = pressed_grip.or(grip_hover.clone()) {
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
                // Plain thin rectangle: solid for window, dashed for crossing selection.
                let st = Stroke::new(1.0, Color32::from_gray(40));
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
        Some(Drag::Move { start, ids }) if crate::tempdims::hosted_drag(app).is_some() && !ctrl => {
            painter.ctx().set_cursor_icon(egui::CursorIcon::Move);
            let (id, along, _) = crate::tempdims::hosted_drag(app).unwrap();
            if resp.drag_stopped() {
                app.run("Move", |p| rc_core::edit::set_opening_offset(p, id, along));
                app.interact.drag = None;
            } else if let Some(c) = resp.hover_pos() {
                style::canvas_tooltip(painter, c + vec2(12.0, 16.0), "Drag to new position");
            }
            let _ = (start, ids);
        }
        Some(Drag::Move { start, ids }) => {
            painter.ctx().set_cursor_icon(egui::CursorIcon::Move);
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
            } else {
                // The reference app shows only the ghost and this hint while dragging.
                app.interact.prompt = "Drag to new position".into();
                if let Some(c) = resp.hover_pos() {
                    style::canvas_tooltip(painter, c + vec2(12.0, 16.0), "Drag to new position");
                }
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
            Prim::Image { min, max, .. } => vec![*min, *max],
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
        let p = &app.doc.data;
        let cat = e.category().label();
        if p.type_of(e).is_some() {
            return format!("{cat} : {} : {}", p.family_name_of(e), p.type_name_of(e));
        }
        return format!("{cat} : {}", p.display_name(e));
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
        if ui.button("Cancel").clicked() {
            app.cancel();
            ui.close();
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
        let has_sel = !app.selection.is_empty();
        let walls = app.selection.iter().any(|id| app.el(*id).is_some_and(|e| matches!(e.kind, ElementKind::Wall(_))));
        let mut open_vg: Option<u8> = None;
        if has_sel {
            if walls {
                item(ui, "Change wall's orientation", Cmd::FlipWall, &mut run);
                item(ui, "Select Joined Elements", Cmd::SelectJoined, &mut run);
                ui.separator();
            }
            ui.menu_button("Hide in View", |ui| {
                item(ui, "Elements", Cmd::HideElements, &mut run);
                item(ui, "Category", Cmd::HideCategory, &mut run);
                if ui.button("By Filter...").clicked() {
                    open_vg = Some(3);
                    ui.close();
                }
            });
            ui.menu_button("Override Graphics in View", |ui| {
                item(ui, "By Element...", Cmd::OverrideElements, &mut run);
                if ui.button("By Category...").clicked() {
                    open_vg = Some(0);
                    ui.close();
                }
                if ui.button("By Filter...").clicked() {
                    open_vg = Some(3);
                    ui.close();
                }
            });
            ui.separator();
            item(ui, "Create Similar", Cmd::CreateSimilar, &mut run);
            let family = app.selection.len() == 1 && app.el(app.selection[0]).is_some_and(|e| matches!(e.kind, ElementKind::Instance(_)));
            if ui.add_enabled(family, egui::Button::new("Edit Family")).clicked() {
                run = Some(Cmd::EditFamily);
                ui.close();
            }
            ui.separator();
        }
        if ui.add_enabled(!app.prev_selection.is_empty(), egui::Button::new("Select Previous")).clicked() {
            let prev = app.prev_selection.clone();
            app.select(prev);
            ui.close();
        }
        if has_sel {
            ui.menu_button("Select All Instances", |ui| {
                item(ui, "Visible in View", Cmd::SelectAllVisible, &mut run);
                item(ui, "In Entire Project", Cmd::SelectAllProject, &mut run);
            });
            item(ui, "Delete", Cmd::Delete, &mut run);
            if app.selection.iter().any(|id| app.doc.data.view(*id).is_some()) {
                item(ui, "Go to View", Cmd::GoToView, &mut run);
            }
        }
        if let Some(tab) = open_vg {
            ui.ctx().memory_mut(|m| m.data.insert_temp(egui::Id::new("vg-tab"), tab));
            app.dialogs.vg = app.active;
        }
        ui.separator();
        item(ui, "Zoom In Region", Cmd::ZoomRegion, &mut run);
        item(ui, "Zoom Out (2x)", Cmd::ZoomOut, &mut run);
        item(ui, "Zoom To Fit", Cmd::ZoomFit, &mut run);
        ui.separator();
        if ui.add_enabled(can_step(app, view.id, true), egui::Button::new("Previous Pan/Zoom")).clicked() {
            run = Some(Cmd::PrevPanZoom);
            ui.close();
        }
        if ui.add_enabled(can_step(app, view.id, false), egui::Button::new("Next Pan/Zoom")).clicked() {
            run = Some(Cmd::NextPanZoom);
            ui.close();
        }
        ui.separator();
        ui.menu_button("Browsers", |ui| {
            item(ui, if app.settings.show_browser { "✓ Project Browser" } else { "Project Browser" }, Cmd::ToggleBrowser, &mut run);
        });
        item(ui, if app.settings.show_properties { "✓ Properties" } else { "Properties" }, Cmd::ToggleProperties, &mut run);
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
        ToolKind::Component | ToolKind::Column | ToolKind::StructColumn | ToolKind::IsolatedFooting | ToolKind::PlaceGroup | ToolKind::Text | ToolKind::Symbol | ToolKind::DetailComponent => {
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
