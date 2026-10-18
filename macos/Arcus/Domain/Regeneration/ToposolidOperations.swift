import Foundation
import ArcusGeometry

/// BL-SITE: model changes for toposolids. Each function works inside the caller's transaction, so one tool action is
/// one undoable step.
public enum ToposolidOperations {
    typealias SiteError = SiteOperations.SiteError

    static func solid(_ id: ElementID, _ tx: TransactionContext) throws -> (Element, TopographyData) {
        guard let e = tx.model[id], let t = e.topography else { throw SiteError("Select a toposolid.") }
        guard e.isToposolid else {
            throw SiteError(e.isToposolidSubdivision ? "“\(e.name)” is a sub-division. Select the toposolid it lies on." : "“\(e.name)” is a legacy toposurface. Use Generate Toposolid first.")
        }
        return (e, t)
    }

    /// `id` when it names a toposolid type, else nil.
    static func toposolidType(_ id: ElementID?, _ tx: TransactionContext) -> ElementID? {
        tx.model[id]?.typeData?.systemFamily == .toposolid ? id : nil
    }

    static func copyContext(from e: Element, to n: inout Element) {
        n.phaseCreated = e.phaseCreated; n.phaseDemolished = e.phaseDemolished; n.designOptionID = e.designOptionID
    }

    // MARK: Create

    /// Sketched toposolid: a flat top at `elevation` over `outline`.
    @discardableResult
    public static func create(outline: Polygon2, elevation: Double, typeID: ElementID? = nil, levelID: ElementID? = nil,
                              name: String = "Toposolid", in tx: TransactionContext) throws -> ElementID {
        let o = outline.simplified().counterClockwise
        guard o.count >= 3, !o.isDegenerate, o.isSimple else { throw SiteError("A toposolid needs a closed boundary that doesn't cross itself.") }
        guard elevation.isFinite else { throw SiteError("The elevation must be a number.") }
        let type = toposolidType(typeID, tx) ?? ToposolidTypes.ensureDefaults(in: tx).solid
        let data = TopographyData(points: ToposolidGeometry.flatPoints(outline: o, z: elevation), solid: ToposolidData(outline: o.points))
        return tx.create(.topography, name: name, data: .topography(data), typeID: type, levelID: levelID)
    }

    /// Toposolid from survey points (point file or CAD import), thinned like a toposurface; its outline is the
    /// points' convex hull. Returns its id and the number of points kept.
    @discardableResult
    public static func create(points: [Vec3], name: String = "Toposolid", typeID: ElementID? = nil, in tx: TransactionContext) throws -> (ElementID, Int) {
        let pts = SiteEditing.thin(points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, maxPoints: SiteOperations.maxSurfacePoints)
        guard pts.count >= 3 else { throw SiteError("A toposolid needs at least three points with different plan positions.") }
        let b = Rect2(points: pts.map(\.xy))
        guard b.width > Tolerance.length, b.height > Tolerance.length else { throw SiteError("The points lie on a line; a toposolid needs points spread over an area.") }
        let type = toposolidType(typeID, tx) ?? ToposolidTypes.ensureDefaults(in: tx).solid
        let id = tx.create(.topography, name: name, data: .topography(TopographyData(points: pts, solid: ToposolidData())), typeID: type)
        return (id, pts.count)
    }

