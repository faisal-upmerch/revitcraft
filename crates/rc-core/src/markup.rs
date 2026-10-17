//! Insert > DWF Markup: the marked-up pages of a DWFx package (XPS fixed pages): their lines
//! and text, in paper millimetres from the page's bottom left.

/// One marked-up page.
#[derive(Clone, Debug, Default)]
pub struct MarkupPage {
    pub name: String,
    pub width: f64,
    pub height: f64,
    pub polylines: Vec<(Vec<crate::geom::DVec2>, [u8; 3])>,
    /// (position, text, height).
    pub texts: Vec<(crate::geom::DVec2, String, f64)>,
}

use crate::geom::DVec2;

/// The canvas holding a page's own drawing in DWFx files RevitCraft exports.
pub const SHEET_CANVAS: &str = "RevitCraftSheet";

/// XPS units (1/96 inch) to millimetres.
const MM: f64 = 25.4 / 96.0;

fn attr(tag: &str, name: &str) -> Option<String> {
    let key = format!("{name}=\"");
    let i = tag.find(&key)? + key.len();
    let j = tag[i..].find('"')? + i;
    Some(tag[i..j].replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\""))
}

fn color(v: &str) -> [u8; 3] {
    let h = v.trim_start_matches('#');
    let h = if h.len() == 8 { &h[2..] } else { h };
    let c = |k: usize| u8::from_str_radix(h.get(k..k + 2).unwrap_or("00"), 16).unwrap_or(0);
    if h.len() >= 6 { [c(0), c(2), c(4)] } else { [255, 0, 0] }
}

/// The figures of an XPS path's abbreviated geometry (M, L, H, V, C, Q, Z; relative too) as
/// polylines; curves are divided into eight segments.
pub fn path_figures(data: &str) -> Vec<Vec<DVec2>> {
    let mut out: Vec<Vec<DVec2>> = Vec::new();
    let mut cur: Vec<DVec2> = Vec::new();
    let mut pos = DVec2::ZERO;
    let mut start = DVec2::ZERO;
    let mut cmd = 'M';
    let toks: Vec<String> = {
        let mut v = Vec::new();
        let mut num = String::new();
        for ch in data.chars() {
            if ch.is_ascii_alphabetic() && ch != 'e' && ch != 'E' {
                if !num.is_empty() {
                    v.push(std::mem::take(&mut num));
                }
                v.push(ch.to_string());
            } else if ch == ',' || ch.is_whitespace() {
                if !num.is_empty() {
                    v.push(std::mem::take(&mut num));
                }
            } else if ch == '-' && !num.is_empty() && !num.ends_with('e') && !num.ends_with('E') {
                v.push(std::mem::take(&mut num));
                num.push(ch);
            } else {
                num.push(ch);
            }
        }
        if !num.is_empty() {
            v.push(num);
        }
        v
    };
    let mut i = 0;
    let num = |i: &mut usize| -> Option<f64> {
        let v = toks.get(*i)?.parse::<f64>().ok()?;
        *i += 1;
        Some(v)
    };
    while i < toks.len() {
        if let Some(c) = toks[i].chars().next().filter(|c| c.is_ascii_alphabetic()) {
            cmd = c;
            i += 1;
            if cmd == 'F' {
                // Fill rule: F0 / F1.
                i += 1;
                continue;
            }
            if cmd == 'Z' || cmd == 'z' {
                if !cur.is_empty() {
                    cur.push(start);
                    out.push(std::mem::take(&mut cur));
                }
                pos = start;
                continue;
            }
        }
        let rel = cmd.is_ascii_lowercase();
        let base = if rel { pos } else { DVec2::ZERO };
        match cmd.to_ascii_uppercase() {
            'M' => {
                let (Some(x), Some(y)) = (num(&mut i), num(&mut i)) else {
                    break;
                };
                if cur.len() > 1 {
                    out.push(std::mem::take(&mut cur));
                }
                cur.clear();
                pos = base + DVec2::new(x, y);
                start = pos;
                cur.push(pos);
                // Further pairs are line segments.
                cmd = if rel { 'l' } else { 'L' };
            }
            'L' => {
                let (Some(x), Some(y)) = (num(&mut i), num(&mut i)) else {
                    break;
                };
                pos = base + DVec2::new(x, y);
                cur.push(pos);
            }
            'H' => {
                let Some(x) = num(&mut i) else { break };
                pos = DVec2::new(if rel { pos.x + x } else { x }, pos.y);
                cur.push(pos);
            }
            'V' => {
                let Some(y) = num(&mut i) else { break };
                pos = DVec2::new(pos.x, if rel { pos.y + y } else { y });
                cur.push(pos);
            }
            'C' => {
                let v: Vec<f64> = (0..6).filter_map(|_| num(&mut i)).collect();
                if v.len() < 6 {
                    break;
                }
                let (a, c1, c2, b) = (pos, base + DVec2::new(v[0], v[1]), base + DVec2::new(v[2], v[3]), base + DVec2::new(v[4], v[5]));
                for k in 1..=8 {
                    let t = k as f64 / 8.0;
                    let u = 1.0 - t;
                    cur.push(a * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + b * (t * t * t));
                }
                pos = b;
            }
            'Q' | 'S' => {
                let v: Vec<f64> = (0..4).filter_map(|_| num(&mut i)).collect();
                if v.len() < 4 {
                    break;
                }
                let (a, c, b) = (pos, base + DVec2::new(v[0], v[1]), base + DVec2::new(v[2], v[3]));
                for k in 1..=8 {
                    let t = k as f64 / 8.0;
                    let u = 1.0 - t;
                    cur.push(a * (u * u) + c * (2.0 * u * t) + b * (t * t));
                }
                pos = b;
            }
            _ => i += 1,
        }
    }
    if cur.len() > 1 {
        out.push(cur);
    }
    out
}

