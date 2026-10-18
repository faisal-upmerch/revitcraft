import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// BL-BROWSER: the Project Browser as an AppKit outline. It owns keyboard focus for inline renaming (the editor becomes
// first responder with the name selected), starts real drag-and-drop (views onto sheets), follows the active view, and
// builds the context menus (ProjectBrowserMenus.swift).

/// SwiftUI host for the Project Browser outline.
struct ProjectBrowserOutline: NSViewRepresentable {
    let state: DocumentState
    let tree: [BrowserNode]
    let activeViewID: ElementID?
    let openViews: [ElementID]
    let filtering: Bool
    /// Links the outline to its SwiftUI host (renaming state for the keyboard-suppression modifier).
    var handle: ProjectBrowserHandle? = nil

    func makeCoordinator() -> ProjectBrowserController {
        let c = ProjectBrowserController(state: state)
        handle?.controller = c
        c.handle = handle
        return c
    }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(tree: tree, active: activeViewID, open: Set(openViews), filtering: filtering)
    }
}

/// The SwiftUI host's view of the outline: whether an inline rename is active, and a way to refocus its field.
@MainActor
@Observable
final class ProjectBrowserHandle {
    var isRenaming = false
    @ObservationIgnored weak var controller: ProjectBrowserController?
    func focusRenameField() { controller?.focusRenameField() }
}

/// Reference wrapper for outline items (NSOutlineView identifies items by object).
final class BrowserItem: NSObject {
    let node: BrowserNode
    var children: [BrowserItem] = []
    init(_ node: BrowserNode) { self.node = node }
}

