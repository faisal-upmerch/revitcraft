import Foundation

/// A parsed formula for family/project parameters, calculated schedule fields and conditional
/// formatting.
///
/// Language summary:
/// - Numbers are dimensionless unless followed by a unit: `600 mm`, `0.6 m`, `2'`, `6"`,
///   `2' 6"`, `6 1/2"`, `30°`, `45 deg`, `0.5 rad`, `25%` (= 0.25), `10 m²`, `3 CF`.
///   Decimals always use `.` (commas separate arguments; `;` is accepted as a separator too).
/// - Parameter names are matched against `knownNames` with greedy longest match, case-sensitive,
///   so names may contain spaces (`Rough Width`, `Frame Width 2`). `[Any Name]` also works.
/// - Operators: `+ - * / ^`, unary minus, parentheses, comparisons `< > = <= >= <>`
///   (`!=` is accepted for `<>`). `-` is always subtraction in formulas (`2' - 6"` is 1'6").
/// - Literals: `true`, `false`, `pi`, `"text"` (text supports only `=` and `<>`).
/// - Functions: `if(c, a, b)` (lazy), `and(…)`, `or(…)`, `not(x)`, `sin cos tan` (an angle
///   argument is used as is; a dimensionless argument is read as **degrees**), `asin acos atan
///   atan2` (return angles), `sqrt` (halves dimension exponents; odd exponents are an error),
///   `abs`, `round roundup rounddown`, `min(…)`, `max(…)`, `exp ln log` (dimensionless only),
///   `pi()`. Rounding works in whole display units of the value's dimension: 1 mm / 1 cm / 1 m,
///   1 inch in feet-and-inches and inch displays, 1 ft in decimal feet, one m² / SF / mm²,
///   one m³ / CF / L, 1° for angles, and integers for plain numbers. `round` is half away from
///   zero, `roundup` towards +∞, `rounddown` towards −∞.
/// - Dimensional analysis: `+ -` and comparisons need matching dimensions, except that a
///   dimensionless `0` combines with anything; `* /` combine dimensions; `^` needs a
///   dimensionless exponent, and an integer exponent (|n| ≤ 64) for a dimensioned base.
/// - Safety: at most 4096 characters and 256 levels of nesting (fewer if the calling thread's
///   stack runs low); division by zero, NaN and infinity are reported as `FormulaError`s and
///   never escape.
///
/// Two formulas are equal when their source and referenced names are equal.
public struct Formula: Sendable, Hashable {
    /// Longest accepted formula, in characters.
    public static let maxLength = 4096
    /// Deepest accepted nesting of parentheses, function calls, unary signs and exponents.
    public static let maxDepth = 256

    /// The formula text as written.
    public let source: String
    let root: FormulaNode
    private let names: Set<String>

    /// Parses `source`. Throws `FormulaError` for syntax errors and names not in `knownNames`.
    public init(_ source: String, knownNames: Set<String>) throws {
        try self.init(source, names: FormulaNames(knownNames))
    }

    /// Parses `source` against a prebuilt name table (cheap to reuse across many formulas).
    init(_ source: String, names table: FormulaNames) throws {
        guard source.count <= Formula.maxLength else {
            throw FormulaError("The formula is too long (the limit is \(Formula.maxLength) characters).")
        }
        var lexer = FormulaLexer(source: source, names: table)
        let tokens = try lexer.tokenize()
        var parser = FormulaParser(tokens: tokens, endPosition: source.count)
        let root = try parser.parse()
        self.source = source
        self.root = root
        var collected = Set<String>()
        for token in tokens {
            if case .name(let n) = token.kind { collected.insert(n) }
        }
        self.names = collected
    }

    /// Parameter names the formula refers to.
    public var referencedNames: Set<String> { names }

    /// Equal when source and referenced names match (never walks the possibly deep syntax tree).
    public static func == (a: Formula, b: Formula) -> Bool { a.source == b.source && a.names == b.names }
    /// Hashes the source text.
    public func hash(into hasher: inout Hasher) { hasher.combine(source) }

    /// Evaluates the formula. `lookup` supplies parameter values (return nil for "no value").
    /// `units` controls the display unit used by `round`, `roundup` and `rounddown`.
    public func evaluate(units: UnitsSettings = .metric, _ lookup: (String) -> FormulaValue?) throws -> FormulaValue {
        let evaluator = FormulaEvaluator(units: units)
        return try evaluator.evaluate(root, lookup)
    }
}

