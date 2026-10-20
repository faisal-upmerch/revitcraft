import AppKit
import SwiftUI
import ArcusDomain
import ArcusCalc
import ArcusApplication
import ArcusCAD
import ArcusMCP
import ArcusAssistant

// AICORE: one window's AI assistant: whether the sidebar is shown, the agent (on the window's own document through
// the MCP tool layer, in process), the composer's text, attachments and selection toggle. Project and Furniture
// windows get theirs from `AIAssistantPanel.of(state)`, Family Editor windows from `of(family:)`.

@MainActor
@Observable
final class AIAssistantPanel {
    private static var panels: [ObjectIdentifier: AIAssistantPanel] = [:]

    /// The panel of a project or Furniture window.
    static func of(_ state: DocumentState) -> AIAssistantPanel {
        let k = ObjectIdentifier(state)
        if let p = panels[k] { return p }
        let host = AIWindowDocumentHost(state: state)
        let toolbox = ArcusToolbox(host: host, dwgHelper: BundledDWGHelpers.standard.acadrust)
        let aiHost = ToolboxAIHost(toolbox: toolbox, selection: { [weak state] in state.map(AIAssistantPanel.chips) ?? [] },
                                   activeView: { [weak state] in state?.activeView.map { ViewTitles.qualified($0) } })
        let p = AIAssistantPanel(host: aiHost)
        if let data = state.document?.assistantHistory, let h = try? AIHistory.decode(data) { p.agent.store.load(h) }
        p.agent.store.onChange = { [weak state] in state?.document?.updateChangeCount(.changeDone) }
        p.selectionCount = { [weak state] in state?.session.selection.count ?? 0 }
        panels[k] = p
        return p
    }

    /// The panel of a Family Editor window.
    static func of(family model: FamilyEditorModel) -> AIAssistantPanel {
        let k = ObjectIdentifier(model)
        if let p = panels[k] { return p }
        // The family tools work on the editor's family (FamilyEditingHost); project-level tools (load into project)
        // reach the project window the family belongs to.
        let toolbox = ArcusToolbox(host: AIWindowDocumentHost(state: model.state))
        let family = FamilyEditorModelHost(model: model)
        toolbox.familyHostProvider = { family }
        let host = ToolboxAIHost(toolbox: toolbox, selection: { [weak model] in
            guard let s = model?.selection else { return [] }
            return [AISelectionChip(id: 0, title: String(describing: s), category: "Family item")]
        })
        host.undoManager = { [weak model] in model?.undo }
        let p = AIAssistantPanel(host: host)
        p.selectionCount = { [weak model] in model?.selection == nil ? 0 : 1 }
        panels[k] = p
        return p
    }

    /// QA: a panel on preview settings (in-memory defaults and key, never the user's), installed for the window.
    @discardableResult
    static func installPreview(_ state: DocumentState, settings: AISettings) -> AIAssistantPanel {
        let toolbox = ArcusToolbox(host: AIWindowDocumentHost(state: state))
        let host = ToolboxAIHost(toolbox: toolbox, selection: { [weak state] in state.map(AIAssistantPanel.chips) ?? [] },
                                 activeView: { [weak state] in state?.activeView.map { ViewTitles.qualified($0) } })
        let p = AIAssistantPanel(host: host, settings: settings, transport: OfflineTransport())
        p.selectionCount = { [weak state] in state?.session.selection.count ?? 0 }
        panels[ObjectIdentifier(state)] = p
        return p
    }

    static func existingPanel(_ k: ObjectIdentifier) -> AIAssistantPanel? { panels[k] }
    static func forget(_ owner: AnyObject) { panels.removeValue(forKey: ObjectIdentifier(owner)) }
    /// The saved chats of a document window's panel (nil when the assistant was never opened in it).
    static func historyData(_ state: DocumentState) -> Data? {
        guard let p = panels[ObjectIdentifier(state)] else { return nil }
        let h = p.agent.store.history
        return h.chats.isEmpty ? Data() : try? h.encoded()
    }

    let agent: AIAgent
    let settings: AISettings
    /// The sidebar is open.
    var isShown = false
    var draft = ""
    var attachments: [AIAttachment] = []
    /// Bumped to focus the composer.
    var focusRequest = 0
    /// The History list is open instead of the chat.
    var showingHistory = false
    @ObservationIgnored var selectionCount: () -> Int = { 0 }

