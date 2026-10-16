//! Model editing operations used by the UI tools. Call them inside `Document::transact`.

use crate::analysis;
use crate::annotation;
use crate::build3d;
use crate::defaults;
use crate::family_params::{self, Resolver};
use crate::geom::{self, DVec2, DVec3};
use crate::model::*;
use std::collections::{BTreeSet, HashMap, HashSet};

// ---------------------------------------------------------------- creation

fn push(p: &mut Project, kind: ElementKind) -> Id {
    let id = p.new_id();
    p.elements.push(Element::new(id, kind));
    id
}

fn push_in_view(p: &mut Project, view: Id, kind: ElementKind) -> Id {
    let id = p.new_id();
    p.elements.push(Element::new(id, kind).in_view(view));
    id
}

/// Default top constraint: the level above when the height matches the storey height.
fn top_for(p: &Project, level: Id, height: f64) -> Option<Id> {
    let top = p.level_above(level)?;
    let dh = top.1.elevation - p.level_elevation(level);
    ((dh - height).abs() < 1e-6).then_some(top.0)
}

pub fn add_wall(p: &mut Project, level: Id, type_id: Id, start: DVec2, end: DVec2, height: f64) -> Result<Id, String> {
    add_wall_ex(p, level, type_id, start, end, None, height, LocationLine::WallCenterline, false)
}

/// Adds a wall drawn along a location line (converted to the wall centreline), optionally curved.
#[allow(clippy::too_many_arguments)]
pub fn add_wall_ex(
    p: &mut Project,
    level: Id,
    type_id: Id,
    start: DVec2,
    end: DVec2,
    arc_mid: Option<DVec2>,
    height: f64,
    location: LocationLine,
    flip: bool,
) -> Result<Id, String> {
    if start.distance(end) < 10.0 {
        return Err("Wall is too short.".into());
    }
    if p.level(level).is_none() {
        return Err("Level not found.".into());
    }
    let t = p.sys_type(type_id).ok_or("Wall type not found.")?;
    // The drawn line is the location line; the centreline sits beside it.
    let off = analysis::location_line_offset(t, location) * if flip { -1.0 } else { 1.0 };
    let (start, end, arc_mid) = if off.abs() > 1e-9 {
        let n = geom::perp((end - start).normalize_or_zero());
        match arc_mid.and_then(|m| geom::Arc2::through(start, m, end)) {
            Some(a) => {
                // Offset an arc radially.
                let side = if a.sweep >= 0.0 { -1.0 } else { 1.0 };
                let r = a.radius + side * off;
                let q = |pt: DVec2| a.center + (pt - a.center).normalize() * r;
                (q(start), q(end), Some(q(a.mid())))
            }
            None => (start - n * off, end - n * off, None),
        }
    } else {
        (start, end, arc_mid)
    };
    let (start, end) = if flip { (end, start) } else { (start, end) };
    let top_level = top_for(p, level, height);
    Ok(push(
        p,
        ElementKind::Wall(Wall {
            start,
            end,
            type_id,
            base_level: level,
            top_level,
            unconnected_height: height,
            room_bounding: true,
            location_line: location,
            arc_mid,
            join_start: true,
            join_end: true,
            ..Default::default()
        }),
    ))
}

pub fn add_floor(p: &mut Project, level: Id, type_id: Id, boundary: Vec<DVec2>) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 1.0);
    if boundary.len() < 3 || geom::area(&boundary) < 1e4 {
        return Err("A floor boundary needs at least three points enclosing an area.".into());
    }
    Ok(push(p, ElementKind::Floor(Floor { boundary: geom::ensure_ccw(&boundary), level, type_id, room_bounding: true, ..Default::default() })))
}

pub fn add_ceiling(p: &mut Project, level: Id, type_id: Id, boundary: Vec<DVec2>, height: f64) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 1.0);
    if boundary.len() < 3 || geom::area(&boundary) < 1e4 {
        return Err("A ceiling boundary needs at least three points enclosing an area.".into());
    }
    Ok(push(p, ElementKind::Ceiling(Ceiling { boundary: geom::ensure_ccw(&boundary), holes: vec![], level, height_offset: height, type_id })))
}

pub fn add_roof(p: &mut Project, level: Id, type_id: Id, footprint: Vec<DVec2>, shape: RoofShape, base_offset: f64) -> Result<Id, String> {
    let footprint = geom::clean(&footprint, 1.0);
    if footprint.len() < 3 || geom::area(&footprint) < 1e4 {
        return Err("A roof footprint needs at least three points enclosing an area.".into());
    }
    Ok(push(
        p,
        ElementKind::Roof(Roof { footprint: geom::ensure_ccw(&footprint), level, base_offset, type_id, shape, slope_deg: 30.0, overhang: 500.0, ..Default::default() }),
    ))
}

/// Extrusion roof: a profile (lateral offset, height above the level) along `start`→`end`.
pub fn add_extrusion_roof(p: &mut Project, level: Id, type_id: Id, start: DVec2, end: DVec2, profile: Vec<DVec2>) -> Result<Id, String> {
    if profile.len() < 2 || start.distance(end) < 100.0 {
        return Err("An extrusion roof needs a profile and a length.".into());
    }
    let d = (end - start).normalize();
    let n = geom::perp(d);
    let (lo, hi) = profile.iter().fold((f64::MAX, f64::MIN), |(a, b), q| (a.min(q.x), b.max(q.x)));
    let footprint = vec![start + n * lo, end + n * lo, end + n * hi, start + n * hi];
    Ok(push(
        p,
        ElementKind::Roof(Roof {
            footprint,
            level,
            type_id,
            shape: RoofShape::Flat,
            slope_deg: 0.0,
            kind: RoofKind::Extrusion { start, end, profile },
            ..Default::default()
        }),
    ))
}

pub fn next_room_number(p: &Project) -> String {
    let max = p.elements.iter().filter_map(|e| e.as_room()).filter_map(|r| r.number.parse::<u32>().ok()).max().unwrap_or(0);
    (max + 1).to_string()
}

pub fn add_room(p: &mut Project, level: Id, at: DVec2) -> Result<Id, String> {
    let Some(target) = analysis::find_enclosure(p, level, at) else {
        return Err("The room is not in a properly enclosed region. Click inside an area bounded by walls or room separation lines.".into());
    };
    let same = |b: &analysis::RoomBoundary| {
        (geom::area(&b.centerline) - geom::area(&target.centerline)).abs() < 1.0
            && geom::centroid(&b.centerline).distance(geom::centroid(&target.centerline)) < 1.0
    };
    if p.elements.iter().filter_map(|e| e.as_room()).filter(|r| r.level == level).any(|r| analysis::room_boundary(p, r).is_some_and(|b| same(&b))) {
        return Err("There is already a room in this region.".into());
    }
    let number = next_room_number(p);
    Ok(push(p, ElementKind::Room(Room { name: "Room".into(), number, level, location: at, upper_offset: 2700.0, ..Default::default() })))
}

pub fn add_area(p: &mut Project, level: Id, scheme: Id, at: DVec2) -> Result<Id, String> {
    if analysis::area_regions(p, level, scheme).iter().all(|r| !geom::contains(&r.centerline, at)) {
        return Err("Areas must be placed inside a region enclosed by area boundary lines.".into());
    }
    let n = p.elements.iter().filter(|e| matches!(e.kind, ElementKind::Area(_))).count() + 1;
    Ok(push(p, ElementKind::Area(Area { name: "Area".into(), number: n.to_string(), level, scheme, location: at, area_type: "Floor Area".into() })))
}

pub fn add_separation(p: &mut Project, level: Id, start: DVec2, end: DVec2, area_scheme: Option<Id>) -> Result<Id, String> {
    if start.distance(end) < 10.0 {
        return Err("The line is too short.".into());
    }
    let s = Separation { level, start, end, scheme: area_scheme };
    Ok(push(p, if area_scheme.is_some() { ElementKind::AreaBoundary(s) } else { ElementKind::RoomSeparation(s) }))
}

pub fn add_grid(p: &mut Project, start: DVec2, end: DVec2) -> Result<Id, String> {
    add_grid_ex(p, start, end, None)
}

pub fn add_grid_ex(p: &mut Project, start: DVec2, end: DVec2, arc_mid: Option<DVec2>) -> Result<Id, String> {
    if start.distance(end) < 100.0 {
        return Err("Grid is too short.".into());
    }
    let names: BTreeSet<String> = p.elements.iter().filter_map(|e| match &e.kind {
        ElementKind::Grid(g) => Some(g.name.clone()),
        _ => None,
    }).collect();
    // Numbers for one direction, letters for the other (Revit's usual convention).
    let vertical = (end - start).normalize().y.abs() > 0.7;
    let name = if vertical {
        (1..).map(|n: u32| n.to_string()).find(|n| !names.contains(n)).unwrap()
    } else {
        (0..)
            .map(|k: u32| {
                let letter = (b'A' + (k % 26) as u8) as char;
                if k < 26 { letter.to_string() } else { format!("{letter}{}", k / 26) }
            })
            .find(|n| !names.contains(n))
            .unwrap()
    };
    // Like the reference app, a new grid shows its bubble at the end point only.
    Ok(push(p, ElementKind::Grid(Grid { name, start, end, arc_mid, bubble_start: false, bubble_end: true, vertices: vec![] })))
}

/// A multi-segment grid through `pts` (named by its first segment's direction).
pub fn add_grid_path(p: &mut Project, pts: Vec<DVec2>) -> Result<Id, String> {
    let mut v: Vec<DVec2> = Vec::new();
    for q in pts {
        if v.last().is_none_or(|l: &DVec2| l.distance(q) > 1.0) {
            v.push(q);
        }
    }
    if v.len() < 2 {
        return Err("Sketch the grid's segments as one connected chain.".into());
    }
    let length: f64 = v.windows(2).map(|w| w[0].distance(w[1])).sum();
    if length < 100.0 {
        return Err("Grid is too short.".into());
    }
    let n = v.len();
    let id = add_grid_ex(p, v[0], v[1] + (v[1] - v[0]).normalize_or_zero(), None)?;
    if let Some(ElementKind::Grid(g)) = p.element_mut(id).map(|e| &mut e.kind) {
        g.start = v[0];
        g.end = v[n - 1];
        g.vertices = v[1..n - 1].to_vec();
    }
    Ok(id)
}

pub fn add_ref_plane(p: &mut Project, start: DVec2, end: DVec2) -> Result<Id, String> {
    if start.distance(end) < 10.0 {
        return Err("Reference plane is too short.".into());
    }
    Ok(push(p, ElementKind::RefPlane(RefPlane { name: String::new(), start, end })))
}

pub fn add_level(p: &mut Project, name: &str, elevation: f64) -> Result<Id, String> {
    if p.levels().iter().any(|(_, l)| l.name == name) {
        return Err(format!("A level named '{name}' already exists."));
    }
    Ok(defaults::add_level(p, name, elevation, true))
}

/// Model lines (view None, on `level`) or detail lines (owned by `view`).
pub fn add_line(p: &mut Project, view: Option<Id>, level: Option<Id>, pts: Vec<DVec2>, arc_mid: Option<DVec2>, style: LineStyle) -> Result<Id, String> {
    if pts.len() < 2 || pts.windows(2).all(|w| w[0].distance(w[1]) < 1.0) {
        return Err("The line is too short.".into());
    }
    let kind = ElementKind::Line(LineElement { pts, closed: false, style, level, arc_mid });
    Ok(match view {
        Some(v) => push_in_view(p, v, kind),
        None => push(p, kind),
    })
}

pub fn add_region(p: &mut Project, view: Id, boundary: Vec<DVec2>, pattern: FillPattern) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 0.5);
    if boundary.len() < 3 {
        return Err("A region needs at least three points.".into());
    }
    Ok(push_in_view(p, view, ElementKind::Region(FilledRegion { boundary, holes: vec![], pattern, color: [0, 0, 0], boundary_style: LineStyle::Thin })))
}

pub fn add_text(p: &mut Project, view: Id, at: DVec2, text: &str, size: f64) -> Result<Id, String> {
    if text.trim().is_empty() {
        return Err("The text is empty.".into());
    }
    Ok(push_in_view(p, view, ElementKind::Text(TextNote { position: at, text: text.into(), size, ..Default::default() })))
}

pub fn add_tag(p: &mut Project, view: Id, host: Id, at: DVec2, leader: bool) -> Result<Id, String> {
    if p.element(host).is_none() {
        return Err("Nothing to tag.".into());
    }
    Ok(push_in_view(p, view, ElementKind::Tag(Tag { host, position: at, leader, leader_end: None, parameter: String::new(), vertical: false, key: String::new() })))
}

/// Tags every untagged element of the given categories visible in a plan view.
pub fn tag_all(p: &mut Project, view: Id, categories: &[Category]) -> Result<usize, String> {
    let v = p.view(view).ok_or("View not found.")?.clone();
    let tagged: HashSet<Id> = p.elements.iter().filter(|e| e.view == Some(view)).filter_map(|e| match &e.kind {
        ElementKind::Tag(t) => Some(t.host),
        _ => None,
    }).collect();
    let targets: Vec<(Id, DVec2, bool)> = p
        .elements
        .iter()
        .filter(|e| categories.contains(&e.category()) && !tagged.contains(&e.id) && crate::plan::in_plan(p, &v, e))
        .map(|e| {
            let pt = annotation::host_point(p, e);
            let offset = match &e.kind {
                ElementKind::Instance(i) if i.host.is_some() => {
                    let f = crate::family_geom::instance_frame(p, i);
                    f.y * (f.depth / 2.0 + 4.0 * v.scale)
                }
                ElementKind::Wall(w) => w.normal() * (analysis::wall_thickness(p, w) / 2.0 + 4.0 * v.scale),
                _ => DVec2::ZERO,
            };
            (e.id, pt + offset, false)
        })
        .collect();
    let n = targets.len();
    for (host, at, leader) in targets {
        add_tag(p, view, host, at, leader)?;
    }
    Ok(n)
}

pub fn add_mass(p: &mut Project, level: Id, boundary: Vec<DVec2>, height: f64) -> Result<Id, String> {
    if boundary.len() < 3 || geom::area(&boundary).abs() < 1.0 {
        return Err("The mass needs a closed boundary.".into());
    }
    if height <= 0.0 {
        return Err("The mass height must be positive.".into());
    }
    let n = p.elements.iter().filter(|e| matches!(e.kind, ElementKind::Mass(_))).count() + 1;
    Ok(push(p, ElementKind::Mass(Mass { level, boundary: geom::ensure_ccw(&boundary), height, base_offset: 0.0, name: format!("Mass {n}") })))
}

pub fn add_toposolid(p: &mut Project, level: Id, boundary: Vec<DVec2>, height: f64, thickness: f64) -> Result<Id, String> {
    if boundary.len() < 3 || geom::area(&boundary).abs() < 1.0 {
        return Err("The toposolid needs a closed boundary.".into());
    }
    let boundary = geom::ensure_ccw(&boundary);
    let heights = vec![height; boundary.len()];
    Ok(push(p, ElementKind::Toposolid(Toposolid { level, boundary, heights, thickness, material: String::new(), points: vec![], host: None })))
}

/// Sets the height (above its level) of a toposolid point: boundary points first, then the
/// interior points (index boundary.len() + k).
pub fn set_topo_point(p: &mut Project, id: Id, index: usize, height: f64) -> Result<(), String> {
    match p.element_mut(id).map(|e| &mut e.kind) {
        Some(ElementKind::Toposolid(t)) if index < t.heights.len() => {
            t.heights[index] = height;
            Ok(())
        }
        Some(ElementKind::Toposolid(t)) if index - t.heights.len() < t.points.len() => {
            let k = index - t.heights.len();
            t.points[k].1 = height;
            Ok(())
        }
        _ => Err("Pick a point of a toposolid.".into()),
    }
}

