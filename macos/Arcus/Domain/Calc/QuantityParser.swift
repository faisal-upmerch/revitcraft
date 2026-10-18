import Foundation

/// A user-facing parse error with a message suitable for showing next to the field.
public struct QuantityParseError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A user-facing explanation.
    public var message: String
    /// Same as `message`.
    public var description: String { message }
    /// Creates an error with a message.
    public init(_ message: String) { self.message = message }
}

/// Parses values typed into the inspector, temporary dimensions, schedules and dialogs.
///
/// Input grammar (forgiving, like a professional BIM tool):
/// - An optional leading `=`, then an arithmetic expression with `+ - * /` and parentheses.
/// - Numbers use the locale decimal separator (or `UnitsSettings.decimalSeparatorOverride`).
///   The other separator is rejected rather than guessed, because `3.500` means 3500 in some
///   locales. Digit grouping is not supported, so `1 200` is an error rather than a guess.
/// - Terms may carry units: `mm cm m km in ft yd ' "`, `m² m2 sq m SF ft² …`, `m³ CF ft3 L …`,
///   `° deg rad`, `%`. Explicit units are always honoured, whatever the project system.
/// - Bare numbers mean the project display unit (mm, feet, inches, m², degrees, …). In a sum
///   with unit-bearing terms, bare terms also take the display unit (`3 m + 500` = 3.5 m in a
///   millimeter project). As multipliers or divisors they are plain scale factors.
/// - Feet-and-inches: `12' 6"`, `12'-6 1/2"`, `12' - 6 1/2"`, `12ft 6in`, `12' 6`; and in
///   feet-based displays `12 6` (feet then inches, inches < 12). A `-` directly after a feet term
///   followed by an inch term is the conventional separator, not subtraction (`12' - 6"` is
///   12'6"). Fractions `1/2"` and mixed numbers `6 1/2"` are single numbers.
/// - Angles: `45`, `45°`, `45 deg`, `0.5 rad`, `45°30'15"` (`'`/`"` are arcminutes/arcseconds
///   in angle fields). Slopes: angles, `6/12`, `6:12`, `25%`, `6" / 12"`; a bare `a/b` or
///   `a:b` is always rise/run, any other bare number follows `UnitsSettings.slope`.
public enum QuantityParser {
    /// Longest accepted input, in characters.
    public static let maxInputLength = 1000
    /// Deepest accepted nesting of parentheses and unary signs.
    public static let maxNesting = 64

    /// Returns the SI value (m, m², m³, rad, rise/run, plain number; percentages return a
    /// fraction, so `"25%"` and `"25"` both give `0.25`; integers return `Double(Int)`).
    /// Throws `QuantityParseError` with a helpful message for anything it cannot read safely.
    public static func parse(_ text: String, kind: UnitKind, units: UnitsSettings, locale: Locale = .current) throws -> Double {
        guard text.count <= maxInputLength else {
            throw QuantityParseError("That entry is too long (the limit is \(maxInputLength) characters).")
        }
        let separator = NumericText.decimalSeparator(units: units, locale: locale)
        var lexer = QLexer(text: text, separator: separator, currencySymbol: units.currencySymbol)
        let tokens = try lexer.tokenize()
        var parser = QParser(tokens: tokens, kind: kind, units: units)
        return try parser.run()
    }
}

// MARK: - Lexer

struct QToken {
    enum Kind {
        case number(Double, isFraction: Bool)
        case unit(UnitSpec, String)
        case plus, minus, times, divide, lparen, rparen, colon, currency
    }
    var kind: Kind
    var text: String

    var isNumber: Bool { if case .number = kind { return true } else { return false } }
    var unitSpec: UnitSpec? { if case .unit(let u, _) = kind { return u } else { return nil } }
}

struct QLexer {
    let chars: [Character]
    let separator: Character
    let currencySymbol: [Character]
    var i = 0

    init(text: String, separator: Character, currencySymbol: String) {
        self.chars = Array(text)
        self.separator = separator
        self.currencySymbol = Array(currencySymbol.trimmingCharacters(in: .whitespaces))
    }

    private var otherSeparator: Character { separator == "," ? "." : "," }

    private func isDigit(_ k: Int) -> Bool { k < chars.count && chars[k].isASCIIDigitChar }

