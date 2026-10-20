import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCAD

/// Executes commands for a document. Every command in the catalog is handled here; commands that cannot run in
/// the current context return a truthful reason via `disabledReason`.
@MainActor
struct CommandRouter {
    let state: DocumentState
    var session: DocumentSession { state.session }
    var model: BIMModel { state.model }
    var selection: [ElementID] { session.selection.ids }
    var viewKind: ViewKind? { state.model[state.editingViewID]?.view?.kind } // WP6a: an activated viewport's view
    var isPlan: Bool { viewKind?.isPlan ?? false }
    var isSheet: Bool { state.model[state.editingViewID]?.sheet != nil }
    var isSchedule: Bool { state.activeView?.schedule != nil }

    func ctx() -> ToolContext? {
        if let c = w23DToolContext() { return c } // W2-3D: tools in 3D views run on a level work plane
        guard let v = state.editingViewID else { return nil } // WP6a: tools work in an activated viewport's view
        let c = state.toolContext(for: v)
        c.currentTypes = state.currentTypes
        if let canvas = state.canvas2D(for: v) { c.pixel = 1 / max(canvas.zoom, 1e-9) }
        return c
    }

    // MARK: Availability

    /// nil when the command can run; otherwise a user-facing reason.
    /// The type Type Properties edits: the selection's single type, else the type of the element being placed.
    var activeCanvas2D: Canvas2DView? { state.activeViewID.flatMap { state.canvases[$0] as? Canvas2DView } }

    var currentTypeID: ElementID? {
        let types = Set(selection.compactMap { model[$0]?.typeID })
        if types.count == 1 { return types.first }
        if let tool = state.activeTool, let cat = PropertiesView.category(for: tool.commandID) {
            return state.currentTypes[cat] ?? model.types(for: cat).first?.id
        }
        return nil
    }

    func disabledReason(_ id: CommandID) -> String? {
        if let reason = s3d2DisabledReason(id) { return reason } // S3D2: tools on any work plane in 3D views
        if let reason = portDisabledReason(id) { return reason } // RevitCraft port batches (CommandRouter+Port.swift)
        if let reason = w23DDisabledReason(id) { return reason } // W2-3D
        if let reason = keysDisabledReason(id) { return reason } // BL-KEYS
        if let reason = wp4DisabledReason(id) { return reason }
        if id == .typeProperties && currentTypeID == nil { return "Select an element with a type, or start placing one." }
        if let reason = wp6aDisabledReason(id) { return reason } // WP6a
        let overrides: Set<CommandID> = [.snapsOff, .snapEndpoint, .snapMidpoint, .snapIntersection, .snapNearest, .snapCenter, .snapPerpendicular, .snapTangent, .snapQuadrant]
        if overrides.contains(id) && state.activeTool == nil { return "Snap overrides apply while a drawing tool is active." }
        let needsSelection: Set<CommandID> = [.move, .copy, .rotate, .mirrorPickAxis, .mirrorDrawAxis, .array, .pin, .unpin, .delete, .createGroup,
                                              .temporaryHide, .temporaryIsolate, .temporaryHideCategory, .temporaryIsolateCategory, .hideInView, .paint, .removePaint,
                                              .selectAllInstancesInView, .selectAllInstancesInProject, .filterSelection, .cut, .copyClipboard]
        if needsSelection.contains(id) && selection.isEmpty && !ToolLifecycle.preselectionCommands.contains(id) { return "Select elements first." } // BL-KEYS: pre-selection
        let planOnly: Set<CommandID> = [.wall, .wallArc, .wallRectangle, .wallPickLines, .column, .structuralColumn, .beam, .floor, .floorPickWalls, .ceiling,
                                        .roofFootprint, .roofPickWalls, .stairStraight, .stairL, .stairU, .railing, .room, .roomSeparator, .area, .areaBoundary,
                                        .modelLine, .grid, .propertyLine, .toposurface, .buildingPad, .component, .section, .elevation, .callout, .roomTag]
        if planOnly.contains(id) && !isPlan { return "Open a plan view to use this tool." }
        if (id == .door || id == .window) && !isPlan && !(viewKind?.isVerticalCut ?? false) { return "Open a plan, elevation or section to place doors and windows." } // BL-CANVAS: ARCUS-036
        if id == .level && !(viewKind?.isVerticalCut ?? false) { return "Open an elevation or section to add levels." }
        let annotation: Set<CommandID> = [.alignedDimension, .linearDimension, .angularDimension, .radialDimension, .diameterDimension, .arcLengthDimension,
                                          .spotElevation, .spotCoordinate, .spotSlope, .detailLine, .filledRegion, .maskingRegion, .detailComponent, .insulation,
                                          .textNote, .tagByCategory, .tagAll, .symbol, .revisionCloud, .northArrow]
        if annotation.contains(id) && (isSchedule || state.activeView?.view?.kind == .threeD) { return "Annotations are added in 2D views and sheets." }
        if [.placeView].contains(id) && !isSheet { return "Open a sheet to place views." }
        if [.sectionBox, .saveOrientation, .visualStyleWireframe, .visualStyleHidden, .visualStyleShaded, .visualStyleConsistent, .visualStyleTransparent].contains(id), viewKind != .threeD {
            return id == .sectionBox || id == .saveOrientation ? "Available in 3D views." : nil
        }
        if [.viewRange].contains(id) && !isPlan { return "View range applies to plan views." }
        if [.exportScheduleCSV, .importScheduleCSV].contains(id) && !isSchedule { return "Open a schedule first." }
        if id == .undo && !session.canUndo { return "Nothing to undo." }
        if id == .redo && !session.canRedo { return "Nothing to redo." }
        if [.paste, .pasteAlignedSameLevel, .pasteAlignedSelectedLevels, .pasteAlignedCurrentView].contains(id) && state.clipboard == nil { return "The clipboard is empty." }
        if id == .editGroup && !(selection.count == 1 && model[selection[0]]?.group != nil) { return "Select one group." }
        if id == .finishEditGroup && session.editingGroupID == nil { return "No group is being edited." }
        if id == .ungroup && !selection.contains(where: { model[$0]?.group != nil }) { return "Select a group." }
        if [.flipFacing, .flipHand].contains(id) && !selection.contains(where: { model[$0]?.insert != nil }) { return "Select doors or windows." }
        if [.flipWall, .attachTop, .detachTop, .joinGeometry, .unjoinGeometry].contains(id) && !selection.contains(where: { model[$0]?.wall != nil }) { return "Select walls." }
        if id == .editProfile && !(selection.count == 1 && model[selection[0]]?.wall != nil && (viewKind?.isVerticalCut ?? false)) { return "Select one wall in an elevation or section." }
        if id == .resetProfile && !selection.contains(where: { model[$0]?.wall?.profile != nil }) { return "Select a wall with an edited profile." }
        if id == .editBoundary && !(selection.count == 1 && editableSketch(model[selection[0]])) { return "Select one floor, ceiling, roof, region, railing or revision cloud." }
        if id == .pickHost && !(selection.count == 1 && model[selection[0]]?.insert != nil) { return "Select one door or window." }
        if [.finishSketch, .cancelSketch].contains(id) && !(state.activeTool?.isSketchMode ?? false) { return "Not in sketch mode." }
        if [.reloadLink, .unloadLink, .convertLinkToDrafting].contains(id) && !selection.contains(where: { model[$0]?.link != nil }) { return "Select a CAD link or import." }
        if id == .familyEditor && !(selection.count == 1 && Parameters.familyDefinition(for: model[selection[0]]!, model) != nil) { return "Select a family instance or type." }
        if let reason = modifyToolsDisabledReason(id) { return reason }
        if let reason = roomAreaDisabledReason(id) { return reason }
        if let reason = wp3DisabledReason(id) { return reason } // WP3
        if let reason = cameraDisabledReason(id) { return reason } // W2-CAM
        if let reason = siteDisabledReason(id) { return reason } // W2-DWG
        if let reason = annotDisabledReason(id) { return reason } // W2-ANNOT
        if let reason = blSchedDisabledReason(id) { return reason } // BL-SCHED
        if let reason = blvgDisabledReason(id) { return reason } // BL-VG
        return nil
    }

