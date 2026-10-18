import Foundation
import Testing
@testable import ArcusIFC

@Suite("STEP parser")
struct STEPParserTests {
    static func wrap(_ data: String, schema: String = "IFC4") -> Data {
        Data("""
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');
        FILE_NAME('t.ifc','2026-01-01T00:00:00',('A'),('B'),'pre','orig','auth');
        FILE_SCHEMA(('\(schema)'));
        ENDSEC;
        DATA;
        \(data)
        ENDSEC;
        END-ISO-10303-21;

        """.utf8)
    }

    @Test func parsesHeader() throws {
        let f = try STEPParser.parse(Self.wrap("#1=IFCWALL('x');"))
        #expect(f.header.schemas == ["IFC4"])
        #expect(f.header.description == ["ViewDefinition [ReferenceView_V1.2]"])
        #expect(f.header.implementationLevel == "2;1")
        #expect(f.header.name == "t.ifc")
        #expect(f.header.author == ["A"])
        #expect(f.header.organization == ["B"])
        #expect(f.header.originatingSystem == "orig")
        #expect(f.count == 1)
    }

    @Test func parsesValueKinds() throws {
        let f = try STEPParser.parse(Self.wrap("#10=IFCTHING($,*,12,-3.5,1.5E-3,2.E+2,'s',.T.,.NOTDEFINED.,#7,(1,(2,3)),IFCLABEL('lab'),\"0FF\",());"))
        let e = try #require(f[10])
        #expect(e.type == "IFCTHING")
        #expect(e[0] == .null)
        #expect(e[1] == .derived)
        #expect(e[2] == .integer(12))
        #expect(e[3] == .real(-3.5))
        #expect(e[4] == .real(0.0015))
        #expect(e[5] == .real(200))
        #expect(e[6] == .string("s"))
        #expect(e[7].boolValue == true)
        #expect(e[8] == .enumeration("NOTDEFINED"))
        #expect(e[9] == .ref(7))
        #expect(e[10] == .list([.integer(1), .list([.integer(2), .integer(3)])]))
        #expect(e[11] == .typed("IFCLABEL", [.string("lab")]))
        #expect(e[11].stringValue == "lab")
        #expect(e[12] == .binary("0FF"))
        #expect(e[13] == .list([]))
        #expect(e[99] == .null) // out of range tolerated
    }

