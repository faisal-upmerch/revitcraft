import Foundation

/// Evaluates a formula syntax tree with dimensional analysis.
///
/// Rounding functions: `round`, `roundup` and `rounddown` round a quantity to a whole number of
/// the project's display unit for its dimension — lengths to 1 mm / 1 cm / 1 m in metric
/// displays, to 1 inch in feet-and-inches and inch displays, to 1 foot in decimal feet; areas
/// and volumes to one display unit (m², SF, mm², m³, CF, L); angles to 1°; dimensionless values
/// (and any other dimension) to an integer of the SI value. `round` rounds half away from zero,
/// `roundup` towards +∞ and `rounddown` towards −∞.
struct FormulaEvaluator {
    typealias Lookup = (String) -> FormulaValue?

    /// SI size of one display unit for lengths, areas and volumes (only what rounding needs,
    /// keeping `self` small because it is copied into every frame of the recursion).
    let lengthUnit: Double
    let areaUnit: Double
    let volumeUnit: Double

    init(units: UnitsSettings) {
        lengthUnit = units.length.roundingUnit
        areaUnit = units.area.squareMetersPerUnit
        volumeUnit = units.volume.cubicMetersPerUnit
    }

    /// Kept small: recursion goes through this dispatcher, so its stack frame is what nesting costs.
    func evaluate(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        switch node {
        case .number, .bool, .text, .name: return try leaf(node, lookup)
        case .negate: return try negate(node, lookup)
        case .binary: return try binary(node, lookup)
        case .chain: return try chain(node, lookup)
        case .call: return try call(node, lookup)
        }
    }

    private static let tooDeep = FormulaError("The formula is nested too deeply to evaluate here.")

    private func leaf(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        switch node {
        case .number(let v, let d): return .quantity(v, d)
        case .bool(let b): return .bool(b)
        case .text(let s): return .text(s)
        case .name(let n, let pos):
            guard let v = lookup(n) else { throw Self.nameError(n, "has no value", pos) }
            if case .quantity(let x, _) = v, !x.isFinite { throw Self.nameError(n, "is not a finite number", pos) }
            return v
        default: throw Self.tooDeep
        }
    }

    private static func nameError(_ n: String, _ problem: String, _ pos: Int) -> FormulaError {
        FormulaError("'\(n)' \(problem).", position: pos)
    }

    private func negate(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        guard case .negate(let a, let pos) = node, !StackGuard.isLow else { throw Self.tooDeep }
        let v = try evaluate(a, lookup)
        guard case .quantity(let x, let d) = v else { throw Self.negateError(v, pos) }
        return .quantity(x == 0 ? 0 : -x, d)
    }

    private static func negateError(_ v: FormulaValue, _ pos: Int) -> FormulaError {
        FormulaError("Can't negate \(v.typePhrase).", position: pos)
    }

    private func binary(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        guard case .binary(let op, let a, let b, let pos) = node, !StackGuard.isLow else { throw Self.tooDeep }
        let l = try evaluate(a, lookup)
        let r = try evaluate(b, lookup)
        return op.isComparison ? try compare(op, l, r, pos) : try arithmetic(op, l, r, pos)
    }

    private func chain(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        guard case .chain(let first, let links) = node, !StackGuard.isLow else { throw Self.tooDeep }
        var accumulator = try evaluate(first, lookup)
        for link in links {
            let r = try evaluate(link.operand, lookup)
            accumulator = try arithmetic(link.op, accumulator, r, link.pos)
        }
        return accumulator
    }

    // MARK: Arithmetic

    private func finite(_ v: Double, _ d: Dimension, _ pos: Int) throws -> FormulaValue {
        guard v.isFinite else { throw FormulaError("The result is too large or undefined.", position: pos) }
        return .quantity(v == 0 ? 0 : v, d)
    }

    private static func isZero(_ x: Double, _ d: Dimension) -> Bool { x == 0 && d == .none }

    /// Dimension shared by two operands, allowing a dimensionless zero to match anything.
    private static func commonDimension(_ x: Double, _ dx: Dimension, _ y: Double, _ dy: Dimension) -> Dimension? {
        if dx == dy { return dx }
        if isZero(x, dx) { return dy }
        if isZero(y, dy) { return dx }
        return nil
    }

