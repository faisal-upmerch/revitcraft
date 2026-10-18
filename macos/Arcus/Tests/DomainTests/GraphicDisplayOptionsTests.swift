import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

@Suite("3D graphic display options")
struct GraphicDisplayOptionsTests {
    @Test func realisticStyleRoundTripsAndUnknownStylesFallBack() throws {
        let data = try JSONEncoder().encode([VisualStyle.realistic])
        #expect(String(decoding: data, as: UTF8.self) == #"["Realistic"]"#)
        #expect(try JSONDecoder().decode([VisualStyle].self, from: data) == [.realistic])
        // Styles written by a newer version decode as Shaded instead of failing the view.
        #expect(try JSONDecoder().decode([VisualStyle].self, from: Data(#"["Ray Traced"]"#.utf8)) == [.shaded])
        #expect(try JSONDecoder().decode([VisualStyle].self, from: Data(#"["Hidden Line"]"#.utf8)) == [.hiddenLine])
    }

    @Test func viewDataWithoutOptionsDecodesWithDefaultsAndEncodesUnchanged() throws {
        var v = ViewData(kind: .threeD)
        v.visualStyle = .consistentColors
        let old = try JSONEncoder().encode(v)
        // Nothing new is written until an option is set, so older builds read the view unchanged.
        #expect(!String(decoding: old, as: UTF8.self).contains("graphicDisplay"))
        let decoded = try JSONDecoder().decode(ViewData.self, from: old)
        #expect(decoded == v)
        #expect(decoded.displayOptions == .default)
        #expect(!decoded.displayOptions.castShadows)
    }

    @Test func optionsRoundTripAndPartialDataUsesDefaults() throws {
        var v = ViewData(kind: .threeD)
        v.visualStyle = .realistic
        v.displayOptions.castShadows = true
        v.displayOptions.ambientShadows = true
        v.displayOptions.sun = SunSettings(mode: .still, month: 12, day: 21, hour: 10.5)
        let decoded = try JSONDecoder().decode(ViewData.self, from: JSONEncoder().encode(v))
        #expect(decoded == v)
        #expect(decoded.displayOptions.sun.mode == .still)

        let partial = try JSONDecoder().decode(GraphicDisplayOptions.self, from: Data(#"{"castShadows":true,"sun":{"altitude":60}}"#.utf8))
        #expect(partial.castShadows && !partial.ambientShadows && !partial.silhouetteEdges)
        #expect(partial.sun.altitude == 60 && partial.sun.azimuth == SunSettings.default.azimuth && partial.sun.mode == .lighting)
        let unknownMode = try JSONDecoder().decode(SunSettings.self, from: Data(#"{"mode":"Animated"}"#.utf8))
        #expect(unknownMode.mode == .lighting)
    }

    @Test func solarPositionMatchesReferenceValues() {
        // Equinox solar noon on the equator: sun overhead.
        let eq = SolarPosition.angles(latitude: 0, longitude: 0, dayOfYear: SolarPosition.dayOfYear(month: 3, day: 20), localHour: 12.1, utcOffset: 0)
        #expect(eq.altitude > 87)
        // 40° N at the equinox around solar noon: altitude ≈ 50°, due south.
        let mid = SolarPosition.angles(latitude: 40, longitude: 0, dayOfYear: SolarPosition.dayOfYear(month: 3, day: 20), localHour: 12.1, utcOffset: 0)
        #expect(abs(mid.altitude - 50) < 1.5)
        #expect(abs(mid.azimuth - 180) < 5)
        // London, June 21, 13:00 BST (UTC+1): altitude ≈ 62°, nearly south.
        let london = SolarPosition.angles(latitude: 51.5, longitude: -0.13, dayOfYear: SolarPosition.dayOfYear(month: 6, day: 21), localHour: 13, utcOffset: 1)
        #expect(abs(london.altitude - 62) < 1.5)
        #expect(abs(london.azimuth - 180) < 8)
        // Morning sun is in the east, afternoon sun in the west.
        let morning = SolarPosition.angles(latitude: 40, longitude: 0, dayOfYear: 172, localHour: 8, utcOffset: 0)
        let evening = SolarPosition.angles(latitude: 40, longitude: 0, dayOfYear: 172, localHour: 16, utcOffset: 0)
        #expect(morning.azimuth > 45 && morning.azimuth < 135)
        #expect(evening.azimuth > 225 && evening.azimuth < 315)
        // Night: below the horizon.
        #expect(SolarPosition.angles(latitude: 40, longitude: 0, dayOfYear: 172, localHour: 0, utcOffset: 0).altitude < 0)
    }

    @Test func sunDirectionUsesTrueNorthOnlyForStillSuns() throws {
        // Azimuth 180 (south), altitude 0: pointing to -Y when true north = project north.
        let south = SolarPosition.direction(azimuth: 180, altitude: 0)
        #expect(abs(south.x) < 1e-9 && abs(south.y + 1) < 1e-9 && abs(south.z) < 1e-9)
        // East is +X.
        let east = SolarPosition.direction(azimuth: 90, altitude: 0)
        #expect(abs(east.x - 1) < 1e-9)
        let up = SolarPosition.direction(azimuth: 0, altitude: 90)
        #expect(abs(up.z - 1) < 1e-9)
        // True north rotated 90° counter-clockwise from project north: true south becomes project +X.
        let rotated = SolarPosition.direction(azimuth: 180, altitude: 0, northAngle: .pi / 2)
        #expect(abs(rotated.x - 1) < 1e-9)

        let lighting = SunSettings(mode: .lighting, azimuth: 180, altitude: 30)
        let d = try #require(lighting.worldDirection(latitude: 51, longitude: 0, trueNorthAngle: .pi / 2))
        #expect(d.y < -0.8) // lighting azimuths are relative to project north
        #expect(SunSettings(relativeToView: true).worldDirection(latitude: 0, longitude: 0, trueNorthAngle: 0) == nil)
        let still = SunSettings(mode: .still, month: 6, day: 21, hour: 12, utcOffset: 0)
        let s = try #require(still.worldDirection(latitude: 51, longitude: 0, trueNorthAngle: 0))
        #expect(s.z > 0.8 && s.y < 0) // high summer sun, in the south
    }
}
