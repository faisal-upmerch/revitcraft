import Foundation
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence
@testable import ArcusServices

@Suite("Performance", .serialized)
struct PerformanceTests {
    static func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18 }

    @Test func twentyThousandElementModel() throws {
        let tmp = TempDir()
        let clock = ContinuousClock()
        var model: BIMModel!
        let build = try clock.measure { model = try Sample.largeModel(walls: 20_000) }
        #expect(model.count >= 20_000)
        let url = tmp.file("Big.arcus")
        let write = try clock.measure { try ArcusPackage.write(model, to: url, info: Sample.info) }
        var read: BIMModel!
        let readTime = try clock.measure { read = try ArcusPackage.read(from: url).model }
        let verifyTime = clock.measure { #expect(ArcusPackage.verify(url).isHealthy) }
        Sample.expectEqual(model, read)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.appending(path: "model.sqlite").path)[.size] as? Int) ?? 0
        let report = String(format: "PERF %d elements: build %.2fs, write %.3fs, read %.3fs, verify %.3fs, model.sqlite %.1f MB",
                            model.count, Self.seconds(build), Self.seconds(write), Self.seconds(readTime), Self.seconds(verifyTime), Double(size) / 1_048_576)
        print(report)
        DiagnosticsLog.shared.recordTiming("package write 20k", seconds: Self.seconds(write))
        // Loose bounds (debug builds); release targets are < 2 s each.
        #expect(write < .seconds(20))
        #expect(readTime < .seconds(20))
    }

    @Test func jsonVersusBinaryPlistElementEncoding() throws {
        let model = try Sample.largeModel(walls: 5_000)
        let elements = model.allElements
        let clock = ContinuousClock()
        var jsonBytes = 0, plistBytes = 0
        let json = try clock.measure { jsonBytes = try ElementCodec.encode(elements).reduce(0) { $0 + $1.count } }
        let plist = try clock.measure {
            let enc = PropertyListEncoder()
            enc.outputFormat = .binary
            for e in elements { plistBytes += try enc.encode(e).count }
        }
        let jsonSerial = try clock.measure {
            let enc = JSONEncoder()
            enc.outputFormatting = .sortedKeys
            for e in elements { _ = try enc.encode(e) }
        }
        print(String(format: "PERF encode %d elements: JSON parallel %.3fs (%.1f MB), JSON serial %.3fs, binary plist serial %.3fs (%.1f MB)",
                     elements.count, Self.seconds(json), Double(jsonBytes) / 1_048_576, Self.seconds(jsonSerial), Self.seconds(plist), Double(plistBytes) / 1_048_576))
        #expect(jsonBytes > 0 && plistBytes > 0)
    }

    @Test func journalAppendThroughput() async throws {
        let tmp = TempDir()
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .metric)
        var model = m0
        let journal = RecoveryJournal(baseDirectory: tmp.url.appending(path: "R"), log: DiagnosticsLog(), syncInterval: .seconds(1))
        let id = UUID()
        try await journal.begin(documentID: id, displayName: "Perf", savedURL: nil, baseModel: model, info: Sample.info)
        var records: [TransactionRecord] = []
        for i in 0..<1_000 {
            let tx = TransactionContext(model: model, name: "e\(i)")
            tx.update(ids.levels[0]) { $0.name = "Perf Level \(i)" }
            let r = try tx.commit()
            model = r.model
            records.append(r.record)
        }
        let clock = ContinuousClock()
        let t = try await clock.measure { for r in records { try await journal.append(r, documentID: id) } }
        try await journal.flush(documentID: id)
        print(String(format: "PERF journal: %d appends in %.3fs (%.1f µs each)", records.count, Self.seconds(t), Self.seconds(t) / Double(records.count) * 1e6))
        #expect(t < .seconds(10))
        try await journal.end(documentID: id)
    }
}