    @Test func decodesStringEscapes() throws {
        let f = try STEPParser.parse(Self.wrap(#"#1=X('It''s','a\\b','\X2\00E400FC\X0\','\X\E9t\X\E9','\S\d','\X4\0001F600\X0\','\X2\D83DDE00\X0\','\PA\ok');"#))
        let e = try #require(f[1])
        #expect(e[0].stringValue == "It's")
        #expect(e[1].stringValue == "a\\b")
        #expect(e[2].stringValue == "äü")
        #expect(e[3].stringValue == "été")
        #expect(e[4].stringValue == "ä")
        #expect(e[5].stringValue == "😀")
        #expect(e[6].stringValue == "😀")
        #expect(e[7].stringValue == "ok")
    }

    @Test func rawUTF8AndLatin1BytesAreAccepted() throws {
        var d = Self.wrap("#1=X('UTFMARK','LATMARK');")
        d = Data(String(decoding: d, as: UTF8.self).replacingOccurrences(of: "UTFMARK", with: "Größe").utf8)
        var bytes = [UInt8](d)
        let mark = Array("LATMARK".utf8)
        if let r = bytes.indices.first(where: { Array(bytes[$0..<min(bytes.count, $0 + mark.count)]) == mark }) {
            bytes.replaceSubrange(r..<(r + mark.count), with: [0x63, 0x61, 0x66, 0xE9]) // "café" in Latin-1
        }
        let f = try STEPParser.parse(Data(bytes))
        #expect(f[1]?[0].stringValue == "Größe")
        #expect(f[1]?[1].stringValue == "café")
    }

    @Test func encodeDecodeRoundTrip() throws {
        let samples = ["plain", "quote ' inside", "back\\slash", "Büro – Küche", "日本語", "emoji 😀 mix", "\u{7F}", ""]
        for s in samples {
            let encoded = STEPFormat.string(s)
            #expect(encoded.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F }, "not 7-bit: \(encoded)")
            let f = try STEPParser.parse(Self.wrap("#1=X(\(encoded));"))
            #expect(f[1]?[0].stringValue == s)
        }
    }

    @Test func commentsAndMultilineRecords() throws {
        let f = try STEPParser.parse(Self.wrap("""
        /* leading comment
           spanning lines */
        #1 = IFCCARTESIANPOINT(
            (1.,
             /* inline */ 2.,
             3.)
        ) ;
        #2=IFCDIRECTION((0.,0.,1.));
        """))
        #expect(f[1]?[0].listValue?.compactMap(\.doubleValue) == [1, 2, 3])
        #expect(f[2]?.type == "IFCDIRECTION")
        #expect(f.order == [1, 2])
    }

    @Test func realFormattingAlwaysHasDecimalPoint() {
        #expect(STEPFormat.real(3) == "3.")
        #expect(STEPFormat.real(-0.5) == "-0.5")
        #expect(STEPFormat.real(0) == "0.")
        #expect(STEPFormat.real(-1e-12) == "0.")
        #expect(STEPFormat.real(1.5e-7) == "1.5E-07")
        #expect(STEPFormat.real(2.5e13) == "2.5E+13")
        #expect(STEPFormat.real(1.0 / 3.0) == "0.333333333")
    }

    @Test func truncatedFileThrowsWithLine() throws {
        let d = try TestModel.fixture("truncated.ifc")
        do {
            _ = try STEPParser.parse(d)
            Issue.record("expected error")
        } catch let e as IFCError {
            #expect(e.line != nil)
            #expect(e.message.contains("end of file") || e.message.contains("Unterminated"))
        }
    }

    @Test func malformedFileReportsLine() throws {
        let d = try TestModel.fixture("malformed.ifc")
        do {
            _ = try STEPParser.parse(d)
            Issue.record("expected error")
        } catch let e as IFCError {
            #expect(e.line == 11)
        }
    }

    @Test func rejectsGarbageAndEdgeCases() {
        let cases: [String] = [
            "",
            "hello world",
            "ISO-10303-21;\nHEADER;\nENDSEC;\nEND-ISO-10303-21;",
            String(decoding: Self.wrap("#1=X('unterminated);"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(1);\n#1=X(2);"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(#99999999999999999999999);"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(1) /* unterminated comment"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(.BAD);"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(\"XYZ\");"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X('\\X2\\00E\\X0\\');"), as: UTF8.self),
            String(decoding: Self.wrap("#1=X(1.E);"), as: UTF8.self),
        ]
        for c in cases {
            #expect(throws: IFCError.self, "should reject: \(c.prefix(60))") { try STEPParser.parse(Data(c.utf8)) }
        }
    }

    @Test func nestingLimitIsEnforced() {
        let deep = String(repeating: "(", count: 5000) + String(repeating: ")", count: 5000)
        #expect(throws: IFCError.self) { try STEPParser.parse(Self.wrap("#1=X(\(deep));")) }
        var limits = STEPParser.Limits()
        limits.maxNesting = 3
        #expect(throws: IFCError.self) { try STEPParser.parse(Self.wrap("#1=X((((1))));"), limits: limits) }
        #expect(throws: Never.self) { try STEPParser.parse(Self.wrap("#1=X(((1)));"), limits: limits) }
    }

    @Test func entityAndStringLimitsAreEnforced() {
        var limits = STEPParser.Limits()
        limits.maxEntities = 3
        #expect(throws: IFCError.self) { try STEPParser.parse(Self.wrap("#1=X();#2=X();#3=X();#4=X();"), limits: limits) }
        limits = STEPParser.Limits()
        limits.maxStringBytes = 10
        #expect(throws: IFCError.self) { try STEPParser.parse(Self.wrap("#1=X('\(String(repeating: "a", count: 50))');"), limits: limits) }
        limits = STEPParser.Limits()
        limits.maxFileBytes = 100
        #expect(throws: IFCError.self) { try STEPParser.parse(Self.wrap("#1=X();"), limits: limits) }
    }

    @Test func complexInstanceKeepsFirstRecord() throws {
        let f = try STEPParser.parse(Self.wrap("#5=(IFCNAMEDUNIT(*,.LENGTHUNIT.) IFCSIUNIT($,.METRE.));"))
        #expect(f[5]?.type == "IFCNAMEDUNIT")
    }

    @Test func largeFileParsesInLinearTime() throws {
        func make(_ n: Int) -> Data {
            var s = ""
            s.reserveCapacity(n * 60)
            for i in 1...n { s += "#\(i)=IFCCARTESIANPOINT((\(i).5,\(i % 97).25,1.E-3));\n" }
            return Self.wrap(s)
        }
        let small = make(20_000), large = make(160_000)
        let t0 = Date()
        let f1 = try STEPParser.parse(small)
        let t1 = Date()
        let f2 = try STEPParser.parse(large)
        let t2 = Date()
        #expect(f1.count == 20_000)
        #expect(f2.count == 160_000)
        #expect(f2[160_000]?[0].listValue?.first?.doubleValue == 160_000.5)
        // 8x the data must not take dramatically more than 8x the time (quadratic would be 64x).
        let r = t2.timeIntervalSince(t1) / max(t1.timeIntervalSince(t0), 0.001)
        #expect(r < 24, "ratio \(r)")
    }

    @Test func cancellationStopsParsing() {
        var s = ""
        for i in 1...200_000 { s += "#\(i)=X(\(i));\n" }
        let d = Self.wrap(s)
        #expect(throws: IFCError.self) { try STEPParser.parse(d, isCancelled: { true }) }
    }
}
