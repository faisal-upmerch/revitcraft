//! DXF exchange: AutoCAD R12 (AC1009) ASCII export of views and sheets, and import of 2D
//! DXF drawings (lines, polylines with bulges, circles, arcs, ellipses, splines, text and
//! block inserts) as linked CAD underlays.

use crate::analysis::{self, Footprint};
use crate::geom::DVec2;
use crate::model::*;
use crate::plan::{Anchor, Dash, Drawing, Prim};
use crate::sheet::{self, SheetPrim};
use std::collections::{BTreeSet, HashMap};
use std::fmt::Write as _;

// ---------------------------------------------------------------- colours

/// RGB of an AutoCAD Color Index entry (approximation of the standard palette).
pub fn aci_rgb(i: u8) -> [u8; 3] {
    match i {
        1 => [255, 0, 0],
        2 => [255, 255, 0],
        3 => [0, 255, 0],
        4 => [0, 255, 255],
        5 => [0, 0, 255],
        6 => [255, 0, 255],
        0 | 7 => [0, 0, 0],
        8 => [128, 128, 128],
        9 => [192, 192, 192],
        250..=255 => {
            let g = [51u8, 80, 105, 130, 190, 255][(i - 250) as usize];
            [g, g, g]
        }
        _ => {
            let k = (i - 10) as usize;
            let hue = (k / 10) as f64 * 15.0;
            let variant = k % 10;
            let value = [1.0, 1.0, 0.8, 0.8, 0.6, 0.6, 0.5, 0.5, 0.3, 0.3][variant];
            let sat = if variant % 2 == 0 { 1.0 } else { 0.5 };
            hsv(hue, sat, value)
        }
    }
}

fn hsv(h: f64, s: f64, v: f64) -> [u8; 3] {
    let c = v * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;
    let (r, g, b) = match (h / 60.0) as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    [((r + m) * 255.0).round() as u8, ((g + m) * 255.0).round() as u8, ((b + m) * 255.0).round() as u8]
}

/// Nearest colour index for an RGB colour (black maps to 7, which CAD shows as black/white).
pub fn nearest_aci(rgb: [u8; 3]) -> u8 {
    if rgb[0] < 30 && rgb[1] < 30 && rgb[2] < 30 {
        return 7;
    }
    let mut best = (u32::MAX, 7u8);
    for i in 1..=255u8 {
        if i == 7 {
            continue;
        }
        let c = aci_rgb(i);
        let d: u32 = (0..3).map(|k| (c[k] as i32 - rgb[k] as i32).pow(2) as u32).sum();
        if d < best.0 {
            best = (d, i);
        }
    }
    best.1
}

// ---------------------------------------------------------------- export

struct Writer {
    out: String,
    layers: BTreeSet<String>,
}

impl Writer {
    fn pair(&mut self, code: i32, value: impl std::fmt::Display) {
        let _ = writeln!(self.out, "{code:>3}\n{value}");
    }
    fn num(&mut self, code: i32, v: f64) {
        self.pair(code, format!("{:.6}", v).trim_end_matches('0').trim_end_matches('.'));
    }
    fn common(&mut self, kind: &str, layer: &str, color: u8, linetype: Option<&str>) {
        self.layers.insert(layer.to_string());
        self.pair(0, kind);
        self.pair(8, layer);
        self.pair(62, color);
        if let Some(lt) = linetype {
            self.pair(6, lt);
        }
    }

    fn polyline(&mut self, layer: &str, pts: &[DVec2], closed: bool, rgb: [u8; 3], dash: Dash) {
        if pts.len() < 2 {
            return;
        }
        let lt = match dash {
            Dash::Solid => None,
            Dash::Dashed => Some("DASHED"),
            Dash::DashDot => Some("DASHDOT"),
            Dash::Dotted => Some("DOT"),
        };
        let color = nearest_aci(rgb);
        if pts.len() == 2 && !closed {
            self.common("LINE", layer, color, lt);
            self.num(10, pts[0].x);
            self.num(20, pts[0].y);
            self.num(30, 0.0);
            self.num(11, pts[1].x);
            self.num(21, pts[1].y);
            self.num(31, 0.0);
            return;
        }
        self.common("POLYLINE", layer, color, lt);
        self.pair(66, 1);
        self.num(10, 0.0);
        self.num(20, 0.0);
        self.num(30, 0.0);
        self.pair(70, if closed { 1 } else { 0 });
        for q in pts {
            self.pair(0, "VERTEX");
            self.pair(8, layer);
            self.num(10, q.x);
            self.num(20, q.y);
            self.num(30, 0.0);
        }
        self.pair(0, "SEQEND");
        self.pair(8, layer);
    }

