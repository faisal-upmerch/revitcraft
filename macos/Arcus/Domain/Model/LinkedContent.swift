import Foundation
import ArcusGeometry

// F67: Insert tab content: linked models (Arcus projects, IFC, coordination models), point clouds, decals and DWF
// markups. Links keep the last content they read, so a project shows them even when the source is missing; the
// source is re-read when the project opens and on Reload (Manage Links).

/// A file a link reads. `bookmark` is a security-scoped bookmark when one could be made.
public struct ExternalFileRef: Hashable, Codable, Sendable {
    public var path: String
    public var name: String
    public var bookmark: Data?
    /// Modification date of the source when it was last read (a reload on open skips unchanged sources).
    public var sourceModified: Date?
    public var lastLoaded: Date?
    public init(path: String, name: String? = nil, bookmark: Data? = nil, sourceModified: Date? = nil, lastLoaded: Date? = nil) {
        self.path = path; self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.bookmark = bookmark; self.sourceModified = sourceModified; self.lastLoaded = lastLoaded
    }
}

/// A mesh stored compactly (Float32 positions and normals, UInt32 indices and feature edges, LZFSE-compressed).
public struct PackedMesh: Hashable, Codable, Sendable {
    public var vertexCount: Int
    public var triangleCount: Int
    public var blob: Data

    public init(_ m: Mesh) {
        vertexCount = m.positions.count
        triangleCount = m.indices.count / 3
        var raw = Data()
        raw.reserveCapacity(16 + m.positions.count * 24 + (m.indices.count + m.featureEdges.count) * 4)
        func put(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { raw.append(contentsOf: $0) } }
        func putF(_ v: Double) { put(Float(v).bitPattern) }
        put(UInt32(m.positions.count)); put(UInt32(m.indices.count)); put(UInt32(m.featureEdges.count))
        put(m.normals.count == m.positions.count ? 1 : 0)
        for p in m.positions { putF(p.x); putF(p.y); putF(p.z) }
        if m.normals.count == m.positions.count { for n in m.normals { putF(n.x); putF(n.y); putF(n.z) } }
        for i in m.indices { put(i) }
        for i in m.featureEdges { put(i) }
        blob = Packing.compress(raw)
    }

