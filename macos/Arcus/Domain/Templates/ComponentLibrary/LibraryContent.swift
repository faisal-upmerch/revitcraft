import Foundation

/// The library's families, written as data with the `FB` builder. All content is original and generic.
enum LibraryContent {
    static func all() -> [ComponentLibraryItem] {
        living() + dining() + bedroom() + kids() + storage() + office() + institutional()
            + kitchen() + appliances() + plumbing() + bathAccessories()
            + lighting() + mep()
            + planting() + entourage() + siteFurniture() + parking()
    }

    // MARK: Shared shorthands

    static let L = W(-0.5), R = W(0.5), Fr = D(-0.5), Bk = D(0.5), T = H(1), Z = K(0)

    /// Points on an ellipse centered at (cx, cy) with radii rx, ry (n segments over the full turn, or an arc).
    static func ellipse(_ cx: LX, _ cy: LX, _ rx: LX, _ ry: LX, _ n: Int = 20, from a0: Double = 0, to a1: Double = 360) -> [(LX, LX)] {
        let full = abs(a1 - a0 - 360) < 1e-9
        let count = full ? n : n + 1
        return (0..<count).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / Double(n)) * .pi / 180
            return (cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    /// Regular polygon points (radius to the corners), first corner at `start` degrees.
    static func ngon(_ cx: LX, _ cy: LX, _ r: LX, _ n: Int, start: Double = 90) -> [(LX, LX)] {
        (0..<n).map { i in
            let a = (start + 360 * Double(i) / Double(n)) * .pi / 180
            return (cx + r * cos(a), cy + r * sin(a))
        }
    }

    /// Four square legs of side `s` inset `i` from the Width x Depth outline, from z0 to z1.
    static func legs(_ b: inout FB, inset i: Double, size s: Double, _ z0: LX = K(0), _ z1: LX, _ m: LM) {
        for (n, (sx, sy)) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].enumerated() {
            let x0 = sx < 0 ? W(-0.5, i) : W(0.5, -i - s), y0 = sy < 0 ? D(-0.5, i) : D(0.5, -i - s)
            b.box("Leg \(n + 1)", x0, x0 + s, y0, y0 + s, z0, z1, m, plan: false)
        }
    }

    /// Four round legs of radius `r` with centers inset `i` from the outline.
    static func roundLegs(_ b: inout FB, inset i: Double, r: Double, _ z0: LX = K(0), _ z1: LX, _ m: LM) {
        for (n, (sx, sy)) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].enumerated() {
            b.cyl("Leg \(n + 1)", W(0.5 * sx, -sx * i), D(0.5 * sy, -sy * i), K(r), z0, z1, m, plan: false)
        }
    }

    /// Seat-count divisions across the inner width (between arms of width `arm`).
    static func divisions(_ n: Int, arm: Double) -> [LX] {
        (0...n).map { i in
            let f = Double(i) / Double(n)
            return W(f - 0.5, arm * (1 - 2 * f))
        }
    }

    /// Plan chair symbol at (cx, cy) facing -Y (rotated by `angle` degrees about its center): seat and back line.
    static func chairSymbol(_ b: inout FB, _ cx: LX, _ cy: LX, w: Double = 0.46, d: Double = 0.46, angle: Double = 0) {
        let a = angle * .pi / 180
        func p(_ x: Double, _ y: Double) -> (LX, LX) { (cx + K(x * cos(a) - y * sin(a)), cy + K(x * sin(a) + y * cos(a))) }
        b.poly([p(-w / 2, -d / 2), p(w / 2, -d / 2), p(w / 2, d / 2), p(-w / 2, d / 2)])
        b.poly([p(-w / 2, d / 2 - 0.08), p(w / 2, d / 2 - 0.08)], closed: false)
    }

    /// A simple chair solid at (cx, cy) facing -Y rotated by `angle` degrees: seat, back and a pedestal.
    static func chairSolid(_ b: inout FB, _ name: String, _ cx: LX, _ cy: LX, w: Double = 0.46, d: Double = 0.46, angle: Double = 0, _ m: LM = .fabric) {
        let a = angle * .pi / 180
        func p(_ x: Double, _ y: Double) -> (LX, LX) { (cx + K(x * cos(a) - y * sin(a)), cy + K(x * sin(a) + y * cos(a))) }
        b.prism("\(name) Seat", [p(-w / 2, -d / 2), p(w / 2, -d / 2), p(w / 2, d / 2 - 0.06), p(-w / 2, d / 2 - 0.06)], K(0.4), K(0.46), m)
        b.prism("\(name) Back", [p(-w / 2, d / 2 - 0.06), p(w / 2, d / 2 - 0.06), p(w / 2, d / 2), p(-w / 2, d / 2)], K(0.4), K(0.86), m)
        b.cyl("\(name) Base", p(0, 0).0, p(0, 0).1, K(0.025), K(0), K(0.4), .metal, plan: false)
    }
}
