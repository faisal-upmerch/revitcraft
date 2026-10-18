import Foundation
import Compression

// F13: a minimal ZIP writer and reader for OPC packages (DWFx), as RevitCraft's rc-core zip.rs. Entries are
// deflated with Apple's Compression framework (raw DEFLATE), with CRC-32 checksums; all local, no external tools.

public enum ZipArchive {
    /// A ZIP archive of `files` (name, contents), deflated when that makes the entry smaller, stored otherwise.
    public static func write(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in files {
            let crc = crc32(data)
            let packed = deflate(data)
            let useDeflate = packed.map { $0.count < data.count } ?? false
            let body = useDeflate ? packed! : data
            let nameBytes = Data(name.utf8)
            let offset = UInt32(out.count)
            // Local file header.
            out.le32(0x0403_4b50); out.le16(20); out.le16(0x0800); out.le16(useDeflate ? 8 : 0); out.le16(0); out.le16(0x21)
            out.le32(crc); out.le32(UInt32(body.count)); out.le32(UInt32(data.count)); out.le16(UInt16(nameBytes.count)); out.le16(0)
            out.append(nameBytes); out.append(body)
            // Central directory entry.
            central.le32(0x0201_4b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(useDeflate ? 8 : 0)
            central.le16(0); central.le16(0x21); central.le32(crc); central.le32(UInt32(body.count)); central.le32(UInt32(data.count))
            central.le16(UInt16(nameBytes.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0); central.le32(0)
            central.le32(offset); central.append(nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4b50); out.le16(0); out.le16(0); out.le16(UInt16(files.count)); out.le16(UInt16(files.count))
        out.le32(UInt32(central.count)); out.le32(cdOffset); out.le16(0)
        return out
    }

    /// The entries of a ZIP archive (stored and deflated), or nil when it isn't one.
    public static func entries(_ data: Data) -> [(name: String, data: Data)]? {
        let b = [UInt8](data)
        func u16(_ i: Int) -> Int? { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : nil }
        func u32(_ i: Int) -> Int? { i + 3 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 : nil }
        guard b.count >= 22, let eocd = (0...(b.count - 22)).reversed().first(where: { u32($0) == 0x0605_4b50 }),
              let count = u16(eocd + 10), var at = u32(eocd + 16) else { return nil }
        var out: [(String, Data)] = []
        for _ in 0..<count {
            guard u32(at) == 0x0201_4b50, let method = u16(at + 10), let csize = u32(at + 20), let usize = u32(at + 24),
                  let nlen = u16(at + 28), let xlen = u16(at + 30), let clen = u16(at + 32), let local = u32(at + 42),
                  at + 46 + nlen <= b.count else { return nil }
            let name = String(decoding: b[(at + 46)..<(at + 46 + nlen)], as: UTF8.self)
            at += 46 + nlen + xlen + clen
            guard let lnlen = u16(local + 26), let lxlen = u16(local + 28) else { return nil }
            let start = local + 30 + lnlen + lxlen
            guard start + csize <= b.count else { return nil }
            let raw = Data(b[start..<(start + csize)])
            switch method {
            case 0: out.append((name, raw))
            case 8: if let d = inflate(raw, size: usize) { out.append((name, d)) }
            default: continue
            }
        }
        return out
    }

    // MARK: Codecs

    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + data.count / 10 + 64
        var dst = [UInt8](repeating: 0, count: capacity)
        let n = data.withUnsafeBytes { src in
            compression_encode_buffer(&dst, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(dst[0..<n]) : nil
    }

    static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var dst = [UInt8](repeating: 0, count: size)
        let n = data.withUnsafeBytes { src in
            compression_decode_buffer(&dst, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return n == size ? Data(dst) : nil
    }

    static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xFF)) } }
}