/// Adds an elevation point inside a toposolid.
pub fn add_topo_point(p: &mut Project, id: Id, at: DVec2, height: f64) -> Result<(), String> {
    match p.element_mut(id).map(|e| &mut e.kind) {
        Some(ElementKind::Toposolid(t)) => {
            if !geom::contains(&t.boundary, at) {
                return Err("Points must be inside the toposolid boundary.".into());
            }
            if t.points.iter().any(|(q, _)| q.distance(at) < 10.0) || t.boundary.iter().any(|q| q.distance(at) < 10.0) {
                return Err("There is already a point here.".into());
            }
            t.points.push((at, height));
            Ok(())
        }
        _ => Err("Click inside a toposolid.".into()),
    }
}

/// Removes an interior point (index as in `set_topo_point`); boundary points stay.
pub fn remove_topo_point(p: &mut Project, id: Id, index: usize) -> Result<(), String> {
    match p.element_mut(id).map(|e| &mut e.kind) {
        Some(ElementKind::Toposolid(t)) if index >= t.heights.len() && index - t.heights.len() < t.points.len() => {
            let k = index - t.heights.len();
            t.points.remove(k);
            Ok(())
        }
        _ => Err("Only interior points can be deleted; boundary points shape the toposolid.".into()),
    }
}

pub fn add_property_line(p: &mut Project, level: Id, boundary: Vec<DVec2>) -> Result<Id, String> {
    if boundary.len() < 3 {
        return Err("A property line needs at least three points.".into());
    }
    let n = p.elements.iter().filter(|e| matches!(e.kind, ElementKind::PropertyLine(_))).count() + 1;
    Ok(push(p, ElementKind::PropertyLine(PropertyLine { level, boundary: geom::ensure_ccw(&boundary), name: format!("Property Line {n}") })))
}

pub fn add_color_legend(p: &mut Project, view: Id, at: DVec2) -> Id {
    push_in_view(p, view, ElementKind::ColorLegend(ColorLegend { position: at }))
}

/// Model by Face: elements made from a mass's faces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ByFace {
    Walls,
    CurtainSystem,
    Floors,
    Roof,
}

pub fn model_by_face(p: &mut Project, mass: Id, what: ByFace, type_id: Id) -> Result<Vec<Id>, String> {
    let Some(ElementKind::Mass(m)) = p.element(mass).map(|e| e.kind.clone()) else { return Err("Select a mass.".into()) };
    let z0 = p.level_elevation(m.level) + m.base_offset;
    let z1 = z0 + m.height;
    let ring = geom::ensure_ccw(&m.boundary);
    let n = ring.len();
    let mut out = Vec::new();
    match what {
        ByFace::Walls | ByFace::CurtainSystem => {
            // The exterior finish face lies on the mass face: centrelines run on the outline
            // inset by half the wall thickness (so the corners still join), clockwise so the
            // exterior side faces out.
            let half = p.sys_type(type_id).map(|t| t.thickness()).unwrap_or(200.0) / 2.0;
            let mut centre = geom::offset(&ring, -half);
            if centre.len() != n {
                centre = ring.clone();
            }
            centre.reverse();
            for k in 0..n {
                let id = add_wall(p, m.level, type_id, centre[k], centre[(k + 1) % n], m.height)?;
                if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
                    w.base_offset = m.base_offset;
                    w.top_level = None;
                    w.unconnected_height = m.height;
                    w.location_line = LocationLine::FinishFaceExterior;
                }
                out.push(id);
            }
        }
        ByFace::Floors => {
            let levels: Vec<Id> = p.levels().into_iter().filter(|(_, l)| l.elevation >= z0 - 1.0 && l.elevation < z1 - 1.0).map(|(id, _)| id).collect();
            if levels.is_empty() {
                return Err("No level cuts the mass. Floors by face need mass floors at levels.".into());
            }
            for lv in levels {
                out.push(add_floor(p, lv, type_id, ring.clone())?);
            }
        }
        ByFace::Roof => {
            let top = p.levels().into_iter().min_by(|a, b| (a.1.elevation - z1).abs().total_cmp(&(b.1.elevation - z1).abs())).map(|(id, _)| id).unwrap_or(m.level);
            let id = add_roof(p, top, type_id, ring.clone(), RoofShape::Flat, 0.0)?;
            let base = z1 - p.level_elevation(top);
            if let Some(ElementKind::Roof(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                r.base_offset = base;
            }
            out.push(id);
        }
    }
    Ok(out)
}

pub fn add_symbol(p: &mut Project, view: Id, kind: SymbolKind, at: DVec2) -> Id {
    push_in_view(p, view, ElementKind::Symbol(Symbol { kind, position: at, rotation_deg: 0.0, points: vec![], value: String::new(), size: 0.0 }))
}

/// Batt insulation between two points in a view.
pub fn add_insulation(p: &mut Project, view: Id, a: DVec2, b: DVec2, width: f64) -> Result<Id, String> {
    if a.distance(b) < 1.0 {
        return Err("The insulation is too short.".into());
    }
    let id = add_symbol(p, view, SymbolKind::Insulation, (a + b) / 2.0);
    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
        s.points = vec![a, b];
        s.size = width.max(1.0);
    }
    Ok(id)
}

/// A repeating detail component along a path.
pub fn add_repeating_detail(p: &mut Project, view: Id, a: DVec2, b: DVec2, kind: &str) -> Result<Id, String> {
    if !REPEATING_DETAILS.iter().any(|r| r.0 == kind) {
        return Err(format!("Unknown repeating detail '{kind}'."));
    }
    if a.distance(b) < 1.0 {
        return Err("The repeating detail is too short.".into());
    }
    let id = add_symbol(p, view, SymbolKind::RepeatingDetail, (a + b) / 2.0);
    if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
        s.points = vec![a, b];
        s.value = kind.to_string();
    }
    Ok(id)
}

/// A scope box from two opposite corners.
pub fn add_scope_box(p: &mut Project, a: DVec2, b: DVec2) -> Result<Id, String> {
    if (a.x - b.x).abs() < 1.0 || (a.y - b.y).abs() < 1.0 {
        return Err("The scope box must have an area.".into());
    }
    let names = p.elements.iter().filter_map(|e| match &e.kind {
        ElementKind::ScopeBox(s) => Some(s.name.clone()),
        _ => None,
    });
    let name = unique_name(names, "Scope Box 1");
    let height = p.levels().iter().map(|(_, l)| l.elevation).fold(0.0, f64::max) + 4000.0;
    Ok(push(p, ElementKind::ScopeBox(ScopeBox { name, min: a.min(b), max: a.max(b), height })))
}

/// A matchline between two points (shown in every plan).
pub fn add_matchline(p: &mut Project, a: DVec2, b: DVec2) -> Result<Id, String> {
    if a.distance(b) < 1.0 {
        return Err("The matchline is too short.".into());
    }
    Ok(push(p, ElementKind::Matchline(Matchline { start: a, end: b })))
}

/// Paints the face of an element lying on the plane (normal, point) with a material.
pub fn paint_face(p: &mut Project, id: Id, normal: DVec3, point: DVec3, material: &str) -> Result<(), String> {
    if p.material(material).is_none() {
        return Err("Pick a material to paint with.".into());
    }
    let n = normal.normalize_or_zero();
    if n == DVec3::ZERO {
        return Err("No face here.".into());
    }
    let offset = n.dot(point);
    let e = p.element_mut(id).ok_or("Element not found.")?;
    e.painted.retain(|f| !same_face(f, n, offset));
    e.painted.push(PaintedFace { normal: n.to_array(), offset, material: material.to_string() });
    Ok(())
}

/// Removes the paint from a face.
pub fn remove_paint(p: &mut Project, id: Id, normal: DVec3, point: DVec3) -> Result<(), String> {
    let n = normal.normalize_or_zero();
    let offset = n.dot(point);
    let e = p.element_mut(id).ok_or("Element not found.")?;
    let before = e.painted.len();
    e.painted.retain(|f| !same_face(f, n, offset));
    if e.painted.len() == before {
        return Err("This face is not painted.".into());
    }
    Ok(())
}

/// Does a painted face lie on the plane with this normal (either direction) and offset?
pub fn same_face(f: &PaintedFace, n: DVec3, offset: f64) -> bool {
    let fnm = DVec3::from_array(f.normal);
    let dot = fnm.dot(n);
    (dot > 0.999 && (f.offset - offset).abs() < 1.0) || (dot < -0.999 && (f.offset + offset).abs() < 1.0)
}

/// Joins the geometry of two model elements (Modify > Join Geometry).
pub fn join_geometry(p: &mut Project, a: Id, b: Id) -> Result<(), String> {
    if a == b {
        return Err("Pick two different elements.".into());
    }
    for id in [a, b] {
        let e = p.element(id).ok_or("Element not found.")?;
        if e.view.is_some() || e.category().is_annotation() {
            return Err("Only model elements can be joined.".into());
        }
    }
    if p.joins.iter().any(|j| (j.0 == a && j.1 == b) || (j.0 == b && j.1 == a)) {
        return Err("These elements are already joined.".into());
    }
    p.joins.push((a, b));
    Ok(())
}

/// Removes the join between two elements.
pub fn unjoin_geometry(p: &mut Project, a: Id, b: Id) -> Result<(), String> {
    let n = p.joins.len();
    p.joins.retain(|j| !((j.0 == a && j.1 == b) || (j.0 == b && j.1 == a)));
    if p.joins.len() == n {
        return Err("These elements are not joined.".into());
    }
    Ok(())
}

/// Housekeeping after every edit: scope box crops, joins of deleted elements.
pub fn tidy(p: &mut Project) {
    sync_scope_boxes(p);
    if !p.joins.is_empty() {
        let ids: std::collections::HashSet<Id> = p.elements.iter().map(|e| e.id).collect();
        p.joins.retain(|j| ids.contains(&j.0) && ids.contains(&j.1));
    }
}

/// Views assigned to a scope box take its extents as their crop region.
pub fn sync_scope_boxes(p: &mut Project) {
    if !p.views.iter().any(|v| v.scope_box.is_some()) {
        return;
    }
    let boxes: Vec<(Id, DVec2, DVec2)> = p
        .elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::ScopeBox(s) => Some((e.id, s.min, s.max)),
            _ => None,
        })
        .collect();
    for v in p.views.iter_mut() {
        let Some(id) = v.scope_box else { continue };
        match boxes.iter().find(|b| b.0 == id) {
            Some((_, a, b)) => {
                v.crop = Some((*a, *b));
                v.crop_active = true;
            }
            None => v.scope_box = None,
        }
    }
}

pub fn add_dimension(p: &mut Project, view: Id, refs: Vec<DimRef>, direction: DVec2, line_point: DVec2) -> Result<Id, String> {
    if refs.len() < 2 {
        return Err("A dimension needs at least two references.".into());
    }
    let dir = direction.normalize_or_zero();
    if dir == DVec2::ZERO {
        return Err("The dimension direction is undefined.".into());
    }
    let style = p.dim_styles.first().map(|s| s.id);
    let n = refs.len() - 1;
    Ok(push_in_view(
        p,
        view,
        ElementKind::Dimension(Dimension {
            kind: DimKind::Aligned,
            refs,
            direction: dir,
            line_point,
            locks: vec![false; n],
            equal: false,
            text_override: String::new(),
            prefix: String::new(),
            suffix: String::new(),
            label: String::new(),
            style,
            alignment: false,
        }),
    ))
}

/// Places a door or window in a wall; `along` is the distance from the wall start to the centre.
pub fn place_hosted(p: &mut Project, type_id: Id, wall_id: Id, along: f64, flip_facing: bool) -> Result<Id, String> {
    let (family, _) = p.family_type(type_id).ok_or("Family type not found.")?;
    if !family.is_hosted() {
        return Err("This family is not wall-hosted.".into());
    }
    let (family_id, category) = (family.id, family.category);
    let wall = p.wall(wall_id).ok_or("Host wall not found.")?.clone();
    if analysis::is_curtain(p, &wall) {
        return Err("Doors and windows cannot be hosted in curtain walls. Change a curtain panel to a door instead.".into());
    }
    let level = wall.base_level;
    let probe = FamilyInstance { family_id, type_id, category, level, host: Some(wall_id), offset_along_host: along, flip_facing, ..Default::default() };
    let (ow, oh) = analysis::opening_size(p, &probe);
    let sill = if category == Category::Windows {
        Resolver::for_instance(p, &probe).map(|r| r.num("Default Sill Height", 900.0)).unwrap_or(900.0)
    } else {
        0.0
    };
    check_opening_fits(p, &wall, wall_id, None, along, ow, sill, oh)?;
    let id = push(p, ElementKind::Instance(FamilyInstance { elevation: sill, ..probe }));
    if matches!(category, Category::Doors | Category::Windows) {
        let mark = next_mark(p, category);
        if let Some(e) = p.element_mut(id) {
            e.mark = mark;
        }
    }
    Ok(id)
}

/// The next door or window Mark: one more than the highest numeric Mark in the category
/// (doors and windows count separately).
pub fn next_mark(p: &Project, cat: Category) -> String {
    let max = p.elements.iter().filter(|e| e.category() == cat).filter_map(|e| e.mark.trim().parse::<u64>().ok()).max().unwrap_or(0);
    (max + 1).to_string()
}

/// Rejects openings that leave the wall or overlap other openings.
#[allow(clippy::too_many_arguments)]
pub fn check_opening_fits(p: &Project, wall: &Wall, wall_id: Id, ignore: Option<Id>, along: f64, ow: f64, sill: f64, oh: f64) -> Result<(), String> {
    if along - ow / 2.0 < -1e-6 || along + ow / 2.0 > wall.length() + 1e-6 {
        return Err("The opening does not fit in the wall.".into());
    }
    let base = analysis::wall_base_z(p, wall) - p.level_elevation(wall.base_level);
    let top = analysis::wall_top_z(p, wall) - p.level_elevation(wall.base_level);
    if sill < base - 1e-6 || sill + oh > top + 1e-6 {
        return Err("The opening is taller than the wall.".into());
    }
    for (e, other) in p.hosted_by(wall_id) {
        if Some(e.id) == ignore {
            continue;
        }
        let (w2, h2) = analysis::opening_size(p, other);
        let overlap_u = (along - other.offset_along_host).abs() < (ow + w2) / 2.0 - 1e-6;
        let overlap_z = sill < other.elevation + h2 - 1e-6 && other.elevation < sill + oh - 1e-6;
        if overlap_u && overlap_z {
            return Err("The opening overlaps another door or window.".into());
        }
    }
    Ok(())
}

pub fn add_wall_opening(p: &mut Project, wall_id: Id, u0: f64, u1: f64, z0: f64, z1: f64) -> Result<(), String> {
    let w = p.wall(wall_id).ok_or("Wall not found.")?;
    let (u0, u1) = (u0.min(u1).max(0.0), u0.max(u1).min(w.length()));
    if u1 - u0 < 10.0 || z1 - z0 < 10.0 {
        return Err("The opening is too small.".into());
    }
    p.element_mut(wall_id).and_then(Element::as_wall_mut).unwrap().openings.push(WallOpening { u0, u1, z0, z1 });
    Ok(())
}

pub fn place_free(p: &mut Project, type_id: Id, level: Id, at: DVec2, rotation_deg: f64) -> Result<Id, String> {
    let (family, _) = p.family_type(type_id).ok_or("Family type not found.")?;
    if family.is_hosted() {
        return Err("Doors and windows must be placed in a wall.".into());
    }
    let column = family.is_column();
    let inst = FamilyInstance {
        family_id: family.id,
        type_id,
        category: family.category,
        level,
        location: at,
        rotation_deg,
        top_level: if column { p.level_above(level).map(|l| l.0) } else { None },
        ..Default::default()
    };
    Ok(push(p, ElementKind::Instance(inst)))
}

