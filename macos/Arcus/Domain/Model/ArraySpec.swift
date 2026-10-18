import Foundation
import ArcusGeometry

/// How an associative array group lays out its members. Member k (k = 0 … count − 1) is the source set transformed
/// by `transform(forMember: k)`; member 0 is the source set itself. Changing `count` regenerates copies 1 … count − 1
/// from the current source elements.
public struct ArraySpec: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case linear = "Linear"
        case radial = "Radial"
    }
    public var kind: Kind
    /// Number of array members, including the source set (≥ 2).
    public var count: Int
    /// Linear arrays: displacement between consecutive members.
    public var step: Vec2
    /// Radial arrays: center of rotation.
    public var center: Vec2
    /// Radial arrays: angle between consecutive members (radians, counterclockwise positive).
    public var stepAngle: Double
    /// The elements of member 0. Copies are made from these.
    public var sourceMembers: [ElementID]
    /// True when the array was placed with Move To Last: changing the number keeps the last member where it is and
    /// re-spaces the others (a full-turn radial array stays evenly spread around the circle). False: the spacing
    /// stays and the array grows or shrinks.
    public var fixedExtent: Bool

    public static let maximumCount = 500

    public init(kind: Kind, count: Int, step: Vec2 = .zero, center: Vec2 = .zero, stepAngle: Double = 0, sourceMembers: [ElementID], fixedExtent: Bool = false) {
        self.kind = kind; self.count = count; self.step = step; self.center = center; self.stepAngle = stepAngle
        self.sourceMembers = sourceMembers; self.fixedExtent = fixedExtent
    }

    public static func linear(count: Int, step: Vec2, sourceMembers: [ElementID], fixedExtent: Bool = false) -> ArraySpec {
        ArraySpec(kind: .linear, count: count, step: step, sourceMembers: sourceMembers, fixedExtent: fixedExtent)
    }
    public static func radial(count: Int, center: Vec2, stepAngle: Double, sourceMembers: [ElementID], fixedExtent: Bool = false) -> ArraySpec {
        ArraySpec(kind: .radial, count: count, center: center, stepAngle: stepAngle, sourceMembers: sourceMembers, fixedExtent: fixedExtent)
    }

    /// True for a radial array whose members are spread evenly around a whole turn.
    public var isFullTurn: Bool { kind == .radial && abs(abs(stepAngle * Double(count)) - 2 * .pi) < 1e-9 }

    /// The spec with a different number of members (see `fixedExtent`).
    public func withCount(_ n: Int) -> ArraySpec {
        var s = self
        s.count = n
        guard fixedExtent, n >= 2 else { return s }
        if isFullTurn {
            s.stepAngle = stepAngle * Double(count) / Double(n)
        } else {
            let k = Double(count - 1) / Double(n - 1)
            s.step = step * k
            s.stepAngle = stepAngle * k
        }
        return s
    }

    /// Placement of member `k` relative to the source set.
    public func transform(forMember k: Int) -> Transform2 {
        switch kind {
        case .linear: .translation(step * Double(k))
        case .radial: .rotation(stepAngle * Double(k), around: center)
        }
    }

    /// The spec after the whole array is moved, rotated or mirrored by `t` (the source members move with it).
    public func transformed(by t: Transform2) -> ArraySpec {
        var s = self
        s.step = t.applyVector(step)
        s.center = t.apply(center)
        if t.isMirroring { s.stepAngle = -stepAngle }
        return s
    }
}
