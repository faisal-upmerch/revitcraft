//! Grips (drag controls) and click controls of selected elements: wall ends and shape handles,
//! flip arrows, grid bubbles, dimension locks and EQ, section ends/depth, crop region edges.

use crate::app::App;
use crate::canvas::{self, Xf};
use crate::style;
use eframe::egui::{self, Color32, Pos2, Rect, Stroke, vec2};
use rc_core::analysis;
use rc_core::geom::{self, DVec2};
use rc_core::model::*;

#[derive(Clone, Debug, PartialEq)]
pub enum GripKind {
    WallEnd(bool),
    WallMid,
    WallFlip,
    Vertex(usize),
    LineMid,
    GridEnd(bool),
    GridBubble(bool),
    /// The 3D/2D extents label at a grid end: click to switch.
    GridExtents(bool),
    /// Add Elbow (or drag an elbow's bubble aside).
    GridElbow(bool),
    /// The alignment lock at a grid end aligned with others.
    GridLock(bool),
    BeamEnd(bool),
    FlipFacing,
    FlipHand,
    TagHead,
    TagLeader,
    TextPos,
    DimLine,
    DimLock(usize),
    DimEq,
    RoomPoint,
    SectionEnd(bool),
    SectionDepth,
    SectionFlip,
    ElevationMarker,
    CropEdge(u8),
    SymbolPos,
    LevelElevation,
}

impl GripKind {
    /// Controls are clicked rather than dragged.
    pub fn is_control(&self) -> bool {
        matches!(self, GripKind::WallFlip | GripKind::FlipFacing | GripKind::FlipHand | GripKind::GridBubble(_) | GripKind::GridExtents(_) | GripKind::GridLock(_) | GripKind::DimLock(_) | GripKind::DimEq | GripKind::SectionFlip)
    }
}

#[derive(Clone, Debug)]
pub struct Grip {
    pub id: Id,
    pub kind: GripKind,
    pub pos: DVec2,
    /// Direction for arrow controls, or a state flag for toggles.
    pub dir: DVec2,
    pub on: bool,
}

fn g(id: Id, kind: GripKind, pos: DVec2) -> Grip {
    Grip { id, kind, pos, dir: DVec2::X, on: false }
}