/// The pages of a DWFx (or XPS) package with their markup lines and text.
pub fn read_dwfx(data: &[u8]) -> Result<Vec<MarkupPage>, String> {
    let files = crate::zip::entries(data)?;
    let mut pages = Vec::new();
    for (name, body) in files.iter().filter(|(n, _)| n.to_lowercase().ends_with(".fpage")) {
        let xml = String::from_utf8_lossy(body);
        let mut page = MarkupPage { name: name.rsplit(['/', '\\']).next().unwrap_or(name).trim_end_matches(".fpage").to_string(), ..Default::default() };
        if let Some(fp) = xml.find("<FixedPage") {
            let tag = &xml[fp..xml[fp..].find('>').map(|k| fp + k).unwrap_or(xml.len())];
            page.width = attr(tag, "Width").and_then(|v| v.parse().ok()).unwrap_or(0.0) * MM;
            page.height = attr(tag, "Height").and_then(|v| v.parse().ok()).unwrap_or(0.0) * MM;
        }
        let h = page.height;
        let map = |q: DVec2| DVec2::new(q.x * MM, h - q.y * MM);
        let mut at = 0;
        // Canvases: whether each open one holds the exported sheet itself (left out, so only
        // the markups added to the page come back).
        let mut canvases: Vec<bool> = Vec::new();
        while let Some(k) = xml[at..].find('<') {
            let s = at + k;
            let e = xml[s..].find('>').map(|j| s + j + 1).unwrap_or(xml.len());
            let tag = &xml[s..e];
            if tag.starts_with("<Canvas") && !tag.ends_with("/>") {
                canvases.push(attr(tag, "Name").as_deref() == Some(SHEET_CANVAS));
            } else if tag.starts_with("</Canvas") {
                canvases.pop();
            } else if canvases.iter().any(|c| *c) {
            } else if tag.starts_with("<Path ") {
                if let Some(d) = attr(tag, "Data") {
                    let col = attr(tag, "Stroke").or_else(|| attr(tag, "Fill")).map(|c| color(&c)).unwrap_or([255, 0, 0]);
                    for fig in path_figures(&d) {
                        page.polylines.push((fig.into_iter().map(map).collect(), col));
                    }
                }
            } else if tag.starts_with("<Glyphs ") {
                if let (Some(t), Some(x), Some(y)) = (attr(tag, "UnicodeString"), attr(tag, "OriginX").and_then(|v| v.parse::<f64>().ok()), attr(tag, "OriginY").and_then(|v| v.parse::<f64>().ok())) {
                    let size = attr(tag, "FontRenderingEmSize").and_then(|v| v.parse::<f64>().ok()).unwrap_or(12.0) * MM;
                    let t = t.strip_prefix("{}").map(str::to_string).unwrap_or(t);
                    page.texts.push((map(DVec2::new(x, y)), t, size));
                }
            }
            at = e;
        }
        pages.push(page);
    }
    if pages.is_empty() {
        return Err("The file has no pages (export the sheets as DWFx from File > Export).".into());
    }
    Ok(pages)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xps_paths_become_polylines() {
        let f = path_figures("M 10,10 L 20,10 20,20 Z M0 0 l 5 0 h 5 v 5");
        assert_eq!(f.len(), 2);
        assert_eq!(f[0], vec![DVec2::new(10.0, 10.0), DVec2::new(20.0, 10.0), DVec2::new(20.0, 20.0), DVec2::new(10.0, 10.0)]);
        assert_eq!(f[1].last().copied(), Some(DVec2::new(10.0, 5.0)));
    }
}