    init(host: any AIToolHost, settings: AISettings = .shared, transport: (any AITransport)? = nil) {
        self.settings = settings
        let client = AnthropicClient(transport: transport ?? URLSessionTransport(), access: AISettings.access(settings))
        agent = AIAgent(host: host, client: client, settings: settings)
    }

    var kind: AIDocumentKind { agent.host.documentKind }
    var useSelection: Bool {
        get { settings.useSelection }
        set { settings.useSelection = newValue }
    }

    /// Opens or closes the sidebar (the AI button, ⇧⌘A, the command).
    func toggle() {
        isShown.toggle()
        if isShown { focusRequest += 1 }
    }

    /// Sends the composer's prompt (⌘↩ or the send button).
    func send() {
        guard canSend else { return }
        let text = draft
        let images = attachments.map(\.image)
        draft = ""
        attachments = []
        showingHistory = false
        agent.send(text, images: images, useSelection: useSelection)
    }

    /// Sends a suggested prompt as is.
    func send(_ prompt: String) {
        draft = prompt
        send()
    }

    var canSend: Bool {
        !agent.isRunning && settings.isReady && settings.explainedWhatIsSent
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    /// Why the composer can't send, for the state shown instead of the empty state.
    var blocker: AIBlocker? {
        if !settings.enabled { return .off }
        if !settings.hasKey { return .noKey }
        if !settings.explainedWhatIsSent { return .explain }
        if settings.budgetReached { return .budget }
        return nil
    }

    // MARK: Attachments

    /// Adds images from the pasteboard or a drop. Returns how many were added.
    @discardableResult
    func attach(_ images: [NSImage], names: [String] = []) -> Int {
        var n = 0
        for (i, img) in images.enumerated() where attachments.count < AIAttachment.maxCount {
            if let a = AIAttachment(img, name: i < names.count ? names[i] : "Image \(attachments.count + 1)") { attachments.append(a); n += 1 }
        }
        return n
    }

    /// Selection chips of a document window: up to 50 selected elements.
    static func chips(_ state: DocumentState) -> [AISelectionChip] {
        let m = state.model
        return state.session.selection.ids.prefix(50).compactMap { id in
            guard let e = m[id] else { return nil }
            let type = e.typeID.flatMap { m[$0]?.name } ?? ""
            let title = !e.name.isEmpty ? e.name : (!type.isEmpty ? type : "\(e.category.displayName) \(id.raw)")
            return AISelectionChip(id: Int(id.raw), title: title, category: e.category.displayName)
        }
    }
}

/// Why the assistant can't run yet.
enum AIBlocker: Equatable {
    case off, noKey, explain, budget
}

/// An image attached in the composer, scaled so its long edge is at most 1568 px (larger images cost more and aren't
/// read better) and encoded as JPEG (photos) or PNG (drawings with flat colour).
struct AIAttachment: Identifiable {
    static let maxCount = 5
    static let maxEdge: CGFloat = 1568
    let id = UUID()
    let name: String
    let thumbnail: NSImage
    let image: AIImage

    init?(_ source: NSImage, name: String) {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, Self.maxEdge / max(w, h))
        let size = NSSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cg, size: NSSize(width: w, height: h)).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:]) ?? Data()
        let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) ?? Data()
        let usePNG = !png.isEmpty && (jpeg.isEmpty || png.count <= jpeg.count * 2)
        let data = usePNG ? png : jpeg
        guard !data.isEmpty, data.count < 5_000_000 else { return nil }
        self.name = name
        thumbnail = NSImage(size: size)
        thumbnail.addRepresentation(rep)
        image = AIImage(name: name, mediaType: usePNG ? "image/png" : "image/jpeg", data: data)
    }
}

/// The assistant's DocumentHost: always this window's document (never another window), saving through NSDocument.
@MainActor
final class AIWindowDocumentHost: DocumentHost {
    let backendName = "assistant"
    weak var state: DocumentState?

    init(state: DocumentState) { self.state = state }

