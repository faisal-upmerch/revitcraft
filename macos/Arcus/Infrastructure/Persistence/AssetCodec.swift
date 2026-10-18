import Foundation
import Compression

/// Compressed asset container used for everything under `assets/`.
///
/// Layout (little-endian):
/// ```
/// 0   4  magic "PLZ1"
/// 4   1  algorithm: 1 = LZFSE, 2 = zlib (raw DEFLATE, as produced by Compression's COMPRESSION_ZLIB)
/// 5   3  reserved (0)
/// 8   8  uncompressed byte count (UInt64)
/// 16  …  compressed stream
/// ```
/// Decoding is bounded: the declared size must be within `maxAssetBytes`, the declared/compressed ratio within
/// `maxCompressionRatio`, and the stream is aborted as soon as it produces more bytes than declared.
enum AssetCodec {
    enum Algorithm: UInt8 {
        case lzfse = 1, zlib = 2
        var raw: compression_algorithm { self == .lzfse ? COMPRESSION_LZFSE : COMPRESSION_ZLIB }
        var fileExtension: String { self == .lzfse ? "lzfse" : "zlib" }
    }
    static let magic: [UInt8] = Array("PLZ1".utf8)
    static let headerSize = 16

    enum DecodeError: Error, CustomStringConvertible {
        case malformed(String)
        case limit(String)
        var description: String {
            switch self {
            case .malformed(let s), .limit(let s): s
            }
        }
    }

    static func encode(_ payload: Data, algorithm: Algorithm = .lzfse) throws -> Data {
        var out = Data(magic)
        out.append(algorithm.rawValue)
        out.append(contentsOf: [0, 0, 0])
        var n = UInt64(payload.count).littleEndian
        withUnsafeBytes(of: &n) { out.append(contentsOf: $0) }
        let compressed = try stream(payload, operation: COMPRESSION_STREAM_ENCODE, algorithm: algorithm.raw, outputLimit: Int.max)
        out.append(compressed)
        return out
    }

    static func decode(_ data: Data, limits: PersistenceLimits) throws -> Data {
        guard data.count >= headerSize else { throw DecodeError.malformed("asset header is truncated") }
        let bytes = [UInt8](data.prefix(headerSize))
        guard Array(bytes[0..<4]) == magic else { throw DecodeError.malformed("asset has an unknown container format") }
        guard let alg = Algorithm(rawValue: bytes[4]) else { throw DecodeError.malformed("asset uses an unknown compression algorithm \(bytes[4])") }
        var declared: UInt64 = 0
        for i in 0..<8 { declared |= UInt64(bytes[8 + i]) << (8 * UInt64(i)) }
        guard declared <= UInt64(limits.maxAssetBytes) else {
            throw DecodeError.limit("an asset declares \(declared) bytes; the limit is \(limits.maxAssetBytes)")
        }
        let compressedCount = data.count - headerSize
        let ratioLimit = UInt64(max(1, compressedCount)) * UInt64(limits.maxCompressionRatio)
        guard declared <= max(ratioLimit, 4096) else {
            throw DecodeError.limit("an asset’s compression ratio exceeds \(limits.maxCompressionRatio):1")
        }
        let body = data.subdata(in: (data.startIndex + headerSize)..<data.endIndex)
        let out = try stream(body, operation: COMPRESSION_STREAM_DECODE, algorithm: alg.raw, outputLimit: Int(declared))
        guard out.count == Int(declared) else {
            throw DecodeError.malformed("asset decompressed to \(out.count) bytes but declared \(declared)")
        }
        return out
    }

    /// Streaming (de)compression with a hard output cap. Exceeding the cap throws `.limit`.
    private static func stream(_ input: Data, operation: compression_stream_operation, algorithm: compression_algorithm, outputLimit: Int) throws -> Data {
        var s = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                   src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&s, operation, algorithm) == COMPRESSION_STATUS_OK else {
            throw DecodeError.malformed("compression stream could not be initialised")
        }
        defer { compression_stream_destroy(&s) }
        let chunk = 1 << 16
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        var output = Data()
        if outputLimit != Int.max { output.reserveCapacity(min(outputLimit, 64 << 20)) }
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: UInt8.self)
            s.src_ptr = src.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!
            s.src_size = src.count
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                s.dst_ptr = dst
                s.dst_size = chunk
                let status = compression_stream_process(&s, flags)
                let produced = chunk - s.dst_size
                if produced > 0 {
                    if output.count + produced > outputLimit {
                        throw DecodeError.limit("an asset decompresses to more data than it declares (possible decompression bomb)")
                    }
                    output.append(dst, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_OK:
                    if produced == 0 && s.src_size == 0 {
                        throw DecodeError.malformed("compressed stream ended unexpectedly")
                    }
                    continue
                case COMPRESSION_STATUS_END:
                    return
                default:
                    throw DecodeError.malformed("compressed stream is damaged")
                }
            }
        }
        return output
    }
}
