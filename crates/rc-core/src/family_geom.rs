//! Geometry and plan symbols of loadable families (built-in templates and custom definitions).

use crate::analysis;
use crate::csg::{self, Solid};
use crate::family_params::Resolver;
use crate::geom::{self, DVec2, DVec3};
use crate::mesh::MeshSet;
use crate::model::*;

/// Local frame of a placed family: x along the host (hand), y towards the facing side, z up.
#[derive(Clone, Copy, Debug)]
pub struct InstanceFrame {
    pub origin: DVec2,
    pub z0: f64,
    pub x: DVec2,
    pub y: DVec2,
    /// Host wall thickness (or 0 for free-standing families).
    pub depth: f64,
    /// Beam length along x (0 for other families).
    pub length: f64,
    /// Beam end elevation relative to `z0` (slope).
    pub rise: f64,
}

impl InstanceFrame {
    pub fn plan(&self, x: f64, y: f64) -> DVec2 {
        self.origin + self.x * x + self.y * y
    }
    pub fn world(&self, x: f64, y: f64, z: f64) -> DVec3 {
        let slope = if self.length > 0.0 { self.rise * (x / self.length) } else { 0.0 };
        geom::at(self.plan(x, y), self.z0 + z + slope)
    }
}

pub fn instance_frame(p: &Project, i: &FamilyInstance) -> InstanceFrame {
    let z0 = p.level_elevation(i.level) + i.elevation;
    if let Some(w) = i.host.and_then(|h| p.wall(h)) {
        let (pt, d) = analysis::wall_point(w, i.offset_along_host);
        let n = geom::perp(d);
        return InstanceFrame {
            origin: pt,
            z0,
            x: if i.flip_hand { -d } else { d },
            y: if i.flip_facing { -n } else { n },
            depth: analysis::wall_thickness(p, w),
            length: 0.0,
            rise: 0.0,
        };
    }
    if let Some(end) = i.end {
        let d = (end - i.location).normalize_or(DVec2::X);
        return InstanceFrame {
            origin: i.location,
            z0,
            x: d,
            y: geom::perp(d),
            depth: 0.0,
            length: i.location.distance(end),
            rise: i.end_elevation - i.elevation,
        };
    }
    let a = i.rotation_deg.to_radians();
    let x = DVec2::new(a.cos(), a.sin());
    InstanceFrame { origin: i.location, z0, x, y: geom::perp(x), depth: 0.0, length: 0.0, rise: 0.0 }
}

/// Adds boxes and extrusions in an instance frame.
struct B<'a> {
    set: &'a mut MeshSet,
    f: InstanceFrame,
}

impl B<'_> {
    fn cube(&mut self, m: &str, x0: f64, x1: f64, y0: f64, y1: f64, z0: f64, z1: f64) {
        if x1 - x0 <= 0.0 || y1 - y0 <= 0.0 || z1 - z0 <= 0.0 {
            return;
        }
        if self.f.length > 0.0 && self.f.rise.abs() > 1e-6 {
            // Sloped beams: build the box from transformed corners.
            let mut local = MeshSet::default();
            local.add_box(m, DVec3::new(x0, y0, z0), DVec3::X * (x1 - x0), DVec3::Y * (y1 - y0), DVec3::Z * (z1 - z0));
            for (name, mesh) in local.by_material {
                let out = self.set.mesh(&name);
                for t in mesh.indices.chunks(3) {
                    let q: Vec<DVec3> = t.iter().map(|k| {
                        let v = mesh.positions[*k as usize];
                        self.f.world(v.x, v.y, v.z)
                    }).collect();
                    out.add_triangle(q[0], q[1], q[2]);
                }
            }
            return;
        }
        let o = self.f.world(x0, y0, z0);
        let u = geom::at(self.f.x * (x1 - x0), 0.0);
        let v = geom::at(self.f.y * (y1 - y0), 0.0);
        self.set.add_box(m, o, u, v, DVec3::Z * (z1 - z0));
    }

    /// Plan polygon (local x, y) extruded between z0 and z1.
    fn prism(&mut self, m: &str, pts: &[DVec2], z0: f64, z1: f64) {
        let world: Vec<DVec2> = pts.iter().map(|q| self.f.plan(q.x, q.y)).collect();
        self.set.add_extrusion(m, &world, self.f.z0 + z0, self.f.z0 + z1);
    }

    /// Polygon in the local x-z plane extruded along y between y0 and y1.
    fn prism_xz(&mut self, m: &str, pts: &[DVec2], y0: f64, y1: f64) {
        let mut local = MeshSet::default();
        local.add_extrusion(m, pts, y0, y1);
        for (name, mesh) in local.by_material {
            let out = self.set.mesh(&name);
            for t in mesh.indices.chunks(3) {
                // (u, v, w) = (x, z, y): a reflection, so swap two vertices to keep winding.
                let q: Vec<DVec3> = t.iter().map(|k| {
                    let v = mesh.positions[*k as usize];
                    self.f.world(v.x, v.z, v.y)
                }).collect();
                out.add_triangle(q[0], q[2], q[1]);
            }
        }
    }
}

fn circle(c: DVec2, r: f64, n: usize) -> Vec<DVec2> {
    (0..n).map(|k| {
        let a = k as f64 / n as f64 * std::f64::consts::TAU;
        c + DVec2::new(a.cos(), a.sin()) * r
    }).collect()
}

