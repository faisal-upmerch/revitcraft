import Foundation

// COMP: the Components panel's search. Local, deterministic and fast for thousands of components: an index of words
// per component (name, aliases, tags, subcategory, category, type names, materials, hosts, description) with weights;
// synonyms (closet = wardrobe, pull = handle, runner = slide…); typo tolerance (one edit from 4 letters, two from 8);
// and sizes ("hinge 110" finds 110° hinges, "drawer slide 450" 450 mm slides, "18 inch slide" 18" ones) matched
// against every type's lengths and angles. Results are ranked by how well every word matches, then by name.

public struct ComponentSearchResult: Sendable, Hashable {
    public var definition: ComponentDefinition
    public var score: Double
    /// The type that matched a size in the query (nil = the default type).
    public var typeName: String?
}

/// Filters of the Components panel.
public struct ComponentSearchFilter: Sendable, Hashable {
    public var category: ComponentCategory?
    public var subcategory: String?
    /// Only components that go on this host.
    public var host: ComponentHostKind?
    /// A material finish name ("Brass").
    public var material: String?
    public var manufacturer: String?
    /// Only types whose main length is in this range (meters).
    public var size: ClosedRange<Double>?
    public var userOnly: Bool
    public init(category: ComponentCategory? = nil, subcategory: String? = nil, host: ComponentHostKind? = nil, material: String? = nil,
                manufacturer: String? = nil, size: ClosedRange<Double>? = nil, userOnly: Bool = false) {
        self.category = category; self.subcategory = subcategory; self.host = host; self.material = material
        self.manufacturer = manufacturer; self.size = size; self.userOnly = userOnly
    }
}

public struct ComponentSearchIndex: Sendable {
    struct Entry: Sendable {
        var definition: ComponentDefinition
        /// word → best weight.
        var words: [String: Double]
        /// Each type's lengths (meters) and angles (degrees).
        var sizes: [(type: String, lengths: [Double], angles: [Double], numbers: [Double])]
        var nameKey: String
    }
    let entries: [Entry]
    /// Every indexed word, for typo matching.
    let vocabulary: [String]

    public init(_ definitions: [ComponentDefinition]) {
        var vocab: Set<String> = []
        entries = definitions.map { d in
            var w: [String: Double] = [:]
            func add(_ text: String, _ weight: Double) {
                let toks = ComponentSearchIndex.tokens(text)
                for t in toks { w[t] = max(w[t] ?? 0, weight) }
                for (a, b) in zip(toks, toks.dropFirst()) { w[a + " " + b] = max(w[a + " " + b] ?? 0, weight + 2) }
            }
            add(d.name, 10)
            d.aliases.forEach { add($0, 8) }
            d.tags.forEach { add($0, 6) }
            add(d.subcategory, 5)
            add(d.category.title, 3)
            d.types.forEach { add($0.name, 4) }
            d.materials.forEach { add($0.finish.name, 2) }
            d.placement.hosts.forEach { add($0.rawValue, 2) }
            if d.hardwareKind != nil { add(d.hardwareKind!.rawValue, 5) }
            if d.electrical != nil { add("electrical power led light", 1) }
            add(d.description, 1)
            vocab.formUnion(w.keys.filter { !$0.contains(" ") })
            let sizes = d.types.map { t -> (String, [Double], [Double], [Double]) in
                var lengths: [Double] = [], angles: [Double] = [], numbers: [Double] = []
                for p in d.parameters {
                    guard let v = t.values[p.name]?.doubleValue else { continue }
                    switch p.type {
                    case .length: lengths.append(v)
                    case .angle: angles.append(v * 180 / .pi)
                    case .number, .integer: numbers.append(v)
                    default: break
                    }
                }
                if d.parameters.isEmpty {
                    for (k, v) in t.values where d.family.parameter(named: k)?.type == .length { if let x = v.doubleValue { lengths.append(x) } }
                }
                numbers += ComponentSearchIndex.numbers(in: t.name)
                return (t.name, lengths, angles, numbers)
            }
            return Entry(definition: d, words: w, sizes: sizes, nameKey: d.name.lowercased())
        }
        vocabulary = vocab.sorted()
    }

    // MARK: Text

