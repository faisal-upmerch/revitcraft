import Foundation
import Testing
@testable import ArcusCalc

@Suite("Formula systems")
struct FormulaSystemTests {
    private func message(_ r: Result<FormulaValue, FormulaError>?) -> String? {
        if case .failure(let e)? = r { return e.message }
        return nil
    }

    private func success(_ r: Result<FormulaValue, FormulaError>?) -> FormulaValue? {
        if case .success(let v)? = r { return v }
        return nil
    }

    @Test func chainedFormulas() {
        let results = FormulaSystem.evaluateAll(
            formulas: [
                "Rough Width": "Width + 2 * Frame Width",
                "Rough Height": "Height + Frame Width",
                "Rough Area": "Rough Width * Rough Height",
            ],
            inputs: ["Width": length(0.9), "Height": length(2.1), "Frame Width": length(0.05)],
            expected: ["Rough Width": .length, "Rough Area": .area])
        let width = success(results["Rough Width"]).flatMap(quantity)
        #expect(width.map { approx($0.0, 1.0) && $0.1 == .length } == true)
        let area = success(results["Rough Area"]).flatMap(quantity)
        #expect(area.map { approx($0.0, 1.0 * 2.15) && $0.1 == .area } == true)
    }

    @Test func twoMemberCycle() {
        let results = FormulaSystem.evaluateAll(formulas: ["A": "B + 1", "B": "A * 2", "C": "5"], inputs: [:])
        let expected = "Circular reference: 'A' → 'B' → 'A'."
        #expect(message(results["A"]) == expected)
        #expect(message(results["B"]) == expected)
        #expect(success(results["C"]) == .number(5))
    }

    @Test func selfReference() {
        let results = FormulaSystem.evaluateAll(formulas: ["Width": "Width + 1 m"], inputs: ["Width": length(1)])
        #expect(message(results["Width"]) == "Circular reference: 'Width' refers to itself.")
    }

