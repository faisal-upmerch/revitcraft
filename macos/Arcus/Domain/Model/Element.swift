import Foundation
import Synchronization
import ArcusGeometry

extension ParameterID: CodingKeyRepresentable {
    public var codingKey: any CodingKey { StringKey(stringValue: key) }
    public init?<T: CodingKey>(codingKey: T) { self.init(codingKey.stringValue) }
}

struct StringKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Classification reference (e.g. Uniclass, OmniClass, custom system).
public struct Classification: Hashable, Codable, Sendable {
    public var system: String
    public var code: String
    public var title: String
    public init(system: String, code: String, title: String = "") { self.system = system; self.code = code; self.title = title }
}

/// Where an element came from when it was created by an import (IFC or CAD).
public struct SourceMetadata: Hashable, Codable, Sendable {
    public var format: String          // "IFC4", "IFC2X3", "DXF", "DWG"
    public var fileName: String
    public var originalID: String      // IFC GlobalId, CAD entity handle
    public var originalType: String    // IfcWallStandardCase, LWPOLYLINE…
    public var layer: String?
    public var attributes: [String: String]
    public init(format: String, fileName: String, originalID: String, originalType: String, layer: String? = nil, attributes: [String: String] = [:]) {
        self.format = format; self.fileName = fileName; self.originalID = originalID; self.originalType = originalType
        self.layer = layer; self.attributes = attributes
    }
}

/// A model element: common identity and relationships plus kind-specific data.
///
/// Elements are immutable values inside a model snapshot. All changes go through
/// `TransactionContext`, which records before/after values for undo and persistence.
public struct Element: Hashable, Codable, Sendable, Identifiable {
    public var id: ElementID
    public var ifcGUID: IFCGUID
    public var category: Category
    /// Name for named elements (levels, views, sheets, types, materials, rooms…).
    public var name: String
    public var typeID: ElementID?
    /// Base/associated level.
    public var levelID: ElementID?
    /// Host element (wall for doors/windows, stair for railings, view for view-specific elements is `ownerViewID`).
    public var hostID: ElementID?
    /// For view-specific elements (annotations, detail items), the owning view or sheet.
    public var ownerViewID: ElementID?
    public var phaseCreated: ElementID?
    public var phaseDemolished: ElementID?
    public var designOptionID: ElementID?
    public var groupID: ElementID?
    public var pinned: Bool
    /// User parameter values and free-form built-in text values (Mark, Comments…).
    public var params: [ParameterID: ParamValue]
    public var classification: Classification?
    public var source: SourceMetadata?
    public var data: ElementData
    /// Content stamp for derived-data caches, replaced with a fresh process-unique value whenever the element is
    /// created or changed by a commit. `(id, revision)` therefore identifies one exact content: undo restores an
    /// earlier (element, revision) pair unchanged, and a later different edit can never reuse a revision. Values are
    /// seeded from the clock (milliseconds << 20), so stamps from earlier sessions stored in files or recovery
    /// journals cannot collide with stamps issued later.
    public var revision: UInt64

    private static let revisionCounter = Atomic<UInt64>(UInt64(max(0, Date().timeIntervalSince1970 * 1000)) << 20)
    /// A fresh, process-unique, monotonically increasing revision stamp.
    public static func nextRevision() -> UInt64 { revisionCounter.add(1, ordering: .relaxed).newValue }
    /// Revisions below this were written by builds that numbered revisions per element (1, 2, 3…); they are
    /// re-stamped when a model is loaded.
    public static let legacyRevisionLimit: UInt64 = 1 << 40

    public init(id: ElementID, category: Category, name: String = "", data: ElementData, typeID: ElementID? = nil,
                levelID: ElementID? = nil, hostID: ElementID? = nil, ownerViewID: ElementID? = nil, ifcGUID: IFCGUID? = nil) {
        self.id = id
        self.ifcGUID = ifcGUID ?? .random()
        self.category = category
        self.name = name
        self.typeID = typeID
        self.levelID = levelID
        self.hostID = hostID
        self.ownerViewID = ownerViewID
        self.phaseCreated = nil
        self.phaseDemolished = nil
        self.designOptionID = nil
        self.groupID = nil
        self.pinned = false
        self.params = [:]
        self.classification = nil
        self.source = nil
        self.data = data
        self.revision = Element.nextRevision()
    }

    public var kind: ElementKind { data.kind }
    public var isType: Bool { if case .type = data { return true }; return false }
    public var isViewSpecific: Bool { ownerViewID != nil }

    public subscript(param id: ParameterID) -> ParamValue? {
        get { params[id] }
        set { params[id] = newValue }
    }
    public var mark: String {
        get { params[.mark]?.textValue ?? "" }
        set { params[.mark] = newValue.isEmpty ? nil : .text(newValue) }
    }
    public var comments: String {
        get { params[.comments]?.textValue ?? "" }
        set { params[.comments] = newValue.isEmpty ? nil : .text(newValue) }
    }
}

