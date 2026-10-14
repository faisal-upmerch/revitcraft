//! Parametric family definitions (the family editor's content): reference planes driven by
//! labelled dimensions and EQ constraints, and solid/void forms sketched on those planes.

use crate::csg::{self, Solid};
use crate::geom::{self, DVec2, DVec3};
use crate::mesh::{Mesh, MeshSet};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Normal axis of a reference plane: X planes are x = c (left/right), Y planes y = c
/// (front/back), Z planes z = c (heights).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Axis {
    X,
    Y,
    Z,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RefPlaneDef {
    pub id: u32,
    pub name: String,
    pub axis: Axis,
    /// Position when nothing else drives it (and the solver's starting point).
    pub default: f64,
    /// Origin planes ("Center (Left/Right)", "Ref. Level") never move.
    #[serde(default)]
    pub fixed: bool,
}

/// A dimension between reference planes of the same axis.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DimDef {
    pub planes: Vec<u32>,
    /// Parameter driving the overall distance (first to last plane); empty = not driving.
    #[serde(default)]
    pub label: String,
    /// EQ: consecutive spans are kept equal.
    #[serde(default)]
    pub equal: bool,
    /// Locked: keeps its current (default) distance.
    #[serde(default)]
    pub locked: bool,
}

/// A sketch coordinate: locked to a reference plane, or a fixed value.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub enum Loc {
    Plane(u32),
    Value(f64),
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SketchPt {
    pub a: Loc,
    pub b: Loc,
}

/// Sketch planes: XY sketches (x, y) extruded along z; XZ sketches (x, z) along y; YZ sketches (y, z) along x.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SketchPlane {
    XY,
    XZ,
    YZ,
}

