import Foundation
import ArcusGeometry
import ArcusDomain

// MARK: - Units

/// Drawing units as stored in the `$INSUNITS` header variable (DXF/DWG "insertion units").
public enum CADUnits: Int, Sendable, CaseIterable, Codable {
    case unitless = 0, inches = 1, feet = 2, miles = 3, millimeters = 4, centimeters = 5, meters = 6, kilometers = 7
    case microinches = 8, mils = 9, yards = 10, angstroms = 11, nanometers = 12, microns = 13, decimeters = 14
    case decameters = 15, hectometers = 16, gigameters = 17, astronomicalUnits = 18, lightYears = 19, parsecs = 20
    case usSurveyFeet = 21, usSurveyInches = 22, usSurveyYards = 23, usSurveyMiles = 24

    /// Meters per drawing unit. `unitless` drawings are interpreted as millimeters (the importer reports a warning).
    public var metersPerUnit: Double {
        switch self {
        case .unitless: 0.001
        case .inches: 0.0254
        case .feet: 0.3048
        case .miles: 1609.344
        case .millimeters: 0.001
        case .centimeters: 0.01
        case .meters: 1
        case .kilometers: 1000
        case .microinches: 2.54e-8
        case .mils: 2.54e-5
        case .yards: 0.9144
        case .angstroms: 1e-10
        case .nanometers: 1e-9
        case .microns: 1e-6
        case .decimeters: 0.1
        case .decameters: 10
        case .hectometers: 100
        case .gigameters: 1e9
        case .astronomicalUnits: 1.495978707e11
        case .lightYears: 9.4607304725808e15
        case .parsecs: 3.0856775814913673e16
        case .usSurveyFeet: 1200.0 / 3937.0
        case .usSurveyInches: 100.0 / 3937.0
        case .usSurveyYards: 3600.0 / 3937.0
        case .usSurveyMiles: 6_336_000.0 / 3937.0
        }
    }

    public var displayName: String {
        switch self {
        case .unitless: "Unitless"
        case .inches: "Inches"
        case .feet: "Feet"
        case .miles: "Miles"
        case .millimeters: "Millimeters"
        case .centimeters: "Centimeters"
        case .meters: "Meters"
        case .kilometers: "Kilometers"
        case .microinches: "Microinches"
        case .mils: "Mils"
        case .yards: "Yards"
        case .angstroms: "Angstroms"
        case .nanometers: "Nanometers"
        case .microns: "Microns"
        case .decimeters: "Decimeters"
        case .decameters: "Decameters"
        case .hectometers: "Hectometers"
        case .gigameters: "Gigameters"
        case .astronomicalUnits: "Astronomical Units"
        case .lightYears: "Light Years"
        case .parsecs: "Parsecs"
        case .usSurveyFeet: "US Survey Feet"
        case .usSurveyInches: "US Survey Inches"
        case .usSurveyYards: "US Survey Yards"
        case .usSurveyMiles: "US Survey Miles"
        }
    }
}

// MARK: - Colors

/// AutoCAD Color Index (ACI) palette and helpers.
public enum ACIColor {
    /// RGB for ACI 1…255 (index 0 = ByBlock and 256 = ByLayer are not colors). Index 7 is black/white; we use black on paper.
    public static func rgb(_ index: Int) -> RGBColor {
        let i = abs(index)
        switch i {
        case 1: return RGBColor(1, 0, 0)
        case 2: return RGBColor(1, 1, 0)
        case 3: return RGBColor(0, 1, 0)
        case 4: return RGBColor(0, 1, 1)
        case 5: return RGBColor(0, 0, 1)
        case 6: return RGBColor(1, 0, 1)
        case 7, 0, 256: return .black
        case 8: return RGBColor(hex: 0x808080)
        case 9: return RGBColor(hex: 0xC0C0C0)
        case 250...255:
            let v = [0x33, 0x50, 0x69, 0x82, 0xBE, 0xFF][i - 250]
            return RGBColor(Double(v) / 255, Double(v) / 255, Double(v) / 255)
        case 10...249:
            // Standard ACI hue wheel: 24 hues × 10 shades (even: full saturation, odd: tinted).
            let hueIndex = (i - 10) / 10
            let shade = (i - 10) % 10
            let hue = Double(hueIndex) * 15.0 / 360.0
            let values: [Double] = [1.0, 1.0, 0.8, 0.8, 0.6, 0.6, 0.5, 0.5, 0.3, 0.3]
            let sat: Double = shade % 2 == 0 ? 1.0 : 0.5
            return hsv(hue, sat, values[shade])
        default: return .black
        }
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGBColor {
        let hh = (h - floor(h)) * 6
        let i = Int(hh) % 6
        let f = hh - floor(hh)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGBColor(v, t, p)
        case 1: return RGBColor(q, v, p)
        case 2: return RGBColor(p, v, t)
        case 3: return RGBColor(p, q, v)
        case 4: return RGBColor(t, p, v)
        default: return RGBColor(v, p, q)
        }
    }

