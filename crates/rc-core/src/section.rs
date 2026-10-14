//! Sections and elevations as 2D vector drawings: cut poché at the section plane, visible edges
//! beyond it (hidden-line removal with a software depth buffer), levels and grids.
//! Drawing coordinates are (u, z): u runs left→right as seen by the viewer, z is height.

use crate::analysis::{self, Footprint};
use crate::build3d;
use crate::geom::{self, DVec2, DVec3};
use crate::mesh::MeshSet;
use crate::model::*;
use crate::plan::{self, Anchor, Dash, Drawing, Prim, Stroke};
use std::collections::HashMap;

/// Maps model space to a section/elevation's 2D space.
#[derive(Clone, Copy, Debug)]
pub struct ViewFrame {
    pub origin: DVec3,
    /// Viewer's right (horizontal).
    pub right: DVec3,
    /// Viewing direction (into the screen).
    pub look: DVec3,
    /// Far clip depth (None = unlimited).
    pub far: Option<f64>,
    /// Is this a cutting section (geometry in front of the plane is removed)?
    pub cuts: bool,
    pub z_range: (f64, f64),
}

impl ViewFrame {
    pub fn to_view(&self, p: DVec3) -> (DVec2, f64) {
        let d = p - self.origin;
        (DVec2::new(d.dot(self.right), p.z), d.dot(self.look))
    }
    pub fn to_world(&self, q: DVec2, depth: f64) -> DVec3 {
        let h = self.origin + self.right * q.x + self.look * depth;
        DVec3::new(h.x, h.y, q.y)
    }
}

pub fn model_bounds(p: &Project, footprints: &HashMap<Id, Footprint>) -> Option<(DVec3, DVec3)> {
    p.elements
        .iter()
        .filter(|e| e.view.is_none())
        .filter_map(|e| build3d::element_mesh(p, e, footprints).bounds())
        .reduce(|(a0, a1), (b0, b1)| (a0.min(b0), a1.max(b1)))
}

