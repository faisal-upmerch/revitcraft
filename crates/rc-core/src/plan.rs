//! 2D graphics for plan-type views (floor, ceiling and area plans, drafting views and legends),
//! annotation drawing, and plan hit-testing. Shared by the plan view, sheets, PDF and DXF export.

use crate::analysis::{self, Footprint, PhaseStatus};
use crate::annotation;
use crate::build3d;
use crate::family_geom::{self, SymStyle};
use crate::geom::{self, DVec2};
use crate::model::*;
use geo::{BooleanOps, Coord, LineString, MultiPolygon, Polygon, TriangulateEarcut};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Dash {
    #[default]
    Solid,
    Dashed,
    DashDot,
    Dotted,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Stroke {
    /// Line weight in paper millimetres.
    pub width: f32,
    pub color: [u8; 3],
    pub dash: Dash,
}

impl Stroke {
    pub const fn new(width: f32, color: [u8; 3], dash: Dash) -> Stroke {
        Stroke { width, color, dash }
    }
    pub fn dashed(&self) -> bool {
        self.dash != Dash::Solid
    }
    pub fn with_dash(self, dash: Dash) -> Stroke {
        Stroke { dash, ..self }
    }
}

pub const HEAVY: Stroke = Stroke::new(0.5, [0, 0, 0], Dash::Solid);
pub const MEDIUM: Stroke = Stroke::new(0.25, [0, 0, 0], Dash::Solid);
pub const THIN: Stroke = Stroke::new(0.13, [60, 60, 60], Dash::Solid);
pub const HIDDEN: Stroke = Stroke::new(0.18, [90, 90, 90], Dash::Dashed);
pub const GRID: Stroke = Stroke::new(0.13, [0, 0, 0], Dash::DashDot);
pub const REFPLANE: Stroke = Stroke::new(0.13, [30, 140, 60], Dash::DashDot);
pub const ANNO: Stroke = Stroke::new(0.18, [0, 0, 0], Dash::Solid);
pub const HALFTONE: [u8; 3] = [165, 165, 165];

pub fn line_style_stroke(s: LineStyle) -> Stroke {
    match s {
        LineStyle::Thin => THIN,
        LineStyle::Medium => MEDIUM,
        LineStyle::Wide => HEAVY,
        LineStyle::Hidden => HIDDEN,
        LineStyle::Dashed => Stroke::new(0.25, [0, 0, 0], Dash::Dashed),
        LineStyle::Centre => Stroke::new(0.13, [0, 0, 0], Dash::DashDot),
        LineStyle::Overhead => Stroke::new(0.18, [0, 0, 0], Dash::Dashed),
        LineStyle::Demolished => Stroke::new(0.18, [0, 0, 0], Dash::Dotted),
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Anchor {
    Center,
    Left,
}

#[derive(Clone, Debug)]
pub enum Prim {
    Line { pts: Vec<DVec2>, closed: bool, stroke: Stroke },
    Fill { tris: Vec<[DVec2; 3]>, color: [u8; 4] },
    /// Text height is in paper millimetres; angle in radians (counter-clockwise).
    Text { pos: DVec2, text: String, size: f32, color: [u8; 3], anchor: Anchor, angle: f32 },
}

#[derive(Clone, Debug, Default)]
pub struct Drawing {
    /// Primitives in paint order, tagged with the element they belong to.
    pub prims: Vec<(Option<Id>, Prim)>,
    /// Crop region (world coordinates) when the view's crop is active.
    pub crop: Option<(DVec2, DVec2)>,
}

impl Drawing {
    pub fn line(&mut self, id: Option<Id>, pts: Vec<DVec2>, closed: bool, stroke: Stroke) {
        if pts.len() >= 2 {
            self.prims.push((id, Prim::Line { pts, closed, stroke }));
        }
    }
    pub fn text(&mut self, id: Option<Id>, pos: DVec2, text: impl Into<String>, size: f32, anchor: Anchor) {
        self.prims.push((id, Prim::Text { pos, text: text.into(), size, color: [0, 0, 0], anchor, angle: 0.0 }));
    }
    pub fn text_rot(&mut self, id: Option<Id>, pos: DVec2, text: impl Into<String>, size: f32, angle: f32) {
        self.prims.push((id, Prim::Text { pos, text: text.into(), size, color: [0, 0, 0], anchor: Anchor::Center, angle }));
    }
    pub fn fill(&mut self, id: Option<Id>, poly: &[DVec2], color: [u8; 4]) {
        if poly.len() < 3 {
            return;
        }
        let tris = geom::triangulate(poly).into_iter().map(|[a, b, c]| [poly[a], poly[b], poly[c]]).collect();
        self.prims.push((id, Prim::Fill { tris, color }));
    }

    pub fn bounds(&self) -> Option<(DVec2, DVec2)> {
        if let Some(c) = self.crop {
            return Some(c);
        }
        let pts = self.prims.iter().flat_map(|(_, p)| match p {
            Prim::Line { pts, .. } => pts.clone(),
            Prim::Fill { tris, .. } => tris.iter().flatten().copied().collect(),
            Prim::Text { pos, .. } => vec![*pos],
        });
        let (mn, mx) = geom::bounds(pts);
        (mn.x <= mx.x).then_some((mn, mx))
    }

    /// Recolours and/or reweights every primitive of an element (overrides, halftone, phases).
    fn restyle(&mut self, from: usize, color: Option<[u8; 3]>, weight: Option<f32>, dash: Option<Dash>) {
        for (_, p) in &mut self.prims[from..] {
            match p {
                Prim::Line { stroke, .. } => {
                    if let Some(c) = color {
                        stroke.color = c;
                    }
                    if let Some(w) = weight {
                        stroke.width = w;
                    }
                    if let Some(d) = dash {
                        stroke.dash = d;
                    }
                }
                Prim::Text { color: tc, .. } => {
                    if let Some(c) = color {
                        *tc = c;
                    }
                }
                Prim::Fill { color: fc, .. } => {
                    if let Some(c) = color {
                        fc[0] = ((fc[0] as u16 + c[0] as u16 * 2) / 3) as u8;
                        fc[1] = ((fc[1] as u16 + c[1] as u16 * 2) / 3) as u8;
                        fc[2] = ((fc[2] as u16 + c[2] as u16 * 2) / 3) as u8;
                    }
                }
            }
        }
    }
}

/// Applies Manage > Object Styles to a finished drawing. Heavy strokes (≥ 0.45 mm) are cut
/// lines; lighter ones are projection lines.
pub fn apply_object_styles(p: &Project, d: &mut Drawing) {
    if p.object_styles.is_empty() {
        return;
    }
    let cats: HashMap<Id, Category> = p.elements.iter().map(|e| (e.id, e.category())).collect();
    for (id, prim) in &mut d.prims {
        let Some(style) = id.and_then(|i| cats.get(&i)).and_then(|c| p.object_styles.get(c)) else { continue };
        match prim {
            Prim::Line { stroke, .. } => {
                // Halftone and phase colours stay as drawn.
                let default_color = stroke.color == [0, 0, 0] || stroke.color == [60, 60, 60] || stroke.color == [90, 90, 90];
                if let (Some(c), true) = (style.color, default_color) {
                    stroke.color = c;
                }
                let cut = stroke.width >= 0.45;
                if let Some(w) = if cut { style.cut_weight } else { style.projection_weight } {
                    stroke.width = w;
                }
                if let Some(pat) = style.pattern {
                    stroke.dash = match pat {
                        1 => Dash::Dashed,
                        2 => Dash::DashDot,
                        3 => Dash::Dotted,
                        _ => Dash::Solid,
                    };
                }
            }
            Prim::Text { color, .. } => {
                if let (Some(c), true) = (style.color, *color == [0, 0, 0]) {
                    *color = c;
                }
            }
            Prim::Fill { .. } => {}
        }
    }
}

fn to_geo(pts: &[DVec2]) -> Polygon<f64> {
    Polygon::new(LineString::from(pts.iter().map(|p| Coord { x: p.x, y: p.y }).collect::<Vec<_>>()), vec![])
}

fn rings(mp: &MultiPolygon<f64>) -> Vec<Vec<DVec2>> {
    let mut out = Vec::new();
    for poly in mp {
        for ring in std::iter::once(poly.exterior()).chain(poly.interiors()) {
            let mut pts: Vec<DVec2> = ring.coords().map(|c| DVec2::new(c.x, c.y)).collect();
            if pts.len() > 1 && pts[0] == pts[pts.len() - 1] {
                pts.pop();
            }
            if pts.len() >= 3 {
                out.push(pts);
            }
        }
    }
    out
}

fn fill_tris(mp: &MultiPolygon<f64>) -> Vec<[DVec2; 3]> {
    mp.iter()
        .flat_map(|poly| poly.earcut_triangles())
        .map(|t| {
            let [a, b, c] = t.to_array();
            [DVec2::new(a.x, a.y), DVec2::new(b.x, b.y), DVec2::new(c.x, c.y)]
        })
        .collect()
}

/// Colour of a room in the "by Name" colour scheme: every room with the same name shares it.
pub fn room_name_color(name: &str) -> [u8; 4] {
    const PALETTE: [[u8; 3]; 12] = [
        [255, 204, 153],
        [204, 255, 204],
        [153, 204, 255],
        [255, 179, 217],
        [221, 187, 255],
        [255, 255, 170],
        [170, 238, 238],
        [221, 204, 187],
        [255, 170, 170],
        [187, 221, 136],
        [170, 187, 238],
        [238, 221, 170],
    ];
    let mut h: u32 = 2166136261;
    for b in name.trim().to_lowercase().bytes() {
        h = (h ^ b as u32).wrapping_mul(16777619);
    }
    let c = PALETTE[(h as usize) % PALETTE.len()];
    [c[0], c[1], c[2], 160]
}


pub fn circle(c: DVec2, r: f64, n: usize) -> Vec<DVec2> {
    (0..n).map(|k| {
        let a = k as f64 / n as f64 * std::f64::consts::TAU;
        c + DVec2::new(a.cos(), a.sin()) * r
    }).collect()
}

/// Hatch segments of a polygon (even-odd) at `angle` (radians) and `spacing`.
pub fn hatch(poly: &[DVec2], angle: f64, spacing: f64) -> Vec<(DVec2, DVec2)> {
    if poly.len() < 3 || spacing <= 0.0 {
        return vec![];
    }
    let d = DVec2::new(angle.cos(), angle.sin());
    let n = geom::perp(d);
    let ds: Vec<f64> = poly.iter().map(|p| p.dot(n)).collect();
    let (lo, hi) = (ds.iter().cloned().fold(f64::MAX, f64::min), ds.iter().cloned().fold(f64::MIN, f64::max));
    let mut out = Vec::new();
    let mut k = (lo / spacing).ceil() * spacing;
    let mut guard = 0;
    while k < hi && guard < 2000 {
        guard += 1;
        let mut ts = Vec::new();
        for i in 0..poly.len() {
            let (a, b) = (poly[i], poly[(i + 1) % poly.len()]);
            let (da, db) = (a.dot(n) - k, b.dot(n) - k);
            if (da > 0.0) != (db > 0.0) {
                let q = a.lerp(b, da / (da - db));
                ts.push(q.dot(d));
            }
        }
        ts.sort_by(f64::total_cmp);
        for pair in ts.chunks(2) {
            if pair.len() == 2 {
                out.push((d * pair[0] + n * k, d * pair[1] + n * k));
            }
        }
        k += spacing;
    }
    out
}

/// Hatch lines for a fill pattern (spacings in paper mm, scaled to the model by `scale`).
pub fn pattern_lines(poly: &[DVec2], pattern: FillPattern, scale: f64) -> Vec<(DVec2, DVec2)> {
    let s = scale;
    match pattern {
        FillPattern::Solid | FillPattern::Masking => vec![],
        FillPattern::Diagonal => hatch(poly, std::f64::consts::FRAC_PI_4, 1.5 * s),
        FillPattern::CrossHatch => {
            let mut v = hatch(poly, std::f64::consts::FRAC_PI_4, 1.5 * s);
            v.extend(hatch(poly, -std::f64::consts::FRAC_PI_4, 1.5 * s));
            v
        }
        FillPattern::Brick => hatch(poly, std::f64::consts::FRAC_PI_4, 0.8 * s),
        FillPattern::Concrete => {
            let mut v = hatch(poly, 0.6, 2.4 * s);
            v.extend(hatch(poly, 2.2, 3.1 * s));
            v
        }
        FillPattern::Insulation => {
            let mut v = hatch(poly, 1.2, 1.0 * s);
            v.extend(hatch(poly, -1.2, 1.0 * s));
            v
        }
    }
}

struct Ctx<'a> {
    p: &'a Project,
    view: &'a View,
    level: Id,
    level_z: f64,
    cut_z: f64,
    bottom_z: f64,
    top_z: f64,
    scale: f64,
    footprints: &'a HashMap<Id, Footprint>,
}

impl Ctx<'_> {
    fn status(&self, e: &Element) -> PhaseStatus {
        analysis::phase_status(self.p, self.view, e)
    }
}

/// Builds the drawing for a plan-type view.
pub fn floor_plan(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Drawing {
    let mut d = Drawing::default();
    if view.crop_active {
        d.crop = view.crop;
    }
    let level = view.plan_level();
    let ceiling_plan = matches!(view.kind, ViewKind::CeilingPlan { .. });
    if let Some(level) = level {
        let level_z = p.level_elevation(level);
        let cut = match view.kind {
            ViewKind::FloorPlan { cut_height, .. } if (view.view_range.cut - 1200.0).abs() < 1e-6 => cut_height,
            _ => view.view_range.cut,
        };
        let ctx = Ctx {
            p,
            view,
            level,
            level_z,
            cut_z: level_z + cut,
            bottom_z: level_z + view.view_range.bottom - view.view_range.depth,
            top_z: level_z + view.view_range.top.max(cut),
            scale: view.scale,
            footprints,
        };
        if let Some(u) = view.underlay {
            underlay(&ctx, u, &mut d);
        }
        if ceiling_plan {
            ceiling_plan_graphics(&ctx, &mut d);
        } else {
            model_graphics(&ctx, &mut d);
        }
    }
    annotation_graphics(p, view, footprints, &mut d);
    d
}

fn model_graphics(c: &Ctx, d: &mut Drawing) {
    let p = c.p;
    let view = c.view;
    let room_colors = matches!(view.kind, ViewKind::FloorPlan { room_colors: true, .. });
    let area_plan = match view.kind {
        ViewKind::AreaPlan { scheme, .. } => Some(scheme),
        _ => None,
    };
    let visible = |e: &Element| analysis::visible_in(p, view, e);

    // Rooms or areas (fills first).
    let mut tags = Vec::new();
    for e in &p.elements {
        if !visible(e) {
            continue;
        }
        match &e.kind {
            ElementKind::Room(r) if r.level == c.level && area_plan.is_none() => {
                let b = analysis::room_boundary(p, r);
                if let (Some(b), true) = (&b, room_colors) {
                    d.fill(Some(e.id), &b.interior, room_name_color(&r.name));
                }
                let _ = b;
            }
            ElementKind::Area(a) if a.level == c.level && area_plan == Some(a.scheme) => {
                let b = analysis::area_boundary(p, a);
                if let Some(b) = &b {
                    d.fill(Some(e.id), &b.centerline, [200, 170, 230, 110]);
                }
                tags.push((e.id, a.name.clone(), a.number.clone(), b.map(|b| geom::area(&b.centerline)), a.location));
            }
            _ => {}
        }
    }

    // Floors and ceilings below the cut seen in projection; floor edges.
    for e in &p.elements {
        if !visible(e) {
            continue;
        }
        let start = d.prims.len();
        match &e.kind {
            ElementKind::Floor(f) if f.level == c.level && f.boundary.len() >= 3 => {
                d.line(Some(e.id), f.boundary.clone(), true, THIN);
                for h in &f.holes {
                    d.line(Some(e.id), h.clone(), true, THIN);
                }
            }
            ElementKind::Mass(m) if m.boundary.len() >= 3 => {
                let z0 = p.level_elevation(m.level) + m.base_offset;
                if z0 <= c.cut_z && z0 + m.height >= p.level_elevation(c.level) {
                    d.line(Some(e.id), m.boundary.clone(), true, MEDIUM);
                }
            }
            ElementKind::Toposolid(t) if t.boundary.len() >= 3 && p.level_elevation(t.level) <= c.cut_z => {
                let interval = if p.units.system == crate::units::UnitSystem::Imperial { 1524.0 } else { 1000.0 };
                for (a, b, major) in analysis::topo_contours(p, t, interval) {
                    d.line(Some(e.id), vec![a, b], false, if major { Stroke::new(0.25, [70, 70, 70], Dash::Solid) } else { Stroke::new(0.13, [130, 130, 130], Dash::Solid) });
                }
                d.line(Some(e.id), t.boundary.clone(), true, MEDIUM);
            }
            ElementKind::PropertyLine(l) if l.boundary.len() >= 2 => {
                d.line(Some(e.id), l.boundary.clone(), true, Stroke::new(0.35, [0, 0, 0], Dash::DashDot));
            }
            ElementKind::Shaft(s) if s.base_level == c.level || shaft_spans(p, s, c.cut_z) => {
                d.line(Some(e.id), s.boundary.clone(), true, MEDIUM);
                if s.boundary.len() >= 3 {
                    let (mn, mx) = geom::bounds(s.boundary.iter().copied());
                    d.line(Some(e.id), vec![mn, mx], false, THIN);
                    d.line(Some(e.id), vec![DVec2::new(mn.x, mx.y), DVec2::new(mx.x, mn.y)], false, THIN);
                }
            }
            _ => {}
        }
        style_element(c, e, d, start);
    }

    walls_graphics(c, d);
    stairs_graphics(c, d);

    // Roofs: overhead (dashed) when above the cut on this level, projection when below.
    for e in &p.elements {
        let ElementKind::Roof(r) = &e.kind else { continue };
        if !visible(e) || r.footprint.len() < 3 {
            continue;
        }
        let base = analysis::roof_base_z(p, r);
        let start = d.prims.len();
        let (stroke, show) = if r.level == c.level && base >= c.cut_z - 1.0 {
            (HIDDEN, true)
        } else if base < c.cut_z && base > c.bottom_z - 50_000.0 && p.level_elevation(r.level) <= c.level_z {
            // A lower roof seen from above.
            (MEDIUM, p.level_above(r.level).is_none_or(|(id, _)| id == c.level) && r.level != c.level)
        } else {
            (HIDDEN, false)
        };
        if !show {
            continue;
        }
        let eave = geom::offset(&geom::ensure_ccw(&r.footprint), r.overhang);
        d.line(Some(e.id), eave, true, stroke);
        for (a, b) in build3d::roof_ridges(r) {
            d.line(Some(e.id), vec![a, b], false, stroke);
        }
        style_element(c, e, d, start);
    }

    // Family instances: doors, windows, furniture, columns, beams, footings...
    for e in &p.elements {
        let ElementKind::Instance(i) = &e.kind else { continue };
        if !visible(e) {
            continue;
        }
        let fam = p.family(i.family_id);
        let on_level = i.level == c.level;
        let column_spans = fam.is_some_and(|f| f.is_column()) && {
            let (z0, z1) = analysis::column_extent(p, i, family_geom::column_height(p, i));
            z0 <= c.cut_z && z1 >= c.cut_z
        };
        let beam_above = fam.is_some_and(|f| f.is_framing()) && {
            let z = p.level_elevation(i.level) + i.elevation;
            z > c.cut_z && z <= c.top_z + 5000.0 && p.level_above(c.level).is_none_or(|(_, l)| z <= l.elevation + 1.0)
        };
        if !(on_level || column_spans || beam_above) {
            continue;
        }
        let start = d.prims.len();
        for s in family_geom::instance_symbol(p, i, c.cut_z) {
            if let Some(fill) = s.fill {
                d.fill(Some(e.id), &s.pts, [fill[0], fill[1], fill[2], 255]);
            }
            let stroke = match s.style {
                SymStyle::Cut => HEAVY,
                SymStyle::Projection => MEDIUM,
                SymStyle::Detail => THIN,
                SymStyle::Hidden => HIDDEN,
            };
            d.line(Some(e.id), s.pts, s.closed, stroke);
        }
        style_element(c, e, d, start);
    }

    // Railings.
    for e in &p.elements {
        let ElementKind::Railing(r) = &e.kind else { continue };
        if !visible(e) || r.level != c.level || r.path.len() < 2 {
            continue;
        }
        let w = p.sys_type(r.type_id).map(|t| t.prop("Rail Width", 50.0)).unwrap_or(50.0) / 2.0;
        let start = d.prims.len();
        for s in r.path.windows(2) {
            let n = geom::perp((s[1] - s[0]).normalize_or_zero()) * w;
            d.line(Some(e.id), vec![s[0] + n, s[1] + n], false, MEDIUM);
            d.line(Some(e.id), vec![s[0] - n, s[1] - n], false, MEDIUM);
        }
        style_element(c, e, d, start);
    }

    // Wall foundations below.
    for e in &p.elements {
        let ElementKind::WallFoundation(f) = &e.kind else { continue };
        let Some(w) = p.wall(f.wall) else { continue };
        if !visible(e) || w.base_level != c.level {
            continue;
        }
        let width = p.sys_type(f.type_id).map(|t| t.prop("Width", 600.0)).unwrap_or(600.0) / 2.0;
        for s in analysis::wall_path(w).windows(2) {
            let n = geom::perp((s[1] - s[0]).normalize_or_zero()) * width;
            d.line(Some(e.id), vec![s[0] + n, s[1] + n], false, HIDDEN);
            d.line(Some(e.id), vec![s[0] - n, s[1] - n], false, HIDDEN);
        }
    }

    // Room separation and area boundary lines, model lines.
    for e in &p.elements {
        if !visible(e) {
            continue;
        }
        match &e.kind {
            ElementKind::RoomSeparation(s) if s.level == c.level && area_plan.is_none() => d.line(Some(e.id), vec![s.start, s.end], false, THIN),
            ElementKind::AreaBoundary(s) if s.level == c.level && area_plan.is_some_and(|sc| s.scheme.is_none_or(|x| x == sc)) => {
                d.line(Some(e.id), vec![s.start, s.end], false, Stroke::new(0.5, [120, 40, 160], Dash::Solid))
            }
            ElementKind::Line(l) if e.view.is_none() && l.level.is_none_or(|lv| lv == c.level) => {
                let pts = line_points(l);
                d.line(Some(e.id), pts, l.closed, line_style_stroke(l.style));
            }
            ElementKind::Cad(cad) if e.view.is_none() && cad.level.is_none_or(|lv| lv == c.level) => {
                for (pts, col) in &cad.polylines {
                    let color = if cad.halftone { HALFTONE } else { *col };
                    d.line(Some(e.id), pts.clone(), false, Stroke::new(0.13, color, Dash::Solid));
                }
                for (pos, text, h) in &cad.texts {
                    d.prims.push((Some(e.id), Prim::Text { pos: *pos, text: text.clone(), size: (*h / c.scale) as f32, color: HALFTONE, anchor: Anchor::Left, angle: 0.0 }));
                }
            }
            _ => {}
        }
    }

    // Room/area tags.
    for (id, name, number, area, pos) in tags {
        let line_h = 2.5 * c.scale * 0.9;
        d.text(Some(id), pos + DVec2::new(0.0, line_h), name, 2.5, Anchor::Center);
        d.text(Some(id), pos, number, 2.5, Anchor::Center);
        let a = match area {
            Some(a) => p.units.area(a),
            None => "Not Enclosed".into(),
        };
        d.text(Some(id), pos - DVec2::new(0.0, line_h), a, 2.0, Anchor::Center);
    }

    // Grids, reference planes.
    for e in &p.elements {
        if !visible(e) {
            continue;
        }
        match &e.kind {
            ElementKind::Grid(g) => grid_graphics(e.id, g, c.scale, d),
            ElementKind::RefPlane(r) => {
                d.line(Some(e.id), vec![r.start, r.end], false, REFPLANE);
                if !r.name.is_empty() {
                    d.text(Some(e.id), r.end + (r.end - r.start).normalize_or_zero() * (3.0 * c.scale), r.name.clone(), 2.0, Anchor::Center);
                }
            }
            _ => {}
        }
    }

    // View markers: sections, elevations, callouts.
    markers(p, view, c.scale, d);
}

fn shaft_spans(p: &Project, s: &Shaft, z: f64) -> bool {
    let b = p.level_elevation(s.base_level) + s.base_offset;
    let t = match s.top_level.and_then(|l| p.level(l)) {
        Some(l) => l.elevation + s.top_offset,
        None => b + s.unconnected_height,
    };
    b <= z && z <= t
}

pub fn line_points(l: &LineElement) -> Vec<DVec2> {
    match (l.arc_mid, l.pts.len()) {
        (Some(m), 2) => match geom::Arc2::through(l.pts[0], m, l.pts[1]) {
            Some(a) => a.tessellate(200.0),
            None => l.pts.clone(),
        },
        _ => l.pts.clone(),
    }
}

/// Applies overrides, halftone and phase graphics to the primitives an element just added.
fn style_element(c: &Ctx, e: &Element, d: &mut Drawing, start: usize) {
    if let Some(o) = c.view.override_for(e) {
        let color = if o.halftone { Some(HALFTONE) } else { o.line_color };
        d.restyle(start, color, o.line_weight, None);
    }
    match c.status(e) {
        PhaseStatus::Existing => d.restyle(start, Some([110, 110, 110]), None, None),
        PhaseStatus::Demolished => d.restyle(start, Some([110, 110, 110]), None, Some(Dash::Dotted)),
        _ => {}
    }
}

fn grid_graphics(id: Id, g: &Grid, scale: f64, d: &mut Drawing) {
    let (pts, d0, d1) = match g.arc_mid.and_then(|m| geom::Arc2::through(g.start, m, g.end)) {
        Some(a) => (a.tessellate(500.0), -a.tangent(0.0), a.tangent(1.0)),
        None => {
            let dir = (g.end - g.start).normalize_or_zero();
            (vec![g.start, g.end], -dir, dir)
        }
    };
    d.line(Some(id), pts, false, GRID);
    // 1/2" bubble with the grid name.
    let r = 6.0 * scale;
    for (pt, dir, show) in [(g.start, d0, g.bubble_start), (g.end, d1, g.bubble_end)] {
        if !show {
            continue;
        }
        let c = pt + dir * r;
        d.line(Some(id), circle(c, r, 32), true, Stroke { dash: Dash::Solid, ..GRID });
        d.text(Some(id), c, g.name.clone(), 4.5, Anchor::Center);
    }
}

/// Section lines, elevation markers and callout boxes shown in a plan.
fn markers(p: &Project, view: &View, scale: f64, d: &mut Drawing) {
    // A 1/2" circle with a dark arrow wedge outside it, like the standard elevation mark.
    let r = 6.0 * scale;
    let heavy = Stroke::new(0.25, [0, 0, 0], Dash::Solid);
    let mark = |d: &mut Drawing, id: Id, c: DVec2, look: DVec2| {
        let side = geom::perp(look);
        // The wedge between the circle and the arrow triangle, as quads along rays from the
        // centre (the region is concave, so it is built directly).
        let (top, tip, bottom) = (c + side * (r * 1.22) + look * (r * 0.12), c + look * (r * 1.62), c - side * (r * 1.22) + look * (r * 0.12));
        let edge_hit = |u: DVec2, p: DVec2, q: DVec2| -> DVec2 {
            let e = q - p;
            let den = u.x * e.y - u.y * e.x;
            if den.abs() < 1e-12 {
                return p;
            }
            let t = ((p.x - c.x) * e.y - (p.y - c.y) * e.x) / den;
            c + u * t
        };
        let n = 24;
        let mut tris = Vec::new();
        let ring: Vec<(DVec2, DVec2)> = (0..=n)
            .map(|k| {
                let a = -std::f64::consts::FRAC_PI_2 + std::f64::consts::PI * k as f64 / n as f64;
                let u = look * a.cos() + side * a.sin();
                let outer = if a >= 0.0 { edge_hit(u, tip, top) } else { edge_hit(u, bottom, tip) };
                (c + u * r, outer)
            })
            .collect();
        for w in ring.windows(2) {
            let ((i0, o0), (i1, o1)) = (w[0], w[1]);
            tris.push([i0, o0, o1]);
            tris.push([i0, o1, i1]);
        }
        d.prims.push((Some(id), Prim::Fill { tris, color: [20, 30, 50, 255] }));
        d.line(Some(id), circle(c, r, 32), true, heavy);
    };
    let sheet_ref = |id: Id| -> Option<(String, String)> {
        let sheet = p.sheet_containing(id)?;
        let ViewKind::Sheet(sh) = &sheet.kind else { return None };
        let vp = sh.viewports.iter().find(|vp| vp.view == id)?;
        Some((vp.detail_number.clone(), sh.number.clone()))
    };
    for v in &p.views {
        if v.is_template {
            continue;
        }
        match &v.kind {
            ViewKind::Section { start, end, .. } if view.shows(Category::Symbols) => {
                let dir = (*end - *start).normalize_or_zero();
                let look = -geom::perp(dir);
                d.line(Some(v.id), vec![*start, *end], false, Stroke::new(0.35, [0, 0, 0], Dash::DashDot));
                for (pt, out) in [(*start, -dir), (*end, dir)] {
                    let c = pt + out * r;
                    mark(d, v.id, c, look);
                }
                d.text(Some(v.id), *start - dir * r, v.name.chars().take(4).collect::<String>(), 2.2, Anchor::Center);
            }
            ViewKind::Elevation { dir } if view.plan_level().is_some() && view.shows(Category::Symbols) => {
                // Elevation markers sit outside the model on each side.
                // An empty project still shows the four markers around the origin.
                let (mn, mx) = model_extent(p).unwrap_or((DVec2::new(-9000.0, -6000.0), DVec2::new(9000.0, 6000.0)));
                let c = (mn + mx) / 2.0;
                let off = 4000.0;
                let look = dir.look().truncate();
                let pos = match v.marker {
                    Some((o, _)) => o,
                    None => DVec2::new(c.x - look.x * ((mx.x - mn.x) / 2.0 + off), c.y - look.y * ((mx.y - mn.y) / 2.0 + off)),
                };
                mark(d, v.id, pos, look);
                d.line(Some(v.id), vec![pos - DVec2::X * (r * 0.92), pos + DVec2::X * (r * 0.92)], false, Stroke::new(0.18, [0, 0, 0], Dash::Solid));
                if let Some((num, sheet)) = sheet_ref(v.id) {
                    d.text(Some(v.id), pos + DVec2::Y * (r * 0.42), num, 2.0, Anchor::Center);
                    d.text(Some(v.id), pos - DVec2::Y * (r * 0.45), sheet, 2.0, Anchor::Center);
                }
            }
            _ => {}
        }
        if v.parent == Some(view.id) {
            if let Some((a, b)) = v.crop {
                let pts = vec![a, DVec2::new(b.x, a.y), b, DVec2::new(a.x, b.y)];
                d.line(Some(v.id), pts, true, Stroke::new(0.25, [0, 0, 0], Dash::Dashed));
                d.text(Some(v.id), DVec2::new(b.x, b.y) + DVec2::new(2.0, 2.0) * scale, v.name.clone(), 2.5, Anchor::Left);
            }
        }
    }
}

fn model_extent(p: &Project) -> Option<(DVec2, DVec2)> {
    let pts: Vec<DVec2> = p
        .elements
        .iter()
        .flat_map(|e| match &e.kind {
            ElementKind::Wall(w) => vec![w.start, w.end],
            ElementKind::Floor(f) => f.boundary.clone(),
            ElementKind::Grid(g) => vec![g.start, g.end],
            _ => vec![],
        })
        .collect();
    if pts.is_empty() {
        return None;
    }
    Some(geom::bounds(pts))
}

// ---------------------------------------------------------------- walls

fn walls_graphics(c: &Ctx, d: &mut Drawing) {
    let p = c.p;
    let view = c.view;
    if !view.shows(Category::Walls) {
        return;
    }
    // Group cut walls by phase status so existing/demolished walls draw differently.
    let mut cut: HashMap<u8, (Vec<Polygon<f64>>, Vec<Polygon<f64>>, Vec<Id>)> = HashMap::new();
    for (e, w) in p.walls() {
        if !analysis::visible_in(p, view, e) {
            continue;
        }
        let Some(fp) = c.footprints.get(&e.id) else { continue };
        let (zb, zt) = (analysis::wall_base_z(p, w), build3d::wall_top_extent(p, w));
        let curtain = analysis::is_curtain(p, w);
        if zb <= c.cut_z && zt >= c.cut_z {
            if curtain {
                curtain_plan(c, e.id, w, d);
                continue;
            }
            let status = c.status(e);
            let key = match status {
                PhaseStatus::Existing => 1,
                PhaseStatus::Demolished => 2,
                _ => 0,
            };
            let entry = cut.entry(key).or_default();
            entry.0.push(to_geo(&fp.polygon()));
            entry.2.push(e.id);
            for (_, i) in p.hosted_by(e.id) {
                if let Some(o) = plan_opening(p, w, i, c.cut_z) {
                    entry.1.push(to_geo(&o));
                }
            }
            for o in &w.openings {
                let base = analysis::wall_base_z(p, w);
                if base + o.z0 <= c.cut_z && c.cut_z <= base + o.z1 {
                    entry.1.push(to_geo(&opening_rect(p, w, (o.u0 + o.u1) / 2.0, o.u1 - o.u0)));
                }
            }
            // Layer lines at medium/fine detail.
            if view.detail != DetailLevel::Coarse {
                wall_layers(c, e.id, w, fp, d);
            }
        } else if w.base_level == c.level && zt < c.cut_z {
            let start = d.prims.len();
            d.line(Some(e.id), fp.polygon(), true, MEDIUM);
            style_element(c, e, d, start);
        }
    }
    for (key, (polys, holes, _ids)) in cut {
        let mut union = geo::unary_union(polys.iter());
        if !holes.is_empty() {
            let h = geo::unary_union(holes.iter());
            union = union.difference(&h);
        }
        let (fill, stroke) = match key {
            1 => ([200, 200, 200, 255], Stroke::new(0.35, [110, 110, 110], Dash::Solid)),
            2 => ([255, 255, 255, 0], Stroke::new(0.35, [110, 110, 110], Dash::Dotted)),
            // Coarse walls are hollow (no coarse fill pattern), as in the reference template.
            _ => ([255, 255, 255, 0], HEAVY),
        };
        if fill[3] > 0 {
            d.prims.insert(0, (None, Prim::Fill { tris: fill_tris(&union), color: fill }));
        }
        for ring in rings(&union) {
            d.line(None, ring, true, stroke);
        }
    }
}

/// Layer boundary lines (and fine-detail hatching) inside a cut wall.
fn wall_layers(c: &Ctx, id: Id, w: &Wall, fp: &Footprint, d: &mut Drawing) {
    let p = c.p;
    let Some(t) = p.sys_type(w.type_id) else { return };
    if t.layers.len() < 2 && c.view.detail != DetailLevel::Fine {
        return;
    }
    let thick = t.thickness();
    let path = analysis::wall_path(w);
    let openings: Vec<(f64, f64)> = build3d::wall_openings(p, id, w)
        .into_iter()
        .filter(|(_, _, z0, z1)| *z0 <= c.cut_z && c.cut_z <= *z1)
        .map(|(u0, u1, _, _)| (u0, u1))
        .collect();
    // Offsets of layer boundaries from the centreline.
    let mut o = thick / 2.0;
    let mut bounds = vec![o];
    for l in &t.layers {
        o -= l.thickness;
        bounds.push(o);
    }
    let offset_line = |off: f64| -> Vec<DVec2> {
        if fp.straight {
            vec![fp.start_at(off, thick), fp.end_at(off, thick)]
        } else {
            let n = path.len();
            (0..n).map(|i| {
                let a = path[i.saturating_sub(1).min(n - 2)];
                let b = path[(i + 1).min(n - 1).max(1)];
                path[i] + geom::perp((b - a).normalize_or_zero()) * off
            }).collect()
        }
    };
    // Lines between layers, broken at openings.
    for &b in &bounds[1..bounds.len() - 1] {
        let pts = offset_line(b);
        for seg in split_by_openings(w, &pts, &openings) {
            d.line(Some(id), seg, false, THIN);
        }
    }
    if c.view.detail == DetailLevel::Fine {
        for (k, l) in t.layers.iter().enumerate() {
            let (outer, inner) = (offset_line(bounds[k]), offset_line(bounds[k + 1]));
            let mut poly = outer.clone();
            poly.extend(inner.iter().rev());
            let pattern = p.material(&l.material).map(|m| m.cut_pattern).unwrap_or_default();
            for (a, b) in pattern_lines(&poly, pattern, c.scale) {
                // Skip hatch segments inside openings.
                let mid = (a + b) / 2.0;
                let (u, _) = analysis::wall_project(w, mid);
                if openings.iter().any(|(u0, u1)| u > *u0 && u < *u1) {
                    continue;
                }
                d.line(Some(id), vec![a, b], false, Stroke::new(0.09, [80, 80, 80], Dash::Solid));
            }
        }
    }
}

fn split_by_openings(w: &Wall, pts: &[DVec2], openings: &[(f64, f64)]) -> Vec<Vec<DVec2>> {
    if openings.is_empty() {
        return vec![pts.to_vec()];
    }
    let mut out = Vec::new();
    let mut cur: Vec<DVec2> = Vec::new();
    for s in pts.windows(2) {
        // Sample each segment finely enough to break at openings.
        let steps = ((s[0].distance(s[1]) / 50.0).ceil() as usize).max(1);
        for k in 0..=steps {
            let q = s[0].lerp(s[1], k as f64 / steps as f64);
            let (u, _) = analysis::wall_project(w, q);
            if openings.iter().any(|(u0, u1)| u > *u0 + 1.0 && u < *u1 - 1.0) {
                if cur.len() >= 2 {
                    out.push(std::mem::take(&mut cur));
                }
                cur.clear();
            } else {
                cur.push(q);
            }
        }
    }
    if cur.len() >= 2 {
        out.push(cur);
    }
    out
}

fn curtain_plan(c: &Ctx, id: Id, w: &Wall, d: &mut Drawing) {
    let p = c.p;
    let (us, _) = build3d::curtain_grid(p, w);
    let t = p.sys_type(w.type_id);
    let (mw, md) = (t.map(|t| t.prop("Mullion Width", 50.0)).unwrap_or(50.0), t.map(|t| t.prop("Mullion Depth", 150.0)).unwrap_or(150.0));
    d.line(Some(id), analysis::wall_path(w), false, MEDIUM);
    for u in us {
        let (pt, dir) = analysis::wall_point(w, u);
        let n = geom::perp(dir);
        let q = vec![pt - dir * (mw / 2.0) - n * (md / 2.0), pt + dir * (mw / 2.0) - n * (md / 2.0), pt + dir * (mw / 2.0) + n * (md / 2.0), pt - dir * (mw / 2.0) + n * (md / 2.0)];
        d.fill(Some(id), &q, [60, 60, 60, 255]);
        d.line(Some(id), q, true, MEDIUM);
    }
}

fn opening_rect(p: &Project, w: &Wall, center_u: f64, width: f64) -> Vec<DVec2> {
    let t = analysis::wall_thickness(p, w) / 2.0 + 1.0;
    let (c, d) = analysis::wall_point(w, center_u);
    let n = geom::perp(d);
    vec![c - d * (width / 2.0) - n * t, c + d * (width / 2.0) - n * t, c + d * (width / 2.0) + n * t, c - d * (width / 2.0) + n * t]
}

/// Plan opening rectangle for a hosted instance if it is cut at `cut_z`.
fn plan_opening(p: &Project, w: &Wall, i: &FamilyInstance, cut_z: f64) -> Option<Vec<DVec2>> {
    let (ow, oh) = analysis::opening_size(p, i);
    let z0 = p.level_elevation(i.level) + i.elevation;
    if !(z0 <= cut_z && cut_z <= z0 + oh) {
        return None;
    }
    Some(opening_rect(p, w, i.offset_along_host, ow))
}

fn underlay(c: &Ctx, level: Id, d: &mut Drawing) {
    let p = c.p;
    for (e, w) in p.walls() {
        if w.base_level != level {
            continue;
        }
        if let Some(fp) = c.footprints.get(&e.id) {
            d.line(None, fp.polygon(), true, Stroke::new(0.18, HALFTONE, Dash::Solid));
        }
    }
}

// ---------------------------------------------------------------- stairs

fn stairs_graphics(c: &Ctx, d: &mut Drawing) {
    let p = c.p;
    for e in &p.elements {
        let ElementKind::Stair(s) = &e.kind else { continue };
        if !analysis::visible_in(p, c.view, e) {
            continue;
        }
        let lay = build3d::stair_layout(p, s);
        let base_level = s.base_level == c.level;
        let top_level = s.top_level == Some(c.level);
        if !base_level && !top_level {
            continue;
        }
        let start = d.prims.len();
        for (k, (run, risers, _, z0)) in lay.runs.iter().enumerate() {
            let len = run.start.distance(run.end);
            if len < 1.0 {
                continue;
            }
            let dir = (run.end - run.start) / len;
            let n = geom::perp(dir) * (run.width / 2.0);
            let going = len / *risers as f64;
            // Cut position along this run (base level only).
            let cut_u = if base_level { ((c.cut_z - z0) / lay.riser) * going } else { f64::MAX };
            for side in [-1.0, 1.0] {
                let a = run.start + n * side;
                let b = run.end + n * side;
                if cut_u < len && base_level {
                    let m = run.start + dir * cut_u.max(0.0) + n * side;
                    d.line(Some(e.id), vec![a, m], false, MEDIUM);
                    d.line(Some(e.id), vec![m, b], false, HIDDEN);
                } else {
                    d.line(Some(e.id), vec![a, b], false, MEDIUM);
                }
            }
            for r in 0..=*risers {
                let u = r as f64 * going;
                let q = run.start + dir * u;
                let stroke = if base_level && u > cut_u { HIDDEN } else { THIN };
                d.line(Some(e.id), vec![q - n, q + n], false, stroke);
            }
            if base_level && cut_u > 0.0 && cut_u < len {
                // Diagonal break line at the cut.
                let m = run.start + dir * cut_u;
                d.line(Some(e.id), vec![m - n * 1.1 - dir * 150.0, m - dir * 40.0, m + dir * 40.0, m + n * 1.1 + dir * 150.0], false, MEDIUM);
            }
            if k == 0 {
                // Walk line with arrow.
                let arrow_end = if base_level { run.start + dir * (cut_u.min(len) - 100.0).max(200.0) } else { run.start + dir * len * 0.8 };
                d.line(Some(e.id), vec![run.start + dir * 80.0, arrow_end], false, THIN);
                let back = -dir * 200.0;
                let side = geom::perp(dir) * 90.0;
                d.line(Some(e.id), vec![arrow_end + back + side, arrow_end, arrow_end + back - side], false, THIN);
                let label = if base_level { "UP" } else { "DN" };
                d.text(Some(e.id), run.start - dir * (3.0 * c.scale), label, 2.5, Anchor::Center);
            }
        }
        for (poly, _) in &lay.landings {
            d.line(Some(e.id), poly.clone(), true, MEDIUM);
        }
        style_element(c, e, d, start);
    }
}

// ---------------------------------------------------------------- ceiling plans

fn ceiling_plan_graphics(c: &Ctx, d: &mut Drawing) {
    let p = c.p;
    // Walls cut (reflected ceiling plans cut above the doors).
    walls_graphics(c, d);
    for e in &p.elements {
        let ElementKind::Ceiling(cl) = &e.kind else { continue };
        if cl.level != c.level || !analysis::visible_in(p, c.view, e) {
            continue;
        }
        let start = d.prims.len();
        d.line(Some(e.id), cl.boundary.clone(), true, MEDIUM);
        for h in &cl.holes {
            d.line(Some(e.id), h.clone(), true, MEDIUM);
        }
        // Grid pattern for tile ceilings.
        let grid = p.sys_type(cl.type_id).is_some_and(|t| t.name.contains("Grid") || t.name.contains("600"));
        if grid {
            let spacing = 600.0;
            for (a, b) in hatch(&cl.boundary, 0.0, spacing).into_iter().chain(hatch(&cl.boundary, std::f64::consts::FRAC_PI_2, spacing)) {
                d.line(Some(e.id), vec![a, b], false, THIN);
            }
        }
        style_element(c, e, d, start);
    }
    for e in &p.elements {
        if let ElementKind::Grid(g) = &e.kind {
            if analysis::visible_in(p, c.view, e) {
                grid_graphics(e.id, g, c.scale, d);
            }
        }
    }
}

// ---------------------------------------------------------------- annotation

/// View-specific elements: dimensions, tags, text, detail lines, regions, symbols.
pub fn annotation_graphics(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, d: &mut Drawing) {
    let scale = view.scale;
    let _ = footprints;
    // Regions first so text and lines draw on top.
    for e in &p.elements {
        if e.view != Some(view.id) || !view.shows_element(e) {
            continue;
        }
        if let ElementKind::Region(r) = &e.kind {
            let color = if r.pattern == FillPattern::Masking { [255, 255, 255, 255] } else { [r.color[0], r.color[1], r.color[2], if r.pattern == FillPattern::Solid { 255 } else { 0 }] };
            if color[3] > 0 {
                let mut poly = to_geo(&r.boundary);
                for h in &r.holes {
                    poly = Polygon::new(poly.exterior().clone(), poly.interiors().iter().cloned().chain(std::iter::once(to_geo(h).exterior().clone())).collect());
                }
                d.prims.push((Some(e.id), Prim::Fill { tris: fill_tris(&MultiPolygon::new(vec![poly])), color }));
            }
            for (a, b) in pattern_lines(&r.boundary, r.pattern, scale) {
                d.line(Some(e.id), vec![a, b], false, Stroke::new(0.13, r.color, Dash::Solid));
            }
            if r.pattern != FillPattern::Masking {
                d.line(Some(e.id), r.boundary.clone(), true, line_style_stroke(r.boundary_style));
            }
        }
    }
    for e in &p.elements {
        if e.view != Some(view.id) || !view.shows_element(e) {
            continue;
        }
        match &e.kind {
            ElementKind::ColorLegend(lg) => {
                // Title, then one swatch per room name on the view's level.
                let h = 2.5 * scale;
                d.text(Some(e.id), lg.position, "Room Legend".to_string(), 3.0, Anchor::Left);
                let level = view.plan_level();
                let mut names: Vec<String> = p
                    .elements
                    .iter()
                    .filter_map(|x| match &x.kind {
                        ElementKind::Room(r) if level.is_none_or(|l| l == r.level) => Some(r.name.clone()),
                        _ => None,
                    })
                    .collect();
                names.sort();
                names.dedup();
                for (k, name) in names.iter().enumerate() {
                    let y = lg.position.y - h * 2.2 * (k as f64 + 1.0);
                    let a = DVec2::new(lg.position.x, y);
                    let sw = [a, a + DVec2::new(h * 2.0, 0.0), a + DVec2::new(h * 2.0, h * 1.4), a + DVec2::new(0.0, h * 1.4)];
                    let c = room_name_color(name);
                    d.fill(Some(e.id), &sw, [c[0], c[1], c[2], 255]);
                    d.line(Some(e.id), sw.to_vec(), true, ANNO);
                    d.text(Some(e.id), a + DVec2::new(h * 2.8, h * 0.7), name.clone(), 2.5, Anchor::Left);
                }
                if names.is_empty() {
                    d.text(Some(e.id), lg.position - DVec2::new(0.0, h * 2.2), "No colors defined".to_string(), 2.5, Anchor::Left);
                }
            }
            ElementKind::Line(l) => d.line(Some(e.id), line_points(l), l.closed, line_style_stroke(l.style)),
            ElementKind::Dimension(dim) => dimension_graphics(p, e.id, dim, scale, d),
            ElementKind::Tag(t) => {
                let text = annotation::tag_text(p, t);
                let lines: Vec<&str> = text.lines().collect();
                let h = 2.5 * scale;
                let w = lines.iter().map(|l| l.chars().count()).max().unwrap_or(1) as f64 * h * 0.6 + h;
                let boxh = h * 1.4 * lines.len() as f64;
                let room = p.element(t.host).is_some_and(|h| h.category() == Category::Rooms);
                if room {
                    let name = lines.first().copied().unwrap_or("");
                    let number = lines.get(1).copied().unwrap_or("");
                    d.text(Some(e.id), t.position + DVec2::new(0.0, h * 0.85), name.to_string(), 3.0, Anchor::Center);
                    let nw = (number.chars().count().max(3) as f64 * h * 0.6 + h * 1.2) / 2.0;
                    let (y0, y1) = (-h * 1.15, h * 0.05);
                    let c = t.position;
                    d.line(Some(e.id), vec![c + DVec2::new(-nw, y0), c + DVec2::new(nw, y0), c + DVec2::new(nw, y1), c + DVec2::new(-nw, y1)], true, ANNO);
                    d.text(Some(e.id), c + DVec2::new(0.0, (y0 + y1) / 2.0), number.to_string(), 2.5, Anchor::Center);
                    if t.leader {
                        let host = p.element(t.host).map(|hh| annotation::host_point(p, hh)).unwrap_or(t.position);
                        d.line(Some(e.id), vec![t.position, t.leader_end.unwrap_or(host)], false, ANNO);
                    }
                    continue;
                }
                if !room {
                    let pts = vec![
                        t.position + DVec2::new(-w / 2.0, -boxh / 2.0),
                        t.position + DVec2::new(w / 2.0, -boxh / 2.0),
                        t.position + DVec2::new(w / 2.0, boxh / 2.0),
                        t.position + DVec2::new(-w / 2.0, boxh / 2.0),
                    ];
                    let is_door_window = p.element(t.host).is_some_and(|h| matches!(h.category(), Category::Doors | Category::Windows));
                    if is_door_window {
                        d.line(Some(e.id), circle(t.position, (w.max(boxh)) / 2.0, 24), true, ANNO);
                    } else {
                        d.line(Some(e.id), pts, true, ANNO);
                    }
                }
                for (k, l) in lines.iter().enumerate() {
                    let y = (lines.len() as f64 - 1.0) / 2.0 - k as f64;
                    d.text(Some(e.id), t.position + DVec2::new(0.0, y * h * 1.3), l.to_string(), 2.5, Anchor::Center);
                }
                if t.leader {
                    let host = p.element(t.host).map(|h| annotation::host_point(p, h)).unwrap_or(t.position);
                    let end = t.leader_end.unwrap_or(host);
                    d.line(Some(e.id), vec![t.position, end], false, ANNO);
                }
            }
            ElementKind::Text(tn) => {
                let lines: Vec<&str> = tn.text.lines().collect();
                let h = tn.size * scale;
                for (k, l) in lines.iter().enumerate() {
                    d.prims.push((
                        Some(e.id),
                        Prim::Text {
                            pos: tn.position - DVec2::new(0.0, k as f64 * h * 1.4),
                            text: l.to_string(),
                            size: tn.size as f32,
                            color: [0, 0, 0],
                            anchor: Anchor::Left,
                            angle: tn.rotation_deg.to_radians() as f32,
                        },
                    ));
                }
                if !tn.leader.is_empty() {
                    let mut pts = vec![tn.position + DVec2::new(-h * 0.3, -h * 0.3)];
                    pts.extend(tn.leader.iter().copied());
                    d.line(Some(e.id), pts.clone(), false, ANNO);
                    if pts.len() >= 2 {
                        let tip = pts[pts.len() - 1];
                        let back = (pts[pts.len() - 2] - tip).normalize_or_zero() * (2.0 * scale);
                        let side = geom::perp(back) * 0.35;
                        d.fill(Some(e.id), &[tip, tip + back + side, tip + back - side], [0, 0, 0, 255]);
                    }
                }
            }
            ElementKind::Symbol(s) => match s.kind {
                SymbolKind::NorthArrow => {
                    let r = 8.0 * scale;
                    let a = (s.rotation_deg + 90.0).to_radians();
                    let dir = DVec2::new(a.cos(), a.sin());
                    let side = geom::perp(dir);
                    d.line(Some(e.id), circle(s.position, r, 32), true, ANNO);
                    d.fill(Some(e.id), &[s.position + dir * r, s.position - dir * r * 0.6 + side * r * 0.45, s.position - dir * r * 0.3], [0, 0, 0, 255]);
                    d.line(Some(e.id), vec![s.position + dir * r, s.position - dir * r * 0.6 - side * r * 0.45, s.position - dir * r * 0.3], true, ANNO);
                    d.text(Some(e.id), s.position + dir * (r * 1.35), "N", 3.5, Anchor::Center);
                }
                SymbolKind::Revision => {
                    // Revision cloud: arcs along the outline.
                    let pts = &s.points;
                    for i in 0..pts.len() {
                        let (a, b) = (pts[i], pts[(i + 1) % pts.len()]);
                        let len = a.distance(b);
                        let bump = 4.0 * scale;
                        let k = (len / bump).ceil().max(1.0) as usize;
                        for j in 0..k {
                            let (q0, q1) = (a.lerp(b, j as f64 / k as f64), a.lerp(b, (j + 1) as f64 / k as f64));
                            let mid = (q0 + q1) / 2.0;
                            let out = -geom::perp((b - a).normalize_or_zero()) * (q0.distance(q1) * 0.35);
                            let arc: Vec<DVec2> = (0..=8).map(|t| {
                                let t = t as f64 / 8.0;
                                q0.lerp(q1, t) + out * (std::f64::consts::PI * t).sin()
                            }).collect();
                            let _ = mid;
                            d.line(Some(e.id), arc, false, Stroke::new(0.35, [200, 0, 0], Dash::Solid));
                        }
                    }
                    if !s.value.is_empty() {
                        if let Some(first) = pts.first() {
                            d.text(Some(e.id), *first, format!("△{}", s.value), 2.5, Anchor::Center);
                        }
                    }
                }
                SymbolKind::SpotElevation => {
                    let r = 1.5 * scale;
                    d.line(Some(e.id), vec![s.position - DVec2::new(r, -r), s.position, s.position + DVec2::new(r, r), s.position + DVec2::new(r * 6.0, r)], false, ANNO);
                    d.text(Some(e.id), s.position + DVec2::new(r * 2.0, r * 2.2), s.value.clone(), 2.2, Anchor::Left);
                }
                SymbolKind::BreakLine => {
                    let a = s.rotation_deg.to_radians();
                    let dir = DVec2::new(a.cos(), a.sin());
                    let side = geom::perp(dir);
                    let l = 10.0 * scale;
                    d.line(Some(e.id), vec![s.position - dir * l, s.position - dir * l * 0.1, s.position + side * l * 0.15, s.position - side * l * 0.15, s.position + dir * l * 0.1, s.position + dir * l], false, ANNO);
                }
            },
            ElementKind::Cad(cad) => {
                for (pts, col) in &cad.polylines {
                    d.line(Some(e.id), pts.clone(), false, Stroke::new(0.13, if cad.halftone { HALFTONE } else { *col }, Dash::Solid));
                }
            }
            _ => {}
        }
    }
}

/// Draws a linear/aligned dimension string.
fn arrow(id: Id, tip: DVec2, from: DVec2, scale: f64, d: &mut Drawing) {
    let dir = (tip - from).normalize_or_zero();
    let n = geom::perp(dir);
    let len = 2.0 * scale;
    let b = tip - dir * len;
    d.fill(Some(id), &[tip, b + n * (len * 0.3), b - n * (len * 0.3)], [0, 0, 0, 255]);
}

fn upright(a: f64) -> f64 {
    let mut a = a;
    if a > std::f64::consts::FRAC_PI_2 + 1e-6 {
        a -= std::f64::consts::PI;
    }
    if a < -std::f64::consts::FRAC_PI_2 + 1e-6 {
        a += std::f64::consts::PI;
    }
    a
}

/// Radial, diameter, angular and arc-length dimensions (point references).
fn special_dimension(p: &Project, id: Id, dim: &Dimension, scale: f64, d: &mut Drawing) {
    let pts: Vec<DVec2> = dim.refs.iter().map(|r| annotation::resolve(p, r).point).collect();
    let fmt = |text: String| format!("{}{}{}", dim.prefix, if dim.text_override.is_empty() { text } else { dim.text_override.clone() }, dim.suffix);
    match dim.kind {
        DimKind::Radial if pts.len() >= 2 => {
            let (c, on) = (pts[0], pts[1]);
            d.line(Some(id), vec![c, on], false, ANNO);
            arrow(id, on, c, scale, d);
            let a = upright((on - c).y.atan2((on - c).x));
            let mid = (c + on) / 2.0 + geom::perp(DVec2::new(a.cos(), a.sin())) * (1.6 * scale);
            d.text_rot(Some(id), mid, fmt(format!("R {}", p.units.length(c.distance(on)))), 2.5, a as f32);
        }
        DimKind::Diameter if pts.len() >= 2 => {
            let (a0, b0) = (pts[0], pts[1]);
            d.line(Some(id), vec![a0, b0], false, ANNO);
            arrow(id, a0, b0, scale, d);
            arrow(id, b0, a0, scale, d);
            let a = upright((b0 - a0).y.atan2((b0 - a0).x));
            let mid = (a0 + b0) / 2.0 + geom::perp(DVec2::new(a.cos(), a.sin())) * (1.6 * scale);
            d.text_rot(Some(id), mid, fmt(format!("⌀ {}", p.units.length(a0.distance(b0)))), 2.5, a as f32);
        }
        DimKind::Angular if pts.len() >= 3 => {
            let (a, v, b) = (pts[0], pts[1], pts[2]);
            let r = dim.line_point.distance(v).max(scale * 4.0);
            let a0 = (a - v).y.atan2((a - v).x);
            let mut sweep = ((b - v).y.atan2((b - v).x) - a0).rem_euclid(std::f64::consts::TAU);
            if sweep > std::f64::consts::PI {
                sweep -= std::f64::consts::TAU;
            }
            let arc: Vec<DVec2> = (0..=32).map(|k| v + DVec2::from_angle(a0 + sweep * k as f64 / 32.0) * r).collect();
            for (pt, dirp) in [(a, a0), (b, a0 + sweep)] {
                let on = v + DVec2::from_angle(dirp) * r;
                // Witness lines from the referenced lines out to the arc.
                if pt.distance(v) < r {
                    d.line(Some(id), vec![pt, on], false, ANNO);
                }
            }
            arrow(id, arc[0], arc[2], scale, d);
            arrow(id, arc[32], arc[30], scale, d);
            d.line(Some(id), arc, false, ANNO);
            let mid_a = a0 + sweep / 2.0;
            let tp = v + DVec2::from_angle(mid_a) * (r + 2.0 * scale);
            d.text_rot(Some(id), tp, fmt(p.units.format(sweep.abs().to_degrees(), ParamKind::Angle)), 2.5, upright(mid_a - std::f64::consts::FRAC_PI_2) as f32);
        }
        DimKind::ArcLength if pts.len() >= 3 => {
            let Some(arc) = geom::Arc2::through(pts[0], pts[1], pts[2]) else { return };
            let r = dim.line_point.distance(arc.center).max(scale * 2.0);
            let off = geom::Arc2 { radius: r, ..arc };
            let poly = off.tessellate(200.0);
            for (q, t) in [(pts[0], 0.0), (pts[2], 1.0)] {
                d.line(Some(id), vec![q, off.point(t)], false, ANNO);
            }
            let n = poly.len();
            arrow(id, poly[0], poly[1.min(n - 1)], scale, d);
            arrow(id, poly[n - 1], poly[n.saturating_sub(2)], scale, d);
            d.line(Some(id), poly, false, ANNO);
            let m = off.point(0.5);
            let t = off.tangent(0.5);
            let a = upright(t.y.atan2(t.x));
            d.text_rot(Some(id), m + (m - arc.center).normalize_or_zero() * (1.6 * scale), fmt(format!("⌒ {}", p.units.length(arc.length()))), 2.5, a as f32);
        }
        _ => {}
    }
}

pub fn dimension_graphics(p: &Project, id: Id, dim: &Dimension, scale: f64, d: &mut Drawing) {
    if !matches!(dim.kind, DimKind::Aligned | DimKind::Linear) {
        special_dimension(p, id, dim, scale, d);
        return;
    }
    if dim.refs.len() < 2 {
        return;
    }
    let dir = dim.direction.normalize_or(DVec2::X);
    let n = geom::perp(dir);
    let resolved: Vec<annotation::Resolved> = dim.refs.iter().map(|r| annotation::resolve(p, r)).collect();
    let coords: Vec<f64> = resolved.iter().map(|r| r.point.dot(dir)).collect();
    let line_off = dim.line_point.dot(n);
    let at = |u: f64| dir * u + n * line_off;
    let ext = 2.0 * scale;
    let gap = 1.5 * scale;
    let tick = 1.3 * scale;
    // Dimension line.
    let (lo, hi) = (coords.iter().cloned().fold(f64::MAX, f64::min), coords.iter().cloned().fold(f64::MIN, f64::max));
    d.line(Some(id), vec![at(lo) - dir * ext * 0.6, at(hi) + dir * ext * 0.6], false, ANNO);
    for (k, r) in resolved.iter().enumerate() {
        let u = coords[k];
        let foot = r.point;
        let foot_off = foot.dot(n);
        let side = if line_off >= foot_off { 1.0 } else { -1.0 };
        let start = dir * u + n * (foot_off + side * gap);
        let end = at(u) + n * side * ext * 0.6;
        d.line(Some(id), vec![start, end], false, ANNO);
        // 45° tick.
        let t = (dir + n).normalize() * tick;
        d.line(Some(id), vec![at(u) - t, at(u) + t], false, Stroke::new(0.35, [0, 0, 0], Dash::Solid));
    }
    let angle = {
        let mut a = dir.y.atan2(dir.x);
        if a > std::f64::consts::FRAC_PI_2 + 1e-6 {
            a -= std::f64::consts::PI;
        }
        if a < -std::f64::consts::FRAC_PI_2 + 1e-6 {
            a += std::f64::consts::PI;
        }
        a
    };
    let text_dir = DVec2::new(angle.cos(), angle.sin());
    let up = geom::perp(text_dir);
    let mut sorted: Vec<f64> = coords.clone();
    sorted.sort_by(f64::total_cmp);
    for (k, w) in sorted.windows(2).enumerate() {
        let value = w[1] - w[0];
        let mid = at((w[0] + w[1]) / 2.0) + up * (1.6 * scale);
        let text = annotation::segment_text(p, dim, value);
        d.text_rot(Some(id), mid, text, 2.5, angle as f32);
        if dim.locks.get(k).copied().unwrap_or(false) {
            let lp = mid + up * (2.4 * scale);
            d.line(Some(id), circle(lp, 0.5 * scale, 12), true, ANNO);
        }
    }
}

// ---------------------------------------------------------------- hit testing

/// Plan outline used for selection highlight and picking.
pub fn element_outline(p: &Project, e: &Element, footprints: &HashMap<Id, Footprint>) -> Vec<Vec<DVec2>> {
    match &e.kind {
        ElementKind::Wall(_) => footprints.get(&e.id).map(|f| vec![f.polygon()]).unwrap_or_default(),
        ElementKind::Floor(f) => vec![f.boundary.clone()],
        ElementKind::Ceiling(c) => vec![c.boundary.clone()],
        ElementKind::Shaft(s) => vec![s.boundary.clone()],
        ElementKind::Mass(m) => vec![m.boundary.clone()],
        ElementKind::Toposolid(t) => vec![t.boundary.clone()],
        ElementKind::PropertyLine(l) => {
            let mut v = l.boundary.clone();
            if let Some(f) = v.first().copied() {
                v.push(f);
            }
            vec![v]
        }
        ElementKind::ColorLegend(c) => vec![vec![c.position, c.position + DVec2::new(4000.0, 0.0), c.position + DVec2::new(4000.0, -3000.0), c.position + DVec2::new(0.0, -3000.0)]],
        ElementKind::Roof(r) => {
            if r.footprint.len() < 3 {
                return vec![];
            }
            vec![geom::offset(&geom::ensure_ccw(&r.footprint), r.overhang)]
        }
        ElementKind::Grid(g) => match g.arc_mid.and_then(|m| geom::Arc2::through(g.start, m, g.end)) {
            Some(a) => vec![a.tessellate(500.0)],
            None => vec![vec![g.start, g.end]],
        },
        ElementKind::RefPlane(r) => vec![vec![r.start, r.end]],
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => vec![vec![s.start, s.end]],
        ElementKind::Line(l) => vec![line_points(l)],
        ElementKind::Room(r) => match analysis::room_boundary(p, r) {
            Some(b) => vec![b.interior],
            None => vec![circle(r.location, 300.0, 16)],
        },
        ElementKind::Area(a) => match analysis::area_boundary(p, a) {
            Some(b) => vec![b.centerline],
            None => vec![circle(a.location, 300.0, 16)],
        },
        ElementKind::Instance(i) => vec![family_geom::instance_outline(p, i)],
        ElementKind::Stair(s) => {
            let lay = build3d::stair_layout(p, s);
            let mut v: Vec<Vec<DVec2>> = lay
                .runs
                .iter()
                .map(|(r, ..)| {
                    let n = geom::perp((r.end - r.start).normalize_or_zero()) * (r.width / 2.0);
                    vec![r.start - n, r.end - n, r.end + n, r.start + n]
                })
                .collect();
            v.extend(lay.landings.into_iter().map(|(poly, _)| poly));
            v
        }
        ElementKind::Railing(r) => vec![r.path.clone()],
        ElementKind::WallFoundation(f) => p.wall(f.wall).map(|w| vec![analysis::wall_path(w)]).unwrap_or_default(),
        ElementKind::Dimension(dim) => {
            let dir = dim.direction.normalize_or(DVec2::X);
            let n = geom::perp(dir);
            let coords = annotation::coordinates(p, dim);
            let off = dim.line_point.dot(n);
            let (lo, hi) = (coords.iter().cloned().fold(f64::MAX, f64::min), coords.iter().cloned().fold(f64::MIN, f64::max));
            vec![vec![dir * lo + n * off, dir * hi + n * off]]
        }
        ElementKind::Tag(t) => vec![circle(t.position, 400.0, 12)],
        ElementKind::Text(t) => {
            let w = t.text.lines().map(|l| l.chars().count()).max().unwrap_or(1) as f64 * t.size * 60.0;
            let h = t.size * 100.0 * t.text.lines().count().max(1) as f64 * 1.4;
            vec![vec![t.position + DVec2::new(0.0, t.size * 100.0), t.position + DVec2::new(w, t.size * 100.0), t.position + DVec2::new(w, t.size * 100.0 - h), t.position + DVec2::new(0.0, t.size * 100.0 - h)]]
        }
        ElementKind::Region(r) => vec![r.boundary.clone()],
        ElementKind::Symbol(s) => {
            if s.points.len() >= 2 {
                vec![s.points.clone()]
            } else {
                vec![circle(s.position, 600.0, 16)]
            }
        }
        ElementKind::Cad(c) => {
            let pts: Vec<DVec2> = c.polylines.iter().flat_map(|(p, _)| p.iter().copied()).collect();
            if pts.is_empty() {
                return vec![];
            }
            let (mn, mx) = geom::bounds(pts);
            vec![vec![mn, DVec2::new(mx.x, mn.y), mx, DVec2::new(mn.x, mx.y)]]
        }
        ElementKind::GroupInstance(_) => {
            let pts: Vec<DVec2> = p
                .elements
                .iter()
                .filter(|m| m.group == Some(e.id))
                .flat_map(|m| element_outline(p, m, footprints).into_iter().flatten())
                .collect();
            if pts.is_empty() {
                return vec![];
            }
            let (mn, mx) = geom::bounds(pts);
            vec![vec![mn, DVec2::new(mx.x, mn.y), mx, DVec2::new(mn.x, mx.y)]]
        }
        ElementKind::Level(_) => vec![],
    }
}

/// Is the element shown in this plan view (level association or view ownership)?
pub fn in_plan(p: &Project, view: &View, e: &Element) -> bool {
    if !analysis::visible_in(p, view, e) {
        return false;
    }
    if e.view.is_some() {
        return e.view == Some(view.id);
    }
    if e.group.is_some() {
        return false; // members are picked through their group
    }
    let Some(level) = view.plan_level() else { return false };
    match &e.kind {
        ElementKind::Grid(_) | ElementKind::RefPlane(_) => true,
        ElementKind::Cad(c) => c.level.is_none_or(|l| l == level),
        ElementKind::Line(l) => l.level.is_none_or(|lv| lv == level),
        ElementKind::Stair(s) => s.base_level == level || s.top_level == Some(level),
        ElementKind::Ceiling(c) => c.level == level && matches!(view.kind, ViewKind::CeilingPlan { .. }),
        ElementKind::Area(a) => a.level == level && matches!(view.kind, ViewKind::AreaPlan { .. }),
        ElementKind::AreaBoundary(s) => s.level == level && matches!(view.kind, ViewKind::AreaPlan { .. }),
        ElementKind::Instance(i) => {
            if i.level == level {
                return true;
            }
            // Columns spanning the cut plane appear on every level they pass through.
            if p.family(i.family_id).is_some_and(|f| f.is_column()) {
                let cut = p.level_elevation(level) + view.view_range.cut;
                let (z0, z1) = analysis::column_extent(p, i, family_geom::column_height(p, i));
                return z0 <= cut && z1 >= cut;
            }
            false
        }
        ElementKind::Wall(w) => {
            if w.base_level == level {
                return true;
            }
            let cut = p.level_elevation(level) + view.view_range.cut;
            analysis::wall_base_z(p, w) <= cut && build3d::wall_top_extent(p, w) >= cut
        }
        ElementKind::GroupInstance(g) => g.level == level,
        _ => e.level() == Some(level),
    }
}

/// Picks the element under `pt`. Small things (doors, windows, annotations) win over walls,
/// walls over floors and rooms.
pub fn pick(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, pt: DVec2, tol: f64) -> Option<Id> {
    pick_all(p, view, footprints, pt, tol).first().copied()
}

/// All elements under `pt`, best first (Tab cycles through them).
pub fn pick_all(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, pt: DVec2, tol: f64) -> Vec<Id> {
    let priority = |c: Category| match c {
        Category::Dimensions | Category::Tags | Category::TextNotes | Category::Symbols => 0,
        Category::Doors | Category::Windows => 1,
        Category::Furniture | Category::Casework | Category::PlumbingFixtures | Category::SpecialtyEquipment | Category::GenericModels => 2,
        Category::Columns | Category::StructuralColumns | Category::StructuralFraming | Category::StructuralFoundations => 2,
        Category::Grids | Category::ReferencePlanes | Category::Lines | Category::RoomSeparation | Category::AreaBoundary => 3,
        Category::Railings | Category::Stairs => 3,
        Category::Walls => 4,
        Category::Groups => 4,
        Category::Rooms | Category::Areas => 5,
        Category::FilledRegions | Category::ImportedCad => 6,
        Category::Roofs | Category::Ceilings | Category::ShaftOpenings => 6,
        Category::Floors => 7,
        _ => 8,
    };
    let mut hits: Vec<(i32, f64, Id)> = Vec::new();
    for e in &p.elements {
        // Group members are picked as their group.
        let target = match e.group.and_then(|g| p.element(g)) {
            Some(ge) => ge,
            None => e,
        };
        let shown = if target.id != e.id { in_plan(p, view, target) && analysis::visible_in(p, view, e) } else { in_plan(p, view, e) };
        if !shown || matches!(e.kind, ElementKind::GroupInstance(_)) {
            continue;
        }
        let c = e.category();
        for outline in element_outline(p, e, footprints) {
            if outline.is_empty() {
                continue;
            }
            let edge_hit = (0..outline.len().saturating_sub(1)).any(|k| geom::distance_to_segment(outline[k], outline[k + 1], pt) <= tol)
                || (outline.len() > 2 && geom::distance_to_segment(outline[outline.len() - 1], outline[0], pt) <= tol);
            let open = matches!(e.kind, ElementKind::Line(_) | ElementKind::Grid(_) | ElementKind::RefPlane(_) | ElementKind::Railing(_) | ElementKind::RoomSeparation(_) | ElementKind::AreaBoundary(_) | ElementKind::Dimension(_) | ElementKind::WallFoundation(_));
            let hit = if open {
                edge_hit
            } else if matches!(c, Category::Floors | Category::Roofs | Category::Ceilings | Category::FilledRegions | Category::ImportedCad) {
                edge_hit
            } else {
                geom::contains(&outline, pt) || edge_hit
            };
            if hit {
                let area = if outline.len() > 2 { geom::area(&outline) } else { 0.0 };
                let id = target.id;
                let pr = if target.id != e.id { priority(Category::Groups) } else { priority(c) };
                if !hits.iter().any(|h| h.2 == id) {
                    hits.push((pr, area, id));
                }
            }
        }
    }
    hits.sort_by(|a, b| (a.0, a.1).partial_cmp(&(b.0, b.1)).unwrap_or(std::cmp::Ordering::Equal));
    hits.into_iter().map(|h| h.2).collect()
}

/// Elements in a plan rectangle: `crossing` selects anything touching it (right-to-left drag),
/// otherwise only elements fully inside (left-to-right drag).
pub fn select_in_rect(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, a: DVec2, b: DVec2, crossing: bool) -> Vec<Id> {
    let (mn, mx) = (a.min(b), a.max(b));
    let inside = |q: &DVec2| q.x >= mn.x && q.x <= mx.x && q.y >= mn.y && q.y <= mx.y;
    let rect = [mn, DVec2::new(mx.x, mn.y), mx, DVec2::new(mn.x, mx.y)];
    let mut out = Vec::new();
    for e in &p.elements {
        if e.group.is_some() || !in_plan(p, view, e) {
            continue;
        }
        let outlines = element_outline(p, e, footprints);
        if outlines.is_empty() || outlines.iter().all(|o| o.is_empty()) {
            continue;
        }
        let all_in = outlines.iter().flatten().all(inside);
        let any = all_in
            || (crossing
                && outlines.iter().any(|o| {
                    o.iter().any(inside)
                        || (0..o.len()).any(|k| {
                            let (s0, s1) = (o[k], o[(k + 1) % o.len()]);
                            (0..4).any(|j| geom::segment_intersection(s0, s1, rect[j], rect[(j + 1) % 4]).is_some())
                        })
                        || (o.len() > 2 && geom::contains(o, (mn + mx) / 2.0))
                }));
        if any {
            out.push(e.id);
        }
    }
    out
}
