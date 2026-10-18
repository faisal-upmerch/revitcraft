import Foundation
import ArcusDomain

/// One page of a PDF export: a sheet at its paper size, or a view/schedule on `PDFExportJob.viewPaper`.
public struct PDFExportItem: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case sheet, view }
    public var elementID: ElementID
    public var kind: Kind
    public init(elementID: ElementID, kind: Kind) { self.elementID = elementID; self.kind = kind }
    public static func sheet(_ id: ElementID) -> PDFExportItem { PDFExportItem(elementID: id, kind: .sheet) }
    public static func view(_ id: ElementID) -> PDFExportItem { PDFExportItem(elementID: id, kind: .view) }
}

/// File naming for individual PDFs.
public enum PDFNaming: Sendable, Hashable {
    /// Sheets: "A101 - Ground Floor Plan"; views: "Floor Plan - Level 1".
    case sheetNumberAndName
    /// The sheet or view name alone.
    case viewName
    /// Template with tokens {Project Number} {Project Name} {Sheet Number} {Sheet Name} {View Name} {Date} (yyyy-MM-dd).
    /// For a view, {Sheet Number}/{Sheet Name} are those of the sheet it is placed on (empty if none);
    /// for a sheet, {View Name} is the sheet name.
    case custom(String)
}

/// What to do when a destination file already exists.
public enum OverwritePolicy: Sendable {
    /// Replace existing files (atomically, after every page has rendered).
    case replace
    /// Leave existing files alone and do not render their pages; they are reported in `skippedExisting`.
    case skip
    /// Write "Name (2).pdf", "Name (3).pdf"… instead.
    case uniquify
    /// Throw `PDFExportError` listing the conflicts before rendering anything.
    case fail
}

public struct PDFExportJob: Sendable {
    public var items: [PDFExportItem]
    /// One multi-page PDF (true) or one file per item (false).
    public var combined = true
    public var combinedFileName = "Arcus Set.pdf"
    public var naming: PDFNaming = .sheetNumberAndName
    public var outputDirectory: URL
    public var overwrite: OverwritePolicy = .fail
    /// Paper for views exported without a sheet.
    public var viewPaper: PaperSize = .a3
    public var viewLandscape = true
    /// `.fit` scales a view to the printable area (10 mm margins); `.actual` prints it at its own scale, centered.
    public var zoom: Zoom = .fit
    public enum Zoom: Sendable, Hashable { case fit, actual }
    /// One bookmark per page ("A101 – Ground Floor Plan").
    public var bookmarks = true
    /// View markers (section/elevation/callout heads) link to the page where their target view is placed.
    public var internalLinks = true
    /// Exclude the overlay layer (crop boundaries, guide grids).
    public var hideCropBoundaries = true
    /// F13: Print Setup options (PrintFiltering.swift): leave out reference planes, scope boxes and the tags of views
    /// not placed on a sheet; print in color, black lines or grayscale.
    public var hideReferencePlanes = false
    public var hideScopeBoxes = false
    public var hideUnreferencedViewTags = false
    public var colors: PrintSetup.Colors = .color
    /// PDF Creator metadata. No user or account name is ever written.
    public var creator = "Arcus"
    public init(items: [PDFExportItem], outputDirectory: URL) {
        self.items = items
        self.outputDirectory = outputDirectory
    }
}

public struct PDFExportResult: Sendable {
    /// Files written, in job order.
    public var files: [URL]
    public var pageCount: Int
    /// Pages written as vector graphics and real text.
    public var vectorPages: Int
    /// Pages that had to be rasterized. The exporter never rasterizes, so this is always 0; kept so the UI can disclose it.
    public var rasterPages: Int
    /// Existing files left untouched under `OverwritePolicy.skip`.
    public var skippedExisting: [URL]
    public var warnings: [String]
    public var elapsed: TimeInterval
}

public struct PDFExportError: Error, Sendable, CustomStringConvertible {
    public var message: String
    /// Existing files that blocked the export (`OverwritePolicy.fail`).
    public var conflicts: [URL]
    public init(_ message: String, conflicts: [URL] = []) { self.message = message; self.conflicts = conflicts }
    public var description: String { message }
}