// MARK: - Name table

/// Known parameter names in a trie for greedy longest-match lookup at any text position.
struct FormulaNames: Sendable {
    private var children: [[Character: Int]] = [[:]]
    private var terminal: [String?] = [nil]
    let all: Set<String>

    init(_ names: Set<String>) {
        all = names
        for name in names where !name.isEmpty {
            var node = 0
            for c in name {
                if let next = children[node][c] {
                    node = next
                } else {
                    children.append([:])
                    terminal.append(nil)
                    children[node][c] = children.count - 1
                    node = children.count - 1
                }
            }
            terminal[node] = name
        }
    }

    /// The longest known name starting at `start` that ends on an identifier boundary
    /// (so "Width" doesn't match inside "Widths"). Returns the name and its end index.
    func longestMatch(in chars: [Character], at start: Int) -> (String, Int)? {
        var node = 0
        var best: (String, Int)?
        var k = start
        while k < chars.count, let next = children[node][chars[k]] {
            node = next
            k += 1
            if let name = terminal[node] {
                let lastIsWord = FormulaLexer.isIdentifierChar(chars[k - 1])
                if k == chars.count || !lastIsWord || !FormulaLexer.isIdentifierChar(chars[k]) {
                    best = (name, k)
                }
            }
        }
        return best
    }
}

// MARK: - Lexer

struct FormulaToken {
    enum Kind: Equatable {
        case number(Double, Dimension)
        case text(String)
        case name(String)
        case function(FormulaFunction)
        case keyword(String)
        case op(FormulaBinaryOperator)
        case lparen, rparen, comma
    }
    var kind: Kind
    var pos: Int
}

struct FormulaLexer {
    let chars: [Character]
    let names: FormulaNames
    var i = 0

    init(source: String, names: FormulaNames) {
        chars = Array(source)
        self.names = names
    }

    static func isIdentifierChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
    private func isIdentifierChar(_ c: Character) -> Bool { Self.isIdentifierChar(c) }
    private func isDigit(_ k: Int) -> Bool { k < chars.count && chars[k].isASCIIDigitChar }

