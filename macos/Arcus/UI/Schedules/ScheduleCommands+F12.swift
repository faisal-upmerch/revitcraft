import AppKit
import UniformTypeIdentifiers
import ImageIO
import ArcusDomain
import ArcusApplication

// F12: the Modify Schedule/Quantities tools RevitCraft has and Arcus lacked (rc-app dialogs/schedule_tools.rs
// `enabled`, `exec`): Combine Parameters, header rows (Insert Above/Below, Resize, Delete, Merge), Insert Image,
// Clear Cell, Freeze Header, Shading, Borders, Font, Reset, Align Horizontal/Vertical and Split & Place.

extension ScheduleCommands {
    /// nil: the command isn't an F12 case here (the BL-SCHED rules apply); "": enabled; otherwise the reason.
    static func f12DisabledReason(_ id: CommandID, _ state: DocumentState, _ def: ScheduleDefinition, _ table: ScheduleTableView?) -> String? {
        let keys = table?.selectedCellKeys ?? []
        let first = keys.first
        let headerRows = keys.compactMap { k -> (Int, Int)? in if case .headerRow(let r, let c) = k { return (r, c) }; return nil }
        let titleOrRow: Bool = { if case .title? = first { return true }; if case .headerRow? = first { return true }; return false }()
        switch id {
        case .scheduleCombineParameters, .scheduleFreezeHeader: return ""
        case .scheduleInsertHeaderRow where def.formatting.headerRows.isEmpty: return ""
        case .scheduleInsertHeaderRow, .scheduleInsertRowBelow, .scheduleResizeRow, .scheduleInsertImage:
            return titleOrRow ? "" : "Click the title or a header row first."
        case .scheduleInsertRowAbove:
            return headerRows.isEmpty ? "Click a header row first." : ""
        case .scheduleClearCell:
            return keys.contains(where: { if case .body = $0 { return false }; if case .heading = $0 { return false }; return true }) ? "" : "Click the title, a header row cell or a header group first."
        case .scheduleShading, .scheduleBorders, .scheduleResetAppearance, .scheduleFont,
             .scheduleAlignLeft, .scheduleAlignCenter, .scheduleAlignRight, .scheduleAlignTop, .scheduleAlignMiddle, .scheduleAlignBottom:
            return keys.isEmpty ? "Click a cell first." : ""
        case .scheduleSplitAndPlace:
            if state.model.sheets.isEmpty { return "Create a sheet first." }
            if (table?.tableModel?.rows.count ?? 2) < 2 { return "The schedule needs at least two rows to split." }
            return ""
        case .scheduleDeleteRow:
            return headerRows.isEmpty ? nil : ""
        case .scheduleMergeHeaders:
            guard let (r, c) = headerRows.first else { return nil }
            let rows = Set(headerRows.map(\.0))
            if rows.count > 1 { return "Pick cells of one header row." }
            let merged = r < def.formatting.headerRows.count && def.formatting.headerRows[r].merges.contains { $0.first == c }
            return headerRows.count >= 2 || merged ? "" : "⇧-click a second cell of the row to merge."
        default: return nil
        }
    }

