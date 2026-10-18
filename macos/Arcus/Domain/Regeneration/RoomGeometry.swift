import Foundation
import ArcusGeometry

/// Result of computing a room's boundary.
public enum RoomBoundaryState: Sendable, Hashable {
    case bounded
    case notEnclosed
    case notPlaced
    /// Another room is placed in the same enclosed region.
    case redundant(ElementID)
}

public struct RoomBoundary: Sendable {
    public var state: RoomBoundaryState
    public var profile: Profile2?
    public var area: Double { profile?.area ?? 0 }
    public var perimeter: Double { profile?.perimeter ?? 0 }
}

public enum RoomGeometry {
    /// Room-bounding segments on a level at a computation height: wall faces (union outline), columns,
    /// room separation lines. Walls are cut at the computation height so openings do not leak rooms.
    public static func boundingSegments(level: ElementID, atZ z: Double, _ model: BIMModel, areaScheme: ElementID? = nil) -> [Segment2] {
        var polys: [Polygon2] = []
        if areaScheme == nil {
            for w in model.elements(.walls) where w.wall?.roomBounding == true && w.phaseDemolished == nil {
                guard let f = WallGeometry.frame(w, model), f.baseZ <= z + Tolerance.length, f.topZ >= z - Tolerance.length else { continue }
                if let fp = WallGeometry.footprint(w, model) { polys.append(fp) }
            }
            for c in model.elements(.columns) + model.elements(.structuralColumns) where c.column?.roomBounding == true {
                guard c.levelID == level else { continue }
                polys.append(contentsOf: ComponentGeometry.planOutline(c, model))
            }
        }
        var segs: [Segment2] = []
        for piece in BoundaryCleanup.unionBoundary(of: polys) { segs.append(piece.segment) }
        let lineCategory: Category = areaScheme == nil ? .roomSeparationLines : .areaBoundaryLines
        for l in model.elements(lineCategory) where l.levelID == level {
            guard let ml = l.modelLine else { continue }
            if areaScheme != nil, l.params[ParameterID("areaScheme")]?.refValue != areaScheme { continue }
            for c in ml.curves { // F1: a spline or ellipse bounds by its segments
                let pts = c.tessellate(chordTolerance: 0.005)
                for i in 0..<(pts.count - 1) { segs.append(Segment2(pts[i], pts[i + 1])) }
            }
        }
        return segs
    }

    /// Computes the arrangement once per level for all rooms on it.
    public static func boundaries(level: ElementID, _ model: BIMModel) -> [ElementID: RoomBoundary] {
        let rooms = model.elements(.rooms).filter { $0.levelID == level && $0.room?.areaSchemeID == nil }
        let areas = model.elements(.areas).filter { $0.levelID == level }
        var out: [ElementID: RoomBoundary] = [:]
        let lv = model.elevation(ofLevel: level)
        if !rooms.isEmpty {
            let h = (model[level]?.level?.computationHeight ?? 0)
            let z = lv + max(h, 0.3)
            let arr = PlanarArrangement(segments: boundingSegments(level: level, atZ: z, model))
            assign(rooms, arr, into: &out)
        }
        let schemes = Set(areas.compactMap { $0.room?.areaSchemeID })
        for s in schemes.sorted() {
            let arr = PlanarArrangement(segments: boundingSegments(level: level, atZ: lv + 1, model, areaScheme: s))
            assign(areas.filter { $0.room?.areaSchemeID == s }, arr, into: &out)
        }
        return out
    }

    private static func assign(_ rooms: [Element], _ arr: PlanarArrangement, into out: inout [ElementID: RoomBoundary]) {
        var claimed: [Int: ElementID] = [:]
        let faces = arr.faces
        for r in rooms.sorted(by: { $0.id < $1.id }) {
            guard let p = r.room?.point else { out[r.id] = RoomBoundary(state: .notPlaced, profile: nil); continue }
            guard let face = arr.face(containing: p) else { out[r.id] = RoomBoundary(state: .notEnclosed, profile: nil); continue }
            let key = faces.firstIndex(where: { $0.outer == face.outer }) ?? -1
            if let owner = claimed[key] {
                out[r.id] = RoomBoundary(state: .redundant(owner), profile: face.profile)
            } else {
                claimed[key] = r.id
                out[r.id] = RoomBoundary(state: .bounded, profile: face.profile)
            }
        }
    }

    public static func boundary(_ room: Element, _ model: BIMModel) -> RoomBoundary {
        guard let l = room.levelID else { return RoomBoundary(state: .notPlaced, profile: nil) }
        return RoomBoundaryCache.shared.boundaries(level: l, model)[room.id] ?? RoomBoundary(state: .notPlaced, profile: nil)
    }

