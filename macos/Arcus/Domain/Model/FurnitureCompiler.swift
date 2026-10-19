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
        addParts(m, to: &f) // FM4: each part becomes family solids bounded by the same planes (FurnitureCompiler+Parts)
        addFronts(m, to: &f) // FM5: fronts as solids on the bays' planes, hardware as nested families, swing lines (FurnitureCompiler+Fronts)
        addPlanRepresentation(to: &f) // FM8: Coarse outline, Medium/Fine edges seen from above (FurnitureCompiler+FM8)
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
        // FM8: nested families (hardware, legs, edge profiles) too, so their materials are the project's.
        func mapMaterials(_ fam: inout FamilyDefinition) {
            for p in fam.parameters { guard case .elementRef(.materials) = p.type else { continue }
                for i in fam.types.indices {
                    if let id = fam.types[i].values[p.name]?.refValue { fam.types[i].values[p.name] = material(id).map { .ref($0) } }
                }
            }
            for i in fam.nestedFamilies.indices { mapMaterials(&fam.nestedFamilies[i]) }
        }
        mapMaterials(&f)
        let fid = FamilyProjectLoader.load(f, replacing: existing, mode: mode, in: tx)
        setIdentity(FurnitureCostEstimate.costs(byType: source), f, family: fid, mode: mode, in: tx) // FM8
        return fid
    }

    /// FM8: the project types' Identity Data from the piece: Cost from its estimate, Description and Manufacturer from
    /// Family Category and Parameters. New types and Overwrite (with parameter values) take them; types that keep their
    /// values keep what is already set in the project.
    static func setIdentity(_ costs: [String: Double], _ f: FamilyDefinition, family fid: ElementID, mode: FamilyReloadMode, in tx: TransactionContext) {
        let cost = ParameterID("type.cost")
        let text: [(ParameterID, String)] = [(ParameterID("type.description"), f.description), (ParameterID("type.manufacturer"), f.manufacturer)]
        for t in tx.model.elements(.elementTypes) where t.typeData?.familyID == fid {
            let keep = mode == .keepProjectValues
            _ = tx.update(t.id) { e in
                if let c = costs[t.name], c > 0, !(keep && (e.typeData?.params[cost]?.doubleValue ?? 0) > 0) { e.typeData?.params[cost] = .double(c) }
                for (k, v) in text where !v.isEmpty && !(keep && !(e.typeData?.params[k]?.textValue ?? "").isEmpty) { e.typeData?.params[k] = .text(v) }
            }
        }
    }
}
