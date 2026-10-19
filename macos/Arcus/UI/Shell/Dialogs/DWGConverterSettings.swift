import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusCAD

// W2-DWG: choosing and explaining the external DWG converter. Arcus never downloads or opens links for a converter; it
// only finds one the user installed and runs it as a separate program.

/// Settings ▸ DWG: the engines bundled in Arcus.app and which one read the last DWG. // DWG
struct DWGEngineSettingsSection: View {
    @State private var last = DWGEngineRecord.last()
    private let helpers = BundledDWGHelpers.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            engine("Arcus DWG engine (acadrust \(BundledDWGHelpers.acadrustVersion))", "reads and writes DWG", helpers.acadrust != nil)
            engine("GNU LibreDWG \(BundledDWGHelpers.libreDWGVersion)", "reads DWG when acadrust can't", helpers.libreDWG != nil)
            if let last {
                Divider()
                if let e = last.engine {
                    Text("Last file: \(last.file), read by \(e) on \(last.date.formatted(date: .abbreviated, time: .shortened)).")
                } else {
                    Text("Last file: \(last.file) could not be read (\(last.date.formatted(date: .abbreviated, time: .shortened))).").foregroundStyle(.orange)
                }
                ForEach(Array(last.failures.enumerated()), id: \.offset) { _, f in
                    Text(f).font(.caption).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(DWGConverterHelp.engineNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { last = DWGEngineRecord.last() }
    }

    private func engine(_ name: String, _ role: String, _ ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(ok ? .green : .red)
            Text(name)
            Text(ok ? role : "missing from this copy of Arcus").foregroundStyle(.secondary)
        }
    }
}

/// Settings ▸ DWG: a converter the user installed (tried after the bundled engines).
struct DWGConverterSettingsSection: View {
    @AppStorage(DWGConverterPreferences.pathKey) private var chosenPath = ""
    @AppStorage(DWGConverterPreferences.autoDetectKey) private var autoDetect = true
    @State private var detected: [ExternalDWGConverter] = []
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(status.ok ? .green : .orange)
                Text(status.text).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(chosenPath.isEmpty ? "Automatic" : chosenPath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Detect") { detect(); chosenPath = "" }
                Button("Choose…") { choose() }
                if !chosenPath.isEmpty { Button("Clear") { chosenPath = "" } }
            }
            Toggle("Use a detected converter automatically", isOn: $autoDetect)
            Text(DWGConverterHelp.settingsNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !checked { detect() } }
    }

    private var status: (ok: Bool, text: String) {
        switch DWGConverterPreferences.resolve(chosenPath: chosenPath, autoDetect: autoDetect) {
        case .success(let c)?:
            return (c.isExecutable, "Using \(c.displayName) at \(c.displayPath).")
        case .failure(let p)?:
            return (false, p.message)
        case nil:
            if !detected.isEmpty && !autoDetect { return (false, "\(detected[0].displayName) is installed but automatic use is off. Turn it on or choose it.") }
            return (false, "No converter installed. Not needed: the engines above read DWG. An installed converter is tried only if they can't.")
        }
    }

    private func detect() {
        detected = ExternalDWGConverter.detect()
        checked = true
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.message = "Choose ODA File Converter (the app) or LibreDWG's dwg2dxf."
        panel.prompt = "Use Converter"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let u = panel.url else { return }
        if ExternalDWGConverter.at(path: u.path) != nil {
            chosenPath = u.path
        } else {
            let a = NSAlert()
            a.messageText = "“\(u.lastPathComponent)” isn't a DWG converter Arcus can use."
            a.informativeText = "Choose ODAFileConverter.app, or the dwg2dxf program from LibreDWG (for example /opt/homebrew/bin/dwg2dxf)."
            a.runModal()
        }
    }
}

/// Plain-language instructions shared by Settings and the "no converter" dialog.
enum DWGConverterHelp {
    static let settingsNote = "Optional. If neither built-in engine can read a drawing, Arcus runs a converter you installed yourself (ODA File Converter or LibreDWG's dwg2dxf), which turns it into DXF in a private temporary folder on this Mac. Nothing is downloaded or sent anywhere."

    /// DWG: the bundled engines.
    static let engineNote = "Both engines are separate programs inside Arcus.app that run on this Mac with no network access. DWG files are read by acadrust first, then LibreDWG; saving (File ▸ Export ▸ CAD Formats ▸ DWG) uses acadrust only."

    static let odaSteps = """
    1. In your web browser, go to the Open Design Alliance website and find “ODA File Converter” (free; requires accepting ODA's license terms).
    2. Download the macOS version and drag ODAFileConverter.app into your Applications folder.
    3. Open it once from Finder, so macOS can confirm you want to run it, then quit it.
    4. Back in Arcus, choose Link DWG or Import DWG again. Arcus finds the app in /Applications or ~/Applications.
    """

    static let libreSteps = """
    1. If you use Homebrew, run this in Terminal:  brew install libredwg
    2. Arcus finds dwg2dxf in /opt/homebrew/bin, /usr/local/bin or /opt/local/bin (MacPorts). Otherwise choose it in Settings ▸ DWG.
    LibreDWG is free software (GNU GPL v3). Arcus only runs it as a separate program and does not include any of it.
    """
}

/// Body of the "no DWG converter" dialog.
struct DWGConverterHelpView: View {
    let state: DocumentState
    @State private var found: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DWGStatus.reason).fixedSize(horizontal: false, vertical: true)
            GroupBox("Option 1: ODA File Converter (free app from the Open Design Alliance)") {
                Text(DWGConverterHelp.odaSteps).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Option 2: LibreDWG's dwg2dxf (command-line tool)") {
                Text(DWGConverterHelp.libreSteps).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The converter you install does the DWG-to-DXF conversion as a separate program on this Mac. Arcus doesn't download, include or update it, and results depend on that tool. DXF files are always supported directly.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Check Again") { recheck() }
                Button("Choose Converter…") { choose() }
                if let found { Text(found).font(.callout).foregroundStyle(.green) }
            }
        }
        .frame(width: 520, alignment: .leading)
    }

    private func recheck() {
        let p = DWGProviders.current
        found = p.isAvailable ? "Found \(p.sdkName). Choose Link DWG or Import DWG again." : "Still no converter found."
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.message = "Choose ODA File Converter (the app) or LibreDWG's dwg2dxf."
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let u = panel.url else { return }
        if ExternalDWGConverter.at(path: u.path) != nil {
            UserDefaults.standard.set(u.path, forKey: DWGConverterPreferences.pathKey)
            recheck()
        } else {
            found = "“\(u.lastPathComponent)” isn't ODA File Converter or dwg2dxf."
        }
    }
}