    func editableSketch(_ e: Element?) -> Bool {
        guard let e else { return false }
        switch e.data {
        case .slab, .roof, .filledRegion, .railing, .revisionCloud: return e.railing.map { !$0.followsHost } ?? true
        case .grid(let g): return g.isMultiSegment // F2: a multi-segment grid's sketch
        case .beamSystem, .areaReinforcement, .fabricArea: return !Reinforcement.isWallHosted(model, e.hostID) // F34: plan sketches
        case .mass: return true // F5: the footprint
        case .furnitureShelf: return true // FM4: a shelf, top or bottom's boundary
        default: return false
        }
    }

    // MARK: Run

    func run(_ id: CommandID) {
        if keysIntercept(id) { return } // BL-KEYS: Modify pre-selection (CommandRouter+Keys.swift)
        if let reason = disabledReason(id), !alwaysAllowed.contains(id) {
            state.show("\(CommandCatalog.info(id).title): \(reason)")
            return
        }
        NotificationCenter.default.post(name: .arcusCommandRan, object: nil) // FMG4: ribbon popovers close
        state.recentCommands.removeAll { $0 == id }
        state.recentCommands.insert(id, at: 0)
        if state.recentCommands.count > 12 { state.recentCommands.removeLast() }
        if let tool = makeTool(id) {
            ModifyToolSettings.shared.restore(into: tool) // BL-KEYS: last-used Modify tool settings
            state.setTool(tool)
            return
        }
        perform(id)
    }

    private var alwaysAllowed: Set<CommandID> { [.modify, .commandSearch, .preferences, .about, .onboarding, .keyboardShortcuts, .designWithClaude] }