/// Places columns at every grid intersection inside the given rectangle ("At Grids").
pub fn columns_at_grids(p: &mut Project, type_id: Id, level: Id, grid_ids: &[Id]) -> Result<Vec<Id>, String> {
    let grids: Vec<Grid> = grid_ids.iter().filter_map(|id| match p.element(*id).map(|e| &e.kind) {
        Some(ElementKind::Grid(g)) => Some(g.clone()),
        _ => None,
    }).collect();
    let mut pts = Vec::new();
    for i in 0..grids.len() {
        for j in i + 1..grids.len() {
            if let Some((t, _)) = geom::segment_intersection(grids[i].start, grids[i].end, grids[j].start, grids[j].end) {
                let q = grids[i].start.lerp(grids[i].end, t);
                if !pts.iter().any(|x: &DVec2| x.distance(q) < 1.0) {
                    pts.push(q);
                }
            }
        }
    }
    if pts.is_empty() {
        return Err("Select at least two intersecting grids.".into());
    }
    let mut out = Vec::new();
    for q in pts {
        let id = place_free(p, type_id, level, q, 0.0)?;
        if let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) {
            i.moves_with_grids = true;
        }
        out.push(id);
    }
    Ok(out)
}

/// Places a beam (structural framing) between two points at the level (top of beam).
pub fn add_beam(p: &mut Project, type_id: Id, level: Id, start: DVec2, end: DVec2) -> Result<Id, String> {
    let (family, _) = p.family_type(type_id).ok_or("Family type not found.")?;
    if !family.is_framing() {
        return Err("Pick a structural framing type.".into());
    }
    if start.distance(end) < 100.0 {
        return Err("The beam is too short.".into());
    }
    let inst = FamilyInstance { family_id: family.id, type_id, category: family.category, level, location: start, end: Some(end), ..Default::default() };
    Ok(push(p, ElementKind::Instance(inst)))
}

/// Creates a stair from runs, with railings on both sides when requested.
pub fn add_stair(p: &mut Project, base_level: Id, type_id: Id, runs: Vec<StairRun>, railing_type: Option<Id>) -> Result<Id, String> {
    if runs.is_empty() || runs.iter().any(|r| r.start.distance(r.end) < 100.0) {
        return Err("A stair run needs at least two risers.".into());
    }
    let top_level = p.level_above(base_level).map(|l| l.0);
    let id = push(
        p,
        ElementKind::Stair(Stair { base_level, top_level, unconnected_height: 3000.0, runs: runs.clone(), type_id, railings: railing_type.is_some(), ..Default::default() }),
    );
    if let Some(rt) = railing_type {
        let lay = build3d::stair_layout(p, p.element(id).and_then(|e| match &e.kind {
            ElementKind::Stair(s) => Some(s),
            _ => None,
        }).unwrap());
        let _ = lay;
        for side in [-1.0, 1.0] {
            let mut path = Vec::new();
            for r in &runs {
                let n = geom::perp((r.end - r.start).normalize_or_zero()) * (r.width / 2.0 - 50.0) * side;
                path.push(r.start + n);
                path.push(r.end + n);
            }
            let rid = push(p, ElementKind::Railing(Railing { path, level: base_level, base_offset: 0.0, type_id: rt, host: Some(id) }));
            let _ = rid;
        }
    }
    Ok(id)
}

/// Rooms in every enclosed region of a level that has none (Place Rooms Automatically).
pub fn place_rooms_automatically(p: &mut Project, level: Id) -> Vec<Id> {
    let regions = analysis::enclosed_regions(p, level);
    let taken: Vec<DVec2> = p.elements.iter().filter_map(|e| match &e.kind {
        ElementKind::Room(r) if r.level == level => Some(r.location),
        _ => None,
    }).collect();
    let mut out = Vec::new();
    for reg in regions {
        if taken.iter().any(|q| geom::contains(&reg.centerline, *q)) {
            continue;
        }
        // A point inside: the centroid, or the centre of the largest triangle for odd shapes.
        let c = geom::centroid(&reg.interior);
        let at = if geom::contains(&reg.interior, c) {
            c
        } else {
            let poly = &reg.interior;
            geom::triangulate(poly)
                .into_iter()
                .max_by(|a, b| tri_area(poly, *a).total_cmp(&tri_area(poly, *b)))
                .map(|[a, b, k]| (poly[a] + poly[b] + poly[k]) / 3.0)
                .unwrap_or(c)
        };
        if let Ok(id) = add_room(p, level, at) {
            out.push(id);
        }
    }
    out
}

fn tri_area(poly: &[DVec2], [a, b, c]: [usize; 3]) -> f64 {
    geom::cross2(poly[b] - poly[a], poly[c] - poly[a]).abs() / 2.0
}

/// Places Model Text lying on `level` at `at`.
pub fn add_model_text(p: &mut Project, level: Id, at: DVec2, text: &str, size: f64, depth: f64) -> Result<Id, String> {
    if text.trim().is_empty() {
        return Err("Type the text to place.".into());
    }
    Ok(push(p, ElementKind::ModelText(ModelText { level, position: at, elevation: 0.0, rotation_deg: 0.0, text: text.to_string(), size, depth, align: 0, material: String::new(), vertical: false })))
}

/// Creates a ramp from its runs (from the base level to the level above), with railings along
/// both sides when requested.
pub fn add_ramp(p: &mut Project, base_level: Id, type_id: Id, runs: Vec<StairRun>, railing_type: Option<Id>) -> Result<Id, String> {
    if runs.is_empty() || runs.iter().any(|r| r.start.distance(r.end) < 100.0) {
        return Err("Draw at least one ramp run.".into());
    }
    let top_level = p.level_above(base_level).map(|l| l.0);
    let id = push(p, ElementKind::Ramp(Ramp { base_level, top_level, runs: runs.clone(), type_id, ..Default::default() }));
    if let Some(rt) = railing_type {
        for side in [-1.0, 1.0] {
            let mut path = Vec::new();
            for r in &runs {
                let n = geom::perp((r.end - r.start).normalize_or_zero()) * (r.width / 2.0 - 50.0) * side;
                path.push(r.start + n);
                path.push(r.end + n);
            }
            push(p, ElementKind::Railing(Railing { path, level: base_level, base_offset: 0.0, type_id: rt, host: Some(id) }));
        }
    }
    Ok(id)
}

pub fn add_railing(p: &mut Project, level: Id, type_id: Id, path: Vec<DVec2>) -> Result<Id, String> {
    if path.len() < 2 {
        return Err("A railing needs a path of at least two points.".into());
    }
    Ok(push(p, ElementKind::Railing(Railing { path, level, base_offset: 0.0, type_id, host: None })))
}

pub fn add_shaft(p: &mut Project, base_level: Id, boundary: Vec<DVec2>) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 1.0);
    if boundary.len() < 3 {
        return Err("A shaft needs a closed boundary.".into());
    }
    let top_level = p.levels().last().map(|l| l.0).filter(|t| *t != base_level);
    Ok(push(p, ElementKind::Shaft(Shaft { boundary: geom::ensure_ccw(&boundary), base_level, top_level, top_offset: 0.0, base_offset: 0.0, unconnected_height: 3000.0, host: None })))
}

/// Adds (`on`) or removes mullions on curtain grid segments of a curtain wall, fixing its grid.
pub fn set_mullions(p: &mut Project, wall: Id, keys: &[String], on: bool) -> Result<usize, String> {
    let w = p.wall(wall).cloned().ok_or("Pick a curtain wall.")?;
    if !analysis::is_curtain(p, &w) {
        return Err("Mullions go on curtain walls.".into());
    }
    let (_, _, auto) = build3d::mullion_spec(p, p.sys_type(w.type_id));
    let (gu, gv) = build3d::curtain_grid(p, &w);
    let wall_mut = p.element_mut(wall).and_then(Element::as_wall_mut).ok_or("Wall not found.")?;
    let inner = |v: &[f64]| v[1..v.len() - 1].to_vec();
    let grid = wall_mut.curtain.get_or_insert_with(|| CurtainGrid { u: inner(&gu), v: inner(&gv), ..Default::default() });
    let mut n = 0;
    for k in keys {
        let was = grid.mullions.get(k).copied().unwrap_or(auto);
        if was != on {
            n += 1;
        }
        if on == auto {
            grid.mullions.remove(k);
        } else {
            grid.mullions.insert(k.clone(), on);
        }
    }
    Ok(n)
}

/// A toposolid subdivision: a region of `host`'s surface with its own material.
pub fn add_subdivision(p: &mut Project, host: Id, boundary: Vec<DVec2>, material: &str) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 1.0);
    if boundary.len() < 3 {
        return Err("A subdivision needs a closed boundary.".into());
    }
    let Some(ElementKind::Toposolid(h)) = p.element(host).map(|e| &e.kind) else { return Err("Select a toposolid to subdivide.".into()) };
    if h.host.is_some() {
        return Err("A subdivision cannot be subdivided; subdivide the toposolid.".into());
    }
    let level = h.level;
    Ok(push(p, ElementKind::Toposolid(Toposolid { level, boundary: geom::ensure_ccw(&boundary), heights: Vec::new(), thickness: 0.0, material: material.to_string(), points: Vec::new(), host: Some(host) })))
}

/// A vertical opening: cuts only `host` (a floor, roof or ceiling), through its whole depth.
pub fn add_vertical_opening(p: &mut Project, host: Id, boundary: Vec<DVec2>) -> Result<Id, String> {
    let boundary = geom::clean(&boundary, 1.0);
    if boundary.len() < 3 {
        return Err("An opening needs a closed boundary.".into());
    }
    let e = p.element(host).ok_or("The host was not found.")?;
    if !matches!(e.kind, ElementKind::Floor(_) | ElementKind::Roof(_) | ElementKind::Ceiling(_)) {
        return Err("Vertical openings cut floors, roofs and ceilings.".into());
    }
    let base_level = e.level().unwrap_or(0);
    Ok(push(p, ElementKind::Shaft(Shaft { boundary: geom::ensure_ccw(&boundary), base_level, top_level: None, top_offset: 0.0, base_offset: 0.0, unconnected_height: 0.0, host: Some(host) })))
}

pub fn add_wall_foundation(p: &mut Project, wall: Id, type_id: Id) -> Result<Id, String> {
    if p.wall(wall).is_none() {
        return Err("Pick a wall.".into());
    }
    if p.elements.iter().any(|e| matches!(&e.kind, ElementKind::WallFoundation(f) if f.wall == wall)) {
        return Err("The wall already has a foundation.".into());
    }
    Ok(push(p, ElementKind::WallFoundation(WallFoundation { wall, type_id })))
}

// ---------------------------------------------------------------- delete

/// Deletes elements and everything that depends on them. Returns the number removed.
pub fn delete_elements(p: &mut Project, ids: &[Id]) -> Result<usize, String> {
    if let Some(e) = ids.iter().filter_map(|id| p.element(*id)).find(|e| e.pinned) {
        return Err(format!("{} is pinned. Unpin it before deleting.", p.display_name(e)));
    }
    let mut doomed: HashSet<Id> = ids.iter().copied().collect();
    if p.levels().iter().filter(|(id, _)| !doomed.contains(id)).count() == 0 {
        return Err("A project must have at least one level.".into());
    }
    loop {
        let before = doomed.len();
        for e in &p.elements {
            let depends = match &e.kind {
                ElementKind::Instance(i) => i.host.is_some_and(|h| doomed.contains(&h)) || doomed.contains(&i.level),
                ElementKind::Wall(w) => doomed.contains(&w.base_level),
                ElementKind::Tag(t) => doomed.contains(&t.host),
                ElementKind::WallFoundation(f) => doomed.contains(&f.wall),
                ElementKind::Railing(r) => r.host.is_some_and(|h| doomed.contains(&h)) || doomed.contains(&r.level),
                ElementKind::Shaft(s) => s.host.is_some_and(|h| doomed.contains(&h)) || doomed.contains(&s.base_level),
                ElementKind::Toposolid(t) => t.host.is_some_and(|h| doomed.contains(&h)) || doomed.contains(&t.level),
                _ => e.level().is_some_and(|l| doomed.contains(&l)),
            } || e.group.is_some_and(|g| doomed.contains(&g))
                || e.view.is_some_and(|v| !p.views.iter().any(|x| x.id == v));
            if depends {
                doomed.insert(e.id);
            }
        }
        if doomed.len() == before {
            break;
        }
    }
    // Elements whose top constraint level disappears become unconnected at their current height.
    let heights: Vec<(Id, f64)> = p
        .walls()
        .filter(|(e, w)| !doomed.contains(&e.id) && w.top_level.is_some_and(|t| doomed.contains(&t)))
        .map(|(e, w)| (e.id, analysis::wall_height(p, w)))
        .collect();
    for (id, h) in heights {
        if let Some(w) = p.element_mut(id).and_then(Element::as_wall_mut) {
            w.top_level = None;
            w.unconnected_height = h;
        }
    }
    for e in &mut p.elements {
        match &mut e.kind {
            ElementKind::Wall(w) => {
                if w.attach_top.is_some_and(|a| doomed.contains(&a)) {
                    w.attach_top = None;
                }
                if w.attach_base.is_some_and(|a| doomed.contains(&a)) {
                    w.attach_base = None;
                }
            }
            ElementKind::Instance(i) if i.top_level.is_some_and(|t| doomed.contains(&t)) => i.top_level = None,
            ElementKind::Stair(s) if s.top_level.is_some_and(|t| doomed.contains(&t)) => s.top_level = None,
            ElementKind::Ramp(r) if r.top_level.is_some_and(|t| doomed.contains(&t)) => r.top_level = None,
            ElementKind::Shaft(s) if s.top_level.is_some_and(|t| doomed.contains(&t)) => s.top_level = None,
            _ => {}
        }
    }
    let before = p.elements.len();
    p.elements.retain(|e| !doomed.contains(&e.id));
    let dead_views: Vec<Id> = p.views.iter().filter(|v| v.plan_level().is_some_and(|l| doomed.contains(&l)) && !v.is_template).map(|v| v.id).collect();
    for v in dead_views {
        delete_view(p, v)?;
    }
    Ok(before - p.elements.len())
}

// ---------------------------------------------------------------- transforms

