//! Structure > Reinforcement: bar types, cover, area reinforcement and straight rebar sets.

use crate::analysis;
use crate::geom::{self, DVec2, DVec3};
use crate::mesh::MeshSet;
use crate::model::*;
use crate::units::UnitSystem;

/// The default concrete cover when the project sets none: 40 mm / 1 1/2".
pub fn cover(p: &Project) -> f64 {
    if p.rebar_cover > 0.0 {
        p.rebar_cover
    } else if p.units.system == UnitSystem::Imperial {
        38.1
    } else {
        40.0
    }
}

/// The project's rebar bar types (created on first use): 10M-25M, or #3-#6 in imperial.
pub fn ensure_bar_types(p: &mut Project) -> Vec<Id> {
    let have: Vec<Id> = p.types.iter().filter(|t| t.category == Category::StructuralRebar).map(|t| t.id).collect();
    if !have.is_empty() {
        return have;
    }
    let sizes: [(&str, f64); 4] = if p.units.system == UnitSystem::Imperial {
        [("#3", 9.525), ("#4", 12.7), ("#5", 15.875), ("#6", 19.05)]
    } else {
        [("10M", 11.3), ("15M", 16.0), ("20M", 19.5), ("25M", 25.2)]
    };
    sizes
        .iter()
        .map(|(name, d)| {
            let id = p.new_id();
            let mut t = SystemType { id, category: Category::StructuralRebar, name: name.to_string(), ..Default::default() };
            t.props.insert("Bar Diameter".into(), *d);
            t.texts.insert("Material".into(), "Steel".into());
            p.types.push(t);
            id
        })
        .collect()
}

pub fn bar_diameter(p: &Project, bar_type: Id) -> f64 {
    p.sys_type(bar_type).map(|t| t.prop("Bar Diameter", 12.0)).unwrap_or(12.0)
}

pub fn bar_name(p: &Project, bar_type: Id) -> String {
    p.sys_type(bar_type).map(|t| t.name.clone()).unwrap_or_default()
}

/// The host's (bottom z, top z) for a floor or structural foundation slab.
fn host_z(p: &Project, host: Id) -> Option<(f64, f64)> {
    match &p.element(host)?.kind {
        ElementKind::Floor(f) => {
            let top = analysis::floor_top_z(p, f);
            Some((top - analysis::floor_thickness(p, f), top))
        }
        _ => None,
    }
}

/// Lines across a polygon parallel to `dir` at `spacing`, centred across it.
fn hatch(poly: &[DVec2], dir: DVec2, spacing: f64) -> Vec<(DVec2, DVec2)> {
    let n = geom::perp(dir);
    let o = poly[0];
    let across: Vec<f64> = poly.iter().map(|q| (*q - o).dot(n)).collect();
    let (lo, hi) = across.iter().fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(*v), b.max(*v)));
    if spacing <= 1.0 || hi - lo < 1.0 {
        return vec![];
    }
    let count = ((hi - lo) / spacing).floor() as usize + 1;
    let first = lo + (hi - lo - (count - 1) as f64 * spacing) / 2.0;
    let mut out = Vec::new();
    for k in 0..count {
        let base = o + n * (first + k as f64 * spacing);
        let mut ts: Vec<f64> = Vec::new();
        for i in 0..poly.len() {
            let (a, b) = (poly[i], poly[(i + 1) % poly.len()]);
            let (da, db) = ((a - base).dot(n), (b - base).dot(n));
            if (da > 0.0) != (db > 0.0) {
                let t = da / (da - db);
                ts.push((a + (b - a) * t - base).dot(dir));
            }
        }
        ts.sort_by(|a, b| a.total_cmp(b));
        for w in ts.chunks(2) {
            if w.len() == 2 && w[1] - w[0] > 1.0 {
                out.push((base + dir * w[0], base + dir * w[1]));
            }
        }
    }
    out
}

