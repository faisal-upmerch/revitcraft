//! 2D/3D geometry helpers. All model coordinates are in millimetres, Z up, +Y north.

pub use glam::{DVec2, DVec3};

/// Left-hand perpendicular (rotated +90°).
/// `v` turned by `a` radians counter-clockwise.
pub fn rotate(v: DVec2, a: f64) -> DVec2 {
    DVec2::from_angle(a).rotate(v)
}

pub fn perp(v: DVec2) -> DVec2 {
    DVec2::new(-v.y, v.x)
}

pub fn cross2(a: DVec2, b: DVec2) -> f64 {
    a.x * b.y - a.y * b.x
}

pub fn almost_eq(a: DVec2, b: DVec2, tol: f64) -> bool {
    a.distance(b) <= tol
}

pub fn at(p: DVec2, z: f64) -> DVec3 {
    DVec3::new(p.x, p.y, z)
}

/// Signed area; positive when counter-clockwise.
pub fn signed_area(pts: &[DVec2]) -> f64 {
    let n = pts.len();
    let mut a = 0.0;
    for i in 0..n {
        let p = pts[i];
        let q = pts[(i + 1) % n];
        a += p.x * q.y - q.x * p.y;
    }
    a / 2.0
}

pub fn area(pts: &[DVec2]) -> f64 {
    signed_area(pts).abs()
}

pub fn perimeter(pts: &[DVec2]) -> f64 {
    let n = pts.len();
    (0..n).map(|i| pts[i].distance(pts[(i + 1) % n])).sum()
}

pub fn ensure_ccw(pts: &[DVec2]) -> Vec<DVec2> {
    let mut v = pts.to_vec();
    if signed_area(&v) < 0.0 {
        v.reverse();
    }
    v
}

pub fn centroid(pts: &[DVec2]) -> DVec2 {
    let a = signed_area(pts);
    if a.abs() < 1e-9 {
        if pts.is_empty() {
            return DVec2::ZERO;
        }
        return pts.iter().copied().sum::<DVec2>() / pts.len() as f64;
    }
    let n = pts.len();
    let mut c = DVec2::ZERO;
    for i in 0..n {
        let p = pts[i];
        let q = pts[(i + 1) % n];
        let f = p.x * q.y - q.x * p.y;
        c += (p + q) * f;
    }
    c / (6.0 * a)
}

/// Even-odd point-in-polygon test.
pub fn contains(pts: &[DVec2], p: DVec2) -> bool {
    let n = pts.len();
    let mut inside = false;
    let mut j = n.wrapping_sub(1);
    for i in 0..n {
        let a = pts[i];
        let b = pts[j];
        if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
            inside = !inside;
        }
        j = i;
    }
    inside
}

/// Removes duplicate and collinear vertices.
pub fn clean(input: &[DVec2], tol: f64) -> Vec<DVec2> {
    let mut pts: Vec<DVec2> = Vec::with_capacity(input.len());
    for &p in input {
        if pts.last().is_none_or(|l| !almost_eq(*l, p, tol)) {
            pts.push(p);
        }
    }
    if pts.len() > 1 && almost_eq(pts[0], *pts.last().unwrap(), tol) {
        pts.pop();
    }
    loop {
        if pts.len() <= 3 {
            break;
        }
        let n = pts.len();
        let mut removed = false;
        for i in 0..n {
            let prev = pts[(i + n - 1) % n];
            let cur = pts[i];
            let next = pts[(i + 1) % n];
            let d1 = (cur - prev).normalize_or_zero();
            let d2 = (next - cur).normalize_or_zero();
            if cross2(d1, d2).abs() < 1e-6 && d1.dot(d2) > 0.0 {
                pts.remove(i);
                removed = true;
                break;
            }
        }
        if !removed {
            break;
        }
    }
    pts
}

/// Intersection of two infinite lines (point + direction).
pub fn line_intersection(p1: DVec2, d1: DVec2, p2: DVec2, d2: DVec2) -> Option<DVec2> {
    let denom = cross2(d1, d2);
    if denom.abs() < 1e-9 {
        return None;
    }
    let t = cross2(p2 - p1, d2) / denom;
    Some(p1 + d1 * t)
}