    private func arithmetic(_ op: FormulaBinaryOperator, _ l: FormulaValue, _ r: FormulaValue, _ pos: Int) throws -> FormulaValue {
        guard case .quantity(let x, let dx) = l, case .quantity(let y, let dy) = r else {
            let offending: FormulaValue
            if case .quantity = l { offending = r } else { offending = l }
            throw FormulaError("Can't use '\(op.rawValue)' with \(offending.typePhrase).", position: pos)
        }
        switch op {
        case .add, .subtract:
            guard let d = Self.commonDimension(x, dx, y, dy) else {
                let message = op == .add
                    ? "Can't add \(dx.phrase) and \(dy.phrase)."
                    : "Can't subtract \(dy.phrase) from \(dx.phrase)."
                throw FormulaError(message, position: pos)
            }
            return try finite(op == .add ? x + y : x - y, d, pos)
        case .multiply:
            return try finite(x * y, dx * dy, pos)
        case .divide:
            guard y != 0 else { throw FormulaError("Division by zero.", position: pos) }
            return try finite(x / y, dx / dy, pos)
        case .power:
            guard dy == .none else {
                throw FormulaError("An exponent must be a plain number, not \(dy.phrase).", position: pos)
            }
            if dx == .none {
                if x < 0 && y != y.rounded() {
                    throw FormulaError("Can't raise a negative number to a fractional power.", position: pos)
                }
                if x == 0 && y < 0 { throw FormulaError("Division by zero.", position: pos) }
                return try finite(pow(x, y), .none, pos)
            }
            let n = y.rounded()
            guard abs(y - n) <= 1e-9, abs(n) <= 64 else {
                throw FormulaError("\(dx.phrase.prefix(1).uppercased() + dx.phrase.dropFirst()) can only be raised to a whole-number power (up to 64).", position: pos)
            }
            let e = Int(n)
            let (lp, lo) = dx.length.multipliedReportingOverflow(by: e)
            let (ap, ao) = dx.angle.multipliedReportingOverflow(by: e)
            guard !lo, !ao, abs(lp) <= 1024, abs(ap) <= 1024 else {
                throw FormulaError("The dimension of the result is too large.", position: pos)
            }
            if x == 0 && e < 0 { throw FormulaError("Division by zero.", position: pos) }
            return try finite(pow(x, n), Dimension(length: lp, angle: ap), pos)
        default:
            throw FormulaError("Unexpected operator '\(op.rawValue)'.", position: pos)
        }
    }

    static func approximatelyEqual(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(1e-6, 1e-9 * max(abs(a), abs(b)))
    }

    private func compare(_ op: FormulaBinaryOperator, _ l: FormulaValue, _ r: FormulaValue, _ pos: Int) throws -> FormulaValue {
        switch (l, r) {
        case (.quantity(let x, let dx), .quantity(let y, let dy)):
            guard Self.commonDimension(x, dx, y, dy) != nil else {
                throw FormulaError("Can't compare \(dx.phrase) with \(dy.phrase).", position: pos)
            }
            let eq = Self.approximatelyEqual(x, y)
            switch op {
            case .equal: return .bool(eq)
            case .notEqual: return .bool(!eq)
            case .less: return .bool(x < y && !eq)
            case .greater: return .bool(x > y && !eq)
            case .lessOrEqual: return .bool(x < y || eq)
            default: return .bool(x > y || eq)
            }
        case (.bool(let a), .bool(let b)):
            return try equality(op, a == b, what: "yes/no values", pos)
        case (.text(let a), .text(let b)):
            return try equality(op, a == b, what: "text", pos)
        default:
            throw FormulaError("Can't compare \(l.typePhrase) with \(r.typePhrase).", position: pos)
        }
    }

    private func equality(_ op: FormulaBinaryOperator, _ equal: Bool, what: String, _ pos: Int) throws -> FormulaValue {
        switch op {
        case .equal: return .bool(equal)
        case .notEqual: return .bool(!equal)
        default: throw FormulaError("Only '=' and '<>' can be used with \(what).", position: pos)
        }
    }