    private func matchesCurrency(at k: Int) -> Int? {
        if "$€£¥".contains(chars[k]) { return 1 }
        guard !currencySymbol.isEmpty, k + currencySymbol.count <= chars.count else { return nil }
        return Array(chars[k..<k + currencySymbol.count]) == currencySymbol ? currencySymbol.count : nil
    }

    mutating func tokenize() throws -> [QToken] {
        var tokens: [QToken] = []
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        if i < chars.count, chars[i] == "=" { i += 1 }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            let start = i
            if c.isASCIIDigitChar || (c == separator && isDigit(i + 1)) {
                let (value, isFraction) = try scanNumber()
                tokens.append(QToken(kind: .number(value, isFraction: isFraction), text: String(chars[start..<i])))
                continue
            }
            if c == otherSeparator && (c == "." || isDigit(i + 1)) {
                if separator == "," {
                    throw QuantityParseError("Use ',' as the decimal separator (for example 3,5).")
                }
                throw QuantityParseError("Use '.' as the decimal separator; digit grouping with ',' isn't supported.")
            }
            if let n = matchesCurrency(at: i) {
                i += n
                tokens.append(QToken(kind: .currency, text: String(chars[start..<i])))
                continue
            }
            if c.isASCIILetterChar {
                tokens.append(try scanWordUnit())
                continue
            }
            if UnitCatalog.isPrimeCharacter(c) {
                // Two primes in a row are commonly typed for inches: 6''
                if i + 1 < chars.count, UnitCatalog.isPrimeCharacter(chars[i + 1]) {
                    i += 2
                    tokens.append(QToken(kind: .unit(UnitCatalog.doublePrime, "\""), text: "''"))
                } else {
                    i += 1
                    tokens.append(QToken(kind: .unit(UnitCatalog.prime, "'"), text: "'"))
                }
                continue
            }
            if let spec = UnitCatalog.symbol(c) {
                i += 1
                tokens.append(QToken(kind: .unit(spec, String(c)), text: String(c)))
                continue
            }
            let kind: QToken.Kind
            switch c {
            case "+": kind = .plus
            case "-", "−", "–": kind = .minus
            case "*", "×": kind = .times
            case "/", "÷": kind = .divide
            case "(": kind = .lparen
            case ")": kind = .rparen
            case ":": kind = .colon
            case "=": throw QuantityParseError("'=' is only allowed at the start of an entry.")
            default: throw QuantityParseError("Unexpected character '\(c)'.")
            }
            i += 1
            tokens.append(QToken(kind: kind, text: String(c)))
        }
        return tokens
    }

    /// Scans digits with an optional decimal part. Returns the digits as normalised text and
    /// whether it was an integer.
    private mutating func scanDecimal() -> (String, Bool) {
        var s = ""
        var isInteger = true
        while i < chars.count {
            let c = chars[i]
            if c.isASCIIDigitChar {
                s.append(c)
            } else if c == separator && isInteger && (!s.isEmpty || isDigit(i + 1)) {
                isInteger = false
                s.append(".")
            } else {
                break
            }
            i += 1
        }
        return (s, isInteger)
    }

    private mutating func scanInteger() -> String? {
        var s = ""
        while i < chars.count, chars[i].isASCIIDigitChar { s.append(chars[i]); i += 1 }
        return s.isEmpty ? nil : s
    }

    /// Tries to read `N/D` (tight, integers) at the current position.
    private mutating func scanFraction() throws -> Double? {
        let save = i
        guard let n = scanInteger(), i < chars.count, chars[i] == "/", isDigit(i + 1) else { i = save; return nil }
        i += 1
        guard let d = scanInteger() else { i = save; return nil }
        // `3/2.5` is a division, not a fraction.
        if i < chars.count, chars[i] == separator, isDigit(i + 1) { i = save; return nil }
        guard let nv = Double(n), let dv = Double(d) else { i = save; return nil }
        guard dv != 0 else { throw QuantityParseError("Can't divide by zero.") }
        return nv / dv
    }

    private mutating func scanNumber() throws -> (Double, Bool) {
        let start = i
        if let f = try scanFraction() { return (f, true) }
        let (text, isInteger) = scanDecimal()
        guard let whole = Double(text), whole.isFinite else {
            throw QuantityParseError("'\(String(chars[start..<i]))' is too large.")
        }
        if isInteger {
            // Mixed number: `6 1/2`
            let save = i
            var k = i
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            if k > i, isDigit(k) {
                i = k
                if let f = try scanFraction() { return (whole + f, false) }
                i = save
            }
        }
        return (whole, false)
    }

    private mutating func scanLetters() -> String {
        var s = ""
        while i < chars.count, chars[i].isASCIILetterChar { s.append(chars[i]); i += 1 }
        return s
    }

    private mutating func scanWordUnit() throws -> QToken {
        let start = i
        let word = scanLetters()
        if let power = UnitCatalog.powerPrefix(word.lowercased()) {
            var k = i
            if k < chars.count, chars[k] == "." { k += 1 }
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            let save = i
            i = k
            let base = scanLetters()
            if !base.isEmpty, let spec = UnitCatalog.unit(word: base, exponent: power) {
                if i < chars.count, chars[i] == "." { i += 1 }
                return QToken(kind: .unit(spec, String(chars[start..<i])), text: String(chars[start..<i]))
            }
            i = save
            if word.lowercased() != "sq" && word.lowercased() != "cu" {
                // "square"/"cubic" alone are not units.
                throw QuantityParseError("Expected a unit after '\(word)' (for example \(word) m).")
            }
        }
        if let (e, n) = UnitCatalog.exponentSuffix(chars, at: i, allowCaret: true) {
            if let spec = UnitCatalog.unit(word: word, exponent: e) {
                i += n
                return QToken(kind: .unit(spec, String(chars[start..<i])), text: String(chars[start..<i]))
            }
        }
        if let spec = UnitCatalog.unit(word: word) {
            return QToken(kind: .unit(spec, word), text: word)
        }
        if word.lowercased() == "x" {
            throw QuantityParseError("Use * to multiply (for example 1200 * 2).")
        }
        throw QuantityParseError("Unknown unit '\(word)'.")
    }
}

