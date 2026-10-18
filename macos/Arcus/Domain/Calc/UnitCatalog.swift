import Foundation

/// How a unit participates in compound entries such as `12' 6"` or `45°30'15"`.
enum UnitRole: Sendable, Equatable {
    case plain
    case feet
    case inch
    /// `'` — feet in length contexts, arcminutes in angle contexts.
    case prime
    /// `"` — inches in length contexts, arcseconds in angle contexts.
    case doublePrime
    case degree
    case arcminute
    case arcsecond
    case percent
    case currency
}

/// A unit recognized in typed input: its dimension and its size in SI.
struct UnitSpec: Sendable, Equatable {
    var dimension: Dimension
    /// SI value of one unit (meters, m², m³, radians, or a plain factor).
    var factor: Double
    var role: UnitRole
}

/// The unit vocabulary shared by the quantity parser and the formula language.
enum UnitCatalog {
    static let foot = 0.3048
    static let inch = 0.0254
    static let degree = Double.pi / 180

    static let prime = UnitSpec(dimension: .length, factor: foot, role: .prime)
    static let doublePrime = UnitSpec(dimension: .length, factor: inch, role: .doublePrime)
    static let feet = UnitSpec(dimension: .length, factor: foot, role: .feet)
    static let inches = UnitSpec(dimension: .length, factor: inch, role: .inch)
    static let degrees = UnitSpec(dimension: .angle, factor: degree, role: .degree)
    static let arcminutes = UnitSpec(dimension: .angle, factor: degree / 60, role: .arcminute)
    static let arcseconds = UnitSpec(dimension: .angle, factor: degree / 3600, role: .arcsecond)
    static let percent = UnitSpec(dimension: .none, factor: 0.01, role: .percent)

    /// Length unit words (lower-cased) with meters per unit and role.
    private static let lengthWords: [String: (Double, UnitRole)] = {
        var t: [String: (Double, UnitRole)] = [:]
        for w in ["mm", "millimeter", "millimeters", "millimetre", "millimetres"] { t[w] = (0.001, .plain) }
        for w in ["cm", "centimeter", "centimeters", "centimetre", "centimetres"] { t[w] = (0.01, .plain) }
        for w in ["m", "meter", "meters", "metre", "metres"] { t[w] = (1, .plain) }
        for w in ["km", "kilometer", "kilometers", "kilometre", "kilometres"] { t[w] = (1000, .plain) }
        for w in ["in", "inch", "inches"] { t[w] = (inch, .inch) }
        for w in ["ft", "foot", "feet"] { t[w] = (foot, .feet) }
        for w in ["yd", "yard", "yards"] { t[w] = (0.9144, .plain) }
        return t
    }()

    /// Non-length unit words (lower-cased).
    private static let otherWords: [String: UnitSpec] = {
        var t: [String: UnitSpec] = [:]
        let ft2 = foot * foot, ft3 = foot * foot * foot, yd3 = 0.9144 * 0.9144 * 0.9144
        for w in ["sf", "sqft"] { t[w] = UnitSpec(dimension: .area, factor: ft2, role: .plain) }
        t["sqm"] = UnitSpec(dimension: .area, factor: 1, role: .plain)
        t["sqmm"] = UnitSpec(dimension: .area, factor: 1e-6, role: .plain)
        t["sqin"] = UnitSpec(dimension: .area, factor: inch * inch, role: .plain)
        for w in ["cf", "cuft"] { t[w] = UnitSpec(dimension: .volume, factor: ft3, role: .plain) }
        for w in ["cy", "cuyd"] { t[w] = UnitSpec(dimension: .volume, factor: yd3, role: .plain) }
        t["cum"] = UnitSpec(dimension: .volume, factor: 1, role: .plain)
        for w in ["l", "liter", "liters", "litre", "litres"] { t[w] = UnitSpec(dimension: .volume, factor: 0.001, role: .plain) }
        t["ml"] = UnitSpec(dimension: .volume, factor: 1e-6, role: .plain)
        for w in ["deg", "degs", "degree", "degrees"] { t[w] = degrees }
        for w in ["rad", "rads", "radian", "radians"] { t[w] = UnitSpec(dimension: .angle, factor: 1, role: .plain) }
        return t
    }()

    /// Words that square (`sq`, `square`) or cube (`cu`, `cubic`) the following length unit.
    static func powerPrefix(_ lowerWord: String) -> Int? {
        switch lowerWord {
        case "sq", "square": 2
        case "cu", "cubic": 3
        default: nil
        }
    }

