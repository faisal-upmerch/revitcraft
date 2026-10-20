import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusViewport3D

// FMG4: a piece dragged from Finder over a 3D view shows where it will land before it's dropped (its box on the work
// plane, named, with its size), as a component being placed does; the drop places it there, on the view's work plane.

/// The piece being dragged over a 3D view: its size (a box round its origin: Width × Depth centred, Height up) and
/// where it would land now.
struct DropPreview3D {
    var url: URL
    var name: String
    var box: Box3
    var at: Vec3?
}

extension Viewport3DToolController {
    /// The level a drop places on and the work plane it lands on (nil: the level).
    var dropTarget: (level: ElementID?, plane: WorkPlaneFrame?) {
        let level = workPlaneLevel ?? state.model.levels.first?.id
        return (level, activeSketchPlane?.frame)
    }

    /// Where a drop at a view point lands: the plan point and its elevation from the level.
    func dropPlacement(at point: CGPoint) -> (point: Vec2, offset: Double)? {
        guard let v = viewport else { return nil }
        let (level, plane) = dropTarget
        let ray = v.pointerRay(at: point)
        let hit = v.pick(at: point)
        let s = WorkPlane3D.PointerSample(origin: ray.origin, direction: ray.direction, pickedID: hit.id, pickedPoint: hit.position)
        return WorkPlane3D.dropPlacement(s, workPlane: plane, levelZ: state.model.elevation(ofLevel: level))
    }

    func viewport3DDragMoved(_ urls: [URL], at point: CGPoint?) {
        defer { overlay.needsDisplay = true }
        guard let point, let url = urls.first(where: { [FurnitureLibraryCatalog.fileExtension, FamilyPackage.fileExtension].contains($0.pathExtension.lowercased()) }) else {
            dropPreview = nil
            return
        }
        if dropPreview?.url != url {
            guard let p = Self.preview(url) else { dropPreview = nil; return }
            dropPreview = p
        }
        let (level, _) = dropTarget
        dropPreview?.at = dropPlacement(at: point).map { Vec3($0.point, z: state.model.elevation(ofLevel: level) + $0.offset) }
    }

    /// The preview of a file: a furniture piece's current type size, or a family's evaluated bounds.
    static func preview(_ url: URL) -> DropPreview3D? {
        let name = url.deletingPathExtension().lastPathComponent
        if url.pathExtension.lowercased() == FurnitureLibraryCatalog.fileExtension {
            guard let m = try? ArcusPackage.read(from: url).model, m.isFurniture else { return nil }
            func value(_ n: String) -> Double {
                if case .quantity(let v, _)? = FurnitureParameters.value(n, m) { return v }
                return 0.6
            }
            let w = value("Width"), d = value("Depth"), h = value("Height")
            return DropPreview3D(url: url, name: name, box: Box3(min: Vec3(-w / 2, -d / 2, 0), max: Vec3(w / 2, d / 2, h)), at: nil)
        }
        guard let (f, _, _) = try? FamilyPackage.read(from: url) else { return nil }
        let ev = FamilyEvaluator.evaluate(f, typeName: f.types.first?.name ?? "", units: .imperial)
        let b = ev.solids.filter { !$0.isVoid }.reduce(Box3.empty) { $0.union($1.bounds) }
        guard !b.isEmpty else { return nil }
        return DropPreview3D(url: url, name: name, box: b, at: nil)
    }

    /// Draws the dragged piece's box where it would land, with its name and size.
    func drawDropPreview(_ cg: CGContext, viewport v: Viewport3DView) {
        guard let p = dropPreview, let at = p.at else { return }
        let b = p.box
        func c(_ x: Double, _ y: Double, _ z: Double) -> Vec3 { at + Vec3(x, y, z) }
        let lo = b.min, hi = b.max
        let corners = [c(lo.x, lo.y, lo.z), c(hi.x, lo.y, lo.z), c(hi.x, hi.y, lo.z), c(lo.x, hi.y, lo.z),
                       c(lo.x, lo.y, hi.z), c(hi.x, lo.y, hi.z), c(hi.x, hi.y, hi.z), c(lo.x, hi.y, hi.z)]
        let edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        cg.saveGState()
        // The footprint on the plane, filled lightly; the box's edges.
        let foot = corners[0..<4].compactMap { v.viewPoint(of: $0) }
        if foot.count == 4 {
            cg.setFillColor(Tokens.selection.withAlphaComponent(0.16).cgColor)
            cg.addLines(between: foot); cg.closePath(); cg.fillPath()
        }
        cg.setStrokeColor(Tokens.selection.cgColor)
        cg.setLineWidth(1.5)
        for (i, j) in edges { if let (a, b) = v.viewSegment(corners[i], corners[j]) { cg.move(to: a); cg.addLine(to: b) } }
        cg.strokePath()
        cg.restoreGState()
        // The name and size by the box's top.
        guard let top = v.viewPoint(of: c((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z)) else { return }
        let size = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z].map { Parameters.format(.double($0), type: .length, model: state.model) }.joined(separator: " × ")
        let text = "\(p.name)  \(size)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
        let s = text.size(withAttributes: attrs)
        let box = NSRect(x: top.x - s.width / 2 - 6, y: top.y + 8, width: s.width + 12, height: s.height + 4)
        cg.saveGState()
        cg.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor)
        cg.fill(box)
        cg.restoreGState()
        text.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attrs)
    }
}