pub fn grips(app: &App, view: &View, xf: &Xf) -> Vec<Grip> {
    let mut out = Vec::new();
    if app.selection.len() > 30 {
        return out;
    }
    let p = &app.doc.data;
    let px = |k: f32| xf.len(k);
    let plan_view = canvas::is_plan(view);
    for id in &app.selection {
        let id = *id;
        if let Some(e) = app.el(id) {
            if e.pinned {
                continue;
            }
            match &e.kind {
                ElementKind::Wall(w) if plan_view => {
                    out.push(g(id, GripKind::WallEnd(true), w.start));
                    out.push(g(id, GripKind::WallEnd(false), w.end));
                    let t = analysis::wall_thickness(p, w);
                    let (mid, n) = match w.arc() {
                        Some(a) => {
                            out.push(g(id, GripKind::WallMid, a.mid()));
                            (a.mid(), geom::perp(a.tangent(0.5)))
                        }
                        None => ((w.start + w.end) / 2.0, w.normal()),
                    };
                    // In plan the reference app shows the ends and the flip control only.
                    if app.selection.len() == 1 {
                        out.push(Grip { id, kind: GripKind::WallFlip, pos: mid + n * (t / 2.0 + px(14.0)), dir: n, on: false });
                    }
                }
                ElementKind::Line(l) if l.pts.len() >= 2 && (plan_view || e.view == Some(view.id)) => {
                    for (k, q) in l.pts.iter().enumerate() {
                        out.push(g(id, GripKind::Vertex(k), *q));
                    }
                    if let (Some(m), 2) = (l.arc_mid, l.pts.len()) {
                        out.push(g(id, GripKind::LineMid, m));
                    }
                }
                ElementKind::RefPlane(r) if plan_view => {
                    out.push(g(id, GripKind::Vertex(0), r.start));
                    out.push(g(id, GripKind::Vertex(1), r.end));
                }
                ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) if plan_view => {
                    out.push(g(id, GripKind::Vertex(0), s.start));
                    out.push(g(id, GripKind::Vertex(1), s.end));
                }
                ElementKind::Grid(gr) if plan_view => {
                    // Ends (hollow circles: model extents; filled: 2D extents in this view) with
                    // their 3D/2D label, the bubble checkboxes beyond them along the grid, the
                    // Add Elbow controls beside the bubbles and locks where ends align.
                    let ext = gr.view_ext(view.id).cloned().unwrap_or_default();
                    let gv = gr.in_view(view.id);
                    let d = (gv.end - gv.start).normalize_or_zero();
                    let n = geom::perp(d);
                    let r = 6.0 * view.scale;
                    for (s, pt, out_dir, two_d, bubble, elbow, lock) in [
                        (true, gv.start, -d, ext.start.is_some(), gr.bubble_start, ext.elbow_start, gr.lock_start),
                        (false, gv.end, d, ext.end.is_some(), gr.bubble_end, ext.elbow_end, gr.lock_end),
                    ] {
                        out.push(Grip { id, kind: GripKind::GridEnd(s), pos: pt, dir: out_dir, on: two_d });
                        out.push(Grip { id, kind: GripKind::GridExtents(s), pos: pt + geom::perp(out_dir) * px(14.0) - out_dir * px(2.0), dir: out_dir, on: two_d });
                        out.push(Grip { id, kind: GripKind::GridBubble(s), pos: pt + elbow.unwrap_or_default() + out_dir * (2.0 * r + px(12.0)), dir: d, on: bubble });
                        if bubble {
                            let at = match elbow {
                                Some(o) => pt + o,
                                None => pt + out_dir * r - n * (r + px(10.0)),
                            };
                            out.push(Grip { id, kind: GripKind::GridElbow(s), pos: at, dir: out_dir, on: elbow.is_some() });
                        }
                        if aligned_grids(p, id, s, view.id).len() > 0 {
                            out.push(Grip { id, kind: GripKind::GridLock(s), pos: pt - out_dir * px(18.0) - geom::perp(out_dir) * px(12.0), dir: out_dir, on: lock });
                        }
                    }
                }
                ElementKind::Instance(i) if plan_view => {
                    if let Some(end) = i.end {
                        out.push(g(id, GripKind::BeamEnd(true), i.location));
                        out.push(g(id, GripKind::BeamEnd(false), end));
                    }
                    // Flip controls of families that have them, at their places in the family.
                    if let (true, Some(def), true) = (i.host.is_none(), p.family(i.family_id).and_then(|f| f.definition.as_ref()), app.selection.len() == 1) {
                        if let Some(r) = rc_core::family_params::Resolver::for_instance(p, i) {
                            if let Ok(solved) = def.solve(&|n| r.number(n).ok()) {
                                let f = rc_core::family_geom::instance_frame(p, i);
                                for c in &def.controls {
                                    let at = f.plan(rc_core::family_def::loc(c.at.a, &solved), rc_core::family_def::loc(c.at.b, &solved));
                                    let (kind, dir) = if c.kind.horizontal() { (GripKind::FlipHand, f.x) } else { (GripKind::FlipFacing, f.y) };
                                    out.push(Grip { id, kind, pos: at, dir, on: false });
                                }
                            }
                        }
                    }
                    if let (Some(h), true) = (i.host.and_then(|h| p.wall(h)), app.selection.len() == 1) {
                        let (pt, dir) = analysis::wall_point(h, i.offset_along_host);
                        let n = geom::perp(dir);
                        let t = analysis::wall_thickness(p, h);
                        let facing = if i.flip_facing { -n } else { n };
                        out.push(Grip { id, kind: GripKind::FlipFacing, pos: pt + facing * (t / 2.0 + px(16.0)), dir: facing, on: false });
                        let (ow, _) = analysis::opening_size(p, i);
                        let hand = if i.flip_hand { -dir } else { dir };
                        out.push(Grip { id, kind: GripKind::FlipHand, pos: pt + hand * (ow / 2.0 + px(14.0)) - facing * (t / 2.0 + px(6.0)), dir: hand, on: false });
                    }
                }
                ElementKind::Tag(t) => {
                    out.push(g(id, GripKind::TagHead, t.position));
                    if t.leader {
                        if let Some(end) = t.leader_end {
                            out.push(g(id, GripKind::TagLeader, end));
                        }
                    }
                }
                ElementKind::Text(t) => out.push(g(id, GripKind::TextPos, t.position)),
                ElementKind::Symbol(s) => out.push(g(id, GripKind::SymbolPos, s.position)),
                ElementKind::Room(r) if plan_view => out.push(g(id, GripKind::RoomPoint, r.location)),
                ElementKind::Area(a) if plan_view => out.push(g(id, GripKind::RoomPoint, a.location)),
                ElementKind::Dimension(d) if matches!(d.kind, DimKind::Aligned | DimKind::Linear) && d.refs.len() >= 2 => {
                    let coords = rc_core::annotation::coordinates(p, d);
                    let base = d.line_point - d.direction * d.line_point.dot(d.direction);
                    let pts: Vec<DVec2> = coords.iter().map(|c| base + d.direction * *c).collect();
                    let n = geom::perp(d.direction);
                    let mid = (pts[0] + pts[pts.len() - 1]) / 2.0;
                    out.push(g(id, GripKind::DimLine, mid + n * px(2.0)));
                    if app.selection.len() == 1 {
                        for k in 0..pts.len() - 1 {
                            let m = (pts[k] + pts[k + 1]) / 2.0;
                            out.push(Grip { id, kind: GripKind::DimLock(k), pos: m - n * px(12.0), dir: d.direction, on: d.locks.get(k).copied().unwrap_or(false) });
                        }
                        if pts.len() >= 3 {
                            out.push(Grip { id, kind: GripKind::DimEq, pos: mid + n * px(16.0), dir: d.direction, on: d.equal });
                        }
                    }
                }
                ElementKind::Level(_) if !plan_view && view.is_graphical() => {
                    // In sections/elevations the level line's right end drags its elevation.
                    if let Some((a, b)) = level_line(app, view, id) {
                        out.push(g(id, GripKind::LevelElevation, a.max(b)));
                    }
                }
                _ => {}
            }
            continue;
        }
        // Views: section/elevation markers and the crop region of this view.
        let Some(v) = p.view(id) else { continue };
        if id == view.id {
            if let Some((a, b)) = v.crop {
                let (mn, mx) = (a.min(b), a.max(b));
                let c = (mn + mx) / 2.0;
                out.push(g(id, GripKind::CropEdge(0), DVec2::new(mn.x, c.y)));
                out.push(g(id, GripKind::CropEdge(1), DVec2::new(mx.x, c.y)));
                out.push(g(id, GripKind::CropEdge(2), DVec2::new(c.x, mn.y)));
                out.push(g(id, GripKind::CropEdge(3), DVec2::new(c.x, mx.y)));
            }
            continue;
        }
        if !plan_view {
            continue;
        }
        match &v.kind {
            ViewKind::Section { start, end, depth, .. } => {
                let look = rc_core::section::section_look(*start, *end);
                out.push(g(id, GripKind::SectionEnd(true), *start));
                out.push(g(id, GripKind::SectionEnd(false), *end));
                out.push(Grip { id, kind: GripKind::SectionDepth, pos: (*start + *end) / 2.0 + look * *depth, dir: look, on: false });
                out.push(Grip { id, kind: GripKind::SectionFlip, pos: (*start + *end) / 2.0 - look * px(18.0), dir: look, on: false });
            }
            ViewKind::Elevation { .. } => {
                if let Some((o, _)) = v.marker {
                    out.push(g(id, GripKind::ElevationMarker, o));
                }
            }
            _ => {}
        }
    }
    out
}

