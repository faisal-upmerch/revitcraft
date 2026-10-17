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
    /// A profile swept along a plan path at height `z`. The profile is sketched in the plane
    /// across the path's first segment: x runs along the path's left normal from the path,
    /// y up from `z`. Without a profile, a `width` x `height` rectangle centred on the path.
    Sweep {
        path: Vec<SketchPt>,
        z: Loc,
        width: f64,
        height: f64,
        #[serde(default)]
        profile: Vec<DVec2>,
    },
    /// A single plan path segment at height `z` with a profile at each end (x along the
    /// path's left normal, y up from `z`), lofted from the first to the second.
    SweptBlend { path: Vec<SketchPt>, z: Loc, profile1: Vec<DVec2>, profile2: Vec<DVec2> },
}

impl Form {
    pub fn kind_label(&self) -> &'static str {
        match self {
            Form::Extrusion { .. } => "Extrusion",
            Form::Blend { .. } => "Blend",
            Form::Revolve { .. } => "Revolve",
            Form::Sweep { .. } => "Sweep",
            Form::SweptBlend { .. } => "Swept Blend",
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

/// A model line or reference line drawn on a work plane (shown in every view).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FamLine {
    pub plane: SketchPlane,
    pub a: SketchPt,
    pub b: SketchPt,
    /// A reference line (green, never shown in projects) rather than a model line.
    #[serde(default)]
    pub reference: bool,
}

impl FamLine {
    /// The line's ends in family coordinates (on the plane through the origin).
    pub fn ends(&self, solved: &Solved) -> (DVec3, DVec3) {
        let at = |p: SketchPt| {
            let (u, v) = (loc(p.a, solved), loc(p.b, solved));
            match self.plane {
                SketchPlane::XY => DVec3::new(u, v, 0.0),
                SketchPlane::XZ => DVec3::new(u, 0.0, v),
                SketchPlane::YZ => DVec3::new(0.0, u, v),
            }
        };
        (at(self.a), at(self.b))
    }
}

/// Create > Control: a flip arrow shown on instances in projects (plan).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ControlKind {
    SingleVertical,
    DoubleVertical,
    SingleHorizontal,
    DoubleHorizontal,
}

impl ControlKind {
    pub const ALL: [ControlKind; 4] = [ControlKind::SingleVertical, ControlKind::DoubleVertical, ControlKind::SingleHorizontal, ControlKind::DoubleHorizontal];
    pub fn label(self) -> &'static str {
        match self {
            ControlKind::SingleVertical => "Single Vertical",
            ControlKind::DoubleVertical => "Double Vertical",
            ControlKind::SingleHorizontal => "Single Horizontal",
            ControlKind::DoubleHorizontal => "Double Horizontal",
        }
    }
    /// Horizontal controls flip the hand (mirror across the family's y axis); vertical ones
    /// flip the facing.
    pub fn horizontal(self) -> bool {
        matches!(self, ControlKind::SingleHorizontal | ControlKind::DoubleHorizontal)
    }
    pub fn double(self) -> bool {
        matches!(self, ControlKind::DoubleVertical | ControlKind::DoubleHorizontal)
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ControlDef {
    pub at: SketchPt,
    pub kind: ControlKind,
}

/// Create > Model Text: glyphs on a sketch plane, extruded `depth` from `offset`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ModelTextDef {
    pub text: String,
    pub plane: SketchPlane,
    pub at: SketchPt,
    #[serde(default)]
    pub offset: f64,
    pub size: f64,
    pub depth: f64,
    #[serde(default)]
    pub material: String,
}

/// Create > Component: a family loaded into this one (`FamilyDef::loaded`), placed in plan.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct NestedDef {
    pub family: String,
    pub type_name: String,
    pub at: SketchPt,
    #[serde(default)]
    pub z: f64,
    #[serde(default)]
    pub rotation_deg: f64,
}

/// Annotate > Filled Region / Masking Region in plan: shown with the family's plan symbol.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FamRegion {
    pub pts: Vec<SketchPt>,
    #[serde(default)]
    pub masking: bool,
}

/// Annotate > Text: notes seen only in the family editor's views (0 plan, 1 front, 2 right).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FamNote {
    pub view: u8,
    pub at: SketchPt,
    pub text: String,
    #[serde(default = "note_size")]
    pub size: f64,
}