    /// Generate Toposolid: replaces a legacy toposurface with a toposolid of the same points, phases and parameters;
    /// its sub-regions become sub-divisions that keep their material.
    @discardableResult
    public static func generate(from surfaceID: ElementID, typeID: ElementID? = nil, in tx: TransactionContext) throws -> ElementID {
        guard let e = tx.model[surfaceID], e.isLegacyToposurface, let t = e.topography else { throw SiteError("Select a toposurface (not a sub-region or toposolid).") }
        guard t.points.count >= 3 else { throw SiteError("“\(e.name)” has fewer than three points.") }
        let defaults = ToposolidTypes.ensureDefaults(in: tx)
        var data = t
        data.solid = ToposolidData()
        let id = tx.create(.topography, name: e.name == "Toposurface" ? "Toposolid" : e.name, data: .topography(data), typeID: toposolidType(typeID, tx) ?? defaults.solid,
                           levelID: e.levelID) { n in copyContext(from: e, to: &n); n.params = e.params; n.classification = e.classification }
        for s in SiteOperations.subregions(of: surfaceID, tx.model) {
            guard let b = s.topography?.boundary else { continue }
            tx.create(.topography, name: "Sub-Division", data: .topography(TopographyData(points: s.topography?.points ?? [], boundary: b,
                                                                                               materialID: s.topography?.materialID,
                                                                                               solid: ToposolidData(subdivisionHeight: 0.05))),
                      typeID: defaults.subdivision, hostID: id) { n in copyContext(from: s, to: &n); n.params = s.params }
            tx.delete(s.id)
        }
        tx.delete(surfaceID)
        return id
    }

    // MARK: Sub-Divide

    /// Adds a sub-division (thin layered solid following the host's surface) inside `boundary`.
    @discardableResult
    public static func subdivide(_ hostID: ElementID, boundary: Polygon2, typeID: ElementID? = nil, height: Double? = nil,
                                 in tx: TransactionContext) throws -> ElementID {
        let (e, _) = try solid(hostID, tx)
        let b = boundary.simplified().counterClockwise
        guard b.count >= 3, !b.isDegenerate, b.isSimple else { throw SiteError("A sub-division needs a closed boundary that doesn't cross itself.") }
        let overlap = PolygonBoolean.intersection([Profile2(outer: b)], [Profile2(outer: ToposolidGeometry.outline(e))])
        guard overlap.reduce(0, { $0 + $1.area }) > Tolerance.area else { throw SiteError("The sub-division doesn't overlap the toposolid.") }
        if let h = height, !(h.isFinite && abs(h) >= 0.001) { throw SiteError("The sub-division height must be at least 1 mm up or down.") }
        let type = toposolidType(typeID, tx) ?? ToposolidTypes.ensureDefaults(in: tx).subdivision
        let thickness = tx.model[type]?.typeData?.assembly?.totalThickness ?? 0.1
        let host = ToposolidGeometry.topSurface(e, tx.model)
        let pts = b.points.map { Vec3($0, z: SiteEditing.elevation(host.points, at: $0, triangles: host.triangles)) }
        let data = TopographyData(points: pts, boundary: b.points, solid: ToposolidData(subdivisionHeight: height ?? max(thickness, 0.001)))
        return tx.create(.topography, name: "Sub-Division", data: .topography(data), typeID: type, hostID: hostID) { n in copyContext(from: e, to: &n) }
    }

    // MARK: Split and merge

