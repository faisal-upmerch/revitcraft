// arcus-bench: repeatable, offline performance measurements for Arcus's engine (no UI).
//
//   swift run -c release arcus-bench [--quick] [--out results.json] [--stress 20000]
//
// Every measurement runs on generated fixtures (Courtyard House and the stress grid), so results never depend on
// user files or the network. Times are wall-clock medians over several runs; memory is the process physical
// footprint (the figure Activity Monitor shows as "Memory").

import Foundation
import Darwin
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusIFC
import ArcusOutput

struct Measurement: Codable {
    var name: String
    var fixture: String
    var medianMs: Double
    var minMs: Double
    var maxMs: Double
    var runs: Int
    var note: String
}

var results: [Measurement] = []
let args = CommandLine.arguments
let quick = args.contains("--quick")
let runs = quick ? 3 : 7
let stressCount = args.firstIndex(of: "--stress").flatMap { i in i + 1 < args.count ? Int(args[i + 1]) : nil } ?? 20_000
let outPath = args.firstIndex(of: "--out").flatMap { i in i + 1 < args.count ? args[i + 1] : nil }

// FM3: `--document-icons <dir>` writes the .arcus, .arcusfamily and .arcusfurniture document icons (.icns) and exits.
if let i = args.firstIndex(of: "--document-icons"), i + 1 < args.count {
    exit(DocumentIcons.writeAll(to: URL(fileURLWithPath: args[i + 1])).count == DocumentIcons.Kind.allCases.count ? 0 : 1)
}

// FM9: `--furniture-library <dir> [--app-version 1.2 --app-build 34]` builds every Furniture Library piece and writes
// `<dir>/<Room>/<Name>.arcusfurniture` with a 3D thumbnail, plus `<dir>/index.json`, then exits (1 if a piece failed).
if let i = args.firstIndex(of: "--furniture-library"), i + 1 < args.count {
    exit(FurnitureLibraryBench.run(dir: URL(fileURLWithPath: args[i + 1]), args: args))
}

