import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W2-ANNOT: editing text notes where they are, on the canvas. The editor sits at the note's top-left at the size the
// note prints (never smaller than a readable minimum). Return adds a line; Esc or a click on the canvas finishes;
// an empty note is discarded.

@MainActor
final class InPlaceTextEditor: NSObject, NSTextViewDelegate {
    let scroll: NSScrollView
    let textView: NSTextView
    /// Top-left of the text in view coordinates.
    let anchor: Vec2
    /// Wrap width on paper (meters; 0 = none) and cap height on paper.
    let wrap: Double
    let capHeight: Double
    weak var canvas: Canvas2DView?
    private var completion: ((String?) -> Void)?
    private let fontBold: Bool, fontItalic: Bool

    init(canvas: Canvas2DView, at anchor: Vec2, initial: String, capHeight: Double, wrap: Double, bold: Bool, italic: Bool,
         completion: @escaping (String?) -> Void) {
        self.canvas = canvas
        self.anchor = anchor
        self.capHeight = capHeight
        self.wrap = wrap
        self.completion = completion
        self.fontBold = bold
        self.fontItalic = italic
        scroll = NSScrollView(frame: .zero)
        textView = NSTextView(frame: .zero)
        super.init()
        textView.string = initial
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92)
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.delegate = self
        textView.setAccessibilityLabel("Text note")
        scroll.documentView = textView
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.borderColor = NSColor.controlAccentColor.cgColor
        scroll.layer?.borderWidth = 1.5
        scroll.layer?.cornerRadius = 3
        canvas.addSubview(scroll, positioned: .above, relativeTo: nil)
        reposition()
        canvas.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    var font: NSFont {
        guard let canvas else { return .systemFont(ofSize: 13) }
        // Cap height on screen = paper cap height × points per paper meter; Helvetica Neue caps are ~0.714 em.
        let capPts = capHeight * canvas.zoom * canvas.scaleDenominator
        let size = max(11, min(96, capPts / 0.714))
        var f = NSFont(name: fontBold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
        if fontItalic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    /// Places the editor over the note after pans and zooms.
    func reposition() {
        guard let canvas else { return }
        textView.font = font
        let top = canvas.toScreen(anchor)
        let wrapPts = wrap > 0 ? wrap * canvas.zoom * canvas.scaleDenominator : 0
        let lm = textView.layoutManager, tc = textView.textContainer
        var usedWidth: CGFloat = 0
        if let lm, let tc { lm.ensureLayout(for: tc); usedWidth = lm.usedRect(for: tc).width }
        let width: CGFloat = wrapPts > 0 ? max(60, CGFloat(wrapPts) + 8) : max(160, min(640, usedWidth + 40))
        if let tc { tc.widthTracksTextView = true; tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude) }
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        if let lm, let tc { lm.ensureLayout(for: tc) }
        var usedHeight = font.pointSize
        if let lm, let tc { usedHeight = lm.usedRect(for: tc).height }
        let used = usedHeight + 8
        let height = max(font.pointSize * 1.5, used)
        scroll.frame = NSRect(x: top.x - 3, y: top.y - height + 2, width: width, height: height)
        textView.frame.size = NSSize(width: width, height: height)
    }

    func textDidChange(_ notification: Notification) { reposition() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { finish(commit: true); return true }
        return false
    }

    func textDidEndEditing(_ notification: Notification) { finish(commit: true) }

    /// Ends editing: `commit` hands the text to the completion (nil when cancelled).
    func finish(commit: Bool) {
        guard let done = completion else { return }
        completion = nil
        let text = textView.string
        scroll.removeFromSuperview()
        canvas?.inPlaceText = nil
        canvas?.window?.makeFirstResponder(canvas)
        done(commit ? text : nil)
    }
}

extension Canvas2DView {
    /// Starts editing text at `anchor` (view coordinates, the top-left of the text).
    func beginInPlaceText(at anchor: Vec2, initial: String, style: TextNoteStyle, wrap: Double, completion: @escaping (String?) -> Void) {
        inPlaceText?.finish(commit: true)
        inPlaceText = InPlaceTextEditor(canvas: self, at: anchor, initial: initial, capHeight: style.size, wrap: wrap, bold: style.bold,
                                        italic: style.italic, completion: completion)
    }
}

extension DocumentState {
    /// Text typed in place on the view's canvas (a sheet dialog when the view has no canvas open).
    func editTextInPlace(viewID: ElementID, at p: Vec2, initial: String, completion: @escaping (String?) -> Void) {
        guard let canvas = canvas2D(for: viewID) else { requestText(prompt: "Text", initial: initial, completion: completion); return }
        let type = currentTypes[.textNotes] ?? model.types(for: .textNotes).first?.id
        canvas.beginInPlaceText(at: p, initial: initial, style: TextNoteStyle.of(type: model[type]?.typeData), wrap: 0, completion: completion)
    }

    /// Double-click on a text note: edit its text where it is.
    func editTextNote(_ e: Element) {
        guard let n = e.textNote else { return }
        let finish: (String?) -> Void = { [weak self] text in
            guard let self, let text else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.session.delete([e.id])
            } else if text != n.text {
                self.session.perform("Edit Text") { tx in tx.update(e.id) { $0.textNote?.text = text } }
            }
        }
        guard let v = e.ownerViewID, let canvas = canvas2D(for: v) ?? (activeViewID.flatMap { canvas2D(for: $0) }) else {
            requestText(prompt: "Edit Text", initial: n.text, completion: finish); return
        }
        let style = TextNoteStyle.resolve(e, model)
        let scale = model[v]?.view.map { Double(max($0.scale, 1)) } ?? 1
        let box = TextNoteGeometry.box(n, style, scale: scale)
        canvas.beginInPlaceText(at: box.origin, initial: n.text, style: style, wrap: n.width, completion: finish)
    }
}
