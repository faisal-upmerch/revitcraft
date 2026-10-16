//! Model Text: 3D text built from Arial glyph outlines (the reference app's default model
//! text font), extruded by its depth.

use crate::geom::{self, DVec2};
use crate::mesh::MeshSet;
use crate::model::{ModelText, Project};
use skrifa::outline::{DrawSettings, OutlinePen};
use skrifa::prelude::{LocationRef, Size};
use skrifa::{FontRef, MetadataProvider};
use std::sync::OnceLock;

/// Cap height of Arial as a fraction of its em: model text size is the capital height.
const CAP_HEIGHT: f64 = 0.716;

/// Arial from the system fonts (or a metric-compatible substitute where Arial is missing).
fn font_bytes() -> Option<&'static [u8]> {
    static FONT: OnceLock<Option<Vec<u8>>> = OnceLock::new();
    FONT.get_or_init(|| {
        let windir = std::env::var("WINDIR").unwrap_or_else(|_| "C:\\Windows".into());
        let candidates = [
            format!("{windir}\\Fonts\\arial.ttf"),
            "/Library/Fonts/Arial.ttf".into(),
            "/System/Library/Fonts/Supplemental/Arial.ttf".into(),
            "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf".into(),
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf".into(),
            "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf".into(),
        ];
        candidates.iter().find_map(|p| std::fs::read(p).ok())
    })
    .as_deref()
}

/// Collects glyph outlines as closed polylines (curves flattened).
struct Pen {
    contours: Vec<Vec<DVec2>>,
    cur: Vec<DVec2>,
    origin: DVec2,
}

impl Pen {
    fn p(&self, x: f32, y: f32) -> DVec2 {
        self.origin + DVec2::new(x as f64, y as f64)
    }
    fn flush(&mut self) {
        let mut c = std::mem::take(&mut self.cur);
        if c.len() >= 2 && c[0].distance(*c.last().unwrap()) < 1e-6 {
            c.pop();
        }
        if c.len() >= 3 {
            self.contours.push(c);
        }
    }
    fn last(&self) -> DVec2 {
        self.cur.last().copied().unwrap_or(self.origin)
    }
}

impl OutlinePen for Pen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.flush();
        let q = self.p(x, y);
        self.cur.push(q);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        let q = self.p(x, y);
        self.cur.push(q);
    }
    fn quad_to(&mut self, cx0: f32, cy0: f32, x: f32, y: f32) {
        let (p0, c, p1) = (self.last(), self.p(cx0, cy0), self.p(x, y));
        for k in 1..=6 {
            let t = k as f64 / 6.0;
            let q = p0 * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + p1 * t * t;
            self.cur.push(q);
        }
    }
    fn curve_to(&mut self, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x: f32, y: f32) {
        let (p0, c0, c1, p1) = (self.last(), self.p(cx0, cy0), self.p(cx1, cy1), self.p(x, y));
        for k in 1..=8 {
            let t = k as f64 / 8.0;
            let u = 1.0 - t;
            let q = p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t;
            self.cur.push(q);
        }
    }
    fn close(&mut self) {
        self.flush();
    }
}

/// Glyph outlines of `text` in local millimetres: capitals `size` tall, the first baseline on
/// y = 0, lines below each other, aligned on x = 0 (0 left, 1 centre, 2 right).
pub fn text_contours(text: &str, size: f64, align: u8) -> Vec<Vec<DVec2>> {
    let Some(font) = font_bytes().and_then(|b| FontRef::new(b).ok()) else { return vec![] };
    let em = (size / CAP_HEIGHT) as f32;
    let charmap = font.charmap();
    let metrics = font.glyph_metrics(Size::new(em), LocationRef::default());
    let outlines = font.outline_glyphs();
    let line_height = size / CAP_HEIGHT * 1.15;
    let mut pen = Pen { contours: Vec::new(), cur: Vec::new(), origin: DVec2::ZERO };
    for (li, line) in text.lines().enumerate() {
        let gids: Vec<_> = line.chars().map(|c| charmap.map(c).unwrap_or_default()).collect();
        let width: f64 = gids.iter().map(|g| metrics.advance_width(*g).unwrap_or(0.0) as f64).sum();
        let mut x = match align {
            1 => -width / 2.0,
            2 => -width,
            _ => 0.0,
        };
        let y = -(li as f64) * line_height;
        for g in gids {
            if let Some(glyph) = outlines.get(g) {
                pen.origin = DVec2::new(x, y);
                let _ = glyph.draw(DrawSettings::unhinted(Size::new(em), LocationRef::default()), &mut pen);
                pen.flush();
            }
            x += metrics.advance_width(g).unwrap_or(0.0) as f64;
        }
    }
    pen.contours
}

