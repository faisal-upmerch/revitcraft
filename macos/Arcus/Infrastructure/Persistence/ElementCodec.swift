import Foundation
import ArcusDomain

/// JSON encoding used for element rows, project values and journal payloads.
///
/// Sorted keys (deterministic bytes for identical values), non-finite doubles as strings
/// (`"+Infinity"`, `"-Infinity"`, `"NaN"`), dates as seconds since 2001-01-01 (Foundation default).
enum StoredJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return d
    }

    /// Returns false when the JSON nests deeper than `limit` (arrays/objects), scanning bytes outside strings.
    static func depthWithinLimit(_ data: Data, limit: Int) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            var depth = 0
            var inString = false
            var escaped = false
            for b in raw {
                if inString {
                    if escaped { escaped = false } else if b == 0x5C { escaped = true } else if b == 0x22 { inString = false }
                    continue
                }
                switch b {
                case 0x22: inString = true
                case 0x5B, 0x7B:
                    depth += 1
                    if depth > limit { return false }
                case 0x5D, 0x7D: depth -= 1
                default: break
                }
            }
            return true
        }
    }

    /// Decodes a value after checking size and nesting.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, limits: PersistenceLimits, maxBytes: Int, what: String) throws -> T {
        guard data.count <= maxBytes else { throw LimitError("\(what) is \(data.count) bytes; the limit is \(maxBytes)") }
        guard depthWithinLimit(data, limit: limits.maxJSONDepth) else { throw LimitError("\(what) nests deeper than \(limits.maxJSONDepth) levels") }
        return try decoder().decode(T.self, from: data)
    }
}

struct LimitError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

/// Parallel element encoding/decoding.
enum ElementCodec {
    /// Encodes elements to JSON blobs (same order). Work is split across cores.
    static func encode(_ elements: [Element]) throws -> [Data] {
        let n = elements.count
        if n == 0 { return [] }
        let chunks = chunking(n)
        let out = UnsafeMutableBufferPointer<Data>.allocate(capacity: n)
        out.initialize(repeating: Data())
        defer { out.deinitialize(); out.deallocate() }
        let errors = UnsafeMutableBufferPointer<(any Error)?>.allocate(capacity: chunks.count)
        errors.initialize(repeating: nil)
        defer { errors.deinitialize(); errors.deallocate() }
        elements.withUnsafeBufferPointer { srcBuf in
            // Each worker writes disjoint indices; buffers outlive concurrentPerform.
            let src = Shared(srcBuf), dst = Shared(out), errs = Shared(errors)
            DispatchQueue.concurrentPerform(iterations: chunks.count) { ci in
                let enc = StoredJSON.encoder()
                for i in chunks[ci] {
                    do { dst.value[i] = try enc.encode(src.value[i]) } catch { errs.value[ci] = error; return }
                }
            }
        }
        if let e = errors.compactMap({ $0 }).first { throw e }
        return Array(out)
    }

    /// Decodes blobs; each slot is either the element or the failure message. Checks size/nesting limits.
    static func decode(_ blobs: [Data], limits: PersistenceLimits) -> [Result<Element, DecodeFailure>] {
        let n = blobs.count
        if n == 0 { return [] }
        let chunks = chunking(n)
        let out = UnsafeMutableBufferPointer<Result<Element, DecodeFailure>>.allocate(capacity: n)
        out.initialize(repeating: .failure(DecodeFailure(message: "not decoded", isLimit: false)))
        defer { out.deinitialize(); out.deallocate() }
        blobs.withUnsafeBufferPointer { srcBuf in
            let src = Shared(srcBuf), dst = Shared(out)
            DispatchQueue.concurrentPerform(iterations: chunks.count) { ci in
                let out = dst.value
                let dec = StoredJSON.decoder()
                for i in chunks[ci] {
                    let blob = src.value[i]
                    if blob.count > limits.maxElementBytes {
                        out[i] = .failure(DecodeFailure(message: "element data is \(blob.count) bytes (limit \(limits.maxElementBytes))", isLimit: true))
                        continue
                    }
                    if !StoredJSON.depthWithinLimit(blob, limit: limits.maxJSONDepth) {
                        out[i] = .failure(DecodeFailure(message: "element data nests deeper than \(limits.maxJSONDepth) levels", isLimit: true))
                        continue
                    }
                    do { out[i] = .success(try dec.decode(Element.self, from: blob)) } catch {
                        out[i] = .failure(DecodeFailure(message: describe(error), isLimit: false))
                    }
                }
            }
        }
        return Array(out)
    }

    /// Wrapper asserting that disjoint-index access from concurrentPerform workers is safe.
    struct Shared<T>: @unchecked Sendable {
        let value: T
        init(_ v: T) { value = v }
    }

    struct DecodeFailure: Error {
        var message: String
        var isLimit: Bool
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c): return "invalid data at \(path(c.codingPath)): \(c.debugDescription)"
        case DecodingError.keyNotFound(let k, let c): return "missing “\(k.stringValue)” at \(path(c.codingPath))"
        case DecodingError.typeMismatch(_, let c): return "wrong value type at \(path(c.codingPath))"
        case DecodingError.valueNotFound(_, let c): return "missing value at \(path(c.codingPath))"
        default: return String(describing: error)
        }
    }
    private static func path(_ p: [any CodingKey]) -> String {
        p.isEmpty ? "root" : p.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }

    private static func chunking(_ n: Int) -> [Range<Int>] {
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, (n + 255) / 256))
        let size = (n + workers - 1) / workers
        return stride(from: 0, to: n, by: size).map { $0..<min(n, $0 + size) }
    }
}

/// Relationship rows derived from element references (table `relations`).
enum RelationRoles {
    static let type = "type", level = "level", host = "host", ownerView = "ownerView"
    static let phaseCreated = "phaseCreated", phaseDemolished = "phaseDemolished"
    static let designOption = "designOption", group = "group", tagTarget = "tagTarget", viewportView = "viewportView"
    static let all = [type, level, host, ownerView, phaseCreated, phaseDemolished, designOption, group, tagTarget, viewportView]

    /// All (role, target) references of an element, including dangling ones.
    static func references(of e: Element) -> [(role: String, target: ElementID)] {
        var out: [(String, ElementID)] = []
        if let v = e.typeID { out.append((type, v)) }
        if let v = e.levelID { out.append((level, v)) }
        if let v = e.hostID { out.append((host, v)) }
        if let v = e.ownerViewID { out.append((ownerView, v)) }
        if let v = e.phaseCreated { out.append((phaseCreated, v)) }
        if let v = e.phaseDemolished { out.append((phaseDemolished, v)) }
        if let v = e.designOptionID { out.append((designOption, v)) }
        if let v = e.groupID { out.append((group, v)) }
        if case .tag(let t) = e.data { out.append((tagTarget, t.taggedID)) }
        if case .viewport(let vp) = e.data { out.append((viewportView, vp.viewID)) }
        return out
    }
}
