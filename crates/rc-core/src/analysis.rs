//! Derived quantities, wall paths and joins, and room/area boundary detection.

use crate::family_params::Resolver;
use crate::geom::{self, DVec2, DVec3};
use crate::model::*;
use std::collections::{BTreeMap, HashMap, HashSet};

// ---------------------------------------------------------------- walls

/// Top-surface triangles of a toposolid (absolute z): the boundary triangulated with its
/// interior points inserted, then improved towards Delaunay without touching the boundary.
pub fn topo_triangles(p: &Project, t: &Toposolid) -> Vec<[DVec3; 3]> {
    let n = t.boundary.len();
    if n < 3 {
        return vec![];
    }
    let base = p.level_elevation(t.level);
    let mut verts: Vec<DVec2> = t.boundary.clone();
    let mut zs: Vec<f64> = (0..n).map(|k| base + t.heights.get(k).copied().unwrap_or(0.0)).collect();
    let ccw = |a: DVec2, b: DVec2, c: DVec2| geom::cross2(b - a, c - a);
    let orient = |tri: [usize; 3], v: &[DVec2]| if ccw(v[tri[0]], v[tri[1]], v[tri[2]]) < 0.0 { [tri[0], tri[2], tri[1]] } else { tri };
    let mut tris: Vec<[usize; 3]> = geom::triangulate(&verts).into_iter().map(|tr| orient(tr, &verts)).collect();
    // Insert interior points by splitting the triangle that contains them.
    for (q, h) in &t.points {
        let Some(k) = tris.iter().position(|tr| {
            let (a, b, c) = (verts[tr[0]], verts[tr[1]], verts[tr[2]]);
            ccw(a, b, *q) >= -1e-9 && ccw(b, c, *q) >= -1e-9 && ccw(c, a, *q) >= -1e-9
        }) else {
            continue;
        };
        let i = verts.len();
        verts.push(*q);
        zs.push(base + h);
        let [a, b, c] = tris.swap_remove(k);
        for (u, v) in [(a, b), (b, c), (c, a)] {
            if ccw(verts[u], verts[v], *q).abs() > 1e-6 * verts[u].distance(verts[v]).max(1.0) {
                tris.push([u, v, i]);
            } else if let Some(j) = tris.iter().position(|tr| tr.contains(&u) && tr.contains(&v)) {
                // The point lies on this edge: split the neighbour too, so no crack opens.
                let other = tris.swap_remove(j);
                let w = *other.iter().find(|&&x| x != u && x != v).unwrap();
                tris.push(orient([u, w, i], &verts));
                tris.push(orient([w, v, i], &verts));
            }
        }
    }
    // Lawson flips of interior edges.
    let is_boundary = |a: usize, b: usize| a < n && b < n && ((a + 1) % n == b || (b + 1) % n == a);
    let in_circle = |a: DVec2, b: DVec2, c: DVec2, d: DVec2| {
        let (ax, ay, bx, by, cx, cy) = (a.x - d.x, a.y - d.y, b.x - d.x, b.y - d.y, c.x - d.x, c.y - d.y);
        (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay) > 1e-6
    };
    for _ in 0..(tris.len() * 4 + 16) {
        let mut flipped = false;
        'outer: for i in 0..tris.len() {
            for e in 0..3 {
                let (u, v, w1) = (tris[i][e], tris[i][(e + 1) % 3], tris[i][(e + 2) % 3]);
                if is_boundary(u, v) {
                    continue;
                }
                let Some(j) = (0..tris.len()).find(|&j| j != i && tris[j].contains(&u) && tris[j].contains(&v)) else { continue };
                let w2 = *tris[j].iter().find(|&&x| x != u && x != v).unwrap();
                if !in_circle(verts[u], verts[v], verts[w1], verts[w2]) {
                    continue;
                }
                // Only flip convex quads: u and v on opposite sides of w1-w2.
                let (s1, s2) = (ccw(verts[w1], verts[w2], verts[u]), ccw(verts[w1], verts[w2], verts[v]));
                if s1 * s2 >= 0.0 {
                    continue;
                }
                tris[i] = orient([u, w2, w1], &verts);
                tris[j] = orient([v, w1, w2], &verts);
                flipped = true;
                break 'outer;
            }
        }
        if !flipped {
            break;
        }
    }
    tris.into_iter().map(|[a, b, c]| [verts[a].extend(zs[a]), verts[b].extend(zs[b]), verts[c].extend(zs[c])]).collect()
}

