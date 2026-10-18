import Foundation
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence
@testable import ArcusServices

@Suite("Diagnostics")
struct DiagnosticsTests {
    func makeLog(capacity: Int = 100) -> DiagnosticsLog {
        DiagnosticsLog(subsystem: "com.local.arcus.tests", capacity: capacity, timingCapacity: 3,
                       homeDirectory: "/Users/jappleseed", userNames: ["jappleseed", "Johnny Appleseed"])
    }

    @Test func ringBufferKeepsNewestInOrder() {
        let log = makeLog(capacity: 3)
        for i in 1...5 { log.log("Test", "message \(i)") }
        #expect(log.entries.map(\.message) == ["message 3", "message 4", "message 5"])
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test func timingsAreBounded() {
        let log = makeLog()
        for i in 1...5 { log.recordTiming("t\(i)", seconds: Double(i)) }
        #expect(log.recentTimings.map(\.name) == ["t3", "t4", "t5"])
        #expect(log.recentTimings.map(\.seconds) == [3, 4, 5])
    }

    @Test func exportRemovesHomePathsUserNamesAndProjectNames() {
        let log = makeLog()
        log.registerProjectName("Secret Tower")
        log.log("Document", "Opened /Users/jappleseed/Documents/Clients/Secret Tower.arcus in 0.2 s")
        log.log("Document", "Autosaved project Secret Tower")
        log.log("Import", "Imported /Users/otherperson/Desktop/site-survey.dwg (2 layers)")
        log.log("Account", "Signed in as Johnny Appleseed (JAPPLESEED)")
        log.log("Paths", "Temp at /private/Users/jappleseed/tmp")
        log.recordTiming("Open Secret Tower.arcus", seconds: 0.25)
        let text = log.exportRedacted()
        for secret in ["jappleseed", "JAPPLESEED", "Johnny", "Appleseed", "Secret Tower", "otherperson", "site-survey", "Clients/Secret"] {
            #expect(!text.contains(secret), "leaked \(secret)")
        }
        #expect(text.contains("~/Documents/Clients/<file>.arcus"))
        #expect(text.contains("~/Desktop/<file>.dwg"))
        #expect(text.contains("<project>"))
        #expect(text.contains("<user>"))
        #expect(text.contains("0.2500 s"))
        // Opting in keeps project and file names (still no home path or account names).
        let named = log.exportRedacted(includeProjectNames: true)
        #expect(named.contains("Secret Tower"))
        #expect(!named.contains("jappleseed"))
        #expect(!named.contains("/Users/"))
    }

    @Test func longMessagesAreTruncated() {
        let log = makeLog()
        log.log("Test", String(repeating: "x", count: 10_000))
        #expect(log.entries[0].message.count <= DiagnosticsLog.maxMessageLength + 1)
    }

    @Test func concurrentLoggingIsSafe() {
        let log = makeLog(capacity: 500)
        DispatchQueue.concurrentPerform(iterations: 8) { t in
            for i in 0..<250 { log.log("T\(t)", "m\(i)"); log.recordTiming("x", seconds: 0) }
        }
        #expect(log.entries.count == 500)
        #expect(log.recentTimings.count == 3)
    }

    @Test func signpostsRecordTimings() async throws {
        let log = makeLog()
        let v = Signposts.interval("Unit work", log: log) { 21 * 2 }
        #expect(v == 42)
        let w = try await Signposts.intervalAsync("Async work", log: log) { () async throws -> String in
            try await Task.sleep(for: .milliseconds(10))
            return "done"
        }
        #expect(w == "done")
        #expect(throws: CocoaError.self) { try Signposts.interval("Failing", log: log) { throw CocoaError(.fileNoSuchFile) } }
        let names = log.recentTimings.map(\.name)
        #expect(names == ["Unit work", "Async work", "Failing"])
        #expect(log.recentTimings[1].seconds >= 0.009)
    }

    @Test func sharedInstanceExists() {
        DiagnosticsLog.shared.log("Tests", "hello")
        #expect(DiagnosticsLog.shared.entries.contains { $0.message == "hello" })
    }
}

@Suite("Versioning and updates")
struct VersioningTests {
    @Test func localOnlyUpdateProviderIsNeverEnabled() async {
        let p = LocalOnlyUpdateProvider()
        #expect(!p.isEnabled)
        #expect(p.statusMessage.contains("Arcus.app"))
        #expect(p.statusMessage.contains("never"))
        let r = await p.checkForUpdates()
        #expect(r == .disabled(p.statusMessage))
        let any: any UpdateProvider = p
        #expect(!any.isEnabled)
    }

