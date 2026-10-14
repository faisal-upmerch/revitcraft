//! Roof surfaces from footprints: a weighted straight-skeleton wavefront sweep.
//!
//! Each footprint edge moves inward at its own speed (1 = slope-defining, 0 = gable). The swept
//! strips between successive wavefronts are planar pieces of the edge's roof plane. Edge events
//! (an edge shrinking to nothing) and split events (a reflex vertex hitting another edge) change
//! the wavefront's topology.

use crate::geom::{self, DVec2};

#[derive(Clone, Copy, Debug)]
struct Vtx {
    pos: DVec2,
    vel: DVec2,
    /// Index of the original edge leaving this vertex (towards the next vertex).
    edge_out: usize,
    /// Index of the original edge arriving at this vertex.
    edge_in: usize,
}

#[derive(Clone, Copy, Debug)]
struct EdgeLine {
    p: DVec2,
    dir: DVec2,
    /// Inward normal (left of the direction for a CCW polygon).
    n: DVec2,
    speed: f64,
}

/// Result of a sweep: roof surface triangles with heights in "time" units (horizontal distance
/// travelled by a speed-1 edge), and skeleton arcs (hips, valleys, ridges) in plan.
#[derive(Clone, Debug, Default)]
pub struct Sweep {
    /// Triangles (plan point, time) per original edge.
    pub faces: Vec<(usize, [(DVec2, f64); 3])>,
    pub arcs: Vec<(DVec2, DVec2)>,
}

fn velocity(a: &EdgeLine, b: &EdgeLine) -> DVec2 {
    // v·n_a = s_a and v·n_b = s_b.
    let det = a.n.x * b.n.y - a.n.y * b.n.x;
    if det.abs() < 1e-9 {
        // Collinear edges move along the shared normal at the mean speed; opposite edges that
        // have met (a collapsed strip) stay put.
        if a.n.dot(b.n) < 0.0 {
            return DVec2::ZERO;
        }
        return a.n * ((a.speed + b.speed) / 2.0);
    }
    DVec2::new((a.speed * b.n.y - b.speed * a.n.y) / det, (a.n.x * b.speed - b.n.x * a.speed) / det)
}

