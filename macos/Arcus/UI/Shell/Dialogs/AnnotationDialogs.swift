import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

// W2-ANNOT: Find/Replace over text notes and tag values, and Check Spelling with the system spell checker (on this
// Mac; nothing leaves it).

struct FindReplaceDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var find = ""
    @State private var replace = ""
    @State private var matchCase = false
    @State private var wholeWords = false
    @State private var scope: TextSearch.Scope = .view
    @State private var excluded: Set<String> = []
    @State private var result: String?

    var options: TextSearch.Options { TextSearch.Options(matchCase: matchCase, wholeWords: wholeWords) }

    func describe(_ m: TextSearch.Match) -> String {
        switch m.source {
        case .textNote: return "Text Note"
        case .tagValue(_, let e, _, let name): return "\(state.model[e]?.category.singularName ?? "Element") \(name) (tag)"
        }
    }

    var body: some View {
        let _ = state.session.changeCounter
        let selection = state.session.selection.ids
        let matches = TextSearch.find(find, options, scope: scope, view: viewID, selection: selection, state.model)
        let chosen = matches.filter { !excluded.contains($0.id) }
        DialogFrameWithActions(title: "Find/Replace", icon: "magnifyingglass", tint: .blue, size: .large, subtitle: "Text notes and the values tags show. Replacing in a tag changes the tagged element.",
                    okTitle: "Done", showCancel: false, labelWidth: 100, state: state) { state.presented = nil } content: {
            DialogSection {
                DialogRow("Find") { TextField("", text: $find).labelsHidden() }
                DialogRow("Replace with") { TextField("", text: $replace).labelsHidden() }
                DialogRow("Search in") {
                    Picker("", selection: $scope) { ForEach(TextSearch.Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                DialogRow("") { HStack(spacing: 16) { Toggle("Match case", isOn: $matchCase); Toggle("Whole words only", isOn: $wholeWords) } }
            }
            DialogSection(find.isEmpty ? "Matches" : "\(matches.count) match\(matches.count == 1 ? "" : "es")" + (excluded.isEmpty ? "" : ", \(chosen.count) to replace"), boxed: false) {
            DialogListBox(count: matches.count, rowHeight: 62, minRows: 2, maxRows: 4, isEmpty: matches.isEmpty) {
            List(matches) { m in
                HStack(alignment: .top) {
                    Toggle("", isOn: Binding(get: { !excluded.contains(m.id) }, set: { on in if on { excluded.remove(m.id) } else { excluded.insert(m.id) } }))
                        .labelsHidden().toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(describe(m)).font(.caption).foregroundStyle(.secondary)
                        Text(m.text).lineLimit(2).strikethrough(true, color: .red.opacity(0.35))
                        Text(m.replaced(with: replace)).lineLimit(2).foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Show") {
                        let id: ElementID
                        switch m.source {
                        case .textNote(let t): id = t
                        case .tagValue(let tag, _, _, _): id = tag
                        }
                        state.session.selection.select([id])
                    }
                    .controlSize(.small)
                }
            }
            } empty: {
                DialogEmptyState(icon: "magnifyingglass", title: find.isEmpty ? "Type the text to find" : "No matches")
            }
            }
            if let result { DialogNotice(.success, result) }
        } actions: {
                Button("Replace \(chosen.count == matches.count ? "All" : "Selected")") {
                    let q = find, r = replace, o = options
                    var n = 0
                    state.session.perform("Replace Text") { tx in n = try TextSearch.replace(chosen, query: q, with: r, o, in: tx) }
                    if let e = state.session.lastError { result = e.message; state.session.clearError() } else { result = "Replaced text in \(n) place\(n == 1 ? "" : "s"). Undo reverts every change." }
                    excluded = []
                }
                .disabled(find.isEmpty || chosen.isEmpty)
        }
        .onAppear { if !state.session.selection.ids.isEmpty { scope = .selection } }
    }
}

/// A misspelling found in annotation text.
struct SpellingIssue: Identifiable, Hashable {
    var source: TextSearch.Source
    var word: String
    var range: Range<Int>
    var context: String
    var id: String { "\(source)-\(range.lowerBound)" }
}

@MainActor
enum AnnotationSpelling {
    static let documentTag = NSSpellChecker.uniqueSpellDocumentTag()

    static func isMisspelled(_ word: String) -> Bool {
        guard word.count > 1, word.rangeOfCharacter(from: .decimalDigits) == nil, word != word.uppercased() || word.count > 3 else { return false }
        let r = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false, inSpellDocumentWithTag: documentTag, wordCount: nil)
        return r.location != NSNotFound
    }

    static func guesses(_ word: String) -> [String] {
        NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: nil,
                                      inSpellDocumentWithTag: documentTag) ?? []
    }

    static func ignore(_ word: String) { NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: documentTag) }

    /// Misspellings in the text notes and tag texts of the selection (or of the view).
    static func issues(_ state: DocumentState, viewID: ElementID) -> [SpellingIssue] {
        let sel = state.session.selection.ids
        let scope: TextSearch.Scope = sel.contains { state.model[$0]?.textNote != nil || state.model[$0]?.tag != nil } ? .selection : .view
        var out: [SpellingIssue] = []
        var seenTags = Set<String>()
        for e in TextSearch.annotations(scope: scope, view: viewID, selection: sel, state.model).sorted(by: { $0.id < $1.id }) {
            var texts: [(TextSearch.Source, String)] = []
            if let n = e.textNote { texts.append((.textNote(e.id), n.text)) }
            if let t = e.tag {
                for (pid, name, value) in TextSearch.tagTexts(e, state.model) where seenTags.insert("\(t.taggedID.raw)-\(pid.key)").inserted {
                    texts.append((.tagValue(tag: e.id, element: t.taggedID, parameter: pid, name: name), value))
                }
            }
            for (src, text) in texts {
                for w in TextSearch.words(text) where isMisspelled(w.word) {
                    out.append(SpellingIssue(source: src, word: w.word, range: w.range, context: text))
                }
            }
        }
        return out
    }
}