    mutating func tokenize() throws -> [FormulaToken] {
        var tokens: [FormulaToken] = []
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        if i < chars.count, chars[i] == "=" { i += 1 }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            let start = i
            if let name = matchKnownName() {
                tokens.append(FormulaToken(kind: .name(name), pos: start))
                continue
            }
            if c.isASCIIDigitChar || (c == "." && isDigit(i + 1)) {
                let (value, dim) = try lexQuantity()
                tokens.append(FormulaToken(kind: .number(value, dim), pos: start))
                continue
            }
            if c == "\"" || c == "“" {
                tokens.append(FormulaToken(kind: .text(try lexString()), pos: start))
                continue
            }
            if c == "[" {
                tokens.append(FormulaToken(kind: .name(try lexBracketName()), pos: start))
                continue
            }
            if c.isLetter || c == "_" {
                tokens.append(try lexIdentifier())
                continue
            }
            let two = i + 1 < chars.count ? String([c, chars[i + 1]]) : ""
            let op2: FormulaBinaryOperator? = switch two {
            case "<=": .lessOrEqual
            case ">=": .greaterOrEqual
            case "<>", "!=": .notEqual
            case "==": .equal
            default: nil
            }
            if let op2 {
                i += 2
                tokens.append(FormulaToken(kind: .op(op2), pos: start))
                continue
            }
            let kind: FormulaToken.Kind
            switch c {
            case "+": kind = .op(.add)
            case "-", "−", "–": kind = .op(.subtract)
            case "*", "×": kind = .op(.multiply)
            case "/", "÷": kind = .op(.divide)
            case "^": kind = .op(.power)
            case "<": kind = .op(.less)
            case ">": kind = .op(.greater)
            case "=": kind = .op(.equal)
            case "≤": kind = .op(.lessOrEqual)
            case "≥": kind = .op(.greaterOrEqual)
            case "≠": kind = .op(.notEqual)
            case "(": kind = .lparen
            case ")": kind = .rparen
            case ",", ";": kind = .comma
            default:
                throw FormulaError("Unexpected character '\(c)'.", position: start)
            }
            i += 1
            tokens.append(FormulaToken(kind: kind, pos: start))
        }
        return tokens
    }

    /// Greedy longest match of a known name at the current position.
    private mutating func matchKnownName() -> String? {
        guard let (name, end) = names.longestMatch(in: chars, at: i) else { return nil }
        i = end
        return name
    }

    private mutating func lexString() throws -> String {
        let start = i
        let close: Character = chars[i] == "“" ? "”" : "\""
        i += 1
        var s = ""
        while i < chars.count {
            if chars[i] == close {
                if close == "\"", i + 1 < chars.count, chars[i + 1] == "\"" {
                    s.append("\"")
                    i += 2
                    continue
                }
                i += 1
                return s
            }
            s.append(chars[i])
            i += 1
        }
        throw FormulaError("Text is missing its closing quote.", position: start)
    }

    private mutating func lexBracketName() throws -> String {
        let start = i
        i += 1
        var s = ""
        while i < chars.count, chars[i] != "]" {
            s.append(chars[i])
            i += 1
        }
        guard i < chars.count else { throw FormulaError("Missing ']' after a parameter name.", position: start) }
        i += 1
        let name = s.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw FormulaError("Empty parameter name '[]'.", position: start) }
        guard names.all.contains(name) else {
            throw FormulaError("Unknown parameter '\(name)'.", position: start)
        }
        return name
    }

    private mutating func lexIdentifier() throws -> FormulaToken {
        let start = i
        var word = ""
        while i < chars.count, isIdentifierChar(chars[i]) { word.append(chars[i]); i += 1 }
        let lower = word.lowercased()
        var k = i
        while k < chars.count, chars[k].isWhitespace { k += 1 }
        let isCall = k < chars.count && chars[k] == "("
        if let f = FormulaFunction(rawValue: lower), f != .pi || isCall {
            guard isCall else {
                throw FormulaError("\(lower)() needs parentheses: \(f.usage).", position: start)
            }
            return FormulaToken(kind: .function(f), pos: start)
        }
        if lower == "true" || lower == "false" || lower == "pi" {
            return FormulaToken(kind: .keyword(lower), pos: start)
        }
        if lower == "size_lookup" {
            throw FormulaError("size_lookup isn't supported in Arcus formulas.", position: start)
        }
        if isCall {
            throw FormulaError("Unknown function '\(word)'.", position: start)
        }
        // Report the whole multi-word phrase so the user sees which name didn't match.
        var phrase = word
        var j = i
        while true {
            var s = j
            while s < chars.count, chars[s] == " " { s += 1 }
            guard s > j, s < chars.count, chars[s].isLetter else { break }
            var next = ""
            var e = s
            while e < chars.count, isIdentifierChar(chars[e]) { next.append(chars[e]); e += 1 }
            phrase += String(repeating: " ", count: s - j) + next
            j = e
        }
        throw FormulaError("Unknown parameter '\(phrase)'.", position: start)
    }

    // MARK: Numbers with units

    private mutating func scanDecimal() -> Double? {
        var s = ""
        var seenDot = false
        while i < chars.count {
            let c = chars[i]
            if c.isASCIIDigitChar {
                s.append(c)
            } else if c == "." && !seenDot && (isDigit(i + 1) || !s.isEmpty) {
                seenDot = true
                s.append(".")
            } else {
                break
            }
            i += 1
        }
        return Double(s)
    }

    private mutating func scanInteger() -> Double? {
        var s = ""
        while i < chars.count, chars[i].isASCIIDigitChar { s.append(chars[i]); i += 1 }
        return s.isEmpty ? nil : Double(s)
    }

    private func isMark(_ k: Int) -> Bool {
        k < chars.count && (UnitCatalog.isPrimeCharacter(chars[k]) || UnitCatalog.isDoublePrimeCharacter(chars[k]))
    }

    /// Tight `N/D` immediately followed by a foot or inch mark (`1/2"`); otherwise `/` is division.
    private mutating func scanMarkedFraction() throws -> Double? {
        let save = i
        guard let n = scanInteger(), i < chars.count, chars[i] == "/", isDigit(i + 1) else { i = save; return nil }
        i += 1
        guard let d = scanInteger(), isMark(i) else { i = save; return nil }
        guard d != 0 else { throw FormulaError("Division by zero.", position: save) }
        return n / d
    }

    /// A number, including `1/2"` fractions and `6 1/2"` mixed numbers before a mark.
    private mutating func scanMagnitude() throws -> Double? {
        let start = i
        if let f = try scanMarkedFraction() { return f }
        guard let whole = scanDecimal() else { i = start; return nil }
        let wasInteger = !chars[start..<i].contains(".")
        if wasInteger {
            let save = i
            var k = i
            while k < chars.count, chars[k] == " " { k += 1 }
            if k > i, isDigit(k) {
                i = k
                if let f = try scanMarkedFraction() { return whole + f }
            }
            i = save
        }
        return whole
    }

    /// Reads a unit right after a number. Returns nil (position unchanged) when there is none.
    private mutating func scanUnit() -> UnitSpec? {
        guard i < chars.count else { return nil }
        let c = chars[i]
        if UnitCatalog.isPrimeCharacter(c) {
            if i + 1 < chars.count, UnitCatalog.isPrimeCharacter(chars[i + 1]) {
                i += 2
                return UnitCatalog.inches
            }
            i += 1
            return UnitCatalog.feet
        }
        if UnitCatalog.isDoublePrimeCharacter(c) && c != "“" {
            i += 1
            return UnitCatalog.inches
        }
        if c == "°" || c == "º" { i += 1; return UnitCatalog.degrees }
        if c == "%" { i += 1; return UnitCatalog.percent }
        let save = i
        while i < chars.count, chars[i] == " " { i += 1 }
        var word = ""
        while i < chars.count, chars[i].isASCIILetterChar { word.append(chars[i]); i += 1 }
        guard !word.isEmpty, i >= chars.count || !isIdentifierChar(chars[i]) || UnitCatalog.exponentSuffix(chars, at: i, allowCaret: false) != nil else {
            i = save
            return nil
        }
        if let power = UnitCatalog.powerPrefix(word.lowercased()) {
            let afterPrefix = i
            while i < chars.count, chars[i] == " " { i += 1 }
            var base = ""
            while i < chars.count, chars[i].isASCIILetterChar { base.append(chars[i]); i += 1 }
            if !base.isEmpty, i >= chars.count || !isIdentifierChar(chars[i]), let spec = UnitCatalog.unit(word: base, exponent: power) {
                return spec
            }
            i = afterPrefix
        }
        if let (e, n) = UnitCatalog.exponentSuffix(chars, at: i, allowCaret: false), let spec = UnitCatalog.unit(word: word, exponent: e) {
            i += n
            return spec
        }
        if let spec = UnitCatalog.unit(word: word) {
            return spec
        }
        i = save
        return nil
    }

    /// Looks ahead for `<number><mark>` where the mark is prime or double prime; consumes on success.
    private mutating func scanMarkedFollower(prime: Bool) throws -> Double? {
        let save = i
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard isDigit(i) || (i < chars.count && chars[i] == "." && isDigit(i + 1)) else { i = save; return nil }
        guard let v = try scanMagnitude(), i < chars.count else { i = save; return nil }
        let isPrime = UnitCatalog.isPrimeCharacter(chars[i]) && !(i + 1 < chars.count && UnitCatalog.isPrimeCharacter(chars[i + 1]))
        let isDouble = (UnitCatalog.isDoublePrimeCharacter(chars[i]) && chars[i] != "“")
            || (UnitCatalog.isPrimeCharacter(chars[i]) && i + 1 < chars.count && UnitCatalog.isPrimeCharacter(chars[i + 1]))
        if prime && isPrime { i += 1; return v }
        if !prime && isDouble { i += UnitCatalog.isPrimeCharacter(chars[i]) ? 2 : 1; return v }
        i = save
        return nil
    }

    private mutating func lexQuantity() throws -> (Double, Dimension) {
        let start = i
        guard let magnitude = try scanMagnitude() else {
            throw FormulaError("Invalid number.", position: start)
        }
        guard magnitude.isFinite else { throw FormulaError("Number is too large.", position: start) }
        guard let unit = scanUnit() else { return (magnitude, .none) }
        var value = magnitude * unit.factor
        switch unit.role {
        case .feet:
            if let inches = try scanMarkedFollower(prime: false) { value += inches * UnitCatalog.inch }
        case .degree:
            if let minutes = try scanMarkedFollower(prime: true) {
                value += minutes * UnitCatalog.arcminutes.factor
            }
            if let seconds = try scanMarkedFollower(prime: false) {
                value += seconds * UnitCatalog.arcseconds.factor
            }
        default:
            break
        }
        guard value.isFinite else { throw FormulaError("Number is too large.", position: start) }
        return (value, unit.dimension)
    }
}

