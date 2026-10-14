//! Constructive solid geometry on triangle meshes using BSP trees (after Evan Wallace's csg.js).
//! Used for void forms in families, shafts cutting slabs, and walls trimmed under roofs.

use crate::geom::DVec3;
use crate::mesh::{Mesh, MeshSet};

const EPS: f64 = 1e-3; // millimetres

#[derive(Clone, Copy, Debug)]
struct Plane {
    n: DVec3,
    w: f64,
}

impl Plane {
    fn from_points(a: DVec3, b: DVec3, c: DVec3) -> Option<Plane> {
        let n = (b - a).cross(c - a);
        let len = n.length();
        if len < 1e-9 {
            return None;
        }
        let n = n / len;
        Some(Plane { n, w: n.dot(a) })
    }
    fn flip(&mut self) {
        self.n = -self.n;
        self.w = -self.w;
    }
}

#[derive(Clone, Debug)]
pub struct Polygon {
    pub verts: Vec<DVec3>,
    plane: Plane,
    /// Material index.
    pub tag: u32,
}

impl Polygon {
    fn new(verts: Vec<DVec3>, tag: u32) -> Option<Polygon> {
        // Find a non-degenerate triple for the plane.
        for i in 0..verts.len().saturating_sub(2) {
            if let Some(plane) = Plane::from_points(verts[0], verts[i + 1], verts[i + 2]) {
                return Some(Polygon { verts, plane, tag });
            }
        }
        None
    }
    fn flip(&mut self) {
        self.verts.reverse();
        self.plane.flip();
    }
}

const COPLANAR: u8 = 0;
const FRONT: u8 = 1;
const BACK: u8 = 2;
const SPANNING: u8 = 3;

fn split(
    plane: &Plane,
    poly: Polygon,
    co_front: &mut Vec<Polygon>,
    co_back: &mut Vec<Polygon>,
    front: &mut Vec<Polygon>,
    back: &mut Vec<Polygon>,
) {
    let mut ptype = 0u8;
    let types: Vec<u8> = poly
        .verts
        .iter()
        .map(|v| {
            let t = plane.n.dot(*v) - plane.w;
            let ty = if t < -EPS { BACK } else if t > EPS { FRONT } else { COPLANAR };
            ptype |= ty;
            ty
        })
        .collect();
    match ptype {
        COPLANAR => {
            if plane.n.dot(poly.plane.n) > 0.0 {
                co_front.push(poly)
            } else {
                co_back.push(poly)
            }
        }
        FRONT => front.push(poly),
        BACK => back.push(poly),
        _ => {
            let mut f = Vec::new();
            let mut b = Vec::new();
            let n = poly.verts.len();
            for i in 0..n {
                let j = (i + 1) % n;
                let (ti, tj) = (types[i], types[j]);
                let (vi, vj) = (poly.verts[i], poly.verts[j]);
                if ti != BACK {
                    f.push(vi);
                }
                if ti != FRONT {
                    b.push(vi);
                }
                if (ti | tj) == SPANNING {
                    let t = (plane.w - plane.n.dot(vi)) / plane.n.dot(vj - vi);
                    let v = vi.lerp(vj, t);
                    f.push(v);
                    b.push(v);
                }
            }
            if f.len() >= 3 {
                if let Some(p) = Polygon::new(f, poly.tag) {
                    front.push(p);
                }
            }
            if b.len() >= 3 {
                if let Some(p) = Polygon::new(b, poly.tag) {
                    back.push(p);
                }
            }
        }
    }
}

#[derive(Default)]
struct Node {
    plane: Option<Plane>,
    front: Option<Box<Node>>,
    back: Option<Box<Node>>,
    polys: Vec<Polygon>,
}

impl Node {
    fn new(polys: Vec<Polygon>) -> Node {
        let mut n = Node::default();
        n.build(polys);
        n
    }

