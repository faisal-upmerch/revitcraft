import Foundation
import Testing
@testable import ArcusRevit

@Suite("Revit file inspector")
struct RevitInspectorTests {
    @Test(arguments: [3, 4])
    func inspectsSyntheticProject(version: Int) throws {
        let data = TestData.revitContainer(majorVersion: version)
        let info = try RevitFileInspector.inspect(data: data, fileName: "Small House.rvt")
        #expect(info.kind == .project)
        #expect(info.kindEvidence.contains(".rvt"))
        #expect(info.revitRelease == "2024")
        #expect(info.productName?.hasPrefix("Autodesk Revit 2024") == true)
        #expect(info.buildString == "20230308_1635(x64)")
        #expect(info.previewPNG == TestData.png())
        #expect(info.streamNames.contains("RevitPreview4.0"))
        #expect(info.streamNames.contains("BasicFileInfo"))
        #expect(info.streamNames.contains("Formats/Latest"))
        #expect(info.containerVersion == version)
        #expect(info.fileSize == data.count)
        #expect(info.basicFileInfoText.contains("Format: 2024"))
        #expect(info.notes.isEmpty)
    }

    @Test func kindFromExtensionAndText() throws {
        let data = TestData.revitContainer(info: ["Autodesk Revit 2023", "D:\\Library\\Door - Single.rfa"])
        #expect(try RevitFileInspector.inspect(data: data, fileName: "Door.rfa").kind == .family)
        #expect(try RevitFileInspector.inspect(data: data, fileName: "Template.rte").kind == .template)
        #expect(try RevitFileInspector.inspect(data: data, fileName: "Family Template.rft").kind == .template)
        // Unknown extension: the saved file name in the text decides.
        let renamed = try RevitFileInspector.inspect(data: data, fileName: "download.bin")
        #expect(renamed.kind == .family)
        #expect(renamed.kindEvidence.contains("Door - Single.rfa"))
        #expect(renamed.revitRelease == "2023")
        // Extension and text disagree: extension wins, with a note.
        let mismatch = try RevitFileInspector.inspect(data: data, fileName: "Door.rvt")
        #expect(mismatch.kind == .project)
        #expect(mismatch.notes.contains { $0.contains("Door - Single.rfa") })
    }

    @Test func formatStringWinsOverProductString() throws {
        let data = TestData.revitContainer(info: ["Autodesk Revit 2025", "Format: 2022"])
        #expect(try RevitFileInspector.inspect(data: data, fileName: "Old.rvt").revitRelease == "2022")
    }

    @Test func unknownKindAndNoReleaseWhenTextIsSilent() throws {
        let data = TestData.revitContainer(info: ["nothing useful here"])
        let info = try RevitFileInspector.inspect(data: data, fileName: "mystery.dat")
        #expect(info.kind == .unknown)
        #expect(info.revitRelease == nil)
    }

    @Test func missingOrBrokenPreview() throws {
        let none = try RevitFileInspector.inspect(data: TestData.revitContainer(preview: nil), fileName: "a.rvt")
        #expect(none.previewPNG == nil)
        #expect(none.notes.contains { $0.contains("PNG") })
        // PNG cut off before IEND.
        let cut = TestData.png().prefix(30)
        let broken = try RevitFileInspector.inspect(data: TestData.revitContainer(preview: Data(cut)), fileName: "a.rvt")
        #expect(broken.previewPNG == nil)
    }

    @Test func extractPNGValidatesChunks() {
        let png = TestData.png()
        #expect(RevitFileInspector.extractPNG(Data([1, 2, 3]) + png + Data([9, 9])) == png)
        #expect(RevitFileInspector.extractPNG(Data([1, 2, 3])) == nil)
        // Signature followed by a non-IHDR chunk.
        var bad = Data(png.prefix(8))
        bad.append(contentsOf: [0, 0, 0, 0, 0x49, 0x44, 0x41, 0x54, 0, 0, 0, 0])
        #expect(RevitFileInspector.extractPNG(bad) == nil)
        // Chunk length pointing past the end.
        var huge = Data(png.prefix(8))
        huge.append(contentsOf: [0x7F, 0xFF, 0xFF, 0xFF, 0x49, 0x48, 0x44, 0x52])
        #expect(RevitFileInspector.extractPNG(huge) == nil)
    }

    @Test func textScanFindsBothAlignments() {
        var d = Data([0x01])
        d.append(TestData.utf16LE("Format: 2021"))
        d.append(contentsOf: [0x00, 0x00, 0x05])
        d.append(TestData.utf16LE("Build: X"))
        let strings = RevitFileInspector.utf16Strings(d)
        #expect(strings.contains("Format: 2021"))
        // A stray byte before an even-aligned string may read as a letter; parsing matches within strings.
        #expect(strings.contains { $0.hasSuffix("Build: X") })
    }

    @Test func nonRevitFilesAreReportedClearly() {
        do {
            _ = try RevitFileInspector.inspect(data: Data("not a revit file at all".utf8), fileName: "notes.rvt")
            Issue.record("expected an error")
        } catch {
            #expect(error.message.contains("not a Revit file"))
        }
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).rvt")
        #expect(throws: RevitInspectionError.self) { try RevitFileInspector.inspect(url) }
    }

    @Test func inspectsFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-inspect-\(UUID().uuidString).rfa")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestData.revitContainer(majorVersion: 4).write(to: url)
        let info = try RevitFileInspector.inspect(url)
        #expect(info.kind == .family)
        #expect(info.previewPNG != nil)
        #expect(info.fileSize > 0)
    }
}