// MARK: - Parser

/// Precedence-climbing recursive-descent parser.
///
/// Recursion happens only at real nesting (parentheses, calls, unary signs, exponents); runs of
/// `+ -` / `* /` become flat `.chain` nodes. Nesting is capped at `Formula.maxDepth` and also
/// stops early if the current thread's stack runs low, so hostile input can't overflow the
/// stack. The syntax tree is therefore at most about `4 × maxDepth` levels deep.
/// Hot recursive functions build no strings; error messages come from cold helpers.
struct FormulaParser {
    let tokens: [FormulaToken]
    let endPosition: Int
    var i = 0
    var nesting = 0

    init(tokens: [FormulaToken], endPosition: Int) {
        self.tokens = tokens
        self.endPosition = endPosition
    }

    private var position: Int { i < tokens.count ? tokens[i].pos : endPosition }

    private static let comparisonLevel = 1, additiveLevel = 2, multiplicativeLevel = 3, powerLevel = 4

    private static func level(_ op: FormulaBinaryOperator) -> Int {
        switch op {
        case .add, .subtract: additiveLevel
        case .multiply, .divide: multiplicativeLevel
        case .power: powerLevel
        default: comparisonLevel
        }
    }

    private var peekOperator: FormulaBinaryOperator? {
        if i < tokens.count, case .op(let op) = tokens[i].kind { return op }
        return nil
    }

