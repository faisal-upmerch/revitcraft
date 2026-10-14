//! Turns elements into 3D meshes.

use crate::analysis::{self, Footprint};
use crate::csg::{self, Solid};
use crate::family_geom;
use crate::geom::{self, DVec2, DVec3};
use crate::mesh::{Mesh, MeshSet};
use crate::model::*;
use crate::skeleton;
use std::collections::HashMap;

pub use crate::family_geom::{InstanceFrame, instance_frame};

/// Builds geometry for one element. `footprints` comes from [`analysis::wall_footprints`].
pub fn element_mesh(p: &Project, e: &Element, footprints: &HashMap<Id, Footprint>) -> MeshSet {
    if e.view.is_some() {
        return MeshSet::default();
    }
    match &e.kind {
        ElementKind::Wall(w) => match footprints.get(&e.id) {
            Some(fp) => wall(p, e.id, w, fp),
            None => MeshSet::default(),
        },
        ElementKind::Floor(f) => floor(p, e.id, f),
        ElementKind::Roof(r) => roof(p, r),
        ElementKind::Ceiling(c) => ceiling(p, c),
        ElementKind::Stair(s) => stair(p, s),
        ElementKind::Railing(r) => railing(p, r),
        ElementKind::WallFoundation(f) => wall_foundation(p, f),
        ElementKind::Instance(i) => family_geom::instance_mesh(p, i),
        _ => MeshSet::default(),
    }
}

// ---------------------------------------------------------------- walls

#[derive(Clone, Copy, Debug)]
struct Opening {
    u0: f64,
    u1: f64,
    z0: f64,
    z1: f64,
}

impl Opening {
    fn contains(&self, u: f64, z: f64) -> bool {
        u > self.u0 && u < self.u1 && z > self.z0 && z < self.z1
    }
}

/// Opening rectangles (along-wall u, absolute z) cut by hosted doors/windows and wall openings.
pub fn wall_openings(p: &Project, id: Id, w: &Wall) -> Vec<(f64, f64, f64, f64)> {
    let len = w.length();
    let zb = analysis::wall_base_z(p, w);
    let zt = wall_top_extent(p, w);
    let mut out: Vec<(f64, f64, f64, f64)> = p
        .hosted_by(id)
        .filter_map(|(_, i)| {
            let (ow, oh) = analysis::opening_size(p, i);
            let u0 = (i.offset_along_host - ow / 2.0).max(0.0);
            let u1 = (i.offset_along_host + ow / 2.0).min(len);
            let z0 = (p.level_elevation(i.level) + i.elevation).max(zb);
            let z1 = (p.level_elevation(i.level) + i.elevation + oh).min(zt);
            (u1 - u0 > 1.0 && z1 - z0 > 1.0).then_some((u0, u1, z0, z1))
        })
        .collect();
    for o in &w.openings {
        let (u0, u1) = (o.u0.max(0.0), o.u1.min(len));
        let (z0, z1) = ((zb + o.z0).max(zb), (zb + o.z1).min(zt));
        if u1 - u0 > 1.0 && z1 - z0 > 1.0 {
            out.push((u0, u1, z0, z1));
        }
    }
    out
}

/// Wall top before trimming, including attachment to floors/roofs above.
pub fn wall_top_extent(p: &Project, w: &Wall) -> f64 {
    let own = analysis::wall_top_z(p, w);
    match w.attach_top.and_then(|id| p.element(id)) {
        Some(Element { kind: ElementKind::Roof(r), .. }) => {
            // Extend to the highest underside point over the wall; the roof cutter trims the rest.
            let path = analysis::wall_path(w);
            let half = analysis::wall_thickness(p, w);
            let (mn, mx) = geom::bounds(path.iter().copied());
            let best = roof_underside(p, r)
                .iter()
                .filter(|t| {
                    let (tmn, tmx) = geom::bounds(t.iter().map(|v| v.truncate()));
                    tmx.x >= mn.x - half && tmn.x <= mx.x + half && tmx.y >= mn.y - half && tmn.y <= mx.y + half
                })
                .flat_map(|t| t.iter().map(|v| v.z))
                .fold(f64::MIN, f64::max);
            if best > f64::MIN { best + 10.0 } else { own }
        }
        Some(Element { kind: ElementKind::Floor(f), .. }) => analysis::floor_top_z(p, f) - analysis::floor_thickness(p, f),
        Some(Element { kind: ElementKind::Ceiling(c), .. }) => p.level_elevation(c.level) + c.height_offset,
        _ => own,
    }
}

fn wall_base_extent(p: &Project, w: &Wall) -> f64 {
    match w.attach_base.and_then(|id| p.element(id)) {
        Some(Element { kind: ElementKind::Floor(f), .. }) => analysis::floor_top_z(p, f),
        _ => analysis::wall_base_z(p, w),
    }
}

/// Height of a 3D triangle above a plan point (None if outside it).
pub fn tri_height(t: &[DVec3; 3], q: DVec2) -> Option<f64> {
    let (a, b, c) = (t[0].truncate(), t[1].truncate(), t[2].truncate());
    let det = geom::cross2(b - a, c - a);
    if det.abs() < 1e-9 {
        return None;
    }
    let l1 = geom::cross2(b - q, c - q) / det;
    let l2 = geom::cross2(c - q, a - q) / det;
    let l3 = 1.0 - l1 - l2;
    (l1 >= -1e-6 && l2 >= -1e-6 && l3 >= -1e-6).then(|| l1 * t[0].z + l2 * t[1].z + l3 * t[2].z)
}