/// Applies a plan transform to an element's geometry. `rot` is the rotation in degrees applied to
/// oriented things; `mirror` marks reflections (walls swap ends to keep their exterior outside).
fn transform_element(e: &mut Element, f: &dyn Fn(DVec2) -> DVec2, rot: f64, mirror: bool) {
    let vec = |d: DVec2| (f(d) - f(DVec2::ZERO)).normalize_or_zero();
    let poly = |v: &mut Vec<DVec2>| v.iter_mut().for_each(|q| *q = f(*q));
    match &mut e.kind {
        ElementKind::Wall(w) => {
            let (s, t) = (f(w.start), f(w.end));
            if mirror {
                w.start = t;
                w.end = s;
            } else {
                w.start = s;
                w.end = t;
            }
            w.arc_mid = w.arc_mid.map(f);
            for o in &mut w.openings {
                if mirror {
                    let len = w.start.distance(w.end);
                    let (a, b) = (len - o.u1, len - o.u0);
                    o.u0 = a;
                    o.u1 = b;
                }
            }
        }
        ElementKind::Grid(g) => {
            g.start = f(g.start);
            g.end = f(g.end);
            g.arc_mid = g.arc_mid.map(f);
            for q in g.vertices.iter_mut() {
                *q = f(*q);
            }
        }
        ElementKind::RefPlane(r) => {
            r.start = f(r.start);
            r.end = f(r.end);
        }
        ElementKind::Floor(fl) => {
            poly(&mut fl.boundary);
            fl.holes.iter_mut().for_each(poly);
            if let Some((a, b, r)) = fl.slope {
                fl.slope = Some((f(a), f(b), r));
            }
        }
        ElementKind::Ceiling(c) => {
            poly(&mut c.boundary);
            c.holes.iter_mut().for_each(poly);
        }
        ElementKind::Shaft(s) => poly(&mut s.boundary),
        ElementKind::Mass(m) => poly(&mut m.boundary),
        ElementKind::Toposolid(t) => {
            poly(&mut t.boundary);
            for q in t.points.iter_mut() {
                q.0 = f(q.0);
            }
            if mirror {
                t.boundary.reverse();
                t.heights.reverse();
            }
        }
        ElementKind::PropertyLine(l) => poly(&mut l.boundary),
        ElementKind::ColorLegend(c) => c.position = f(c.position),
        ElementKind::Matchline(m) => {
            m.start = f(m.start);
            m.end = f(m.end);
        }
        ElementKind::ScopeBox(s) => {
            let (a, b) = (f(s.min), f(s.max));
            let (c, d) = (f(DVec2::new(s.min.x, s.max.y)), f(DVec2::new(s.max.x, s.min.y)));
            s.min = a.min(b).min(c).min(d);
            s.max = a.max(b).max(c).max(d);
        }
        ElementKind::Roof(r) => {
            poly(&mut r.footprint);
            if let RoofKind::Extrusion { start, end, .. } = &mut r.kind {
                *start = f(*start);
                *end = f(*end);
            }
        }
        ElementKind::Room(r) => r.location = f(r.location),
        ElementKind::Area(a) => a.location = f(a.location),
        ElementKind::Instance(i) if i.host.is_none() => {
            i.location = f(i.location);
            i.end = i.end.map(f);
            if mirror {
                let x = vec(DVec2::from_angle(i.rotation_deg.to_radians()));
                i.rotation_deg = x.y.atan2(x.x).to_degrees().rem_euclid(360.0);
                i.flip_hand = !i.flip_hand;
            } else {
                i.rotation_deg = (i.rotation_deg + rot).rem_euclid(360.0);
            }
        }
        ElementKind::Stair(s) => {
            for r in &mut s.runs {
                r.start = f(r.start);
                r.end = f(r.end);
            }
        }
        ElementKind::Ramp(rm) => {
            for r in &mut rm.runs {
                r.start = f(r.start);
                r.end = f(r.end);
            }
        }
        ElementKind::ModelText(t) => {
            let x = vec(DVec2::from_angle(t.rotation_deg.to_radians()));
            t.position = f(t.position);
            t.rotation_deg = x.y.atan2(x.x).to_degrees().rem_euclid(360.0);
        }
        ElementKind::Railing(r) => poly(&mut r.path),
        ElementKind::Line(l) => {
            poly(&mut l.pts);
            l.arc_mid = l.arc_mid.map(f);
        }
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => {
            s.start = f(s.start);
            s.end = f(s.end);
        }
        ElementKind::Dimension(d) => {
            d.line_point = f(d.line_point);
            d.direction = vec(d.direction);
            for r in &mut d.refs {
                r.point = f(r.point);
            }
        }
        ElementKind::Tag(t) => {
            t.position = f(t.position);
            t.leader_end = t.leader_end.map(f);
        }
        ElementKind::Text(t) => {
            t.position = f(t.position);
            poly(&mut t.leader);
            t.rotation_deg += rot;
        }
        ElementKind::Region(r) => {
            poly(&mut r.boundary);
            r.holes.iter_mut().for_each(poly);
        }
        ElementKind::Symbol(s) => {
            s.position = f(s.position);
            poly(&mut s.points);
            s.rotation_deg += rot;
        }
        ElementKind::GroupInstance(g) => {
            g.origin = f(g.origin);
            g.rotation_deg = (g.rotation_deg + rot).rem_euclid(360.0);
        }
        ElementKind::Cad(c) => {
            for (pts, _) in &mut c.polylines {
                poly(pts);
            }
            for (q, _, _) in &mut c.texts {
                *q = f(*q);
            }
        }
        _ => {}
    }
}

/// Group instances in `ids` bring their members along.
fn with_group_members(p: &Project, ids: &[Id]) -> Vec<Id> {
    let set: HashSet<Id> = ids.iter().copied().collect();
    let mut out: Vec<Id> = ids.to_vec();
    for e in &p.elements {
        if e.group.is_some_and(|g| set.contains(&g)) && !set.contains(&e.id) {
            out.push(e.id);
        }
    }
    out
}

/// Moves elements by a plan offset. Hosted openings slide along their host; pinned elements stay.
pub fn move_elements(p: &mut Project, ids: &[Id], delta: DVec2) {
    let ids = with_group_members(p, ids);
    let set: HashSet<Id> = ids.iter().copied().filter(|id| !p.element(*id).is_some_and(|e| e.pinned)).collect();
    for e in p.elements.iter_mut().filter(|e| set.contains(&e.id)) {
        transform_element(e, &|q| q + delta, 0.0, false);
    }
    // Hosted elements whose host did not move slide along it.
    let hosted: Vec<(Id, Id)> = p
        .instances()
        .filter(|(e, i)| set.contains(&e.id) && i.host.is_some_and(|h| !set.contains(&h)))
        .map(|(e, i)| (e.id, i.host.unwrap()))
        .collect();
    for (id, host) in hosted {
        let Some(w) = p.wall(host).cloned() else { continue };
        let (ow, _) = p.element(id).and_then(Element::as_instance).map(|i| analysis::opening_size(p, i)).unwrap_or((0.0, 0.0));
        let target = p.element(id).and_then(Element::as_instance).map(|i| analysis::wall_point(&w, i.offset_along_host).0 + delta);
        if let (Some(i), Some(t)) = (p.element_mut(id).and_then(Element::as_instance_mut), target) {
            let (along, _) = analysis::wall_project(&w, t);
            i.offset_along_host = along.clamp(ow / 2.0, (w.length() - ow / 2.0).max(ow / 2.0));
        }
    }
    // Columns that move with grids follow moved grids.
    let moved_grids: Vec<(DVec2, DVec2)> = p
        .elements
        .iter()
        .filter(|e| set.contains(&e.id))
        .filter_map(|e| match &e.kind {
            ElementKind::Grid(g) => Some((g.start - delta, g.end - delta)),
            _ => None,
        })
        .collect();
    if !moved_grids.is_empty() {
        for e in p.elements.iter_mut() {
            if let ElementKind::Instance(i) = &mut e.kind {
                if i.moves_with_grids && !set.contains(&e.id) && moved_grids.iter().any(|(a, b)| geom::distance_to_segment(*a, *b, i.location) < 1.0) {
                    i.location += delta;
                }
            }
        }
    }
}

/// Copies elements by a plan offset; hosted openings, tags and group members come along.
pub fn copy_elements(p: &mut Project, ids: &[Id], delta: DVec2) -> Vec<Id> {
    let ids = with_group_members(p, ids);
    let set: HashSet<Id> = ids.iter().copied().collect();
    let originals: Vec<Element> = p.elements.iter().filter(|e| set.contains(&e.id)).cloned().collect();
    let mut map: HashMap<Id, Id> = HashMap::new();
    for e in &originals {
        map.insert(e.id, p.new_id());
    }
    let mut created = Vec::new();
    for e in &originals {
        // Hosted things whose host is not copied stay put (Revit copies them only with the host).
        let orphan = match &e.kind {
            ElementKind::Instance(i) => i.host.is_some_and(|h| !set.contains(&h)),
            ElementKind::Tag(t) => !set.contains(&t.host),
            ElementKind::WallFoundation(f) => !set.contains(&f.wall),
            _ => false,
        };
        if orphan && !matches!(e.kind, ElementKind::Tag(_)) {
            continue;
        }
        let mut c = e.clone();
        c.id = map[&e.id];
        c.uid = uuid::Uuid::new_v4().to_string();
        c.pinned = false;
        c.group = e.group.and_then(|g| map.get(&g).copied());
        match &mut c.kind {
            ElementKind::Instance(i) => i.host = i.host.and_then(|h| map.get(&h).copied()),
            ElementKind::Tag(t) => t.host = map.get(&t.host).copied().unwrap_or(t.host),
            ElementKind::WallFoundation(f) => f.wall = map[&f.wall],
            ElementKind::Railing(r) => r.host = r.host.and_then(|h| map.get(&h).copied()),
            ElementKind::Dimension(d) => {
                for r in &mut d.refs {
                    r.element = r.element.map(|x| map.get(&x).copied().unwrap_or(x));
                }
            }
            _ => {}
        }
        let hosted = matches!(&c.kind, ElementKind::Instance(i) if i.host.is_some());
        if !hosted {
            transform_element(&mut c, &|q| q + delta, 0.0, false);
        }
        p.elements.push(c);
        created.push(map[&e.id]);
    }
    for id in &created {
        // Copied doors and windows with numeric Marks get the next free number.
        let numbered = p.element(*id).filter(|e| matches!(e.category(), Category::Doors | Category::Windows) && e.mark.trim().parse::<u64>().is_ok()).map(|e| e.category());
        if let Some(cat) = numbered {
            let mark = next_mark(p, cat);
            if let Some(e) = p.element_mut(*id) {
                e.mark = mark;
            }
        }
        let number = next_room_number(p);
        if let Some(Element { kind: ElementKind::Room(r), .. }) = p.element_mut(*id) {
            if delta.length() > 1.0 {
                r.number = number;
            }
        }
    }
    created
}

/// Rotates elements around a point.
pub fn rotate_elements(p: &mut Project, ids: &[Id], center: DVec2, degrees: f64) {
    let ids = with_group_members(p, ids);
    let a = degrees.to_radians();
    let r = DVec2::from_angle(a);
    let set: HashSet<Id> = ids.iter().copied().filter(|id| !p.element(*id).is_some_and(|e| e.pinned)).collect();
    for e in p.elements.iter_mut().filter(|e| set.contains(&e.id)) {
        transform_element(e, &|q| center + r.rotate(q - center), degrees, false);
    }
}

/// Mirrors elements across the line through `a` and `b`.
pub fn mirror_elements(p: &mut Project, ids: &[Id], a: DVec2, b: DVec2) {
    let ids = with_group_members(p, ids);
    let d = (b - a).normalize_or_zero();
    if d == DVec2::ZERO {
        return;
    }
    let m = |q: DVec2| {
        let v = q - a;
        a + d * (2.0 * v.dot(d)) - v
    };
    let set: HashSet<Id> = ids.iter().copied().filter(|id| !p.element(*id).is_some_and(|e| e.pinned)).collect();
    for e in p.elements.iter_mut().filter(|e| set.contains(&e.id)) {
        transform_element(e, &m, 0.0, true);
    }
    // Openings in swapped walls keep their place.
    let hosted: Vec<(Id, Id)> = p.instances().filter(|(_, i)| i.host.is_some_and(|h| set.contains(&h))).map(|(e, i)| (e.id, i.host.unwrap())).collect();
    for (id, host) in hosted {
        let len = p.wall(host).map(|w| w.length()).unwrap_or(0.0);
        if let Some(i) = p.element_mut(id).and_then(Element::as_instance_mut) {
            i.offset_along_host = len - i.offset_along_host;
            i.flip_hand = !i.flip_hand;
        }
    }
}

/// Scales line-like detail elements about a point (Revit's Scale tool for lines and text positions).
pub fn scale_elements(p: &mut Project, ids: &[Id], center: DVec2, factor: f64) -> Result<(), String> {
    if factor <= 0.0 {
        return Err("The scale factor must be positive.".into());
    }
    let set: HashSet<Id> = ids.iter().copied().collect();
    for e in p.elements.iter_mut().filter(|e| set.contains(&e.id)) {
        if matches!(e.kind, ElementKind::Instance(_) | ElementKind::Room(_) | ElementKind::Area(_)) {
            continue;
        }
        transform_element(e, &|q| center + (q - center) * factor, 0.0, false);
    }
    Ok(())
}

/// Linear array: `count` total copies (including the original) spaced by `step`.
pub fn array_linear(p: &mut Project, ids: &[Id], step: DVec2, count: usize) -> Result<Vec<Id>, String> {
    if count < 2 {
        return Err("An array needs at least two items.".into());
    }
    let mut created = Vec::new();
    for k in 1..count {
        created.extend(copy_elements(p, ids, step * k as f64));
    }
    Ok(created)
}

/// Radial array around `center` over `total_deg` with `count` items.
pub fn array_radial(p: &mut Project, ids: &[Id], center: DVec2, total_deg: f64, count: usize) -> Result<Vec<Id>, String> {
    if count < 2 {
        return Err("An array needs at least two items.".into());
    }
    let full = (total_deg.abs() - 360.0).abs() < 1e-6;
    let step = if full { total_deg / count as f64 } else { total_deg / (count - 1) as f64 };
    let mut created = Vec::new();
    for k in 1..count {
        let copies = copy_elements(p, ids, DVec2::ZERO);
        rotate_elements(p, &copies, center, step * k as f64);
        created.extend(copies);
    }
    Ok(created)
}

/// Offsets walls/lines/grids perpendicular to themselves towards `side`, optionally as a copy.
pub fn offset_elements(p: &mut Project, ids: &[Id], distance: f64, side: DVec2, copy: bool) -> Result<Vec<Id>, String> {
    let targets = if copy { copy_elements(p, ids, DVec2::ZERO) } else { ids.to_vec() };
    for id in &targets {
        let Some(e) = p.element(*id) else { continue };
        let (a, b) = match &e.kind {
            ElementKind::Wall(w) => (w.start, w.end),
            ElementKind::Grid(g) => (g.start, g.end),
            ElementKind::RefPlane(r) => (r.start, r.end),
            ElementKind::Line(l) if l.pts.len() >= 2 => (l.pts[0], l.pts[1]),
            ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => (s.start, s.end),
            _ => continue,
        };
        let n = geom::perp((b - a).normalize_or_zero());
        let sign = if (side - a).dot(n) >= 0.0 { 1.0 } else { -1.0 };
        move_elements(p, &[*id], n * (distance * sign));
    }
    Ok(targets)
}

/// The linear "axis" of a wall/line/grid/separation element: (start, end).
pub fn linear_axis(e: &Element) -> Option<(DVec2, DVec2)> {
    match &e.kind {
        ElementKind::Wall(w) if w.arc_mid.is_none() => Some((w.start, w.end)),
        ElementKind::Grid(g) if g.arc_mid.is_none() && g.vertices.is_empty() => Some((g.start, g.end)),
        ElementKind::RefPlane(r) => Some((r.start, r.end)),
        ElementKind::Line(l) if l.pts.len() == 2 && l.arc_mid.is_none() => Some((l.pts[0], l.pts[1])),
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => Some((s.start, s.end)),
        ElementKind::Railing(r) if r.path.len() == 2 => Some((r.path[0], r.path[1])),
        _ => None,
    }
}

fn set_ends(e: &mut Element, a: DVec2, b: DVec2) {
    match &mut e.kind {
        ElementKind::Wall(w) => {
            w.start = a;
            w.end = b;
        }
        ElementKind::Grid(g) => {
            g.start = a;
            g.end = b;
        }
        ElementKind::RefPlane(r) => {
            r.start = a;
            r.end = b;
        }
        ElementKind::Line(l) => {
            l.pts[0] = a;
            l.pts[1] = b;
        }
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => {
            s.start = a;
            s.end = b;
        }
        ElementKind::Railing(r) => {
            r.path[0] = a;
            r.path[1] = b;
        }
        _ => {}
    }
}

/// Trims or extends `id` to the line through (c, d), keeping the side of `keep`.
fn trim_to(p: &mut Project, id: Id, keep: DVec2, c: DVec2, d: DVec2) -> Result<(), String> {
    let e = p.element(id).ok_or("Element not found.")?;
    if e.pinned {
        return Err("The element is pinned.".into());
    }
    let (a, b) = linear_axis(e).ok_or("Only straight walls and lines can be trimmed or extended.")?;
    let x = geom::line_intersection(a, b - a, c, d - c).ok_or("The elements are parallel.")?;
    let dir = (b - a).normalize_or_zero();
    // Keep the end on the keep side of the intersection; move the other end to it.
    let keep_side = (keep - x).dot(dir);
    let (na, nb) = if keep_side >= 0.0 {
        // Keep the end with the larger projection.
        if (b - x).dot(dir) >= (a - x).dot(dir) { (x, b) } else { (a, x) }
    } else if (a - x).dot(dir) <= (b - x).dot(dir) {
        (a, x)
    } else {
        (x, b)
    };
    if na.distance(nb) < 10.0 {
        return Err("The result would be too short.".into());
    }
    let len_before = a.distance(b);
    let e = p.element_mut(id).unwrap();
    set_ends(e, na, nb);
    // Hosted openings keep their position along the wall from the (possibly moved) start.
    if na != a && matches!(e.kind, ElementKind::Wall(_)) {
        let shift = (a - na).dot(dir);
        let hosted: Vec<Id> = p.hosted_by(id).map(|(e, _)| e.id).collect();
        for h in hosted {
            if let Some(i) = p.element_mut(h).and_then(Element::as_instance_mut) {
                i.offset_along_host += shift;
            }
        }
    }
    let _ = len_before;
    Ok(())
}

