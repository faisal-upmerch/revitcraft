import Foundation

/// Formats SI values for display. Formatting never changes stored values.
///
/// Rules: values are rounded half away from zero at the display increment; `-0` is never
/// produced; the locale decimal separator is used unless `UnitsSettings.decimalSeparatorOverride`
/// is set; digit grouping is never used (so every output parses back with `QuantityParser`).
/// Non-finite values format as `—` (NaN) or `∞`.
public enum QuantityFormatter {
    /// Formats `si` (m, m², m³, rad, rise/run, number, fraction for percentages) per the project settings.
    ///
    /// `includeSymbol: false` drops unit symbols where the number alone still reads correctly
    /// as display units. Feet-and-inches (`12' - 6"`) and rise-per-12 slopes always keep
    /// their marks because they are part of the notation.
    public static func format(_ si: Double, kind: UnitKind, units: UnitsSettings, locale: Locale = .current, includeSymbol: Bool = true) -> String {
        let sep = NumericText.decimalSeparator(units: units, locale: locale)
        guard si.isFinite else { return NumericText.fixed(si, decimals: 0, separator: sep) }
        switch kind {
        case .length:
            return formatLength(si, display: units.length, rounding: units.lengthRounding, separator: sep, includeSymbol: includeSymbol)
        case .area:
            let text = NumericText.fixed(si / units.area.squareMetersPerUnit, decimals: units.areaDecimals, separator: sep)
            return includeSymbol ? "\(text) \(units.area.symbol)" : text
        case .volume:
            let text = NumericText.fixed(si / units.volume.cubicMetersPerUnit, decimals: units.volumeDecimals, separator: sep)
            return includeSymbol ? "\(text) \(units.volume.symbol)" : text
        case .angle:
            let text = NumericText.fixed(si / UnitCatalog.degree, decimals: units.angleDecimals, separator: sep)
            return includeSymbol ? "\(text)°" : text
        case .slope:
            return formatSlope(si, units: units, separator: sep, includeSymbol: includeSymbol)
        case .number:
            return NumericText.fixed(si, decimals: units.numberDecimals, separator: sep)
        case .integer:
            return NumericText.fixed(si, decimals: 0, separator: sep)
        case .percentage:
            let text = NumericText.fixed(si * 100, decimals: units.numberDecimals, separator: sep)
            return includeSymbol ? "\(text)%" : text
        case .currency:
            let magnitude = NumericText.fixed(abs(si), decimals: units.numberDecimals, separator: sep)
            let negative = si < 0 && magnitude.contains(where: { $0 >= "1" && $0 <= "9" })
            return (negative ? "-" : "") + (includeSymbol ? units.currencySymbol : "") + magnitude
        }
    }

    /// Formats a length with a specific display regardless of the project setting (for example
    /// alternate units on dimensions). `rounding` is the increment in meters; a non-positive or
    /// non-finite increment falls back to `display.defaultRounding`.
    public static func formatLength(_ meters: Double, display: LengthDisplay, rounding: Double, locale: Locale = .current, includeSymbol: Bool = true) -> String {
        let sep: Character = locale.decimalSeparator?.first ?? "."
        return formatLength(meters, display: display, rounding: rounding, separator: sep, includeSymbol: includeSymbol)
    }