fn wall(p: &Project, id: Id, w: &Wall, fp: &Footprint) -> MeshSet {
    let zb = wall_base_extent(p, w);
    let zt = wall_top_extent(p, w);
    if zt - zb < 1.0 || w.length() < 1.0 {
        return MeshSet::default();
    }
    let ty = p.sys_type(w.type_id);
    let openings: Vec<Opening> = wall_openings(p, id, w).into_iter().map(|(u0, u1, z0, z1)| Opening { u0, u1, z0, z1 }).collect();
    let mut set = match ty.map(|t| t.wall_kind) {
        Some(WallKind::Curtain) => curtain_wall(p, w, ty.unwrap(), zb, zt),
        Some(WallKind::Stacked) => {
            let t = ty.unwrap();
            let mut set = MeshSet::default();
            let mut z = zb;
            let n = t.stack.len();
            for (k, (sub, h)) in t.stack.iter().enumerate() {
                let top = if *h <= 0.0 || k + 1 == n { zt } else { (z + h).min(zt) };
                if let Some(st) = p.sys_type(*sub) {
                    let mut layers = st.layers.clone();
                    if layers.is_empty() {
                        layers.push(Layer { material: "Default".into(), thickness: 200.0, ..Default::default() });
                    }
                    basic_wall(w, fp, &layers, analysis::wall_thickness(p, w), z, top, &openings, &mut set);
                }
                z = top;
                if z >= zt {
                    break;
                }
            }
            set
        }
        _ => {
            let layers: Vec<Layer> = match ty {
                Some(t) if !t.layers.is_empty() => t.layers.clone(),
                _ => vec![Layer { material: "Default".into(), thickness: 200.0, ..Default::default() }],
            };
            let mut set = MeshSet::default();
            basic_wall(w, fp, &layers, analysis::wall_thickness(p, w), zb, zt, &openings, &mut set);
            set
        }
    };
    // Trim under an attached roof.
    if let Some(Element { kind: ElementKind::Roof(r), .. }) = w.attach_top.and_then(|id| p.element(id)) {
        let cutter = roof_upper_cutter(p, r);
        set = csg::subtract_set(&set, &cutter);
    }
    set
}

/// Builds a layered wall along its path (straight or tessellated arc).
#[allow(clippy::too_many_arguments)]
fn basic_wall(w: &Wall, fp: &Footprint, layers: &[Layer], t: f64, zb: f64, zt: f64, openings: &[Opening], set: &mut MeshSet) {
    let path = analysis::wall_path(w);
    let nseg = path.len() - 1;
    let mut u_acc = 0.0;
    for k in 0..nseg {
        let (a, b) = (path[k], path[k + 1]);
        let seg_len = a.distance(b);
        if seg_len < 1e-6 {
            continue;
        }
        let dir = (b - a) / seg_len;
        let n = geom::perp(dir);
        // Segment footprint corners (start/end at lateral offsets).
        let sl = fp.left[k.min(fp.left.len() - 1)];
        let el = fp.left[(k + 1).min(fp.left.len() - 1)];
        let sr = fp.right[k.min(fp.right.len() - 1)];
        let er = fp.right[(k + 1).min(fp.right.len() - 1)];
        let seg = SegCtx { a, dir, n, u0: u_acc, len: seg_len, first: k == 0, last: k + 1 == nseg, sl, el, sr, er, t };
        build_segment(&seg, layers, zb, zt, openings, set);
        u_acc += seg_len;
    }
}

struct SegCtx {
    a: DVec2,
    dir: DVec2,
    n: DVec2,
    /// Distance along the whole wall where this segment starts.
    u0: f64,
    len: f64,
    first: bool,
    last: bool,
    sl: DVec2,
    el: DVec2,
    sr: DVec2,
    er: DVec2,
    t: f64,
}

impl SegCtx {
    fn start_at(&self, o: f64) -> DVec2 {
        self.sr.lerp(self.sl, if self.t <= 0.0 { 0.5 } else { (o + self.t / 2.0) / self.t })
    }
    fn end_at(&self, o: f64) -> DVec2 {
        self.er.lerp(self.el, if self.t <= 0.0 { 0.5 } else { (o + self.t / 2.0) / self.t })
    }
    /// World point at global u (clamped to this segment), lateral o, height z.
    fn world(&self, u: f64, o: f64, z: f64) -> DVec3 {
        geom::at(self.a + self.dir * (u - self.u0) + self.n * o, z)
    }
    fn along(&self, q: DVec2) -> f64 {
        self.u0 + (q - self.a).dot(self.dir)
    }
}

