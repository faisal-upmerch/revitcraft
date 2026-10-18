import Testing
@testable import ArcusGeometry

@Test func toleranceBasics() {
    #expect(Tolerance.equal(1.0, 1.0 + 1e-6))
    #expect(!Tolerance.equal(1.0, 1.0 + 1e-4))
}
