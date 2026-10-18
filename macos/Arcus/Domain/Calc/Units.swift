import Foundation

// MARK: - Kinds and display settings

/// The kind of value a field or parameter holds. Drives parsing, formatting and dimension checks.
///
/// Internal storage is always SI: meters, m², m³, radians, rise/run ratios, plain numbers,
/// and fractions for percentages (`0.25` means 25 %).
public enum UnitKind: String, Codable, Sendable, CaseIterable {
    case length, area, volume, angle, slope, number, integer, percentage, currency
}

/// The measurement system of a project.
public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric, imperial
}

/// How lengths are shown (and how bare numbers typed into a length field are interpreted).
public enum LengthDisplay: String, Codable, Sendable, CaseIterable {
    case millimeters, centimeters, meters, feetFractionalInches, decimalFeet, fractionalInches, decimalInches

    /// Meters per display unit. For feet-and-inches this is one foot, the unit a bare number means.
    public var metersPerUnit: Double {
        switch self {
        case .millimeters: 0.001
        case .centimeters: 0.01
        case .meters: 1
        case .feetFractionalInches, .decimalFeet: UnitCatalog.foot
        case .fractionalInches, .decimalInches: UnitCatalog.inch
        }
    }

    /// True for displays in which a bare number means feet (`12 6` then reads as 12 ft 6 in).
    public var isFeetBased: Bool { self == .feetFractionalInches || self == .decimalFeet }

    /// A sensible rounding increment (in meters) for this display, used when a caller passes
    /// a non-positive or non-finite increment.
    public var defaultRounding: Double {
        switch self {
        case .millimeters, .centimeters, .meters: 0.001
        case .feetFractionalInches, .fractionalInches: UnitCatalog.inch / 16
        case .decimalFeet: UnitCatalog.foot / 100
        case .decimalInches: UnitCatalog.inch / 100
        }
    }

    /// The "whole display unit" used by the formula functions `round`, `roundup` and `rounddown`:
    /// 1 mm, 1 cm, 1 m, 1 inch (feet-and-inches and inch displays) or 1 foot (decimal feet).
    var roundingUnit: Double {
        switch self {
        case .feetFractionalInches: UnitCatalog.inch
        default: metersPerUnit
        }
    }
}

/// How areas are shown.
public enum AreaDisplay: String, Codable, Sendable, CaseIterable {
    case squareMeters, squareFeet, squareMillimeters

    /// Square meters per display unit.
    public var squareMetersPerUnit: Double {
        switch self {
        case .squareMeters: 1
        case .squareFeet: UnitCatalog.foot * UnitCatalog.foot
        case .squareMillimeters: 1e-6
        }
    }

    /// The symbol appended when formatting.
    public var symbol: String {
        switch self {
        case .squareMeters: "m²"
        case .squareFeet: "SF"
        case .squareMillimeters: "mm²"
        }
    }
}

/// How volumes are shown.
public enum VolumeDisplay: String, Codable, Sendable, CaseIterable {
    case cubicMeters, cubicFeet, liters

    /// Cubic meters per display unit.
    public var cubicMetersPerUnit: Double {
        switch self {
        case .cubicMeters: 1
        case .cubicFeet: UnitCatalog.foot * UnitCatalog.foot * UnitCatalog.foot
        case .liters: 0.001
        }
    }

    /// The symbol appended when formatting.
    public var symbol: String {
        switch self {
        case .cubicMeters: "m³"
        case .cubicFeet: "CF"
        case .liters: "L"
        }
    }
}

/// How slopes are shown (and how a bare number typed into a slope field is interpreted).
public enum SlopeDisplay: String, Codable, Sendable, CaseIterable {
    /// `30.00°`; a bare number means degrees.
    case degrees
    /// `6" / 12"`; a bare number means inches of rise per 12 inches of run.
    case risePer12Inches
    /// `50.00%`; a bare number means percent.
    case percent
    /// `1:2.00` (rise : run with a unit rise); a bare number `n` means `1:n`.
    case ratio
}