/// Data source, delegate, renaming and drag-and-drop for the Project Browser outline.
@MainActor
final class ProjectBrowserController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    weak var state: DocumentState?
    weak var handle: ProjectBrowserHandle?
    let outline = BrowserOutlineView()
    let scrollView = NSScrollView()
    private(set) var tree: [BrowserNode] = []
    private var roots: [BrowserItem] = []
    private var byID: [String: BrowserItem] = [:]
    /// Expanded folders, kept per user across projects.
    private var expanded: Set<String>
    private var active: ElementID?
    private var openViews: Set<ElementID> = []
    private var filtering = false
    private var syncedActive: ElementID?
    private var loaded = false
    /// Programmatic selection or expansion in progress (not the user's).
    private var quiet = false
    private var pendingTree: [BrowserNode]?
    private(set) var lastSelectionChange = Date.distantPast

    struct RenameSession { let nodeID: String; let original: String; weak var cell: BrowserCell? }
    private(set) var renaming: RenameSession?

    static let expandedKey = "navigator.expanded"

    init(state: DocumentState) {
        self.state = state
        expanded = Set(UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? ["views", "views.Floor Plans", "sheets", "schedules"])
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .custom
        outline.rowHeight = 22
        outline.indentationPerLevel = 13
        outline.allowsMultipleSelection = true
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.backgroundColor = .clear
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.controller = self
        outline.registerForDraggedTypes([.string])
        outline.setDraggingSourceOperationMask(.copy, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.draggingDestinationFeedbackStyle = .regular
        outline.setAccessibilityLabel("Project Browser")
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
    }

    // MARK: Updates

    func update(tree: [BrowserNode], active: ElementID?, open: Set<ElementID>, filtering: Bool) {
        let styleChanged = active != self.active || open != openViews
        self.active = active; openViews = open
        let filterChanged = filtering != self.filtering
        self.filtering = filtering
        if renaming != nil {
            // Never rebuild under the inline editor; apply once it closes.
            if tree != self.tree { pendingTree = tree }
            return
        }
        if tree != self.tree || filterChanged || !loaded {
            self.tree = tree
            reload()
        } else if styleChanged {
            refreshVisibleCells()
        }
        if !loaded || active != syncedActive { syncSelectionToActiveView() }
        loaded = true
    }

    private func reload() {
        quiet = true
        defer { quiet = false }
        let selected = Set(selectedNodes().map(\.id))
        byID = [:]
        func make(_ n: BrowserNode) -> BrowserItem {
            let item = BrowserItem(n)
            item.children = (n.children ?? []).map(make)
            byID[n.id] = item
            return item
        }
        roots = tree.map(make)
        outline.reloadData()
        outline.sizeLastColumnToFit()
        func restore(_ items: [BrowserItem]) {
            for i in items where !i.children.isEmpty && (filtering || expanded.contains(i.node.id)) {
                outline.expandItem(i)
                restore(i.children)
            }
        }
        restore(roots)
        let rows = IndexSet(selected.compactMap { byID[$0] }.map { outline.row(forItem: $0) }.filter { $0 >= 0 })
        outline.selectRowIndexes(rows, byExtendingSelection: false)
    }

    private func refreshVisibleCells() {
        outline.enumerateAvailableRowViews { rowView, row in
            if let cell = rowView.view(atColumn: 0) as? BrowserCell, let item = self.outline.item(atRow: row) as? BrowserItem {
                self.configure(cell, item.node)
            }
        }
    }

    /// Selects (and reveals) the active view's node, whichever way the view was activated (tab, double-click,
    /// duplicate, schedule jump, menu, sheet viewport).
    private func syncSelectionToActiveView() {
        syncedActive = active
        guard let state, let active, let id = ProjectBrowserTree.nodeID(forOpenable: active, state.model) else { return }
        reveal(id)
        guard let item = byID[id] else { return }
        let row = outline.row(forItem: item)
        guard row >= 0 else { return }
        quiet = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        quiet = false
        lastSelectionChange = Date()
        outline.scrollRowToVisible(row)
    }

    /// Expands the folders above a node.
    func reveal(_ id: String) {
        for a in ProjectBrowserTree.ancestors(of: id, in: tree) { if let i = byID[a] { outline.expandItem(i) } }
    }

    func expandAll() { outline.expandItem(nil, expandChildren: true) }
    func collapseAll() { outline.collapseItem(nil, collapseChildren: true) }

    // MARK: Lookup

    func node(atRow row: Int) -> BrowserNode? { (outline.item(atRow: row) as? BrowserItem)?.node }
    func selectedNodes() -> [BrowserNode] { outline.selectedRowIndexes.compactMap { node(atRow: $0) } }
    func item(_ id: String) -> BrowserItem? { byID[id] }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? BrowserItem)?.children.count ?? roots.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? BrowserItem)?.children ?? roots)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? BrowserItem)?.children.isEmpty ?? true)
    }

    // MARK: Cells

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = (item as? BrowserItem)?.node else { return nil }
        let cell = outlineView.makeView(withIdentifier: BrowserCell.identifier, owner: nil) as? BrowserCell ?? BrowserCell()
        configure(cell, node)
        return cell
    }

    func configure(_ cell: BrowserCell, _ node: BrowserNode) {
        let openable = [.view, .sheet, .schedule].contains(node.kind)
        let isActive = openable && node.elementID != nil && node.elementID == active
        let isOpen = openable && !isActive && node.elementID.map(openViews.contains) == true
        cell.configure(node, tint: tint(node), active: isActive, open: isOpen)
    }

    /// Symbol colours tell views, sheets, schedules and families apart at a glance.
    func tint(_ node: BrowserNode) -> NSColor {
        switch node.kind {
        case .folder: return node.id.hasPrefix("views.") || node.id.hasPrefix("f.") || node.id.hasPrefix("groups.") ? .secondaryLabelColor : .controlAccentColor
        case .view, .placedView:
            if node.symbol.contains("cube") || node.symbol == "camera" { return NSColor(RibbonContent.view) }
            if node.symbol.contains("tablecells") { return NSColor(RibbonContent.rooms) }
            return NSColor(RibbonContent.build)
        case .sheet: return NSColor(RibbonContent.sheet)
        case .schedule: return NSColor(RibbonContent.rooms)
        case .family, .type: return NSColor(RibbonContent.circulation)
        case .group: return NSColor(RibbonContent.datum)
        case .link: return NSColor(RibbonContent.annotate)
        }
    }

    // MARK: Selection and activation

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !quiet, renaming == nil, let state else { return }
        lastSelectionChange = Date()
        let nodes = selectedNodes().filter { $0.kind != .folder && $0.kind != .family }
        // A single view, sheet or schedule previews its properties without joining the model selection (no
        // contextual ribbon tab, ARCUS-019); other items are selected. BL-BROWSER hook
        if nodes.count == 1, [.view, .sheet, .schedule, .placedView].contains(nodes[0].kind), let e = nodes[0].elementID, state.model[e] != nil {
            state.previewViewProperties(e)
            return
        }
        let ids = nodes.compactMap(\.elementID).filter { state.model[$0] != nil }
        if !ids.isEmpty { state.session.selection.select(ids) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !quiet, !filtering, let item = notification.userInfo?["NSObject"] as? BrowserItem else { return }
        expanded.insert(item.node.id); saveExpanded()
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !quiet, !filtering, let item = notification.userInfo?["NSObject"] as? BrowserItem else { return }
        expanded.remove(item.node.id); saveExpanded()
    }
    private func saveExpanded() { UserDefaults.standard.set(Array(expanded).sorted(), forKey: Self.expandedKey) }

    @objc func doubleClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = node(atRow: row) else { return }
        activate(node)
    }

    /// Double-click / Return: opens views, sheets and schedules; types show Type Properties; folders toggle.
    func activate(_ node: BrowserNode) {
        guard let state else { return }
        switch node.kind {
        case .view, .sheet, .schedule, .placedView:
            if let e = node.elementID { state.open(e) }
        case .type:
            if let e = node.elementID { state.presented = .typeProperties(e) }
        case .folder, .family:
            guard let item = byID[node.id] else { return }
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
        case .group:
            if let e = node.elementID { ProjectBrowserActions(state: state, browser: self).selectGroupInstances(e) }
        case .link:
            if let e = node.elementID { state.session.selection.select([e]) }
        }
    }

    // MARK: Context menu

    func contextMenu(forRow row: Int) -> NSMenu? {
        guard let state, let node = node(atRow: row) else { return nil }
        let all = outline.selectedRowIndexes.contains(row) ? selectedNodes() : [node]
        return ProjectBrowserMenus(state: state, browser: self).menu(for: node, all: all)
    }

    // MARK: Renaming

    /// Nodes renamed in place. Sheets use the Sheet Title dialog (number and name); system families keep their names.
    func renameUnavailableReason(_ node: BrowserNode) -> String? {
        switch node.kind {
        case .view, .schedule, .type, .group, .sheet: return nil
        case .family: return node.elementID == nil ? "Built-in (system) families can't be renamed; rename their types instead." : nil
        case .placedView: return nil
        default: return "This item can't be renamed."
        }
    }

    /// Starts renaming: views, schedules, types, families and groups edit in place; sheets open the Sheet Title dialog.
    func beginRename(_ nodeID: String) {
        guard let state, renaming == nil, var node = byID[nodeID]?.node else { return }
        if node.kind == .placedView, let e = node.elementID, let n = ProjectBrowserTree.nodeID(forOpenable: e, state.model), let target = byID[n]?.node { node = target }
        if let reason = renameUnavailableReason(node) { state.show(reason, error: true); return }
        if node.kind == .sheet, let e = node.elementID { state.presented = .sheetTitle(e); return }
        reveal(node.id)
        guard let item = byID[node.id] else { return }
        let row = outline.row(forItem: item)
        guard row >= 0 else { return }
        quiet = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        quiet = false
        outline.scrollRowToVisible(row)
        guard let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? BrowserCell else { return }
        let current = editableName(node)
        // The browser takes the keyboard: end any running tool so it can't receive keystrokes.
        state.cancelTool()
        renaming = RenameSession(nodeID: node.id, original: current, cell: cell)
        handle?.isRenaming = true
        cell.beginEditing(current, delegate: self)
        focusRenameField()
    }

    /// Gives the rename field the keyboard with its whole text selected.
    func focusRenameField() {
        guard let field = renaming?.cell?.textField else { return }
        if field.currentEditor() != nil || outline.window?.makeFirstResponder(field) == true { field.currentEditor()?.selectAll(nil) }
    }

    func editableName(_ node: BrowserNode) -> String {
        if node.kind == .family { return node.familyName ?? node.title }
        if node.kind == .group { return node.title }
        return node.elementID.flatMap { state?.model[$0]?.name } ?? node.title
    }

    func renameProblem(_ node: BrowserNode, _ name: String) -> String? {
        guard let state else { return "The project is closed." }
        if node.kind == .family {
            return BrowserNaming.familyRenameProblem(node.familyName ?? "", category: node.category ?? .genericModels, to: name, in: state.model)
        }
        guard let e = node.elementID else { return "The item no longer exists." }
        return BrowserNaming.renameProblem(e, to: name, in: state.model)
    }

    /// Enter: commits a valid name; an invalid one is reported and the editor stays open with the text selected.
    /// Focus loss: commits a valid name, otherwise keeps the old one.
    @discardableResult
    func commitRename(keepOpenOnError: Bool) -> Bool {
        guard let state, let r = renaming, let node = byID[r.nodeID]?.node, let field = r.cell?.textField else { finishRename(refocus: keepOpenOnError); return false }
        let name = BrowserNaming.normalized(field.stringValue)
        if name == r.original { finishRename(refocus: keepOpenOnError); return true }
        if let problem = renameProblem(node, name) {
            state.show(problem, error: true)
            if keepOpenOnError {
                NSSound.beep()
                field.currentEditor()?.selectAll(nil)
            } else {
                finishRename(refocus: false)
            }
            return false
        }
        finishRename(refocus: keepOpenOnError)
        ProjectBrowserActions(state: state, browser: self).rename(node, to: name)
        return true
    }

    /// Closes the editor. `refocus` returns the keyboard to the browser (Enter, Esc); focus loss leaves it where it went.
    func finishRename(refocus: Bool = true) {
        guard let r = renaming else { return }
        renaming = nil
        handle?.isRenaming = false
        r.cell?.endEditing()
        if let node = byID[r.nodeID]?.node, let cell = r.cell { configure(cell, node) }
        if refocus { outline.window?.makeFirstResponder(outline) }
        if let t = pendingTree { pendingTree = nil; tree = t; reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard renaming != nil else { return false }
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            finishRename(); return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            commitRename(keepOpenOnError: true); return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard renaming != nil else { return }
        commitRename(keepOpenOnError: false)
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let node = (item as? BrowserItem)?.node, [.view, .schedule, .placedView].contains(node.kind), let e = node.elementID else { return nil }
        let p = NSPasteboardItem()
        p.setString(Canvas2DView.elementDragPrefix + String(e.raw), forType: .string)
        return p
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        outline.dragStarted = true
        outline.cancelPendingRename()
    }

    /// Views dropped on a sheet node (or on a view placed on it) start placing them on that sheet.
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let sheet = dropSheet(item), !Canvas2DView.draggedElementIDs(info.draggingPasteboard).isEmpty else { return [] }
        outlineView.setDropItem(sheet, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .copy
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let state, let sheet = dropSheet(item)?.node.elementID else { return false }
        return state.beginViewportPlacement(Canvas2DView.draggedElementIDs(info.draggingPasteboard), onSheet: sheet)
    }

    private func dropSheet(_ item: Any?) -> BrowserItem? {
        guard let item = item as? BrowserItem else { return nil }
        if item.node.kind == .sheet { return item }
        if item.node.kind == .placedView, let parent = outline.parent(forItem: item) as? BrowserItem, parent.node.kind == .sheet { return parent }
        return nil
    }
}

