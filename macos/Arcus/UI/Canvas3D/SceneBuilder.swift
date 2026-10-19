import Foundation
import ArcusGeometry
import ArcusDomain

/// Collects the visible model geometry of a 3D view into a `Viewport3DScene`.
nonisolated public enum SceneBuilder {
    /// Off-main-actor friendly (nonisolated): collects visible model elements for a 3D view (VisibilityResolver +
    /// TemporaryVisibility), their meshes (GeometryCache) and material colors; honors section box culling
    /// coarse-grained (GPU clips precisely). Returns `.empty` when `isCancelled` reports true.
    nonisolated public static func build(model: BIMModel, view: Element, temporary: TemporaryVisibility = TemporaryVisibility(),
                                         detail: DetailLevel = .medium, isCancelled: @Sendable () -> Bool = { false }) -> Viewport3DScene {
        let resolver = VisibilityResolver(model: model, view: view, temporary: temporary)
        let data = resolver.data
        let sectionBox: Box3? = (data.sectionBoxActive ? data.sectionBox : nil).flatMap { $0.isEmpty ? nil : $0 }

        // Candidate elements with their overrides (cheap, sequential).
        var candidates: [(Element, GraphicOverride)] = []
        for e in model.allElements where e.category.isModel && !e.isType && e.ownerViewID == nil && ElementMeshes.hasModelGeometry(e) {
            if let o = resolver.resolve(e) { candidates.append((e, o)) }
        }
        if isCancelled() { return .empty }

        // Mesh generation (GeometryCache is thread-safe) in parallel chunks.
        let count = candidates.count
        let results = ResultSlots(count: count)
        let chunk = 32
        let chunks = (count + chunk - 1) / chunk
        let frozen = candidates
        let realistic = data.visualStyle == .realistic // F67
        DispatchQueue.concurrentPerform(iterations: chunks) { c in
            if isCancelled() { return }
            let lo = c * chunk, hi = min(count, lo + chunk)
            for i in lo..<hi {
                let (e, o) = frozen[i]
                results.set(i, element(e, override: o, model: model, detail: detail, sectionBox: sectionBox, realistic: realistic))
            }
        }
        if isCancelled() { return .empty }
        var elements = results.values()
        elements += lineElements(model: model, view: view, resolver: resolver, sectionBox: sectionBox) // S3D2: datums, model lines, 2D CAD
        return Viewport3DScene(elements: elements, modelRevision: model.revision)
    }

    /// Builds one scene element (nil when it has no geometry or lies outside the section box).
    nonisolated static func element(_ e: Element, override o: GraphicOverride, model: BIMModel, detail: DetailLevel, sectionBox: Box3?, realistic: Bool = false) -> SceneElement? {
        let parts = GeometryCache.shared.parts(e, model, detail: detail)
        var out: [ScenePart] = []
        out.reserveCapacity(parts.count)
        var bounds = Box3.empty
        for p in parts where !p.mesh.isEmpty && p.isVisibleIn3D && p.styles.shows(realistic: realistic) { // F67: decal images in Realistic
            var c = p.color ?? color(for: p.materialID, category: e.category, model: model) // F67: linked and point colours
            if let s = o.surfaceColor { c = RGBColor(s.r, s.g, s.b, c.a) }
            if let t = o.transparency { c.a = max(0.05, min(1, 1 - t)) }
            if o.halftone == true { c = c.mixed(with: RGBColor(1, 1, 1, c.a), amount: 0.5) }
            bounds.include(p.mesh.bounds)
            let finish = p.roughness.map { SurfaceFinish(roughness: $0) } ?? model[p.materialID]?.material.map { SurfaceFinish.typical(for: $0.materialClass) } ?? .matte // F67
            out.append(ScenePart(mesh: p.mesh, color: c, finish: finish))
        }
        guard !out.isEmpty, !bounds.isEmpty else { return nil }
        if let sb = sectionBox, !sb.intersects(bounds) { return nil }
        return SceneElement(id: e.id, category: e.category, parts: out, bounds: bounds)
    }

    /// Material color with alpha = 1 - transparency; category default when the material is missing.
    nonisolated public static func color(for materialID: ElementID?, category: ArcusDomain.Category, model: BIMModel) -> RGBColor {
        if let m = model[materialID]?.material {
            var c = m.color
            c.a = max(0.05, min(1, 1 - m.transparency))
            return c
        }
        return ElementMeshes.defaultColor(category)
    }
}

/// Lock-protected result slots for the parallel mesh gather.
nonisolated private final class ResultSlots: @unchecked Sendable {
    private var slots: [SceneElement?]
    private let lock = NSLock()
    init(count: Int) { slots = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ v: SceneElement?) { lock.lock(); slots[i] = v; lock.unlock() }
    func values() -> [SceneElement] { lock.lock(); defer { lock.unlock() }; return slots.compactMap { $0 } }
}
