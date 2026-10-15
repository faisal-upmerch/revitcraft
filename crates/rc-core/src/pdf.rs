//! A small vector PDF writer (lines, fills, Arial text, RGB images) for sheet export.

use flate2::Compression;
use flate2::write::ZlibEncoder;
use std::fmt::Write as _;
use std::io::Write as _;

const PT_PER_MM: f64 = 72.0 / 25.4;

pub struct Image {
    pub width: u32,
    pub height: u32,
    /// Tightly packed RGB8 rows, top row first.
    pub rgb: Vec<u8>,
}

pub struct Page {
    pub width_mm: f64,
    pub height_mm: f64,
    ops: String,
    images: Vec<Image>,
}

fn n(v: f64) -> String {
    let s = format!("{:.3}", v);
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s == "-0" || s.is_empty() { "0".into() } else { s.to_string() }
}

/// Encodes text for a WinAnsi string literal.
fn pdf_text(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        match c {
            '(' | ')' | '\\' => {
                out.push('\\');
                out.push(c);
            }
            ' '..='~' => out.push(c),
            _ => {
                let code = win_ansi(c);
                match code {
                    Some(b) => {
                        let _ = write!(out, "\\{:03o}", b);
                    }
                    None => out.push('?'),
                }
            }
        }
    }
    out
}

/// WinAnsi code of a character (the encoding the PDF fonts use), if it has one.
fn win_ansi(c: char) -> Option<u8> {
    Some(match c {
        ' '..='~' => c as u8,
        '€' => 0x80,
        '‚' => 0x82,
        'ƒ' => 0x83,
        '„' => 0x84,
        '…' => 0x85,
        '†' => 0x86,
        '‡' => 0x87,
        'ˆ' => 0x88,
        '‰' => 0x89,
        'Š' => 0x8A,
        '‹' => 0x8B,
        'Œ' => 0x8C,
        'Ž' => 0x8E,
        '\u{2018}' => 0x91,
        '\u{2019}' => 0x92,
        '\u{201C}' => 0x93,
        '\u{201D}' => 0x94,
        '•' => 0x95,
        '–' => 0x96,
        '—' => 0x97,
        '˜' => 0x98,
        '™' => 0x99,
        'š' => 0x9A,
        '›' => 0x9B,
        'œ' => 0x9C,
        'ž' => 0x9E,
        'Ÿ' => 0x9F,
        c if (0xA0..=0xFF).contains(&(c as u32)) => c as u32 as u8,
        _ => return None,
    })
}

/// Advance widths (1/1000 em) of Arial — metrically the same as Helvetica — for WinAnsi
/// codes 32..=255, regular and bold. Revit's PDFs set annotation text in Arial.
const ARIAL_WIDTHS: [u16; 224] = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, // 32
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, // 48
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, // 64
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, // 80
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, // 96
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 350, // 112
    556, 350, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350, // 128
    350, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 350, 500, 667, // 144
    278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333, // 160
    400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611, // 176
    667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, // 192
    722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, // 208
    556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278, // 224
    556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500, // 240
];

const ARIAL_BOLD_WIDTHS: [u16; 224] = [
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, // 32
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, // 48
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, // 64
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556, // 80
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611, // 96
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 350, // 112
    556, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350, // 128
    350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 350, 500, 667, // 144
    278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333, // 160
    400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611, // 176
    722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, // 192
    722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, // 208
    556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, // 224
    611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556, // 240
];

/// Advance width of `s` in em, from Arial's metrics (characters without a WinAnsi code count
/// as a question mark, which is what the PDF shows for them).
pub fn text_width_em_font(s: &str, bold: bool) -> f64 {
    let table = if bold { &ARIAL_BOLD_WIDTHS } else { &ARIAL_WIDTHS };
    s.chars().map(|c| table[(win_ansi(c).unwrap_or(b'?').max(32) - 32) as usize] as f64 / 1000.0).sum()
}

/// Advance width of regular text in em.
pub fn text_width_em(s: &str) -> f64 {
    text_width_em_font(s, false)
}

/// A non-embedded TrueType Arial font dictionary with its widths (viewers use the installed
/// Arial, or a metric-compatible substitute).
fn arial_font(bold: bool, descriptor: usize) -> Vec<u8> {
    let table = if bold { &ARIAL_BOLD_WIDTHS } else { &ARIAL_WIDTHS };
    let widths: Vec<String> = table.iter().map(|w| w.to_string()).collect();
    format!(
        "<< /Type /Font /Subtype /TrueType /BaseFont /{} /FirstChar 32 /LastChar 255 /Widths [{}] /FontDescriptor {} 0 R /Encoding /WinAnsiEncoding >>",
        if bold { "Arial-BoldMT" } else { "ArialMT" },
        widths.join(" "),
        descriptor
    )
    .into_bytes()
}

