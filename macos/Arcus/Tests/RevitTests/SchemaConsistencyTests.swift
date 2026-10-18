import Foundation
import Testing
@testable import ArcusRevit

/// Keeps the Swift schema, the JSON Schema used by the Revit add-in and the fixtures in step.
@Suite("Exchange schema consistency")
struct SchemaConsistencyTests {
    static func repoRoot() -> URL {
        // <root>/Arcus/Tests/RevitTests/<this file>
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func schema() throws -> [String: Any] {
        let url = repoRoot().appendingPathComponent("Tools/RevitBridge/arcus-exchange.schema.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func properties(_ s: [String: Any]) -> Set<String> { Set((s["properties"] as? [String: Any])?.keys.map { $0 } ?? []) }

    /// Stored property names of a struct decoded from `{}` (all exchange properties are optional).
    static func keys<T: Decodable>(_ t: T.Type) throws -> Set<String> {
        let v = try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        return Set(Mirror(reflecting: v).children.compactMap(\.label))
    }

    @Test func rootPropertiesMatchSwift() throws {
        let s = try Self.schema()
        var doc = ExchangeDocument()
        doc.generator = XGenerator(); doc.source = XSource(); doc.units = XUnits(); doc.projectInfo = XProjectInfo()
        let encoded = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(doc)) as? [String: Any]
        #expect(Set(encoded?.keys.map { $0 } ?? []) == Self.properties(s))
        #expect((s["properties"] as? [String: Any])?["format"] as? [String: String] == ["const": ExchangeFormat.identifier])
    }

    @Test func definitionsMatchSwiftTypes() throws {
        let defs = try #require(try Self.schema()["$defs"] as? [String: [String: Any]])
        func check<T: Decodable>(_ name: String, _ t: T.Type) throws {
            let def = try #require(defs[name], "missing $defs/\(name)")
            #expect(Self.properties(def) == (try Self.keys(t)), "$defs/\(name) vs \(T.self)")
        }
        try check("curve", XCurve.self)
        try check("transform", XTransform.self)
        try check("mesh", XMesh.self)
        try check("generator", XGenerator.self)
        try check("source", XSource.self)
        try check("units", XUnits.self)
        try check("projectInfo", XProjectInfo.self)
        try check("material", XMaterial.self)
        try check("level", XLevel.self)
        try check("grid", XGrid.self)
        try check("layer", XLayer.self)
        try check("section", XSection.self)
        try check("stairTypeInfo", XStairTypeInfo.self)
        try check("railingTypeInfo", XRailingTypeInfo.self)
        try check("type", XType.self)
        try check("familyParameter", XFamilyParameter.self)
        try check("familyType", XFamilyType.self)
        try check("referencePlane", XReferencePlane.self)
        try check("familyDimension", XFamilyDimension.self)
        try check("profileCurve", XProfileCurve.self)
        try check("familyGeometry", XFamilyGeometry.self)
        try check("familyLine", XFamilyLine.self)
        try check("opening", XOpening.self)
        try check("family", XFamily.self)
        try check("wall", XWall.self)
        try check("slopeArrow", XSlopeArrow.self)
        try check("slab", XSlab.self)
        try check("roof", XRoof.self)
        try check("insert", XInsert.self)
        try check("room", XRoom.self)
        try check("column", XColumn.self)
        try check("beam", XBeam.self)
        try check("stair", XStair.self)
        try check("railing", XRailing.self)
        try check("component", XComponent.self)
        try check("meshElement", XMeshElement.self)
    }

    /// Every key used in the fixtures is declared in the JSON Schema (apart from deliberate forward-compatibility probes).
    @Test(arguments: ["small-project.arcusx", "parametric-door.arcusx"])
    func fixturesUseDeclaredKeys(name: String) throws {
        let schema = try Self.schema()
        let defs = try #require(schema["$defs"] as? [String: [String: Any]])
        let fixture = try JSONSerialization.jsonObject(with: try Fixture.data(name))
        var problems: [String] = []
        func resolve(_ s: [String: Any]) -> [String: Any] {
            if let ref = s["$ref"] as? String, ref.hasPrefix("#/$defs/"), let d = defs[String(ref.dropFirst(8))] { return resolve(d) }
            return s
        }
        func walk(_ value: Any, _ s0: [String: Any], _ path: String) {
            let s = resolve(s0)
            if let obj = value as? [String: Any] {
                if let props = s["properties"] as? [String: [String: Any]] {
                    for (k, v) in obj {
                        if let ps = props[k] { walk(v, ps, path + "." + k) } else if k != "someFutureField" { problems.append(path + "." + k) }
                    }
                } else if let ap = s["additionalProperties"] as? [String: Any] {
                    for (k, v) in obj { walk(v, ap, path + "." + k) }
                }
            } else if let arr = value as? [Any], let items = s["items"] as? [String: Any] {
                for (i, v) in arr.enumerated() { walk(v, items, "\(path)[\(i)]") }
            }
        }
        walk(fixture, schema, "$")
        #expect(problems.isEmpty, "undeclared keys: \(problems)")
    }
}