/// Contour segments of a toposolid: (a, b, major) every `interval` with a major line every fifth.
pub fn topo_contours(p: &Project, t: &Toposolid, interval: f64) -> Vec<(DVec2, DVec2, bool)> {
    let mut out = Vec::new();
    if interval <= 0.0 {
        return out;
    }
    for tri in topo_triangles(p, t) {
        let zmin = tri.iter().map(|q| q.z).fold(f64::MAX, f64::min);
        let zmax = tri.iter().map(|q| q.z).fold(f64::MIN, f64::max);
        let mut k = (zmin / interval).ceil() as i64;
        while (k as f64) * interval <= zmax && zmax - zmin > 1e-6 {
            let z = k as f64 * interval;
            let mut pts = Vec::new();
            for i in 0..3 {
                let (a, b) = (tri[i], tri[(i + 1) % 3]);
                if (a.z - z) * (b.z - z) < 0.0 || ((a.z - z).abs() < 1e-9 && (b.z - z).abs() > 1e-9) {
                    let s = (z - a.z) / (b.z - a.z);
                    pts.push((a + (b - a) * s).truncate());
                }
            }
            if pts.len() >= 2 && pts[0].distance(pts[1]) > 1e-3 {
                out.push((pts[0], pts[1], k.rem_euclid(5) == 0));
            }
            k += 1;
        }
    }
    out
}

pub fn wall_type<'a>(p: &'a Project, w: &Wall) -> Option<&'a SystemType> {
    p.sys_type(w.type_id)
}

pub fn wall_thickness(p: &Project, w: &Wall) -> f64 {
    wall_type(p, w).map(|t| t.thickness()).unwrap_or(200.0)
}

pub fn is_curtain(p: &Project, w: &Wall) -> bool {
    wall_type(p, w).is_some_and(|t| t.wall_kind == WallKind::Curtain)
}

pub fn wall_base_z(p: &Project, w: &Wall) -> f64 {
    p.level_elevation(w.base_level) + w.base_offset
}

/// Top of the wall's own constraint (before any roof attachment).
pub fn wall_top_z(p: &Project, w: &Wall) -> f64 {
    match w.top_level.and_then(|id| p.level(id)) {
        Some(l) => l.elevation + w.top_offset,
        None => wall_base_z(p, w) + w.unconnected_height,
    }
}

pub fn wall_height(p: &Project, w: &Wall) -> f64 {
    (wall_top_z(p, w) - wall_base_z(p, w)).max(0.0)
}

/// Offset from the wall centreline to a location line (+ = exterior side).
pub fn location_line_offset(t: &SystemType, line: LocationLine) -> f64 {
    let half = t.thickness() / 2.0;
    let (core_mid, core_ext, core_int) = t.core_offsets();
    match line {
        LocationLine::WallCenterline => 0.0,
        LocationLine::CoreCenterline => core_mid,
        LocationLine::FinishFaceExterior => half,
        LocationLine::FinishFaceInterior => -half,
        LocationLine::CoreFaceExterior => core_ext,
        LocationLine::CoreFaceInterior => core_int,
    }
}

/// The wall centreline as a polyline (two points, or a tessellated arc).
pub fn wall_path(w: &Wall) -> Vec<DVec2> {
    match w.arc() {
        Some(a) => a.tessellate(600.0),
        None => vec![w.start, w.end],
    }
}

/// Point and unit tangent at distance `u` along the wall.
pub fn wall_point(w: &Wall, u: f64) -> (DVec2, DVec2) {
    match w.arc() {
        Some(a) => {
            let t = (u / a.length().max(1e-9)).clamp(0.0, 1.0);
            (a.point(t), a.tangent(t))
        }
        None => (w.start + w.direction() * u, w.direction()),
    }
}

/// Distance along the wall of the point closest to `q`, and the signed lateral offset (+ = left).
pub fn wall_project(w: &Wall, q: DVec2) -> (f64, f64) {
    match w.arc() {
        Some(a) => {
            let t = a.param_of(q);
            let pt = a.point(t);
            let n = geom::perp(a.tangent(t));
            (t * a.length(), (q - pt).dot(n))
        }
        None => {
            let d = w.direction();
            ((q - w.start).dot(d), (q - w.start).dot(geom::perp(d)))
        }
    }
}

/// Rough opening (width, height) a door or window cuts into its host.
pub fn opening_size(p: &Project, inst: &FamilyInstance) -> (f64, f64) {
    match Resolver::for_instance(p, inst) {
        Some(r) => {
            let w = r.num("Rough Width", r.num("Width", 900.0));
            let h = r.num("Rough Height", r.num("Height", 2100.0));
            (w.max(1.0), h.max(1.0))
        }
        None => (900.0, 2100.0),
    }
}

