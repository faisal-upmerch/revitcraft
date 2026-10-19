// swift-tools-version: 6.2
//
// Arcus — a native architectural BIM studio for macOS.
//
// The package is built with SwiftPM and staged into a real `Arcus.app`
// bundle by `script/build_and_run.sh`. Module layering (enforced by target
// dependencies; lower layers never import higher ones):
//
//   ArcusGeometry      Pure geometry kernel (2D/3D primitives, tolerance, polygons,
//                       triangulation, arrangements, meshes, hidden-line). Foundation + simd.
//   ArcusCalc          Units, quantity parsing/formatting, formula language. Foundation only.
//   ArcusDomain        BIM model, elements, parameters, constraints, transactions,
//                       regeneration, views, schedules, sheets. No UI, no SQLite, no formats.
//   ArcusApplication   Document session, commands, tools state machines, undo glue.
//   ArcusPersistence   `.arcus` / `.arcusfamily` packages on transactional SQLite.
//   ArcusIFC           IFC2x3 CV / IFC4 RV STEP reader + writer for the architectural subset.
//   ArcusCAD           CAD reference model, DXF reader/writer, DWG provider protocol,
//                       conversion to Arcus drafting/reference geometry.
//   ArcusOutput        Vector PDF sheet sets, printing support, CSV schedules.
//   ArcusServices      Recovery journal, diagnostics, versioning, update policy.
//   ArcusUI            AppKit + SwiftUI + Metal user interface.
//   Arcus              The app executable.
//
// DWG: the licensed ODA Drawings SDK is linked only when ARCUS_ODA_SDK_DIR points
// at a local SDK installation (see Docs/DWGSDKSetup.md). Without it, DWG import is
// reported as unavailable with a truthful reason. Set ARCUS_REQUIRE_DWG=1 to make
// a build fail loudly when the SDK is missing (release gate for DWG-enabled builds).
import Foundation
import PackageDescription

let env = ProcessInfo.processInfo.environment
let odaDir = env["ARCUS_ODA_SDK_DIR"].flatMap { $0.isEmpty ? nil : $0 }
let requireDWG = env["ARCUS_REQUIRE_DWG"] == "1"

if requireDWG && odaDir == nil {
    fatalError("""

    ─────────────────────────────────────────────────────────────────────────
    Arcus: ARCUS_REQUIRE_DWG=1 but ARCUS_ODA_SDK_DIR is not set.
    DWG import requires a licensed ODA Drawings SDK build for macOS arm64.
    See Docs/DWGSDKSetup.md for setup. Arcus never compiles fake DWG support.
    ─────────────────────────────────────────────────────────────────────────
    """)
}
if let odaDir, !FileManager.default.fileExists(atPath: odaDir + "/Kernel/Include") {
    fatalError("""

    Arcus: ARCUS_ODA_SDK_DIR=\(odaDir) does not look like an ODA Drawings SDK
    (missing Kernel/Include). See Docs/DWGSDKSetup.md.
    """)
}

let strictNoImports: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

var cadDependencies: [Target.Dependency] = ["ArcusGeometry", "ArcusDomain"]
var extraTargets: [Target] = []
var cadSwiftSettings = strictNoImports
if let odaDir {
    // ODA Drawings SDK layout (UNVERIFIED against a licensed SDK — see Docs/DWGSDKSetup.md). Library folder names depend on
    // the SDK release and toolchain (e.g. "macOsX_arm64_15.0"); set ARCUS_ODA_LIB_DIR to override the guesses below.
    // Newer SDKs split TD_Db into TD_DbCore/TD_DbEntities/TD_DbIO; add those names if the linker reports missing symbols.
    // If your SDK requires license activation, put the ODA-supplied activation header (OdActivationInfo) on an include path;
    // the bridge picks it up with __has_include.
    let odaLibDirs = env["ARCUS_ODA_LIB_DIR"].map { [$0] }
        ?? ["\(odaDir)/lib/macOsX_arm64_15.0dll", "\(odaDir)/lib/macOsX_arm64_15.0"]
    cadDependencies.append("ArcusDWGBridge")
    cadSwiftSettings.append(.define("ARCUS_HAS_ODA"))
    extraTargets.append(
        .target(
            name: "ArcusDWGBridge",
            path: "Arcus/Infrastructure/Exchange/DWGBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I\(odaDir)/Kernel/Include",
                    "-I\(odaDir)/Kernel/Extensions/ExServices",
                    "-I\(odaDir)/Drawing/Include",
                    "-I\(odaDir)/Drawing/Extensions/ExServices",
                    "-std=c++17",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags(odaLibDirs.map { "-L\($0)" }),
                // ExSystemServices/ExHostAppServices implementations (built from the SDK's ExServices sources).
                .linkedLibrary("TD_ExamplesCommon"),
                .linkedLibrary("TD_Db"), .linkedLibrary("TD_DbRoot"), .linkedLibrary("TD_Root"),
                .linkedLibrary("TD_Gi"), .linkedLibrary("TD_Ge"), .linkedLibrary("TD_Alloc"),
                .linkedLibrary("c++"), .linkedFramework("CoreFoundation"),
            ]
        )
    )
}

