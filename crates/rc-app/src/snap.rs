//! Object snaps and drawing aids: endpoints, midpoints, intersections, centres, quadrants,
//! perpendicular and tangent points, nearest, alignment and extension tracking lines, and
//! angle/length increments relative to the last picked point.

use rc_core::geom::{self, Arc2, DVec2};
use rc_core::model::Id;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SnapKind {
    Endpoint,
    Midpoint,
    Center,
    Intersection,
    Perpendicular,
    Tangent,
    Quadrant,
    Nearest,
    Alignment,
    Extension,
    Angle,
    Free,
}

impl SnapKind {
    pub fn label(self) -> &'static str {
        match self {
            SnapKind::Endpoint => "Endpoint",
            SnapKind::Midpoint => "Midpoint",
            SnapKind::Center => "Center",
            SnapKind::Intersection => "Intersection",
            SnapKind::Perpendicular => "Perpendicular",
            SnapKind::Tangent => "Tangent",
            SnapKind::Quadrant => "Quadrant",
            SnapKind::Nearest => "Nearest",
            SnapKind::Alignment => "Alignment",
            SnapKind::Extension => "Extension",
            SnapKind::Angle => "Angle",
            SnapKind::Free => "",
        }
    }
}

/// Snap toggles (Manage > Snaps). Kept per user, not per project.
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct SnapSettings {
    pub enabled: bool,
    pub endpoints: bool,
    pub midpoints: bool,
    pub nearest: bool,
    pub intersections: bool,
    pub centers: bool,
    pub perpendicular: bool,
    pub tangents: bool,
    pub quadrants: bool,
    pub remote: bool,
    pub length_increments: bool,
    pub angle_increments: bool,
}

impl Default for SnapSettings {
    fn default() -> Self {
        SnapSettings {
            enabled: true,
            endpoints: true,
            midpoints: true,
            nearest: true,
            intersections: true,
            centers: true,
            perpendicular: true,
            tangents: true,
            quadrants: true,
            remote: true,
            length_increments: true,
            angle_increments: true,
        }
    }
}

/// A one-shot snap override typed as a two-letter code (SE, SM, SI ...); `Off` disables snapping
/// for the next pick.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Override {
    Only(SnapKind),
    Off,
}

/// Geometry the cursor can snap to, gathered from the active view.
#[derive(Default, Clone)]
pub struct SnapGeom {
    pub segs: Vec<(DVec2, DVec2, Option<Id>)>,
    pub arcs: Vec<(Arc2, Option<Id>)>,
    /// Extra key points (insertion points, room points, sketch vertices).
    pub points: Vec<(DVec2, Option<Id>)>,
}

impl SnapGeom {
    pub fn add_polyline(&mut self, pts: &[DVec2], closed: bool, id: Option<Id>) {
        let n = pts.len();
        if n < 2 {
            return;
        }
        for k in 0..n - 1 {
            if pts[k].distance(pts[k + 1]) > 1e-6 {
                self.segs.push((pts[k], pts[k + 1], id));
            }
        }
        if closed && n > 2 && pts[n - 1].distance(pts[0]) > 1e-6 {
            self.segs.push((pts[n - 1], pts[0], id));
        }
    }
}

#[derive(Clone, Debug)]
pub struct SnapResult {
    pub point: DVec2,
    pub kind: SnapKind,
    /// Dashed tracking lines to draw (alignment, extension, angle rays).
    pub guides: Vec<(DVec2, DVec2)>,
    #[allow(dead_code)]
    pub target: Option<Id>,
}

pub struct SnapInput<'a> {
    pub geom: &'a SnapGeom,
    pub cursor: DVec2,
    /// Pick tolerance in model units (a few pixels).
    pub tol: f64,
    /// Screen pixels per model unit.
    pub zoom: f64,
    pub reference: Option<DVec2>,
    /// Shift: constrain to horizontal/vertical from the reference point.
    pub ortho: bool,
    pub settings: &'a SnapSettings,
    pub over: Option<Override>,
    pub imperial: bool,
}

fn allowed(inp: &SnapInput, k: SnapKind) -> bool {
    let s = inp.settings;
    match inp.over {
        Some(Override::Off) => return false,
        Some(Override::Only(o)) => return o == k,
        None => {}
    }
    if !s.enabled {
        return false;
    }
    match k {
        SnapKind::Endpoint => s.endpoints,
        SnapKind::Midpoint => s.midpoints,
        SnapKind::Center => s.centers,
        SnapKind::Intersection => s.intersections,
        SnapKind::Perpendicular => s.perpendicular,
        SnapKind::Tangent => s.tangents,
        SnapKind::Quadrant => s.quadrants,
        SnapKind::Nearest => s.nearest,
        SnapKind::Alignment | SnapKind::Extension => s.remote,
        SnapKind::Angle => s.angle_increments,
        SnapKind::Free => true,
    }
}

