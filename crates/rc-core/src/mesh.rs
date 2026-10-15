//! Triangle meshes produced for 3D display and IFC export.

use crate::geom::{self, DVec2, DVec3};
use std::collections::BTreeMap;

/// Triangles sharing one material. Vertices are never shared between faces (flat shading).
#[derive(Clone, Debug, Default)]
pub struct Mesh {
    pub positions: Vec<DVec3>,
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn triangle_count(&self) -> usize {
        self.indices.len() / 3
    }

    pub fn add_triangle(&mut self, a: DVec3, b: DVec3, c: DVec3) {
        let i = self.positions.len() as u32;
        self.positions.extend([a, b, c]);
        self.indices.extend([i, i + 1, i + 2]);
    }

    /// Quad a-b-c-d, counter-clockwise when seen from the front.
    pub fn add_quad(&mut self, a: DVec3, b: DVec3, c: DVec3, d: DVec3) {
        let i = self.positions.len() as u32;
        self.positions.extend([a, b, c, d]);
        self.indices.extend([i, i + 1, i + 2, i, i + 2, i + 3]);
    }

    /// Adds a quad whose front face points along `normal`, whatever the input winding.
    pub fn add_quad_facing(&mut self, a: DVec3, b: DVec3, c: DVec3, d: DVec3, normal: DVec3) {
        let mut n = (b - a).cross(c - a);
        if n.length() < 1e-9 {
            n = (c - a).cross(d - a);
        }
        if n.length() < 1e-9 {
            return;
        }
        if n.dot(normal) >= 0.0 {
            self.add_quad(a, b, c, d)
        } else {
            self.add_quad(d, c, b, a)
        }
    }

    /// Adds a planar polygon whose front face points along `normal`.
    pub fn add_polygon_facing(&mut self, pts: &[DVec3], normal: DVec3) {
        if pts.len() < 3 {
            return;
        }
        let poly_n = newell_normal(pts);
        if poly_n.length() < 1e-9 {
            return;
        }
        let n = poly_n.normalize();
        // Planar frame (u, v) with u × v = n so polygon winding is preserved.
        let helper = if n.z.abs() < 0.9 { DVec3::Z } else { DVec3::X };
        let u = helper.cross(n).normalize();
        let v = n.cross(u);
        let o = pts[0];
        let flat: Vec<DVec2> = pts.iter().map(|p| DVec2::new((*p - o).dot(u), (*p - o).dot(v))).collect();
        let flip = poly_n.dot(normal) < 0.0;
        for [a, b, c] in geom::triangulate(&flat) {
            if flip {
                self.add_triangle(pts[a], pts[c], pts[b]);
            } else {
                self.add_triangle(pts[a], pts[b], pts[c]);
            }
        }
    }

    pub fn append(&mut self, other: &Mesh) {
        let off = self.positions.len() as u32;
        self.positions.extend_from_slice(&other.positions);
        self.indices.extend(other.indices.iter().map(|i| i + off));
    }

    pub fn bounds(&self) -> Option<(DVec3, DVec3)> {
        let first = *self.positions.first()?;
        Some(self.positions.iter().fold((first, first), |(mn, mx), p| (mn.min(*p), mx.max(*p))))
    }
}

fn newell_normal(pts: &[DVec3]) -> DVec3 {
    let n = pts.len();
    let mut r = DVec3::ZERO;
    for i in 0..n {
        let p = pts[i];
        let q = pts[(i + 1) % n];
        r.x += (p.y - q.y) * (p.z + q.z);
        r.y += (p.z - q.z) * (p.x + q.x);
        r.z += (p.x - q.x) * (p.y + q.y);
    }
    r
}

/// Meshes of one element grouped by material name.
#[derive(Clone, Debug, Default)]
pub struct MeshSet {
    pub by_material: BTreeMap<String, Mesh>,
}

impl MeshSet {
    pub fn mesh(&mut self, material: &str) -> &mut Mesh {
        self.by_material.entry(material.to_string()).or_default()
    }

    /// The set without faces buried inside the element: back-to-back faces where two layers
    /// of a compound wall meet (coplanar, opposite normals). Hidden-line drawings use the
    /// outer surface only; section cuts use the full set, so every layer cuts as a region.
    pub fn without_internal_faces(&self) -> MeshSet {
        let key = |n: DVec3, p: DVec3| -> (i64, i64, i64, i64) { ((n.x * 1000.0).round() as i64, (n.y * 1000.0).round() as i64, (n.z * 1000.0).round() as i64, (n.dot(p) * 2.0).round() as i64) };
        let plane = |m: &Mesh, t: &[u32]| -> Option<(DVec3, DVec3)> {
            let (a, b, c) = (m.positions[t[0] as usize], m.positions[t[1] as usize], m.positions[t[2] as usize]);
            let n = (b - a).cross(c - a);
            (n.length() > 1e-9).then(|| (n.normalize(), a))
        };
        let mut planes = std::collections::HashSet::new();
        for m in self.by_material.values() {
            for t in m.indices.chunks(3) {
                if let Some((n, a)) = plane(m, t) {
                    planes.insert(key(n, a));
                }
            }
        }
        let mut out = MeshSet::default();
        for (name, m) in &self.by_material {
            let mut keep = Mesh { positions: m.positions.clone(), indices: Vec::with_capacity(m.indices.len()) };
            for t in m.indices.chunks(3) {
                let internal = plane(m, t).is_some_and(|(n, a)| planes.contains(&key(-n, a)));
                if !internal {
                    keep.indices.extend_from_slice(t);
                }
            }
            if !keep.indices.is_empty() {
                out.by_material.insert(name.clone(), keep);
            }
        }
        out
    }