// MARK: - Parser / evaluator

/// An intermediate value: SI magnitude, dimension, and whether it came only from unit-less numbers.
struct QValue {
    var value: Double
    var dimension: Dimension
    /// Built only from numbers without units; takes the display unit when the entry is finished.
    var bare: Bool
    /// A bare `a/b` (fraction or division): read as rise/run in slope fields.
    var bareRatio = false
    /// Role of a single literal's unit, used for compound entries such as `12' 6"`.
    var role: UnitRole?
    /// True for a single number literal (not a parenthesised or computed value).
    var isLiteral = false
}

struct QParser {
    let tokens: [QToken]
    let kind: UnitKind
    let units: UnitsSettings
    var i = 0
    var nesting = 0

    init(tokens: [QToken], kind: UnitKind, units: UnitsSettings) {
        self.tokens = tokens
        self.kind = kind
        self.units = units
    }

    private var peek: QToken? { i < tokens.count ? tokens[i] : nil }
    private func peek(_ offset: Int) -> QToken? { i + offset < tokens.count ? tokens[i + offset] : nil }

    mutating func run() throws -> Double {
        guard !tokens.isEmpty else { throw QuantityParseError("Enter a value.") }
        var q = try parseExpression()
        if let t = peek, case .colon = t.kind {
            guard kind == .slope else {
                throw QuantityParseError("':' is only used for slope ratios such as 1:12.")
            }
            i += 1
            let run = try parseExpression()
            q = try ratio(q, run)
        }
        if let t = peek { throw unexpected(t) }
        return try finish(q)
    }

    private func unexpected(_ t: QToken) -> QuantityParseError {
        switch t.kind {
        case .rparen: return QuantityParseError("There's a ')' without a matching '('.")
        case .number: return QuantityParseError("Missing operator before '\(t.text)' (use + - * /).")
        case .unit: return QuantityParseError("Unexpected unit '\(t.text)'.")
        default: return QuantityParseError("Unexpected '\(t.text)'.")
        }
    }

    private mutating func enter() throws {
        nesting += 1
        if nesting > QuantityParser.maxNesting || StackGuard.isLow {
            throw QuantityParseError("The entry is nested too deeply.")
        }
    }