/// The outline view: F2 and slow double-click rename, Return opens, and right-click menus.
final class BrowserOutlineView: NSOutlineView {
    weak var controller: ProjectBrowserController?
    var dragStarted = false
    private var pendingRename: DispatchWorkItem?

    func cancelPendingRename() { pendingRename?.cancel(); pendingRename = nil }

    override func mouseDown(with event: NSEvent) {
        cancelPendingRename()
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        let wasSoleSelection = row >= 0 && selectedRowIndexes == IndexSet(integer: row)
        let selectedAt = controller?.lastSelectionChange ?? .distantPast
        dragStarted = false
        super.mouseDown(with: event)
        // Slow double-click: a second single click on the already selected row, after the double-click interval.
        guard event.clickCount == 1, wasSoleSelection, !dragStarted,
              event.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty,
              Date().timeIntervalSince(selectedAt) > NSEvent.doubleClickInterval,
              let controller, let node = controller.node(atRow: row), node.kind != .sheet,
              controller.renameUnavailableReason(node) == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.selectedRowIndexes == IndexSet(integer: row), self.controller?.node(atRow: row)?.id == node.id else { return }
            self.controller?.beginRename(node.id)
        }
        pendingRename = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.05, execute: work)
    }

    override func keyDown(with event: NSEvent) {
        guard let controller, controller.renaming == nil else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 36, 76: // Return, Enter
            if let n = controller.selectedNodes().first { controller.activate(n) }
        case 120: // F2
            if let n = controller.selectedNodes().first { controller.beginRename(n.id) }
        default:
            super.keyDown(with: event)
        }
    }

    /// F2 is also the Rename menu item's key equivalent; while the browser has focus it renames the browser item.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 120, window?.firstResponder === self, let controller, controller.renaming == nil,
           let n = controller.selectedNodes().first {
            controller.beginRename(n.id)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return controller?.contextMenu(forRow: row)
    }
}