/// Length increment for the current zoom: the smallest "round" length at least ~5 px long.
pub fn length_increment(zoom: f64, imperial: bool) -> f64 {
    let steps: &[f64] = if imperial {
        &[3.175, 6.35, 12.7, 25.4, 76.2, 152.4, 304.8, 609.6, 1524.0, 3048.0, 15240.0]
    } else {
        &[1.0, 5.0, 10.0, 50.0, 100.0, 500.0, 1000.0, 5000.0, 10000.0]
    };
    for s in steps {
        if s * zoom >= 5.0 {
            return *s;
        }
    }
    *steps.last().unwrap()
}

/// Angle increment (degrees) for a rubber band of `radius_px` pixels.
pub fn angle_increment(radius_px: f64) -> f64 {
    if radius_px < 60.0 {
        45.0
    } else if radius_px < 220.0 {
        15.0
    } else if radius_px < 900.0 {
        5.0
    } else {
        1.0
    }
}

fn line_line(a: DVec2, b: DVec2, c: DVec2, d: DVec2) -> Option<DVec2> {
    let (t, u) = geom::segment_intersection(a, b, c, d)?;
    ((-1e-9..=1.0 + 1e-9).contains(&t) && (-1e-9..=1.0 + 1e-9).contains(&u)).then(|| a + (b - a) * t)
}

fn seg_arc(a: DVec2, b: DVec2, arc: &Arc2) -> Vec<DVec2> {
    let d = b - a;
    let f = a - arc.center;
    let aa = d.dot(d);
    if aa < 1e-12 {
        return vec![];
    }
    let bb = 2.0 * f.dot(d);
    let cc = f.dot(f) - arc.radius * arc.radius;
    let disc = bb * bb - 4.0 * aa * cc;
    if disc < 0.0 {
        return vec![];
    }
    let s = disc.sqrt();
    [(-bb - s) / (2.0 * aa), (-bb + s) / (2.0 * aa)]
        .into_iter()
        .filter(|t| (0.0..=1.0).contains(t))
        .map(|t| a + d * t)
        .filter(|q| on_arc(arc, *q))
        .collect()
}

fn on_arc(arc: &Arc2, q: DVec2) -> bool {
    let tau = std::f64::consts::TAU;
    if arc.sweep.abs() >= tau - 1e-9 {
        return true;
    }
    let a = (q - arc.center).y.atan2((q - arc.center).x);
    let d = if arc.sweep >= 0.0 { (a - arc.start_angle).rem_euclid(tau) } else { (arc.start_angle - a).rem_euclid(tau) };
    d <= arc.sweep.abs() + 1e-6
}