    // MARK: Static types (for if() branch checks without evaluating)

    enum StaticType: Equatable {
        case quantity(Dimension, isZero: Bool)
        case bool, text, unknown
    }

    func staticType(_ node: FormulaNode, _ lookup: Lookup) -> StaticType {
        if StackGuard.isLow { return .unknown }
        switch node {
        case .number(let v, let d): return .quantity(d, isZero: Self.isZero(v, d))
        case .bool: return .bool
        case .text: return .text
        case .name(let n, _):
            switch lookup(n) {
            case .quantity(let v, let d)?: return .quantity(d, isZero: Self.isZero(v, d))
            case .bool?: return .bool
            case .text?: return .text
            case nil: return .unknown
            }
        case .negate(let a, _): return staticType(a, lookup)
        case .binary(let op, let a, let b, _):
            if op.isComparison { return .bool }
            guard case .quantity(let da, _) = staticType(a, lookup) else { return .unknown }
            if da == .none { return .quantity(.none, isZero: false) }
            if case .number(let e, .none) = b, e == e.rounded(), abs(e) <= 64 { return .quantity(da.power(Int(e)), isZero: false) }
            return .unknown
        case .chain(let first, let links):
            var acc = staticType(first, lookup)
            for link in links {
                guard case .quantity(let da, let za) = acc, case .quantity(let db, let zb) = staticType(link.operand, lookup) else { return .unknown }
                switch link.op {
                case .add, .subtract:
                    if da == db { acc = .quantity(da, isZero: false) }
                    else if za { acc = .quantity(db, isZero: false) }
                    else if zb { acc = .quantity(da, isZero: false) }
                    else { return .unknown }
                case .multiply: acc = .quantity(da * db, isZero: false)
                default: acc = .quantity(da / db, isZero: false)
                }
            }
            return acc
        case .call(let f, let args, _):
            switch f {
            case .and, .or, .not: return .bool
            case .sin, .cos, .tan, .exp, .ln, .log, .pi: return .quantity(.none, isZero: false)
            case .asin, .acos, .atan, .atan2: return .quantity(.angle, isZero: false)
            case .sqrt:
                guard case .quantity(let d, _) = staticType(args[0], lookup), let h = d.squareRoot else { return .unknown }
                return .quantity(h, isZero: false)
            case .abs, .round, .roundup, .rounddown, .min, .max:
                guard case .quantity(let d, _) = staticType(args[0], lookup) else { return .unknown }
                return .quantity(d, isZero: false)
            case .if:
                let a = staticType(args[1], lookup), b = staticType(args[2], lookup)
                switch (a, b) {
                case (.quantity(let da, let za), .quantity(let db, let zb)):
                    if da == db { return .quantity(da, isZero: za && zb) }
                    if za { return .quantity(db, isZero: false) }
                    if zb { return .quantity(da, isZero: false) }
                    return .unknown
                default:
                    return a == b ? a : .unknown
                }
            }
        }
    }

    private func typeName(_ t: StaticType) -> String {
        switch t {
        case .quantity(let d, _): d.phrase
        case .bool: "a yes/no value"
        case .text: "text"
        case .unknown: "an unknown value"
        }
    }

    // MARK: Functions

    // Functions on the recursion path keep their frames small (no string building); error
    // messages are built in separate cold helpers.

    private func call(_ node: FormulaNode, _ lookup: Lookup) throws -> FormulaValue {
        guard case .call(let f, let args, let pos) = node, !StackGuard.isLow else { throw Self.tooDeep }
        switch f {
        case .if: return try conditional(args, pos, lookup)
        case .and, .or: return try logical(f, args, pos, lookup)
        case .not: return try negation(args[0], pos, lookup)
        case .pi: return .quantity(Double.pi, .none)
        case .min, .max: return try extremum(f, args, pos, lookup)
        case .atan2: return try arctangent2(args[0], args[1], pos, lookup)
        default: return try unaryFunction(f, args[0], pos, lookup)
        }
    }