fn build_segment(s: &SegCtx, layers: &[Layer], zb: f64, zt: f64, openings: &[Opening], set: &mut MeshSet) {
    let (seg0, seg1) = (s.u0, s.u0 + s.len);
    let n3 = geom::at(s.n, 0.0);
    let d3 = geom::at(s.dir, 0.0);
    let eps = 0.5;
    let t = s.t;
    let mut o1 = t / 2.0;
    for layer in layers {
        let o0 = o1 - layer.thickness;
        let m = set.mesh(&layer.material);
        // Exterior and interior faces with rectangular holes.
        for (o, normal, outer) in [(o1, n3, (o1 - t / 2.0).abs() < 1e-6), (o0, -n3, (o0 + t / 2.0).abs() < 1e-6)] {
            if !outer {
                continue;
            }
            let u_start = if s.first { s.along(s.start_at(o)) } else { seg0 };
            let u_end = if s.last { s.along(s.end_at(o)) } else { seg1 };
            let mut us = vec![u_start, u_end];
            let mut zs = vec![zb, zt];
            for op in openings {
                us.extend([op.u0, op.u1].into_iter().filter(|u| *u > u_start && *u < u_end));
                zs.extend([op.z0, op.z1].into_iter().filter(|z| *z > zb && *z < zt));
            }
            us.sort_by(f64::total_cmp);
            us.dedup_by(|a, b| (*a - *b).abs() < 1e-6);
            zs.sort_by(f64::total_cmp);
            zs.dedup_by(|a, b| (*a - *b).abs() < 1e-6);
            for ui in 0..us.len() - 1 {
                for zi in 0..zs.len() - 1 {
                    let (ua, ub, za, zc) = (us[ui], us[ui + 1], zs[zi], zs[zi + 1]);
                    if openings.iter().any(|op| op.contains((ua + ub) / 2.0, (za + zc) / 2.0)) {
                        continue;
                    }
                    m.add_quad_facing(s.world(ua, o, za), s.world(ub, o, za), s.world(ub, o, zc), s.world(ua, o, zc), normal);
                }
            }
        }
        // Top and bottom, split where openings touch them.
        let start0 = if s.first { s.start_at(o0) } else { s.a + s.n * o0 };
        let start1 = if s.first { s.start_at(o1) } else { s.a + s.n * o1 };
        let end0 = if s.last { s.end_at(o0) } else { s.a + s.dir * s.len + s.n * o0 };
        let end1 = if s.last { s.end_at(o1) } else { s.a + s.dir * s.len + s.n * o1 };
        let quad = [start0, end0, end1, start1];
        for (z, normal, touch_top) in [(zt, DVec3::Z, true), (zb, -DVec3::Z, false)] {
            let mut gaps: Vec<(f64, f64)> = openings
                .iter()
                .filter(|op| if touch_top { op.z1 >= zt - eps } else { op.z0 <= zb + eps })
                .map(|op| (op.u0, op.u1))
                .collect();
            gaps.sort_by(|a, b| a.0.total_cmp(&b.0));
            let mut lo = f64::MIN;
            let mut pieces = Vec::new();
            for (g0, g1) in gaps {
                pieces.push((lo, g0));
                lo = lo.max(g1);
            }
            pieces.push((lo, f64::MAX));
            for (a, b) in pieces {
                if b - a < 1e-6 {
                    continue;
                }
                let poly = geom::clip_convex(&quad, |q| s.along(q), a, b);
                if poly.len() >= 3 {
                    let pts: Vec<DVec3> = poly.iter().map(|q| geom::at(*q, z)).collect();
                    m.add_polygon_facing(&pts, normal);
                }
            }
        }
        if s.first {
            m.add_quad_facing(geom::at(start0, zb), geom::at(start1, zb), geom::at(start1, zt), geom::at(start0, zt), -d3);
        }
        if s.last {
            m.add_quad_facing(geom::at(end0, zb), geom::at(end1, zb), geom::at(end1, zt), geom::at(end0, zt), d3);
        }
        // Reveals of openings whose edges fall within this segment.
        for op in openings {
            if op.u0 >= seg0 - 1e-6 && op.u0 <= seg1 + 1e-6 {
                m.add_quad_facing(s.world(op.u0, o0, op.z0), s.world(op.u0, o1, op.z0), s.world(op.u0, o1, op.z1), s.world(op.u0, o0, op.z1), d3);
            }
            if op.u1 >= seg0 - 1e-6 && op.u1 <= seg1 + 1e-6 {
                m.add_quad_facing(s.world(op.u1, o0, op.z0), s.world(op.u1, o1, op.z0), s.world(op.u1, o1, op.z1), s.world(op.u1, o0, op.z1), -d3);
            }
            let (a, b) = (op.u0.max(seg0), op.u1.min(seg1));
            if b - a > 1e-6 {
                if op.z0 > zb + eps {
                    m.add_quad_facing(s.world(a, o0, op.z0), s.world(b, o0, op.z0), s.world(b, o1, op.z0), s.world(a, o1, op.z0), DVec3::Z);
                }
                if op.z1 < zt - eps {
                    m.add_quad_facing(s.world(a, o0, op.z1), s.world(b, o0, op.z1), s.world(b, o1, op.z1), s.world(a, o1, op.z1), -DVec3::Z);
                }
            }
        }
        o1 = o0;
    }
}

