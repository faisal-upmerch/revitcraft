import Foundation
import ArcusGeometry
import ArcusDomain

// F67: model operations behind the Insert tab (links, point clouds, linked topography, DWF markups, decals, gbXML
// and image imports). File reading happens elsewhere (ArcusCAD readers, the UI's link loader); everything here
// works on already-read content inside a transaction.

public struct InsertError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ s: String) { description = s }
}

public enum InsertOperations {
    /// Largest packed content one link may hold (the element is stored as one record).
    public static let maxLinkBytes = 48 << 20

    // MARK: Linked models

    /// Link Model / Link IFC / Coordination Model: the content placed internal origin to internal origin.
    @discardableResult
    public static func addLinkedModel(_ format: LinkedModelFormat, source: ExternalFileRef, parts: [LinkedModelPart], elementCount: Int,
                                      in tx: TransactionContext) throws -> ElementID {
        guard !parts.isEmpty else { throw InsertError("“\(source.name)” has no model elements with geometry to link.") }
        try checkSize(parts, source.name)
        let category: Category = format == .obj ? .coordinationModels : .linkedModels
        let names = Set(tx.model.elements(category).map(\.name))
        var name = source.name, k = 2
        while names.contains(name) { name = "\(source.name) (\(k))"; k += 1 }
        var src = source
        src.lastLoaded = Date()
        return tx.create(category, name: name, data: .linkedModel(LinkedModelData(format: format, source: src, parts: parts, elementCount: elementCount)))
    }

    /// Replaces a link's content with what was just read from its source (placement and load state are kept).
    public static func reloadLinkedModel(_ id: ElementID, parts: [LinkedModelPart], elementCount: Int, sourceModified: Date?, in tx: TransactionContext) throws {
        guard let name = tx.model[id]?.linkedModel?.source.name else { throw InsertError("The element is not a linked model.") }
        try checkSize(parts, name)
        tx.update(id) { e in
            guard var l = e.linkedModel else { return }
            l.parts = parts; l.elementCount = elementCount; l.isLoaded = true
            l.source.sourceModified = sourceModified; l.source.lastLoaded = Date()
            e.linkedModel = l
        }
    }

    static func checkSize(_ parts: [LinkedModelPart], _ name: String) throws {
        let bytes = parts.reduce(0) { $0 + $1.mesh.blob.count }
        if bytes > maxLinkBytes { throw InsertError("“\(name)” is too large to link (\(bytes >> 20) MB of geometry; the limit is \(maxLinkBytes >> 20) MB).") }
    }

    // MARK: Point clouds

    @discardableResult
    public static func addPointCloud(_ set: PointSet, source: ExternalFileRef, in tx: TransactionContext) throws -> ElementID {
        guard !set.points.isEmpty else { throw InsertError("“\(source.name)” has no points.") }
        var src = source
        src.lastLoaded = Date()
        let data = PointCloudData(source: src, points: set.points, sourceCount: set.sourceCount, hasColor: set.hasColor, unitScale: set.unitScale)
        return tx.create(.pointClouds, name: source.name, data: .pointCloud(data))
    }

    public static func reloadPointCloud(_ id: ElementID, _ set: PointSet, sourceModified: Date?, in tx: TransactionContext) {
        tx.update(id) { e in
            guard var p = e.pointCloud else { return }
            p.points = PackedPoints(set.points); p.sourceCount = set.sourceCount; p.hasColor = set.hasColor; p.isLoaded = true
            p.source.sourceModified = sourceModified; p.source.lastLoaded = Date()
            e.pointCloud = p
        }
    }

    // MARK: Linked topography

    /// Link Topography: a toposolid through the surveyed points that re-reads its file when the project opens.
    @discardableResult
    public static func linkTopography(_ set: PointSet, source: ExternalFileRef, typeID: ElementID? = nil, in tx: TransactionContext) throws -> (ElementID, Int) {
        let name = URL(fileURLWithPath: source.path).deletingPathExtension().lastPathComponent
        let (id, kept) = try ToposolidOperations.create(points: set.positions, name: name.isEmpty ? "Toposolid" : name, typeID: typeID, in: tx)
        var src = source
        src.lastLoaded = Date()
        tx.update(id) { $0.source = TopographyLink.metadata(src, unitScale: set.unitScale) }
        return (id, kept)
    }