/// Trim/Extend to Corner (TR): both elements meet at their intersection.
pub fn trim_extend_corner(p: &mut Project, a: Id, keep_a: DVec2, b: Id, keep_b: DVec2) -> Result<(), String> {
    let (ea, eb) = (p.element(a).cloned().ok_or("Element not found.")?, p.element(b).cloned().ok_or("Element not found.")?);
    let (a0, a1) = linear_axis(&ea).ok_or("Only straight walls and lines can be trimmed or extended.")?;
    let (b0, b1) = linear_axis(&eb).ok_or("Only straight walls and lines can be trimmed or extended.")?;
    trim_to(p, a, keep_a, b0, b1)?;
    trim_to(p, b, keep_b, a0, a1)?;
    Ok(())
}

/// Trim/Extend Single or Multiple Elements to a boundary element.
pub fn trim_extend_to(p: &mut Project, boundary: Id, targets: &[(Id, DVec2)]) -> Result<(), String> {
    let eb = p.element(boundary).cloned().ok_or("Boundary not found.")?;
    let (c, d) = linear_axis(&eb).ok_or("The boundary must be a straight wall, line, grid or reference plane.")?;
    for (id, keep) in targets {
        trim_to(p, *id, *keep, c, d)?;
    }
    Ok(())
}

/// Splits a wall or line at a point (Split Element, SL). Returns the new element.
pub fn split_element(p: &mut Project, id: Id, at: DVec2, gap: f64) -> Result<Id, String> {
    let e = p.element(id).cloned().ok_or("Element not found.")?;
    if e.pinned {
        return Err("The element is pinned.".into());
    }
    if matches!(e.kind, ElementKind::Grid(_) | ElementKind::RefPlane(_)) {
        return Err("Grids and reference planes cannot be split.".into());
    }
    let (a, b) = linear_axis(&e).ok_or("Only straight walls and lines can be split.")?;
    let (q, t) = geom::closest_on_segment(a, b, at);
    let len = a.distance(b);
    if t * len < 10.0 + gap || (1.0 - t) * len < 10.0 + gap {
        return Err("Split point is too close to the end.".into());
    }
    let dir = (b - a) / len;
    let (q0, q1) = (q - dir * (gap / 2.0), q + dir * (gap / 2.0));
    let new_id = p.new_id();
    let mut second = e.clone();
    second.id = new_id;
    second.uid = uuid::Uuid::new_v4().to_string();
    set_ends(&mut second, q1, b);
    set_ends(p.element_mut(id).unwrap(), a, q0);
    p.elements.push(second);
    // Move hosted openings beyond the split to the new wall.
    let split_u = q0.distance(a);
    let hosted: Vec<(Id, f64)> = p.hosted_by(id).map(|(e, i)| (e.id, i.offset_along_host)).collect();
    for (h, u) in hosted {
        if u > split_u {
            if let Some(i) = p.element_mut(h).and_then(Element::as_instance_mut) {
                i.host = Some(new_id);
                i.offset_along_host = u - q1.distance(a);
            }
        }
    }
    Ok(new_id)
}

/// Align (AL): moves `target` so its reference nearest `target_pick` lines up with the reference
/// line through `ref_a`–`ref_b`.
pub fn align(p: &mut Project, ref_a: DVec2, ref_b: DVec2, target: Id, target_pick: DVec2) -> Result<(), String> {
    let e = p.element(target).ok_or("Element not found.")?;
    if e.pinned {
        return Err("The element is pinned.".into());
    }
    let rd = (ref_b - ref_a).normalize_or_zero();
    let n = geom::perp(rd);
    // Target reference: wall face/centre nearest the pick, or the element's axis/point.
    let target_line: (DVec2, DVec2) = match &e.kind {
        ElementKind::Wall(w) => {
            let t = analysis::wall_thickness(p, w) / 2.0;
            let wn = w.normal();
            let cands = [0.0, t, -t];
            let best = cands
                .iter()
                .min_by(|x, y| geom::distance_to_segment(w.start + wn * **x, w.end + wn * **x, target_pick).total_cmp(&geom::distance_to_segment(w.start + wn * **y, w.end + wn * **y, target_pick)))
                .copied()
                .unwrap_or(0.0);
            (w.start + wn * best, w.end + wn * best)
        }
        _ => match linear_axis(e) {
            Some(ab) => ab,
            None => (annotation::host_point(p, e), annotation::host_point(p, e) + rd),
        },
    };
    let td = (target_line.1 - target_line.0).normalize_or_zero();
    if geom::cross2(td, rd).abs() > 0.02 && td != DVec2::ZERO && target_line.0.distance(target_line.1) > 1.0 {
        return Err("The references are not parallel.".into());
    }
    let delta = n * (ref_a - target_line.0).dot(n);
    move_elements(p, &[target], delta);
    Ok(())
}

pub fn set_pinned(p: &mut Project, ids: &[Id], pinned: bool) {
    for e in p.elements.iter_mut().filter(|e| ids.contains(&e.id)) {
        e.pinned = pinned;
    }
}

/// Match Type Properties (MA).
pub fn match_type(p: &mut Project, source: Id, targets: &[Id]) -> Result<(), String> {
    let src = p.element(source).ok_or("Source not found.")?;
    let t = p.type_of(src).ok_or("The source element has no type.")?;
    change_type(p, targets, t)
}

/// Flips a wall's interior/exterior about its location line (the flip arrows).
pub fn flip_wall(p: &mut Project, id: Id) -> Result<(), String> {
    let w = p.wall(id).ok_or("Not a wall.")?.clone();
    let off = p.sys_type(w.type_id).map(|t| analysis::location_line_offset(t, w.location_line)).unwrap_or(0.0);
    let n = w.normal();
    let len = w.length();
    let shift = n * (2.0 * off);
    let wm = p.element_mut(id).and_then(Element::as_wall_mut).unwrap();
    let (s, e) = (wm.end + shift, wm.start + shift);
    wm.start = s;
    wm.end = e;
    wm.arc_mid = wm.arc_mid.map(|m| m + shift);
    wm.flipped = !wm.flipped;
    for o in &mut wm.openings {
        let (a, b) = (len - o.u1, len - o.u0);
        o.u0 = a;
        o.u1 = b;
    }
    let hosted: Vec<Id> = p.hosted_by(id).map(|(e, _)| e.id).collect();
    for h in hosted {
        if let Some(i) = p.element_mut(h).and_then(Element::as_instance_mut) {
            i.offset_along_host = len - i.offset_along_host;
            i.flip_hand = !i.flip_hand;
            i.flip_facing = !i.flip_facing;
        }
    }
    Ok(())
}

pub fn set_wall_join(p: &mut Project, id: Id, at_start: bool, allow: bool) -> Result<(), String> {
    let w = p.element_mut(id).and_then(Element::as_wall_mut).ok_or("Not a wall.")?;
    if at_start {
        w.join_start = allow;
    } else {
        w.join_end = allow;
    }
    Ok(())
}

/// Attach Top/Base: walls to a roof, floor or ceiling.
pub fn attach_walls(p: &mut Project, walls: &[Id], target: Id, top: bool) -> Result<(), String> {
    let ok = matches!(p.element(target).map(|e| &e.kind), Some(ElementKind::Roof(_) | ElementKind::Floor(_) | ElementKind::Ceiling(_)));
    if !ok {
        return Err("Walls can attach to roofs, floors and ceilings.".into());
    }
    for id in walls {
        let w = p.element_mut(*id).and_then(Element::as_wall_mut).ok_or("Select walls first.")?;
        if top {
            w.attach_top = Some(target);
        } else {
            w.attach_base = Some(target);
        }
    }
    Ok(())
}

pub fn detach_walls(p: &mut Project, walls: &[Id]) {
    for id in walls {
        if let Some(w) = p.element_mut(*id).and_then(Element::as_wall_mut) {
            w.attach_top = None;
            w.attach_base = None;
        }
    }
}

/// Copy to Clipboard + Paste Aligned to Selected Levels.
pub fn copy_to_levels(p: &mut Project, ids: &[Id], levels: &[Id]) -> Result<Vec<Id>, String> {
    let mut out = Vec::new();
    for &lv in levels {
        let copies = copy_elements(p, ids, DVec2::ZERO);
        for id in &copies {
            let src_level = p.element(*id).and_then(|e| e.level());
            let Some(src_level) = src_level else { continue };
            let above_src = p.level_above(src_level).map(|l| l.0);
            let above_dst = p.level_above(lv).map(|l| l.0);
            if let Some(e) = p.element_mut(*id) {
                match &mut e.kind {
                    ElementKind::Wall(w) => {
                        w.base_level = lv;
                        if w.top_level == above_src && w.top_level.is_some() {
                            w.top_level = above_dst;
                        }
                    }
                    ElementKind::Floor(f) => f.level = lv,
                    ElementKind::Roof(r) => r.level = lv,
                    ElementKind::Ceiling(c) => c.level = lv,
                    ElementKind::Room(r) => r.level = lv,
                    ElementKind::Instance(i) => {
                        i.level = lv;
                        if i.top_level == above_src && i.top_level.is_some() {
                            i.top_level = above_dst;
                        }
                    }
                    ElementKind::Stair(s) => {
                        s.base_level = lv;
                        s.top_level = above_dst;
                    }
                    ElementKind::Ramp(r) => {
                        r.base_level = lv;
                        r.top_level = above_dst;
                    }
                    ElementKind::ModelText(t) => t.level = lv,
                    ElementKind::Railing(r) => r.level = lv,
                    ElementKind::Shaft(s) => s.base_level = lv,
                    ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => s.level = lv,
                    ElementKind::GroupInstance(g) => g.level = lv,
                    _ => {}
                }
            }
        }
        out.extend(copies);
    }
    Ok(out)
}

/// Changes the type of elements (only to a type of the same kind).
pub fn change_type(p: &mut Project, ids: &[Id], new_type: Id) -> Result<(), String> {
    let sys = p.sys_type(new_type).map(|t| t.category);
    let fam = p.family_type(new_type).map(|(f, _)| (f.id, f.category, f.is_hosted()));
    for id in ids {
        let mut e = p.element(*id).ok_or("Element not found.")?.clone();
        match (&mut e.kind, sys, fam) {
            (ElementKind::Wall(w), Some(Category::Walls), _) => w.type_id = new_type,
            (ElementKind::Floor(f), Some(Category::Floors), _) => f.type_id = new_type,
            (ElementKind::Roof(r), Some(Category::Roofs), _) => r.type_id = new_type,
            (ElementKind::Ceiling(c), Some(Category::Ceilings), _) => c.type_id = new_type,
            (ElementKind::Stair(s), Some(Category::Stairs), _) => s.type_id = new_type,
            (ElementKind::Ramp(r), Some(Category::Ramps), _) => r.type_id = new_type,
            (ElementKind::Railing(r), Some(Category::Railings), _) => r.type_id = new_type,
            (ElementKind::WallFoundation(f), Some(Category::StructuralFoundations), _) => f.type_id = new_type,
            (ElementKind::Instance(i), _, Some((fid, cat, hosted))) if cat == i.category && hosted == i.host.is_some() => {
                i.family_id = fid;
                i.type_id = new_type;
                if let Some(host) = i.host {
                    let wall = p.wall(host).cloned().ok_or("Host not found.")?;
                    let (ow, oh) = analysis::opening_size(p, i);
                    check_opening_fits(p, &wall, host, Some(*id), i.offset_along_host, ow, i.elevation, oh)?;
                }
            }
            _ => return Err("The selected type does not match the element.".into()),
        }
        *p.element_mut(*id).unwrap() = e;
    }
    Ok(())
}

/// Moves a hosted opening along its wall.
pub fn set_opening_offset(p: &mut Project, id: Id, along: f64) -> Result<(), String> {
    let inst = p.element(id).and_then(Element::as_instance).ok_or("Not a door or window.")?.clone();
    let host = inst.host.ok_or("Not hosted.")?;
    let wall = p.wall(host).ok_or("Host not found.")?.clone();
    let (ow, oh) = analysis::opening_size(p, &inst);
    check_opening_fits(p, &wall, host, Some(id), along, ow, inst.elevation, oh)?;
    p.element_mut(id).and_then(Element::as_instance_mut).unwrap().offset_along_host = along;
    Ok(())
}

// ---------------------------------------------------------------- groups

fn group_level_of(members: &[Element]) -> Option<Id> {
    members.iter().find_map(|m| m.level())
}

/// Creates a group from elements; returns the group instance id. Model elements make a
/// model group and view-specific (detail) elements a detail group in their view; a mixed
/// selection makes a model group with an attached detail group.
pub fn create_group(p: &mut Project, ids: &[Id], name: &str) -> Result<Id, String> {
    let groupable = |e: &Element| ids.contains(&e.id) && e.group.is_none() && !matches!(e.kind, ElementKind::Level(_) | ElementKind::GroupInstance(_));
    let model: Vec<Id> = p.elements.iter().filter(|e| groupable(e) && e.view.is_none()).map(|e| e.id).collect();
    let detail: Vec<Id> = p.elements.iter().filter(|e| groupable(e) && e.view.is_some()).map(|e| e.id).collect();
    if model.is_empty() && detail.is_empty() {
        return Err("Select elements to group.".into());
    }
    let views: BTreeSet<Id> = detail.iter().filter_map(|id| p.element(*id).and_then(|e| e.view)).collect();
    if views.len() > 1 {
        return Err("Detail elements of a group must be in one view.".into());
    }
    if model.is_empty() {
        return group_of(p, &detail, name, views.first().copied());
    }
    let inst = group_of(p, &model, name, None)?;
    if !detail.is_empty() {
        let attached = unique_name(p.group_types.iter().map(|g| g.name.clone()), &format!("{name} - Detail"));
        group_of(p, &detail, &attached, views.first().copied())?;
    }
    Ok(inst)
}

fn group_of(p: &mut Project, ids: &[Id], name: &str, view: Option<Id>) -> Result<Id, String> {
    if p.group_types.iter().any(|g| g.name == name) {
        return Err(format!("A group named '{name}' already exists."));
    }
    let members: Vec<Element> = p.elements.iter().filter(|e| ids.contains(&e.id)).cloned().collect();
    let level = match view.and_then(|v| p.view(v)).and_then(|v| v.plan_level()) {
        Some(l) => l,
        None => group_level_of(&members).or_else(|| p.levels().first().map(|l| l.0)).ok_or("No level.")?,
    };
    let fp = analysis::wall_footprints(p);
    let pts: Vec<DVec2> = members.iter().flat_map(|e| crate::plan::element_outline(p, e, &fp).into_iter().flatten()).collect();
    let (mn, mx) = geom::bounds(pts);
    let origin = if mn.x <= mx.x { (mn + mx) / 2.0 } else { DVec2::ZERO };
    let mut stored: Vec<Element> = members.clone();
    for e in &mut stored {
        transform_element(e, &|q| q - origin, 0.0, false);
    }
    let type_id = p.new_id();
    p.group_types.push(GroupType { id: type_id, name: name.into(), members: stored, detail: view.is_some() });
    let inst = match view {
        Some(v) => push_in_view(p, v, ElementKind::GroupInstance(GroupInstance { type_id, origin, level, rotation_deg: 0.0 })),
        None => push(p, ElementKind::GroupInstance(GroupInstance { type_id, origin, level, rotation_deg: 0.0 })),
    };
    for e in p.elements.iter_mut().filter(|e| ids.contains(&e.id)) {
        e.group = Some(inst);
    }
    Ok(inst)
}