    public static func height(_ room: Element, _ model: BIMModel) -> Double {
        guard let r = room.room else { return 0 }
        let base = model.baseElevation(of: room)
        let upper = r.upperLimitLevelID ?? room.levelID
        return max(0, model.elevation(ofLevel: upper) + r.limitOffset - base)
    }
}

/// Memoizes per-level room boundaries for a model revision (room computation is the costliest derived query).
public final class RoomBoundaryCache: @unchecked Sendable {
    public static let shared = RoomBoundaryCache()
    private let lock = NSLock()
    private var entries: [String: [ElementID: RoomBoundary]] = [:]
    private var order: [String] = []
    /// (content stamp, level) → content key, so repeated queries on one snapshot skip hashing the model.
    private var stampKeys: [SIMD2<UInt64>: String] = [:]

    public func boundaries(level: ElementID, _ model: BIMModel) -> [ElementID: RoomBoundary] {
        let stamp = SIMD2(model.contentStamp, level.raw)
        lock.lock()
        if let k = stampKeys[stamp], let hit = entries[k] { lock.unlock(); return hit }
        lock.unlock()
        let key = cacheKey(level: level, model)
        lock.lock()
        if stampKeys.count > 256 { stampKeys.removeAll(keepingCapacity: true) }
        stampKeys[stamp] = key
        if let hit = entries[key] { lock.unlock(); return hit }
        lock.unlock()
        let computed = RoomGeometry.boundaries(level: level, model)
        lock.lock()
        entries[key] = computed
        order.append(key)
        if order.count > 64 { entries.removeValue(forKey: order.removeFirst()) }
        lock.unlock()
        return computed
    }

    /// Key from the revisions of every element that can affect rooms on the level.
    func cacheKey(level: ElementID, _ model: BIMModel) -> String {
        var h = Hasher()
        h.combine(level)
        for c: Category in [.walls, .rooms, .areas, .roomSeparationLines, .areaBoundaryLines, .columns, .structuralColumns, .levels, .elementTypes] {
            for e in model.elements(c) { h.combine(e.id); h.combine(e.revision) }
        }
        return "\(level.raw)-\(h.finalize())"
    }

    public func purge() { lock.lock(); entries.removeAll(); order.removeAll(); stampKeys.removeAll(); lock.unlock() }
}

public enum RoomQueries {
    /// The room (bounded) whose boundary contains a plan point on a level.
    public static func room(at p: Vec2, level: ElementID?, _ model: BIMModel) -> Element? {
        guard let level else { return nil }
        let b = RoomBoundaryCache.shared.boundaries(level: level, model)
        for r in model.elements(.rooms) where r.levelID == level {
            if let bd = b[r.id], bd.state == .bounded, bd.profile?.contains(p) == true { return r }
        }
        return nil
    }

    public static func room(containing e: Element, _ model: BIMModel) -> Element? {
        let p: Vec2?
        switch e.data {
        case .component(let c): p = c.location
        case .column(let c): p = c.location
        default: p = nil
        }
        guard let p else { return nil }
        return room(at: p, level: e.levelID, model)
    }

    /// From/To rooms for a door or window: rooms on each side of the host at the insert location.
    public static func roomsAround(insert e: Element, _ model: BIMModel) -> (from: Element?, to: Element?) {
        guard let pl = InsertGeometry.placement(e, model), let host = model[e.hostID], let f = WallGeometry.frame(host, model) else { return (nil, nil) }
        let origin = pl.plan.apply(.zero)
        let facing = pl.plan.applyVector(Vec2(0, 1)).normalized
        let d = f.thickness / 2 + 0.3
        let level = host.levelID
        // "To" is the room the door opens into (opposite the facing side), "From" the facing side.
        return (room(at: origin + facing * d, level: level, model), room(at: origin - facing * d, level: level, model))
    }
}

// MARK: - Enclosed regions and automatic placement

/// An enclosed region on a level that no room (or area) occupies yet.
public struct EnclosedRegion: Sendable {
    public var profile: Profile2
    /// A point well inside the region, used as the placement point.
    public var point: Vec2
    public var area: Double { profile.area }
}

extension RoomGeometry {
    /// The computation height used for rooms on a level (same rule as `boundaries`).
    static func computationZ(level: ElementID, _ model: BIMModel) -> Double {
        model.elevation(ofLevel: level) + max(model[level]?.level?.computationHeight ?? 0, 0.3)
    }

    /// Plan polygons of room-bounding material cut at `z` (walls and columns): faces inside them are not rooms.
    static func boundingMaterial(level: ElementID, atZ z: Double, _ model: BIMModel) -> [Polygon2] {
        var polys: [Polygon2] = []
        for w in model.elements(.walls) where w.wall?.roomBounding == true && w.phaseDemolished == nil {
            guard let f = WallGeometry.frame(w, model), f.baseZ <= z + Tolerance.length, f.topZ >= z - Tolerance.length else { continue }
            if let fp = WallGeometry.footprint(w, model) { polys.append(fp) }
        }
        for c in model.elements(.columns) + model.elements(.structuralColumns) where c.column?.roomBounding == true && c.levelID == level {
            polys.append(contentsOf: ComponentGeometry.planOutline(c, model))
        }
        return polys
    }