pub fn wall_net_area(p: &Project, id: Id, w: &Wall) -> f64 {
    let gross = w.length() * wall_height(p, w);
    let openings: f64 = p
        .hosted_by(id)
        .map(|(_, i)| {
            let (ow, oh) = opening_size(p, i);
            ow * oh
        })
        .sum::<f64>()
        + w.openings.iter().map(|o| (o.u1 - o.u0) * (o.z1 - o.z0)).sum::<f64>();
    (gross - openings).max(0.0)
}

// ---------------------------------------------------------------- slabs

pub fn floor_thickness(p: &Project, f: &Floor) -> f64 {
    p.sys_type(f.type_id).map(|t| t.thickness()).unwrap_or(300.0)
}

pub fn floor_top_z(p: &Project, f: &Floor) -> f64 {
    p.level_elevation(f.level) + f.height_offset
}

/// Floor top height at a plan point, honouring a slope arrow.
pub fn floor_top_at(p: &Project, f: &Floor, q: DVec2) -> f64 {
    let base = floor_top_z(p, f);
    match f.slope {
        Some((tail, head, rise)) if tail.distance(head) > 1.0 => {
            let d = head - tail;
            base + rise * (q - tail).dot(d) / d.length_squared()
        }
        _ => base,
    }
}

pub fn floor_area(f: &Floor) -> f64 {
    (geom::area(&f.boundary) - f.holes.iter().map(|h| geom::area(h)).sum::<f64>()).max(0.0)
}

pub fn ceiling_thickness(p: &Project, c: &Ceiling) -> f64 {
    p.sys_type(c.type_id).map(|t| t.thickness()).unwrap_or(25.0)
}

pub fn roof_thickness(p: &Project, r: &Roof) -> f64 {
    p.sys_type(r.type_id).map(|t| t.thickness()).unwrap_or(300.0)
}

pub fn roof_base_z(p: &Project, r: &Roof) -> f64 {
    p.level_elevation(r.level) + r.base_offset
}

/// Which footprint edges define slope (explicit flags, else derived from the shape).
pub fn roof_edge_slopes(r: &Roof) -> Vec<bool> {
    let n = r.footprint.len();
    if r.edge_slopes.len() == n {
        return r.edge_slopes.clone();
    }
    match r.shape {
        RoofShape::Flat => vec![false; n],
        RoofShape::Hip => vec![true; n],
        RoofShape::Gable | RoofShape::Shed => {
            // Long sides slope for gables; for sheds the first long side.
            let pts = geom::ensure_ccw(&r.footprint);
            let lens: Vec<f64> = (0..n).map(|i| pts[i].distance(pts[(i + 1) % n])).collect();
            let longest = lens.iter().cloned().fold(0.0, f64::max);
            let mut flags: Vec<bool> = lens.iter().map(|l| *l >= longest * 0.99).collect();
            if r.shape == RoofShape::Shed {
                if let Some(first) = flags.iter().position(|f| *f) {
                    flags = (0..n).map(|i| i == first).collect();
                }
            } else if n == 4 && flags.iter().filter(|f| **f).count() == 4 {
                // Square: slope one opposite pair.
                flags = vec![true, false, true, false];
            }
            // The footprint may have been reversed by ensure_ccw; map flags back.
            if geom::signed_area(&r.footprint) < 0.0 {
                let mut back = vec![false; n];
                for (i, f) in flags.iter().enumerate() {
                    // Edge i of the reversed polygon is edge n-2-i of the original.
                    back[(2 * n - 2 - i) % n] = *f;
                }
                back
            } else {
                flags
            }
        }
    }
}

/// Surface area of the roof including overhangs (approximate for mixed slopes).
pub fn roof_area(r: &Roof) -> f64 {
    if r.footprint.len() < 3 {
        return 0.0;
    }
    let eave = geom::offset(&geom::ensure_ccw(&r.footprint), r.overhang);
    let plan = geom::area(&eave);
    if roof_edge_slopes(r).iter().any(|s| *s) {
        plan / r.slope_deg.to_radians().cos().max(0.05)
    } else {
        plan
    }
}

// ---------------------------------------------------------------- instances

/// Plan location of a hosted or free-standing instance.
pub fn instance_location(p: &Project, inst: &FamilyInstance) -> DVec2 {
    match inst.host.and_then(|h| p.wall(h)) {
        Some(w) => wall_point(w, inst.offset_along_host).0,
        None => inst.location,
    }
}