/// Places a detail group type in a view.
pub fn place_detail_group(p: &mut Project, type_id: Id, view: Id, origin: DVec2) -> Result<Id, String> {
    let gt = p.group_types.iter().find(|g| g.id == type_id).cloned().ok_or("Group type not found.")?;
    if !gt.detail {
        return Err("This is a model group.".into());
    }
    if !p.view(view).is_some_and(|v| v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. })) {
        return Err("Detail groups are placed in 2D views.".into());
    }
    let level = p.view(view).and_then(|v| v.plan_level()).or_else(|| p.levels().first().map(|l| l.0)).ok_or("No level.")?;
    let inst = push_in_view(p, view, ElementKind::GroupInstance(GroupInstance { type_id, origin, level, rotation_deg: 0.0 }));
    instantiate_members(p, &gt, inst, origin, level, 0.0);
    Ok(inst)
}

/// Places a group type at `origin` on `level`.
pub fn place_group(p: &mut Project, type_id: Id, origin: DVec2, level: Id) -> Result<Id, String> {
    let gt = p.group_types.iter().find(|g| g.id == type_id).cloned().ok_or("Group type not found.")?;
    if gt.detail {
        return Err("This is a detail group; place it from Annotate > Detail Group.".into());
    }
    let inst = push(p, ElementKind::GroupInstance(GroupInstance { type_id, origin, level, rotation_deg: 0.0 }));
    instantiate_members(p, &gt, inst, origin, level, 0.0);
    Ok(inst)
}

fn instantiate_members(p: &mut Project, gt: &GroupType, inst: Id, origin: DVec2, level: Id, rot: f64) {
    let src_level = group_level_of(&gt.members);
    let mut map = HashMap::new();
    for m in &gt.members {
        map.insert(m.id, p.new_id());
    }
    let r = DVec2::from_angle(rot.to_radians());
    let inst_view = p.element(inst).and_then(|e| e.view);
    for m in &gt.members {
        let mut c = m.clone();
        c.id = map[&m.id];
        c.uid = uuid::Uuid::new_v4().to_string();
        c.group = Some(inst);
        if gt.detail {
            c.view = inst_view;
        }
        transform_element(&mut c, &|q| origin + r.rotate(q), rot, false);
        match &mut c.kind {
            ElementKind::Instance(i) => {
                i.host = i.host.and_then(|h| map.get(&h).copied());
                if Some(i.level) == src_level {
                    i.level = level;
                }
            }
            ElementKind::Wall(w) if Some(w.base_level) == src_level => {
                let above_src = src_level.and_then(|l| p.level_above(l)).map(|l| l.0);
                if w.top_level.is_some() && w.top_level == above_src {
                    w.top_level = p.level_above(level).map(|l| l.0);
                }
                w.base_level = level;
            }
            ElementKind::Floor(f) if Some(f.level) == src_level => f.level = level,
            ElementKind::Room(rm) if Some(rm.level) == src_level => rm.level = level,
            ElementKind::Ceiling(cl) if Some(cl.level) == src_level => cl.level = level,
            ElementKind::Railing(rl) => {
                rl.host = rl.host.and_then(|h| map.get(&h).copied());
                if Some(rl.level) == src_level {
                    rl.level = level;
                }
            }
            _ => {}
        }
        p.elements.push(c);
    }
}

/// Ungroup: members become ordinary elements.
pub fn ungroup(p: &mut Project, inst: Id) -> Result<(), String> {
    if !matches!(p.element(inst).map(|e| &e.kind), Some(ElementKind::GroupInstance(_))) {
        return Err("Not a group.".into());
    }
    for e in &mut p.elements {
        if e.group == Some(inst) {
            e.group = None;
        }
    }
    p.elements.retain(|e| e.id != inst);
    Ok(())
}

/// After editing one instance's members, updates the group type and every other instance.
pub fn finish_group_edit(p: &mut Project, inst: Id) -> Result<(), String> {
    let gi = match p.element(inst).map(|e| &e.kind) {
        Some(ElementKind::GroupInstance(g)) => g.clone(),
        _ => return Err("Not a group.".into()),
    };
    let r = DVec2::from_angle(-gi.rotation_deg.to_radians());
    let mut members: Vec<Element> = p.elements.iter().filter(|e| e.group == Some(inst)).cloned().collect();
    for m in &mut members {
        transform_element(m, &|q| r.rotate(q - gi.origin), -gi.rotation_deg, false);
        m.group = None;
    }
    if let Some(gt) = p.group_types.iter_mut().find(|g| g.id == gi.type_id) {
        gt.members = members;
    }
    let gt = p.group_types.iter().find(|g| g.id == gi.type_id).cloned().unwrap();
    let others: Vec<(Id, GroupInstance)> = p
        .elements
        .iter()
        .filter_map(|e| match &e.kind {
            ElementKind::GroupInstance(g) if g.type_id == gi.type_id && e.id != inst => Some((e.id, g.clone())),
            _ => None,
        })
        .collect();
    for (oid, og) in others {
        p.elements.retain(|e| e.group != Some(oid));
        instantiate_members(p, &gt, oid, og.origin, og.level, og.rotation_deg);
    }
    Ok(())
}

// ---------------------------------------------------------------- types and families

pub fn unique_name(existing: impl Iterator<Item = String>, base: &str) -> String {
    let names: BTreeSet<String> = existing.collect();
    if !names.contains(base) {
        return base.to_string();
    }
    (2..).map(|n| format!("{base} {n}")).find(|n| !names.contains(n)).unwrap()
}

pub fn duplicate_system_type(p: &mut Project, type_id: Id, name: &str) -> Result<Id, String> {
    let src = p.sys_type(type_id).ok_or("Type not found.")?.clone();
    if p.types_of(src.category).any(|t| t.name == name) {
        return Err(format!("A type named '{name}' already exists."));
    }
    let id = p.new_id();
    p.types.push(SystemType { id, name: name.to_string(), ..src });
    Ok(id)
}

pub fn duplicate_family_type(p: &mut Project, type_id: Id, name: &str) -> Result<Id, String> {
    let (family, src) = p.family_type(type_id).ok_or("Type not found.")?;
    let fid = family.id;
    if family.types.iter().any(|t| t.name == name) {
        return Err(format!("A type named '{name}' already exists."));
    }
    let values = src.values.clone();
    let id = p.new_id();
    p.family_mut(fid).unwrap().types.push(FamilyType { id, name: name.to_string(), values });
    Ok(id)
}

pub fn type_in_use(p: &Project, type_id: Id) -> bool {
    p.elements.iter().any(|e| p.type_of(e) == Some(type_id))
        || p.types.iter().any(|t| t.stack.iter().any(|(s, _)| *s == type_id))
        || p.group_types.iter().any(|g| g.members.iter().any(|m| p.type_of(m) == Some(type_id)))
}

pub fn delete_type(p: &mut Project, type_id: Id) -> Result<(), String> {
    if type_in_use(p, type_id) {
        return Err("This type is used by elements in the model and cannot be deleted.".into());
    }
    if let Some(t) = p.sys_type(type_id) {
        let c = t.category;
        if p.types_of(c).count() <= 1 {
            return Err("The last type of a category cannot be deleted.".into());
        }
        p.types.retain(|t| t.id != type_id);
        return Ok(());
    }
    let (family, _) = p.family_type(type_id).ok_or("Type not found.")?;
    if family.types.len() <= 1 {
        return Err("A family needs at least one type.".into());
    }
    let fid = family.id;
    p.family_mut(fid).unwrap().types.retain(|t| t.id != type_id);
    Ok(())
}

pub fn new_family(p: &mut Project, name: &str, template: FamilyTemplate) -> Result<Id, String> {
    if p.families.iter().any(|f| f.name == name) {
        return Err(format!("A family named '{name}' already exists."));
    }
    Ok(defaults::add_family(p, name, template, &[("Default", &[])]))
}

pub fn delete_family(p: &mut Project, family_id: Id) -> Result<(), String> {
    if p.instances().any(|(_, i)| i.family_id == family_id) {
        return Err("This family has instances in the model and cannot be deleted.".into());
    }
    p.families.retain(|f| f.id != family_id);
    Ok(())
}

/// Loads a family (from a .rcfa file) into the project, renaming on clash; returns its id.
pub fn load_family(p: &mut Project, mut family: Family) -> Id {
    family.name = unique_name(p.families.iter().map(|f| f.name.clone()), &family.name);
    family.id = p.new_id();
    for t in &mut family.types {
        t.id = p.new_id();
    }
    let id = family.id;
    p.families.push(family);
    id
}

/// Adds a user parameter to a family.
pub fn add_family_param(p: &mut Project, family_id: Id, name: &str, kind: ParamKind, instance: bool, group: &str) -> Result<(), String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("Parameter name cannot be empty.".into());
    }
    if name.contains(['[', ']', '(', ')', '+', '-', '*', '/', '^', '<', '>', '=', ',']) {
        return Err("Parameter names cannot contain operators or brackets.".into());
    }
    let f = p.family_mut(family_id).ok_or("Family not found.")?;
    if f.param(name).is_some() || name.eq_ignore_ascii_case(family_params::WALL_THICKNESS) {
        return Err(format!("A parameter named '{name}' already exists."));
    }
    let default = match kind {
        ParamKind::Text => String::new(),
        ParamKind::Material => "Default".into(),
        _ => "0".into(),
    };
    f.params.push(FamilyParameter { name: name.to_string(), kind, instance, group: group.to_string(), default, ..Default::default() });
    Ok(())
}

pub fn remove_family_param(p: &mut Project, family_id: Id, name: &str) -> Result<(), String> {
    let f = p.family_mut(family_id).ok_or("Family not found.")?;
    let param = f.param(name).ok_or("Parameter not found.")?;
    if param.built_in {
        return Err("Built-in parameters cannot be deleted.".into());
    }
    let pname = param.name.clone();
    if let Some(user) = f.params.iter().find(|q| crate::formula::references(&q.formula).iter().any(|r| r.eq_ignore_ascii_case(&pname))) {
        return Err(format!("'{}' is used in the formula of '{}'.", pname, user.name));
    }
    if f.definition.as_ref().is_some_and(|d| d.dims.iter().any(|dm| dm.label.eq_ignore_ascii_case(&pname))) {
        return Err(format!("'{pname}' labels a dimension. Remove the label first."));
    }
    f.params.retain(|q| q.name != pname);
    for t in &mut f.types {
        t.values.remove(&pname);
    }
    for e in &mut p.elements {
        if let ElementKind::Instance(i) = &mut e.kind {
            if i.family_id == family_id {
                i.values.remove(&pname);
            }
        }
    }
    Ok(())
}

pub fn set_family_formula(p: &mut Project, family_id: Id, name: &str, formula: &str) -> Result<(), String> {
    let f = p.family(family_id).ok_or("Family not found.")?;
    family_params::validate_formula(f, name, formula)?;
    let f = p.family_mut(family_id).unwrap();
    f.params.iter_mut().find(|q| q.name.eq_ignore_ascii_case(name)).unwrap().formula = formula.trim().to_string();
    Ok(())
}

/// Sets a type value from user input, validating numbers.
pub fn set_family_type_value(p: &mut Project, type_id: Id, name: &str, input: &str) -> Result<(), String> {
    let units = p.units.clone();
    let (family, _) = p.family_type(type_id).ok_or("Type not found.")?;
    let param = family.param(name).ok_or("Parameter not found.")?.clone();
    if !param.formula.is_empty() {
        return Err(format!("'{}' is computed by a formula.", param.name));
    }
    let stored = if param.kind.is_numeric() {
        let v = if param.kind == ParamKind::YesNo { crate::units::parse_input(input, param.kind) } else { units.parse(input, param.kind) };
        let v = v.ok_or_else(|| format!("'{input}' is not a valid {}.", param.kind.label().to_lowercase()))?;
        if param.kind == ParamKind::Length && v < 0.0 {
            return Err("Lengths cannot be negative.".into());
        }
        crate::units::to_stored(v)
    } else {
        input.to_string()
    };
    let fid = family.id;
    let t = p.family_mut(fid).unwrap().types.iter_mut().find(|t| t.id == type_id).unwrap();
    t.values.insert(param.name.clone(), stored);
    // The new values must still solve for parametric families.
    if let Some(f) = p.family(fid) {
        if let (Some(def), Some(ft)) = (&f.definition, f.types.iter().find(|t| t.id == type_id)) {
            let r = Resolver::for_type(f, ft);
            def.solve(&|n| r.number(n).ok())?;
        }
    }
    Ok(())
}

// ---------------------------------------------------------------- views

pub fn new_schedule(p: &mut Project, category: Category) -> Id {
    let name = unique_name(p.views.iter().map(|v| v.name.clone()), &format!("{} Schedule", category.singular()));
    let fields: Vec<String> = match category {
        Category::Rooms | Category::Areas => vec!["Number", "Name", "Level", "Area"],
        Category::Walls | Category::Floors | Category::Roofs | Category::Ceilings => vec!["Family and Type", "Area", "Count"],
        Category::Stairs => vec!["Family and Type", "Actual Number of Risers", "Actual Riser Height", "Actual Tread Depth"],
        _ => vec!["Mark", "Family and Type", "Level", "Count"],
    }
    .into_iter()
    .map(String::from)
    .collect();
    let id = p.new_id();
    p.views.push(View::new(id, name, 100.0, ViewKind::Schedule(ScheduleDef { category, fields, itemize: true, grand_total: true, ..Default::default() })));
    id
}

pub fn new_material_takeoff(p: &mut Project, category: Category) -> Id {
    let name = unique_name(p.views.iter().map(|v| v.name.clone()), &format!("{} Material Takeoff", category.singular()));
    let id = p.new_id();
    p.views.push(View::new(
        id,
        name,
        100.0,
        ViewKind::Schedule(ScheduleDef {
            category,
            fields: vec!["Family and Type".into(), "Material: Name".into(), "Material: Area".into(), "Material: Volume".into()],
            sort_by: vec!["Material: Name".into()],
            itemize: false,
            grand_total: true,
            total_fields: vec!["Material: Area".into(), "Material: Volume".into()],
            material_takeoff: true,
            ..Default::default()
        }),
    ));
    id
}

pub fn new_keynote_legend(p: &mut Project) -> Id {
    let id = p.new_id();
    p.views.push(View::new(
        id,
        unique_name(p.views.iter().map(|v| v.name.clone()), "Keynote Legend"),
        100.0,
        ViewKind::Schedule(ScheduleDef { category: Category::GenericModels, fields: vec!["Key Value".into(), "Keynote Text".into()], sort_by: vec!["Key Value".into()], keynote_legend: true, itemize: true, ..Default::default() }),
    ));
    id
}

pub fn new_sheet_list(p: &mut Project) -> Id {
    let id = p.new_id();
    p.views.push(View::new(
        id,
        unique_name(p.views.iter().map(|v| v.name.clone()), "Sheet List"),
        100.0,
        ViewKind::Schedule(ScheduleDef { category: Category::GenericModels, fields: vec!["Sheet Number".into(), "Sheet Name".into(), "Drawn By".into(), "Current Revision".into()], sort_by: vec!["Sheet Number".into()], sheet_list: true, itemize: true, ..Default::default() }),
    ));
    id
}

pub fn new_sheet(p: &mut Project, size: SheetSize) -> Id {
    let max = p
        .views
        .iter()
        .filter_map(|v| match &v.kind {
            ViewKind::Sheet(s) => s.number.trim_start_matches(|c: char| c.is_alphabetic()).parse::<u32>().ok(),
            _ => None,
        })
        .max()
        .unwrap_or(100);
    let id = p.new_id();
    p.views.push(View::new(
        id,
        "Unnamed",
        1.0,
        ViewKind::Sheet(Sheet { number: format!("A{}", max + 1), size, drawn_by: "Author".into(), checked_by: "Checker".into(), ..Default::default() }),
    ));
    id
}

