import SwiftUI
import AppKit
import ArcusDomain
import ArcusCalc
import ArcusApplication
import ArcusPersistence
import ArcusServices

/// The app icon (original mark: a datum line over a stepped arcus).
struct ArcusMark: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Vector version of the mark for contexts without the bundle icon.
struct ArcusMarkVector: View {
    var size: CGFloat = 64
    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let base = Path(roundedRect: CGRect(x: w * 0.14, y: h * 0.62, width: w * 0.72, height: h * 0.16), cornerRadius: w * 0.02)
            let step = Path(roundedRect: CGRect(x: w * 0.26, y: h * 0.44, width: w * 0.48, height: h * 0.16), cornerRadius: w * 0.02)
            let block = Path(roundedRect: CGRect(x: w * 0.36, y: h * 0.18, width: w * 0.28, height: h * 0.24), cornerRadius: w * 0.02)
            ctx.fill(base, with: .color(Color(red: 0.42, green: 0.45, blue: 0.48)))
            ctx.fill(step, with: .color(Color(red: 0.72, green: 0.74, blue: 0.75)))
            ctx.fill(block, with: .color(Color(red: 0.93, green: 0.92, blue: 0.89)))
            var datum = Path()
            datum.move(to: CGPoint(x: w * 0.06, y: h * 0.44)); datum.addLine(to: CGPoint(x: w * 0.94, y: h * 0.44))
            ctx.stroke(datum, with: .color(Color(red: 0.24, green: 0.52, blue: 0.76)), style: StrokeStyle(lineWidth: max(1, w * 0.022), dash: [w * 0.06, w * 0.03]))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Where a new project starts from: a built-in template or a user template file.
enum ProjectTemplateChoice: Hashable {
    case builtIn(ProjectTemplateKind)
    case user(URL)
}

/// User project templates: `.arcus` packages flagged `isTemplate`, kept in Application Support/Arcus/Templates.
@MainActor
enum UserTemplates {
    struct Entry: Identifiable, Hashable {
        var url: URL
        var name: String
        var modified: Date
        var id: URL { url }
    }

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Arcus/Templates", directoryHint: .isDirectory)
    }

