import Foundation
import Testing
@testable import ArcusCalc

@Suite("Formatting")
struct FormattingTests {
    @Test func metricMillimeters() {
        #expect(format(3.5) == "3500 mm")
        #expect(format(3.5, symbol: false) == "3500")
        #expect(format(3.5004) == "3500 mm")
        #expect(format(-0.3) == "-300 mm")
    }

    @Test func roundHalfAwayFromZero() {
        #expect(format(0.0025) == "3 mm")
        #expect(format(-0.0025) == "-3 mm")
        #expect(format(0.0015) == "2 mm")
        #expect(format(1.2345, .number) == "1.23")
        #expect(format(1.235, .number) == "1.24")
        #expect(format(-1.235, .number) == "-1.24")
    }

    @Test func neverNegativeZero() {
        #expect(format(-0.0004) == "0 mm")
        #expect(format(-0.0) == "0 mm")
        #expect(format(-0.001, .number) == "0.00")
        #expect(format(-0.004, .currency) == "$0.00")
        #expect(format(-0.0001, .length, .imperial) == "0' - 0\"")
        #expect(format(-1e-6, .angle) == "0.00°")
    }

    @Test func metersAndCentimetersDerivedDecimals() {
        var u = UnitsSettings.metric
        u.length = .meters
        #expect(format(3.5, .length, u) == "3.500 m")
        #expect(format(3.5, .length, u, deDE) == "3,500 m")
        u.length = .centimeters
        #expect(format(3.5, .length, u) == "350.0 cm")
        u.length = .meters
        u.lengthRounding = 0.01
        #expect(format(3.456, .length, u) == "3.46 m")
        u.lengthRounding = 0.005
        #expect(format(3.456, .length, u) == "3.455 m")
    }

    @Test func feetFractionalInches() {
        let u = UnitsSettings.imperial
        #expect(format(12 * foot + 6.5 * inch, .length, u) == "12' - 6 1/2\"")
        #expect(format(12 * foot, .length, u) == "12' - 0\"")
        #expect(format(-(2 * foot + 3 * inch), .length, u) == "-2' - 3\"")
        #expect(format(6.25 * inch, .length, u) == "0' - 6 1/4\"")
        #expect(format(0.5 * inch, .length, u) == "0' - 0 1/2\"")
        #expect(format(3.81, .length, u) == "12' - 6\"")
    }

    @Test func fractionsReduce() {
        let u = UnitsSettings.imperial
        // 8/16 → 1/2, 12/16 → 3/4, 2/16 → 1/8
        #expect(format(5.5 * inch, .length, u) == "0' - 5 1/2\"")
        #expect(format(5.75 * inch, .length, u) == "0' - 5 3/4\"")
        #expect(format(5.125 * inch, .length, u) == "0' - 5 1/8\"")
        #expect(format(5.0625 * inch, .length, u) == "0' - 5 1/16\"")
    }

    @Test func fractionalCarryIntoNextFoot() {
        let u = UnitsSettings.imperial
        // 12' 11.97" rounds to 12' 12" which must carry to 13' - 0".
        #expect(format(12 * foot + 11.97 * inch, .length, u) == "13' - 0\"")
        // 11 31/32" rounds up at 1/16" to 12" → 1' - 0"
        #expect(format((11 + 31.0 / 32) * inch, .length, u) == "1' - 0\"")
        #expect(format(-(11 + 31.0 / 32) * inch, .length, u) == "-1' - 0\"")
        // 15/16 + half a sixteenth rounds away to the next inch.
        #expect(format((6 + 31.0 / 32) * inch, .length, u) == "0' - 7\"")
    }

    @Test func coarserImperialRounding() {
        let u = units(.feetFractionalInches, rounding: inch / 2)
        #expect(format(6.3 * inch, .length, u) == "0' - 6 1/2\"")
        let wholeInch = units(.feetFractionalInches, rounding: inch)
        #expect(format(6.5 * inch, .length, wholeInch) == "0' - 7\"")
    }