    fn solid(&mut self, layer: &str, t: &[DVec2; 3], rgb: [u8; 3]) {
        self.common("SOLID", layer, nearest_aci(rgb), None);
        for (k, q) in [t[0], t[1], t[2], t[2]].iter().enumerate() {
            self.num(10 + k as i32, q.x);
            self.num(20 + k as i32, q.y);
            self.num(30 + k as i32, 0.0);
        }
    }

    fn text(&mut self, layer: &str, pos: DVec2, text: &str, height: f64, rgb: [u8; 3], anchor: Anchor, angle_deg: f64) {
        if text.trim().is_empty() {
            return;
        }
        self.common("TEXT", layer, nearest_aci(rgb), None);
        self.num(10, pos.x);
        self.num(20, pos.y);
        self.num(30, 0.0);
        self.num(40, height);
        self.pair(1, dxf_text(text));
        if angle_deg.abs() > 1e-6 {
            self.num(50, angle_deg);
        }
        // Justification as the views draw it: centred (middle), or bottom-left/right.
        let (h, v) = match anchor {
            Anchor::Center => (1, 2),
            Anchor::Left => (0, 1),
            Anchor::Right => (2, 1),
        };
        self.pair(72, h);
        self.num(11, pos.x);
        self.num(21, pos.y);
        self.num(31, 0.0);
        self.pair(73, v);
    }

    fn finish(self, units: i32) -> String {
        let mut head = Writer { out: String::new(), layers: BTreeSet::new() };
        head.pair(0, "SECTION");
        head.pair(2, "HEADER");
        head.pair(9, "$ACADVER");
        head.pair(1, "AC1009");
        head.pair(9, "$INSUNITS");
        head.pair(70, units);
        head.pair(0, "ENDSEC");
        head.pair(0, "SECTION");
        head.pair(2, "TABLES");
        // Line types.
        head.pair(0, "TABLE");
        head.pair(2, "LTYPE");
        head.pair(70, 4);
        for (name, desc, pattern) in [
            ("CONTINUOUS", "Solid line", vec![]),
            ("DASHED", "__ __ __", vec![6.0, -3.0]),
            ("DASHDOT", "__ . __ .", vec![8.0, -2.0, 0.0, -2.0]),
            ("DOT", ". . . .", vec![0.0, -2.0]),
        ] {
            head.pair(0, "LTYPE");
            head.pair(2, name);
            head.pair(70, 0);
            head.pair(3, desc);
            head.pair(72, 65);
            head.pair(73, pattern.len());
            head.num(40, pattern.iter().map(|v: &f64| v.abs()).sum());
            for v in pattern {
                head.num(49, v);
            }
        }
        head.pair(0, "ENDTAB");
        // Layers.
        head.pair(0, "TABLE");
        head.pair(2, "LAYER");
        head.pair(70, self.layers.len().max(1));
        for l in self.layers.iter().chain(std::iter::once(&"0".to_string())).collect::<BTreeSet<_>>() {
            head.pair(0, "LAYER");
            head.pair(2, l);
            head.pair(70, 0);
            head.pair(62, 7);
            head.pair(6, "CONTINUOUS");
        }
        head.pair(0, "ENDTAB");
        head.pair(0, "TABLE");
        head.pair(2, "STYLE");
        head.pair(70, 1);
        head.pair(0, "STYLE");
        head.pair(2, "STANDARD");
        head.pair(70, 0);
        head.num(40, 0.0);
        head.num(41, 1.0);
        head.num(50, 0.0);
        head.pair(71, 0);
        head.num(42, 2.5);
        head.pair(3, "txt");
        head.pair(4, "");
        head.pair(0, "ENDTAB");
        head.pair(0, "ENDSEC");
        head.pair(0, "SECTION");
        head.pair(2, "BLOCKS");
        head.pair(0, "ENDSEC");
        head.pair(0, "SECTION");
        head.pair(2, "ENTITIES");
        let mut out = head.out;
        out.push_str(&self.out);
        out.push_str("  0\nENDSEC\n  0\nEOF\n");
        out
    }
}