    pub fn is_empty(&self) -> bool {
        self.by_material.values().all(|m| m.indices.is_empty())
    }

    /// Oriented box from a corner and three edge vectors; mirrored frames are handled.
    pub fn add_box(&mut self, material: &str, origin: DVec3, u: DVec3, v: DVec3, w: DVec3) {
        let (mut origin, mut v) = (origin, v);
        if u.cross(v).dot(w) < 0.0 {
            origin += v;
            v = -v;
        }
        let m = self.mesh(material);
        let p000 = origin;
        let p100 = origin + u;
        let p010 = origin + v;
        let p110 = origin + u + v;
        let p001 = origin + w;
        let p101 = origin + u + w;
        let p011 = origin + v + w;
        let p111 = origin + u + v + w;
        m.add_quad(p000, p010, p110, p100);
        m.add_quad(p001, p101, p111, p011);
        m.add_quad(p000, p100, p101, p001);
        m.add_quad(p010, p011, p111, p110);
        m.add_quad(p000, p001, p011, p010);
        m.add_quad(p100, p110, p111, p101);
    }

    /// Extrudes a plan polygon between two elevations.
    pub fn add_extrusion(&mut self, material: &str, profile: &[DVec2], z0: f64, z1: f64) {
        let pts = geom::ensure_ccw(profile);
        if pts.len() < 3 || z1 <= z0 {
            return;
        }
        let m = self.mesh(material);
        let top: Vec<DVec3> = pts.iter().map(|p| geom::at(*p, z1)).collect();
        m.add_polygon_facing(&top, DVec3::Z);
        let bottom: Vec<DVec3> = pts.iter().map(|p| geom::at(*p, z0)).collect();
        m.add_polygon_facing(&bottom, -DVec3::Z);
        let n = pts.len();
        for i in 0..n {
            let a = pts[i];
            let b = pts[(i + 1) % n];
            m.add_quad(geom::at(a, z0), geom::at(b, z0), geom::at(b, z1), geom::at(a, z1));
        }
    }

    /// Extrudes a polygon with holes between two elevations.
    pub fn add_extrusion_with_holes(&mut self, material: &str, outer: &[DVec2], holes: &[Vec<DVec2>], z0: f64, z1: f64) {
        if holes.is_empty() {
            self.add_extrusion(material, outer, z0, z1);
            return;
        }
        use geo::{Coord, LineString, Polygon, TriangulateEarcut};
        let outer = geom::ensure_ccw(outer);
        if outer.len() < 3 || z1 <= z0 {
            return;
        }
        let ring = |pts: &[DVec2]| LineString::from(pts.iter().map(|p| Coord { x: p.x, y: p.y }).collect::<Vec<_>>());
        let holes_cw: Vec<Vec<DVec2>> = holes
            .iter()
            .filter(|h| h.len() >= 3)
            .map(|h| {
                let mut v = geom::ensure_ccw(h);
                v.reverse();
                v
            })
            .collect();
        let poly = Polygon::new(ring(&outer), holes_cw.iter().map(|h| ring(h)).collect());
        let m = self.mesh(material);
        for t in poly.earcut_triangles() {
            let [a, b, c] = t.to_array();
            let (a, b, c) = (DVec2::new(a.x, a.y), DVec2::new(b.x, b.y), DVec2::new(c.x, c.y));
            let (a, b, c) = if geom::cross2(b - a, c - a) < 0.0 { (a, c, b) } else { (a, b, c) };
            m.add_triangle(geom::at(a, z1), geom::at(b, z1), geom::at(c, z1));
            m.add_triangle(geom::at(a, z0), geom::at(c, z0), geom::at(b, z0));
        }
        // Side walls: outer ring CCW faces out; hole rings CW face into the hole (also "out" of the solid).
        for r in std::iter::once(&outer).chain(holes_cw.iter()) {
            let n = r.len();
            for i in 0..n {
                let (a, b) = (r[i], r[(i + 1) % n]);
                m.add_quad(geom::at(a, z0), geom::at(b, z0), geom::at(b, z1), geom::at(a, z1));
            }
        }
    }

    /// Adds every mesh of another set.
    pub fn merge(&mut self, other: MeshSet) {
        for (name, m) in other.by_material {
            self.mesh(&name).append(&m);
        }
    }

    pub fn bounds(&self) -> Option<(DVec3, DVec3)> {
        self.by_material
            .values()
            .filter_map(|m| m.bounds())
            .reduce(|(a0, a1), (b0, b1)| (a0.min(b0), a1.max(b1)))
    }
}
