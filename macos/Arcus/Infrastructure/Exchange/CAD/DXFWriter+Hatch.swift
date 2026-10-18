import Foundation
import ArcusDomain

// W4-HATCH: names for custom HATCH pattern definitions written from project fill patterns.

extension DXFWriter {
    /// A stable, CAD-safe pattern name for a fill: the procedural kind's name plus a short hash of the line families
    /// (so two different project patterns of the same kind get different names).
    static func hatchPatternName(_ f: GFill) -> String {
        let base = f.pattern.rawValue.uppercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        if let hp = f.hatch {
            for fam in hp.families {
                for v in [fam.angle, fam.origin.x, fam.origin.y, fam.shift, fam.spacing] + fam.dashes {
                    h = (h ^ UInt64(v.bitPattern & 0xffff_ffff)) &* 0x100_0000_01b3
                }
            }
            if hp.isModel { h = (h ^ 1) &* 0x100_0000_01b3 }
        }
        return "ARCUS_" + String(base) + "_" + String(h & 0xffff, radix: 16).uppercased()
    }
}