extension ParameterID {
    public static let mark = ParameterID("mark")
    public static let comments = ParameterID("comments")
    /// Painted material override (element surfaces).
    public static let paintMaterial = ParameterID("paint.material")
}

/// Discriminator for `ElementData`.
public enum ElementKind: String, Codable, Sendable, CaseIterable {
    case level, grid, referencePlane, wall, insert, component, column, beam, slab, roof, stair, railing, room
    case modelLine, topography, view, sheet, viewport, schedule, dimension, tag, textNote, spot, filledRegion
    case detailComponent, revisionCloud, insulation, revision, type, family, material, phase, designOption
    case group, link, referenceGeometry, constraint, projectInfo, viewTemplate, filter, lineStyle, fillPattern, areaScheme
    case scopeBox // WP6a
    case colorScheme, colorFillLegend
    case ramp
    case opening // WP3

    // RevitCraft port feature batches: each adds its kinds right after its marker.
    // F1 element kinds:


    // F2 element kinds:


    // F34 element kinds:


    // F5 element kinds:


    // F67 element kinds:


    // F810 element kinds:


    // F11 element kinds:


    // F1415 element kinds:


}

/// Kind-specific element data.
public enum ElementData: Hashable, Codable, Sendable {
    case level(LevelData)
    case grid(GridData)
    case referencePlane(ReferencePlaneData)
    case wall(WallData)
    /// Hosted inserts: doors and windows (and hosted components).
    case insert(InsertData)
    /// Free-standing loadable family instance: furniture, casework, generic models, fixtures.
    case component(ComponentData)
    case column(ColumnData)
    case beam(BeamData)
    /// Floors, ceilings, building pads.
    case slab(SlabData)
    case roof(RoofData)
    case stair(StairData)
    case railing(RailingData)
    /// Rooms and areas.
    case room(RoomData)
    /// Room separation, area boundary, property and detail lines.
    case modelLine(ModelLineData)
    case topography(TopographyData)
    case view(ViewData)
    case sheet(SheetData)
    case viewport(ViewportData)
    case schedule(ScheduleDefinition)
    case dimension(DimensionData)
    case tag(TagData)
    case textNote(TextNoteData)
    case spot(SpotData)
    case filledRegion(FilledRegionData)
    case detailComponent(DetailComponentData)
    case revisionCloud(RevisionCloudData)
    case insulation(InsulationData)
    case revision(RevisionData)
    case type(TypeData)
    case family(FamilyDefinition)
    case material(MaterialData)
    case phase(PhaseData)
    case designOption(DesignOptionData)
    case group(GroupData)
    case link(LinkData)
    case referenceGeometry(ReferenceGeometryData)
    case constraint(ConstraintData)
    case projectInfo(ProjectInfoData)
    case viewTemplate(ViewTemplateData)
    case filter(ViewFilterData)
    case lineStyle(LineStyleData)
    case fillPattern(FillPatternData)
    case areaScheme(AreaSchemeData)
    /// Wall openings and shafts.
    case opening(OpeningData)
    case ramp(RampData)
    /// Scope boxes (plan rectangle with a height range) that limit datums and crop views.
    case scopeBox(ScopeBoxData)
    /// Colour fill scheme for rooms or areas (by parameter value or range).
    case colorScheme(ColorSchemeData)
    /// View-specific legend listing the colour fill values in use.
    case colorFillLegend(ColorFillLegendData)

    // RevitCraft port feature batches: each adds its cases right after its marker.
    // F1 element data:


    // F2 element data:


    // F34 element data:


    // F5 element data:


    // F67 element data:


    // F810 element data:


    // F11 element data:


    // F1415 element data:



    public var kind: ElementKind {
        switch self {
        case .level: .level
        case .grid: .grid
        case .referencePlane: .referencePlane
        case .wall: .wall
        case .insert: .insert
        case .component: .component
        case .column: .column
        case .beam: .beam
        case .slab: .slab
        case .roof: .roof
        case .stair: .stair
        case .railing: .railing
        case .room: .room
        case .modelLine: .modelLine
        case .topography: .topography
        case .view: .view
        case .sheet: .sheet
        case .viewport: .viewport
        case .schedule: .schedule
        case .dimension: .dimension
        case .tag: .tag
        case .textNote: .textNote
        case .spot: .spot
        case .filledRegion: .filledRegion
        case .detailComponent: .detailComponent
        case .revisionCloud: .revisionCloud
        case .insulation: .insulation
        case .revision: .revision
        case .type: .type
        case .family: .family
        case .material: .material
        case .phase: .phase
        case .designOption: .designOption
        case .group: .group
        case .link: .link
        case .referenceGeometry: .referenceGeometry
        case .constraint: .constraint
        case .projectInfo: .projectInfo
        case .viewTemplate: .viewTemplate
        case .filter: .filter
        case .lineStyle: .lineStyle
        case .fillPattern: .fillPattern
        case .areaScheme: .areaScheme
        case .scopeBox: .scopeBox // WP6a
        case .colorScheme: .colorScheme
        case .colorFillLegend: .colorFillLegend
        case .ramp: .ramp
        case .opening: .opening
        // RevitCraft port feature batches: each adds its cases right after its marker.
        // F1 element data kinds:


        // F2 element data kinds:


        // F34 element data kinds:


        // F5 element data kinds:


        // F67 element data kinds:


        // F810 element data kinds:


        // F11 element data kinds:


        // F1415 element data kinds:


        }
    }
}