/// Contours grouped into outlines with their holes (by how many contours enclose each one).
pub fn shapes(contours: &[Vec<DVec2>]) -> Vec<(Vec<DVec2>, Vec<Vec<DVec2>>)> {
    let depth: Vec<usize> = contours
        .iter()
        .enumerate()
        .map(|(i, c)| contours.iter().enumerate().filter(|(j, o)| *j != i && geom::contains(o, c[0])).count())
        .collect();
    let mut out: Vec<(usize, Vec<DVec2>, Vec<Vec<DVec2>>)> = contours
        .iter()
        .enumerate()
        .filter(|(i, _)| depth[*i] % 2 == 0)
        .map(|(i, c)| (i, c.clone(), Vec::new()))
        .collect();
    for (i, c) in contours.iter().enumerate().filter(|(i, _)| depth[*i] % 2 == 1) {
        // The hole belongs to the smallest outline around it.
        let owner = out
            .iter_mut()
            .filter(|(j, o, _)| *j != i && geom::contains(o, c[0]))
            .min_by(|a, b| geom::area(&a.1).total_cmp(&geom::area(&b.1)));
        if let Some((_, _, holes)) = owner {
            holes.push(c.clone());
        }
    }
    out.into_iter().map(|(_, o, h)| (o, h)).collect()
}

/// Plan outlines of a model text element, placed and rotated.
pub fn plan_contours(t: &ModelText) -> Vec<Vec<DVec2>> {
    let (dir, n) = frame(t);
    text_contours(&t.text, t.size, t.align).into_iter().map(|c| c.into_iter().map(|q| t.position + dir * q.x + n * q.y).collect()).collect()
}

fn frame(t: &ModelText) -> (DVec2, DVec2) {
    let a = t.rotation_deg.to_radians();
    let dir = DVec2::new(a.cos(), a.sin());
    (dir, geom::perp(dir))
}

/// The 3D text: lying on its level (extruded up), or standing upright when `vertical`
/// (extruded behind the text plane).
pub fn mesh(p: &Project, t: &ModelText) -> MeshSet {
    let mut set = MeshSet::default();
    let mat = if t.material.is_empty() { "Default" } else { t.material.as_str() };
    let z0 = p.level_elevation(t.level) + t.elevation;
    let shapes = shapes(&text_contours(&t.text, t.size, t.align));
    let (dir, n) = frame(t);
    for (outer, holes) in shapes {
        let mut local = MeshSet::default();
        local.add_extrusion_with_holes(mat, &outer, &holes, 0.0, t.depth.max(0.1));
        for (name, m) in local.by_material {
            let target = set.mesh(&name);
            for tri in m.indices.chunks(3) {
                let q: Vec<geom::DVec3> = tri
                    .iter()
                    .map(|k| {
                        let v = m.positions[*k as usize];
                        if t.vertical {
                            // Text in the vertical plane along `dir`, extruded behind it (-n).
                            geom::at(t.position + dir * v.x - n * v.z, z0 + v.y)
                        } else {
                            geom::at(t.position + dir * v.x + n * v.y, z0 + v.z)
                        }
                    })
                    .collect();
                // Both placements are rotations of the local frame, so the winding holds.
                target.add_triangle(q[0], q[1], q[2]);
            }
        }
    }
    set
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Glyphs come out at the requested capital height, with the hole of an "O" found.
    #[test]
    fn glyph_outlines() {
        let c = text_contours("HO", 300.0, 0);
        if c.is_empty() {
            return; // No Arial (or substitute) on this machine.
        }
        let top = c.iter().flatten().map(|q| q.y).fold(f64::MIN, f64::max);
        assert!((top - 300.0).abs() < 25.0, "cap top {top}");
        let s = shapes(&c);
        assert_eq!(s.len(), 2);
        assert_eq!(s.iter().map(|x| x.1.len()).sum::<usize>(), 1);
    }

    /// Lying text rises by its depth from the level; upright text stands as tall as its capitals.
    #[test]
    fn lying_and_upright_meshes() {
        if text_contours("A", 300.0, 0).is_empty() {
            return;
        }
        let mut p = crate::defaults::new_project(crate::units::UnitSystem::Metric);
        let l1 = p.levels()[0].0;
        let id = crate::edit::add_model_text(&mut p, l1, DVec2::ZERO, "A", 300.0, 50.0).unwrap();
        let crate::model::ElementKind::ModelText(t) = p.element(id).unwrap().kind.clone() else { panic!() };
        let (mn, mx) = mesh(&p, &t).bounds().unwrap();
        assert!((mn.z - 0.0).abs() < 1e-6 && (mx.z - 50.0).abs() < 1e-6);
        let up = ModelText { vertical: true, ..t };
        let (mn, mx) = mesh(&p, &up).bounds().unwrap();
        assert!(mn.z.abs() < 1.0 && (mx.z - 300.0).abs() < 25.0, "upright z {} {}", mn.z, mx.z);
        assert!((mn.y + 50.0).abs() < 1e-6, "extruded behind the text plane");
        p.elements.clear();
    }
}
