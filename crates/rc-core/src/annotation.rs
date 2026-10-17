//! Annotation logic: resolving dimension references, measuring, and tag text.

use crate::analysis;
use crate::geom::{self, DVec2};
use crate::model::*;
use crate::params;

/// A resolved reference: a point on it and, for linear references, its direction.
#[derive(Clone, Copy, Debug)]
pub struct Resolved {
    pub point: DVec2,
    pub dir: Option<DVec2>,
}

/// Lateral offset of a wall face from the wall centreline (+ = exterior/left side).
pub fn wall_face_offset(p: &Project, w: &Wall, exterior: bool) -> f64 {
    let t = analysis::wall_thickness(p, w) / 2.0;
    if exterior { t } else { -t }
}

pub fn resolve(p: &Project, r: &DimRef) -> Resolved {
    let fallback = Resolved { point: r.point, dir: None };
    let Some(e) = r.element.and_then(|id| p.element(id)) else { return fallback };
    let on_line = |a: DVec2, b: DVec2| {
        let d = (b - a).normalize_or_zero();
        let q = a + d * (r.point - a).dot(d);
        Resolved { point: q, dir: Some(d) }
    };
    if matches!(r.part, RefPart::ArcCenter | RefPart::ArcPoint | RefPart::ArcMid) {
        let Some(arc) = element_arc(e).and_then(|(a, m, b)| geom::Arc2::through(a, m, b).map(|arc| (arc, m))) else { return fallback };
        let (arc, m) = arc;
        return match r.part {
            RefPart::ArcCenter => Resolved { point: arc.center, dir: None },
            RefPart::ArcMid => Resolved { point: m, dir: None },
            _ => Resolved { point: arc.center + (r.point - arc.center).normalize_or(DVec2::X) * arc.radius, dir: None },
        };
    }
    match (&e.kind, &r.part) {
        (ElementKind::Wall(w), RefPart::WallCenter | RefPart::WallExterior | RefPart::WallInterior) => {
            let off = match r.part {
                RefPart::WallExterior => wall_face_offset(p, w, true),
                RefPart::WallInterior => wall_face_offset(p, w, false),
                _ => 0.0,
            };
            let n = w.normal() * off;
            on_line(w.start + n, w.end + n)
        }
        (ElementKind::Wall(w), RefPart::EndStart) => Resolved { point: w.start, dir: None },
        (ElementKind::Wall(w), RefPart::EndEnd) => Resolved { point: w.end, dir: None },
        (ElementKind::Grid(g), _) => on_line(g.start, g.end),
        (ElementKind::RefPlane(rp), _) => on_line(rp.start, rp.end),
        (ElementKind::Line(l), RefPart::EndStart) => Resolved { point: l.pts.first().copied().unwrap_or(r.point), dir: None },
        (ElementKind::Line(l), RefPart::EndEnd) => Resolved { point: l.pts.last().copied().unwrap_or(r.point), dir: None },
        (ElementKind::Line(l), _) if l.pts.len() >= 2 => on_line(l.pts[0], l.pts[1]),
        (ElementKind::Instance(i), _) => {
            let c = analysis::instance_location(p, i);
            let f = crate::build3d::instance_frame(p, i);
            // The instance's centre plane runs along its facing (y) direction.
            on_line(c, c + f.y)
        }
        _ => fallback,
    }
}

/// Start, mid and end of an arc-shaped element.
pub fn element_arc(e: &Element) -> Option<(DVec2, DVec2, DVec2)> {
    match &e.kind {
        ElementKind::Wall(w) => w.arc_mid.map(|m| (w.start, m, w.end)),
        ElementKind::Grid(g) => g.arc_mid.map(|m| (g.start, m, g.end)),
        ElementKind::Line(l) if l.pts.len() == 2 => l.arc_mid.map(|m| (l.pts[0], m, l.pts[1])),
        _ => None,
    }
}

/// Vertex and the two ray points of an angular dimension (the vertex follows the lines).
pub fn angular_points(p: &Project, d: &Dimension) -> Option<(DVec2, DVec2, DVec2)> {
    if d.refs.len() < 3 {
        return None;
    }
    let (ra, rv, rb) = (resolve(p, &d.refs[0]), resolve(p, &d.refs[1]), resolve(p, &d.refs[2]));
    let v = match (ra.dir, rb.dir) {
        (Some(da), Some(db)) => geom::line_intersection(ra.point, da, rb.point, db).unwrap_or(rv.point),
        _ => rv.point,
    };
    Some((ra.point, v, rb.point))
}

