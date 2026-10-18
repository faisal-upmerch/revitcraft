import Foundation
import ArcusGeometry
import ArcusDomain

/// Places, reloads, unloads and removes CAD (DXF/DWG) links and imports.
///
/// Reading and converting happen in `prepare` / `load` (no model access; safe to run off the main actor). Model changes go
/// through the caller's `TransactionContext`, which the caller commits as one undoable step.
public enum CADLinkService {
    /// A parsed and converted drawing ready to be added to a model.
    public struct Prepared: Sendable {
        public var url: URL
        public var bookmark: Data?
        public var format: LinkFormat
        public var drawing: ReferenceDrawing
        public var report: CADImportReport
        public var options: CADImportOptions
        public var placement: Transform2
        public var sourceModified: Date?
        public var dependencies: [CADDependency]
    }

    /// Reads and converts off the main actor. Pair with `place(prepared:in:)` on the actor that owns the transaction.
    @concurrent
    public static func prepare(url: URL, bookmark: Data?, options: CADImportOptions, projectSurveyOrigin: Vec2,
                               progress: @escaping @Sendable (Double) -> Void = { _ in },
                               isCancelled: @escaping @Sendable () -> Bool = { false }) async throws -> Prepared {
        try prepareSync(url: url, bookmark: bookmark, options: options, projectSurveyOrigin: projectSurveyOrigin, localOrigin: nil,
                        progress: progress, isCancelled: isCancelled)
    }

