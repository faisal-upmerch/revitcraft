import Foundation
import ArcusGeometry

/// Per-view 3D graphic display options: cast shadows, ambient shadows, silhouette edges and the sun.
///
/// Persisted as the optional `ViewData.graphicDisplay` field. Every field decodes with a default when missing, so
/// files written before (or by builds without) these options load unchanged; nothing is written until a user
/// changes an option.
public struct GraphicDisplayOptions: Hashable, Codable, Sendable {
    /// Directional sun shadows.
    public var castShadows: Bool
    /// Screen-space ambient occlusion ("ambient shadows").
    public var ambientShadows: Bool
    /// Heavy outlines where surfaces meet the background or step in depth.
    public var silhouetteEdges: Bool
    public var sun: SunSettings

    public init(castShadows: Bool = false, ambientShadows: Bool = false, silhouetteEdges: Bool = false, sun: SunSettings = .default) {
        self.castShadows = castShadows; self.ambientShadows = ambientShadows; self.silhouetteEdges = silhouetteEdges; self.sun = sun
    }

    public static let `default` = GraphicDisplayOptions()

    private enum CodingKeys: String, CodingKey { case castShadows, ambientShadows, silhouetteEdges, sun }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        castShadows = try c.decodeIfPresent(Bool.self, forKey: .castShadows) ?? false
        ambientShadows = try c.decodeIfPresent(Bool.self, forKey: .ambientShadows) ?? false
        silhouetteEdges = try c.decodeIfPresent(Bool.self, forKey: .silhouetteEdges) ?? false
        sun = try c.decodeIfPresent(SunSettings.self, forKey: .sun) ?? .default
    }
}

/// Sun position for shading and shadows.
///
/// - `lighting`: a fixed azimuth/altitude. Azimuth is measured in degrees clockwise from project north; when
///   `relativeToView` is true the azimuth is taken relative to the camera instead (the light follows the view).
/// - `still`: the sun at a date and local time for the project location (latitude/longitude/true north).
public struct SunSettings: Hashable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case lighting = "Lighting"
        case still = "Still"
    }

    public var mode: Mode
    /// Degrees clockwise from north (project north in `lighting` mode, true north in `still` mode).
    public var azimuth: Double
    /// Degrees above the horizon.
    public var altitude: Double
    public var relativeToView: Bool
    public var month: Int
    public var day: Int
    /// Local clock time in decimal hours (14.5 = 2:30 pm).
    public var hour: Double
    /// Hours from UTC of the local clock time (nil: derived from longitude, 15° per hour).
    public var utcOffset: Double?

    public init(mode: Mode = .lighting, azimuth: Double = 135, altitude: Double = 35, relativeToView: Bool = false,
                month: Int = 6, day: Int = 21, hour: Double = 15, utcOffset: Double? = nil) {
        self.mode = mode; self.azimuth = azimuth; self.altitude = altitude; self.relativeToView = relativeToView
        self.month = month; self.day = day; self.hour = hour; self.utcOffset = utcOffset
    }

    public static let `default` = SunSettings()

    private enum CodingKeys: String, CodingKey { case mode, azimuth, altitude, relativeToView, month, day, hour, utcOffset }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SunSettings.default
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? d.mode
        azimuth = try c.decodeIfPresent(Double.self, forKey: .azimuth) ?? d.azimuth
        altitude = try c.decodeIfPresent(Double.self, forKey: .altitude) ?? d.altitude
        relativeToView = try c.decodeIfPresent(Bool.self, forKey: .relativeToView) ?? d.relativeToView
        month = try c.decodeIfPresent(Int.self, forKey: .month) ?? d.month
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? d.day
        hour = try c.decodeIfPresent(Double.self, forKey: .hour) ?? d.hour
        utcOffset = try c.decodeIfPresent(Double.self, forKey: .utcOffset)
    }

    /// Sun azimuth (degrees clockwise from north) and altitude (degrees) for these settings at a project location.
    /// In `lighting` mode this is just the stored angles.
    public func angles(latitude: Double, longitude: Double) -> (azimuth: Double, altitude: Double) {
        switch mode {
        case .lighting:
            return (azimuth, altitude)
        case .still:
            let doy = SolarPosition.dayOfYear(month: month, day: day)
            return SolarPosition.angles(latitude: latitude, longitude: longitude, dayOfYear: doy, localHour: hour,
                                        utcOffset: utcOffset ?? (longitude / 15).rounded())
        }
    }

    /// World-space unit vector toward the sun (model coordinates: +Y project north, +Z up), or nil when the
    /// settings follow the view (`relativeToView`) and must be resolved against a camera.
    public func worldDirection(latitude: Double, longitude: Double, trueNorthAngle: Double) -> Vec3? {
        if mode == .lighting && relativeToView { return nil }
        let a = angles(latitude: latitude, longitude: longitude)
        return SolarPosition.direction(azimuth: a.azimuth, altitude: a.altitude, northAngle: mode == .still ? trueNorthAngle : 0)
    }
}

extension ViewData {
    /// 3D graphic display options with defaults filled in.
    public var displayOptions: GraphicDisplayOptions {
        get { graphicDisplay ?? .default }
        set { graphicDisplay = newValue }
    }
}

/// Solar position (NOAA general solar position approximations, accurate to about a degree between ±72° latitude).
public enum SolarPosition {
    /// Day of the year (1 = January 1) in a non-leap year.
    public static func dayOfYear(month: Int, day: Int) -> Int {
        let starts = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let m = max(1, min(12, month))
        return starts[m - 1] + max(1, min(31, day))
    }

    /// Azimuth (degrees clockwise from true north, 0..<360) and altitude (degrees above the horizon).
    /// - Parameters:
    ///   - latitude: degrees, north positive. longitude: degrees, east positive.
    ///   - localHour: local clock time in decimal hours. utcOffset: hours from UTC of that clock.
    public static func angles(latitude: Double, longitude: Double, dayOfYear: Int, localHour: Double, utcOffset: Double) -> (azimuth: Double, altitude: Double) {
        let rad = Double.pi / 180
        let g = 2 * Double.pi / 365 * (Double(dayOfYear) - 1 + (localHour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let timeOffset = eqTime + 4 * longitude - 60 * utcOffset
        let trueSolarMinutes = localHour * 60 + timeOffset
        let hourAngle = (trueSolarMinutes / 4 - 180) * rad
        let lat = latitude * rad
        let cosZenith = max(-1, min(1, sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)))
        let altitude = 90 - acos(cosZenith) / rad
        var azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(lat) - tan(decl) * cos(lat)) / rad + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return (azimuth, altitude)
    }

    /// Unit vector toward the sun in model coordinates (+Y project north, +Z up).
    /// - Parameter northAngle: angle from project north to the north the azimuth is measured from (radians,
    ///   counter-clockwise positive; `ProjectInfoData.trueNorthAngle` for true-north azimuths).
    public static func direction(azimuth: Double, altitude: Double, northAngle: Double = 0) -> Vec3 {
        let rad = Double.pi / 180
        let phi = Double.pi / 2 + northAngle - azimuth * rad
        let alt = altitude * rad
        return Vec3(cos(alt) * cos(phi), cos(alt) * sin(phi), sin(alt))
    }
}