    func makeTool(_ id: CommandID) -> (any InteractiveTool)? {
        if let t = s3d2MakeTool(id) { return t } // S3D2: on a 3D view's reference-plane or face work plane
        guard let c = ctx() else { return nil }
        if let t = portMakeTool(id, c) { return t } // RevitCraft port batches
        if let t = annotMakeTool(id, c) { return t } // W2-ANNOT
        if let t = blvgMakeTool(id, c) { return t } // BL-VG
        let sel = selection
        switch id {
        case .wall: return WallTool(ctx: c, mode: .line)
        case .wallArc: return WallTool(ctx: c, mode: .arc)
        case .wallRectangle: return WallTool(ctx: c, mode: .rectangle)
        case .wallPickLines: return WallTool(ctx: c, mode: .pickLines)
        case .door: return InsertTool(ctx: c, category: .doors)
        case .window: return InsertTool(ctx: c, category: .windows)
        case .component: return ComponentTool(ctx: c, category: componentCategory(), commandID: .component)
        case .column: return ComponentTool(ctx: c, category: .columns, commandID: .column)
        case .structuralColumn: return ComponentTool(ctx: c, category: .structuralColumns, commandID: .structuralColumn)
        case .beam: return LineTool(ctx: c, kind: .beam, commandID: .beam)
        case .floor: let t = SketchTool(ctx: c, target: .floor, commandID: .floor); t.drawMode = .line; return t
        case .floorPickWalls: return SketchTool(ctx: c, target: .floor, commandID: .floorPickWalls)
        case .ceiling: return SketchTool(ctx: c, target: .ceiling, commandID: .ceiling)
        case .roofFootprint: let t = SketchTool(ctx: c, target: .roof, commandID: .roofFootprint); t.drawMode = .line; return t
        case .roofPickWalls: return SketchTool(ctx: c, target: .roof, commandID: .roofPickWalls)
        case .buildingPad: return SketchTool(ctx: c, target: .buildingPad, commandID: .buildingPad)
        case .stairStraight: return StairTool(ctx: c, shape: .straight)
        case .stairL: return StairTool(ctx: c, shape: .lShaped)
        case .stairU: return StairTool(ctx: c, shape: .uShaped)
        case .railing: return SketchTool(ctx: c, target: .railing, commandID: .railing)
        case .room: return RoomTool(ctx: c)
        case .area: return RoomTool(ctx: c, isArea: true)
        case .roomSeparator: return LineTool(ctx: c, kind: .roomSeparation, commandID: .roomSeparator)
        case .areaBoundary: return LineTool(ctx: c, kind: .areaBoundary, commandID: .areaBoundary)
        case .modelLine: return LineTool(ctx: c, kind: .model, commandID: .modelLine)
        case .grid: return LineTool(ctx: c, kind: .grid, commandID: .grid)
        case .level: return LevelTool(ctx: c)
        case .referencePlane: return LineTool(ctx: c, kind: .referencePlane, commandID: .referencePlane)
        case .propertyLine: return SketchTool(ctx: c, target: .propertyLine, commandID: .propertyLine)
        case .toposurface: return ToposurfaceTool(ctx: c)
        case .alignedDimension: return DimensionTool(ctx: c, kind: .aligned)
        case .linearDimension: return DimensionTool(ctx: c, kind: .linear)
        case .angularDimension: return DimensionTool(ctx: c, kind: .angular)
        case .radialDimension: return DimensionTool(ctx: c, kind: .radial)
        case .diameterDimension: return DimensionTool(ctx: c, kind: .diameter)
        case .arcLengthDimension: return DimensionTool(ctx: c, kind: .arcLength)
        case .spotElevation: return SpotTool(ctx: c, kind: .elevation)
        case .spotCoordinate: return SpotTool(ctx: c, kind: .coordinate)
        case .spotSlope: return SpotTool(ctx: c, kind: .slope)
        case .detailLine: return LineTool(ctx: c, kind: .detail, commandID: .detailLine)
        case .insulation: return LineTool(ctx: c, kind: .insulation, commandID: .insulation)
        case .filledRegion: let t = SketchTool(ctx: c, target: .filledRegion, commandID: .filledRegion); t.drawMode = .line; return t
        case .maskingRegion: let t = SketchTool(ctx: c, target: .maskingRegion, commandID: .maskingRegion); t.drawMode = .rectangle; return t
        case .revisionCloud:
            guard !model.revisions.filter({ $0.revisionData?.issued == false }).isEmpty else { state.show("Every revision is issued. Add a revision in Manage ▸ Revisions first.", error: true); return nil }
            let t = SketchTool(ctx: c, target: .revisionCloud, commandID: .revisionCloud); t.drawMode = .rectangle; return t
        case .detailComponent: return ComponentTool(ctx: c, category: .detailComponents, commandID: .detailComponent)
        case .symbol, .northArrow:
            if id == .northArrow, let na = model.types(for: .genericAnnotations).first(where: { $0.typeData?.familyName == "North Arrow" }) { c.currentTypes[.genericAnnotations] = na.id }
            return ComponentTool(ctx: c, category: .genericAnnotations, commandID: id)
        case .textNote: return TextTool(ctx: c)
        case .tagByCategory: return TagTool(ctx: c)
        case .roomTag: return TagTool(ctx: c, commandID: .roomTag, categories: [.rooms])
        case .section: return SectionTool(ctx: c)
        case .elevation: return ElevationTool(ctx: c)
        case .callout: let t = SketchTool(ctx: c, target: .callout, commandID: .callout); t.drawMode = .rectangle; return t
        case .move: return MoveCopyTool(ctx: c, ids: sel, copy: false)
        case .copy: return MoveCopyTool(ctx: c, ids: sel, copy: true)
        case .rotate: return RotateTool(ctx: c, ids: sel)
        case .mirrorPickAxis: return MirrorTool(ctx: c, ids: sel, pickAxis: true)
        case .mirrorDrawAxis: return MirrorTool(ctx: c, ids: sel, pickAxis: false)
        case .array: return ArrayTool(ctx: c, ids: sel)
        case .align: return AlignTool(ctx: c)
        case .offset: return OffsetTool(ctx: c)
        case .trimExtendCorner: return TrimExtendTool(ctx: c, mode: .corner)
        case .trimExtendSingle: return TrimExtendTool(ctx: c, mode: .single)
        case .trimExtendMultiple: return TrimExtendTool(ctx: c, mode: .multiple)
        case .split: return SplitTool(ctx: c)
        case .matchType: return MatchTypeTool(ctx: c)
        case .editBoundary:
            guard let id = sel.first, let e = model[id] else { return nil }
            let target: SketchTool.Target
            switch e.data {
            case .slab: target = e.category == .ceilings ? .ceiling : e.category == .buildingPads ? .buildingPad : .floor
            case .roof(let r): target = r.extrusion != nil ? .roofExtrusion : .roof
            case .filledRegion(let f): target = f.isMasking ? .maskingRegion : .filledRegion
            case .railing: target = .railing
            case .revisionCloud: target = .revisionCloud
            default: return nil
            }
            let t = SketchTool(ctx: c, target: target, commandID: .editBoundary, editing: id)
            t.drawMode = .line
            return t
        case .editProfile:
            guard let id = sel.first else { return nil }
            return WallProfileTool(ctx: c, wallID: id)
        case .attachTop:
            return AttachTool(ctx: c, walls: sel.filter { model[$0]?.wall != nil })
        case .pickHost:
            guard let id = sel.first else { return nil }
            return PickHostTool(ctx: c, insertID: id)
        case .colorFillLegend: return colorFillLegendTool(c)
        case .parkingLayout, .subregion, .splitSurface, .labelContours, .editSurface: return siteTool(id, c) // W2-DWG
        default:
            return nil
        }
    }