fn arial_descriptor(bold: bool) -> Vec<u8> {
    format!(
        "<< /Type /FontDescriptor /FontName /{} /Flags 32 /FontBBox [{}] /ItalicAngle 0 /Ascent 905 /Descent -212 /CapHeight 716 /StemV {} >>",
        if bold { "Arial-BoldMT" } else { "ArialMT" },
        if bold { "-628 -376 2000 1018" } else { "-665 -325 2000 1006" },
        if bold { 136 } else { 80 }
    )
    .into_bytes()
}

impl Page {
    pub fn new(width_mm: f64, height_mm: f64) -> Page {
        Page { width_mm, height_mm, ops: String::new(), images: Vec::new() }
    }

    fn path(&mut self, pts: &[(f64, f64)], closed: bool) {
        for (k, (x, y)) in pts.iter().enumerate() {
            let _ = writeln!(self.ops, "{} {} {}", n(x * PT_PER_MM), n(y * PT_PER_MM), if k == 0 { "m" } else { "l" });
        }
        if closed {
            self.ops.push_str("h\n");
        }
    }

    /// Strokes a polyline; coordinates in millimetres from the bottom-left corner.
    pub fn line(&mut self, pts: &[(f64, f64)], closed: bool, width_mm: f64, rgb: [u8; 3], dash: crate::plan::Dash) {
        if pts.len() < 2 {
            return;
        }
        let _ = writeln!(
            self.ops,
            "{} w {} {} {} RG {} d",
            n(width_mm * PT_PER_MM),
            n(rgb[0] as f64 / 255.0),
            n(rgb[1] as f64 / 255.0),
            n(rgb[2] as f64 / 255.0),
            dash_array(dash)
        );
        self.path(pts, closed);
        self.ops.push_str("S\n");
    }

    /// Shorthand for solid or plain dashed lines.
    pub fn line_dashed(&mut self, pts: &[(f64, f64)], closed: bool, width_mm: f64, rgb: [u8; 3], dashed: bool) {
        self.line(pts, closed, width_mm, rgb, if dashed { crate::plan::Dash::Dashed } else { crate::plan::Dash::Solid });
    }

    pub fn fill(&mut self, pts: &[(f64, f64)], rgb: [u8; 3]) {
        if pts.len() < 3 {
            return;
        }
        let _ = writeln!(self.ops, "{} {} {} rg", n(rgb[0] as f64 / 255.0), n(rgb[1] as f64 / 255.0), n(rgb[2] as f64 / 255.0));
        self.path(pts, true);
        self.ops.push_str("f\n");
    }

    /// Text with its baseline at y; `center` centres horizontally on x.
    pub fn text(&mut self, x: f64, y: f64, size_mm: f64, s: &str, rgb: [u8; 3], center: bool, bold: bool) {
        let size = size_mm * PT_PER_MM;
        let w = if center { text_width_em_font(s, bold) * size } else { 0.0 };
        let _ = writeln!(
            self.ops,
            "BT /{} {} Tf {} {} {} rg {} {} Td ({}) Tj ET",
            if bold { "F2" } else { "F1" },
            n(size),
            n(rgb[0] as f64 / 255.0),
            n(rgb[1] as f64 / 255.0),
            n(rgb[2] as f64 / 255.0),
            n(x * PT_PER_MM - w / 2.0),
            n(y * PT_PER_MM),
            pdf_text(s)
        );
    }

    /// Text placed like the views draw it: `Center` centres the text box on the point,
    /// `Left`/`Right` put its bottom-left/bottom-right corner there (the box bottom is the
    /// descender line, about 0.21 em below the baseline).
    #[allow(clippy::too_many_arguments)]
    pub fn text_anchored(&mut self, x: f64, y: f64, size_mm: f64, s: &str, rgb: [u8; 3], anchor: crate::plan::Anchor, bold: bool, angle: f64) {
        use crate::plan::Anchor;
        let size = size_mm * PT_PER_MM;
        let w = text_width_em_font(s, bold) * size;
        let (dx, dy) = match anchor {
            Anchor::Center => (-w / 2.0, -0.35 * size),
            Anchor::Left => (0.0, 0.21 * size),
            Anchor::Right => (-w, 0.21 * size),
        };
        let (c, sn) = (angle.cos(), angle.sin());
        let (px, py) = (x * PT_PER_MM + c * dx - sn * dy, y * PT_PER_MM + sn * dx + c * dy);
        let _ = writeln!(
            self.ops,
            "BT /{} {} Tf {} {} {} rg {} {} {} {} {} {} Tm ({}) Tj ET",
            if bold { "F2" } else { "F1" },
            n(size),
            n(rgb[0] as f64 / 255.0),
            n(rgb[1] as f64 / 255.0),
            n(rgb[2] as f64 / 255.0),
            n(c),
            n(sn),
            n(-sn),
            n(c),
            n(px),
            n(py),
            pdf_text(s)
        );
    }

