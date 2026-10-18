import Foundation
import Testing
@testable import ArcusCalc

@Suite("Formula language")
struct FormulaTests {
    let door: [String: FormulaValue] = [
        "Width": length(0.9),
        "Width Total": length(1.1),
        "Rough Width": length(0.95),
        "Frame Width 2": length(0.05),
        "Sill Height": length(0.8),
        "Height": length(2.1),
        "Area": .quantity(4.0, .area),
        "Count": .number(3),
        "Material": .text("Oak"),
        "Is Fire Rated": .bool(true),
    ]

    private func value(_ source: String, _ inputs: [String: FormulaValue]? = nil) throws -> (Double, Dim) {
        let result = try evaluate(source, inputs ?? door)
        guard let q = quantity(result) else {
            Issue.record("Expected a quantity from \(source), got \(result)")
            return (.nan, .none)
        }
        return q
    }

    @Test func arithmeticAndPrecedence() throws {
        #expect(try value("1 + 2 * 3").0 == 7)
        #expect(try value("(1 + 2) * 3").0 == 9)
        #expect(try value("2 ^ 3 ^ 2").0 == 512)
        #expect(try value("-2 ^ 2").0 == -4)
        #expect(try value("10 - 4 - 3").0 == 3)
        #expect(try value("12 / 3 / 2").0 == 2)
        #expect(try value("2 * -3").0 == -6)
        #expect(try value("=1 + 1").0 == 2)
    }

    @Test func unitLiterals() throws {
        let (a, da) = try value("600 mm + 0.4 m")
        #expect(approx(a, 1.0) && da == .length)
        #expect(approx(try value("2' 6\"").0, 0.762))
        #expect(approx(try value("6 1/2\"").0, 6.5 * inch))
        #expect(approx(try value("1/2\"").0, 0.5 * inch))
        let (angle, dAngle) = try value("30°")
        #expect(approx(angle, Double.pi / 6) && dAngle == .angle)
        #expect(approx(try value("45 deg").0, Double.pi / 4))
        #expect(approx(try value("45°30'").0, 45.5 * Double.pi / 180))
        #expect(try value("10 m² / 2 m") == (5, .length))
        #expect(try value("2 CF").1 == .volume)
        #expect(approx(try value("25%").0, 0.25))
        #expect(approx(try value("50% * Width").0, 0.45))
    }

    @Test func namesWithSpaces() throws {
        let (v, d) = try value("Rough Width - Frame Width 2 * 2")
        #expect(approx(v, 0.85) && d == .length)
        #expect(approx(try value("Sill Height + 100 mm").0, 0.9))
    }

    @Test func greedyLongestNameMatch() throws {
        // "Width Total" must win over "Width" followed by garbage.
        #expect(approx(try value("Width Total - Width").0, 0.2))
        let f = try Formula("Width Total + Width", knownNames: ["Width", "Width Total"])
        #expect(f.referencedNames == ["Width", "Width Total"])
        // "Width" must not match inside "Widths".
        #expect(formulaError("Widths + 1 m", door)?.message == "Unknown parameter 'Widths'.")
    }

    @Test func namesAreCaseSensitive() {
        #expect(formulaError("width + 1 m", door)?.message == "Unknown parameter 'width'.")
    }

    @Test func bracketNames() throws {
        #expect(approx(try value("[Sill Height] + [Height]").0, 2.9))
        let odd: [String: FormulaValue] = ["Width (clear) - trim": length(0.8)]
        #expect(approx(try value("[Width (clear) - trim] * 2", odd).0, 1.6))
        #expect(formulaError("[Nope] + 1", door)?.message == "Unknown parameter 'Nope'.")
    }

    @Test func unknownNamesAreListed() {
        let error = formulaError("Rough Widht + 1 m", door)
        #expect(error?.message == "Unknown parameter 'Rough Widht'.")
        #expect(error?.position == 0)
        #expect(formulaError("foo(2)", door)?.message == "Unknown function 'foo'.")
    }