    func componentCategory() -> Category {
        if let t = state.currentTypes[.furniture] ?? state.currentTypes[.casework], let c = model[t]?.typeData?.instanceCategory { return c }
        return .furniture
    }

    func perform(_ id: CommandID) {
        if portPerform(id) { return } // RevitCraft port batches
        if performAnnot(id) { return } // W2-ANNOT
        if keysPerform(id) { return } // BL-KEYS
        if performBLSched(id) { return } // BL-SCHED
        if performBLVG(id) { return } // BL-VG
        let sel = selection
        switch id {
        case .modify:
            state.cancelTool()
        case .selectAll:
            if let g = state.graphics.graphics(state.activeViewID ?? ElementID(0)) {
                var ids = Set<ElementID>()
                for i in g.items where i.selectable { if let e = i.elementID { ids.insert(e) } }
                session.selection.select(ids.sorted())
            }
        case .selectAllInstancesInView, .selectAllInstancesInProject:
            let types = Set(sel.compactMap { model[$0]?.typeID })
            var ids = types.flatMap { model.instances(ofType: $0).map(\.id) }
            if id == .selectAllInstancesInView, let g = state.graphics.graphics(state.activeViewID ?? ElementID(0)) {
                let visible = Set(g.items.compactMap(\.elementID))
                ids = ids.filter(visible.contains)
            }
            session.selection.select(ids)
            state.show("\(ids.count) elements selected.")
        case .selectByCategory: state.presented = .selectByCategory
        case .filterSelection: state.presented = .filterSelection
        case .pin, .unpin:
            let pin = id == .pin
            session.perform(pin ? "Pin" : "Unpin") { tx in for e in sel { tx.update(e) { $0.pinned = pin } } }
        case .delete: session.delete(sel)
        case .paint: state.presented = .materials
        case .removePaint:
            session.perform("Remove Paint") { tx in for e in sel { tx.update(e) { $0.params[.paintMaterial] = nil } } }
        case .joinGeometry, .unjoinGeometry:
            let allow = id == .joinGeometry
            session.perform(allow ? "Allow Join" : "Disallow Join") { tx in
                for e in sel { tx.update(e) { $0.wall?.allowJoinAtStart = allow; $0.wall?.allowJoinAtEnd = allow } }
            }
        case .createGroup: createGroup(sel)
        case .ungroup:
            session.perform("Ungroup") { tx in for e in sel where tx.model[e]?.group != nil {
                for m in tx.model[e]?.group?.members ?? [] { tx.update(m) { $0.groupID = nil } }
                tx.delete(e)
            } }
        case .editGroup:
            session.editingGroupID = sel.first
            if let g = sel.first.flatMap({ model[$0]?.group }) { session.selection.select(g.members) }
            state.show("Editing group. Change its members, then choose Finish; other instances of the group type update.")
        case .finishEditGroup: finishGroupEdit()
        case .flipFacing, .flipHand:
            session.perform(id == .flipFacing ? "Flip Facing" : "Flip Hand") { tx in
                for e in sel { tx.update(e) { if id == .flipFacing { $0.insert?.facingFlipped.toggle() } else { $0.insert?.handFlipped.toggle() } } }
            }
        case .flipWall:
            session.perform("Flip Wall") { tx in for e in sel { tx.update(e) { $0.wall?.flipped.toggle() } } }
        case .detachTop:
            session.perform("Detach Top/Base") { tx in for e in sel { tx.update(e) { $0.wall?.attachedTopIDs = []; $0.wall?.attachedBaseIDs = [] } } }
        case .resetProfile:
            session.perform("Reset Profile") { tx in for e in sel { tx.update(e) { $0.wall?.profile = nil } } }
        case .finishSketch:
            if let t = state.activeTool, t.finish() { state.toolChangedState() }
        case .cancelSketch:
            state.activeTool?.cancelSketch(); state.cancelTool()
        case .tagAll: tagAll()
        case .floorPlan, .ceilingPlan, .structuralPlan: state.presented = .newView(id == .floorPlan ? .floorPlan : id == .ceilingPlan ? .ceilingPlan : .structuralPlan)
        case .draftingView, .legend: createSimpleView(id == .draftingView ? .drafting : .legend)
        case .threeDView: openDefault3D()
        case .schedule: state.presented = .newSchedule(.category)
        case .materialTakeoff: state.presented = .newSchedule(.materialTakeoff)
        case .sheetList: createSpecialSchedule(.sheetList)
        case .revisionSchedule: createSpecialSchedule(.revisionSchedule)
        case .newSheet: state.presented = .newSheet
        case .placeView: if let s = state.activeViewID { state.presented = .placeView(s) }
        case .duplicateView, .duplicateViewWithDetailing, .duplicateDependent: duplicateView(id)
        case .renameView: if let v = navigatorOrActiveView() { state.presented = .rename(v) }
        case .viewTemplateApply, .visibilityGraphics: if let v = state.editingViewID { state.presented = .visibilityGraphics(v) }
        case .viewRange: if let v = state.editingViewID { state.presented = .viewRange(v) }
        case .cropView: toggleView { $0.cropActive.toggle(); if $0.cropActive && $0.cropRegion == nil { $0.cropRegion = currentExtents() } }
        case .toggleCropVisible: toggleView { $0.cropVisible.toggle(); if $0.cropRegion == nil { $0.cropRegion = currentExtents() } }
        case .sectionBox: toggleView { v in v.sectionBoxActive.toggle(); if v.sectionBox == nil { v.sectionBox = modelBounds3D() } }
        case .thinLines: state.thinLines.toggle()
        case .temporaryHide, .temporaryIsolate, .temporaryHideCategory, .temporaryIsolateCategory, .resetTemporary, .revealHidden: temporary(id)
        case .hideInView, .unhideInView:
            guard let v = state.editingViewID else { return }
            let hide = id == .hideInView
            session.perform(hide ? "Hide in View" : "Unhide in View") { tx in
                tx.update(v) { e in for s in sel { if hide { e.view?.visibility.hiddenElements.insert(s) } else { e.view?.visibility.hiddenElements.remove(s) } } }
            }
            if hide { session.selection.clear() }
        case .zoomExtents: activeCanvas2D?.recordNavigation(); activeCanvas2D?.zoomToFit(); (state.canvases[state.activeViewID ?? ElementID(0)] as? Viewport3DHost)?.zoomExtents()
        case .zoomIn, .zoomOut:
            if let c = activeCanvas2D { c.recordNavigation(); c.zoom(by: id == .zoomIn ? 1.4 : 1 / 1.4, at: NSPoint(x: c.bounds.midX, y: c.bounds.midY)) }
        case .zoomOutTwice:
            if let c = activeCanvas2D { c.recordNavigation(); c.zoom(by: 0.5, at: NSPoint(x: c.bounds.midX, y: c.bounds.midY)) }
        case .zoomSheetSize: activeCanvas2D?.zoomSheetSize()
        case .previousPanZoom: if activeCanvas2D?.stepNavigation(back: true) != true { state.show("No previous pan or zoom for this view.") }
        case .nextPanZoom: if activeCanvas2D?.stepNavigation(back: false) != true { state.show("No next pan or zoom for this view.") }
        case .zoomRegion:
            if let c = state.canvases[state.activeViewID ?? ElementID(0)] as? Canvas2DView { c.zoomRegionArmed = true; state.show("Drag a rectangle to zoom into.") }
        case .previousView: state.previousView()
        case .closeHiddenViews: state.closeInactiveViews()
        case .saveOrientation: (state.canvases[state.activeViewID ?? ElementID(0)] as? Viewport3DHost)?.saveOrientation()
        case .detailCoarse, .detailMedium, .detailFine:
            let d: DetailLevel = id == .detailCoarse ? .coarse : id == .detailMedium ? .medium : .fine
            setViewParam(ParameterID("view.detailLevel"), .text(d.rawValue), "Detail Level")
        case .visualStyleWireframe, .visualStyleHidden, .visualStyleShaded, .visualStyleConsistent, .visualStyleTransparent:
            let map: [CommandID: VisualStyle] = [.visualStyleWireframe: .wireframe, .visualStyleHidden: .hiddenLine, .visualStyleShaded: .shaded, .visualStyleConsistent: .consistentColors, .visualStyleTransparent: .transparent]
            setViewParam(ParameterID("view.visualStyle"), .text(map[id]!.rawValue), "Visual Style")
        case .projectInfo: state.presented = .projectInfo
        case .projectUnits: state.presented = .projectUnits
        case .projectParameters, .sharedParameters: state.presented = .projectParameters
        case .materials: state.presented = .materials
        case .typeProperties:
            if let t = currentTypeID { state.presented = .typeProperties(t) } else { state.show("Select an element with a type, or start placing one.") }
        case .lineStyles: state.presented = .lineStyles
        case .snapSettings: state.presented = .snaps
        case .snapsOff, .snapEndpoint, .snapMidpoint, .snapIntersection, .snapNearest, .snapCenter, .snapPerpendicular, .snapTangent, .snapQuadrant:
            let o: ToolContext.SnapOverride = switch id {
            case .snapEndpoint: .only(.endpoint)
            case .snapMidpoint: .only(.midpoint)
            case .snapIntersection: .only(.intersection)
            case .snapNearest: .only(.nearest)
            case .snapCenter: .only(.center)
            case .snapPerpendicular: .only(.perpendicular)
            case .snapTangent: .only(.tangent)
            case .snapQuadrant: .only(.quadrant)
            default: .off
            }
            ctx()?.snapOverride = o
            if case .only(let k) = o { state.show("Next pick snaps to \(k.rawValue.lowercased()) only.") } else { state.show("Snaps are off for the next pick.") }
        case .phases: state.presented = .phases
        case .designOptions: state.presented = .designOptions
        case .revisions: state.presented = .revisions
        case .locationSettings: state.presented = .location
        case .familyEditor:
            if let e = sel.first.flatMap({ model[$0] }), let famID = (e.typeData ?? model.typeData(of: e))?.familyID { FamilyEditorWindowController.open(familyID: famID, state: state) }
        case .newFamily: state.presented = .newFamily
        case .loadFamily: FamilyLoader(state: state).loadFromDisk()
        case .reloadFamily: FamilyLoader(state: state).reloadSelected()
        case .typeCatalog: FamilyLoader(state: state).loadTypeCatalog()
        case .purgeUnused: state.presented = .purge
        case .modelHealth: state.presented = .modelHealth
        case .diagnostics: DiagnosticsWindowController.show(state: state)
        case .linkDWG, .importDWG:
            let provider = DWGProviders.current
            guard provider.isAvailable else { state.presented = .dwgUnavailable; return }
            chooseFile([UTType(filenameExtension: "dwg") ?? .data]) { url in state.presented = .importCAD(url, isLink: id == .linkDWG, isDWG: true) }
        case .linkDXF, .importDXF:
            chooseFile([UTType(filenameExtension: "dxf") ?? .data]) { url in state.presented = .importCAD(url, isLink: id == .linkDXF, isDWG: false) }
        case .manageLinks: state.presented = .manageLinks
        case .reloadLink: LinkActions(state: state).reload(sel.filter { model[$0]?.link != nil })
        case .unloadLink:
            session.perform("Unload Link") { tx in for e in sel where tx.model[e]?.link != nil { tx.update(e) { $0.link?.isLoaded = false } } }
        case .convertLinkToDrafting: LinkActions(state: state).convert(sel.filter { model[$0]?.link != nil })
        case .importIFC: chooseFile([UTType(filenameExtension: "ifc") ?? .data]) { url in state.presented = .importIFC(url) }
        case .importRevit:
            let types = ["arcusx", "rvt", "rfa", "rte", "rft"].compactMap { UTType(filenameExtension: $0) }
            chooseFile(types.isEmpty ? [.data] : types) { url in state.presented = .importRevit(url) }
        case .linkPDF: chooseFile([.pdf]) { url in state.presented = .linkPDF(url) }
        case .linkImage: chooseFile([.png, .jpeg, .tiff]) { url in state.presented = .linkImage(url) }
        case .exportIFC: state.presented = .exportIFC
        case .exportPDF: state.presented = .exportPDF
        case .exportDXF: ExportActions(state: state).exportDXF()
        case .exportScheduleCSV: ExportActions(state: state).exportScheduleCSV()
        case .importScheduleCSV:
            if let s = state.activeViewID { chooseFile([.commaSeparatedText, .tabSeparatedText, .plainText]) { url in state.presented = .csvImport(s, url) } }
        case .print: ExportActions(state: state).printSheets()
        case .home: AppDelegate.shared?.showHub(tab: .recent)
        case .newProject: AppDelegate.shared?.showHub(tab: .new)
        case .openProject: NSDocumentController.shared.openDocument(nil)
        case .save: state.document?.save(nil)
        case .saveAs: state.document?.saveAs(nil)
        case .duplicateDocument: state.document?.duplicate(nil)
        case .revert: state.document?.revertToSaved(nil)
        case .closeDocument: state.window?.performClose(nil)
        case .exportRecoveryCopy: state.document?.saveRecoveryCopy()
        case .commandSearch: state.commandSearchVisible.toggle()
        case .preferences: AppDelegate.shared?.showSettings()
        case .workspaceBIMFamiliar: state.workspace = .bimFamiliar
        case .workspaceMacSpacious: state.workspace = .macSpacious
        case .resetWorkspace: state.workspace = .bimFamiliar; state.showNavigator = true; state.showProperties = true
        case .toggleNavigator: state.showNavigator.toggle(); state.onWorkspaceChange?()
        case .toggleProperties: state.showProperties.toggle(); state.onWorkspaceChange?()
        case .keyboardShortcuts: state.presented = .keyboardShortcuts
        case .onboarding: AppDelegate.shared?.showOnboarding()
        case .about: AppDelegate.shared?.showAbout()
        case .undo: session.undoManager.undo()
        case .redo: session.undoManager.redo()
        case .cut: Clipboard(state: state).copy(); session.delete(sel)
        case .copyClipboard: Clipboard(state: state).copy()
        case .paste: Clipboard(state: state).paste(mode: .cursor)
        case .pasteAlignedSameLevel: Clipboard(state: state).paste(mode: .samePlace)
        case .pasteAlignedSelectedLevels: state.presented = .pasteToLevels
        case .pasteAlignedCurrentView: Clipboard(state: state).paste(mode: .currentView)
        case .selectPrevious:
            if !session.selection.selectPrevious(in: model) { state.show("There is no previous selection to restore.") }
        case .editWitnessLines:
            guard sel.count == 1, let d = model[sel[0]]?.dimension, d.kind == .linear || d.kind == .aligned, let c = ctx() else {
                state.show("Edit Witness Lines: Select one linear or aligned dimension."); return
            }
            state.setTool(WitnessLineTool(ctx: c, dimensionID: sel[0]))
        case .curtainWall, .curtainGrid, .mullion, .curtainPanel, .wallOpening, .shaftOpening: runWP3Tool(id)
        case .ramp, .roofExtrusion, .editStair, .modifySubElements, .addShapePoint, .resetShape, .attachWallsToHost, .joinSolids, .unjoinSolids:
            performWP4(id)
        case .createSimilar: createSimilar()
        case .measureBetween, .measureAlong, .demolish, .scale: runModifyTool(id)
        case .arrayNumber: editArrayNumber()
        case .selectionBox, .overrideGraphicsElement, .activateViewport, .deactivateViewport, .cameraView, .scopeBox, .gridPickLines,
             .showProjectBasePoint, .showSurveyPoint:
            ViewCommands(state: state).perform(id)
        case .placeRoomsAutomatically, .placeAreasAutomatically: placeAutomatically(areas: id == .placeAreasAutomatically)
        case .colorSchemes: if let v = state.activeViewID { state.presented = .colorSchemes(v, placeLegend: false) }
        case .areaPlan: state.presented = .newAreaPlan
        case .saveAsTemplate: UserTemplates.saveAsTemplate(state: state)
        case .view3DFront, .view3DBack, .view3DLeft, .view3DRight, .view3DTop, .view3DBottom, .view3DToggleProjection, .view3DFrameSelected, .view3DFly,
             .viewThroughCamera, .alignCameraToView, .lockCameraToView, .createCameraFromView: performCameraCommand(id) // W2-CAM
        case .loadStandardTypes: loadStandardTypes() // W2-TYPES
        case _ where Self.siteCommands.contains(id): performSite(id) // W2-DWG
        case .componentLibrary, .siteLibrary: state.showComponentLibrary(categories: id == .siteLibrary ? ComponentLibrary.siteCategories : []) // W2-LIB
        default:
            state.show("\(CommandCatalog.info(id).title) is not available here.")
        }
    }