    /// Runs an F12 schedule command; false when it isn't one (or doesn't apply to the current pick).
    static func f12Perform(_ id: CommandID, _ state: DocumentState, _ sid: ElementID, _ table: ScheduleTableView?) -> Bool {
        let keys = table?.selectedCellKeys ?? []
        let headerRows = keys.compactMap { k -> (Int, Int)? in if case .headerRow(let r, let c) = k { return (r, c) }; return nil }
        switch id {
        case .scheduleCombineParameters:
            state.presented = .f11(.combineParameters(sid))
        case .scheduleInsertHeaderRow, .scheduleInsertRowAbove, .scheduleInsertRowBelow:
            var at = 0
            if let (r, _) = headerRows.first { at = id == .scheduleInsertRowAbove ? r : r + 1 }
            state.session.editSchedule(sid, "Insert Row") { ScheduleFormattingEdits.insertHeaderRow(at: at, &$0) }
            table?.recomputeNow()
            table?.titleStrip.selection = [.headerRow(at, 0)]
            table?.headerSelectionChanged()
        case .scheduleResizeRow:
            let def = state.model[sid]?.schedule
            let current: Double
            if let (r, _) = headerRows.first { current = def?.formatting.headerRows[safe: r]?.height ?? ScheduleLayout.rowHeight }
            else { current = def?.formatting.titleHeight ?? ScheduleLayout.titleHeight }
            state.requestText(prompt: "Row height on paper (mm)", initial: String(format: "%g", current * 1000)) { text in
                guard let text, let mm = Double(text.replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)), mm >= 2, mm <= 200 else {
                    if text != nil { state.show("Type a height between 2 and 200 mm.", error: true) }
                    return
                }
                state.session.editSchedule(sid, "Resize Row") { def in
                    var f = def.formatting
                    if let (r, _) = headerRows.first, r < f.headerRows.count { f.headerRows[r].height = mm / 1000 } else { f.titleHeight = mm / 1000 }
                    def.formatting = f
                }
            }
        case .scheduleDeleteRow:
            guard !headerRows.isEmpty else { return false }
            state.session.editSchedule(sid, "Delete Row") { ScheduleFormattingEdits.deleteHeaderRows(Set(headerRows.map(\.0)), &$0) }
            table?.titleStrip.selection = []
        case .scheduleMergeHeaders:
            guard let (r, _) = headerRows.first else { return false }
            state.session.editSchedule(sid, "Merge Unmerge") { ScheduleFormattingEdits.mergeOrUnmerge(row: r, columns: headerRows.map(\.1), &$0) }
            table?.titleStrip.selection = [.headerRow(r, headerRows.map(\.1).min() ?? 0)]
        case .scheduleInsertImage:
            guard let target = keys.first else { return true }
            insertImage(state, sid, target)
        case .scheduleClearCell:
            state.session.editSchedule(sid, "Clear Cell") { ScheduleFormattingEdits.clear(keys, &$0) }
        case .scheduleFreezeHeader:
            var frozen = false
            state.session.editSchedule(sid, "Freeze Header") { def in var f = def.formatting; f.freezeHeader.toggle(); frozen = f.freezeHeader; def.formatting = f }
            state.show(frozen ? "The title and headers stay in view while the rows scroll." : "The title and headers scroll with the rows.")
        case .scheduleShading: state.presented = .f11(.shading(sid, keys))
        case .scheduleBorders: state.presented = .f11(.borders(sid, keys))
        case .scheduleFont: state.presented = .f11(.font(sid, keys))
        case .scheduleResetAppearance:
            state.session.editSchedule(sid, "Reset") { ScheduleFormattingEdits.reset(keys, &$0) }
        case .scheduleAlignLeft, .scheduleAlignCenter, .scheduleAlignRight:
            let a: HorizontalAlign = id == .scheduleAlignLeft ? .left : (id == .scheduleAlignCenter ? .center : .right)
            state.session.editSchedule(sid, "Align") { ScheduleFormattingEdits.style(keys, &$0) { $0.horizontal = a } }
        case .scheduleAlignTop, .scheduleAlignMiddle, .scheduleAlignBottom:
            let a: ScheduleVerticalAlign = id == .scheduleAlignTop ? .top : (id == .scheduleAlignMiddle ? .middle : .bottom)
            state.session.editSchedule(sid, "Align") { ScheduleFormattingEdits.style(keys, &$0) { $0.vertical = a } }
        case .scheduleSplitAndPlace:
            state.presented = .f11(.splitAndPlace(sid))
        default:
            return false
        }
        ScheduleUIState.shared.revision += 1
        return true
    }

    /// Insert Image: a PNG, JPEG, TIFF or BMP file, kept in the project downscaled to at most 512 pixels.
    static func insertImage(_ state: DocumentState, _ sid: ElementID, _ target: ScheduleCellKey) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.message = "The image is copied into the project."
        let finish: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = panel.url else { return }
            guard let img = loadImage(url) else { state.show("The image couldn't be read.", error: true); return }
            state.session.editSchedule(sid, "Insert Image") { ScheduleFormattingEdits.insertImage(img, at: target, &$0) }
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    static func loadImage(_ url: URL, maxPixels: Int = 512) -> ScheduleImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cg, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return ScheduleImage(png: data as Data, pixelWidth: cg.width, pixelHeight: cg.height)
    }
}

extension Array {
    fileprivate subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