    static func prepareSync(url: URL, bookmark: Data?, options: CADImportOptions, projectSurveyOrigin: Vec2, localOrigin: Vec2?,
                            progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> Prepared {
        let loaded = try load(url: url, options: options, localOrigin: localOrigin, progress: progress, isCancelled: isCancelled)
        let placement = CADConverter.placement(for: loaded.drawing, options: options, surveyOrigin: projectSurveyOrigin)
        var report = loaded.report
        let placed = Rect2(points: loaded.drawing.extents.corners.map(placement.apply))
        let far = max(abs(placed.min.x), abs(placed.min.y), abs(placed.max.x), abs(placed.max.y))
        if CADGeometry.isFinite(placed), far > Tolerance.farFromOrigin {
            report.warnings.append(String(format: "The placed content lies %.1f km from the project origin. Consider center-to-center or shared-coordinates positioning.", far / 1000))
        }
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return Prepared(url: url, bookmark: bookmark, format: loaded.format, drawing: loaded.drawing, report: report, options: options,
                        placement: placement, sourceModified: modified, dependencies: loaded.dependencies)
    }

    /// Adds a prepared drawing to the model and creates the `.importedCAD` element.
    public static func place(prepared p: Prepared, in tx: TransactionContext) throws -> (ElementID, CADImportReport) {
        if let l = p.options.levelID, tx.model[l]?.level == nil { throw CADError("The level to place the drawing on does not exist.") }
        if let v = p.options.currentViewOnly, tx.model[v]?.view == nil { throw CADError("The view for a current-view-only import does not exist.") }
        let key = tx.addReferenceDrawing(p.drawing)
        var ld = LinkData(format: p.format, isLinked: p.options.isLink, sourcePath: p.url.path, sourceName: p.url.lastPathComponent,
                          contentKey: key, placement: p.placement)
        ld.bookmark = p.bookmark
        ld.layers = p.drawing.layers.map { LinkLayerState(name: $0.name) }
        ld.page = p.options.layout
        ld.lastLoaded = Date()
        ld.sourceModified = p.sourceModified
        let format = p.format.rawValue
        let name = p.url.lastPathComponent
        let id = tx.create(.importedCAD, name: name, data: .link(ld), levelID: p.options.levelID, ownerViewID: p.options.currentViewOnly) {
            $0.source = SourceMetadata(format: format, fileName: name, originalID: "", originalType: p.options.isLink ? "CAD Link" : "CAD Import")
        }
        return (id, p.report)
    }

    /// Reads (DXF natively; DWG via DWGProviders.current), converts, adds the ReferenceDrawing and creates an `.importedCAD` element with `.link(LinkData)`; returns element id + report. Runs parse/convert off the main actor; the tx is committed by the caller as one undoable step.
    public static func place(url: URL, bookmark: Data?, options: CADImportOptions, projectSurveyOrigin: Vec2, in tx: TransactionContext,
                             progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> (ElementID, CADImportReport) {
        let p = try prepareSync(url: url, bookmark: bookmark, options: options, projectSurveyOrigin: projectSurveyOrigin, localOrigin: nil,
                                progress: progress, isCancelled: isCancelled)
        return try place(prepared: p, in: tx)
    }

    /// Re-reads a link's source and swaps its content (the previous content stays in the model assets for undo). Preserves the
    /// placement and per-layer visibility/halftone by layer name. Imports (snapshots) cannot be reloaded.
    public static func reload(linkElementID: ElementID, from url: URL, in tx: TransactionContext,
                              progress: @Sendable (Double) -> Void, isCancelled: @Sendable () -> Bool) throws -> CADImportReport {
        guard let el = tx.model[linkElementID], let old = el.link else { throw CADError("The element is not a CAD link.") }
        guard old.format == .dxf || old.format == .dwg else { throw CADError("“\(old.sourceName)” is not a DWG or DXF link.") }
        guard old.isLinked else {
            throw CADError("“\(old.sourceName)” was imported, not linked. Imports are snapshots and can't be reloaded; import the file again instead.")
        }
        let oldDrawing = tx.model.referenceDrawings[old.contentKey]
        var options = CADImportOptions()
        options.isLink = true
        options.layout = old.page
        if let d = oldDrawing {
            if let u = d.metadata["cad.unitsOverride"].flatMap(Int.init).flatMap(CADUnits.init(rawValue:)) { options.unitsOverride = u }
            options.explodeBlocks = d.metadata["cad.explodeBlocks"] == "1"
            if let inc = d.metadata["cad.includedLayers"] { options.includedLayers = Set(inc.split(separator: "\n").map(String.init)) }
            if let l = d.metadata["cad.layout"], !l.isEmpty { options.layout = l }
        }
        // Keep the old local origin so the stored placement stays valid.
        let localOrigin: Vec2? = oldDrawing.flatMap { d in
            guard let x = d.metadata["cad.localOriginX"].flatMap(Double.init), let y = d.metadata["cad.localOriginY"].flatMap(Double.init) else { return nil }
            return Vec2(x, y)
        }
        let loaded = try load(url: url, options: options, localOrigin: localOrigin, progress: progress, isCancelled: isCancelled)
        // When the previous content is missing from the model its local origin is unknown; the placement is kept as is.
        let drawing = loaded.drawing
        let key = tx.addReferenceDrawing(drawing)
        let previous = Dictionary(old.layers.map { ($0.name.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        tx.update(linkElementID) { e in
            guard var ld = e.link else { return }
            ld.contentKey = key
            ld.layers = drawing.layers.map { l in
                if let s = previous[l.name.uppercased()] { return LinkLayerState(name: l.name, visible: s.visible, halftone: s.halftone) }
                return LinkLayerState(name: l.name)
            }
            ld.isLoaded = true
            ld.sourcePath = url.path
            ld.lastLoaded = Date()
            ld.sourceModified = modified
            e.link = ld
        }
        return loaded.report
    }

    /// Unloads a link: it stays in the model but is not displayed until reloaded.
    public static func unload(_ id: ElementID, in tx: TransactionContext) {
        tx.update(id) { $0.link?.isLoaded = false }
    }

    /// Removes a link or import element (its reference content remains in the model assets for undo).
    public static func remove(_ id: ElementID, in tx: TransactionContext) {
        guard tx.model[id]?.link != nil else { return }
        tx.delete(id)
    }

    // MARK: Loading

    struct Loaded {
        var format: LinkFormat
        var drawing: ReferenceDrawing
        var report: CADImportReport
        var dependencies: [CADDependency]
    }

    static func format(of url: URL, data: Data?) throws -> LinkFormat {
        switch url.pathExtension.lowercased() {
        case "dxf": return .dxf
        case "dwg": return .dwg
        default:
            if let data, DXFReader.looksLikeDXF(data) { return .dxf }
            throw CADError("“\(url.lastPathComponent)” is not a DWG or DXF file.")
        }
    }

    static func readDocument(url: URL, options: CADReadOptions, progress: @Sendable (Double) -> Void,
                             isCancelled: @Sendable () -> Bool) throws -> (CADDocument, LinkFormat) {
        if url.pathExtension.lowercased() == "dwg" {
            let provider = DWGProviders.current
            guard provider.isAvailable else { throw CADError(provider.unavailableReason ?? "DWG import is not available.") }
            return (try provider.read(url, options: options, progress: progress, isCancelled: isCancelled), .dwg)
        }
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
            throw CADError("“\(url.lastPathComponent)” could not be read: \(error.localizedDescription)")
        }
        let fmt = try format(of: url, data: data)
        if fmt == .dwg { return try readDocument(url: url, options: options, progress: progress, isCancelled: isCancelled) }
        return (try DXFReader.read(data, fileName: url.lastPathComponent, options: options, progress: progress, isCancelled: isCancelled), .dxf)
    }

    static func load(url: URL, options: CADImportOptions, localOrigin: Vec2?, progress: @Sendable (Double) -> Void,
                     isCancelled: @Sendable () -> Bool) throws -> Loaded {
        let start = Date()
        let sampler = CADPeakSampler()
        sampler.sample(force: true)
        let readOptions = CADReadOptions()
        var (doc, fmt) = try readDocument(url: url, options: readOptions, progress: { v in sampler.sample(); progress(0.7 * v) }, isCancelled: isCancelled)
        sampler.sample(force: true)
        if isCancelled() { throw CancellationError() }
        var xrefWarnings: [String] = []
        var loadedXrefs: Set<String> = []
        doc = try resolveXrefs(doc, parentURL: url, depth: 0, visited: [url.standardizedFileURL.resolvingSymlinksInPath().path], loaded: &loadedXrefs,
                               warnings: &xrefWarnings, isCancelled: isCancelled)
        progress(0.8)
        let deps = CADDependencies.scan(doc, parentURL: url)
        let result = try CADConverter.convertDocument(doc, options: options, localOrigin: localOrigin, maxEntities: readOptions.maxEntities,
                                                      maxBlockDepth: readOptions.maxBlockDepth, isCancelled: isCancelled)
        sampler.sample(force: true)
        var report = result.report
        report.fileName = url.lastPathComponent
        report.format = fmt.rawValue
        report.missingXrefs = deps.filter { $0.kind == .xref && !loadedXrefs.contains($0.name.uppercased()) }.map(\.name)
        report.missingImages = deps.filter { $0.kind == .image && $0.status != .found }.map(\.declaredPath)
        report.missingFonts = deps.filter { d in
            d.kind == .font && d.status != .found && ["shx", "shp", ""].contains((d.declaredPath as NSString).pathExtension.lowercased())
        }.map { CADDependencies.fileName(of: $0.declaredPath) }
        for d in deps where d.status == .outsideParentFolder {
            report.warnings.append("“\(d.name)” refers to \(d.declaredPath), which is outside the drawing's folder. It was not loaded; choose the file explicitly to use it.")
        }
        report.warnings.append(contentsOf: xrefWarnings)
        report.elapsed = Date().timeIntervalSince(start)
        report.peakMemoryBytes = sampler.value
        progress(1)
        return Loaded(format: fmt, drawing: result.drawing, report: report, dependencies: deps)
    }

    /// Loads DXF (and, with an SDK, DWG) xrefs found inside the drawing's folder and merges them as block content
    /// ("XREF|name" blocks and layers). Cycles and depth are bounded.
    static func resolveXrefs(_ doc: CADDocument, parentURL: URL, depth: Int, visited: Set<String>, loaded: inout Set<String>,
                             warnings: inout [String], isCancelled: @Sendable () -> Bool) throws -> CADDocument {
        guard !doc.xrefs.isEmpty else { return doc }
        var doc = doc
        let deps = Dictionary(CADDependencies.scan(doc, parentURL: parentURL).filter { $0.kind == .xref }.map { ($0.name, $0) },
                              uniquingKeysWith: { a, _ in a })
        for x in doc.xrefs {
            guard let dep = deps[x.blockName], dep.status == .found, let childURL = dep.resolvedURL else { continue }
            let key = childURL.standardizedFileURL.resolvingSymlinksInPath().path
            if visited.contains(key) {
                warnings.append("Reference “\(x.blockName)” refers back to a drawing that is already loaded (circular reference); it was skipped.")
                continue
            }
            guard depth < 4 else { warnings.append("Reference “\(x.blockName)” is nested too deeply and was not loaded."); continue }
            if isCancelled() { throw CancellationError() }
            let child: CADDocument
            do {
                child = try readDocument(url: childURL, options: CADReadOptions(), progress: { _ in }, isCancelled: isCancelled).0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warnings.append("Reference “\(x.blockName)” could not be read: \(error)")
                continue
            }
            var nestedLoaded: Set<String> = []
            let resolvedChild = try resolveXrefs(child, parentURL: childURL, depth: depth + 1, visited: visited.union([key]), loaded: &nestedLoaded,
                                                 warnings: &warnings, isCancelled: isCancelled)
            merge(resolvedChild, into: &doc, as: x.blockName)
            loaded.insert(x.blockName.uppercased())
        }
        return doc
    }

    /// Merges a child drawing as the content of xref block `name`.
    static func merge(_ child: CADDocument, into doc: inout CADDocument, as name: String) {
        let prefix = name + "|"
        func renameLayer(_ l: String) -> String { l == "0" ? "0" : prefix + l }
        func adapt(_ e: CADEntity) -> CADEntity {
            var r = e.renamingBlocks { prefix + $0 }
            var p = r.props
            p.layer = renameLayer(p.layer)
            r.props = p
            return r
        }
        for (bn, b) in child.blocks {
            var nb = b
            nb.name = prefix + bn
            nb.entities = b.entities.map(adapt)
            doc.blocks[nb.name] = nb
        }
        let modelName = prefix + "*Model"
        doc.blocks[modelName] = CADBlock(name: modelName, entities: child.modelSpace.map(adapt))
        let parentUnits = doc.units == .unitless ? CADUnits.millimeters : doc.units
        let childUnits = child.units == .unitless ? parentUnits : child.units
        let k = childUnits.metersPerUnit / parentUnits.metersPerUnit
        if var xb = doc.block(named: name) {
            xb.entities = [.insert(CADInsert(blockName: modelName, position: .zero, scale: Vec2(k, k)), CADEntityProps(layer: "0"))]
            doc.blocks[xb.name] = xb
        }
        let known = Set(doc.layers.map { $0.name.uppercased() })
        for l in child.layers where l.name != "0" {
            var nl = l
            nl.name = renameLayer(l.name)
            if !known.contains(nl.name.uppercased()) { doc.layers.append(nl) }
        }
        var seenFonts = Set(doc.fonts.map { $0.uppercased() })
        doc.fonts.append(contentsOf: child.fonts.filter { seenFonts.insert($0.uppercased()).inserted })
        for (t, c) in child.entityCounts { doc.entityCounts[t, default: 0] += c }
        for (t, c) in child.unsupportedCounts { doc.unsupportedCounts[t, default: 0] += c }
        doc.warnings.append(contentsOf: child.warnings.map { "\(name): \($0)" })
    }
}