/// DXF R12 strings are 8-bit; non-ASCII characters use the \U+XXXX escape.
fn dxf_text(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        match c {
            '\n' | '\r' => out.push(' '),
            ' '..='~' => out.push(c),
            '°' => out.push_str("%%d"),
            '±' => out.push_str("%%p"),
            '⌀' | 'Ø' => out.push_str("%%c"),
            _ => {
                let _ = write!(out, "\\U+{:04X}", c as u32);
            }
        }
    }
    out
}

fn layer_name(s: &str) -> String {
    let s: String = s.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' }).collect();
    if s.is_empty() { "0".into() } else { s.to_uppercase() }
}

/// How exported DWG/DXF layers are named.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum LayerStandard {
    /// The American Institute of Architects CAD layer guidelines (the reference app's default
    /// export setup): A-WALL, A-DOOR, A-GLAZ, S-GRID, A-ANNO-DIMS...
    #[default]
    Aia,
    /// One layer per category, named after it.
    Category,
}

impl LayerStandard {
    pub const ALL: [LayerStandard; 2] = [LayerStandard::Aia, LayerStandard::Category];
    pub fn label(self) -> &'static str {
        match self {
            LayerStandard::Aia => "American Institute of Architects Standard (AIA)",
            LayerStandard::Category => "Category names",
        }
    }
}

/// AIA layer of an element (tags take their host's "-IDEN" layer, curtain walls "A-GLAZ-CWMG").
fn aia_layer(p: &Project, e: &Element) -> String {
    use Category::*;
    let host_cat = match &e.kind {
        ElementKind::Tag(t) => p.element(t.host).map(|h| h.category()),
        _ => None,
    };
    let s = match e.category() {
        Walls if matches!(&e.kind, ElementKind::Wall(w) if analysis::is_curtain(p, w)) => "A-GLAZ-CWMG",
        Walls => "A-WALL",
        Doors => "A-DOOR",
        Windows => "A-GLAZ",
        Floors => "A-FLOR",
        Ceilings => "A-CLNG",
        Roofs => "A-ROOF",
        Stairs => "A-FLOR-STRS",
        Ramps => "A-FLOR-LEVL",
        Railings => "A-FLOR-HRAL",
        Columns => "A-COLS",
        StructuralColumns => "S-COLS",
        StructuralFraming => "S-BEAM",
        StructuralFoundations => "S-FNDN",
        ShaftOpenings => "A-FLOR-OTLN",
        Furniture => "A-FURN",
        Casework => "A-FLOR-CASE",
        PlumbingFixtures => "P-SANR-FIXT",
        SpecialtyEquipment => "A-FLOR-SPCL",
        GenericModels => "A-GENM",
        Rooms => "A-AREA-IDEN",
        Areas | AreaBoundary => "A-AREA",
        RoomSeparation => "A-AREA-BNDY",
        Grids => "S-GRID",
        Levels => "S-GRID-IDEN",
        ReferencePlanes => "A-ANNO-REFR",
        Lines => "A-DETL",
        Dimensions => "A-ANNO-DIMS",
        TextNotes => "A-ANNO-TEXT",
        Tags => match host_cat {
            Some(Doors) => "A-DOOR-IDEN",
            Some(Windows) => "A-GLAZ-IDEN",
            Some(Rooms) | Some(Areas) => "A-AREA-IDEN",
            Some(Walls) => "A-WALL-IDEN",
            Some(StructuralColumns) | Some(StructuralFraming) => "S-ANNO-IDEN",
            _ => "A-ANNO-IDEN",
        },
        FilledRegions => "A-DETL-PATT",
        Symbols => "A-ANNO-SYMB",
        Mass => "A-MASS",
        Toposolid => "C-TOPO",
        Site => "C-SITE",
        Parking => "C-PRKG",
        Planting => "L-PLNT",
        PropertyLines => "C-PROP-LINE",
        Matchline => "A-ANNO-MTCH",
        ColorFillLegends => "A-ANNO-LEGN",
        _ => return layer_name(e.category().label()),
    };
    s.to_string()
}

/// The layer an element's graphics go on under `std`.
pub fn element_layer(p: &Project, e: &Element, std: LayerStandard) -> String {
    match std {
        LayerStandard::Aia => aia_layer(p, e),
        LayerStandard::Category => layer_name(e.category().label()),
    }
}

/// Writes a view drawing in model millimetres, on AIA layers.
pub fn export_drawing(p: &Project, d: &Drawing, view_scale: f64) -> String {
    export_drawing_with(p, d, view_scale, LayerStandard::Aia)
}

