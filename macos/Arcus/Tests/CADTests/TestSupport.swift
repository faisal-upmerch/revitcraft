import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

enum Fx {
    static var root: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)! }
    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
    static func doc(_ name: String, options: CADReadOptions = .init()) throws -> CADDocument {
        try DXFReader.read(try data(name), fileName: name, options: options)
    }

    /// Copies fixtures into a fresh temporary folder (for tests that modify files).
    static func tempCopy(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-cad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in names {
            let dst = dir.appendingPathComponent(n)
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url(n), to: dst)
        }
        return dir
    }
}

extension CADDocument {
    func entities(_ type: String, in list: [CADEntity]? = nil) -> [CADEntity] {
        (list ?? modelSpace).filter { $0.typeName == type }
    }
    func entity(handle: String) -> CADEntity? {
        modelSpace.first { $0.props.handle == handle }
    }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol * max(1, abs(a), abs(b)) }
func approx(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-9) -> Bool { approx(a.x, b.x, tol) && approx(a.y, b.y, tol) }

/// Minimal ASCII DXF builder for in-test documents.
struct DXFText {
    var lines: [String] = []
    mutating func g(_ code: Int, _ v: Any) { lines.append(String(code)); lines.append("\(v)") }
    mutating func seq(_ pairs: [(Int, Any)]) { for (c, v) in pairs { g(c, v) } }
    var data: Data { Data((lines.joined(separator: "\n") + "\n").utf8) }
    static func minimal(version: String = "AC1015", units: Int = 4, entities: (inout DXFText) -> Void) -> DXFText {
        var d = DXFText()
        d.seq([(0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, version), (9, "$INSUNITS"), (70, units), (0, "ENDSEC")])
        d.seq([(0, "SECTION"), (2, "ENTITIES")])
        entities(&d)
        d.seq([(0, "ENDSEC"), (0, "EOF")])
        return d
    }
}

func templateModel() -> (BIMModel, ProjectTemplates.Ids) {
    ProjectTemplates.make(.architectural, units: .metric)
}