    @Test func decimalFeetAndInches() {
        #expect(format(12.54 * foot, .length, units(.decimalFeet, rounding: 0.01 * foot)) == "12.54'")
        #expect(format(12.54 * foot, .length, units(.decimalFeet, rounding: 0.01 * foot), symbol: false) == "12.54")
        #expect(format(150.5 * inch, .length, units(.fractionalInches)) == "150 1/2\"")
        #expect(format(150.5 * inch, .length, units(.fractionalInches), symbol: false) == "150 1/2")
        #expect(format(0.5 * inch, .length, units(.fractionalInches)) == "1/2\"")
        #expect(format(-0.5 * inch, .length, units(.fractionalInches)) == "-1/2\"")
        #expect(format(150.5 * inch, .length, units(.decimalInches)) == "150.50\"")
    }

    @Test func formatLengthWithExplicitDisplay() {
        #expect(QuantityFormatter.formatLength(3.81, display: .feetFractionalInches, rounding: inch / 16, locale: enUS) == "12' - 6\"")
        #expect(QuantityFormatter.formatLength(3.81, display: .millimeters, rounding: 0.001, locale: enUS) == "3810 mm")
        // Invalid increments fall back to the display default.
        #expect(QuantityFormatter.formatLength(3.81, display: .millimeters, rounding: 0, locale: enUS) == "3810 mm")
        #expect(QuantityFormatter.formatLength(3.81, display: .meters, rounding: .nan, locale: deDE) == "3,810 m")
    }

    @Test func areaAndVolume() {
        #expect(format(12.5, .area) == "12.50 m²")
        #expect(format(12.5, .area, .imperial) == "134.55 SF")
        #expect(format(12.5, .area, .metric, symbol: false) == "12.50")
        #expect(format(3.2, .volume) == "3.20 m³")
        #expect(format(113 * 0.028316846592, .volume, .imperial) == "113.00 CF")
        var u = UnitsSettings.metric
        u.volume = .liters
        u.volumeDecimals = 0
        #expect(format(0.5, .volume, u) == "500 L")
        u.area = .squareMillimeters
        u.areaDecimals = 0
        #expect(format(0.01, .area, u) == "10000 mm²")
    }

    @Test func angles() {
        #expect(format(Double.pi / 4, .angle) == "45.00°")
        #expect(format(Double.pi / 4, .angle, .metric, deDE) == "45,00°")
        #expect(format(-Double.pi / 2, .angle) == "-90.00°")
        #expect(format(Double.pi / 4, .angle, symbol: false) == "45.00")
    }

    @Test func slopes() {
        #expect(format(tan(Double.pi / 6), .slope, slopeUnits(.degrees)) == "30.00°")
        #expect(format(0.5, .slope, slopeUnits(.risePer12Inches)) == "6\" / 12\"")
        #expect(format(6.5 / 12, .slope, slopeUnits(.risePer12Inches)) == "6 1/2\" / 12\"")
        #expect(format(0.5, .slope, slopeUnits(.percent)) == "50.00%")
        #expect(format(0.5, .slope, slopeUnits(.ratio)) == "1:2.00")
        #expect(format(0, .slope, slopeUnits(.ratio)) == "0:1")
        #expect(format(-0.5, .slope, slopeUnits(.ratio)) == "-1:2.00")
    }

    @Test func numbersPercentagesCurrency() {
        #expect(format(2.5, .number) == "2.50")
        #expect(format(2.6, .integer) == "3")
        #expect(format(0.25, .percentage) == "25.00%")
        #expect(format(0.25, .percentage, symbol: false) == "25.00")
        #expect(format(12.5, .currency) == "$12.50")
        #expect(format(-12.5, .currency) == "-$12.50")
        #expect(format(12.5, .currency, .metric, deDE) == "$12,50")
    }

    @Test func decimalSeparatorOverrideWins() {
        var u = UnitsSettings.metric
        u.decimalSeparatorOverride = ","
        #expect(format(2.5, .number, u, enUS) == "2,50")
    }