/// The bars of an area reinforcement: (start, end, diameter), each layer inside the cover.
pub fn area_bars(p: &Project, a: &AreaReinforcement) -> Vec<(DVec3, DVec3, f64)> {
    let Some((zb, zt)) = host_z(p, a.host) else { return vec![] };
    let c = cover(p);
    let inner = geom::offset(&geom::ensure_ccw(&a.boundary), -c);
    if inner.len() < 3 || geom::area(&inner).abs() < 1.0 {
        return vec![];
    }
    let major = a.major.normalize_or(DVec2::X);
    let minor = geom::perp(major);
    let mut out = Vec::new();
    // Layers: top major (outermost), top minor, bottom major (outermost), bottom minor.
    let d = |k: usize| bar_diameter(p, a.layers[k].bar_type);
    let zs = [zt - c - d(0) / 2.0, zt - c - d(0) - d(1) / 2.0, zb + c + d(2) / 2.0, zb + c + d(2) + d(3) / 2.0];
    for k in 0..4 {
        let l = &a.layers[k];
        if !l.on {
            continue;
        }
        let dir = if k % 2 == 0 { major } else { minor };
        for (s, e) in hatch(&inner, dir, l.spacing) {
            out.push((geom::at(s, zs[k]), geom::at(e, zs[k]), d(k)));
        }
    }
    out
}

/// A straight rebar set: `count` bars `spacing` apart, to the left of start→end, at the
/// bottom cover of the host.
pub fn rebar_bars(p: &Project, r: &Rebar) -> Vec<(DVec3, DVec3, f64)> {
    let Some((zb, _)) = host_z(p, r.host) else { return vec![] };
    let d = bar_diameter(p, r.bar_type);
    let z = zb + cover(p) + d / 2.0;
    let n = geom::perp((r.end - r.start).normalize_or_zero());
    (0..r.count.max(1)).map(|k| {
        let off = n * (r.spacing * k as f64);
        (geom::at(r.start + off, z), geom::at(r.end + off, z), d)
    }).collect()
}

/// The z of a top or bottom layer of bars of diameter `d` (`below` = diameters of bars laid
/// outside it).
fn layer_z(p: &Project, host: Id, top: bool, d: f64, below: f64) -> Option<f64> {
    let (zb, zt) = host_z(p, host)?;
    let c = cover(p) + below;
    Some(if top { zt - c - d / 2.0 } else { zb + c + d / 2.0 })
}

/// Which side of the path (+1 left, -1 right) the bars run to: into the host.
pub fn path_side(p: &Project, r: &PathReinforcement) -> f64 {
    let side = match (p.element(r.host).map(|e| &e.kind), r.path.first(), r.path.get(1)) {
        (Some(ElementKind::Floor(f)), Some(a), Some(b)) => {
            let n = geom::perp((*b - *a).normalize_or_zero());
            if geom::contains(&f.boundary, (*a + *b) / 2.0 + n * r.length.min(600.0) / 2.0) { 1.0 } else { -1.0 }
        }
        _ => 1.0,
    };
    if r.flip { -side } else { side }
}

/// The bars of a path reinforcement, centred along each segment of the path.
pub fn path_bars(p: &Project, r: &PathReinforcement) -> Vec<(DVec3, DVec3, f64)> {
    let d = bar_diameter(p, r.bar_type);
    let Some(z) = layer_z(p, r.host, r.top, d, 0.0) else { return vec![] };
    let side = path_side(p, r);
    let mut out = Vec::new();
    for w in r.path.windows(2) {
        let len = w[0].distance(w[1]);
        if len < 1.0 || r.spacing < 1.0 {
            continue;
        }
        let dir = (w[1] - w[0]) / len;
        let n = geom::perp(dir) * side;
        let count = (len / r.spacing).floor() as usize + 1;
        let first = (len - (count - 1) as f64 * r.spacing) / 2.0;
        for k in 0..count {
            let q = w[0] + dir * (first + k as f64 * r.spacing);
            out.push((geom::at(q, z), geom::at(q + n * r.length, z), d));
        }
    }
    out
}

/// The strips a path reinforcement covers, one per path segment.
pub fn path_region(p: &Project, r: &PathReinforcement) -> Vec<Vec<DVec2>> {
    let side = path_side(p, r);
    r.path.windows(2).map(|w| {
        let n = geom::perp((w[1] - w[0]).normalize_or_zero()) * side * r.length;
        vec![w[0], w[1], w[1] + n, w[0] + n]
    }).collect()
}

/// The tag of a path reinforcement, as "15M @ 300".
pub fn path_tag(p: &Project, r: &PathReinforcement) -> String {
    format!("{} @ {}", bar_name(p, r.bar_type), p.units.length(r.spacing))
}

