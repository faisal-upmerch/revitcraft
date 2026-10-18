import Foundation
import ArcusGeometry

/// F67: Properties of linked models, point clouds, DWF markups and decals.
enum F67Parameters {
    typealias P = BuiltInParameter

    static let source = P("f67.source", "Source File", .text, .identity, get: { e, _ in e.f67LinkSource.map { .text($0.path) } })
    static let format = P("f67.format", "Format", .text, .identity, get: { e, _ in
        switch e.data {
        case .linkedModel(let l): .text(l.format == .arcus ? "Arcus Project" : l.format.rawValue)
        case .pointCloud: .text("Point Cloud")
        case .markup: .text("DWFx")
        default: nil
        }
    })
    static let loaded = P("f67.loaded", "Loaded", .bool, .identity, get: { e, _ in
        switch e.data {
        case .linkedModel(let l): .bool(l.isLoaded)
        case .pointCloud(let p): .bool(p.isLoaded)
        case .markup(let m): .bool(m.isLoaded)
        default: nil
        }
    }, set: { e, v, _ in
        guard let b = v.boolValue else { throw ParameterError("“Loaded” is yes or no.") }
        switch e.data {
        case .linkedModel(var l): l.isLoaded = b; e.data = .linkedModel(l)
        case .pointCloud(var p): p.isLoaded = b; e.data = .pointCloud(p)
        case .markup(var m): m.isLoaded = b; e.data = .markup(m)
        default: break
        }
    })
    static let count = P("f67.count", "Count", .integer, .identity, tooltip: "Elements read from a linked model; points kept from a point cloud.", get: { e, _ in
        switch e.data {
        case .linkedModel(let l): .int(l.elementCount)
        case .pointCloud(let p): .int(p.points.count)
        default: nil
        }
    })
    static let offset = P("f67.elevationOffset", "Offset", .length, .constraints, tooltip: "Raises the link above its internal-origin position.", get: { e, _ in
        switch e.data {
        case .linkedModel(let l): .double(l.elevationOffset)
        case .pointCloud(let p): .double(p.elevationOffset)
        default: nil
        }
    }, set: { e, v, _ in
        guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“Offset” needs a length.") }
        switch e.data {
        case .linkedModel(var l): l.elevationOffset = d; e.data = .linkedModel(l)
        case .pointCloud(var p): p.elevationOffset = d; e.data = .pointCloud(p)
        default: break
        }
    })
    static let decalWidth = P("f67.decal.width", "Width", .length, .dimensions, get: { e, _ in e.decal.map { .double($0.width) } }, set: { e, v, _ in
        guard let d = v.doubleValue, d.isFinite, d >= 0.01 else { throw ParameterError("“Width” must be at least 1 cm.") }
        e.decal?.width = d
    })
    static let decalHeight = P("f67.decal.height", "Height", .length, .dimensions, get: { e, _ in e.decal.map { .double($0.height) } }, set: { e, v, _ in
        guard let d = v.doubleValue, d.isFinite, d >= 0.01 else { throw ParameterError("“Height” must be at least 1 cm.") }
        e.decal?.height = d
    })
    static let decalType = P("f67.decal.type", "Decal Type", .text, .identity, get: { e, ctx in e.decal.map { .text(ctx.model[$0.decalTypeID]?.name ?? "") } })

    static func instance(for e: Element) -> [P] {
        switch e.data {
        case .linkedModel: [BuiltInCatalog.name, format, source, loaded, count, offset, BuiltInCatalog.comments]
        case .pointCloud: [BuiltInCatalog.name, format, source, loaded, count, offset, BuiltInCatalog.comments]
        case .markup: [BuiltInCatalog.name, format, source, loaded, BuiltInCatalog.comments]
        case .decal: [decalType, decalWidth, decalHeight, BuiltInCatalog.comments]
        default: []
        }
    }

    /// Elements whose parameters the catalog registers.
    static var probes: [ElementData] {
        let src = ExternalFileRef(path: "")
        return [.linkedModel(LinkedModelData(format: .arcus, source: src, parts: [], elementCount: 0)),
                .pointCloud(PointCloudData(source: src, points: [], sourceCount: 0, hasColor: false, unitScale: 1)),
                .decal(DecalData(decalTypeID: ElementID(0), center: .zero, normal: .unitZ, up: .unitY, width: 1, height: 1))]
    }
}
