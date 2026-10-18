import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusCAD

// F67: Insert tab dialogs: point file units, DWF Markup, Import PDF, Insert Views / 2D Elements from File, Transfer
// Project Standards and Decal Types.

enum F67Dialog: Equatable {
    case pointFile(URL, topography: Bool)
    case dwfMarkup(URL)
    case importPDF(URL)
    case insertViews(URL)
    case insert2D(URL)
    case transferStandards
    case decalTypes(placeAfter: Bool)
}

struct F67DialogHost: View {
    let state: DocumentState
    let dialog: F67Dialog
    var body: some View {
        switch dialog {
        case .pointFile(let u, let topo): PointLinkDialog(state: state, url: u, topography: topo)
        case .dwfMarkup(let u): DWFMarkupDialog(state: state, url: u)
        case .importPDF(let u): ImportPDFDialog(state: state, url: u)
        case .insertViews(let u): InsertFromFileDialog(state: state, url: u, views: true)
        case .insert2D(let u): InsertFromFileDialog(state: state, url: u, views: false)
        case .transferStandards: TransferStandardsDialog(state: state)
        case .decalTypes(let place): DecalTypesDialog(state: state, placeAfter: place)
        }
    }
}

/// Reads another project off the main actor.
@MainActor
func f67ReadProject(_ u: URL) async -> Result<BIMModel, any Error> {
    await Task.detached(priority: .userInitiated) {
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        do { return .success(try ArcusPackage.read(from: u).model) } catch { return .failure(error) }
    }.value
}

// MARK: - Point Cloud / Link Topography

struct PointLinkDialog: View {
    let state: DocumentState
    let url: URL
    let topography: Bool
    @State private var units = PointFileReader.Units.auto
    var body: some View {
        DialogFrame(title: topography ? "Link Topography" : "Point Cloud", subtitle: url.lastPathComponent, okTitle: "Link", state: state) {
            state.presented = nil
            F67Links(state: state).linkPoints(url, units: units, topography: topography)
        } content: {
            FormRow(label: "File units") {
                Picker("", selection: $units) { ForEach(PointFileReader.Units.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 180)
            }
            Text(topography
                 ? "Each line: x y z, separated by spaces, commas, semicolons or tabs. The toposolid goes through the points, placed as internal coordinates, and follows the file when the project opens."
                 : "Each line: x y z, optionally followed by r g b (XYZ, PTS, CSV, TXT, or ASCII PLY). Points are placed as internal coordinates; dense clouds are thinned evenly. The cloud is re-read when the project opens.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Automatic reads meters unless the coordinates are evidently millimeters.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 480)
    }
}

// MARK: - DWF Markup

struct DWFMarkupDialog: View {
    let state: DocumentState
    let url: URL
    @State private var pages: [DWFPage] = []
    @State private var targets: [Int: ElementID] = [:]
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        let sheets = state.model.sheets
        DialogFrame(title: "Link Markups", subtitle: "DWF file: \(url.lastPathComponent)", okTitle: "OK", okDisabled: targets.isEmpty, state: state) {
            place()
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if loading { ProgressView("Reading \(url.lastPathComponent)…").frame(maxWidth: .infinity, minHeight: 80) }
            else if !pages.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("DWF Sheet").bold(); Text("Sheet").bold() }
                    ForEach(pages.indices, id: \.self) { k in
                        GridRow {
                            Text(pages[k].name).lineLimit(1)
                            Picker("", selection: Binding(get: { targets[k] ?? ElementID(0) }, set: { targets[k] = $0 == ElementID(0) ? nil : $0 })) {
                                Text("(None)").tag(ElementID(0))
                                ForEach(sheets) { s in Text("\(s.sheet?.number ?? "") - \(s.name)").tag(s.id) }
                            }.labelsHidden().frame(width: 260)
                        }
                    }
                }
            }
        }
        .frame(width: 520)
        .task { await load() }
    }

    func load() async {
        let u = url
        let r = await Task.detached { () -> Result<[DWFPage], any Error> in
            do { if case .pages(let p) = try F67Links.read(.dwfx, u) { return .success(p) }; return .success([]) } catch { return .failure(error) }
        }.value
        loading = false
        switch r {
        case .success(let p):
            pages = p
            let active = state.model[state.activeViewID]?.sheet != nil ? state.activeViewID : nil
            for (k, pg) in p.enumerated() { targets[k] = InsertOperations.matchingSheet(for: pg.name, in: state.model) ?? active }
        case .failure(let e): error = "\(e)"
        }
    }

    func place() {
        let src = F67Links.ref(url)
        let jobs = targets.sorted { $0.key < $1.key }.map { (pages[$0.key], $0.value) }
        state.session.perform("DWF Markup") { tx in for (p, s) in jobs where !p.isEmpty { try InsertOperations.addMarkup(p, onSheet: s, source: src, in: tx) } }
        if let e = state.session.lastError { error = e.message; return }
        state.presented = nil
        state.show("Linked \(jobs.count) marked-up sheet\(jobs.count == 1 ? "" : "s").")
    }
}