    @Test func dimensionMismatchMessages() {
        #expect(formulaError("Width + 2", door)?.message == "Can't add a length and a number.")
        #expect(formulaError("Width - Area", door)?.message == "Can't subtract an area from a length.")
        #expect(formulaError("Width > 2", door)?.message == "Can't compare a length with a number.")
        #expect(formulaError("Width ^ Width", door)?.message.contains("exponent") == true)
        #expect(formulaError("Width ^ 0.5", door)?.message.contains("whole-number power") == true)
    }

    @Test func zeroIsCompatibleWithAnyDimension() throws {
        #expect(try value("Width + 0") == (0.9, .length))
        #expect(try evaluate("Width > 0", door) == .bool(true))
        #expect(try value("max(Width, 0)") == (0.9, .length))
    }

    @Test func dimensionsCombine() throws {
        #expect(try value("Width * Height").1 == .area)
        #expect(try value("Area / Width").1 == .length)
        #expect(try value("Width * Height * Sill Height").1 == .volume)
        #expect(try value("Width ^ 2").1 == .area)
        #expect(try value("Width / Height").1 == .none)
        #expect(try value("Width ^ -1").1 == Dim(length: -1))
    }

    @Test func comparisonsAndTolerance() throws {
        #expect(try evaluate("Width = 900 mm", door) == .bool(true))
        #expect(try evaluate("Width = 900.0000001 mm", door) == .bool(true))
        #expect(try evaluate("Width <> 901 mm", door) == .bool(true))
        #expect(try evaluate("Width < 1 m", door) == .bool(true))
        #expect(try evaluate("Width >= 900 mm", door) == .bool(true))
        #expect(try evaluate("Width > 900 mm", door) == .bool(false))
        #expect(try evaluate("Width <= 899 mm", door) == .bool(false))
        #expect(try evaluate("0.1 + 0.2 = 0.3", door) == .bool(true))
        #expect(try evaluate("Width != 1 m", door) == .bool(true))
    }

    @Test func textAndBooleans() throws {
        #expect(try evaluate("Material = \"Oak\"", door) == .bool(true))
        #expect(try evaluate("Material <> \"Pine\"", door) == .bool(true))
        #expect(try evaluate("if(Is Fire Rated, \"FD30\", \"-\")", door) == .text("FD30"))
        #expect(try evaluate("\"say \"\"hi\"\"\"", door) == .text("say \"hi\""))
        #expect(formulaError("\"a\" < \"b\"", door)?.message == "Only '=' and '<>' can be used with text.")
        #expect(formulaError("Material + 1", door)?.message == "Can't use '+' with text.")
        #expect(formulaError("Material = 1", door)?.message == "Can't compare text with a number.")
        #expect(try evaluate("true = not(false)", door) == .bool(true))
    }

    @Test func conditionalsAreLazy() throws {
        #expect(try value("if(true, 1, 1 / 0)").0 == 1)
        let zero: [String: FormulaValue] = ["x": .number(0)]
        #expect(try value("if(x > 0, 10 / x, 0)", zero).0 == 0)
        #expect(try value("if(Width > 1 m, Width, Width * 2)") == (1.8, .length))
    }

    @Test func conditionalBranchesMustAgree() {
        let e = formulaError("if(true, 1 m, 2)", door)
        #expect(e?.message == "Both results of if() must have the same dimension, but one is a length and the other is a number.")
        #expect(formulaError("if(true, Width, Area)", door)?.message.contains("same dimension") == true)
        #expect(formulaError("if(true, 1, \"a\")", door)?.message.contains("same kind of value") == true)
        #expect(formulaError("if(Width, 1, 2)", door)?.message == "The condition of if() must be yes/no, not a length.")
    }

