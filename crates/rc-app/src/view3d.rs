//! 3D views: navigation (orbit/pan/zoom), the ViewCube and navigation bar, picking, window
//! selection and section box grips.

use crate::app::App;
use crate::render3d::{self, Camera, DrawSettings};
use crate::style;
use eframe::egui::{self, Color32, Pos2, Rect, Sense, Stroke, pos2, vec2};
use glam::{DVec3, Vec3};
use rc_core::model::*;
use std::collections::HashSet;

/// Template eyes of never-navigated {3D} views (older and current templates): such views
/// zoom to fit the model from their direction when first opened.
const DEFAULT_EYES: [DVec3; 3] = [DVec3::new(-12000.0, -16000.0, 12000.0), DVec3::new(15000.0, -15000.0, 16500.0), DVec3::new(20000.0, -11000.0, 16500.0)];

/// The default view direction (from the eye towards nothing in particular): the south-east
/// corner of the ViewCube, Top + Front + Right, an exact isometric.
pub const HOME_DIR: DVec3 = DVec3::new(1.0, -1.0, 1.0);

/// A ViewCube or Home transition, interpolated over a short time.
#[derive(Clone, Copy)]
struct CamAnim {
    from: Camera,
    to: Camera,
    start: f64,
}

const ANIM_SECS: f64 = 0.4;

fn anim_id(view: Id) -> egui::Id {
    egui::Id::new(("cam-anim", view))
}

/// Starts an animated transition of a view's camera.
fn animate_to(app: &mut App, ui: &egui::Ui, view_id: Id, to: Camera) {
    let from = camera_of(app, view_id);
    let start = ui.input(|i| i.time);
    ui.memory_mut(|m| m.data.insert_temp(anim_id(view_id), CamAnim { from, to, start }));
    ui.ctx().request_repaint();
}

/// Interpolates two cameras: the view direction turns on a great circle, distance, target and
/// zoom ease in and out.
fn lerp_cam(a: &Camera, b: &Camera, t: f64) -> Camera {
    let s = t * t * (3.0 - 2.0 * t);
    let (da, db) = (a.eye - a.target, b.eye - b.target);
    let (ra, rb) = (da.length().max(1.0), db.length().max(1.0));
    let (ua, ub) = (da / ra, db / rb);
    let ang = ua.dot(ub).clamp(-1.0, 1.0).acos();
    let axis = ua.cross(ub);
    let axis = if axis.length() > 1e-9 { axis.normalize() } else if ua.z.abs() < 0.9 { DVec3::Z } else { DVec3::X };
    let u = glam::DQuat::from_axis_angle(axis, ang * s) * ua;
    let target = a.target.lerp(b.target, s);
    Camera { eye: target + u * (ra + (rb - ra) * s), target, perspective: b.perspective, ortho_height: a.ortho_height + (b.ortho_height - a.ortho_height) * s }
}