    private func conditional(_ args: [FormulaNode], _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        let condition = try evaluate(args[0], lookup)
        guard case .bool(let c) = condition else { throw Self.conditionError(condition, pos) }
        let (ta, tb) = try branchTypes(args[1], args[2], pos, lookup)
        let chosen = try evaluate(args[c ? 1 : 2], lookup)
        if case .quantity(let v, .none) = chosen, v == 0, case .quantity(let other, _) = (c ? tb : ta), other != .none {
            return .quantity(0, other)
        }
        return chosen
    }

    /// Static types of both if() branches; throws when they can't agree.
    private func branchTypes(_ a: FormulaNode, _ b: FormulaNode, _ pos: Int, _ lookup: Lookup) throws -> (StaticType, StaticType) {
        let ta = staticType(a, lookup), tb = staticType(b, lookup)
        switch (ta, tb) {
        case (.quantity(let da, let za), .quantity(let db, let zb)):
            if da != db && !za && !zb {
                throw FormulaError("Both results of if() must have the same dimension, but one is \(da.phrase) and the other is \(db.phrase).", position: pos)
            }
        case (.unknown, _), (_, .unknown):
            break
        default:
            if ta != tb {
                throw FormulaError("Both results of if() must be the same kind of value, but one is \(typeName(ta)) and the other is \(typeName(tb)).", position: pos)
            }
        }
        return (ta, tb)
    }

    private static func conditionError(_ v: FormulaValue, _ pos: Int) -> FormulaError {
        FormulaError("The condition of if() must be yes/no, not \(v.typePhrase).", position: pos)
    }

    private func logical(_ f: FormulaFunction, _ args: [FormulaNode], _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        for index in args.indices {
            let v = try evaluate(args[index], lookup)
            guard case .bool(let b) = v else { throw Self.logicalError(f, index, v, pos) }
            if f == .and && !b { return .bool(false) }
            if f == .or && b { return .bool(true) }
        }
        return .bool(f == .and)
    }

    private static func logicalError(_ f: FormulaFunction, _ index: Int, _ v: FormulaValue, _ pos: Int) -> FormulaError {
        if f == .not { return FormulaError("not() needs a yes/no value, not \(v.typePhrase).", position: pos) }
        return FormulaError("\(f.rawValue)() needs yes/no values, but argument \(index + 1) is \(v.typePhrase).", position: pos)
    }

    private func negation(_ arg: FormulaNode, _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        let v = try evaluate(arg, lookup)
        guard case .bool(let b) = v else { throw Self.logicalError(.not, 0, v, pos) }
        return .bool(!b)
    }

    private func extremum(_ f: FormulaFunction, _ args: [FormulaNode], _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        var best: (Double, Dimension)?
        for arg in args {
            let (x, d) = try quantity(arg, f, pos, lookup)
            guard let (b, bd) = best else { best = (x, d); continue }
            guard let common = Self.commonDimension(b, bd, x, d) else { throw Self.sameDimensionError(f, bd, d, pos) }
            best = (f == .min ? Swift.min(b, x) : Swift.max(b, x), common)
        }
        let (v, d) = best ?? (0, .none)
        return try finite(v, d, pos)
    }

    private static func sameDimensionError(_ f: FormulaFunction, _ a: Dimension, _ b: Dimension, _ pos: Int) -> FormulaError {
        let what = f == .atan2 ? "two values" : "values"
        return FormulaError("\(f.rawValue)() needs \(what) of the same dimension, but got \(a.phrase) and \(b.phrase).", position: pos)
    }

    private func arctangent2(_ ya: FormulaNode, _ xa: FormulaNode, _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        let (y, dy) = try quantity(ya, .atan2, pos, lookup)
        let (x, dx) = try quantity(xa, .atan2, pos, lookup)
        guard Self.commonDimension(y, dy, x, dx) != nil else { throw Self.sameDimensionError(.atan2, dy, dx, pos) }
        guard x != 0 || y != 0 else { throw FormulaError("atan2(0, 0) is undefined.", position: pos) }
        return try finite(Foundation.atan2(y, x), .angle, pos)
    }

