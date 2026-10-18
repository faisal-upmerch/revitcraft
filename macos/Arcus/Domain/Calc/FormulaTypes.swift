import Foundation

/// A value produced or consumed by formulas. Quantities are SI with an explicit dimension.
public enum FormulaValue: Sendable, Equatable, Hashable {
    /// An SI magnitude with its dimension.
    case quantity(Double, Dimension)
    /// A yes/no value.
    case bool(Bool)
    /// A text value.
    case text(String)

    /// A dimensionless number.
    public static func number(_ value: Double) -> FormulaValue { .quantity(value, .none) }

    /// The numeric value if this is a quantity.
    public var quantityValue: Double? {
        if case .quantity(let v, _) = self { return v }
        return nil
    }

    /// Short description of the value's type for messages ("a length", "a yes/no value", "text").
    var typePhrase: String {
        switch self {
        case .quantity(_, let d): d.phrase
        case .bool: "a yes/no value"
        case .text: "text"
        }
    }
}

/// A formula syntax or evaluation error. `position` is a character offset into the source
/// when the error can be pinned to one.
public struct FormulaError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A user-facing explanation.
    public var message: String
    /// Character offset in the formula source, when known.
    public var position: Int?
    /// The message, plus "(at character N)" when a position is known.
    public var description: String {
        guard let position else { return message }
        return "\(message) (at character \(position + 1))"
    }
    /// Creates an error with a message and optional character offset.
    public init(_ message: String, position: Int? = nil) {
        self.message = message
        self.position = position
    }
}

/// Built-in functions.
enum FormulaFunction: String, Sendable, Hashable, CaseIterable {
    case sin, cos, tan, asin, acos, atan, atan2, sqrt, abs, round, roundup, rounddown
    case min, max, exp, ln, log, pi
    case `if`, and, or, not

    /// Allowed argument counts (nil upper bound = variadic).
    var arity: (min: Int, max: Int?) {
        switch self {
        case .pi: (0, 0)
        case .atan2: (2, 2)
        case .if: (3, 3)
        case .and, .or, .min, .max: (1, nil)
        default: (1, 1)
        }
    }

    var usage: String {
        switch self {
        case .if: "if(condition, value if true, value if false)"
        case .atan2: "atan2(y, x)"
        case .pi: "pi()"
        case .and, .or, .min, .max: "\(rawValue)(a, b, …)"
        default: "\(rawValue)(x)"
        }
    }
}

enum FormulaBinaryOperator: String, Sendable, Hashable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^"
    case less = "<", greater = ">", equal = "=", lessOrEqual = "<=", greaterOrEqual = ">=", notEqual = "<>"

    var isComparison: Bool {
        switch self {
        case .less, .greater, .equal, .lessOrEqual, .greaterOrEqual, .notEqual: true
        default: false
        }
    }
}

/// One `op operand` step of a left-associative chain such as `a + b - c` or `a * b / c`.
struct FormulaChainLink: Sendable, Hashable {
    var op: FormulaBinaryOperator
    var operand: FormulaNode
    var pos: Int
}

/// Formula syntax tree. `pos` is the character offset used in error messages.
///
/// Runs of `+ -` (or `* /`) at one precedence level are stored flat in `.chain` and evaluated
/// iteratively, so long sums don't make the tree deep.
indirect enum FormulaNode: Sendable, Hashable {
    case number(Double, Dimension)
    case bool(Bool)
    case text(String)
    case name(String, pos: Int)
    case negate(FormulaNode, pos: Int)
    case binary(FormulaBinaryOperator, FormulaNode, FormulaNode, pos: Int)
    case chain(FormulaNode, [FormulaChainLink])
    case call(FormulaFunction, [FormulaNode], pos: Int)
}
