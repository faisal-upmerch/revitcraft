import Foundation
@testable import ArcusCalc

/// `Foundation.Dimension` also exists; use this alias in tests to avoid ambiguity.
typealias Dim = ArcusCalc.Dimension

let enUS = Locale(identifier: "en_US")
let deDE = Locale(identifier: "de_DE")

let inch = 0.0254
let foot = 0.3048

func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

/// Parses with explicit English locale unless another one is given.
func parse(_ text: String, _ kind: UnitKind = .length, _ units: UnitsSettings = .metric, _ locale: Locale = enUS) throws -> Double {
    try QuantityParser.parse(text, kind: kind, units: units, locale: locale)
}

/// The parse error message, or nil if parsing succeeded.
func parseError(_ text: String, _ kind: UnitKind = .length, _ units: UnitsSettings = .metric, _ locale: Locale = enUS) -> String? {
    do {
        _ = try QuantityParser.parse(text, kind: kind, units: units, locale: locale)
        return nil
    } catch let error as QuantityParseError {
        return error.message
    } catch {
        return "unexpected error type: \(error)"
    }
}

func format(_ si: Double, _ kind: UnitKind = .length, _ units: UnitsSettings = .metric, _ locale: Locale = enUS, symbol: Bool = true) -> String {
    QuantityFormatter.format(si, kind: kind, units: units, locale: locale, includeSymbol: symbol)
}

func units(_ length: LengthDisplay, rounding: Double? = nil) -> UnitsSettings {
    var u = UnitsSettings.imperial
    u.length = length
    u.lengthRounding = rounding ?? length.defaultRounding
    return u
}

func slopeUnits(_ display: SlopeDisplay) -> UnitsSettings {
    var u = UnitsSettings.metric
    u.slope = display
    return u
}

/// Evaluates a single formula with the given inputs (names are the input keys).
func evaluate(_ source: String, _ inputs: [String: FormulaValue] = [:], units: UnitsSettings = .metric) throws -> FormulaValue {
    let f = try Formula(source, knownNames: Set(inputs.keys))
    return try f.evaluate(units: units) { inputs[$0] }
}

func formulaError(_ source: String, _ inputs: [String: FormulaValue] = [:], units: UnitsSettings = .metric) -> FormulaError? {
    do {
        _ = try evaluate(source, inputs, units: units)
        return nil
    } catch let error as FormulaError {
        return error
    } catch {
        return FormulaError("unexpected error type: \(error)")
    }
}

func quantity(_ v: FormulaValue) -> (Double, Dim)? {
    if case .quantity(let x, let d) = v { return (x, d) }
    return nil
}

func length(_ meters: Double) -> FormulaValue { .quantity(meters, .length) }

/// Deterministic pseudo-random generator for fuzz tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
        return z ^ (z >> 29)
    }
}
