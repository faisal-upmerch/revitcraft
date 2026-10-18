import Foundation
import Testing
@testable import ArcusCalc

@Suite("Metric length parsing")
struct MetricParsingTests {
    @Test("Metric examples from the spec", arguments: [
        ("3500", 3.5),
        ("3.5 m", 3.5),
        ("3500 mm", 3.5),
        ("350cm", 3.5),
        ("3.5m", 3.5),
        ("-300", -0.3),
        ("2400+150", 2.55),
        ("3000/2", 1.5),
        ("(1200+300)*2", 3.0),
        ("=1200*2", 2.4),
        ("  = 1200 * 2  ", 2.4),
        ("0.5 km", 500),
        ("1 yd", 0.9144),
    ])
    func metricExamples(text: String, meters: Double) throws {
        #expect(approx(try parse(text), meters))
    }

    @Test func bareNumbersFollowDisplayUnit() throws {
        var u = UnitsSettings.metric
        u.length = .centimeters
        #expect(approx(try parse("350", .length, u), 3.5))
        u.length = .meters
        #expect(approx(try parse("3.5", .length, u), 3.5))
    }

    @Test func arithmeticPrecedence() throws {
        #expect(approx(try parse("2 + 3 * 4"), 0.014))
        #expect(approx(try parse("(2 + 3) * 4"), 0.020))
        #expect(approx(try parse("100 - 20 - 30"), 0.050))
        #expect(approx(try parse("1200 / 2 / 3"), 0.2))
        #expect(approx(try parse("-(200 + 300)"), -0.5))
        #expect(approx(try parse("--500"), 0.5))
    }

    @Test func unitBearingTermsAdd() throws {
        #expect(approx(try parse("3 m + 500 mm"), 3.5))
        #expect(approx(try parse("1 m - 25 cm"), 0.75))
        // Bare terms in a sum take the display unit.
        #expect(approx(try parse("3 m + 500"), 3.5))
        #expect(approx(try parse("2 * 1.5 m"), 3.0))
        #expect(approx(try parse("3 m / 2"), 1.5))
    }

    @Test func imperialUnitsHonouredInMetricProject() throws {
        #expect(approx(try parse("12' 6\""), 3.81))
        #expect(approx(try parse("6in"), 0.1524))
        #expect(approx(try parse("1 m + 6\""), 1.1524))
    }

    @Test func spaceBetweenDigitsIsAnError() {
        let message = parseError("1 200")
        #expect(message?.contains("Digit grouping isn't supported") == true)
        #expect(message?.contains("1 200") == true)
    }

    @Test func commaDecimalOnlyInCommaLocales() throws {
        #expect(approx(try parse("1,5 m", .length, .metric, deDE), 1.5))
        #expect(approx(try parse("1500,5", .length, .metric, deDE), 1.5005))
        let english = parseError("1,5 m")
        #expect(english?.contains("'.' as the decimal separator") == true)
        let german = parseError("3.5 m", .length, .metric, deDE)
        #expect(german?.contains("','") == true)
    }

    @Test func decimalSeparatorOverride() throws {
        var u = UnitsSettings.metric
        u.decimalSeparatorOverride = ","
        #expect(approx(try parse("2,5 m", .length, u, enUS), 2.5))
        #expect(parseError("2.5 m", .length, u, enUS) != nil)
    }

    @Test func multiplyingTwoLengthsIsAnError() {
        let message = parseError("3 m * 2 m")
        #expect(message?.contains("multiplying two lengths gives an area") == true)
    }

    @Test func dimensionMismatchInSums() {
        #expect(parseError("3 m + 2 m²") == "Can't add a length and an area.")
        #expect(parseError("3 m - 45°") == "Can't subtract an angle from a length.")
    }

    @Test func helpfulErrors() {
        #expect(parseError("") == "Enter a value.")
        #expect(parseError("   ") == "Enter a value.")
        #expect(parseError("10 / 0") == "Can't divide by zero.")
        #expect(parseError("1/0") == "Can't divide by zero.")
        #expect(parseError("(1200 + 300") == "Missing ')'.")
        #expect(parseError("1200)") == "There's a ')' without a matching '('.")
        #expect(parseError("1200 +") != nil)
        #expect(parseError("3 furlongs") == "Unknown unit 'furlongs'.")
        #expect(parseError("1200 x 2")?.contains("Use * to multiply") == true)
        #expect(parseError("m") == "'m' needs a number before it.")
        #expect(parseError("12=3")?.contains("'='") == true)
        #expect(parseError("3 m 500 mm")?.contains("Use + to combine") == true)
        #expect(parseError("1:2")?.contains("slope ratios") == true)
        #expect(parseError("2(3)")?.contains("Missing operator") == true)
    }

    @Test func percentScalesLengths() throws {
        #expect(approx(try parse("50% * 3 m"), 1.5))
        #expect(parseError("50%")?.contains("Expected a length") == true)
    }

    @Test func unicodeOperatorsAndSpaces() throws {
        #expect(approx(try parse("3000 − 500"), 2.5))
        #expect(approx(try parse("1200 × 2"), 2.4))
        #expect(approx(try parse("3000 ÷ 2"), 1.5))
        #expect(approx(try parse("3,5\u{00A0}m", .length, .metric, deDE), 3.5))
    }

    @Test func neverReturnsNegativeZero() throws {
        let v = try parse("-0")
        #expect(v == 0 && v.sign == .plus)
    }
}