// Revit: direct .rvt/.rfa import needs the licensed ODA BimRv SDK (see Docs/RevitInterop.md). Without it Revit files can
// still be inspected (preview, release) and imported through the Arcus Bridge add-in (.arcusx) or IFC.
let bimRvDir = env["ARCUS_ODA_BIMRV_SDK_DIR"].flatMap { $0.isEmpty ? nil : $0 }
let requireRevit = env["ARCUS_REQUIRE_REVIT"] == "1"

if requireRevit && bimRvDir == nil {
    fatalError("""

    ─────────────────────────────────────────────────────────────────────────
    Arcus: ARCUS_REQUIRE_REVIT=1 but ARCUS_ODA_BIMRV_SDK_DIR is not set.
    Direct .rvt/.rfa import requires a licensed ODA BimRv SDK build for macOS arm64.
    See Docs/RevitInterop.md for setup. Arcus never compiles fake Revit support.
    ─────────────────────────────────────────────────────────────────────────
    """)
}
if let bimRvDir, !FileManager.default.fileExists(atPath: bimRvDir + "/Kernel/Include") {
    fatalError("""

    Arcus: ARCUS_ODA_BIMRV_SDK_DIR=\(bimRvDir) does not look like an ODA SDK
    (missing Kernel/Include). See Docs/RevitInterop.md.
    """)
}

var revitDependencies: [Target.Dependency] = ["ArcusGeometry", "ArcusCalc", "ArcusDomain"]
var revitSwiftSettings = strictNoImports
if let bimRvDir {
    // UNVERIFIED layout; adjust to your SDK release. Set ARCUS_ODA_BIMRV_LIB_DIR to the folder holding the SDK libraries.
    let libDirs = env["ARCUS_ODA_BIMRV_LIB_DIR"].map { [$0] }
        ?? ["\(bimRvDir)/lib/macOsX_arm64_15.0dll", "\(bimRvDir)/lib/macOsX_arm64_15.0"]
    revitDependencies.append("ArcusBimRvBridge")
    revitSwiftSettings.append(.define("ARCUS_HAS_ODA_BIMRV"))
    extraTargets.append(
        .target(
            name: "ArcusBimRvBridge",
            path: "Tools/RevitBridge/BimRvBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I\(bimRvDir)/Kernel/Include",
                    "-I\(bimRvDir)/Kernel/Extensions/ExServices",
                    "-I\(bimRvDir)/BimRv/Include",
                    "-I\(bimRvDir)/BimRv/Extensions/ExServices",
                    "-std=c++17",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags(libDirs.map { "-L\($0)" }),
                // Add the libraries your SDK's BimRv samples link (names differ between releases).
                .linkedLibrary("c++"), .linkedFramework("CoreFoundation"),
            ]
        )
    )
}