    /// Templates in the user template folder, by name.
    static func list() -> [Entry] {
        guard let dir = directory, let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == ArcusPackage.fileExtension }.compactMap { url in
            guard let m = try? ArcusPackage.readManifest(url), m.isTemplate == true else { return nil }
            return Entry(url: url, name: url.deletingPathExtension().lastPathComponent, modified: m.modified)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// File-name-safe version of a template name.
    static func fileName(_ name: String) -> String {
        var n = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        while n.hasPrefix(".") { n.removeFirst() }
        return n.isEmpty ? "Template" : n
    }

    /// Saves the document as a user template (model elements removed) after asking for a name.
    static func saveAsTemplate(state: DocumentState) {
        guard let dir = directory else { state.show("The template folder isn't available.", error: true); return }
        let alert = NSAlert()
        alert.messageText = "Save as Template"
        alert.informativeText = "The template keeps this project's types, families, materials, levels, views, sheets, schedules and settings. Walls, floors, components, rooms and other model elements are left out. It appears under My Templates when you start a new project."
        let base = state.document?.displayName.map { ($0 as NSString).deletingPathExtension } ?? "Project"
        let field = NSTextField(string: base + " Template")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = fileName(field.stringValue)
        let url = dir.appending(path: name + "." + ArcusPackage.fileExtension, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: url.path) {
            let confirm = NSAlert()
            confirm.messageText = "A template named “\(name)” already exists."
            confirm.informativeText = "Replace it with this project's settings?"
            confirm.addButton(withTitle: "Replace"); confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let v = AppVersionInfo.current
            try ArcusPackage.writeTemplate(state.model, to: url, info: ArcusPackage.WriteInfo(appVersion: v.marketingVersion, build: v.build))
            state.show("Saved the template “\(name)”. Choose it in New Project under My Templates.")
        } catch {
            state.show("Couldn't save the template: \(error.localizedDescription)", error: true)
        }
    }

    /// Opens a new untitled project made from the template at `url`.
    static func newProject(from url: URL, name: String) {
        do {
            let (template, _) = try ArcusPackage.read(from: url)
            let model = ProjectTemplates.instantiate(template: template, projectName: name)
            let doc = ArcusDocument(model: model, displayName: nil)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            AppDelegate.shared?.closeHub()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Project hub: recent projects, new project from a template, open, and the sample project.
struct ProjectHubView: View {
    @State var initialTab: AppDelegate.HubTab
    @State private var template: ProjectTemplateChoice = .builtIn(.architectural)
    @State private var userTemplates: [UserTemplates.Entry] = UserTemplates.list()
    @State private var browsed: [URL] = []
    // W2-TYPES: new projects default to imperial unless the user chose metric.
    @State private var metric = UserDefaults.standard.string(forKey: "defaultUnits") == "metric"
    @State private var name = "Untitled Project"
    @State private var openingSample = false

    var recents: [URL] { NSDocumentController.shared.recentDocumentURLs }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ArcusMark(size: 54)
                    VStack(alignment: .leading) {
                        Text("Arcus").font(.system(size: 26, weight: .semibold))
                        Text("Architectural BIM studio").foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Start a Project").font(.headline)
                templatePicker
                Text(summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Units", selection: $metric) { Text("Imperial (ft-in)").tag(false); Text("Metric (mm)").tag(true) }.pickerStyle(.segmented)
                    .disabled(isUserTemplate)
                    .help(isUserTemplate ? "Units come from the template." : "Units for the new project")
                TextField("Project name", text: $name).textFieldStyle(.roundedBorder)
                Button {
                    MainActor.assumeIsolated { create() }
                } label: { Label("Create Project", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                HStack {
                    Button { NSDocumentController.shared.openDocument(nil) } label: { Label("Open…", systemImage: "folder") }
                    Button {
                        openingSample = true
                        MainActor.assumeIsolated { AppDelegate.shared?.openSample() }
                    } label: { Label(openingSample ? "Building sample…" : "Open Sample Project", systemImage: "building.2") }
                        .disabled(openingSample)
                        .help("Courtyard House: 4 levels, 2 wings, 120 rooms, 16 sheets")
                }
                Spacer()
                Text("Documents stay on this Mac. No account, no network.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(width: 330)
            .background(.regularMaterial)
            VStack(alignment: .leading) {
                Text("Recent Projects").font(.headline).padding(.horizontal, 20).padding(.top, 24)
                if recents.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock").font(.system(size: 30, weight: .thin)).foregroundStyle(.tertiary)
                        Text("Projects you open appear here.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(recents, id: \.self) { url in
                        HStack(spacing: 12) {
                            RecentThumbnail(url: url)
                            VStack(alignment: .leading) {
                                Text(url.deletingPathExtension().lastPathComponent).font(.body.weight(.medium))
                                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(url) }
                        .contextMenu { Button("Open") { open(url) }; Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { open(url) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    var isUserTemplate: Bool { if case .user = template { return true }; return false }

    var summary: String {
        switch template {
        case .builtIn(let k): return k.summary
        case .user(let url):
            let when = userTemplates.first { $0.url == url }.map { " Saved \($0.modified.formatted(date: .abbreviated, time: .omitted))." } ?? ""
            return "Your template: its types, families, views, sheets and settings, with no model elements. Units come from the template." + when
        }
    }

    var templatePicker: some View {
        HStack {
            Picker("Template", selection: $template) {
                ForEach(ProjectTemplateKind.allCases, id: \.self) { Text($0.rawValue).tag(ProjectTemplateChoice.builtIn($0)) }
                if !userTemplates.isEmpty {
                    Divider()
                    Section("My Templates") {
                        ForEach(userTemplates) { t in Text(t.name).tag(ProjectTemplateChoice.user(t.url)) }
                    }
                }
                if !browsed.isEmpty {
                    Divider()
                    ForEach(browsed, id: \.self) { u in Text(u.deletingPathExtension().lastPathComponent).tag(ProjectTemplateChoice.user(u)) }
                }
            }
            Menu {
                Button("Choose Template File…") { browse() }
                if case .user(let url) = template {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    if userTemplates.contains(where: { $0.url == url }) {
                        Button("Move Template to Trash") { trash(url) }
                    }
                }
                if let dir = UserTemplates.directory {
                    Divider()
                    Button("Open Templates Folder") {
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(dir)
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Browse for a template, or manage your templates")
        }
        .onAppear { userTemplates = UserTemplates.list() }
    }

    func create() {
        switch template {
        case .builtIn(let kind): AppDelegate.shared?.newProject(template: kind, units: metric ? .metric : .imperial, name: name)
        case .user(let url): UserTemplates.newProject(from: url, name: name)
        }
    }

    func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusProject]
        panel.message = "Choose an Arcus template or project to start from. Model elements are left out of the new project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !browsed.contains(url) && !userTemplates.contains(where: { $0.url == url }) { browsed.append(url) }
        template = .user(url)
    }

    func trash(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message { showTrashError(message); return }
                userTemplates = UserTemplates.list()
                template = .builtIn(.architectural)
            }
        }
    }

    func showTrashError(_ message: String) {
        let a = NSAlert()
        a.messageText = "Couldn't move the template to the Trash."
        a.informativeText = message
        a.runModal()
    }

    func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSAlert(error: error).runModal() } else { MainActor.assumeIsolated { AppDelegate.shared?.closeHub() } }
        }
    }
}

struct RecentThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { Image(systemName: "doc.richtext").font(.system(size: 20)).foregroundStyle(.tertiary) }
        }
        .frame(width: 64, height: 46)
        .background(Color(nsColor: Tokens.canvas))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .task {
            let u = url
            let data = await Task.detached { ArcusPackage.readThumbnail(u) }.value
            if let data { image = NSImage(data: data) }
        }
        .accessibilityHidden(true)
    }
}

/// First-launch onboarding: welcome, defaults, how documents work, sample project.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var metric = false // W2-TYPES: imperial is the default
    @State private var template: ProjectTemplateKind = .architectural

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: defaults
                case 2: documents
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
            .transition(AccessibilityPrefs.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            Divider()
            HStack {
                HStack(spacing: 6) { ForEach(0..<4) { i in Circle().fill(i == step ? Tokens.selectionColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7) } }
                    .accessibilityElement().accessibilityLabel("Step \(step + 1) of 4")
                Spacer()
                if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
                Button(step == 3 ? "Close" : "Continue") {
                    if step == 3 { save(); onFinish() } else { withAnimation { step += 1 } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 720, height: 520)
    }

    var welcome: some View {
        VStack(spacing: 18) {
            ArcusMark(size: 110)
            Text("Welcome to Arcus").font(.system(size: 30, weight: .semibold))
            Text("A calm, precise studio for architectural BIM. Model levels, walls, doors, floors, roofs, stairs and rooms; the plans, sections, elevations, schedules and sheets stay coordinated with every change.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
            HStack(spacing: 24) {
                feature("square.grid.3x3.topleft.filled", "Coordinated views")
                feature("tablecells", "Live schedules")
                feature("doc.richtext", "Sheets & vector PDF")
                feature("cube.transparent", "IFC exchange")
            }
        }
    }
    func feature(_ symbol: String, _ title: String) -> some View {
        // W4-AUDIT: symbols differ in height; a fixed icon box keeps the four captions on one baseline.
        VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Tokens.selectionColor).frame(height: 30); Text(title).font(.caption) }.frame(width: 110)
    }

    var defaults: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your defaults").font(.title2.weight(.semibold))
            Picker("Units", selection: $metric) { Text("Imperial – feet and inches").tag(false); Text("Metric – millimeters").tag(true) }.pickerStyle(.radioGroup)
            Picker("Template", selection: $template) { ForEach(ProjectTemplateKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.radioGroup)
            Text(template.summary).foregroundStyle(.secondary)
            Text("You can change units per project later in Manage ▸ Project Units.").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: 480, alignment: .leading)
    }

    var documents: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How your work is kept").font(.title2.weight(.semibold))
            row("externaldrive", "Local documents", "Projects are .arcus packages on your Mac. Arcus never uploads anything and needs no account.")
            row("clock.arrow.circlepath", "Autosave and recovery", "Changes are saved automatically and journaled as you work. If Arcus quits unexpectedly, you're offered your unsaved changes next launch.")
            row("arrow.left.arrow.right", "Exchange", "IFC2x3/IFC4 import and export for BIM exchange; DXF and DWG link/import and export (DWG through engines built into Arcus); vector PDF sets. Revit files (RVT/RFA) aren't supported — export IFC from Revit instead.")
            row("lock.shield", "Privacy", "Arcus asks for no special permissions. Files you pick in Open and Save panels are the only files it can read.")
        }.frame(maxWidth: 560, alignment: .leading)
    }
    func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Tokens.selectionColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    var finish: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2").font(.system(size: 54, weight: .thin)).foregroundStyle(Tokens.selectionColor)
            Text("Ready to start").font(.title2.weight(.semibold))
            Text("Open the Courtyard House sample to explore a complete project, or start a new one from your template.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack {
                Button("Open Sample Project") { save(); onFinish(); MainActor.assumeIsolated { AppDelegate.shared?.openSample() } }.controlSize(.large)
                Button("New Project") { save(); onFinish(); MainActor.assumeIsolated { AppDelegate.shared?.newProject(template: template, units: metric ? .metric : .imperial, name: "Untitled Project") } }.controlSize(.large)
            }
        }
    }

    func save() { UserDefaults.standard.set(metric ? "metric" : "imperial", forKey: "defaultUnits") }
}

struct AboutView: View {
    var body: some View {
        let v = AppVersionInfo.current
        VStack(spacing: 12) {
            ArcusMark(size: 96)
            Text("Arcus").font(.system(size: 26, weight: .semibold))
            Text("Version \(v.marketingVersion) (\(v.build))").font(.body.monospacedDigit())
            Text("Document schema \(v.documentSchema)").font(.caption).foregroundStyle(.secondary)
            Text("DWG: \(DWGStatus.reason)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            Text(LocalOnlyUpdateProvider().statusMessage).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            Text("Arcus is a working product name. Not affiliated with Autodesk.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 420)
    }
}

@MainActor
enum DiagnosticsWindowController {
    private static var window: NSWindow?
    static func show(state: DocumentState) {
        if let w = window { w.contentViewController = NSHostingController(rootView: DiagnosticsView(state: state)); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Diagnostics"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: DiagnosticsView(state: state))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct DiagnosticsView: View {
    let state: DocumentState
    @State private var refresh = 0
    var body: some View {
        let _ = refresh
        let v = AppVersionInfo.current
        let m = state.model
        Form {
            Section("Build") {
                LabeledContent("Version", value: "\(v.marketingVersion) (\(v.build))")
                LabeledContent("Document schema", value: "\(v.documentSchema)")
                LabeledContent("DWG", value: DWGStatus.reason)
                LabeledContent("Machine", value: machine())
            }
            Section("Document") {
                LabeledContent("Elements", value: "\(m.count)")
                LabeledContent("Walls / Doors / Windows", value: "\(m.elements(.walls).count) / \(m.elements(.doors).count) / \(m.elements(.windows).count)")
                LabeledContent("Rooms", value: "\(m.elements(.rooms).count)")
                LabeledContent("Views / Sheets / Schedules", value: "\(m.views.count) / \(m.sheets.count) / \(m.schedules.count)")
                LabeledContent("Model revision", value: "\(m.revision)")
                LabeledContent("Geometry cache", value: "\(GeometryCache.shared.count) elements, \(ByteCountFormatter.string(fromByteCount: Int64(GeometryCache.shared.approximateBytes), countStyle: .memory))")
            }
            Section("Recent timings") {
                ForEach(Array(DiagnosticsLog.shared.recentTimings.suffix(20).reversed().enumerated()), id: \.offset) { _, t in
                    LabeledContent(t.name, value: String(format: "%.1f ms", t.seconds * 1000))
                }
            }
            Section {
                HStack {
                    Button("Refresh") { refresh += 1 }
                    Button("Purge Caches") { GeometryCache.shared.purge(); RoomBoundaryCache.shared.purge(); UnderlayRenderer.purge(); refresh += 1 }
                    Button("Export Redacted Log…") { export() }
                }
                Text("The exported log contains timings and events only — no file contents, no user or home folder names.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 500)
    }
    func machine() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let mem = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        let model = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return "\(model), \(mem) GB"
    }
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Arcus Diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? DiagnosticsLog.shared.exportRedacted().write(to: url, atomically: true, encoding: .utf8)
    }
}