/// Grid lines of a curtain wall: (u positions, v heights above base), including the ends.
pub fn curtain_grid(p: &Project, w: &Wall) -> (Vec<f64>, Vec<f64>) {
    let len = w.length();
    let h = (wall_top_extent(p, w) - wall_base_extent(p, w)).max(0.0);
    let t = p.sys_type(w.type_id);
    let (mut u, mut v) = match &w.curtain {
        Some(g) => (g.u.clone(), g.v.clone()),
        None => {
            let su = t.map(|t| t.prop("Vertical Spacing", 1500.0)).unwrap_or(1500.0);
            let sv = t.map(|t| t.prop("Horizontal Spacing", 0.0)).unwrap_or(0.0);
            let us = if su > 1.0 { (1..(len / su).ceil() as usize).map(|k| len * k as f64 / (len / su).ceil()).collect() } else { vec![] };
            let vs = if sv > 1.0 { (1..(h / sv).ceil() as usize).map(|k| h * k as f64 / (h / sv).ceil()).collect() } else { vec![] };
            (us, vs)
        }
    };
    u.retain(|x| *x > 1.0 && *x < len - 1.0);
    v.retain(|x| *x > 1.0 && *x < h - 1.0);
    u.insert(0, 0.0);
    u.push(len);
    v.insert(0, 0.0);
    v.push(h);
    u.sort_by(f64::total_cmp);
    v.sort_by(f64::total_cmp);
    (u, v)
}

fn curtain_wall(p: &Project, w: &Wall, t: &SystemType, zb: f64, zt: f64) -> MeshSet {
    let mut set = MeshSet::default();
    let (us, vs) = curtain_grid(p, w);
    let mw = t.prop("Mullion Width", 50.0);
    let md = t.prop("Mullion Depth", 150.0);
    let mullion = t.text("Mullion Material", "Aluminum");
    let glass = t.text("Panel Material", "Glass");
    let solid = t.text("Solid Panel Material", "Aluminum");
    let panel_t = 24.0;
    let point = |u: f64| analysis::wall_point(w, u);
    // Vertical mullions.
    for &u in &us {
        let (c, d) = point(u);
        let n = geom::perp(d);
        let o = geom::at(c - d * (mw / 2.0) - n * (md / 2.0), zb);
        set.add_box(&mullion, o, geom::at(d * mw, 0.0), geom::at(n * md, 0.0), DVec3::Z * (zt - zb));
    }
    // Horizontal mullions and panels per bay (subdivided along arcs).
    for i in 0..us.len() - 1 {
        let (u0, u1) = (us[i], us[i + 1]);
        let steps = if w.arc_mid.is_some() { ((u1 - u0) / 400.0).ceil().max(1.0) as usize } else { 1 };
        for k in 0..steps {
            let (a, b) = (u0 + (u1 - u0) * k as f64 / steps as f64, u0 + (u1 - u0) * (k + 1) as f64 / steps as f64);
            let (pa, _) = point(a);
            let (pb, _) = point(b);
            let d = (pb - pa).normalize_or_zero();
            let n = geom::perp(d);
            let len = pa.distance(pb);
            for &v in &vs {
                let z = zb + v;
                let o = geom::at(pa - n * (md / 2.0), (z - mw / 2.0).max(zb));
                let hgt = (z + mw / 2.0).min(zt) - (z - mw / 2.0).max(zb);
                set.add_box(&mullion, o, geom::at(d * len, 0.0), geom::at(n * md, 0.0), DVec3::Z * hgt);
            }
            for j in 0..vs.len() - 1 {
                let key = format!("{i},{j}");
                let kind = w.curtain.as_ref().and_then(|g| g.panels.get(&key)).copied().unwrap_or(PanelKind::Glazed);
                let (z0, z1) = (zb + vs[j], zb + vs[j + 1]);
                let mat = match kind {
                    PanelKind::Empty => continue,
                    PanelKind::Solid => &solid,
                    PanelKind::Glazed | PanelKind::Door => &glass,
                };
                let o = geom::at(pa - n * (panel_t / 2.0), z0);
                set.add_box(mat, o, geom::at(d * len, 0.0), geom::at(n * panel_t, 0.0), DVec3::Z * (z1 - z0));
                if kind == PanelKind::Door && k == 0 {
                    let (pc, _) = point((u0 + u1) / 2.0);
                    let o = geom::at(pc - n * 30.0, z0 + (z1 - z0) * 0.48);
                    set.add_box("Aluminum", o, geom::at(d * 120.0, 0.0), geom::at(n * 60.0, 0.0), DVec3::Z * 25.0);
                }
            }
        }
    }
    set
}

// ---------------------------------------------------------------- floors, ceilings, shafts

/// Shaft openings overlapping the vertical band [z0, z1].
pub fn shafts_cutting(p: &Project, z0: f64, z1: f64) -> Vec<Vec<DVec2>> {
    p.elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::Shaft(s) => {
                let b = p.level_elevation(s.base_level) + s.base_offset;
                let t = match s.top_level.and_then(|l| p.level(l)) {
                    Some(l) => l.elevation + s.top_offset,
                    None => b + s.unconnected_height,
                };
                (b < z1 && t > z0 && s.boundary.len() >= 3).then(|| s.boundary.clone())
            }
            _ => None,
        })
        .collect()
}