pub fn snap(inp: &SnapInput) -> SnapResult {
    let c = inp.cursor;
    let tol = inp.tol;
    let free = SnapResult { point: c, kind: SnapKind::Free, guides: vec![], target: None };
    if matches!(inp.over, Some(Override::Off)) {
        return free;
    }
    let tol_pts = if matches!(inp.over, Some(Override::Only(_))) { tol * 3.0 } else { tol };

    // Nearby geometry.
    let near_segs: Vec<&(DVec2, DVec2, Option<Id>)> =
        inp.geom.segs.iter().filter(|(a, b, _)| geom::distance_to_segment(*a, *b, c) <= tol_pts * 2.5).collect();
    let near_arcs: Vec<&(Arc2, Option<Id>)> = inp
        .geom
        .arcs
        .iter()
        .filter(|(a, _)| ((c.distance(a.center) - a.radius).abs() <= tol_pts * 2.5) || c.distance(a.center) <= tol_pts * 2.0)
        .collect();

    // ---- point snaps (priority-weighted nearest)
    let mut best: Option<(f64, SnapResult)> = None;
    let consider = |q: DVec2, kind: SnapKind, prio: f64, target: Option<Id>, best: &mut Option<(f64, SnapResult)>| {
        if !allowed(inp, kind) {
            return;
        }
        let d = q.distance(c);
        if d > tol_pts {
            return;
        }
        let score = d + prio * tol_pts * 0.35;
        if best.as_ref().is_none_or(|b| score < b.0) {
            *best = Some((score, SnapResult { point: q, kind, guides: vec![], target }));
        }
    };
    for (a, b, id) in &near_segs {
        consider(*a, SnapKind::Endpoint, 0.0, *id, &mut best);
        consider(*b, SnapKind::Endpoint, 0.0, *id, &mut best);
        consider((*a + *b) / 2.0, SnapKind::Midpoint, 1.0, *id, &mut best);
    }
    for (q, id) in &inp.geom.points {
        consider(*q, SnapKind::Endpoint, 0.2, *id, &mut best);
    }
    for (arc, id) in &near_arcs {
        consider(arc.center, SnapKind::Center, 0.5, *id, &mut best);
        consider(arc.point(0.0), SnapKind::Endpoint, 0.0, *id, &mut best);
        consider(arc.point(1.0), SnapKind::Endpoint, 0.0, *id, &mut best);
        consider(arc.mid(), SnapKind::Midpoint, 1.0, *id, &mut best);
        for k in 0..4 {
            let ang = k as f64 * std::f64::consts::FRAC_PI_2;
            let q = arc.center + DVec2::new(ang.cos(), ang.sin()) * arc.radius;
            if on_arc(arc, q) {
                consider(q, SnapKind::Quadrant, 1.2, *id, &mut best);
            }
        }
    }
    // Intersections between nearby curves.
    for i in 0..near_segs.len() {
        for j in i + 1..near_segs.len() {
            let (a, b, ia) = near_segs[i];
            let (cc, d, _) = near_segs[j];
            if let Some(q) = line_line(*a, *b, *cc, *d) {
                consider(q, SnapKind::Intersection, 0.3, *ia, &mut best);
            }
        }
        for (arc, _) in &near_arcs {
            let (a, b, ia) = near_segs[i];
            for q in seg_arc(*a, *b, arc) {
                consider(q, SnapKind::Intersection, 0.3, *ia, &mut best);
            }
        }
    }
    // Perpendicular / tangent relative to the previous point.
    if let Some(r) = inp.reference {
        for (a, b, id) in &near_segs {
            let d = (*b - *a).normalize_or_zero();
            if d == DVec2::ZERO {
                continue;
            }
            let foot = *a + d * (r - *a).dot(d);
            if geom::distance_to_segment(*a, *b, foot) < 1e-6 && foot.distance(r) > 1e-3 {
                consider(foot, SnapKind::Perpendicular, 0.8, *id, &mut best);
            }
        }
        for (arc, id) in &near_arcs {
            let dc = r.distance(arc.center);
            if dc > arc.radius + 1e-6 {
                let base = (r - arc.center).y.atan2((r - arc.center).x);
                let off = (arc.radius / dc).acos();
                for s in [-1.0, 1.0] {
                    let ang = base + s * off;
                    let q = arc.center + DVec2::new(ang.cos(), ang.sin()) * arc.radius;
                    if on_arc(arc, q) {
                        consider(q, SnapKind::Tangent, 0.8, *id, &mut best);
                    }
                }
            }
        }
    }
    if let Some((_, r)) = best {
        return r;
    }
    if let Some(Override::Only(k)) = inp.over {
        // Only nearest-type overrides fall through.
        if k != SnapKind::Nearest {
            return free;
        }
    }

    // ---- angle snap from the reference point (with length increments)
    let mut angled: Option<SnapResult> = None;
    if let Some(r) = inp.reference {
        let v = c - r;
        let dist = v.length();
        if dist > 1e-6 {
            let ang = v.y.atan2(v.x).to_degrees();
            let radius_px = dist * inp.zoom;
            let inc = if inp.ortho { 90.0 } else { angle_increment(radius_px) };
            let snapped = (ang / inc).round() * inc;
            let diff = ((ang - snapped + 540.0) % 360.0 - 180.0).abs().to_radians();
            if inp.ortho || (allowed(inp, SnapKind::Angle) && diff * dist <= tol * 1.2) {
                let dir = DVec2::new(snapped.to_radians().cos(), snapped.to_radians().sin());
                let mut len = v.dot(dir);
                // Intersections of the angle ray with nearby geometry take priority.
                let ray_end = r + dir * len;
                let mut hit: Option<(DVec2, Option<Id>)> = None;
                for (a, b, id) in &near_segs {
                    if let Some((t, u)) = geom::segment_intersection(r, r + dir * (len * 2.0 + 1.0), *a, *b) {
                        if (0.0..=1.0).contains(&u) && t > 0.0 {
                            let q = r + dir * ((len * 2.0 + 1.0) * t);
                            if q.distance(ray_end) <= tol && hit.is_none_or(|h| h.0.distance(ray_end) > q.distance(ray_end)) {
                                hit = Some((q, *id));
                            }
                        }
                    }
                }
                if let Some((q, id)) = hit {
                    if allowed(inp, SnapKind::Intersection) || inp.ortho {
                        return SnapResult { point: q, kind: SnapKind::Intersection, guides: vec![(r, q)], target: id };
                    }
                }
                if inp.settings.length_increments {
                    let step = length_increment(inp.zoom, inp.imperial);
                    len = (len / step).round() * step;
                }
                let q = r + dir * len;
                angled = Some(SnapResult { point: q, kind: SnapKind::Angle, guides: vec![(r, r + dir * (len + 40.0 / inp.zoom))], target: None });
            }
        }
    }

    // Nearest point on a curve under the cursor (used below and as the last resort).
    let mut nearest: Option<(f64, DVec2, Option<Id>, Option<(DVec2, DVec2)>)> = None;
    if allowed(inp, SnapKind::Nearest) {
        for (a, b, id) in &near_segs {
            let (q, _) = geom::closest_on_segment(*a, *b, c);
            let d = q.distance(c);
            if d <= tol && nearest.is_none_or(|n| d < n.0) {
                nearest = Some((d, q, *id, Some((*a, *b))));
            }
        }
        for (arc, id) in &near_arcs {
            let dir = (c - arc.center).normalize_or_zero();
            let q = arc.center + dir * arc.radius;
            let d = q.distance(c);
            if d <= tol && on_arc(arc, q) && nearest.is_none_or(|n| d < n.0) {
                nearest = Some((d, q, *id, None));
            }
        }
    }

    // ---- alignment and extension tracking
    if allowed(inp, SnapKind::Alignment) {
        let mut key: Vec<DVec2> = Vec::new();
        for (a, b, _) in &inp.geom.segs {
            key.push(*a);
            key.push(*b);
        }
        for (q, _) in &inp.geom.points {
            key.push(*q);
        }
        if let Some(r) = inp.reference {
            key.push(r);
        }
        let reach = 2500.0 / inp.zoom.max(1e-9) * 0.1; // ≈ 250 px either way
        let mut vx: Option<(f64, DVec2)> = None; // vertical alignment line (shared x)
        let mut hy: Option<(f64, DVec2)> = None; // horizontal (shared y)
        for k in &key {
            let d = k.distance(c);
            if d < tol || d > reach * 4.0 {
                continue;
            }
            if (k.x - c.x).abs() <= tol && vx.is_none_or(|v| d < v.0) {
                vx = Some((d, *k));
            }
            if (k.y - c.y).abs() <= tol && hy.is_none_or(|h| d < h.0) {
                hy = Some((d, *k));
            }
        }
        // Extensions of nearby lines beyond their ends.
        let mut ext: Option<(f64, DVec2, DVec2)> = None;
        if allowed(inp, SnapKind::Extension) {
            for (a, b, _) in &inp.geom.segs {
                let d = *b - *a;
                let len = d.length();
                if len < 1e-6 {
                    continue;
                }
                let u = d / len;
                let t = (c - *a).dot(u);
                let off = (c - (*a + u * t)).length();
                if off > tol || (t >= -tol && t <= len + tol) {
                    continue;
                }
                let (anchor, gap) = if t < 0.0 { (*a, -t) } else { (*b, t - len) };
                if gap > reach * 3.0 {
                    continue;
                }
                let q = *a + u * t;
                if ext.is_none_or(|e| off < e.0) {
                    ext = Some((off, q, anchor));
                }
            }
        }
        match (vx, hy) {
            (Some((_, kx)), Some((_, ky))) => {
                let q = DVec2::new(kx.x, ky.y);
                return SnapResult { point: q, kind: SnapKind::Alignment, guides: vec![(kx, q), (ky, q)], target: None };
            }
            (Some((_, k)), None) | (None, Some((_, k))) => {
                let vertical = vx.is_some();
                // Combine with the angle ray or an extension when possible.
                if let Some(a) = &angled {
                    let r = inp.reference.unwrap();
                    let dir = (a.point - r).normalize_or_zero();
                    let line_p = k;
                    let line_d = if vertical { DVec2::Y } else { DVec2::X };
                    if let Some(q) = geom::line_intersection(r, dir, line_p, line_d) {
                        if q.distance(c) <= tol * 2.0 {
                            return SnapResult { point: q, kind: SnapKind::Alignment, guides: vec![(k, q), (r, q)], target: None };
                        }
                    }
                }
                if let Some((_, eq, anchor)) = ext {
                    let line_d = if vertical { DVec2::Y } else { DVec2::X };
                    if let Some(q) = geom::line_intersection(anchor, (eq - anchor).normalize_or_zero(), k, line_d) {
                        if q.distance(c) <= tol * 2.0 {
                            return SnapResult { point: q, kind: SnapKind::Intersection, guides: vec![(k, q), (anchor, q)], target: None };
                        }
                    }
                }
                if angled.is_none() {
                    // On a line: snap where the alignment guide crosses it, else stay on the line.
                    if let Some((_, nq, nid, seg)) = nearest {
                        if let Some((a, b)) = seg {
                            let line_d = if vertical { DVec2::Y } else { DVec2::X };
                            if let Some(q) = geom::line_intersection(a, (b - a).normalize_or_zero(), k, line_d) {
                                if q.distance(c) <= tol * 1.5 && geom::distance_to_segment(a, b, q) < 1e-6 {
                                    return SnapResult { point: q, kind: SnapKind::Alignment, guides: vec![(k, q)], target: nid };
                                }
                            }
                        }
                        return SnapResult { point: nq, kind: SnapKind::Nearest, guides: vec![], target: nid };
                    }
                    let q = if vertical { DVec2::new(k.x, c.y) } else { DVec2::new(c.x, k.y) };
                    return SnapResult { point: q, kind: SnapKind::Alignment, guides: vec![(k, q)], target: None };
                }
            }
            (None, None) => {
                if let (Some((_, q, anchor)), None, None) = (ext, &angled, nearest) {
                    return SnapResult { point: q, kind: SnapKind::Extension, guides: vec![(anchor, q)], target: None };
                }
            }
        }
    }
    if let Some(a) = angled {
        return a;
    }

    // ---- nearest
    if let Some((_, q, id, _)) = nearest {
        return SnapResult { point: q, kind: SnapKind::Nearest, guides: vec![], target: id };
    }
    free
}

