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
/// The 3D ray behind a point of a plan, section or elevation (into the view).
pub fn view_ray(p: &Project, view: &View, q: DVec2, footprints: &HashMap<Id, Footprint>) -> Option<(DVec3, DVec3)> {
    if let Some(level) = view.plan_level() {
        let z = p.level_elevation(level) + view.view_range.cut;
        let up = matches!(view.kind, ViewKind::CeilingPlan { .. });
        return Some((DVec3::new(q.x, q.y, z), if up { DVec3::Z } else { -DVec3::Z }));
    }
    let f = view_frame(p, view, footprints)?;
    let start = if f.cuts { 0.0 } else { -1.0e7 };
    Some((f.to_world(q, start), f.look))
}

/// The nearest model face under a point of a 2D view: element, hit point and face normal.
pub fn pick_face(p: &Project, view: &View, q: DVec2, footprints: &HashMap<Id, Footprint>) -> Option<(Id, DVec3, DVec3)> {
    let (o, d) = view_ray(p, view, q, footprints)?;
    let mut best: Option<(f64, Id, DVec3)> = None;
    for e in p.elements.iter().filter(|e| e.view.is_none() && analysis::visible_in(p, view, e)) {
        let set = build3d::element_mesh(p, e, footprints);
        for m in set.by_material.values() {
            for tri in m.indices.chunks(3) {
                let (a, b, c) = (m.positions[tri[0] as usize], m.positions[tri[1] as usize], m.positions[tri[2] as usize]);
                let (e1, e2) = (b - a, c - a);
                let h = d.cross(e2);
                let det = e1.dot(h);
                if det.abs() < 1e-12 {
                    continue;
                }
                let s = o - a;
                let u = s.dot(h) / det;
                if !(0.0..=1.0).contains(&u) {
                    continue;
                }
                let qv = s.cross(e1);
                let v = d.dot(qv) / det;
                if v < 0.0 || u + v > 1.0 {
                    continue;
                }
                let t = e2.dot(qv) / det;
                if t > 1e-6 && best.is_none_or(|bb| t < bb.0) {
                    best = Some((t, e.id, e1.cross(e2).normalize_or_zero()));
                }
            }
        }
    }
    best.map(|(t, id, n)| (id, o + d * t, n))
}

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
    /// Deepest value over each pixel and its 8 neighbours (built by `finish`).
    deepest: Vec<f32>,
}

impl ZBuf {
    /// Precomputes the 3x3 neighbourhood maximum used by `visible`; outside the buffer is
    /// background (infinite depth).
    fn finish(&mut self) {
        let (w, h) = (self.w, self.h);
        let at = |x: isize, y: isize| if x < 0 || y < 0 || x as usize >= w || y as usize >= h { f32::INFINITY } else { self.depth[y as usize * w + x as usize] };
        // Separable max: rows, then columns.
        let mut rows = vec![0f32; w * h];
        for y in 0..h as isize {
            for x in 0..w as isize {
                rows[y as usize * w + x as usize] = at(x - 1, y).max(at(x, y)).max(at(x + 1, y));
            }
        }
        let row_at = |x: usize, y: isize| if y < 0 || y as usize >= h { f32::INFINITY } else { rows[y as usize * w + x] };
        let mut out = vec![0f32; w * h];
        for y in 0..h as isize {
            for x in 0..w {
                out[y as usize * w + x] = row_at(x, y - 1).max(row_at(x, y)).max(row_at(x, y + 1));
            }
        }
        self.deepest = out;
    }

    fn new(min: DVec2, max: DVec2) -> ZBuf {
        let size = (max - min).max(DVec2::splat(1.0));
        let px = (size.x.max(size.y) / 1400.0).max(5.0);
        let w = (size.x / px).ceil() as usize + 2;
        let h = (size.y / px).ceil() as usize + 2;
        ZBuf { min, px, w, h, depth: vec![f32::INFINITY; w * h], deepest: Vec::new() }
    }

