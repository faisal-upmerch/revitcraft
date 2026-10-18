import Foundation
import Testing
import ArcusDomain
@testable import ArcusIFC

/// Byte-for-byte regression goldens for both schemas.
///
/// When an export change is intentional, regenerate with:
///   ARCUS_REGENERATE_IFC_GOLDENS=1 swift test --filter GoldenTests
/// then review the diff of `Fixtures/golden-*.ifc` before committing.
@Suite("IFC goldens")
struct GoldenTests {
    static var regenerate: Bool { ProcessInfo.processInfo.environment["ARCUS_REGENERATE_IFC_GOLDENS"] == "1" }

    static func goldenName(_ schema: IFCSchema) -> String { "golden-\(schema.rawValue.lowercased()).ifc" }

    /// Writes the golden into the source tree (only when regeneration is requested).
    static func writeGolden(_ data: Data, schema: IFCSchema) throws {
        let url = TestModel.sourceFixturesDir().appendingPathComponent(goldenName(schema))
        try data.write(to: url, options: .atomic)
    }

    @Test(arguments: IFCSchema.allCases)
    func exportMatchesGolden(_ schema: IFCSchema) throws {
        let b = try TestModel.build()
        let (data, _) = try TestModel.export(b.model, TestModel.options(schema))
        if Self.regenerate {
            try Self.writeGolden(data, schema: schema)
            return
        }
        let golden = try TestModel.fixture(Self.goldenName(schema))
        if golden != data {
            let a = TestModel.text(golden).split(separator: "\n", omittingEmptySubsequences: false)
            let c = TestModel.text(data).split(separator: "\n", omittingEmptySubsequences: false)
            let i = zip(a, c).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(a.count, c.count)
            let expected = i < a.count ? String(a[i].prefix(300)) : "<end of file>"
            let actual = i < c.count ? String(c[i].prefix(300)) : "<end of file>"
            Issue.record("""
            \(Self.goldenName(schema)) differs at line \(i + 1) (golden \(a.count) lines, actual \(c.count) lines).
              golden: \(expected)
              actual: \(actual)
            If the change is intentional, run ARCUS_REGENERATE_IFC_GOLDENS=1 swift test --filter GoldenTests and review the diff.
            """)
        }
    }

    @Test(arguments: IFCSchema.allCases)
    func goldenParsesAndImports(_ schema: IFCSchema) throws {
        guard !Self.regenerate else { return }
        let golden = try TestModel.fixture(Self.goldenName(schema))
        let f = try STEPParser.parse(golden)
        #expect(f.header.schemas == [schema.rawValue])
        let (_, r, _) = try TestModel.importIntoTemplate(golden)
        #expect(r.nativeCounts["walls"] == 4)
    }
}
