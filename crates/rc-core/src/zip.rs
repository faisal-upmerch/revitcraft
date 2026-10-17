//! A minimal ZIP reader (stored and deflated entries), for DWFx packages.

use std::io::Read;

fn u16_at(b: &[u8], i: usize) -> Option<u16> {
    Some(u16::from_le_bytes([*b.get(i)?, *b.get(i + 1)?]))
}

fn u32_at(b: &[u8], i: usize) -> Option<u32> {
    Some(u32::from_le_bytes([*b.get(i)?, *b.get(i + 1)?, *b.get(i + 2)?, *b.get(i + 3)?]))
}

/// The entries of a ZIP archive: (name, contents).
pub fn entries(data: &[u8]) -> Result<Vec<(String, Vec<u8>)>, String> {
    // The end of central directory record, searched from the end.
    let eocd = (0..data.len().saturating_sub(21)).rev().find(|&i| u32_at(data, i) == Some(0x0605_4b50)).ok_or("Not a ZIP package.")?;
    let count = u16_at(data, eocd + 10).ok_or("Damaged ZIP package.")? as usize;
    let mut at = u32_at(data, eocd + 16).ok_or("Damaged ZIP package.")? as usize;
    let mut out = Vec::new();
    for _ in 0..count {
        if u32_at(data, at) != Some(0x0201_4b50) {
            return Err("Damaged ZIP directory.".into());
        }
        let method = u16_at(data, at + 10).unwrap_or(0);
        let csize = u32_at(data, at + 20).unwrap_or(0) as usize;
        let nlen = u16_at(data, at + 28).unwrap_or(0) as usize;
        let xlen = u16_at(data, at + 30).unwrap_or(0) as usize;
        let clen = u16_at(data, at + 32).unwrap_or(0) as usize;
        let local = u32_at(data, at + 42).unwrap_or(0) as usize;
        let name = String::from_utf8_lossy(data.get(at + 46..at + 46 + nlen).unwrap_or(&[])).to_string();
        at += 46 + nlen + xlen + clen;
        // The local header's own name and extra lengths lead to the data.
        let lnlen = u16_at(data, local + 26).unwrap_or(0) as usize;
        let lxlen = u16_at(data, local + 28).unwrap_or(0) as usize;
        let start = local + 30 + lnlen + lxlen;
        let Some(raw) = data.get(start..start + csize) else {
            continue;
        };
        let body = match method {
            0 => raw.to_vec(),
            8 => {
                let mut v = Vec::new();
                flate2::read::DeflateDecoder::new(raw).read_to_end(&mut v).map_err(|e| e.to_string())?;
                v
            }
            _ => continue,
        };
        out.push((name, body));
    }
    Ok(out)
}

/// A ZIP archive of `files` (deflated), as DWFx and other OPC packages are written.
pub fn write(files: &[(String, Vec<u8>)]) -> Vec<u8> {
    use std::io::Write;
    let mut out: Vec<u8> = Vec::new();
    let mut central: Vec<u8> = Vec::new();
    let le16 = |v: &mut Vec<u8>, x: u16| v.extend_from_slice(&x.to_le_bytes());
    let le32 = |v: &mut Vec<u8>, x: u32| v.extend_from_slice(&x.to_le_bytes());
    for (name, data) in files {
        let mut crc = flate2::Crc::new();
        crc.update(data);
        let mut enc = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
        let _ = enc.write_all(data);
        let packed = enc.finish().unwrap_or_default();
        let (method, body) = if packed.len() < data.len() { (8u16, packed) } else { (0u16, data.clone()) };
        let offset = out.len() as u32;
        // Local header.
        le32(&mut out, 0x0403_4b50);
        le16(&mut out, 20);
        le16(&mut out, 0);
        le16(&mut out, method);
        le16(&mut out, 0);
        le16(&mut out, 0x21);
        le32(&mut out, crc.sum());
        le32(&mut out, body.len() as u32);
        le32(&mut out, data.len() as u32);
        le16(&mut out, name.len() as u16);
        le16(&mut out, 0);
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(&body);
        // Central directory entry.
        le32(&mut central, 0x0201_4b50);
        le16(&mut central, 20);
        le16(&mut central, 20);
        le16(&mut central, 0);
        le16(&mut central, method);
        le16(&mut central, 0);
        le16(&mut central, 0x21);
        le32(&mut central, crc.sum());
        le32(&mut central, body.len() as u32);
        le32(&mut central, data.len() as u32);
        le16(&mut central, name.len() as u16);
        le16(&mut central, 0);
        le16(&mut central, 0);
        le16(&mut central, 0);
        le16(&mut central, 0);
        le32(&mut central, 0);
        le32(&mut central, offset);
        central.extend_from_slice(name.as_bytes());
    }
    let start = out.len() as u32;
    let size = central.len() as u32;
    out.extend_from_slice(&central);
    le32(&mut out, 0x0605_4b50);
    le16(&mut out, 0);
    le16(&mut out, 0);
    le16(&mut out, files.len() as u16);
    le16(&mut out, files.len() as u16);
    le32(&mut out, size);
    le32(&mut out, start);
    le16(&mut out, 0);
    out
}

#[cfg(test)]
mod tests {
    #[test]
    fn written_archives_read_back() {
        let files = vec![("a.txt".to_string(), b"hello hello hello hello".to_vec()), ("dir/b.bin".to_string(), vec![1, 2, 3])];
        assert_eq!(super::entries(&super::write(&files)).unwrap(), files);
    }
}
