import Foundation
import ArcusGeometry

/// W2-DWG: model changes for the Massing & Site tools. Each function works inside the caller's transaction, so one tool
/// action is one undoable step.
public enum SiteOperations {
    public struct SiteError: Error, Sendable, CustomStringConvertible {
        public var message: String
        public init(_ m: String) { message = m }
        public var description: String { message }
    }

    /// Largest number of survey points a new toposurface is given (more are thinned evenly), so the surface stays fast
    /// to triangulate and draw.
    public static let maxSurfacePoints = 2500

    /// Creates a toposurface from survey points (thinned to `maxSurfacePoints`). Returns its id and the number of points kept.
    @discardableResult
    public static func createToposurface(_ points: [Vec3], name: String = "Toposurface", in tx: TransactionContext) throws -> (ElementID, Int) {
        let pts = SiteEditing.thin(points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, maxPoints: maxSurfacePoints)
        guard pts.count >= 3 else { throw SiteError("A toposurface needs at least three points with different plan positions.") }
        let b = Rect2(points: pts.map(\.xy))
        guard b.width > Tolerance.length, b.height > Tolerance.length else { throw SiteError("The points lie on a line; a toposurface needs points spread over an area.") }
        let id = tx.create(.topography, name: name, data: .topography(TopographyData(points: pts)))
        return (id, pts.count)
    }

    static func surface(_ id: ElementID, _ tx: TransactionContext) throws -> (Element, TopographyData) {
        guard let e = tx.model[id], let t = e.topography else { throw SiteError("Select a toposurface.") }
        guard !e.isToposolidSubdivision else { throw SiteError("“\(e.name)” is a sub-division. Select the toposolid it lies on.") } // BL-SITE
        guard t.boundary == nil else { throw SiteError("“\(e.name)” is a sub-region. Select the toposurface it lies on.") }
        return (e, t)
    }

    /// Sub-regions hosted on a surface.
    public static func subregions(of id: ElementID, _ model: BIMModel) -> [Element] {
        model.elements(.topography).filter { $0.hostID == id && $0.topography?.boundary != nil }
    }

    /// Adds a sub-region with its own material on a toposurface.
    @discardableResult
    public static func createSubregion(on host: ElementID, boundary: Polygon2, materialID: ElementID? = nil, in tx: TransactionContext) throws -> ElementID {
        let (e, t) = try surface(host, tx)
        if e.isToposolid { throw SiteError("Sub-regions are for legacy toposurfaces. Use Sub-Divide on a toposolid.") } // BL-SITE
        let b = boundary.simplified().counterClockwise
        guard b.count >= 3, !b.isDegenerate, b.isSimple else { throw SiteError("A sub-region needs a closed boundary that doesn't cross itself.") }
        let pts = SiteEditing.subregionPoints(host: t.points, boundary: b)
        guard pts.count >= 3 else { throw SiteError("The sub-region doesn't overlap the toposurface.") }
        return tx.create(.topography, name: "Sub-Region", data: .topography(TopographyData(points: pts, boundary: b.points, materialID: materialID)),
                         hostID: host) { $0.phaseCreated = e.phaseCreated; $0.designOptionID = e.designOptionID }
    }

    /// Splits a toposurface along a line or polyline into two surfaces; sub-regions follow the half that holds their centre.
    @discardableResult
    public static func split(_ id: ElementID, along path: [Vec2], in tx: TransactionContext) throws -> [ElementID] {
        if tx.model[id]?.isToposolid == true { return try ToposolidOperations.split(id, along: path, in: tx) } // BL-SITE
        let (e, t) = try surface(id, tx)
        guard let (left, right) = SiteEditing.split(t.points, along: path) else {
            throw SiteError("The split line must cross the toposurface so both parts keep at least three points.")
        }
        tx.update(id) { $0.topography?.points = left }
        let other = tx.create(.topography, name: e.name, data: .topography(TopographyData(points: right, materialID: t.materialID))) { n in
            n.phaseCreated = e.phaseCreated; n.phaseDemolished = e.phaseDemolished; n.designOptionID = e.designOptionID; n.params = e.params
        }
        let rightTri = TopographyGeometry.triangulate(right)
        for s in subregions(of: id, tx.model) {
            guard let b = s.topography?.boundary, b.count >= 3 else { continue }
            if SiteEditing.surfaceZ(right, at: Polygon2(b).centroid, triangles: rightTri) != nil && SiteEditing.surfaceZ(left, at: Polygon2(b).centroid) == nil {
                tx.update(s.id) { $0.hostID = other }
            }
        }
        return [id, other]
    }

    /// Merges toposurfaces into the first one; the others are deleted and their sub-regions move to the result.
    @discardableResult
    public static func merge(_ ids: [ElementID], in tx: TransactionContext) throws -> ElementID {
        let unique = ids.reduce(into: [ElementID]()) { if !$0.contains($1) { $0.append($1) } }
        guard unique.count >= 2 else { throw SiteError("Select two or more toposurfaces to merge.") }
        let solids = unique.filter { tx.model[$0]?.isToposolid == true }.count // BL-SITE
        if solids == unique.count { return try ToposolidOperations.merge(unique, in: tx) } // BL-SITE
        if solids > 0 { throw SiteError("Toposolids can only be merged with other toposolids. Generate Toposolid from the toposurfaces first.") } // BL-SITE
        var pts: [Vec3] = []
        for id in unique { pts = SiteEditing.merge(pts, try surface(id, tx).1.points) }
        let keep = unique[0]
        tx.update(keep) { $0.topography?.points = pts }
        for id in unique.dropFirst() {
            for s in subregions(of: id, tx.model) { tx.update(s.id) { $0.hostID = keep } }
            tx.delete(id)
        }
        return keep
    }

    /// Graded region: the existing surface is marked demolished in `phase` and a copy created in that phase is returned
    /// for editing. The existing surface must have been created in an earlier phase (it is moved to the one before
    /// `phase` when it was created in `phase` itself).
    @discardableResult
    public static func gradedRegion(from id: ElementID, phase: ElementID?, in tx: TransactionContext) throws -> ElementID {
        let (e, t) = try surface(id, tx)
        let phases = tx.model.phases
        guard let current = phase ?? phases.last?.id, let ci = phases.firstIndex(where: { $0.id == current }) else {
            throw SiteError("The project has no phases.")
        }
        guard ci > 0 else {
            throw SiteError("Graded Region needs an earlier phase for the existing ground. Set the view's phase to a later phase (Manage ▸ Phases), then try again.")
        }
        guard e.phaseDemolished == nil else { throw SiteError("“\(e.name)” is already demolished. Grade the surface that replaced it.") }
        let createdOrder = tx.model.phaseOrder(e.phaseCreated) ?? 0
        let currentOrder = phases[ci].phase?.order ?? 0
        tx.update(id) { x in
            if createdOrder >= currentOrder { x.phaseCreated = phases[ci - 1].id }
            x.phaseDemolished = current
        }
        let graded = tx.create(.topography, name: "Graded Region", data: .topography(TopographyData(points: t.points, materialID: t.materialID, solid: t.solid)), // BL-SITE: keeps a toposolid's outline
                               typeID: e.typeID) { n in
            n.phaseCreated = current; n.designOptionID = e.designOptionID
        }
        return graded
    }
}
