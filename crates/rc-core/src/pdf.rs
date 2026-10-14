//! A small vector PDF writer (lines, fills, Helvetica text, RGB images) for sheet export.

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

/// Encodes text for a WinAnsi Helvetica string literal.
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
                let code: Option<u8> = match c {
                    '€' => Some(0x80),
                    '–' => Some(0x96),
                    '—' => Some(0x97),
                    '•' => Some(0x95),
                    c if (c as u32) >= 0xA0 && (c as u32) <= 0xFF => Some(c as u32 as u8),
                    _ => None,
                };
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

/// Approximate Helvetica advance width (in em) used for centring text.
pub fn text_width_em(s: &str) -> f64 {
    s.chars()
        .map(|c| match c {
            'i' | 'j' | 'l' | '.' | ',' | ':' | ';' | '\'' | '!' | '|' => 0.24,
            'f' | 't' | 'r' | 'I' | ' ' | '(' | ')' | '[' | ']' | '-' => 0.32,
            'm' | 'M' | 'W' => 0.84,
            'w' => 0.72,
            c if c.is_ascii_uppercase() => 0.68,
            c if c.is_ascii_digit() => 0.556,
            _ => 0.54,
        })
        .sum()
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
    pub fn line(&mut self, pts: &[(f64, f64)], closed: bool, width_mm: f64, rgb: [u8; 3], dashed: bool) {
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
            if dashed { "[4 2] 0" } else { "[] 0" }
        );
        self.path(pts, closed);
        self.ops.push_str("S\n");
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
        let w = if center { text_width_em(s) * size } else { 0.0 };
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

    /// Text rotated by `angle` radians about its anchor.
    #[allow(clippy::too_many_arguments)]
    pub fn text_rot(&mut self, x: f64, y: f64, size_mm: f64, s: &str, rgb: [u8; 3], center: bool, bold: bool, angle: f64) {
        if angle.abs() < 1e-9 {
            self.text(x, y, size_mm, s, rgb, center, bold);
            return;
        }
        let size = size_mm * PT_PER_MM;
        let w = if center { text_width_em(s) * size } else { 0.0 };
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
    objects[font - 1] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".to_vec();
    objects[font_bold - 1] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>".to_vec();
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
        page.line(&[(10.0, 10.0), (410.0, 10.0), (410.0, 287.0)], false, 0.5, [0, 0, 0], false);
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