fn floor(p: &Project, _id: Id, f: &Floor) -> MeshSet {
    let mut set = MeshSet::default();
    if f.boundary.len() < 3 {
        return set;
    }
    let top = analysis::floor_top_z(p, f);
    let thick = analysis::floor_thickness(p, f);
    let mut holes = f.holes.clone();
    holes.extend(shafts_cutting(p, top - thick, top));
    let mut z = top;
    match p.sys_type(f.type_id) {
        Some(t) if !t.layers.is_empty() => {
            for l in &t.layers {
                set.add_extrusion_with_holes(&l.material, &f.boundary, &holes, z - l.thickness, z);
                z -= l.thickness;
            }
        }
        _ => set.add_extrusion_with_holes("Default", &f.boundary, &holes, z - 300.0, z),
    }
    if f.slope.is_some() {
        // Shear the slab so its top follows the slope arrow.
        for m in set.by_material.values_mut() {
            for v in &mut m.positions {
                let dz = analysis::floor_top_at(p, f, v.truncate()) - top;
                v.z += dz;
            }
        }
    }
    set
}

fn ceiling(p: &Project, c: &Ceiling) -> MeshSet {
    let mut set = MeshSet::default();
    if c.boundary.len() < 3 {
        return set;
    }
    let z = p.level_elevation(c.level) + c.height_offset;
    let thick = analysis::ceiling_thickness(p, c);
    let mut holes = c.holes.clone();
    holes.extend(shafts_cutting(p, z, z + thick));
    let mut zz = z + thick;
    match p.sys_type(c.type_id) {
        Some(t) if !t.layers.is_empty() => {
            for l in &t.layers {
                set.add_extrusion_with_holes(&l.material, &c.boundary, &holes, zz - l.thickness, zz);
                zz -= l.thickness;
            }
        }
        _ => set.add_extrusion_with_holes("Plasterboard", &c.boundary, &holes, z, z + thick),
    }
    set
}

fn wall_foundation(p: &Project, f: &WallFoundation) -> MeshSet {
    let mut set = MeshSet::default();
    let Some(w) = p.wall(f.wall) else { return set };
    let t = p.sys_type(f.type_id);
    let width = t.map(|t| t.prop("Width", 600.0)).unwrap_or(600.0);
    let depth = t.map(|t| t.prop("Foundation Thickness", 300.0)).unwrap_or(300.0);
    let mat = t.map(|t| t.primary_material()).unwrap_or_else(|| "Concrete".into());
    let zb = analysis::wall_base_z(p, w);
    let path = analysis::wall_path(w);
    for s in path.windows(2) {
        let d = (s[1] - s[0]).normalize_or_zero();
        let n = geom::perp(d) * (width / 2.0);
        let ext = d * (width / 2.0 - analysis::wall_thickness(p, w) / 2.0).max(0.0);
        let q = [s[0] - n - ext, s[1] - n + ext, s[1] + n + ext, s[0] + n - ext];
        set.add_extrusion(&mat, &q, zb - depth, zb);
    }
    set
}

// ---------------------------------------------------------------- roofs

/// Footprint in CCW order with matching slope flags.
pub fn roof_ccw(r: &Roof) -> (Vec<DVec2>, Vec<bool>) {
    let flags = analysis::roof_edge_slopes(r);
    let n = r.footprint.len();
    if geom::signed_area(&r.footprint) >= 0.0 {
        return (r.footprint.clone(), flags);
    }
    let pts: Vec<DVec2> = r.footprint.iter().rev().copied().collect();
    // Reversed edge i is original edge n-2-i.
    let f = (0..n).map(|i| flags[(2 * n - 2 - i) % n]).collect();
    (pts, f)
}

/// Roof underside triangles (absolute coordinates).
pub fn roof_underside(p: &Project, r: &Roof) -> Vec<[DVec3; 3]> {
    if r.footprint.len() < 3 {
        return vec![];
    }
    let base = analysis::roof_base_z(p, r);
    match &r.kind {
        RoofKind::Extrusion { start, end, profile } => {
            let mut out = Vec::new();
            let d = (*end - *start).normalize_or_zero();
            let n = geom::perp(d);
            for s in profile.windows(2) {
                let q = |pt: DVec2, along: DVec2| geom::at(along + n * pt.x, base + pt.y);
                let (a0, a1, b0, b1) = (q(s[0], *start), q(s[1], *start), q(s[0], *end), q(s[1], *end));
                out.push([a0, a1, b1]);
                out.push([a0, b1, b0]);
            }
            out
        }
        RoofKind::Footprint => {
            let (pts, flags) = roof_ccw(r);
            if !flags.iter().any(|f| *f) {
                let eave = geom::offset(&pts, r.overhang);
                return geom::triangulate(&eave)
                    .into_iter()
                    .map(|[a, b, c]| [geom::at(eave[a], base), geom::at(eave[b], base), geom::at(eave[c], base)])
                    .collect();
            }
            let tan = r.slope_deg.clamp(1.0, 85.0).to_radians().tan();
            let eave = geom::offset(&pts, r.overhang);
            let speeds: Vec<f64> = flags.iter().map(|f| if *f { 1.0 } else { 0.0 }).collect();
            let s = skeleton::sweep(&eave, &speeds);
            let z_eave = base - r.overhang * tan;
            s.faces.iter().map(|(_, t)| t.map(|(q, time)| geom::at(q, z_eave + time * tan))).collect()
        }
    }
}