    // expression := term (('+' | '-') term)*
    private mutating func parseExpression() throws -> QValue {
        var left = try parseTerm()
        while let t = peek {
            let subtract: Bool
            switch t.kind {
            case .plus: subtract = false
            case .minus: subtract = true
            default: return left
            }
            i += 1
            let right = try parseTerm()
            left = try add(left, right, subtract: subtract)
        }
        return left
    }

    // term := unary (('*' | '/') unary)*
    private mutating func parseTerm() throws -> QValue {
        var left = try parseUnary()
        while let t = peek {
            switch t.kind {
            case .times:
                i += 1
                let r = try parseUnary()
                left = QValue(value: left.value * r.value, dimension: left.dimension * r.dimension, bare: left.bare && r.bare)
            case .divide:
                i += 1
                let r = try parseUnary()
                guard r.value != 0 else { throw QuantityParseError("Can't divide by zero.") }
                left = QValue(value: left.value / r.value, dimension: left.dimension / r.dimension,
                              bare: left.bare && r.bare, bareRatio: left.bare && r.bare)
            default:
                return left
            }
            guard left.value.isFinite else { throw QuantityParseError("The result is too large.") }
        }
        return left
    }

    // unary := ('-' | '+') unary | compound
    // Functions on the recursion path (expression → term → unary → compound → parenthesized)
    // stay small; literal and compound-entry handling lives in non-recursive helpers.
    private mutating func parseUnary() throws -> QValue {
        guard i < tokens.count else { throw QuantityParseError("The entry ends unexpectedly; a value is missing.") }
        switch tokens[i].kind {
        case .minus, .plus:
            let negative: Bool
            if case .minus = tokens[i].kind { negative = true } else { negative = false }
            i += 1
            try enter()
            var q = try parseUnary()
            nesting -= 1
            if negative { q.value = -q.value }
            q.isLiteral = false
            return q
        case .currency:
            guard kind == .currency else {
                throw QuantityParseError("Currency symbols are only allowed in currency fields.")
            }
            i += 1
            return try parseUnary()
        default:
            return try parseCompound()
        }
    }

    // compound := '(' expression ')' | literal [inch-term | minutes/seconds | feet-inch pair]
    private mutating func parseCompound() throws -> QValue {
        guard i < tokens.count, case .lparen = tokens[i].kind else { return try compoundLiteral() }
        i += 1
        try enter()
        var q = try parseExpression()
        guard i < tokens.count, case .rparen = tokens[i].kind else { throw QuantityParseError("Missing ')'.") }
        i += 1
        nesting -= 1
        q.isLiteral = false
        q.role = nil
        try rejectJuxtaposition(after: q, first: q)
        return q
    }

    // literal := number unit? currency?
    private mutating func literal() throws -> QValue {
        guard i < tokens.count else { throw QuantityParseError("The entry ends unexpectedly; a value is missing.") }
        let t = tokens[i]
        switch t.kind {
        case .number(let v, let isFraction):
            i += 1
            var q = QValue(value: v, dimension: .none, bare: true, bareRatio: isFraction, role: nil, isLiteral: true)
            if let u = peek?.unitSpec {
                i += 1
                let spec = resolve(u)
                q = QValue(value: v * spec.factor, dimension: spec.dimension, bare: false, role: spec.role, isLiteral: true)
            }
            if let c = peek, case .currency = c.kind {
                guard kind == .currency else {
                    throw QuantityParseError("Currency symbols are only allowed in currency fields.")
                }
                i += 1
            }
            guard q.value.isFinite else { throw QuantityParseError("'\(t.text)' is too large.") }
            return q
        case .unit:
            throw QuantityParseError("'\(t.text)' needs a number before it.")
        case .rparen:
            throw QuantityParseError("A value is missing before ')'.")
        default:
            throw QuantityParseError("A value is missing before '\(t.text)'.")
        }
    }

    /// Primes mean arcminutes/arcseconds in angle fields and feet/inches everywhere else.
    private func resolve(_ u: UnitSpec) -> UnitSpec {
        switch u.role {
        case .prime: kind == .angle ? UnitCatalog.arcminutes : UnitCatalog.feet
        case .doublePrime: kind == .angle ? UnitCatalog.arcseconds : UnitCatalog.inches
        default: u
        }
    }

