import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// A live schedule: a dense table computed from the model that edits in place like a spreadsheet (BL-SCHED).
///
/// Clicking a cell makes it the active cell (its row is highlighted); typing, Return, a second click or a double-click
/// edits it. Text cells take numbers with units; type, level, material, phase, Yes/No and choice cells open a drop-down.
/// Tab/⇧Tab/arrows/Return move the active cell. Read-only cells (calculated, counts, totals, measured values) refuse
/// with a brief tint and the reason in the status bar. Highlight in Model (ribbon, or ⌥-double-click) selects the
/// row's elements in a model view. Row clicks don't change the model selection, so the Properties palette and the
/// ribbon keep showing the schedule.
final class ScheduleTableView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    unowned let state: DocumentState
    let scheduleID: ElementID
    private let scroll = NSScrollView()
    let table = ScheduleGrid()
    private let header = NSTextField(labelWithString: "")
    private let summary = NSTextField(labelWithString: "")
    private let groupStrip = ScheduleHeaderGroupStrip()
    private var groupStripHeight: NSLayoutConstraint?
    private(set) var tableModel: ScheduleTable?
    private var changeToken: UUID?
    private var generation = 0

    /// Active cell and the anchor of a shift-extended range (row, column indices into `tableModel`).
    private(set) var active: (row: Int, column: Int)?
    private var anchor: (row: Int, column: Int)?
    /// The active row's elements, to find it again after a recompute re-sorts the rows.
    private var activeKey: [ElementID] = []
    /// Cell being edited in place.
    private var editing: (row: Int, column: Int)?
    private var editCancelled = false
    private var flash: (row: Int, column: Int)?

    init(state: DocumentState, scheduleID: ElementID) {
        self.state = state
        self.scheduleID = scheduleID
        super.init(frame: .zero)
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        let props = NSButton(title: "Schedule Properties…", target: self, action: #selector(openProperties))
        props.bezelStyle = .push
        props.controlSize = .small
        props.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        props.imagePosition = .imageLeading
        let exportB = NSButton(title: "Export CSV…", target: self, action: #selector(exportCSV))
        exportB.controlSize = .small
        exportB.bezelStyle = .push
        let bar = NSStackView(views: [header, summary, NSView(), exportB, props])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        table.owner = self
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.rowHeight = 20
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.dataSource = self
        table.delegate = self
        table.headerView = ScheduleHeaderView()
        table.setAccessibilityLabel("Schedule table")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        groupStrip.owner = self
        let stack = NSStackView(views: [bar, groupStrip, scroll])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let stripHeight = groupStrip.heightAnchor.constraint(equalToConstant: 0)
        groupStripHeight = stripHeight
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor), // W4-WIRE: clear of the floating shell
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: stack.leadingAnchor), bar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            groupStrip.leadingAnchor.constraint(equalTo: stack.leadingAnchor), groupStrip.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            stripHeight,
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        changeToken = state.session.onChange { [weak self] _ in self?.recompute() }
        recompute()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func openProperties() { state.presented = .scheduleProperties(scheduleID) }
    @objc private func exportCSV() { ExportActions(state: state).exportScheduleCSV() }
    @objc private func scrolled() { groupStrip.offset = scroll.contentView.bounds.origin.x; groupStrip.needsDisplay = true }

    var schedule: Element? { state.model[scheduleID] }

    func recompute() {
        guard let s = state.model[scheduleID], s.schedule != nil else { return }
        generation += 1
        let gen = generation
        let model = state.model
        Task { [weak self] in
            let interval = Signpost.begin("schedule recompute")
            let t = await Task.detached(priority: .userInitiated) { ScheduleEngine.compute(s, model) }.value
            guard let self, gen == self.generation else { Signpost.end(interval, completed: false); return }
            Signpost.end(interval)
            self.apply(t)
        }
    }

    /// Recomputes synchronously (QA and commands that act on the table right after a model change).
    func recomputeNow() {
        guard let s = state.model[scheduleID], s.schedule != nil else { return }
        generation += 1
        apply(ScheduleEngine.compute(s, state.model))
    }

    private func apply(_ t: ScheduleTable) {
        let columnsChanged = tableModel.map { $0.columns.map(\.id) != t.columns.map(\.id) || $0.columns.map(\.heading) != t.columns.map(\.heading)
            || $0.columns.map(\.width) != t.columns.map(\.width) } ?? true
        let activeFieldID = active.flatMap { a in tableModel.flatMap { a.column < $0.columns.count ? $0.columns[a.column].id : nil } }
        tableModel = t
        header.stringValue = t.title
        summary.stringValue = "\(t.elementCount) items · \(t.rows.filter { $0.kind == .data }.count) rows"
        if columnsChanged {
            for c in table.tableColumns { table.removeTableColumn(c) }
            for f in t.columns {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(f.id))
                col.title = f.heading
                col.width = max(60, f.width * Self.pixelsPerPaperMeter)
                col.minWidth = 40
                col.headerCell.alignment = .center
                col.headerToolTip = f.heading
                table.addTableColumn(col)
            }
        }
        table.gridStyleMask = t.appearance.gridLines ? [.solidVerticalGridLineMask, .solidHorizontalGridLineMask] : []
        if t.showHeaders { if table.headerView == nil { table.headerView = ScheduleHeaderView() } } else { table.headerView = nil }
        groupStrip.spans = t.showHeaders ? t.headerSpans : []
        groupStrip.widths = table.tableColumns.map(\.width)
        groupStripHeight?.constant = groupStrip.spans.isEmpty ? 0 : 20
        groupStrip.needsDisplay = true
        // Keep the active cell on the same elements and field after re-sorting.
        if let a = active {
            let row = activeKey.isEmpty ? a.row : (t.rows.firstIndex { $0.elementIDs == activeKey } ?? a.row)
            let col = activeFieldID.flatMap { id in t.columns.firstIndex { $0.id == id } } ?? a.column
            active = t.rows.isEmpty || t.columns.isEmpty ? nil : (min(row, t.rows.count - 1), min(col, t.columns.count - 1))
            anchor = anchor.map { (min($0.row, max(0, t.rows.count - 1)), min($0.column, max(0, t.columns.count - 1))) }
        }
        table.reloadData()
        if let a = active { table.selectRowIndexes(selectedRows, byExtendingSelection: false); table.scrollRowToVisible(a.row) }
        setAccessibilityLabel("Schedule: \(t.title), \(t.elementCount) items")
        ScheduleUIState.shared.revision += 1
    }

    /// Screen pixels per paper meter for column widths (a 25 mm column is 100 px wide).
    static let pixelsPerPaperMeter = 4000.0

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int { tableModel?.rows.count ?? 0 }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard let r = tableModel?.rows[row] else { return false }
        return r.kind == .groupHeader
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let t = tableModel, row < t.rows.count else { return nil }
        let r = t.rows[row]
        if r.kind == .groupHeader {
            let tf = NSTextField(labelWithString: r.title)
            tf.font = .systemFont(ofSize: 11, weight: .semibold)
            return tf
        }
        guard let col = tableColumn, let ci = t.columns.firstIndex(where: { $0.id == col.identifier.rawValue }) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let tf = (tableView.makeView(withIdentifier: id, owner: self) as? ScheduleCellField) ?? {
            let f = ScheduleCellField()
            f.identifier = id
            f.isBordered = false
            f.drawsBackground = false
            f.isEditable = false
            f.isSelectable = false
            f.lineBreakMode = .byTruncatingTail
            f.cell?.usesSingleLineMode = true
            f.delegate = self
            f.target = self
            f.action = #selector(cellEdited(_:))
            return f
        }()
        var text = ci < r.cells.count ? r.cells[ci].text : ""
        if ci == 0, r.kind != .data, !r.title.isEmpty, text.isEmpty { text = r.title }
        if editing.map({ $0.row == row && $0.column == ci }) != true {
            tf.isEditable = false
            tf.stringValue = text
        }
        let cell = ci < r.cells.count ? r.cells[ci] : nil
        let aff = schedule?.schedule.map { ScheduleEditing.affordance(t, row: row, column: ci, def: $0, model: state.model) } ?? (editable: false, dropDown: false, hint: nil)
        tf.alignment = cell?.alignment == .right ? .right : cell?.alignment == .center ? .center : .left
        let size = max(9, min(18, CGFloat(t.appearance.bodyTextHeight / 0.0022 * 11)))
        tf.font = r.kind == .data ? .monospacedDigitSystemFont(ofSize: size, weight: .regular) : .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        tf.textColor = aff.editable ? .labelColor : (r.kind == .data ? .secondaryLabelColor : .labelColor)
        let isActive = active.map { $0.row == row && $0.column == ci } ?? false
        tf.isActiveCell = isActive
        tf.showsChevron = isActive && aff.dropDown
        tf.inRange = !isActive && selectedColumns.contains(ci) && selectedRows.contains(row)
        tf.isFlashing = flash.map { $0.row == row && $0.column == ci } ?? false
        tf.fill = cell?.background?.nsColor
        tf.tag = row * 1000 + ci
        tf.toolTip = aff.hint
        tf.setAccessibilityLabel("\(t.columns[ci].heading): \(text)\(aff.editable ? "" : ", read only")")
        tf.needsDisplay = true
        return tf
    }

    // MARK: Active cell and range

    var selectedRows: IndexSet {
        guard let a = active else { return [] }
        let b = anchor ?? a
        return IndexSet(integersIn: min(a.row, b.row)...max(a.row, b.row))
    }
    var selectedColumns: IndexSet {
        guard let a = active else { return [] }
        let b = anchor ?? a
        return IndexSet(integersIn: min(a.column, b.column)...max(a.column, b.column))
    }
    /// Fields of the selected columns (active column when nothing is extended).
    var selectedFieldIDs: [String] {
        guard let t = tableModel else { return [] }
        return selectedColumns.filter { $0 < t.columns.count }.map { t.columns[$0].id }
    }
    /// Elements of the selected rows (grouped rows contribute every element).
    var selectedElementIDs: [ElementID] {
        guard let t = tableModel else { return [] }
        var seen = Set<ElementID>()
        return selectedRows.filter { $0 < t.rows.count && t.rows[$0].kind == .data }.flatMap { t.rows[$0].elementIDs }.filter { seen.insert($0).inserted }
    }

    func setActive(row: Int, column: Int, extend: Bool = false) {
        guard let t = tableModel, !t.rows.isEmpty, !t.columns.isEmpty else { return }
        let r = max(0, min(row, t.rows.count - 1)), c = max(0, min(column, t.columns.count - 1))
        let oldRows = selectedRows.union(IndexSet(integer: active?.row ?? r))
        if extend { if anchor == nil { anchor = active } } else { anchor = nil }
        active = (r, c)
        activeKey = t.rows[r].kind == .data ? t.rows[r].elementIDs : []
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        table.scrollRowToVisible(r)
        table.scrollColumnToVisible(c)
        reload(rows: oldRows.union(selectedRows))
        ScheduleUIState.shared.revision += 1
    }

    private func reload(rows: IndexSet) {
        guard let t = tableModel else { return }
        let valid = rows.filteredIndexSet { $0 < t.rows.count }
        table.reloadData(forRowIndexes: valid, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
    }

    /// Moves the active cell; Tab wraps to the next row, arrows stop at the edges.
    func move(dRow: Int, dColumn: Int, wrap: Bool = false, extend: Bool = false) {
        guard let t = tableModel, let a = active else { setActive(row: 0, column: 0); return }
        var r = a.row, c = a.column + dColumn
        if wrap {
            if c >= t.columns.count { c = 0; r += 1 } else if c < 0 { c = t.columns.count - 1; r -= 1 }
        }
        r += dRow
        // Skip group headers and blank rows when moving vertically.
        let step = dRow != 0 ? dRow.signum() : (r != a.row ? (r - a.row).signum() : 0)
        while step != 0, r >= 0, r < t.rows.count, t.rows[r].kind == .groupHeader || t.rows[r].kind == .blank { r += step }
        guard r >= 0, r < t.rows.count else { return }
        setActive(row: r, column: max(0, min(c, t.columns.count - 1)), extend: extend)
    }

    // MARK: Mouse and keyboard

    /// Returns true when the click was handled (the grid doesn't run NSTableView's own selection tracking).
    func handleClick(row: Int, column: Int, event: NSEvent) -> Bool {
        guard let t = tableModel, row >= 0, row < t.rows.count, column >= 0 else { return false }
        window?.makeFirstResponder(table)
        if event.clickCount >= 2 && event.modifierFlags.contains(.option) { setActive(row: row, column: column); highlightInModel(); return true }
        let wasActive = active.map { $0.row == row && $0.column == column } ?? false
        setActive(row: row, column: column, extend: event.modifierFlags.contains(.shift))
        if event.clickCount >= 2 || (wasActive && event.clickCount == 1 && !event.modifierFlags.contains(.shift)) { beginEditing() }
        return true
    }

    /// Keyboard navigation and type-to-edit. Returns true when handled.
    func handleKey(_ e: NSEvent) -> Bool {
        guard tableModel != nil else { return false }
        let shift = e.modifierFlags.contains(.shift)
        switch e.keyCode {
        case 48: move(dRow: 0, dColumn: shift ? -1 : 1, wrap: true); return true               // Tab / ⇧Tab
        case 36, 76: if active == nil { setActive(row: 0, column: 0) } else { beginEditing() }; return true // Return / Enter
        case 123: move(dRow: 0, dColumn: -1, extend: shift); return true
        case 124: move(dRow: 0, dColumn: 1, extend: shift); return true
        case 125: move(dRow: 1, dColumn: 0, extend: shift); return true
        case 126: move(dRow: -1, dColumn: 0, extend: shift); return true
        case 53: if anchor != nil, let a = active { setActive(row: a.row, column: a.column) }; return true // Esc collapses the range
        case 51, 117: // ⌫ / ⌦ clear a text cell
            guard active != nil, case .text? = activeTarget?.editor else { refuseIfReadOnly(); return true }
            commit("", at: active!)
            return true
        default: break
        }
        if e.modifierFlags.intersection([.command, .control]).isEmpty, let ch = e.characters, let scalar = ch.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar), scalar.value < 0xF700 {
            beginEditing(typing: ch)
            return true
        }
        return false
    }

    /// The active cell's edit target.
    var activeTarget: ScheduleCellTarget? {
        guard let t = tableModel, let s = schedule, let a = active else { return nil }
        return ScheduleEditing.target(t, row: a.row, column: a.column, schedule: s, model: state.model)
    }

    /// Starts editing the active cell: a text field for text/number cells, a menu for drop-down cells.
    func beginEditing(typing: String? = nil) {
        guard let a = active, let target = activeTarget else { return }
        switch target.editor {
        case .readOnly: refuseIfReadOnly()
        case .options(let opts):
            if let typing, typing != " " {
                // Typing on a drop-down cell jumps to the first option starting with the letters.
                if let o = opts.first(where: { $0.title.lowercased().hasPrefix(typing.lowercased()) }) { showOptions(opts, at: a, preselect: o.title) } else { showOptions(opts, at: a) }
            } else {
                showOptions(opts, at: a)
            }
        case .text:
            guard let tf = table.view(atColumn: a.column, row: a.row, makeIfNecessary: true) as? ScheduleCellField else { return }
            editing = a
            editCancelled = false
            tf.isEditable = true
            tf.isSelectable = true
            tf.textColor = .labelColor
            window?.makeFirstResponder(tf)
            if let typing, let editor = tf.currentEditor() as? NSTextView {
                editor.string = typing
                editor.setSelectedRange(NSRange(location: (typing as NSString).length, length: 0))
            } else {
                tf.currentEditor()?.selectAll(nil)
            }
        }
    }

    private func showOptions(_ opts: [ScheduleCellOption], at a: (row: Int, column: Int), preselect: String? = nil) {
        let menu = NSMenu()
        let current = tableModel.map { a.row < $0.rows.count && a.column < $0.rows[a.row].cells.count ? $0.rows[a.row].cells[a.column].text : "" } ?? ""
        var highlighted: NSMenuItem?
        for o in opts {
            let item = NSMenuItem(title: o.title, action: #selector(optionChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OptionChoice(row: a.row, column: a.column, value: o.value)
            item.state = o.title == current || current.hasSuffix(": " + o.title) && !current.isEmpty ? .on : .off
            if o.title == (preselect ?? current) { highlighted = item }
            menu.addItem(item)
        }
        let rect = table.frameOfCell(atColumn: a.column, row: a.row)
        menu.popUp(positioning: highlighted, at: NSPoint(x: rect.minX, y: rect.maxY), in: table)
    }

    private final class OptionChoice: NSObject {
        let row: Int, column: Int, value: ParamValue
        init(row: Int, column: Int, value: ParamValue) { self.row = row; self.column = column; self.value = value }
    }

    @objc private func optionChosen(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? OptionChoice, let t = tableModel else { return }
        let ok = state.session.editScheduleCell(scheduleID, table: t, row: c.row, column: c.column, value: c.value)
        report(ok, target: activeTarget)
    }

    /// The subtle cue for a read-only cell: a short tint and the reason in the status bar.
    func refuseIfReadOnly() {
        guard let a = active, let target = activeTarget, case .readOnly(let why) = target.editor else { return }
        flash = a
        reload(rows: IndexSet(integer: a.row))
        if !why.isEmpty { state.show(why) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.flash.map({ $0.row == a.row && $0.column == a.column }) == true else { return }
            self.flash = nil
            self.reload(rows: IndexSet(integer: a.row))
        }
    }

    // MARK: Committing

    /// Writes text into a cell (one undo step). Used by in-place editing and QA.
    @discardableResult
    func commit(_ text: String, at cell: (row: Int, column: Int)) -> Bool {
        guard let t = tableModel, cell.row < t.rows.count, cell.column < t.columns.count, let s = schedule else { return false }
        let target = ScheduleEditing.target(t, row: cell.row, column: cell.column, schedule: s, model: state.model)
        let current = cell.column < t.rows[cell.row].cells.count ? t.rows[cell.row].cells[cell.column].text : ""
        guard text != current else { return true }
        let ok = state.session.editScheduleCell(scheduleID, table: t, row: cell.row, column: cell.column, text: text)
        report(ok, target: target)
        return ok
    }

    private func report(_ ok: Bool, target: ScheduleCellTarget?) {
        if !ok || state.session.lastError != nil {
            state.show(state.session.lastError?.message ?? "The value couldn't be applied.", error: true)
            state.session.clearError()
            recompute()
        } else if let target, ScheduleEditing.writesToType(target, model: state.model),
                  let e = target.elementIDs.first.flatMap({ state.model[$0] }), let type = state.model.type(of: e) {
            let n = state.model.elements(e.category).filter { $0.typeID == type.id }.count
            state.show("“\(target.heading)” is a type parameter: changed type “\(type.name)” (\(n) element\(n == 1 ? "" : "s")).")
        }
    }

    @objc private func cellEdited(_ sender: NSTextField) {
        // Action fires on Return/Tab and on end editing; controlTextDidEndEditing does the work for in-place edits.
        guard editing == nil else { return }
        let row = sender.tag / 1000, ci = sender.tag % 1000
        commit(sender.stringValue, at: (row, ci))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            editCancelled = true
            control.abortEditing()
            finishEditing(control as? NSTextField, movement: .cancel)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        let movement = (obj.userInfo?["NSTextMovement"] as? Int).flatMap { NSTextMovement(rawValue: $0) }
        finishEditing(tf, movement: movement)
    }

    private func finishEditing(_ tf: NSTextField?, movement: NSTextMovement?) {
        guard let cell = editing else { return }
        editing = nil
        tf?.isEditable = false
        tf?.isSelectable = false
        if !editCancelled, let tf { commit(tf.stringValue, at: cell) }
        editCancelled = false
        // Keyboard endings keep the focus in the grid; a click elsewhere keeps its own target.
        if let movement, movement != .other { window?.makeFirstResponder(table) }
        switch movement {
        case .tab?: move(dRow: 0, dColumn: 1, wrap: true)
        case .backtab?: move(dRow: 0, dColumn: -1, wrap: true)
        case .return?: move(dRow: 1, dColumn: 0)
        default: reload(rows: IndexSet(integer: cell.row))
        }
    }

    // MARK: Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Row highlight only: the model selection changes through Highlight in Model.
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let t = tableModel, let c = t.columns.firstIndex(where: { $0.id == tableColumn.identifier.rawValue }) else { return }
        let dataRows = t.rows.indices.filter { t.rows[$0].kind == .data }
        guard let first = dataRows.first, let last = dataRows.last else { return }
        anchor = nil
        setActive(row: last, column: c)
        anchor = (first, c)
        setActive(row: last, column: c, extend: true)
    }

    // MARK: Commands

    /// Selects the active rows' elements in a model view (a plan on their level, else a 3D view) and zooms to them.
    func highlightInModel() {
        let ids = selectedElementIDs
        guard let first = ids.first.flatMap({ state.model[$0] }) else { state.show("Highlight in Model: pick a row with elements."); return }
        let m = state.model
        if first.view != nil || first.sheet != nil || first.schedule != nil { state.open(first.id); return }
        let viewID = m.views.first { $0.view?.kind == .floorPlan && $0.levelID == first.levelID && state.openViews.contains($0.id) }?.id
            ?? m.views.first { $0.view?.kind == .floorPlan && $0.levelID == first.levelID }?.id
            ?? m.views.first { $0.view?.kind == .threeD }?.id
        guard let viewID else { state.show("No plan or 3D view shows these elements."); return }
        state.open(viewID)
        state.session.selection.select(ids)
        var bounds = Rect2.empty
        for id in ids { if let e = m[id] { bounds = bounds.union(ElementMeshes.bounds(e, m).xy) } }
        let s = state
        Task { @MainActor in
            for _ in 0..<40 {
                if let canvas = s.canvases[viewID] as? Canvas2DView {
                    if !bounds.isEmpty { canvas.zoom(to: bounds.expanded(by: 3)) }
                    return
                }
                if let host = s.canvases[viewID] as? Viewport3DHost { host.viewport.frameSelection(); return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        state.show("Highlighted \(ids.count) element\(ids.count == 1 ? "" : "s") in \(m[viewID]?.name ?? "the model").")
    }

    /// Persists column widths after the user drags a column edge in the header (one undo step).
    func columnsResized() {
        guard let t = tableModel else { return }
        var widths: [String: Double] = [:]
        for (i, c) in table.tableColumns.enumerated() where i < t.columns.count {
            let shown = max(60, t.columns[i].width * Self.pixelsPerPaperMeter)
            if abs(c.width - shown) > 0.5 { widths[c.identifier.rawValue] = Double(c.width) / Self.pixelsPerPaperMeter }
        }
        guard !widths.isEmpty else { return }
        state.session.editSchedule(scheduleID, "Resize Column") { def in
            for i in def.fields.indices { if let w = widths[def.fields[i].id] { def.fields[i].width = w } }
        }
    }
}

/// The schedule's table: forwards clicks and keys to the schedule view so cells edit in place.
final class ScheduleGrid: NSTableView {
    weak var owner: ScheduleTableView?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let owner, owner.handleClick(row: row(at: p), column: column(at: p), event: event) { return }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if owner?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let owner else { return super.menu(for: event) }
        let p = convert(event.locationInWindow, from: nil)
        let r = row(at: p), c = column(at: p)
        if r >= 0, c >= 0, !(owner.selectedRows.contains(r) && owner.selectedColumns.contains(c)) { owner.setActive(row: r, column: c) }
        return ScheduleCommands.contextMenu(owner.state)
    }
}

/// Header that saves column widths when a resize drag ends.
final class ScheduleHeaderView: NSTableHeaderView {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // tracks the drag until the mouse goes up
        (tableView as? ScheduleGrid)?.owner?.columnsResized()
    }
}

