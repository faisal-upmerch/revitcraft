//! Temporary dimensions shown for a single selected element. Clicking the value lets you type
//! a new distance; the element moves to satisfy it.

use crate::app::App;
use crate::canvas::{self, Xf};
use crate::grips;
use eframe::egui;
use rc_core::analysis;
use rc_core::geom::{self, DVec2};
use rc_core::model::*;

#[derive(Clone, Debug)]
pub struct TempDim {
    /// Fixed reference point.
    pub a: DVec2,
    /// Point on the selected element.
    pub b: DVec2,
    pub value: f64,
    pub offset_px: f32,
}

/// Straight parallel references (walls, grids, reference planes, lines) on the view.
fn parallel_refs(p: &Project, level: Option<Id>, skip: Id, dir: DVec2) -> Vec<(DVec2, DVec2)> {
    let mut out = Vec::new();
    for e in &p.elements {
        if e.id == skip {
            continue;
        }
        let seg = match &e.kind {
            ElementKind::Wall(w) if level.is_none_or(|l| w.base_level == l) && w.arc_mid.is_none() => Some((w.start, w.end)),
            ElementKind::Grid(g) if g.arc_mid.is_none() => Some((g.start, g.end)),
            ElementKind::RefPlane(r) => Some((r.start, r.end)),
            _ => None,
        };
        if let Some((a, b)) = seg {
            let d = (b - a).normalize_or_zero();
            if d.dot(dir).abs() > 0.9998 {
                out.push((a, b));
            }
        }
    }
    out
}

/// Nearest parallel reference on each side of `pt` along normal `n`: (reference foot, distance).
fn nearest_each_side(refs: &[(DVec2, DVec2)], pt: DVec2, n: DVec2, max: f64) -> Vec<(DVec2, f64)> {
    let mut pos: Option<(DVec2, f64)> = None;
    let mut neg: Option<(DVec2, f64)> = None;
    for (a, b) in refs {
        let d = (*b - *a).normalize_or_zero();
        let foot = *a + d * (pt - *a).dot(d);
        let s = (foot - pt).dot(n);
        if s.abs() < 1.0 || s.abs() > max {
            continue;
        }
        if s > 0.0 {
            if pos.is_none_or(|x| s < x.1) {
                pos = Some((foot, s));
            }
        } else if neg.is_none_or(|x| -s < x.1) {
            neg = Some((foot, -s));
        }
    }
    pos.into_iter().chain(neg).collect()
}

/// Nearest wall centreline hit from `pt` along `dir`.
fn ray_hit(p: &Project, level: Id, skip: Id, pt: DVec2, dir: DVec2, max: f64) -> Option<(DVec2, f64)> {
    let mut best: Option<(DVec2, f64)> = None;
    let far = pt + dir * max;
    for e in &p.elements {
        if e.id == skip {
            continue;
        }
        let (a, b) = match &e.kind {
            ElementKind::Wall(w) if w.base_level == level && w.arc_mid.is_none() => (w.start, w.end),
            ElementKind::Grid(g) if g.arc_mid.is_none() => (g.start, g.end),
            _ => continue,
        };
        if let Some((t, u)) = geom::segment_intersection(pt, far, a, b) {
            if t > 1e-6 && (0.0..=1.0).contains(&u) && (0.0..=1.0).contains(&t) {
                let d = t * max;
                if best.is_none_or(|x| d < x.1) {
                    best = Some((pt + dir * d, d));
                }
            }
        }
    }
    best
}

/// A door or window being dragged along its host: (id, position along the host, delta along
/// the host). The reference app slides hosted openings along their wall, kept inside it.
pub fn hosted_drag(app: &App) -> Option<(Id, f64, DVec2)> {
    let Some(crate::canvas::Drag::Move { start, ids }) = &app.interact.drag else { return None };
    let pt = app.interact.point?;
    if ids.len() != 1 {
        return None;
    }
    let p = &app.doc.data;
    let i = p.element(ids[0])?.as_instance()?;
    let w = p.wall(i.host?)?;
    let (_, dir) = analysis::wall_point(w, i.offset_along_host);
    let hw = analysis::opening_size(p, i).0 / 2.0;
    let len = w.length();
    let along = (i.offset_along_host + (pt - *start).dot(dir)).clamp(hw.min(len / 2.0), (len - hw).max(len / 2.0));
    let (a, _) = analysis::wall_point(w, i.offset_along_host);
    let (b, _) = analysis::wall_point(w, along);
    Some((ids[0], along, b - a))
}

/// The reference app's temporary dimensions of a door or window: from each edge of the
/// opening to the nearest reference on that side along the host (the face of a wall that
/// meets or crosses it, another opening, or the wall end), both on the exterior side.
pub fn hosted_dims(p: &Project, id: Id, i: &FamilyInstance, w: &Wall, along: f64) -> Vec<TempDim> {
    hosted_dims_on(p, id, i, w, along, w.normal())
}