    private func isInchRole(_ r: UnitRole?) -> Bool { r == .inch }

    /// Whether the tokens after a `-` that follows a feet term form an inch term (`12' - 6 1/2"`).
    private func dashStartsInchTerm() -> Bool {
        guard let n = peek(1), n.isNumber else { return false }
        guard let after = peek(2) else { return true }
        switch after.kind {
        case .unit(let u, _): return resolve(u).role == .inch
        case .plus, .minus, .rparen, .colon: return true
        default: return false
        }
    }

    /// A literal plus any juxtaposed parts: `12' 6"`, `12'-6 1/2"`, `12 6`, `45°30'15"`.
    private mutating func compoundLiteral() throws -> QValue {
        let first = try literal()
        var q = first
        if first.isLiteral {
            switch first.role {
            case .feet:
                var hasInches = false
                if let t = peek, case .minus = t.kind, dashStartsInchTerm() {
                    i += 1
                    hasInches = true
                } else if peek?.isNumber == true {
                    hasInches = true
                }
                if hasInches {
                    let b = try literal()
                    if b.bare {
                        q.value += b.value * UnitCatalog.inch
                    } else if isInchRole(b.role) {
                        q.value += b.value
                    } else {
                        throw QuantityParseError("After feet, expected inches (for example 12' 6\").")
                    }
                    q.role = nil
                    q.isLiteral = false
                }
            case .degree:
                if peek?.isNumber == true {
                    let b = try literal()
                    if b.role == .arcminute {
                        q.value += b.value
                        if peek?.isNumber == true {
                            let c = try literal()
                            guard c.role == .arcsecond else {
                                throw QuantityParseError("After minutes, expected seconds (for example 45°30'15\").")
                            }
                            q.value += c.value
                        }
                    } else if b.role == .arcsecond {
                        q.value += b.value
                    } else {
                        throw QuantityParseError("After degrees, expected minutes (') or seconds (\"), for example 45°30'.")
                    }
                    q.role = nil
                    q.isLiteral = false
                }
            case .arcminute:
                if peek?.isNumber == true {
                    let b = try literal()
                    guard b.role == .arcsecond else {
                        throw QuantityParseError("After minutes, expected seconds (for example 30'15\").")
                    }
                    q.value += b.value
                    q.role = nil
                    q.isLiteral = false
                }
            case nil where first.bare && kind == .length && units.length.isFeetBased && peek?.isNumber == true:
                // `12 6` → 12 ft 6 in
                let b = try literal()
                let inches: Double
                if b.bare {
                    guard b.value >= 0 && b.value < 12 else {
                        throw QuantityParseError("In an entry like '12 6' the inches must be less than 12.")
                    }
                    inches = b.value * UnitCatalog.inch
                } else if isInchRole(b.role) {
                    inches = b.value
                } else {
                    throw QuantityParseError("After feet, expected inches (for example 12 6 or 12' 6\").")
                }
                q = QValue(value: first.value * UnitCatalog.foot + inches, dimension: .length, bare: false)
            default:
                break
            }
        }
        try rejectJuxtaposition(after: q, first: first)
        return q
    }

    /// Two values side by side without an operator are an error (with a hint for `1 200`).
    private func rejectJuxtaposition(after q: QValue, first: QValue) throws {
        if let t = peek {
            switch t.kind {
            case .number:
                if q.bare && first.isLiteral {
                    throw QuantityParseError("Unexpected space between numbers ('\(tokenText(first: first, next: t))'). Digit grouping isn't supported — type the number without spaces, or use + - * / between values.")
                }
                throw QuantityParseError("Missing operator before '\(t.text)'. Use + to combine values with different units (for example 3 m + 500 mm).")
            case .lparen:
                throw QuantityParseError("Missing operator before '(' (use * to multiply).")
            default:
                break
            }
        }
    }

    private func tokenText(first: QValue, next: QToken) -> String {
        guard i >= 1 else { return next.text }
        return "\(tokens[i - 1].text) \(next.text)"
    }