/// The level line of `level` in a section/elevation drawing (from the cached drawing).
fn level_line(app: &App, view: &View, level: Id) -> Option<(DVec2, DVec2)> {
    let d = app.cache.drawings.get(&view.id)?;
    d.prims.iter().find_map(|(id, prim)| match prim {
        rc_core::plan::Prim::Line { pts, .. } if *id == Some(level) && pts.len() == 2 => Some((pts[0], pts[1])),
        _ => None,
    })
}

pub fn paint(painter: &egui::Painter, xf: &Xf, grips: &[Grip], hover: Option<&GripKind>) {
    for gr in grips {
        let p = xf.s(gr.pos);
        let hot = hover == Some(&gr.kind);
        let fill = if hot { Color32::from_rgb(120, 190, 255) } else { Color32::WHITE };
        let st = Stroke::new(1.5, style::SELECT);
        match &gr.kind {
            GripKind::WallFlip | GripKind::FlipFacing | GripKind::FlipHand | GripKind::SectionFlip => {
                // The flip control: a thin double arrow.
                let d = egui::vec2(gr.dir.x as f32, -gr.dir.y as f32);
                let n = vec2(-d.y, d.x);
                let c = if hot { style::PRESELECT } else { style::SELECT };
                let st = Stroke::new(1.6, c);
                painter.line_segment([p - d * 8.0, p + d * 8.0], st);
                for s in [1.0f32, -1.0] {
                    let tip = p + d * 8.0 * s;
                    painter.add(egui::Shape::line(vec![tip - d * 4.0 * s + n * 3.5, tip, tip - d * 4.0 * s - n * 3.5], st));
                }
            }
            GripKind::GridEnd(_) => {
                // Hollow for model (3D) extents, filled for 2D extents in this view.
                let fill = if hot { Color32::from_rgb(120, 190, 255) } else if gr.on { style::SELECT } else { Color32::WHITE };
                painter.circle(p, 4.5, fill, Stroke::new(1.5, style::SELECT));
            }
            GripKind::GridExtents(_) => {
                let c = if hot { style::PRESELECT } else { style::SELECT };
                painter.text(p, egui::Align2::CENTER_CENTER, if gr.on { "2D" } else { "3D" }, style::bold(10.0), c);
            }
            GripKind::GridElbow(_) => {
                // A small break symbol; with an elbow, a dot that drags the bubble aside.
                let c = if hot { style::PRESELECT } else { style::SELECT };
                if gr.on {
                    painter.circle(p, 3.5, Color32::WHITE, Stroke::new(1.5, c));
                } else {
                    painter.add(egui::Shape::line(vec![p + vec2(-6.0, 3.0), p + vec2(-2.0, 3.0), p + vec2(2.0, -3.0), p + vec2(6.0, -3.0)], Stroke::new(1.5, c)));
                }
            }
            GripKind::GridLock(_) => paint_lock(painter, p, gr.on, hot),
            GripKind::SectionDepth => {
                let d = egui::vec2(gr.dir.x as f32, -gr.dir.y as f32);
                let n = vec2(-d.y, d.x);
                painter.add(egui::Shape::convex_polygon(vec![p + d * 8.0, p - d * 4.0 + n * 6.0, p - d * 4.0 - n * 6.0], fill, st));
            }
            GripKind::GridBubble(_) => {
                let r = Rect::from_center_size(p, vec2(9.0, 9.0));
                painter.rect_filled(r, 0.0, Color32::WHITE);
                painter.rect_stroke(r, 0.0, Stroke::new(1.0, style::SELECT), egui::StrokeKind::Middle);
                if gr.on {
                    painter.line_segment([r.left_center() + vec2(1.5, 0.0), r.center_bottom() + vec2(0.0, -2.0)], Stroke::new(1.5, style::SELECT));
                    painter.line_segment([r.center_bottom() + vec2(0.0, -2.0), r.right_top() + vec2(-1.5, 2.0)], Stroke::new(1.5, style::SELECT));
                }
            }
            GripKind::DimLock(_) => paint_lock(painter, p, gr.on, hot),
            GripKind::DimEq => {
                let c = if hot { style::PRESELECT } else { style::SELECT };
                painter.text(p, egui::Align2::CENTER_CENTER, "EQ", egui::FontId::proportional(11.0), c);
                if !gr.on {
                    painter.line_segment([p + vec2(-9.0, 6.0), p + vec2(9.0, -6.0)], Stroke::new(1.2, c));
                }
            }
            _ => {
                // Solid blue dots, like the reference app.
                let dot = if hot { Color32::from_rgb(110, 165, 250) } else { Color32::from_rgb(64, 112, 210) };
                painter.circle(p, 4.0, dot, Stroke::new(1.0, Color32::from_rgb(20, 60, 160)));
            }
        }
    }
}