/// Column bottom and top elevations.
pub fn column_extent(p: &Project, i: &FamilyInstance, default_height: f64) -> (f64, f64) {
    let z0 = p.level_elevation(i.level) + i.elevation;
    let z1 = match i.top_level.and_then(|l| p.level(l)) {
        Some(l) => l.elevation + i.top_offset,
        None => z0 + default_height,
    };
    (z0, z1.max(z0 + 10.0))
}

// ---------------------------------------------------------------- stairs

/// Computed stair geometry numbers: (riser count, riser height, tread depth, total rise).
pub fn stair_numbers(p: &Project, s: &Stair) -> (u32, f64, f64, f64) {
    let base = p.level_elevation(s.base_level) + s.base_offset;
    let top = match s.top_level.and_then(|l| p.level(l)) {
        Some(l) => l.elevation + s.top_offset,
        None => base + s.unconnected_height.max(100.0),
    };
    let rise = (top - base).max(1.0);
    let t = p.sys_type(s.type_id);
    let max_riser = t.map(|t| t.prop("Maximum Riser Height", 180.0)).unwrap_or(180.0);
    let tread = t.map(|t| t.prop("Minimum Tread Depth", 280.0)).unwrap_or(280.0);
    let n = if s.desired_risers > 0 { s.desired_risers } else { (rise / max_riser).ceil().max(1.0) as u32 };
    (n, rise / n as f64, tread, rise)
}

/// Risers in a straight run of plan length `len`, as the reference app counts them: the
/// run spans its treads, and one riser more than there are treads.
pub fn run_risers(len: f64, tread: f64) -> u32 {
    (len / tread.max(1.0)).round().max(0.0) as u32 + 1
}

/// (base z, top z, required sloped length) of a ramp: the rise at the type's maximum slope.
pub fn ramp_numbers(p: &Project, r: &Ramp) -> (f64, f64, f64) {
    let base = p.level_elevation(r.base_level) + r.base_offset;
    let top = match r.top_level.and_then(|l| p.level(l)) {
        Some(l) => l.elevation + r.top_offset,
        None => base + r.unconnected_height.max(10.0),
    };
    let x = p.sys_type(r.type_id).map(|t| t.prop("Ramp Max Slope (1/x)", 12.0)).unwrap_or(12.0).max(1.0);
    (base, top, (top - base).abs() * x)
}

pub fn stair_base_z(p: &Project, s: &Stair) -> f64 {
    p.level_elevation(s.base_level) + s.base_offset
}

// ---------------------------------------------------------------- wall outlines and joins

/// Plan outline of a wall after joins. `left` is the exterior (+normal) side; both run start → end.
#[derive(Clone, Debug, PartialEq)]
pub struct Footprint {
    pub left: Vec<DVec2>,
    pub right: Vec<DVec2>,
    pub straight: bool,
}

impl Footprint {
    pub fn polygon(&self) -> Vec<DVec2> {
        let mut v = self.right.clone();
        v.extend(self.left.iter().rev());
        v
    }
    pub fn start_left(&self) -> DVec2 {
        self.left[0]
    }
    pub fn start_right(&self) -> DVec2 {
        self.right[0]
    }
    pub fn end_left(&self) -> DVec2 {
        *self.left.last().unwrap()
    }
    pub fn end_right(&self) -> DVec2 {
        *self.right.last().unwrap()
    }
    /// Point on the start edge at lateral offset `o` in [-t/2, t/2].
    pub fn start_at(&self, o: f64, t: f64) -> DVec2 {
        self.start_right().lerp(self.start_left(), if t <= 0.0 { 0.5 } else { (o + t / 2.0) / t })
    }
    pub fn end_at(&self, o: f64, t: f64) -> DVec2 {
        self.end_right().lerp(self.end_left(), if t <= 0.0 { 0.5 } else { (o + t / 2.0) / t })
    }
}

pub const JOIN_TOLERANCE: f64 = 5.0;

/// Offsets of a wall's core boundaries from its location line along its normal:
/// (core face on the + side, core face on the − side). Walls without a core use their faces.
pub fn wall_core_offsets(p: &Project, w: &Wall) -> (f64, f64) {
    let t = wall_thickness(p, w);
    let Some(ty) = p.sys_type(w.type_id) else { return (t / 2.0, -t / 2.0) };
    let mut o = t / 2.0;
    let (mut plus, mut minus) = (None, None);
    for l in &ty.layers {
        let o0 = o - l.thickness;
        if l.core {
            plus.get_or_insert(o);
            minus = Some(o0);
        }
        o = o0;
    }
    (plus.unwrap_or(t / 2.0), minus.unwrap_or(-t / 2.0))
}