    static func formatLength(_ meters: Double, display: LengthDisplay, rounding: Double, separator sep: Character, includeSymbol: Bool) -> String {
        guard meters.isFinite else { return NumericText.fixed(meters, decimals: 0, separator: sep) }
        let increment = rounding > 0 && rounding.isFinite ? rounding : display.defaultRounding
        switch display {
        case .millimeters, .centimeters, .meters, .decimalFeet, .decimalInches:
            let unit = display.metersPerUnit
            let rounded = NumericText.round(meters, toIncrement: increment) / unit
            let text = NumericText.fixed(rounded, decimals: NumericText.decimals(forIncrement: increment / unit), separator: sep)
            guard includeSymbol else { return text }
            switch display {
            case .millimeters: return text + " mm"
            case .centimeters: return text + " cm"
            case .meters: return text + " m"
            case .decimalFeet: return text + "'"
            default: return text + "\""
            }
        case .feetFractionalInches:
            guard let (negative, grid) = inchGrid(meters, increment: increment) else {
                return formatLength(meters, display: .decimalFeet, rounding: increment, separator: sep, includeSymbol: includeSymbol)
            }
            let perFoot: Int64 = 12 * gridPerInch
            let feet = grid / perFoot
            let inches = inchText(grid % perFoot, alwaysWhole: true)
            return (negative ? "-" : "") + "\(feet)' - \(inches)\""
        case .fractionalInches:
            guard let (negative, grid) = inchGrid(meters, increment: increment) else {
                return formatLength(meters, display: .decimalInches, rounding: increment, separator: sep, includeSymbol: includeSymbol)
            }
            return (negative ? "-" : "") + inchText(grid, alwaysWhole: false) + (includeSymbol ? "\"" : "")
        }
    }

    /// Finest fraction shown: 1/256".
    static let gridPerInch: Int64 = 256

    /// Rounds to the increment and expresses the magnitude in 1/256" steps.
    /// Returns nil when the value is too large for exact integer arithmetic.
    static func inchGrid(_ meters: Double, increment: Double) -> (Bool, Int64)? {
        let incrementInches = max(increment / UnitCatalog.inch, 1.0 / Double(gridPerInch))
        let inches = meters / UnitCatalog.inch
        let rounded = NumericText.round(inches, toIncrement: incrementInches)
        let steps = (abs(rounded) * Double(gridPerInch)).rounded()
        guard steps.isFinite, steps < 1e15 else { return nil }
        let grid = Int64(steps)
        return (grid != 0 && rounded < 0, grid)
    }

    /// `6 1/2`, `6`, `1/2` (or `0 1/2` when `alwaysWhole`), `0`, from a count of 1/256" steps.
    static func inchText(_ grid: Int64, alwaysWhole: Bool) -> String {
        let whole = grid / gridPerInch
        var numerator = grid % gridPerInch
        guard numerator != 0 else { return "\(whole)" }
        var denominator = gridPerInch
        while numerator % 2 == 0 && denominator % 2 == 0 {
            numerator /= 2
            denominator /= 2
        }
        let fraction = "\(numerator)/\(denominator)"
        return whole == 0 && !alwaysWhole ? fraction : "\(whole) \(fraction)"
    }

    static func formatSlope(_ ratio: Double, units: UnitsSettings, separator sep: Character, includeSymbol: Bool) -> String {
        let decimals = units.slopeDecimals
        switch units.slope {
        case .degrees:
            let text = NumericText.fixed(atan(ratio) / UnitCatalog.degree, decimals: decimals, separator: sep)
            return includeSymbol ? text + "°" : text
        case .risePer12Inches:
            let riseMeters = ratio * 12 * UnitCatalog.inch
            guard let (negative, grid) = inchGrid(riseMeters, increment: UnitCatalog.inch / 16) else {
                return NumericText.fixed(ratio * 12, decimals: decimals, separator: sep) + "\" / 12\""
            }
            return (negative ? "-" : "") + inchText(grid, alwaysWhole: false) + "\" / 12\""
        case .percent:
            let text = NumericText.fixed(ratio * 100, decimals: decimals, separator: sep)
            return includeSymbol ? text + "%" : text
        case .ratio:
            let run = NumericText.fixed(1 / abs(ratio), decimals: decimals, separator: sep)
            guard ratio != 0, run.contains(where: { $0 >= "1" && $0 <= "9" }) else {
                return ratio == 0 ? "0:1" : (ratio < 0 ? "-1:0" : "1:0")
            }
            return (ratio < 0 ? "-1:" : "1:") + run
        }
    }
}
