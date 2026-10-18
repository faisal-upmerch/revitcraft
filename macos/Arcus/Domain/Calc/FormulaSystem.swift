import Foundation

/// Evaluates sets of named formulas that reference each other (family types, project
/// parameters, calculated schedule fields).
public enum FormulaSystem {
    /// Evaluates a set of named formulas that may reference each other and plain inputs.
    ///
    /// - Names known to each formula are the formula names plus the input names; a formula
    ///   shadows an input with the same name.
    /// - Every member of a reference cycle (including a formula that refers to itself) fails
    ///   with an error naming the cycle; formulas depending on a failed formula fail too.
    /// - If `expected` has a kind for a name, the result's dimension must match it. A
    ///   dimensionless `0` is accepted for any quantity kind; `.integer` results are rounded
    ///   half away from zero.
    /// - Evaluation order is deterministic (see `dependencyOrder`).
    public static func evaluateAll(formulas: [String: String], inputs: [String: FormulaValue], expected: [String: UnitKind] = [:], units: UnitsSettings = .metric) -> [String: Result<FormulaValue, FormulaError>] {
        var out: [String: Result<FormulaValue, FormulaError>] = [:]
        for entry in evaluateAllOrdered(formulas: formulas, inputs: inputs, expected: expected, units: units) {
            out[entry.name] = entry.result
        }
        return out
    }

    /// Same as `evaluateAll`, returning results as a list in evaluation order (dependencies
    /// first, ties broken alphabetically), followed by formulas caught in cycles (alphabetically).
    public static func evaluateAllOrdered(formulas: [String: String], inputs: [String: FormulaValue], expected: [String: UnitKind] = [:], units: UnitsSettings = .metric) -> [(name: String, result: Result<FormulaValue, FormulaError>)] {
        let table = FormulaNames(Set(formulas.keys).union(inputs.keys))
        var parsed: [String: Formula] = [:]
        var results: [String: Result<FormulaValue, FormulaError>] = [:]
        for name in formulas.keys.sorted() {
            do {
                parsed[name] = try Formula(formulas[name]!, names: table)
            } catch let error as FormulaError {
                results[name] = .failure(error)
            } catch {
                results[name] = .failure(FormulaError(String(describing: error)))
            }
        }

        var graph: [String: Set<String>] = [:]
        for name in formulas.keys {
            graph[name] = parsed[name].map { $0.referencedNames.filter { formulas[$0] != nil } } ?? []
        }
        let (order, cycles) = dependencyOrder(formulas: graph)

        for cycle in cycles {
            let error = FormulaError(cycleMessage(cycle, graph: graph))
            for member in cycle where results[member] == nil {
                results[member] = .failure(error)
            }
        }

        for name in order {
            guard results[name] == nil, let formula = parsed[name] else { continue }
            let failedDependency = graph[name, default: []].sorted().first { dep in
                if case .failure? = results[dep] { return true }
                return false
            }
            if let dep = failedDependency {
                results[name] = .failure(FormulaError("Depends on '\(dep)', which has an error."))
                continue
            }
            do {
                let value = try formula.evaluate(units: units) { ref in
                    if formulas[ref] != nil {
                        if case .success(let v)? = results[ref] { return v }
                        return nil
                    }
                    return inputs[ref]
                }
                results[name] = .success(try check(value, expected[name]))
            } catch let error as FormulaError {
                results[name] = .failure(error)
            } catch {
                results[name] = .failure(FormulaError(String(describing: error)))
            }
        }

        let ordered = Set(order)
        let rest = formulas.keys.filter { !ordered.contains($0) }.sorted()
        return (order + rest).map { name in
            (name, results[name] ?? .failure(FormulaError("'\(name)' could not be evaluated.")))
        }
    }

    /// Checks (and lightly normalises) a result against the expected kind.
    static func check(_ value: FormulaValue, _ kind: UnitKind?) throws -> FormulaValue {
        guard let kind else { return value }
        let expected = Dimension(kind: kind)
        guard case .quantity(let v, let d) = value else {
            throw FormulaError("Expected \(kind.phrase), but the formula gives \(value.typePhrase).")
        }
        if d != expected && !(v == 0 && d == .none) {
            throw FormulaError("Expected \(kind.phrase), but the formula gives \(d.phrase).")
        }
        if kind == .integer {
            let r = NumericText.roundHalfAway(v)
            guard abs(r) <= 9_007_199_254_740_992 else { throw FormulaError("The result is too large for a whole number.") }
            return .quantity(r, .none)
        }
        return .quantity(v, expected)
    }

