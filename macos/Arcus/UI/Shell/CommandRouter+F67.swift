import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusApplication
import ArcusCAD

// F67: Insert: links, imports, load as group, insert from file, decals, point clouds, topography, DWF markup. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    static let f67Commands: Set<CommandID> = [.linkModel, .linkIFC, .linkTopography, .dwfMarkup, .placeDecal, .decalTypes, .pointCloud, .coordinationModel,
                                              .importGbXML, .importPDF, .importImage, .loadAsGroup, .insertViewsFromFile, .insert2DElementsFromFile, .transferProjectStandards]

    static func f67Types(_ exts: [String]) -> [UTType] { exts.compactMap { UTType(filenameExtension: $0) } }

    /// The tool for one of this batch's commands, or nil.
    func f67MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        guard id == .placeDecal, !model.elements(.decalTypes).isEmpty else { return nil }
        let current = state.currentTypes[.decals].flatMap { model[$0]?.decalType != nil ? $0 : nil }
        let tool = DecalTool(ctx: c, typeID: current)
        let session = self.session
        tool.onPlaced = { session.selection.select([$0]) }
        return tool
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f67Perform(_ id: CommandID) -> Bool {
        guard Self.f67Commands.contains(id) else { return false }
        let st = state
        switch id {
        case .linkModel: chooseFile([UTType.arcusProject]) { F67Links(state: st).link(.arcus, $0) }
        case .linkIFC: chooseFile(Self.f67Types(["ifc"])) { F67Links(state: st).link(.ifc, $0) }
        case .coordinationModel: chooseFile(Self.f67Types(["obj"])) { F67Links(state: st).link(.obj, $0) }
        case .linkTopography, .pointCloud:
            let topo = id == .linkTopography
            chooseFile(Self.f67Types(topo ? ["xyz", "pts", "csv", "txt"] : ["xyz", "pts", "csv", "txt", "ply"]) + [.commaSeparatedText, .plainText]) { u in
                st.presented = .f67(.pointFile(u, topography: topo))
            }
        case .dwfMarkup: chooseFile(Self.f67Types(["dwfx", "xps"])) { st.presented = .f67(.dwfMarkup($0)) }
        case .placeDecal: state.presented = .f67(.decalTypes(placeAfter: true)) // no decal types yet: Decal Types opens first
        case .decalTypes: state.presented = .f67(.decalTypes(placeAfter: false))
        case .importGbXML: chooseFile(Self.f67Types(["xml", "gbxml"]) + [.xml]) { f67ImportGbXML($0) }
        case .importPDF: chooseFile([.pdf]) { st.presented = .f67(.importPDF($0)) }
        case .importImage:
            chooseFile([.png, .jpeg, .tiff, .bmp]) { u in
                guard let (png, w, h) = F67Images.load(u) else { st.show("“\(u.lastPathComponent)” is not an image Arcus can read.", error: true); return }
                F67Images.place(st, png: png, size: (w, h), dpi: 96, name: u.lastPathComponent, title: "Import Image")
            }
        case .loadAsGroup: chooseFile([UTType.arcusProject]) { f67LoadAsGroup($0) }
        case .insertViewsFromFile: chooseFile([UTType.arcusProject]) { st.presented = .f67(.insertViews($0)) }
        case .insert2DElementsFromFile: chooseFile([UTType.arcusProject]) { st.presented = .f67(.insert2D($0)) }
        case .transferProjectStandards: state.presented = .f67(.transferStandards)
        default: return false
        }
        return true
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f67DisabledReason(_ id: CommandID) -> String? {
        let kind = model[state.editingViewID]?.view?.kind
        let twoD = isSheet || (kind != nil && kind != .threeD) && !isSchedule
        switch id {
        case .placeDecal:
            guard !model.elements(.decalTypes).isEmpty else { return nil }
            return isPlan || (kind?.isVerticalCut ?? false) ? nil : "Open a plan, elevation or section to place decals."
        case .dwfMarkup:
            return model.sheets.isEmpty ? "DWF markups are linked onto sheets. Create a sheet first." : nil
        case .importPDF, .importImage:
            return twoD ? nil : "Open a 2D view or sheet to import into."
        case .insert2DElementsFromFile:
            return twoD && !isSheet ? nil : "Open a plan, section, drafting view or legend to insert 2D elements into."
        case .importGbXML:
            return model.levels.isEmpty ? "The project has no levels." : nil
        default:
            return nil
        }
    }

    func f67ImportGbXML(_ u: URL) {
        let st = state, session = self.session
        state.runBackground("Reading \(u.lastPathComponent)") { _, _ in
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            return try GbXMLReader.read(try F67Links.text(u))
        } completion: { r in
            switch r {
            case .success(let spaces):
                var rooms: [ElementID] = []
                session.perform("Import gbXML") { tx in rooms = try InsertOperations.importGbXML(spaces, in: tx) }
                if let e = session.lastError { st.show(e.message, error: true); return }
                session.selection.select(rooms)
                st.show("Imported \(rooms.count) space\(rooms.count == 1 ? "" : "s") as rooms bounded by room separation lines.")
            case .failure(let e): st.show("Couldn't import “\(u.lastPathComponent)”: \(e)", error: true)
            }
        }
    }

    func f67LoadAsGroup(_ u: URL) {
        let st = state, session = self.session
        let level = state.activeView?.levelID
        Task {
            switch await f67ReadProject(u) {
            case .success(let src):
                var made: (ElementID, PasteReport)?
                session.perform("Load as Group") { tx in made = try InsertFromFile.loadAsGroup(src, name: u.deletingPathExtension().lastPathComponent, fallbackLevel: level, in: tx) }
                if let e = session.lastError { st.show(e.message, error: true); return }
                guard let (gid, report) = made else { return }
                session.selection.select([gid])
                let name = st.model[gid]?.group?.groupTypeName ?? ""
                let skipped = report.skipped.isEmpty ? "" : " Not loaded: \(report.skipped.joined(separator: "; "))."
                st.show("Loaded group “\(name)” (\(report.pasted.count) elements) at the internal origin.\(skipped)")
            case .failure(let e): st.show("Couldn't read “\(u.lastPathComponent)”: \(e)", error: true)
            }
        }
    }
}