/// Segment intersection; returns the parameters along each segment.
pub fn segment_intersection(a: DVec2, b: DVec2, c: DVec2, d: DVec2) -> Option<(f64, f64)> {
    let r = b - a;
    let s = d - c;
    let denom = cross2(r, s);
    if denom.abs() < 1e-9 {
        return None;
    }
    let t = cross2(c - a, s) / denom;
    let u = cross2(c - a, r) / denom;
    let eps = 1e-9;
    ((-eps..=1.0 + eps).contains(&t) && (-eps..=1.0 + eps).contains(&u)).then_some((t, u))
}

/// Closest point on segment ab to p and its parameter t in [0,1].
pub fn closest_on_segment(a: DVec2, b: DVec2, p: DVec2) -> (DVec2, f64) {
    let ab = b - a;
    let len2 = ab.length_squared();
    let t = if len2 < 1e-12 { 0.0 } else { ((p - a).dot(ab) / len2).clamp(0.0, 1.0) };
    (a + ab * t, t)
}

pub fn distance_to_segment(a: DVec2, b: DVec2, p: DVec2) -> f64 {
    closest_on_segment(a, b, p).0.distance(p)
}

/// Offsets every edge by its own distance (positive = outward for any winding) and mitres the corners.
pub fn offset_edges(pts: &[DVec2], distances: &[f64]) -> Vec<DVec2> {
    let n = pts.len();
    let ccw = signed_area(pts) > 0.0;
    let lines: Vec<(DVec2, DVec2)> = (0..n)
        .map(|i| {
            let a = pts[i];
            let b = pts[(i + 1) % n];
            let d = (b - a).normalize_or_zero();
            let outward = if ccw { DVec2::new(d.y, -d.x) } else { DVec2::new(-d.y, d.x) };
            (a + outward * distances[i], d)
        })
        .collect();
    (0..n)
        .map(|i| {
            let prev = lines[(i + n - 1) % n];
            let cur = lines[i];
            line_intersection(prev.0, prev.1, cur.0, cur.1).unwrap_or(cur.0)
        })
        .collect()
}

pub fn offset(pts: &[DVec2], distance: f64) -> Vec<DVec2> {
    offset_edges(pts, &vec![distance; pts.len()])
}

pub fn bounds(pts: impl IntoIterator<Item = DVec2>) -> (DVec2, DVec2) {
    let mut min = DVec2::splat(f64::MAX);
    let mut max = DVec2::splat(f64::MIN);
    for p in pts {
        min = min.min(p);
        max = max.max(p);
    }
    (min, max)
}

/// An oriented rectangle: centre, unit long axis, half length (along axis) and half width.
#[derive(Clone, Copy, Debug)]
pub struct OrientedRect {
    pub center: DVec2,
    pub axis: DVec2,
    pub half_length: f64,
    pub half_width: f64,
}

impl OrientedRect {
    pub fn side(&self) -> DVec2 {
        perp(self.axis)
    }

    pub fn point(&self, along: f64, across: f64) -> DVec2 {
        self.center + self.axis * along + self.side() * across
    }
}

/// Recognises a rectangle in any orientation.
pub fn as_rectangle(input: &[DVec2]) -> Option<OrientedRect> {
    let pts = clean(input, 0.5);
    if pts.len() != 4 {
        return None;
    }
    for i in 0..4 {
        let a = (pts[(i + 1) % 4] - pts[i]).normalize_or_zero();
        let b = (pts[(i + 2) % 4] - pts[(i + 1) % 4]).normalize_or_zero();
        if a.dot(b).abs() > 1e-3 {
            return None;
        }
    }
    let e0 = pts[1] - pts[0];
    let e1 = pts[2] - pts[1];
    let center = (pts[0] + pts[2]) / 2.0;
    let (axis, hl, hw) = if e0.length() >= e1.length() {
        (e0.normalize(), e0.length() / 2.0, e1.length() / 2.0)
    } else {
        (e1.normalize(), e1.length() / 2.0, e0.length() / 2.0)
    };
    Some(OrientedRect { center, axis, half_length: hl, half_width: hw })
}