/// Project unit settings. Everything is stored in SI; these settings only affect display
/// and how unit-less input is interpreted.
public struct UnitsSettings: Codable, Hashable, Sendable {
    /// Measurement system of the project.
    public var system: UnitSystem
    /// Length display (also the meaning of bare numbers in length fields).
    public var length: LengthDisplay
    /// Rounding increment in meters for length display (e.g. `0.001` for 1 mm; `0.0254/16` for 1/16").
    public var lengthRounding: Double
    /// Area display unit.
    public var area: AreaDisplay
    /// Decimal places for areas.
    public var areaDecimals: Int
    /// Volume display unit.
    public var volume: VolumeDisplay
    /// Decimal places for volumes.
    public var volumeDecimals: Int
    /// Decimal places for angles (degrees).
    public var angleDecimals: Int
    /// Slope display (also the meaning of bare numbers in slope fields).
    public var slope: SlopeDisplay
    /// Decimal places for slopes shown in degrees, percent or ratio form.
    public var slopeDecimals: Int
    /// Decimal places for numbers, percentages and currency.
    public var numberDecimals: Int
    /// Currency symbol shown before amounts and accepted when parsing.
    public var currencySymbol: String
    /// Decimal separator to use instead of the locale's; `nil` uses the locale.
    public var decimalSeparatorOverride: String?

    /// Millimeters (1 mm rounding), m² and m³ with 2 decimals, angles with 2 decimals, slopes in degrees.
    public static let metric = UnitsSettings()

    /// Feet and fractional inches (1/16" rounding), SF and CF with 2 decimals, slopes as rise per 12".
    public static let imperial = UnitsSettings(
        system: .imperial, length: .feetFractionalInches, lengthRounding: UnitCatalog.inch / 16,
        area: .squareFeet, volume: .cubicFeet, slope: .risePer12Inches)

    /// Memberwise initializer; defaults match `UnitsSettings.metric`.
    public init(
        system: UnitSystem = .metric,
        length: LengthDisplay = .millimeters,
        lengthRounding: Double = 0.001,
        area: AreaDisplay = .squareMeters,
        areaDecimals: Int = 2,
        volume: VolumeDisplay = .cubicMeters,
        volumeDecimals: Int = 2,
        angleDecimals: Int = 2,
        slope: SlopeDisplay = .degrees,
        slopeDecimals: Int = 2,
        numberDecimals: Int = 2,
        currencySymbol: String = "$",
        decimalSeparatorOverride: String? = nil
    ) {
        self.system = system
        self.length = length
        self.lengthRounding = lengthRounding
        self.area = area
        self.areaDecimals = areaDecimals
        self.volume = volume
        self.volumeDecimals = volumeDecimals
        self.angleDecimals = angleDecimals
        self.slope = slope
        self.slopeDecimals = slopeDecimals
        self.numberDecimals = numberDecimals
        self.currencySymbol = currencySymbol
        self.decimalSeparatorOverride = decimalSeparatorOverride
    }

    private enum CodingKeys: String, CodingKey {
        case system, length, lengthRounding, area, areaDecimals, volume, volumeDecimals
        case angleDecimals, slope, slopeDecimals, numberDecimals, currencySymbol, decimalSeparatorOverride
    }

    /// Decodes leniently: any missing key falls back to the metric default, so settings saved by
    /// older versions keep loading when fields are added.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UnitsSettings()
        system = try c.decodeIfPresent(UnitSystem.self, forKey: .system) ?? d.system
        length = try c.decodeIfPresent(LengthDisplay.self, forKey: .length) ?? d.length
        lengthRounding = try c.decodeIfPresent(Double.self, forKey: .lengthRounding) ?? d.lengthRounding
        area = try c.decodeIfPresent(AreaDisplay.self, forKey: .area) ?? d.area
        areaDecimals = try c.decodeIfPresent(Int.self, forKey: .areaDecimals) ?? d.areaDecimals
        volume = try c.decodeIfPresent(VolumeDisplay.self, forKey: .volume) ?? d.volume
        volumeDecimals = try c.decodeIfPresent(Int.self, forKey: .volumeDecimals) ?? d.volumeDecimals
        angleDecimals = try c.decodeIfPresent(Int.self, forKey: .angleDecimals) ?? d.angleDecimals
        slope = try c.decodeIfPresent(SlopeDisplay.self, forKey: .slope) ?? d.slope
        slopeDecimals = try c.decodeIfPresent(Int.self, forKey: .slopeDecimals) ?? d.slopeDecimals
        numberDecimals = try c.decodeIfPresent(Int.self, forKey: .numberDecimals) ?? d.numberDecimals
        currencySymbol = try c.decodeIfPresent(String.self, forKey: .currencySymbol) ?? d.currencySymbol
        decimalSeparatorOverride = try c.decodeIfPresent(String.self, forKey: .decimalSeparatorOverride)
    }
}