    /// Text rotated by `angle` radians about its anchor.
    #[allow(clippy::too_many_arguments)]
    pub fn text_rot(&mut self, x: f64, y: f64, size_mm: f64, s: &str, rgb: [u8; 3], center: bool, bold: bool, angle: f64) {
        if angle.abs() < 1e-9 {
            self.text(x, y, size_mm, s, rgb, center, bold);
            return;
        }
        let size = size_mm * PT_PER_MM;
        let w = if center { text_width_em_font(s, bold) * size } else { 0.0 };
        let (c, sn) = (angle.cos(), angle.sin());
        let (px, py) = (x * PT_PER_MM - c * w / 2.0, y * PT_PER_MM - sn * w / 2.0);
        let _ = writeln!(
            self.ops,
            "BT /{} {} Tf {} {} {} rg {} {} {} {} {} {} Tm ({}) Tj ET",
            if bold { "F2" } else { "F1" },
            n(size),
            n(rgb[0] as f64 / 255.0),
            n(rgb[1] as f64 / 255.0),
            n(rgb[2] as f64 / 255.0),
            n(c),
            n(sn),
            n(-sn),
            n(c),
            n(px),
            n(py),
            pdf_text(s)
        );
    }

    /// Places an image in the rectangle (x, y)–(x + w, y + h), millimetres.
    pub fn image(&mut self, x: f64, y: f64, w: f64, h: f64, img: Image) {
        let idx = self.images.len() + 1;
        let _ = writeln!(
            self.ops,
            "q {} 0 0 {} {} {} cm /Im{idx} Do Q",
            n(w * PT_PER_MM),
            n(h * PT_PER_MM),
            n(x * PT_PER_MM),
            n(y * PT_PER_MM)
        );
        self.images.push(img);
    }
}

fn deflate(data: &[u8]) -> Vec<u8> {
    let mut e = ZlibEncoder::new(Vec::new(), Compression::default());
    e.write_all(data).expect("in-memory write");
    e.finish().expect("in-memory write")
}

