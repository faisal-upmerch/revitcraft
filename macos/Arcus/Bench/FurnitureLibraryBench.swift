import Foundation
import ArcusDomain
import ArcusPersistence
import ArcusOutput

// FM9: `arcus-bench --furniture-library <dir>`: the Furniture Library generator (see FurnitureLibraryWriter).

enum FurnitureLibraryBench {
    /// Writes the library to `dir`; prints one line per piece and a summary. Returns the exit status.
    static func run(dir: URL, args: [String]) -> Int32 {
        // Sets and dictionaries encode in hash order: run with deterministic hashing so rebuilds write the same bytes.
        if ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == nil {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            p.arguments = Array(args.dropFirst())
            var env = ProcessInfo.processInfo.environment
            env["SWIFT_DETERMINISTIC_HASHING"] = "1"
            p.environment = env
            do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { print("Furniture Library: \(error)"); return 1 }
        }
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let t0 = Date()
        do {
            let (results, index) = try FurnitureLibraryWriter.write(FurnitureLibrary.all, to: dir, appVersion: value("--app-version") ?? "1.0",
                                                                    build: value("--app-build") ?? "1") { FurniturePreview.png($0) }
            var failed = 0
            for r in results {
                if let e = r.error { failed += 1; print("  ✗ \(r.name): \(e)") } else { print(String(format: "  ✓ %@  (%.2f s)", r.file as NSString, r.seconds)) }
            }
            let rooms = Set(index.pieces.flatMap(\.rooms)).count
            print(String(format: "Furniture Library: %d pieces in %d rooms, %d failed, %.1f s → %@", index.pieces.count, rooms, failed, Date().timeIntervalSince(t0), dir.path))
            return failed == 0 ? 0 : 1
        } catch {
            print("Furniture Library: \(error)")
            return 1
        }
    }
}