    @Test func conditionalZeroBranchTakesOtherDimension() throws {
        #expect(try evaluate("if(false, Width, 0)", door) == .quantity(0, .length))
        #expect(try evaluate("if(true, 0, Area)", door) == .quantity(0, .area))
    }

    @Test func logicalFunctions() throws {
        #expect(try evaluate("and(Width > 0.5 m, Height > 2 m)", door) == .bool(true))
        #expect(try evaluate("and(true, true, false)", door) == .bool(false))
        #expect(try evaluate("or(false, Count = 3)", door) == .bool(true))
        #expect(try evaluate("not(Is Fire Rated)", door) == .bool(false))
        // Short-circuit: the division by zero is never evaluated.
        #expect(try evaluate("or(true, 1 / 0 > 1)", door) == .bool(true))
        #expect(try evaluate("and(false, 1 / 0 > 1)", door) == .bool(false))
        #expect(formulaError("and(true, 1)", door)?.message == "and() needs yes/no values, but argument 2 is a number.")
    }

    @Test func trigonometryUsesDegreesForPlainNumbers() throws {
        #expect(approx(try value("sin(30)").0, 0.5, 1e-12))
        #expect(approx(try value("sin(30°)").0, 0.5, 1e-12))
        #expect(approx(try value("cos(pi / 3 * 1 rad)").0, 0.5, 1e-12))
        #expect(approx(try value("tan(45)").0, 1, 1e-12))
        let (a, d) = try value("asin(0.5)")
        #expect(approx(a, Double.pi / 6, 1e-12) && d == .angle)
        let (b, db) = try value("atan2(1 m, 1 m)")
        #expect(approx(b, Double.pi / 4) && db == .angle)
        #expect(try value("atan(1)").1 == .angle)
        // Rise from a run and slope angle.
        #expect(approx(try value("Width * tan(30°)").0, 0.9 * tan(Double.pi / 6)))
    }

    @Test func trigonometryErrors() {
        #expect(formulaError("sin(Width)", door)?.message == "sin() needs an angle (or a number of degrees), not a length.")
        #expect(formulaError("tan(90)", door)?.message == "tan() is undefined at ±90°.")
        #expect(formulaError("acos(2)", door)?.message == "acos() needs a value between -1 and 1.")
        #expect(formulaError("atan2(0, 0)", door)?.message == "atan2(0, 0) is undefined.")
        #expect(formulaError("atan2(1 m, 1)", door)?.message.contains("same dimension") == true)
    }

    @Test func squareRoots() throws {
        let (v, d) = try value("sqrt(Area)")
        #expect(v == 2 && d == .length)
        #expect(try value("sqrt(16)").0 == 4)
        #expect(formulaError("sqrt(Width)", door)?.message.contains("square root of a length") == true)
        #expect(formulaError("sqrt(-1)", door)?.message == "Can't take the square root of a negative value.")
    }

    @Test func roundingInDisplayUnits() throws {
        #expect(approx(try value("round(1234.5 mm)").0, 1.235))
        #expect(approx(try value("round(1234.4 mm)").0, 1.234))
        #expect(approx(try value("roundup(1234.1 mm)").0, 1.235))
        #expect(approx(try value("rounddown(1234.9 mm)").0, 1.234))
        #expect(approx(try value("roundup(2.5 m)").0, 2.5))
        #expect(try value("round(2.5)").0 == 3)
        #expect(try value("round(-2.5)").0 == -3)
        #expect(try value("roundup(-2.5)").0 == -2)
        #expect(try value("rounddown(-2.5)").0 == -3)
        #expect(try value("round(Area * 1.123)") == (4, .area))
        // Imperial feet-and-inches rounds to whole inches.
        let imperial = try Formula("round(6.6\")", knownNames: []).evaluate(units: .imperial) { _ in nil }
        #expect(quantity(imperial).map { approx($0.0, 7 * inch) } == true)
    }