/// Clips a convex polygon to the band min <= f(p) <= max.
pub fn clip_convex(poly: &[DVec2], f: impl Fn(DVec2) -> f64, min: f64, max: f64) -> Vec<DVec2> {
    let a = clip_half(poly, |p| f(p) - min);
    clip_half(&a, |p| max - f(p))
}

fn clip_half(poly: &[DVec2], inside: impl Fn(DVec2) -> f64) -> Vec<DVec2> {
    let n = poly.len();
    let mut out = Vec::new();
    for i in 0..n {
        let cur = poly[i];
        let prev = poly[(i + n - 1) % n];
        let dc = inside(cur);
        let dp = inside(prev);
        if dc >= 0.0 {
            if dp < 0.0 {
                out.push(prev.lerp(cur, dp / (dp - dc)));
            }
            out.push(cur);
        } else if dp >= 0.0 {
            out.push(prev.lerp(cur, dp / (dp - dc)));
        }
    }
    out
}

/// Ear-clipping triangulation; triangles keep the input winding.
pub fn triangulate(pts: &[DVec2]) -> Vec<[usize; 3]> {
    let n = pts.len();
    let mut out = Vec::new();
    if n < 3 {
        return out;
    }
    let ccw = signed_area(pts) > 0.0;
    let mut idx: Vec<usize> = (0..n).collect();
    let mut guard = 0;
    while idx.len() > 3 && guard < n * n {
        guard += 1;
        let m = idx.len();
        let mut clipped = false;
        for i in 0..m {
            let ia = idx[(i + m - 1) % m];
            let ib = idx[i];
            let ic = idx[(i + 1) % m];
            let (a, b, c) = (pts[ia], pts[ib], pts[ic]);
            let cr = cross2(b - a, c - b);
            if if ccw { cr <= 1e-12 } else { cr >= -1e-12 } {
                continue;
            }
            let blocked = idx
                .iter()
                .any(|&j| j != ia && j != ib && j != ic && point_in_triangle(pts[j], a, b, c));
            if blocked {
                continue;
            }
            out.push([ia, ib, ic]);
            idx.remove(i);
            clipped = true;
            break;
        }
        if !clipped {
            for i in 1..idx.len() - 1 {
                out.push([idx[0], idx[i], idx[i + 1]]);
            }
            return out;
        }
    }
    if idx.len() == 3 {
        out.push([idx[0], idx[1], idx[2]]);
    }
    out
}

fn point_in_triangle(p: DVec2, a: DVec2, b: DVec2, c: DVec2) -> bool {
    let d1 = cross2(b - a, p - a);
    let d2 = cross2(c - b, p - b);
    let d3 = cross2(a - c, p - c);
    let neg = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
    let pos = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
    !(neg && pos)
}

/// A circular arc in plan.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Arc2 {
    pub center: DVec2,
    pub radius: f64,
    /// Angle of the start point (radians).
    pub start_angle: f64,
    /// Signed sweep (radians, positive = counter-clockwise).
    pub sweep: f64,
}

impl Arc2 {
    /// The arc from `a` through `m` to `b`; None if the points are (nearly) collinear.
    pub fn through(a: DVec2, m: DVec2, b: DVec2) -> Option<Arc2> {
        let d = 2.0 * (a.x * (m.y - b.y) + m.x * (b.y - a.y) + b.x * (a.y - m.y));
        if d.abs() < 1e-6 {
            return None;
        }
        let (a2, m2, b2) = (a.length_squared(), m.length_squared(), b.length_squared());
        let center = DVec2::new(
            (a2 * (m.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - m.y)) / d,
            (a2 * (b.x - m.x) + m2 * (a.x - b.x) + b2 * (m.x - a.x)) / d,
        );
        let radius = center.distance(a);
        if radius > 1e7 {
            return None;
        }
        let ang = |p: DVec2| (p - center).y.atan2((p - center).x);
        let (sa, ma, ea) = (ang(a), ang(m), ang(b));
        let tau = std::f64::consts::TAU;
        let ccw = |from: f64, to: f64| (to - from).rem_euclid(tau);
        // Choose the direction that passes through m.
        let sweep = if ccw(sa, ma) <= ccw(sa, ea) { ccw(sa, ea) } else { -ccw(ea, sa) };
        Some(Arc2 { center, radius, start_angle: sa, sweep })
    }

