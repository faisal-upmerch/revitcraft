//! Sheet composition: title block (with revision schedule), viewports of any view type, schedules.
//! Everything is in paper millimetres with the origin at the bottom-left corner.

use crate::analysis::Footprint;
use crate::geom::{self, DVec2, DVec3};
use crate::model::*;
use crate::plan::{self, Anchor, Drawing, Prim};
use crate::schedule;
use crate::section;
use std::collections::HashMap;

#[derive(Clone, Debug)]
pub enum SheetPrim {
    /// `id`: the element drawn (None for the sheet's own graphics), for export layers.
    Line { pts: Vec<DVec2>, closed: bool, width: f32, color: [u8; 3], dash: plan::Dash, id: Option<Id> },
    Fill { tris: Vec<[DVec2; 3]>, color: [u8; 4], id: Option<Id> },
    Text { pos: DVec2, text: String, size: f32, anchor: Anchor, bold: bool, angle: f32, id: Option<Id> },
    /// A rendered 3D image of `view` fills this rectangle.
    Image { view: Id, min: DVec2, max: DVec2 },
    /// A project image asset (Import/Link Image) fills this rectangle.
    Picture { asset: Id, min: DVec2, max: DVec2, id: Option<Id> },
}

#[derive(Clone, Debug)]
pub struct ViewportBox {
    pub index: usize,
    pub view: Id,
    pub min: DVec2,
    pub max: DVec2,
}

pub const MARGIN: f64 = 10.0;
pub const TITLE_W: f64 = 180.0;
pub const TITLE_H: f64 = 72.0;

/// Model bounding box over all elements with 3D geometry.
pub fn model_bounds(p: &Project, footprints: &HashMap<Id, Footprint>) -> Option<(DVec3, DVec3)> {
    section::model_bounds(p, footprints)
}