    // MARK: Helpers

    func chooseFile(_ types: [UTType], then: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard let w = state.window else { if panel.runModal() == .OK, let u = panel.url { then(u) }; return }
        panel.beginSheetModal(for: w) { r in if r == .OK, let u = panel.url { then(u) } }
    }

    func navigatorOrActiveView() -> ElementID? { state.activeViewID }

    func toggleView(_ mutate: @escaping (inout ViewData) -> Void) {
        guard let v = state.activeViewID, model[v]?.view != nil else { return }
        session.perform("Change View") { tx in tx.update(v) { if var d = $0.view { mutate(&d); $0.view = d } } }
    }

    func setViewParam(_ p: ParameterID, _ value: ParamValue, _ name: String) {
        guard let v = state.activeViewID else { return }
        session.setParameter(p, value: value, on: [v], name: name)
    }

    func currentExtents() -> Rect2? {
        guard let v = state.activeViewID, let g = state.graphics.graphics(v) else { return nil }
        return g.extents.isEmpty ? nil : g.extents.expanded(by: Double(g.scale) * 0.01)
    }

    func modelBounds3D() -> Box3 {
        model.allElements.filter { $0.category.isModel }.reduce(Box3.empty) { $0.union(ElementMeshes.bounds($1, model)) }
    }