/// The default 3D view: orthographic, looking from the south-east corner (Top, Front, Right).
pub fn new_3d_view(p: &mut Project) -> Id {
    let name = unique_name(p.views.iter().map(|v| v.name.clone()), "3D View");
    let id = p.new_id();
    let mut v = View::new(id, name, 100.0, ViewKind::ThreeD { eye: DVec3::new(20000.0, -11000.0, 16500.0), target: DVec3::new(5000.0, 4000.0, 1500.0), perspective: false });
    v.phase = p.phases.last().map(|ph| ph.id);
    p.views.push(v);
    id
}

pub fn new_section(p: &mut Project, start: DVec2, end: DVec2, depth: f64) -> Result<Id, String> {
    if start.distance(end) < 500.0 {
        return Err("The section line is too short.".into());
    }
    let n = p.views.iter().filter(|v| matches!(v.kind, ViewKind::Section { .. })).count() + 1;
    let levels = p.levels();
    let z_min = levels.first().map(|l| l.1.elevation).unwrap_or(0.0) - 1500.0;
    let z_max = levels.last().map(|l| l.1.elevation).unwrap_or(3000.0) + 6000.0;
    let id = p.new_id();
    let mut v = View::new(id, unique_name(p.views.iter().map(|v| v.name.clone()), &format!("Section {n}")), 100.0, ViewKind::Section { start, end, depth, z_min, z_max });
    v.phase = p.phases.last().map(|ph| ph.id);
    p.views.push(v);
    Ok(id)
}

pub fn new_callout(p: &mut Project, parent: Id, a: DVec2, b: DVec2) -> Result<Id, String> {
    let src = p.view(parent).ok_or("View not found.")?.clone();
    if src.plan_level().is_none() {
        return Err("Callouts can be created in plan views.".into());
    }
    if (a - b).abs().min_element() < 100.0 {
        return Err("The callout is too small.".into());
    }
    let id = p.new_id();
    let name = unique_name(p.views.iter().map(|v| v.name.clone()), &format!("Callout of {}", src.name));
    p.views.push(View { id, name, scale: 50.0, crop: Some((a.min(b), a.max(b))), crop_active: true, crop_visible: true, parent: Some(parent), detail: DetailLevel::Fine, is_template: false, template: None, ..src });
    Ok(id)
}

pub fn new_drafting_view(p: &mut Project, name: &str, scale: f64) -> Id {
    let id = p.new_id();
    p.views.push(View::new(id, unique_name(p.views.iter().map(|v| v.name.clone()), name), scale, ViewKind::Drafting));
    id
}

pub fn new_legend(p: &mut Project, name: &str) -> Id {
    let id = p.new_id();
    p.views.push(View::new(id, unique_name(p.views.iter().map(|v| v.name.clone()), name), 50.0, ViewKind::Legend));
    id
}

pub fn new_area_plan(p: &mut Project, level: Id, scheme: Id) -> Result<Id, String> {
    let lname = p.level(level).ok_or("Level not found.")?.name.clone();
    let sname = p.area_schemes.iter().find(|s| s.id == scheme).ok_or("Area scheme not found.")?.name.clone();
    let id = p.new_id();
    let mut v = View::new(id, unique_name(p.views.iter().map(|v| v.name.clone()), &format!("{lname} ({sname})")), 100.0, ViewKind::AreaPlan { level, scheme });
    v.phase = p.phases.last().map(|ph| ph.id);
    p.views.push(v);
    Ok(id)
}

pub fn new_floor_plan(p: &mut Project, level: Id) -> Result<Id, String> {
    let lname = p.level(level).ok_or("Level not found.")?.name.clone();
    let id = p.new_id();
    let mut v = View::new(id, unique_name(p.views.iter().map(|v| v.name.clone()), &lname), 100.0, ViewKind::FloorPlan { level, cut_height: 1200.0, room_colors: false });
    v.phase = p.phases.last().map(|ph| ph.id);
    p.views.push(v);
    Ok(id)
}

/// Duplicate (optionally With Detailing: view-specific annotation is copied too).
pub fn duplicate_view(p: &mut Project, view: Id, with_detailing: bool) -> Result<Id, String> {
    let mut src = p.view(view).ok_or("View not found.")?.clone();
    // Duplicate Sheet: a new sheet number and no viewports (views sit on one sheet only).
    if let ViewKind::Sheet(sh) = &mut src.kind {
        let numbers: Vec<String> = p.views.iter().filter_map(|v| match &v.kind {
            ViewKind::Sheet(s) => Some(s.number.clone()),
            _ => None,
        }).collect();
        let base = sh.number.trim_end_matches(|c: char| c.is_ascii_digit()).to_string();
        let start: u32 = sh.number[base.len()..].parse().unwrap_or(100);
        sh.number = (start + 1..).map(|n| format!("{base}{n}")).find(|n| !numbers.contains(n)).unwrap();
        sh.viewports.clear();
        sh.revisions.clear();
    }
    let name = unique_name(p.views.iter().map(|v| v.name.clone()), &format!("{} Copy", src.name));
    let id = p.new_id();
    p.views.push(View { id, name, ..src });
    if with_detailing {
        let owned: Vec<Element> = p.elements.iter().filter(|e| e.view == Some(view)).cloned().collect();
        for mut e in owned {
            e.id = p.new_id();
            e.uid = uuid::Uuid::new_v4().to_string();
            e.view = Some(id);
            p.elements.push(e);
        }
    }
    Ok(id)
}

pub fn rename_view(p: &mut Project, view: Id, name: &str) -> Result<(), String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("View name cannot be empty.".into());
    }
    let kind_label = p.view(view).ok_or("View not found.")?.type_label();
    if p.views.iter().any(|v| v.id != view && v.name == name && v.type_label() == kind_label) {
        return Err(format!("A {} named '{name}' already exists.", kind_label.to_lowercase()));
    }
    p.view_mut(view).unwrap().name = name.to_string();
    Ok(())
}

pub fn delete_view(p: &mut Project, view: Id) -> Result<(), String> {
    p.views.retain(|v| v.id != view && v.parent != Some(view));
    for v in &mut p.views {
        if let ViewKind::Sheet(s) = &mut v.kind {
            s.viewports.retain(|vp| vp.view != view);
        }
        if v.template == Some(view) {
            v.template = None;
        }
    }
    p.elements.retain(|e| e.view != Some(view));
    Ok(())
}

/// Applies a view template's settings to a view.
pub fn apply_template(p: &mut Project, view: Id, template: Id) -> Result<(), String> {
    let t = p.view(template).ok_or("Template not found.")?.clone();
    if !t.is_template {
        return Err("That view is not a view template.".into());
    }
    let v = p.view_mut(view).ok_or("View not found.")?;
    v.scale = t.scale;
    v.detail = t.detail;
    v.style = t.style;
    v.hidden = t.hidden.clone();
    v.overrides = t.overrides.clone();
    v.phase_filter = t.phase_filter;
    if v.plan_level().is_some() && t.plan_level().is_some() {
        v.view_range = t.view_range;
    }
    v.template = Some(template);
    Ok(())
}

pub fn template_from_view(p: &mut Project, view: Id, name: &str) -> Result<Id, String> {
    let src = p.view(view).ok_or("View not found.")?.clone();
    if p.views.iter().any(|v| v.is_template && v.name == name) {
        return Err(format!("A view template named '{name}' already exists."));
    }
    let id = p.new_id();
    p.views.push(View { id, name: name.into(), is_template: true, template: None, parent: None, crop: None, crop_active: false, ..src });
    Ok(id)
}

pub fn place_on_sheet(p: &mut Project, sheet: Id, view: Id, cx: f64, cy: f64) -> Result<(), String> {
    let v = p.view(view).ok_or("View not found.")?;
    if matches!(v.kind, ViewKind::Sheet(_)) || v.is_template {
        return Err("That view cannot be placed on a sheet.".into());
    }
    if v.single_placement() {
        if let Some(s) = p.sheet_containing(view) {
            return Err(format!("'{}' is already placed on sheet '{}'.", v.name, s.name));
        }
    }
    match p.view_mut(sheet).map(|s| &mut s.kind) {
        Some(ViewKind::Sheet(s)) => {
            let number = (s.viewports.len() + 1).to_string();
            s.viewports.push(Viewport { view, cx, cy, detail_number: number, show_title: true });
            Ok(())
        }
        _ => Err("Not a sheet.".into()),
    }
}

pub fn add_revision(p: &mut Project, description: &str) -> Id {
    let id = p.new_id();
    let seq = p.revisions.len() as u32 + 1;
    p.revisions.push(Revision { id, sequence: seq, date: String::new(), description: description.into(), issued_to: String::new(), issued_by: String::new(), issued: false });
    id
}

pub fn add_phase(p: &mut Project, name: &str) -> Result<Id, String> {
    if p.phases.iter().any(|ph| ph.name == name) {
        return Err(format!("A phase named '{name}' already exists."));
    }
    let id = p.new_id();
    p.phases.push(Phase { id, name: name.into() });
    Ok(id)
}

pub fn add_option_set(p: &mut Project, name: &str) -> Id {
    let id = p.new_id();
    let primary = p.new_id();
    p.option_sets.push(OptionSet { id, name: name.into(), options: vec![DesignOption { id: primary, name: "Option 1 (primary)".into(), primary: true }] });
    id
}

pub fn add_option(p: &mut Project, set: Id, name: &str) -> Result<Id, String> {
    let id = p.new_id();
    let s = p.option_sets.iter_mut().find(|s| s.id == set).ok_or("Option set not found.")?;
    s.options.push(DesignOption { id, name: name.into(), primary: false });
    Ok(id)
}

pub fn set_design_option(p: &mut Project, ids: &[Id], option: Option<Id>) {
    for e in p.elements.iter_mut().filter(|e| ids.contains(&e.id)) {
        e.design_option = option;
    }
}