/// Sweeps a counter-clockwise footprint. `speeds[i]` belongs to edge i (pts[i] → pts[i+1]).
pub fn sweep(pts: &[DVec2], speeds: &[f64]) -> Sweep {
    let mut out = Sweep::default();
    let n = pts.len();
    if n < 3 || speeds.iter().all(|s| *s <= 0.0) {
        return out;
    }
    let lines: Vec<EdgeLine> = (0..n)
        .map(|i| {
            let a = pts[i];
            let b = pts[(i + 1) % n];
            let dir = (b - a).normalize_or_zero();
            EdgeLine { p: a, dir, n: geom::perp(dir), speed: speeds[i].max(0.0) }
        })
        .collect();
    let make = |pos: DVec2, edge_in: usize, edge_out: usize| Vtx { pos, vel: velocity(&lines[edge_in], &lines[edge_out]), edge_out, edge_in };
    let mut polys: Vec<Vec<Vtx>> = vec![(0..n).map(|i| make(pts[i], (i + n - 1) % n, i)).collect()];
    let mut time = 0.0;
    let eps = 1e-7;

    let scale = pts.iter().fold(0.0f64, |m, p| m.max(p.distance(pts[0]))).max(1e-9);
    for _iteration in 0..(20 * n + 50) {
        // A wavefront that has collapsed to zero area is finished: its edges are ridges.
        for poly in &mut polys {
            if poly.len() >= 3 {
                let ring: Vec<DVec2> = poly.iter().map(|v| v.pos).collect();
                if geom::area(&ring).abs() < 1e-9 * scale * scale {
                    for k in 0..ring.len() {
                        let (a, b) = (ring[k], ring[(k + 1) % ring.len()]);
                        if a.distance(b) > 1e-6 * scale && !out.arcs.iter().any(|(x, y)| x.distance(b) < 1e-9 && y.distance(a) < 1e-9) {
                            out.arcs.push((a, b));
                        }
                    }
                    poly.clear();
                }
            }
        }
        polys.retain(|p| p.len() >= 3);
        if polys.is_empty() {
            break;
        }
        // Find the earliest event over all wavefront polygons.
        #[derive(Clone, Copy)]
        enum Ev {
            Edge { poly: usize, k: usize },
            Split { poly: usize, a: usize, c: usize },
        }
        let mut best: Option<(f64, Ev)> = None;
        let consider = |dt: f64, ev: Ev, best: &mut Option<(f64, Ev)>| {
            if dt.is_finite() && dt >= -eps && best.as_ref().is_none_or(|b| dt < b.0) {
                *best = Some((dt.max(0.0), ev));
            }
        };
        for (pi, poly) in polys.iter().enumerate() {
            let m = poly.len();
            for k in 0..m {
                let a = poly[k];
                let b = poly[(k + 1) % m];
                let e = &lines[a.edge_out];
                // Edge event: the edge between a and b shrinks to zero.
                let rel = (b.pos - a.pos).dot(e.dir);
                let rate = (b.vel - a.vel).dot(e.dir);
                if rate < -1e-12 {
                    consider(-rel / rate, Ev::Edge { poly: pi, k }, &mut best);
                } else if rel.abs() < 1e-6 {
                    consider(0.0, Ev::Edge { poly: pi, k }, &mut best);
                }
            }
            // Split events: reflex vertices hitting non-adjacent edges.
            for ai in 0..m {
                let v = poly[ai];
                let din = lines[v.edge_in].dir;
                let dout = lines[v.edge_out].dir;
                if geom::cross2(din, dout) >= -1e-9 {
                    continue; // convex
                }
                for ci in 0..m {
                    let di = (ci + 1) % m;
                    if ci == ai || di == ai || ci == (ai + m - 1) % m {
                        continue;
                    }
                    let e = &lines[poly[ci].edge_out];
                    // Signed distance of v to edge line at relative time dt:
                    // n·(pos + vel dt) − (n·p + speed (time + dt)) = 0.
                    let d0 = e.n.dot(v.pos) - (e.n.dot(e.p) + e.speed * time);
                    let rate = e.n.dot(v.vel) - e.speed;
                    if rate >= -1e-12 || d0 < -1e-6 {
                        continue;
                    }
                    let dt = -d0 / rate;
                    // The hit point must be within the edge at that time.
                    let hit = v.pos + v.vel * dt;
                    let c = poly[ci].pos + poly[ci].vel * dt;
                    let d = poly[di].pos + poly[di].vel * dt;
                    let len = (d - c).dot(e.dir);
                    let along = (hit - c).dot(e.dir);
                    if len > 1e-6 && along > 1e-6 && along < len - 1e-6 {
                        consider(dt, Ev::Split { poly: pi, a: ai, c: ci }, &mut best);
                    }
                }
            }
        }
        let Some((dt, ev)) = best else { break };
        let t1 = time + dt;
        // Advance every wavefront, emitting swept faces and skeleton arcs.
        for poly in &mut polys {
            let m = poly.len();
            let new: Vec<DVec2> = poly.iter().map(|v| v.pos + v.vel * dt).collect();
            if dt > 1e-9 {
                for k in 0..m {
                    let j = (k + 1) % m;
                    let e = poly[k].edge_out;
                    if lines[e].speed <= 0.0 {
                        continue; // vertical gable face
                    }
                    let (a0, b0, a1, b1) = (poly[k].pos, poly[j].pos, new[k], new[j]);
                    out.faces.push((e, [(a0, time), (b0, time), (b1, t1)]));
                    if a1.distance(b1) > 1e-6 {
                        out.faces.push((e, [(a0, time), (b1, t1), (a1, t1)]));
                    }
                }
                for (k, v) in poly.iter().enumerate() {
                    if v.pos.distance(new[k]) > 1e-6 {
                        out.arcs.push((v.pos, new[k]));
                    }
                }
            }
            for (k, v) in poly.iter_mut().enumerate() {
                v.pos = new[k];
            }
        }
        time = t1;
        match ev {
            Ev::Edge { poly, k } => {
                let p = &mut polys[poly];
                let m = p.len();
                let j = (k + 1) % m;
                let a = p[k];
                let b = p[j];
                let merged = make((a.pos + b.pos) / 2.0, a.edge_in, b.edge_out);
                if j == 0 {
                    p.remove(k);
                    p[0] = merged;
                } else {
                    p[k] = merged;
                    p.remove(j);
                }
                if p.len() < 3 {
                    // The remaining wavefront collapses to a segment: that's a ridge.
                    if p.len() == 2 && p[0].pos.distance(p[1].pos) > 1e-6 {
                        out.arcs.push((p[0].pos, p[1].pos));
                    }
                }
            }
            Ev::Split { poly, a, c } => {
                let p = polys[poly].clone();
                let m = p.len();
                let v = p[a];
                let e = p[c].edge_out;
                let d = (c + 1) % m;
                // Polygon A: v(in = v.edge_in, out = e), d, ..., prev(v).
                let mut pa = vec![make(v.pos, v.edge_in, e)];
                let mut k = d;
                while k != a {
                    pa.push(p[k]);
                    k = (k + 1) % m;
                }
                // Polygon B: v(in = e, out = v.edge_out), next(v), ..., c.
                let mut pb = vec![make(v.pos, e, v.edge_out)];
                let mut k = (a + 1) % m;
                loop {
                    pb.push(p[k]);
                    if k == c {
                        break;
                    }
                    k = (k + 1) % m;
                }
                polys[poly] = pa;
                polys.push(pb);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn height_at(s: &Sweep, q: DVec2) -> Option<f64> {
        for (_, t) in &s.faces {
            let (a, b, c) = (t[0].0, t[1].0, t[2].0);
            let det = geom::cross2(b - a, c - a);
            if det.abs() < 1e-9 {
                continue;
            }
            let l1 = geom::cross2(b - q, c - q) / det;
            let l2 = geom::cross2(c - q, a - q) / det;
            let l3 = 1.0 - l1 - l2;
            if l1 >= -1e-9 && l2 >= -1e-9 && l3 >= -1e-9 {
                return Some(l1 * t[0].1 + l2 * t[1].1 + l3 * t[2].1);
            }
        }
        None
    }

    #[test]
    fn hip_roof_on_rectangle() {
        let pts = vec![DVec2::new(0.0, 0.0), DVec2::new(10.0, 0.0), DVec2::new(10.0, 6.0), DVec2::new(0.0, 6.0)];
        let s = sweep(&pts, &[1.0; 4]);
        assert!((height_at(&s, DVec2::new(5.0, 3.0)).unwrap() - 3.0).abs() < 1e-6);
        assert!((height_at(&s, DVec2::new(1.0, 3.0)).unwrap() - 1.0).abs() < 1e-6);
        assert!((height_at(&s, DVec2::new(5.0, 0.5)).unwrap() - 0.5).abs() < 1e-6);
    }

    #[test]
    fn gable_roof_has_full_length_ridge() {
        let pts = vec![DVec2::new(0.0, 0.0), DVec2::new(10.0, 0.0), DVec2::new(10.0, 6.0), DVec2::new(0.0, 6.0)];
        let s = sweep(&pts, &[1.0, 0.0, 1.0, 0.0]);
        // Near the gable ends the height is still the ridge height on the centre line.
        assert!((height_at(&s, DVec2::new(0.2, 3.0)).unwrap() - 3.0).abs() < 1e-6);
        assert!((height_at(&s, DVec2::new(9.8, 1.0)).unwrap() - 1.0).abs() < 1e-6);
    }

    #[test]
    fn l_shaped_hip_roof_has_valley() {
        // L shape: 10 x 4 bar plus a 4 x 6 wing.
        let pts = vec![
            DVec2::new(0.0, 0.0),
            DVec2::new(10.0, 0.0),
            DVec2::new(10.0, 4.0),
            DVec2::new(4.0, 4.0),
            DVec2::new(4.0, 10.0),
            DVec2::new(0.0, 10.0),
        ];
        let s = sweep(&pts, &[1.0; 6]);
        // Everywhere the height equals the distance to the nearest edge for this convex-piece union.
        for (q, want) in [(DVec2::new(8.0, 2.0), 2.0), (DVec2::new(2.0, 8.0), 2.0), (DVec2::new(2.0, 2.0), 2.0), (DVec2::new(5.0, 3.0), 1.0)] {
            let h = height_at(&s, q).unwrap_or(-1.0);
            assert!((h - want).abs() < 1e-6, "{q:?}: {h}");
        }
        let total: f64 = s.faces.iter().map(|(_, t)| geom::area(&[t[0].0, t[1].0, t[2].0])).sum();
        assert!((total - 64.0).abs() < 1e-6, "{total}");
    }
}