    func temporary(_ id: CommandID) {
        guard let v = state.editingViewID else { return }
        var t = session.temporaryVisibility[v] ?? TemporaryVisibility()
        let sel = Set(selection)
        let cats = Set(selection.compactMap { model[$0]?.category })
        switch id {
        case .temporaryHide: t.hiddenElements.formUnion(sel)
        case .temporaryIsolate: t.isolatedElements = sel
        case .temporaryHideCategory: t.hiddenCategories.formUnion(cats)
        case .temporaryIsolateCategory: t.isolatedCategories = cats
        case .resetTemporary: t = TemporaryVisibility()
        case .revealHidden: t.revealHidden.toggle()
        default: break
        }
        session.temporaryVisibility[v] = t
        if id != .revealHidden && id != .resetTemporary { session.selection.clear() }
        state.graphics.invalidateView(v)
        state.toolChangedState()
    }

    func createGroup(_ ids: [ElementID]) {
        let members = ids.filter { model[$0].map { ElementTransform.isTransformable($0) && $0.groupID == nil } ?? false }
        guard !members.isEmpty else { state.show("These elements can't be grouped (or are already grouped).", error: true); return }
        let origin = ElementOperations.center(of: members, model)
        let n = model.elements(.modelGroups).count + 1
        let isDetail = members.allSatisfy { model[$0]?.ownerViewID != nil }
        session.perform("Create Group") { tx in
            let gid = tx.create(isDetail ? .detailGroups : .modelGroups, name: "Group \(n)", data: .group(GroupData(members: members, origin: origin, groupTypeName: "Group \(n)")),
                                ownerViewID: isDetail ? model[members[0]]?.ownerViewID : nil)
            for m in members { tx.update(m) { $0.groupID = gid } }
        }
        if let g = model.elements(isDetail ? .detailGroups : .modelGroups).last { session.selection.select([g.id]) }
    }