fn paint_lock(painter: &egui::Painter, p: Pos2, locked: bool, hot: bool) {
    let c = if hot { style::PRESELECT } else { style::SELECT };
    let body = Rect::from_center_size(p + vec2(0.0, 2.0), vec2(9.0, 7.0));
    painter.rect(body, 1.0, if locked { c } else { Color32::WHITE }, Stroke::new(1.2, c), egui::StrokeKind::Middle);
    let shackle: Vec<Pos2> = (0..=10)
        .map(|k| {
            let a = std::f32::consts::PI * (1.0 + k as f32 / 10.0);
            let cx = if locked { p.x } else { p.x + 3.0 };
            Pos2::new(cx + 3.0 * a.cos(), p.y - 1.5 + 3.5 * a.sin())
        })
        .collect();
    painter.add(egui::Shape::line(shackle, Stroke::new(1.2, c)));
}

/// Other straight grids parallel to `id` whose end lies on the same line across the grids as
/// its start (`at_start`) or end: (grid, which end).
pub fn aligned_grids(p: &Project, id: Id, at_start: bool, view: Id) -> Vec<(Id, bool)> {
    let Some(ElementKind::Grid(g)) = p.element(id).map(|e| &e.kind) else { return vec![] };
    if g.arc_mid.is_some() || !g.vertices.is_empty() {
        return vec![];
    }
    let g = g.in_view(view);
    let dir = (g.end - g.start).normalize_or_zero();
    let end = if at_start { g.start } else { g.end };
    let mut out = Vec::new();
    for e in &p.elements {
        let ElementKind::Grid(o) = &e.kind else { continue };
        if e.id == id || o.arc_mid.is_some() || !o.vertices.is_empty() {
            continue;
        }
        let o = o.in_view(view);
        let od = (o.end - o.start).normalize_or_zero();
        if od.perp_dot(dir).abs() > 1e-3 {
            continue;
        }
        for (os, q) in [(true, o.start), (false, o.end)] {
            if ((q - end).dot(dir)).abs() < 1.0 {
                out.push((e.id, os));
            }
        }
    }
    out
}