/// A Project Browser row: symbol, name (bold for the active view), a dot for other open views, and a trailing detail.
final class BrowserCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("BrowserCell")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let dot = NSView()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        imageView = icon
        textField = title
        title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: 11)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.cell?.usesSingleLineMode = true
        detail.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        detail.setContentHuggingPriority(.required, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        dot.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
        for v in [icon, title, detail, dot] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 17),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 4),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 5), dot.heightAnchor.constraint(equalToConstant: 5),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: dot.trailingAnchor, constant: 4),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ node: BrowserNode, tint: NSColor, active: Bool, open: Bool) {
        icon.image = NSImage(systemSymbolName: node.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11.5, weight: .regular))
        icon.contentTintColor = tint
        if title.currentEditor() == nil { title.stringValue = node.title }
        title.font = .systemFont(ofSize: 11, weight: active ? .bold : .regular)
        detail.stringValue = node.subtitle
        dot.isHidden = !open
        toolTip = open ? "\(node.title) (open)" : nil
        setAccessibilityLabel(node.title + (active ? ", active view" : open ? ", open" : "") + (node.subtitle.isEmpty ? "" : ", \(node.subtitle)"))
    }

    func beginEditing(_ text: String, delegate: any NSTextFieldDelegate) {
        title.stringValue = text
        title.isEditable = true
        title.isSelectable = true
        title.isBezeled = true
        title.bezelStyle = .roundedBezel
        title.drawsBackground = true
        title.backgroundColor = .textBackgroundColor
        title.focusRingType = .exterior
        title.delegate = delegate
        title.setAccessibilityLabel("Name")
    }

    func endEditing() {
        title.abortEditing()
        title.delegate = nil
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.drawsBackground = false
    }
}