    /// Finishing a group edit propagates the edited member layout to every other instance of the same group type.
    func finishGroupEdit() {
        guard let gid = session.editingGroupID, let g = model[gid], let gd = g.group else { session.editingGroupID = nil; return }
        let others = (model.elements(.modelGroups) + model.elements(.detailGroups)).filter { $0.id != gid && $0.group?.groupTypeName == gd.groupTypeName }
        let view = state.activeViewID
        session.perform("Finish Group") { tx in
            for o in others {
                guard let od = o.group else { continue }
                for m in od.members { tx.delete(m) }
                let delta = od.origin - gd.origin
                let map = ElementOperations.copy(gd.members, by: .translation(delta), in: tx, viewID: view)
                let newMembers = gd.members.compactMap { map[$0] }
                if tx.model[o.id] == nil {
                    tx.create(o.category, name: o.name, data: .group(GroupData(members: newMembers, origin: od.origin, groupTypeName: od.groupTypeName)), ownerViewID: o.ownerViewID)
                } else {
                    tx.update(o.id) { $0.group?.members = newMembers }
                }
                for m in newMembers { tx.update(m) { $0.groupID = o.id } }
            }
        }
        session.editingGroupID = nil
        state.show(others.isEmpty ? "Group edit finished." : "Group edit finished; \(others.count) other instance(s) updated.")
    }