/// Walls whose ends coincide with `pt` (joined there), excluding `skip`.
pub fn walls_joined_at(p: &Project, pt: DVec2, skip: Id) -> Vec<(Id, bool)> {
    let mut out = Vec::new();
    for (e, w) in p.walls() {
        if e.id == skip {
            continue;
        }
        if w.start.distance(pt) < 1.0 {
            out.push((e.id, true));
        } else if w.end.distance(pt) < 1.0 {
            out.push((e.id, false));
        }
    }
    out
}

/// Moves a wall perpendicular to itself; walls joined at its ends stretch to follow.
pub fn move_wall_with_joins(p: &mut Project, id: Id, delta: DVec2) -> Result<(), String> {
    let w = p.wall(id).ok_or("Wall not found.")?.clone();
    let js = walls_joined_at(p, w.start, id);
    let je = walls_joined_at(p, w.end, id);
    rc_core::edit::move_elements(p, &[id], delta);
    for (jid, at_start) in js.into_iter().chain(je) {
        if let Some(j) = p.element_mut(jid).and_then(Element::as_wall_mut) {
            if at_start {
                j.start += delta;
            } else {
                j.end += delta;
            }
        }
    }
    Ok(())
}

/// The point a grip drag ends at, constrained where the element requires it.
fn constrained(p: &Project, id: Id, kind: &GripKind, start: DVec2, pt: DVec2) -> DVec2 {
    match kind {
        GripKind::GridEnd(_) => {
            if let Some(ElementKind::Grid(gr)) = p.element(id).map(|e| &e.kind) {
                if gr.arc_mid.is_none() {
                    let d = (gr.end - gr.start).normalize_or_zero();
                    return gr.start + d * (pt - gr.start).dot(d);
                }
            }
            pt
        }
        GripKind::SectionDepth => {
            let n = match p.element(id).map(|e| &e.kind) {
                Some(ElementKind::Wall(w)) => w.normal(),
                _ => match p.view(id).map(|v| &v.kind) {
                    Some(ViewKind::Section { start, end, .. }) => geom::perp((*end - *start).normalize_or_zero()),
                    _ => DVec2::X,
                },
            };
            start + n * (pt - start).dot(n)
        }
        GripKind::LevelElevation => DVec2::new(start.x, pt.y),
        _ => pt,
    }
}