    public static func reloadTopography(_ id: ElementID, _ set: PointSet, sourceModified: Date?, in tx: TransactionContext) throws {
        guard let e = tx.model[id], var f = TopographyLink.source(of: e) else { throw InsertError("The element is not a linked toposolid.") }
        let pts = SiteEditing.thin(set.positions.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, maxPoints: SiteOperations.maxSurfacePoints)
        guard pts.count >= 3 else { throw InsertError("“\(f.name)” now has fewer than three points; the toposolid was left as it was.") }
        f.sourceModified = sourceModified
        let meta = TopographyLink.metadata(f, unitScale: set.unitScale)
        tx.update(id) { $0.topography?.points = pts; $0.source = meta }
    }

    // MARK: DWF markups

    /// DWF Markup: one page's lines, text and pictures on a sheet.
    @discardableResult
    public static func addMarkup(_ page: DWFPage, onSheet sheetID: ElementID, source: ExternalFileRef, in tx: TransactionContext) throws -> ElementID {
        guard tx.model[sheetID]?.sheet != nil else { throw InsertError("DWF markups are placed on sheets.") }
        guard !page.isEmpty else { throw InsertError("The page “\(page.name)” has no markups.") }
        var src = source
        src.lastLoaded = Date()
        let m = MarkupData(source: src, pageName: page.name, pageSize: page.size, polylines: page.polylines, texts: page.texts, pictures: page.pictures)
        return tx.create(.dwfMarkups, name: "\(source.name) - \(page.name)", data: .markup(m), ownerViewID: sheetID)
    }

    /// Replaces a markup with its page from the re-read file (matched by page name).
    public static func reloadMarkup(_ id: ElementID, pages: [DWFPage], sourceModified: Date?, in tx: TransactionContext) throws {
        guard let m = tx.model[id]?.markup else { throw InsertError("The element is not a DWF markup.") }
        guard let p = pages.first(where: { $0.name == m.pageName }) else { throw InsertError("“\(m.source.name)” no longer has the page “\(m.pageName)”.") }
        tx.update(id) { e in
            guard var d = e.markup else { return }
            d.polylines = p.polylines; d.texts = p.texts; d.pictures = p.pictures; d.pageSize = p.size; d.isLoaded = true
            d.source.sourceModified = sourceModified; d.source.lastLoaded = Date()
            e.markup = d
        }
    }

    /// The sheet a page most likely belongs to: one whose number or name the page name contains (or the reverse).
    public static func matchingSheet(for pageName: String, in model: BIMModel) -> ElementID? {
        let n = pageName.lowercased()
        return model.sheets.first { s in
            let num = (s.sheet?.number ?? "").lowercased(), name = s.name.lowercased()
            return (!num.isEmpty && n.contains(num)) || (!name.isEmpty && (n.contains(name) || name.contains(n)))
        }?.id
    }

    // MARK: Load / unload

    public static func setLoaded(_ id: ElementID, _ loaded: Bool, in tx: TransactionContext) {
        tx.update(id) { e in
            switch e.data {
            case .linkedModel(var l): l.isLoaded = loaded; e.data = .linkedModel(l)
            case .pointCloud(var p): p.isLoaded = loaded; e.data = .pointCloud(p)
            case .markup(var m): m.isLoaded = loaded; e.data = .markup(m)
            default: break
            }
        }
    }

    /// Every element that reads an external file through an F67 link, in a stable order.
    public static func linkElements(_ model: BIMModel) -> [Element] {
        let cats: [Category] = [.linkedModels, .coordinationModels, .pointClouds, .dwfMarkups, .topography]
        return model.elements(cats).filter { $0.f67LinkSource != nil }.sorted { $0.id < $1.id }
    }