    /// Tag All: the dialog chooses categories, tag types, selection scope, leader and orientation.
    func tagAll() {
        guard let v = state.activeViewID, state.graphics.graphics(v) != nil else { return }
        state.presented = .tagAll(v)
    }

    func createSimpleView(_ kind: ViewKind) {
        let n = model.views.filter { $0.view?.kind == kind }.count + 1
        var created: ElementID?
        session.perform("Create \(kind.rawValue)") { tx in
            var v = ViewData(kind: kind, scale: kind == .legend ? 50 : 20)
            v.phaseID = model.latestPhase?.id
            created = tx.create(.views, name: "\(kind.rawValue) \(n)", data: .view(v))
        }
        if let created { state.open(created) }
    }

    func openDefault3D() {
        if let v = model.views.first(where: { $0.view?.kind == .threeD && $0.name == "{3D}" }) ?? model.views.first(where: { $0.view?.kind == .threeD }) {
            state.open(v.id); return
        }
        var created: ElementID?
        session.perform("Create 3D View") { tx in
            var v = ViewData(kind: .threeD); v.camera = .defaultIsometric; v.phaseID = model.latestPhase?.id
            created = tx.create(.views, name: "{3D}", data: .view(v))
        }
        if let created { state.open(created) }
    }

    func createSpecialSchedule(_ kind: ScheduleKind) {
        let def = kind == .sheetList ? ScheduleTemplates.sheetList() : ScheduleDefinition(kind: .revisionSchedule, categories: [.revisions], fields: [
            ScheduleTemplates.field("revision.number", "Rev", width: 0.012), ScheduleTemplates.field("revision.date", "Date", width: 0.025),
            ScheduleTemplates.field("revision.description", "Description", width: 0.07),
        ])
        let base = kind == .sheetList ? "Sheet List" : "Revision Schedule"
        var name = base; var k = 2
        while model.schedules.contains(where: { $0.name == name }) { name = "\(base) \(k)"; k += 1 }
        var created: ElementID?
        session.perform("Create \(base)") { tx in created = tx.create(.schedules, name: name, data: .schedule(def)) }
        if let created { state.open(created) }
    }

    func duplicateView(_ id: CommandID) {
        guard let v = state.activeViewID, let e = model[v] else { return }
        var created: ElementID?
        session.perform("Duplicate View") { tx in
            if let sched = e.schedule {
                created = tx.create(.schedules, name: BrowserNaming.duplicateViewName(e, in: tx.model), data: .schedule(sched)) // BL-BROWSER
                return
            }
            guard var vd = e.view else { return }
            var name = BrowserNaming.duplicateViewName(e, in: tx.model) // BL-BROWSER: "Copy of X", "Copy (2) of X"
            if id == .duplicateDependent {
                vd.parentViewID = v
                vd.cropActive = true
                if vd.cropRegion == nil { vd.cropRegion = currentExtents() }
                name = BrowserNaming.dependentName(of: e.name) { BrowserNaming.viewNameTaken($0, kind: vd.kind, in: tx.model) } // BL-BROWSER
            }
            let nv = tx.create(.views, name: name, data: .view(vd), levelID: e.levelID)
            created = nv
            if id == .duplicateViewWithDetailing {
                let owned = tx.model.owned(byView: v).map(\.id)
                ElementOperations.copy(owned, by: .identity, in: tx, viewID: v, targetView: nv)
            }
        }
        if let created { state.open(created) }
    }

    func doubleClick(_ e: Element) {
        if doubleClickPreference(e) { return } // BL-CANVAS: ARCUS-085
        if f5EditInPlace(e) { return } // F5: an in-place family's instance opens it in the Family Editor
        switch e.data {
        case .slab, .roof, .filledRegion, .revisionCloud, .mass: // F5: a mass edits its footprint
            session.selection.select([e.id]); run(.editBoundary)
        case .railing(let r) where !r.followsHost:
            session.selection.select([e.id]); run(.editBoundary)
        case .stair where isPlan:
            session.selection.select([e.id]); run(.editStair)
        case .textNote:
            editTextNoteInPlace(e) // W2-ANNOT: in place on the canvas
        case .group:
            session.selection.select([e.id]); run(.editGroup)
        case .insert, .component, .column, .detailComponent:
            if let t = e.typeID { state.presented = .typeProperties(t) }
        case .viewport(let vp):
            state.open(vp.viewID)
        default:
            if let t = e.typeID { state.presented = .typeProperties(t) }
        }
    }
}
