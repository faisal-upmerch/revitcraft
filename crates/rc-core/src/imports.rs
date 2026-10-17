//! Insert tab readers: gbXML spaces, point clouds (XYZ/PTS text), OBJ meshes (coordination
//! models) and topography points; and an OBJ writer for Twinmotion.

use crate::geom::{DVec2, DVec3};
use crate::mesh::MeshSet;

fn attr(tag: &str, name: &str) -> Option<String> {
    let key = format!("{name}=\"");
    let i = tag.find(&key)? + key.len();
    let j = tag[i..].find('"')? + i;
    Some(tag[i..j].to_string())
}

/// Millimetres per unit for a length unit name (gbXML's lengthUnit, or a guess).
fn unit_mm(name: &str) -> f64 {
    match name.to_lowercase().as_str() {
        "millimeters" => 1.0,
        "centimeters" => 10.0,
        "feet" => 304.8,
        "inches" => 25.4,
        "kilometers" => 1_000_000.0,
        _ => 1000.0,
    }
}

/// A gbXML space: (name, floor outline, bottom z, top z), in millimetres.
pub type GbSpace = (String, Vec<DVec2>, f64, f64);

/// The spaces of a gbXML file, each from its shell's lowest horizontal polyloop and its height.
pub fn read_gbxml(xml: &str) -> Result<Vec<GbSpace>, String> {
    let root = xml.find("<gbXML").ok_or("Not a gbXML file.")?;
    let root_tag = &xml[root..xml[root..].find('>').map(|k| root + k).unwrap_or(xml.len())];
    let k = unit_mm(&attr(root_tag, "lengthUnit").unwrap_or_else(|| "Meters".into()));
    let mut out = Vec::new();
    let mut at = 0;
    while let Some(s) = xml[at..].find("<Space") {
        let s = at + s;
        let e = xml[s..].find("</Space>").map(|j| s + j).unwrap_or(xml.len());
        let body = &xml[s..e];
        at = e.max(s + 6);
        let name = body.find("<Name>").and_then(|i| body[i + 6..].find("</Name>").map(|j| body[i + 6..i + 6 + j].trim().to_string())).or_else(|| attr(body, "id")).unwrap_or_else(|| "Space".into());
        // Polyloops of the shell: lists of points.
        let mut loops: Vec<Vec<DVec3>> = Vec::new();
        let mut lat = 0;
        while let Some(ls) = body[lat..].find("<PolyLoop>") {
            let ls = lat + ls;
            let le = body[ls..].find("</PolyLoop>").map(|j| ls + j).unwrap_or(body.len());
            let lp = &body[ls..le];
            let mut pts = Vec::new();
            let mut pat = 0;
            while let Some(ps) = lp[pat..].find("<CartesianPoint>") {
                let ps = pat + ps;
                let pe = lp[ps..].find("</CartesianPoint>").map(|j| ps + j).unwrap_or(lp.len());
                let vals: Vec<f64> = lp[ps..pe].split("<Coordinate>").skip(1).filter_map(|c| c.split("</Coordinate>").next()?.trim().parse().ok()).collect();
                if vals.len() >= 3 {
                    pts.push(DVec3::new(vals[0] * k, vals[1] * k, vals[2] * k));
                }
                pat = pe.max(ps + 1);
            }
            if pts.len() >= 3 {
                loops.push(pts);
            }
            lat = le.max(ls + 1);
        }
        if loops.is_empty() {
            continue;
        }
        let zmin = loops.iter().flatten().map(|q| q.z).fold(f64::MAX, f64::min);
        let zmax = loops.iter().flatten().map(|q| q.z).fold(f64::MIN, f64::max);
        let floor = loops.iter().find(|l| l.iter().all(|q| (q.z - zmin).abs() < 1.0));
        if let Some(f) = floor {
            out.push((name, f.iter().map(|q| q.truncate()).collect(), zmin, zmax));
        }
    }
    if out.is_empty() {
        return Err("The gbXML file has no spaces with a floor.".into());
    }
    Ok(out)
}