// MARK: - Import PDF

struct ImportPDFDialog: View {
    let state: DocumentState
    let url: URL
    @State private var page = 1
    @State private var pageCount = 1
    @State private var dpi = 150
    @State private var error: String?
    var body: some View {
        DialogFrame(title: "Import PDF", subtitle: url.lastPathComponent, okTitle: "Import", state: state) {
            importPage()
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            FormRow(label: "Page") { Stepper("\(page) of \(pageCount)", value: $page, in: 1...max(pageCount, 1)) }
            FormRow(label: "Resolution") {
                Picker("", selection: $dpi) { ForEach([72, 150, 300], id: \.self) { Text("\($0) dpi").tag($0) } }.labelsHidden().frame(width: 120)
            }
            Text("The page is stored in the project as an image at its printed size (scaled by the view scale in model views). Use Link PDF to keep it linked to the file.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 460)
        .onAppear {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            pageCount = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
            if pageCount == 0 { error = "The PDF could not be read." }
        }
    }

    func importPage() {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let doc = CGPDFDocument(url as CFURL), let p = doc.page(at: page) else { error = "The page could not be read."; return }
        let box = p.getBoxRect(.cropBox)
        let k = Double(dpi) / 72
        let w = Int((box.width * k).rounded()), h = Int((box.height * k).rounded())
        guard w > 0, h > 0, w * h < 120_000_000, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { error = "The page is too large at \(dpi) dpi."; return }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(p)
        guard let img = ctx.makeImage(), let png = F67Images.png(img) else { error = "The page could not be rendered."; return }
        let name = "\(url.deletingPathExtension().lastPathComponent) - page \(page)"
        F67Images.place(state, png: png, size: (w, h), dpi: Double(dpi), name: name, title: "Import PDF")
        state.presented = nil
    }
}

/// Imported pictures: PNG encoding and placement in the active view or sheet.
@MainActor
enum F67Images {
    static func png(_ img: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }

    /// Reads an image file as PNG (or keeps JPEG bytes) with its pixel size.
    static func load(_ u: URL) -> (Data, Int, Int)? {
        let access = u.startAccessingSecurityScopedResource()
        defer { if access { u.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: u), data.count < 256 << 20, let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let type = CGImageSourceGetType(src) as String?
        if type == UTType.png.identifier || type == UTType.jpeg.identifier { return (data, img.width, img.height) }
        return png(img).map { ($0, img.width, img.height) }
    }

    /// Places a picture in the active view or sheet at its printed size for `dpi` (times the view scale in model and
    /// drafting views), with its bottom left at the centre of the window.
    static func place(_ state: DocumentState, png: Data, size: (Int, Int), dpi: Double, name: String, title: String) {
        guard let v = state.activeViewID, let view = state.model[v] else { return }
        let isSheet = view.sheet != nil
        let scale = isSheet ? 1.0 : Double(view.view?.scale ?? 100)
        let mpp = 0.0254 / dpi * scale
        let center = (state.canvases[v] as? Canvas2DView)?.center ?? .zero
        let origin = center - Vec2(Double(size.0), Double(size.1)) * (mpp / 2)
        var id: ElementID?
        state.session.perform(title) { tx in
            id = try InsertOperations.importImage(png, name: name, pixelSize: size, metersPerPixel: mpp, origin: origin, viewID: v, levelID: nil, in: tx)
        }
        if let e = state.session.lastError { state.show(e.message, error: true) }
        else if let id { state.session.selection.select([id]); state.show("Imported “\(name)”; it is stored in the project.") }
    }
}

// MARK: - Insert Views / 2D Elements from File

struct InsertFromFileDialog: View {
    let state: DocumentState
    let url: URL
    /// Insert Views (checklist) or Insert 2D Elements (one view).
    let views: Bool
    @State private var src: BIMModel?
    @State private var chosen: Set<ElementID> = []
    @State private var error: String?
    var candidates: [Element] { src.map { views ? InsertFromFile.insertableViews($0) : InsertFromFile.viewsWith2DElements($0) } ?? [] }
    var body: some View {
        DialogFrame(title: views ? "Insert Views" : "Insert 2D Elements", subtitle: url.lastPathComponent, okTitle: "OK", okDisabled: chosen.isEmpty, state: state) {
            insert()
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if src == nil && error == nil { ProgressView("Reading \(url.lastPathComponent)…").frame(maxWidth: .infinity, minHeight: 100) }
            else if src != nil {
                Text(views ? "Views (drafting views, legends and schedules):" : "Choose the view whose 2D elements to copy into the current view:").font(.callout)
                List(candidates) { v in
                    Toggle(isOn: Binding(get: { chosen.contains(v.id) }, set: { on in
                        if views { if on { chosen.insert(v.id) } else { chosen.remove(v.id) } } else { chosen = on ? [v.id] : [] }
                    })) {
                        HStack { Text(v.name); Spacer(); Text(v.schedule != nil ? "Schedule" : v.view?.kind.rawValue ?? "").foregroundStyle(.secondary).font(.caption) }
                    }
                }.frame(height: 240)
                if views { HStack { Button("Check All") { chosen = Set(candidates.map(\.id)) }; Button("Check None") { chosen = [] } } }
            }
        }
        .frame(width: 480)
        .task {
            switch await f67ReadProject(url) {
            case .success(let m):
                src = m
                if candidates.isEmpty { error = views ? "The file has no drafting views, legends or schedules to insert." : "The file has no drafting views or legends with 2D elements." }
            case .failure(let e): error = "\(e)"
            }
        }
    }

    func insert() {
        guard let src else { return }
        let ids = candidates.map(\.id).filter(chosen.contains)
        var summary = ""
        if views {
            var made: [ElementID] = []
            state.session.perform("Insert Views") { tx in
                let r = try InsertFromFile.insertViews(ids, from: src, in: tx)
                made = r.views
                summary = "Inserted \(r.views.count) view\(r.views.count == 1 ? "" : "s") with \(r.report.pasted.count) 2D element\(r.report.pasted.count == 1 ? "" : "s")."
            }
            if state.session.lastError == nil, let first = made.first(where: { state.model[$0]?.view != nil }) { state.open(first) }
        } else {
            guard let target = state.editingViewID, let v = ids.first else { return }
            state.session.perform("Insert 2D Elements") { tx in
                let r = try InsertFromFile.insert2DElements(from: v, of: src, into: target, in: tx)
                summary = r.summary
            }
        }
        if let e = state.session.lastError { error = e.message; return }
        state.presented = nil
        state.show(summary)
    }
}

// MARK: - Transfer Project Standards

struct TransferStandardsDialog: View {
    let state: DocumentState
    /// A source: another open project or a chosen file.
    struct Source: Hashable, Identifiable { var id: String; var name: String }
    @State private var sources: [Source] = []
    @State private var sourceID = ""
    @State private var models: [String: BIMModel] = [:]
    @State private var chosen: Set<String> = []
    @State private var duplicates: [String]?
    @State private var error: String?
    var src: BIMModel? { models[sourceID] }
    var items: [ProjectStandards.Item] { src.map(ProjectStandards.items) ?? [] }

    var body: some View {
        DialogFrame(title: "Select Items to Copy", subtitle: "Copies types and settings from another project. Existing items with the same name can be overwritten or kept.",
                    okTitle: "OK", okDisabled: src == nil || chosen.isEmpty || duplicates != nil, state: state) {
            proceed()
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if let duplicates {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duplicate Types").font(.headline)
                    Text("These items already exist in this project:").font(.callout)
                    ScrollView { Text(duplicates.joined(separator: "\n")).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 140)
                    HStack {
                        Button("Overwrite") { transfer(overwrite: true) }
                        Button("New Only") { transfer(overwrite: false) }.keyboardShortcut(.defaultAction)
                        Button("Cancel") { self.duplicates = nil }
                    }
                }
            } else {
                FormRow(label: "Copy from") {
                    Picker("", selection: $sourceID) { ForEach(sources) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 260)
                    Button("Choose File…") { chooseFile() }
                }
                if src != nil {
                    List(items) { it in
                        Toggle(isOn: Binding(get: { chosen.contains(it.id) }, set: { if $0 { chosen.insert(it.id) } else { chosen.remove(it.id) } })) {
                            HStack { Text(it.title); Spacer(); Text("\(it.count)").foregroundStyle(.secondary).font(.caption) }
                        }
                    }.frame(height: 260)
                    HStack { Button("Check All") { chosen = Set(items.map(\.id)) }; Button("Check None") { chosen = [] } }
                } else {
                    Text("Open the source project, or choose its file.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .frame(width: 520)
        .onAppear(perform: findOpenProjects)
        .onChange(of: sourceID) { _, _ in chosen = Set(items.map(\.id)) }
    }

    func findOpenProjects() {
        for case let d as ArcusDocument in NSDocumentController.shared.documents where d !== state.document {
            let id = "doc:\(ObjectIdentifier(d).hashValue)"
            models[id] = d.session.model
            sources.append(Source(id: id, name: d.displayName ?? "Untitled"))
        }
        if let first = sources.first { sourceID = first.id; chosen = Set(items.map(\.id)) }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.arcusProject]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        Task {
            switch await f67ReadProject(u) {
            case .success(let m):
                let id = "file:" + u.path
                models[id] = m
                if !sources.contains(where: { $0.id == id }) { sources.append(Source(id: id, name: u.lastPathComponent)) }
                sourceID = id
                chosen = Set(items.map(\.id))
            case .failure(let e): error = "\(e)"
            }
        }
    }

    func proceed() {
        guard let src else { return }
        let d = ProjectStandards.duplicates(chosen, from: src, into: state.model)
        if d.isEmpty { transfer(overwrite: false) } else { duplicates = d }
    }

    func transfer(overwrite: Bool) {
        guard let src else { return }
        var report = ProjectStandards.Report()
        let c = chosen
        state.session.perform("Transfer Project Standards") { tx in report = ProjectStandards.transfer(c, from: src, overwrite: overwrite, in: tx) }
        if let e = state.session.lastError { error = e.message; duplicates = nil; return }
        state.presented = nil
        state.show("Transfer Project Standards: \(report.summary)")
    }
}

// MARK: - Decal Types

struct DecalTypesDialog: View {
    let state: DocumentState
    let placeAfter: Bool
    struct Draft: Identifiable, Hashable {
        var id = UUID()
        var elementID: ElementID?
        var name: String
        var data: DecalTypeData
    }
    @State private var drafts: [Draft] = []
    @State private var removed: [ElementID] = []
    @State private var selection: UUID?
    @State private var search = ""
    @State private var error: String?

    var index: Int? { drafts.firstIndex { $0.id == selection } }

    var body: some View {
        DialogFrame(title: "Decal Types", okTitle: "OK", state: state) { commit() } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Decal Types in Project").font(.caption).foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                    List(drafts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, selection: $selection) { d in
                        Text(d.name).tag(d.id)
                    }.frame(width: 220, height: 260)
                    HStack {
                        Button("New") { add(DecalTypeData(), name: "New Decal") }
                        Button("Duplicate") { if let i = index { add(drafts[i].data, name: drafts[i].name + " 2") } }.disabled(index == nil)
                        Button("Delete") { delete() }.disabled(index == nil)
                    }.controlSize(.small)
                }
                if let i = index { settings(i) } else {
                    Text("Create a decal type with New.").foregroundStyle(.secondary).frame(width: 300, height: 260)
                }
            }
        }
        .frame(width: 600)
        .onAppear {
            drafts = state.model.elements(.decalTypes).sorted { $0.name < $1.name }.compactMap { e in e.decalType.map { Draft(elementID: e.id, name: e.name, data: $0) } }
            selection = drafts.first(where: { $0.elementID == state.currentTypes[.decals] })?.id ?? drafts.first?.id
            if drafts.isEmpty { add(DecalTypeData(), name: "Decal 1") }
        }
    }

    @ViewBuilder func settings(_ i: Int) -> some View {
        Form {
            TextField("Name", text: $drafts[i].name)
            LabeledContent("Source") {
                HStack {
                    Text(drafts[i].data.imageName.isEmpty ? "(none)" : drafts[i].data.imageName).lineLimit(1).truncationMode(.middle)
                    Button("…") { chooseImage(i) }
                }
            }
            Group {
                if let img = NSImage(data: drafts[i].data.image) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: 90)
                } else {
                    Text(drafts[i].data.image.isEmpty ? "No image" : "Invalid Image File").foregroundStyle(.secondary).frame(height: 90)
                }
            }
            LabeledContent("Brightness") { TextField("", value: $drafts[i].data.brightness, format: .number.precision(.fractionLength(0...2))).frame(width: 80) }
            percent("Reflectivity", $drafts[i].data.reflectivity)
            percent("Transparency", $drafts[i].data.transparency)
            Picker("Finish", selection: $drafts[i].data.finish) { ForEach(DecalFinish.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Luminance (cd/m²)", selection: $drafts[i].data.luminance) { ForEach(DecalTypeData.luminancePresets, id: \.self) { Text($0).tag($0) } }
            percent("Bump Amount", $drafts[i].data.bumpAmount)
            Picker("Cutouts", selection: $drafts[i].data.cutout) { Text("None").tag(false); Text("Image file").tag(true) }
        }
        .frame(width: 320)
    }

    func percent(_ label: String, _ v: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField("", value: Binding(get: { (v.wrappedValue * 100).rounded() }, set: { v.wrappedValue = max(0, min(100, $0)) / 100 }), format: .number).frame(width: 60)
            Text("%")
        }
    }