    @Test func minMaxAbs() throws {
        #expect(try value("min(Width, Height, Sill Height)") == (0.8, .length))
        #expect(try value("max(1, 5, 3)").0 == 5)
        #expect(try value("abs(-2 m)") == (2, .length))
        #expect(formulaError("min(Width, 2)", door)?.message == "min() needs values of the same dimension, but got a length and a number.")
    }

    @Test func exponentialsAndLogs() throws {
        #expect(approx(try value("exp(0)").0, 1))
        #expect(approx(try value("ln(exp(2))").0, 2, 1e-12))
        #expect(approx(try value("log(1000)").0, 3, 1e-12))
        #expect(formulaError("ln(0)", door)?.message == "ln() needs a positive number.")
        #expect(formulaError("log(Width)", door)?.message == "log() needs a plain number, not a length.")
    }

    @Test func piAndConstants() throws {
        #expect(try value("pi").0 == Double.pi)
        #expect(try value("pi()").0 == Double.pi)
        #expect(try value("2 * pi * 1 m") == (2 * Double.pi, .length))
    }

    @Test func unsupportedFeatures() {
        #expect(formulaError("size_lookup(\"t\", \"w\", 1, Width)", door)?.message == "size_lookup isn't supported in Arcus formulas.")
        #expect(formulaError("sqrt 4", door)?.message.contains("needs parentheses") == true)
        #expect(formulaError("if(true, 1)", door)?.message == "if() takes 3 arguments: if(condition, value if true, value if false).")
    }

    @Test func divisionByZeroAndNonFiniteResults() {
        #expect(formulaError("1 / 0", door)?.message == "Division by zero.")
        #expect(formulaError("Width / (Width - Width)", door)?.message == "Division by zero.")
        #expect(formulaError("10 ^ 400", door)?.message == "The result is too large or undefined.")
        #expect(formulaError("(-8) ^ (1/3)", door)?.message == "Can't raise a negative number to a fractional power.")
        #expect(formulaError("0 ^ -1", door)?.message == "Division by zero.")
        #expect(formulaError("x + 1", ["x": .number(.nan)])?.message == "'x' is not a finite number.")
    }

    @Test func missingValues() throws {
        let f = try Formula("Width * 2", knownNames: ["Width"])
        #expect(throws: FormulaError("'Width' has no value.", position: 0)) {
            try f.evaluate { _ in nil }
        }
    }

    @Test func syntaxErrorsCarryPositions() {
        let e1 = formulaError("1 +", door)
        #expect(e1?.message == "The formula ends unexpectedly; a value is missing.")
        #expect(e1?.position == 3)
        let e2 = formulaError("(1 + 2", door)
        #expect(e2?.message == "Missing ')'.")
        #expect(formulaError("1 2", door)?.position == 2)
        #expect(formulaError("1 < 2 < 3", door)?.message.contains("can't be chained") == true)
        #expect(formulaError("1 # 2", door)?.message == "Unexpected character '#'.")
        #expect(formulaError("\"open", door)?.message == "Text is missing its closing quote.")
        #expect(formulaError("", door)?.message == "The formula is empty.")
        #expect(formulaError("max(1,)", door)?.message == "A value is missing before ')'.")
        #expect(FormulaError("Oops", position: 4).description == "Oops (at character 5)")
    }

    @Test func referencedNamesAndHashing() throws {
        let f = try Formula("if(Width > Height, Width, Sill Height)", knownNames: Set(door.keys))
        #expect(f.referencedNames == ["Width", "Height", "Sill Height"])
        let g = try Formula("if(Width > Height, Width, Sill Height)", knownNames: Set(door.keys))
        #expect(f == g)
        #expect(Set([f, g]).count == 1)
        #expect(f.source == "if(Width > Height, Width, Sill Height)")
    }

    @Test func functionNamesAreCaseInsensitive() throws {
        #expect(try value("IF(TRUE, MAX(1, 2), 0)").0 == 2)
    }
}
