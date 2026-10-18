import Foundation
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Family packages")
struct FamilyPackageTests {
    @Test func familyRoundTrip() throws {
        let tmp = TempDir()
        let fam = StarterLibrary.singleDoor()
        let url = tmp.file("Door.arcusfamily")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
        try FamilyPackage.write(fam, thumbnailPNG: png, to: url, appVersion: "1.0.0", build: "7")
        let (read, thumb, manifest) = try FamilyPackage.read(from: url)
        #expect(read == fam)
        #expect(thumb == png)
        #expect(manifest.format == "com.local.arcus.family")
        #expect(manifest.writerAppVersion == "1.0.0")
        #expect(manifest.elementCount == fam.types.count)
        #expect(manifest.checksums["family.json"]?.count == 64)
    }

    @Test func rewritingKeepsIdentity() throws {
        let tmp = TempDir()
        let url = tmp.file("F.arcusfamily")
        var fam = StarterLibrary.singleDoor()
        try FamilyPackage.write(fam, thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
        let first = try FamilyPackage.readManifest(url)
        fam.description = "Changed"
        try FamilyPackage.write(fam, thumbnailPNG: nil, to: url, appVersion: "1", build: "2")
        let (read, thumb, second) = try FamilyPackage.read(from: url)
        #expect(read.description == "Changed")
        #expect(thumb == nil)
        #expect(second.documentID == first.documentID)
        #expect(second.created == first.created)
        #expect(second.writerBuild == "2")
    }

    @Test func damagedFamilyIsDetected() throws {
        let tmp = TempDir()
        let url = tmp.file("F.arcusfamily")
        try FamilyPackage.write(StarterLibrary.singleDoor(), thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
        var d = try Data(contentsOf: url.appending(path: "family.json"))
        d[d.count / 2] ^= 0x20
        try d.write(to: url.appending(path: "family.json"))
        #expect { try FamilyPackage.read(from: url) } throws: { e in
            guard let e = e as? PersistenceError, case .checksumMismatch("family.json") = e.kind else { return false }
            return true
        }
        // A project package is not a family.
        let proj = tmp.file("P.arcus")
        try ArcusPackage.write(BIMModel(), to: proj, info: Sample.info)
        #expect { try FamilyPackage.read(from: proj) } throws: { e in (e as? PersistenceError)?.kind == .notAPackage }
    }

    @Test func newerFamilyFormatIsRefused() throws {
        let tmp = TempDir()
        let url = tmp.file("F.arcusfamily")
        try FamilyPackage.write(StarterLibrary.singleDoor(), thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
        let mURL = url.appending(path: "manifest.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: mURL)) as! [String: Any]
        obj["minimumReaderVersion"] = 5
        obj["writerAppVersion"] = "3.0"
        try JSONSerialization.data(withJSONObject: obj).write(to: mURL)
        #expect { try FamilyPackage.read(from: url) } throws: { e in
            (e as? PersistenceError)?.kind == .newerFormat(requiredReader: 5, writtenBy: "3.0")
        }
    }
}

@Suite("Type catalogs")
struct TypeCatalogTests {
    /// Family with parameters of several kinds.
    static func family() -> FamilyDefinition {
        var f = StarterLibrary.singleDoor()
        f.parameters += [
            FamilyParameter(name: "Fire Rating", type: .text, group: .identity),
            FamilyParameter(name: "Glazed", type: .bool),
            FamilyParameter(name: "Leaves", type: .integer),
            FamilyParameter(name: "Swing", type: .angle),
            FamilyParameter(name: "Finish", type: .choice(["Paint", "Stain"])),
            FamilyParameter(name: "Clear Area", type: .area),
            FamilyParameter(name: "Label", type: .text, isInstance: true),
        ]
        return f
    }

    @Test func parsesMillimetresMetresAndFeet() throws {
        let csv = #"""
        Type Name,Width [length:mm],Height [length:m],Frame Width [length:ft],Frame Depth [length:in],Fire Rating [text],Glazed [bool]
        810 x 2040,810,2.04,0.25,6,FD30,no
        "Wide, Double",1600.5,2.1,0.5,4.5,"FD60 ""S""",Yes
        """#
        let (types, errors) = try TypeCatalog.parse(Data(csv.utf8), family: Self.family())
        #expect(errors == [])
        #expect(types.map(\.name) == ["810 x 2040", "Wide, Double"])
        let a = types[0].values, b = types[1].values
        #expect(a["Width"] == .double(0.81))
        #expect(a["Height"] == .double(2.04))
        #expect(abs((a["Frame Width"]?.doubleValue ?? 0) - 0.0762) < 1e-12)
        #expect(abs((a["Frame Depth"]?.doubleValue ?? 0) - 0.1524) < 1e-12)
        #expect(a["Fire Rating"] == .text("FD30"))
        #expect(a["Glazed"] == .bool(false))
        #expect(b["Width"] == .double(1.6005))
        #expect(b["Fire Rating"] == .text("FD60 \"S\""))
        #expect(b["Glazed"] == .bool(true))
    }

    @Test func reportsRowErrorsWithRowNumbers() throws {
        let csv = #"""
        Type Name,Width [length:mm],Leaves [integer],Finish [text],Height [length:m]
        Good,900,1,Paint,2.1
        Bad Number,9O0,1,Paint,2.1
        Bad Int,900,1.5,Stain,2.1

        ,900,1,Paint,2.1
        Good,900,2,Paint,2.1
        Bad Choice,900,1,Varnish,2.1
        Negative,-5,1,Paint,2.1
        Trailing,1000,,,
        """#
        let (types, errors) = try TypeCatalog.parse(Data(csv.utf8), family: Self.family())
        #expect(types.map(\.name) == ["Good", "Trailing"])
        #expect(types[1].values == ["Width": .double(1.0)])
        #expect(errors.contains { $0.hasPrefix("Row 3:") && $0.contains("9O0") })
        #expect(errors.contains { $0.hasPrefix("Row 4:") && $0.contains("whole number") })
        #expect(errors.contains { $0.hasPrefix("Row 6:") && $0.contains("type name is empty") })
        #expect(errors.contains { $0.hasPrefix("Row 7:") && $0.contains("duplicate") })
        #expect(errors.contains { $0.hasPrefix("Row 8:") && $0.contains("Varnish") })
        #expect(errors.contains { $0.hasPrefix("Row 9:") && $0.contains("negative") })
    }

    @Test func headerErrorsSkipColumns() throws {
        let csv = #"""
        Type Name,Width [length:furlongs],Nope [text],Height [area:m2],Rough Width [length:mm],Label [text],Frame Width,Swing [angle:deg],Width [length:mm],Clear Area [area:ft2]
        T1,1,x,2,3,lbl,50,90,700,10
        """#
        let (types, errors) = try TypeCatalog.parse(Data(csv.utf8), family: Self.family())
        #expect(errors.contains { $0.contains("column 2") && $0.contains("furlongs") })
        #expect(errors.contains { $0.contains("column 3") && $0.contains("not a parameter") })
        #expect(errors.contains { $0.contains("column 4") && $0.contains("declared as area") })
        #expect(errors.contains { $0.contains("column 5") && $0.contains("formula") })
        #expect(errors.allSatisfy { $0.hasPrefix("Row 1:") })
        let v = types[0].values
        #expect(v["Width"] == .double(0.7))                         // later valid column wins
        #expect(v["Frame Width"] == .double(0.05))                 // bare header → parameter type, default mm
        #expect(abs((v["Swing"]?.doubleValue ?? 0) - Double.pi / 2) < 1e-12)
        #expect(abs((v["Clear Area"]?.doubleValue ?? 0) - 0.9290304) < 1e-9)
        #expect(v["Label"] == .text("lbl"))                        // instance parameters may be given too
    }

    @Test func wholeFileProblemsThrow() {
        let fam = Self.family()
        #expect(throws: TypeCatalog.CatalogError.self) { try TypeCatalog.parse(Data(), family: fam) }
        #expect(throws: TypeCatalog.CatalogError.self) { try TypeCatalog.parse(Data([0xFF, 0xFE, 0x00, 0xD8]), family: fam) }
        #expect(throws: TypeCatalog.CatalogError.self) { try TypeCatalog.parse(Data("Width,Height\n1,2".utf8), family: fam) }
        #expect(throws: TypeCatalog.CatalogError.self) { try TypeCatalog.parse(Data("Type Name,Width\n\"unterminated,1".utf8), family: fam) }
    }

    @Test func toleratesBOMAndCRLFAndEmptyFirstHeader() throws {
        let csv = "\u{FEFF},Width [length:cm]\r\nA,90\r\nB,82.5\r\n"
        let (types, errors) = try TypeCatalog.parse(Data(csv.utf8), family: Self.family())
        #expect(errors.isEmpty)
        #expect(types.map(\.name) == ["A", "B"])
        #expect(types[0].values["Width"] == .double(0.9))
        #expect(types[1].values["Width"] == .double(0.825))
    }

    @Test func exportThenParseRoundTrips() throws {
        var fam = Self.family()
        fam.types[0].values["Fire Rating"] = .text("FD30, \"smoke\"")
        fam.types[0].values["Glazed"] = .bool(true)
        fam.types[0].values["Leaves"] = .int(2)
        fam.types[0].values["Swing"] = .double(Double.pi / 2)
        fam.types[1].values["Finish"] = .text("Stain")
        let csv = TypeCatalog.export(fam)
        let text = String(decoding: csv, as: UTF8.self)
        #expect(text.hasPrefix("Type Name,Width [length:mm],Height [length:mm],Frame Width [length:mm]"))
        #expect(!text.contains("Rough Width"))       // formula parameters are not exported
        #expect(!text.contains("Frame Material"))    // element references can't be expressed
        #expect(!text.contains("Label"))             // instance parameters are not type data
        #expect(text.contains("900"))
        let (types, errors) = try TypeCatalog.parse(csv, family: fam)
        #expect(errors == [])
        #expect(types.map(\.name) == fam.types.map(\.name))
        for (a, b) in zip(types, fam.types) {
            for (k, v) in b.values {
                if let x = v.doubleValue, case .double = v {
                    #expect(abs((a.values[k]?.doubleValue ?? .nan) - x) < 1e-9, "\(b.name).\(k)")
                } else {
                    #expect(a.values[k] == v, "\(b.name).\(k)")
                }
            }
        }
        // Metric lengths come back bit-identical.
        #expect(types[0].values["Width"] == fam.types[0].values["Width"])
        #expect(types[2].values["Panel Thickness"] == fam.types[2].values["Panel Thickness"])
    }

    @Test func numberFormatting() {
        #expect(TypeCatalog.formatNumber(900) == "900")
        #expect(TypeCatalog.formatNumber(0.1 + 0.2) == "0.3")
        #expect(TypeCatalog.formatNumber(-0.0) == "0")
        #expect(TypeCatalog.formatNumber(1e-12) == "0")
        #expect(TypeCatalog.parseNumber("1e3") == 1000)
        #expect(TypeCatalog.parseNumber("1,000") == nil)
        #expect(TypeCatalog.parseNumber("nan") == nil)
        #expect(TypeCatalog.parseNumber("inf") == nil)
    }
}