impl SketchPlane {
    pub fn axes(self) -> (Axis, Axis, Axis) {
        match self {
            SketchPlane::XY => (Axis::X, Axis::Y, Axis::Z),
            SketchPlane::XZ => (Axis::X, Axis::Z, Axis::Y),
            SketchPlane::YZ => (Axis::Y, Axis::Z, Axis::X),
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            SketchPlane::XY => "Ref. Level (plan)",
            SketchPlane::XZ => "Front (elevation)",
            SketchPlane::YZ => "Right (elevation)",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum Form {
    Extrusion { plane: SketchPlane, profile: Vec<SketchPt>, start: Loc, end: Loc },
    /// Plan profiles at two heights, lofted.
    Blend { bottom: Vec<SketchPt>, top: Vec<SketchPt>, start: Loc, end: Loc },
    /// A profile in the XZ plane (a = x, b = z) revolved about the vertical axis through `axis`.
    Revolve { profile: Vec<SketchPt>, axis: SketchPt, angle_deg: f64 },
    /// A rectangular profile swept along a plan path at height `z`.
    Sweep { path: Vec<SketchPt>, z: Loc, width: f64, height: f64 },
}

impl Form {
    pub fn kind_label(&self) -> &'static str {
        match self {
            Form::Extrusion { .. } => "Extrusion",
            Form::Blend { .. } => "Blend",
            Form::Revolve { .. } => "Revolve",
            Form::Sweep { .. } => "Sweep",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FormDef {
    pub name: String,
    pub form: Form,
    #[serde(default)]
    pub void: bool,
    /// Family parameter (Material kind) or a literal material name.
    #[serde(default)]
    pub material: String,
    /// Yes/No parameter controlling visibility; empty = always visible.
    #[serde(default)]
    pub visible: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SymLine {
    pub a: SketchPt,
    pub b: SketchPt,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct FamilyDef {
    pub planes: Vec<RefPlaneDef>,
    pub dims: Vec<DimDef>,
    pub forms: Vec<FormDef>,
    /// Plan-only symbolic lines (XY).
    #[serde(default)]
    pub symbolic: Vec<SymLine>,
}

pub type Solved = HashMap<u32, f64>;

impl FamilyDef {
    pub fn plane(&self, id: u32) -> Option<&RefPlaneDef> {
        self.planes.iter().find(|p| p.id == id)
    }

    pub fn next_plane_id(&self) -> u32 {
        self.planes.iter().map(|p| p.id).max().unwrap_or(0) + 1
    }

    /// Solves plane positions from parameter values (`param` returns None for unknown names).
    pub fn solve(&self, param: &dyn Fn(&str) -> Option<f64>) -> Result<Solved, String> {
        let mut out = Solved::new();
        for axis in [Axis::X, Axis::Y, Axis::Z] {
            let planes: Vec<&RefPlaneDef> = self.planes.iter().filter(|p| p.axis == axis).collect();
            if planes.is_empty() {
                continue;
            }
            let idx: HashMap<u32, usize> = planes.iter().enumerate().map(|(i, p)| (p.id, i)).collect();
            let n = planes.len();
            // Rows: (coefficients, rhs, weight).
            let mut rows: Vec<(Vec<f64>, f64, f64)> = Vec::new();
            const HARD: f64 = 1e8;
            for (i, p) in planes.iter().enumerate() {
                let mut c = vec![0.0; n];
                c[i] = 1.0;
                rows.push((c, p.default, if p.fixed { HARD } else { 1e-6 }));
            }
            for d in &self.dims {
                let ids: Vec<usize> = d.planes.iter().filter_map(|id| idx.get(id).copied()).collect();
                if ids.len() != d.planes.len() || ids.len() < 2 {
                    continue;
                }
                let first = ids[0];
                let last = *ids.last().unwrap();
                let span_default = planes[last].default - planes[first].default;
                let sign = if span_default < 0.0 { -1.0 } else { 1.0 };
                let target = if !d.label.is_empty() {
                    let v = param(&d.label).ok_or_else(|| format!("Dimension label '{}' is not a parameter.", d.label))?;
                    Some(sign * v)
                } else if d.locked {
                    Some(span_default)
                } else {
                    None
                };
                if let Some(t) = target {
                    let mut c = vec![0.0; n];
                    c[last] += 1.0;
                    c[first] -= 1.0;
                    rows.push((c, t, HARD));
                }
                if d.equal && ids.len() >= 3 {
                    for k in 0..ids.len() - 2 {
                        // (x1 - x0) - (x2 - x1) = 0
                        let mut c = vec![0.0; n];
                        c[ids[k + 1]] += 2.0;
                        c[ids[k]] -= 1.0;
                        c[ids[k + 2]] -= 1.0;
                        rows.push((c, 0.0, HARD));
                    }
                }
            }
            let x = least_squares(&rows, n).ok_or("The family's constraints cannot be satisfied.")?;
            // Check hard rows are satisfied (over-constrained otherwise).
            for (c, rhs, w) in &rows {
                if *w >= HARD {
                    let lhs: f64 = c.iter().zip(&x).map(|(a, b)| a * b).sum();
                    if (lhs - rhs).abs() > 0.5 {
                        return Err("Constraints are not satisfied: the family is over-constrained.".into());
                    }
                }
            }
            for (i, p) in planes.iter().enumerate() {
                out.insert(p.id, x[i]);
            }
        }
        Ok(out)
    }

    /// Builds the family geometry (solids minus voids) in family coordinates.
    pub fn build(&self, solved: &Solved, material: &dyn Fn(&str) -> String, visible: &dyn Fn(&str) -> bool) -> MeshSet {
        let mut solids: Vec<(String, MeshSet)> = Vec::new();
        let mut voids = Solid::default();
        for f in &self.forms {
            if !f.visible.is_empty() && !visible(&f.visible) {
                continue;
            }
            let mat = if f.void { String::new() } else { material(&f.material) };
            let set = form_mesh(&f.form, solved, if mat.is_empty() { "Default" } else { &mat });
            if set.is_empty() {
                continue;
            }
            if f.void {
                let mut tags = Vec::new();
                voids.polys.extend(Solid::from_set(&set, &mut tags).polys);
            } else {
                solids.push((mat, set));
            }
        }
        let mut out = MeshSet::default();
        for (_, set) in solids {
            let cut = if voids.polys.is_empty() { set } else { csg::subtract_set(&set, &voids) };
            for (name, m) in cut.by_material {
                out.mesh(&name).append(&m);
            }
        }
        out
    }

    /// Plan symbolic lines in family coordinates.
    pub fn symbolic_lines(&self, solved: &Solved) -> Vec<(DVec2, DVec2)> {
        self.symbolic
            .iter()
            .map(|l| (pt2(l.a, Axis::X, Axis::Y, solved), pt2(l.b, Axis::X, Axis::Y, solved)))
            .collect()
    }
}

pub fn loc(l: Loc, solved: &Solved) -> f64 {
    match l {
        Loc::Value(v) => v,
        Loc::Plane(id) => solved.get(&id).copied().unwrap_or(0.0),
    }
}

fn pt2(p: SketchPt, _a: Axis, _b: Axis, solved: &Solved) -> DVec2 {
    DVec2::new(loc(p.a, solved), loc(p.b, solved))
}

/// Maps sketch coordinates (u, v, w = extrusion) to family XYZ for a sketch plane.
fn map(plane: SketchPlane, u: f64, v: f64, w: f64) -> DVec3 {
    match plane {
        SketchPlane::XY => DVec3::new(u, v, w),
        SketchPlane::XZ => DVec3::new(u, w, v),
        SketchPlane::YZ => DVec3::new(w, u, v),
    }
}

fn mirrored(plane: SketchPlane) -> bool {
    // XZ mapping (u, w, v) swaps two axes: a reflection.
    plane == SketchPlane::XZ
}

fn transformed(set: MeshSet, plane: SketchPlane) -> MeshSet {
    let mut out = MeshSet::default();
    for (name, m) in set.by_material {
        let mut t = Mesh::default();
        for tri in m.indices.chunks(3) {
            let p: Vec<DVec3> = tri.iter().map(|i| {
                let q = m.positions[*i as usize];
                map(plane, q.x, q.y, q.z)
            }).collect();
            if mirrored(plane) {
                t.add_triangle(p[0], p[2], p[1]);
            } else {
                t.add_triangle(p[0], p[1], p[2]);
            }
        }
        out.by_material.insert(name, t);
    }
    out
}

pub fn form_mesh(form: &Form, solved: &Solved, material: &str) -> MeshSet {
    let mut set = MeshSet::default();
    match form {
        Form::Extrusion { plane, profile, start, end } => {
            let pts: Vec<DVec2> = profile.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            let (z0, z1) = (loc(*start, solved), loc(*end, solved));
            let (z0, z1) = (z0.min(z1), z0.max(z1));
            if pts.len() < 3 || z1 - z0 < 1e-6 || geom::area(&pts) < 1e-6 {
                return set;
            }
            let mut local = MeshSet::default();
            local.add_extrusion(material, &pts, z0, z1);
            return transformed(local, *plane);
        }
        Form::Blend { bottom, top, start, end } => {
            let b: Vec<DVec2> = bottom.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            let t: Vec<DVec2> = top.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            let (z0, z1) = (loc(*start, solved), loc(*end, solved));
            if b.len() < 3 || t.len() < 3 || (z1 - z0).abs() < 1e-6 {
                return set;
            }
            let n = b.len().max(t.len());
            let b = geom::ensure_ccw(&resample(&b, n));
            let t = geom::ensure_ccw(&resample(&t, n));
            let m = set.mesh(material);
            m.add_polygon_facing(&b.iter().map(|p| geom::at(*p, z0)).collect::<Vec<_>>(), -DVec3::Z);
            m.add_polygon_facing(&t.iter().map(|p| geom::at(*p, z1)).collect::<Vec<_>>(), DVec3::Z);
            let c0 = geom::centroid(&b);
            for i in 0..n {
                let j = (i + 1) % n;
                let (a0, a1, b0, b1) = (geom::at(b[i], z0), geom::at(b[j], z0), geom::at(t[i], z1), geom::at(t[j], z1));
                let mid = (b[i] + b[j]) / 2.0 - c0;
                let out = DVec3::new(mid.x, mid.y, 0.0);
                m.add_quad_facing(a0, a1, b1, b0, out);
            }
        }
        Form::Revolve { profile, axis, angle_deg } => {
            let ax = DVec2::new(loc(axis.a, solved), loc(axis.b, solved));
            let prof: Vec<DVec2> = profile.iter().map(|p| DVec2::new((loc(p.a, solved) - ax.x).abs(), loc(p.b, solved))).collect();
            if prof.len() < 3 {
                return set;
            }
            let full = angle_deg.abs() >= 359.9;
            let ang = angle_deg.to_radians();
            let segs = ((angle_deg.abs() / 10.0).ceil() as usize).clamp(8, 72);
            let ring = |k: usize| -> Vec<DVec3> {
                let a = ang * k as f64 / segs as f64;
                prof.iter().map(|p| DVec3::new(ax.x + p.x * a.cos(), ax.y + p.x * a.sin(), p.y)).collect()
            };
            let m = set.mesh(material);
            let pc = geom::centroid(&prof);
            for k in 0..segs {
                let (r0, r1) = (ring(k), ring(k + 1));
                let amid = ang * (k as f64 + 0.5) / segs as f64;
                for i in 0..prof.len() {
                    let j = (i + 1) % prof.len();
                    let e = (prof[i] + prof[j]) / 2.0 - pc;
                    let out = DVec3::new(e.x * amid.cos(), e.x * amid.sin(), e.y);
                    m.add_quad_facing(r0[i], r0[j], r1[j], r1[i], out);
                }
            }
            if !full {
                let start: Vec<DVec3> = ring(0);
                let end: Vec<DVec3> = ring(segs);
                m.add_polygon_facing(&start, DVec3::new(0.0, -1.0, 0.0));
                m.add_polygon_facing(&end, DVec3::new(-ang.sin(), ang.cos(), 0.0));
            }
        }
        Form::Sweep { path, z, width, height } => {
            let pts: Vec<DVec2> = path.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            let z0 = loc(*z, solved);
            for w in pts.windows(2) {
                let d = (w[1] - w[0]).normalize_or_zero();
                if d == DVec2::ZERO {
                    continue;
                }
                let n = geom::perp(d) * (width / 2.0);
                let quad = [w[0] - n - d * (width / 2.0), w[1] - n + d * (width / 2.0), w[1] + n + d * (width / 2.0), w[0] + n - d * (width / 2.0)];
                set.add_extrusion(material, &quad, z0, z0 + height);
            }
        }
    }
    set
}

/// Resamples a closed polygon to `n` vertices by splitting its longest edges.
fn resample(pts: &[DVec2], n: usize) -> Vec<DVec2> {
    let mut v = pts.to_vec();
    while v.len() < n {
        let (k, _) = (0..v.len())
            .map(|i| (i, v[i].distance(v[(i + 1) % v.len()])))
            .max_by(|a, b| a.1.total_cmp(&b.1))
            .unwrap();
        let mid = (v[k] + v[(k + 1) % v.len()]) / 2.0;
        v.insert(k + 1, mid);
    }
    v
}

/// Least-squares solve of weighted rows (normal equations with Gaussian elimination).
fn least_squares(rows: &[(Vec<f64>, f64, f64)], n: usize) -> Option<Vec<f64>> {
    let mut a = vec![vec![0.0; n + 1]; n];
    for (c, rhs, w) in rows {
        for i in 0..n {
            if c[i] == 0.0 {
                continue;
            }
            for j in 0..n {
                a[i][j] += w * c[i] * c[j];
            }
            a[i][n] += w * c[i] * rhs;
        }
    }
    for col in 0..n {
        let piv = (col..n).max_by(|x, y| a[*x][col].abs().total_cmp(&a[*y][col].abs()))?;
        if a[piv][col].abs() < 1e-18 {
            return None;
        }
        a.swap(col, piv);
        for r in 0..n {
            if r != col {
                let f = a[r][col] / a[col][col];
                if f != 0.0 {
                    for k in col..=n {
                        a[r][k] -= f * a[col][k];
                    }
                }
            }
        }
    }
    Some((0..n).map(|i| a[i][n] / a[i][i]).collect())
}

/// Revit's Generic Model template: centre and level planes, Width/Depth/Height planes with EQ,
/// and one extrusion locked to them.
pub fn generic_template() -> FamilyDef {
    let plane = |id, name: &str, axis, default, fixed| RefPlaneDef { id, name: name.into(), axis, default, fixed };
    let p = |a, b| SketchPt { a: Loc::Plane(a), b: Loc::Plane(b) };
    FamilyDef {
        planes: vec![
            plane(1, "Center (Left/Right)", Axis::X, 0.0, true),
            plane(2, "Center (Front/Back)", Axis::Y, 0.0, true),
            plane(3, "Ref. Level", Axis::Z, 0.0, true),
            plane(4, "Left", Axis::X, -500.0, false),
            plane(5, "Right", Axis::X, 500.0, false),
            plane(6, "Front", Axis::Y, -500.0, false),
            plane(7, "Back", Axis::Y, 500.0, false),
            plane(8, "Top", Axis::Z, 1000.0, false),
        ],
        dims: vec![
            DimDef { planes: vec![4, 1, 5], label: String::new(), equal: true, locked: false },
            DimDef { planes: vec![4, 5], label: "Width".into(), equal: false, locked: false },
            DimDef { planes: vec![6, 2, 7], label: String::new(), equal: true, locked: false },
            DimDef { planes: vec![6, 7], label: "Depth".into(), equal: false, locked: false },
            DimDef { planes: vec![3, 8], label: "Height".into(), equal: false, locked: false },
        ],
        forms: vec![FormDef {
            name: "Extrusion 1".into(),
            form: Form::Extrusion { plane: SketchPlane::XY, profile: vec![p(4, 6), p(5, 6), p(5, 7), p(4, 7)], start: Loc::Plane(3), end: Loc::Plane(8) },
            void: false,
            material: "Material".into(),
            visible: String::new(),
        }],
        symbolic: vec![],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn solver_handles_eq_and_labels() {
        let def = generic_template();
        let s = def.solve(&|n| match n {
            "Width" => Some(1200.0),
            "Depth" => Some(600.0),
            "Height" => Some(750.0),
            _ => None,
        })
        .unwrap();
        assert!((s[&4] + 600.0).abs() < 1e-6 && (s[&5] - 600.0).abs() < 1e-6);
        assert!((s[&6] + 300.0).abs() < 1e-6 && (s[&7] - 300.0).abs() < 1e-6);
        assert!((s[&8] - 750.0).abs() < 1e-6);
        let mesh = def.build(&s, &|_| "Wood".into(), &|_| true);
        let (mn, mx) = mesh.bounds().unwrap();
        assert!((mx - mn - DVec3::new(1200.0, 600.0, 750.0)).length() < 1e-6);
    }

    #[test]
    fn voids_cut_solids_and_overconstraint_is_reported() {
        let mut def = generic_template();
        let p = |a: f64, b: f64| SketchPt { a: Loc::Value(a), b: Loc::Value(b) };
        def.forms.push(FormDef {
            name: "Hole".into(),
            form: Form::Extrusion { plane: SketchPlane::XY, profile: vec![p(-100.0, -100.0), p(100.0, -100.0), p(100.0, 100.0), p(-100.0, 100.0)], start: Loc::Value(-10.0), end: Loc::Value(2000.0) },
            void: true,
            material: String::new(),
            visible: String::new(),
        });
        let s = def.solve(&|n| match n {
            "Width" | "Depth" | "Height" => Some(1000.0),
            _ => None,
        })
        .unwrap();
        let mesh = def.build(&s, &|_| "M".into(), &|_| true);
        let mut tags = Vec::new();
        let v = Solid::from_set(&mesh, &mut tags).volume();
        assert!((v - (1e9 - 200.0 * 200.0 * 1000.0)).abs() < 1e3, "{v}");
        def.dims.push(DimDef { planes: vec![4, 5], label: "Depth".into(), equal: false, locked: false });
        assert!(def.solve(&|n| if n == "Depth" { Some(300.0) } else { Some(1000.0) }).is_err());
    }
}
