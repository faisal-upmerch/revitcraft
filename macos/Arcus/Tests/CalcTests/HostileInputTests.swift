import Foundation
import Testing
@testable import ArcusCalc

@Suite("Hostile input")
struct HostileInputTests {
    @Test func overlongQuantityInput() {
        let text = String(repeating: "1+", count: 3000) + "1"
        #expect(parseError(text)?.contains("too long") == true)
    }

    @Test func deeplyNestedQuantityInput() {
        let text = String(repeating: "(", count: 400) + "1" + String(repeating: ")", count: 400)
        #expect(parseError(text) == "The entry is nested too deeply.")
        let minuses = String(repeating: "-", count: 200) + "5"
        #expect(parseError(minuses) == "The entry is nested too deeply.")
        let fine = String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)
        #expect(parseError(fine) == nil)
    }

    @Test func hugeNumbers() {
        let digits = String(repeating: "9", count: 400)
        #expect(parseError(digits)?.contains("too large") == true)
        #expect(parseError("1e308")?.contains("Unknown unit") == true)
        #expect(parseError(String(repeating: "9", count: 300) + " * " + String(repeating: "9", count: 300)) != nil)
        #expect(formulaError(digits)?.message == "Number is too large.")
    }

    @Test func overlongFormula() {
        let source = String(repeating: "1+", count: 2100) + "1"
        #expect(formulaError(source)?.message.contains("too long") == true)
    }

    @Test func deeplyNestedFormula() throws {
        let deep = String(repeating: "(", count: 1000) + "1" + String(repeating: ")", count: 1000)
        #expect(formulaError(deep)?.message == "The formula is nested too deeply.")
        let calls = String(repeating: "abs(", count: 400) + "1" + String(repeating: ")", count: 400)
        #expect(formulaError(calls)?.message == "The formula is nested too deeply.")
        let unary = String(repeating: "-", count: 1000) + "1"
        #expect(formulaError(unary)?.message == "The formula is nested too deeply.")
        let powers = Array(repeating: "2", count: 1000).joined(separator: "^")
        #expect(formulaError(powers)?.message == "The formula is nested too deeply.")
    }

    @MainActor
    @Test func nestingJustInsideTheLimitWorksOnTheMainThread() throws {
        // The main thread has a large stack, so the full nesting limit is available.
        let n = Formula.maxDepth - 2
        #expect(try evaluate(String(repeating: "(", count: n) + "1" + String(repeating: ")", count: n)) == .number(1))
        #expect(try evaluate(String(repeating: "abs(", count: n) + "-1" + String(repeating: ")", count: n)) == .number(1))
        #expect(try evaluate(String(repeating: "-", count: n) + "1") == .number(1))
        #expect(try evaluate(String(repeating: "if(true, ", count: n) + "1" + String(repeating: ", 2)", count: n)) == .number(1))
        let nestedSums = String(repeating: "1 + (", count: n) + "1" + String(repeating: ")", count: n)
        #expect(try evaluate(nestedSums) == .number(Double(n + 1)))
    }

    @Test func moderateNestingWorksOnAnyThread() async throws {
        let source = String(repeating: "max(1, if(true, ", count: 20) + "2" + String(repeating: ", 0))", count: 20)
        let result = try await Task.detached { try evaluate(source) }.value
        #expect(result == .number(2))
    }

    @Test func deepNestingOnASmallStackNeverCrashes() async {
        // Cooperative-pool threads have small stacks; deep input must fail cleanly, not crash.
        let n = Formula.maxDepth - 2
        let cases: [(String, Double)] = [
            (String(repeating: "max(1, ", count: n) + "2" + String(repeating: ")", count: n), 2),
            (String(repeating: "if(true, ", count: n) + "1" + String(repeating: ", 2)", count: n), 1),
            (String(repeating: "abs(-", count: n) + "1" + String(repeating: ")", count: n), 1),
        ]
        for (source, expected) in cases {
            let outcome: Result<FormulaValue, FormulaError> = await Task.detached {
                do { return .success(try evaluate(source)) } catch let e as FormulaError { return .failure(e) } catch { return .failure(FormulaError("\(error)")) }
            }.value
            switch outcome {
            case .success(let v): #expect(v == .number(expected))
            case .failure(let e): #expect(e.message.contains("nested too deeply"))
            }
        }
    }

    @Test func longFlatChainsDontCountAsNesting() throws {
        // Runs of + - and * / are stored flat, so long sums are fine.
        let long = Array(repeating: "1", count: 2000).joined(separator: "+")
        #expect(try evaluate(long) == .number(2000))
        let product = Array(repeating: "1 m / 1 m", count: 300).joined(separator: " * ")
        #expect(try evaluate(product) == .number(1))
    }

    @Test func dimensionExponentOverflow() {
        let source = "((((1 m ^ 64) ^ 64) ^ 64) ^ 64)"
        #expect(formulaError(source)?.message == "The dimension of the result is too large.")
    }

    @Test("Weird unicode never crashes", arguments: [
        "🙂", "12👍", "３５００", "٣٥٠٠", "1\u{200B}200", "1\u{0301}2", "e\u{0301}", "\u{202E}0053",
        "12' 6\u{0022}\u{0301}", "Ⅻ", "½\"", "∞", "NaN", "inf", "-", "+", "*", "()", "(-)", "'", "\"",
        "°", "%", ":", "1:", ":1", "1::2", "..", ".", ",", "1..2", "1,,2", "$", "$$", "=", "==1", "\u{0000}", "\t\n",
        "sq", "sq ft", "cu", "12 sq", "m²", "1'''", "1''''", "1/", "1//2", "/2", "1/2/", "1 1/", "12'-", "12'-'",
    ])
    func weirdUnicode(text: String) {
        for kind in UnitKind.allCases {
            for u in [UnitsSettings.metric, UnitsSettings.imperial] {
                if let v = try? QuantityParser.parse(text, kind: kind, units: u, locale: enUS) {
                    #expect(v.isFinite)
                }
            }
        }
        let names: Set<String> = ["Width", "🙂 Name", "Höhe"]
        if let f = try? Formula(text, knownNames: names), let v = try? f.evaluate(units: .metric, { _ in .quantity(1, .length) }) {
            if case .quantity(let x, _) = v { #expect(x.isFinite) }
        }
    }

    @Test func unicodeNamesWork() throws {
        let inputs: [String: FormulaValue] = ["Höhe": length(2), "🙂 Name": length(1)]
        #expect(try evaluate("Höhe + [🙂 Name]", inputs) == length(3))
        #expect(try evaluate("Höhe + 🙂 Name", inputs) == length(3))
    }

    @Test func randomQuantityFuzz() {
        var rng = SeededGenerator(state: 0xC0FFEE)
        let alphabet = Array("0123456789 .,+-*/()'\"°%:=mftinsqcuSFL$²³-− ")
        for _ in 0..<3000 {
            let n = Int.random(in: 0...24, using: &rng)
            let text = String((0..<n).map { _ in alphabet.randomElement(using: &rng)! })
            let kind = UnitKind.allCases.randomElement(using: &rng)!
            let settings = Bool.random(using: &rng) ? UnitsSettings.metric : UnitsSettings.imperial
            let locale = Bool.random(using: &rng) ? enUS : deDE
            do {
                let v = try QuantityParser.parse(text, kind: kind, units: settings, locale: locale)
                #expect(v.isFinite, "\(text)")
                let formatted = QuantityFormatter.format(v, kind: kind, units: settings, locale: locale)
                #expect(!formatted.isEmpty)
            } catch is QuantityParseError {
                // Expected for most random strings.
            } catch {
                Issue.record("Unexpected error type for \(text): \(error)")
            }
        }
    }

    @Test func randomFormulaFuzz() {
        var rng = SeededGenerator(state: 42)
        let pieces = ["1", "0", "2.5", "Width", "Width Total", "[Width]", "+", "-", "*", "/", "^", "(", ")", ",", "<", ">", "=", "<>",
                      "if(", "and(", "or(", "not(", "sin(", "sqrt(", "round(", "min(", "max(", "ln(", "true", "false", "pi",
                      "\"a\"", " m", "'", "\"", "°", "%", " ", "mm", "atan2("]
        let names: Set<String> = ["Width", "Width Total"]
        let inputs: [String: FormulaValue] = ["Width": length(0.9), "Width Total": length(0)]
        for _ in 0..<3000 {
            let n = Int.random(in: 0...16, using: &rng)
            let source = (0..<n).map { _ in pieces.randomElement(using: &rng)! }.joined()
            do {
                let f = try Formula(source, knownNames: names)
                let v = try f.evaluate { inputs[$0] }
                if case .quantity(let x, _) = v { #expect(x.isFinite, "\(source)") }
            } catch is FormulaError {
                // Expected for most random strings.
            } catch {
                Issue.record("Unexpected error type for \(source): \(error)")
            }
        }
    }

    @Test func formattingExtremeValuesDoesNotCrash() {
        for v in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 1e300, 1e-300, Double.leastNonzeroMagnitude, .nan, .infinity] {
            for kind in UnitKind.allCases {
                for u in [UnitsSettings.metric, UnitsSettings.imperial] {
                    #expect(!QuantityFormatter.format(v, kind: kind, units: u, locale: enUS).isEmpty)
                }
            }
            for display in LengthDisplay.allCases {
                #expect(!QuantityFormatter.formatLength(v, display: display, rounding: 1e-300, locale: enUS).isEmpty)
                #expect(!QuantityFormatter.formatLength(v, display: display, rounding: 1e300, locale: enUS).isEmpty)
            }
        }
    }

    @Test func unitsSettingsCodableIsLenient() throws {
        let data = Data(#"{"system":"imperial","length":"decimalFeet"}"#.utf8)
        let decoded = try JSONDecoder().decode(UnitsSettings.self, from: data)
        #expect(decoded.system == .imperial)
        #expect(decoded.length == .decimalFeet)
        #expect(decoded.areaDecimals == 2)
        let roundTrip = try JSONDecoder().decode(UnitsSettings.self, from: JSONEncoder().encode(UnitsSettings.imperial))
        #expect(roundTrip == .imperial)
    }

    @Test func dimensionBasics() {
        #expect(Dim.length * Dim.length == .area)
        #expect(Dim.volume / Dim.length == .area)
        #expect(Dim(kind: .slope) == .none)
        #expect(Dim(kind: .angle) == .angle)
        #expect(Dim(length: 4, angle: -1).description == "length^4·angle^-1")
        #expect(Dim.none.description == "dimensionless")
        #expect(Dim.area.squareRoot == .length)
        #expect(Dim.length.squareRoot == nil)
    }
}