struct CheckSpellingDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var issues: [SpellingIssue] = []
    @State private var index = 0
    @State private var replacement = ""
    @State private var scanned = false

    var current: SpellingIssue? { index < issues.count ? issues[index] : nil }

    func rescan() {
        issues = AnnotationSpelling.issues(state, viewID: viewID)
        index = 0
        replacement = current.map { AnnotationSpelling.guesses($0.word).first ?? $0.word } ?? ""
        scanned = true
    }

    func change(all: Bool) {
        guard let c = current else { return }
        let word = replacement
        let targets = all ? issues.filter { $0.word == c.word } : [c]
        // Later ranges first, so earlier ranges in the same text stay valid.
        let ordered = targets.sorted { ($0.source.editedElement.raw, $0.range.lowerBound) > ($1.source.editedElement.raw, $1.range.lowerBound) }
        state.session.perform(all ? "Change All Spelling" : "Change Spelling") { tx in
            for t in ordered { try TextSearch.replaceRange(t.source, t.range, with: word, in: tx) }
        }
        rescan()
    }

    var body: some View {
        DialogFrame(title: "Check Spelling", icon: "textformat.abc", tint: .blue, subtitle: "Text notes and tag texts in the selection or this view, with the macOS dictionary.",
                    okTitle: "Done", showCancel: false, labelWidth: 90, state: state) { state.presented = nil } content: {
            if !scanned {
                ProgressView().frame(maxWidth: .infinity).onAppear { rescan() }
            } else if let c = current {
                DialogSection("Not in dictionary · \(index + 1) of \(issues.count)") {
                    Text(c.context).frame(maxWidth: .infinity, alignment: .leading)
                    DialogRow("Word") { Text("“\(c.word)”").font(.headline) }
                    DialogRow("Change to") { TextField("", text: $replacement).labelsHidden() }
                }
                let guesses = AnnotationSpelling.guesses(c.word)
                if !guesses.isEmpty {
                    DialogSection("Suggestions", boxed: false) {
                        DialogListBox(count: guesses.count, rowHeight: 26, minRows: 1, maxRows: 4) {
                            List(guesses, id: \.self) { g in
                                Button(g) { replacement = g }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Button("Ignore") { index += 1; replacement = current.map { AnnotationSpelling.guesses($0.word).first ?? $0.word } ?? "" }
                    Button("Ignore All") { AnnotationSpelling.ignore(c.word); rescan() }
                    Spacer()
                    Button("Change") { change(all: false) }.disabled(replacement.isEmpty || replacement == c.word)
                    Button("Change All") { change(all: true) }.disabled(replacement.isEmpty || replacement == c.word)
                }
            } else {
                DialogNotice(.success, issues.isEmpty ? "No spelling mistakes found." : "Spelling check complete.")
            }
        }
    }
}