/// The project's fabric sheet type (made on first use): 4800 x 2400 at 200 / 12'-6" x 8'-0" at 1'-0".
pub fn ensure_fabric_types(p: &mut Project) -> Id {
    if let Some(t) = p.types.iter().find(|t| t.category == Category::FabricReinforcement) {
        return t.id;
    }
    let (l, w, s, dia, lap) = if p.units.system == UnitSystem::Imperial { (3810.0, 2438.4, 304.8, 4.9, 203.2) } else { (4800.0, 2400.0, 200.0, 6.0, 200.0) };
    let id = p.new_id();
    let mut t = SystemType { id, category: Category::FabricReinforcement, name: "Fabric Sheet 1".into(), ..Default::default() };
    for (k, v) in [("Overall Length", l), ("Overall Width", w), ("Major Spacing", s), ("Minor Spacing", s), ("Wire Diameter", dia), ("Default Major Lap Splice Length", lap), ("Default Minor Lap Splice Length", lap)] {
        t.props.insert(k.into(), v);
    }
    t.texts.insert("Material".into(), "Steel".into());
    p.types.push(t);
    id
}

/// (length, width, major spacing, minor spacing, wire diameter) of a fabric sheet type.
pub fn sheet_size(p: &Project, type_id: Id) -> (f64, f64, f64, f64, f64) {
    let t = p.sys_type(type_id);
    let g = |k: &str, d: f64| t.map(|t| t.prop(k, d)).unwrap_or(d);
    (g("Overall Length", 4800.0), g("Overall Width", 2400.0), g("Major Spacing", 200.0), g("Minor Spacing", 200.0), g("Wire Diameter", 6.0))
}

/// The outline of a sheet of `length` x `width` centred at `c`, its length along `dir`.
pub fn sheet_rect(c: DVec2, dir: DVec2, length: f64, width: f64) -> Vec<DVec2> {
    let (u, v) = (dir * (length / 2.0), geom::perp(dir) * (width / 2.0));
    vec![c - u - v, c + u - v, c + u + v, c - u + v]
}

/// The wires of a fabric piece (an outline), major wires along `dir`.
fn sheet_wires(p: &Project, host: Id, top: bool, type_id: Id, piece: &[DVec2], dir: DVec2) -> Vec<(DVec3, DVec3, f64)> {
    let (_, _, smaj, smin, d) = sheet_size(p, type_id);
    let (Some(z0), Some(z1)) = (layer_z(p, host, top, d, 0.0), layer_z(p, host, top, d, d)) else { return vec![] };
    let mut out: Vec<(DVec3, DVec3, f64)> = hatch(piece, dir, smaj).into_iter().map(|(a, b)| (geom::at(a, z0), geom::at(b, z0), d)).collect();
    out.extend(hatch(piece, geom::perp(dir), smin).into_iter().map(|(a, b)| (geom::at(a, z1), geom::at(b, z1), d)));
    out
}

pub fn fabric_sheet_wires(p: &Project, s: &FabricSheet) -> Vec<(DVec3, DVec3, f64)> {
    let (l, w, ..) = sheet_size(p, s.type_id);
    let dir = DVec2::from_angle(s.angle.to_radians());
    sheet_wires(p, s.host, s.top, s.type_id, &sheet_rect(s.center, dir, l, w), dir)
}

/// The sheets of a fabric area: lapped tiles along the major direction, cut to the boundary
/// inside the cover.
pub fn fabric_area_sheets(p: &Project, a: &FabricArea) -> Vec<Vec<DVec2>> {
    use geo::BooleanOps;
    let inner = geom::offset(&geom::ensure_ccw(&a.boundary), -cover(p));
    if inner.len() < 3 {
        return vec![];
    }
    let (l, w, ..) = sheet_size(p, a.type_id);
    let dir = a.major.normalize_or(DVec2::X);
    let n = geom::perp(dir);
    let (su, sv) = ((l - a.major_lap).max(100.0), (w - a.minor_lap).max(100.0));
    let o = inner[0];
    let us: Vec<f64> = inner.iter().map(|q| (*q - o).dot(dir)).collect();
    let vs: Vec<f64> = inner.iter().map(|q| (*q - o).dot(n)).collect();
    let (u0, u1) = us.iter().fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(*v), b.max(*v)));
    let (v0, v1) = vs.iter().fold((f64::MAX, f64::MIN), |(a, b), v| (a.min(*v), b.max(*v)));
    let to = |pts: &[DVec2]| geo::Polygon::new(geo::LineString::from(pts.iter().map(|q| geo::Coord { x: q.x, y: q.y }).collect::<Vec<_>>()), vec![]);
    let area = geo::MultiPolygon::new(vec![to(&inner)]);
    let mut out = Vec::new();
    let mut u = u0;
    while u < u1 - 1.0 && out.len() < 2000 {
        let mut v = v0;
        while v < v1 - 1.0 {
            let c = o + dir * (u + l / 2.0) + n * (v + w / 2.0);
            let tile = geo::MultiPolygon::new(vec![to(&geom::ensure_ccw(&sheet_rect(c, dir, l, w)))]);
            for poly in tile.intersection(&area).0 {
                let mut pts: Vec<DVec2> = poly.exterior().coords().map(|c| DVec2::new(c.x, c.y)).collect();
                pts.pop();
                if pts.len() >= 3 && geom::area(&pts).abs() > 1000.0 {
                    out.push(pts);
                }
            }
            v += sv;
        }
        u += su;
    }
    out
}

