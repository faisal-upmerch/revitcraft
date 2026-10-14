//! Minimal PNG encoder (8-bit RGB/RGBA) used for image exports and screenshots.

use flate2::Compression;
use flate2::write::ZlibEncoder;
use std::io::Write;

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let mut c = kind.to_vec();
    c.extend_from_slice(data);
    out.extend_from_slice(&c);
    out.extend_from_slice(&crc32(&c).to_be_bytes());
}

/// Encodes pixels (rows top to bottom) with 3 (RGB) or 4 (RGBA) channels.
pub fn encode(width: u32, height: u32, channels: u8, pixels: &[u8]) -> Vec<u8> {
    assert!(channels == 3 || channels == 4);
    assert_eq!(pixels.len(), (width * height * channels as u32) as usize);
    let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.extend_from_slice(&[8, if channels == 4 { 6 } else { 2 }, 0, 0, 0]);
    chunk(&mut out, b"IHDR", &ihdr);
    let stride = (width * channels as u32) as usize;
    let mut raw = Vec::with_capacity((stride + 1) * height as usize);
    for row in pixels.chunks(stride) {
        raw.push(0); // no filter
        raw.extend_from_slice(row);
    }
    let mut z = ZlibEncoder::new(Vec::new(), Compression::fast());
    z.write_all(&raw).expect("in-memory write");
    chunk(&mut out, b"IDAT", &z.finish().expect("in-memory write"));
    chunk(&mut out, b"IEND", &[]);
    out
}

#[cfg(test)]
mod tests {
    #[test]
    fn crc_matches_reference() {
        assert_eq!(super::crc32(b"IEND"), 0xAE42_6082);
    }
}