    fn invert(&mut self) {
        for p in &mut self.polys {
            p.flip();
        }
        if let Some(pl) = &mut self.plane {
            pl.flip();
        }
        if let Some(f) = &mut self.front {
            f.invert();
        }
        if let Some(b) = &mut self.back {
            b.invert();
        }
        std::mem::swap(&mut self.front, &mut self.back);
    }

    fn clip_polygons(&self, polys: Vec<Polygon>) -> Vec<Polygon> {
        let Some(plane) = &self.plane else { return polys };
        let mut front = Vec::new();
        let mut back = Vec::new();
        for p in polys {
            let (mut cf, mut cb) = (Vec::new(), Vec::new());
            split(plane, p, &mut cf, &mut cb, &mut front, &mut back);
            front.extend(cf);
            back.extend(cb);
        }
        let mut front = match &self.front {
            Some(f) => f.clip_polygons(front),
            None => front,
        };
        let back = match &self.back {
            Some(b) => b.clip_polygons(back),
            None => Vec::new(),
        };
        front.extend(back);
        front
    }

    fn clip_to(&mut self, other: &Node) {
        self.polys = other.clip_polygons(std::mem::take(&mut self.polys));
        if let Some(f) = &mut self.front {
            f.clip_to(other);
        }
        if let Some(b) = &mut self.back {
            b.clip_to(other);
        }
    }

    fn all_polygons(&self) -> Vec<Polygon> {
        let mut out = self.polys.clone();
        if let Some(f) = &self.front {
            out.extend(f.all_polygons());
        }
        if let Some(b) = &self.back {
            out.extend(b.all_polygons());
        }
        out
    }

    fn build(&mut self, polys: Vec<Polygon>) {
        if polys.is_empty() {
            return;
        }
        let plane = *self.plane.get_or_insert(polys[0].plane);
        let mut front = Vec::new();
        let mut back = Vec::new();
        let (mut cf, mut cb) = (Vec::new(), Vec::new());
        for p in polys {
            split(&plane, p, &mut cf, &mut cb, &mut front, &mut back);
        }
        self.polys.extend(cf);
        self.polys.extend(cb);
        if !front.is_empty() {
            self.front.get_or_insert_with(Default::default).build(front);
        }
        if !back.is_empty() {
            self.back.get_or_insert_with(Default::default).build(back);
        }
    }
}

/// A solid as a polygon soup.
#[derive(Clone, Debug, Default)]
pub struct Solid {
    pub polys: Vec<Polygon>,
}

impl Solid {
    pub fn from_mesh(mesh: &Mesh, tag: u32) -> Solid {
        let polys = mesh
            .indices
            .chunks(3)
            .filter_map(|t| Polygon::new(vec![mesh.positions[t[0] as usize], mesh.positions[t[1] as usize], mesh.positions[t[2] as usize]], tag))
            .collect();
        Solid { polys }
    }

    /// All meshes of a set as one solid; `tags` receives the material names by tag index.
    pub fn from_set(set: &MeshSet, tags: &mut Vec<String>) -> Solid {
        let mut s = Solid::default();
        for (name, mesh) in &set.by_material {
            let tag = match tags.iter().position(|t| t == name) {
                Some(i) => i as u32,
                None => {
                    tags.push(name.clone());
                    (tags.len() - 1) as u32
                }
            };
            s.polys.extend(Solid::from_mesh(mesh, tag).polys);
        }
        s
    }

    pub fn to_set(&self, tags: &[String]) -> MeshSet {
        let mut set = MeshSet::default();
        for p in &self.polys {
            let name = tags.get(p.tag as usize).map(String::as_str).unwrap_or("Default");
            let m = set.mesh(name);
            for i in 1..p.verts.len() - 1 {
                m.add_triangle(p.verts[0], p.verts[i], p.verts[i + 1]);
            }
        }
        set
    }

    pub fn union(&self, other: &Solid) -> Solid {
        let mut a = Node::new(self.polys.clone());
        let mut b = Node::new(other.polys.clone());
        a.clip_to(&b);
        b.clip_to(&a);
        b.invert();
        b.clip_to(&a);
        b.invert();
        a.build(b.all_polygons());
        Solid { polys: a.all_polygons() }
    }

