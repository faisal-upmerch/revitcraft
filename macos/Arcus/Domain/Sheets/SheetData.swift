import Foundation
import ArcusGeometry

/// Paper sizes in meters (width × height in landscape orientation).
public enum PaperSize: String, Codable, Sendable, CaseIterable {
    case a0 = "A0", a1 = "A1", a2 = "A2", a3 = "A3", a4 = "A4"
    case archD = "ARCH D", archE = "ARCH E", archC = "ARCH C", ansiB = "ANSI B (Tabloid)", letter = "Letter"

    public var landscapeSize: Vec2 {
        switch self {
        case .a0: Vec2(1.189, 0.841)
        case .a1: Vec2(0.841, 0.594)
        case .a2: Vec2(0.594, 0.420)
        case .a3: Vec2(0.420, 0.297)
        case .a4: Vec2(0.297, 0.210)
        case .archD: Vec2(0.9144, 0.6096)
        case .archE: Vec2(1.2192, 0.9144)
        case .archC: Vec2(0.6096, 0.4572)
        case .ansiB: Vec2(0.4318, 0.2794)
        case .letter: Vec2(0.2794, 0.2159)
        }
    }
    public var isMetric: Bool { [.a0, .a1, .a2, .a3, .a4].contains(self) }
}

public struct SheetData: Hashable, Codable, Sendable {
    /// Sheet number (unique within the project). The sheet name is `Element.name`.
    public var number: String
    /// Title block type element.
    public var titleBlockTypeID: ElementID?
    public var paper: PaperSize
    public var issueDate: String
    public var drawnBy: String
    public var checkedBy: String
    public var designedBy: String
    public var approvedBy: String
    /// Revisions explicitly shown on this sheet (in addition to those with clouds on the sheet's views).
    public var additionalRevisionIDs: [ElementID]
    /// Guide grid spacing on paper (meters); nil = no guide grid.
    public var guideGridSpacing: Double?
    /// Placeholder sheets appear in sheet lists but have no drawing area content.
    public var isPlaceholder: Bool
    public var appearsInSheetList: Bool
    public init(number: String, paper: PaperSize = .a1, titleBlockTypeID: ElementID? = nil) {
        self.number = number; self.titleBlockTypeID = titleBlockTypeID; self.paper = paper; issueDate = ""; drawnBy = "Author"
        checkedBy = "Checker"; designedBy = "Designer"; approvedBy = "Approver"; additionalRevisionIDs = []
        guideGridSpacing = nil; isPlaceholder = false; appearsInSheetList = true
    }
}

/// A view or schedule placed on a sheet. The owning sheet is `Element.ownerViewID`.
public struct ViewportData: Hashable, Codable, Sendable {
    public var viewID: ElementID
    /// Center of the viewport on the sheet (paper meters from the sheet's lower-left corner).
    public var center: Vec2
    public var showTitle: Bool
    public var detailNumber: String
    /// Offset of the viewport title from the bottom-left of the viewport box.
    public var titleOffset: Vec2
    /// Title line length override (paper meters); nil = fit to title.
    public var titleLineLength: Double?
    /// Split & Place: the rows of a schedule this viewport shows (nil = all). Optional: older files decode as nil. // F12
    public var scheduleRows: ScheduleRowRange?
    public init(viewID: ElementID, center: Vec2, detailNumber: String) {
        self.viewID = viewID; self.center = center; showTitle = true; self.detailNumber = detailNumber
        titleOffset = Vec2(0, -0.012); titleLineLength = nil
    }
}

/// A named set of sheets/views for printing and export.
public struct ViewSheetSet: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var members: [ElementID]
    public init(name: String, members: [ElementID]) { id = UUID().uuidString; self.name = name; self.members = members }
}