    var document: ArcusDocument? { state?.document }
    var session: DocumentSession? { state?.session }
    var documentURL: URL? { document?.fileURL }
    var documentName: String { document?.displayName ?? state?.documentName ?? "" }

    func adopt(_ model: BIMModel, name: String) throws(ToolError) {
        throw ToolError("The assistant works in this window's document; it can't start another one.")
    }
    func open(_ url: URL) throws(ToolError) {
        throw ToolError("The assistant works in this window's document; open other files from File ▸ Open.")
    }
    func save(to url: URL?) async throws(ToolError) -> URL {
        guard let doc = document else { throw ToolError("No document.") }
        guard let dest = url ?? doc.fileURL else {
            throw ToolError("“\(doc.displayName ?? "This document")” hasn't been saved yet. Pass path, e.g. ~/Documents/Arcus/\(doc.displayName ?? "Untitled").\(FileDocumentHost.fileExtension(doc.session.model)).")
        }
        let op: NSDocument.SaveOperationType = url == nil || url == doc.fileURL ? .saveOperation : .saveToOperation
        let type = ArcusDocument.documentType(doc.session.model).identifier
        let error: (any Error)? = await withCheckedContinuation { cont in
            doc.save(to: dest, ofType: type, for: op) { cont.resume(returning: $0) }
        }
        if let error { throw ToolError("Arcus could not save to \(dest.path): \(error.localizedDescription)") }
        return dest
    }
}

/// QA previews: a transport that never connects.
struct OfflineTransport: AITransport {
    func open(_ request: URLRequest) async throws -> (status: Int, headers: [String: String], lines: AsyncThrowingStream<String, any Error>) {
        throw URLError(.notConnectedToInternet)
    }
}

// AICORE: the window features the tool layer asks for (DocumentUIHost): the active view, opening views, zooming and
// running menu commands, all in this window.
extension AIWindowDocumentHost: DocumentUIHost {
    var activeViewID: ElementID? { state?.activeViewID }

    func activateView(_ id: ElementID) -> Bool {
        guard let s = state, let e = s.model[id], e.view != nil || e.sheet != nil || e.schedule != nil else { return false }
        s.open(id)
        return true
    }

    func zoom(to ids: [ElementID]?) {
        guard let s = state else { return }
        if let ids, !ids.isEmpty { SelectByIDDialog.showElements(ids, state: s) } else { CommandRouter(state: s).run(.zoomExtents) }
    }

    func commandDisabledReason(_ id: CommandID) -> String? {
        guard let s = state else { return "No window." }
        return CommandRouter(state: s).disabledReason(id)
    }

    func runCommand(_ id: CommandID) -> CommandOutcome {
        guard let s = state else { return .unavailable("No window.") }
        let router = CommandRouter(state: s)
        if let r = router.disabledReason(id) { return .unavailable(r) }
        router.run(id)
        if let t = s.activeTool { return .startedTool(t.prompt) }
        return .done(CommandCatalog.info(id).title)
    }

    /// Project and Furniture windows have no family in front (the Family Editor's panel passes its own).
    var familyHost: (any FamilyEditingHost)? { nil }
}

/// AICORE: the Family Editor window's family for the tool layer's family tools: edits go through the editor's
/// `edit` (re-evaluated, one undo step on the family's own stack), loading through Load into Project.
@MainActor
final class FamilyEditorModelHost: FamilyEditingHost {
    weak var model: FamilyEditorModel?
    init(model: FamilyEditorModel) { self.model = model }

    var family: FamilyDefinition { model?.family ?? FamilyDefinition(name: "", template: .genericModel) }
    var currentType: String {
        get { model?.currentType ?? "" }
        set { model?.currentType = newValue }
    }
    var units: UnitsSettings { model?.units ?? .imperial }

    func apply(name: String, edit: (inout FamilyDefinition) throws -> Void) throws {
        guard let m = model else { throw ToolError("The Family Editor window is closed.") }
        var next = m.family
        try edit(&next)
        m.edit(name) { $0 = next }
    }

    func loadIntoProject() throws -> String {
        guard let m = model else { throw ToolError("The Family Editor window is closed.") }
        guard m.loadIntoProject() else { throw ToolError(m.message ?? "The family wasn't loaded.") }
        return m.message ?? "Loaded “\(m.family.name)” into the project."
    }
}
