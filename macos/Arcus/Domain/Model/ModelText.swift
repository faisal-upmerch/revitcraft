import Foundation
import Synchronization
import ArcusGeometry

// F1: Model Text (RevitCraft `crates/rc-core/src/model_text.rs`): 3D text built from font glyph outlines, extruded by
// its depth, lying on its level's work plane or standing upright. The glyphs come from a font outliner installed by the
// app (`ModelTextGlyphs.install`; ArcusOutput's CoreText `GlyphOutliner`), because the Domain layer draws no text.

/// A Model Text element: the text, its font, its capital height and depth, and where it stands.
public struct ModelTextData: Hashable, Codable, Sendable {
    public enum Alignment: String, Codable, Sendable, CaseIterable { case left = "Left", center = "Center", right = "Right" }

    public var text: String
    /// Insertion point: the first baseline's left end, centre or right end (by `alignment`).
    public var position: Vec2
    /// Height of the work plane above the level.
    public var offset: Double
    /// Direction of the text line (radians from the x axis).
    public var rotation: Double
    /// Text Size: the capital height.
    public var size: Double
    /// Extrusion depth.
    public var depth: Double
    public var alignment: Alignment
    /// Text Font (RevitCraft and the reference app use Arial).
    public var fontName: String
    public var materialID: ElementID?
    /// Upright text stands in the vertical plane along its direction and is extruded behind it (signage on a wall);
    /// otherwise it lies on the work plane and is extruded up.
    public var upright: Bool

    public static let defaultFont = "Arial"

    public init(text: String, position: Vec2, size: Double = 0.3, depth: Double = 0.05, offset: Double = 0, rotation: Double = 0,
                alignment: Alignment = .left, fontName: String = ModelTextData.defaultFont, materialID: ElementID? = nil, upright: Bool = false) {
        self.text = text; self.position = position; self.size = size; self.depth = depth; self.offset = offset; self.rotation = rotation
        self.alignment = alignment; self.fontName = fontName; self.materialID = materialID; self.upright = upright
    }

    /// Unit direction of the text line and its left normal.
    public var frame: (dir: Vec2, normal: Vec2) {
        let d = Vec2.fromAngle(rotation)
        return (d, d.perpendicular)
    }
}

extension Element {
    /// F1: the Model Text payload.
    public var modelText: ModelTextData? {
        get { if case .modelText(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .modelText(v) } }
    }
}

// MARK: - Glyph outlines

/// The font outliner seam. The provider returns one line of text as closed contours (curves flattened) in units of the
/// font's capital height, baseline on y = 0 and starting at x = 0, plus the line's advance width.
public enum ModelTextGlyphs {
    public typealias Provider = @Sendable (_ line: String, _ fontName: String) -> (contours: [[Vec2]], advance: Double)

    private struct State {
        var provider: Provider?
        var cache: [String: (contours: [[Vec2]], advance: Double)] = [:]
    }
    private static let state = Mutex(State())

    /// Installs (or, with nil, removes) the outliner. Clears cached outlines.
    public static func install(_ provider: Provider?) {
        state.withLock { $0 = State(provider: provider) }
    }

    public static var isInstalled: Bool { state.withLock { $0.provider != nil } }

    /// Outlines of one line in `fontName`, unit capital height; nil without an outliner.
    static func line(_ s: String, fontName: String) -> (contours: [[Vec2]], advance: Double)? {
        let key = fontName + "\u{1}" + s
        let (hit, provider) = state.withLock { ($0.cache[key], $0.provider) }
        if let hit { return hit }
        guard let provider else { return nil }
        let r = provider(s, fontName)
        state.withLock { st in
            if st.cache.count > 2048 { st.cache.removeAll() }
            st.cache[key] = r
        }
        return r
    }
}

// MARK: - Geometry

public enum ModelTextGeometry {
    /// Line spacing in capital heights (RevitCraft: 1.15 em).
    static let lineSpacing = 1.15 / 0.716