/// Coordinates of each reference along the dimension direction.
pub fn coordinates(p: &Project, d: &Dimension) -> Vec<f64> {
    d.refs.iter().map(|r| resolve(p, r).point.dot(d.direction)).collect()
}

/// Segment values (mm) of a linear/aligned dimension.
pub fn segments(p: &Project, d: &Dimension) -> Vec<f64> {
    let c = coordinates(p, d);
    c.windows(2).map(|w| (w[1] - w[0]).abs()).collect()
}

/// Text for one segment.
pub fn segment_text(p: &Project, d: &Dimension, value: f64) -> String {
    // Replace With Text keeps the prefix and suffix, as in the reference app.
    let core = if !d.text_override.is_empty() {
        d.text_override.clone()
    } else if d.equal {
        "EQ".to_string()
    } else {
        p.units.length(value)
    };
    format!("{}{}{}", d.prefix, core, d.suffix)
}

/// The default parameter shown by a tag for its host's category.
pub fn default_tag_parameter(c: Category) -> &'static str {
    match c {
        Category::Rooms | Category::Spaces => "Name",
        Category::Areas => "Name",
        Category::Walls | Category::Floors | Category::Roofs | Category::Ceilings => "Type Mark",
        _ => "Mark",
    }
}

/// Text a tag displays.
pub fn tag_text(p: &Project, t: &Tag) -> String {
    let Some(host) = p.element(t.host) else { return "?".into() };
    match t.parameter.as_str() {
        "Keynote" => return crate::keynote::display(p, &crate::keynote::element_keynote(p, host)),
        "Material Keynote" => return crate::keynote::display(p, &crate::keynote::material_keynote(p, host)),
        "User Keynote" => return crate::keynote::display(p, &t.key),
        _ => {}
    }
    let param = if t.parameter.is_empty() { default_tag_parameter(host.category()) } else { t.parameter.as_str() };
    let v = match params::get(p, host, param) {
        Some(params::Value::Text(s)) if !s.is_empty() => s,
        Some(params::Value::Num(x)) => p.units.length(x),
        _ if param == "Material" => element_material(p, host),
        _ => String::new(),
    };
    if matches!(host.category(), Category::Rooms | Category::Spaces) {
        let number = match params::get(p, host, "Number") {
            Some(params::Value::Text(s)) => s,
            _ => String::new(),
        };
        return format!("{v}\n{number}");
    }
    if v.is_empty() { "?".into() } else { v }
}

/// The main material of an element, as a material tag shows it: the structural layer of
/// layered types, else the first layer, else a family's material parameter.
pub fn element_material(p: &Project, e: &Element) -> String {
    if let Some(t) = p.type_of(e).and_then(|t| p.sys_type(t)) {
        let layer = t.layers.iter().find(|l| l.function == LayerFunction::Structure).or(t.layers.first());
        if let Some(l) = layer {
            return l.material.clone();
        }
    }
    if let ElementKind::Instance(i) = &e.kind {
        if let Some(f) = p.family(i.family_id) {
            for fp in f.params.iter().filter(|fp| fp.kind == ParamKind::Material) {
                if let Some(params::Value::Text(s)) = params::get(p, e, &fp.name) {
                    if !s.is_empty() {
                        return s;
                    }
                }
            }
        }
    }
    match &e.kind {
        ElementKind::Toposolid(t) if !t.material.is_empty() => t.material.clone(),
        ElementKind::Toposolid(_) => "Site - Earth".into(),
        _ => String::new(),
    }
}

/// Where a tag points (the host's location in plan).
pub fn host_point(p: &Project, host: &Element) -> DVec2 {
    match &host.kind {
        ElementKind::Wall(w) => (w.start + w.end) / 2.0,
        ElementKind::Instance(i) => analysis::instance_location(p, i),
        ElementKind::Room(r) => r.location,
        ElementKind::Area(a) => a.location,
        ElementKind::Floor(f) => geom::centroid(&f.boundary),
        ElementKind::Ceiling(c) => geom::centroid(&c.boundary),
        ElementKind::Roof(r) => geom::centroid(&r.footprint),
        ElementKind::Stair(s) => s.runs.first().map(|r| (r.start + r.end) / 2.0).unwrap_or_default(),
        ElementKind::Ramp(r) => r.runs.first().map(|q| (q.start + q.end) / 2.0).unwrap_or_default(),
        ElementKind::ModelText(t) => t.position,
        _ => DVec2::ZERO,
    }
}