/// [`hosted_dims`] drawn on the side of the wall that `side` points to.
pub fn hosted_dims_on(p: &Project, id: Id, i: &FamilyInstance, w: &Wall, along: f64, side: DVec2) -> Vec<TempDim> {
    let len = w.length();
    let hw = analysis::opening_size(p, i).0 / 2.0;
    let (ul, ur) = (along - hw, along + hw);
    let mut refs: Vec<f64> = vec![0.0, len];
    let dir = w.direction();
    for (e, o) in p.walls() {
        if Some(e.id) == i.host || o.base_level != w.base_level || o.arc_mid.is_some() || o.length() < 1.0 {
            continue;
        }
        let od = o.direction();
        let s = geom::cross2(dir, od).abs();
        if s < 0.05 {
            continue;
        }
        let Some(x) = geom::line_intersection(w.start, dir, o.start, od) else { continue };
        let (q, _) = geom::closest_on_segment(o.start, o.end, x);
        let t = (x - w.start).dot(dir);
        if q.distance(x) > analysis::JOIN_TOLERANCE || t < -analysis::wall_thickness(p, w) || t > len + analysis::wall_thickness(p, w) {
            continue;
        }
        let ht = analysis::wall_thickness(p, o) / 2.0 / s;
        refs.push(t - ht);
        refs.push(t + ht);
    }
    for (e2, i2) in p.hosted_by(i.host.unwrap_or_default()) {
        if e2.id != id {
            let h2 = analysis::opening_size(p, i2).0 / 2.0;
            refs.push(i2.offset_along_host - h2);
            refs.push(i2.offset_along_host + h2);
        }
    }
    let left = refs.iter().copied().filter(|r| *r <= ul - 1.0).fold(None, |m: Option<f64>, r| Some(m.map_or(r, |m| m.max(r))));
    let right = refs.iter().copied().filter(|r| *r >= ur + 1.0).fold(None, |m: Option<f64>, r| Some(m.map_or(r, |m| m.min(r))));
    // Witness lines start at the exterior face; the dimension line sits outside it.
    let face = analysis::wall_thickness(p, w) / 2.0;
    let n = if side.dot(w.normal()) >= 0.0 { w.normal() } else { -w.normal() };
    let at = |u: f64| analysis::wall_point(w, u).0 + n * face;
    let mut out = Vec::new();
    for (r, e) in left.map(|r| (r, ul)).into_iter().chain(right.map(|r| (r, ur))) {
        let (a, b) = (at(r), at(e));
        let dw = (b - a).normalize_or_zero();
        // A positive screen offset moves towards the world's -perp of the dimension.
        let sign = if (-geom::perp(dw)).dot(n) >= 0.0 { 1.0 } else { -1.0 };
        out.push(TempDim { a, b, value: (e - r).abs(), offset_px: 26.0 * sign });
    }
    out
}