    private func isToken(_ kind: FormulaToken.Kind) -> Bool { i < tokens.count && tokens[i].kind == kind }

    mutating func parse() throws -> FormulaNode {
        guard !tokens.isEmpty else { throw FormulaError("The formula is empty.", position: 0) }
        let node = try parseExpression(0)
        if i < tokens.count {
            let t = tokens[i]
            switch t.kind {
            case .rparen: throw FormulaError("There's a ')' without a matching '('.", position: t.pos)
            case .comma: throw FormulaError("Unexpected ','; commas only separate function arguments.", position: t.pos)
            default: throw FormulaError("Missing operator (use + - * / ^ or a comparison).", position: t.pos)
            }
        }
        return node
    }

    /// Counts one level of nesting (parentheses, calls, unary signs, exponents).
    private mutating func enter() throws {
        nesting += 1
        if nesting > Formula.maxDepth || StackGuard.isLow {
            throw FormulaError("The formula is nested too deeply.", position: position)
        }
    }

    /// Parses operators whose level is at least `minLevel`.
    private mutating func parseExpression(_ minLevel: Int) throws -> FormulaNode {
        var left = try parsePrefix()
        while let op = peekOperator, Self.level(op) >= minLevel {
            let level = Self.level(op)
            let pos = tokens[i].pos
            i += 1
            if level == Self.additiveLevel || level == Self.multiplicativeLevel {
                var links = [FormulaChainLink(op: op, operand: try parseExpression(level + 1), pos: pos)]
                while let next = peekOperator, Self.level(next) == level {
                    let linkPos = tokens[i].pos
                    i += 1
                    links.append(FormulaChainLink(op: next, operand: try parseExpression(level + 1), pos: linkPos))
                }
                left = .chain(left, links)
            } else if level == Self.powerLevel {
                try enter()
                left = .binary(op, left, try parseExpression(level), pos: pos)
                nesting -= 1
            } else {
                left = .binary(op, left, try parseExpression(level + 1), pos: pos)
                if let again = peekOperator, again.isComparison {
                    throw FormulaError("Comparisons can't be chained; combine them with and(…).", position: position)
                }
            }
        }
        return left
    }