/// Wall outlines with mitred L-corner joins between straight walls whose endpoints meet.
pub fn wall_footprints(p: &Project) -> HashMap<Id, Footprint> {
    let walls: Vec<(Id, &Wall)> = p.walls().filter(|(_, w)| w.length() > 1e-6).map(|(e, w)| (e.id, w)).collect();
    let mut out = HashMap::new();
    for &(id, w) in &walls {
        let h = wall_thickness(p, w) / 2.0;
        if w.arc().is_some() {
            let path = wall_path(w);
            let n = path.len();
            let normal_at = |i: usize| {
                let a = path[i.saturating_sub(1).min(n - 2)];
                let b = path[(i + 1).min(n - 1).max(1)];
                geom::perp((b - a).normalize_or_zero())
            };
            let left = (0..n).map(|i| path[i] + normal_at(i) * h).collect();
            let right = (0..n).map(|i| path[i] - normal_at(i) * h).collect();
            out.insert(id, Footprint { left, right, straight: false });
            continue;
        }
        let n = w.normal();
        let mut left = vec![w.start + n * h, w.end + n * h];
        let mut right = vec![w.start - n * h, w.end - n * h];
        if w.join_start {
            apply_join(p, &walls, id, w, true, &mut left, &mut right, h);
        }
        if w.join_end {
            apply_join(p, &walls, id, w, false, &mut left, &mut right, h);
        }
        out.insert(id, Footprint { left, right, straight: true });
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn apply_join(p: &Project, walls: &[(Id, &Wall)], id: Id, a: &Wall, at_start: bool, left: &mut [DVec2], right: &mut [DVec2], ha: f64) {
    let pt = if at_start { a.start } else { a.end };
    let mut found = None;
    let mut count = 0;
    for &(bid, b) in walls {
        if bid == id || b.base_level != a.base_level || b.arc_mid.is_some() {
            continue;
        }
        if geom::almost_eq(b.start, pt, JOIN_TOLERANCE) && b.join_start {
            found = Some((b, true));
            count += 1;
        } else if geom::almost_eq(b.end, pt, JOIN_TOLERANCE) && b.join_end {
            found = Some((b, false));
            count += 1;
        }
    }
    let (Some((b, b_at_start)), 1) = (found, count) else { return };
    let da = if at_start { a.direction() } else { -a.direction() };
    let db = if b_at_start { b.direction() } else { -b.direction() };
    if geom::cross2(da, db).abs() < 0.02 {
        return; // straight continuation
    }
    let hb = wall_thickness(p, b) / 2.0;
    let (ma, mb) = (geom::perp(da), geom::perp(db));
    // The A "+" side faces the sector from da (CCW) to db, which B bounds with its "−" side.
    let plus = geom::line_intersection(pt + ma * ha, da, pt - mb * hb, db);
    let minus = geom::line_intersection(pt - ma * ha, da, pt + mb * hb, db);
    let (Some(plus), Some(minus)) = (plus, minus) else { return };
    let limit = 8.0 * ha.max(hb);
    if plus.distance(pt) > limit || minus.distance(pt) > limit {
        return;
    }
    if at_start {
        left[0] = plus;
        right[0] = minus;
    } else {
        right[1] = plus;
        left[1] = minus;
    }
}

// ---------------------------------------------------------------- rooms and areas

#[derive(Clone, Debug)]
pub struct RoomBoundary {
    /// Loop along wall location lines (CCW).
    pub centerline: Vec<DVec2>,
    /// Loop along the interior wall faces (CCW); area is measured here, as in Revit.
    pub interior: Vec<DVec2>,
    /// Loop along the outer faces of the bounding walls (used for floors and roofs picked from a region).
    pub exterior: Vec<DVec2>,
}

impl RoomBoundary {
    pub fn area(&self) -> f64 {
        geom::area(&self.interior)
    }
    pub fn perimeter(&self) -> f64 {
        geom::perimeter(&self.interior)
    }
}

const SNAP: f64 = 10.0;

/// The smallest region enclosed by room-bounding walls that contains `point`.
pub fn find_enclosure(p: &Project, level: Id, point: DVec2) -> Option<RoomBoundary> {
    enclosed_regions(p, level)
        .into_iter()
        .filter(|r| geom::contains(&r.centerline, point))
        .min_by(|a, b| geom::area(&a.centerline).total_cmp(&geom::area(&b.centerline)))
}

/// A room's Unbounded Height: from its base to its upper limit plus the limit offset.
pub fn room_height(p: &Project, r: &Room) -> f64 {
    let top = p.level_elevation(r.upper_level.unwrap_or(r.level)) + r.upper_offset;
    (top - p.level_elevation(r.level) - r.base_offset).max(0.0)
}

pub fn room_boundary(p: &Project, room: &Room) -> Option<RoomBoundary> {
    find_enclosure(p, room.level, room.location)
}

/// Segments (a, b, half-thickness) bounding rooms on a level: walls and room separation lines.
fn room_segments(p: &Project, level: Id) -> Vec<(DVec2, DVec2, f64)> {
    let mut segs = Vec::new();
    for (_, w) in p.walls() {
        if !w.room_bounding || w.base_level != level || w.length() <= 1.0 {
            continue;
        }
        let h = wall_thickness(p, w) / 2.0;
        for s in wall_path(w).windows(2) {
            segs.push((s[0], s[1], h));
        }
    }
    for e in &p.elements {
        if let ElementKind::RoomSeparation(s) = &e.kind {
            if s.level == level && s.start.distance(s.end) > 1.0 {
                segs.push((s.start, s.end, 0.0));
            }
        }
    }
    segs
}

/// Area boundaries for an area scheme: area boundary lines on the level.
pub fn area_regions(p: &Project, level: Id, scheme: Id) -> Vec<RoomBoundary> {
    let segs: Vec<(DVec2, DVec2, f64)> = p
        .elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::AreaBoundary(s) if s.level == level && s.scheme.is_none_or(|x| x == scheme) => Some((s.start, s.end, 0.0)),
            _ => None,
        })
        .collect();
    faces_from_segments(segs)
}