    @Test func appVersionFallsBackOutsideTheArcusBundle() {
        let v = AppVersionInfo.current
        #expect(v.marketingVersion == AppVersionInfo.fallbackMarketingVersion)
        #expect(v.build == AppVersionInfo.fallbackBuild)
        #expect(v.documentSchema == ArcusPackage.currentSchemaVersion)
    }

    @Test func appVersionReadsArcusInfoPlist() {
        let v = AppVersionInfo.from(infoDictionary: ["CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "812"], bundleIdentifier: "com.local.arcus")
        #expect(v.marketingVersion == "1.4.0" && v.build == "812")
        let missing = AppVersionInfo.from(infoDictionary: [:], bundleIdentifier: "com.local.arcus")
        #expect(missing.marketingVersion == "0.0.0" && missing.build == "dev")
        let foreign = AppVersionInfo.from(infoDictionary: ["CFBundleShortVersionString": "16.0"], bundleIdentifier: "com.apple.xctest")
        #expect(foreign.marketingVersion == "0.0.0")
        let info = v.writeInfo(documentID: Sample.info.documentID)
        #expect(info.appVersion == "1.4.0" && info.build == "812")
        #expect(v.description.contains("1.4.0"))
    }

    @Test func versionComparison() {
        #expect(AppVersionInfo.compare("1.10.0", "1.9.2") == .orderedDescending)
        #expect(AppVersionInfo.compare("1.0", "1.0.0") == .orderedSame)
        #expect(AppVersionInfo.compare("0.9.0", "1.0.0") == .orderedAscending)
        #expect(AppVersionInfo.compare("2.0.0-beta", "2.0.0") == .orderedSame)
    }
}

@Suite("External change detection")
struct ExternalChangeTests {
    @Test func detectsResaveOfPackage() async throws {
        let tmp = TempDir()
        let url = tmp.file("Ext.arcus")
        try ArcusPackage.write(try Sample.richModel(), to: url, info: Sample.info)
        let fp = try #require(ExternalChangeDetector.fingerprint(url))
        #expect(fp.documentID == Sample.info.documentID)
        #expect(fp.size > 1000)
        #expect(!ExternalChangeDetector.hasChanged(url, since: fp))
        try await Task.sleep(for: .milliseconds(5))
        try ArcusPackage.write(BIMModel(), to: url, info: Sample.info)
        #expect(ExternalChangeDetector.hasChanged(url, since: fp))
        let fp2 = try #require(ExternalChangeDetector.fingerprint(url))
        #expect(!fp2.sameDocumentState(as: fp))
        try FileManager.default.removeItem(at: url)
        #expect(ExternalChangeDetector.hasChanged(url, since: fp2))
        #expect(ExternalChangeDetector.fingerprint(url) == nil)
    }

    @Test func detectsChangesToPlainFilesAndFamilies() async throws {
        let tmp = TempDir()
        let file = tmp.file("notes.csv")
        try Data("a,b".utf8).write(to: file)
        let fp = try #require(ExternalChangeDetector.fingerprint(file))
        #expect(fp.documentID == nil)
        #expect(!ExternalChangeDetector.hasChanged(file, since: fp))
        try Data("a,b,c".utf8).write(to: file)
        #expect(ExternalChangeDetector.hasChanged(file, since: fp))

        let fam = tmp.file("Door.arcusfamily")
        try FamilyPackage.write(StarterLibrary.singleDoor(), thumbnailPNG: nil, to: fam, appVersion: "1", build: "1")
        let ffp = try #require(ExternalChangeDetector.fingerprint(fam))
        #expect(ffp.documentID != nil)
        try await Task.sleep(for: .milliseconds(5))
        try FamilyPackage.write(StarterLibrary.doubleDoor(), thumbnailPNG: nil, to: fam, appVersion: "1", build: "1")
        #expect(ExternalChangeDetector.hasChanged(fam, since: ffp))
    }
}
