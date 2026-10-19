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

/// First-launch onboarding: welcome, the three ways to start, and how documents are kept. // HOME: no units or
/// template choice (Architectural is Imperial; Home has the cards).
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step: Int
    static let steps = 3

    init(onFinish: @escaping () -> Void, step: Int = 0) {
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: start
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .transition(AccessibilityPrefs.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            Divider()
            HStack {
                HStack(spacing: 6) { ForEach(0..<Self.steps, id: \.self) { i in Circle().fill(i == step ? Tokens.selectionColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7) } }
                    .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(Self.steps)")
                Spacer()
                if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
                Button(step == Self.steps - 1 ? "Close" : "Continue") {
                    if step == Self.steps - 1 { onFinish() } else { withAnimation { step += 1 } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 720, height: 520)
    }

    var welcome: some View {
        VStack(spacing: 16) {
            ArcusMark(size: 104)
            Text("Welcome to Arcus").font(.system(size: 30, weight: .semibold))
            Text("A calm, precise studio for buildings, furniture and families. Plans, sections, elevations, schedules and sheets stay coordinated with every change.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
            HStack(spacing: 24) {
                feature("square.grid.3x3.topleft.filled", "Coordinated views")
                feature("tablecells", "Live schedules")
                feature("doc.richtext", "Sheets & vector PDF")
                feature("cube.transparent", "IFC exchange")
            }
            .padding(.top, 8)
        }
    }
    func feature(_ symbol: String, _ title: String) -> some View {
        // W4-AUDIT: symbols differ in height; a fixed icon box keeps the four captions on one baseline.
        VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Tokens.selectionColor).frame(height: 30); Text(title).font(.caption) }.frame(width: 110)
    }

    var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Three ways to start").font(.title2.weight(.semibold))
            ForEach(HomeCard.allCases) { card in
                HStack(spacing: 16) {
                    HomeIllustration(card: card, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title).font(.headline)
                        Text(card.line).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("File ▸ Home shows these cards and your recent files. Units are Imperial; change them per project in Manage ▸ Project Units.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    var finish: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your work stays on this Mac").font(.title2.weight(.semibold))
            row("externaldrive", "Local documents", "Projects, furniture and families are packages on your Mac. No account, no network.")
            row("clock.arrow.circlepath", "Autosave and recovery", "Changes are saved and journaled as you work. If Arcus quits unexpectedly, you're offered them next launch.")
            row("arrow.left.arrow.right", "Exchange", "IFC import and export, DXF and DWG link, import and export, vector PDF sets. Revit files aren't supported; export IFC from Revit instead.")
            HStack(spacing: 12) {
                Button("Open Sample Project") { onFinish(); AppDelegate.shared?.openSample() }.controlSize(.large)
                Button("New Architectural Project") {
                    onFinish()
                    AppDelegate.shared?.newProject(template: .architectural, units: .imperial, name: "Untitled Project")
                }
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
    func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Tokens.selectionColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
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