/// The frame for a section or elevation view.
pub fn view_frame(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Option<ViewFrame> {
    match &view.kind {
        ViewKind::Section { start, end, depth, z_min, z_max } => {
            let d = (*end - *start).normalize_or_zero();
            let look = -geom::perp(d);
            Some(ViewFrame {
                origin: geom::at(*start, 0.0),
                right: geom::at(d, 0.0),
                look: geom::at(look, 0.0),
                far: Some(*depth),
                cuts: true,
                z_range: (*z_min, *z_max),
            })
        }
        ViewKind::Elevation { dir } => {
            let (mn, mx) = model_bounds(p, footprints).unwrap_or((DVec3::ZERO, DVec3::new(10000.0, 10000.0, 6000.0)));
            let (look, origin) = match view.marker {
                Some((o, l)) => (geom::at(l.normalize_or_zero(), 0.0), geom::at(o, 0.0)),
                None => {
                    let look = dir.look();
                    let c = (mn + mx) / 2.0;
                    let half = (mx - mn) / 2.0;
                    let back = DVec3::new(look.x * (half.x + 3000.0), look.y * (half.y + 3000.0), 0.0);
                    (look, DVec3::new(c.x, c.y, 0.0) - back)
                }
            };
            let right = look.cross(DVec3::Z).normalize();
            Some(ViewFrame { origin, right, look, far: None, cuts: false, z_range: (mn.z.min(0.0) - 1000.0, mx.z + 2000.0) })
        }
        _ => None,
    }
}

fn shade(color: [u8; 3], normal: DVec3) -> [u8; 4] {
    let light = DVec3::new(0.35, -0.6, 0.72).normalize();
    let k = 0.55 + 0.45 * normal.dot(light).abs();
    [(color[0] as f64 * k) as u8, (color[1] as f64 * k) as u8, (color[2] as f64 * k) as u8, 255]
}

/// A small software depth buffer in view space.
struct ZBuf {
    min: DVec2,
    px: f64,
    w: usize,
    h: usize,
    depth: Vec<f32>,
}

impl ZBuf {
    fn new(min: DVec2, max: DVec2) -> ZBuf {
        let size = (max - min).max(DVec2::splat(1.0));
        let px = (size.x.max(size.y) / 1400.0).max(5.0);
        let w = (size.x / px).ceil() as usize + 2;
        let h = (size.y / px).ceil() as usize + 2;
        ZBuf { min, px, w, h, depth: vec![f32::INFINITY; w * h] }
    }

    fn raster(&mut self, t: [(DVec2, f64); 3]) {
        let to_px = |q: DVec2| (q - self.min) / self.px;
        let (a, b, c) = (to_px(t[0].0), to_px(t[1].0), to_px(t[2].0));
        let det = geom::cross2(b - a, c - a);
        if det.abs() < 1e-9 {
            return;
        }
        let x0 = a.x.min(b.x).min(c.x).floor().max(0.0) as usize;
        let x1 = (a.x.max(b.x).max(c.x).ceil() as usize).min(self.w - 1);
        let y0 = a.y.min(b.y).min(c.y).floor().max(0.0) as usize;
        let y1 = (a.y.max(b.y).max(c.y).ceil() as usize).min(self.h - 1);
        for y in y0..=y1 {
            for x in x0..=x1 {
                let q = DVec2::new(x as f64 + 0.5, y as f64 + 0.5);
                let l1 = geom::cross2(b - q, c - q) / det;
                let l2 = geom::cross2(c - q, a - q) / det;
                let l3 = 1.0 - l1 - l2;
                if l1 < -1e-6 || l2 < -1e-6 || l3 < -1e-6 {
                    continue;
                }
                let z = (l1 * t[0].1 + l2 * t[1].1 + l3 * t[2].1) as f32;
                let slot = &mut self.depth[y * self.w + x];
                if z < *slot {
                    *slot = z;
                }
            }
        }
    }

    /// Is a point at `depth` visible (not behind the buffer by more than a tolerance)?
    fn visible(&self, q: DVec2, depth: f64) -> bool {
        let p = (q - self.min) / self.px;
        let (cx, cy) = (p.x.floor() as isize, p.y.floor() as isize);
        // An edge is visible if it is not behind the surface in its whole 3x3 neighbourhood;
        // silhouette edges touch background (infinite depth) and stay visible.
        let mut deepest = f32::NEG_INFINITY;
        for dy in -1..=1 {
            for dx in -1..=1 {
                let (x, y) = (cx + dx, cy + dy);
                let v = if x < 0 || y < 0 || x as usize >= self.w || y as usize >= self.h { f32::INFINITY } else { self.depth[y as usize * self.w + x as usize] };
                deepest = deepest.max(v);
            }
        }
        (depth as f32) <= deepest + (self.px as f32) * 2.0 + 20.0
    }
}

/// Clips a triangle (view-space points with depths) to depth ≥ 0; returns 0..2 triangles.
fn clip_front(t: [(DVec2, f64); 3]) -> Vec<[(DVec2, f64); 3]> {
    let inside: Vec<bool> = t.iter().map(|v| v.1 >= 0.0).collect();
    let n_in = inside.iter().filter(|b| **b).count();
    if n_in == 3 {
        return vec![t];
    }
    if n_in == 0 {
        return vec![];
    }
    let lerp = |a: (DVec2, f64), b: (DVec2, f64)| {
        let s = a.1 / (a.1 - b.1);
        (a.0.lerp(b.0, s), 0.0)
    };
    let mut poly = Vec::new();
    for i in 0..3 {
        let (a, b) = (t[i], t[(i + 1) % 3]);
        if a.1 >= 0.0 {
            poly.push(a);
        }
        if (a.1 >= 0.0) != (b.1 >= 0.0) {
            poly.push(lerp(a, b));
        }
    }
    (1..poly.len() - 1).map(|k| [poly[0], poly[k], poly[k + 1]]).collect()
}

/// Section cut segments of a mesh at depth 0 (view space).
fn cut_segments(set: &MeshSet, f: &ViewFrame) -> Vec<(DVec2, DVec2)> {
    let mut out = Vec::new();
    for m in set.by_material.values() {
        for tri in m.indices.chunks(3) {
            let v: Vec<(DVec2, f64)> = tri.iter().map(|k| f.to_view(m.positions[*k as usize])).collect();
            let mut pts = Vec::new();
            for i in 0..3 {
                let (a, b) = (v[i], v[(i + 1) % 3]);
                if (a.1 >= 0.0) != (b.1 >= 0.0) {
                    let s = a.1 / (a.1 - b.1);
                    pts.push(a.0.lerp(b.0, s));
                }
            }
            if pts.len() == 2 && pts[0].distance(pts[1]) > 1e-6 {
                out.push((pts[0], pts[1]));
            }
        }
    }
    out
}

/// Chains cut segments into closed loops.
fn chain(mut segs: Vec<(DVec2, DVec2)>) -> Vec<Vec<DVec2>> {
    let mut loops = Vec::new();
    let tol = 1.0;
    while let Some((a, b)) = segs.pop() {
        let mut lp = vec![a, b];
        let mut progress = true;
        while progress {
            progress = false;
            let tail = *lp.last().unwrap();
            if let Some(k) = segs.iter().position(|(c, d)| c.distance(tail) < tol || d.distance(tail) < tol) {
                let (c, d) = segs.swap_remove(k);
                lp.push(if c.distance(tail) < tol { d } else { c });
                progress = true;
            }
        }
        if lp.len() >= 4 && lp[0].distance(*lp.last().unwrap()) < tol {
            lp.pop();
            loops.push(lp);
        }
    }
    loops
}

/// Feature edges of a mesh in world space.
fn feature_edges(set: &MeshSet) -> Vec<(DVec3, DVec3)> {
    let q = |v: DVec3| ((v.x * 2.0).round() as i64, (v.y * 2.0).round() as i64, (v.z * 2.0).round() as i64);
    let mut map: HashMap<((i64, i64, i64), (i64, i64, i64)), (DVec3, DVec3, Vec<DVec3>)> = HashMap::new();
    for m in set.by_material.values() {
        for tri in m.indices.chunks(3) {
            let p = [m.positions[tri[0] as usize], m.positions[tri[1] as usize], m.positions[tri[2] as usize]];
            let n = (p[1] - p[0]).cross(p[2] - p[0]).normalize_or_zero();
            for k in 0..3 {
                let (a, b) = (p[k], p[(k + 1) % 3]);
                let (ka, kb) = (q(a), q(b));
                let key = if ka < kb { (ka, kb) } else { (kb, ka) };
                map.entry(key).or_insert_with(|| (a, b, Vec::new())).2.push(n);
            }
        }
    }
    map.into_values()
        .filter(|(_, _, ns)| ns.len() == 1 || ns.iter().any(|n| n.dot(ns[0]) < 0.94))
        .map(|(a, b, _)| (a, b))
        .collect()
}

/// Builds the drawing for a section or elevation view.
pub fn drawing(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Drawing {
    let mut d = Drawing::default();
    let Some(f) = view_frame(p, view, footprints) else { return d };
    let shaded = matches!(view.style, VisualStyle::Shaded | VisualStyle::ConsistentColors | VisualStyle::Realistic);
    // Gather geometry in view space.
    struct Item {
        id: Id,
        set: MeshSet,
        status: analysis::PhaseStatus,
    }
    let mut items = Vec::new();
    for e in &p.elements {
        if e.view.is_some() || !analysis::visible_in(p, view, e) {
            continue;
        }
        let set = build3d::element_mesh(p, e, footprints);
        let Some((mn, mx)) = set.bounds() else { continue };
        // Cull by depth range.
        let corners = [mn, mx, DVec3::new(mn.x, mx.y, mn.z), DVec3::new(mx.x, mn.y, mn.z)];
        let depths: Vec<f64> = corners.iter().map(|c| f.to_view(*c).1).collect();
        let (dmin, dmax) = (depths.iter().cloned().fold(f64::MAX, f64::min), depths.iter().cloned().fold(f64::MIN, f64::max));
        if dmax < 0.0 && f.cuts {
            continue;
        }
        if let Some(far) = f.far {
            if dmin > far {
                continue;
            }
        }
        items.push(Item { id: e.id, set, status: analysis::phase_status(p, view, e) });
    }
    // View-space triangles (behind the cut plane).
    let mut tris: Vec<(Id, [(DVec2, f64); 3], [u8; 4])> = Vec::new();
    for it in &items {
        for (mat, m) in &it.set.by_material {
            let color = p.material(mat).map(|m| m.color).unwrap_or([200, 200, 200]);
            for tri in m.indices.chunks(3) {
                let w: Vec<DVec3> = tri.iter().map(|k| m.positions[*k as usize]).collect();
                let n = (w[1] - w[0]).cross(w[2] - w[0]).normalize_or_zero();
                let v = [f.to_view(w[0]), f.to_view(w[1]), f.to_view(w[2])];
                let parts = if f.cuts { clip_front(v) } else { vec![v] };
                for t in parts {
                    if let Some(far) = f.far {
                        if t.iter().all(|x| x.1 > far) {
                            continue;
                        }
                    }
                    let c = if view.style == VisualStyle::ConsistentColors { [color[0], color[1], color[2], 255] } else { shade(color, n) };
                    tris.push((it.id, t, c));
                }
            }
        }
    }
    let pts = tris.iter().flat_map(|t| t.1.iter().map(|v| v.0));
    let (mn, mx) = geom::bounds(pts);
    if mn.x > mx.x {
        levels_and_grids(p, view, &f, None, &mut d);
        return d;
    }
    let mut zb = ZBuf::new(mn - DVec2::splat(10.0), mx + DVec2::splat(10.0));
    for (_, t, _) in &tris {
        zb.raster(*t);
    }

    // Shaded: painter's algorithm, far to near.
    if shaded {
        let mut order: Vec<usize> = (0..tris.len()).collect();
        order.sort_by(|a, b| {
            let da = tris[*a].1.iter().map(|v| v.1).sum::<f64>();
            let db = tris[*b].1.iter().map(|v| v.1).sum::<f64>();
            db.total_cmp(&da)
        });
        for k in order {
            let (id, t, c) = &tris[k];
            d.prims.push((Some(*id), Prim::Fill { tris: vec![[t[0].0, t[1].0, t[2].0]], color: *c }));
        }
    }

    // Visible edges beyond the cut.
    for it in &items {
        let stroke = match it.status {
            analysis::PhaseStatus::Existing => Stroke::new(0.13, [120, 120, 120], Dash::Solid),
            analysis::PhaseStatus::Demolished => Stroke::new(0.13, [120, 120, 120], Dash::Dotted),
            _ => plan::THIN,
        };
        for (a, b) in feature_edges(&it.set) {
            let (va, da) = f.to_view(a);
            let (vb, db) = f.to_view(b);
            if f.cuts && da < -1.0 && db < -1.0 {
                continue;
            }
            let len = va.distance(vb);
            let steps = ((len / (zb.px * 0.7)).ceil() as usize).clamp(1, 4000);
            let mut run: Vec<DVec2> = Vec::new();
            for s in 0..=steps {
                let t = s as f64 / steps as f64;
                let q = va.lerp(vb, t);
                let dep = da + (db - da) * t;
                let ok = (!f.cuts || dep >= -1.0) && zb.visible(q, dep) && f.far.is_none_or(|far| dep <= far);
                if ok {
                    run.push(q);
                } else if run.len() >= 2 {
                    d.line(Some(it.id), vec![run[0], *run.last().unwrap()], false, stroke);
                    run.clear();
                } else {
                    run.clear();
                }
            }
            if run.len() >= 2 {
                d.line(Some(it.id), vec![run[0], *run.last().unwrap()], false, stroke);
            }
        }
    }

    // Cut poché and heavy outlines at the section plane.
    if f.cuts {
        for it in &items {
            let loops = chain(cut_segments(&it.set, &f));
            for lp in loops {
                let cat = p.element(it.id).map(|e| e.category());
                let fill = match cat {
                    Some(Category::Walls | Category::Floors | Category::Roofs | Category::Stairs | Category::StructuralFraming | Category::StructuralColumns | Category::Columns | Category::StructuralFoundations) => [60, 60, 60, 255],
                    _ => [140, 140, 140, 255],
                };
                d.fill(Some(it.id), &lp, fill);
                d.line(Some(it.id), lp, true, plan::HEAVY);
            }
        }
    }
    levels_and_grids(p, view, &f, Some((mn, mx)), &mut d);
    d
}

fn levels_and_grids(p: &Project, view: &View, f: &ViewFrame, extent: Option<(DVec2, DVec2)>, d: &mut Drawing) {
    let scale = view.scale;
    let (u0, u1) = match extent {
        Some((mn, mx)) => (mn.x - 2500.0, mx.x + 2500.0),
        None => (-5000.0, 15000.0),
    };
    if view.shows(Category::Levels) {
        for (id, l) in p.levels() {
            let y = l.elevation;
            d.line(Some(id), vec![DVec2::new(u0, y), DVec2::new(u1, y)], false, Stroke::new(0.13, [40, 40, 140], Dash::DashDot));
            let head = DVec2::new(u1, y);
            let r = 1.6 * scale;
            d.fill(Some(id), &[head, head + DVec2::new(r, r), head + DVec2::new(r * 2.0, 0.0)], [40, 40, 140, 255]);
            d.prims.push((Some(id), Prim::Text { pos: head + DVec2::new(r * 2.6, r * 0.9), text: l.name.clone(), size: 2.5, color: [40, 40, 140], anchor: Anchor::Left, angle: 0.0 }));
            d.prims.push((Some(id), Prim::Text { pos: head + DVec2::new(r * 2.6, -r * 1.3), text: p.units.length(l.elevation), size: 2.0, color: [40, 40, 140], anchor: Anchor::Left, angle: 0.0 }));
        }
    }
    if view.shows(Category::Grids) {
        let (z0, z1) = (f.z_range.0, p.levels().last().map(|l| l.1.elevation).unwrap_or(3000.0) + 4000.0);
        for e in &p.elements {
            let ElementKind::Grid(g) = &e.kind else { continue };
            // Grids that cross the view plane (or are perpendicular to the view) show as vertical lines.
            let a = f.to_view(geom::at(g.start, 0.0));
            let b = f.to_view(geom::at(g.end, 0.0));
            let u = if (a.1 - b.1).abs() > 1e-6 {
                // Where the grid crosses depth 0 (sections) or its mid point (elevations).
                if f.cuts {
                    let t = a.1 / (a.1 - b.1);
                    if !(0.0..=1.0).contains(&t) {
                        continue;
                    }
                    a.0.x + (b.0.x - a.0.x) * t
                } else if (a.0.x - b.0.x).abs() < 1.0 {
                    a.0.x
                } else {
                    continue;
                }
            } else {
                continue;
            };
            d.line(Some(e.id), vec![DVec2::new(u, z0), DVec2::new(u, z1)], false, plan::GRID);
            let r = 4.0 * scale;
            let c = DVec2::new(u, z1 + r);
            d.line(Some(e.id), plan::circle(c, r, 32), true, Stroke { dash: Dash::Solid, ..plan::GRID });
            d.text(Some(e.id), c, g.name.clone(), 3.5, Anchor::Center);
        }
    }
    plan::annotation_graphics(p, view, &HashMap::new(), d);
}

/// Picks the element under a 2D point in a section/elevation drawing.
pub fn pick(dw: &Drawing, pt: DVec2, tol: f64) -> Option<Id> {
    let mut best: Option<(f64, Id)> = None;
    for (id, prim) in dw.prims.iter().rev() {
        let Some(id) = id else { continue };
        let dist = match prim {
            Prim::Line { pts, closed, .. } => {
                let mut dmin = f64::MAX;
                let n = pts.len();
                for k in 0..n.saturating_sub(1) {
                    dmin = dmin.min(geom::distance_to_segment(pts[k], pts[k + 1], pt));
                }
                if *closed && n > 2 {
                    dmin = dmin.min(geom::distance_to_segment(pts[n - 1], pts[0], pt));
                }
                dmin
            }
            Prim::Fill { tris, .. } => {
                if tris.iter().any(|t| geom::contains(&t[..], pt)) { 0.0 } else { f64::MAX }
            }
            Prim::Text { pos, .. } => pos.distance(pt),
        };
        if dist <= tol && best.is_none_or(|b| dist < b.0) {
            best = Some((dist, *id));
        }
    }
    best.map(|b| b.1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn section_through_sample_has_cut_poche_and_levels() {
        let p = crate::sample::sample_house();
        let fp = analysis::wall_footprints(&p);
        let mut v = View::new(0, "S", 100.0, ViewKind::Section { start: DVec2::new(-2000.0, 3000.0), end: DVec2::new(14000.0, 3000.0), depth: 20000.0, z_min: -1000.0, z_max: 9000.0 });
        v.style = VisualStyle::HiddenLine;
        let d = drawing(&p, &v, &fp);
        let fills = d.prims.iter().filter(|(_, pr)| matches!(pr, Prim::Fill { color, .. } if color[0] == 60)).count();
        assert!(fills >= 3, "expected cut walls and slab, got {fills}");
        let lines = d.prims.iter().filter(|(_, pr)| matches!(pr, Prim::Line { .. })).count();
        assert!(lines > 50, "{lines}");
        let e = View::new(0, "N", 100.0, ViewKind::Elevation { dir: ElevationDir::North });
        let d = drawing(&p, &e, &fp);
        assert!(d.prims.len() > 50);
    }
}