fn ellipse(c: DVec2, rx: f64, ry: f64, n: usize) -> Vec<DVec2> {
    (0..n).map(|k| {
        let a = k as f64 / n as f64 * std::f64::consts::TAU;
        c + DVec2::new(a.cos() * rx, a.sin() * ry)
    }).collect()
}

/// I-section outline centred on the origin (width along a, depth along b).
pub fn i_section(depth: f64, width: f64, tw: f64, tf: f64) -> Vec<DVec2> {
    let (h, b) = (depth / 2.0, width / 2.0);
    let (w, f) = (tw / 2.0, tf);
    vec![
        DVec2::new(-b, -h), DVec2::new(b, -h), DVec2::new(b, -h + f), DVec2::new(w, -h + f),
        DVec2::new(w, h - f), DVec2::new(b, h - f), DVec2::new(b, h), DVec2::new(-b, h),
        DVec2::new(-b, h - f), DVec2::new(-w, h - f), DVec2::new(-w, -h + f), DVec2::new(-b, -h + f),
    ]
}

/// Default height used when a column has no top constraint.
pub fn column_height(p: &Project, i: &FamilyInstance) -> f64 {
    Resolver::for_instance(p, i).map(|r| r.num("Height", 3000.0)).unwrap_or(3000.0)
}

