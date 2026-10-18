import Foundation
import ArcusDomain

/// BL-PROPS: search, most-recently-used and grouping for the Type Selector popover.
public enum TypeSelectorModel {
    /// A section of the list: "Most Recently Used" or a family.
    public struct Section: Hashable, Sendable {
        public var title: String
        public var types: [ElementID]
        public var isRecent: Bool
    }

    /// Keywords of a query: whitespace-separated, matched in any order.
    public static func keywords(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Ranges of `text` matched by every keyword (case- and diacritic-insensitive), or nil when a keyword is missing.
    /// An empty query matches with no highlights.
    public static func match(_ text: String, query: String) -> [Range<String.Index>]? {
        var ranges: [Range<String.Index>] = []
        for k in keywords(query) {
            guard let r = text.range(of: k, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            ranges.append(r)
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The label a type is searched and shown by: "Family: Type" (family names are searchable too).
    public static func searchText(_ type: Element) -> String {
        let fam = type.typeData?.familyName ?? ""
        return fam.isEmpty ? type.name : "\(fam): \(type.name)"
    }

    /// Sections for `types`: recently used first (most recent first, only those in `types`), then one section per
    /// family in name order. With a query, only matching types appear (the recent section too).
    public static func sections(types: [Element], recent: [ElementID], query: String, recentLimit: Int = 5) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matching = types.filter { q.isEmpty || match(searchText($0), query: q) != nil }
        let ids = Set(matching.map(\.id))
        var out: [Section] = []
        let mru = recent.filter(ids.contains).prefix(recentLimit)
        if !mru.isEmpty { out.append(Section(title: "Most Recently Used", types: Array(mru), isRecent: true)) }
        let families = Dictionary(grouping: matching, by: { $0.typeData?.familyName ?? "" })
        for fam in families.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let list = families[fam]!.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            out.append(Section(title: fam, types: list.map(\.id), isRecent: false))
        }
        return out
    }

    /// Records a use: `id` moves to the front; the list keeps at most `limit` entries.
    public static func noteUse(_ id: ElementID, in recent: [ElementID], limit: Int = 12) -> [ElementID] {
        Array(([id] + recent.filter { $0 != id }).prefix(limit))
    }
}