    /// Unary signs, literals, names, calls and parenthesised expressions.
    private mutating func parsePrefix() throws -> FormulaNode {
        guard i < tokens.count else {
            throw FormulaError("The formula ends unexpectedly; a value is missing.", position: endPosition)
        }
        let pos = tokens[i].pos
        if let op = peekOperator, op == .subtract || op == .add {
            i += 1
            try enter()
            // Unary minus binds looser than ^, so -2^2 = -(2^2); 2^-1 still works.
            let operand = try parseExpression(Self.powerLevel)
            nesting -= 1
            return op == .add ? operand : .negate(operand, pos: pos)
        }
        if isToken(.lparen) {
            i += 1
            try enter()
            let inner = try parseExpression(0)
            guard isToken(.rparen) else { throw FormulaError("Missing ')'.", position: position) }
            i += 1
            nesting -= 1
            return inner
        }
        if case .function(let f) = tokens[i].kind {
            i += 1
            return try parseCall(f, at: pos)
        }
        let node = try Self.leaf(tokens[i])
        i += 1
        return node
    }

    /// Converts a literal or name token to a node, or throws for tokens that can't start a value.
    private static func leaf(_ t: FormulaToken) throws -> FormulaNode {
        switch t.kind {
        case .number(let v, let d): return .number(v, d)
        case .text(let s): return .text(s)
        case .name(let n): return .name(n, pos: t.pos)
        case .keyword("true"): return .bool(true)
        case .keyword("false"): return .bool(false)
        case .keyword: return .number(Double.pi, .none)
        case .rparen: throw FormulaError("A value is missing before ')'.", position: t.pos)
        case .comma: throw FormulaError("A value is missing before ','.", position: t.pos)
        case .op(let op): throw FormulaError("A value is missing before '\(op.rawValue)'.", position: t.pos)
        case .function, .lparen: throw FormulaError("Unexpected token.", position: t.pos)
        }
    }

    private mutating func parseCall(_ f: FormulaFunction, at pos: Int) throws -> FormulaNode {
        guard isToken(.lparen) else { throw Self.callError(f, .missingParentheses, position) }
        i += 1
        try enter()
        var args: [FormulaNode] = []
        if isToken(.rparen) {
            i += 1
        } else {
            while true {
                args.append(try parseExpression(0))
                if isToken(.comma) { i += 1; continue }
                if isToken(.rparen) { i += 1; break }
                throw Self.callError(f, i < tokens.count ? .expectedSeparator : .missingClose, position)
            }
        }
        nesting -= 1
        let (lo, hi) = f.arity
        if args.count < lo || (hi.map { args.count > $0 } ?? false) {
            throw Self.callError(f, .arity, pos)
        }
        return .call(f, args, pos: pos)
    }

    private enum CallProblem { case missingParentheses, expectedSeparator, missingClose, arity }

    private static func callError(_ f: FormulaFunction, _ problem: CallProblem, _ pos: Int) -> FormulaError {
        switch problem {
        case .missingParentheses:
            return FormulaError("\(f.rawValue) needs parentheses: \(f.usage).", position: pos)
        case .expectedSeparator:
            return FormulaError("Expected ',' or ')' in \(f.rawValue)().", position: pos)
        case .missingClose:
            return FormulaError("Missing ')' after the arguments of \(f.rawValue)().", position: pos)
        case .arity:
            let (lo, hi) = f.arity
            let count: String
            if let hi {
                count = lo == hi ? (lo == 0 ? "no arguments" : "\(lo) argument\(lo == 1 ? "" : "s")") : "\(lo) to \(hi) arguments"
            } else {
                count = "at least \(lo) argument\(lo == 1 ? "" : "s")"
            }
            return FormulaError("\(f.rawValue)() takes \(count): \(f.usage).", position: pos)
        }
    }
}

// MARK: - Stack guard

/// Reports when the current thread's stack is nearly exhausted, so recursive parsing and
/// evaluation can stop with an error instead of crashing (threads other than the main thread
/// often have only 512 KB of stack, and unoptimised builds use large frames).
enum StackGuard {
    /// Stop recursing when fewer than this many bytes of stack remain.
    static let reserve = 128 * 1024

    static var isLow: Bool { remaining < reserve }

    /// Approximate bytes of stack left below the current frame.
    static var remaining: Int {
        #if canImport(Darwin)
        let thread = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        guard top > size else { return Int.max }
        let bottom = top - size
        var marker: UInt8 = 0
        let here = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
        return here > bottom ? Int(here - bottom) : 0
        #else
        return Int.max
        #endif
    }
}