/// 3D geometry of a family instance.
pub fn instance_mesh(p: &Project, i: &FamilyInstance) -> MeshSet {
    let mut set = MeshSet::default();
    let Some(r) = Resolver::for_instance(p, i) else { return set };
    let f = instance_frame(p, i);
    let template = r.family().template;
    let num = |n: &str, d: f64| r.num(n, d);
    let txt = |n: &str, d: &str| r.text(n, d);
    let mut b = B { set: &mut set, f };
    use FamilyTemplate::*;
    match template {
        SingleDoor | DoubleDoor | GlazedDoor | SlidingDoor | BifoldDoor | GarageDoor => {
            let (w, h, fw, pt) = (num("Width", 900.0), num("Height", 2100.0), num("Frame Width", 50.0), num("Panel Thickness", 40.0));
            let fd = if f.depth > 0.0 { f.depth } else { 120.0 };
            let frame = txt("Frame Material", "Wood");
            let panel = txt("Panel Material", "Wood - Painted White");
            let glass = txt("Glass Material", "Glass");
            b.cube(&frame, -w / 2.0 - fw, -w / 2.0, -fd / 2.0, fd / 2.0, 0.0, h + fw);
            b.cube(&frame, w / 2.0, w / 2.0 + fw, -fd / 2.0, fd / 2.0, 0.0, h + fw);
            b.cube(&frame, -w / 2.0, w / 2.0, -fd / 2.0, fd / 2.0, h, h + fw);
            let (py0, py1) = (-fd / 2.0, -fd / 2.0 + pt);
            let handle = "Aluminum";
            match template {
                SingleDoor => {
                    b.cube(&panel, -w / 2.0, w / 2.0, py0, py1, 0.0, h);
                    b.cube(handle, w / 2.0 - 160.0, w / 2.0 - 40.0, py0 - 50.0, py0, 1000.0, 1025.0);
                }
                GlazedDoor => {
                    let s = 120.0;
                    b.cube(&panel, -w / 2.0, -w / 2.0 + s, py0, py1, 0.0, h);
                    b.cube(&panel, w / 2.0 - s, w / 2.0, py0, py1, 0.0, h);
                    b.cube(&panel, -w / 2.0 + s, w / 2.0 - s, py0, py1, 0.0, s * 2.0);
                    b.cube(&panel, -w / 2.0 + s, w / 2.0 - s, py0, py1, h - s, h);
                    b.cube(&glass, -w / 2.0 + s, w / 2.0 - s, py0 + pt / 2.0 - 4.0, py0 + pt / 2.0 + 4.0, s * 2.0, h - s);
                    b.cube(handle, w / 2.0 - 160.0, w / 2.0 - 40.0, py0 - 50.0, py0, 1000.0, 1025.0);
                }
                DoubleDoor => {
                    b.cube(&panel, -w / 2.0, -3.0, py0, py1, 0.0, h);
                    b.cube(&panel, 3.0, w / 2.0, py0, py1, 0.0, h);
                    b.cube(handle, -160.0, -40.0, py0 - 50.0, py0, 1000.0, 1025.0);
                    b.cube(handle, 40.0, 160.0, py0 - 50.0, py0, 1000.0, 1025.0);
                }
                SlidingDoor => {
                    let s = 60.0;
                    for (x0, x1, y) in [(-w / 2.0, 30.0, -25.0), (-30.0, w / 2.0, 25.0)] {
                        b.cube(&frame, x0, x0 + s, y - 20.0, y + 20.0, 0.0, h);
                        b.cube(&frame, x1 - s, x1, y - 20.0, y + 20.0, 0.0, h);
                        b.cube(&frame, x0 + s, x1 - s, y - 20.0, y + 20.0, 0.0, s);
                        b.cube(&frame, x0 + s, x1 - s, y - 20.0, y + 20.0, h - s, h);
                        b.cube(&glass, x0 + s, x1 - s, y - 4.0, y + 4.0, s, h - s);
                    }
                }
                BifoldDoor => {
                    let n = num("Leaves", 4.0).round().clamp(2.0, 8.0) as usize;
                    let lw = w / n as f64;
                    for k in 0..n {
                        let x0 = -w / 2.0 + k as f64 * lw;
                        b.cube(&panel, x0 + 2.0, x0 + lw - 2.0, -15.0, 15.0, 0.0, h);
                    }
                }
                GarageDoor => {
                    let n = num("Sections", 5.0).round().clamp(2.0, 10.0) as usize;
                    let sh = h / n as f64;
                    for k in 0..n {
                        b.cube(&panel, -w / 2.0, w / 2.0, -fd / 2.0 + 10.0, -fd / 2.0 + 55.0, k as f64 * sh + 4.0, (k + 1) as f64 * sh - 4.0);
                    }
                }
                _ => {}
            }
        }
        FixedWindow | CasementWindow | AwningWindow | DoubleHungWindow | SlidingWindow => {
            let (w, h) = (num("Width", 1200.0), num("Height", 1200.0));
            let fw = num("Frame Width", 60.0).clamp(10.0, w / 3.0);
            let fd = num("Frame Depth", 100.0);
            let frame = txt("Frame Material", "Aluminum");
            let glass = txt("Glass Material", "Glass");
            let (y0, y1) = (-fd / 2.0, fd / 2.0);
            b.cube(&frame, -w / 2.0, -w / 2.0 + fw, y0, y1, 0.0, h);
            b.cube(&frame, w / 2.0 - fw, w / 2.0, y0, y1, 0.0, h);
            b.cube(&frame, -w / 2.0 + fw, w / 2.0 - fw, y0, y1, 0.0, fw);
            b.cube(&frame, -w / 2.0 + fw, w / 2.0 - fw, y0, y1, h - fw, h);
            let (iw, ih) = (w - 2.0 * fw, h - 2.0 * fw);
            let sw = num("Sash Width", 45.0);
            let sash = |b: &mut B, x0: f64, x1: f64, z0: f64, z1: f64, y: f64| {
                b.cube(&frame, x0, x0 + sw, y - 20.0, y + 20.0, z0, z1);
                b.cube(&frame, x1 - sw, x1, y - 20.0, y + 20.0, z0, z1);
                b.cube(&frame, x0 + sw, x1 - sw, y - 20.0, y + 20.0, z0, z0 + sw);
                b.cube(&frame, x0 + sw, x1 - sw, y - 20.0, y + 20.0, z1 - sw, z1);
                b.cube(&glass, x0 + sw, x1 - sw, y - 4.0, y + 4.0, z0 + sw, z1 - sw);
            };
            match template {
                FixedWindow | CasementWindow => {
                    let panels = num("Panels", 1.0).round().clamp(1.0, 20.0) as usize;
                    let transoms = num("Transoms", 0.0).round().clamp(0.0, 20.0) as usize;
                    let mw = num("Mullion Width", fw);
                    for k in 1..panels {
                        let x = -w / 2.0 + fw + iw * k as f64 / panels as f64;
                        b.cube(&frame, x - mw / 2.0, x + mw / 2.0, y0 * 0.8, y1 * 0.8, fw, h - fw);
                    }
                    for k in 1..=transoms {
                        let z = fw + ih * k as f64 / (transoms + 1) as f64;
                        b.cube(&frame, -w / 2.0 + fw, w / 2.0 - fw, y0 * 0.8, y1 * 0.8, z - mw / 2.0, z + mw / 2.0);
                    }
                    if template == CasementWindow {
                        for k in 0..panels {
                            let xa = -w / 2.0 + fw + iw * k as f64 / panels as f64 + if k > 0 { mw / 2.0 } else { 0.0 };
                            let xb = -w / 2.0 + fw + iw * (k + 1) as f64 / panels as f64 - if k + 1 < panels { mw / 2.0 } else { 0.0 };
                            sash(&mut b, xa, xb, fw, h - fw, 0.0);
                        }
                    } else {
                        b.cube(&glass, -w / 2.0 + fw, w / 2.0 - fw, -4.0, 4.0, fw, h - fw);
                    }
                }
                AwningWindow => sash(&mut b, -w / 2.0 + fw, w / 2.0 - fw, fw, h - fw, 0.0),
                DoubleHungWindow => {
                    sash(&mut b, -w / 2.0 + fw, w / 2.0 - fw, fw, h / 2.0 + 20.0, -22.0);
                    sash(&mut b, -w / 2.0 + fw, w / 2.0 - fw, h / 2.0 - 20.0, h - fw, 22.0);
                }
                SlidingWindow => {
                    sash(&mut b, -w / 2.0 + fw, 20.0, fw, h - fw, -22.0);
                    sash(&mut b, -20.0, w / 2.0 - fw, fw, h - fw, 22.0);
                }
                _ => {}
            }
            if f.depth > 0.0 {
                b.cube(&frame, -w / 2.0 - 30.0, w / 2.0 + 30.0, y1, f.depth / 2.0 + 40.0, -25.0, 0.0);
            }
        }
        RoundWindow => {
            let d = num("Diameter", 900.0);
            let fw = num("Frame Width", 60.0);
            let fd = num("Frame Depth", 100.0);
            let frame = txt("Frame Material", "Aluminum");
            let glass = txt("Glass Material", "Glass");
            let c = DVec2::new(0.0, d / 2.0);
            let outer = circle(c, d / 2.0, 32);
            let inner = circle(c, d / 2.0 - fw, 32);
            for k in 0..32 {
                let j = (k + 1) % 32;
                b.prism_xz(&frame, &[inner[k], outer[k], outer[j], inner[j]], -fd / 2.0, fd / 2.0);
            }
            b.prism_xz(&glass, &inner, -4.0, 4.0);
        }
        Table => {
            let (w, d, h) = (num("Width", 1600.0), num("Depth", 800.0), num("Height", 750.0));
            let (tt, ls) = (num("Top Thickness", 40.0), num("Leg Size", 60.0));
            let (top, leg) = (txt("Top Material", "Wood"), txt("Leg Material", "Steel"));
            b.cube(&top, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, h - tt, h);
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let (cx, cy) = (sx * (w / 2.0 - 40.0 - ls / 2.0), sy * (d / 2.0 - 40.0 - ls / 2.0));
                b.cube(&leg, cx - ls / 2.0, cx + ls / 2.0, cy - ls / 2.0, cy + ls / 2.0, 0.0, h - tt);
            }
        }
        Chair => {
            let (w, d, sh, h) = (num("Width", 450.0), num("Depth", 500.0), num("Seat Height", 450.0), num("Height", 850.0));
            let m = txt("Material", "Wood");
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, sh - 40.0, sh);
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let (cx, cy) = (sx * (w / 2.0 - 25.0), sy * (d / 2.0 - 25.0));
                b.cube(&m, cx - 20.0, cx + 20.0, cy - 20.0, cy + 20.0, 0.0, sh - 40.0);
            }
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 40.0, sh, h);
        }
        Sofa => {
            let (w, d, h, sh, aw) = (num("Width", 2000.0), num("Depth", 900.0), num("Height", 800.0), num("Seat Height", 420.0), num("Arm Width", 200.0));
            let m = txt("Material", "Fabric");
            b.cube(&m, -w / 2.0 + aw, w / 2.0 - aw, -d / 2.0 + 200.0, d / 2.0, 100.0, sh);
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 200.0, 100.0, h);
            b.cube(&m, -w / 2.0, -w / 2.0 + aw, -d / 2.0, d / 2.0, 100.0, sh + 180.0);
            b.cube(&m, w / 2.0 - aw, w / 2.0, -d / 2.0, d / 2.0, 100.0, sh + 180.0);
            b.cube("Wood", -w / 2.0 + 30.0, w / 2.0 - 30.0, -d / 2.0 + 30.0, d / 2.0 - 30.0, 0.0, 100.0);
        }
        Bed => {
            let (w, d, h, hh) = (num("Width", 1600.0), num("Depth", 2000.0), num("Height", 500.0), num("Headboard Height", 1000.0));
            let (fr, ma) = (txt("Frame Material", "Wood"), txt("Mattress Material", "Fabric"));
            b.cube(&fr, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, 100.0, h - 200.0);
            b.cube(&ma, -w / 2.0 + 20.0, w / 2.0 - 20.0, -d / 2.0 + 60.0, d / 2.0 - 20.0, h - 200.0, h);
            b.cube(&fr, -w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 60.0, 0.0, hh);
            let pw = (w - 120.0) / 2.0;
            for k in 0..2 {
                let x0 = -w / 2.0 + 40.0 + k as f64 * (pw + 40.0);
                b.cube("Fabric", x0, x0 + pw, -d / 2.0 + 90.0, -d / 2.0 + 450.0, h, h + 120.0);
            }
        }
        Desk => {
            let (w, d, h, dw) = (num("Width", 1400.0), num("Depth", 700.0), num("Height", 740.0), num("Drawer Width", 400.0));
            let m = txt("Material", "Wood");
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, h - 30.0, h);
            b.cube(&m, w / 2.0 - dw, w / 2.0, -d / 2.0 + 20.0, d / 2.0 - 20.0, 0.0, h - 30.0);
            b.cube(&m, -w / 2.0, -w / 2.0 + 30.0, -d / 2.0 + 20.0, d / 2.0 - 20.0, 0.0, h - 30.0);
        }
        Wardrobe => {
            let (w, d, h) = (num("Width", 1200.0), num("Depth", 600.0), num("Height", 2100.0));
            let n = num("Doors", 2.0).round().clamp(1.0, 6.0) as usize;
            let m = txt("Material", "Wood - Painted White");
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0 - 20.0, 0.0, h);
            for k in 0..n {
                let x0 = -w / 2.0 + w * k as f64 / n as f64;
                let x1 = x0 + w / n as f64;
                b.cube(&m, x0 + 2.0, x1 - 2.0, d / 2.0 - 20.0, d / 2.0, 0.0, h);
                let hx = if k % 2 == 0 { x1 - 60.0 } else { x0 + 50.0 };
                b.cube("Aluminum", hx, hx + 10.0, d / 2.0, d / 2.0 + 25.0, h / 2.0 - 150.0, h / 2.0 + 150.0);
            }
        }
        KitchenCabinet => {
            let (w, d, h) = (num("Width", 600.0), num("Depth", 600.0), num("Height", 900.0));
            let (ct, pl) = (num("Countertop Thickness", 40.0), num("Plinth Height", 100.0));
            let (cab, top) = (txt("Cabinet Material", "Wood - Painted White"), txt("Countertop Material", "Stone"));
            b.cube("Default", -w / 2.0, w / 2.0, -d / 2.0, d / 2.0 - 60.0, 0.0, pl);
            b.cube(&cab, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0 - 20.0, pl, h - ct);
            b.cube(&cab, -w / 2.0 + 2.0, w / 2.0 - 2.0, d / 2.0 - 20.0, d / 2.0, pl + 2.0, h - ct - 2.0);
            b.cube(&top, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0 + 20.0, h - ct, h);
            b.cube("Aluminum", -w / 4.0, w / 4.0, d / 2.0, d / 2.0 + 25.0, h - ct - 80.0, h - ct - 70.0);
        }
        Toilet => {
            let (w, d, h) = (num("Width", 380.0), num("Depth", 700.0), num("Height", 400.0));
            let m = txt("Material", "Porcelain");
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 180.0, 0.0, h + 380.0);
            b.prism(&m, &ellipse(DVec2::new(0.0, 80.0), w / 2.0, d / 2.0 - 100.0, 24), 0.0, h);
        }
        Sink => {
            let (w, d, h) = (num("Width", 600.0), num("Depth", 450.0), num("Height", 850.0));
            let m = txt("Material", "Porcelain");
            b.cube("Wood - Painted White", -w / 2.0, w / 2.0, -d / 2.0, d / 2.0 - 20.0, 100.0, h - 60.0);
            let mut top = MeshSet::default();
            let mut tb = B { set: &mut top, f };
            tb.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, h - 60.0, h);
            let mut basin = MeshSet::default();
            let mut bb = B { set: &mut basin, f };
            bb.prism("x", &ellipse(DVec2::new(0.0, 20.0), w / 2.0 - 70.0, d / 2.0 - 80.0, 24), h - 50.0, h + 10.0);
            let cut = csg::subtract_set(&top, &Solid::from_mesh(&basin.by_material["x"], 0));
            for (n, msh) in cut.by_material {
                set_append(b.set, &n, msh);
            }
        }
        Bathtub => {
            let (w, d, h) = (num("Width", 1700.0), num("Depth", 750.0), num("Height", 550.0));
            let m = txt("Material", "Porcelain");
            let mut outer = MeshSet::default();
            let mut ob = B { set: &mut outer, f };
            ob.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, 0.0, h);
            let mut inner = MeshSet::default();
            let mut ib = B { set: &mut inner, f };
            ib.prism("x", &ellipse(DVec2::ZERO, w / 2.0 - 90.0, d / 2.0 - 80.0, 32), 120.0, h + 10.0);
            let cut = csg::subtract_set(&outer, &Solid::from_mesh(&inner.by_material["x"], 0));
            for (n, msh) in cut.by_material {
                set_append(b.set, &n, msh);
            }
        }
        Shower => {
            let (w, d, h, sh) = (num("Width", 900.0), num("Depth", 900.0), num("Height", 60.0), num("Screen Height", 1900.0));
            let (m, g) = (txt("Material", "Porcelain"), txt("Glass Material", "Glass"));
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, 0.0, h);
            b.cube(&g, -w / 2.0, w / 2.0, d / 2.0 - 8.0, d / 2.0, h, h + sh);
            b.cube(&g, w / 2.0 - 8.0, w / 2.0, -d / 2.0, d / 2.0, h, h + sh);
        }
        Refrigerator => {
            let (w, d, h) = (num("Width", 700.0), num("Depth", 700.0), num("Height", 1800.0));
            let m = txt("Material", "Steel - Stainless");
            b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, 0.0, h);
            b.cube("Default", -w / 2.0 + 10.0, w / 2.0 - 10.0, d / 2.0, d / 2.0 + 4.0, h * 0.62, h * 0.62 + 8.0);
            b.cube("Aluminum", w / 2.0 - 70.0, w / 2.0 - 50.0, d / 2.0, d / 2.0 + 40.0, h * 0.3, h * 0.55);
        }
        RectColumn | RoundColumn | SteelColumn => {
            let (z0, z1) = analysis::column_extent(p, i, column_height(p, i));
            let (bz0, bz1) = (z0 - f.z0, z1 - f.z0);
            let m = txt("Material", "Concrete");
            match template {
                RectColumn => {
                    let (w, d) = (num("Width", 400.0), num("Depth", 400.0));
                    b.cube(&m, -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, bz0, bz1);
                }
                RoundColumn => b.prism(&m, &circle(DVec2::ZERO, num("Diameter", 400.0) / 2.0, 32), bz0, bz1),
                _ => {
                    let sec = i_section(num("Section Depth", 300.0), num("Flange Width", 300.0), num("Web Thickness", 11.0), num("Flange Thickness", 19.0));
                    let rot: Vec<DVec2> = sec.iter().map(|q| DVec2::new(q.x, q.y)).collect();
                    b.prism(&m, &rot, bz0, bz1);
                }
            }
        }
        RectBeam | SteelBeam => {
            let len = f.length.max(1.0);
            let dep = num("Section Depth", 600.0);
            let m = txt("Material", "Concrete");
            if template == RectBeam {
                let w = num("Width", 300.0);
                b.cube(&m, 0.0, len, -w / 2.0, w / 2.0, -dep, 0.0);
            } else {
                let (bw, tw, tf) = (num("Flange Width", 190.0), num("Web Thickness", 9.0), num("Flange Thickness", 15.0));
                b.cube(&m, 0.0, len, -bw / 2.0, bw / 2.0, -tf, 0.0);
                b.cube(&m, 0.0, len, -bw / 2.0, bw / 2.0, -dep, -dep + tf);
                b.cube(&m, 0.0, len, -tw / 2.0, tw / 2.0, -dep + tf, -tf);
            }
        }
        Footing => {
            let (w, d, t) = (num("Width", 1500.0), num("Depth", 1500.0), num("Thickness", 500.0));
            b.cube(&txt("Material", "Concrete"), -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, -t, 0.0);
        }
        Box => {
            let (w, d, h) = (num("Width", 1000.0), num("Depth", 1000.0), num("Height", 1000.0));
            b.cube(&txt("Material", "Default"), -w / 2.0, w / 2.0, -d / 2.0, d / 2.0, 0.0, h);
        }
        Custom => {
            if let Some(def) = &r.family().definition {
                if let Ok(solved) = def.solve(&|n| r.number(n).ok()) {
                    let local = def.build(&solved, &|m| if r.family().param(m).is_some() { r.text(m, "Default") } else if m.is_empty() { "Default".into() } else { m.to_string() }, &|v| r.yes_no(v, true));
                    for (name, mesh) in local.by_material {
                        let out = b.set.mesh(&name);
                        for t in mesh.indices.chunks(3) {
                            let q: Vec<DVec3> = t.iter().map(|k| {
                                let v = mesh.positions[*k as usize];
                                f.world(v.x, v.y, v.z)
                            }).collect();
                            out.add_triangle(q[0], q[1], q[2]);
                        }
                    }
                }
            }
        }
    }
    set
}