    /// The mesh (empty when the blob is damaged).
    public var mesh: Mesh {
        guard let raw = Packing.decompress(blob), raw.count >= 16 else { return Mesh() }
        return raw.withUnsafeBytes { (b: UnsafeRawBufferPointer) -> Mesh in
            var o = 0
            func u() -> UInt32? { guard o + 4 <= b.count else { return nil }; defer { o += 4 }; return UInt32(littleEndian: b.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            func f() -> Double { Double(Float(bitPattern: u() ?? 0)) }
            guard let nv = u(), let ni = u(), let ne = u(), let hasN = u() else { return Mesh() }
            let need = 16 + Int(nv) * (hasN == 1 ? 24 : 12) + Int(ni + ne) * 4
            guard need <= b.count else { return Mesh() }
            var m = Mesh()
            m.positions.reserveCapacity(Int(nv))
            for _ in 0..<nv { m.positions.append(Vec3(f(), f(), f())) }
            if hasN == 1 { for _ in 0..<nv { m.normals.append(Vec3(f(), f(), f())) } }
            for _ in 0..<ni { m.indices.append(u() ?? 0) }
            for _ in 0..<ne { m.featureEdges.append(u() ?? 0) }
            let n = UInt32(nv)
            if m.indices.contains(where: { $0 >= n }) || m.featureEdges.contains(where: { $0 >= n }) { return Mesh() }
            if m.normals.isEmpty { m.normals = Packing.flatNormals(m) }
            return m
        }
    }
}

/// Compression helpers for packed link content.
public enum Packing {
    public static func compress(_ d: Data) -> Data {
        guard !d.isEmpty, let c = try? (d as NSData).compressed(using: .lzfse) as Data else { return Data([0]) + d }
        return Data([1]) + c
    }
    public static func decompress(_ d: Data) -> Data? {
        guard let flag = d.first else { return nil }
        let body = d.dropFirst()
        if flag == 0 { return Data(body) }
        return try? (Data(body) as NSData).decompressed(using: .lzfse) as Data
    }
    static func flatNormals(_ m: Mesh) -> [Vec3] {
        var normals = [Vec3](repeating: .unitZ, count: m.positions.count)
        for i in stride(from: 0, to: m.indices.count - 2, by: 3) {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            let n = (b - a).cross(c - a).normalized
            for k in 0..<3 { normals[Int(m.indices[i + k])] = n }
        }
        return normals
    }
}

/// Where linked content comes from.
public enum LinkedModelFormat: String, Codable, Sendable, CaseIterable {
    /// Another Arcus project (Link Model).
    case arcus = "Arcus"
    case ifc = "IFC"
    /// A coordination model: an OBJ mesh shown in 3D views.
    case obj = "OBJ"
}

/// One element of a linked model, as display geometry in the link's own coordinates.
public struct LinkedModelPart: Hashable, Codable, Sendable {
    /// Category in the linked model (drives line styles and cut patterns in the host's views).
    public var category: Category
    public var name: String
    public var color: RGBColor
    public var mesh: PackedMesh
    public init(category: Category, name: String, color: RGBColor, mesh: Mesh) {
        self.category = category; self.name = name; self.color = color; self.mesh = PackedMesh(mesh)
    }
}

/// Insert ▸ Link Model / Link IFC / Coordination Model: another model shown read-only, placed internal origin to
/// internal origin (`placement` is identity until the link is moved).
public struct LinkedModelData: Hashable, Codable, Sendable {
    public var format: LinkedModelFormat
    public var source: ExternalFileRef
    public var placement: Transform2
    public var elevationOffset: Double
    /// Unloaded links stay in the project but are not drawn.
    public var isLoaded: Bool
    public var parts: [LinkedModelPart]
    /// Number of model elements read from the source (some have no geometry).
    public var elementCount: Int
    public init(format: LinkedModelFormat, source: ExternalFileRef, parts: [LinkedModelPart], elementCount: Int) {
        self.format = format; self.source = source; self.placement = .identity; self.elevationOffset = 0; self.isLoaded = true
        self.parts = parts; self.elementCount = elementCount
    }
    /// Link coordinates to host coordinates.
    public var transform: Transform3 { Transform3.translation(Vec3(0, 0, elevationOffset)) * Transform3(placement) }
}

/// Points stored compactly: Float32 x, y, z and 8-bit r, g, b per point, LZFSE-compressed.
public struct PackedPoints: Hashable, Codable, Sendable {
    public var count: Int
    public var blob: Data
    public init(_ pts: [(Vec3, (UInt8, UInt8, UInt8))]) {
        count = pts.count
        var raw = Data()
        raw.reserveCapacity(pts.count * 15)
        for (p, c) in pts {
            for v in [p.x, p.y, p.z] { var x = Float(v).bitPattern.littleEndian; withUnsafeBytes(of: &x) { raw.append(contentsOf: $0) } }
            raw.append(contentsOf: [c.0, c.1, c.2])
        }
        blob = Packing.compress(raw)
    }
    public var points: [(position: Vec3, color: RGBColor)] {
        guard let raw = Packing.decompress(blob) else { return [] }
        return raw.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            var out: [(position: Vec3, color: RGBColor)] = []
            out.reserveCapacity(b.count / 15)
            var o = 0
            func f(_ k: Int) -> Double { Double(Float(bitPattern: UInt32(littleEndian: b.loadUnaligned(fromByteOffset: k, as: UInt32.self)))) }
            while o + 15 <= b.count {
                out.append((Vec3(f(o), f(o + 4), f(o + 8)), RGBColor(Double(b[o + 12]) / 255, Double(b[o + 13]) / 255, Double(b[o + 14]) / 255)))
                o += 15
            }
            return out
        }
    }
}

/// Insert ▸ Point Cloud: survey points shown as points in 3D and plan views, decimated evenly on import.
public struct PointCloudData: Hashable, Codable, Sendable {
    public var source: ExternalFileRef
    public var placement: Transform2
    public var elevationOffset: Double
    public var isLoaded: Bool
    public var points: PackedPoints
    /// Points in the source file (before thinning).
    public var sourceCount: Int
    /// False when the file has no colours (points draw in the category colour).
    public var hasColor: Bool
    /// Length unit factor used when reading (meters per file unit), kept for reloads.
    public var unitScale: Double
    public init(source: ExternalFileRef, points: [(Vec3, (UInt8, UInt8, UInt8))], sourceCount: Int, hasColor: Bool, unitScale: Double) {
        self.source = source; self.placement = .identity; self.elevationOffset = 0; self.isLoaded = true
        self.points = PackedPoints(points); self.sourceCount = sourceCount; self.hasColor = hasColor; self.unitScale = unitScale
    }
    public var transform: Transform3 { Transform3.translation(Vec3(0, 0, elevationOffset)) * Transform3(placement) }
}

/// Decal finish (RevitCraft's list).
public enum DecalFinish: String, Codable, Sendable, CaseIterable {
    case matte = "Matte", semiGloss = "Semi-gloss", gloss = "Gloss", highGloss = "High Gloss"
}

/// A decal type (Decal Types dialog): the image and how it renders.
public struct DecalTypeData: Hashable, Codable, Sendable {
    /// PNG (or JPEG) bytes of the image; empty until an image is chosen.
    public var image: Data
    public var imageName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// 0…10, 1 = as in the image.
    public var brightness: Double
    /// 0…1.
    public var reflectivity: Double
    /// 0…1.
    public var transparency: Double
    public var finish: DecalFinish
    /// Luminance preset name ("Not illuminated", "LCD screen"…).
    public var luminance: String
    /// 0…1.
    public var bumpAmount: Double
    /// Image file cutout: transparent pixels of the image are left out.
    public var cutout: Bool
    public init(image: Data = Data(), imageName: String = "", pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.image = image; self.imageName = imageName; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        brightness = 1; reflectivity = 0; transparency = 0; finish = .matte; luminance = "Not illuminated"; bumpAmount = 0; cutout = false
    }
    public static let luminancePresets = ["Not illuminated", "Dim glow", "LED panel", "LCD screen", "Cell phone screen", "CRT television",
                                          "Lamp shade exterior", "Lamp shade interior", "Desk lamp lens", "Halogen lamp lens", "Frosted bulb"]