/// Skeleton arcs (ridges, hips, valleys) in plan for drawing.
pub fn roof_ridges(r: &Roof) -> Vec<(DVec2, DVec2)> {
    if r.footprint.len() < 3 || !matches!(r.kind, RoofKind::Footprint) {
        return vec![];
    }
    let (pts, flags) = roof_ccw(r);
    if !flags.iter().any(|f| *f) {
        return vec![];
    }
    let eave = geom::offset(&pts, r.overhang);
    let speeds: Vec<f64> = flags.iter().map(|f| if *f { 1.0 } else { 0.0 }).collect();
    let s = skeleton::sweep(&eave, &speeds);
    merge_collinear(s.arcs)
}

fn merge_collinear(mut segs: Vec<(DVec2, DVec2)>) -> Vec<(DVec2, DVec2)> {
    // Join consecutive collinear pieces so ridges draw as single lines.
    let mut changed = true;
    while changed {
        changed = false;
        'outer: for i in 0..segs.len() {
            for j in 0..segs.len() {
                if i == j {
                    continue;
                }
                let (a, b) = segs[i];
                let (c, d) = segs[j];
                if b.distance(c) < 1e-6 && geom::cross2((b - a).normalize_or_zero(), (d - c).normalize_or_zero()).abs() < 1e-6 {
                    segs[i] = (a, d);
                    segs.remove(j);
                    changed = true;
                    break 'outer;
                }
            }
        }
    }
    segs
}

fn roof(p: &Project, r: &Roof) -> MeshSet {
    let mut set = MeshSet::default();
    if r.footprint.len() < 3 {
        return set;
    }
    let ty = p.sys_type(r.type_id);
    let finish = ty.and_then(|t| t.layers.first()).map(|l| l.material.clone()).unwrap_or_else(|| "Default".into());
    let thick = analysis::roof_thickness(p, r);
    let under = roof_underside(p, r);
    let up = DVec3::Z * thick;
    let m = set.mesh(&finish);
    for t in &under {
        m.add_polygon_facing(&[t[0], t[1], t[2]], -DVec3::Z);
        m.add_polygon_facing(&[t[0] + up, t[1] + up, t[2] + up], DVec3::Z);
    }
    // Close the slab: vertical faces along boundary edges of the underside surface.
    let key = |v: DVec3| ((v.x * 10.0).round() as i64, (v.y * 10.0).round() as i64, (v.z * 10.0).round() as i64);
    let mut count: HashMap<((i64, i64, i64), (i64, i64, i64)), (DVec3, DVec3, usize)> = HashMap::new();
    for t in &under {
        for k in 0..3 {
            let (a, b) = (t[k], t[(k + 1) % 3]);
            let (ka, kb) = (key(a), key(b));
            let e = if ka < kb { (ka, kb) } else { (kb, ka) };
            count.entry(e).or_insert((a, b, 0)).2 += 1;
        }
    }
    let center = under.iter().flat_map(|t| t.iter()).fold(DVec3::ZERO, |s, v| s + *v) / (under.len() * 3).max(1) as f64;
    for (a, b, c) in count.into_values() {
        if c != 1 {
            continue;
        }
        let mid = (a + b) / 2.0;
        let out = DVec3::new(mid.x - center.x, mid.y - center.y, 0.0);
        m.add_quad_facing(a, b, b + up, a + up, out);
    }
    // Shafts cut through the roof.
    let (z0, z1) = under.iter().flat_map(|t| t.iter()).fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(v.z), b.max(v.z)));
    for s in shafts_cutting(p, z0, z1 + thick) {
        set = csg::subtract_set(&set, &csg::prism(&s, z0 - 10.0, z1 + thick + 10.0));
    }
    if r.fascia || r.gutter {
        let (pts, flags) = roof_ccw(r);
        let eave = geom::offset(&pts, r.overhang);
        let tan = r.slope_deg.clamp(1.0, 85.0).to_radians().tan();
        let z = analysis::roof_base_z(p, r) - if flags.iter().any(|f| *f) { r.overhang * tan } else { 0.0 };
        let n = eave.len();
        for i in 0..n {
            if !flags[i] && flags.iter().any(|f| *f) {
                continue;
            }
            let (a, b) = (eave[i], eave[(i + 1) % n]);
            let d = (b - a).normalize_or_zero();
            let outn = DVec2::new(d.y, -d.x);
            if r.fascia {
                let q = [a, b, b + outn * 25.0, a + outn * 25.0];
                set.add_extrusion("Wood - Painted White", &q, z - 200.0, z + thick);
            }
            if r.gutter {
                let q = [a + outn * 25.0, b + outn * 25.0, b + outn * 150.0, a + outn * 150.0];
                set.add_extrusion("Aluminum", &q, z - 150.0, z - 30.0);
            }
        }
    }
    set
}

