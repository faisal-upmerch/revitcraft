//! File > Export > DWF/DWFx: sheets and views as a DWFx package (XPS fixed pages): lines and
//! fills as paths, text as glyphs in Arial, pictures and rendered 3D views as PNG images.
//! Insert > DWF Markup reads these pages back (see `markup`).

use crate::geom::DVec2;
use crate::model::Id;
use crate::plan::{Anchor, Dash};
use crate::sheet::SheetPrim;

/// Millimetres to XPS units (1/96 inch).
const PX: f64 = 96.0 / 25.4;

/// A page: its name (the file name inside the package), paper size in mm and contents.
pub struct DwfPage {
    pub name: String,
    pub size: DVec2,
    pub prims: Vec<SheetPrim>,
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

fn n(v: f64) -> String {
    let s = format!("{v:.2}");
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s.is_empty() || s == "-0" { "0".into() } else { s.to_string() }
}

fn hex(c: [u8; 3]) -> String {
    format!("#FF{:02X}{:02X}{:02X}", c[0], c[1], c[2])
}

/// A file name for a page: letters, digits, '-' and '_' only.
fn safe(name: &str, k: usize) -> String {
    let s: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' }).collect();
    let s = s.trim_matches('_').to_string();
    if s.is_empty() { format!("Page{}", k + 1) } else { s }
}

/// The package. `render` draws 3D views placed on sheets; `fonts` are Arial regular and bold
/// (text is left out when they are missing).
pub fn write(
    p: &crate::model::Project,
    pages: Vec<DwfPage>,
    render: &mut dyn FnMut(Id, u32, u32) -> Option<crate::pdf::Image>,
    fonts: (Option<Vec<u8>>, Option<Vec<u8>>),
) -> Vec<u8> {
    let mut files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut images: Vec<(String, Vec<u8>)> = Vec::new();
    let (regular, bold) = fonts;
    let bold_uri = if bold.is_some() { "/Resources/arialbd.ttf" } else { "/Resources/arial.ttf" };
    let mut doc = String::from(r#"<FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06">"#);
    let mut used = std::collections::HashSet::new();
    for (k, page) in pages.into_iter().enumerate() {
        let mut name = safe(&page.name, k);
        while !used.insert(name.clone()) {
            name = format!("{name}_{}", k + 1);
        }
        let (w, h) = (page.size.x * PX, page.size.y * PX);
        let at = |q: &DVec2| (q.x * PX, h - q.y * PX);
        let mut body = format!(r#"<FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="{}" Height="{}" xml:lang="en-US">"#, n(w), n(h));
        body.push_str(&format!(r##"<Canvas Name="{}"><Path Fill="#FFFFFFFF" Data="M 0,0 L {w},0 {w},{h} 0,{h} Z" />"##, crate::markup::SHEET_CANVAS, w = n(w), h = n(h)));
        let mut resources: Vec<String> = Vec::new();
        let mut image = |px: u32, py: u32, rgb: &[u8], min: DVec2, max: DVec2, body: &mut String, resources: &mut Vec<String>| {
            let file = format!("/Resources/image{}.png", images.len() + 1);
            images.push((file.trim_start_matches('/').to_string(), crate::png::encode(px, py, 3, rgb)));
            let (x0, y0) = at(&DVec2::new(min.x, max.y));
            let (x1, y1) = at(&DVec2::new(max.x, min.y));
            body.push_str(&format!(
                r#"<Path Data="M {x0},{y0} L {x1},{y0} {x1},{y1} {x0},{y1} Z"><Path.Fill><ImageBrush ImageSource="{file}" Viewbox="0,0,{px},{py}" ViewboxUnits="Absolute" Viewport="{x0},{y0},{vw},{vh}" ViewportUnits="Absolute" TileMode="None" /></Path.Fill></Path>"#,
                x0 = n(x0),
                y0 = n(y0),
                x1 = n(x1),
                y1 = n(y1),
                vw = n(x1 - x0),
                vh = n(y1 - y0),
            ));
            resources.push(file);
        };
        for prim in page.prims {
            match prim {
                SheetPrim::Line { pts, closed, width, color, dash, .. } => {
                    if pts.len() < 2 {
                        continue;
                    }
                    let mut d = String::new();
                    for (i, q) in pts.iter().enumerate() {
                        let (x, y) = at(q);
                        d.push_str(&format!("{}{},{} ", if i == 0 { "M " } else if i == 1 { "L " } else { "" }, n(x), n(y)));
                    }
                    if closed {
                        d.push('Z');
                    }
                    let t = (width as f64 * PX).max(0.5);
                    let dashes = match dash {
                        Dash::Solid => String::new(),
                        Dash::Dashed => r#" StrokeDashArray="6 3""#.into(),
                        Dash::DashDot => r#" StrokeDashArray="8 2 1 2""#.into(),
                        Dash::Dotted => r#" StrokeDashArray="1 2""#.into(),
                    };
                    body.push_str(&format!(r#"<Path Stroke="{}" StrokeThickness="{}"{dashes} StrokeLineJoin="Round" Data="{}" />"#, hex(color), n(t), d.trim_end()));
                }
                SheetPrim::Fill { tris, color, .. } => {
                    if color[3] == 0 || tris.is_empty() {
                        continue;
                    }
                    let mut d = String::new();
                    for t in &tris {
                        let [a, b, c] = t.map(|q| at(&q));
                        d.push_str(&format!("M {},{} L {},{} {},{} Z ", n(a.0), n(a.1), n(b.0), n(b.1), n(c.0), n(c.1)));
                    }
                    let fill = format!("#{:02X}{:02X}{:02X}{:02X}", color[3], color[0], color[1], color[2]);
                    body.push_str(&format!(r#"<Path Fill="{fill}" Data="{}" />"#, d.trim_end()));
                }
                SheetPrim::Text { pos, text, size, anchor, bold: is_bold, angle, color, .. } => {
                    if regular.is_none() || text.trim().is_empty() {
                        continue;
                    }
                    let size = size as f64;
                    let wdt = crate::pdf::text_width_em_font(&text, is_bold) * size;
                    let (dx, dy) = match anchor {
                        Anchor::Center => (-wdt / 2.0, -0.35 * size),
                        Anchor::Left => (0.0, 0.21 * size),
                        Anchor::Right => (-wdt, 0.21 * size),
                    };
                    let (c, s) = ((angle as f64).cos(), (angle as f64).sin());
                    let origin = DVec2::new(pos.x + c * dx - s * dy, pos.y + s * dx + c * dy);
                    let (ox, oy) = at(&origin);
                    // XPS turns clockwise with y down: the paper angle negated.
                    let transform = if angle.abs() > 1e-6 { format!(r#" RenderTransform="{},{},{},{},{},{}""#, n(c), n(-s), n(s), n(c), n(ox), n(oy)) } else { String::new() };
                    let (x, y) = if transform.is_empty() { (ox, oy) } else { (0.0, 0.0) };
                    let uri = if is_bold { bold_uri } else { "/Resources/arial.ttf" };
                    body.push_str(&format!(
                        r#"<Glyphs Fill="{}" FontUri="{uri}" FontRenderingEmSize="{}" StyleSimulations="{}" OriginX="{}" OriginY="{}"{transform} UnicodeString="{}" />"#,
                        hex(color),
                        n(size * PX),
                        if is_bold && bold.is_none() { "BoldSimulation" } else { "None" },
                        n(x),
                        n(y),
                        // A leading brace is escaped as {} (XPS markup extensions).
                        if text.starts_with('{') { format!("{{}}{}", esc(&text)) } else { esc(&text) }
                    ));
                    if !resources.iter().any(|r| r == uri) {
                        resources.push(uri.to_string());
                    }
                }
                SheetPrim::Picture { asset, min, max, .. } => {
                    if let Some(img) = p.images.iter().find(|a| a.id == asset).and_then(|a| a.rgb().map(|rgb| (a.width, a.height, rgb))) {
                        image(img.0, img.1, &img.2, min, max, &mut body, &mut resources);
                    }
                }
                SheetPrim::Image { view, min, max } => {
                    let px_per_mm = 6.0;
                    let iw = ((max.x - min.x) * px_per_mm).round().clamp(16.0, 4096.0) as u32;
                    let ih = ((max.y - min.y) * px_per_mm).round().clamp(16.0, 4096.0) as u32;
                    if let Some(img) = render(view, iw, ih) {
                        image(img.width, img.height, &img.rgb, min, max, &mut body, &mut resources);
                    }
                }
            }
        }
        body.push_str("</Canvas></FixedPage>");
        files.push((format!("Documents/1/Pages/{name}.fpage"), body.into_bytes()));
        if !resources.is_empty() {
            let mut rels = String::from(r#"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#);
            for (i, r) in resources.iter().enumerate() {
                rels.push_str(&format!(r#"<Relationship Id="R{i}" Type="http://schemas.microsoft.com/xps/2005/06/required-resource" Target="{r}" />"#));
            }
            rels.push_str("</Relationships>");
            files.push((format!("Documents/1/Pages/_rels/{name}.fpage.rels"), rels.into_bytes()));
        }
        doc.push_str(&format!(r#"<PageContent Source="/Documents/1/Pages/{name}.fpage" Width="{}" Height="{}" />"#, n(w), n(h)));
    }
    doc.push_str("</FixedDocument>");
    let mut out: Vec<(String, Vec<u8>)> = vec![
        (
            "[Content_Types].xml".into(),
            br#"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" /><Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml" /><Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml" /><Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml" /><Default Extension="png" ContentType="image/png" /><Default Extension="ttf" ContentType="application/vnd.ms-opentype" /></Types>"#.to_vec(),
        ),
        (
            "_rels/.rels".into(),
            br#"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="R0" Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocumentSequence.fdseq" /></Relationships>"#.to_vec(),
        ),
        ("FixedDocumentSequence.fdseq".into(), br#"<FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="/Documents/1/FixedDocument.fdoc" /></FixedDocumentSequence>"#.to_vec()),
        ("Documents/1/FixedDocument.fdoc".into(), doc.into_bytes()),
    ];
    out.extend(files);
    out.extend(images);
    if let Some(f) = regular {
        out.push(("Resources/arial.ttf".into(), f));
    }
    if let Some(f) = bold {
        out.push(("Resources/arialbd.ttf".into(), f));
    }
    crate::zip::write(&out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sheets_round_trip_through_dwf_markup() {
        let p = crate::sample::sample_house();
        let fp = crate::analysis::wall_footprints(&p);
        let sheet = p.views.iter().find(|v| matches!(v.kind, crate::model::ViewKind::Sheet(_))).unwrap();
        let (size, prims) = crate::sheet::print_layout(&p, sheet, &fp, &Default::default()).unwrap();
        let lines = prims.iter().filter(|q| matches!(q, SheetPrim::Line { .. })).count();
        let number = match &sheet.kind {
            crate::model::ViewKind::Sheet(s) => s.number.clone(),
            _ => unreachable!(),
        };
        let bytes = write(&p, vec![DwfPage { name: number.clone(), size, prims }], &mut |_, _, _| None, (Some(vec![0u8; 16]), None));
        let pages = crate::markup::read_dwfx(&bytes).unwrap();
        assert_eq!(pages.len(), 1);
        assert_eq!(pages[0].name, number);
        assert!((pages[0].width - size.x).abs() < 0.5 && (pages[0].height - size.y).abs() < 0.5);
        // The sheet itself stays out: only markups added to the page come back.
        assert!(lines > 0);
        assert!(pages[0].polylines.is_empty() && pages[0].texts.is_empty());
        let marked = String::from_utf8_lossy(&crate::zip::entries(&bytes).unwrap().into_iter().find(|(n, _)| n.ends_with(".fpage")).unwrap().1)
            .replace("</FixedPage>", r##"<Path Stroke="#FFFF0000" Data="M 10,10 L 50,50" /><Glyphs OriginX="60" OriginY="60" FontRenderingEmSize="12" UnicodeString="FIX" /></FixedPage>"##);
        let files: Vec<(String, Vec<u8>)> = crate::zip::entries(&bytes).unwrap().into_iter().map(|(n, b)| if n.ends_with(".fpage") { (n, marked.clone().into_bytes()) } else { (n, b) }).collect();
        let pages = crate::markup::read_dwfx(&crate::zip::write(&files)).unwrap();
        assert_eq!(pages[0].polylines.len(), 1);
        assert_eq!(pages[0].polylines[0].1, [255, 0, 0]);
        assert_eq!(pages[0].texts[0].1, "FIX");
    }
}