    /// The image as a coarse grid of colours for display (filled in by the UI layer, which can decode images).
    public var swatch: DecalSwatch?
}

/// A decal image reduced to a grid of colours (row-major, bottom row first; alpha 0 = cut out).
public struct DecalSwatch: Hashable, Codable, Sendable {
    public var columns: Int
    public var rows: Int
    /// RGBA bytes, `columns * rows * 4`.
    public var rgba: Data
    public init(columns: Int, rows: Int, rgba: Data) { self.columns = columns; self.rows = rows; self.rgba = rgba }
    public func color(_ col: Int, _ row: Int) -> (RGBColor, alpha: Double) {
        let i = (row * columns + col) * 4
        guard i + 3 < rgba.count else { return (.gray, 1) }
        return (RGBColor(Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255), Double(rgba[i + 3]) / 255)
    }
}

/// Insert ▸ Decal: an image on a planar face of the model (the element's `hostID`). Shown as an outline with a cross
/// in 2D views and in the non-realistic 3D styles; the image shows in the Realistic visual style.
public struct DecalData: Hashable, Codable, Sendable {
    public var decalTypeID: ElementID
    public var center: Vec3
    /// Out of the face.
    public var normal: Vec3
    /// The image's up direction, in the face.
    public var up: Vec3
    public var width: Double
    public var height: Double
    public init(decalTypeID: ElementID, center: Vec3, normal: Vec3, up: Vec3, width: Double, height: Double) {
        self.decalTypeID = decalTypeID; self.center = center; self.normal = normal; self.up = up; self.width = width; self.height = height
    }
    public var right: Vec3 { up.cross(normal).normalized }
    /// Bottom left, bottom right, top right, top left (seen from the front), lifted `lift` off the face.
    public func corners(lift: Double = 0) -> [Vec3] {
        let r = right * (width / 2), u = up.normalized * (height / 2), c = center + normal.normalized * lift
        return [c - r - u, c + r - u, c + r + u, c - r + u]
    }
}

/// One marked-up page of a DWFx file, placed on a sheet (paper meters from the sheet's bottom left).
public struct MarkupData: Hashable, Codable, Sendable {
    public struct Polyline: Hashable, Codable, Sendable {
        public var points: [Vec2]
        public var color: RGBColor
        public var filled: Bool
        public init(points: [Vec2], color: RGBColor, filled: Bool = false) { self.points = points; self.color = color; self.filled = filled }
    }
    public struct Text: Hashable, Codable, Sendable {
        public var position: Vec2
        public var string: String
        /// Paper meters.
        public var height: Double
        public var color: RGBColor
        public init(position: Vec2, string: String, height: Double, color: RGBColor = RGBColor(1, 0, 0)) {
            self.position = position; self.string = string; self.height = height; self.color = color
        }
    }
    /// A picture on the page: its bounds on paper and the image bytes (PNG/JPEG).
    public struct Picture: Hashable, Codable, Sendable {
        public var bounds: Rect2
        public var image: Data
        public init(bounds: Rect2, image: Data) { self.bounds = bounds; self.image = image }
    }
    public var source: ExternalFileRef
    /// Page name inside the DWFx package (used to find the page again on reload).
    public var pageName: String
    public var pageSize: Vec2
    public var offset: Vec2
    public var isLoaded: Bool
    public var polylines: [Polyline]
    public var texts: [Text]
    public var pictures: [Picture]
    public init(source: ExternalFileRef, pageName: String, pageSize: Vec2, polylines: [Polyline], texts: [Text], pictures: [Picture]) {
        self.source = source; self.pageName = pageName; self.pageSize = pageSize; self.offset = .zero; self.isLoaded = true
        self.polylines = polylines; self.texts = texts; self.pictures = pictures
    }
}

// MARK: - Accessors

extension Element {
    public var linkedModel: LinkedModelData? {
        get { if case .linkedModel(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .linkedModel(v) } }
    }
    public var pointCloud: PointCloudData? {
        get { if case .pointCloud(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .pointCloud(v) } }
    }
    public var decal: DecalData? {
        get { if case .decal(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .decal(v) } }
    }
    public var decalType: DecalTypeData? {
        get { if case .decalType(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .decalType(v) } }
    }
    public var markup: MarkupData? {
        get { if case .markup(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .markup(v) } }
    }
    /// The file an F67 link reads (linked models, point clouds, DWF markups, linked topography), or nil.
    public var f67LinkSource: ExternalFileRef? {
        switch data {
        case .linkedModel(let l): l.source
        case .pointCloud(let p): p.source
        case .markup(let m): m.source
        default: TopographyLink.source(of: self)
        }
    }
}

/// Insert ▸ Link Topography: a toposolid whose points come from a survey file. The link is kept in the element's
/// source metadata (format "Topography Link"), so the toposolid stays an ordinary toposolid.
public enum TopographyLink {
    public static let originalType = "Topography Link"
    static let pathKey = "link.path", nameKey = "link.name", scaleKey = "link.unitScale", modifiedKey = "link.modified", bookmarkKey = "link.bookmark"

    public static func isLinked(_ e: Element) -> Bool { e.topography != nil && e.source?.originalType == originalType }

    public static func source(of e: Element) -> ExternalFileRef? {
        guard isLinked(e), let a = e.source?.attributes, let path = a[pathKey] else { return nil }
        return ExternalFileRef(path: path, name: a[nameKey], bookmark: a[bookmarkKey].flatMap { Data(base64Encoded: $0) },
                               sourceModified: a[modifiedKey].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) })
    }
    public static func unitScale(of e: Element) -> Double { e.source?.attributes[scaleKey].flatMap(Double.init) ?? 1 }

    public static func metadata(_ f: ExternalFileRef, unitScale: Double) -> SourceMetadata {
        var a = [pathKey: f.path, nameKey: f.name, scaleKey: String(unitScale)]
        if let m = f.sourceModified { a[modifiedKey] = String(m.timeIntervalSince1970) }
        if let b = f.bookmark { a[bookmarkKey] = b.base64EncodedString() }
        return SourceMetadata(format: "XYZ", fileName: f.name, originalID: "", originalType: originalType, attributes: a)
    }
}