pub fn fabric_area_wires(p: &Project, a: &FabricArea) -> Vec<(DVec3, DVec3, f64)> {
    let dir = a.major.normalize_or(DVec2::X);
    fabric_area_sheets(p, a).iter().flat_map(|s| sheet_wires(p, a.host, a.top, a.type_id, s, dir)).collect()
}

/// Couplers: (centre, bar axis, bar diameter), one per bar of the set.
pub fn coupler_points(p: &Project, c: &RebarCoupler) -> Vec<(DVec3, DVec3, f64)> {
    let Some(ElementKind::Rebar(r)) = p.element(c.rebar).map(|e| &e.kind) else { return vec![] };
    rebar_bars(p, r).into_iter().map(|(a, b, d)| (if c.at_end { b } else { a }, (b - a).normalize_or_zero(), d)).collect()
}

/// Couplers as sleeves: 4 bar diameters long, 1.6 wide.
pub fn couplers_mesh(pts: &[(DVec3, DVec3, f64)]) -> MeshSet {
    let sleeves: Vec<(DVec3, DVec3, f64)> = pts.iter().map(|(c, ax, d)| (*c - *ax * 2.0 * d, *c + *ax * 2.0 * d, 1.6 * d)).collect();
    bars_mesh(&sleeves)
}

/// Bars as octagonal rods.
pub fn bars_mesh(bars: &[(DVec3, DVec3, f64)]) -> MeshSet {
    let mut set = MeshSet::default();
    let m = set.mesh("Steel");
    for (a, b, d) in bars {
        let axis = (*b - *a).normalize_or_zero();
        if axis == DVec3::ZERO {
            continue;
        }
        let u = if axis.z.abs() < 0.9 { axis.cross(DVec3::Z).normalize() } else { axis.cross(DVec3::X).normalize() };
        let v = axis.cross(u);
        let r = d / 2.0;
        let ring = |c: DVec3| -> Vec<DVec3> { (0..8).map(|k| { let t = k as f64 * std::f64::consts::TAU / 8.0; c + (u * t.cos() + v * t.sin()) * r }).collect() };
        let (ra, rb) = (ring(*a), ring(*b));
        for k in 0..8 {
            let j = (k + 1) % 8;
            let mid = (ra[k] + ra[j]) / 2.0 - *a;
            m.add_quad_facing(ra[k], ra[j], rb[j], rb[k], mid);
        }
        m.add_polygon_facing(&ra, -axis);
        m.add_polygon_facing(&rb, axis);
    }
    set
}