/// A cell: a label that draws the active-cell frame, the range tint, the drop-down chevron and the read-only flash.
final class ScheduleCellField: NSTextField {
    var isActiveCell = false
    var inRange = false
    var showsChevron = false
    var isFlashing = false
    var fill: NSColor?

    override func draw(_ dirtyRect: NSRect) {
        if let fill { fill.setFill(); bounds.fill() }
        if inRange { NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); bounds.fill() }
        if isFlashing { NSColor.systemGray.withAlphaComponent(0.35).setFill(); bounds.fill() }
        super.draw(dirtyRect)
        if showsChevron, let img = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let s: CGFloat = 8
            img.withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))?
                .draw(in: NSRect(x: bounds.maxX - s - 4, y: bounds.midY - s / 2, width: s, height: s))
        }
        if isActiveCell {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
        }
    }
}

/// The header-group row above the column headings (grouped and merged headers), scrolled with the table.
final class ScheduleHeaderGroupStrip: NSView {
    weak var owner: ScheduleTableView?
    var spans: [ScheduleHeaderSpan] = []
    var widths: [CGFloat] = []
    var offset: CGFloat = 0
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        let xs = widths.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor]
        for sp in spans where sp.columns.upperBound < xs.count {
            let r = NSRect(x: xs[sp.columns.lowerBound] - offset, y: 0, width: xs[sp.columns.upperBound] - xs[sp.columns.lowerBound], height: bounds.height)
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            let s = sp.title as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Double-click a group heading to rename it.
        guard event.clickCount == 2, let owner else { return }
        let x = convert(event.locationInWindow, from: nil).x + offset
        let xs = widths.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        guard let sp = spans.first(where: { $0.columns.upperBound < xs.count && x >= xs[$0.columns.lowerBound] && x < xs[$0.columns.upperBound] }) else { return }
        ScheduleCommands.renameHeaderGroup(owner, groupID: sp.groupID, current: sp.title)
    }
}