    /// Orders formula names so each comes after the formulas it references.
    ///
    /// `formulas` maps each name to the names it references; references to names that aren't
    /// keys are ignored (they are plain inputs). `order` lists every name that is not part of a
    /// cycle, dependencies first, choosing the alphabetically smallest ready name at each step.
    /// `cycles` lists each strongly connected group of mutually dependent names (and each
    /// self-referencing name), starting with its alphabetically first member and following
    /// references around the loop, with any further members of the group appended in
    /// alphabetical order. Cycles are sorted by their first member.
    public static func dependencyOrder(formulas: [String: Set<String>]) -> (order: [String], cycles: [[String]]) {
        let names = formulas.keys.sorted()
        var index: [String: Int] = [:]
        for (k, n) in names.enumerated() { index[n] = k }
        let adjacency: [[Int]] = names.map { n in formulas[n]!.compactMap { index[$0] }.sorted() }

        // Tarjan's strongly connected components, iterative to avoid deep recursion.
        let count = names.count
        var order = Array(repeating: -1, count: count)
        var low = Array(repeating: 0, count: count)
        var onStack = Array(repeating: false, count: count)
        var stack: [Int] = []
        var counter = 0
        var components: [[Int]] = []
        for root in 0..<count where order[root] == -1 {
            var work: [(node: Int, edge: Int)] = [(root, 0)]
            order[root] = counter; low[root] = counter; counter += 1
            stack.append(root); onStack[root] = true
            while !work.isEmpty {
                let (v, e) = work[work.count - 1]
                if e < adjacency[v].count {
                    work[work.count - 1].edge += 1
                    let w = adjacency[v][e]
                    if order[w] == -1 {
                        order[w] = counter; low[w] = counter; counter += 1
                        stack.append(w); onStack[w] = true
                        work.append((w, 0))
                    } else if onStack[w] {
                        low[v] = min(low[v], order[w])
                    }
                } else {
                    work.removeLast()
                    if let parent = work.last { low[parent.node] = min(low[parent.node], low[v]) }
                    if low[v] == order[v] {
                        var component: [Int] = []
                        while let w = stack.popLast() {
                            onStack[w] = false
                            component.append(w)
                            if w == v { break }
                        }
                        components.append(component)
                    }
                }
            }
        }

        var cyclic = Array(repeating: false, count: count)
        var cycles: [[String]] = []
        for component in components {
            let isCycle = component.count > 1 || adjacency[component[0]].contains(component[0])
            guard isCycle else { continue }
            for m in component { cyclic[m] = true }
            cycles.append(cyclePath(Set(component), adjacency: adjacency).map { names[$0] })
        }
        cycles.sort { $0[0] < $1[0] }

        // Kahn's algorithm over the acyclic part, smallest ready name first.
        var remaining = Array(repeating: 0, count: count)
        var dependents = Array(repeating: [Int](), count: count)
        for v in 0..<count where !cyclic[v] {
            for w in adjacency[v] where !cyclic[w] && w != v {
                remaining[v] += 1
                dependents[w].append(v)
            }
        }
        var ready = (0..<count).filter { !cyclic[$0] && remaining[$0] == 0 }
        var result: [String] = []
        while !ready.isEmpty {
            let v = ready.removeFirst()
            result.append(names[v])
            for d in dependents[v] {
                remaining[d] -= 1
                if remaining[d] == 0 {
                    // Indices follow alphabetical order, so keep `ready` sorted by index.
                    let at = ready.firstIndex { $0 > d } ?? ready.count
                    ready.insert(d, at: at)
                }
            }
        }
        return (result, cycles)
    }

    /// A loop through the smallest member of a strongly connected component (shortest path back
    /// to it), followed by any members not on that loop.
    private static func cyclePath(_ members: Set<Int>, adjacency: [[Int]]) -> [Int] {
        let start = members.min()!
        if adjacency[start].contains(start) && members.count == 1 { return [start] }
        var previous: [Int: Int] = [:]
        var queue = [start]
        var head = 0
        var last: Int?
        search: while head < queue.count {
            let v = queue[head]
            head += 1
            for w in adjacency[v] where members.contains(w) {
                if w == start { last = v; break search }
                if previous[w] == nil {
                    previous[w] = v
                    queue.append(w)
                }
            }
        }
        var path: [Int] = []
        var node = last
        while let n = node, n != start {
            path.append(n)
            node = previous[n]
        }
        path.append(start)
        path.reverse()
        let onPath = Set(path)
        return path + members.filter { !onPath.contains($0) }.sorted()
    }

    private static func cycleMessage(_ cycle: [String], graph: [String: Set<String>]) -> String {
        if cycle.count == 1 { return "Circular reference: '\(cycle[0])' refers to itself." }
        // The loop is the shortest prefix whose members follow references and lead back to the start.
        var loop = cycle
        for k in 2...cycle.count {
            let prefix = Array(cycle[0..<k])
            let chained = zip(prefix, prefix.dropFirst()).allSatisfy { graph[$0.0, default: []].contains($0.1) }
            guard chained else { break }
            if graph[prefix[k - 1], default: []].contains(cycle[0]) {
                loop = prefix
                break
            }
        }
        var text = "Circular reference: " + (loop + [cycle[0]]).map { "'\($0)'" }.joined(separator: " → ")
        let others = cycle.filter { !loop.contains($0) }
        if !others.isEmpty {
            text += " (also involving " + others.map { "'\($0)'" }.joined(separator: ", ") + ")"
        }
        return text + "."
    }
}