    fn raster(&mut self, t: [(DVec2, f64); 3]) {
        let to_px = |q: DVec2| (q - self.min) / self.px;
        let (a, b, c) = (to_px(t[0].0), to_px(t[1].0), to_px(t[2].0));
        let det = geom::cross2(b - a, c - a);
        if det.abs() < 1e-9 {
            return;
        }
        // Scanline fill: for each pixel row, the span inside the triangle, with the depth
        // plane stepped along it.
        let (e1, e2) = (b - a, c - a);
        let (dz1, dz2) = (t[1].1 - t[0].1, t[2].1 - t[0].1);
        let dzdx = (dz1 * e2.y - dz2 * e1.y) / det;
        let dzdy = (dz2 * e1.x - dz1 * e2.x) / det;
        let y0 = a.y.min(b.y).min(c.y).floor().max(0.0) as usize;
        let y1 = (a.y.max(b.y).max(c.y).ceil().max(0.0) as usize).min(self.h - 1);
        let edges = [(a, b), (b, c), (c, a)];
        for y in y0..=y1 {
            let yc = y as f64 + 0.5;
            let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
            for (p, q) in edges {
                if (p.y - yc) * (q.y - yc) <= 0.0 && (p.y - q.y).abs() > 1e-12 {
                    let x = p.x + (yc - p.y) * (q.x - p.x) / (q.y - p.y);
                    lo = lo.min(x);
                    hi = hi.max(x);
                }
            }
            if lo > hi {
                continue;
            }
            let xs = (lo - 0.5).ceil().max(0.0) as usize;
            let xe = ((hi - 0.5).floor().max(-1.0)) as isize;
            if xe < xs as isize {
                continue;
            }
            let xe = (xe as usize).min(self.w - 1);
            let row = y * self.w;
            let mut z = t[0].1 + dzdx * (xs as f64 + 0.5 - a.x) + dzdy * (yc - a.y);
            for x in xs..=xe {
                let slot = &mut self.depth[row + x];
                if (z as f32) < *slot {
                    *slot = z as f32;
                }
                z += dzdx;
            }
        }
    }