    /// Nearest ACI index (1…255) for an RGB color. Black maps to 7 (black/white).
    public static func nearest(_ c: RGBColor) -> Int {
        if c.r < 0.02 && c.g < 0.02 && c.b < 0.02 { return 7 }
        var best = 7, bestD = Double.infinity
        for i in 1...255 where i != 7 {
            let p = rgb(i)
            let d = (p.r - c.r) * (p.r - c.r) + (p.g - c.g) * (p.g - c.g) + (p.b - c.b) * (p.b - c.b)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Decodes a DXF true color (group 420: 0x00RRGGBB).
    public static func trueColor(_ v: Int) -> RGBColor { RGBColor(hex: UInt32(truncatingIfNeeded: v) & 0xFFFFFF) }
    public static func trueColorValue(_ c: RGBColor) -> Int {
        func b(_ x: Double) -> Int { max(0, min(255, Int((x * 255).rounded()))) }
        return (b(c.r) << 16) | (b(c.g) << 8) | b(c.b)
    }
}

/// Entity color as stored in CAD data.
public enum CADColor: Sendable, Hashable {
    case byLayer
    case byBlock
    case index(Int)
    case rgb(RGBColor)

    /// Resolved color, or nil when it depends on the layer/block.
    public var resolved: RGBColor? {
        switch self {
        case .byLayer, .byBlock: nil
        case .index(let i): ACIColor.rgb(i)
        case .rgb(let c): c
        }
    }
}

// MARK: - Tables

public struct CADLayer: Sendable, Hashable {
    public var name: String
    public var colorIndex: Int
    public var trueColor: RGBColor?
    public var lineType: String
    /// Line weight in millimeters; nil = default.
    public var lineWeight: Double?
    public var isOn: Bool
    public var isFrozen: Bool
    public var isLocked: Bool
    public var plots: Bool

    public init(name: String, colorIndex: Int = 7, trueColor: RGBColor? = nil, lineType: String = "Continuous", lineWeight: Double? = nil,
                isOn: Bool = true, isFrozen: Bool = false, isLocked: Bool = false, plots: Bool = true) {
        self.name = name; self.colorIndex = colorIndex; self.trueColor = trueColor; self.lineType = lineType; self.lineWeight = lineWeight
        self.isOn = isOn; self.isFrozen = isFrozen; self.isLocked = isLocked; self.plots = plots
    }

    /// Display color: true color if set, otherwise the ACI color.
    public var color: RGBColor { trueColor ?? ACIColor.rgb(colorIndex) }
}

public struct CADLineType: Sendable, Hashable {
    public var name: String
    public var description: String
    /// Dash pattern in drawing units (positive = dash, negative = gap, 0 = dot).
    public var pattern: [Double]
    public init(name: String, description: String = "", pattern: [Double] = []) { self.name = name; self.description = description; self.pattern = pattern }
}

public struct CADTextStyle: Sendable, Hashable {
    public var name: String
    public var fontFile: String
    public var bigFontFile: String
    public var isShapeFile: Bool
    public init(name: String, fontFile: String, bigFontFile: String = "", isShapeFile: Bool = false) {
        self.name = name; self.fontFile = fontFile; self.bigFontFile = bigFontFile; self.isShapeFile = isShapeFile
    }
    /// SHX (compiled shape) fonts are AutoCAD-specific; Arcus substitutes a system font.
    public var isSHX: Bool {
        let f = fontFile.lowercased()
        return f.hasSuffix(".shx") || (!f.isEmpty && !f.contains(".") && !f.hasSuffix(".ttf"))
    }
}

// MARK: - Entities

/// Properties common to every CAD entity.
public struct CADEntityProps: Sendable, Hashable {
    /// Source handle (hex string, group 5). Empty when the file has no handles (some R12 files).
    public var handle: String
    public var layer: String
    public var color: CADColor
    /// nil = BYLAYER.
    public var lineType: String?
    /// Millimeters; nil = BYLAYER/default.
    public var lineWeight: Double?
    /// Lineweight explicitly BYBLOCK.
    public var lineWeightByBlock: Bool
    public var paperSpace: Bool
    /// Owner block record handle (group 330), when present.
    public var owner: String
    public init(handle: String = "", layer: String = "0", color: CADColor = .byLayer, lineType: String? = nil, lineWeight: Double? = nil,
                lineWeightByBlock: Bool = false, paperSpace: Bool = false, owner: String = "") {
        self.handle = handle; self.layer = layer; self.color = color; self.lineType = lineType; self.lineWeight = lineWeight
        self.lineWeightByBlock = lineWeightByBlock; self.paperSpace = paperSpace; self.owner = owner
    }
}

public struct CADPolyline: Sendable, Hashable {
    /// Vertices in WCS (z kept for 3D polylines).
    public var points: [Vec3]
    /// Bulge per vertex (tan(sweep/4) of the segment starting at that vertex); empty or all 0 = straight.
    public var bulges: [Double]
    public var closed: Bool
    public var is3D: Bool
    /// Polyface / polygon mesh faces (vertex indices into `points`); empty for ordinary polylines.
    public var meshFaces: [[Int]]
    public var constantWidth: Double
    public init(points: [Vec3], bulges: [Double] = [], closed: Bool = false, is3D: Bool = false, meshFaces: [[Int]] = [], constantWidth: Double = 0) {
        self.points = points; self.bulges = bulges; self.closed = closed; self.is3D = is3D; self.meshFaces = meshFaces; self.constantWidth = constantWidth
    }
    public var isMesh: Bool { !meshFaces.isEmpty }
    public var hasBulges: Bool { bulges.contains { $0 != 0 } }
    public func bulge(at i: Int) -> Double { i < bulges.count ? bulges[i] : 0 }
    public var points2D: [Vec2] { points.map(\.xy) }
}

public enum CADHorizontalAlignment: Int, Sendable, Hashable { case left = 0, center = 1, right = 2, aligned = 3, middle = 4, fit = 5 }
public enum CADVerticalAlignment: Int, Sendable, Hashable { case baseline = 0, bottom = 1, middle = 2, top = 3 }

public struct CADText: Sendable, Hashable {
    /// Decoded display text (control codes such as %%d translated).
    public var text: String
    /// First alignment point (insertion point).
    public var position: Vec2
    /// Second alignment point (used when the alignment is not left/baseline).
    public var alignmentPoint: Vec2?
    public var height: Double
    /// Radians, counter-clockwise.
    public var rotation: Double
    public var widthFactor: Double
    public var style: String
    public var horizontal: CADHorizontalAlignment
    public var vertical: CADVerticalAlignment
    public init(text: String, position: Vec2, alignmentPoint: Vec2? = nil, height: Double, rotation: Double = 0, widthFactor: Double = 1,
                style: String = "Standard", horizontal: CADHorizontalAlignment = .left, vertical: CADVerticalAlignment = .baseline) {
        self.text = text; self.position = position; self.alignmentPoint = alignmentPoint; self.height = height; self.rotation = rotation
        self.widthFactor = widthFactor; self.style = style; self.horizontal = horizontal; self.vertical = vertical
    }
}

public struct CADMText: Sendable, Hashable {
    /// Raw MTEXT content including format codes.
    public var rawText: String
    /// Text with format codes stripped; paragraphs separated by "\n".
    public var plainText: String
    public var position: Vec2
    public var height: Double
    /// Reference rectangle width (wrap width); 0 = no wrapping.
    public var width: Double
    public var rotation: Double
    /// Attachment point 1…9 (1 = top left … 9 = bottom right).
    public var attachment: Int
    public var style: String
    public var lineSpacingFactor: Double
    public init(rawText: String, plainText: String, position: Vec2, height: Double, width: Double = 0, rotation: Double = 0, attachment: Int = 1,
                style: String = "Standard", lineSpacingFactor: Double = 1) {
        self.rawText = rawText; self.plainText = plainText; self.position = position; self.height = height; self.width = width
        self.rotation = rotation; self.attachment = attachment; self.style = style; self.lineSpacingFactor = lineSpacingFactor
    }
}

public enum CADHatchEdge: Sendable, Hashable {
    case line(Vec2, Vec2)
    /// Angles in radians as traversed: counter-clockwise when `ccw`, otherwise clockwise from start to end.
    case arc(center: Vec2, radius: Double, start: Double, end: Double, ccw: Bool)
    /// Elliptical arc: ellipse (params) traversed ccw or cw.
    case ellipse(Ellipse2, ccw: Bool)
    case spline(BSpline2)
    /// Polyline boundary with bulges.
    case polyline([Vec2], bulges: [Double], closed: Bool)
}

public struct CADHatch: Sendable, Hashable {
    public var loops: [[CADHatchEdge]]
    public var isSolid: Bool
    public var patternName: String
    public var patternAngle: Double
    public var patternScale: Double
    public init(loops: [[CADHatchEdge]], isSolid: Bool, patternName: String, patternAngle: Double = 0, patternScale: Double = 1) {
        self.loops = loops; self.isSolid = isSolid; self.patternName = patternName; self.patternAngle = patternAngle; self.patternScale = patternScale
    }
}

public struct CADAttribute: Sendable, Hashable {
    public var tag: String
    public var text: CADText
    public var isInvisible: Bool
    public var isConstant: Bool
    public var prompt: String
    public init(tag: String, text: CADText, isInvisible: Bool = false, isConstant: Bool = false, prompt: String = "") {
        self.tag = tag; self.text = text; self.isInvisible = isInvisible; self.isConstant = isConstant; self.prompt = prompt
    }
}

public struct CADInsert: Sendable, Hashable {
    public var blockName: String
    public var position: Vec2
    public var scale: Vec2
    /// Radians.
    public var rotation: Double
    public var columns: Int
    public var rows: Int
    public var columnSpacing: Double
    public var rowSpacing: Double
    public var attributes: [CADAttribute]
    public init(blockName: String, position: Vec2, scale: Vec2 = Vec2(1, 1), rotation: Double = 0, columns: Int = 1, rows: Int = 1,
                columnSpacing: Double = 0, rowSpacing: Double = 0, attributes: [CADAttribute] = []) {
        self.blockName = blockName; self.position = position; self.scale = scale; self.rotation = rotation
        self.columns = columns; self.rows = rows; self.columnSpacing = columnSpacing; self.rowSpacing = rowSpacing; self.attributes = attributes
    }

    /// Transform of one array cell (drawing units): p' = pos + R·(offset) + R·S·(p − base).
    public func transform(basePoint: Vec2, column: Int = 0, row: Int = 0) -> Transform2 {
        let offset = Vec2(Double(column) * columnSpacing, Double(row) * rowSpacing).rotated(by: rotation)
        return .translation(position + offset) * .rotation(rotation) * .scale(scale.x, scale.y) * .translation(-basePoint)
    }
}

public struct CADDimension: Sendable, Hashable {
    /// Anonymous block with the dimension's graphics ("*D12").
    public var blockName: String
    public var measurement: Double?
    /// Displayed text (override with "<>" replaced by the measurement, or the measurement itself).
    public var text: String
    public var dimensionType: Int
    public var definitionPoint: Vec2
    public var textMidpoint: Vec2
    public var style: String
    public init(blockName: String, measurement: Double?, text: String, dimensionType: Int, definitionPoint: Vec2, textMidpoint: Vec2, style: String = "Standard") {
        self.blockName = blockName; self.measurement = measurement; self.text = text; self.dimensionType = dimensionType
        self.definitionPoint = definitionPoint; self.textMidpoint = textMidpoint; self.style = style
    }
}

public struct CADMultiLeader: Sendable, Hashable {
    public var leaderLines: [[Vec2]]
    public var text: String
    public var textPosition: Vec2?
    public var textHeight: Double
    public var hasArrowhead: Bool
    public init(leaderLines: [[Vec2]], text: String, textPosition: Vec2?, textHeight: Double, hasArrowhead: Bool = true) {
        self.leaderLines = leaderLines; self.text = text; self.textPosition = textPosition; self.textHeight = textHeight; self.hasArrowhead = hasArrowhead
    }
}

/// A CAD entity parsed from DXF (or produced by a DWG provider). Coordinates are WCS drawing units, 2D-projected
/// where the entity is planar (OCS entities are already mapped to WCS).
public enum CADEntity: Sendable {
    case line(Vec3, Vec3, CADEntityProps)
    case polyline(CADPolyline, CADEntityProps)
    /// Circular arc (angles in radians, counter-clockwise from start to end).
    case arc(center: Vec2, radius: Double, startAngle: Double, endAngle: Double, CADEntityProps)
    case circle(center: Vec2, radius: Double, CADEntityProps)
    case ellipse(Ellipse2, CADEntityProps)
    case spline(BSpline2?, fitPoints: [Vec2], closed: Bool, CADEntityProps)
    case point(Vec3, CADEntityProps)
    case text(CADText, CADEntityProps)
    case mtext(CADMText, CADEntityProps)
    case hatch(CADHatch, CADEntityProps)
    /// SOLID / TRACE: 3 or 4 corners in outline order.
    case solid([Vec2], CADEntityProps)
    case insert(CADInsert, CADEntityProps)
    /// ATTDEF inside a block definition (template; not drawn in inserts unless constant).
    case attributeDefinition(CADAttribute, CADEntityProps)
    case dimension(CADDimension, CADEntityProps)
    case leader(points: [Vec2], arrow: Bool, CADEntityProps)
    case multileader(CADMultiLeader, CADEntityProps)
    /// Raster image: declared path (from IMAGEDEF) and its four corners.
    case image(path: String, corners: [Vec2], CADEntityProps)
    case face3D([Vec3], CADEntityProps)
    /// Proxy or unsupported object whose bounds may be known; retained as a reference box when bounds exist.
    case proxy(typeName: String, bounds: Rect2?, CADEntityProps)
    /// An entity type Arcus does not convert (3DSOLID, REGION, BODY, unknown…). Counted, never silently dropped.
    case unsupported(typeName: String, CADEntityProps)

    public var props: CADEntityProps {
        get {
            switch self {
            case .line(_, _, let p), .polyline(_, let p), .arc(_, _, _, _, let p), .circle(_, _, let p), .ellipse(_, let p),
                 .spline(_, _, _, let p), .point(_, let p), .text(_, let p), .mtext(_, let p), .hatch(_, let p), .solid(_, let p),
                 .insert(_, let p), .attributeDefinition(_, let p), .dimension(_, let p), .leader(_, _, let p), .multileader(_, let p),
                 .image(_, _, let p), .face3D(_, let p), .proxy(_, _, let p), .unsupported(_, let p):
                return p
            }
        }
        set {
            switch self {
            case .line(let a, let b, _): self = .line(a, b, newValue)
            case .polyline(let x, _): self = .polyline(x, newValue)
            case .arc(let c, let r, let s, let e, _): self = .arc(center: c, radius: r, startAngle: s, endAngle: e, newValue)
            case .circle(let c, let r, _): self = .circle(center: c, radius: r, newValue)
            case .ellipse(let x, _): self = .ellipse(x, newValue)
            case .spline(let s, let f, let c, _): self = .spline(s, fitPoints: f, closed: c, newValue)
            case .point(let x, _): self = .point(x, newValue)
            case .text(let x, _): self = .text(x, newValue)
            case .mtext(let x, _): self = .mtext(x, newValue)
            case .hatch(let x, _): self = .hatch(x, newValue)
            case .solid(let x, _): self = .solid(x, newValue)
            case .insert(let x, _): self = .insert(x, newValue)
            case .attributeDefinition(let x, _): self = .attributeDefinition(x, newValue)
            case .dimension(let x, _): self = .dimension(x, newValue)
            case .leader(let pts, let a, _): self = .leader(points: pts, arrow: a, newValue)
            case .multileader(let x, _): self = .multileader(x, newValue)
            case .image(let p, let c, _): self = .image(path: p, corners: c, newValue)
            case .face3D(let x, _): self = .face3D(x, newValue)
            case .proxy(let n, let b, _): self = .proxy(typeName: n, bounds: b, newValue)
            case .unsupported(let n, _): self = .unsupported(typeName: n, newValue)
            }
        }
    }

    /// DXF-style type name.
    public var typeName: String {
        switch self {
        case .line: "LINE"
        case .polyline(let p, _): p.isMesh ? "POLYLINE" : (p.is3D ? "POLYLINE" : "LWPOLYLINE")
        case .arc: "ARC"
        case .circle: "CIRCLE"
        case .ellipse: "ELLIPSE"
        case .spline: "SPLINE"
        case .point: "POINT"
        case .text: "TEXT"
        case .mtext: "MTEXT"
        case .hatch: "HATCH"
        case .solid: "SOLID"
        case .insert: "INSERT"
        case .attributeDefinition: "ATTDEF"
        case .dimension: "DIMENSION"
        case .leader: "LEADER"
        case .multileader: "MULTILEADER"
        case .image: "IMAGE"
        case .face3D: "3DFACE"
        case .proxy(let n, _, _): n
        case .unsupported(let n, _): n
        }
    }

    /// Renames referenced blocks (used when merging xref content).
    func renamingBlocks(_ f: (String) -> String) -> CADEntity {
        switch self {
        case .insert(var i, let p): i.blockName = f(i.blockName); return .insert(i, p)
        case .dimension(var d, let p): d.blockName = f(d.blockName); return .dimension(d, p)
        default: return self
        }
    }
}

public struct CADBlock: Sendable {
    public var name: String
    public var basePoint: Vec2
    public var entities: [CADEntity]
    public var isXref: Bool
    public var xrefPath: String?
    public var isAnonymous: Bool
    /// Block record handle (for layout blocks).
    public var recordHandle: String
    public init(name: String, basePoint: Vec2 = .zero, entities: [CADEntity] = [], isXref: Bool = false, xrefPath: String? = nil,
                isAnonymous: Bool = false, recordHandle: String = "") {
        self.name = name; self.basePoint = basePoint; self.entities = entities; self.isXref = isXref; self.xrefPath = xrefPath
        self.isAnonymous = isAnonymous; self.recordHandle = recordHandle
    }
    /// Model/paper space layout blocks.
    public var isLayoutBlock: Bool {
        let u = name.uppercased()
        return u.hasPrefix("*MODEL_SPACE") || u.hasPrefix("*PAPER_SPACE")
    }
}

public struct CADLayout: Sendable {
    public var name: String
    public var isModelSpace: Bool
    public var entities: [CADEntity]
    /// Paper size in millimeters, when known.
    public var paperSize: Vec2?
    public var tabOrder: Int
    public init(name: String, isModelSpace: Bool, entities: [CADEntity], paperSize: Vec2? = nil, tabOrder: Int = 0) {
        self.name = name; self.isModelSpace = isModelSpace; self.entities = entities; self.paperSize = paperSize; self.tabOrder = tabOrder
    }
}

public struct CADXrefInfo: Sendable, Hashable {
    public var blockName: String
    public var path: String
    public var isOverlay: Bool
    public init(blockName: String, path: String, isOverlay: Bool = false) { self.blockName = blockName; self.path = path; self.isOverlay = isOverlay }
}

/// A parsed CAD drawing (DXF or DWG), in source drawing units.
public struct CADDocument: Sendable {
    /// Format version code, e.g. "AC1032".
    public var version: String
    /// Friendly version name, e.g. "AutoCAD 2018".
    public var versionName: String
    /// "DXF" or "DWG" (plus "Binary DXF").
    public var format: String
    public var codepage: String
    /// Units from $INSUNITS.
    public var units: CADUnits
    /// Extents of model space content (drawing units); computed from geometry, header values as fallback.
    public var extents: Rect2
    public var layers: [CADLayer]
    public var lineTypes: [CADLineType]
    public var textStyles: [CADTextStyle]
    public var blocks: [String: CADBlock]
    public var modelSpace: [CADEntity]
    /// All layouts including Model (first).
    public var layouts: [CADLayout]
    public var xrefs: [CADXrefInfo]
    /// Declared raster image paths (IMAGEDEF).
    public var images: [String]
    /// Font files referenced by text styles.
    public var fonts: [String]
    /// Header variables ($NAME → value; points as "x,y,z").
    public var header: [String: String]
    /// Entity types that were not converted to geometry, by type name.
    public var unsupportedCounts: [String: Int]
    /// All entity occurrences by type name (model, layouts and block definitions).
    public var entityCounts: [String: Int]
    /// Non-fatal parse problems (truncation, invalid values…), shown in the import report.
    public var warnings: [String]

    public init(version: String = "", versionName: String = "", format: String = "DXF", codepage: String = "", units: CADUnits = .unitless,
                extents: Rect2 = .empty, layers: [CADLayer] = [], lineTypes: [CADLineType] = [], textStyles: [CADTextStyle] = [],
                blocks: [String: CADBlock] = [:], modelSpace: [CADEntity] = [], layouts: [CADLayout] = [], xrefs: [CADXrefInfo] = [],
                images: [String] = [], fonts: [String] = [], header: [String: String] = [:], unsupportedCounts: [String: Int] = [:],
                entityCounts: [String: Int] = [:], warnings: [String] = []) {
        self.version = version; self.versionName = versionName; self.format = format; self.codepage = codepage; self.units = units
        self.extents = extents; self.layers = layers; self.lineTypes = lineTypes; self.textStyles = textStyles; self.blocks = blocks
        self.modelSpace = modelSpace; self.layouts = layouts; self.xrefs = xrefs; self.images = images; self.fonts = fonts
        self.header = header; self.unsupportedCounts = unsupportedCounts; self.entityCounts = entityCounts; self.warnings = warnings
    }

    /// Case-insensitive block lookup (CAD block names are case-insensitive).
    public func block(named name: String) -> CADBlock? {
        if let b = blocks[name] { return b }
        let u = name.uppercased()
        return blocks.first { $0.key.uppercased() == u }?.value
    }

    public func layout(named name: String) -> CADLayout? {
        layouts.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public var totalEntityCount: Int { entityCounts.values.reduce(0, +) }

    /// Friendly name for a version code.
    public static func friendlyVersion(_ code: String) -> String {
        switch code.uppercased() {
        case "AC1002": "AutoCAD 2.5"
        case "AC1003": "AutoCAD 2.6"
        case "AC1004": "AutoCAD R9"
        case "AC1006": "AutoCAD R10"
        case "AC1009": "AutoCAD R11/R12"
        case "AC1012": "AutoCAD R13"
        case "AC1014": "AutoCAD R14"
        case "AC1015": "AutoCAD 2000"
        case "AC1018": "AutoCAD 2004"
        case "AC1021": "AutoCAD 2007"
        case "AC1024": "AutoCAD 2010"
        case "AC1027": "AutoCAD 2013"
        case "AC1032": "AutoCAD 2018"
        case "": "Unknown"
        default: "Unknown (\(code))"
        }
    }
}

// MARK: - Options and errors

public struct CADReadOptions: Sendable {
    /// Maximum number of entities (after expanding block inserts) accepted before the read is refused.
    public var maxEntities = 5_000_000
    /// Maximum block nesting depth; deeper references are ignored with a warning.
    public var maxBlockDepth = 32
    public init() {}
}

public struct CADError: Error, Sendable, CustomStringConvertible {
    public var message: String
    public var line: Int?
    public init(_ message: String, line: Int? = nil) { self.message = message; self.line = line }
    public var description: String {
        if let line { return "Line \(line): \(message)" }
        return message
    }
}