/// The 2D drawing of any drawable view (plans, sections, elevations, drafting, legends).
pub fn view_drawing(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Option<Drawing> {
    let mut d = match view.kind {
        ViewKind::Section { .. } | ViewKind::Elevation { .. } => {
            let mut d = section::drawing(p, view, footprints);
            if view.crop_active {
                d.crop = view.crop;
            }
            d
        }
        _ if view.is_planar_2d() => plan::floor_plan(p, view, footprints),
        _ => return None,
    };
    plan::apply_object_styles(p, &mut d);
    Some(d)
}

fn schedule_size(t: &schedule::Table) -> (Vec<f64>, f64, f64) {
    let widths: Vec<f64> = t
        .columns
        .iter()
        .enumerate()
        .map(|(ci, c)| {
            let longest = t.rows.iter().map(|r| r.cells[ci].chars().count()).max().unwrap_or(0).max(c.def.name.chars().count());
            longest as f64 * 1.9 + 4.0
        })
        .collect();
    let row_h = 6.0;
    let w: f64 = widths.iter().sum();
    let h = row_h * (t.rows.len() as f64 + 2.0);
    (widths, w.max(40.0), h)
}

/// Paper size of a view placed on a sheet.
pub fn viewport_size(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> DVec2 {
    match &view.kind {
        ViewKind::ThreeD { .. } => DVec2::new(160.0, 120.0),
        ViewKind::Schedule(def) => {
            let (_, w, h) = schedule_size(&schedule::build(p, def));
            DVec2::new(w, h)
        }
        ViewKind::Sheet(_) => DVec2::ZERO,
        _ => match view_drawing(p, view, footprints).and_then(|d| d.bounds()) {
            Some((mn, mx)) => (mx - mn) / view.scale + DVec2::splat(10.0),
            None => DVec2::new(120.0, 90.0),
        },
    }
}

pub fn viewport_boxes(p: &Project, sheet: &Sheet, footprints: &HashMap<Id, Footprint>) -> Vec<ViewportBox> {
    sheet
        .viewports
        .iter()
        .enumerate()
        .filter_map(|(index, vp)| {
            let v = p.view(vp.view)?;
            let size = viewport_size(p, v, footprints);
            let c = DVec2::new(vp.cx, vp.cy);
            Some(ViewportBox { index, view: vp.view, min: c - size / 2.0, max: c + size / 2.0 })
        })
        .collect()
}

fn line(out: &mut Vec<SheetPrim>, pts: Vec<DVec2>, closed: bool, width: f32) {
    out.push(SheetPrim::Line { pts, closed, width, color: [0, 0, 0], dash: plan::Dash::Solid, id: None });
}

fn text(out: &mut Vec<SheetPrim>, pos: DVec2, s: impl Into<String>, size: f32, bold: bool) {
    out.push(SheetPrim::Text { pos, text: s.into(), size, anchor: Anchor::Left, bold, angle: 0.0, id: None });
}

fn rect(a: DVec2, b: DVec2) -> Vec<DVec2> {
    vec![a, DVec2::new(b.x, a.y), b, DVec2::new(a.x, b.y)]
}

/// Clips a segment to a rectangle (Liang–Barsky).
fn clip_segment(a: DVec2, b: DVec2, mn: DVec2, mx: DVec2) -> Option<(DVec2, DVec2)> {
    let d = b - a;
    let (mut t0, mut t1) = (0.0f64, 1.0f64);
    for (pv, qv) in [(-d.x, a.x - mn.x), (d.x, mx.x - a.x), (-d.y, a.y - mn.y), (d.y, mx.y - a.y)] {
        if pv.abs() < 1e-12 {
            if qv < 0.0 {
                return None;
            }
        } else {
            let r = qv / pv;
            if pv < 0.0 {
                t0 = t0.max(r);
            } else {
                t1 = t1.min(r);
            }
        }
    }
    (t0 <= t1).then(|| (a + d * t0, a + d * t1))
}

/// Maps a view drawing onto the sheet, clipping to its crop.
fn place_drawing(out: &mut Vec<SheetPrim>, d: Drawing, center: DVec2, scale: f64) {
    let Some((mn, mx)) = d.bounds() else { return };
    let wc = (mn + mx) / 2.0;
    let map = |q: DVec2| center + (q - wc) / scale;
    let crop = d.crop;
    let inside = |q: DVec2| crop.is_none_or(|(a, b)| q.x >= a.x && q.x <= b.x && q.y >= a.y && q.y <= b.y);
    for (id, prim) in d.prims {
        match prim {
            Prim::Line { pts, closed, stroke } => {
                let mut pts = pts;
                if closed && !pts.is_empty() {
                    pts.push(pts[0]);
                }
                match crop {
                    None => out.push(SheetPrim::Line { pts: pts.into_iter().map(map).collect(), closed: false, width: stroke.width, color: stroke.color, dash: stroke.dash, id }),
                    Some((a, b)) => {
                        for s in pts.windows(2) {
                            if let Some((p0, p1)) = clip_segment(s[0], s[1], a, b) {
                                out.push(SheetPrim::Line { pts: vec![map(p0), map(p1)], closed: false, width: stroke.width, color: stroke.color, dash: stroke.dash, id });
                            }
                        }
                    }
                }
            }
            Prim::Fill { tris, color } => {
                let tris: Vec<[DVec2; 3]> = match crop {
                    None => tris,
                    Some((a, b)) => tris
                        .into_iter()
                        .flat_map(|t| {
                            let poly = geom::clip_convex(&t, |q| q.x, a.x, b.x);
                            let poly = geom::clip_convex(&poly, |q| q.y, a.y, b.y);
                            (1..poly.len().saturating_sub(1)).map(|k| [poly[0], poly[k], poly[k + 1]]).collect::<Vec<_>>()
                        })
                        .collect(),
                };
                out.push(SheetPrim::Fill { tris: tris.into_iter().map(|t| [map(t[0]), map(t[1]), map(t[2])]).collect(), color, id });
            }
            Prim::Text { pos, text, size, anchor, angle, bold, .. } => {
                if inside(pos) {
                    out.push(SheetPrim::Text { pos: map(pos), text, size, anchor, bold, angle, id });
                }
            }
            Prim::Image { asset, min, max } => {
                let (a, b) = geom::bounds([map(min), map(max)]);
                out.push(SheetPrim::Picture { asset, min: a, max: b, id });
            }
        }
    }
}

/// Lays out a whole sheet.
pub fn layout(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Vec<SheetPrim> {
    let ViewKind::Sheet(sheet) = &view.kind else { return vec![] };
    let (pw, ph) = sheet.size.paper();
    let mut out = Vec::new();

    // Border and title block.
    line(&mut out, rect(DVec2::new(MARGIN + 10.0, MARGIN), DVec2::new(pw - MARGIN, ph - MARGIN)), true, 0.7);
    let tb0 = DVec2::new(pw - MARGIN - TITLE_W, MARGIN);
    let tb1 = DVec2::new(pw - MARGIN, MARGIN + TITLE_H);
    line(&mut out, rect(tb0, tb1), true, 0.5);
    let rows = [MARGIN + 14.0, MARGIN + 28.0, MARGIN + 46.0, MARGIN + 58.0];
    for y in rows {
        line(&mut out, vec![DVec2::new(tb0.x, y), DVec2::new(tb1.x, y)], false, 0.25);
    }
    let mid = tb0.x + TITLE_W / 2.0;
    line(&mut out, vec![DVec2::new(mid, MARGIN), DVec2::new(mid, rows[1])], false, 0.25);
    let small = 2.0;
    let x0 = tb0.x + 3.0;
    text(&mut out, DVec2::new(x0, MARGIN + 66.0), if p.info.organization.is_empty() { "RevitCraft".to_string() } else { p.info.organization.clone() }, 4.0, true);
    text(&mut out, DVec2::new(x0, rows[3] + 2.5), format!("{}   ({})", p.info.name, p.info.number), 3.0, true);
    text(&mut out, DVec2::new(x0, rows[2] + 7.5), "Sheet name", small, false);
    text(&mut out, DVec2::new(x0, rows[2] + 2.5), &view.name, 4.0, true);
    text(&mut out, DVec2::new(x0, rows[1] + 13.0), "Sheet number", small, false);
    text(&mut out, DVec2::new(x0, rows[1] + 3.0), &sheet.number, 8.0, true);
    text(&mut out, DVec2::new(x0, rows[0] + 9.0), "Drawn by", small, false);
    text(&mut out, DVec2::new(x0, rows[0] + 3.0), &sheet.drawn_by, 3.0, false);
    text(&mut out, DVec2::new(mid + 3.0, rows[0] + 9.0), "Checked by", small, false);
    text(&mut out, DVec2::new(mid + 3.0, rows[0] + 3.0), &sheet.checked_by, 3.0, false);
    text(&mut out, DVec2::new(x0, MARGIN + 9.0), "Issue date", small, false);
    text(&mut out, DVec2::new(x0, MARGIN + 3.0), &sheet.issue_date, 3.0, false);
    text(&mut out, DVec2::new(mid + 3.0, MARGIN + 9.0), "Scale", small, false);
    text(&mut out, DVec2::new(mid + 3.0, MARGIN + 3.0), "As indicated", 3.0, false);

    // Revision schedule above the title block.
    let revs: Vec<&Revision> = sheet.revisions.iter().filter_map(|id| p.revisions.iter().find(|r| r.id == *id)).collect();
    if !revs.is_empty() {
        let row_h = 5.0;
        let top = MARGIN + TITLE_H + row_h * (revs.len() as f64 + 1.0);
        line(&mut out, rect(DVec2::new(tb0.x, MARGIN + TITLE_H), DVec2::new(tb1.x, top)), true, 0.35);
        text(&mut out, DVec2::new(x0, top - row_h + 1.5), "Rev    Description                               Date", 2.2, true);
        for (k, r) in revs.iter().enumerate() {
            let y = top - row_h * (k as f64 + 2.0) + 1.5;
            text(&mut out, DVec2::new(x0, y), format!("{:<5}  {:<40}  {}", r.sequence, r.description, r.date), 2.2, false);
        }
    }

    for vb in viewport_boxes(p, sheet, footprints) {
        let Some(v) = p.view(vb.view) else { continue };
        let vp = &sheet.viewports[vb.index];
        let center = (vb.min + vb.max) / 2.0;
        match &v.kind {
            ViewKind::ThreeD { .. } => {
                out.push(SheetPrim::Image { view: v.id, min: vb.min, max: vb.max });
                line(&mut out, rect(vb.min, vb.max), true, 0.18);
            }
            ViewKind::Schedule(def) => {
                let t = schedule::build(p, def);
                let (widths, w, _) = schedule_size(&t);
                let row_h = 6.0;
                let top = vb.max.y;
                let left = vb.min.x;
                line(&mut out, rect(vb.min, DVec2::new(left + w, top)), true, 0.35);
                text(&mut out, DVec2::new(left + 2.0, top - row_h + 1.8), format!("<{}>", v.name), 3.0, true);
                let mut y = top - row_h;
                let rows_all: Vec<(Vec<String>, bool)> = std::iter::once((t.columns.iter().map(|c| c.def.name.clone()).collect(), true))
                    .chain(t.rows.iter().map(|r| (r.cells.clone(), matches!(r.kind, schedule::RowKind::Total | schedule::RowKind::Header))))
                    .collect();
                for (cells, bold) in rows_all {
                    line(&mut out, vec![DVec2::new(left, y), DVec2::new(left + w, y)], false, 0.18);
                    let mut x = left;
                    for (ci, c) in cells.iter().enumerate() {
                        text(&mut out, DVec2::new(x + 1.5, y - row_h + 1.8), c, 2.5, bold);
                        x += widths.get(ci).copied().unwrap_or(20.0);
                    }
                    y -= row_h;
                }
                let mut x = left;
                for wd in &widths[..widths.len().saturating_sub(1)] {
                    x += wd;
                    line(&mut out, vec![DVec2::new(x, top - row_h), DVec2::new(x, vb.min.y)], false, 0.18);
                }
                continue;
            }
            ViewKind::Sheet(_) => continue,
            _ => {
                if let Some(d) = view_drawing(p, v, footprints) {
                    place_drawing(&mut out, d, center, v.scale);
                }
            }
        }
        if !vp.show_title {
            continue;
        }
        // Viewport title: detail number bubble, name, underline and scale.
        let ty = vb.min.y - 7.0;
        let bubble = DVec2::new(vb.min.x + 4.5, ty + 1.0);
        line(&mut out, plan::circle(bubble, 4.5, 24), true, 0.35);
        line(&mut out, vec![bubble - DVec2::new(4.5, 0.0), bubble + DVec2::new(4.5, 0.0)], false, 0.25);
        out.push(SheetPrim::Text { pos: bubble + DVec2::new(0.0, 2.0), text: vp.detail_number.clone(), size: 2.5, anchor: Anchor::Center, bold: true, angle: 0.0, id: None });
        out.push(SheetPrim::Text { pos: bubble - DVec2::new(0.0, 2.4), text: sheet.number.clone(), size: 1.8, anchor: Anchor::Center, bold: false, angle: 0.0, id: None });
        let title = if v.title_on_sheet.is_empty() { v.name.clone() } else { v.title_on_sheet.clone() };
        let tx = vb.min.x + 11.0;
        text(&mut out, DVec2::new(tx, ty + 1.0), title, 3.5, true);
        line(&mut out, vec![DVec2::new(tx, ty - 0.5), DVec2::new(tx + 70.0_f64.min((vb.max.x - vb.min.x).max(40.0)), ty - 0.5)], false, 0.5);
        if !matches!(v.kind, ViewKind::ThreeD { .. }) {
            text(&mut out, DVec2::new(tx, ty - 4.5), format!("1 : {}", v.scale.round()), 2.5, false);
        }
    }
    // Annotation drawn on the sheet itself (text, detail lines, symbols, regions, clouds).
    // Already in paper millimetres: copied as they are.
    for (id, prim) in sheet_annotations(p, view, footprints).prims {
        match prim {
            Prim::Line { mut pts, closed, stroke } => {
                if closed && !pts.is_empty() {
                    pts.push(pts[0]);
                }
                out.push(SheetPrim::Line { pts, closed: false, width: stroke.width, color: stroke.color, dash: stroke.dash, id });
            }
            Prim::Fill { tris, color } => out.push(SheetPrim::Fill { tris, color, id }),
            Prim::Text { pos, text, size, anchor, angle, .. } => out.push(SheetPrim::Text { pos, text, size, anchor, bold: false, angle, id }),
            Prim::Image { asset, min, max } => out.push(SheetPrim::Picture { asset, min, max, id }),
        }
    }
    out
}

/// The sheet's own annotation, drawn at paper scale (1 model mm = 1 paper mm).
pub fn sheet_annotations(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Drawing {
    let mut sv = view.clone();
    sv.scale = 1.0;
    let mut d = Drawing::default();
    plan::annotation_graphics(p, &sv, footprints, &mut d);
    d
}

/// Colors of printed and exported sheets (the reference app's Print Setup "Colors").
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum PrintColors {
    #[default]
    Color,
    /// Text and non-white lines black; solid fills and images in grey.
    BlackLines,
    Grayscale,
}

impl PrintColors {
    pub const ALL: [PrintColors; 3] = [PrintColors::BlackLines, PrintColors::Grayscale, PrintColors::Color];
    pub fn label(self) -> &'static str {
        match self {
            PrintColors::Color => "Color",
            PrintColors::BlackLines => "Black Lines",
            PrintColors::Grayscale => "Grayscale",
        }
    }
}

/// Print / PDF export settings, as in the reference app's Print Setup and PDF export.
#[derive(Clone, Debug, PartialEq)]
pub struct PrintSettings {
    pub colors: PrintColors,
    /// Views (not sheets): None = a page sized to the view at its scale; Some = this paper.
    pub paper: Option<SheetSize>,
    pub landscape: bool,
    /// On a chosen paper: fit the view to the page (else print it at 100% of its scale).
    pub fit_to_page: bool,
    pub hide_ref_planes: bool,
    pub hide_scope_boxes: bool,
}

impl Default for PrintSettings {
    fn default() -> Self {
        PrintSettings { colors: PrintColors::Color, paper: None, landscape: true, fit_to_page: true, hide_ref_planes: true, hide_scope_boxes: true }
    }
}

fn grey(c: [u8; 3]) -> u8 {
    (0.299 * c[0] as f64 + 0.587 * c[1] as f64 + 0.114 * c[2] as f64).round() as u8
}

/// Applies the settings to laid-out primitives: hidden categories dropped, colours converted.
pub fn apply_print_settings(p: &Project, prims: Vec<SheetPrim>, s: &PrintSettings) -> Vec<SheetPrim> {
    let hidden = |id: Option<Id>| {
        id.and_then(|i| p.element(i)).is_some_and(|e| (s.hide_ref_planes && e.category() == Category::ReferencePlanes) || (s.hide_scope_boxes && e.category() == Category::ScopeBoxes))
    };
    let line_color = |c: [u8; 3]| match s.colors {
        PrintColors::Color => c,
        PrintColors::BlackLines => if c.iter().all(|v| *v > 250) { c } else { [0, 0, 0] },
        PrintColors::Grayscale => [grey(c); 3],
    };
    let fill_color = |c: [u8; 4]| match s.colors {
        PrintColors::Color => c,
        _ => {
            let g = grey([c[0], c[1], c[2]]);
            [g, g, g, c[3]]
        }
    };
    prims
        .into_iter()
        .filter_map(|prim| match prim {
            SheetPrim::Line { id, .. } | SheetPrim::Fill { id, .. } | SheetPrim::Text { id, .. } | SheetPrim::Picture { id, .. } if hidden(id) => None,
            SheetPrim::Line { pts, closed, width, color, dash, id } => Some(SheetPrim::Line { pts, closed, width, color: line_color(color), dash, id }),
            SheetPrim::Fill { tris, color, id } => Some(SheetPrim::Fill { tris, color: fill_color(color), id }),
            other => Some(other),
        })
        .collect()
}

/// A project image for PDF output (grey when printing in grayscale or black lines).
fn picture(p: &Project, asset: Id, grey_out: bool) -> Option<crate::pdf::Image> {
    let a = p.images.iter().find(|a| a.id == asset)?;
    let mut rgb = a.rgb()?;
    if grey_out {
        for px in rgb.chunks_mut(3) {
            let g = grey([px[0], px[1], px[2]]);
            px.copy_from_slice(&[g, g, g]);
        }
    }
    Some(crate::pdf::Image { width: a.width, height: a.height, rgb })
}

/// Writes a sheet to PDF. `render` produces an RGB image (w, h, pixels) for 3D viewports.
pub fn to_pdf_page(
    p: &Project,
    view: &View,
    footprints: &HashMap<Id, Footprint>,
    render: &mut dyn FnMut(Id, u32, u32) -> Option<crate::pdf::Image>,
) -> crate::pdf::Page {
    to_pdf_page_with(p, view, footprints, render, &PrintSettings::default())
}

pub fn to_pdf_page_with(
    p: &Project,
    view: &View,
    footprints: &HashMap<Id, Footprint>,
    render: &mut dyn FnMut(Id, u32, u32) -> Option<crate::pdf::Image>,
    settings: &PrintSettings,
) -> crate::pdf::Page {
    let ViewKind::Sheet(sheet) = &view.kind else { return crate::pdf::Page::new(297.0, 210.0) };
    let (pw, ph) = sheet.size.paper();
    let mut page = crate::pdf::Page::new(pw, ph);
    let xy = |q: &DVec2| (q.x, q.y);
    for prim in apply_print_settings(p, layout(p, view, footprints), settings) {
        match prim {
            SheetPrim::Line { pts, closed, width, color, dash, .. } => page.line(&pts.iter().map(xy).collect::<Vec<_>>(), closed, width as f64, color, dash),
            SheetPrim::Fill { tris, color, .. } => {
                let a = color[3] as f64 / 255.0;
                if a <= 0.0 {
                    continue;
                }
                let c = [0, 1, 2].map(|k| (color[k] as f64 * a + 255.0 * (1.0 - a)).round() as u8);
                for t in tris {
                    page.fill(&t.iter().map(xy).collect::<Vec<_>>(), c);
                }
            }
            SheetPrim::Text { pos, text, size, anchor, bold, angle, .. } => page.text_anchored(pos.x, pos.y, size as f64, &text, [0, 0, 0], anchor, bold, angle as f64),
            SheetPrim::Picture { asset, min, max, .. } => {
                if let Some(img) = picture(p, asset, settings.colors != PrintColors::Color) {
                    page.image(min.x, min.y, max.x - min.x, max.y - min.y, img);
                }
            }
            SheetPrim::Image { view, min, max } => {
                let px_per_mm = 6.0;
                let w = ((max.x - min.x) * px_per_mm).round().clamp(16.0, 4096.0) as u32;
                let h = ((max.y - min.y) * px_per_mm).round().clamp(16.0, 4096.0) as u32;
                if let Some(mut img) = render(view, w, h) {
                    if settings.colors != PrintColors::Color {
                        for px in img.rgb.chunks_mut(3) {
                            let g = grey([px[0], px[1], px[2]]);
                            px.copy_from_slice(&[g, g, g]);
                        }
                    }
                    page.image(min.x, min.y, max.x - min.x, max.y - min.y, img);
                }
            }
        }
    }
    page
}

/// A standalone view (not a sheet) as a PDF page at its scale.
pub fn view_to_pdf_page(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>) -> Option<crate::pdf::Page> {
    view_to_pdf_page_with(p, view, footprints, &PrintSettings::default())
}

/// What printing `view` puts on paper: the page size (mm) and its primitives with the settings
/// applied. Sheets print at their sheet size; views on a page sized to them at their scale, or
/// centred on the chosen paper at 100% or fitted inside 10 mm margins.
pub fn print_layout(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, settings: &PrintSettings) -> Option<(DVec2, Vec<SheetPrim>)> {
    if let ViewKind::Sheet(sheet) = &view.kind {
        let (pw, ph) = sheet.size.paper();
        return Some((DVec2::new(pw, ph), apply_print_settings(p, layout(p, view, footprints), settings)));
    }
    let d = view_drawing(p, view, footprints)?;
    let (mn, mx) = d.bounds()?;
    let natural = (mx - mn) / view.scale;
    let (page_size, scale) = match settings.paper {
        None => (natural + DVec2::splat(30.0), view.scale),
        Some(size) => {
            let (a, b) = size.paper();
            let (w, h) = if settings.landscape { (a.max(b), a.min(b)) } else { (a.min(b), a.max(b)) };
            let paper = DVec2::new(w, h);
            let fit = ((paper.x - 20.0) / natural.x.max(1e-6)).min((paper.y - 20.0) / natural.y.max(1e-6));
            (paper, if settings.fit_to_page { view.scale / fit } else { view.scale })
        }
    };
    let page_size = page_size.max(DVec2::new(100.0, 80.0));
    let mut out = Vec::new();
    place_drawing(&mut out, d, page_size / 2.0, scale);
    Some((page_size, apply_print_settings(p, out, settings)))
}

/// A standalone view as a PDF page (see `print_layout`).
pub fn view_to_pdf_page_with(p: &Project, view: &View, footprints: &HashMap<Id, Footprint>, settings: &PrintSettings) -> Option<crate::pdf::Page> {
    if matches!(view.kind, ViewKind::Sheet(_)) {
        return None;
    }
    let (page_size, prims) = print_layout(p, view, footprints, settings)?;
    let mut page = crate::pdf::Page::new(page_size.x, page_size.y);
    for prim in prims {
        match prim {
            SheetPrim::Line { pts, closed, width, color, dash, .. } => page.line(&pts.iter().map(|q| (q.x, q.y)).collect::<Vec<_>>(), closed, width as f64, color, dash),
            SheetPrim::Fill { tris, color, .. } => {
                if color[3] == 0 {
                    continue;
                }
                let a = color[3] as f64 / 255.0;
                let c = [0, 1, 2].map(|k| (color[k] as f64 * a + 255.0 * (1.0 - a)).round() as u8);
                for t in tris {
                    page.fill(&t.iter().map(|q| (q.x, q.y)).collect::<Vec<_>>(), c);
                }
            }
            SheetPrim::Text { pos, text, size, anchor, bold, angle, .. } => page.text_anchored(pos.x, pos.y, size as f64, &text, [0, 0, 0], anchor, bold, angle as f64),
            SheetPrim::Image { .. } => {}
            SheetPrim::Picture { asset, min, max, .. } => {
                if let Some(img) = picture(p, asset, settings.colors != PrintColors::Color) {
                    page.image(min.x, min.y, max.x - min.x, max.y - min.y, img);
                }
            }
        }
    }
    Some(page)
}