fn note_size() -> f64 {
    2.5
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct FamilyDef {
    pub planes: Vec<RefPlaneDef>,
    pub dims: Vec<DimDef>,
    pub forms: Vec<FormDef>,
    /// Plan-only symbolic lines (XY).
    #[serde(default)]
    pub symbolic: Vec<SymLine>,
    /// Model and reference lines.
    #[serde(default)]
    pub lines: Vec<FamLine>,
    #[serde(default)]
    pub controls: Vec<ControlDef>,
    #[serde(default)]
    pub texts: Vec<ModelTextDef>,
    /// Families loaded into this family (Insert > Load Family) and their placed instances.
    #[serde(default)]
    pub loaded: Vec<crate::model::Family>,
    #[serde(default)]
    pub nested: Vec<NestedDef>,
    #[serde(default)]
    pub regions: Vec<FamRegion>,
    #[serde(default)]
    pub notes: Vec<FamNote>,
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
        // Model text and nested components.
        for t in &self.texts {
            let mat = material(&t.material);
            let set = text_mesh(t, solved, if mat.is_empty() { "Default" } else { &mat });
            if !set.is_empty() {
                solids.push((mat, set));
            }
        }
        for n in &self.nested {
            let set = self.nested_mesh(n, solved);
            if !set.is_empty() {
                solids.push((String::new(), set));
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

    /// A nested component's family and type.
    pub fn nested_type(&self, n: &NestedDef) -> Option<(&crate::model::Family, &crate::model::FamilyType)> {
        let f = self.loaded.iter().find(|f| f.name == n.family)?;
        let t = f.types.iter().find(|t| t.name == n.type_name).or(f.types.first())?;
        Some((f, t))
    }

    /// Placement of a nested component: family point (x, y, z) of its local point.
    fn nested_place(n: &NestedDef, solved: &Solved) -> impl Fn(DVec3) -> DVec3 {
        let o = DVec3::new(loc(n.at.a, solved), loc(n.at.b, solved), n.z);
        let (c, s) = (n.rotation_deg.to_radians().cos(), n.rotation_deg.to_radians().sin());
        move |q: DVec3| o + DVec3::new(q.x * c - q.y * s, q.x * s + q.y * c, q.z)
    }

    /// A nested component's geometry in family coordinates.
    pub fn nested_mesh(&self, n: &NestedDef, solved: &Solved) -> MeshSet {
        let mut out = MeshSet::default();
        let Some((f, t)) = self.nested_type(n) else { return out };
        let place = Self::nested_place(n, solved);
        for (name, m) in crate::build3d::family_type_preview(f, t).by_material {
            let target = out.mesh(&name);
            for tri in m.indices.chunks(3) {
                let q: Vec<DVec3> = tri.iter().map(|k| place(m.positions[*k as usize])).collect();
                target.add_triangle(q[0], q[1], q[2]);
            }
        }
        out
    }

    /// Plan graphics of nested components, filled/masking regions and flat model text:
    /// (points, closed, fill).
    pub fn plan_extras(&self, solved: &Solved) -> Vec<(Vec<DVec2>, bool, Option<[u8; 3]>)> {
        let mut out = Vec::new();
        for n in &self.nested {
            let Some((f, t)) = self.nested_type(n) else { continue };
            let place = Self::nested_place(n, solved);
            for l in crate::family_geom::family_type_symbol(f, t) {
                out.push((l.pts.iter().map(|q| place(DVec3::new(q.x, q.y, 0.0)).truncate()).collect(), l.closed, l.fill));
            }
        }
        for r in &self.regions {
            let pts: Vec<DVec2> = r.pts.iter().map(|q| DVec2::new(loc(q.a, solved), loc(q.b, solved))).collect();
            if pts.len() >= 3 {
                out.push((pts, true, Some(if r.masking { [255, 255, 255] } else { [0, 0, 0] })));
            }
        }
        for t in self.texts.iter().filter(|t| t.plane == SketchPlane::XY) {
            let o = DVec2::new(loc(t.at.a, solved), loc(t.at.b, solved));
            for c in crate::model_text::text_contours(&t.text, t.size, 0) {
                out.push((c.into_iter().map(|q| o + q).collect(), true, None));
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

/// Model text glyphs extruded from their sketch plane.
fn text_mesh(t: &ModelTextDef, solved: &Solved, material: &str) -> MeshSet {
    let mut set = MeshSet::default();
    let o = DVec2::new(loc(t.at.a, solved), loc(t.at.b, solved));
    for (outer, holes) in crate::model_text::shapes(&crate::model_text::text_contours(&t.text, t.size, 0)) {
        let mut local = MeshSet::default();
        let outer: Vec<DVec2> = outer.into_iter().map(|q| o + q).collect();
        let holes: Vec<Vec<DVec2>> = holes.into_iter().map(|h| h.into_iter().map(|q| o + q).collect()).collect();
        local.add_extrusion_with_holes(material, &outer, &holes, t.offset, t.offset + t.depth.max(0.1));
        for (name, m) in local.by_material {
            let target = set.mesh(&name);
            for tri in m.indices.chunks(3) {
                let q: Vec<DVec3> = tri.iter().map(|k| {
                    let v = m.positions[*k as usize];
                    map(t.plane, v.x, v.y, v.z)
                }).collect();
                if mirrored(t.plane) {
                    target.add_triangle(q[0], q[2], q[1]);
                } else {
                    target.add_triangle(q[0], q[1], q[2]);
                }
            }
        }
    }
    set
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
        Form::SweptBlend { path, z, profile1, profile2 } => {
            let pts: Vec<DVec2> = path.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            if pts.len() < 2 || profile1.len() < 3 || profile2.len() < 3 || pts[0].distance(pts[1]) < 1e-6 {
                return set;
            }
            let z0 = loc(*z, solved);
            let (a, b) = (pts[0], pts[1]);
            let d = (b - a).normalize();
            let nrm = geom::perp(d);
            let n = profile1.len().max(profile2.len());
            let p1 = geom::ensure_ccw(&resample(profile1, n));
            let p2 = geom::ensure_ccw(&resample(profile2, n));
            let at = |o: DVec2, q: DVec2| { let w = o + nrm * q.x; DVec3::new(w.x, w.y, z0 + q.y) };
            let r0: Vec<DVec3> = p1.iter().map(|q| at(a, *q)).collect();
            let r1: Vec<DVec3> = p2.iter().map(|q| at(b, *q)).collect();
            let m = set.mesh(material);
            let c1 = geom::centroid(&p1);
            for i in 0..n {
                let j = (i + 1) % n;
                let e = (p1[i] + p1[j]) / 2.0 - c1;
                m.add_quad_facing(r0[i], r0[j], r1[j], r1[i], DVec3::new(nrm.x * e.x, nrm.y * e.x, e.y));
            }
            m.add_polygon_facing(&r0, DVec3::new(-d.x, -d.y, 0.0));
            m.add_polygon_facing(&r1, DVec3::new(d.x, d.y, 0.0));
        }
        Form::Sweep { path, z, width, height, profile } => {
            let pts: Vec<DVec2> = path.iter().map(|p| DVec2::new(loc(p.a, solved), loc(p.b, solved))).collect();
            let z0 = loc(*z, solved);
            if profile.len() >= 3 {
                sweep_profile(set.mesh(material), &pts, z0, profile);
                return set;
            }
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

/// Sweeps a closed profile (x along the left normal, y up) along a polyline path at `z0`,
/// mitring the corners and capping both ends.
fn sweep_profile(m: &mut crate::mesh::Mesh, path: &[DVec2], z0: f64, profile: &[DVec2]) {
    let mut pts: Vec<DVec2> = Vec::new();
    for q in path {
        if pts.last().is_none_or(|l: &DVec2| l.distance(*q) > 1e-6) {
            pts.push(*q);
        }
    }
    if pts.len() < 2 {
        return;
    }
    let closed = pts.len() > 3 && pts[0].distance(pts[pts.len() - 1]) < 1e-6;
    if closed {
        pts.pop();
    }
    let n = pts.len();
    let seg = |i: usize| (pts[(i + 1) % n] - pts[i]).normalize();
    // Mitre direction and scale at each station.
    let station = |i: usize| -> (DVec2, f64) {
        let (din, dout) = if closed {
            (seg((i + n - 1) % n), seg(i))
        } else if i == 0 {
            (seg(0), seg(0))
        } else if i == n - 1 {
            (seg(n - 2), seg(n - 2))
        } else {
            (seg(i - 1), seg(i))
        };
        let (nin, nout) = (geom::perp(din), geom::perp(dout));
        let bis = (nin + nout).normalize_or_zero();
        if bis == DVec2::ZERO {
            return (nout, 1.0);
        }
        (bis, 1.0 / bis.dot(nout).max(0.2))
    };
    let ring = |i: usize| -> Vec<DVec3> {
        let (nrm, k) = station(i);
        profile.iter().map(|p| { let q = pts[i] + nrm * (p.x * k); DVec3::new(q.x, q.y, z0 + p.y) }).collect()
    };
    let rings: Vec<Vec<DVec3>> = (0..n).map(ring).collect();
    let pc = geom::centroid(profile);
    let count = if closed { n } else { n - 1 };
    for i in 0..count {
        let (r0, r1) = (&rings[i], &rings[(i + 1) % n]);
        let nrm = geom::perp(seg(i));
        for a in 0..profile.len() {
            let b = (a + 1) % profile.len();
            let e = (profile[a] + profile[b]) / 2.0 - pc;
            let out = DVec3::new(nrm.x * e.x, nrm.y * e.x, e.y);
            m.add_quad_facing(r0[a], r0[b], r1[b], r1[a], out);
        }
    }
    if !closed {
        let d0 = seg(0);
        let d1 = seg(n - 2);
        m.add_polygon_facing(&rings[0], DVec3::new(-d0.x, -d0.y, 0.0));
        m.add_polygon_facing(&rings[n - 1], DVec3::new(d1.x, d1.y, 0.0));
    }
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
/// The reference app's Generic Model template: only the origin planes (the two centre planes
/// and the reference level), no forms, dimensions or parameters.
pub fn empty_template() -> FamilyDef {
    let plane = |id, name: &str, axis, default, fixed| RefPlaneDef { id, name: name.into(), axis, default, fixed };
    FamilyDef {
        planes: vec![plane(1, "Center (Left/Right)", Axis::X, 0.0, true), plane(2, "Center (Front/Back)", Axis::Y, 0.0, true), plane(3, "Ref. Level", Axis::Z, 0.0, true)],
        dims: vec![],
        forms: vec![],
        symbolic: vec![],
        lines: vec![],
        ..Default::default()
    }
}

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
        lines: vec![],
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_sweep_follows_the_path_with_mitred_corners() {
        let mut def = FamilyDef::default();
        let p = |a: f64, b: f64| SketchPt { a: Loc::Value(a), b: Loc::Value(b) };
        // An L path with a 100 x 50 profile left of the path, starting 20 above the path.
        let profile = vec![DVec2::new(0.0, 20.0), DVec2::new(100.0, 20.0), DVec2::new(100.0, 70.0), DVec2::new(0.0, 70.0)];
        def.forms.push(FormDef { name: "S".into(), form: Form::Sweep { path: vec![p(0.0, 0.0), p(1000.0, 0.0), p(1000.0, 1000.0)], z: Loc::Value(0.0), width: 50.0, height: 50.0, profile }, void: false, material: String::new(), visible: String::new() });
        let mesh = def.build(&Solved::new(), &|_| "Wood".into(), &|_| true);
        let (mn, mx) = mesh.bounds().unwrap();
        // Left of an eastward path is +y; the mitred corner reaches x = 1000 - 100.
        assert!((mn - DVec3::new(0.0, 0.0, 20.0)).length() < 1e-6, "{mn:?}");
        assert!((mx - DVec3::new(1000.0, 1000.0, 70.0)).length() < 1e-6, "{mx:?}");
        let tris = mesh.by_material.values().map(|m| m.indices.len() / 3).sum::<usize>();
        // 2 segments x 4 sides x 2 triangles + 2 caps x 2 triangles.
        assert_eq!(tris, 20);
    }

    #[test]
    fn swept_blend_lofts_between_its_end_profiles() {
        let mut def = FamilyDef::default();
        let p = |a: f64, b: f64| SketchPt { a: Loc::Value(a), b: Loc::Value(b) };
        let sq = |s: f64| vec![DVec2::new(0.0, 0.0), DVec2::new(s, 0.0), DVec2::new(s, s), DVec2::new(0.0, s)];
        def.forms.push(FormDef { name: "SB".into(), form: Form::SweptBlend { path: vec![p(0.0, 0.0), p(1000.0, 0.0)], z: Loc::Value(0.0), profile1: sq(200.0), profile2: sq(100.0) }, void: false, material: String::new(), visible: String::new() });
        let mesh = def.build(&Solved::new(), &|_| "Wood".into(), &|_| true);
        let (mn, mx) = mesh.bounds().unwrap();
        assert!((mn - DVec3::ZERO).length() < 1e-6 && (mx - DVec3::new(1000.0, 200.0, 200.0)).length() < 1e-6, "{mn:?} {mx:?}");
        // The far end is the small profile.
        let far: Vec<DVec3> = mesh.by_material.values().flat_map(|m| m.positions.iter().copied()).filter(|q| (q.x - 1000.0).abs() < 1e-6).collect();
        assert!(far.iter().all(|q| q.y <= 100.0 + 1e-6 && q.z <= 100.0 + 1e-6));
    }

    #[test]
    fn nested_components_text_and_flip_controls() {
        let mut p = crate::defaults::new_project(crate::units::UnitSystem::Metric);
        let chair = p.families.iter().find(|f| f.template == crate::model::FamilyTemplate::Chair).unwrap().clone();
        let mut def = empty_template();
        def.loaded.push(chair.clone());
        def.nested.push(NestedDef { family: chair.name.clone(), type_name: chair.types[0].name.clone(), at: SketchPt { a: Loc::Value(1000.0), b: Loc::Value(0.0) }, z: 0.0, rotation_deg: 90.0 });
        def.texts.push(ModelTextDef { text: "A".into(), plane: SketchPlane::XZ, at: SketchPt { a: Loc::Value(-500.0), b: Loc::Value(0.0) }, offset: 0.0, size: 300.0, depth: 50.0, material: String::new() });
        def.controls.push(ControlDef { at: SketchPt { a: Loc::Value(0.0), b: Loc::Value(-300.0) }, kind: ControlKind::SingleHorizontal });
        def.regions.push(FamRegion { pts: vec![SketchPt { a: Loc::Value(0.0), b: Loc::Value(0.0) }, SketchPt { a: Loc::Value(100.0), b: Loc::Value(0.0) }, SketchPt { a: Loc::Value(100.0), b: Loc::Value(100.0) }], masking: false });
        let solved = def.solve(&|_| None).unwrap();
        let set = def.build(&solved, &|m| m.to_string(), &|_| true);
        let (mn, mx) = set.bounds().unwrap();
        // The chair sits around x = 1000; the text stands in the front plane at x = -500.
        assert!(mx.x > 1100.0 && mn.x < -400.0, "{mn:?} {mx:?}");
        let extras = def.plan_extras(&solved);
        assert!(extras.iter().any(|(_, _, f)| *f == Some([0, 0, 0])));
        assert!(extras.iter().any(|(pts, _, _)| pts.iter().any(|q| q.x > 700.0)));
        // An instance flipped by the control mirrors across its y axis.
        let mut fam = crate::model::Family { name: "Flip".into(), category: crate::model::Category::GenericModels, template: crate::model::FamilyTemplate::Custom, definition: Some(def), ..Default::default() };
        fam.types.push(crate::model::FamilyType { id: 0, name: "Flip".into(), values: Default::default() });
        let fid = crate::edit::load_family(&mut p, fam);
        let ty = p.family(fid).unwrap().types[0].id;
        let level = p.levels()[0].0;
        let mut inst = crate::model::FamilyInstance { family_id: fid, type_id: ty, category: crate::model::Category::GenericModels, level, ..Default::default() };
        let (_, a) = crate::family_geom::instance_mesh(&p, &inst).bounds().unwrap();
        inst.flip_hand = true;
        let (b, _) = crate::family_geom::instance_mesh(&p, &inst).bounds().unwrap();
        assert!((a.x + b.x).abs() < 1.0, "{a:?} {b:?}");
    }

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