    pub fn subtract(&self, other: &Solid) -> Solid {
        if self.polys.is_empty() || other.polys.is_empty() {
            return self.clone();
        }
        let mut a = Node::new(self.polys.clone());
        let mut b = Node::new(other.polys.clone());
        a.invert();
        a.clip_to(&b);
        b.clip_to(&a);
        b.invert();
        b.clip_to(&a);
        b.invert();
        a.build(b.all_polygons());
        a.invert();
        Solid { polys: a.all_polygons() }
    }

    pub fn intersect(&self, other: &Solid) -> Solid {
        let mut a = Node::new(self.polys.clone());
        let mut b = Node::new(other.polys.clone());
        a.invert();
        b.clip_to(&a);
        b.invert();
        a.clip_to(&b);
        b.clip_to(&a);
        a.build(b.all_polygons());
        a.invert();
        Solid { polys: a.all_polygons() }
    }

    /// Signed volume (positive for outward-facing solids).
    pub fn volume(&self) -> f64 {
        self.polys
            .iter()
            .map(|p| (1..p.verts.len() - 1).map(|i| p.verts[0].dot(p.verts[i].cross(p.verts[i + 1]))).sum::<f64>())
            .sum::<f64>()
            / 6.0
    }

    pub fn bounds(&self) -> Option<(DVec3, DVec3)> {
        let first = *self.polys.first()?.verts.first()?;
        Some(self.polys.iter().flat_map(|p| p.verts.iter()).fold((first, first), |(a, b), v| (a.min(*v), b.max(*v))))
    }
}

/// Subtracts `cutter` from every mesh of `set` (materials are kept).
pub fn subtract_set(set: &MeshSet, cutter: &Solid) -> MeshSet {
    if cutter.polys.is_empty() {
        return set.clone();
    }
    let mut tags = Vec::new();
    let solid = Solid::from_set(set, &mut tags);
    // Skip the boolean when the boxes do not overlap.
    if let (Some((a0, a1)), Some((b0, b1))) = (solid.bounds(), cutter.bounds()) {
        if a1.x < b0.x || b1.x < a0.x || a1.y < b0.y || b1.y < a0.y || a1.z < b0.z || b1.z < a0.z {
            return set.clone();
        }
    }
    solid.subtract(cutter).to_set(&tags)
}

/// A prism solid: a plan polygon extruded between two heights.
pub fn prism(profile: &[crate::geom::DVec2], z0: f64, z1: f64) -> Solid {
    let mut set = MeshSet::default();
    set.add_extrusion("x", profile, z0, z1);
    Solid::from_mesh(&set.by_material["x"], 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom::DVec2;

    fn square(c: DVec2, h: f64) -> Vec<DVec2> {
        vec![c + DVec2::new(-h, -h), c + DVec2::new(h, -h), c + DVec2::new(h, h), c + DVec2::new(-h, h)]
    }

    #[test]
    fn subtract_box_from_box() {
        let a = prism(&square(DVec2::ZERO, 1000.0), 0.0, 1000.0);
        let b = prism(&square(DVec2::ZERO, 250.0), -100.0, 2000.0);
        let v = a.subtract(&b).volume();
        let expected = 2000.0 * 2000.0 * 1000.0 - 500.0 * 500.0 * 1000.0;
        assert!((v - expected).abs() / expected < 1e-6, "{v} vs {expected}");
        let u = a.union(&prism(&square(DVec2::new(1000.0, 0.0), 500.0), 0.0, 1000.0)).volume();
        let expected_u = 2000.0 * 2000.0 * 1000.0 + 500.0 * 1000.0 * 1000.0;
        assert!((u - expected_u).abs() / expected_u < 1e-6, "{u} vs {expected_u}");
        let i = a.intersect(&b).volume();
        assert!((i - 500.0 * 500.0 * 1000.0).abs() < 1.0);
    }
}