    func add(_ d: DecalTypeData, name: String) {
        var n = name, k = 2
        while drafts.contains(where: { $0.name == n }) { n = "\(name) \(k)"; k += 1 }
        let draft = Draft(name: n, data: d)
        drafts.append(draft)
        selection = draft.id
    }

    func delete() {
        guard let i = index else { return }
        if let e = drafts[i].elementID {
            if state.model.elements(.decals).contains(where: { $0.decal?.decalTypeID == e }) { error = "“\(drafts[i].name)” is used by decals in the project."; return }
            removed.append(e)
        }
        drafts.remove(at: i)
        selection = drafts.first?.id
    }

    func chooseImage(_ i: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        guard let (data, w, h) = F67Images.load(u) else { error = "“\(u.lastPathComponent)” is not an image Arcus can read."; return }
        drafts[i].data.image = data
        drafts[i].data.imageName = u.lastPathComponent
        drafts[i].data.pixelWidth = w
        drafts[i].data.pixelHeight = h
        drafts[i].data.swatch = Self.swatch(data)
        error = nil
    }

    /// The image reduced to at most 64 cells on its long side (bottom row first).
    static func swatch(_ data: Data) -> DecalSwatch? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil), img.width > 0, img.height > 0 else { return nil }
        let k = 64.0 / Double(max(img.width, img.height))
        let w = max(1, Int((Double(img.width) * min(1, k)).rounded())), h = max(1, Int((Double(img.height) * min(1, k)).rounded()))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Memory rows run top-down; swatch rows bottom-up. Un-premultiply the colours.
        var out = Data(capacity: w * h * 4)
        for row in (0..<h).reversed() {
            for col in 0..<w {
                let o = (row * w + col) * 4
                let a = buf[o + 3]
                func un(_ c: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, Int(c) * 255 / Int(a))) }
                out.append(contentsOf: [un(buf[o]), un(buf[o + 1]), un(buf[o + 2]), a])
            }
        }
        return DecalSwatch(columns: w, rows: h, rgba: out)
    }

    func commit() {
        let ds = drafts, gone = removed
        var selected: ElementID?
        let sel = selection
        state.session.perform("Decal Types") { tx in
            for id in gone { tx.delete(id) }
            for d in ds {
                if let id = d.elementID {
                    tx.update(id) { $0.name = d.name; $0.data = .decalType(d.data) }
                    if d.id == sel { selected = id }
                } else {
                    let id = InsertOperations.createDecalType(d.name, d.data, in: tx)
                    if d.id == sel { selected = id }
                }
            }
        }
        if let e = state.session.lastError { error = e.message; return }
        state.presented = nil
        if let selected { state.currentTypes[.decals] = selected }
        if placeAfter, selected != nil {
            if state.model[selected]?.decalType?.image.isEmpty ?? true { state.show("The decal type has no image yet; it places as an outline until you choose one in Decal Types.") }
            CommandRouter(state: state).run(.placeDecal)
        }
    }
}