pub fn preview(app: &App, painter: &egui::Painter, xf: &Xf, view: &View, id: Id, kind: &GripKind, start: DVec2, pt: DVec2) {
    let p = &app.doc.data;
    let pt = constrained(p, id, kind, start, pt);
    let st = Stroke::new(1.5, style::PREVIEW);
    let units = &p.units;
    match (p.element(id).map(|e| &e.kind), kind) {
        (Some(ElementKind::Wall(w)), GripKind::WallEnd(s)) => {
            // As the reference app: the wall stays as it is and its new location line shows as a
            // thick orange dashed line, with a thin tracking line beyond the cursor.
            let fixed = if *s { w.end } else { w.start };
            let (a, b) = (xf.s(fixed), xf.s(pt));
            let len = a.distance(b);
            if len > 1.0 {
                let d = (b - a) / len;
                canvas::track_line(painter, b, b + d * 120.0);
                let orange = egui::Color32::from_rgb(226, 148, 82);
                let (dash, gap, width) = (16.0f32, 10.0f32, 5.0f32);
                let mut t = 0.0;
                while t < len {
                    let (u0, u1) = (t, (t + dash).min(len));
                    let (p0, p1) = (b - d * u0, b - d * u1);
                    painter.line_segment([p0, p1], Stroke::new(width, orange));
                    painter.circle_filled(p0, width / 2.0, orange);
                    painter.circle_filled(p1, width / 2.0, orange);
                    t += dash + gap;
                }
            }
            canvas::temp_dim(painter, xf, fixed, pt, &units.length(fixed.distance(pt)), -20.0);
        }
        (Some(ElementKind::Wall(w)), GripKind::WallMid) => {
            if let Some(a) = geom::Arc2::through(w.start, pt, w.end) {
                let pts: Vec<Pos2> = a.tessellate(200.0).iter().map(|q| xf.s(*q)).collect();
                painter.add(egui::Shape::line(pts, st));
                canvas::temp_dim(painter, xf, a.center, pt, &format!("R {}", units.length(a.radius)), 14.0);
            }
        }
        _ => {
            painter.extend(egui::Shape::dashed_line(&[xf.s(start), xf.s(pt)], Stroke::new(1.0, style::PREVIEW), 5.0, 3.0));
            painter.circle_stroke(xf.s(pt), 5.0, st);
            if start.distance(pt) > 1.0 {
                canvas::temp_dim(painter, xf, start, pt, &units.length(start.distance(pt)), -16.0);
            }
        }
    }
    let _ = view;
}