    /// Splits a toposolid along a line or polyline into two toposolids with split outlines; sub-divisions follow the
    /// part that holds their centre.
    @discardableResult
    public static func split(_ id: ElementID, along path: [Vec2], in tx: TransactionContext) throws -> [ElementID] {
        let (e, t) = try solid(id, tx)
        guard path.count >= 2 else { throw SiteError("Click at least two points of the split line.") }
        let outline = ToposolidGeometry.outline(e)
        let surface = ToposolidGeometry.topSurface(e, tx.model)
        guard let (lp, rp) = SiteEditing.split(surface.points, along: path) else {
            throw SiteError("The split line must cross the toposolid so both parts keep at least three points.")
        }
        // The region left of the extended split line, closed far away on the left.
        let b = outline.bounds
        let reach = (b.width + b.height) * 2 + 1
        var ext = path
        ext[0] = path[0] - (path[1] - path[0]).normalized * reach
        ext[ext.count - 1] = path[path.count - 1] + (path[path.count - 1] - path[path.count - 2]).normalized * reach
        let left = (ext[ext.count - 1] - ext[0]).normalized.perpendicular
        let region = Polygon2(ext + [ext[ext.count - 1] + left * reach, ext[0] + left * reach])
        func largest(_ ps: [Profile2]) -> Polygon2? { ps.max { $0.area < $1.area }.map(\.outer) }
        guard let lo = largest(PolygonBoolean.intersection([Profile2(outer: outline)], [Profile2(outer: region)])),
              let ro = largest(PolygonBoolean.difference([Profile2(outer: outline)], [Profile2(outer: region)])),
              lo.area > Tolerance.area, ro.area > Tolerance.area else {
            throw SiteError("The split line must cross the toposolid from edge to edge.")
        }
        func points(_ side: [Vec3], _ o: Polygon2) -> [Vec3] {
            let edge = ToposolidGeometry.densify(o.points, spacing: ToposolidGeometry.densifySpacing(for: o))
                .map { Vec3($0, z: SiteEditing.elevation(surface.points, at: $0, triangles: surface.triangles)) }
            return SiteEditing.dedupe(edge + side.filter { o.contains($0.xy, onBoundary: false) })
        }
        let leftPts = points(lp, lo), rightPts = points(rp, ro)
        tx.update(id) { $0.topography?.points = leftPts; $0.topography?.solid?.outline = lo.counterClockwise.points }
        var rd = t
        rd.points = rightPts
        rd.solid?.outline = ro.counterClockwise.points
        rd.solid?.cutVolume = nil; rd.solid?.fillVolume = nil
        let other = tx.create(.topography, name: e.name, data: .topography(rd), typeID: e.typeID, levelID: e.levelID) { n in
            copyContext(from: e, to: &n); n.params = e.params
        }
        for s in tx.model.hosted(by: id) where s.isToposolidSubdivision {
            guard let sb = s.topography?.boundary, sb.count >= 3 else { continue }
            if ro.contains(Polygon2(sb).centroid) { tx.update(s.id) { $0.hostID = other } }
        }
        return [id, other]
    }

    /// Merges toposolids whose outlines touch or overlap into the first one (outline = their union).
    @discardableResult
    public static func merge(_ ids: [ElementID], in tx: TransactionContext) throws -> ElementID {
        let unique = ids.reduce(into: [ElementID]()) { if !$0.contains($1) { $0.append($1) } }
        guard unique.count >= 2 else { throw SiteError("Select two or more toposolids to merge.") }
        var pts: [Vec3] = []
        var outlines: [Profile2] = []
        for id in unique {
            let (e, t) = try solid(id, tx)
            pts = SiteEditing.merge(pts, t.points)
            outlines.append(Profile2(outer: ToposolidGeometry.outline(e)))
        }
        let union = PolygonBoolean.union(outlines)
        guard union.count == 1, let o = union.first?.outer else { throw SiteError("Only toposolids that touch or overlap can be merged.") }
        let keep = unique[0]
        tx.update(keep) { $0.topography?.points = pts; $0.topography?.solid?.outline = o.counterClockwise.points }
        for id in unique.dropFirst() {
            for s in tx.model.hosted(by: id) where s.topography != nil { tx.update(s.id) { $0.hostID = keep } }
            tx.delete(id)
        }
        return keep
    }

    // MARK: Simplify

    /// Simplify: drops survey points that change the surface by less than `tolerance`. Returns the point counts.
    @discardableResult
    public static func simplify(_ id: ElementID, tolerance: Double, in tx: TransactionContext) throws -> (before: Int, after: Int) {
        guard let e = tx.model[id], e.topography != nil, e.topography?.boundary == nil else { throw SiteError("Select a toposolid or toposurface.") }
        guard tolerance.isFinite, tolerance > 0 else { throw SiteError("The accuracy must be greater than zero.") }
        let pts = e.topography?.points ?? []
        let o = e.topography?.solid?.outline.flatMap { $0.count >= 3 ? Polygon2($0) : nil }
        let kept = ToposolidGeometry.simplify(pts, outline: o, tolerance: tolerance)
        if kept.count < pts.count { tx.update(id) { $0.topography?.points = kept } }
        return (pts.count, kept.count)
    }