let package = Package(
    name: "Arcus",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Arcus", targets: ["Arcus"]),
        .executable(name: "arcus-bench", targets: ["ArcusBench"]),
    ],
    targets: [
        .target(name: "ArcusGeometry", path: "Arcus/Domain/Geometry", swiftSettings: strictNoImports),
        .target(name: "ArcusCalc", path: "Arcus/Domain/Calc", swiftSettings: strictNoImports),
        .target(
            name: "ArcusDomain",
            dependencies: ["ArcusGeometry", "ArcusCalc"],
            path: "Arcus/Domain",
            exclude: ["Geometry", "Calc"],
            swiftSettings: strictNoImports
        ),
        .target(
            name: "ArcusApplication",
            dependencies: ["ArcusGeometry", "ArcusCalc", "ArcusDomain"],
            path: "Arcus/Application",
            swiftSettings: strictNoImports
        ),
        .target(
            name: "ArcusPersistence",
            dependencies: ["ArcusDomain"],
            path: "Arcus/Infrastructure/Persistence",
            swiftSettings: strictNoImports,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ArcusIFC",
            dependencies: ["ArcusGeometry", "ArcusDomain"],
            path: "Arcus/Infrastructure/Exchange/IFC",
            swiftSettings: strictNoImports
        ),
        .target(
            name: "ArcusCAD",
            dependencies: cadDependencies,
            path: "Arcus/Infrastructure/Exchange/CAD",
            swiftSettings: cadSwiftSettings
        ),
        .target(
            name: "ArcusOutput",
            dependencies: ["ArcusGeometry", "ArcusDomain"],
            path: "Arcus/Infrastructure/Exchange/Output",
            swiftSettings: strictNoImports
        ),
        .target(
            name: "ArcusServices",
            dependencies: ["ArcusDomain", "ArcusPersistence"],
            path: "Arcus/Infrastructure",
            exclude: ["Persistence", "Exchange"],
            swiftSettings: strictNoImports
        ),
        .target(
            name: "ArcusRevit",
            dependencies: revitDependencies,
            path: "Arcus/Infrastructure/Exchange/Revit",
            swiftSettings: revitSwiftSettings
        ),
        .target(
            name: "ArcusCanvasMetal",
            dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusOutput"],
            path: "Arcus/UI/CanvasMetal",
            exclude: ["README.md"],
            swiftSettings: strictNoImports + [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "ArcusViewport3D",
            dependencies: ["ArcusGeometry", "ArcusDomain"],
            path: "Arcus/UI/Canvas3D",
            swiftSettings: strictNoImports + [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "ArcusUI",
            dependencies: [
                "ArcusGeometry", "ArcusCalc", "ArcusDomain", "ArcusApplication",
                "ArcusPersistence", "ArcusIFC", "ArcusCAD", "ArcusOutput", "ArcusServices", "ArcusViewport3D",
                "ArcusRevit", "ArcusCanvasMetal",
            ],
            path: "Arcus/UI",
            exclude: ["Canvas3D", "CanvasMetal"],
            resources: [.process("Resources")],
            swiftSettings: strictNoImports + [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Arcus",
            dependencies: ["ArcusUI"],
            path: "Arcus/App",
            swiftSettings: strictNoImports + [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "ArcusBench",
            dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusApplication", "ArcusPersistence", "ArcusIFC", "ArcusOutput"],
            path: "Arcus/Bench",
            swiftSettings: strictNoImports
        ),
        .testTarget(name: "RevitTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusRevit"], path: "Arcus/Tests/RevitTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "CanvasMetalTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusOutput", "ArcusCanvasMetal"], path: "Arcus/Tests/CanvasMetalTests"),
        .testTarget(name: "Viewport3DTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusViewport3D"], path: "Arcus/Tests/Viewport3DTests"),
        .testTarget(name: "GeometryTests", dependencies: ["ArcusGeometry"], path: "Arcus/Tests/GeometryTests"),
        .testTarget(name: "CalcTests", dependencies: ["ArcusCalc"], path: "Arcus/Tests/CalcTests"),
        .testTarget(
            name: "DomainTests",
            dependencies: ["ArcusGeometry", "ArcusCalc", "ArcusDomain", "ArcusApplication"],
            path: "Arcus/Tests/DomainTests"
        ),
        // POLISH: the Furniture Library suites (FM9, FM9B, FM9C build, flex and compile every piece, ~5 min) are kept out of
        // DomainTests so it stays fast. Run them with `swift test --filter LibraryTests`.
        .testTarget(
            name: "LibraryTests",
            dependencies: ["ArcusGeometry", "ArcusCalc", "ArcusDomain", "ArcusApplication"],
            path: "Arcus/Tests/LibraryTests"
        ),
        .testTarget(name: "IFCTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusIFC"], path: "Arcus/Tests/IFCTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "CADTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusCAD"], path: "Arcus/Tests/CADTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "OutputTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusOutput"], path: "Arcus/Tests/OutputTests"),
        .testTarget(name: "HomeUITests", dependencies: ["ArcusDomain", "ArcusApplication", "ArcusUI"], path: "Arcus/Tests/HomeUITests"), // HOME: offscreen renders of Home
        // FES: app-target (ArcusUI) views hosted offscreen: the Family Editor shell's layout regressions and captures.
        .testTarget(name: "UITests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusApplication", "ArcusUI"], path: "Arcus/Tests/UITests"),
        .testTarget(name: "PersistenceTests", dependencies: ["ArcusGeometry", "ArcusDomain", "ArcusPersistence", "ArcusServices"], path: "Arcus/Tests/PersistenceTests", resources: [.copy("Fixtures")]),
    ] + extraTargets,
    swiftLanguageModes: [.v6]
)