pub fn apply(app: &mut App, view: &View, id: Id, kind: &GripKind, start: DVec2, pt: DVec2) {
    let pt = constrained(&app.doc.data, id, kind, start, pt);
    if pt.distance(start) < 1e-6 {
        return;
    }
    let kind = kind.clone();
    let view_id = view.id;
    app.run("Drag", move |p| {
        if p.element(id).is_some() {
            if let GripKind::WallEnd(s) = kind {
                let old = { let w = p.wall(id).ok_or("Wall not found.")?; if s { w.start } else { w.end } };
                let joined = walls_joined_at(p, old, id);
                if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
                    if s {
                        w.start = pt;
                    } else {
                        w.end = pt;
                    }
                    if w.start.distance(w.end) < 10.0 {
                        return Err("The wall would be too short.".into());
                    }
                }
                for (jid, at_start) in joined {
                    if let Some(j) = p.element_mut(jid).and_then(Element::as_wall_mut) {
                        if at_start {
                            j.start = pt;
                        } else {
                            j.end = pt;
                        }
                    }
                }
                return Ok(());
            }
            // Locked grid ends drag the ends aligned with them along.
            if let GripKind::GridEnd(s) = kind {
                let locked = matches!(p.element(id).map(|e| &e.kind), Some(ElementKind::Grid(g)) if if s { g.lock_start } else { g.lock_end });
                if locked {
                    let Some(ElementKind::Grid(g)) = p.element(id).map(|e| e.kind.clone()) else { return Ok(()) };
                    let old = if s { g.start } else { g.end };
                    let dir = (g.end - g.start).normalize_or_zero();
                    let shift = (pt - old).dot(dir);
                    for (other, os) in aligned_grids(p, id, s, view_id) {
                        if let Some(ElementKind::Grid(o)) = p.element_mut(other).map(|e| &mut e.kind) {
                            let od = (o.end - o.start).normalize_or_zero();
                            let sign = if od.dot(dir) >= 0.0 { 1.0 } else { -1.0 };
                            if os {
                                o.start += od * shift * sign;
                            } else {
                                o.end += od * shift * sign;
                            }
                        }
                    }
                }
            }
            if let GripKind::LevelElevation = kind {
                if let Some(ElementKind::Level(l)) = p.element_mut(id).map(|e| &mut e.kind) {
                    l.elevation = pt.y;
                }
                return Ok(());
            }
            let e = p.element_mut(id).unwrap();
            match (&mut e.kind, &kind) {
                (ElementKind::Wall(w), GripKind::WallMid) => w.arc_mid = Some(pt),
                (ElementKind::Line(l), GripKind::Vertex(k)) => {
                    if let Some(q) = l.pts.get_mut(*k) {
                        *q = pt;
                    }
                }
                (ElementKind::Line(l), GripKind::LineMid) => l.arc_mid = Some(pt),
                (ElementKind::RefPlane(r), GripKind::Vertex(k)) => {
                    if *k == 0 {
                        r.start = pt
                    } else {
                        r.end = pt
                    }
                }
                (ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s), GripKind::Vertex(k)) => {
                    if *k == 0 {
                        s.start = pt
                    } else {
                        s.end = pt
                    }
                }
                (ElementKind::Grid(gr), GripKind::GridEnd(s)) if gr.view_ext(view_id).is_some_and(|x| if *s { x.start.is_some() } else { x.end.is_some() }) => {
                    let x = gr.view_ext_mut(view_id);
                    if *s {
                        x.start = Some(pt)
                    } else {
                        x.end = Some(pt)
                    }
                }
                (ElementKind::Grid(gr), GripKind::GridElbow(s)) => {
                    // The elbow's offset is the drag across the grid.
                    let g2 = gr.in_view(view_id);
                    let (end, dir) = if *s { (g2.start, (g2.start - g2.end).normalize_or_zero()) } else { (g2.end, (g2.end - g2.start).normalize_or_zero()) };
                    let n = geom::perp(dir);
                    let o = n * (pt - end).dot(n);
                    let x = gr.view_ext_mut(view_id);
                    if *s {
                        x.elbow_start = Some(o)
                    } else {
                        x.elbow_end = Some(o)
                    }
                }
                (ElementKind::Grid(gr), GripKind::GridEnd(s)) => {
                    if *s {
                        gr.start = pt
                    } else {
                        gr.end = pt
                    }
                }
                (ElementKind::Instance(i), GripKind::BeamEnd(s)) => {
                    if *s {
                        i.location = pt
                    } else {
                        i.end = Some(pt)
                    }
                }
                (ElementKind::Tag(t), GripKind::TagHead) => t.position = pt,
                (ElementKind::Tag(t), GripKind::TagLeader) => t.leader_end = Some(pt),
                (ElementKind::Text(t), GripKind::TextPos) => t.position = pt,
                (ElementKind::Symbol(s), GripKind::SymbolPos) => s.position = pt,
                (ElementKind::Room(r), GripKind::RoomPoint) => r.location = pt,
                (ElementKind::Area(a), GripKind::RoomPoint) => a.location = pt,
                (ElementKind::Dimension(d), GripKind::DimLine) => d.line_point = pt,
                _ => {}
            }
            return Ok(());
        }
        let v = p.view_mut(id).ok_or("View not found.")?;
        match (&mut v.kind, &kind) {
            (ViewKind::Section { start: s, .. }, GripKind::SectionEnd(true)) => *s = pt,
            (ViewKind::Section { end: e, .. }, GripKind::SectionEnd(false)) => *e = pt,
            (ViewKind::Section { start: s, end: e, depth, .. }, GripKind::SectionDepth) => {
                let look = rc_core::section::section_look(*s, *e);
                let mid = (*s + *e) / 2.0;
                *depth = (pt - mid).dot(look).max(100.0);
            }
            (ViewKind::Elevation { .. }, GripKind::ElevationMarker) => {
                if let Some((o, _)) = v.marker.as_mut() {
                    *o = pt;
                }
            }
            (_, GripKind::CropEdge(k)) => {
                if let Some((a, b)) = v.crop.as_mut() {
                    let (mut mn, mut mx) = (a.min(*b), a.max(*b));
                    match k {
                        0 => mn.x = pt.x.min(mx.x - 100.0),
                        1 => mx.x = pt.x.max(mn.x + 100.0),
                        2 => mn.y = pt.y.min(mx.y - 100.0),
                        _ => mx.y = pt.y.max(mn.y + 100.0),
                    }
                    *a = mn;
                    *b = mx;
                }
            }
            _ => {}
        }
        let _ = view_id;
        Ok(())
    });
}

