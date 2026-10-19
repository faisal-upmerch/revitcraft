import Foundation
import ArcusGeometry

// FMG2: the Properties rows this batch adds, read and written through Parameters (instanceEntries / set): joints in
// parts' and joints' Properties (FurnitureJointProperties) and Explode Parts in Furniture 3D views (Graphics).

enum FMG2Properties {
    static func adjust(_ entries: [ParameterEntry], _ e: Element, _ m: BIMModel) -> [ParameterEntry] {
        FurnitureJointProperties.adjust(entries, e, m) + explodeEntries(e, m)
    }

    static func set(_ id: ParameterID, to value: ParamValue, on elementID: ElementID, in tx: TransactionContext) throws(ParameterError) -> Bool {
        if try FurnitureJointProperties.set(id, to: value, on: elementID, in: tx) { return true }
        return try setExplode(id, value, elementID, tx)
    }

    // MARK: Explode Parts

    static func explodeEntries(_ e: Element, _ m: BIMModel) -> [ParameterEntry] {
        guard m.isFurniture, e.view?.kind == .threeD else { return [] }
        let on = FurnitureExplode.isExploded(e)
        let off = on ? nil : "Turn on Explode Parts first."
        return [
            ParameterEntry(id: FurnitureExplode.onParam, name: "Explode Parts", type: .bool, group: .graphics, isType: false, isReadOnly: false, value: .bool(on),
                           formula: nil, tooltip: "Draws the parts moved apart along their joints, with their tags (shop drawing F104).", readOnlyReason: nil),
            ParameterEntry(id: FurnitureExplode.distanceParam, name: "Explode Distance", type: .length, group: .graphics, isType: false, isReadOnly: !on,
                           value: .double(FurnitureExplode.distance(e)), formula: nil, tooltip: "How far each part moves from the parts it joins.", readOnlyReason: off),
            ParameterEntry(id: FurnitureExplode.tagsParam, name: "Tag Parts", type: .bool, group: .graphics, isType: false, isReadOnly: !on,
                           value: .bool(FurnitureExplode.showsTags(e)), formula: nil, tooltip: "Shows each part's Mark in the exploded view.", readOnlyReason: off),
        ]
    }

    static func setExplode(_ id: ParameterID, _ value: ParamValue, _ viewID: ElementID, _ tx: TransactionContext) throws(ParameterError) -> Bool {
        guard [FurnitureExplode.onParam, FurnitureExplode.distanceParam, FurnitureExplode.tagsParam].contains(id), let v = tx.model[viewID] else { return false }
        var on = FurnitureExplode.isExploded(v), distance: Double?, tags: Bool?
        switch id {
        case FurnitureExplode.onParam:
            guard let b = value.boolValue else { throw ParameterError("“Explode Parts” needs Yes or No.") }
            on = b
        case FurnitureExplode.distanceParam:
            guard let d = value.doubleValue else { throw ParameterError("“Explode Distance” needs a length.") }
            distance = d
        default:
            guard let b = value.boolValue else { throw ParameterError("“Tag Parts” needs Yes or No.") }
            tags = b
        }
        do { try FurnitureExplode.set(viewID, on: on, distance: distance, tags: tags, in: tx) } catch { throw ParameterError(error.message) }
        return true
    }
}
