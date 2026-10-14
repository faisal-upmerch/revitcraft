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
const DEFAULT_EYES: [DVec3; 2] = [DVec3::new(-12000.0, -16000.0, 12000.0), DVec3::new(15000.0, -15000.0, 16500.0)];

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
            meshes.push((e.id, set));
        }
    }
    let mut scene = renderer.upload(p, meshes, &HashSet::new(), key, &halftone);
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
        _ => render3d::frame_bounds(None, DVec3::new(-0.6, -0.9, 0.55), false),
    };
    app.cams3d.insert(view_id, cam);
    cam
}

pub fn frame_all(app: &mut App, view_id: Id) {
    let cam = camera_of(app, view_id);
    let dir = (cam.eye - cam.target).normalize_or(DVec3::new(-0.6, -0.9, 0.55));
    let b = app.doc.data.view(view_id).and_then(|v| v.section_box).or_else(|| app.model_bounds());
    let framed = render3d::frame_bounds(b, dir, cam.perspective);
    app.cams3d.insert(view_id, framed);
}

fn orbit(cam: &mut Camera, dx: f32, dy: f32) {
    let offset = cam.eye - cam.target;
    let r = offset.length();
    let mut yaw = offset.y.atan2(offset.x);
    let mut pitch = (offset.z / r).clamp(-1.0, 1.0).asin();
    yaw -= dx as f64 * 0.008;
    pitch = (pitch + dy as f64 * 0.008).clamp(-1.55, 1.55);
    cam.eye = cam.target + DVec3::new(yaw.cos() * pitch.cos(), yaw.sin() * pitch.cos(), pitch.sin()) * r;
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

    // Navigation.
    let mut moved = false;
    let wheel_on = crate::wheel::load(ui, view_id).on;
    let left_drag = resp.dragged_by(egui::PointerButton::Primary) && !wheel_on;
    let section_drag: Option<(usize, Pos2)> = ui.memory(|m| m.data.get_temp(egui::Id::new(("sbox-drag", view_id))));
    if left_drag && section_drag.is_none() && (drag_from_cube || shift || mode == NavMode::Orbit) {
        let d = resp.drag_delta();
        orbit(&mut cam, d.x, d.y);
        moved = true;
    } else if left_drag && section_drag.is_none() && mode == NavMode::Pan {
        pan(&mut cam, resp.drag_delta(), rect);
        moved = true;
    }
    if resp.dragged_by(egui::PointerButton::Middle) {
        let d = resp.drag_delta();
        if shift {
            orbit(&mut cam, d.x, d.y);
        } else {
            pan(&mut cam, d, rect);
        }
        moved = true;
    }
    if resp.dragged_by(egui::PointerButton::Secondary) {
        pan(&mut cam, resp.drag_delta(), rect);
        moved = true;
    }
    if resp.hovered() {
        let scroll = ui.input(|i| i.smooth_scroll_delta.y) as f64;
        let zoom = ui.input(|i| i.zoom_delta()) as f64;
        let f = (-scroll * 0.0022).exp() / zoom;
        if (f - 1.0).abs() > 1e-6 {
            // Zoom towards the cursor.
            if let Some(hp) = resp.hover_pos() {
                let aspect = rect.width() / rect.height().max(1.0);
                let nx = ((hp.x - rect.left()) / rect.width() * 2.0 - 1.0) as f64;
                let ny = (1.0 - (hp.y - rect.top()) / rect.height() * 2.0) as f64;
                let (o, d) = cam.ray(nx, ny, aspect);
                let dist = (cam.target - cam.eye).length();
                let toward = o + d * dist;
                let k = 1.0 - f.clamp(0.2, 5.0);
                cam.target += (toward - cam.target) * k * if cam.perspective { 0.6 } else { 1.0 };
                cam.eye += (toward - cam.eye) * k * if cam.perspective { 0.6 } else { 0.0 };
                if !cam.perspective {
                    cam.ortho_height *= f.clamp(0.2, 5.0);
                }
            }
            moved = true;
        }
    }
    let _ = moved;
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
            if resp.clicked_by(egui::PointerButton::Primary) && section_drag.is_none() {
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
        if mode == NavMode::Select && !shift && !drag_from_cube && section_drag.is_none() {
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
        if ui.button("Orient to View... (Home)").clicked() {
            go_home(app, view_id);
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

fn go_home(app: &mut App, view_id: Id) {
    let cam = camera_of(app, view_id);
    let b = app.model_bounds();
    let framed = render3d::frame_bounds(b, DVec3::new(-0.6, -0.9, 0.55), cam.perspective);
    app.cams3d.insert(view_id, framed);
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

fn view_cube(app: &mut App, ui: &egui::Ui, painter: &egui::Painter, area: Rect, view_id: Id) {
    let cam = camera_of(app, view_id);
    let view_m = cam.view_matrix();
    let rot = |v: DVec3| -> Vec3 { view_m.transform_vector3(v.as_vec3()) };
    let center = area.center() + vec2(0.0, -6.0);
    let s = 26.0f32;
    let proj = |v: DVec3| -> Pos2 {
        let r = rot(v);
        center + vec2(r.x, -r.y) * s
    };
    let pointer = ui.input(|i| i.pointer.hover_pos());
    let clicked = ui.input(|i| i.pointer.primary_released()) && ui.input(|i| i.pointer.press_origin()).is_some_and(|p| area.contains(p)) && ui.input(|i| i.pointer.total_drag_delta().map(|d| d.length() < 3.0).unwrap_or(true));
    // Compass ring.
    let ring_c = center + vec2(0.0, 30.0);
    let mut ring: Vec<Pos2> = Vec::new();
    for k in 0..=48 {
        let a = k as f64 / 48.0 * std::f64::consts::TAU;
        ring.push(proj(DVec3::new(a.cos() * 1.9, a.sin() * 1.9, -1.0)));
    }
    painter.add(egui::Shape::line(ring, Stroke::new(5.0, Color32::from_rgba_unmultiplied(160, 166, 176, 120))));
    for (label, d) in [("N", DVec3::Y), ("E", DVec3::X), ("S", DVec3::NEG_Y), ("W", DVec3::NEG_X)] {
        let p = proj(d * 1.9 + DVec3::new(0.0, 0.0, -1.0));
        painter.text(p, egui::Align2::CENTER_CENTER, label, egui::FontId::proportional(10.0), style::text_dim());
    }
    let _ = ring_c;
    // Faces: (normal, label, u, v) with u/v the face's in-plane axes.
    let faces: [(DVec3, &str, DVec3, DVec3); 6] = [
        (DVec3::Z, "TOP", DVec3::X, DVec3::Y),
        (DVec3::NEG_Z, "BOTTOM", DVec3::X, DVec3::NEG_Y),
        (DVec3::NEG_Y, "FRONT", DVec3::X, DVec3::Z),
        (DVec3::Y, "BACK", DVec3::NEG_X, DVec3::Z),
        (DVec3::X, "RIGHT", DVec3::Y, DVec3::Z),
        (DVec3::NEG_X, "LEFT", DVec3::NEG_Y, DVec3::Z),
    ];
    let mut order: Vec<usize> = (0..6).collect();
    order.sort_by(|a, b| rot(faces[*a].0).z.total_cmp(&rot(faces[*b].0).z));
    let mut target_dir: Option<DVec3> = None;
    for k in order {
        let (n, label, u, v) = faces[k];
        if rot(n).z <= 0.02 {
            continue;
        }
        // 3x3 grid on each face: centre = face, edges and corners = combined directions.
        for i in -1..=1 {
            for j in -1..=1 {
                let (a0, a1) = (i as f64 / 1.5 - 1.0 / 3.0, i as f64 / 1.5 + 1.0 / 3.0);
                let (b0, b1) = (j as f64 / 1.5 - 1.0 / 3.0, j as f64 / 1.5 + 1.0 / 3.0);
                let quad = [n + u * a0 + v * b0, n + u * a1 + v * b0, n + u * a1 + v * b1, n + u * a0 + v * b1].map(proj);
                let hovered = pointer.is_some_and(|p| point_in_quad(p, &quad));
                let base = if i == 0 && j == 0 { Color32::from_rgb(236, 238, 242) } else { Color32::from_rgb(222, 225, 231) };
                let fill = if hovered { Color32::from_rgb(150, 200, 250) } else { base };
                painter.add(egui::Shape::convex_polygon(quad.to_vec(), fill, Stroke::NONE));
                if hovered && clicked {
                    target_dir = Some((n + u * i as f64 + v * j as f64).normalize());
                }
            }
        }
        let outline = [n - u - v, n + u - v, n + u + v, n - u + v].map(proj);
        painter.add(egui::Shape::closed_line(outline.to_vec(), Stroke::new(1.0, Color32::from_rgb(120, 124, 132))));
        // Label oriented roughly along the face's u axis.
        let pu = proj(n + u * 0.5) - proj(n - u * 0.5);
        let angle = pu.y.atan2(pu.x);
        let font = egui::FontId::proportional(9.5);
        let galley = painter.layout_no_wrap(label.to_string(), font, Color32::from_rgb(60, 64, 72));
        let c = proj(n);
        let shape = egui::epaint::TextShape::new(c - galley.size() / 2.0, galley, Color32::from_rgb(60, 64, 72)).with_angle_and_anchor(angle, egui::Align2::CENTER_CENTER);
        painter.add(shape);
    }
    // Home button.
    let home = Rect::from_center_size(area.left_top() + vec2(12.0, 10.0), vec2(18.0, 18.0));
    let hovered_home = pointer.is_some_and(|p| home.contains(p));
    if hovered_home {
        painter.rect_filled(home, 2.0, style::hover());
    }
    crate::icons::paint(painter, home.shrink(1.0), crate::icons::Icon::Home, true);
    if hovered_home && clicked {
        go_home(app, view_id);
        return;
    }
    if let Some(dir) = target_dir {
        let dist = (cam.eye - cam.target).length();
        // Straight down needs a tiny tilt so "up" stays well defined.
        let d = if dir.z.abs() > 0.999 { DVec3::new(0.0, -0.0001, dir.z.signum()).normalize() } else { dir };
        app.cams3d.insert(view_id, Camera { eye: cam.target + d * dist, ..cam });
    }
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