pub fn area_boundary(p: &Project, a: &Area) -> Option<RoomBoundary> {
    area_regions(p, a.level, a.scheme)
        .into_iter()
        .filter(|r| geom::contains(&r.centerline, a.location))
        .min_by(|x, y| geom::area(&x.centerline).total_cmp(&geom::area(&y.centerline)))
}

/// All bounded regions formed by room-bounding walls and separation lines on a level.
pub fn enclosed_regions(p: &Project, level: Id) -> Vec<RoomBoundary> {
    faces_from_segments(room_segments(p, level))
}

/// Planar faces of a set of segments (after splitting at intersections and pruning dead ends).
pub fn faces_from_segments(segs: Vec<(DVec2, DVec2, f64)>) -> Vec<RoomBoundary> {
    if segs.len() < 3 {
        return Vec::new();
    }
    // 1. Split segments at mutual intersections and T-junctions.
    let mut splits: Vec<Vec<f64>> = segs.iter().map(|_| vec![0.0, 1.0]).collect();
    for i in 0..segs.len() {
        for j in i + 1..segs.len() {
            let (a, b, _) = segs[i];
            let (c, d, _) = segs[j];
            if let Some((t, u)) = geom::segment_intersection(a, b, c, d) {
                splits[i].push(t.clamp(0.0, 1.0));
                splits[j].push(u.clamp(0.0, 1.0));
            }
            for (pt, (s0, s1), k) in [(c, (a, b), i), (d, (a, b), i), (a, (c, d), j), (b, (c, d), j)] {
                let (q, t) = geom::closest_on_segment(s0, s1, pt);
                if q.distance(pt) <= SNAP && t > 1e-6 && t < 1.0 - 1e-6 {
                    splits[k].push(t);
                }
            }
        }
    }

    // 2. Nodes and unique edges.
    let mut nodes: Vec<DVec2> = Vec::new();
    let node_of = |pt: DVec2, nodes: &mut Vec<DVec2>| -> usize {
        if let Some(k) = nodes.iter().position(|n| geom::almost_eq(*n, pt, SNAP)) {
            return k;
        }
        nodes.push(pt);
        nodes.len() - 1
    };
    let mut edges: Vec<(usize, usize, f64)> = Vec::new();
    let mut seen = HashSet::new();
    for (i, s) in segs.iter().enumerate() {
        let mut ts = splits[i].clone();
        ts.sort_by(f64::total_cmp);
        ts.dedup_by(|a, b| (*a - *b).abs() < 1e-9);
        for k in 0..ts.len() - 1 {
            let a = s.0.lerp(s.1, ts[k]);
            let b = s.0.lerp(s.1, ts[k + 1]);
            if a.distance(b) < SNAP {
                continue;
            }
            let (na, nb) = (node_of(a, &mut nodes), node_of(b, &mut nodes));
            if na == nb || !seen.insert((na.min(nb), na.max(nb))) {
                continue;
            }
            edges.push((na, nb, s.2));
        }
    }

    // 3. Prune dangling edges.
    loop {
        let mut degree = vec![0; nodes.len()];
        for &(a, b, _) in &edges {
            degree[a] += 1;
            degree[b] += 1;
        }
        let before = edges.len();
        edges.retain(|&(a, b, _)| degree[a] >= 2 && degree[b] >= 2);
        if edges.len() == before {
            break;
        }
    }
    if edges.len() < 3 {
        return Vec::new();
    }

    // 4. Face traversal: from half-edge u→v, continue with the edge just clockwise of v→u.
    let mut outgoing: BTreeMap<usize, Vec<(usize, f64, f64)>> = BTreeMap::new();
    for &(a, b, h) in &edges {
        outgoing.entry(a).or_default().push((b, angle(nodes[b] - nodes[a]), h));
        outgoing.entry(b).or_default().push((a, angle(nodes[a] - nodes[b]), h));
    }
    for list in outgoing.values_mut() {
        list.sort_by(|x, y| x.1.total_cmp(&y.1));
    }
    let mut visited = HashSet::new();
    let mut out = Vec::new();
    for &(ea, eb, _) in &edges {
        for (from, to) in [(ea, eb), (eb, ea)] {
            if visited.contains(&(from, to)) {
                continue;
            }
            let (mut u, mut v) = (from, to);
            let mut loop_nodes = Vec::new();
            let mut halves = Vec::new();
            let mut guard = 0;
            while visited.insert((u, v)) && guard < 10_000 {
                guard += 1;
                loop_nodes.push(u);
                let list = &outgoing[&v];
                let idx = list.iter().position(|x| x.0 == u).unwrap();
                halves.push(list[idx].2);
                let next = list[(idx + list.len() - 1) % list.len()];
                u = v;
                v = next.0;
            }
            if loop_nodes.len() < 3 {
                continue;
            }
            let poly: Vec<DVec2> = loop_nodes.iter().map(|&i| nodes[i]).collect();
            if geom::signed_area(&poly) <= 1.0 {
                continue; // the unbounded outer face
            }
            let neg: Vec<f64> = halves.iter().map(|h| -h).collect();
            let mut interior = geom::offset_edges(&poly, &neg);
            if geom::signed_area(&interior) <= 0.0 {
                interior = poly.clone();
            }
            let exterior = geom::offset_edges(&poly, &halves);
            out.push(RoomBoundary {
                centerline: geom::clean(&poly, 0.5),
                interior: geom::clean(&interior, 0.5),
                exterior: geom::clean(&exterior, 0.5),
            });
        }
    }
    out
}

