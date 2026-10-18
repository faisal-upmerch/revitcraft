import Foundation

// W2-ANNOT: Find/Replace and spelling support over annotation text. Text notes are searched directly; tags are
// searched through the text parameters their labels show (a room tag's Name, a door tag's Mark…), so replacing
// in a tag edits the tagged element, exactly as editing the label would.
public enum TextSearch {
    public enum Scope: String, CaseIterable, Sendable { case selection = "Selection", view = "Current View", project = "Whole Project" }

    public struct Options: Sendable, Hashable {
        public var matchCase: Bool
        public var wholeWords: Bool
        public init(matchCase: Bool = false, wholeWords: Bool = false) { self.matchCase = matchCase; self.wholeWords = wholeWords }
    }

    /// Where a found text lives.
    public enum Source: Sendable, Hashable {
        case textNote(ElementID)
        /// A text parameter of `element` shown by `tag`.
        case tagValue(tag: ElementID, element: ElementID, parameter: ParameterID, name: String)

        /// The element whose text changes.
        public var editedElement: ElementID {
            switch self {
            case .textNote(let id): id
            case .tagValue(_, let e, _, _): e
            }
        }
    }

    public struct Match: Sendable, Hashable, Identifiable {
        public var source: Source
        /// The whole text the match is in.
        public var text: String
        /// Occurrences in `text` (character offsets).
        public var ranges: [Range<Int>]
        public var id: String {
            switch source {
            case .textNote(let e): "t\(e.raw)"
            case .tagValue(let t, let e, let p, _): "g\(t.raw)-\(e.raw)-\(p.key)"
            }
        }
        /// The text after replacing every occurrence with `replacement`.
        public func replaced(with replacement: String) -> String {
            var out = ""
            var cursor = 0
            let chars = Array(text)
            for r in ranges {
                out += String(chars[cursor..<r.lowerBound]) + replacement
                cursor = r.upperBound
            }
            return out + String(chars[cursor...])
        }
    }

    /// Occurrences of `query` in `text`.
    public static func occurrences(of query: String, in text: String, _ o: Options) -> [Range<Int>] {
        guard !query.isEmpty else { return [] }
        let hay = Array(o.matchCase ? text : text.lowercased())
        let needle = Array(o.matchCase ? query : query.lowercased())
        guard needle.count <= hay.count else { return [] }
        var out: [Range<Int>] = []
        var i = 0
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        while i + needle.count <= hay.count {
            if Array(hay[i..<(i + needle.count)]) == needle {
                let before = i > 0 ? hay[i - 1] : " ", after = i + needle.count < hay.count ? hay[i + needle.count] : " "
                if !o.wholeWords || (!isWord(before) && !isWord(after)) {
                    out.append(i..<(i + needle.count))
                    i += needle.count
                    continue
                }
            }
            i += 1
        }
        return out
    }

    /// Text notes and tags in scope: the view's own annotations (sheets include their viewports' views), the given
    /// selection, or the whole project.
    public static func annotations(scope: Scope, view: ElementID?, selection: [ElementID], _ model: BIMModel) -> [Element] {
        let isText: (Element) -> Bool = { $0.textNote != nil || ($0.tag != nil && $0.tag?.kind == nil) }
        switch scope {
        case .selection: return selection.compactMap { model[$0] }.filter(isText)
        case .project: return (model.elements(.textNotes) + model.elements(.tags)).filter(isText)
        case .view:
            guard let v = view else { return [] }
            var views = [v]
            for vp in model.owned(byView: v) { if let id = vp.viewport?.viewID { views.append(id) } }
            return views.flatMap { model.owned(byView: $0) }.filter(isText)
        }
    }