    // MARK: gbXML

    /// Import gbXML: each space becomes a room on the level at or below its floor, bounded by room separation lines
    /// along the space's outline (shared edges are drawn once). Returns the rooms.
    public static func importGbXML(_ spaces: [GbXMLSpace], in tx: TransactionContext) throws -> [ElementID] {
        let levels = tx.model.levels
        guard !levels.isEmpty else { throw InsertError("The project has no levels.") }
        var drawn: [ElementID: [Segment2]] = [:]
        var rooms: [ElementID] = []
        var number = (tx.model.elements(.rooms).compactMap { Int($0.room?.number ?? "") }.max() ?? 0) + 1
        for s in spaces {
            let poly = Polygon2(s.floor).counterClockwise
            guard poly.count >= 3, poly.area > 0.01 else { continue }
            let level = levels.last { ($0.level?.elevation ?? 0) <= s.bottom + 0.001 } ?? levels[0]
            let z = level.level?.elevation ?? 0
            for edge in poly.edges where edge.length > Tolerance.shortCurve {
                let seen = drawn[level.id, default: []].contains { o in
                    (o.start.distance(to: edge.start) < 0.001 && o.end.distance(to: edge.end) < 0.001) || (o.start.distance(to: edge.end) < 0.001 && o.end.distance(to: edge.start) < 0.001)
                }
                guard !seen else { continue }
                drawn[level.id, default: []].append(edge)
                tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(edge))), levelID: level.id)
            }
            var data = RoomData(point: interiorPoint(poly), number: String(number), limitOffset: max(0.1, s.top - s.bottom))
            data.baseOffset = s.bottom - z
            data.limitOffset = max(0.1, s.top - s.bottom) + data.baseOffset
            let id = tx.create(.rooms, name: s.name, data: .room(data), levelID: level.id) { e in
                if !s.number.isEmpty { e.comments = "gbXML space \(s.number)" }
            }
            rooms.append(id)
            number += 1
        }
        guard !rooms.isEmpty else { throw InsertError("No spaces could be imported (none has a floor outline with an area).") }
        return rooms
    }

    /// A point inside a polygon: its centroid when inside, else a point just inside its longest edge.
    static func interiorPoint(_ p: Polygon2) -> Vec2 {
        let c = p.centroid
        if p.contains(c, onBoundary: false) { return c }
        let e = p.edges.max { $0.length < $1.length } ?? Segment2(p.points[0], p.points[1])
        let mid = (e.start + e.end) * 0.5
        let d = (e.end - e.start).normalized
        let inward = Vec2(-d.y, d.x) * min(0.05, e.length / 10)
        return p.contains(mid + inward, onBoundary: false) ? mid + inward : mid - inward
    }

    // MARK: Imported images

    /// Import Image / Import PDF: a raster stored in the project (not linked), placed in a view at `scale` meters per
    /// pixel with its bottom left at `origin`.
    @discardableResult
    public static func importImage(_ png: Data, name: String, pixelSize: (Int, Int), metersPerPixel: Double, origin: Vec2 = .zero,
                                   viewID: ElementID?, levelID: ElementID?, in tx: TransactionContext) throws -> ElementID {
        guard !png.isEmpty, pixelSize.0 > 0, pixelSize.1 > 0 else { throw InsertError("The image could not be read.") }
        let t = Transform2.translation(origin) * Transform2.scale(metersPerPixel, metersPerPixel)
        var ld = LinkData(format: .image, isLinked: false, sourcePath: "", sourceName: name, contentKey: "", placement: t)
        ld.embeddedData = png
        ld.opacity = 1
        ld.lastLoaded = Date()
        return tx.create(.importedCAD, name: name, data: .link(ld), levelID: levelID, ownerViewID: viewID) {
            $0.source = SourceMetadata(format: "Image", fileName: name, originalID: "", originalType: "Image Import")
        }
    }

    // MARK: Decals

    @discardableResult
    public static func createDecalType(_ name: String, _ data: DecalTypeData, in tx: TransactionContext) -> ElementID {
        let names = Set(tx.model.elements(.decalTypes).map(\.name))
        var n = name.isEmpty ? "Decal" : name, k = 2
        while names.contains(n) { n = "\(name) \(k)"; k += 1 }
        return tx.create(.decalTypes, name: n, data: .decalType(data))
    }

    /// Place Decal: a decal of `typeID` on the face of `host` through `center` with outward `normal`. Upright on walls;
    /// on floors and roofs the image's top points north. 1 m wide (3 ft in imperial projects), as tall as the image's
    /// aspect ratio makes it.
    @discardableResult
    public static func placeDecal(_ typeID: ElementID, host: ElementID, center: Vec3, normal: Vec3, in tx: TransactionContext) throws -> ElementID {
        guard let type = tx.model[typeID]?.decalType else { throw InsertError("Create a decal type first (Decal Types).") }
        guard let h = tx.model[host], h.category.isModel else { throw InsertError("Place the decal on a face of the model.") }
        let n = normal.normalized
        guard n.length > 0.5 else { throw InsertError("Place the decal on a planar face.") }
        var up = Vec3(0, 0, 1) - n * n.z
        if up.length < 1e-6 { up = Vec3(0, 1, 0) - n * n.y }
        let width = tx.model.units.system == .imperial ? 0.9144 : 1.0
        let height = type.pixelWidth > 0 && type.pixelHeight > 0 ? width * Double(type.pixelHeight) / Double(type.pixelWidth) : width
        let d = DecalData(decalTypeID: typeID, center: center, normal: n, up: up.normalized, width: width, height: height)
        return tx.create(.decals, name: tx.model[typeID]?.name ?? "Decal", data: .decal(d), levelID: h.levelID, hostID: host)
    }

    /// The planar face of a model element under a plan or elevation pick, as (center, outward normal).
    /// Plans: walls give the face on the picked side (at 1.5 m above the base, or mid-height), floors, roofs and
    /// other horizontal elements their top. Elevations and sections: the wall face towards the viewer at the pick.
    public static func decalFace(host e: Element, at p: Vec2, view: ViewData?, model: BIMModel) -> (Vec3, Vec3)? {
        if let f = WallGeometry.frame(e, model), case .line(let seg) = f.location {
            let d = seg.direction
            let left = Vec2(-d.y, d.x)
            if let v = view, v.kind.isVerticalCut, let o = v.planeOrigin, let r = v.rightVector, let fwd = v.viewDirection?.normalized {
                // (u, z) → the point on the location line seen at u.
                let eye = o.xy + r * p.x
                let denom = fwd.cross(seg.end - seg.start)
                guard abs(denom) > 1e-12 else { return nil }
                let s = (seg.start - eye).cross(fwd) / denom
                let on = seg.start + (seg.end - seg.start) * min(1, max(0, s))
                let towards = left.dot(-fwd) >= 0 ? 1.0 : -1.0
                let off = towards > 0 ? f.leftOffset : f.rightOffset
                let c = on + left * off
                guard p.y >= f.baseZ - 0.01, p.y <= f.topZ + 0.01 else { return nil }
                return (Vec3(c, z: p.y), Vec3(left * towards, z: 0))
            }
            let side = (p - seg.start).dot(left) >= 0 ? 1.0 : -1.0
            let on = seg.closestPoint(to: p)
            let c = on + left * (side > 0 ? f.leftOffset : f.rightOffset)
            let z = f.baseZ + min(1.5, (f.topZ - f.baseZ) / 2)
            return (Vec3(c, z: z), Vec3(left * side, z: 0))
        }
        let b = ElementMeshes.bounds(e, model)
        guard !b.isEmpty else { return nil }
        if let v = view, v.kind.isVerticalCut { return nil }
        return (Vec3(p, z: b.max.z), Vec3(0, 0, 1))
    }
}
