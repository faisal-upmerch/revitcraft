import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusIFC
import ArcusCAD

// F67: reads the files the Insert tab links (Arcus projects, IFC, OBJ, point files, DWFx) off the main actor and
// adds or reloads the links in one undoable step. Links are re-read when the project opens; unchanged sources
// (same modification date) are skipped.

/// What a link file holds once read.
enum F67LinkContent: Sendable {
    case model([LinkedModelPart], Int)
    case points(PointSet)
    case pages([DWFPage])
}

/// How a link file is read.
enum F67LinkKind: Sendable {
    case arcus, ifc, obj
    /// Point cloud or survey points; `scale` fixes meters per file unit (reloads), else `units` decide.
    case points(PointFileReader.Units, scale: Double?, maxPoints: Int)
    case dwfx

    init?(_ e: Element) {
        switch e.data {
        case .linkedModel(let l): self = l.format == .arcus ? .arcus : l.format == .ifc ? .ifc : .obj
        case .pointCloud(let p): self = .points(.auto, scale: p.unitScale, maxPoints: 500_000)
        case .markup: self = .dwfx
        case .topography where TopographyLink.isLinked(e): self = .points(.auto, scale: TopographyLink.unitScale(of: e), maxPoints: 200_000)
        default: return nil
        }
    }
}

@MainActor
struct F67Links {
    let state: DocumentState

    // MARK: Files