    /// Display unit for bare numbers in this field.
    private var bareUnit: (factor: Double, dimension: Dimension) {
        switch kind {
        case .length: (units.length.metersPerUnit, .length)
        case .area: (units.area.squareMetersPerUnit, .area)
        case .volume: (units.volume.cubicMetersPerUnit, .volume)
        case .angle: (UnitCatalog.degree, .angle)
        case .slope:
            switch units.slope {
            case .degrees: (UnitCatalog.degree, .angle)
            case .risePer12Inches: (1.0 / 12, .none)
            case .percent: (0.01, .none)
            case .ratio: (1, .none)
            }
        case .percentage: (0.01, .none)
        case .number, .integer, .currency: (1, .none)
        }
    }

    private func applyBareUnit(_ q: QValue) -> QValue {
        guard q.bare else { return q }
        let u = bareUnit
        return QValue(value: q.value * u.factor, dimension: u.dimension, bare: false)
    }

    private func add(_ a: QValue, _ b: QValue, subtract: Bool) throws -> QValue {
        if a.bare && b.bare {
            let v = subtract ? a.value - b.value : a.value + b.value
            return QValue(value: v, dimension: .none, bare: true)
        }
        let l = applyBareUnit(a), r = applyBareUnit(b)
        guard l.dimension == r.dimension else {
            throw QuantityParseError(subtract
                ? "Can't subtract \(r.dimension.phrase) from \(l.dimension.phrase)."
                : "Can't add \(l.dimension.phrase) and \(r.dimension.phrase).")
        }
        let v = subtract ? l.value - r.value : l.value + r.value
        guard v.isFinite else { throw QuantityParseError("The result is too large.") }
        return QValue(value: v, dimension: l.dimension, bare: false)
    }

    private func ratio(_ rise: QValue, _ run: QValue) throws -> QValue {
        guard rise.dimension == run.dimension, rise.bare == run.bare else {
            throw QuantityParseError("Both sides of a ratio must use the same units (for example 1:12 or 6\":12\").")
        }
        guard run.value != 0 else { throw QuantityParseError("The run of a ratio can't be zero.") }
        return QValue(value: rise.value / run.value, dimension: .none, bare: false)
    }

    private func finish(_ input: QValue) throws -> Double {
        if kind == .slope { return try finishSlope(input) }
        let q = applyBareUnit(input)
        let expected = Dimension(kind: kind)
        guard q.dimension == expected else {
            var message = "Expected \(kind.phrase) but got \(q.dimension.phrase)"
            if kind == .length && q.dimension == .area {
                message += " — multiplying two lengths gives an area"
            } else if kind == .length && q.dimension == .none {
                message += " — ratios and percentages can't be used as a length on their own"
            }
            throw QuantityParseError(message + ".")
        }
        guard q.value.isFinite else { throw QuantityParseError("The result is too large.") }
        if kind == .integer {
            let r = q.value.rounded()
            guard abs(q.value - r) <= 1e-9 * max(1, abs(r)) else {
                throw QuantityParseError("Enter a whole number.")
            }
            guard abs(r) <= 9_007_199_254_740_992 else { throw QuantityParseError("The number is too large.") }
            return r == 0 ? 0 : r
        }
        return q.value == 0 ? 0 : q.value
    }

    private func slopeFromAngle(_ radians: Double) throws -> Double {
        guard abs(radians) < Double.pi / 2 - 1e-9 else {
            throw QuantityParseError("A slope angle must be between -90° and 90°.")
        }
        return tan(radians)
    }

    private func finishSlope(_ q: QValue) throws -> Double {
        let result: Double
        if q.dimension == .angle {
            result = try slopeFromAngle(q.value)
        } else if q.dimension == .none {
            if q.bare && !q.bareRatio {
                switch units.slope {
                case .degrees: result = try slopeFromAngle(q.value * UnitCatalog.degree)
                case .risePer12Inches: result = q.value / 12
                case .percent: result = q.value / 100
                case .ratio:
                    guard q.value != 0 else { throw QuantityParseError("Enter a ratio such as 1:12.") }
                    result = 1 / q.value
                }
            } else {
                result = q.value
            }
        } else {
            throw QuantityParseError("Expected a slope (an angle, a ratio such as 1:12, or a percentage) but got \(q.dimension.phrase).")
        }
        guard result.isFinite else { throw QuantityParseError("The slope is too steep.") }
        return result == 0 ? 0 : result
    }
}