/// Points of an XYZ/PTS/CSV text file: (position in mm, colour). Coordinates in metres unless
/// they are evidently millimetres; a leading count line (PTS) is skipped.
pub fn read_points(text: &str, max: usize) -> Result<Vec<(DVec3, [u8; 3])>, String> {
    let mut raw: Vec<(DVec3, [u8; 3])> = Vec::new();
    for line in text.lines() {
        let v: Vec<f64> = line.split(|c: char| c == ',' || c == ';' || c.is_whitespace()).filter(|s| !s.is_empty()).filter_map(|s| s.parse().ok()).collect();
        if v.len() < 3 {
            continue;
        }
        // x y z [intensity] [r g b]
        let col = if v.len() >= 6 {
            let o = v.len() - 3;
            [v[o] as u8, v[o + 1] as u8, v[o + 2] as u8]
        } else {
            [120, 120, 120]
        };
        raw.push((DVec3::new(v[0], v[1], v[2]), col));
    }
    if raw.len() < 2 {
        return Err("No points were found (expected lines of x y z).".into());
    }
    let span = raw.iter().fold(0.0f64, |m, (q, _)| m.max(q.x.abs()).max(q.y.abs()).max(q.z.abs()));
    let k = if span > 5000.0 { 1.0 } else { 1000.0 };
    // Every n-th point, to at most `max`.
    let step = raw.len().div_ceil(max.max(1)).max(1);
    Ok(raw.into_iter().step_by(step).map(|(q, c)| (q * k, c)).collect())
}

/// Packs points as base64 of deflated (f32 x, y, z, u8 r, g, b) records.
pub fn pack_points(pts: &[(DVec3, [u8; 3])]) -> String {
    use std::io::Write as _;
    let mut raw = Vec::with_capacity(pts.len() * 15);
    for (q, c) in pts {
        for v in [q.x as f32, q.y as f32, q.z as f32] {
            raw.extend_from_slice(&v.to_le_bytes());
        }
        raw.extend_from_slice(c);
    }
    let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    let _ = z.write_all(&raw);
    crate::util::b64_encode(&z.finish().unwrap_or_default())
}

pub fn unpack_points(data: &str) -> Vec<(DVec3, [u8; 3])> {
    use std::io::Read as _;
    let Some(raw) = crate::util::b64_decode(data) else {
        return vec![];
    };
    let mut out = Vec::new();
    if flate2::read::ZlibDecoder::new(&raw[..]).read_to_end(&mut out).is_err() {
        return vec![];
    }
    out.chunks_exact(15)
        .map(|r| {
            let f = |k: usize| f32::from_le_bytes([r[k], r[k + 1], r[k + 2], r[k + 3]]) as f64;
            (DVec3::new(f(0), f(4), f(8)), [r[12], r[13], r[14]])
        })
        .collect()
}

/// An OBJ mesh: positions in mm (metres unless evidently millimetres) and triangles.
pub fn read_obj(text: &str) -> Result<(Vec<DVec3>, Vec<[u32; 3]>), String> {
    let mut v: Vec<DVec3> = Vec::new();
    let mut f: Vec<[u32; 3]> = Vec::new();
    for line in text.lines() {
        let mut it = line.split_whitespace();
        match it.next() {
            Some("v") => {
                let c: Vec<f64> = it.filter_map(|s| s.parse().ok()).collect();
                if c.len() >= 3 {
                    // OBJ is Y-up: turn it Z-up.
                    v.push(DVec3::new(c[0], -c[2], c[1]));
                }
            }
            Some("f") => {
                let idx: Vec<u32> = it.filter_map(|s| s.split('/').next()?.parse::<i64>().ok()).map(|i| if i < 0 { (v.len() as i64 + i) as u32 } else { (i - 1) as u32 }).collect();
                for k in 1..idx.len().saturating_sub(1) {
                    f.push([idx[0], idx[k], idx[k + 1]]);
                }
            }
            _ => {}
        }
    }
    if v.is_empty() || f.is_empty() {
        return Err("The OBJ file has no faces.".into());
    }
    let span = v.iter().fold(0.0f64, |m, q| m.max(q.x.abs()).max(q.y.abs()).max(q.z.abs()));
    let k = if span > 5000.0 { 1.0 } else { 1000.0 };
    f.retain(|t| t.iter().all(|i| (*i as usize) < v.len()));
    Ok((v.into_iter().map(|q| q * k).collect(), f))
}

pub fn pack_mesh(v: &[DVec3], f: &[[u32; 3]]) -> String {
    use std::io::Write as _;
    let mut raw = Vec::new();
    raw.extend_from_slice(&(v.len() as u32).to_le_bytes());
    for q in v {
        for c in [q.x as f32, q.y as f32, q.z as f32] {
            raw.extend_from_slice(&c.to_le_bytes());
        }
    }
    for t in f {
        for i in t {
            raw.extend_from_slice(&i.to_le_bytes());
        }
    }
    let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    let _ = z.write_all(&raw);
    crate::util::b64_encode(&z.finish().unwrap_or_default())
}