    /// Looks up a unit word, optionally raised to a power (`m²`, `ft3`, `sq m`).
    static func unit(word: String, exponent: Int? = nil) -> UnitSpec? {
        let lower = word.lowercased()
        if let e = exponent {
            guard let (f, _) = lengthWords[lower], e == 2 || e == 3 else { return nil }
            return UnitSpec(dimension: Dimension(length: e), factor: e == 2 ? f * f : f * f * f, role: .plain)
        }
        if let (f, role) = lengthWords[lower] {
            return UnitSpec(dimension: .length, factor: f, role: role)
        }
        return otherWords[lower]
    }

    /// Symbol units recognised right after a number.
    static func symbol(_ c: Character) -> UnitSpec? {
        switch c {
        case "'", "’", "′", "‘": prime
        case "\"", "”", "″", "“": doublePrime
        case "°", "º": degrees
        case "%": percent
        default: nil
        }
    }

    static func isPrimeCharacter(_ c: Character) -> Bool { "'’′‘".contains(c) }
    static func isDoublePrimeCharacter(_ c: Character) -> Bool { "\"”″“".contains(c) }

    /// Superscript/caret/digit exponent directly after a unit word. Returns the exponent and the
    /// number of characters consumed. A plain digit only counts when it is not followed by more
    /// of the entry (so `2ft2in` is not read as ft²).
    static func exponentSuffix(_ chars: [Character], at i: Int, allowCaret: Bool) -> (Int, Int)? {
        guard i < chars.count else { return nil }
        switch chars[i] {
        case "²": return (2, 1)
        case "³": return (3, 1)
        case "^" where allowCaret:
            if i + 1 < chars.count, chars[i + 1] == "2" || chars[i + 1] == "3" {
                return (chars[i + 1] == "2" ? 2 : 3, 2)
            }
            return nil
        case "2", "3":
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            let terminators: Set<Character> = ["+", "-", "−", "–", "*", "×", "/", "÷", ")", "(", ":", ",", ";", "<", ">", "=", "^"]
            guard next.isWhitespace || terminators.contains(next) else { return nil }
            return (chars[i] == "2" ? 2 : 3, 1)
        default:
            return nil
        }
    }
}

extension Character {
    var isASCIIDigitChar: Bool { isASCII && isNumber }
    var isASCIILetterChar: Bool { isASCII && isLetter }
}

/// Number-to-text helpers shared by parsing and formatting.
enum NumericText {
    /// The decimal separator in effect: the override if set, else the locale's, else ".".
    static func decimalSeparator(units: UnitsSettings, locale: Locale) -> Character {
        if let o = units.decimalSeparatorOverride, let c = o.first { return c }
        return locale.decimalSeparator?.first ?? "."
    }

    /// Rounds half away from zero, nudged slightly so values like `2.4999999999999996` that are
    /// really `2.5` after a division still round away from zero.
    static func roundHalfAway(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let a = abs(x)
        let r = (a + max(1e-9, a * 1e-13)).rounded(.toNearestOrAwayFromZero)
        let signed = x < 0 ? -r : r
        return signed == 0 ? 0 : signed
    }

    /// Rounds `x` to a multiple of `increment` (half away from zero). Never returns -0.
    static func round(_ x: Double, toIncrement increment: Double) -> Double {
        guard increment > 0, increment.isFinite, x.isFinite else { return x }
        let q = x / increment
        guard q.isFinite, abs(q) < 1e17 else { return x }
        let r = roundHalfAway(q) * increment
        return r == 0 ? 0 : r
    }

    /// Decimal places needed to show values rounded to `increment` (0…9).
    static func decimals(forIncrement increment: Double) -> Int {
        guard increment > 0, increment.isFinite else { return 2 }
        let d = Int((-log10(increment) - 1e-9).rounded(.up))
        return min(max(d, 0), 9)
    }

    /// Fixed-point text with the given decimals and separator, rounded half away from zero.
    /// Never produces `-0` or `-0.00`.
    static func fixed(_ x: Double, decimals: Int, separator: Character) -> String {
        guard x.isFinite else { return x.isNaN ? "—" : (x < 0 ? "-∞" : "∞") }
        let d = min(max(decimals, 0), 9)
        let scale = pow(10.0, Double(d))
        var r = x
        let scaled = x * scale
        if scaled.isFinite && abs(scaled) < 1e17 { r = roundHalfAway(scaled) / scale }
        if r == 0 { r = 0 }
        var s = String(format: "%.\(d)f", r)
        if s.hasPrefix("-") && !s.contains(where: { $0 >= "1" && $0 <= "9" }) { s.removeFirst() }
        if separator != "." { s = s.replacingOccurrences(of: ".", with: String(separator)) }
        return s
    }
}