fn angle(v: DVec2) -> f64 {
    v.y.atan2(v.x)
}

// ---------------------------------------------------------------- phases

/// Phase status of an element as seen from a view.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PhaseStatus {
    New,
    Existing,
    Demolished,
    Future,
    Gone,
}

pub fn phase_status(p: &Project, view: &View, e: &Element) -> PhaseStatus {
    if p.phases.is_empty() {
        return PhaseStatus::New;
    }
    let vp = p.phase_index(view.phase.or_else(|| p.phases.last().map(|x| x.id)));
    let created = p.created_phase_index(e);
    if created > vp {
        return PhaseStatus::Future;
    }
    if let Some(d) = e.phase_demolished {
        let di = p.phase_index(Some(d));
        if di < vp {
            return PhaseStatus::Gone;
        }
        if di == vp {
            return PhaseStatus::Demolished;
        }
    }
    if created == vp { PhaseStatus::New } else { PhaseStatus::Existing }
}

/// Whether a view's phase filter shows an element with this status.
pub fn phase_filter_shows(f: PhaseFilter, s: PhaseStatus) -> bool {
    use PhaseStatus::*;
    match (f, s) {
        (_, Future) | (_, Gone) => false,
        (PhaseFilter::None, _) | (PhaseFilter::ShowAll, _) => true,
        (PhaseFilter::ShowComplete, Demolished) => false,
        (PhaseFilter::ShowComplete, _) => true,
        (PhaseFilter::ShowNew, New) => true,
        (PhaseFilter::ShowNew, _) => false,
        (PhaseFilter::ShowPreviousAndNew, Demolished) => false,
        (PhaseFilter::ShowPreviousAndNew, _) => true,
        (PhaseFilter::ShowDemoAndNew, Existing) => false,
        (PhaseFilter::ShowDemoAndNew, _) => true,
        (PhaseFilter::ShowPrevious, New) => false,
        (PhaseFilter::ShowPrevious, _) => true,
    }
}

