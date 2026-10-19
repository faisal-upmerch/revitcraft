import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// COMPD: group D components (16 Lighting & Electrical · 17 Glass & Panels · 18 Edges & Profiles · 19 Motion ·
/// 20 Decorative).
@Suite("COMPD group D components")
struct COMPDTests {
    @Test func everyDefinitionBuilds() {
        for d in ComponentLibrary.fm5Components.prefix(8) + ComponentLibrary.groupD + ComponentLibrary.groupD.prefix(3) {
            let problems = ComponentKit.validate(d)
            #expect(problems.isEmpty, "\(problems)")
        }
    }
}