    // MARK: Shape editing

    /// Split Line (shape editing): points along a segment where it crosses the surface's triangulation, at the
    /// surface's elevations, so the surface can fold along the line. Returns the new point set.
    public static func addSplitLine(_ pts: [Vec3], from a: Vec2, to b: Vec2) -> [Vec3] {
        guard a.distance(to: b) > Tolerance.length, pts.count >= 3 else { return pts }
        let tri = TopographyGeometry.triangulate(pts)
        let ends = [a, b].map { Vec3($0, z: SiteEditing.elevation(pts, at: $0, triangles: tri)) }
        return SiteEditing.dedupe(pts + ends + SiteEditing.crossings(pts, tri: tri, path: [a, b]))
    }

    // MARK: Excavate

    /// Excavate: the toposolid's surface inside each floor or building pad footprint is lowered or raised to the
    /// element's underside (a 50 mm batter at the edge); the cut and fill volumes are added to the toposolid's
    /// Cut and Fill parameters and returned.
    @discardableResult
    public static func excavate(_ id: ElementID, by cutterIDs: [ElementID], in tx: TransactionContext) throws -> (cut: Double, fill: Double) {
        let (e, t) = try solid(id, tx)
        let cutters = cutterIDs.compactMap { tx.model[$0] }.filter { $0.slab != nil && ($0.category == .floors || $0.category == .buildingPads) }
        guard !cutters.isEmpty else { throw SiteError("Select floors or building pads that lie over the toposolid.") }
        var pts = t.points
        let outline = ToposolidGeometry.outline(e)
        var cut = 0.0, fill = 0.0, touched = 0
        for c in cutters {
            guard let prof = SlabGeometry.profile(c) else { continue }
            let foot = prof.outer.counterClockwise
            guard PolygonBoolean.intersection([Profile2(outer: foot)], [Profile2(outer: outline)]).reduce(0, { $0 + $1.area }) > Tolerance.area else { continue }
            let bottom = ElementMeshes.bounds(c, tx.model).min.z
            guard bottom.isFinite else { continue }
            var surf = e
            surf.topography?.points = pts
            let s = ToposolidGeometry.topSurface(surf, tx.model)
            let v = ToposolidGeometry.cutFill(surface: s, region: foot, level: bottom)
            cut += v.cut; fill += v.fill
            let spacing = ToposolidGeometry.densifySpacing(for: foot)
            let rim = ToposolidGeometry.densify(foot.points, spacing: spacing)
                .filter { outline.contains($0) }
                .map { Vec3($0, z: SiteEditing.elevation(s.points, at: $0, triangles: s.triangles)) }
            let inner = foot.offset(by: -0.05).flatMap { ToposolidGeometry.densify($0.points, spacing: spacing) }
                .filter { outline.contains($0) }.map { Vec3($0, z: bottom) }
            let corners = ToposolidGeometry.densify(outline.points, spacing: spacing).filter { foot.contains($0, onBoundary: false) }.map { Vec3($0, z: bottom) }
            pts = SiteEditing.dedupe(pts.filter { !foot.contains($0.xy) } + rim + inner + corners)
            touched += 1
        }
        guard touched > 0 else { throw SiteError("None of the selected floors or pads lies over the toposolid.") }
        let newPts = pts
        tx.update(id) { x in
            guard var d = x.topography else { return }
            d.points = newPts
            d.solid?.cutVolume = (t.solid?.cutVolume ?? 0) + cut
            d.solid?.fillVolume = (t.solid?.fillVolume ?? 0) + fill
            x.topography = d
        }
        return (cut, fill)
    }
}