    @Test func threeMemberCycleAndDependents() {
        let results = FormulaSystem.evaluateAll(
            formulas: ["A": "C + 1", "B": "A + 1", "C": "B + 1", "D": "A * 2", "E": "1"],
            inputs: [:])
        let cycle = "Circular reference: 'A' → 'C' → 'B' → 'A'."
        for name in ["A", "B", "C"] { #expect(message(results[name]) == cycle) }
        #expect(message(results["D"]) == "Depends on 'A', which has an error.")
        #expect(success(results["E"]) == .number(1))
    }

    @Test func dependencyOrderIsDeterministic() {
        let (order, cycles) = FormulaSystem.dependencyOrder(formulas: [
            "a": ["b"], "b": [], "c": [], "d": ["a", "c", "Input"],
        ])
        #expect(order == ["b", "a", "c", "d"])
        #expect(cycles.isEmpty)
        for _ in 0..<5 {
            #expect(FormulaSystem.dependencyOrder(formulas: ["z": ["y"], "y": ["x"], "x": []]).order == ["x", "y", "z"])
        }
    }

    @Test func dependencyOrderReportsCycles() {
        let (order, cycles) = FormulaSystem.dependencyOrder(formulas: [
            "a": ["b"], "b": ["a"], "c": ["c"], "d": ["a"], "e": [],
        ])
        #expect(cycles == [["a", "b"], ["c"]])
        #expect(order == ["d", "e"])
    }

    @Test func largerStronglyConnectedGroupListsAllMembers() {
        // a→b→a and b→c→b share b: one group of three.
        let (_, cycles) = FormulaSystem.dependencyOrder(formulas: ["a": ["b"], "b": ["a", "c"], "c": ["b"]])
        #expect(cycles.count == 1)
        #expect(cycles.first.map(Set.init) == ["a", "b", "c"])
        #expect(cycles.first?.first == "a")
        let results = FormulaSystem.evaluateAll(formulas: ["a": "b", "b": "a + c", "c": "b"], inputs: [:])
        #expect(message(results["c"]) == "Circular reference: 'a' → 'b' → 'a' (also involving 'c').")
    }

    @Test func longChainDoesNotRecurseDeeply() {
        var formulas: [String: String] = ["p0": "1"]
        for k in 1..<2000 { formulas["p\(k)"] = "p\(k - 1) + 1" }
        let results = FormulaSystem.evaluateAll(formulas: formulas, inputs: [:])
        #expect(success(results["p1999"]) == .number(2000))
    }

    @Test func expectedDimensionsAreChecked() {
        let results = FormulaSystem.evaluateAll(
            formulas: ["Width": "Height * Height", "Flag": "Height > 1 m", "Offset": "if(Height > 5 m, Height, 0)", "Count": "7 / 2"],
            inputs: ["Height": length(2)],
            expected: ["Width": .length, "Flag": .length, "Offset": .length, "Count": .integer])
        #expect(message(results["Width"]) == "Expected a length, but the formula gives an area.")
        #expect(message(results["Flag"]) == "Expected a length, but the formula gives a yes/no value.")
        #expect(success(results["Offset"]) == length(0))
        #expect(success(results["Count"]) == .number(4))
    }

    @Test func angleAndSlopeExpectations() {
        let results = FormulaSystem.evaluateAll(
            formulas: ["Pitch": "atan(Rise / Run)", "Slope": "Rise / Run", "Bad": "Rise"],
            inputs: ["Rise": length(1), "Run": length(2)],
            expected: ["Pitch": .angle, "Slope": .slope, "Bad": .slope])
        #expect(success(results["Pitch"]).flatMap(quantity).map { approx($0.0, atan(0.5)) && $0.1 == .angle } == true)
        #expect(success(results["Slope"]) == .number(0.5))
        #expect(message(results["Bad"]) == "Expected a slope, but the formula gives a length.")
    }

    @Test func parseErrorsAreIsolated() {
        let results = FormulaSystem.evaluateAll(formulas: ["A": "1 +", "B": "2", "C": "A + 1"], inputs: [:])
        #expect(message(results["A"]) == "The formula ends unexpectedly; a value is missing.")
        #expect(success(results["B"]) == .number(2))
        #expect(message(results["C"]) == "Depends on 'A', which has an error.")
    }

    @Test func formulaShadowsInputOfSameName() {
        let results = FormulaSystem.evaluateAll(formulas: ["W": "2 m", "X": "W * 2"], inputs: ["W": length(1)])
        #expect(success(results["X"]) == length(4))
    }

    @Test func orderedResultsFollowDependencies() {
        let ordered = FormulaSystem.evaluateAllOrdered(
            formulas: ["c": "b + 1", "b": "a + 1", "a": "1", "x": "x"], inputs: [:])
        #expect(ordered.map(\.name) == ["a", "b", "c", "x"])
    }

    @Test func textAndBooleanResults() {
        let results = FormulaSystem.evaluateAll(
            formulas: ["Label": "if(Wide, \"Double\", \"Single\")", "Wide": "Width > 1.2 m"],
            inputs: ["Width": length(1.5)])
        #expect(success(results["Label"]) == .text("Double"))
        #expect(success(results["Wide"]) == .bool(true))
    }

    @Test func roundingUsesProjectUnits() {
        let results = FormulaSystem.evaluateAll(formulas: ["R": "round(W)"], inputs: ["W": length(1.2345)], units: .metric)
        #expect(success(results["R"]).flatMap(quantity).map { approx($0.0, 1.235) } == true)
        var decimalFeet = UnitsSettings.imperial
        decimalFeet.length = .decimalFeet
        let feet = FormulaSystem.evaluateAll(formulas: ["R": "round(W)"], inputs: ["W": length(1.2345)], units: decimalFeet)
        #expect(success(feet["R"]).flatMap(quantity).map { approx($0.0, 4 * foot) } == true)
    }
}
