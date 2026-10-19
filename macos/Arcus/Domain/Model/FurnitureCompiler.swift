import Foundation
import ArcusGeometry
import ArcusCalc

// FM3: Load into Project for Furniture documents (Docs/FurnitureMode.md §3, "Load into Project and Edit Family").
// The document compiles into an ordinary loadable family: its planes with their formulas, the labelled and EQ
// dimensions, parameters, types and category, plus the geometry FM3 can map (model lines as symbolic plan lines,
// placed components and in-place families as nested families). Later milestones add parts (FM4–FM8). The family keeps
// the whole document (`furnitureSource`), so Edit Family can reopen it in Furniture mode.

/// The serialised Furniture document embedded in a compiled family.
public struct FurnitureSource: Codable, Sendable {
    public var elements: [Element]
    public var nextID: UInt64
    public var referenceDrawings: [String: ReferenceDrawing]
    public var projectParameters: [ParameterDefinition]

    public init(_ m: BIMModel) {
        elements = m.allElements; nextID = m.nextID; referenceDrawings = m.referenceDrawings; projectParameters = m.projectParameters
    }

    public var model: BIMModel {
        BIMModel(elements: elements, nextID: nextID, referenceDrawings: referenceDrawings, projectParameters: projectParameters)
    }

    /// LZFSE-compressed JSON.
    public func encoded() -> Data? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        return try? (json as NSData).compressed(using: .lzfse) as Data
    }

    public static func decode(_ data: Data) -> FurnitureSource? {
        guard let json = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return try? JSONDecoder().decode(FurnitureSource.self, from: json)
    }
}

public enum FurnitureCompiler {
    /// The loadable family a Furniture document compiles to (a generic family for other documents).
    public static func family(from m: BIMModel) -> FamilyDefinition {
        guard let setup = m.furnitureSetup, var f = FurnitureParameters.frame(m, setup: setup)?.family else {
            return FamilyDefinition(name: m.projectInfo.projectName, template: .genericModel)
        }
        f.formatVersion = FamilyDefinition.currentFormatVersion
        f.planLines = symbolicLines(m)
        addComponents(m, to: &f)
        // FM4 parts: each part becomes a FamilySolid bounded by the same planes (FurnitureCompiler+Parts).
        f.furnitureSource = FurnitureSource(m).encoded()
        return f
    }

    /// The Furniture document a compiled family was made from (Edit Family), or nil.
    public static func source(of family: FamilyDefinition) -> BIMModel? {
        family.furnitureSource.flatMap(FurnitureSource.decode)?.model
    }

    /// Model lines as plan symbolic lines (lines on other work planes are drawn as their plan projection).
    static func symbolicLines(_ m: BIMModel) -> [FamilyLine] {
        var out: [FamilyLine] = []
        func n(_ v: Double) -> String { String(v) }
        for e in m.elements(.detailLines) where e.ownerViewID == nil {
            guard let l = e.modelLine else { continue }
            let pts = l.worldPolyline(baseZ: m.elevation(ofLevel: e.levelID)).map(\.xy)
            for (a, b) in zip(pts, pts.dropFirst()) where a.distance(to: b) > Tolerance.shortCurve {
                out.append(FamilyLine(shape: .line(FamilyPoint(n(a.x), n(a.y)), FamilyPoint(n(b.x), n(b.y)))))
            }
        }
        return out
    }

    /// Placed components (hardware, nested furniture, in-place forms) as nested families at their positions.
    static func addComponents(_ m: BIMModel, to f: inout FamilyDefinition) {
        for e in m.elements(.furniture) + m.elements(.casework) + m.elements(.genericModels) + m.elements(.specialtyEquipment) {
            guard let c = e.component, let t = m[e.typeID], let td = t.typeData, let nested = m[td.familyID]?.family, nested.template.is3D else { continue }
            if f.nestedFamily(named: nested.name) == nil {
                var copy = nested
                copy.furnitureSource = nil // a nested piece doesn't carry its own document
                // The project type's values become the nested family's type values (materials stay by id).
                if let i = copy.types.firstIndex(where: { $0.name == t.name }) {
                    for (k, v) in td.params where k.key.hasPrefix(Parameters.familyParamID("").key) {
                        copy.types[i].values[String(k.key.dropFirst(Parameters.familyParamID("").key.count))] = v
                    }
                }
                f.nestedFamilies.append(copy)
            }
            let z = m.baseElevation(of: e)
            var inst = NestedFamilyInstance(familyName: nested.name, typeName: t.name, x: .expr(String(c.location.x)), y: .expr(String(c.location.y)),
                                            z: .expr(String(z)), rotation: String(c.rotation * 180 / .pi), mirrored: c.mirrored)
            inst.visibleAt = [.coarse, .medium, .fine]
            f.nestedInstances.append(inst)
        }
    }
}

/// Loading a Furniture document into a project.
public enum FurnitureLoading {
    /// Loads `family` (compiled from `source`) into the project of `tx`, replacing the family of the same name when
    /// `replacing` is set. Materials the types name are matched by name in the project, or copied in. Returns the
    /// family element.
    @discardableResult
    public static func load(_ family: FamilyDefinition, from source: BIMModel, replacing existing: ElementID?, mode: FamilyReloadMode = .keepProjectValues,
                            in tx: TransactionContext) -> ElementID {
        var f = family
        var mapped: [ElementID: ElementID] = [:]
        func material(_ id: ElementID) -> ElementID? {
            if let hit = mapped[id] { return hit }
            guard let src = source[id], let data = src.material else { return nil }
            let target = tx.model.elements(.materials).first { $0.name == src.name }?.id
                ?? tx.create(.materials, name: src.name, data: .material(data))
            mapped[id] = target
            return target
        }
        for p in f.parameters { guard case .elementRef(.materials) = p.type else { continue }
            for i in f.types.indices {
                if let id = f.types[i].values[p.name]?.refValue { f.types[i].values[p.name] = material(id).map { .ref($0) } }
            }
        }
        return FamilyProjectLoader.load(f, replacing: existing, mode: mode, in: tx)
    }
}