    /// Glyph contours of the text in its local frame (x along the line, y up the text), capitals `size` tall, the first
    /// baseline on y = 0, lines below each other, aligned on x = 0.
    public static func localContours(_ t: ModelTextData) -> [[Vec2]] {
        var out: [[Vec2]] = []
        let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.replacingOccurrences(of: "\r", with: "") }
        for (k, line) in lines.enumerated() where !line.isEmpty {
            guard let g = ModelTextGlyphs.line(line, fontName: t.fontName) else { continue }
            let w = g.advance * t.size
            let x0 = t.alignment == .center ? -w / 2 : t.alignment == .right ? -w : 0
            let y0 = -Double(k) * lineSpacing * t.size
            for c in g.contours where c.count >= 3 { out.append(c.map { Vec2(x0 + $0.x * t.size, y0 + $0.y * t.size) }) }
        }
        return out
    }

    /// Contours grouped into outlines with their holes, by how many other contours enclose each one (RevitCraft `shapes`).
    public static func shapes(_ contours: [[Vec2]]) -> [Profile2] {
        let polys = contours.map { Polygon2($0) }.filter { !$0.isDegenerate }
        let depth = polys.indices.map { i in polys.indices.filter { j in j != i && polys[j].contains(polys[i].points[0], onBoundary: false) }.count }
        var outers = polys.indices.filter { depth[$0] % 2 == 0 }.map { (index: $0, holes: [Polygon2]()) }
        for i in polys.indices where depth[i] % 2 == 1 {
            // The hole belongs to the smallest outline around it.
            let owners = outers.indices.filter { polys[outers[$0].index].contains(polys[i].points[0], onBoundary: false) }
            if let k = owners.min(by: { polys[outers[$0].index].area < polys[outers[$1].index].area }) { outers[k].holes.append(polys[i]) }
        }
        return outers.map { Profile2(outer: polys[$0.index], holes: $0.holes) }
    }

    /// Plan outlines of lying text, placed and rotated (RevitCraft `plan_contours`).
    public static func planContours(_ t: ModelTextData) -> [Polygon2] {
        let (d, n) = t.frame
        return localContours(t).map { Polygon2($0.map { t.position + d * $0.x + n * $0.y }) }
    }

    /// Local bounds of the glyphs (x along the line, y up the text); nil when there are none.
    public static func localBounds(_ t: ModelTextData) -> Rect2? {
        let pts = localContours(t).flatMap { $0 }
        return pts.isEmpty ? nil : Rect2(points: pts)
    }

    /// Elevation of the work plane.
    public static func baseZ(_ e: Element, _ model: BIMModel) -> Double {
        model.elevation(ofLevel: e.levelID) + (e.modelText?.offset ?? 0)
    }

    /// Plan footprint of the text: the glyph outlines for lying text, the extruded strip for upright text.
    public static func planOutlines(_ e: Element) -> [Polygon2] {
        guard let t = e.modelText else { return [] }
        guard t.upright else { return planContours(t) }
        guard let b = localBounds(t) else { return [] }
        let (d, n) = t.frame
        let depth = max(t.depth, 0.001)
        return [Polygon2([t.position + d * b.min.x, t.position + d * b.max.x, t.position + d * b.max.x - n * depth, t.position + d * b.min.x - n * depth]).counterClockwise]
    }

    /// The 3D text: lying on its work plane (extruded up), or upright (extruded behind the text plane).
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let t = e.modelText else { return [] }
        let z0 = baseZ(e, model)
        let depth = max(t.depth, 0.0001)
        let (d, _) = t.frame
        var mesh = Mesh()
        if t.upright {
            // Local x along the line, y up, local +z = d × up (behind the text plane).
            let frame = Transform3.frame(origin: Vec3(t.position.x, t.position.y, z0), xAxis: Vec3(d.x, d.y, 0), yAxis: .unitZ)
            for p in shapes(localContours(t)) { mesh.append(MeshBuilder.extrude(p, frame: frame, depth: depth)) }
        } else {
            for p in shapes(planContours(t).map(\.points)) { mesh.append(MeshBuilder.extrude(p, bottom: z0, top: z0 + depth)) }
        }
        return mesh.isEmpty ? [] : [MeshPart(mesh: mesh, materialID: t.materialID)]
    }
}
