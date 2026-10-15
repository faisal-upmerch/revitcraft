//! Sheet views: title block, viewports (drag to move, Delete removes, double-click opens),
//! views dropped from the Project Browser are placed where they are released.

use crate::app::App;
use crate::browser::DragView;
use crate::canvas::{self, Cam2, Xf};
use crate::style;
use eframe::egui::{self, Color32, Pos2, Rect, Sense, Stroke, pos2};
use rc_core::geom::DVec2;
use rc_core::model::*;
use rc_core::plan::{Dash, Prim};
use rc_core::sheet::SheetPrim;

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let ViewKind::Sheet(sh) = &view.kind else { return };
    let (pw, ph) = sh.size.paper();
    let (rect, resp) = ui.allocate_exact_size(ui.available_size(), Sense::click_and_drag());
    if !app.cams.get(&view_id).is_some_and(|c| c.fitted) {
        let zoom = ((rect.width() as f64 - 40.0) / pw).min((rect.height() as f64 - 40.0) / ph).max(0.05);
        app.cams.insert(view_id, Cam2 { center: DVec2::new(pw / 2.0, ph / 2.0), zoom, fitted: true });
    }
    // Pan/zoom.
    let mut cam = app.cams[&view_id];
    if let Some(h) = resp.hover_pos() {
        let scroll = ui.input(|i| i.smooth_scroll_delta.y) as f64;
        let f = (scroll * 0.0028).exp() * ui.input(|i| i.zoom_delta()) as f64;
        if (f - 1.0).abs() > 1e-6 {
            let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 1.0, thin: false };
            let before = xf.w(h);
            cam.zoom = (cam.zoom * f).clamp(0.05, 60.0);
            let xf2 = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 1.0, thin: false };
            cam.center += before - xf2.w(h);
        }
    }
    if resp.dragged_by(egui::PointerButton::Middle) {
        let d = resp.drag_delta();
        cam.center += DVec2::new(-d.x as f64, d.y as f64) / cam.zoom;
    }
    app.cams.insert(view_id, cam);
    let xf = Xf { rect, center: cam.center, zoom: cam.zoom, scale: 1.0, thin: app.thin_lines };
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 0.0, style::canvas(app.settings.black_canvas));
    let paper = Rect::from_two_pos(xf.s(DVec2::ZERO), xf.s(DVec2::new(pw, ph)));
    // Like the reference app, the sheet sits on the plain view background (no paper shadow).
    painter.rect_filled(paper, 0.0, Color32::WHITE);

    let _fp = app.footprints();
    let layout = app.sheet_layout(view_id);
    for prim in &layout.0 {
        match prim {
            SheetPrim::Line { pts, closed, width, color, dashed } => {
                let v: Vec<Pos2> = pts.iter().map(|q| xf.s(*q)).collect();
                canvas::paint_polyline(&painter, &v, *closed, Stroke::new((*width * 4.5).clamp(1.0, 3.0), Color32::from_rgb(color[0], color[1], color[2])), if *dashed { Dash::Dashed } else { Dash::Solid }, &xf);
            }
            SheetPrim::Fill { tris, color } => {
                let mut mesh = egui::Mesh::default();
                let c = Color32::from_rgba_unmultiplied(color[0], color[1], color[2], color[3]);
                for t in tris {
                    let i = mesh.vertices.len() as u32;
                    for q in t {
                        mesh.colored_vertex(xf.s(*q), c);
                    }
                    mesh.add_triangle(i, i + 1, i + 2);
                }
                painter.add(egui::Shape::mesh(mesh));
            }
            SheetPrim::Text { pos, text, size, anchor, angle, bold } => {
                let h = (*size as f64 * xf.zoom) as f32;
                let t = if *bold { text.clone() } else { text.clone() };
                canvas::paint_text(&painter, xf.s(*pos), &t, h, Color32::BLACK, *anchor, *angle);
            }
            SheetPrim::Image { view: v3, min, max } => {
                let r = Rect::from_two_pos(xf.s(*min), xf.s(*max));
                let ppp = ui.ctx().pixels_per_point();
                let size = [(r.width() * ppp).max(8.0) as u32, (r.height() * ppp).max(8.0) as u32];
                if crate::view3d::ensure_scene(app, *v3) {
                    let cam = crate::view3d::camera_of(app, *v3);
                    let cam = crate::render3d::Camera { perspective: cam.perspective, ..cam };
                    let style = app.doc.data.view(*v3).map(|v| v.style).unwrap_or_default();
                    let sb = app.doc.data.view(*v3).and_then(|v| v.section_box);
                    let shadows = app.doc.data.view(*v3).is_some_and(|v| v.shadows);
                    let sun = crate::render3d::sun_direction(app.doc.data.sun.azimuth, app.doc.data.sun.altitude);
                    let set = crate::render3d::DrawSettings { style, shadows, sun, section_box: sb, background: [1.0, 1.0, 1.0] };
                    let key = v3 ^ 0x4000_0000 ^ view_id.rotate_left(8);
                    if let (Some(scene), Some(renderer)) = (app.scenes.get(v3), app.renderer.as_mut()) {
                        let tex = renderer.render_view(key, size, scene, &cam, &set);
                        painter.image(tex, r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                    }
                }
            }
        }
    }
    let _ = Prim::Text { pos: DVec2::ZERO, text: String::new(), size: 0.0, color: [0; 3], anchor: rc_core::plan::Anchor::Center, angle: 0.0 };

    if app.active_tab() != Some(view_id) {
        return;
    }
    let boxes = layout.1.clone();
    // Guide grid: light lines over the paper, not printed.
    if let Some(g) = sh.guide_grid.filter(|g| *g >= 5.0) {
        let gc = Color32::from_rgba_unmultiplied(70, 140, 230, 110);
        let mut x = g;
        while x < pw {
            painter.line_segment([xf.s(DVec2::new(x, 0.0)), xf.s(DVec2::new(x, ph))], Stroke::new(1.0, gc));
            x += g;
        }
        let mut y = g;
        while y < ph {
            painter.line_segment([xf.s(DVec2::new(0.0, y)), xf.s(DVec2::new(pw, y))], Stroke::new(1.0, gc));
            y += g;
        }
    }
    // A viewport activated in place: the sheet greys out and the view is edited through it.
    if let Some((s, v)) = app.sheet_activation {
        if s == view_id {
            if let Some(b) = boxes.iter().find(|b| b.view == v).cloned() {
                painter.rect_filled(paper, 0.0, Color32::from_rgba_unmultiplied(255, 255, 255, 150));
                let vr = Rect::from_two_pos(xf.s(b.min), xf.s(b.max)).intersect(rect);
                let mut child = ui.new_child(egui::UiBuilder::new().max_rect(vr).layout(egui::Layout::top_down(egui::Align::Min)));
                if app.doc.data.view(v).is_some_and(|x| matches!(x.kind, ViewKind::ThreeD { .. })) {
                    // A 3D viewport navigates in place (orbit, pan, zoom) like the 3D view.
                    crate::view3d::show(app, &mut child, v);
                } else {
                    let scale = app.doc.data.view(v).map(|x| x.scale).unwrap_or(100.0);
                    let d = app.drawing(v);
                    let wc = d.bounds().map(|(a, c)| (a + c) / 2.0).unwrap_or(DVec2::ZERO);
                    let mid = xf.w(vr.center());
                    let c = (b.min + b.max) / 2.0;
                    app.cams.insert(v, Cam2 { center: wc + (mid - c) * scale, zoom: xf.zoom / scale, fitted: true });
                    canvas::show(app, &mut child, v);
                }
                painter.rect_stroke(Rect::from_two_pos(xf.s(b.min), xf.s(b.max)), 0.0, Stroke::new(2.0, style::ACCENT), egui::StrokeKind::Outside);
                let outside = resp.hover_pos().is_some_and(|h| !vr.contains(h));
                if resp.double_clicked() && outside {
                    app.deactivate_viewport();
                }
                if app.sheet_activation.is_some() {
                    app.interact.prompt = format!("{}   (double-click outside the viewport to deactivate the view)", app.interact.prompt);
                }
                return;
            }
            app.sheet_activation = None;
        }
    }
    // Annotation on the sheet: tools draw at paper scale, clicks select it.
    let cursor = resp.hover_pos().map(|s| xf.w(s));
    let notes = rc_core::sheet::sheet_annotations(&app.doc.data, &view, &app.footprints());
    let note_sel: std::collections::HashSet<Id> = app.selection.iter().copied().filter(|id| app.el(*id).is_some_and(|e| e.view == Some(view_id))).collect();
    if !note_sel.is_empty() {
        let hl: Vec<(Option<Id>, Prim)> = notes.prims.iter().filter(|(id, _)| id.is_some_and(|i| note_sel.contains(&i))).cloned().collect();
        canvas::paint_prims(&painter, &hl, &xf, &|_, _| Some(style::SELECT));
    }
    // Move with viewports selected moves the viewports.
    let vp_sel: Vec<Id> = app.selection.iter().copied().filter(|id| sh.viewports.iter().any(|vp| vp.view == *id)).collect();
    if app.tool.kind == crate::tools::ToolKind::Move && !vp_sel.is_empty() {
        app.interact.prompt = if app.tool.pts.is_empty() { "Click to enter move start point.".into() } else { "Click to enter move end point.".into() };
        if let (Some(a), Some(c)) = (app.tool.pts.first().copied(), cursor) {
            painter.line_segment([xf.s(a), xf.s(c)], Stroke::new(1.5, style::PREVIEW));
        }
        if resp.clicked_by(egui::PointerButton::Primary) {
            if let Some(c) = cursor {
                match app.tool.pts.first().copied() {
                    None => app.tool.pts.push(c),
                    Some(a) => {
                        let d = c - a;
                        app.run("Move Viewport", |p| {
                            if let Some(ViewKind::Sheet(s)) = p.view_mut(view_id).map(|v| &mut v.kind) {
                                for vp in s.viewports.iter_mut().filter(|vp| vp_sel.contains(&vp.view)) {
                                    vp.cx += d.x;
                                    vp.cy += d.y;
                                }
                            }
                            Ok(())
                        });
                        app.set_tool(crate::tools::ToolKind::Select);
                        app.select(vp_sel);
                    }
                }
            }
        }
        return;
    }
    if !app.tool.is_select() || app.sketch.is_some() {
        let mut sv = view.clone();
        sv.scale = 1.0;
        app.interact.prompt = crate::canvas_tools::prompt(app);
        let clicked = resp.clicked_by(egui::PointerButton::Primary);
        crate::canvas_tools::handle(app, ui, &resp, &painter, &xf, &sv, &notes, cursor, cursor, clicked);
        if let Some(sk) = app.sketch.as_ref() {
            for s in &sk.segs {
                let pts: Vec<Pos2> = s.points().iter().map(|q| xf.s(*q)).collect();
                painter.add(egui::Shape::line(pts, Stroke::new(2.0, style::SKETCH)));
            }
        }
        return;
    }
    if resp.clicked_by(egui::PointerButton::Primary) {
        if let Some(id) = cursor.and_then(|c| rc_core::section::pick(&notes, c, 4.0 / xf.zoom)) {
            let ctrl = ui.input(|i| i.modifiers.ctrl);
            let mut s = if ctrl { app.selection.clone() } else { vec![] };
            if !s.contains(&id) {
                s.push(id);
            }
            app.select(s);
            return;
        }
    }
    // Viewport selection and moves.
    let hover = cursor.and_then(|c| boxes.iter().find(|b| c.x >= b.min.x && c.x <= b.max.x && c.y >= b.min.y && c.y <= b.max.y)).map(|b| b.view);
    let sel_vp: Option<Id> = app.selection.iter().copied().find(|id| sh.viewports.iter().any(|vp| vp.view == *id));
    for b in &boxes {
        let r = Rect::from_two_pos(xf.s(b.min), xf.s(b.max));
        if Some(b.view) == sel_vp {
            painter.rect_stroke(r, 0.0, Stroke::new(2.0, style::SELECT), egui::StrokeKind::Middle);
        } else if Some(b.view) == hover {
            painter.rect_stroke(r, 0.0, Stroke::new(1.5, style::PRESELECT), egui::StrokeKind::Middle);
        }
    }
    app.interact.prompt = match hover {
        Some(v) => format!("Viewport: {} - drag to move, double-click to activate the view, Delete removes it from the sheet.", app.doc.data.view(v).map(|v| v.name.clone()).unwrap_or_default()),
        None => "Drag views from the Project Browser onto the sheet to place them.".into(),
    };
    let drag_id = egui::Id::new(("vp-drag", view_id));
    if resp.drag_started_by(egui::PointerButton::Primary) {
        if let Some(h) = ui.input(|i| i.pointer.press_origin()).map(|s| xf.w(s)).and_then(|c| boxes.iter().find(|b| c.x >= b.min.x && c.x <= b.max.x && c.y >= b.min.y && c.y <= b.max.y)).map(|b| b.view) {
            app.select(vec![h]);
            ui.memory_mut(|m| m.data.insert_temp(drag_id, h));
        }
    }
    let dragging: Option<Id> = ui.memory(|m| m.data.get_temp(drag_id));
    if let Some(vid) = dragging {
        let total = ui.input(|i| i.pointer.total_drag_delta()).unwrap_or_default();
        let mut d = DVec2::new(total.x as f64, -total.y as f64) / xf.zoom;
        // Viewport edges and centre snap to the guide grid.
        if let (Some(g), Some(b)) = (sh.guide_grid.filter(|g| *g >= 5.0), boxes.iter().find(|b| b.view == vid)) {
            let tol = 8.0 / xf.zoom;
            for axis in 0..2 {
                let get = |q: DVec2| if axis == 0 { q.x } else { q.y };
                let cands = [get(b.min), get((b.min + b.max) / 2.0), get(b.max)];
                let shift = cands
                    .iter()
                    .map(|v| {
                        let moved = v + get(d);
                        (moved / g).round() * g - moved
                    })
                    .min_by(|a, c| a.abs().total_cmp(&c.abs()))
                    .unwrap_or(0.0);
                if shift.abs() < tol {
                    if axis == 0 {
                        d.x += shift;
                    } else {
                        d.y += shift;
                    }
                }
            }
        }
        if let Some(b) = boxes.iter().find(|b| b.view == vid) {
            let r = Rect::from_two_pos(xf.s(b.min + d), xf.s(b.max + d));
            painter.rect_stroke(r, 0.0, Stroke::new(1.5, style::PREVIEW), egui::StrokeKind::Middle);
        }
        if resp.drag_stopped() {
            ui.memory_mut(|m| m.data.remove::<Id>(drag_id));
            app.run("Move Viewport", |p| {
                if let Some(ViewKind::Sheet(s)) = p.view_mut(view_id).map(|v| &mut v.kind) {
                    if let Some(vp) = s.viewports.iter_mut().find(|vp| vp.view == vid) {
                        vp.cx += d.x;
                        vp.cy += d.y;
                    }
                }
                Ok(())
            });
        }
    } else if resp.clicked_by(egui::PointerButton::Primary) {
        match hover {
            Some(v) => app.select(vec![v]),
            None => app.select(vec![]),
        }
    }
    if resp.double_clicked() {
        if let Some(v) = hover {
            // Schedules open in their own view; plans, sections, details and 3D views activate in place.
            let in_place = app.doc.data.view(v).is_some_and(|x| x.is_graphical());
            if in_place {
                app.activate_viewport(view_id, v);
            } else {
                app.open_view(v);
            }
        }
    }
    // Drops from the browser.
    if let Some(payload) = resp.dnd_release_payload::<DragView>() {
        if let Some(c) = cursor {
            let v = payload.0;
            app.run("Place View", |p| rc_core::edit::place_on_sheet(p, view_id, v, c.x, c.y));
        }
    } else if egui::DragAndDrop::has_payload_of_type::<DragView>(ui.ctx()) && resp.hovered() {
        painter.rect_stroke(paper, 0.0, Stroke::new(2.0, style::ACCENT), egui::StrokeKind::Outside);
    }
}