    private func unaryFunction(_ f: FormulaFunction, _ arg: FormulaNode, _ pos: Int, _ lookup: Lookup) throws -> FormulaValue {
        let (x, d) = try quantity(arg, f, pos, lookup)
        return try unary(f, x, d, pos)
    }

    private func quantity(_ node: FormulaNode, _ f: FormulaFunction, _ pos: Int, _ lookup: Lookup) throws -> (Double, Dimension) {
        let v = try evaluate(node, lookup)
        guard case .quantity(let x, let d) = v else { throw Self.numberExpected(f, v, pos) }
        return (x, d)
    }

    private static func numberExpected(_ f: FormulaFunction, _ v: FormulaValue, _ pos: Int) -> FormulaError {
        FormulaError("\(f.rawValue)() needs a number, not \(v.typePhrase).", position: pos)
    }

    private func requireDimensionless(_ f: FormulaFunction, _ d: Dimension, _ pos: Int) throws {
        guard d == .none else {
            throw FormulaError("\(f.rawValue)() needs a plain number, not \(d.phrase).", position: pos)
        }
    }

    private func roundingIncrement(_ d: Dimension) -> Double {
        switch d {
        case .length: lengthUnit
        case .area: areaUnit
        case .volume: volumeUnit
        case .angle: UnitCatalog.degree
        default: 1
        }
    }

    private func unary(_ f: FormulaFunction, _ x: Double, _ d: Dimension, _ pos: Int) throws -> FormulaValue {
        switch f {
        case .sin, .cos, .tan:
            let radians: Double
            if d == .angle {
                radians = x
            } else if d == .none {
                radians = x * UnitCatalog.degree
            } else {
                throw FormulaError("\(f.rawValue)() needs an angle (or a number of degrees), not \(d.phrase).", position: pos)
            }
            if f == .tan && abs(Foundation.cos(radians)) < 1e-12 {
                throw FormulaError("tan() is undefined at ±90°.", position: pos)
            }
            let v = f == .sin ? Foundation.sin(radians) : f == .cos ? Foundation.cos(radians) : Foundation.tan(radians)
            return try finite(v, .none, pos)
        case .asin, .acos:
            try requireDimensionless(f, d, pos)
            guard x >= -1 - 1e-12 && x <= 1 + 1e-12 else {
                throw FormulaError("\(f.rawValue)() needs a value between -1 and 1.", position: pos)
            }
            let c = Swift.min(1, Swift.max(-1, x))
            return try finite(f == .asin ? Foundation.asin(c) : Foundation.acos(c), .angle, pos)
        case .atan:
            try requireDimensionless(f, d, pos)
            return try finite(Foundation.atan(x), .angle, pos)
        case .sqrt:
            guard x >= 0 else { throw FormulaError("Can't take the square root of a negative value.", position: pos) }
            guard let half = d.squareRoot else {
                throw FormulaError("Can't take the square root of \(d.phrase); its dimension must have even powers.", position: pos)
            }
            return try finite(x.squareRoot(), half, pos)
        case .abs:
            return try finite(Swift.abs(x), d, pos)
        case .round, .roundup, .rounddown:
            let increment = roundingIncrement(d)
            var q = x / increment
            let nearest = q.rounded()
            if Swift.abs(q - nearest) <= 1e-9 * Swift.max(1, Swift.abs(q)) { q = nearest }
            let r: Double
            switch f {
            case .round: r = NumericText.roundHalfAway(q)
            case .roundup: r = q.rounded(.up)
            default: r = q.rounded(.down)
            }
            return try finite(r * increment, d, pos)
        case .exp:
            try requireDimensionless(f, d, pos)
            return try finite(Foundation.exp(x), .none, pos)
        case .ln, .log:
            try requireDimensionless(f, d, pos)
            guard x > 0 else { throw FormulaError("\(f.rawValue)() needs a positive number.", position: pos) }
            return try finite(f == .ln ? Foundation.log(x) : Foundation.log10(x), .none, pos)
        default:
            throw FormulaError("\(f.rawValue)() can't be used here.", position: pos)
        }
    }
}