    /// Enclosed regions on a level that contain no placed room — or, with `areaScheme`, no area of that scheme.
    /// Regions inside walls or columns and slivers smaller than `minimumArea` are skipped. Sorted top-left first.
    public static func unoccupiedRegions(level: ElementID, _ model: BIMModel, areaScheme: ElementID? = nil, minimumArea: Double = 0.25) -> [EnclosedRegion] {
        let z = areaScheme == nil ? computationZ(level: level, model) : model.elevation(ofLevel: level) + 1
        let arr = PlanarArrangement(segments: boundingSegments(level: level, atZ: z, model, areaScheme: areaScheme))
        guard !arr.faces.isEmpty else { return [] }
        let material = areaScheme == nil ? boundingMaterial(level: level, atZ: z, model) : []
        let materialBounds = material.map(\.bounds)
        var occupied = Set<Int>()
        let placed = areaScheme == nil
            ? model.elements(.rooms).filter { $0.levelID == level && $0.room?.areaSchemeID == nil }
            : model.elements(.areas).filter { $0.levelID == level && $0.room?.areaSchemeID == areaScheme }
        for r in placed {
            if let p = r.room?.point, let i = arr.faceIndex(containing: p) { occupied.insert(i) }
        }
        var out: [EnclosedRegion] = []
        for (i, f) in arr.faces.enumerated() where !occupied.contains(i) && f.area >= minimumArea {
            guard let p = interiorPoint(of: f.profile) else { continue }
            if material.indices.contains(where: { materialBounds[$0].contains(p) && material[$0].contains(p, onBoundary: true) }) { continue }
            // The point must fall in this face, not in a smaller face nested inside it.
            guard arr.faceIndex(containing: p) == i else { continue }
            out.append(EnclosedRegion(profile: f.profile, point: p))
        }
        return out.sorted { a, b in
            let ya = (a.point.y * 10).rounded(), yb = (b.point.y * 10).rounded()
            return ya != yb ? ya > yb : a.point.x < b.point.x
        }
    }

    /// A point comfortably inside a profile: its centroid when that lies inside with clearance, otherwise the
    /// centroid of the largest triangle of its triangulation.
    public static func interiorPoint(of profile: Profile2) -> Vec2? {
        let c = profile.outer.centroid
        if profile.contains(c), profile.loops.allSatisfy({ loop in loop.edges.allSatisfy { $0.distance(to: c) > 0.3 } }) { return c }
        let tri = Triangulator.triangulate(profile)
        var best: Vec2?
        var bestArea = 0.0
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            let a = tri.points[tri.triangles[t]], b = tri.points[tri.triangles[t + 1]], d = tri.points[tri.triangles[t + 2]]
            let ar = (b - a).cross(d - a) * 0.5
            if ar > bestArea { bestArea = ar; best = (a + b + d) / 3 }
        }
        return best
    }
}

/// Automatic room and area placement.
public enum RoomPlacement {
    /// The next free number on a level: numbers run 101, 102… on the first level, 201… on the second.
    public static func nextNumber(level: ElementID?, _ model: BIMModel, areas: Bool = false) -> Int {
        let nums = model.elements(areas ? .areas : .rooms).compactMap { Int($0.room?.number ?? "") }
        let base = (model.levels.firstIndex { $0.id == level } ?? 0) + 1
        return max(nums.filter { $0 / 100 == base }.max().map { $0 + 1 } ?? base * 100 + 1, base * 100 + 1)
    }

    /// Places one room (or area of `areaScheme`) in every enclosed, unoccupied region of a level, numbered from the
    /// level's next free number, and tags each in `tagView` when a tag type is given. Returns the new elements in order.
    @discardableResult
    public static func placeAutomatically(level: ElementID, in tx: TransactionContext, areaScheme: ElementID? = nil,
                                          tagType: ElementID? = nil, tagView: ElementID? = nil) -> [ElementID] {
        let regions = RoomGeometry.unoccupiedRegions(level: level, tx.model, areaScheme: areaScheme)
        var number = nextNumber(level: level, tx.model, areas: areaScheme != nil)
        var created: [ElementID] = []
        for region in regions {
            var rd = RoomData(point: region.point, number: String(number))
            rd.areaSchemeID = areaScheme
            let id = tx.create(areaScheme == nil ? .rooms : .areas, name: areaScheme == nil ? "Room" : "Area", data: .room(rd), levelID: level)
            if let tagType, let tagView {
                tx.create(.tags, data: .tag(TagData(taggedID: id, head: region.point)), typeID: tagType, ownerViewID: tagView)
            }
            created.append(id)
            number += 1
        }
        return created
    }
}