fn set_append(set: &mut MeshSet, name: &str, mesh: crate::mesh::Mesh) {
    set.mesh(name).append(&mesh);
}

/// Kinds of plan linework a family contributes.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SymStyle {
    /// Cut by the view plane (heavy).
    Cut,
    /// Seen below the cut plane.
    Projection,
    /// Thin detail lines (swings, glass).
    Detail,
    /// Above the cut plane or hidden.
    Hidden,
}

#[derive(Clone, Debug)]
pub struct SymLine {
    pub pts: Vec<DVec2>,
    pub closed: bool,
    pub style: SymStyle,
    /// Solid fill (columns cut in plan).
    pub fill: Option<[u8; 3]>,
}

fn arc_pts(c: DVec2, r: f64, a0: f64, sweep: f64, n: usize) -> Vec<DVec2> {
    (0..=n).map(|k| {
        let a = a0 + sweep * k as f64 / n as f64;
        c + DVec2::new(a.cos(), a.sin()) * r
    }).collect()
}

/// Plan symbol of an instance as seen in a plan cut at `cut_z` (absolute).
pub fn instance_symbol(p: &Project, i: &FamilyInstance, cut_z: f64) -> Vec<SymLine> {
    let mut out = Vec::new();
    let Some(r) = Resolver::for_instance(p, i) else { return out };
    let f = instance_frame(p, i);
    let num = |n: &str, d: f64| r.num(n, d);
    let template = r.family().template;
    let rect = |x0: f64, x1: f64, y0: f64, y1: f64| vec![f.plan(x0, y0), f.plan(x1, y0), f.plan(x1, y1), f.plan(x0, y1)];
    let line = |pts: Vec<DVec2>, closed: bool, style: SymStyle| SymLine { pts, closed, style, fill: None };
    use FamilyTemplate::*;
    match template {
        SingleDoor | DoubleDoor | GlazedDoor | SlidingDoor | BifoldDoor | GarageDoor => {
            let w = num("Width", 900.0);
            let fw = num("Frame Width", 50.0);
            let t = f.depth.max(100.0) / 2.0;
            out.push(line(rect(-w / 2.0 - fw, -w / 2.0, -t, t), true, SymStyle::Projection));
            out.push(line(rect(w / 2.0, w / 2.0 + fw, -t, t), true, SymStyle::Projection));
            let swing = |out: &mut Vec<SymLine>, hinge_x: f64, leaf: f64, dir: f64| {
                let hinge = f.plan(hinge_x, -t);
                let open_end = f.plan(hinge_x, -t - leaf);
                out.push(line(vec![hinge, open_end], false, SymStyle::Projection));
                let a_open = (open_end - hinge).y.atan2((open_end - hinge).x);
                let closed = f.plan(hinge_x + dir * leaf, -t);
                let a_closed = (closed - hinge).y.atan2((closed - hinge).x);
                let mut sweep = a_closed - a_open;
                while sweep > std::f64::consts::PI {
                    sweep -= std::f64::consts::TAU;
                }
                while sweep < -std::f64::consts::PI {
                    sweep += std::f64::consts::TAU;
                }
                out.push(line(arc_pts(hinge, leaf, a_open, sweep, 24), false, SymStyle::Detail));
            };
            match template {
                SingleDoor | GlazedDoor => swing(&mut out, -w / 2.0, w, 1.0),
                DoubleDoor => {
                    swing(&mut out, -w / 2.0, w / 2.0, 1.0);
                    swing(&mut out, w / 2.0, w / 2.0, -1.0);
                }
                SlidingDoor => {
                    out.push(line(rect(-w / 2.0, 30.0, -45.0, -5.0), true, SymStyle::Projection));
                    out.push(line(rect(-30.0, w / 2.0, 5.0, 45.0), true, SymStyle::Projection));
                }
                BifoldDoor => {
                    let n = num("Leaves", 4.0).round().clamp(2.0, 8.0) as usize;
                    let lw = w / n as f64;
                    let mut pts = vec![f.plan(-w / 2.0, -t)];
                    for k in 1..=n {
                        let y = if k % 2 == 1 { -t - lw * 0.6 } else { -t };
                        pts.push(f.plan(-w / 2.0 + k as f64 * lw * 0.45, y));
                    }
                    out.push(line(pts, false, SymStyle::Detail));
                }
                GarageDoor => {
                    out.push(line(vec![f.plan(-w / 2.0, -t + 30.0), f.plan(w / 2.0, -t + 30.0)], false, SymStyle::Projection));
                    let h = num("Height", 2100.0);
                    out.push(line(rect(-w / 2.0, w / 2.0, -t - h, -t), true, SymStyle::Hidden));
                }
                _ => {}
            }
        }
        FixedWindow | CasementWindow | AwningWindow | DoubleHungWindow | SlidingWindow | RoundWindow => {
            let w = num("Width", 1200.0);
            let (_, oh) = analysis::opening_size(p, i);
            let cut = f.z0 <= cut_z && cut_z <= f.z0 + oh;
            let t = f.depth.max(100.0) / 2.0;
            let s = if cut { SymStyle::Projection } else { SymStyle::Hidden };
            out.push(line(rect(-w / 2.0, w / 2.0, -t, t), true, s));
            out.push(line(vec![f.plan(-w / 2.0, 0.0), f.plan(w / 2.0, 0.0)], false, if cut { SymStyle::Detail } else { SymStyle::Hidden }));
            if cut {
                let fd = num("Frame Depth", 100.0) / 2.0;
                out.push(line(vec![f.plan(-w / 2.0, -fd), f.plan(w / 2.0, -fd)], false, SymStyle::Detail));
                out.push(line(vec![f.plan(-w / 2.0, fd), f.plan(w / 2.0, fd)], false, SymStyle::Detail));
            }
        }
        RectColumn | RoundColumn | SteelColumn => {
            let (z0, z1) = analysis::column_extent(p, i, column_height(p, i));
            let cut = z0 <= cut_z && cut_z <= z1;
            let shape: Vec<DVec2> = match template {
                RectColumn => rect(-num("Width", 400.0) / 2.0, num("Width", 400.0) / 2.0, -num("Depth", 400.0) / 2.0, num("Depth", 400.0) / 2.0),
                RoundColumn => circle(DVec2::ZERO, num("Diameter", 400.0) / 2.0, 32).into_iter().map(|q| f.plan(q.x, q.y)).collect(),
                _ => i_section(num("Section Depth", 300.0), num("Flange Width", 300.0), num("Web Thickness", 11.0), num("Flange Thickness", 19.0))
                    .into_iter()
                    .map(|q| f.plan(q.x, q.y))
                    .collect(),
            };
            let fill = if cut {
                Some(if template == SteelColumn { [40, 40, 40] } else { [150, 150, 150] })
            } else {
                None
            };
            out.push(SymLine { pts: shape, closed: true, style: if cut { SymStyle::Cut } else { SymStyle::Projection }, fill });
        }
        RectBeam | SteelBeam => {
            let len = f.length;
            let w = num("Width", 300.0);
            out.push(line(rect(0.0, len, -w / 2.0, w / 2.0), true, SymStyle::Hidden));
            out.push(line(vec![f.plan(0.0, 0.0), f.plan(len, 0.0)], false, SymStyle::Detail));
        }
        Footing => {
            let (w, d) = (num("Width", 1500.0), num("Depth", 1500.0));
            out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, d / 2.0), true, SymStyle::Hidden));
        }
        Custom => {
            if let Some(def) = &r.family().definition {
                if let Ok(solved) = def.solve(&|n| r.number(n).ok()) {
                    for (a, b) in def.symbolic_lines(&solved) {
                        out.push(line(vec![f.plan(a.x, a.y), f.plan(b.x, b.y)], false, SymStyle::Projection));
                    }
                    if def.symbolic.is_empty() {
                        // Outline of the geometry's footprint.
                        let mesh = instance_mesh(p, i);
                        if let Some((mn, mx)) = mesh.bounds() {
                            let pts = vec![DVec2::new(mn.x, mn.y), DVec2::new(mx.x, mn.y), DVec2::new(mx.x, mx.y), DVec2::new(mn.x, mx.y)];
                            out.push(line(pts, true, SymStyle::Projection));
                        }
                    }
                }
            }
        }
        _ => {
            // Furniture, casework, fixtures: outline plus characteristic detail.
            let (w, d) = (num("Width", 1000.0), num("Depth", 1000.0));
            out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, d / 2.0), true, SymStyle::Projection));
            match template {
                Box => {
                    out.push(line(vec![f.plan(-w / 2.0, -d / 2.0), f.plan(w / 2.0, d / 2.0)], false, SymStyle::Detail));
                    out.push(line(vec![f.plan(-w / 2.0, d / 2.0), f.plan(w / 2.0, -d / 2.0)], false, SymStyle::Detail));
                }
                Chair => out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 40.0), true, SymStyle::Detail)),
                Sofa => {
                    let aw = num("Arm Width", 200.0);
                    out.push(line(rect(-w / 2.0 + aw, w / 2.0 - aw, -d / 2.0 + 200.0, d / 2.0), true, SymStyle::Detail));
                }
                Bed => {
                    out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 60.0), true, SymStyle::Detail));
                    let pw = (w - 120.0) / 2.0;
                    for k in 0..2 {
                        let x0 = -w / 2.0 + 40.0 + k as f64 * (pw + 40.0);
                        out.push(line(rect(x0, x0 + pw, -d / 2.0 + 90.0, -d / 2.0 + 450.0), true, SymStyle::Detail));
                    }
                    out.push(line(vec![f.plan(-w / 2.0, -d / 2.0 + 700.0), f.plan(w / 2.0, -d / 2.0 + 900.0)], false, SymStyle::Detail));
                }
                Desk => out.push(line(rect(w / 2.0 - num("Drawer Width", 400.0), w / 2.0, -d / 2.0 + 20.0, d / 2.0 - 20.0), true, SymStyle::Hidden)),
                Wardrobe => {
                    out.push(line(vec![f.plan(-w / 2.0, d / 2.0 - 20.0), f.plan(w / 2.0, d / 2.0 - 20.0)], false, SymStyle::Detail));
                    out.push(line(vec![f.plan(-w / 2.0, -d / 2.0), f.plan(w / 2.0, d / 2.0 - 20.0)], false, SymStyle::Detail));
                }
                KitchenCabinet => out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, d / 2.0 + 20.0), true, SymStyle::Detail)),
                Toilet => {
                    out.push(line(ellipse(DVec2::new(0.0, 80.0), w / 2.0, d / 2.0 - 100.0, 24).into_iter().map(|q| f.plan(q.x, q.y)).collect(), true, SymStyle::Detail));
                    out.push(line(rect(-w / 2.0, w / 2.0, -d / 2.0, -d / 2.0 + 180.0), true, SymStyle::Detail));
                }
                Sink => out.push(line(ellipse(DVec2::new(0.0, 20.0), w / 2.0 - 70.0, d / 2.0 - 80.0, 24).into_iter().map(|q| f.plan(q.x, q.y)).collect(), true, SymStyle::Detail)),
                Bathtub => out.push(line(ellipse(DVec2::ZERO, w / 2.0 - 90.0, d / 2.0 - 80.0, 32).into_iter().map(|q| f.plan(q.x, q.y)).collect(), true, SymStyle::Detail)),
                Shower => {
                    out.push(line(vec![f.plan(-w / 2.0, -d / 2.0), f.plan(w / 2.0, d / 2.0)], false, SymStyle::Detail));
                    out.push(line(vec![f.plan(-w / 2.0, d / 2.0), f.plan(w / 2.0, -d / 2.0)], false, SymStyle::Detail));
                }
                Refrigerator => out.push(line(vec![f.plan(-w / 2.0, d / 2.0 - 40.0), f.plan(w / 2.0, d / 2.0 - 40.0)], false, SymStyle::Detail)),
                _ => {}
            }
        }
    }
    out
}