    /// Lowercased words, punctuation and units split off, simple plurals singular ("hinges" → "hinge").
    static func tokens(_ s: String) -> [String] {
        let lowered = s.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "/", with: " / ")
        var out: [String] = []
        for raw in lowered.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "/") }) {
            var t = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !t.isEmpty, t != "/" else { continue }
            // "450mm" → "450", "mm".
            if let k = t.firstIndex(where: \.isLetter), k != t.startIndex, t[t.startIndex..<k].allSatisfy({ $0.isNumber || $0 == "." }) {
                out.append(String(t[t.startIndex..<k])); t = String(t[k...])
            }
            out.append(singular(t))
        }
        return out
    }

    static func singular(_ t: String) -> String {
        guard t.count > 3, t.allSatisfy(\.isLetter) else { return t }
        if t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.hasSuffix("sses") || t.hasSuffix("shes") || t.hasSuffix("ches") || t.hasSuffix("xes") { return String(t.dropLast(2)) }
        if t.hasSuffix("ss") || t.hasSuffix("us") { return t }
        if t.hasSuffix("s") { return String(t.dropLast()) }
        return t
    }

    static func numbers(in s: String) -> [Double] {
        tokens(s).compactMap { Double($0) }
    }

    /// Words that mean the same in furniture hardware (each group is searched as one).
    static let synonymGroups: [[String]] = [
        ["closet", "wardrobe", "armoire"], ["pull", "handle"], ["runner", "slide", "glide"], ["castor", "caster", "wheel"],
        ["catch", "latch"], ["lazy susan", "carousel", "turntable"], ["led", "light", "lighting", "lamp"], ["grommet", "cable hole", "cable port"],
        ["stay", "support"], ["foot", "feet", "leg"], ["leveler", "leveling", "leveller", "levelling", "adjustable foot"],
        ["soft close", "damper", "soft closing"], ["push open", "push to open", "touch latch", "tip on", "push latch"],
        ["concealed", "hidden", "invisible", "euro"], ["cupboard", "cabinet"], ["bin", "trash", "waste", "garbage"],
        ["rod", "rail", "hanger bar", "hanging rail"], ["lift", "gas strut", "gas spring", "hydraulic"], ["knob", "pull knob"],
        ["shelf support", "shelf pin", "shelf peg", "shelf rest"], ["bracket", "brace"], ["lock", "locking", "latch lock"],
        ["connector", "fitting", "fastener"], ["dowel", "pin"], ["track", "rail"], ["mirror", "looking glass"],
        ["drawer slide", "drawer runner", "drawer glide"], ["kitchen corner", "blind corner", "corner unit", "magic corner"],
        ["organizer", "organiser", "insert"], ["trouser", "pant"], ["desk", "table"], ["bed lift", "gas lift bed", "storage bed lift", "bed mechanism"],
    ]

    static let synonyms: [String: [String]] = {
        var out: [String: [String]] = [:]
        for g in synonymGroups {
            let toks = g.map { tokens($0).joined(separator: " ") }
            for t in toks { out[t, default: []] += toks.filter { $0 != t } }
        }
        return out
    }()

    /// Damerau-Levenshtein distance up to `limit` (larger values are reported as limit + 1).
    static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        if x.isEmpty || y.isEmpty { return max(x.count, y.count) }
        var d = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            var rowBest = Int.max
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
                rowBest = min(rowBest, d[i][j])
            }
            if rowBest > limit { return limit + 1 }
        }
        return d[x.count][y.count]
    }

    /// Vocabulary words within typo distance of a query word.
    func corrections(_ t: String) -> [String] {
        guard t.count >= 4, t.allSatisfy(\.isLetter) else { return [] }
        let limit = t.count >= 8 ? 2 : 1
        return vocabulary.filter { abs($0.count - t.count) <= limit && $0.first == t.first && $0 != t && Self.distance(t, $0, limit: limit) <= limit }
    }

    // MARK: Sizes

    /// A size in the query: a number and the unit written (or implied by the next word).
    struct Size { var value: Double; var unit: String? }

    static func sizes(_ toks: [String]) -> (sizes: [Size], rest: [String]) {
        var sizes: [Size] = [], rest: [String] = []
        var i = 0
        let units: Set<String> = ["mm", "cm", "in", "inch", "\"", "°", "deg", "degree", "ft", "foot", "lb", "w", "v"]
        while i < toks.count {
            let t = toks[i]
            if let v = Double(t) {
                // 1 / 2 → 0.5
                var value = v, j = i + 1
                if j + 1 < toks.count, toks[j] == "/", let den = Double(toks[j + 1]), den != 0 { value = v / den; j += 2 }
                let unit = j < toks.count && units.contains(toks[j]) ? toks[j] : nil
                sizes.append(Size(value: value, unit: unit))
                i = unit == nil ? j : j + 1
                continue
            }
            if t != "/" { rest.append(t) }
            i += 1
        }
        return (sizes, rest)
    }

    /// How well a type matches a size (0 = not at all, 1 = exactly).
    static func match(_ s: Size, lengths: [Double], angles: [Double], numbers: [Double]) -> Double {
        let mm = lengths.map { $0 * 1000 }, inches = lengths.map { $0 / 0.0254 }
        func near(_ list: [Double], _ v: Double, _ tol: Double) -> Bool { list.contains { abs($0 - v) <= tol } }
        switch s.unit {
        case "mm"?: return near(mm, s.value, max(2, s.value * 0.02)) ? 1 : 0
        case "cm"?: return near(mm, s.value * 10, max(2, s.value * 0.2)) ? 1 : 0
        case "in"?, "inch"?, "\""?: return near(inches, s.value, max(0.06, s.value * 0.02)) ? 1 : 0
        case "ft"?, "foot"?: return near(inches, s.value * 12, 0.5) ? 1 : 0
        case "°"?, "deg"?, "degree"?: return near(angles, s.value, 1) ? 1 : 0
        default:
            if near(angles, s.value, 1) || near(numbers, s.value, 0.01) { return 1 }
            if near(mm, s.value, max(2, s.value * 0.02)) { return 0.9 }
            if s.value <= 120, near(inches, s.value, max(0.06, s.value * 0.02)) { return 0.8 }
            return 0
        }
    }

    // MARK: Search

    /// Components matching `query` and `filter`, best first (all of them, by name, for an empty query).
    public func search(_ query: String, filter: ComponentSearchFilter = ComponentSearchFilter(), limit: Int? = nil) -> [ComponentSearchResult] {
        let toks = Self.tokens(query)
        let (sizes, words) = Self.sizes(toks)
        var results: [ComponentSearchResult] = []
        // Query phrases: two-word phrases that are synonyms keys are matched as one ("soft close").
        var terms: [[String]] = []
        var i = 0
        while i < words.count {
            if i + 1 < words.count {
                let pair = words[i] + " " + words[i + 1]
                if Self.synonyms[pair] != nil || entries.contains(where: { $0.words[pair] != nil && ($0.words[pair] ?? 0) >= 8 }) {
                    terms.append([pair] + (Self.synonyms[pair] ?? [])); i += 2; continue
                }
            }
            terms.append([words[i]] + (Self.synonyms[words[i]] ?? []))
            i += 1
        }
        let corrected: [[String]] = terms.map { alts in alts.count == 1 && alts[0].count >= 4 ? corrections(alts[0]) : [] }
        for e in entries where passes(e.definition, filter) {
            var score = 0.0
            var matched = 0
            for (k, alts) in terms.enumerated() {
                var best = 0.0
                for (n, a) in alts.enumerated() {
                    let factor = n == 0 ? 1.0 : 0.85
                    if let w = e.words[a] { best = max(best, w * factor) }
                    else if a.count >= 3, !a.contains(" "), let w = e.words.first(where: { $0.key.hasPrefix(a) && !$0.key.contains(" ") })?.value {
                        best = max(best, w * factor * 0.7) // prefix: "hing" → hinge
                    }
                }
                if best == 0 { for c in corrected[k] { if let w = e.words[c] { best = max(best, w * 0.6) } } }
                if best > 0 { matched += 1 }
                // The last word is usually the thing ("closet handle" is a handle): it counts more.
                score += k == terms.count - 1 && terms.count > 1 ? best * 1.5 : best
            }
            // Every word should match; with two or more words, components matching some of them follow the full matches.
            guard matched == terms.count || (terms.count >= 2 && matched >= 1) || terms.isEmpty else { continue }
            if matched < terms.count { score -= 100 * Double(terms.count - matched) }
            var typeName: String?
            if !sizes.isEmpty {
                var bestType = 0.0
                for t in e.sizes {
                    let m = sizes.reduce(0.0) { $0 + Self.match($1, lengths: t.lengths, angles: t.angles, numbers: t.numbers) } / Double(sizes.count)
                    if m > bestType { bestType = m; typeName = t.type }
                }
                score += bestType * 12
                if terms.isEmpty, bestType == 0 { continue }
            }
            if let r = filter.size {
                guard let t = e.sizes.first(where: { $0.lengths.max().map(r.contains) ?? false }) else { continue }
                if typeName == nil { typeName = t.type }
            }
            // A query that is the name, or starts it, ranks first.
            let q = words.joined(separator: " ")
            if !q.isEmpty, e.nameKey == q { score += 15 } else if !q.isEmpty, Self.tokens(e.definition.name).joined(separator: " ").hasPrefix(q) { score += 5 }
            results.append(ComponentSearchResult(definition: e.definition, score: score, typeName: typeName))
        }
        results.sort { a, b in a.score != b.score ? a.score > b.score : a.definition.name.localizedStandardCompare(b.definition.name) == .orderedAscending }
        if let limit { return Array(results.prefix(limit)) }
        return results
    }

    func passes(_ d: ComponentDefinition, _ f: ComponentSearchFilter) -> Bool {
        if let c = f.category, d.category != c { return false }
        if let s = f.subcategory, d.subcategory != s { return false }
        if let h = f.host, !ComponentPlacement.accepts(d, h) { return false }
        if let m = f.material, !d.materials.contains(where: { $0.finish.name.localizedCaseInsensitiveContains(m) }) { return false }
        if let m = f.manufacturer, !d.types.contains(where: { $0.manufacturer == m }) && d.manufacturer != m { return false }
        if f.userOnly, !d.isUserComponent { return false }
        return true
    }
}

/// Recent searches (most recent first, no repeats, at most 12); the panel keeps them in the user defaults.
public struct ComponentRecentSearches: Sendable, Hashable, Codable {
    public private(set) var items: [String] = []
    public static let limit = 12
    public init(_ items: [String] = []) { self.items = Array(items.prefix(Self.limit)) }
    public mutating func add(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        items.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        items.insert(t, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }
}