/// Click controls. Returns true when the click was consumed.
pub fn click(app: &mut App, view: &View, id: Id, kind: &GripKind) -> bool {
    let view_id = view.id;
    // Add Elbow: a click adds the jog (an existing elbow drags instead).
    if let GripKind::GridElbow(s) = kind {
        let s = *s;
        let has = matches!(app.el(id).map(|e| &e.kind), Some(ElementKind::Grid(g)) if g.view_ext(view_id).is_some_and(|x| if s { x.elbow_start.is_some() } else { x.elbow_end.is_some() }));
        if has {
            return false;
        }
        let off = 8.0 * view.scale;
        app.run("Add Elbow", move |p| {
            if let Some(ElementKind::Grid(g)) = p.element_mut(id).map(|e| &mut e.kind) {
                let gv = g.in_view(view_id);
                let d = (gv.end - gv.start).normalize_or_zero();
                let o = -geom::perp(d) * off;
                let x = g.view_ext_mut(view_id);
                if s {
                    x.elbow_start = Some(o)
                } else {
                    x.elbow_end = Some(o)
                }
            }
            Ok(())
        });
        return true;
    }
    if !kind.is_control() {
        return false;
    }
    let kind = kind.clone();
    let name = match kind {
        GripKind::WallFlip => "Flip Wall",
        GripKind::FlipFacing => "Flip Facing",
        GripKind::FlipHand => "Flip Hand",
        GripKind::GridBubble(_) => "Show Bubble",
        GripKind::GridExtents(_) => "Switch Extents",
        GripKind::GridLock(_) => "Lock Alignment",
        GripKind::DimLock(_) => "Lock Dimension",
        GripKind::DimEq => "Equality Constraint",
        _ => "Flip Section",
    };
    app.run(name, move |p| {
        if let GripKind::WallFlip = kind {
            return rc_core::edit::flip_wall(p, id);
        }
        if let Some(e) = p.element_mut(id) {
            match (&mut e.kind, &kind) {
                (ElementKind::Instance(i), GripKind::FlipFacing) => i.flip_facing = !i.flip_facing,
                (ElementKind::Instance(i), GripKind::FlipHand) => i.flip_hand = !i.flip_hand,
                (ElementKind::Grid(g), GripKind::GridExtents(s)) => {
                    // 3D -> 2D keeps the end where it is in this view; 2D -> 3D returns it to
                    // the model extents.
                    let model = if *s { g.start } else { g.end };
                    let x = g.view_ext_mut(view_id);
                    let cur = if *s { &mut x.start } else { &mut x.end };
                    *cur = if cur.is_some() { None } else { Some(model) };
                }
                (ElementKind::Grid(g), GripKind::GridLock(s)) => {
                    if *s {
                        g.lock_start = !g.lock_start
                    } else {
                        g.lock_end = !g.lock_end
                    }
                }
                (ElementKind::Grid(g), GripKind::GridBubble(s)) => {
                    if *s {
                        g.bubble_start = !g.bubble_start
                    } else {
                        g.bubble_end = !g.bubble_end
                    }
                }
                (ElementKind::Dimension(d), GripKind::DimLock(k)) => {
                    let n = d.refs.len().saturating_sub(1);
                    d.locks.resize(n, false);
                    if let Some(l) = d.locks.get_mut(*k) {
                        *l = !*l;
                    }
                }
                (ElementKind::Dimension(d), GripKind::DimEq) => d.equal = !d.equal,
                _ => {}
            }
            return Ok(());
        }
        if let Some(v) = p.view_mut(id) {
            if let ViewKind::Section { start, end, .. } = &mut v.kind {
                std::mem::swap(start, end);
            }
        }
        Ok(())
    });
    true
}