pub fn unpack_mesh(data: &str) -> (Vec<DVec3>, Vec<[u32; 3]>) {
    use std::io::Read as _;
    let Some(raw) = crate::util::b64_decode(data) else {
        return (vec![], vec![]);
    };
    let mut b = Vec::new();
    if flate2::read::ZlibDecoder::new(&raw[..]).read_to_end(&mut b).is_err() || b.len() < 4 {
        return (vec![], vec![]);
    }
    let n = u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize;
    let f32_at = |k: usize| f32::from_le_bytes([b[k], b[k + 1], b[k + 2], b[k + 3]]) as f64;
    let mut v = Vec::with_capacity(n);
    for k in 0..n {
        let o = 4 + k * 12;
        if o + 12 > b.len() {
            break;
        }
        v.push(DVec3::new(f32_at(o), f32_at(o + 4), f32_at(o + 8)));
    }
    let mut f = Vec::new();
    let mut o = 4 + n * 12;
    while o + 12 <= b.len() {
        let u = |k: usize| u32::from_le_bytes([b[k], b[k + 1], b[k + 2], b[k + 3]]);
        f.push([u(o), u(o + 4), u(o + 8)]);
        o += 12;
    }
    (v, f)
}

/// The model's meshes as an OBJ file (metres, Y up) with one group per element and a
/// material library, for Twinmotion and other visualisation apps.
pub fn write_obj(p: &crate::model::Project, meshes: &[(crate::model::Id, MeshSet)], mtl_name: &str) -> (String, String) {
    let mut obj = format!("# RevitCraft export\nmtllib {mtl_name}\n");
    let mut mtl = String::new();
    let mut mats: Vec<String> = Vec::new();
    let mut base = 1usize;
    for (id, set) in meshes {
        obj.push_str(&format!("g element_{id}\n"));
        for (mat, m) in &set.by_material {
            let safe: String = mat.chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect();
            let safe = if safe.is_empty() { "Default".to_string() } else { safe };
            if !mats.contains(&safe) {
                let c = p.material(mat).map(|m| m.color).unwrap_or([200, 200, 200]);
                mtl.push_str(&format!("newmtl {safe}\nKd {:.3} {:.3} {:.3}\n\n", c[0] as f64 / 255.0, c[1] as f64 / 255.0, c[2] as f64 / 255.0));
                mats.push(safe.clone());
            }
            obj.push_str(&format!("usemtl {safe}\n"));
            for q in &m.positions {
                obj.push_str(&format!("v {:.4} {:.4} {:.4}\n", q.x / 1000.0, q.z / 1000.0, -q.y / 1000.0));
            }
            for t in m.indices.chunks(3) {
                obj.push_str(&format!("f {} {} {}\n", base + t[0] as usize, base + t[1] as usize, base + t[2] as usize));
            }
            base += m.positions.len();
        }
    }
    (obj, mtl)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gbxml_spaces_points_and_obj_round_trip() {
        let xml = r#"<gbXML lengthUnit="Meters"><Campus><Building><Space id="sp1"><Name>Office</Name><ShellGeometry><ClosedShell>
            <PolyLoop><CartesianPoint><Coordinate>0</Coordinate><Coordinate>0</Coordinate><Coordinate>0</Coordinate></CartesianPoint>
            <CartesianPoint><Coordinate>4</Coordinate><Coordinate>0</Coordinate><Coordinate>0</Coordinate></CartesianPoint>
            <CartesianPoint><Coordinate>4</Coordinate><Coordinate>3</Coordinate><Coordinate>0</Coordinate></CartesianPoint></PolyLoop>
            <PolyLoop><CartesianPoint><Coordinate>0</Coordinate><Coordinate>0</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint>
            <CartesianPoint><Coordinate>4</Coordinate><Coordinate>0</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint>
            <CartesianPoint><Coordinate>4</Coordinate><Coordinate>3</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint></PolyLoop>
            </ClosedShell></ShellGeometry></Space></Building></Campus></gbXML>"#;
        let s = read_gbxml(xml).unwrap();
        assert_eq!(s[0].0, "Office");
        assert!((s[0].3 - 2700.0).abs() < 1e-6 && s[0].1.len() == 3);
        let pts = read_points("3\n1 2 3\n4 5 6 255 0 0\n7 8 9\n", 2).unwrap();
        assert_eq!(pts.len(), 2);
        assert_eq!(unpack_points(&pack_points(&pts)).len(), 2);
        let (v, f) = read_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 2 3 4\n").unwrap();
        assert_eq!((v.len(), f.len()), (4, 2));
        let (v2, f2) = unpack_mesh(&pack_mesh(&v, &f));
        assert_eq!((v2.len(), f2.len()), (4, 2));
    }
}