/// Writes a view drawing in model millimetres with layers named by `std`. Cut patterns and
/// fills go on the element layer's "-PATT" companion, as the reference app exports hatches.
pub fn export_drawing_with(p: &Project, d: &Drawing, view_scale: f64, std: LayerStandard) -> String {
    let layers: HashMap<Id, String> = p.elements.iter().map(|e| (e.id, element_layer(p, e, std))).collect();
    let annotation = if std == LayerStandard::Aia { "A-ANNO-SYMB" } else { "ANNOTATION" };
    let mut w = Writer { out: String::new(), layers: BTreeSet::new() };
    for (id, prim) in &d.prims {
        let layer = id.and_then(|i| layers.get(&i).cloned()).unwrap_or_else(|| annotation.to_string());
        match prim {
            Prim::Line { pts, closed, stroke } => w.polyline(&layer, pts, *closed, stroke.color, stroke.dash),
            // Images export as their frame (DXF image references need the file beside the drawing).
            Prim::Image { min, max, .. } => w.polyline(&layer, &[*min, DVec2::new(max.x, min.y), *max, DVec2::new(min.x, max.y)], true, [128, 128, 128], Dash::Solid),
            Prim::Fill { tris, color } => {
                // Skip invisible and pure white (masking) fills.
                if color[3] < 20 || (color[0] > 250 && color[1] > 250 && color[2] > 250) {
                    continue;
                }
                let fill_layer = if std == LayerStandard::Aia { format!("{layer}-PATT") } else { format!("{layer}-FILL") };
                for t in tris {
                    w.solid(&fill_layer, t, [color[0], color[1], color[2]]);
                }
            }
            Prim::Text { pos, text, size, color, anchor, angle, .. } => {
                w.text(&layer, *pos, text, *size as f64 * view_scale, *color, *anchor, (*angle as f64).to_degrees())
            }
        }
    }
    w.finish(4)
}

/// Exports a plan, section, elevation, drafting view or legend.
pub fn export_view(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Option<String> {
    export_view_with(p, view, footprints, LayerStandard::Aia)
}

pub fn export_view_with(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, std: LayerStandard) -> Option<String> {
    let d = sheet::view_drawing(p, view, footprints)?;
    Some(export_drawing_with(p, &d, view.scale, std))
}

/// Exports a sheet in paper millimetres (3D viewports appear as their frame).
pub fn export_sheet(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> String {
    export_sheet_with(p, view, footprints, LayerStandard::Aia)
}

/// A sheet with the views' elements on their layers and the sheet's own graphics (title block,
/// viewport titles) on the title block layer.
pub fn export_sheet_with(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, std: LayerStandard) -> String {
    let aia = std == LayerStandard::Aia;
    let layers: HashMap<Id, String> = p.elements.iter().map(|e| (e.id, element_layer(p, e, std))).collect();
    let sheet_layer = if aia { "G-ANNO-TTLB" } else { "SHEET" };
    let layer_of = |id: Option<Id>| id.and_then(|i| layers.get(&i).cloned()).unwrap_or_else(|| sheet_layer.to_string());
    let mut w = Writer { out: String::new(), layers: BTreeSet::new() };
    for prim in sheet::layout(p, view, footprints) {
        match prim {
            SheetPrim::Line { pts, closed, color, dash, id, .. } => w.polyline(&layer_of(id), &pts, closed, color, dash),
            SheetPrim::Fill { tris, color, id } => {
                if color[3] < 20 || (color[0] > 250 && color[1] > 250 && color[2] > 250) {
                    continue;
                }
                let l = format!("{}-{}", layer_of(id), if aia { "PATT" } else { "FILL" });
                for t in &tris {
                    w.solid(&l, t, [color[0], color[1], color[2]]);
                }
            }
            SheetPrim::Text { pos, text, size, anchor, angle, id, .. } => w.text(&layer_of(id).replace("SHEET", "SHEET-TEXT"), pos, &text, size as f64, [0, 0, 0], anchor, (angle as f64).to_degrees()),
            SheetPrim::Picture { min, max, id, .. } => {
                let pts = vec![min, DVec2::new(max.x, min.y), max, DVec2::new(min.x, max.y)];
                w.polyline(&layer_of(id), &pts, true, [128, 128, 128], Dash::Solid);
            }
            SheetPrim::Image { min, max, .. } => {
                let pts = vec![min, DVec2::new(max.x, min.y), max, DVec2::new(min.x, max.y)];
                w.polyline(if aia { "G-ANNO-VPRT" } else { "SHEET-VIEWPORT" }, &pts, true, [128, 128, 128], Dash::Solid);
            }
        }
    }
    w.finish(4)
}

// ---------------------------------------------------------------- import

#[derive(Clone, Copy)]
struct Xform {
    origin: DVec2,
    sx: f64,
    sy: f64,
    rot: f64,
    base: DVec2,
}

impl Xform {
    const ID: Xform = Xform { origin: DVec2::ZERO, sx: 1.0, sy: 1.0, rot: 0.0, base: DVec2::ZERO };
    fn apply(&self, p: DVec2) -> DVec2 {
        let q = DVec2::new((p.x - self.base.x) * self.sx, (p.y - self.base.y) * self.sy);
        let (s, c) = self.rot.sin_cos();
        self.origin + DVec2::new(q.x * c - q.y * s, q.x * s + q.y * c)
    }
    fn then(&self, inner: &Xform) -> Xform {
        // Approximation for nested inserts: compose origin and rotation, multiply scales.
        Xform { origin: self.apply(inner.origin), sx: self.sx * inner.sx, sy: self.sy * inner.sy, rot: self.rot + inner.rot, base: inner.base }
    }
}

type Ent = Vec<(i32, String)>;

fn get<'a>(e: &'a Ent, code: i32) -> Option<&'a str> {
    e.iter().find(|(c, _)| *c == code).map(|(_, v)| v.as_str())
}
fn num(e: &Ent, code: i32) -> Option<f64> {
    get(e, code).and_then(|v| v.trim().parse().ok())
}
fn all_nums(e: &Ent, code: i32) -> Vec<f64> {
    e.iter().filter(|(c, _)| *c == code).filter_map(|(_, v)| v.trim().parse().ok()).collect()
}