// MARK: - Manage Links (models, point clouds, topography, DWF markups)

/// F67: the links the Insert tab adds, listed under the CAD links in Manage Links.
struct F67ManageLinksSection: View {
    let state: DocumentState
    @State private var selected: ElementID?
    var body: some View {
        let _ = state.session.changeCounter
        let links = InsertOperations.linkElements(state.model)
        VStack(alignment: .leading, spacing: 8) {
            Text("Models, IFC, Point Clouds, Topography and DWF Markups").font(DialogMetrics.sectionHeader).foregroundStyle(.secondary)
            Table(links, selection: $selected) {
                TableColumn("Name") { e in Text(e.name) }
                TableColumn("Type") { e in Text(Self.kind(e)) }.width(130)
                TableColumn("Status") { e in Text(Self.status(e)) }.width(80)
                TableColumn("Path") { e in Text(e.f67LinkSource?.path ?? "").lineLimit(1).truncationMode(.middle) }
            }
            .frame(minHeight: 140)
            .overlay {
                if links.isEmpty {
                    Text("No linked models, point clouds, topography or markups.\nUse Insert ▸ Link Model, Link IFC, Point Cloud or DWF Markup.").multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Reload") { if let s = selected { F67Links(state: state).reload([s]) } }.disabled(selected == nil)
                Button("Reload From…") { if let s = selected { F67Links(state: state).locate(s) } }.disabled(selected == nil)
                Button("Unload") { if let s = selected { state.session.perform("Unload Link") { tx in InsertOperations.setLoaded(s, false, in: tx) } } }.disabled(!canToggle(true))
                Button("Load") { if let s = selected { state.session.perform("Load Link") { tx in InsertOperations.setLoaded(s, true, in: tx) } } }.disabled(!canToggle(false))
                Spacer()
                Button("Remove", role: .destructive) { if let s = selected { state.session.delete([s]); selected = nil } }.disabled(selected == nil)
            }
        }
    }

    func canToggle(_ loaded: Bool) -> Bool {
        guard let s = selected, let e = state.model[s] else { return false }
        switch e.data {
        case .linkedModel(let l): return l.isLoaded == loaded
        case .pointCloud(let p): return p.isLoaded == loaded
        case .markup(let m): return m.isLoaded == loaded
        default: return false
        }
    }

    static func kind(_ e: Element) -> String {
        switch e.data {
        case .linkedModel(let l): l.format == .arcus ? "Arcus Model" : l.format == .ifc ? "IFC" : "Coordination Model"
        case .pointCloud: "Point Cloud"
        case .markup: "DWF Markup"
        default: "Topography"
        }
    }

    static func status(_ e: Element) -> String {
        let loaded: Bool = switch e.data {
        case .linkedModel(let l): l.isLoaded
        case .pointCloud(let p): p.isLoaded
        case .markup(let m): m.isLoaded
        default: true
        }
        guard loaded else { return "Unloaded" }
        return e.f67LinkSource.flatMap(F67Links.url) == nil ? "Not Found" : "Loaded"
    }
}