    /// Arc with a given centre from start to end, counter-clockwise if `ccw`.
    pub fn from_center(center: DVec2, start: DVec2, end: DVec2, ccw: bool) -> Arc2 {
        let ang = |p: DVec2| (p - center).y.atan2((p - center).x);
        let tau = std::f64::consts::TAU;
        let (sa, ea) = (ang(start), ang(end));
        let mut sweep = (ea - sa).rem_euclid(tau);
        if sweep < 1e-9 {
            sweep = tau;
        }
        if !ccw {
            sweep -= tau;
        }
        Arc2 { center, radius: center.distance(start), start_angle: sa, sweep }
    }

    pub fn length(&self) -> f64 {
        self.radius * self.sweep.abs()
    }

    /// Point at parameter t in [0, 1].
    pub fn point(&self, t: f64) -> DVec2 {
        let a = self.start_angle + self.sweep * t;
        self.center + DVec2::new(a.cos(), a.sin()) * self.radius
    }

    /// Unit tangent (direction of travel) at t.
    pub fn tangent(&self, t: f64) -> DVec2 {
        let a = self.start_angle + self.sweep * t;
        let d = DVec2::new(-a.sin(), a.cos());
        if self.sweep >= 0.0 { d } else { -d }
    }

    pub fn mid(&self) -> DVec2 {
        self.point(0.5)
    }

    /// Polyline approximation with segments no longer than `max_seg` and at most 5° each.
    pub fn tessellate(&self, max_seg: f64) -> Vec<DVec2> {
        let by_len = (self.length() / max_seg.max(1.0)).ceil() as usize;
        let by_ang = (self.sweep.abs() / 5f64.to_radians()).ceil() as usize;
        let n = by_len.max(by_ang).clamp(2, 256);
        (0..=n).map(|k| self.point(k as f64 / n as f64)).collect()
    }

    /// Parameter (0..1) of the point on the arc closest to p.
    pub fn param_of(&self, p: DVec2) -> f64 {
        let a = (p - self.center).y.atan2((p - self.center).x);
        let tau = std::f64::consts::TAU;
        let d = if self.sweep >= 0.0 { (a - self.start_angle).rem_euclid(tau) } else { (self.start_angle - a).rem_euclid(tau) };
        let t = d / self.sweep.abs();
        if t > 1.0 {
            // Beyond the end: snap to the nearer end.
            let over = d - self.sweep.abs();
            let under = tau - d;
            if over < under { 1.0 } else { 0.0 }
        } else {
            t
        }
    }
}

/// A local frame for placing things in the model (IFC-style placement).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Frame3 {
    pub origin: DVec3,
    pub x: DVec3,
    pub y: DVec3,
    pub z: DVec3,
}

impl Frame3 {
    pub const IDENTITY: Frame3 = Frame3 { origin: DVec3::ZERO, x: DVec3::X, y: DVec3::Y, z: DVec3::Z };

    /// Builds a frame from a Z axis and a reference X direction (IfcAxis2Placement3D semantics).
    pub fn from_axes(origin: DVec3, z: Option<DVec3>, ref_x: Option<DVec3>) -> Frame3 {
        let z = z.unwrap_or(DVec3::Z).normalize_or(DVec3::Z);
        let xr = ref_x.unwrap_or(DVec3::X);
        let mut x = (xr - z * xr.dot(z)).normalize_or_zero();
        if x.length() < 1e-9 {
            let helper = if z.x.abs() < 0.9 { DVec3::X } else { DVec3::Y };
            x = (helper - z * helper.dot(z)).normalize();
        }
        let y = z.cross(x).normalize();
        Frame3 { origin, x, y, z }
    }

    pub fn point(&self, p: DVec3) -> DVec3 {
        self.origin + self.x * p.x + self.y * p.y + self.z * p.z
    }

    pub fn vector(&self, v: DVec3) -> DVec3 {
        self.x * v.x + self.y * v.y + self.z * v.z
    }

    /// self ∘ child: apply child first, then self.
    pub fn then(&self, child: &Frame3) -> Frame3 {
        Frame3 {
            origin: self.point(child.origin),
            x: self.vector(child.x),
            y: self.vector(child.y),
            z: self.vector(child.z),
        }
    }
}