// MARK: - Dimension

/// Physical dimension of a quantity as exponents of length and angle.
///
/// Angles are tracked as their own base dimension (rather than being dimensionless as in SI)
/// so the formula language can check that trigonometric functions receive angles.
public struct Dimension: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Exponent of length (1 = length, 2 = area, 3 = volume).
    public var length: Int
    /// Exponent of angle.
    public var angle: Int

    /// Dimensionless (numbers, ratios, slopes, percentages, currency).
    public static let none = Dimension()
    /// Length (m).
    public static let length = Dimension(length: 1)
    /// Area (m²).
    public static let area = Dimension(length: 2)
    /// Volume (m³).
    public static let volume = Dimension(length: 3)
    /// Angle (rad).
    public static let angle = Dimension(angle: 1)

    /// A dimension with the given exponents.
    public init(length: Int = 0, angle: Int = 0) {
        self.length = length
        self.angle = angle
    }

    /// The dimension stored for a unit kind. Slopes, numbers, integers, percentages and
    /// currency are dimensionless.
    public init(kind: UnitKind) {
        switch kind {
        case .length: self = .length
        case .area: self = .area
        case .volume: self = .volume
        case .angle: self = .angle
        case .slope, .number, .integer, .percentage, .currency: self = .none
        }
    }

    /// True when both exponents are zero.
    public var isDimensionless: Bool { length == 0 && angle == 0 }

    /// Dimension of a product (exponents add).
    public static func * (a: Dimension, b: Dimension) -> Dimension {
        Dimension(length: a.length &+ b.length, angle: a.angle &+ b.angle)
    }

    /// Dimension of a quotient (exponents subtract).
    public static func / (a: Dimension, b: Dimension) -> Dimension {
        Dimension(length: a.length &- b.length, angle: a.angle &- b.angle)
    }

    /// The dimension raised to an integer power.
    public func power(_ n: Int) -> Dimension {
        Dimension(length: length &* n, angle: angle &* n)
    }

    /// The square root of the dimension, or `nil` when an exponent is odd.
    public var squareRoot: Dimension? {
        guard length % 2 == 0, angle % 2 == 0 else { return nil }
        return Dimension(length: length / 2, angle: angle / 2)
    }

    /// `length`, `area`, `volume`, `angle`, `dimensionless`, or a composite like `length^4·angle^-1`.
    public var description: String {
        switch self {
        case .none: return "dimensionless"
        case .length: return "length"
        case .area: return "area"
        case .volume: return "volume"
        case .angle: return "angle"
        default:
            var parts: [String] = []
            if length != 0 { parts.append(length == 1 ? "length" : "length^\(length)") }
            if angle != 0 { parts.append(angle == 1 ? "angle" : "angle^\(angle)") }
            return parts.joined(separator: "·")
        }
    }

    /// A phrase with an article for messages: "a length", "an area", "a number", …
    var phrase: String {
        switch self {
        case .none: return "a number"
        case .length: return "a length"
        case .area: return "an area"
        case .volume: return "a volume"
        case .angle: return "an angle"
        default: return "a value of dimension \(description)"
        }
    }

    /// Short noun for messages: "length", "area", "number", …
    var noun: String { self == .none ? "number" : description }
}

extension UnitKind {
    /// A phrase with an article for messages: "a length", "an angle", "a whole number", …
    var phrase: String {
        switch self {
        case .length: "a length"
        case .area: "an area"
        case .volume: "a volume"
        case .angle: "an angle"
        case .slope: "a slope"
        case .number: "a number"
        case .integer: "a whole number"
        case .percentage: "a percentage"
        case .currency: "an amount"
        }
    }
}
