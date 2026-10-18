import Foundation

public enum ScheduleKind: String, Codable, Sendable, CaseIterable {
    case category = "Schedule/Quantities"
    case multiCategory = "Multi-Category"
    case materialTakeoff = "Material Takeoff"
    case keySchedule = "Key Schedule"
    case sheetList = "Sheet List"
    case viewList = "View List"
    case revisionSchedule = "Revision Schedule"
    case noteBlock = "Note Block"
    case keynoteLegend = "Keynote Legend" // F12
}

public enum ScheduleFieldSource: Hashable, Codable, Sendable {
    /// A parameter of the scheduled element (instance first, then type).
    case parameter(ParameterID)
    /// A parameter of the element's material layer (material takeoffs): material name, area, volume.
    case material(String)
    /// Count of items in the row (1 per element when itemized).
    case count
    /// Calculated value using the formula language, referencing other field names.
    case formula(String, ParamType)
    /// Percentage of another field's total, optionally within the current grouping.
    case percentage(of: String, byGroup: Bool)
    /// Parameter of the room the element is in (e.g. "Room: Name").
    case roomParameter(ParameterID)
    /// Combine Parameters: several parameters' values in one column (ScheduleFormatting.swift). // F12
    case combined([ScheduleCombinedPart])
}

public enum ScheduleTotal: String, Codable, Sendable, CaseIterable {
    case none = "None", total = "Calculate totals", minimum = "Calculate minimum", maximum = "Calculate maximum", minAndMax = "Calculate minimum and maximum"
}

public enum HorizontalAlign: String, Codable, Sendable, CaseIterable { case left = "Left", center = "Center", right = "Right" }

public struct ConditionalFormat: Hashable, Codable, Sendable {
    public var op: FilterRule.Op
    public var value: ParamValue
    public var background: RGBColor
    public init(op: FilterRule.Op, value: ParamValue, background: RGBColor) { self.op = op; self.value = value; self.background = background }
}

public struct ScheduleField: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var source: ScheduleFieldSource
    public var heading: String
    public var hidden: Bool
    public var alignment: HorizontalAlign
    /// Column width on paper (meters).
    public var width: Double
    public var total: ScheduleTotal
    /// Display override: decimals for numeric fields (nil = project units).
    public var decimals: Int?
    public var conditionalFormat: ConditionalFormat?
    public init(source: ScheduleFieldSource, heading: String, width: Double = 0.025, alignment: HorizontalAlign = .left) {
        id = UUID().uuidString; self.source = source; self.heading = heading; hidden = false; self.alignment = alignment
        self.width = width; total = .none; decimals = nil; conditionalFormat = nil
    }
}

public struct ScheduleFilter: Hashable, Codable, Sendable {
    public var fieldID: String
    public var op: FilterRule.Op
    public var value: ParamValue
    public init(fieldID: String, op: FilterRule.Op, value: ParamValue) { self.fieldID = fieldID; self.op = op; self.value = value }
}

public struct ScheduleSort: Hashable, Codable, Sendable {
    public var fieldID: String
    public var ascending: Bool
    public var header: Bool
    public var footer: Bool
    public var footerShowsTitleCountTotals: Bool
    public var blankLine: Bool
    public init(fieldID: String, ascending: Bool = true, header: Bool = false, footer: Bool = false, blankLine: Bool = false) {
        self.fieldID = fieldID; self.ascending = ascending; self.header = header; self.footer = footer
        footerShowsTitleCountTotals = true; self.blankLine = blankLine
    }
}

/// A live schedule definition. Rows are always computed from the model.
public struct ScheduleDefinition: Hashable, Codable, Sendable {
    public var kind: ScheduleKind
    /// Scheduled categories (one for category schedules, several for multi-category).
    public var categories: [Category]
    public var fields: [ScheduleField]
    public var filters: [ScheduleFilter]
    public var sorting: [ScheduleSort]
    public var itemizeEveryInstance: Bool
    public var grandTotals: Bool
    public var grandTotalTitle: String
    public var showTitle: Bool
    public var showHeaders: Bool
    /// Phase filter & phase (nil = latest phase).
    public var phaseID: ElementID?
    public var phaseFilter: PhaseFilter
    /// Include elements in linked files (not supported for links; kept false).
    public var includeLinks: Bool
    /// Appearance (grid lines, text sizes, shading) and header groups; optional so older documents decode unchanged.
    /// Read and write them through `appearance` and `headerGroups` (ScheduleEditing.swift). // BL-SCHED
    var appearanceStorage: ScheduleAppearance?
    var headerGroupStorage: [ScheduleHeaderGroup]?
    /// Header rows, cell styles, title image and Freeze Header; read and write through `formatting`. // F12
    var formattingStorage: ScheduleFormatting?
    public init(kind: ScheduleKind, categories: [Category], fields: [ScheduleField] = []) {
        self.kind = kind; self.categories = categories; self.fields = fields; filters = []; sorting = []
        itemizeEveryInstance = true; grandTotals = false; grandTotalTitle = "Grand total"; showTitle = true; showHeaders = true
        phaseID = nil; phaseFilter = .showAll; includeLinks = false
    }
}