pub fn compute(app: &App, view: &View, _xf: &Xf) -> Vec<TempDim> {
    if let Some((id, along, _)) = hosted_drag(app) {
        // Live dimensions while a door or window slides along its wall.
        let p = &app.doc.data;
        if let Some(i) = p.element(id).and_then(|e| e.as_instance()) {
            if let Some(w) = i.host.and_then(|h| p.wall(h)) {
                return hosted_dims(p, id, i, w, along);
            }
        }
        return vec![];
    }
    if app.interact.drag.is_some() || app.selection.len() != 1 || !app.tool.is_select() || app.sketch.is_some() {
        return vec![];
    }
    let id = app.selection[0];
    let p = &app.doc.data;
    let Some(e) = app.el(id) else { return vec![] };
    if e.pinned {
        return vec![];
    }
    let level = view.plan_level();
    let mut out = Vec::new();
    match &e.kind {
        ElementKind::Wall(w) if level.is_some() && w.arc_mid.is_none() => {
            let d = w.direction();
            let n = w.normal();
            let mid = (w.start + w.end) / 2.0;
            for (foot, dist) in nearest_each_side(&parallel_refs(p, level, id, d), mid, n, 60000.0) {
                out.push(TempDim { a: foot, b: mid, value: dist, offset_px: 0.0 });
            }
        }
        ElementKind::Grid(g) if level.is_some() && g.arc_mid.is_none() => {
            let d = (g.end - g.start).normalize_or_zero();
            let n = geom::perp(d);
            let mid = (g.start + g.end) / 2.0;
            for (foot, dist) in nearest_each_side(&parallel_refs(p, None, id, d), mid, n, 100000.0) {
                out.push(TempDim { a: foot, b: mid, value: dist, offset_px: 0.0 });
            }
        }
        ElementKind::RefPlane(r) => {
            let d = (r.end - r.start).normalize_or_zero();
            let n = geom::perp(d);
            let mid = (r.start + r.end) / 2.0;
            for (foot, dist) in nearest_each_side(&parallel_refs(p, level, id, d), mid, n, 60000.0) {
                out.push(TempDim { a: foot, b: mid, value: dist, offset_px: 0.0 });
            }
        }
        ElementKind::Instance(i) if level.is_some() => {
            if let Some(w) = i.host.and_then(|h| p.wall(h)) {
                out.extend(hosted_dims(p, id, i, w, i.offset_along_host));
            } else if i.end.is_none() {
                let loc = analysis::instance_location(p, i);
                for dir in [DVec2::X, -DVec2::X, DVec2::Y, -DVec2::Y] {
                    if let Some((hit, dist)) = ray_hit(p, i.level, id, loc, dir, 30000.0) {
                        out.push(TempDim { a: hit, b: loc, value: dist, offset_px: 0.0 });
                    }
                }
            }
        }
        ElementKind::Level(l) if level.is_none() && view.is_graphical() => {
            let below = p.levels().into_iter().filter(|(lid, x)| *lid != id && x.elevation < l.elevation).last();
            let above = p.levels().into_iter().find(|(lid, x)| *lid != id && x.elevation > l.elevation);
            let x = app.cache.drawings.get(&view.id).and_then(|d| d.bounds()).map(|(mn, mx)| mn.x + (mx.x - mn.x) * 0.15).unwrap_or(0.0);
            for (_, o) in below.into_iter().chain(above) {
                out.push(TempDim { a: DVec2::new(x, o.elevation), b: DVec2::new(x, l.elevation), value: (l.elevation - o.elevation).abs(), offset_px: 0.0 });
            }
        }
        _ => {}
    }
    out
}

/// The inline editor for a clicked temporary dimension.
pub fn editor(app: &mut App, ui: &egui::Ui, xf: &Xf, dims: &[TempDim]) {
    let Some(mut ed) = app.interact.temp_dim_edit.clone() else { return };
    let Some(td) = dims.get(ed.index).cloned() else {
        app.interact.temp_dim_edit = None;
        return;
    };
    let (sa, sb) = (xf.s(td.a), xf.s(td.b));
    let d = (sb - sa).normalized();
    let n = egui::vec2(-d.y, d.x);
    let mid = sa + (sb - sa) / 2.0 + n * (td.offset_px + 9.0);
    let mut done: Option<bool> = None;
    egui::Area::new(egui::Id::new("temp-dim-edit"))
        .fixed_pos(mid - egui::vec2(45.0, 10.0))
        .order(egui::Order::Foreground)
        .show(ui.ctx(), |ui| {
            let r = ui.add(egui::TextEdit::singleline(&mut ed.text).desired_width(90.0));
            if ed.focus {
                r.request_focus();
                ed.focus = false;
            }
            if r.lost_focus() {
                done = Some(ui.input(|i| i.key_pressed(egui::Key::Enter)));
            }
            if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
                done = Some(false);
            }
        });
    match done {
        Some(true) => {
            app.interact.temp_dim_edit = None;
            match app.doc.data.units.parse(ed.text.trim(), ParamKind::Length) {
                Some(v) => {
                    let dir = (td.b - td.a).normalize_or_zero();
                    let delta = dir * (v - td.value);
                    let id = ed.id;
                    let is_wall = app.doc.data.wall(id).is_some();
                    let hosted = app.doc.data.element(id).and_then(|e| e.as_instance()).and_then(|i| i.host.map(|_| i.offset_along_host));
                    app.run("Move by Temporary Dimension", |p| {
                        if is_wall {
                            return grips::move_wall_with_joins(p, id, delta);
                        }
                        if let Some(along) = hosted {
                            // Along-host distances: from the start grows, from the end shrinks.
                            let w = p.element(id).and_then(|e| e.as_instance()).and_then(|i| i.host).and_then(|h| p.wall(h)).cloned();
                            if let Some(w) = w {
                                let (_, wd) = analysis::wall_point(&w, along);
                                let new_along = along + delta.dot(wd);
                                return rc_core::edit::set_opening_offset(p, id, new_along);
                            }
                        }
                        if let Some(ElementKind::Level(l)) = p.element_mut(id).map(|e| &mut e.kind) {
                            l.elevation += delta.y;
                            return Ok(());
                        }
                        rc_core::edit::move_elements(p, &[id], delta);
                        Ok(())
                    });
                }
                None => app.error(format!("'{}' is not a valid length.", ed.text.trim())),
            }
        }
        Some(false) => app.interact.temp_dim_edit = None,
        None => app.interact.temp_dim_edit = Some(ed),
    }
    let _ = canvas::is_plan;
}
