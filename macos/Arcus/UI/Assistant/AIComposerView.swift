import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ArcusAssistant

// AICORE: the composer: the selection as chips with the "Use selection" toggle, attached images, a multi-line field
// (Return adds a line, ⌘Return sends, paste or drop images) and the Send / Stop button.

struct AIComposer: View {
    @Bindable var panel: AIAssistantPanel
    @State private var height: CGFloat = 20
    @State private var dropTarget = false

    var body: some View {
        let agent = panel.agent
        let chips = agent.host.selection()
        VStack(alignment: .leading, spacing: 7) {
            if !chips.isEmpty { AISelectionChips(panel: panel, chips: chips) }
            if !panel.attachments.isEmpty { attachmentsRow }
            HStack(alignment: .bottom, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if panel.draft.isEmpty {
                        Text(placeholder).font(.system(size: 12.5)).foregroundStyle(.tertiary).padding(.top, 1).allowsHitTesting(false)
                    }
                    AIPromptField(text: $panel.draft, height: $height, focusRequest: panel.focusRequest,
                                  onSend: { panel.send() }, onImages: { panel.attach($0) })
                        .frame(height: min(max(height, 18), 120))
                }
                .padding(.vertical, 4)
                Button { pickImages() } label: { Image(systemName: "paperclip").font(.system(size: 13)).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Attach images (or paste or drop them)").accessibilityLabel("Attach images")
                    .disabled(panel.attachments.count >= AIAttachment.maxCount)
                sendButton
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dropTarget ? AIStyle.tint : AIStyle.stroke, lineWidth: dropTarget ? 2 : 1))
            .onDrop(of: [.image, .fileURL], isTargeted: $dropTarget) { providers in drop(providers) }
            HStack(spacing: 4) {
                Text(agent.isRunning ? "Stop with ⌘." : "⌘↩ to send · Return for a new line")
                Spacer()
                Text("Haiku 5.5 · Sonnet 5.5 retries")
                    .help("Haiku 5.5 does the work; a step that fails Arcus's check twice is retried on Sonnet 5.5.")
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
    }

    private var placeholder: String {
        switch panel.kind {
        case .project: "Ask for a change, a drawing or a PDF…"
        case .furniture: "Describe the piece or a change…"
        case .family: "Ask about this family…"
        }
    }

    @ViewBuilder private var sendButton: some View {
        if panel.agent.isRunning {
            Button { panel.agent.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.75)))
            }
            .buttonStyle(.plain).keyboardShortcut(".", modifiers: .command)
            .help("Stop (⌘.)").accessibilityLabel("Stop")
        } else {
            Button { panel.send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(panel.canSend ? AIStyle.tint : Color.secondary.opacity(0.35)))
            }
            .buttonStyle(.plain).disabled(!panel.canSend)
            .help("Send (⌘↩)").accessibilityLabel("Send")
        }
    }

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(panel.attachments) { a in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: a.thumbnail).resizable().aspectRatio(contentMode: .fill).frame(width: 52, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(AIStyle.stroke))
                        Button { panel.attachments.removeAll { $0.id == a.id } } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 13)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain).offset(x: 5, y: -5).accessibilityLabel("Remove \(a.name)")
                    }
                    .help(a.name)
                }
            }
            .padding(.top, 5).padding(.trailing, 6)
        }
    }

    private func pickImages() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.message = "Choose images for the assistant (sketches, photos, markups)."
        guard p.runModal() == .OK else { return }
        panel.attach(p.urls.compactMap { NSImage(contentsOf: $0) }, names: p.urls.map(\.lastPathComponent))
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers {
            if p.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    let wrapped = UncheckedImage(image: img)
                    DispatchQueue.main.async { panel.attach([wrapped.image]) }
                }
            }
        }
        return handled
    }
}

/// Carries an NSImage across the drop callback's queue hop.
private struct UncheckedImage: @unchecked Sendable { let image: NSImage }

/// The selected elements as chips, with the toggle that decides whether they go with the prompt.
struct AISelectionChips: View {
    @Bindable var panel: AIAssistantPanel
    let chips: [AISelectionChip]
    var body: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { panel.useSelection }, set: { panel.useSelection = $0 })) {
                Text("Use selection").font(.system(size: 11))
            }
            .toggleStyle(.checkbox).controlSize(.small)
            .help("Send the selected elements with the prompt (“these”, “the selected”)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chips.prefix(6)) { c in chip(c.title, c.category) }
                    if chips.count > 6 { chip("+\(chips.count - 6)", "more selected") }
                }
            }
            .opacity(panel.useSelection ? 1 : 0.45)
        }
    }

    private func chip(_ title: String, _ help: String) -> some View {
        Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            .padding(.horizontal, PillSpec.padding).padding(.vertical, 3) // PILLS: 12 pt sides
            .background(Capsule().fill(AIStyle.tint.opacity(0.13)))
            .overlay(Capsule().strokeBorder(AIStyle.tint.opacity(0.3)))
            .help(help)
    }
}

/// The prompt field: an NSTextView so ⌘Return sends, Return inserts a line, and pasted images become attachments.
struct AIPromptField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var focusRequest: Int
    var onSend: () -> Void
    var onImages: ([NSImage]) -> Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        let tv = PromptTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12.5)
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.setAccessibilityLabel("Prompt")
        tv.onSend = { context.coordinator.parent.onSend() }
        tv.onImages = { context.coordinator.parent.onImages($0) }
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text; context.coordinator.measure() }
        if context.coordinator.lastFocus != focusRequest {
            context.coordinator.lastFocus = focusRequest
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIPromptField
        weak var textView: PromptTextView?
        var lastFocus = -1
        init(_ p: AIPromptField) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            measure()
        }
        func measure() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = max(17, lm.usedRect(for: tc).height)
            if abs(h - parent.height) > 0.5 { DispatchQueue.main.async { self.parent.height = h } }
        }
    }
}

/// ⌘Return sends; image paste attaches.
final class PromptTextView: NSTextView {
    var onSend: (() -> Void)?
    var onImages: (([NSImage]) -> Int)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command) { onSend?(); return }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command), window?.firstResponder === self { onSend?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], !images.isEmpty {
            if (onImages?(images) ?? 0) > 0 { return }
        }
        super.paste(sender)
    }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { super.readablePasteboardTypes + [.png, .tiff] }
}
