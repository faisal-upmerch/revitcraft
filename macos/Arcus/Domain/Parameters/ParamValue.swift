import Foundation
import ArcusCalc

/// A stored parameter value. Numeric values are SI (see `ParamType` for the unit).
public enum ParamValue: Hashable, Codable, Sendable, CustomStringConvertible {
    case double(Double)
    case int(Int)
    case bool(Bool)
    case text(String)
    case ref(ElementID?)

    public var doubleValue: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        case .bool(let b): b ? 1 : 0
        case .text(let s): Double(s)
        case .ref: nil
        }
    }
    public var intValue: Int? {
        switch self {
        case .int(let i): i
        case .double(let d): d.isFinite ? Int(d.rounded()) : nil
        case .bool(let b): b ? 1 : 0
        case .text(let s): Int(s)
        case .ref: nil
        }
    }
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): b
        case .int(let i): i != 0
        case .double(let d): d != 0
        case .text(let s): ["yes", "true", "1"].contains(s.lowercased()) ? true : (["no", "false", "0"].contains(s.lowercased()) ? false : nil)
        case .ref: nil
        }
    }
    public var textValue: String? {
        switch self {
        case .text(let s): s
        default: nil
        }
    }
    public var refValue: ElementID? {
        if case .ref(let r) = self { return r }
        return nil
    }
    public var description: String {
        switch self {
        case .double(let d): "\(d)"
        case .int(let i): "\(i)"
        case .bool(let b): b ? "Yes" : "No"
        case .text(let s): s
        case .ref(let r): r.map(\.description) ?? "<None>"
        }
    }
}

/// The storage and unit type of a parameter.
public enum ParamType: Hashable, Codable, Sendable {
    case length, area, volume, angle, slope, number, integer, percentage, currency
    case text, multilineText, bool, url
    /// Reference to another element (level, material, phase, type…).
    case elementRef(Category)
    /// A choice among fixed text options.
    case choice([String])

    public var unitKind: UnitKind? {
        switch self {
        case .length: .length
        case .area: .area
        case .volume: .volume
        case .angle: .angle
        case .slope: .slope
        case .number: .number
        case .integer: .integer
        case .percentage: .percentage
        case .currency: .currency
        default: nil
        }
    }
    public var isNumeric: Bool { unitKind != nil }
    public var displayName: String {
        switch self {
        case .length: "Length"
        case .area: "Area"
        case .volume: "Volume"
        case .angle: "Angle"
        case .slope: "Slope"
        case .number: "Number"
        case .integer: "Integer"
        case .percentage: "Percentage"
        case .currency: "Currency"
        case .text: "Text"
        case .multilineText: "Multiline Text"
        case .bool: "Yes/No"
        case .url: "URL"
        case .elementRef(let c): c == .materials ? "Material" : c.singularName
        case .choice: "Choice"
        }
    }
    /// Types offered to users when creating project/family parameters.
    public static let userCreatable: [ParamType] = [
        .length, .area, .volume, .angle, .slope, .number, .integer, .percentage, .currency, .text, .multilineText, .bool, .url, .elementRef(.materials),
    ]
    public var defaultValue: ParamValue {
        switch self {
        case .integer: .int(0)
        case .text, .multilineText, .url: .text("")
        case .bool: .bool(false)
        case .elementRef: .ref(nil)
        case .choice(let c): .text(c.first ?? "")
        default: .double(0)
        }
    }
    /// Dimension used by the formula engine.
    public var dimension: ArcusCalc.Dimension? { unitKind.map { ArcusCalc.Dimension(kind: $0) } }
}

/// Grouping of parameters in the Properties inspector.
public enum ParameterGroup: String, Codable, Sendable, CaseIterable, Comparable {
    case constraints = "Constraints"
    case construction = "Construction"
    case graphics = "Graphics"
    case materials = "Materials and Finishes"
    case crossSection = "Cross-Section Definition" // BL-PROPS
    case structural = "Structural" // BL-PROPS: before Dimensions, as BIM users read the palette
    case dimensions = "Dimensions"
    case identity = "Identity Data"
    case phasing = "Phasing"
    /// Arcus-only instance parameters (wall sweeps, slab edges, soffits), shown after Phasing. BL-PROPS
    case arcus = "Arcus Extensions"
    case extents = "Extents"
    case camera = "Camera" // W2-CAM
    case text = "Text"
    case ifc = "IFC Parameters"
    case other = "Other"

    public static func < (a: ParameterGroup, b: ParameterGroup) -> Bool {
        (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
    }
}

/// Identity of a parameter. Built-in parameters use stable keys; user parameters use their definition GUID.
public struct ParameterID: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public let key: String
    public init(_ key: String) { self.key = key }
    public var description: String { key }
    public var isBuiltIn: Bool { !key.hasPrefix("user:") }
    public static func user(_ guid: String) -> ParameterID { ParameterID("user:" + guid) }
    public static func < (a: ParameterID, b: ParameterID) -> Bool { a.key < b.key }

    public init(from decoder: any Decoder) throws { key = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(key) }
}

/// Definition of a user-created (project or shared) parameter.
public struct ParameterDefinition: Hashable, Codable, Sendable, Identifiable {
    public var id: ParameterID
    public var name: String
    public var type: ParamType
    public var group: ParameterGroup
    public var isInstance: Bool
    /// Categories the parameter is bound to (project parameters). Empty for family parameters.
    public var categories: [Category]
    /// GUID for shared parameters; nil for project-only parameters.
    public var sharedGUID: String?
    public var tooltip: String
    /// Optional formula (family parameters and calculated project parameters).
    public var formula: String?
    public var defaultValue: ParamValue?

    public init(id: ParameterID? = nil, name: String, type: ParamType, group: ParameterGroup = .other, isInstance: Bool = true,
                categories: [Category] = [], sharedGUID: String? = nil, tooltip: String = "", formula: String? = nil, defaultValue: ParamValue? = nil) {
        self.id = id ?? .user(sharedGUID ?? UUID().uuidString)
        self.name = name; self.type = type; self.group = group; self.isInstance = isInstance
        self.categories = categories; self.sharedGUID = sharedGUID; self.tooltip = tooltip; self.formula = formula
        self.defaultValue = defaultValue
    }
}