/// Make Primary: the chosen option becomes primary in its set.
pub fn make_primary(p: &mut Project, option: Id) -> Result<(), String> {
    let s = p.option_sets.iter_mut().find(|s| s.options.iter().any(|o| o.id == option)).ok_or("Option not found.")?;
    for o in &mut s.options {
        o.primary = o.id == option;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::units::UnitSystem;

    fn project() -> (Project, Id, Id) {
        let p = defaults::new_project(UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let wt = p.types_of(Category::Walls).next().unwrap().id;
        (p, lvl, wt)
    }

    #[test]
    fn multi_segment_grid_keeps_its_bends() {
        let (mut p, ..) = project();
        let id = add_grid_path(&mut p, vec![DVec2::new(0.0, 0.0), DVec2::new(0.0, 5000.0), DVec2::new(3000.0, 8000.0)]).unwrap();
        let Some(ElementKind::Grid(g)) = p.element(id).map(|e| &e.kind) else { panic!() };
        assert_eq!(g.polyline(), vec![DVec2::new(0.0, 0.0), DVec2::new(0.0, 5000.0), DVec2::new(3000.0, 8000.0)]);
        // Named as a vertical grid (numbers), from its first segment.
        assert!(g.name.parse::<u32>().is_ok(), "{}", g.name);
        let (d0, d1) = g.end_dirs();
        assert!((d0 - DVec2::new(0.0, -1.0)).length() < 1e-9 && (d1 - DVec2::new(1.0, 1.0).normalize()).length() < 1e-9);
    }

    #[test]
    fn masses_toposolids_and_model_by_face() {
        let (mut p, lvl, wt) = project();
        let sq = vec![DVec2::new(0.0, 0.0), DVec2::new(10000.0, 0.0), DVec2::new(10000.0, 8000.0), DVec2::new(0.0, 8000.0)];
        let m = add_mass(&mut p, lvl, sq.clone(), 7000.0).unwrap();
        let walls = model_by_face(&mut p, m, ByFace::Walls, wt).unwrap();
        assert_eq!(walls.len(), 4);
        // Exterior faces lie on the mass faces and the body is inside the mass.
        for id in &walls {
            let w = p.wall(*id).unwrap().clone();
            let half = analysis::wall_thickness(&p, &w) / 2.0;
            let mid = (w.start + w.end) / 2.0;
            let ext = mid + w.normal() * half;
            let on_face = ext.x.abs() < 1e-6 || (ext.x - 10000.0).abs() < 1e-6 || ext.y.abs() < 1e-6 || (ext.y - 8000.0).abs() < 1e-6;
            assert!(on_face, "exterior face at {ext:?}");
            assert!(geom::contains(&sq, mid));
        }
        // Consecutive walls share corner points, so they join.
        for k in 0..4 {
            let (a, b) = (p.wall(walls[k]).unwrap().end, p.wall(walls[(k + 1) % 4]).unwrap().start);
            assert!(a.distance(b) < 1e-6);
        }
        assert!((analysis::wall_height(&p, p.wall(walls[0]).unwrap()) - 7000.0).abs() < 1e-6);
        let ft = p.types_of(Category::Floors).next().unwrap().id;
        // Levels at 0 and 3000 cut a 7000 mm mass.
        let floors = model_by_face(&mut p, m, ByFace::Floors, ft).unwrap();
        assert_eq!(floors.len(), 2);
        // A toposolid with one raised corner has contours, and Height Offset shifts every point.
        let t = add_toposolid(&mut p, lvl, sq, 0.0, 2000.0).unwrap();
        set_topo_point(&mut p, t, 2, 3500.0).unwrap();
        let ElementKind::Toposolid(ts) = p.element(t).unwrap().kind.clone() else { panic!() };
        let c = analysis::topo_contours(&p, &ts, 1000.0);
        assert!(c.len() >= 3, "{}", c.len());
        // An interior point raises the middle of the surface.
        let before = analysis::topo_triangles(&p, &ts).len();
        add_topo_point(&mut p, t, DVec2::new(5000.0, 4000.0), 6000.0).unwrap();
        let ElementKind::Toposolid(ts2) = p.element(t).unwrap().kind.clone() else { panic!() };
        let tris = analysis::topo_triangles(&p, &ts2);
        assert_eq!(tris.len(), before + 2);
        assert!(tris.iter().flatten().any(|q| (q.z - 6000.0).abs() < 1e-6));
        let area: f64 = tris.iter().map(|[a, b, c]| geom::cross2(b.truncate() - a.truncate(), c.truncate() - a.truncate()) / 2.0).sum();
        assert!((area - 80e6).abs() < 1.0, "{area}");
        set_topo_point(&mut p, t, 4, 1000.0).unwrap();
        remove_topo_point(&mut p, t, 4).unwrap();
        assert!(remove_topo_point(&mut p, t, 0).is_err());
        crate::params::set(&mut p, t, "Height Offset From Level", "500").unwrap();
        let ElementKind::Toposolid(ts) = p.element(t).unwrap().kind.clone() else { panic!() };
        assert!((ts.heights[0] - 500.0).abs() < 1e-6 && (ts.heights[2] - 4000.0).abs() < 1e-6);
        assert!(!crate::build3d::element_mesh(&p, p.element(t).unwrap(), &Default::default()).is_empty());
        let pl = add_property_line(&mut p, lvl, vec![DVec2::new(-1000.0, -1000.0), DVec2::new(12000.0, -1000.0), DVec2::new(12000.0, 9000.0)]).unwrap();
        assert!(crate::params::get(&p, p.element(pl).unwrap(), "Area").is_some());
    }

    #[test]
    fn doors_and_windows_number_their_marks() {
        let (mut p, lvl, wt) = project();
        let w = add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(10000.0, 0.0), 3000.0).unwrap();
        let door = p.families.iter().find(|f| f.name == "Single-Flush").unwrap().types[0].id;
        let a = place_hosted(&mut p, door, w, 2000.0, false).unwrap();
        let b = place_hosted(&mut p, door, w, 5000.0, false).unwrap();
        assert_eq!(p.element(a).unwrap().mark, "1");
        assert_eq!(p.element(b).unwrap().mark, "2");
        let c = copy_elements(&mut p, &[w, a, b], DVec2::new(0.0, 4000.0));
        let marks: Vec<String> = c.iter().filter_map(|id| p.element(*id)).filter(|e| e.category() == Category::Doors).map(|e| e.mark.clone()).collect();
        assert_eq!(marks.len(), 2);
        assert!(marks.contains(&"3".to_string()) && marks.contains(&"4".to_string()), "{marks:?}");
        // Windows keep their own sequence.
        let window = p.families.iter().find(|f| f.name == "Fixed").unwrap().types[0].id;
        let w1 = place_hosted(&mut p, window, w, 8000.0, false).unwrap();
        assert_eq!(p.element(w1).unwrap().mark, "1");
        let copy = copy_elements(&mut p, &[w, w1], DVec2::new(0.0, 8000.0));
        let wm: Vec<String> = copy.iter().filter_map(|id| p.element(*id)).filter(|e| e.category() == Category::Windows).map(|e| e.mark.clone()).collect();
        assert_eq!(wm, vec!["2".to_string()]);
    }

    #[test]
    fn trim_split_offset_align() {
        let (mut p, lvl, wt) = project();
        let a = add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(4000.0, 0.0), 3000.0).unwrap();
        let b = add_wall(&mut p, lvl, wt, DVec2::new(5000.0, 1000.0), DVec2::new(5000.0, 5000.0), 3000.0).unwrap();
        trim_extend_corner(&mut p, a, DVec2::new(1000.0, 0.0), b, DVec2::new(5000.0, 4000.0)).unwrap();
        assert!(p.wall(a).unwrap().end.distance(DVec2::new(5000.0, 0.0)) < 1e-6);
        assert!(p.wall(b).unwrap().start.distance(DVec2::new(5000.0, 0.0)) < 1e-6);
        let c = split_element(&mut p, a, DVec2::new(2000.0, 100.0), 0.0).unwrap();
        assert!(p.wall(a).unwrap().end.distance(DVec2::new(2000.0, 0.0)) < 1e-6);
        assert!(p.wall(c).unwrap().start.distance(DVec2::new(2000.0, 0.0)) < 1e-6);
        let copies = offset_elements(&mut p, &[c], 1500.0, DVec2::new(3000.0, 2000.0), true).unwrap();
        assert!((p.wall(copies[0]).unwrap().start.y - 1500.0).abs() < 1e-6);
        let g = add_grid(&mut p, DVec2::new(0.0, 3000.0), DVec2::new(8000.0, 3000.0)).unwrap();
        let _ = g;
        align(&mut p, DVec2::new(0.0, 3000.0), DVec2::new(8000.0, 3000.0), copies[0], DVec2::new(3000.0, 1600.0)).unwrap();
        // The wall's picked face (exterior side, y + 100) is now on the grid line.
        let w = p.wall(copies[0]).unwrap();
        assert!((w.start.y + 100.0 - 3000.0).abs() < 1e-6 || (w.start.y - 3000.0).abs() < 1e-6, "{}", w.start.y);
    }

    #[test]
    fn groups_propagate_edits() {
        let (mut p, lvl, wt) = project();
        let w = add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(3000.0, 0.0), 3000.0).unwrap();
        let g = create_group(&mut p, &[w], "Bay").unwrap();
        let gt = match &p.element(g).unwrap().kind {
            ElementKind::GroupInstance(gi) => gi.type_id,
            _ => unreachable!(),
        };
        let g2 = place_group(&mut p, gt, DVec2::new(1500.0, 5000.0), lvl).unwrap();
        let members2: Vec<Id> = p.elements.iter().filter(|e| e.group == Some(g2)).map(|e| e.id).collect();
        assert_eq!(members2.len(), 1);
        // Edit the first instance: lengthen its wall, then finish.
        p.element_mut(w).and_then(Element::as_wall_mut).unwrap().end = DVec2::new(4000.0, 0.0);
        finish_group_edit(&mut p, g).unwrap();
        let w2 = p.elements.iter().find(|e| e.group == Some(g2)).and_then(|e| e.as_wall()).unwrap();
        assert!((w2.length() - 4000.0).abs() < 1e-6);
        // Moving the group moves its members.
        move_elements(&mut p, &[g2], DVec2::new(0.0, 1000.0));
        let w2 = p.elements.iter().find(|e| e.group == Some(g2)).and_then(|e| e.as_wall()).unwrap();
        assert!((w2.start.y - 6000.0).abs() < 1e-6);
    }

    #[test]
    fn locked_dimension_moves_dependent_wall() {
        let (p, lvl, wt) = project();
        let mut doc = Document::new(p);
        let (a, b) = doc
            .transact("walls", |p| Ok((add_wall(p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(0.0, 4000.0), 3000.0)?, add_wall(p, lvl, wt, DVec2::new(3000.0, 0.0), DVec2::new(3000.0, 4000.0), 3000.0)?)))
            .unwrap();
        let view = doc.data.views[0].id;
        doc.transact("dim", |p| {
            let d = add_dimension(p, view, vec![DimRef { element: Some(a), part: RefPart::WallCenter, point: DVec2::new(0.0, 2000.0) }, DimRef { element: Some(b), part: RefPart::WallCenter, point: DVec2::new(3000.0, 2000.0) }], DVec2::X, DVec2::new(0.0, -1000.0))?;
            if let Some(Element { kind: ElementKind::Dimension(dm), .. }) = p.element_mut(d) {
                dm.locks[0] = true;
            }
            Ok(())
        })
        .unwrap();
        doc.transact("move a", |p| {
            move_elements(p, &[a], DVec2::new(500.0, 0.0));
            Ok(())
        })
        .unwrap();
        assert!((doc.data.wall(b).unwrap().start.x - 3500.0).abs() < 1e-6);
    }

    #[test]
    fn radial_and_angular_labels_drive_geometry() {
        let (p, lvl, wt) = project();
        let mut doc = Document::new(p);
        let view = doc.data.views.iter().find(|v| v.plan_level().is_some()).unwrap().id;
        // An arc wall of radius 3000 about the origin, and two lines from the origin.
        let (arc, la, lb) = doc
            .transact("geometry", |p| {
                let w = add_wall(p, lvl, wt, DVec2::new(3000.0, 0.0), DVec2::new(-3000.0, 0.0), 3000.0)?;
                p.element_mut(w).and_then(Element::as_wall_mut).unwrap().arc_mid = Some(DVec2::new(0.0, 3000.0));
                let la = add_line(p, Some(view), None, vec![DVec2::ZERO, DVec2::new(5000.0, 0.0)], None, LineStyle::Thin)?;
                let lb = add_line(p, Some(view), None, vec![DVec2::ZERO, DVec2::new(0.0, 5000.0)], None, LineStyle::Thin)?;
                Ok((w, la, lb))
            })
            .unwrap();
        doc.transact("dims", |p| {
            p.global_params.push(GlobalParameter { name: "R".into(), kind: ParamKind::Length, value: 4000.0, ..Default::default() });
            p.global_params.push(GlobalParameter { name: "A".into(), kind: ParamKind::Angle, value: 60.0, ..Default::default() });
            let r = add_dimension(p, view, vec![DimRef { element: Some(arc), part: RefPart::ArcCenter, point: DVec2::ZERO }, DimRef { element: Some(arc), part: RefPart::ArcPoint, point: DVec2::new(0.0, 3000.0) }], DVec2::X, DVec2::new(0.0, 1000.0))?;
            let a = add_dimension(
                p,
                view,
                vec![
                    DimRef { element: Some(la), part: RefPart::Point, point: DVec2::new(2000.0, 0.0) },
                    DimRef { element: None, part: RefPart::Point, point: DVec2::ZERO },
                    DimRef { element: Some(lb), part: RefPart::Point, point: DVec2::new(0.0, 2000.0) },
                ],
                DVec2::X,
                DVec2::new(1500.0, 1500.0),
            )?;
            for (id, kind, label) in [(r, DimKind::Radial, "R"), (a, DimKind::Angular, "A")] {
                if let Some(Element { kind: ElementKind::Dimension(dm), .. }) = p.element_mut(id) {
                    dm.kind = kind;
                    dm.label = label.into();
                }
            }
            Ok(())
        })
        .unwrap();
        let w = doc.data.wall(arc).unwrap();
        let a2 = geom::Arc2::through(w.start, w.arc_mid.unwrap(), w.end).unwrap();
        assert!((a2.radius - 4000.0).abs() < 1e-6, "{}", a2.radius);
        assert!(a2.center.length() < 1e-6);
        let ElementKind::Line(l) = &doc.data.element(lb).unwrap().kind else { panic!() };
        let ang = (l.pts[1] - l.pts[0]).y.atan2((l.pts[1] - l.pts[0]).x).to_degrees();
        assert!((ang - 60.0).abs() < 1e-6, "{ang}");
    }

    #[test]
    fn paint_matchline_and_view_reference() {
        let (mut p, lvl, wt) = project();
        let w = add_wall(&mut p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(4000.0, 0.0), 3000.0).unwrap();
        let fp = analysis::wall_footprints(&p);
        let before = build3d::element_mesh(&p, p.element(w).unwrap(), &fp);
        // Paint the face on the y = -half plane (outward normal -Y) with brick.
        let half = p.sys_type(wt).unwrap().thickness() / 2.0;
        let mat = p.materials.iter().find(|m| !before.by_material.contains_key(&m.name)).unwrap().name.clone();
        paint_face(&mut p, w, DVec3::new(0.0, -1.0, 0.0), DVec3::new(1000.0, -half, 1000.0), &mat).unwrap();
        let after = build3d::element_mesh(&p, p.element(w).unwrap(), &fp);
        let painted = after.by_material.get(&mat).map(|m| m.triangle_count()).unwrap_or(0);
        assert!(painted >= 2, "painted triangles: {painted}");
        let total = |s: &crate::mesh::MeshSet| s.by_material.values().map(|m| m.triangle_count()).sum::<usize>();
        assert_eq!(total(&before), total(&after));
        // Painting the same face again replaces it; remove clears it.
        paint_face(&mut p, w, DVec3::new(0.0, 1.0, 0.0), DVec3::new(500.0, -half, 200.0), &mat).unwrap();
        assert_eq!(p.element(w).unwrap().painted.len(), 1);
        remove_paint(&mut p, w, DVec3::new(0.0, -1.0, 0.0), DVec3::new(0.0, -half, 0.0)).unwrap();
        assert!(p.element(w).unwrap().painted.is_empty());
        assert!(paint_face(&mut p, w, DVec3::Y, DVec3::ZERO, "No Such Material").is_err());

        // Matchlines show in every plan; view references read detail / sheet.
        let ml = add_matchline(&mut p, DVec2::new(2000.0, -3000.0), DVec2::new(2000.0, 3000.0)).unwrap();
        for v in p.views.iter().filter(|v| v.plan_level().is_some()) {
            let d = crate::plan::floor_plan(&p, v, &fp);
            assert!(d.prims.iter().any(|(id, _)| *id == Some(ml)), "{} {:?} hidden={:?}", v.name, v.kind, v.hidden);
        }
        let plan = p.views.iter().find(|v| v.plan_level().is_some()).unwrap().id;
        assert_eq!(crate::plan::view_reference_label(&p, plan), p.view(plan).unwrap().name);
        let sheet = new_sheet(&mut p, SheetSize::A1);
        place_on_sheet(&mut p, sheet, plan, 200.0, 200.0).unwrap();
        let ViewKind::Sheet(sh) = &p.view(sheet).unwrap().kind else { panic!() };
        assert!(crate::plan::view_reference_label(&p, plan).ends_with(&sh.number));
    }

    #[test]
    fn detail_groups_live_in_their_view() {
        let (mut p, lvl, wt) = project();
        let view = p.views.iter().find(|v| v.plan_level().is_some()).unwrap().id;
        let a = add_line(&mut p, Some(view), None, vec![DVec2::ZERO, DVec2::new(1000.0, 0.0)], None, LineStyle::Thin).unwrap();
        let b = add_text(&mut p, view, DVec2::new(0.0, 300.0), "NOTE", 2.5).unwrap();
        let inst = create_group(&mut p, &[a, b], "Note").unwrap();
        let gt = p.group_types.iter().find(|g| g.name == "Note").unwrap().clone();
        assert!(gt.detail);
        assert_eq!(gt.members.len(), 2);
        assert_eq!(p.element(inst).unwrap().view, Some(view));
        assert!(place_group(&mut p, gt.id, DVec2::ZERO, lvl).is_err());
        let copy = place_detail_group(&mut p, gt.id, view, DVec2::new(5000.0, 0.0)).unwrap();
        let members: Vec<&Element> = p.elements.iter().filter(|e| e.group == Some(copy)).collect();
        assert_eq!(members.len(), 2);
        assert!(members.iter().all(|e| e.view == Some(view)));
        // A mixed selection makes a model group and an attached detail group.
        let w = add_wall(&mut p, lvl, wt, DVec2::new(0.0, 5000.0), DVec2::new(4000.0, 5000.0), 3000.0).unwrap();
        let c = add_line(&mut p, Some(view), None, vec![DVec2::new(0.0, 5500.0), DVec2::new(1000.0, 5500.0)], None, LineStyle::Thin).unwrap();
        let g = create_group(&mut p, &[w, c], "Room A").unwrap();
        assert_eq!(p.element(g).unwrap().view, None);
        assert!(p.group_types.iter().any(|t| t.name == "Room A - Detail" && t.detail));
        assert!(p.element(c).unwrap().group.is_some_and(|x| x != g));
    }

    #[test]
    fn global_parameters_drive_dimensions_and_parameters() {
        let (p, lvl, wt) = project();
        let mut doc = Document::new(p);
        let (a, b) = doc
            .transact("walls", |p| Ok((add_wall(p, lvl, wt, DVec2::new(0.0, 0.0), DVec2::new(0.0, 4000.0), 3000.0)?, add_wall(p, lvl, wt, DVec2::new(3000.0, 0.0), DVec2::new(3000.0, 4000.0), 3000.0)?)))
            .unwrap();
        let view = doc.data.views[0].id;
        // Width drives the dimension; Height = Width / 2 drives a wall parameter.
        doc.transact("globals", |p| {
            p.global_params.push(GlobalParameter { name: "Width".into(), kind: ParamKind::Length, value: 5000.0, ..Default::default() });
            p.global_params.push(GlobalParameter { name: "Height".into(), kind: ParamKind::Length, formula: "Width / 2".into(), ..Default::default() });
            let d = add_dimension(p, view, vec![DimRef { element: Some(a), part: RefPart::WallCenter, point: DVec2::new(0.0, 2000.0) }, DimRef { element: Some(b), part: RefPart::WallCenter, point: DVec2::new(3000.0, 2000.0) }], DVec2::X, DVec2::new(0.0, -1000.0))?;
            if let Some(Element { kind: ElementKind::Dimension(dm), .. }) = p.element_mut(d) {
                dm.label = "Width".into();
            }
            crate::params::set(p, a, "Top Constraint", "Unconnected")?;
            p.element_mut(a).unwrap().global_links.insert("Unconnected Height".into(), "Height".into());
            Ok(())
        })
        .unwrap();
        assert!((doc.data.wall(b).unwrap().start.x - 5000.0).abs() < 1e-6);
        assert!((doc.data.global("Height").unwrap().value - 2500.0).abs() < 1e-9);
        assert!((doc.data.wall(a).unwrap().unconnected_height - 2500.0).abs() < 1e-6);
        // Changing the global moves the wall and updates the linked height.
        doc.transact("edit", |p| {
            p.global_params[0].value = 6000.0;
            Ok(())
        })
        .unwrap();
        assert!((doc.data.wall(b).unwrap().start.x - 6000.0).abs() < 1e-6);
        assert!((doc.data.wall(a).unwrap().unconnected_height - 3000.0).abs() < 1e-6);
        // A self-referencing formula is refused.
        assert!(doc
            .transact("bad", |p| {
                p.global_params[1].formula = "Height + 1".into();
                Ok(())
            })
            .is_err());
    }
}