fn bulge_points(a: DVec2, b: DVec2, bulge: f64) -> Vec<DVec2> {
    if bulge.abs() < 1e-9 {
        return vec![a];
    }
    let theta = 4.0 * bulge.atan();
    let chord = b - a;
    let len = chord.length();
    if len < 1e-12 {
        return vec![a];
    }
    let r = len / (2.0 * (theta / 2.0).sin());
    let mid = (a + b) / 2.0;
    let n = DVec2::new(-chord.y, chord.x) / len;
    let h = r * (theta / 2.0).cos();
    let center = mid + n * h;
    let a0 = (a - center).y.atan2((a - center).x);
    let segs = ((theta.abs() / (std::f64::consts::PI / 16.0)).ceil() as usize).max(2);
    (0..segs).map(|k| {
        let t = a0 + theta * k as f64 / segs as f64;
        center + DVec2::new(t.cos(), t.sin()) * r.abs()
    }).collect()
}

fn arc_points(c: DVec2, r: f64, a0_deg: f64, a1_deg: f64) -> Vec<DVec2> {
    let mut a1 = a1_deg;
    while a1 <= a0_deg {
        a1 += 360.0;
    }
    let sweep = (a1 - a0_deg).to_radians();
    let n = ((sweep / (std::f64::consts::PI / 24.0)).ceil() as usize).max(2);
    (0..=n).map(|k| {
        let t = a0_deg.to_radians() + sweep * k as f64 / n as f64;
        c + DVec2::new(t.cos(), t.sin()) * r
    }).collect()
}

struct Importer<'a> {
    layers: HashMap<String, i32>,
    blocks: HashMap<String, (DVec2, Vec<Ent>)>,
    scale: f64,
    out: &'a mut CadImport,
}

