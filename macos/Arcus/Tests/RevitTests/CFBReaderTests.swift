import Foundation
import Testing
@testable import ArcusRevit

@Suite("Compound file reader")
struct CFBReaderTests {
    static func sample(_ version: Int, padding: Int = 0) -> (Data, CFBWriter.Layout, [String: Data]) {
        var w = CFBWriter()
        w.majorVersion = version
        w.paddingSectors = padding
        let small = Data((0..<100).map { UInt8($0) })
        let exact = Data(repeating: 7, count: 64)
        let big = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 * 31) })
        let nested = Data(repeating: 9, count: 4096)
        w.nodes = [
            .stream("Small", small),
            .stream("Exact64", exact),
            .stream("Empty", Data()),
            .stream("Big", big),
            .storage("Folder", [.stream("Nested", nested), .storage("Deeper", [.stream("Leaf", Data("leaf".utf8))])]),
        ]
        let (d, l) = w.build()
        return (d, l, ["Small": small, "Exact64": exact, "Empty": Data(), "Big": big, "Folder/Nested": nested, "Folder/Deeper/Leaf": Data("leaf".utf8)])
    }

    static func patch32(_ d: inout Data, _ o: Int, _ v: UInt32) { for k in 0..<4 { d[o + k] = UInt8((v >> (8 * UInt32(k))) & 0xff) } }
    static func patch64(_ d: inout Data, _ o: Int, _ v: UInt64) { for k in 0..<8 { d[o + k] = UInt8((v >> (8 * UInt64(k))) & 0xff) } }

    @Test(arguments: [3, 4])
    func readsValidFile(version: Int) throws {
        let (data, _, expected) = Self.sample(version)
        let cfb = try CompoundFile(data: data)
        #expect(cfb.majorVersion == version)
        #expect(cfb.sectorSize == (version == 4 ? 4096 : 512))
        #expect(Set(cfb.streamPaths) == Set(expected.keys))
        #expect(cfb.entries.contains { $0.path == "Folder" && $0.kind == .storage })
        #expect(cfb.entries.contains { $0.path == "Folder/Deeper" && $0.kind == .storage })
        for (path, bytes) in expected {
            #expect(try cfb.read(path: path) == bytes, "stream \(path)")
        }
        // Paths compare case-insensitively like CFB names.
        #expect(try cfb.read(path: "folder/deeper/LEAF") == Data("leaf".utf8))
    }

    @Test func miniStreamAndRegularStreamsAreDistinguished() throws {
        let (data, layout, _) = Self.sample(3)
        #expect(layout.isMini["Small"] == true)
        #expect(layout.isMini["Big"] == false)
        #expect(layout.isMini["Folder/Nested"] == false) // exactly 4096 bytes is a regular stream
        let cfb = try CompoundFile(data: data)
        #expect(cfb.entry(atPath: "Small")?.size == 100)
    }

    @Test func readsFileWithDIFATSectors() throws {
        // > 109 allocation sectors forces the DIFAT chain (v3: 128 entries per FAT sector).
        let (data, layout, expected) = Self.sample(3, padding: 110 * 128)
        #expect(layout.difatSectors.count >= 1)
        let cfb = try CompoundFile(data: data)
        #expect(try cfb.read(path: "Big") == expected["Big"])
    }

    @Test func rejectsNonCompoundData() {
        #expect(throws: CompoundFileError.self) { try CompoundFile(data: Data()) }
        do {
            _ = try CompoundFile(data: Data(repeating: 0x41, count: 4096))
            Issue.record("expected an error")
        } catch { #expect(error.kind == .notCompoundFile) }
    }

    @Test func rejectsUnsupportedVersionAndBadHeader() throws {
        var (data, _, _) = Self.sample(3)
        data[26] = 5
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .unsupportedVersion) }
        (data, _, _) = Self.sample(3)
        data[28] = 0x00 // byte order mark
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .malformed) }
        (data, _, _) = Self.sample(3)
        Self.patch32(&data, 44, 0x7FFF_FFFF) // absurd FAT sector count
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .malformed) }
    }

    @Test func detectsCycleInStreamChain() throws {
        var (data, layout, _) = Self.sample(3)
        let start = layout.streamStart["Big"]!
        Self.patch32(&data, layout.fatEntryOffset(start + 1), UInt32(start)) // second sector points back to the first
        let cfb = try CompoundFile(data: data)
        do { _ = try cfb.read(path: "Big"); Issue.record("expected an error") } catch { #expect(error.kind == .cycle) }
        // Other streams are still readable.
        #expect(try cfb.read(path: "Small").count == 100)
    }

    @Test func detectsCycleInMiniChain() throws {
        var (data, layout, _) = Self.sample(3)
        let m = layout.streamStart["Small"]! // 100 bytes = 2 mini sectors
        Self.patch32(&data, layout.miniFATEntryOffset(m), UInt32(m)) // first mini sector points to itself
        let cfb = try CompoundFile(data: data)
        do { _ = try cfb.read(path: "Small"); Issue.record("expected an error") } catch { #expect(error.kind == .cycle) }
    }

    @Test func detectsCycleInDirectoryTree() throws {
        var (data, layout, _) = Self.sample(3)
        let i = layout.entryIndex["Small"]!
        Self.patch32(&data, layout.dirEntryOffset(i) + 72, UInt32(i)) // right sibling = itself
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .cycle) }
        // Child pointing back to the root.
        (data, layout, _) = Self.sample(3)
        let f = layout.entryIndex["Folder/Deeper"]!
        Self.patch32(&data, layout.dirEntryOffset(f) + 76, 0)
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .cycle) }
    }

    @Test func rejectsOutOfRangeDirectoryReference() throws {
        var (data, layout, _) = Self.sample(3)
        Self.patch32(&data, layout.dirEntryOffset(layout.entryIndex["Small"]!) + 72, 50_000)
        do { _ = try CompoundFile(data: data); Issue.record("expected an error") } catch { #expect(error.kind == .malformed) }
    }

    @Test(arguments: [3, 4])
    func hugeClaimedSizesAreLimited(version: Int) throws {
        var (data, layout, _) = Self.sample(version)
        // Claim a 1 TB stream (v4 keeps the high bits; v3 masks them, leaving a size the chain cannot back).
        Self.patch64(&data, layout.dirEntryOffset(layout.entryIndex["Big"]!) + 120, 1 << 40 | 20_000)
        let cfb = try CompoundFile(data: data)
        do { _ = try cfb.read(path: "Big"); Issue.record("expected an error") } catch {
            #expect(version == 4 ? error.kind == .limitExceeded : (error.kind == .truncated || error.kind == .malformed))
        }
        // An explicit cap is honored even for a genuine stream.
        do { _ = try cfb.read(path: "Folder/Nested", maxBytes: 100); Issue.record("expected an error") } catch { #expect(error.kind == .limitExceeded) }
    }

    @Test func truncatedFilesFailCleanly() throws {
        let (data, _, _) = Self.sample(3)
        for cut in [511, 512, 600, 1024, data.count / 2, data.count - 1] {
            let d = data.prefix(cut)
            do {
                let cfb = try CompoundFile(data: Data(d))
                for s in cfb.streams { _ = try? cfb.read(s) }
            } catch {
                #expect([.notCompoundFile, .truncated, .malformed].contains(error.kind), "cut at \(cut): \(error)")
            }
        }
    }

    @Test func fileSizeLimit() throws {
        let (data, _, _) = Self.sample(3)
        var limits = CompoundFileLimits()
        limits.maxFileSize = 1024
        do { _ = try CompoundFile(data: data, limits: limits); Issue.record("expected an error") } catch { #expect(error.kind == .limitExceeded) }
    }

    /// Random corruption must never crash or hang; every outcome is a value or a CompoundFileError.
    @Test func fuzzedFilesNeverCrash() throws {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for version in [3, 4] {
            let (base, _, _) = Self.sample(version)
            for _ in 0..<300 {
                var d = base
                let flips = Int.random(in: 1...12, using: &rng)
                for _ in 0..<flips {
                    let o = Int.random(in: 0..<min(d.count, version == 4 ? 16384 : 4096), using: &rng)
                    d[o] = UInt8.random(in: 0...255, using: &rng)
                }
                if let cfb = try? CompoundFile(data: d) {
                    for s in cfb.streams { _ = try? cfb.read(s, maxBytes: 1 << 20) }
                }
            }
        }
    }
}