/// Element visible in a view: category, element hides, owner view, design options, phases.
pub fn visible_in(p: &Project, view: &View, e: &Element) -> bool {
    if !view.shows_element(e) || !p.option_visible(view, e) {
        return false;
    }
    if view.overrides.iter().any(|o| o.hidden) && crate::params::filter_hidden(p, view, e) {
        return false;
    }
    phase_filter_shows(view.phase_filter, phase_status(p, view, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::defaults;

    fn add_wall(p: &mut Project, level: Id, ty: Id, a: (f64, f64), b: (f64, f64)) -> Id {
        let id = p.new_id();
        p.elements.push(Element::new(
            id,
            ElementKind::Wall(Wall {
                start: DVec2::new(a.0, a.1),
                end: DVec2::new(b.0, b.1),
                type_id: ty,
                base_level: level,
                unconnected_height: 3000.0,
                room_bounding: true,
                join_start: true,
                join_end: true,
                ..Default::default()
            }),
        ));
        id
    }

    fn generic_200(p: &Project) -> Id {
        p.types_of(Category::Walls).find(|t| (t.thickness() - 200.0).abs() < 1e-6).unwrap().id
    }

    #[test]
    fn rectangle_room_area_measured_at_interior_faces() {
        let mut p = defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let t = generic_200(&p);
        add_wall(&mut p, lvl, t, (0.0, 0.0), (6000.0, 0.0));
        add_wall(&mut p, lvl, t, (6000.0, 0.0), (6000.0, 4000.0));
        add_wall(&mut p, lvl, t, (6000.0, 4000.0), (0.0, 4000.0));
        add_wall(&mut p, lvl, t, (0.0, 4000.0), (0.0, 0.0));
        let b = find_enclosure(&p, lvl, DVec2::new(3000.0, 2000.0)).expect("room");
        assert!((b.area() - 5800.0 * 3800.0).abs() < 1.0, "area {}", b.area());
        assert!(find_enclosure(&p, lvl, DVec2::new(9000.0, 2000.0)).is_none());
    }

    #[test]
    fn partitions_separation_lines_and_dangling_walls() {
        let mut p = defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let t = generic_200(&p);
        add_wall(&mut p, lvl, t, (0.0, 0.0), (8000.0, 0.0));
        add_wall(&mut p, lvl, t, (8000.0, 0.0), (8000.0, 4000.0));
        add_wall(&mut p, lvl, t, (8000.0, 4000.0), (0.0, 4000.0));
        add_wall(&mut p, lvl, t, (0.0, 4000.0), (0.0, 0.0));
        add_wall(&mut p, lvl, t, (4000.0, 0.0), (4000.0, 4000.0));
        add_wall(&mut p, lvl, t, (6000.0, 0.0), (6000.0, 1500.0));
        assert_eq!(enclosed_regions(&p, lvl).len(), 2);
        let id = p.new_id();
        p.elements.push(Element::new(id, ElementKind::RoomSeparation(Separation { level: lvl, start: DVec2::new(4000.0, 2000.0), end: DVec2::new(8000.0, 2000.0), scheme: None })));
        assert_eq!(enclosed_regions(&p, lvl).len(), 3);
        let right_top = find_enclosure(&p, lvl, DVec2::new(6000.0, 3000.0)).unwrap();
        assert!((right_top.area() - 3800.0 * 1900.0).abs() < 1.0, "{}", right_top.area());
    }

    #[test]
    fn l_corner_is_mitred_and_arc_wall_has_curved_outline() {
        let mut p = defaults::new_project(crate::units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let t = generic_200(&p);
        let a = add_wall(&mut p, lvl, t, (0.0, 0.0), (5000.0, 0.0));
        let b = add_wall(&mut p, lvl, t, (5000.0, 0.0), (5000.0, 3000.0));
        let fps = wall_footprints(&p);
        assert!(fps[&a].end_left().distance(DVec2::new(4900.0, 100.0)) < 1e-6);
        assert!(fps[&a].end_right().distance(DVec2::new(5100.0, -100.0)) < 1e-6);
        assert!(fps[&b].start_left().distance(DVec2::new(4900.0, 100.0)) < 1e-6);
        let c = add_wall(&mut p, lvl, t, (0.0, 10000.0), (4000.0, 10000.0));
        if let Some(w) = p.element_mut(c).and_then(Element::as_wall_mut) {
            w.arc_mid = Some(DVec2::new(2000.0, 12000.0));
        }
        let w = p.wall(c).unwrap();
        assert!((w.length() - std::f64::consts::PI * 2000.0).abs() < 1.0);
        let fp = &wall_footprints(&p)[&c];
        assert!(fp.left.len() > 10);
    }
}