/// The point orbits turn about: the centre of the selection, else of the section box or the
/// model (when it is on screen), else the model point under the cursor.
fn orbit_pivot(app: &mut App, view_id: Id, cam: &Camera, rect: Rect, at: Option<Pos2>) -> DVec3 {
    if !app.selection.is_empty() {
        let sel: HashSet<Id> = app.selection.iter().copied().collect();
        let b = app.scenes.get(&view_id).and_then(|s| s.meshes.iter().filter(|(id, _)| sel.contains(id)).filter_map(|(_, m)| m.bounds()).reduce(|(a0, a1), (b0, b1)| (a0.min(b0), a1.max(b1))));
        if let Some((mn, mx)) = b {
            return (mn + mx) / 2.0;
        }
    }
    let section = app.doc.data.view(view_id).and_then(|v| v.section_box);
    if let Some(c) = section.or_else(|| app.model_bounds()).map(|(a, b)| (a + b) / 2.0) {
        if screen_of(cam, rect, c).is_some_and(|p| rect.contains(p)) {
            return c;
        }
    }
    if let Some(p) = at {
        let aspect = rect.width() / rect.height().max(1.0);
        let nx = ((p.x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
        let ny = (1.0 - (p.y - rect.top()) / rect.height() * 2.0) as f64;
        let (o, d) = cam.ray(nx, ny, aspect);
        if let Some((_, hit)) = app.scenes.get(&view_id).and_then(|s| render3d::pick(s, o, d, section)) {
            return hit;
        }
    }
    cam.target
}

/// Orbits the camera about a pivot: horizontal drags turn about the vertical axis (the scene
/// stays upright), vertical drags tilt about the screen's horizontal axis.
fn orbit_about(cam: &mut Camera, pivot: DVec3, dx: f32, dy: f32) {
    let off = (cam.eye - cam.target).normalize_or(DVec3::Z);
    let elev = off.z.clamp(-1.0, 1.0).asin();
    let lim = 1.5703f64.max(elev.abs());
    let dp = (elev + dy as f64 * 0.006).clamp(-lim, lim) - elev;
    let fwd = -off;
    let right = fwd.cross(cam.up().as_dvec3()).normalize_or(DVec3::X);
    let q = glam::DQuat::from_rotation_z(-dx as f64 * 0.006) * glam::DQuat::from_axis_angle(right, -dp);
    cam.eye = pivot + q * (cam.eye - pivot);
    cam.target = pivot + q * (cam.target - pivot);
}

/// Zooms by `f` (below 1 zooms in) keeping the model point under `at` in place.
fn zoom_at(cam: &mut Camera, rect: Rect, at: Pos2, f: f64) {
    let f = f.clamp(0.2, 5.0);
    let aspect = rect.width() / rect.height().max(1.0);
    let nx = ((at.x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
    let ny = (1.0 - (at.y - rect.top()) / rect.height() * 2.0) as f64;
    let fwd = (cam.target - cam.eye).normalize_or(DVec3::Y);
    let dist = (cam.target - cam.eye).length();
    if cam.perspective {
        // Moving the eye along the cursor's ray keeps the point under the cursor in place.
        let (_, d) = cam.ray(nx, ny, aspect);
        let new_dist = (dist * f).max(300.0);
        cam.eye += d * ((dist - new_dist) / d.dot(fwd).max(0.2));
        cam.target = cam.eye + fwd * new_dist;
    } else {
        let new_h = (cam.ortho_height * f).clamp(50.0, 5.0e7);
        let k = 1.0 - new_h / cam.ortho_height;
        let (o, _) = cam.ray(nx, ny, aspect);
        let (c, _) = cam.ray(0.0, 0.0, aspect);
        cam.target += (o - c) * k;
        cam.eye = cam.target - fwd * (new_h / 0.8);
        cam.ortho_height = new_h;
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum NavMode {
    #[default]
    Select,
    Orbit,
    Pan,
}

fn nav_mode(ui: &egui::Ui, view: Id) -> NavMode {
    ui.memory(|m| m.data.get_temp(egui::Id::new(("nav-mode", view)))).unwrap_or_default()
}

fn set_nav_mode(ui: &egui::Ui, view: Id, m: NavMode) {
    ui.memory_mut(|mem| mem.data.insert_temp(egui::Id::new(("nav-mode", view)), m));
}

/// Builds (or reuses) the GPU scene of a 3D view.
pub fn ensure_scene(app: &mut App, view_id: Id) -> bool {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return false };
    let sel: HashSet<Id> = app.selection.iter().copied().collect();
    let temp = app.temp_hide.get(&view_id).cloned().unwrap_or_default();
    let mut h: u64 = 1469598103934665603;
    let mut ids: Vec<Id> = sel.iter().copied().collect();
    ids.sort();
    let mut sel_key: u64 = 1469598103934665603;
    for id in &ids {
        sel_key = (sel_key ^ *id as u64).wrapping_mul(1099511628211);
    }
    let hover = app.interact.hover3d.filter(|_| app.active == Some(view_id));
    sel_key = (sel_key ^ hover.map(|h| h as u64 + (1 << 40)).unwrap_or(7)).wrapping_mul(1099511628211);
    let mut feed = |x: u64| h = (h ^ x).wrapping_mul(1099511628211);
    for id in &temp.hidden_elements {
        feed(*id as u64 + (1 << 33));
    }
    for c in &temp.hidden_categories {
        feed(*c as u64 + (1 << 34));
    }
    if let Some(iso) = &temp.isolate_elements {
        feed(iso.len() as u64 + (1 << 35));
    }
    if let Some(iso) = &temp.isolate_categories {
        feed(iso.len() as u64 + (1 << 36));
    }
    if app.reveal_hidden.contains(&view_id) {
        feed(1 << 37);
    }
    if let Some((g, _)) = &app.group_edit {
        feed(*g as u64 + (1 << 38));
    }
    if !app.show_mass {
        feed(1 << 39);
    }
    let key = (app.doc.revision, h);
    if app.scenes.get(&view_id).is_some_and(|s| s.key == key) {
        if let (Some(scene), Some(r)) = (app.scenes.get_mut(&view_id), app.renderer.as_ref()) {
            r.set_selection(scene, &sel, hover, sel_key ^ app.doc.revision.rotate_left(17));
        }
        return true;
    }
    let Some(renderer) = app.renderer.as_ref() else { return false };
    let fp = app.footprints();
    let p = &app.doc.data;
    let reveal = app.reveal_hidden.contains(&view_id);
    let mut halftone: HashSet<Id> = HashSet::new();
    let mut overrides: std::collections::HashMap<Id, GraphicOverride> = std::collections::HashMap::new();
    let mut meshes: Vec<(Id, rc_core::mesh::MeshSet)> = Vec::new();
    for e in p.elements.iter().filter(|e| e.view.is_none()) {
        let visible = rc_core::analysis::visible_in(p, &view, e);
        if !visible && !reveal {
            continue;
        }
        if temp.hides(e.id, e.category()) {
            continue;
        }
        if !visible {
            halftone.insert(e.id);
        }
        if let Some((g, _)) = &app.group_edit {
            if e.group != Some(*g) && e.id != *g {
                halftone.insert(e.id);
            }
        }
        if !app.show_mass && matches!(e.kind, ElementKind::Mass(_)) {
            continue;
        }
        let set = rc_core::build3d::element_mesh(p, e, &fp);
        if !set.is_empty() {
            if !view.overrides.is_empty() {
                if let Some(o) = rc_core::params::effective_override(p, &view, e) {
                    overrides.insert(e.id, o);
                }
            }
            meshes.push((e.id, set));
        }
    }
    let mut scene = renderer.upload(p, meshes, &HashSet::new(), key, &halftone, &overrides);
    renderer.set_selection(&mut scene, &sel, hover, sel_key ^ app.doc.revision.rotate_left(17));
    app.scenes.insert(view_id, scene);
    true
}

pub fn camera_of(app: &mut App, view_id: Id) -> Camera {
    if let Some(c) = app.cams3d.get(&view_id) {
        let persp = matches!(app.doc.data.view(view_id).map(|v| &v.kind), Some(ViewKind::ThreeD { perspective: true, .. }));
        return Camera { perspective: persp, ..*c };
    }
    let kind = app.doc.data.view(view_id).map(|v| v.kind.clone());
    let cam = match kind {
        Some(ViewKind::ThreeD { eye, target, perspective }) if !DEFAULT_EYES.contains(&eye) => Camera { eye, target, perspective, ortho_height: (target - eye).length() * 0.8 },
        Some(ViewKind::ThreeD { eye, target, perspective }) => {
            let b = app.model_bounds();
            render3d::frame_bounds(b, eye - target, perspective)
        }
        _ => render3d::frame_bounds(None, HOME_DIR, false),
    };
    app.cams3d.insert(view_id, cam);
    cam
}

pub fn frame_all(app: &mut App, view_id: Id) {
    let cam = camera_of(app, view_id);
    let dir = (cam.eye - cam.target).normalize_or(HOME_DIR);
    let b = app.doc.data.view(view_id).and_then(|v| v.section_box).or_else(|| app.model_bounds());
    let framed = render3d::frame_bounds(b, dir, cam.perspective);
    app.cams3d.insert(view_id, framed);
}

fn orbit(cam: &mut Camera, dx: f32, dy: f32) {
    let pivot = cam.target;
    orbit_about(cam, pivot, dx, dy);
}

fn pan(cam: &mut Camera, d: egui::Vec2, rect: Rect) {
    let fwd = (cam.target - cam.eye).normalize();
    let right = fwd.cross(DVec3::Z).normalize_or(DVec3::X);
    let up = right.cross(fwd);
    let k = if cam.perspective { (cam.target - cam.eye).length() * 0.83 / rect.height() as f64 } else { cam.ortho_height / rect.height() as f64 };
    let shift = (-right * d.x as f64 + up * d.y as f64) * k;
    cam.eye += shift;
    cam.target += shift;
}

/// Modify tools available in 3D views, as in the reference app.
pub fn is_3d_tool(k: crate::tools::ToolKind) -> bool {
    use crate::tools::ToolKind as T;
    matches!(
        k,
        T::Move | T::Copy | T::Rotate | T::Array | T::MirrorPick | T::MirrorDraw | T::Align | T::Measure | T::Split | T::SplitGap | T::JoinGeometry | T::UnjoinGeometry
            | T::MatchType | T::AttachTop | T::AttachBase | T::TrimCorner | T::TrimSingle | T::TrimMulti | T::ZoomRegion | T::Door | T::Window | T::Wall
    )
}

/// Runs a modify tool in a 3D view: elements are picked on their faces, points come from the
/// face under the cursor or the work plane at the level of the elements being modified.
#[allow(clippy::too_many_arguments)]
fn tool_3d(app: &mut App, resp: &egui::Response, painter: &egui::Painter, rect: Rect, cam: &Camera, view: &View, o: DVec3, d: DVec3) {
    use crate::tools::ToolKind as T;
    use rc_core::edit;
    use rc_core::geom::DVec2;
    let kind = app.tool.kind;
    let hit = app.scenes.get(&view.id).and_then(|s| render3d::pick(s, o, d, view.section_box));
    let hit_id = hit.map(|h| h.0).and_then(|id| crate::canvas::selectable_id(app, view, id));
    app.interact.hover3d = hit_id;
    let z0 = app.tool.ids.first().and_then(|id| app.el(*id)).and_then(|e| e.level()).map(|l| app.doc.data.level_elevation(l)).unwrap_or(0.0);
    let on_plane = if d.z.abs() > 1e-9 {
        let t = (z0 - o.z) / d.z;
        (t > 0.0).then(|| (o + d * t).truncate())
    } else {
        None
    };
    let point = hit.map(|h| h.1.truncate()).or(on_plane);
    let at3 = |q: DVec2| DVec3::new(q.x, q.y, z0);
    let preview = |a: DVec2, b: DVec2| {
        if let (Some(sa), Some(sb)) = (screen_of(cam, rect, at3(a)), screen_of(cam, rect, at3(b))) {
            painter.line_segment([sa, sb], Stroke::new(1.5, style::PREVIEW));
        }
    };
    let ids = app.tool.ids.clone();
    let pts = app.tool.pts.clone();
    if let (Some(a), Some(c)) = (pts.first(), point) {
        if !matches!(kind, T::Align | T::TrimCorner | T::TrimSingle | T::TrimMulti | T::MatchType | T::JoinGeometry | T::UnjoinGeometry) {
            preview(*a, c);
        }
    }
    // The centre of the elements being modified (rotation centre).
    let centre = || {
        let fp = app.footprints();
        let pts: Vec<DVec2> = ids.iter().filter_map(|id| app.el(*id)).flat_map(|e| rc_core::plan::element_outline(&app.doc.data, e, &fp).into_iter().flatten()).collect();
        let (mn, mx) = rc_core::geom::bounds(pts);
        if mn.x <= mx.x { (mn + mx) / 2.0 } else { DVec2::ZERO }
    };
    if kind == T::ZoomRegion {
        if resp.dragged() {
            if let (Some(start), Some(cur)) = (resp.ctx.input(|i| i.pointer.press_origin()), resp.hover_pos()) {
                painter.rect_stroke(Rect::from_two_pos(start, cur), 0.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Middle);
            }
        }
        if resp.drag_stopped() {
            if let (Some(start), Some(end)) = (resp.ctx.input(|i| i.pointer.press_origin()), resp.hover_pos()) {
                let r = Rect::from_two_pos(start, end);
                if r.width() > 4.0 && r.height() > 4.0 {
                    let mut c2 = *cam;
                    let f = (r.height() / rect.height()).max(r.width() / rect.width()) as f64;
                    let cx = ((r.center().x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
                    let cy = (1.0 - (r.center().y - rect.top()) / rect.height() * 2.0) as f64;
                    let (ro, rd) = cam.ray(cx, cy, (rect.width() / rect.height().max(1.0)) as f32);
                    let target = app.scenes.get(&view.id).and_then(|s| render3d::pick(s, ro, rd, view.section_box)).map(|h| h.1).unwrap_or(ro + rd * (cam.target - cam.eye).length());
                    let shift = target - c2.target;
                    c2.target += shift;
                    c2.eye += shift;
                    if c2.perspective {
                        c2.eye = c2.target + (c2.eye - c2.target) * f.max(0.05);
                    } else {
                        c2.ortho_height *= f.max(0.02);
                    }
                    app.cams3d.insert(view.id, c2);
                    app.set_tool(T::Select);
                }
            }
        }
        return;
    }
    // Walls are drawn on the lowest level's plane: a box preview, its length, chained clicks.
    if kind == T::Wall {
        let Some(level) = app.doc.data.levels().first().map(|(id, _)| *id) else { return };
        let z = app.doc.data.level_elevation(level);
        let mut on_level = (d.z.abs() > 1e-9).then(|| (z - o.z) / d.z).filter(|t| *t > 0.0).map(|t| (o + d * t).truncate());
        // Wall ends snap within a few pixels, so chains and corners close.
        if let Some(c) = on_level {
            let near = app.doc.data.elements.iter().filter_map(|e| e.as_wall()).filter(|w| w.base_level == level).flat_map(|w| [w.start, w.end]).filter_map(|q| screen_of(cam, rect, DVec3::new(q.x, q.y, z)).map(|s| (q, s))).filter(|(_, s)| resp.hover_pos().is_some_and(|h| h.distance(*s) < 10.0)).map(|(q, _)| q).next();
            if let Some(q) = near {
                if let Some(sq) = screen_of(cam, rect, DVec3::new(q.x, q.y, z)) {
                    painter.rect_stroke(Rect::from_center_size(sq, egui::vec2(10.0, 10.0)), 0.0, Stroke::new(1.6, style::SNAP), egui::StrokeKind::Middle);
                }
                on_level = Some(q);
            }
            let _ = c;
        }
        if let Some(h) = resp.hover_pos() {
            resp.ctx.set_cursor_icon(egui::CursorIcon::None);
            crate::canvas::paint_crosshair(painter, h);
        }
        let (t, height) = (app.doc.data.sys_type(app.opts.wall_type).map(|t| t.thickness()).unwrap_or(200.0), app.opts.wall_height.max(1.0));
        if let (Some(a), Some(b)) = (app.tool.pts.last().copied(), on_level) {
            if a.distance(b) > 1.0 {
                let dir = (b - a).normalize();
                let n = rc_core::geom::perp(dir) * (t / 2.0);
                let base = [a + n, b + n, b - n, a - n];
                let ring = |zz: f64| base.iter().map(|q| screen_of(cam, rect, DVec3::new(q.x, q.y, zz))).collect::<Option<Vec<Pos2>>>();
                if let (Some(lo), Some(hi)) = (ring(z), ring(z + height)) {
                    let st = Stroke::new(1.5, style::PREVIEW);
                    painter.add(egui::Shape::closed_line(lo.clone(), st));
                    painter.add(egui::Shape::closed_line(hi.clone(), st));
                    for k in 0..4 {
                        painter.line_segment([lo[k], hi[k]], st);
                    }
                    let mid = lo[0] + (lo[1] - lo[0]) / 2.0;
                    style::canvas_tooltip(painter, mid + egui::vec2(6.0, 8.0), &app.doc.data.units.length(a.distance(b)));
                }
            }
        }
        if resp.clicked_by(egui::PointerButton::Primary) {
            if let Some(b) = on_level {
                match app.tool.pts.last().copied() {
                    Some(a) if a.distance(b) > 10.0 => {
                        let o2 = app.opts.clone();
                        app.run("Wall", |p| edit::add_wall_ex(p, level, o2.wall_type, a, b, None, height, o2.location_line, false));
                        app.tool.pts = if app.opts.chain { vec![b] } else { Vec::new() };
                    }
                    Some(_) => {}
                    None => app.tool.pts.push(b),
                }
            }
        }
        app.interact.prompt = if app.tool.pts.is_empty() { "Click to enter wall start point.".into() } else { "Click to enter wall end point.".into() };
        return;
    }
    // Doors and windows go on the wall face under the cursor.
    if matches!(kind, T::Door | T::Window) {
        let wall = hit.filter(|h| app.doc.data.wall(h.0).is_some());
        if let Some((wid, q)) = wall {
            let w = app.doc.data.wall(wid).unwrap().clone();
            let (along, _) = rc_core::analysis::wall_project(&w, q.truncate());
            let is_door = kind == T::Door;
            let type_id = if is_door { app.opts.door_type } else { app.opts.window_type };
            let width = app.doc.data.family_type(type_id).map(|(f, t)| rc_core::family_params::Resolver::for_type(f, t)).map(|r| r.num("Rough Width", r.num("Width", 900.0))).unwrap_or(900.0);
            let along = along.clamp(width / 2.0, (w.length() - width / 2.0).max(width / 2.0));
            let (c, dir) = rc_core::analysis::wall_point(&w, along);
            let base = app.doc.data.level_elevation(w.base_level) + w.base_offset;
            let corners = [c - dir * (width / 2.0), c + dir * (width / 2.0)];
            let pts: Vec<Pos2> = [(corners[0], base), (corners[1], base), (corners[1], base + 2100.0), (corners[0], base + 2100.0)].iter().filter_map(|(p2, z)| screen_of(cam, rect, DVec3::new(p2.x, p2.y, *z))).collect();
            if pts.len() == 4 {
                painter.add(egui::Shape::closed_line(pts, Stroke::new(2.0, style::PREVIEW)));
            }
            if resp.clicked_by(egui::PointerButton::Primary) {
                let sill = if is_door { None } else { app.opts.window_sill };
                app.run(if is_door { "Place Door" } else { "Place Window" }, |p| {
                    let id = edit::place_hosted(p, type_id, wid, along, false)?;
                    if let Some(s) = sill {
                        if let Some(i) = p.element_mut(id).and_then(|e| e.as_instance_mut()) {
                            i.elevation = s;
                        }
                    }
                    Ok(id)
                });
            }
        } else if resp.clicked_by(egui::PointerButton::Primary) {
            app.error(if kind == T::Door { "Doors must be hosted by a wall. Click a wall face." } else { "Windows must be hosted by a wall. Click a wall face." });
        }
        return;
    }
    if !resp.clicked_by(egui::PointerButton::Primary) {
        return;
    }
    match kind {
        T::Move | T::Copy | T::Array | T::MirrorDraw | T::Measure | T::Rotate => {
            let Some(c) = point else { return };
            if pts.is_empty() {
                app.tool.pts.push(c);
                return;
            }
            let a = pts[0];
            match kind {
                T::Move => {
                    app.run("Move", |p| {
                        edit::move_elements(p, &ids, c - a);
                        Ok(())
                    });
                    app.tool.reset();
                    app.set_tool(T::Select);
                    app.select(ids);
                }
                T::Copy => {
                    let made = app.run("Copy", |p| Ok(edit::copy_elements(p, &ids, c - a)));
                    if app.opts.copy_multiple {
                        // Further clicks copy again from the same start.
                        return;
                    }
                    app.set_tool(T::Select);
                    app.select(made.unwrap_or_default());
                }
                T::Array => {
                    let n = app.opts.array_count.max(2) as usize;
                    let step = if app.opts.array_last { (c - a) / (n - 1) as f64 } else { c - a };
                    app.run("Array", |p| edit::array_linear(p, &ids, step, n));
                    app.set_tool(T::Select);
                }
                T::MirrorDraw => {
                    let copy = app.opts.mirror_copy;
                    app.run("Mirror", |p| {
                        let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
                        edit::mirror_elements(p, &targets, a, c);
                        Ok(())
                    });
                    app.set_tool(T::Select);
                }
                T::Measure => {
                    let units = app.doc.data.units.clone();
                    app.info(format!("Length: {}   ΔX: {}   ΔY: {}", units.length(a.distance(c)), units.length((c.x - a.x).abs()), units.length((c.y - a.y).abs())));
                    app.tool.pts.clear();
                }
                _ => {
                    // Rotate: the first click sets the start ray, the second the end ray.
                    let ctr = centre();
                    let deg = (a - ctr).angle_to(c - ctr).to_degrees();
                    let copy = app.opts.rotate_copy;
                    app.run("Rotate", |p| {
                        let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
                        edit::rotate_elements(p, &targets, ctr, deg);
                        Ok(())
                    });
                    app.set_tool(T::Select);
                    app.select(ids);
                }
            }
        }
        T::MirrorPick => {
            let Some((a, b)) = hit_id.and_then(|id| app.el(id)).and_then(edit::linear_axis) else {
                app.error("Pick a straight wall, line or grid as the mirror axis.");
                return;
            };
            let copy = app.opts.mirror_copy;
            app.run("Mirror", |p| {
                let targets = if copy { edit::copy_elements(p, &ids, DVec2::ZERO) } else { ids.clone() };
                edit::mirror_elements(p, &targets, a, b);
                Ok(())
            });
            app.set_tool(T::Select);
        }
        T::Split | T::SplitGap => {
            let (Some(id), Some(c)) = (hit_id, point) else { return };
            let gap = if kind == T::SplitGap { app.opts.split_gap } else { 0.0 };
            app.run("Split", |p| edit::split_element(p, id, c, gap));
        }
        T::Align | T::TrimCorner | T::TrimSingle | T::TrimMulti | T::JoinGeometry | T::UnjoinGeometry | T::MatchType => {
            let (Some(id), Some(c)) = (hit_id, point) else { return };
            if app.tool.picked.is_empty() {
                app.tool.picked.push(id);
                app.tool.pts = vec![c];
                if kind == T::Align && app.el(id).and_then(edit::linear_axis).is_none() {
                    app.error("Pick a straight wall, line or grid as the alignment reference.");
                    app.tool.reset();
                }
                return;
            }
            let (first, first_pt) = (app.tool.picked[0], app.tool.pts.first().copied().unwrap_or(c));
            let ok = match kind {
                T::Align => {
                    let (ra, rb) = app.el(first).and_then(edit::linear_axis).unwrap_or((first_pt, first_pt));
                    app.run("Align", |p| edit::align(p, ra, rb, id, c)).is_some()
                }
                T::TrimCorner => app.run("Trim/Extend", |p| edit::trim_extend_corner(p, first, first_pt, id, c)).is_some(),
                T::TrimSingle | T::TrimMulti => {
                    app.run("Trim/Extend", |p| edit::trim_extend_to(p, first, &[(id, c)]));
                    // Multiple: keep the boundary and trim more elements.
                    if kind == T::TrimMulti {
                        return;
                    }
                    true
                }
                T::JoinGeometry => app.run("Join Geometry", |p| edit::join_geometry(p, first, id)).is_some(),
                T::UnjoinGeometry => app.run("Unjoin Geometry", |p| edit::unjoin_geometry(p, first, id)).is_some(),
                _ => {
                    app.run("Match Type", |p| edit::match_type(p, first, &[id]));
                    // Match Type keeps the source for more picks.
                    return;
                }
            };
            let _ = ok;
            app.tool.picked.clear();
            app.tool.pts.clear();
        }
        T::AttachTop | T::AttachBase => {
            let Some(target) = hit_id else { return };
            let top = kind == T::AttachTop;
            app.run(if top { "Attach Top" } else { "Attach Base" }, |p| edit::attach_walls(p, &ids, target, top));
            app.set_tool(T::Select);
            app.select(ids);
        }
        _ => {}
    }
}

fn screen_of(cam: &Camera, rect: Rect, p: DVec3) -> Option<Pos2> {
    let aspect = rect.width() / rect.height().max(1.0);
    let ndc = cam.project(p, aspect);
    if !(0.0..=1.0).contains(&ndc.z) {
        return None;
    }
    Some(pos2(rect.left() + ((ndc.x + 1.0) / 2.0) as f32 * rect.width(), rect.top() + ((1.0 - ndc.y) / 2.0) as f32 * rect.height()))
}

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    if app.renderer.is_none() {
        ui.painter().text(rect.center(), egui::Align2::CENTER_CENTER, "3D rendering is unavailable: no GPU adapter was found.", egui::FontId::proportional(14.0), style::text_dim());
        return;
    }
    let mut cam = camera_of(app, view_id);
    let mode = nav_mode(ui, view_id);
    let shift = ui.input(|i| i.modifiers.shift);
    let ctrl = ui.input(|i| i.modifiers.command || i.modifiers.ctrl);

    // ViewCube and nav bar areas take input first.
    let cube_rect = Rect::from_min_size(rect.right_top() + vec2(-128.0, 10.0), vec2(118.0, 118.0));
    let nav_rect = Rect::from_min_size(rect.right_top() + vec2(-38.0, 136.0), vec2(30.0, 66.0));
    let pointer = ui.input(|i| i.pointer.interact_pos());
    let over_cube = app.settings.show_viewcube && pointer.is_some_and(|p| cube_rect.contains(p));
    let over_nav = app.settings.show_navbar && pointer.is_some_and(|p| nav_rect.contains(p));
    let press_origin = ui.input(|i| i.pointer.press_origin());
    let drag_from_cube = press_origin.is_some_and(|p| cube_rect.contains(p) && app.settings.show_viewcube);

    // Navigation, as in the reference app: wheel zooms about the cursor, middle drag pans,
    // Shift+middle drag (or a drag on the ViewCube) orbits about the model or the selection,
    // Ctrl+middle drag zooms, a middle double-click zooms to fit.
    let mut moved = false;
    if let Some(a) = ui.memory(|m| m.data.get_temp::<CamAnim>(anim_id(view_id))) {
        let t = ((ui.input(|i| i.time) - a.start) / ANIM_SECS).clamp(0.0, 1.0);
        cam = lerp_cam(&a.from, &a.to, t);
        if t >= 1.0 {
            ui.memory_mut(|m| m.data.remove::<CamAnim>(anim_id(view_id)));
        } else {
            ui.ctx().request_repaint();
        }
    }
    let wheel_on = crate::wheel::load(ui, view_id).on;
    let left_drag = resp.dragged_by(egui::PointerButton::Primary) && !wheel_on;
    let middle_drag = resp.dragged_by(egui::PointerButton::Middle);
    let section_drag: Option<(usize, Pos2)> = ui.memory(|m| m.data.get_temp(egui::Id::new(("sbox-drag", view_id))));
    let ring_drag = drag_from_cube && ui.memory(|m| m.data.get_temp::<bool>(egui::Id::new(("cube-ring-drag", view_id)))).unwrap_or(false);
    let orbit_drag = (left_drag && section_drag.is_none() && (drag_from_cube || shift || mode == NavMode::Orbit)) || (middle_drag && shift);
    let pivot_key = egui::Id::new(("orbit-pivot", view_id));
    let mut pivot_shown: Option<DVec3> = None;
    if orbit_drag {
        let pv = match ui.memory(|m| m.data.get_temp::<DVec3>(pivot_key)) {
            Some(p) => p,
            None => {
                let p = orbit_pivot(app, view_id, &cam, rect, press_origin);
                ui.memory_mut(|m| m.data.insert_temp(pivot_key, p));
                p
            }
        };
        let d = resp.drag_delta();
        orbit_about(&mut cam, pv, d.x, if ring_drag { 0.0 } else { d.y });
        ui.ctx().set_cursor_icon(egui::CursorIcon::Grabbing);
        pivot_shown = Some(pv).filter(|_| !drag_from_cube);
        moved = true;
    } else {
        ui.memory_mut(|m| m.data.remove::<DVec3>(pivot_key));
        if left_drag && section_drag.is_none() && mode == NavMode::Pan {
            pan(&mut cam, resp.drag_delta(), rect);
            moved = true;
        } else if middle_drag && ctrl {
            let at = press_origin.unwrap_or(rect.center());
            zoom_at(&mut cam, rect, at, (resp.drag_delta().y as f64 * 0.01).exp());
            moved = true;
        } else if middle_drag {
            pan(&mut cam, resp.drag_delta(), rect);
            ui.ctx().set_cursor_icon(egui::CursorIcon::Move);
            moved = true;
        }
    }
    if resp.hovered() {
        let scroll = ui.input(|i| i.smooth_scroll_delta.y) as f64;
        let zoom = ui.input(|i| i.zoom_delta()) as f64;
        let f = (-scroll * 0.0022).exp() / zoom;
        if (f - 1.0).abs() > 1e-6 {
            if let Some(hp) = resp.hover_pos() {
                zoom_at(&mut cam, rect, hp, f);
            }
            moved = true;
        }
    }
    if resp.double_clicked_by(egui::PointerButton::Middle) {
        app.cams3d.insert(view_id, cam);
        frame_all(app, view_id);
        cam = camera_of(app, view_id);
        moved = true;
    }
    if moved {
        // Navigating interrupts a ViewCube transition.
        ui.memory_mut(|m| m.data.remove::<CamAnim>(anim_id(view_id)));
    }
    if wheel_on && !over_cube && !over_nav {
        wheel_3d(app, ui, &resp, rect, view_id, &mut cam, view.section_box);
    }
    app.cams3d.insert(view_id, cam);

    // Render.
    if !ensure_scene(app, view_id) {
        return;
    }
    let ppp = ui.ctx().pixels_per_point();
    let size = [(rect.width() * ppp).round().max(8.0) as u32, (rect.height() * ppp).round().max(8.0) as u32];
    let sun = render3d::sun_direction(app.doc.data.sun.azimuth + app.doc.data.true_north, app.doc.data.sun.altitude);
    let bg = if app.settings.black_canvas { [0.13, 0.15, 0.18] } else if matches!(view.style, VisualStyle::Realistic) { [0.84, 0.89, 0.95] } else { [1.0, 1.0, 1.0] };
    let settings = DrawSettings { style: view.style, shadows: view.shadows, sun, section_box: view.section_box, background: bg };
    let tex = {
        let (Some(scene), Some(renderer)) = (app.scenes.get(&view_id), app.renderer.as_mut()) else { return };
        renderer.render_view(view_id, size, scene, &cam, &settings)
    };
    let painter = ui.painter_at(rect);
    painter.image(tex, rect, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
    let is_active = app.active == Some(view_id);
    if app.reveal_hidden.contains(&view_id) {
        painter.rect_stroke(rect.shrink(2.0), 0.0, Stroke::new(3.0, style::REVEAL), egui::StrokeKind::Inside);
    } else if app.temp_hide.get(&view_id).is_some_and(|t| t.is_active()) {
        painter.rect_stroke(rect.shrink(2.0), 0.0, Stroke::new(3.0, style::TEMP_HIDE), egui::StrokeKind::Inside);
    }

    // Work Plane > Show: the lowest level's plane as a translucent grid around the model.
    if app.show_work_plane.contains(&view_id) {
        if let (Some((mn, mx)), Some(z)) = (app.model_bounds(), app.doc.data.levels().first().map(|(_, l)| l.elevation)) {
            let spacing = if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { 3048.0 } else { 3000.0 };
            let (x0, y0) = ((mn.x / spacing).floor() * spacing - spacing * 2.0, (mn.y / spacing).floor() * spacing - spacing * 2.0);
            let (x1, y1) = ((mx.x / spacing).ceil() * spacing + spacing * 2.0, (mx.y / spacing).ceil() * spacing + spacing * 2.0);
            let at = |x: f64, y: f64| screen_of(&cam, rect, DVec3::new(x, y, z));
            if let (Some(a), Some(b), Some(c), Some(d)) = (at(x0, y0), at(x1, y0), at(x1, y1), at(x0, y1)) {
                painter.add(egui::Shape::convex_polygon(vec![a, b, c, d], egui::Color32::from_rgba_unmultiplied(110, 170, 235, 45), Stroke::new(1.5, egui::Color32::from_rgb(60, 130, 220))));
                let st = Stroke::new(1.0, egui::Color32::from_rgba_unmultiplied(80, 150, 230, 160));
                let mut x = x0 + spacing;
                while x < x1 - 1.0 {
                    if let (Some(p0), Some(p1)) = (at(x, y0), at(x, y1)) {
                        painter.extend(egui::Shape::dashed_line(&[p0, p1], st, 6.0, 4.0));
                    }
                    x += spacing;
                }
                let mut y = y0 + spacing;
                while y < y1 - 1.0 {
                    if let (Some(p0), Some(p1)) = (at(x0, y), at(x1, y)) {
                        painter.extend(egui::Shape::dashed_line(&[p0, p1], st, 6.0, 4.0));
                    }
                    y += spacing;
                }
            }
        }
    }
    // Section box: edges and face grips.
    if let Some((mn, mx)) = view.section_box {
        section_box_ui(app, ui, &painter, &resp, rect, &cam, view_id, mn, mx);
    }

    // Picking and window selection.
    let aspect = rect.width() / rect.height().max(1.0);
    if wheel_on {
        let st = crate::wheel::load(ui, view_id);
        if let (Some(c), Some(p)) = (st.center, ui.input(|i| i.pointer.latest_pos())) {
            let hot = st.drag.or_else(|| crate::wheel::wedge_at(true, c, p));
            crate::wheel::paint(&painter, c, true, hot, st.drag);
            app.interact.prompt = crate::wheel::prompt(hot).into();
        }
        if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
            crate::wheel::store(ui, view_id, Default::default());
        }
        ui.ctx().request_repaint();
    }
    if is_active && !over_cube && !over_nav && !wheel_on {
        if let Some(hp) = resp.hover_pos() {
            let nx = ((hp.x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
            let ny = (1.0 - (hp.y - rect.top()) / rect.height() * 2.0) as f64;
            let (o, d) = cam.ray(nx, ny, aspect);
            let hit = app.scenes.get(&view_id).and_then(|s| render3d::pick(s, o, d, view.section_box));
            let hit_id = hit.map(|h| h.0).and_then(|id| crate::canvas::selectable_id(app, &view, id));
            if app.interact.hover3d != hit_id {
                app.interact.hover3d = hit_id;
                ui.ctx().request_repaint();
            }
            app.interact.prompt = hit_id.map(|id| crate::canvas::describe(app, id)).unwrap_or_else(|| "Click to select, TAB for alternates, CTRL adds, SHIFT unselects.".into());
            // Modify tools that work in 3D (Move, Copy, Rotate, Align, Trim, Join, Attach, ...).
            let modify_3d = is_3d_tool(app.tool.kind);
            if modify_3d {
                app.interact.prompt = crate::canvas_tools::prompt(app);
                tool_3d(app, &resp, &painter, rect, &cam, &view, o, d);
            }
            // Paint: click faces to paint them (or remove their paint).
            let painting = matches!(app.tool.kind, crate::tools::ToolKind::Paint | crate::tools::ToolKind::RemovePaint);
            if painting {
                let face = app.scenes.get(&view_id).and_then(|s| render3d::pick_face(s, o, d, view.section_box));
                let remove = app.tool.kind == crate::tools::ToolKind::RemovePaint;
                app.interact.prompt = if remove { "Click a painted face to remove its paint. Esc to finish.".into() } else { format!("Click a face to paint it with {}. Esc to finish.", app.opts.paint_material) };
                if resp.clicked_by(egui::PointerButton::Primary) {
                    if let Some((id, q, n)) = face {
                        let mat = app.opts.paint_material.clone();
                        app.run(if remove { "Remove Paint" } else { "Paint" }, |p| if remove { rc_core::edit::remove_paint(p, id, n, q) } else { rc_core::edit::paint_face(p, id, n, q, &mat) });
                    }
                }
            }
            // Wall: Sweep / Reveal: click a wall face.
            if app.tool.kind == crate::tools::ToolKind::WallSweep {
                app.interact.prompt = crate::canvas_tools::prompt(app);
                if resp.clicked_by(egui::PointerButton::Primary) {
                    match app.scenes.get(&view_id).and_then(|s| render3d::pick_face(s, o, d, view.section_box)) {
                        Some((host, q, n)) => crate::canvas_tools::place_wall_sweep(app, host, q, n),
                        None => app.error("Click on a wall face."),
                    }
                }
            }
            // Place Decal: click a face.
            let decal = app.tool.kind == crate::tools::ToolKind::PlaceDecal;
            if decal {
                app.interact.prompt = "Click on a planar face to place the decal.".into();
                if resp.clicked_by(egui::PointerButton::Primary) {
                    match app.scenes.get(&view_id).and_then(|s| render3d::pick_face(s, o, d, view.section_box)) {
                        Some((host, q, n)) if !app.el(host).is_some_and(|e| matches!(e.kind, ElementKind::Decal(_))) => {
                            let t = app.opts.decal_type;
                            if let Some(id) = app.run("Place Decal", |p| rc_core::edit::add_decal(p, t, host, q, n)) {
                                app.select(vec![id]);
                            }
                        }
                        _ => app.error("Click on a planar face of the model."),
                    }
                }
            }
            if resp.clicked_by(egui::PointerButton::Primary) && section_drag.is_none() && !painting && !modify_3d && !decal && app.tool.kind != crate::tools::ToolKind::WallSweep {
                match hit_id {
                    Some(id) if ctrl => {
                        let mut s = app.selection.clone();
                        if !s.contains(&id) {
                            s.push(id);
                        }
                        app.select(s);
                    }
                    Some(id) if shift => {
                        let mut s = app.selection.clone();
                        s.retain(|x| *x != id);
                        app.select(s);
                    }
                    Some(id) => app.select(vec![id]),
                    None if !ctrl && !shift => app.select(vec![]),
                    None => {}
                }
            }
            if resp.double_clicked_by(egui::PointerButton::Primary) {
                if let Some(id) = hit_id {
                    if app.el(id).is_some_and(|e| matches!(e.kind, ElementKind::Instance(_))) {
                        crate::actions::exec(app, crate::commands::Cmd::EditFamily);
                    }
                }
            }
        }
        // Window selection with a plain left drag in select mode.
        if mode == NavMode::Select && !shift && !drag_from_cube && section_drag.is_none() && !is_3d_tool(app.tool.kind) {
            if let (Some(start), Some(cur)) = (press_origin.filter(|_| left_drag || resp.drag_stopped()), resp.hover_pos().or(pointer)) {
                if rect.contains(start) {
                    let r = Rect::from_two_pos(start, cur);
                    let crossing = cur.x < start.x;
                    painter.rect_filled(r, 0.0, if crossing { Color32::from_rgba_unmultiplied(60, 200, 90, 30) } else { Color32::from_rgba_unmultiplied(40, 120, 255, 30) });
                    painter.rect_stroke(r, 0.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Middle);
                    if resp.drag_stopped() && r.width() > 3.0 {
                        let mut ids = Vec::new();
                        if let Some(scene) = app.scenes.get(&view_id) {
                            for (id, set) in &scene.meshes {
                                let Some((mn, mx)) = set.bounds() else { continue };
                                let corners: Vec<Pos2> = (0..8).filter_map(|k| {
                                    let p = DVec3::new(if k & 1 == 0 { mn.x } else { mx.x }, if k & 2 == 0 { mn.y } else { mx.y }, if k & 4 == 0 { mn.z } else { mx.z });
                                    screen_of(&cam, rect, p)
                                }).collect();
                                if corners.is_empty() {
                                    continue;
                                }
                                let inside = corners.iter().all(|c| r.contains(*c));
                                let touches = Rect::from_points(&corners).intersects(r);
                                if inside || (crossing && touches) {
                                    ids.push(*id);
                                }
                            }
                        }
                        let mut out: Vec<Id> = if ctrl { app.selection.clone() } else { vec![] };
                        for id in ids {
                            if let Some(s) = crate::canvas::selectable_id(app, &view, id) {
                                if !out.contains(&s) {
                                    out.push(s);
                                }
                            }
                        }
                        app.select(out);
                    }
                }
            }
        }
    }

    // The orbit pivot, while orbiting.
    if let Some(p) = pivot_shown.and_then(|p| screen_of(&cam, rect, p)) {
        painter.circle_filled(p, 7.0, Color32::from_rgba_unmultiplied(70, 170, 70, 200));
        painter.circle_stroke(p, 7.0, Stroke::new(1.0, Color32::from_rgb(30, 90, 30)));
        painter.circle_filled(p + vec2(-2.0, -2.0), 2.0, Color32::from_rgba_unmultiplied(230, 255, 230, 220));
    }
    if app.settings.show_viewcube {
        view_cube(app, ui, &painter, cube_rect, view_id);
    }
    if app.settings.show_navbar {
        nav_bar(app, ui, nav_rect, view_id, mode);
    }
    resp.context_menu(|ui| {
        if ui.button("Zoom To Fit").clicked() {
            frame_all(app, view_id);
            ui.close();
        }
        if ui.button("Go to Home").clicked() {
            go_home(app, ui, view_id);
            ui.close();
        }
        if !app.selection.is_empty() {
            ui.separator();
            if ui.button("Delete").clicked() {
                crate::actions::exec(app, crate::commands::Cmd::Delete);
                ui.close();
            }
            if ui.button("Hide in View: Elements").clicked() {
                crate::actions::exec(app, crate::commands::Cmd::HideElements);
                ui.close();
            }
            if ui.button("Isolate Element (temporary)").clicked() {
                crate::actions::exec(app, crate::commands::Cmd::TempIsolateElement);
                ui.close();
            }
            if ui.button("Section Box: Selection").clicked() {
                section_box_to_selection(app, view_id);
                ui.close();
            }
        }
        ui.separator();
        if ui.button("Properties").clicked() {
            app.settings.show_properties = true;
            ui.close();
        }
    });
}

/// Home: the view saved with "Set Current View as Home", else the south-east isometric
/// framing the section box or the model.
fn go_home(app: &mut App, ui: &egui::Ui, view_id: Id) {
    let cam = camera_of(app, view_id);
    let to = match app.home3d.get(&view_id) {
        Some(h) => Camera { perspective: cam.perspective, ..*h },
        None => {
            let b = app.doc.data.view(view_id).and_then(|v| v.section_box).or_else(|| app.model_bounds());
            render3d::frame_bounds(b, HOME_DIR, cam.perspective)
        }
    };
    animate_to(app, ui, view_id, to);
}

fn section_box_to_selection(app: &mut App, view_id: Id) {
    let fp = app.footprints();
    let p = &app.doc.data;
    let b = app
        .selection
        .iter()
        .filter_map(|id| p.element(*id))
        .filter_map(|e| rc_core::build3d::element_mesh(p, e, &fp).bounds())
        .reduce(|(a0, a1), (b0, b1)| (a0.min(b0), a1.max(b1)));
    if let Some((mn, mx)) = b {
        let pad = DVec3::splat(300.0);
        app.run("Section Box", |p| {
            if let Some(v) = p.view_mut(view_id) {
                v.section_box = Some((mn - pad, mx + pad));
            }
            Ok(())
        });
        app.select(vec![]);
        frame_all(app, view_id);
    }
}

fn section_box_ui(app: &mut App, ui: &egui::Ui, painter: &egui::Painter, resp: &egui::Response, rect: Rect, cam: &Camera, view_id: Id, mn: DVec3, mx: DVec3) {
    let corner = |k: usize| DVec3::new(if k & 1 == 0 { mn.x } else { mx.x }, if k & 2 == 0 { mn.y } else { mx.y }, if k & 4 == 0 { mn.z } else { mx.z });
    let edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)];
    for (a, b) in edges {
        if let (Some(pa), Some(pb)) = (screen_of(cam, rect, corner(a)), screen_of(cam, rect, corner(b))) {
            painter.line_segment([pa, pb], Stroke::new(1.0, Color32::from_rgb(110, 110, 120)));
        }
    }
    let c = (mn + mx) / 2.0;
    // Faces: -x, +x, -y, +y, -z, +z.
    let faces = [
        (DVec3::new(mn.x, c.y, c.z), DVec3::NEG_X),
        (DVec3::new(mx.x, c.y, c.z), DVec3::X),
        (DVec3::new(c.x, mn.y, c.z), DVec3::NEG_Y),
        (DVec3::new(c.x, mx.y, c.z), DVec3::Y),
        (DVec3::new(c.x, c.y, mn.z), DVec3::NEG_Z),
        (DVec3::new(c.x, c.y, mx.z), DVec3::Z),
    ];
    let drag_id = egui::Id::new(("sbox-drag", view_id));
    let mut drag: Option<(usize, Pos2)> = ui.memory(|m| m.data.get_temp(drag_id));
    let pointer = ui.input(|i| i.pointer.interact_pos());
    for (k, (p, n)) in faces.iter().enumerate() {
        let (Some(sp), Some(sn)) = (screen_of(cam, rect, *p), screen_of(cam, rect, *p + *n * ((mx - mn).length() * 0.05))) else { continue };
        let dir = (sn - sp).normalized();
        let hot = pointer.is_some_and(|q| q.distance(sp) < 9.0) || drag.is_some_and(|d| d.0 == k);
        let col = if hot { style::PRESELECT } else { style::SELECT };
        let nrm = vec2(-dir.y, dir.x);
        painter.add(egui::Shape::convex_polygon(vec![sp + dir * 10.0, sp - dir * 3.0 + nrm * 6.0, sp - dir * 3.0 - nrm * 6.0], col, Stroke::new(1.0, Color32::WHITE)));
        if resp.drag_started_by(egui::PointerButton::Primary) && ui.input(|i| i.pointer.press_origin()).is_some_and(|q| q.distance(sp) < 9.0) {
            drag = Some((k, sp));
        }
    }
    if let Some((k, start)) = drag {
        if let Some(cur) = pointer {
            let (p, n) = faces[k];
            if let (Some(sp), Some(sn)) = (screen_of(cam, rect, p), screen_of(cam, rect, p + n * 1000.0)) {
                let axis = sn - sp;
                let per_mm = axis.length() / 1000.0;
                let moved_px = (cur - start).dot(axis.normalized());
                let delta = (moved_px / per_mm.max(1e-6)) as f64;
                let preview_p = p + n * delta;
                if let Some(pp) = screen_of(cam, rect, preview_p) {
                    painter.circle_stroke(pp, 7.0, Stroke::new(2.0, style::PREVIEW));
                }
                if resp.drag_stopped() {
                    let (mut a, mut b) = (mn, mx);
                    match k {
                        0 => a.x = (a.x + delta).min(b.x - 100.0),
                        1 => b.x = (b.x + delta).max(a.x + 100.0),
                        2 => a.y = (a.y + delta).min(b.y - 100.0),
                        3 => b.y = (b.y + delta).max(a.y + 100.0),
                        4 => a.z = (a.z + delta).min(b.z - 100.0),
                        _ => b.z = (b.z + delta).max(a.z + 100.0),
                    }
                    app.run("Section Box", |p| {
                        if let Some(v) = p.view_mut(view_id) {
                            v.section_box = Some((a, b));
                        }
                        Ok(())
                    });
                    drag = None;
                }
            }
        }
        if !ui.input(|i| i.pointer.primary_down()) && !resp.drag_stopped() {
            drag = None;
        }
    }
    ui.memory_mut(|m| match drag {
        Some(d) => {
            m.data.insert_temp(drag_id, d);
        }
        None => {
            m.data.remove::<(usize, Pos2)>(drag_id);
        }
    });
}

// ---------------------------------------------------------------- ViewCube
/// The ViewCube: 26 clickable regions (6 faces, 12 edges, 8 corners) that highlight as one
/// across the faces they span, the compass ring (click a letter, drag the ring to turn the
/// view), arrows to the neighbouring faces in a face view, Home, and a right-click menu.
/// The cube fades when the cursor is elsewhere.
fn view_cube(app: &mut App, ui: &egui::Ui, painter: &egui::Painter, area: Rect, view_id: Id) {
    let cam = camera_of(app, view_id);
    let view_m = cam.view_matrix();
    let rot = |v: DVec3| -> Vec3 { view_m.transform_vector3(v.as_vec3()) };
    let center = area.center() + vec2(4.0, -2.0);
    let s = 27.0f32;
    let proj = |v: DVec3| -> Pos2 {
        let r = rot(v);
        center + vec2(r.x, -r.y) * s
    };
    let cube_resp = ui.interact(area, egui::Id::new(("viewcube", view_id)), Sense::click());
    let pointer = ui.input(|i| i.pointer.hover_pos()).filter(|p| area.contains(*p));
    let pressed_here = ui.input(|i| i.pointer.press_origin()).is_some_and(|p| area.contains(p));
    let down = ui.input(|i| i.pointer.any_down());
    let active = pointer.is_some() || (down && pressed_here);
    let alpha = if active { 1.0 } else { 0.5 };
    let col = |r: u8, g: u8, b: u8| Color32::from_rgb(r, g, b).gamma_multiply(alpha);
    let highlight = Color32::from_rgb(140, 196, 245);
    let clicked = cube_resp.clicked();
    let off = (cam.eye - cam.target).normalize_or(HOME_DIR);
    let mut go: Option<DVec3> = None;

    // Faces: (normal, label, u, v) with u/v the face's in-plane axes.
    let faces: [(DVec3, &str, DVec3, DVec3); 6] = [
        (DVec3::Z, "TOP", DVec3::X, DVec3::Y),
        (DVec3::NEG_Z, "BOTTOM", DVec3::X, DVec3::NEG_Y),
        (DVec3::NEG_Y, "FRONT", DVec3::X, DVec3::Z),
        (DVec3::Y, "BACK", DVec3::NEG_X, DVec3::Z),
        (DVec3::X, "RIGHT", DVec3::Y, DVec3::Z),
        (DVec3::NEG_X, "LEFT", DVec3::NEG_Y, DVec3::Z),
    ];
    let span = |k: i32| match k {
        -1 => (-1.0, -0.62),
        0 => (-0.62, 0.62),
        _ => (0.62, 1.0),
    };
    let cell = |n: DVec3, u: DVec3, v: DVec3, i: i32, j: i32| -> [Pos2; 4] {
        let ((a0, a1), (b0, b1)) = (span(i), span(j));
        [n + u * a0 + v * b0, n + u * a1 + v * b0, n + u * a1 + v * b1, n + u * a0 + v * b1].map(proj)
    };
    let key = |d: DVec3| [d.x.round() as i32, d.y.round() as i32, d.z.round() as i32];
    let visible: Vec<usize> = {
        let mut o: Vec<usize> = (0..6).filter(|k| rot(faces[*k].0).z > 0.02).collect();
        o.sort_by(|a, b| rot(faces[*a].0).z.total_cmp(&rot(faces[*b].0).z));
        o
    };
    // The region under the cursor: a face, edge or corner, shared by every face it touches.
    let mut hot: Option<[i32; 3]> = None;
    if let Some(p) = pointer {
        for &k in &visible {
            let (n, _, u, v) = faces[k];
            for i in -1..=1 {
                for j in -1..=1 {
                    if point_in_quad(p, &cell(n, u, v, i, j)) {
                        hot = Some(key(n + u * i as f64 + v * j as f64));
                    }
                }
            }
        }
    }

    // Compass ring on the ground plane under the cube.
    let ring_r = 1.85;
    let ring: Vec<Pos2> = (0..=72).map(|k| {
        let t = k as f64 / 72.0 * std::f64::consts::TAU;
        proj(DVec3::new(t.cos() * ring_r, t.sin() * ring_r, -1.0))
    }).collect();
    let letters = [("N", DVec3::Y), ("E", DVec3::X), ("S", DVec3::NEG_Y), ("W", DVec3::NEG_X)];
    let letter_pos = |d: DVec3| proj(d * ring_r + DVec3::new(0.0, 0.0, -1.0));
    let mut hot_letter: Option<usize> = None;
    let mut ring_hot = false;
    if let (None, Some(p)) = (hot, pointer) {
        hot_letter = letters.iter().position(|(_, d)| letter_pos(*d).distance(p) < 8.0);
        ring_hot = hot_letter.is_none() && ring.windows(2).any(|w| seg_dist(p, w[0], w[1]) < 5.0);
    }
    let ring_key = egui::Id::new(("cube-ring-drag", view_id));
    if (ring_hot || hot_letter.is_some()) && ui.input(|i| i.pointer.primary_pressed()) {
        ui.memory_mut(|m| m.data.insert_temp(ring_key, true));
    } else if !down {
        ui.memory_mut(|m| m.data.remove::<bool>(ring_key));
    }
    let ring_dragging = ui.memory(|m| m.data.get_temp::<bool>(ring_key)).unwrap_or(false);
    let ring_fill = if ring_hot || ring_dragging { highlight.gamma_multiply(alpha) } else { col(214, 218, 224) };
    painter.add(egui::Shape::line(ring.clone(), Stroke::new(8.0, col(150, 156, 166))));
    painter.add(egui::Shape::line(ring, Stroke::new(6.0, ring_fill)));
    for (k, (label, d)) in letters.iter().enumerate() {
        let p = letter_pos(*d);
        let hl = hot_letter == Some(k);
        painter.circle_filled(p, 6.5, if hl { highlight.gamma_multiply(alpha) } else { col(236, 238, 241) });
        painter.circle_stroke(p, 6.5, Stroke::new(1.0, col(150, 156, 166)));
        painter.text(p, egui::Align2::CENTER_CENTER, *label, egui::FontId::proportional(8.5), col(50, 54, 60));
        if hl && clicked {
            // Look from that side, keeping the current tilt.
            let z = off.z.clamp(-0.98, 0.98);
            go = Some(if off.z.abs() > 0.999 { *d * 1e-4 + DVec3::Z * off.z.signum() } else { *d * (1.0 - z * z).sqrt() + DVec3::Z * z });
        }
    }

    // The cube.
    let light = DVec3::new(-0.3, -0.5, 0.8).normalize();
    for &k in &visible {
        let (n, label, u, v) = faces[k];
        let b = (0.9 + 0.1 * n.dot(light)) as f32;
        let base = col((238.0 * b) as u8, (240.0 * b) as u8, (243.0 * b) as u8);
        for i in -1..=1 {
            for j in -1..=1 {
                let q = cell(n, u, v, i, j);
                let d = n + u * i as f64 + v * j as f64;
                let lit = hot == Some(key(d));
                painter.add(egui::Shape::convex_polygon(q.to_vec(), if lit { highlight.gamma_multiply(alpha) } else { base }, Stroke::NONE));
                if lit && clicked {
                    go = Some(d);
                }
            }
        }
        let outline = [n - u - v, n + u - v, n + u + v, n - u + v].map(proj);
        painter.add(egui::Shape::closed_line(outline.to_vec(), Stroke::new(1.0, col(112, 118, 128))));
        // Label along the face's u axis.
        let pu = proj(n + u * 0.5) - proj(n - u * 0.5);
        if pu.length() > 6.0 {
            let angle = pu.y.atan2(pu.x);
            let galley = painter.layout_no_wrap(label.to_string(), egui::FontId::proportional(8.5), col(58, 62, 70));
            let c = proj(n);
            painter.add(egui::epaint::TextShape::new(c - galley.size() / 2.0, galley, col(58, 62, 70)).with_angle_and_anchor(angle, egui::Align2::CENTER_CENTER));
        }
    }

    // In a face view, arrows lead to the four neighbouring faces.
    if faces.iter().any(|f| off.dot(f.0) > 0.9995) {
        let fwd = -off;
        let right = fwd.cross(cam.up().as_dvec3()).normalize_or(DVec3::X);
        let up = right.cross(fwd);
        for (w, sv) in [(up, vec2(0.0, -1.0)), (-up, vec2(0.0, 1.0)), (right, vec2(1.0, 0.0)), (-right, vec2(-1.0, 0.0))] {
            let tip = center + sv * (s + 7.0);
            let bc = center + sv * (s + 16.0);
            let perp = vec2(-sv.y, sv.x) * 6.0;
            let tri = [tip, bc + perp, bc - perp];
            let lit = pointer.is_some_and(|p| point_in_tri(p, &tri));
            painter.add(egui::Shape::convex_polygon(tri.to_vec(), if lit { highlight.gamma_multiply(alpha) } else { col(214, 218, 224) }, Stroke::new(1.0, col(112, 118, 128))));
            if lit && clicked {
                go = Some(axis_of(w));
            }
        }
    }

    // Home.
    let home = Rect::from_center_size(area.left_top() + vec2(11.0, 10.0), vec2(18.0, 18.0));
    let home_hot = pointer.is_some_and(|p| home.contains(p));
    if active {
        if home_hot {
            painter.rect_filled(home, 2.0, style::hover());
        }
        crate::icons::paint(painter, home.shrink(1.0), crate::icons::Icon::Home, true);
    }
    if home_hot && clicked {
        go_home(app, ui, view_id);
        return;
    }
    let tip = if home_hot {
        Some("Home")
    } else if hot_letter.is_some() || ring_hot {
        Some("Click a letter to look from that side; drag the ring to turn the view")
    } else if hot.is_some() {
        Some("Click to orient the view; drag to orbit")
    } else {
        None
    };
    let cube_resp = match tip {
        Some(t) => cube_resp.on_hover_text(t),
        None => cube_resp,
    };
    if let Some(dir) = go {
        orient_to(app, ui, view_id, dir);
    }
    cube_resp.context_menu(|ui| {
        if ui.button("Go to Home").clicked() {
            go_home(app, ui, view_id);
            ui.close();
        }
        ui.separator();
        let persp = cam.perspective;
        for (label, want) in [("Orthographic", false), ("Perspective", true)] {
            if ui.radio(persp == want, label).clicked() {
                if persp != want {
                    app.run(label, |p| {
                        if let Some(ViewKind::ThreeD { perspective, .. }) = p.view_mut(view_id).map(|v| &mut v.kind) {
                            *perspective = want;
                        }
                        Ok(())
                    });
                }
                ui.close();
            }
        }
        ui.separator();
        if ui.button("Set Current View as Home").clicked() {
            let here = camera_of(app, view_id);
            app.home3d.insert(view_id, here);
            ui.close();
        }
        ui.menu_button("Orient to a Direction", |ui| {
            let dirs: [(&str, DVec3); 10] = [
                ("Top", DVec3::Z),
                ("Bottom", DVec3::NEG_Z),
                ("Front", DVec3::NEG_Y),
                ("Back", DVec3::Y),
                ("Left", DVec3::NEG_X),
                ("Right", DVec3::X),
                ("Southeast Isometric", DVec3::new(1.0, -1.0, 1.0)),
                ("Southwest Isometric", DVec3::new(-1.0, -1.0, 1.0)),
                ("Northeast Isometric", DVec3::new(1.0, 1.0, 1.0)),
                ("Northwest Isometric", DVec3::new(-1.0, 1.0, 1.0)),
            ];
            for (label, d) in dirs {
                if ui.button(label).clicked() {
                    orient_to(app, ui, view_id, d);
                    ui.close();
                }
            }
        });
        if ui.button("Zoom To Fit").clicked() {
            frame_all(app, view_id);
            ui.close();
        }
    });
}

/// Turns the view to look from `dir` (towards the model), framing the selection, the section
/// box or the model.
fn orient_to(app: &mut App, ui: &egui::Ui, view_id: Id, dir: DVec3) {
    let cam = camera_of(app, view_id);
    let mut d = dir.normalize_or(HOME_DIR);
    if d.z.abs() > 0.999 && DVec3::new(d.x, d.y, 0.0).length() < 1e-6 {
        // Straight down (or up) keeps north at the top of the screen.
        d = DVec3::new(0.0, -1e-4, d.z.signum()).normalize();
    }
    let b = selection_bounds(app, view_id).or_else(|| app.doc.data.view(view_id).and_then(|v| v.section_box)).or_else(|| app.model_bounds());
    animate_to(app, ui, view_id, render3d::frame_bounds(b, d, cam.perspective));
}

fn selection_bounds(app: &App, view_id: Id) -> Option<(DVec3, DVec3)> {
    let sel: HashSet<Id> = app.selection.iter().copied().collect();
    if sel.is_empty() {
        return None;
    }
    app.scenes.get(&view_id)?.meshes.iter().filter(|(id, _)| sel.contains(id)).filter_map(|(_, m)| m.bounds()).reduce(|(a0, a1), (b0, b1)| (a0.min(b0), a1.max(b1)))
}

/// The world axis nearest a direction.
fn axis_of(v: DVec3) -> DVec3 {
    let a = v.abs();
    if a.x >= a.y && a.x >= a.z {
        DVec3::X * v.x.signum()
    } else if a.y >= a.z {
        DVec3::Y * v.y.signum()
    } else {
        DVec3::Z * v.z.signum()
    }
}

fn seg_dist(p: Pos2, a: Pos2, b: Pos2) -> f32 {
    let ab = b - a;
    let t = ((p - a).dot(ab) / ab.length_sq().max(1e-6)).clamp(0.0, 1.0);
    p.distance(a + ab * t)
}

fn point_in_tri(p: Pos2, t: &[Pos2; 3]) -> bool {
    let side = |a: Pos2, b: Pos2| (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    let (d0, d1, d2) = (side(t[0], t[1]), side(t[1], t[2]), side(t[2], t[0]));
    (d0 >= 0.0 && d1 >= 0.0 && d2 >= 0.0) || (d0 <= 0.0 && d1 <= 0.0 && d2 <= 0.0)
}

fn point_in_quad(p: Pos2, q: &[Pos2; 4]) -> bool {
    let mut sign = 0.0f32;
    for k in 0..4 {
        let a = q[k];
        let b = q[(k + 1) % 4];
        let c = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
        if c.abs() < 1e-6 {
            continue;
        }
        if sign == 0.0 {
            sign = c.signum();
        } else if c.signum() != sign {
            return false;
        }
    }
    true
}

/// The Full Navigation Wheel: Zoom, Pan, Rewind, Orbit (outer) and Center, Look, Up/Down,
/// Walk (inner), driven by dragging from a wedge.
fn wheel_3d(app: &mut App, ui: &egui::Ui, resp: &egui::Response, rect: Rect, view_id: Id, cam: &mut Camera, clip: Option<(DVec3, DVec3)>) {
    use crate::wheel::{self, Wedge};
    let mut st = wheel::load(ui, view_id);
    let Some(p) = ui.input(|i| i.pointer.latest_pos()).filter(|p| rect.contains(*p)) else { return };
    // The wheel appears under the cursor once it has left the navigation bar.
    if st.center.is_none() && p.x > rect.right() - 60.0 {
        return;
    }
    let c = if st.drag.is_some() { st.center.unwrap_or(p) } else { wheel::follow(&mut st, p) };
    let pressed = resp.drag_started_by(egui::PointerButton::Primary) || (resp.clicked_by(egui::PointerButton::Primary) && st.drag.is_none());
    if pressed {
        let press = ui.input(|i| i.pointer.press_origin()).unwrap_or(p);
        if wheel::on_close(c, press) {
            wheel::store(ui, view_id, Default::default());
            return;
        }
        st.drag = wheel::wedge_at(true, c, press);
        st.accum = 0.0;
        if st.drag.is_some() && st.drag != Some(Wedge::Rewind) {
            let h = app.cam3d_history.entry(view_id).or_default();
            h.push(*cam);
            if h.len() > 50 {
                h.remove(0);
            }
        }
    }
    let dist = (cam.target - cam.eye).length().max(1.0);
    if resp.dragged_by(egui::PointerButton::Primary) {
        let d = resp.drag_delta();
        match st.drag {
            Some(Wedge::Zoom) => {
                let f = (d.y as f64 * 0.01).exp();
                cam.eye = cam.target + (cam.eye - cam.target) * f;
                cam.ortho_height *= f;
            }
            Some(Wedge::Pan) => {
                pan(cam, d, rect);
                st.center = Some(c + d);
            }
            Some(Wedge::Orbit) => orbit(cam, d.x, d.y),
            Some(Wedge::Look) => {
                // Turn the view direction around the eye.
                let off = cam.target - cam.eye;
                let r = off.length();
                let mut yaw = off.y.atan2(off.x);
                let mut pitch = (off.z / r).clamp(-1.0, 1.0).asin();
                yaw -= d.x as f64 * 0.005;
                pitch = (pitch - d.y as f64 * 0.005).clamp(-1.5, 1.5);
                cam.target = cam.eye + DVec3::new(yaw.cos() * pitch.cos(), yaw.sin() * pitch.cos(), pitch.sin()) * r;
            }
            Some(Wedge::Walk) => {
                let f = (cam.target - cam.eye) * DVec3::new(1.0, 1.0, 0.0);
                let step = f.normalize_or_zero() * (-d.y as f64 * dist * 0.004);
                cam.eye += step;
                cam.target += step;
            }
            Some(Wedge::UpDown) => {
                let step = DVec3::Z * (-d.y as f64 * dist * 0.004);
                cam.eye += step;
                cam.target += step;
            }
            Some(Wedge::Rewind) => {
                st.accum += d.x;
                if st.accum < -40.0 {
                    if let Some(prev) = app.cam3d_history.get_mut(&view_id).and_then(|h| h.pop()) {
                        *cam = prev;
                    }
                    st.accum = 0.0;
                }
            }
            _ => {}
        }
    }
    // Center: a click on the model makes the point under the wheel the pivot.
    if resp.clicked_by(egui::PointerButton::Primary) && st.drag == Some(Wedge::Center) {
        let aspect = rect.width() / rect.height().max(1.0);
        let nx = ((c.x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
        let ny = (1.0 - (c.y - rect.top()) / rect.height() * 2.0) as f64;
        let (o, dir) = cam.ray(nx, ny, aspect);
        if let Some((_, hit)) = app.scenes.get(&view_id).and_then(|s| render3d::pick(s, o, dir, clip)) {
            let off = cam.eye - cam.target;
            cam.target = hit;
            cam.eye = hit + off;
        }
    }
    if resp.drag_stopped() || ui.input(|i| i.pointer.any_released()) {
        st.drag = None;
    }
    wheel::store(ui, view_id, st);
}

fn nav_bar(app: &mut App, ui: &mut egui::Ui, area: Rect, view_id: Id, mode: NavMode) {
    // Same slim bar as the 2D views: the navigation wheel (orbit with the left button) and the
    // zoom button with its menu.
    let area = Rect::from_min_size(area.min + vec2(4.0, 0.0), vec2(26.0, 62.0));
    let painter = ui.painter();
    painter.rect_filled(area, 3.0, Color32::from_rgba_unmultiplied(244, 246, 248, 235));
    painter.rect_stroke(area, 3.0, Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    let r = Rect::from_min_size(area.min + vec2(2.0, 3.0), vec2(22.0, 22.0));
    let resp = ui.interact(r, egui::Id::new(("navbar-wheel", view_id)), Sense::click());
    let orbiting = crate::wheel::load(ui, view_id).on;
    if orbiting {
        ui.painter().rect_filled(r, 2.0, style::accent_light());
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 2.0, style::hover());
    }
    let c = r.center();
    ui.painter().circle_stroke(c, 8.0, Stroke::new(2.2, Color32::from_rgb(120, 126, 136)));
    ui.painter().circle_stroke(c, 8.0, Stroke::new(1.0, Color32::from_rgb(70, 76, 86)));
    ui.painter().circle_filled(c, 2.5, Color32::from_rgb(40, 90, 170));
    if resp.clicked() {
        crate::wheel::store(ui, view_id, crate::wheel::WheelState { on: !orbiting, ..Default::default() });
    }
    resp.on_hover_text("Full Navigation Wheel (Esc closes). Shift+middle drag orbits at any time.");
    let sep_y = area.top() + 30.0;
    ui.painter().line_segment([pos2(area.left() + 4.0, sep_y), pos2(area.right() - 4.0, sep_y)], Stroke::new(1.0, style::border()));
    let r = Rect::from_min_size(pos2(area.left() + 2.0, sep_y + 2.0), vec2(22.0, 28.0));
    let resp = ui.interact(r, egui::Id::new(("navbar-zoom", view_id)), Sense::click());
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
            frame_all(app, view_id);
        }
        None
    };
    let resp = resp.on_hover_text("Zoom To Fit (arrow: navigation modes)");
    egui::Popup::menu(&resp).open_memory(toggle).close_behavior(egui::PopupCloseBehavior::CloseOnClick).show(|ui| {
        ui.set_min_width(160.0);
        if ui.button("Zoom To Fit").clicked() {
            frame_all(app, view_id);
        }
        ui.separator();
        for (label, m) in [("Orbit (left drag)", NavMode::Orbit), ("Pan (left drag)", NavMode::Pan), ("Select (left drag = window)", NavMode::Select)] {
            if ui.selectable_label(mode == m, label).clicked() {
                set_nav_mode(ui, view_id, m);
            }
        }
    });
}

/// Renders a 3D view off-screen at the given pixel size (sheets, PDF, image export).
/// View > Render: the 3D view in the Realistic style with sun shadows over a sky background.
pub fn render_realistic(app: &mut App, view_id: Id, w: u32, h: u32) -> Option<rc_core::pdf::Image> {
    let view = app.doc.data.view(view_id)?.clone();
    if !matches!(view.kind, ViewKind::ThreeD { .. }) {
        return None;
    }
    let cam = camera_of(app, view_id);
    ensure_scene(app, view_id);
    let sun = render3d::sun_direction(app.doc.data.sun.azimuth + app.doc.data.true_north, app.doc.data.sun.altitude);
    let set = DrawSettings { style: VisualStyle::Realistic, shadows: true, sun, section_box: view.section_box, background: [0.74, 0.84, 0.95] };
    let scene = app.scenes.get(&view_id)?;
    let renderer = app.renderer.as_ref()?;
    Some(renderer.render_to_rgb(scene, &cam, &set, w, h))
}

pub fn render_image(app: &mut App, view_id: Id, w: u32, h: u32) -> Option<rc_core::pdf::Image> {
    let view = app.doc.data.view(view_id)?.clone();
    if !matches!(view.kind, ViewKind::ThreeD { .. }) {
        return None;
    }
    let cam = camera_of(app, view_id);
    ensure_scene(app, view_id);
    let sun = render3d::sun_direction(app.doc.data.sun.azimuth + app.doc.data.true_north, app.doc.data.sun.altitude);
    let set = DrawSettings { style: view.style, shadows: view.shadows, sun, section_box: view.section_box, background: [1.0, 1.0, 1.0] };
    let scene = app.scenes.get(&view_id)?;
    let renderer = app.renderer.as_ref()?;
    Some(renderer.render_to_rgb(scene, &cam, &set, w, h))
}