impl Importer<'_> {
    fn color(&self, e: &Ent, block_color: [u8; 3]) -> Option<[u8; 3]> {
        let layer = get(e, 8).unwrap_or("0");
        let lc = self.layers.get(layer).copied().unwrap_or(7);
        if lc < 0 {
            return None; // layer off
        }
        let c = num(e, 62).map(|v| v as i32).unwrap_or(256);
        Some(match c {
            256 => aci_rgb(lc.clamp(0, 255) as u8),
            0 => block_color,
            c if c < 0 => return None,
            c => aci_rgb(c.clamp(0, 255) as u8),
        })
    }

    fn push_line(&mut self, pts: Vec<DVec2>, color: [u8; 3], xf: &Xform) {
        if pts.len() >= 2 {
            let pts = pts.into_iter().map(|q| xf.apply(q) * self.scale).collect();
            self.out.polylines.push((pts, color));
        }
    }

    fn entities(&mut self, ents: &[Ent], xf: &Xform, block_color: [u8; 3], depth: usize) {
        let mut k = 0;
        while k < ents.len() {
            let e = &ents[k];
            let kind = get(e, 0).unwrap_or("");
            let Some(color) = self.color(e, block_color) else {
                k += 1;
                if kind == "POLYLINE" {
                    while k < ents.len() && get(&ents[k], 0) != Some("SEQEND") {
                        k += 1;
                    }
                }
                continue;
            };
            let p2 = |cx: i32, cy: i32| DVec2::new(num(e, cx).unwrap_or(0.0), num(e, cy).unwrap_or(0.0));
            match kind {
                "LINE" => self.push_line(vec![p2(10, 20), p2(11, 21)], color, xf),
                "LWPOLYLINE" => {
                    let closed = num(e, 70).map(|f| f as i32 & 1 == 1).unwrap_or(false);
                    // Vertices with optional bulges, in order.
                    let mut verts: Vec<(DVec2, f64)> = Vec::new();
                    let mut x = None;
                    for (c, v) in e {
                        match c {
                            10 => x = v.trim().parse::<f64>().ok(),
                            20 => {
                                if let (Some(xv), Ok(yv)) = (x, v.trim().parse::<f64>()) {
                                    verts.push((DVec2::new(xv, yv), 0.0));
                                }
                            }
                            42 => {
                                if let (Some(last), Ok(b)) = (verts.last_mut(), v.trim().parse::<f64>()) {
                                    last.1 = b;
                                }
                            }
                            _ => {}
                        }
                    }
                    let pts = expand_bulges(&verts, closed);
                    self.push_line(pts, color, xf);
                }
                "POLYLINE" => {
                    let closed = num(e, 70).map(|f| f as i32 & 1 == 1).unwrap_or(false);
                    let mut verts = Vec::new();
                    k += 1;
                    while k < ents.len() && get(&ents[k], 0) == Some("VERTEX") {
                        let v = &ents[k];
                        verts.push((DVec2::new(num(v, 10).unwrap_or(0.0), num(v, 20).unwrap_or(0.0)), num(v, 42).unwrap_or(0.0)));
                        k += 1;
                    }
                    let pts = expand_bulges(&verts, closed);
                    self.push_line(pts, color, xf);
                }
                "CIRCLE" => {
                    let mut pts = arc_points(p2(10, 20), num(e, 40).unwrap_or(0.0), 0.0, 360.0);
                    pts.pop();
                    pts.push(pts[0]);
                    self.push_line(pts, color, xf);
                }
                "ARC" => {
                    let pts = arc_points(p2(10, 20), num(e, 40).unwrap_or(0.0), num(e, 50).unwrap_or(0.0), num(e, 51).unwrap_or(360.0));
                    self.push_line(pts, color, xf);
                }
                "ELLIPSE" => {
                    let c = p2(10, 20);
                    let major = p2(11, 21);
                    let ratio = num(e, 40).unwrap_or(1.0);
                    let (t0, mut t1) = (num(e, 41).unwrap_or(0.0), num(e, 42).unwrap_or(std::f64::consts::TAU));
                    if t1 <= t0 {
                        t1 += std::f64::consts::TAU;
                    }
                    let minor = DVec2::new(-major.y, major.x) * ratio;
                    let n = 48;
                    let pts = (0..=n).map(|i| {
                        let t = t0 + (t1 - t0) * i as f64 / n as f64;
                        c + major * t.cos() + minor * t.sin()
                    }).collect();
                    self.push_line(pts, color, xf);
                }
                "SPLINE" => {
                    // Fit points if present, else the control polygon (smoothed).
                    let fx = all_nums(e, 11);
                    let fy = all_nums(e, 21);
                    let (xs, ys) = if fx.len() >= 2 { (fx, fy) } else { (all_nums(e, 10), all_nums(e, 20)) };
                    let pts: Vec<DVec2> = xs.iter().zip(ys.iter()).map(|(x, y)| DVec2::new(*x, *y)).collect();
                    self.push_line(chaikin(&pts, 2), color, xf);
                }
                "TEXT" | "MTEXT" => {
                    let text = get(e, 1).unwrap_or("").to_string();
                    let text = clean_mtext(&text);
                    let h = num(e, 40).unwrap_or(2.5);
                    let pos = xf.apply(p2(10, 20)) * self.scale;
                    if !text.is_empty() {
                        self.out.texts.push((pos, text, h * self.scale * xf.sy.abs()));
                    }
                }
                "SOLID" | "TRACE" | "3DFACE" => {
                    let pts = vec![p2(10, 20), p2(11, 21), p2(13, 23), p2(12, 22)];
                    let mut closed = pts.clone();
                    closed.push(pts[0]);
                    self.push_line(closed, color, xf);
                }
                "INSERT" if depth < 8 => {
                    let name = get(e, 2).unwrap_or("").to_string();
                    if let Some((base, body)) = self.blocks.get(&name).cloned() {
                        let inner = Xform {
                            origin: p2(10, 20),
                            sx: num(e, 41).unwrap_or(1.0),
                            sy: num(e, 42).unwrap_or(1.0),
                            rot: num(e, 50).unwrap_or(0.0).to_radians(),
                            base,
                        };
                        let composed = xf.then(&inner);
                        self.entities(&body, &composed, color, depth + 1);
                    }
                }
                _ => {}
            }
            k += 1;
        }
    }
}