    /// Text parameters a tag shows (label parameter names of its family) with their values on the tagged element.
    public static func tagTexts(_ tag: Element, _ model: BIMModel) -> [(id: ParameterID, name: String, value: String)] {
        guard let t = tag.tag, let target = model[t.taggedID], let fam = Parameters.familyDefinition(for: tag, model) else { return [] }
        var out: [(ParameterID, String, String)] = []
        for lb in fam.labels {
            guard let name = lb.parameterName, let d = Parameters.descriptor(named: name, for: target, model) else { continue }
            switch d.type {
            case .text, .multilineText: break
            default: continue
            }
            guard Parameters.isEditable(d.id, on: target, model), !out.contains(where: { $0.0 == d.id }) else { continue }
            out.append((d.id, name, Parameters.value(d.id, of: target, model)?.textValue ?? ""))
        }
        return out
    }

    /// Every match of `query` in the annotations of `scope`. A tagged element's parameter is listed once even when
    /// several tags show it.
    public static func find(_ query: String, _ o: Options = Options(), scope: Scope, view: ElementID?, selection: [ElementID] = [],
                            _ model: BIMModel) -> [Match] {
        var out: [Match] = []
        var seen = Set<String>()
        for e in annotations(scope: scope, view: view, selection: selection, model).sorted(by: { $0.id < $1.id }) {
            if let n = e.textNote {
                let r = occurrences(of: query, in: n.text, o)
                if !r.isEmpty { out.append(Match(source: .textNote(e.id), text: n.text, ranges: r)) }
            } else if let t = e.tag {
                for (pid, name, value) in tagTexts(e, model) {
                    let key = "\(t.taggedID.raw)-\(pid.key)"
                    guard !seen.contains(key) else { continue }
                    let r = occurrences(of: query, in: value, o)
                    if !r.isEmpty { seen.insert(key); out.append(Match(source: .tagValue(tag: e.id, element: t.taggedID, parameter: pid, name: name), text: value, ranges: r)) }
                }
            }
        }
        return out
    }

    /// Replaces the matches (re-found in the current model so stale ones are skipped). Returns how many texts changed.
    @discardableResult
    public static func replace(_ matches: [Match], query: String, with replacement: String, _ o: Options = Options(), in tx: TransactionContext) throws -> Int {
        var n = 0
        for m in matches {
            switch m.source {
            case .textNote(let id):
                guard let text = tx.model[id]?.textNote?.text else { continue }
                let r = occurrences(of: query, in: text, o)
                guard !r.isEmpty else { continue }
                let new = Match(source: m.source, text: text, ranges: r).replaced(with: replacement)
                tx.update(id) { $0.textNote?.text = new }
                n += 1
            case .tagValue(_, let element, let pid, _):
                guard let e = tx.model[element], let text = Parameters.value(pid, of: e, tx.model)?.textValue else { continue }
                let r = occurrences(of: query, in: text, o)
                guard !r.isEmpty else { continue }
                try Parameters.set(pid, to: .text(Match(source: m.source, text: text, ranges: r).replaced(with: replacement)), on: element, in: tx)
                n += 1
            }
        }
        return n
    }

    /// Replaces the characters `range` of the text of `source` with `word` (spelling corrections).
    public static func replaceRange(_ source: Source, _ range: Range<Int>, with word: String, in tx: TransactionContext) throws {
        switch source {
        case .textNote(let id):
            guard let text = tx.model[id]?.textNote?.text, range.upperBound <= text.count else { return }
            tx.update(id) { $0.textNote?.text = Match(source: source, text: text, ranges: [range]).replaced(with: word) }
        case .tagValue(_, let element, let pid, _):
            guard let e = tx.model[element], let text = Parameters.value(pid, of: e, tx.model)?.textValue, range.upperBound <= text.count else { return }
            try Parameters.set(pid, to: .text(Match(source: source, text: text, ranges: [range]).replaced(with: word)), on: element, in: tx)
        }
    }

    /// Words of a text with their character ranges (for spell checking).
    public static func words(_ text: String) -> [(word: String, range: Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var start: Int?
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            let inWord = c.isLetter || (c == "'" && start != nil)
            if inWord { if start == nil { start = i } } else if let s = start {
                out.append((String(chars[s..<i]), s..<i)); start = nil
            }
        }
        if let s = start { out.append((String(chars[s...]), s..<chars.count)) }
        return out
    }
}
