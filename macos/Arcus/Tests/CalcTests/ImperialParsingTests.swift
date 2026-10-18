import Foundation
import Testing
@testable import ArcusCalc

@Suite("Imperial length parsing")
struct ImperialParsingTests {
    let imperial = UnitsSettings.imperial

    static let imperialCases: [(String, Double)] = [
        ("12' 6\"", 12 * foot + 6 * inch),
        ("12'-6 1/2\"", 12 * foot + 6.5 * inch),
        ("12' 6 1/2\"", 12 * foot + 6.5 * inch),
        ("12'", 12 * foot),
        ("6\"", 6 * inch),
        ("6 1/2\"", 6.5 * inch),
        ("1/2\"", 0.5 * inch),
        ("12.5'", 12.5 * foot),
        ("12 6", 12 * foot + 6 * inch),
        ("12ft 6in", 12 * foot + 6 * inch),
        ("-2' 3\"", -(2 * foot + 3 * inch)),
        ("150", 150 * foot),
        ("12' 6\" + 3'", 15 * foot + 6 * inch),
        ("3 m", 3.0),
    ]

    @Test("Imperial examples from the spec", arguments: imperialCases)
    func imperialExamples(text: String, meters: Double) throws {
        #expect(approx(try parse(text, .length, imperial), meters))
    }

    @Test func twelveSixIsThreePointEightOne() throws {
        #expect(approx(try parse("12' 6\"", .length, imperial), 3.81, 1e-12))
    }

    @Test func bareNumberIsInchesInInchDisplays() throws {
        #expect(approx(try parse("150", .length, units(.decimalInches)), 150 * inch))
        #expect(approx(try parse("6 1/2", .length, units(.fractionalInches)), 6.5 * inch))
        #expect(approx(try parse("12.5", .length, units(.decimalFeet)), 12.5 * foot))
    }

    @Test func dashAfterFeetIsASeparator() throws {
        // BIM convention: the formatter's own output `12' - 6"` means 12'6", not 12' minus 6".
        #expect(approx(try parse("12' - 6\"", .length, imperial), 12 * foot + 6 * inch))
        #expect(approx(try parse("12'-6", .length, imperial), 12 * foot + 6 * inch))
        #expect(approx(try parse("-2' - 3\"", .length, imperial), -(2 * foot + 3 * inch)))
        // …but subtracting feet from feet is still subtraction.
        #expect(approx(try parse("12' - 3'", .length, imperial), 9 * foot))
        #expect(approx(try parse("12' 6\" - 3\"", .length, imperial), 12 * foot + 3 * inch))
    }

    @Test func feetThenBareInches() throws {
        #expect(approx(try parse("12' 6", .length, imperial), 12 * foot + 6 * inch))
        #expect(approx(try parse("12 6 1/2", .length, imperial), 12 * foot + 6.5 * inch))
        #expect(approx(try parse("12 6\"", .length, imperial), 12 * foot + 6 * inch))
    }

    @Test func explicitInchesMayExceedTwelve() throws {
        #expect(approx(try parse("12' 14\"", .length, imperial), 13 * foot + 2 * inch))
        #expect(parseError("12 14", .length, imperial)?.contains("less than 12") == true)
    }

    @Test func smartQuotesPrimesAndDoubleApostrophes() throws {
        #expect(approx(try parse("12’ 6”", .length, imperial), 3.81))
        #expect(approx(try parse("12′ 6″", .length, imperial), 3.81))
        #expect(approx(try parse("6''", .length, imperial), 6 * inch))
        #expect(approx(try parse("12'6\"", .length, imperial), 3.81))
    }

    @Test func arithmeticWithImperialTerms() throws {
        #expect(approx(try parse("2 * 3'", .length, imperial), 6 * foot))
        #expect(approx(try parse("(12' 6\") / 2", .length, imperial), 6 * foot + 3 * inch))
        #expect(approx(try parse("3' + 6", .length, imperial), 9 * foot))
        #expect(approx(try parse("1 m + 1'", .length, imperial), 1 + foot))
    }

    @Test func imperialErrors() {
        #expect(parseError("12' 3'", .length, imperial)?.contains("After feet, expected inches") == true)
        #expect(parseError("1 200", .length, units(.decimalInches))?.contains("Digit grouping") == true)
        #expect(parseError("6\" * 6\"", .length, imperial)?.contains("multiplying two lengths") == true)
    }
}

@Suite("Angle, slope, area and volume parsing")
struct OtherKindParsingTests {
    static let angleCases: [(String, Double)] = [
        ("45", 45.0),
        ("45°", 45.0),
        ("45 deg", 45.0),
        ("30.5°", 30.5),
        ("45°30'", 45.5),
        ("45°30'15\"", 45 + 30.0 / 60 + 15.0 / 3600),
        ("45° 30' 15\"", 45 + 30.0 / 60 + 15.0 / 3600),
        ("-90", -90.0),
        ("90° - 45", 45.0),
        ("30'", 0.5),
    ]

    @Test("Angle examples from the spec", arguments: angleCases)
    func angleExamples(text: String, degrees: Double) throws {
        #expect(approx(try parse(text, .angle), degrees * Double.pi / 180, 1e-12))
    }