fn expand_bulges(verts: &[(DVec2, f64)], closed: bool) -> Vec<DVec2> {
    let mut pts = Vec::new();
    let n = verts.len();
    for i in 0..n {
        let (a, bulge) = verts[i];
        let next = if i + 1 < n { Some(verts[i + 1].0) } else if closed { Some(verts[0].0) } else { None };
        match next {
            Some(b) => pts.extend(bulge_points(a, b, bulge)),
            None => pts.push(a),
        }
    }
    if closed && !pts.is_empty() {
        pts.push(pts[0]);
    }
    pts
}

fn chaikin(pts: &[DVec2], iterations: usize) -> Vec<DVec2> {
    let mut v = pts.to_vec();
    for _ in 0..iterations {
        if v.len() < 3 {
            break;
        }
        let mut out = vec![v[0]];
        for w in v.windows(2) {
            out.push(w[0] * 0.75 + w[1] * 0.25);
            out.push(w[0] * 0.25 + w[1] * 0.75);
        }
        out.push(*v.last().unwrap());
        v = out;
    }
    v
}

fn clean_mtext(s: &str) -> String {
    // Strip common MTEXT formatting codes.
    let mut out = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\\' => match chars.next() {
                Some('P') | Some('X') => out.push(' '),
                Some('\\') => out.push('\\'),
                Some(_) => {
                    // Skip to ';' for codes with arguments.
                    while let Some(&n) = chars.peek() {
                        chars.next();
                        if n == ';' {
                            break;
                        }
                    }
                }
                None => {}
            },
            '{' | '}' => {}
            _ => out.push(c),
        }
    }
    out.replace("%%d", "°").replace("%%p", "±").replace("%%c", "⌀").trim().to_string()
}