#[cfg(test)]
mod tests {
    use super::*;

    fn geom_l() -> SnapGeom {
        let mut g = SnapGeom::default();
        g.add_polyline(&[DVec2::new(0.0, 0.0), DVec2::new(5000.0, 0.0), DVec2::new(5000.0, 4000.0)], false, Some(1));
        g
    }

    fn input<'a>(g: &'a SnapGeom, s: &'a SnapSettings, c: DVec2, r: Option<DVec2>) -> SnapInput<'a> {
        SnapInput { geom: g, cursor: c, tol: 100.0, zoom: 0.08, reference: r, ortho: false, settings: s, over: None, imperial: false }
    }

    #[test]
    fn endpoints_beat_midpoints_and_nearest() {
        let g = geom_l();
        let s = SnapSettings::default();
        let r = snap(&input(&g, &s, DVec2::new(4960.0, 30.0), None));
        assert_eq!(r.kind, SnapKind::Endpoint);
        assert_eq!(r.point, DVec2::new(5000.0, 0.0));
        let r = snap(&input(&g, &s, DVec2::new(2520.0, 40.0), None));
        assert_eq!(r.kind, SnapKind::Midpoint);
        let r = snap(&input(&g, &s, DVec2::new(1200.0, 40.0), None));
        assert_eq!(r.kind, SnapKind::Nearest);
        assert!((r.point.y).abs() < 1e-9);
    }