// MARK: - Typed accessors

extension Element {
    public var level: LevelData? {
        get { if case .level(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .level(v) } }
    }
    public var grid: GridData? {
        get { if case .grid(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .grid(v) } }
    }
    public var referencePlane: ReferencePlaneData? {
        get { if case .referencePlane(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .referencePlane(v) } }
    }
    public var wall: WallData? {
        get { if case .wall(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .wall(v) } }
    }
    public var insert: InsertData? {
        get { if case .insert(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .insert(v) } }
    }
    public var component: ComponentData? {
        get { if case .component(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .component(v) } }
    }
    public var column: ColumnData? {
        get { if case .column(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .column(v) } }
    }
    public var beam: BeamData? {
        get { if case .beam(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .beam(v) } }
    }
    public var slab: SlabData? {
        get { if case .slab(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .slab(v) } }
    }
    public var roof: RoofData? {
        get { if case .roof(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .roof(v) } }
    }
    public var stair: StairData? {
        get { if case .stair(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .stair(v) } }
    }
    public var railing: RailingData? {
        get { if case .railing(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .railing(v) } }
    }
    public var room: RoomData? {
        get { if case .room(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .room(v) } }
    }
    public var modelLine: ModelLineData? {
        get { if case .modelLine(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .modelLine(v) } }
    }
    public var topography: TopographyData? {
        get { if case .topography(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .topography(v) } }
    }
    public var view: ViewData? {
        get { if case .view(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .view(v) } }
    }
    public var sheet: SheetData? {
        get { if case .sheet(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .sheet(v) } }
    }
    public var viewport: ViewportData? {
        get { if case .viewport(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .viewport(v) } }
    }
    public var schedule: ScheduleDefinition? {
        get { if case .schedule(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .schedule(v) } }
    }
    public var dimension: DimensionData? {
        get { if case .dimension(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .dimension(v) } }
    }
    public var tag: TagData? {
        get { if case .tag(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .tag(v) } }
    }
    public var textNote: TextNoteData? {
        get { if case .textNote(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .textNote(v) } }
    }
    public var spot: SpotData? {
        get { if case .spot(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .spot(v) } }
    }
    public var filledRegion: FilledRegionData? {
        get { if case .filledRegion(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .filledRegion(v) } }
    }
    public var detailComponent: DetailComponentData? {
        get { if case .detailComponent(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .detailComponent(v) } }
    }
    public var revisionCloud: RevisionCloudData? {
        get { if case .revisionCloud(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .revisionCloud(v) } }
    }
    public var insulation: InsulationData? {
        get { if case .insulation(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .insulation(v) } }
    }
    public var revisionData: RevisionData? {
        get { if case .revision(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .revision(v) } }
    }
    public var typeData: TypeData? {
        get { if case .type(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .type(v) } }
    }
    public var family: FamilyDefinition? {
        get { if case .family(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .family(v) } }
    }
    public var material: MaterialData? {
        get { if case .material(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .material(v) } }
    }
    public var phase: PhaseData? {
        get { if case .phase(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .phase(v) } }
    }
    public var designOption: DesignOptionData? {
        get { if case .designOption(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .designOption(v) } }
    }
    public var group: GroupData? {
        get { if case .group(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .group(v) } }
    }
    public var link: LinkData? {
        get { if case .link(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .link(v) } }
    }
    public var referenceGeometry: ReferenceGeometryData? {
        get { if case .referenceGeometry(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .referenceGeometry(v) } }
    }
    public var constraint: ConstraintData? {
        get { if case .constraint(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .constraint(v) } }
    }
    public var projectInfo: ProjectInfoData? {
        get { if case .projectInfo(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .projectInfo(v) } }
    }
    public var viewTemplate: ViewTemplateData? {
        get { if case .viewTemplate(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .viewTemplate(v) } }
    }
    public var viewFilter: ViewFilterData? {
        get { if case .filter(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .filter(v) } }
    }
    public var lineStyle: LineStyleData? {
        get { if case .lineStyle(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .lineStyle(v) } }
    }
    public var fillPattern: FillPatternData? {
        get { if case .fillPattern(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .fillPattern(v) } }
    }
    public var areaScheme: AreaSchemeData? {
        get { if case .areaScheme(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .areaScheme(v) } }
    }
    public var opening: OpeningData? {
        get { if case .opening(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .opening(v) } }
    }
}

extension Element {
    public var ramp: RampData? {
        get { if case .ramp(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .ramp(v) } }
    }
}