    /// The file a link reads: its bookmark when it resolves, else its path when the file is there.
    static func url(_ f: ExternalFileRef) -> URL? {
        var stale = false
        if let b = f.bookmark, let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: u.path) { return u }
        return FileManager.default.fileExists(atPath: f.path) ? URL(fileURLWithPath: f.path) : nil
    }

    nonisolated static func modified(_ u: URL) -> Date? { (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }

    static func ref(_ u: URL) -> ExternalFileRef {
        ExternalFileRef(path: u.path, name: u.lastPathComponent,
                        bookmark: try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
                        sourceModified: modified(u))
    }

    /// Reads a link file (off the main actor).
    nonisolated static func read(_ kind: F67LinkKind, _ u: URL, progress: @Sendable (Double) -> Void = { _ in }, isCancelled: @Sendable () -> Bool = { false }) throws -> F67LinkContent {
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        switch kind {
        case .arcus:
            let (m, _) = try ArcusPackage.read(from: u)
            let (parts, count) = LinkedGeometry.content(of: m, isCancelled: isCancelled)
            return .model(parts, count)
        case .ifc:
            let r = try IFCLink.content(try Data(contentsOf: u), fileName: u.lastPathComponent, progress: progress, isCancelled: isCancelled)
            return .model(r.parts, r.elementCount)
        case .obj:
            let groups = try OBJReader.read(try text(u))
            return .model(LinkedGeometry.content(ofMesh: groups), groups.count)
        case .points(let units, let scale, let maxPoints):
            return .points(try PointFileReader.read(try text(u), units: units, scale: scale, maxPoints: maxPoints))
        case .dwfx:
            return .pages(try DWFxReader.read(try Data(contentsOf: u)))
        }
    }

    nonisolated static func text(_ u: URL) throws -> String {
        let d = try Data(contentsOf: u)
        guard d.count < 1 << 30 else { throw InsertError("“\(u.lastPathComponent)” is larger than 1 GB.") }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: Linking

    /// Link Model, Link IFC or Coordination Model: reads `u` and links it.
    func link(_ format: LinkedModelFormat, _ u: URL) {
        if format == .arcus, let own = state.document?.fileURL, own.standardizedFileURL == u.standardizedFileURL {
            state.show("A project can't link itself.", error: true); return
        }
        let kind: F67LinkKind = format == .arcus ? .arcus : format == .ifc ? .ifc : .obj
        let src = Self.ref(u)
        let session = state.session, st = state
        state.runBackground("Linking \(u.lastPathComponent)") { progress, cancelled in
            try Self.read(kind, u, progress: { progress($0, "Reading") }, isCancelled: cancelled)
        } completion: { r in
            switch r {
            case .success(.model(let parts, let count)):
                var id: ElementID?
                session.perform(format == .obj ? "Coordination Model" : format == .ifc ? "Link IFC" : "Link Model") { tx in
                    id = try InsertOperations.addLinkedModel(format, source: src, parts: parts, elementCount: count, in: tx)
                }
                if let e = session.lastError { st.show(e.message, error: true) }
                else if let id { session.selection.select([id]); st.show("Linked “\(src.name)”: \(count) element\(count == 1 ? "" : "s"), internal origin to internal origin.") }
            case .success: break
            case .failure(let e): st.show("Couldn't link “\(u.lastPathComponent)”: \(e)", error: true)
            }
        }
    }

    /// Point Cloud or Link Topography with the chosen file units.
    func linkPoints(_ u: URL, units: PointFileReader.Units, topography: Bool) {
        let src = Self.ref(u)
        let session = state.session, st = state, type = state.currentTypes[.topography]
        state.runBackground("Reading \(u.lastPathComponent)") { _, _ in
            try Self.read(.points(units, scale: nil, maxPoints: topography ? 200_000 : 500_000), u)
        } completion: { r in
            guard case .success(.points(let set)) = r else {
                if case .failure(let e) = r { st.show("Couldn't read “\(u.lastPathComponent)”: \(e)", error: true) }
                return
            }
            var id: ElementID?, kept = 0
            session.perform(topography ? "Link Topography" : "Point Cloud") { tx in
                if topography { (id, kept) = try InsertOperations.linkTopography(set, source: src, typeID: type, in: tx) }
                else { id = try InsertOperations.addPointCloud(set, source: src, in: tx); kept = set.points.count }
            }
            if let e = session.lastError { st.show(e.message, error: true); return }
            if let id { session.selection.select([id]) }
            let thinned = set.sourceCount > kept ? " (thinned from \(set.sourceCount))" : ""
            st.show(topography ? "Linked toposolid through \(kept) points\(thinned)." : "Linked point cloud: \(kept) points\(thinned).")
        }
    }

    // MARK: Reloading

    /// Re-reads the sources of F67 links. `onlyIfChanged` skips sources whose modification date is the one last read
    /// (used when the project opens); missing sources are reported, and their last content stays.
    func reload(_ ids: [ElementID], onlyIfChanged: Bool = false) {
        var jobs: [(ElementID, F67LinkKind, URL, String)] = []
        var missing: [String] = []
        for id in ids {
            guard let e = state.model[id], let f = e.f67LinkSource, let kind = F67LinkKind(e) else { continue }
            guard let u = Self.url(f) else { missing.append(f.name); continue }
            if onlyIfChanged, let m = Self.modified(u), let last = f.sourceModified, abs(m.timeIntervalSince(last)) < 0.5 { continue }
            jobs.append((id, kind, u, f.name))
        }
        if !missing.isEmpty {
            state.show("Not found: \(missing.joined(separator: ", ")). The last loaded content is shown; use Manage Links ▸ Reload From… to locate \(missing.count == 1 ? "it" : "them").", error: !onlyIfChanged)
        }
        guard !jobs.isEmpty else { return }
        let session = state.session, st = state, todo = jobs
        state.runBackground(jobs.count == 1 ? "Reloading \(jobs[0].3)" : "Reloading \(jobs.count) links") { progress, cancelled in
            let jobs = todo
            var out: [(ElementID, F67LinkContent?, Date?, String)] = []
            for (k, (id, kind, u, name)) in jobs.enumerated() {
                progress(Double(k) / Double(jobs.count), name)
                if cancelled() { break }
                do { out.append((id, try Self.read(kind, u, isCancelled: cancelled), Self.modified(u), "")) }
                catch { out.append((id, nil, nil, "\(name): \(error)")) }
            }
            return out
        } completion: { r in
            guard case .success(let results) = r else { return }
            var failures = results.map(\.3).filter { !$0.isEmpty }
            session.perform(results.count == 1 ? "Reload Link" : "Reload Links") { tx in
                for (id, content, date, _) in results {
                    guard let content, let e = tx.model[id] else { continue }
                    do {
                        switch (e.data, content) {
                        case (.linkedModel, .model(let parts, let count)): try InsertOperations.reloadLinkedModel(id, parts: parts, elementCount: count, sourceModified: date, in: tx)
                        case (.pointCloud, .points(let set)): InsertOperations.reloadPointCloud(id, set, sourceModified: date, in: tx)
                        case (.markup, .pages(let pages)): try InsertOperations.reloadMarkup(id, pages: pages, sourceModified: date, in: tx)
                        case (.topography, .points(let set)): try InsertOperations.reloadTopography(id, set, sourceModified: date, in: tx)
                        default: break
                        }
                    } catch { failures.append("\(e.name): \(error)") }
                }
            }
            if let e = session.lastError { failures.append(e.message) }
            if !failures.isEmpty { st.show("Reload: \(failures.joined(separator: "; "))", error: true) }
            else if !onlyIfChanged { st.show("Reloaded \(results.count) link\(results.count == 1 ? "" : "s").") }
        }
    }

    /// When the project opens: re-read every F67 link whose source changed since it was last read.
    func reloadOnOpen() {
        let ids = InsertOperations.linkElements(state.model).map(\.id)
        guard !ids.isEmpty else { return }
        reload(ids, onlyIfChanged: true)
    }

    /// Reload From…: points a link at another file and reloads it.
    func locate(_ id: ElementID) {
        guard let e = state.model[id], let f = e.f67LinkSource else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose the file for “\(f.name)”."
        panel.allowsMultipleSelection = false
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let u = panel.url else { return }
            var nf = Self.ref(u)
            nf.sourceModified = nil
            state.session.perform("Reload From") { tx in
                tx.update(id) { e in
                    switch e.data {
                    case .linkedModel(var l): l.source = nf; e.data = .linkedModel(l)
                    case .pointCloud(var p): p.source = nf; e.data = .pointCloud(p)
                    case .markup(var m): m.source = nf; e.data = .markup(m)
                    case .topography: e.source = TopographyLink.metadata(nf, unitScale: TopographyLink.unitScale(of: e))
                    default: break
                    }
                }
            }
            reload([id])
        }
    }
}