    @Test func radians() throws {
        #expect(approx(try parse("0.5 rad", .angle), 0.5))
        #expect(approx(try parse("45º", .angle), Double.pi / 4))
    }

    @Test func angleErrors() {
        #expect(parseError("3 m", .angle) == "Expected an angle but got a length.")
        #expect(parseError("45° 3 m", .angle)?.contains("After degrees") == true)
    }

    @Test func slopeInDegreesMode() throws {
        let u = slopeUnits(.degrees)
        #expect(approx(try parse("30°", .slope, u), tan(Double.pi / 6)))
        #expect(approx(try parse("30", .slope, u), tan(Double.pi / 6)))
        #expect(approx(try parse("6/12", .slope, u), 0.5))
        #expect(approx(try parse("6 / 12", .slope, u), 0.5))
        #expect(approx(try parse("6:12", .slope, u), 0.5))
        #expect(approx(try parse("25%", .slope, u), 0.25))
        #expect(approx(try parse("6\" / 12\"", .slope, u), 0.5))
    }

    @Test func slopeBareNumbersFollowDisplay() throws {
        #expect(approx(try parse("6", .slope, slopeUnits(.risePer12Inches)), 0.5))
        #expect(approx(try parse("50", .slope, slopeUnits(.percent)), 0.5))
        #expect(approx(try parse("12", .slope, slopeUnits(.ratio)), 1.0 / 12))
        #expect(approx(try parse("1:12", .slope, slopeUnits(.ratio)), 1.0 / 12))
        #expect(approx(try parse("1:2.00", .slope, slopeUnits(.ratio)), 0.5))
        #expect(approx(try parse("-6/12", .slope, slopeUnits(.ratio)), -0.5))
    }

    @Test func slopeErrors() {
        #expect(parseError("90°", .slope)?.contains("between -90° and 90°") == true)
        #expect(parseError("1:0", .slope)?.contains("can't be zero") == true)
        #expect(parseError("3 m", .slope)?.contains("Expected a slope") == true)
        #expect(parseError("6\":12", .slope)?.contains("same units") == true)
    }

    @Test("Area inputs", arguments: [
        ("12.5", 12.5),
        ("12.5 m²", 12.5),
        ("12.5 m2", 12.5),
        ("12.5 sq m", 12.5),
        ("12.5 sqm", 12.5),
        ("100 SF", 9.290304),
        ("100 sf", 9.290304),
        ("100 ft²", 9.290304),
        ("100 sq ft", 9.290304),
        ("100 ft^2", 9.290304),
        ("2 m * 3 m", 6.0),
        ("2 m * 3 m + 1", 7.0),
        ("1000000 mm²", 1.0),
    ])
    func areaInputs(text: String, squareMeters: Double) throws {
        #expect(approx(try parse(text, .area), squareMeters, 1e-9))
    }

    @Test func imperialBareAreaIsSquareFeet() throws {
        #expect(approx(try parse("100", .area, .imperial), 9.290304))
    }

    @Test("Volume inputs", arguments: [
        ("3.2", 3.2),
        ("3.2 m³", 3.2),
        ("3.2 m3", 3.2),
        ("100 CF", 2.8316846592),
        ("100 ft3", 2.8316846592),
        ("100 cu ft", 2.8316846592),
        ("500 L", 0.5),
        ("2 m * 2 m * 2 m", 8.0),
    ])
    func volumeInputs(text: String, cubicMeters: Double) throws {
        #expect(approx(try parse(text, .volume), cubicMeters, 1e-9))
    }

    @Test func areaAndVolumeErrors() {
        #expect(parseError("3 m", .area) == "Expected an area but got a length.")
        #expect(parseError("3 m²", .volume) == "Expected a volume but got an area.")
    }

    @Test func numbersIntegersPercentagesCurrency() throws {
        #expect(approx(try parse("2.5", .number), 2.5))
        #expect(approx(try parse("(1 + 2) * 3", .number), 9))
        #expect(try parse("3", .integer) == 3)
        #expect(try parse("6/2", .integer) == 3)
        #expect(parseError("2.5", .integer) == "Enter a whole number.")
        #expect(parseError("7/2", .integer) == "Enter a whole number.")
        #expect(approx(try parse("25%", .percentage), 0.25))
        #expect(approx(try parse("25", .percentage), 0.25))
        #expect(approx(try parse("12.5 %", .percentage), 0.125))
        #expect(approx(try parse("10% + 5", .percentage), 0.15))
        #expect(approx(try parse("$12.50", .currency), 12.5))
        #expect(approx(try parse("12.50 $", .currency), 12.5))
        #expect(approx(try parse("12,50 €", .currency, .metric, deDE), 12.5))
        #expect(approx(try parse("-$5", .currency), -5))
        #expect(parseError("$12", .number)?.contains("Currency symbols") == true)
        #expect(parseError("3 m", .number) == "Expected a number but got a length.")
    }

    @Test func customCurrencySymbol() throws {
        var u = UnitsSettings.metric
        u.currencySymbol = "CHF"
        #expect(approx(try parse("CHF 120", .currency, u), 120))
        #expect(approx(try parse("120 CHF", .currency, u), 120))
    }
}