/// The tag text of an area reinforcement, as "(T) 15M@300 EW (B) 15M@300 EW".
pub fn area_tag(p: &Project, a: &AreaReinforcement) -> String {
    let face = |i: usize, tag: &str| -> Option<String> {
        let (maj, min) = (&a.layers[i], &a.layers[i + 1]);
        let s = |l: &RebarLayer| format!("{}@{}", bar_name(p, l.bar_type), p.units.length(l.spacing));
        match (maj.on, min.on) {
            (true, true) if maj.bar_type == min.bar_type && (maj.spacing - min.spacing).abs() < 1e-6 => Some(format!("({tag}) {} EW", s(maj))),
            (true, true) => Some(format!("({tag}) {} / {}", s(maj), s(min))),
            (true, false) => Some(format!("({tag}) {}", s(maj))),
            (false, true) => Some(format!("({tag}) {}", s(min))),
            _ => None,
        }
    };
    [face(0, "T"), face(2, "B")].into_iter().flatten().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_fabric_and_couplers_lay_out_their_bars() {
        let mut p = crate::defaults::new_project(UnitSystem::Metric);
        let l1 = p.levels()[0].0;
        let ft = p.types_of(Category::Floors).next().unwrap().id;
        let sq = vec![DVec2::ZERO, DVec2::new(6000.0, 0.0), DVec2::new(6000.0, 4000.0), DVec2::new(0.0, 4000.0)];
        let floor = crate::edit::add_floor(&mut p, l1, ft, sq.clone()).unwrap();
        let bt = ensure_bar_types(&mut p)[1];
        // A path along the south edge, drawn west to east: bars run north, into the slab.
        let path = crate::edit::add_path_reinforcement(&mut p, floor, vec![DVec2::new(0.0, 0.0), DVec2::new(3000.0, 0.0)], bt, 300.0, 1800.0).unwrap();
        let Some(ElementKind::PathReinforcement(r)) = p.element(path).map(|e| e.kind.clone()) else { panic!() };
        let bars = path_bars(&p, &r);
        assert_eq!(bars.len(), 11);
        assert!(bars.iter().all(|(a, b, _)| (b.y - a.y - 1800.0).abs() < 1e-6));
        // A fabric area over the slab: 2 x 2 lapped 4800 x 2400 sheets cover 5920 x 3920.
        let fa = crate::edit::add_fabric_area(&mut p, floor, sq).unwrap();
        let Some(ElementKind::FabricArea(a)) = p.element(fa).map(|e| e.kind.clone()) else { panic!() };
        assert_eq!(fabric_area_sheets(&p, &a).len(), 4);
        assert!(!fabric_area_wires(&p, &a).is_empty());
        // Couplers on the bar ends of a two-bar set.
        let rb = crate::edit::add_rebar(&mut p, floor, DVec2::new(500.0, 1000.0), DVec2::new(2500.0, 1000.0), bt, 2, 200.0).unwrap();
        let c = crate::edit::add_coupler(&mut p, rb, true, None).unwrap();
        let Some(ElementKind::RebarCoupler(cp)) = p.element(c).map(|e| e.kind.clone()) else { panic!() };
        let pts = coupler_points(&p, &cp);
        assert_eq!(pts.len(), 2);
        assert!((pts[0].0.x - 2500.0).abs() < 1e-6);
        crate::edit::delete_elements(&mut p, &[rb]).unwrap();
        assert!(p.element(c).is_none());
    }

    #[test]
    fn area_reinforcement_bars_sit_inside_the_cover_in_four_layers() {
        let mut p = crate::defaults::new_project(UnitSystem::Metric);
        let l1 = p.levels()[0].0;
        let ft = p.types_of(Category::Floors).next().unwrap().id;
        let sq = vec![DVec2::ZERO, DVec2::new(3000.0, 0.0), DVec2::new(3000.0, 2000.0), DVec2::new(0.0, 2000.0)];
        let floor = crate::edit::add_floor(&mut p, l1, ft, sq.clone()).unwrap();
        let bt = ensure_bar_types(&mut p)[1];
        let id = crate::edit::add_area_reinforcement(&mut p, floor, sq, bt, 300.0).unwrap();
        let Some(ElementKind::AreaReinforcement(a)) = p.element(id).map(|e| e.kind.clone()) else { panic!() };
        let bars = area_bars(&p, &a);
        // Major bars (along x) across 2000 - 2 x 40 at 300: 7; minor (along y) across 2920: 10.
        assert_eq!(bars.len(), 2 * (7 + 10), "{}", bars.len());
        let Some(ElementKind::Floor(f)) = p.element(floor).map(|e| e.kind.clone()) else { panic!() };
        let top = analysis::floor_top_z(&p, &f);
        let zmax = bars.iter().map(|b| b.0.z).fold(f64::MIN, f64::max);
        assert!((zmax - (top - 40.0 - 8.0)).abs() < 1e-6, "{zmax}");
        assert!(bars.iter().all(|(s, e, _)| s.x >= 40.0 - 1e-6 && e.x <= 2960.0 + 1e-6 && s.y >= 40.0 - 1e-6 && e.y <= 1960.0 + 1e-6));
        assert_eq!(area_tag(&p, &a), "(T) 15M@300 EW (B) 15M@300 EW");
    }
}