    #[test]
    fn alignment_and_angle_tracking() {
        let g = geom_l();
        let s = SnapSettings::default();
        // Straight above the origin: aligned with the (0,0) endpoint.
        let r = snap(&input(&g, &s, DVec2::new(40.0, 3000.0), None));
        assert_eq!(r.kind, SnapKind::Alignment);
        assert!((r.point.x).abs() < 1e-9);
        // Drawing from (0, 8000) towards the right lands on the horizontal ray with a round length.
        let r = snap(&input(&g, &s, DVec2::new(2337.0, 8030.0), Some(DVec2::new(0.0, 8000.0))));
        assert!(matches!(r.kind, SnapKind::Angle | SnapKind::Alignment));
        assert!((r.point.y - 8000.0).abs() < 1e-9);
        // Perpendicular foot onto the vertical segment.
        let r = snap(&input(&g, &s, DVec2::new(4950.0, 2510.0), Some(DVec2::new(1000.0, 2500.0))));
        assert_eq!(r.kind, SnapKind::Perpendicular);
        assert!((r.point - DVec2::new(5000.0, 2500.0)).length() < 1e-9);
    }

    #[test]
    fn overrides() {
        let g = geom_l();
        let s = SnapSettings::default();
        let mut i = input(&g, &s, DVec2::new(4960.0, 30.0), None);
        i.over = Some(Override::Off);
        assert_eq!(snap(&i).kind, SnapKind::Free);
        i.over = Some(Override::Only(SnapKind::Midpoint));
        i.cursor = DVec2::new(2700.0, 30.0);
        assert_eq!(snap(&i).kind, SnapKind::Midpoint);
    }
}