/// Serialises pages into a PDF document.
pub fn write(pages: Vec<Page>, title: &str) -> Vec<u8> {
    let mut objects: Vec<Vec<u8>> = Vec::new(); // object n is objects[n - 1]
    let reserve = |objects: &mut Vec<Vec<u8>>| {
        objects.push(Vec::new());
        objects.len()
    };
    let catalog = reserve(&mut objects);
    let pages_obj = reserve(&mut objects);
    let font = reserve(&mut objects);
    let font_bold = reserve(&mut objects);
    let info = reserve(&mut objects);
    let (desc, desc_bold) = (reserve(&mut objects), reserve(&mut objects));
    objects[font - 1] = arial_font(false, desc);
    objects[font_bold - 1] = arial_font(true, desc_bold);
    objects[desc - 1] = arial_descriptor(false);
    objects[desc_bold - 1] = arial_descriptor(true);
    objects[info - 1] = format!("<< /Title ({}) /Producer (RevitCraft) >>", pdf_text(title)).into_bytes();

    let mut kids = Vec::new();
    for page in pages {
        let mut xobjects = String::new();
        for (k, img) in page.images.iter().enumerate() {
            let data = deflate(&img.rgb);
            let id = reserve(&mut objects);
            let mut obj = format!(
                "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {} >>\nstream\n",
                img.width,
                img.height,
                data.len()
            )
            .into_bytes();
            obj.extend_from_slice(&data);
            obj.extend_from_slice(b"\nendstream");
            objects[id - 1] = obj;
            let _ = write!(xobjects, "/Im{} {} 0 R ", k + 1, id);
        }
        let content = deflate(page.ops.as_bytes());
        let cid = reserve(&mut objects);
        let mut obj = format!("<< /Length {} /Filter /FlateDecode >>\nstream\n", content.len()).into_bytes();
        obj.extend_from_slice(&content);
        obj.extend_from_slice(b"\nendstream");
        objects[cid - 1] = obj;
        let pid = reserve(&mut objects);
        objects[pid - 1] = format!(
            "<< /Type /Page /Parent {pages_obj} 0 R /MediaBox [0 0 {} {}] /Resources << /Font << /F1 {font} 0 R /F2 {font_bold} 0 R >> /XObject << {xobjects}>> >> /Contents {cid} 0 R >>",
            n(page.width_mm * PT_PER_MM),
            n(page.height_mm * PT_PER_MM)
        )
        .into_bytes();
        kids.push(pid);
    }
    objects[catalog - 1] = format!("<< /Type /Catalog /Pages {pages_obj} 0 R >>").into_bytes();
    objects[pages_obj - 1] = format!(
        "<< /Type /Pages /Kids [{}] /Count {} >>",
        kids.iter().map(|k| format!("{k} 0 R")).collect::<Vec<_>>().join(" "),
        kids.len()
    )
    .into_bytes();

    let mut out = b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".to_vec();
    let mut offsets = Vec::new();
    for (k, obj) in objects.iter().enumerate() {
        offsets.push(out.len());
        out.extend_from_slice(format!("{} 0 obj\n", k + 1).as_bytes());
        out.extend_from_slice(obj);
        out.extend_from_slice(b"\nendobj\n");
    }
    let xref = out.len();
    out.extend_from_slice(format!("xref\n0 {}\n0000000000 65535 f \n", objects.len() + 1).as_bytes());
    for o in offsets {
        out.extend_from_slice(format!("{:010} 00000 n \n", o).as_bytes());
    }
    out.extend_from_slice(
        format!("trailer\n<< /Size {} /Root {catalog} 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n", objects.len() + 1).as_bytes(),
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_a_well_formed_pdf() {
        let mut page = Page::new(420.0, 297.0);
        page.line(&[(10.0, 10.0), (410.0, 10.0), (410.0, 287.0)], false, 0.5, [0, 0, 0], crate::plan::Dash::Solid);
        page.fill(&[(20.0, 20.0), (40.0, 20.0), (40.0, 40.0)], [200, 100, 50]);
        page.text(50.0, 50.0, 3.5, "Area 12.50 m² (ground)", [0, 0, 0], true, false);
        page.image(100.0, 100.0, 50.0, 30.0, Image { width: 2, height: 1, rgb: vec![255, 0, 0, 0, 0, 255] });
        let bytes = write(vec![page], "Test");
        let text = String::from_utf8_lossy(&bytes);
        assert!(text.starts_with("%PDF-1.4"));
        assert!(text.trim_end().ends_with("%%EOF"));
        // The xref offset must point at the xref keyword.
        let start = text.rfind("startxref\n").unwrap() + 10;
        let off: usize = text[start..].lines().next().unwrap().parse().unwrap();
        assert_eq!(&bytes[off..off + 4], b"xref");
        assert!(pdf_text("m²").contains("\\262"));
    }
}

/// PDF dash arrays (points) for the line patterns, in paper sizes matching the views.
fn dash_array(dash: crate::plan::Dash) -> String {
    use crate::plan::Dash;
    let mm = |v: f64| n(v * PT_PER_MM);
    match dash {
        Dash::Solid => "[] 0".into(),
        Dash::Dashed => format!("[{} {}] 0", mm(3.0), mm(1.5)),
        Dash::DashDot => format!("[{} {} {} {}] 0", mm(6.0), mm(1.2), mm(0.5), mm(1.2)),
        Dash::Dotted => format!("[{} {}] 0", mm(0.5), mm(1.1)),
    }
}

#[cfg(test)]
mod export_tests {
    use super::*;

    /// Arial (Helvetica-metric) advance widths, regular and bold.
    #[test]
    fn arial_widths() {
        assert!((text_width_em_font("Hello", false) - 2.278).abs() < 1e-9);
        assert!((text_width_em_font("Hello", true) - 2.445).abs() < 1e-9);
        assert!((text_width_em("90°") - 1.512).abs() < 1e-9);
        let pdf = String::from_utf8_lossy(&write(vec![Page::new(100.0, 100.0)], "t")).to_string();
        assert!(pdf.contains("/BaseFont /ArialMT") && pdf.contains("/BaseFont /Arial-BoldMT") && pdf.contains("/Widths ["));
    }
}