    /// Is a point at `depth` visible (not behind the buffer by more than a tolerance)?
    fn visible(&self, q: DVec2, depth: f64) -> bool {
        let p = (q - self.min) / self.px;
        let (cx, cy) = (p.x.floor() as isize, p.y.floor() as isize);
        // An edge is visible if it is not behind the surface in its whole 3x3 neighbourhood;
        // silhouette edges touch background (infinite depth) and stay visible.
        let deepest = if cx < 0 || cy < 0 || cx as usize >= self.w || cy as usize >= self.h { f32::INFINITY } else { self.deepest[cy as usize * self.w + cx as usize] };
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
fn mesh_cut_segments(m: &crate::mesh::Mesh, f: &ViewFrame) -> Vec<(DVec2, DVec2)> {
    let mut out = Vec::new();
    {
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

/// Depth at a view point inside a view-space triangle (plane through its corners).
fn bary_depth(t: &[(DVec2, f64); 3], q: DVec2) -> Option<f64> {
    let (a, b, c) = (t[0].0, t[1].0, t[2].0);
    let den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
    if den.abs() < 1e-9 {
        return None;
    }
    let l0 = ((b.y - c.y) * (q.x - c.x) + (c.x - b.x) * (q.y - c.y)) / den;
    let l1 = ((c.y - a.y) * (q.x - c.x) + (a.x - c.x) * (q.y - c.y)) / den;
    Some(l0 * t[0].1 + l1 * t[1].1 + (1.0 - l0 - l1) * t[2].1)
}

/// The parameter interval where the line o + t·d crosses a triangle (2D, convex).
fn line_in_tri(o: DVec2, d: DVec2, t: &[DVec2; 3]) -> Option<(f64, f64)> {
    let (mut lo, mut hi) = (f64::MIN, f64::MAX);
    let ccw = (t[1] - t[0]).perp_dot(t[2] - t[0]) > 0.0;
    for k in 0..3 {
        let (a, b) = (t[k], t[(k + 1) % 3]);
        let e = b - a;
        // Inside: cross(e, p - a) >= 0 for a CCW triangle.
        let s = if ccw { 1.0 } else { -1.0 };
        let c0 = s * e.perp_dot(o - a);
        let c1 = s * e.perp_dot(d);
        if c1.abs() < 1e-12 {
            if c0 < 0.0 {
                return None;
            }
            continue;
        }
        let tt = -c0 / c1;
        if c1 > 0.0 {
            lo = lo.max(tt);
        } else {
            hi = hi.min(tt);
        }
    }
    (hi - lo > 1e-6).then_some((lo, hi))
}

/// Running-bond coursing on a vertical face: horizontal bed joints every `course`, head
/// joints every `unit`, offset by half a unit on alternate courses. Model units, aligned to
/// the world so neighbouring faces line up.
fn coursing(w: &[DVec3; 3], n: DVec3, course: f64, unit: f64) -> Vec<(DVec3, DVec3)> {
    if n.z.abs() > 0.05 {
        return vec![];
    }
    let h = DVec3::Z.cross(n).normalize_or_zero();
    if h == DVec3::ZERO {
        return vec![];
    }
    let t2 = [DVec2::new(w[0].dot(h), w[0].z), DVec2::new(w[1].dot(h), w[1].z), DVec2::new(w[2].dot(h), w[2].z)];
    let at = |q: DVec2| w[0] + h * (q.x - t2[0].x) + DVec3::Z * (q.y - t2[0].y);
    let (smin, smax) = (t2.iter().map(|q| q.x).fold(f64::MAX, f64::min), t2.iter().map(|q| q.x).fold(f64::MIN, f64::max));
    let (zmin, zmax) = (t2.iter().map(|q| q.y).fold(f64::MAX, f64::min), t2.iter().map(|q| q.y).fold(f64::MIN, f64::max));
    if (zmax - zmin) / course * (smax - smin) / unit > 200_000.0 {
        return vec![];
    }
    let mut out = Vec::new();
    let k0 = (zmin / course).floor() as i64;
    let k1 = (zmax / course).ceil() as i64;
    for k in k0..=k1 {
        let z = k as f64 * course;
        if z > zmin + 0.5 && z < zmax - 0.5 {
            if let Some((a, b)) = line_in_tri(DVec2::new(0.0, z), DVec2::X, &t2) {
                out.push((at(DVec2::new(a, z)), at(DVec2::new(b, z))));
            }
        }
        // Head joints in the course above this bed joint.
        let shift = if k.rem_euclid(2) == 0 { 0.0 } else { unit / 2.0 };
        let j0 = ((smin - shift) / unit).floor() as i64;
        let j1 = ((smax - shift) / unit).ceil() as i64;
        for j in j0..=j1 {
            let s = j as f64 * unit + shift;
            if let Some((a, b)) = line_in_tri(DVec2::new(s, 0.0), DVec2::Y, &t2) {
                let (a, b) = (a.max(z), b.min(z + course));
                if b - a > 0.5 {
                    out.push((at(DVec2::new(s, a)), at(DVec2::new(s, b))));
                }
            }
        }
    }
    out
}

/// The visible parts of a view-space segment (depth-buffer test), honouring the cut plane and
/// the far clip.
fn visible_runs(zb: &ZBuf, f: &ViewFrame, va: DVec2, da: f64, vb: DVec2, db: f64) -> Vec<(DVec2, DVec2)> {
    let mut out = Vec::new();
    let steps = ((va.distance(vb) / (zb.px * 0.7)).ceil() as usize).clamp(1, 4000);
    let mut run: Option<(DVec2, DVec2)> = None;
    for s in 0..=steps {
        let t = s as f64 / steps as f64;
        let q = va.lerp(vb, t);
        let dep = da + (db - da) * t;
        let ok = (!f.cuts || dep >= -1.0) && f.far.is_none_or(|far| dep <= far) && zb.visible(q, dep);
        match (&mut run, ok) {
            (Some(r), true) => r.1 = q,
            (None, true) => run = Some((q, q)),
            (Some(r), false) => {
                if r.0.distance(r.1) > 1e-6 {
                    out.push(*r);
                }
                run = None;
            }
            (None, false) => {}
        }
    }
    if let Some(r) = run {
        if r.0.distance(r.1) > 1e-6 {
            out.push(r);
        }
    }
    out
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
        /// Every face, for section cuts (each layer is a closed solid).
        full: MeshSet,
        /// The outer surface, for hidden-line edges, depth and surface patterns.
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
        items.push(Item { id: e.id, set: set.without_internal_faces(), full: set, status: analysis::phase_status(p, view, e) });
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
    // Cut faces cap the elements at the section plane, so nothing behind a cut shows in any
    // output (vector exports have no white masks to rely on).
    if f.cuts {
        for it in &items {
            for m in it.full.by_material.values() {
                for lp in chain(mesh_cut_segments(m, &f)).into_iter().filter(|lp| lp.len() >= 3) {
                    for [a, b, c] in geom::triangulate(&lp) {
                        zb.raster([(lp[a], 0.0), (lp[b], 0.0), (lp[c], 0.0)]);
                    }
                }
            }
        }
    }
    zb.finish();

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

    // Visible edges beyond the cut; obscured edges dashed for Show Hidden Lines elements.
    for it in &items {
        let reveal = view.hidden_lines.iter().any(|h| h.1 == it.id);
        // Projection pens of the reference Object Styles.
        let proj = plan::pen(plan::category_pens(p.element(it.id).map(|e| e.category()).unwrap_or_default()).0, view.scale);
        let stroke = match it.status {
            analysis::PhaseStatus::Existing => Stroke { color: [120, 120, 120], ..proj },
            analysis::PhaseStatus::Demolished => Stroke { color: [120, 120, 120], dash: Dash::Dotted, ..proj },
            _ => proj,
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
            let mut hidden_run: Vec<DVec2> = Vec::new();
            for s in 0..=steps {
                let t = s as f64 / steps as f64;
                let q = va.lerp(vb, t);
                let dep = da + (db - da) * t;
                let in_range = (!f.cuts || dep >= -1.0) && f.far.is_none_or(|far| dep <= far);
                let ok = in_range && zb.visible(q, dep);
                if ok {
                    run.push(q);
                } else if run.len() >= 2 {
                    d.line(Some(it.id), vec![run[0], *run.last().unwrap()], false, stroke);
                    run.clear();
                } else {
                    run.clear();
                }
                if reveal && in_range && !ok {
                    hidden_run.push(q);
                } else {
                    if hidden_run.len() >= 2 {
                        d.line(Some(it.id), vec![hidden_run[0], *hidden_run.last().unwrap()], false, plan::HIDDEN);
                    }
                    hidden_run.clear();
                }
            }
            if run.len() >= 2 {
                d.line(Some(it.id), vec![run[0], *run.last().unwrap()], false, stroke);
            }
            if hidden_run.len() >= 2 {
                d.line(Some(it.id), vec![hidden_run[0], *hidden_run.last().unwrap()], false, plan::HIDDEN);
            }
        }
    }

    // Material surface patterns on the faces seen (brick and block coursing, sand).
    for it in &items {
        for (mat, m) in &it.set.by_material {
            let sp = p.material(mat).map(|m| m.surface_pattern).unwrap_or_default();
            if sp == SurfacePattern::None {
                continue;
            }
            for tri in m.indices.chunks(3) {
                let w = [m.positions[tri[0] as usize], m.positions[tri[1] as usize], m.positions[tri[2] as usize]];
                let n = (w[1] - w[0]).cross(w[2] - w[0]).normalize_or_zero();
                // Faces turned towards the viewer only.
                if n.dot(-f.look) < 0.15 {
                    continue;
                }
                let segs: Vec<(DVec3, DVec3)> = match sp {
                    SurfacePattern::Brick => coursing(&w, n, 75.0, 225.0),
                    SurfacePattern::Block => coursing(&w, n, 200.0, 400.0),
                    SurfacePattern::Sand => {
                        let v = [f.to_view(w[0]), f.to_view(w[1]), f.to_view(w[2])];
                        let poly = [v[0].0, v[1].0, v[2].0];
                        plan::stipple(&poly, view.scale, 1.6, false, 2)
                            .into_iter()
                            .filter_map(|(a, b)| Some((f.to_world(a, bary_depth(&v, a)?), f.to_world(b, bary_depth(&v, b)?))))
                            .collect()
                    }
                    SurfacePattern::None => vec![],
                };
                for (a, b) in segs {
                    let (va, da) = f.to_view(a);
                    let (vb, db) = f.to_view(b);
                    for (p0, p1) in visible_runs(&zb, &f, va, da, vb, db) {
                        d.line(Some(it.id), vec![p0, p1], false, plan::PATTERN);
                    }
                }
            }
        }
    }

    // Cut elements at the section plane: at Medium and Fine each layer shows its material's
    // cut pattern with thin lines between layers; Coarse cuts are hollow (no coarse fill
    // pattern in the default types). Heavy outlines go round each element, or round a whole
    // group of joined elements.
    if f.cuts {
        let detailed = view.detail != DetailLevel::Coarse;
        let host = |id: Id| {
            matches!(
                p.element(id).map(|e| e.category()),
                Some(Category::Walls | Category::Floors | Category::Roofs | Category::Ceilings | Category::Stairs | Category::StructuralFraming | Category::StructuralColumns | Category::Columns | Category::StructuralFoundations | Category::Toposolid)
            )
        };
        for it in &items {
            for (mat, m) in &it.full.by_material {
                let loops = chain(mesh_cut_segments(m, &f));
                let pattern = if detailed && host(it.id) { p.material(mat).map(|m| m.cut_pattern).unwrap_or_default() } else { FillPattern::Solid };
                for lp in loops.iter().filter(|lp| lp.len() >= 3) {
                    // Opaque, so edges beyond never show through the cut.
                    d.fill(Some(it.id), lp, if pattern == FillPattern::Solid { [0, 0, 0, 255] } else { [255, 255, 255, 255] });
                    for (a, b) in plan::pattern_lines(lp, pattern, view.scale) {
                        d.line(Some(it.id), vec![a, b], false, plan::PATTERN);
                    }
                    if detailed {
                        d.line(Some(it.id), lp.clone(), true, plan::pen(1, view.scale));
                    }
                }
            }
        }
        let cuts: Vec<(Id, Vec<Vec<DVec2>>)> = items
            .iter()
            .map(|it| (it.id, it.full.by_material.values().flat_map(|m| chain(mesh_cut_segments(m, &f))).collect::<Vec<_>>()))
            .filter(|c| !c.1.is_empty())
            .collect();
        // Groups of joined elements (union-find over the join pairs).
        let mut group: Vec<usize> = (0..cuts.len()).collect();
        fn root(g: &mut Vec<usize>, k: usize) -> usize {
            let mut r = k;
            while g[r] != r {
                r = g[r];
            }
            g[k] = r;
            r
        }
        for (a, b) in &p.joins {
            if let (Some(i), Some(j)) = (cuts.iter().position(|c| c.0 == *a), cuts.iter().position(|c| c.0 == *b)) {
                let (ri, rj) = (root(&mut group, i), root(&mut group, j));
                group[ri] = rj;
            }
        }
        let mut done = vec![false; cuts.len()];
        for k in 0..cuts.len() {
            let r = root(&mut group, k);
            if done[k] {
                continue;
            }
            let members: Vec<usize> = (0..cuts.len()).filter(|m| root(&mut group, *m) == r).collect();
            for m in &members {
                done[*m] = true;
            }
            // Outline the union of the members' layers so no heavy line runs between layers
            // or between joined elements.
            let mut union: Option<geo::MultiPolygon<f64>> = None;
            for m in &members {
                let (_, loops) = &cuts[*m];
                for lp in loops.iter().filter(|lp| lp.len() >= 3) {
                    let poly = geo::MultiPolygon::new(vec![geo::Polygon::new(geo::LineString::from(lp.iter().map(|q| geo::Coord { x: q.x, y: q.y }).collect::<Vec<_>>()), vec![])]);
                    union = Some(match union {
                        None => poly,
                        Some(u) => geo::BooleanOps::union(&u, &poly),
                    });
                }
            }
            let owner = cuts[members[0]].0;
            for poly in union.iter().flatten() {
                for ring in std::iter::once(poly.exterior()).chain(poly.interiors()) {
                    let mut pts: Vec<DVec2> = ring.coords().map(|c| DVec2::new(c.x, c.y)).collect();
                    if pts.len() > 1 && pts[0] == pts[pts.len() - 1] {
                        pts.pop();
                    }
                    if pts.len() >= 3 {
                        d.line(Some(owner), pts, true, plan::pen(plan::category_pens(p.element(owner).map(|e| e.category()).unwrap_or_default()).1, view.scale).as_cut());
                    }
                }
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
            d.line(Some(id), vec![DVec2::new(u0, y), DVec2::new(u1, y)], false, Stroke::new(0.13, [0, 0, 0], Dash::DashDot));
            // Target head: a circle with two filled quadrants, name above and elevation below.
            let r = 1.6 * scale;
            let c = DVec2::new(u1 + r, y);
            d.line(Some(id), plan::circle(c, r, 32), true, Stroke::new(0.18, [0, 0, 0], Dash::Solid));
            for q in [0.0f64, 2.0] {
                let mut pts = vec![c];
                for k in 0..=8 {
                    let a = (q + k as f64 / 8.0) * std::f64::consts::FRAC_PI_2;
                    pts.push(c + DVec2::new(a.cos(), a.sin()) * r);
                }
                d.fill(Some(id), &pts, [0, 0, 0, 255]);
            }
            // As the reference level head: name above the line and elevation below it, both
            // right-aligned just before the target.
            let x = c.x - r * 1.5;
            let gap = 0.6 * scale;
            d.prims.push((Some(id), Prim::Text { pos: DVec2::new(x, y + gap), text: l.name.clone(), size: 2.5, color: [0, 0, 0], anchor: Anchor::Right, angle: 0.0 }));
            d.prims.push((Some(id), Prim::Text { pos: DVec2::new(x, y - gap - 2.5 * 1.25 * scale), text: p.units.length(l.elevation), size: 2.5, color: [0, 0, 0], anchor: Anchor::Right, angle: 0.0 }));
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
            let r = 6.0 * scale;
            let c = DVec2::new(u, z1 + r);
            d.line(Some(e.id), plan::circle(c, r, 32), true, Stroke { dash: Dash::Solid, ..plan::GRID });
            d.text(Some(e.id), c, g.name.clone(), 4.5, Anchor::Center);
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
        // Cut regions are opaque white with material patterns at Medium detail.
        let fills = d.prims.iter().filter(|(_, pr)| matches!(pr, Prim::Fill { color, .. } if *color == [255, 255, 255, 255])).count();
        assert!(fills >= 3, "expected cut walls and slab, got {fills}");
        let pattern = d.prims.iter().filter(|(_, pr)| matches!(pr, Prim::Line { stroke, .. } if *stroke == plan::PATTERN)).count();
        assert!(pattern > 20, "expected cut patterns, got {pattern}");
        let lines = d.prims.iter().filter(|(_, pr)| matches!(pr, Prim::Line { .. })).count();
        assert!(lines > 50, "{lines}");
        let e = View::new(0, "N", 100.0, ViewKind::Elevation { dir: ElevationDir::North });
        let d = drawing(&p, &e, &fp);
        assert!(d.prims.len() > 50);
    }

    #[test]
    fn faces_pick_from_2d_views_and_hidden_lines_dash_in_plan() {
        let mut p = crate::defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let wt = p.types_of(Category::Walls).next().unwrap().id;
        let ft = p.types_of(Category::Floors).next().unwrap().id;
        let wall = crate::edit::add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(6000.0, 0.0), 3000.0).unwrap();
        let fp = analysis::wall_footprints(&p);
        // South elevation looks north at the wall's exterior face.
        let south = p.views.iter().find(|v| matches!(v.kind, ViewKind::Elevation { dir: ElevationDir::South })).unwrap().clone();
        let (id, q, n) = pick_face(&p, &south, DVec2::new(0.0, 1500.0), &fp).or_else(|| {
            // The elevation frame's horizontal origin may differ: try along the wall.
            (-8000..8000).step_by(500).find_map(|x| pick_face(&p, &south, DVec2::new(x as f64, 1500.0), &fp))
        }).expect("a face of the wall");
        assert_eq!(id, wall);
        assert!(n.y.abs() > 0.99, "{n:?}");
        assert!((q.z - 1500.0).abs() < 1.0);
        // A plan ray hits the wall top only below the cut: walls are cut, so a plan pick
        // through the wall finds its bottom-most face or nothing — floors are found from above.
        let floor = crate::edit::add_floor(&mut p, lvl, ft, vec![DVec2::new(1000.0, 1000.0), DVec2::new(5000.0, 1000.0), DVec2::new(5000.0, 4000.0), DVec2::new(1000.0, 4000.0)]).unwrap();
        let fp = analysis::wall_footprints(&p);
        let plan = p.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. })).unwrap().clone();
        let (fid, _, fnorm) = pick_face(&p, &plan, DVec2::new(3000.0, 2500.0), &fp).unwrap();
        assert_eq!(fid, floor);
        assert!(fnorm.z.abs() > 0.99);

        // Show Hidden Lines: a line under the floor turns dashed where the floor covers it.
        let vid = plan.id;
        let line = crate::edit::add_line(&mut p, None, Some(lvl), vec![DVec2::new(0.0, 2500.0), DVec2::new(6000.0, 2500.0)], None, LineStyle::Medium).unwrap();
        p.view_mut(vid).unwrap().hidden_lines.push((floor, line));
        let fp = analysis::wall_footprints(&p);
        let d = plan::floor_plan(&p, p.view(vid).unwrap(), &fp);
        let segs: Vec<(f64, Dash)> = d
            .prims
            .iter()
            .filter(|(i, _)| *i == Some(line))
            .filter_map(|(_, pr)| match pr {
                Prim::Line { pts, stroke, .. } => Some(((pts[0].x + pts[1].x) / 2.0, stroke.dash)),
                _ => None,
            })
            .collect();
        assert!(segs.iter().any(|(x, dash)| *x > 1000.0 && *x < 5000.0 && *dash == Dash::Dashed), "{segs:?}");
        assert!(segs.iter().any(|(x, dash)| *x < 1000.0 && *dash == Dash::Solid), "{segs:?}");
    }

    #[test]
    fn joined_wall_and_floor_share_one_cut_outline() {
        let mut p = crate::defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let wt = p.types_of(Category::Walls).next().unwrap().id;
        let ft = p.types_of(Category::Floors).next().unwrap().id;
        let wall = crate::edit::add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(0.0, 6000.0), 3000.0).unwrap();
        // The slab runs under the wall, so their cuts touch along the wall base.
        let floor = crate::edit::add_floor(&mut p, lvl, ft, vec![DVec2::new(-1000.0, -1000.0), DVec2::new(4000.0, -1000.0), DVec2::new(4000.0, 7000.0), DVec2::new(-1000.0, 7000.0)]).unwrap();
        let v = View::new(0, "S", 100.0, ViewKind::Section { start: DVec2::new(-3000.0, 3000.0), end: DVec2::new(6000.0, 3000.0), depth: 10000.0, z_min: -2000.0, z_max: 5000.0 });
        let heavy = |p: &Project| {
            let fp = analysis::wall_footprints(p);
            drawing(p, &v, &fp).prims.iter().filter(|(_, pr)| matches!(pr, Prim::Line { stroke, closed: true, .. } if stroke.width >= 0.45)).count()
        };
        let before = heavy(&p);
        assert!(before >= 2, "{before}");
        crate::edit::join_geometry(&mut p, wall, floor).unwrap();
        assert!(crate::edit::join_geometry(&mut p, floor, wall).is_err());
        let after = heavy(&p);
        assert!(after < before, "joined cuts should merge: {before} -> {after}");
        crate::edit::unjoin_geometry(&mut p, floor, wall).unwrap();
        assert_eq!(heavy(&p), before);
        // Deleting an element drops its joins.
        crate::edit::join_geometry(&mut p, wall, floor).unwrap();
        p.elements.retain(|e| e.id != floor);
        crate::edit::tidy(&mut p);
        assert!(p.joins.is_empty());
    }
}