/// A solid occupying the space above a roof's underside (trims attached walls).
fn roof_upper_cutter(p: &Project, r: &Roof) -> Solid {
    let mut solid = Solid::default();
    let top = 1.0e6;
    for t in roof_underside(p, r) {
        let base: Vec<DVec2> = t.iter().map(|v| v.truncate()).collect();
        if geom::area(&base) < 1e-3 {
            continue;
        }
        // A prism from the triangle up to a large height, its bottom following the triangle.
        let mut m = Mesh::default();
        let (a, b, c) = (t[0], t[1], t[2]);
        let (at, bt, ct) = (DVec3::new(a.x, a.y, top), DVec3::new(b.x, b.y, top), DVec3::new(c.x, c.y, top));
        let ccw = geom::cross2(b.truncate() - a.truncate(), c.truncate() - a.truncate()) > 0.0;
        let (b, c, bt, ct) = if ccw { (b, c, bt, ct) } else { (c, b, ct, bt) };
        m.add_triangle(a, c, b);
        m.add_triangle(at, bt, ct);
        m.add_quad(a, b, bt, at);
        m.add_quad(b, c, ct, bt);
        m.add_quad(c, a, at, ct);
        solid.polys.extend(Solid::from_mesh(&m, 0).polys);
    }
    solid
}

// ---------------------------------------------------------------- stairs and railings

/// Per-run layout: (riser count, first riser index, start z) plus landings.
pub struct StairLayout {
    pub runs: Vec<(StairRun, u32, u32, f64)>,
    pub riser: f64,
    pub base: f64,
    pub landings: Vec<(Vec<DVec2>, f64)>,
}

pub fn stair_layout(p: &Project, s: &Stair) -> StairLayout {
    let (n, rh, _tread, _rise) = analysis::stair_numbers(p, s);
    let base = analysis::stair_base_z(p, s);
    let lens: Vec<f64> = s.runs.iter().map(|r| r.start.distance(r.end).max(1.0)).collect();
    let total: f64 = lens.iter().sum();
    let mut counts: Vec<u32> = lens.iter().map(|l| ((n as f64) * l / total).round().max(1.0) as u32).collect();
    let sum: i64 = counts.iter().map(|c| *c as i64).sum();
    if let Some(last) = counts.last_mut() {
        *last = (*last as i64 + n as i64 - sum).max(1) as u32;
    }
    let mut runs = Vec::new();
    let mut first = 0;
    let mut landings = Vec::new();
    for (k, r) in s.runs.iter().enumerate() {
        let z0 = base + first as f64 * rh;
        runs.push((r.clone(), counts[k], first, z0));
        first += counts[k];
        if k + 1 < s.runs.len() {
            let nxt = &s.runs[k + 1];
            let d0 = (r.end - r.start).normalize_or_zero();
            let d1 = (nxt.end - nxt.start).normalize_or_zero();
            let (n0, n1) = (geom::perp(d0) * (r.width / 2.0), geom::perp(d1) * (nxt.width / 2.0));
            let mut pts = vec![r.end - n0, r.end + n0, nxt.start - n1, nxt.start + n1];
            // Extend the landing to cover the turn.
            pts.push(r.end + d0 * r.width - n0);
            pts.push(r.end + d0 * r.width + n0);
            let hull = convex_hull(&pts);
            landings.push((hull, base + first as f64 * rh));
        }
    }
    StairLayout { runs, riser: rh, base, landings }
}