// `--commands-markdown` prints the command catalog (shortcuts and typed aliases) as Markdown tables and exits;
// Docs/KeyboardShortcuts.md is generated from it so the document never drifts from the code.
if args.contains("--commands-markdown") {
    for g in CommandGroup.allCases {
        let cmds = CommandCatalog.all.filter { $0.group == g }
        guard !cmds.isEmpty else { continue }
        print("### \(g.rawValue)\n\n| Command | Shortcut | Typed alias | What it does |\n|---|---|---|---|")
        for c in cmds {
            let help = c.help.replacingOccurrences(of: "|", with: "\\|")
            print("| \(c.title) | \(c.shortcut.map { "`\($0)`" } ?? "") | \(c.aliases.map { "`\($0)`" }.joined(separator: " ")) | \(help) |")
        }
        print("")
    }
    exit(0)
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

@MainActor @discardableResult
func measure<T>(_ name: String, _ fixture: String, runs n: Int = runs, note: String = "", _ body: () throws -> T) rethrows -> T {
    var times: [Double] = []
    var last: T?
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        last = try body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    times.sort()
    let m = Measurement(name: name, fixture: fixture, medianMs: times[times.count / 2], minMs: times.first!, maxMs: times.last!, runs: n, note: note)
    results.append(m)
    print(String(format: "  %-44@ %-16@ %10.2f ms  (min %.2f, max %.2f)%@", name as NSString, fixture as NSString, m.medianMs, m.minMs, m.maxMs,
                 (note.isEmpty ? "" : "  " + note) as NSString))
    return last!
}

@MainActor func measureAsync<T>(_ name: String, _ fixture: String, runs n: Int = runs, note: String = "", _ body: () async throws -> T) async rethrows -> T {
    var times: [Double] = []
    var last: T?
    for _ in 0..<n {
        let t0 = DispatchTime.now().uptimeNanoseconds
        last = try await body()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    times.sort()
    let m = Measurement(name: name, fixture: fixture, medianMs: times[times.count / 2], minMs: times.first!, maxMs: times.last!, runs: n, note: note)
    results.append(m)
    print(String(format: "  %-44@ %-16@ %10.2f ms  (min %.2f, max %.2f)", name as NSString, fixture as NSString, m.medianMs, m.minMs, m.maxMs))
    return last!
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-bench-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

let startMB = footprintMB()
print("Arcus engine benchmark — \(ProcessInfo.processInfo.operatingSystemVersionString), \(ProcessInfo.processInfo.activeProcessorCount) cores, \(runs) runs each")
print("Baseline footprint: \(String(format: "%.0f", startMB)) MB\n")

// MARK: Courtyard House

print("Courtyard House")
let courtyard = measure("Generate reference project", "courtyard", runs: quick ? 1 : 3) { CourtyardHouse.make() }
let stats = CourtyardHouse.stats(courtyard)
// Profiling hook: ARCUS_BENCH_PROFILE="<schedule name>" loops that schedule for `sample`/Instruments, then exits.
if let target = ProcessInfo.processInfo.environment["ARCUS_BENCH_PROFILE"], let sc = courtyard.schedules.first(where: { $0.name == target }) {
    for _ in 0..<200 { _ = ScheduleEngine.compute(sc, courtyard) }
    exit(0)
}
print("    \(stats.elements) elements, \(stats.rooms) rooms, \(stats.openings) openings, \(stats.views) views, \(stats.sheets) sheets, \(stats.schedules) schedules")

let info = ArcusPackage.WriteInfo(appVersion: "bench", build: "0")
let courtyardURL = tmp.appendingPathComponent("Courtyard.arcus")
try measure("Save .arcus package", "courtyard") { try ArcusPackage.write(courtyard, to: courtyardURL, info: info) }
try measure("Open .arcus package", "courtyard") { try ArcusPackage.read(from: courtyardURL).model.count }

let groundPlan = courtyard.views.first { $0.name == "Ground Floor" && $0.view?.kind == .floorPlan }!
measure("Floor plan graphics (Ground Floor)", "courtyard") { ViewGraphicsBuilder(model: courtyard, view: groundPlan).build().items.count }
let section = courtyard.views.first { $0.name == "Section 1" }!
measure("Section graphics with hidden lines", "courtyard") { ViewGraphicsBuilder(model: courtyard, view: section).build().items.count }
let south = courtyard.views.first { $0.view?.kind == .elevation }!
measure("Elevation graphics with hidden lines", "courtyard") { ViewGraphicsBuilder(model: courtyard, view: south).build().items.count }
let sheet = courtyard.sheets.first { $0.sheet?.number == "A101" }!
measure("Sheet graphics (A101)", "courtyard") { SheetGraphicsBuilder(model: courtyard, sheet: sheet).build().items.count }
for sc in courtyard.schedules { measure("Schedule: \(sc.name)", "courtyard", runs: 3) { ScheduleEngine.compute(sc, courtyard).rows.count } }
measure("All 10 schedules recompute", "courtyard") { courtyard.schedules.reduce(0) { $0 + ScheduleEngine.compute($1, courtyard).rows.count } }
measure("3D meshes, all elements (cold)", "courtyard", runs: quick ? 1 : 3) {
    courtyard.elements.values.reduce(0) { $0 + ElementMeshes.parts($1, courtyard).reduce(0) { $0 + $1.mesh.triangleCount } }
}
measure("Room boundaries (all rooms)", "courtyard") { courtyard.elements(.rooms).filter { RoomGeometry.boundary($0, courtyard).state == .bounded }.count }
let health = measure("Model health check", "courtyard", runs: 3) { ModelHealth.check(courtyard) }
print("    \(health.count) model health item(s)\(health.isEmpty ? "" : ": " + health.prefix(5).map(\.message).joined(separator: "; "))")

var ifcOptions = IFCExportOptions()
ifcOptions.fileName = "Courtyard.ifc"
let ifcData = try measure("IFC4 export", "courtyard", runs: 3) { try IFCExporter.export(courtyard, options: ifcOptions).files[0].data }
print("    IFC file: \(ByteCountFormatter.string(fromByteCount: Int64(ifcData.count), countStyle: .file))")
try measure("IFC4 import into template", "courtyard", runs: 3) {
    let (fresh, _) = ProjectTemplates.make(.architectural, units: .metric)
    let tx = TransactionContext(model: fresh, name: "Import")
    _ = try IFCImporter.importFile(ifcData, fileName: "Courtyard.ifc", into: tx)
    return try tx.commit().model.count
}

let pdfDir = tmp.appendingPathComponent("pdf", isDirectory: true)
try FileManager.default.createDirectory(at: pdfDir, withIntermediateDirectories: true)
var pdfJob = PDFExportJob(items: courtyard.sheets.map { PDFExportItem(elementID: $0.id, kind: .sheet) }, outputDirectory: pdfDir)
pdfJob.combinedFileName = "Set.pdf"
pdfJob.overwrite = .replace
let pdf = try await measureAsync("Vector PDF, all 16 sheets", "courtyard", runs: 3) { try await PDFExporter.export(courtyard, job: pdfJob) }
print("    \(pdf.pageCount) pages, \(pdf.rasterPages) raster")

// Edits through the document session (commit + regeneration + change propagation) and undo/redo.
let session = DocumentSession(model: courtyard)
// No run loop here, so group undo explicitly (the app groups by event).
session.undoManager.groupsByEvent = false
@MainActor func grouped<T>(_ um: UndoManager, _ body: () -> T) -> T { um.beginUndoGrouping(); defer { um.endUndoGrouping() }; return body() }
let wall = courtyard.elements(.walls).first { $0.wall != nil && !(courtyard.hosted(by: $0.id).isEmpty) } ?? courtyard.elements(.walls)[0]
var toggle = 1.0
measure("Move a hosting wall (commit + regen)", "courtyard", runs: 15) {
    toggle = -toggle
    return grouped(session.undoManager) { session.perform("Move") { tx in try ElementOperations.transform([wall.id], by: .translation(Vec2(0, 0.05 * toggle)), in: tx, viewID: nil) } }
}
measure("Undo", "courtyard", runs: 15) { session.undoManager.undo() }
measure("Redo", "courtyard", runs: 15) { session.undoManager.redo() }
precondition(session.undoManager.canUndo, "undo stack empty — measurements would be meaningless")
let door = courtyard.elements(.doors)[0]
measure("Change door width (family parameter)", "courtyard", runs: 9) {
    toggle = -toggle
    grouped(session.undoManager) { session.setParameter(Parameters.familyParamID("Width"), text: toggle > 0 ? "900" : "1000", on: [door.id], type: .length, name: "Width") }
}
let courtyardMB = footprintMB()

// MARK: Stress fixture

print("\nStress fixture (\(stressCount) elements)")
let stress = measure("Generate stress model", "stress", runs: 1) { CourtyardHouse.stress(count: stressCount) }
print("    \(stress.count) elements total")
let stressURL = tmp.appendingPathComponent("Stress.arcus")
try measure("Save .arcus package", "stress", runs: 3) { try ArcusPackage.write(stress, to: stressURL, info: info) }
try measure("Open .arcus package", "stress", runs: 3) { try ArcusPackage.read(from: stressURL).model.count }
let stressPlan = stress.views.first { $0.view?.kind == .floorPlan }!
measure("Floor plan graphics", "stress", runs: 3) { ViewGraphicsBuilder(model: stress, view: stressPlan).build().items.count }
measure("3D meshes, all elements (cold)", "stress", runs: 1) {
    stress.elements.values.reduce(0) { $0 + ElementMeshes.parts($1, stress).reduce(0) { $0 + $1.mesh.triangleCount } }
}
let stressSession = DocumentSession(model: stress)
stressSession.undoManager.groupsByEvent = false
let stressWall = stress.elements(.walls)[stress.elements(.walls).count / 2]
measure("Move one wall (commit + regen)", "stress", runs: 9) {
    toggle = -toggle
    return grouped(stressSession.undoManager) { stressSession.perform("Move") { tx in try ElementOperations.transform([stressWall.id], by: .translation(Vec2(0.05 * toggle, 0)), in: tx, viewID: nil) } }
}
measure("Undo", "stress", runs: 9) { stressSession.undoManager.undo() }
measure("Redo", "stress", runs: 9) { stressSession.undoManager.redo() }
let allWalls = stress.elements(.walls).map(\.id)
measure("Move all \(allWalls.count) walls (one transaction)", "stress", runs: 3) {
    toggle = -toggle
    return grouped(stressSession.undoManager) { stressSession.perform("Move all") { tx in try ElementOperations.transform(allWalls, by: .translation(Vec2(0.01 * toggle, 0)), in: tx, viewID: nil) } }
}
let peakMB = footprintMB()

print(String(format: "\nFootprint: baseline %.0f MB, after Courtyard House %.0f MB, after stress %.0f MB", startMB, courtyardMB, peakMB))

struct Report: Codable {
    var date: String
    var os: String
    var cores: Int
    var physicalMemoryGB: Double
    var stressElements: Int
    var footprintMB: [String: Double]
    var measurements: [Measurement]
}
if let outPath {
    let report = Report(date: ISO8601DateFormatter().string(from: Date()), os: ProcessInfo.processInfo.operatingSystemVersionString,
                        cores: ProcessInfo.processInfo.activeProcessorCount,
                        physicalMemoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824, stressElements: stress.count,
                        footprintMB: ["baseline": startMB, "courtyard": courtyardMB, "stress": peakMB], measurements: results)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(report).write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath)")
}