/// Plan outline used for picking and selection highlight.
pub fn instance_outline(p: &Project, i: &FamilyInstance) -> Vec<DVec2> {
    let Some(r) = Resolver::for_instance(p, i) else { return vec![] };
    let f = instance_frame(p, i);
    let rect = |x0: f64, x1: f64, y0: f64, y1: f64| vec![f.plan(x0, y0), f.plan(x1, y0), f.plan(x1, y1), f.plan(x0, y1)];
    let fam = r.family();
    if fam.is_hosted() {
        let w = r.num("Rough Width", r.num("Width", 900.0));
        let t = f.depth.max(100.0) / 2.0;
        if fam.category == Category::Doors {
            let leaf = r.num("Width", 900.0);
            return rect(-w / 2.0, w / 2.0, -t - leaf, t);
        }
        return rect(-w / 2.0, w / 2.0, -t, t);
    }
    if fam.is_framing() {
        let w = r.num("Width", 300.0);
        return rect(0.0, f.length, -w / 2.0, w / 2.0);
    }
    if fam.template == FamilyTemplate::Custom {
        let mesh = instance_mesh(p, i);
        if let Some((mn, mx)) = mesh.bounds() {
            return vec![DVec2::new(mn.x, mn.y), DVec2::new(mx.x, mn.y), DVec2::new(mx.x, mx.y), DVec2::new(mn.x, mx.y)];
        }
    }
    let (w, d) = (r.num("Width", 1000.0), r.num("Depth", 1000.0));
    rect(-w / 2.0, w / 2.0, -d / 2.0, d / 2.0)
}