fn convex_hull(pts: &[DVec2]) -> Vec<DVec2> {
    let mut v = pts.to_vec();
    v.sort_by(|a, b| a.x.total_cmp(&b.x).then(a.y.total_cmp(&b.y)));
    v.dedup_by(|a, b| a.distance(*b) < 1e-6);
    if v.len() < 3 {
        return v;
    }
    let mut lower: Vec<DVec2> = Vec::new();
    for p in &v {
        while lower.len() >= 2 && geom::cross2(lower[lower.len() - 1] - lower[lower.len() - 2], *p - lower[lower.len() - 1]) <= 0.0 {
            lower.pop();
        }
        lower.push(*p);
    }
    let mut upper: Vec<DVec2> = Vec::new();
    for p in v.iter().rev() {
        while upper.len() >= 2 && geom::cross2(upper[upper.len() - 1] - upper[upper.len() - 2], *p - upper[upper.len() - 1]) <= 0.0 {
            upper.pop();
        }
        upper.push(*p);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower
}

fn stair(p: &Project, s: &Stair) -> MeshSet {
    let mut set = MeshSet::default();
    let ty = p.sys_type(s.type_id);
    let mat = ty.map(|t| t.primary_material()).unwrap_or_else(|| "Concrete".into());
    let waist = ty.map(|t| t.prop("Structural Depth", 150.0)).unwrap_or(150.0);
    let landing_t = ty.map(|t| t.prop("Landing Thickness", 200.0)).unwrap_or(200.0);
    let lay = stair_layout(p, s);
    for (run, risers, _first, z0) in &lay.runs {
        let len = run.start.distance(run.end);
        if len < 1.0 || *risers == 0 {
            continue;
        }
        let d = (run.end - run.start) / len;
        let n = geom::perp(d);
        let going = len / *risers as f64;
        let rh = lay.riser;
        // Side profile (u, z) of steps plus the sloped waist underneath.
        let mut prof = vec![DVec2::new(0.0, *z0)];
        for k in 0..*risers {
            let u = k as f64 * going;
            prof.push(DVec2::new(u, z0 + (k + 1) as f64 * rh));
            prof.push(DVec2::new(u + going, z0 + (k + 1) as f64 * rh));
        }
        let top = z0 + *risers as f64 * rh;
        let slope = (rh / going).atan();
        // Vertical thickness of the waist slab below the pitch line through the nosings.
        let wv = waist / slope.cos();
        prof.push(DVec2::new(len, (top + rh - wv).min(top - 1.0)));
        let u_floor = ((wv - rh) * going / rh).clamp(0.0, len - 1.0);
        prof.push(DVec2::new(u_floor, *z0));
        let prof = geom::clean(&prof, 0.1);
        // Extrude the profile across the run width.
        let mut local = MeshSet::default();
        local.add_extrusion(&mat, &prof, -run.width / 2.0, run.width / 2.0);
        for (name, m) in local.by_material {
            let out = set.mesh(&name);
            for t in m.indices.chunks(3) {
                let q: Vec<DVec3> = t.iter().map(|k| {
                    let v = m.positions[*k as usize];
                    // (u, z, lateral) -> world; (x,y,z) = (u, lateral, z) is a reflection of (u, z, lateral).
                    geom::at(run.start + d * v.x + n * v.z, v.y)
                }).collect();
                out.add_triangle(q[0], q[2], q[1]);
            }
        }
    }
    for (poly, z) in &lay.landings {
        set.add_extrusion(&mat, poly, z - landing_t, *z);
    }
    set
}

/// Height of the stair walking surface at a plan point (None if off the stair).
pub fn stair_height_at(p: &Project, s: &Stair, q: DVec2) -> Option<f64> {
    let lay = stair_layout(p, s);
    for (run, risers, _, z0) in &lay.runs {
        let len = run.start.distance(run.end);
        let d = (run.end - run.start) / len.max(1e-9);
        let u = (q - run.start).dot(d);
        let o = (q - run.start).dot(geom::perp(d));
        if u >= -1.0 && u <= len + 1.0 && o.abs() <= run.width / 2.0 + 200.0 {
            // Smooth nosing line for railings.
            return Some(z0 + lay.riser * (*risers as f64) * (u / len).clamp(0.0, 1.0));
        }
    }
    for (poly, z) in &lay.landings {
        if geom::contains(poly, q) || poly.iter().any(|v| v.distance(q) < 250.0) {
            return Some(*z);
        }
    }
    None
}

fn railing(p: &Project, r: &Railing) -> MeshSet {
    let mut set = MeshSet::default();
    if r.path.len() < 2 {
        return set;
    }
    let ty = p.sys_type(r.type_id);
    let h = ty.map(|t| t.prop("Height", 1000.0)).unwrap_or(1000.0);
    let spacing = ty.map(|t| t.prop("Baluster Spacing", 120.0)).unwrap_or(120.0);
    let rail_w = ty.map(|t| t.prop("Rail Width", 50.0)).unwrap_or(50.0);
    let bal = ty.map(|t| t.prop("Baluster Size", 20.0)).unwrap_or(20.0);
    let mat = ty.map(|t| t.text("Material", "Steel")).unwrap_or_else(|| "Steel".into());
    let host = r.host.and_then(|h| p.element(h)).and_then(|e| match &e.kind {
        ElementKind::Stair(s) => Some(s.clone()),
        _ => None,
    });
    let base = p.level_elevation(r.level) + r.base_offset;
    let z_at = |q: DVec2| host.as_ref().and_then(|s| stair_height_at(p, s, q)).unwrap_or(base);
    for seg in r.path.windows(2) {
        let (a, b) = (seg[0], seg[1]);
        let len = a.distance(b);
        if len < 1.0 {
            continue;
        }
        let d = (b - a) / len;
        let n = geom::perp(d);
        let (za, zb) = (z_at(a), z_at(b));
        for (zoff, size) in [(h, rail_w), (100.0, rail_w * 0.6)] {
            let o = geom::at(a - n * (size / 2.0), za + zoff - size);
            let u = DVec3::new(b.x - a.x, b.y - a.y, zb - za);
            set.add_box(&mat, o, u, geom::at(n * size, 0.0), DVec3::Z * size);
        }
        let count = (len / spacing).floor().max(1.0) as usize;
        for k in 0..=count {
            let q = a + d * (len * k as f64 / count as f64);
            let z = z_at(q);
            let o = geom::at(q - d * (bal / 2.0) - n * (bal / 2.0), z);
            set.add_box(&mat, o, geom::at(d * bal, 0.0), geom::at(n * bal, 0.0), DVec3::Z * (h - rail_w));
        }
    }
    set
}

/// Builds a family type on its own (for previews in the family editor).
pub fn family_type_preview(family: &Family, ftype: &FamilyType) -> MeshSet {
    let mut p = Project::empty();
    let level = p.new_id();
    p.elements.push(Element::new(level, ElementKind::Level(Level { name: "L".into(), elevation: 0.0, building_story: true })));
    let mut fam = family.clone();
    fam.types = vec![ftype.clone()];
    p.families.push(fam);
    let mut inst = FamilyInstance { family_id: family.id, type_id: ftype.id, category: family.category, level, ..Default::default() };
    if family.is_framing() {
        inst.end = Some(DVec2::new(3000.0, 0.0));
        inst.elevation = 3000.0;
        inst.end_elevation = 3000.0;
    }
    family_geom::instance_mesh(&p, &inst)
}