    @Test func nonFiniteValues() {
        #expect(format(.nan) == "—")
        #expect(format(.infinity, .area) == "∞")
        #expect(format(-.infinity, .number) == "-∞")
    }

    @Test func noDigitGroupingEvenForLargeValues() {
        #expect(format(1234.5, .length) == "1234500 mm")
        #expect(format(1234567.891, .number) == "1234567.89")
    }
}

@Suite("Round trips: parse(format(x)) ≈ x")
struct RoundTripTests {
    static let values: [Double] = [0, 0.001, 0.0254, 0.3, 1, 1.2345, 3.81, 3.8227, 12.345678, 100.5, -0.6858, -3.14159, 1234.567]

    @Test("Length displays", arguments: LengthDisplay.allCases)
    func lengths(display: LengthDisplay) throws {
        var u = display.isFeetBased || display == .fractionalInches || display == .decimalInches ? UnitsSettings.imperial : UnitsSettings.metric
        u.length = display
        u.lengthRounding = display.defaultRounding
        for locale in [enUS, deDE] {
            for x in Self.values {
                let text = QuantityFormatter.format(x, kind: .length, units: u, locale: locale)
                let back = try QuantityParser.parse(text, kind: .length, units: u, locale: locale)
                #expect(abs(back - x) <= u.lengthRounding / 2 + 1e-9, "\(display) \(x) → \(text) → \(back)")
                let bare = QuantityFormatter.format(x, kind: .length, units: u, locale: locale, includeSymbol: false)
                let bareBack = try QuantityParser.parse(bare, kind: .length, units: u, locale: locale)
                #expect(abs(bareBack - x) <= u.lengthRounding / 2 + 1e-9, "\(display) \(x) → \(bare) → \(bareBack)")
            }
        }
    }

    @Test func formattingIsStableAfterOneRoundTrip() throws {
        let u = UnitsSettings.imperial
        for x in Self.values {
            let once = QuantityFormatter.format(x, kind: .length, units: u, locale: enUS)
            let twice = QuantityFormatter.format(try QuantityParser.parse(once, kind: .length, units: u, locale: enUS), kind: .length, units: u, locale: enUS)
            #expect(once == twice)
        }
    }

    @Test("Other kinds", arguments: [UnitKind.area, .volume, .angle, .number, .percentage, .currency])
    func otherKinds(kind: UnitKind) throws {
        for settings in [UnitsSettings.metric, UnitsSettings.imperial] {
            for x in [0.0, 0.25, 1, 12.5, -3.75, 1000] {
                let text = QuantityFormatter.format(x, kind: kind, units: settings, locale: deDE)
                let back = try QuantityParser.parse(text, kind: kind, units: settings, locale: deDE)
                let tolerance: Double = switch kind {
                case .area: 0.005 * settings.area.squareMetersPerUnit + 1e-9
                case .volume: 0.005 * settings.volume.cubicMetersPerUnit + 1e-9
                case .angle: 0.005 * Double.pi / 180
                case .percentage: 0.00005
                default: 0.005
                }
                #expect(abs(back - x) <= tolerance, "\(kind) \(x) → \(text) → \(back)")
            }
        }
    }

    @Test("Slope displays", arguments: SlopeDisplay.allCases)
    func slopes(display: SlopeDisplay) throws {
        let u = slopeUnits(display)
        for x in [0.0, 0.08333, 0.25, 0.5, 1, 2.5, -0.5] {
            for includeSymbol in [true, false] {
                let text = QuantityFormatter.format(x, kind: .slope, units: u, locale: enUS, includeSymbol: includeSymbol)
                let back = try QuantityParser.parse(text, kind: .slope, units: u, locale: enUS)
                #expect(abs(back - x) <= 0.02 * max(1, abs(x)), "\(display) \(x) → \(text) → \(back)")
            }
        }
    }

    @Test func integersRoundTrip() throws {
        for x in [0.0, 7, -42, 123456] {
            #expect(try parse(format(x, .integer), .integer) == x)
        }
    }
}