/// Imports a DXF drawing; coordinates are converted to millimetres using $INSUNITS.
pub fn import(text: &str, name: &str) -> Result<CadImport, String> {
    let lines: Vec<&str> = text.lines().collect();
    if lines.len() < 4 {
        return Err("The file is empty or not a DXF drawing.".into());
    }
    let mut pairs: Vec<(i32, String)> = Vec::with_capacity(lines.len() / 2);
    let mut i = 0;
    while i + 1 < lines.len() {
        let code: i32 = lines[i].trim().parse().map_err(|_| format!("Not an ASCII DXF file (bad group code on line {}).", i + 1))?;
        pairs.push((code, lines[i + 1].trim_end().to_string()));
        i += 2;
    }
    // Split into sections.
    let mut sections: HashMap<String, Vec<Ent>> = HashMap::new();
    let mut k = 0;
    while k < pairs.len() {
        if pairs[k].0 == 0 && pairs[k].1 == "SECTION" && k + 1 < pairs.len() {
            let name = pairs[k + 1].1.clone();
            k += 2;
            let mut ents: Vec<Ent> = Vec::new();
            while k < pairs.len() && !(pairs[k].0 == 0 && pairs[k].1 == "ENDSEC") {
                if pairs[k].0 == 0 || ents.is_empty() {
                    ents.push(Vec::new());
                }
                ents.last_mut().unwrap().push(pairs[k].clone());
                k += 1;
            }
            sections.insert(name, ents);
        }
        k += 1;
    }
    // Units.
    let mut scale = 1.0;
    if let Some(header) = sections.get("HEADER") {
        let flat: Vec<&(i32, String)> = header.iter().flatten().collect();
        for w in flat.windows(2) {
            if w[0].0 == 9 && w[0].1 == "$INSUNITS" && w[1].0 == 70 {
                scale = match w[1].1.trim().parse::<i32>().unwrap_or(4) {
                    1 => 25.4,
                    2 => 304.8,
                    5 => 10.0,
                    6 => 1000.0,
                    8 => 0.0254,
                    14 => 100.0,
                    _ => 1.0,
                };
            }
        }
    }
    // Layer colours.
    let mut layers = HashMap::new();
    for e in sections.get("TABLES").map(|v| v.as_slice()).unwrap_or(&[]) {
        if get(e, 0) == Some("LAYER") {
            if let Some(n) = get(e, 2) {
                layers.insert(n.to_string(), num(e, 62).unwrap_or(7.0) as i32);
            }
        }
    }
    // Blocks.
    let mut blocks = HashMap::new();
    let mut current: Option<(String, DVec2, Vec<Ent>)> = None;
    for e in sections.get("BLOCKS").map(|v| v.as_slice()).unwrap_or(&[]) {
        match get(e, 0) {
            Some("BLOCK") => {
                current = Some((get(e, 2).unwrap_or("").to_string(), DVec2::new(num(e, 10).unwrap_or(0.0), num(e, 20).unwrap_or(0.0)), Vec::new()))
            }
            Some("ENDBLK") => {
                if let Some((n, base, body)) = current.take() {
                    blocks.insert(n, (base, body));
                }
            }
            _ => {
                if let Some((_, _, body)) = current.as_mut() {
                    body.push(e.clone());
                }
            }
        }
    }
    let ents = sections.get("ENTITIES").cloned().unwrap_or_default();
    if ents.is_empty() {
        return Err("The DXF file has no entities.".into());
    }
    let mut out = CadImport { name: name.to_string(), level: None, polylines: Vec::new(), texts: Vec::new(), halftone: true };
    let mut imp = Importer { layers, blocks, scale, out: &mut out };
    imp.entities(&ents, &Xform::ID, [0, 0, 0], 0);
    if out.polylines.is_empty() && out.texts.is_empty() {
        return Err("No supported 2D entities (lines, polylines, arcs, circles, text) were found.".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{analysis, sample};

    #[test]
    fn colour_index_round_trip() {
        assert_eq!(nearest_aci([255, 0, 0]), 1);
        assert_eq!(nearest_aci([0, 0, 0]), 7);
        assert_eq!(nearest_aci([0, 0, 255]), 5);
    }

    #[test]
    fn plan_exports_and_reimports() {
        let p = sample::sample_house();
        let fp = analysis::wall_footprints(&p);
        let view = p.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. })).unwrap();
        let text = export_view(&p, view, &fp).unwrap();
        assert!(text.contains("AC1009"));
        // AIA layers by default; category names on request.
        assert!(text.contains("A-WALL") && text.contains("S-GRID") && text.contains("A-DOOR"));
        let named = export_view_with(&p, view, &fp, LayerStandard::Category).unwrap();
        assert!(named.contains("WALLS"));
        assert!(text.trim_end().ends_with("EOF"));
        let cad = import(&text, "plan").unwrap();
        assert!(cad.polylines.len() > 20);
        assert!(!cad.texts.is_empty());
    }

    #[test]
    fn imports_bulges_blocks_and_units() {
        let dxf = "0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n6\n0\nENDSEC\n0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nB1\n10\n0\n20\n0\n0\nLINE\n8\n0\n10\n0\n20\n0\n11\n1\n21\n0\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLWPOLYLINE\n8\n0\n90\n2\n70\n0\n10\n0\n20\n0\n42\n1\n10\n2\n20\n0\n0\nINSERT\n8\n0\n2\nB1\n10\n5\n20\n5\n50\n90\n0\nENDSEC\n0\nEOF\n";
        let cad = import(dxf, "t").unwrap();
        assert_eq!(cad.polylines.len(), 2);
        // Metres → millimetres; the half circle bulges below the chord for a CCW bulge of 1.
        let arc = &cad.polylines[0].0;
        assert!((arc[0].x - 0.0).abs() < 1e-6 && (arc.last().unwrap().x - 2000.0).abs() < 1e-6);
        assert!(arc.iter().any(|q| (q.y.abs() - 1000.0).abs() < 50.0));
        // The block line rotated 90° about (5, 5) m.
        let line = &cad.polylines[1].0;
        assert!((line[1] - DVec2::new(5000.0, 6000.0)).length() < 1e-6);
    }
}
