//! The building model: elements, types, families, views and the project container.

use crate::geom::{DVec2, DVec3};
use crate::units::Units;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub type Id = u32;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum Category {
    Levels,
    Grids,
    Walls,
    Floors,
    Roofs,
    Rooms,
    Doors,
    Windows,
    Furniture,
    #[default]
    GenericModels,
    Ceilings,
    Stairs,
    Railings,
    Ramps,
    Columns,
    StructuralColumns,
    StructuralFraming,
    StructuralFoundations,
    ShaftOpenings,
    Casework,
    PlumbingFixtures,
    SpecialtyEquipment,
    Areas,
    RoomSeparation,
    AreaBoundary,
    ReferencePlanes,
    Lines,
    Dimensions,
    Tags,
    TextNotes,
    FilledRegions,
    Symbols,
    Groups,
    ImportedCad,
}

impl Category {
    pub const ALL: [Category; 34] = [
        Category::Levels,
        Category::Grids,
        Category::Walls,
        Category::Floors,
        Category::Roofs,
        Category::Rooms,
        Category::Doors,
        Category::Windows,
        Category::Furniture,
        Category::GenericModels,
        Category::Ceilings,
        Category::Stairs,
        Category::Railings,
        Category::Ramps,
        Category::Columns,
        Category::StructuralColumns,
        Category::StructuralFraming,
        Category::StructuralFoundations,
        Category::ShaftOpenings,
        Category::Casework,
        Category::PlumbingFixtures,
        Category::SpecialtyEquipment,
        Category::Areas,
        Category::RoomSeparation,
        Category::AreaBoundary,
        Category::ReferencePlanes,
        Category::Lines,
        Category::Dimensions,
        Category::Tags,
        Category::TextNotes,
        Category::FilledRegions,
        Category::Symbols,
        Category::Groups,
        Category::ImportedCad,
    ];

    /// Model categories (shown in Visibility/Graphics' model tab).
    pub const MODEL: [Category; 25] = [
        Category::Walls,
        Category::Floors,
        Category::Roofs,
        Category::Ceilings,
        Category::Doors,
        Category::Windows,
        Category::Stairs,
        Category::Railings,
        Category::Ramps,
        Category::Columns,
        Category::StructuralColumns,
        Category::StructuralFraming,
        Category::StructuralFoundations,
        Category::ShaftOpenings,
        Category::Furniture,
        Category::Casework,
        Category::PlumbingFixtures,
        Category::SpecialtyEquipment,
        Category::GenericModels,
        Category::Rooms,
        Category::Areas,
        Category::RoomSeparation,
        Category::AreaBoundary,
        Category::Lines,
        Category::Groups,
    ];

    /// Annotation categories.
    pub const ANNOTATION: [Category; 9] = [
        Category::Levels,
        Category::Grids,
        Category::ReferencePlanes,
        Category::Dimensions,
        Category::Tags,
        Category::TextNotes,
        Category::FilledRegions,
        Category::Symbols,
        Category::ImportedCad,
    ];

    /// Categories that can be scheduled.
    pub const SCHEDULABLE: [Category; 19] = [
        Category::Walls,
        Category::Floors,
        Category::Roofs,
        Category::Ceilings,
        Category::Rooms,
        Category::Areas,
        Category::Doors,
        Category::Windows,
        Category::Stairs,
        Category::Railings,
        Category::Columns,
        Category::StructuralColumns,
        Category::StructuralFraming,
        Category::StructuralFoundations,
        Category::Furniture,
        Category::Casework,
        Category::PlumbingFixtures,
        Category::SpecialtyEquipment,
        Category::GenericModels,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Category::Levels => "Levels",
            Category::Grids => "Grids",
            Category::Walls => "Walls",
            Category::Floors => "Floors",
            Category::Roofs => "Roofs",
            Category::Rooms => "Rooms",
            Category::Doors => "Doors",
            Category::Windows => "Windows",
            Category::Furniture => "Furniture",
            Category::GenericModels => "Generic Models",
            Category::Ceilings => "Ceilings",
            Category::Stairs => "Stairs",
            Category::Railings => "Railings",
            Category::Ramps => "Ramps",
            Category::Columns => "Columns",
            Category::StructuralColumns => "Structural Columns",
            Category::StructuralFraming => "Structural Framing",
            Category::StructuralFoundations => "Structural Foundations",
            Category::ShaftOpenings => "Shaft Openings",
            Category::Casework => "Casework",
            Category::PlumbingFixtures => "Plumbing Fixtures",
            Category::SpecialtyEquipment => "Specialty Equipment",
            Category::Areas => "Areas",
            Category::RoomSeparation => "Room Separation Lines",
            Category::AreaBoundary => "Area Boundary Lines",
            Category::ReferencePlanes => "Reference Planes",
            Category::Lines => "Lines",
            Category::Dimensions => "Dimensions",
            Category::Tags => "Tags",
            Category::TextNotes => "Text Notes",
            Category::FilledRegions => "Filled Regions",
            Category::Symbols => "Symbols",
            Category::Groups => "Model Groups",
            Category::ImportedCad => "Imported CAD",
        }
    }

    pub fn singular(self) -> &'static str {
        match self {
            Category::Levels => "Level",
            Category::Grids => "Grid",
            Category::Walls => "Wall",
            Category::Floors => "Floor",
            Category::Roofs => "Roof",
            Category::Rooms => "Room",
            Category::Doors => "Door",
            Category::Windows => "Window",
            Category::Furniture => "Furniture",
            Category::GenericModels => "Generic Model",
            Category::Ceilings => "Ceiling",
            Category::Stairs => "Stair",
            Category::Railings => "Railing",
            Category::Ramps => "Ramp",
            Category::Columns => "Column",
            Category::StructuralColumns => "Structural Column",
            Category::StructuralFraming => "Structural Framing",
            Category::StructuralFoundations => "Structural Foundation",
            Category::ShaftOpenings => "Shaft Opening",
            Category::Casework => "Casework",
            Category::PlumbingFixtures => "Plumbing Fixture",
            Category::SpecialtyEquipment => "Specialty Equipment",
            Category::Areas => "Area",
            Category::RoomSeparation => "Room Separation Line",
            Category::AreaBoundary => "Area Boundary Line",
            Category::ReferencePlanes => "Reference Plane",
            Category::Lines => "Line",
            Category::Dimensions => "Dimension",
            Category::Tags => "Tag",
            Category::TextNotes => "Text Note",
            Category::FilledRegions => "Filled Region",
            Category::Symbols => "Symbol",
            Category::Groups => "Model Group",
            Category::ImportedCad => "Imported CAD",
        }
    }

    pub fn is_annotation(self) -> bool {
        Category::ANNOTATION.contains(&self)
    }
}

// ---------------------------------------------------------------- elements

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Element {
    pub id: Id,
    #[serde(default)]
    pub mark: String,
    #[serde(default)]
    pub comments: String,
    /// Stable GUID used as the IFC GlobalId.
    pub uid: String,
    pub kind: ElementKind,
    /// Phase in which the element was created (None = the first phase).
    #[serde(default)]
    pub phase_created: Option<Id>,
    /// Phase in which the element was demolished.
    #[serde(default)]
    pub phase_demolished: Option<Id>,
    /// Design option the element belongs to (None = main model).
    #[serde(default)]
    pub design_option: Option<Id>,
    #[serde(default)]
    pub pinned: bool,
    /// Group instance this element is a member of.
    #[serde(default)]
    pub group: Option<Id>,
    /// Owner view for view-specific elements (annotations, detail lines, regions).
    #[serde(default)]
    pub view: Option<Id>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ElementKind {
    Level(Level),
    Grid(Grid),
    Wall(Wall),
    Floor(Floor),
    Roof(Roof),
    Room(Room),
    Instance(FamilyInstance),
    Ceiling(Ceiling),
    Stair(Stair),
    Railing(Railing),
    Shaft(Shaft),
    WallFoundation(WallFoundation),
    RefPlane(RefPlane),
    Line(LineElement),
    RoomSeparation(Separation),
    AreaBoundary(Separation),
    Area(Area),
    Dimension(Dimension),
    Tag(Tag),
    Text(TextNote),
    Region(FilledRegion),
    Symbol(Symbol),
    GroupInstance(GroupInstance),
    Cad(CadImport),
}

impl Element {
    pub fn new(id: Id, kind: ElementKind) -> Element {
        Element {
            id,
            mark: String::new(),
            comments: String::new(),
            uid: uuid::Uuid::new_v4().to_string(),
            kind,
            phase_created: None,
            phase_demolished: None,
            design_option: None,
            pinned: false,
            group: None,
            view: None,
        }
    }

    pub fn in_view(mut self, view: Id) -> Element {
        self.view = Some(view);
        self
    }

    pub fn category(&self) -> Category {
        match &self.kind {
            ElementKind::Level(_) => Category::Levels,
            ElementKind::Grid(_) => Category::Grids,
            ElementKind::Wall(_) => Category::Walls,
            ElementKind::Floor(_) => Category::Floors,
            ElementKind::Roof(_) => Category::Roofs,
            ElementKind::Room(_) => Category::Rooms,
            ElementKind::Instance(i) => i.category,
            ElementKind::Ceiling(_) => Category::Ceilings,
            ElementKind::Stair(_) => Category::Stairs,
            ElementKind::Railing(_) => Category::Railings,
            ElementKind::Shaft(_) => Category::ShaftOpenings,
            ElementKind::WallFoundation(_) => Category::StructuralFoundations,
            ElementKind::RefPlane(_) => Category::ReferencePlanes,
            ElementKind::Line(_) => Category::Lines,
            ElementKind::RoomSeparation(_) => Category::RoomSeparation,
            ElementKind::AreaBoundary(_) => Category::AreaBoundary,
            ElementKind::Area(_) => Category::Areas,
            ElementKind::Dimension(_) => Category::Dimensions,
            ElementKind::Tag(_) => Category::Tags,
            ElementKind::Text(_) => Category::TextNotes,
            ElementKind::Region(_) => Category::FilledRegions,
            ElementKind::Symbol(_) => Category::Symbols,
            ElementKind::GroupInstance(_) => Category::Groups,
            ElementKind::Cad(_) => Category::ImportedCad,
        }
    }

    /// The level the element is associated with, if any.
    pub fn level(&self) -> Option<Id> {
        match &self.kind {
            ElementKind::Wall(w) => Some(w.base_level),
            ElementKind::Floor(f) => Some(f.level),
            ElementKind::Roof(r) => Some(r.level),
            ElementKind::Room(r) => Some(r.level),
            ElementKind::Instance(i) => Some(i.level),
            ElementKind::Ceiling(c) => Some(c.level),
            ElementKind::Stair(s) => Some(s.base_level),
            ElementKind::Railing(r) => Some(r.level),
            ElementKind::Shaft(s) => Some(s.base_level),
            ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => Some(s.level),
            ElementKind::Area(a) => Some(a.level),
            ElementKind::Line(l) => l.level,
            ElementKind::GroupInstance(g) => Some(g.level),
            _ => None,
        }
    }

    /// Model elements visible in more than one view (as opposed to view-specific annotation).
    pub fn is_model(&self) -> bool {
        self.view.is_none() && !matches!(self.kind, ElementKind::Level(_))
    }

    pub fn as_wall(&self) -> Option<&Wall> {
        match &self.kind {
            ElementKind::Wall(w) => Some(w),
            _ => None,
        }
    }
    pub fn as_wall_mut(&mut self) -> Option<&mut Wall> {
        match &mut self.kind {
            ElementKind::Wall(w) => Some(w),
            _ => None,
        }
    }
    pub fn as_level(&self) -> Option<&Level> {
        match &self.kind {
            ElementKind::Level(l) => Some(l),
            _ => None,
        }
    }
    pub fn as_instance(&self) -> Option<&FamilyInstance> {
        match &self.kind {
            ElementKind::Instance(i) => Some(i),
            _ => None,
        }
    }
    pub fn as_instance_mut(&mut self) -> Option<&mut FamilyInstance> {
        match &mut self.kind {
            ElementKind::Instance(i) => Some(i),
            _ => None,
        }
    }
    pub fn as_room(&self) -> Option<&Room> {
        match &self.kind {
            ElementKind::Room(r) => Some(r),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Level {
    pub name: String,
    pub elevation: f64,
    #[serde(default = "yes")]
    pub building_story: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Grid {
    pub name: String,
    pub start: DVec2,
    pub end: DVec2,
    /// A point on the arc for curved grids.
    #[serde(default)]
    pub arc_mid: Option<DVec2>,
    #[serde(default = "yes")]
    pub bubble_start: bool,
    #[serde(default = "yes")]
    pub bubble_end: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocationLine {
    #[default]
    WallCenterline,
    CoreCenterline,
    FinishFaceExterior,
    FinishFaceInterior,
    CoreFaceExterior,
    CoreFaceInterior,
}

impl LocationLine {
    pub const ALL: [LocationLine; 6] = [
        LocationLine::WallCenterline,
        LocationLine::CoreCenterline,
        LocationLine::FinishFaceExterior,
        LocationLine::FinishFaceInterior,
        LocationLine::CoreFaceExterior,
        LocationLine::CoreFaceInterior,
    ];
    pub fn label(self) -> &'static str {
        match self {
            LocationLine::WallCenterline => "Wall Centerline",
            LocationLine::CoreCenterline => "Core Centerline",
            LocationLine::FinishFaceExterior => "Finish Face: Exterior",
            LocationLine::FinishFaceInterior => "Finish Face: Interior",
            LocationLine::CoreFaceExterior => "Core Face: Exterior",
            LocationLine::CoreFaceInterior => "Core Face: Interior",
        }
    }
}

/// A rectangular opening cut in a wall (Architecture > Wall Opening).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct WallOpening {
    pub u0: f64,
    pub u1: f64,
    /// Heights above the wall base.
    pub z0: f64,
    pub z1: f64,
}

/// Instance-level curtain grid layout (overrides the type's automatic spacing).
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct CurtainGrid {
    /// Vertical grid lines as distances along the wall from its start.
    pub u: Vec<f64>,
    /// Horizontal grid lines as heights above the wall base.
    pub v: Vec<f64>,
    /// Panels replaced by doors or solid panels, keyed by (column, row).
    #[serde(default)]
    pub panels: BTreeMap<String, PanelKind>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PanelKind {
    Glazed,
    Solid,
    Empty,
    Door,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Wall {
    pub start: DVec2,
    pub end: DVec2,
    pub type_id: Id,
    pub base_level: Id,
    #[serde(default)]
    pub base_offset: f64,
    /// Top constraint; `None` = "Unconnected" and `unconnected_height` applies.
    pub top_level: Option<Id>,
    #[serde(default)]
    pub top_offset: f64,
    pub unconnected_height: f64,
    #[serde(default)]
    pub structural: bool,
    #[serde(default = "yes")]
    pub room_bounding: bool,
    /// The line `start`–`end` describes (Revit's Location Line).
    #[serde(default)]
    pub location_line: LocationLine,
    /// A point the wall passes through, for arc walls.
    #[serde(default)]
    pub arc_mid: Option<DVec2>,
    /// Allow automatic joins at each end ("Allow/Disallow Join").
    #[serde(default = "yes")]
    pub join_start: bool,
    #[serde(default = "yes")]
    pub join_end: bool,
    /// Element (roof, floor or ceiling) the wall top is attached to.
    #[serde(default)]
    pub attach_top: Option<Id>,
    #[serde(default)]
    pub attach_base: Option<Id>,
    #[serde(default)]
    pub openings: Vec<WallOpening>,
    #[serde(default)]
    pub curtain: Option<CurtainGrid>,
    /// Exterior faces this way (+normal); flipped with the flip arrows.
    #[serde(default)]
    pub flipped: bool,
}

pub(crate) fn yes() -> bool {
    true
}

impl Wall {
    /// Straight-line length between the ends (chord for arc walls).
    pub fn chord(&self) -> f64 {
        self.start.distance(self.end)
    }
    /// Length along the wall (arc length for curved walls).
    pub fn length(&self) -> f64 {
        match self.arc() {
            Some(a) => a.length(),
            None => self.chord(),
        }
    }
    pub fn direction(&self) -> DVec2 {
        (self.end - self.start).normalize_or_zero()
    }
    /// Left normal of the location line; by convention the exterior side.
    pub fn normal(&self) -> DVec2 {
        crate::geom::perp(self.direction())
    }
    pub fn arc(&self) -> Option<crate::geom::Arc2> {
        self.arc_mid.and_then(|m| crate::geom::Arc2::through(self.start, m, self.end))
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Floor {
    pub boundary: Vec<DVec2>,
    pub level: Id,
    #[serde(default)]
    pub height_offset: f64,
    pub type_id: Id,
    #[serde(default)]
    pub holes: Vec<Vec<DVec2>>,
    #[serde(default)]
    pub structural: bool,
    /// Optional slope arrow: (tail, head, rise at the head relative to the tail).
    #[serde(default)]
    pub slope: Option<(DVec2, DVec2, f64)>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum RoofShape {
    Flat,
    Gable,
    #[default]
    Hip,
    Shed,
}

impl RoofShape {
    pub const ALL: [RoofShape; 4] = [RoofShape::Flat, RoofShape::Gable, RoofShape::Hip, RoofShape::Shed];
    pub fn label(self) -> &'static str {
        match self {
            RoofShape::Flat => "Flat",
            RoofShape::Gable => "Gable",
            RoofShape::Hip => "Hip",
            RoofShape::Shed => "Shed",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub enum RoofKind {
    /// Footprint roof: each footprint edge may define a slope.
    #[default]
    Footprint,
    /// Extrusion roof: a profile in the vertical plane through `start`→`end`, extruded along it.
    Extrusion { start: DVec2, end: DVec2, profile: Vec<DVec2> },
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Roof {
    pub footprint: Vec<DVec2>,
    pub level: Id,
    #[serde(default)]
    pub base_offset: f64,
    pub type_id: Id,
    pub shape: RoofShape,
    pub slope_deg: f64,
    pub overhang: f64,
    #[serde(default)]
    pub kind: RoofKind,
    /// Per footprint edge: does it define a slope? Empty = derived from `shape`.
    #[serde(default)]
    pub edge_slopes: Vec<bool>,
    #[serde(default)]
    pub fascia: bool,
    #[serde(default)]
    pub gutter: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Room {
    pub name: String,
    pub number: String,
    pub level: Id,
    /// Where the room was placed; the boundary is found from surrounding walls.
    pub location: DVec2,
    pub upper_offset: f64,
    #[serde(default)]
    pub department: String,
    #[serde(default)]
    pub floor_finish: String,
    #[serde(default)]
    pub wall_finish: String,
    #[serde(default)]
    pub ceiling_finish: String,
    #[serde(default)]
    pub occupancy: String,
}

/// Instance of a loadable family (door, window, furniture, column, beam...).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct FamilyInstance {
    pub family_id: Id,
    pub type_id: Id,
    pub category: Category,
    pub level: Id,
    /// Host wall for doors and windows.
    pub host: Option<Id>,
    /// Distance from the host wall start to the opening centre.
    #[serde(default)]
    pub offset_along_host: f64,
    /// Insertion point for unhosted families (start point of beams).
    #[serde(default)]
    pub location: DVec2,
    /// Height above the level (sill height for doors/windows).
    #[serde(default)]
    pub elevation: f64,
    #[serde(default)]
    pub rotation_deg: f64,
    #[serde(default)]
    pub flip_facing: bool,
    #[serde(default)]
    pub flip_hand: bool,
    /// Instance parameter values by name (invariant strings).
    #[serde(default)]
    pub values: BTreeMap<String, String>,
    /// Columns: top constraint (None = unconnected height from the family).
    #[serde(default)]
    pub top_level: Option<Id>,
    #[serde(default)]
    pub top_offset: f64,
    /// Beams/braces: end point and end elevation above the level.
    #[serde(default)]
    pub end: Option<DVec2>,
    #[serde(default)]
    pub end_elevation: f64,
    /// Columns: does the column move with the grid intersection it was placed on.
    #[serde(default)]
    pub moves_with_grids: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Ceiling {
    pub boundary: Vec<DVec2>,
    #[serde(default)]
    pub holes: Vec<Vec<DVec2>>,
    pub level: Id,
    pub height_offset: f64,
    pub type_id: Id,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct StairRun {
    /// Run centre line from the first riser to the last.
    pub start: DVec2,
    pub end: DVec2,
    pub width: f64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Stair {
    pub base_level: Id,
    #[serde(default)]
    pub base_offset: f64,
    pub top_level: Option<Id>,
    #[serde(default)]
    pub top_offset: f64,
    /// Used when there is no top level.
    #[serde(default)]
    pub unconnected_height: f64,
    pub runs: Vec<StairRun>,
    pub type_id: Id,
    /// Desired number of risers (0 = computed from the type's maximum riser height).
    #[serde(default)]
    pub desired_risers: u32,
    #[serde(default = "yes")]
    pub railings: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Railing {
    pub path: Vec<DVec2>,
    pub level: Id,
    #[serde(default)]
    pub base_offset: f64,
    pub type_id: Id,
    /// Stair the railing follows (its height then follows the stair slope).
    #[serde(default)]
    pub host: Option<Id>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Shaft {
    pub boundary: Vec<DVec2>,
    pub base_level: Id,
    #[serde(default)]
    pub base_offset: f64,
    pub top_level: Option<Id>,
    #[serde(default)]
    pub top_offset: f64,
    #[serde(default)]
    pub unconnected_height: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct WallFoundation {
    pub wall: Id,
    pub type_id: Id,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RefPlane {
    pub name: String,
    pub start: DVec2,
    pub end: DVec2,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum LineStyle {
    Thin,
    #[default]
    Medium,
    Wide,
    Hidden,
    Dashed,
    Centre,
    Overhead,
    Demolished,
}

impl LineStyle {
    pub const ALL: [LineStyle; 8] = [
        LineStyle::Thin,
        LineStyle::Medium,
        LineStyle::Wide,
        LineStyle::Hidden,
        LineStyle::Dashed,
        LineStyle::Centre,
        LineStyle::Overhead,
        LineStyle::Demolished,
    ];
    pub fn label(self) -> &'static str {
        match self {
            LineStyle::Thin => "Thin Lines",
            LineStyle::Medium => "Medium Lines",
            LineStyle::Wide => "Wide Lines",
            LineStyle::Hidden => "<Hidden>",
            LineStyle::Dashed => "Dashed",
            LineStyle::Centre => "<Centerline>",
            LineStyle::Overhead => "<Overhead>",
            LineStyle::Demolished => "<Demolished>",
        }
    }
}

/// Model lines (view = None, on a level) or detail lines (owned by a view).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LineElement {
    pub pts: Vec<DVec2>,
    #[serde(default)]
    pub closed: bool,
    #[serde(default)]
    pub style: LineStyle,
    /// Work plane level for model lines.
    #[serde(default)]
    pub level: Option<Id>,
    /// Arc segments: a mid point per segment, if curved.
    #[serde(default)]
    pub arc_mid: Option<DVec2>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Separation {
    pub level: Id,
    pub start: DVec2,
    pub end: DVec2,
    /// Area scheme for area boundary lines.
    #[serde(default)]
    pub scheme: Option<Id>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Area {
    pub name: String,
    pub number: String,
    pub level: Id,
    pub scheme: Id,
    pub location: DVec2,
    #[serde(default)]
    pub area_type: String,
}

/// What a dimension witness line references.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum RefPart {
    /// A free point (also the fallback if the element is gone).
    Point,
    WallCenter,
    WallExterior,
    WallInterior,
    GridLine,
    RefPlane,
    /// Start or end point of a linear element.
    EndStart,
    EndEnd,
    /// Centre line of a family instance (along its hand direction).
    InstanceCenter,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DimRef {
    pub element: Option<Id>,
    pub part: RefPart,
    /// Where the reference was picked (and the fallback position).
    pub point: DVec2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum DimKind {
    Aligned,
    Linear,
    Angular,
    Radial,
    Diameter,
    ArcLength,
    SpotElevation,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Dimension {
    pub kind: DimKind,
    pub refs: Vec<DimRef>,
    /// Measuring direction (unit) for aligned/linear dimensions.
    pub direction: DVec2,
    /// A point the dimension line passes through.
    pub line_point: DVec2,
    /// Locked segments (constraints), one per segment.
    #[serde(default)]
    pub locks: Vec<bool>,
    /// EQ: all segments are kept equal.
    #[serde(default)]
    pub equal: bool,
    #[serde(default)]
    pub text_override: String,
    #[serde(default)]
    pub prefix: String,
    #[serde(default)]
    pub suffix: String,
    /// Label (family editor dimensions): parameter name.
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub style: Option<Id>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tag {
    pub host: Id,
    pub position: DVec2,
    #[serde(default)]
    pub leader: bool,
    /// Where the leader ends (defaults to the host).
    #[serde(default)]
    pub leader_end: Option<DVec2>,
    /// Parameter shown ("Mark", "Type Mark", "Name", ...); empty = the category default.
    #[serde(default)]
    pub parameter: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TextNote {
    pub position: DVec2,
    pub text: String,
    /// Paper height in mm.
    pub size: f64,
    #[serde(default)]
    pub leader: Vec<DVec2>,
    #[serde(default)]
    pub bold: bool,
    #[serde(default)]
    pub rotation_deg: f64,
    #[serde(default)]
    pub type_id: Option<Id>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum FillPattern {
    #[default]
    Solid,
    Diagonal,
    CrossHatch,
    Brick,
    Concrete,
    Insulation,
    Masking,
}

impl FillPattern {
    pub const ALL: [FillPattern; 7] = [
        FillPattern::Solid,
        FillPattern::Diagonal,
        FillPattern::CrossHatch,
        FillPattern::Brick,
        FillPattern::Concrete,
        FillPattern::Insulation,
        FillPattern::Masking,
    ];
    pub fn label(self) -> &'static str {
        match self {
            FillPattern::Solid => "Solid fill",
            FillPattern::Diagonal => "Diagonal up",
            FillPattern::CrossHatch => "Crosshatch",
            FillPattern::Brick => "Brick",
            FillPattern::Concrete => "Concrete",
            FillPattern::Insulation => "Insulation (batt)",
            FillPattern::Masking => "Masking region",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FilledRegion {
    pub boundary: Vec<DVec2>,
    #[serde(default)]
    pub holes: Vec<Vec<DVec2>>,
    pub pattern: FillPattern,
    pub color: [u8; 3],
    #[serde(default)]
    pub boundary_style: LineStyle,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SymbolKind {
    NorthArrow,
    Revision,
    SpotElevation,
    BreakLine,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Symbol {
    pub kind: SymbolKind,
    pub position: DVec2,
    #[serde(default)]
    pub rotation_deg: f64,
    /// Revision clouds: the cloud outline; revision id in `value`.
    #[serde(default)]
    pub points: Vec<DVec2>,
    #[serde(default)]
    pub value: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GroupInstance {
    pub type_id: Id,
    pub origin: DVec2,
    pub level: Id,
    #[serde(default)]
    pub rotation_deg: f64,
}

/// An imported CAD drawing (DXF) used as an underlay.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CadImport {
    pub name: String,
    pub level: Option<Id>,
    pub polylines: Vec<(Vec<DVec2>, [u8; 3])>,
    #[serde(default)]
    pub texts: Vec<(DVec2, String, f64)>,
    #[serde(default = "yes")]
    pub halftone: bool,
}

// ---------------------------------------------------------------- types

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Material {
    pub name: String,
    pub color: [u8; 3],
    pub opacity: f64,
    #[serde(default)]
    pub class: String,
    /// Cut pattern drawn in plans and sections at fine detail.
    #[serde(default)]
    pub cut_pattern: FillPattern,
    /// Shininess 0..1 for the realistic style.
    #[serde(default)]
    pub shininess: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum LayerFunction {
    #[default]
    Structure,
    Substrate,
    ThermalAir,
    Membrane,
    Finish1,
    Finish2,
}

impl LayerFunction {
    pub const ALL: [LayerFunction; 6] = [
        LayerFunction::Structure,
        LayerFunction::Substrate,
        LayerFunction::ThermalAir,
        LayerFunction::Membrane,
        LayerFunction::Finish1,
        LayerFunction::Finish2,
    ];
    pub fn label(self) -> &'static str {
        match self {
            LayerFunction::Structure => "Structure [1]",
            LayerFunction::Substrate => "Substrate [2]",
            LayerFunction::ThermalAir => "Thermal/Air Layer [3]",
            LayerFunction::Membrane => "Membrane Layer",
            LayerFunction::Finish1 => "Finish 1 [4]",
            LayerFunction::Finish2 => "Finish 2 [5]",
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Layer {
    pub function: LayerFunction,
    pub material: String,
    pub thickness: f64,
    /// Part of the core (between core boundaries).
    #[serde(default)]
    pub core: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum WallFunction {
    #[default]
    Exterior,
    Interior,
    Foundation,
    Retaining,
}

impl WallFunction {
    pub const ALL: [WallFunction; 4] =
        [WallFunction::Exterior, WallFunction::Interior, WallFunction::Foundation, WallFunction::Retaining];
    pub fn label(self) -> &'static str {
        match self {
            WallFunction::Exterior => "Exterior",
            WallFunction::Interior => "Interior",
            WallFunction::Foundation => "Foundation",
            WallFunction::Retaining => "Retaining",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum WallKind {
    #[default]
    Basic,
    Curtain,
    Stacked,
}

/// System family types: walls, floors, roofs, ceilings, stairs, railings, wall foundations.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SystemType {
    pub id: Id,
    pub category: Category,
    pub name: String,
    #[serde(default)]
    pub type_mark: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub cost: f64,
    #[serde(default = "exterior")]
    pub function: WallFunction,
    /// Exterior → interior for walls, top → bottom for floors and roofs.
    pub layers: Vec<Layer>,
    #[serde(default)]
    pub wall_kind: WallKind,
    /// Kind-specific numeric properties (stair risers, railing height, curtain spacing...).
    #[serde(default)]
    pub props: BTreeMap<String, f64>,
    /// Kind-specific text properties (materials, profiles...).
    #[serde(default)]
    pub texts: BTreeMap<String, String>,
    /// Stacked walls: (wall type, height; 0 = variable) from the bottom up.
    #[serde(default)]
    pub stack: Vec<(Id, f64)>,
}

fn exterior() -> WallFunction {
    WallFunction::Exterior
}

impl SystemType {
    pub fn thickness(&self) -> f64 {
        match self.category {
            Category::Walls if self.wall_kind == WallKind::Curtain => self.prop("Mullion Depth", 150.0),
            _ => self.layers.iter().map(|l| l.thickness).sum(),
        }
    }

    pub fn prop(&self, name: &str, fallback: f64) -> f64 {
        self.props.get(name).copied().unwrap_or(fallback)
    }

    pub fn text(&self, name: &str, fallback: &str) -> String {
        self.texts.get(name).cloned().unwrap_or_else(|| fallback.to_string())
    }

    pub fn family_name(&self) -> &'static str {
        match (self.category, self.wall_kind) {
            (Category::Walls, WallKind::Curtain) => "Curtain Wall",
            (Category::Walls, WallKind::Stacked) => "Stacked Wall",
            (Category::Walls, _) => "Basic Wall",
            (Category::Floors, _) => "Floor",
            (Category::Roofs, _) => "Basic Roof",
            (Category::Ceilings, _) => "Compound Ceiling",
            (Category::Stairs, _) => "Assembled Stair",
            (Category::Railings, _) => "Railing",
            (Category::StructuralFoundations, _) => "Wall Foundation",
            _ => "System Family",
        }
    }

    /// Material of the thickest structure layer.
    pub fn primary_material(&self) -> String {
        if let Some(m) = self.texts.get("Material") {
            return m.clone();
        }
        self.layers
            .iter()
            .filter(|l| l.function == LayerFunction::Structure)
            .max_by(|a, b| a.thickness.total_cmp(&b.thickness))
            .or_else(|| self.layers.iter().max_by(|a, b| a.thickness.total_cmp(&b.thickness)))
            .map(|l| l.material.clone())
            .unwrap_or_else(|| "Default".into())
    }

    /// Offset of the core centre and both core faces from the wall centre (+ = exterior side).
    pub fn core_offsets(&self) -> (f64, f64, f64) {
        let t = self.thickness();
        let mut o = t / 2.0;
        let (mut ext, mut int) = (None, None);
        for l in &self.layers {
            let o0 = o - l.thickness;
            let is_core = l.core || l.function == LayerFunction::Structure;
            if is_core {
                ext.get_or_insert(o);
                int = Some(o0);
            }
            o = o0;
        }
        let (e, i) = (ext.unwrap_or(t / 2.0), int.unwrap_or(-t / 2.0));
        ((e + i) / 2.0, e, i)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum FamilyTemplate {
    SingleDoor,
    DoubleDoor,
    FixedWindow,
    CasementWindow,
    Table,
    Box,
    SlidingDoor,
    BifoldDoor,
    GarageDoor,
    GlazedDoor,
    AwningWindow,
    DoubleHungWindow,
    SlidingWindow,
    RoundWindow,
    Chair,
    Sofa,
    Bed,
    Desk,
    Wardrobe,
    KitchenCabinet,
    Toilet,
    Sink,
    Bathtub,
    Shower,
    Refrigerator,
    RectColumn,
    RoundColumn,
    SteelColumn,
    RectBeam,
    SteelBeam,
    Footing,
    #[default]
    /// Parametric family built in the family editor from reference planes and forms.
    Custom,
}

impl FamilyTemplate {
    pub const ALL: [FamilyTemplate; 32] = [
        FamilyTemplate::SingleDoor,
        FamilyTemplate::DoubleDoor,
        FamilyTemplate::SlidingDoor,
        FamilyTemplate::BifoldDoor,
        FamilyTemplate::GarageDoor,
        FamilyTemplate::GlazedDoor,
        FamilyTemplate::FixedWindow,
        FamilyTemplate::CasementWindow,
        FamilyTemplate::AwningWindow,
        FamilyTemplate::DoubleHungWindow,
        FamilyTemplate::SlidingWindow,
        FamilyTemplate::RoundWindow,
        FamilyTemplate::Table,
        FamilyTemplate::Chair,
        FamilyTemplate::Sofa,
        FamilyTemplate::Bed,
        FamilyTemplate::Desk,
        FamilyTemplate::Wardrobe,
        FamilyTemplate::KitchenCabinet,
        FamilyTemplate::Toilet,
        FamilyTemplate::Sink,
        FamilyTemplate::Bathtub,
        FamilyTemplate::Shower,
        FamilyTemplate::Refrigerator,
        FamilyTemplate::RectColumn,
        FamilyTemplate::RoundColumn,
        FamilyTemplate::SteelColumn,
        FamilyTemplate::RectBeam,
        FamilyTemplate::SteelBeam,
        FamilyTemplate::Footing,
        FamilyTemplate::Box,
        FamilyTemplate::Custom,
    ];
    pub fn label(self) -> &'static str {
        match self {
            FamilyTemplate::SingleDoor => "Single Door",
            FamilyTemplate::DoubleDoor => "Double Door",
            FamilyTemplate::SlidingDoor => "Sliding Door",
            FamilyTemplate::BifoldDoor => "Bifold Door",
            FamilyTemplate::GarageDoor => "Garage Door",
            FamilyTemplate::GlazedDoor => "Glazed Door",
            FamilyTemplate::FixedWindow => "Fixed Window",
            FamilyTemplate::CasementWindow => "Casement Window",
            FamilyTemplate::AwningWindow => "Awning Window",
            FamilyTemplate::DoubleHungWindow => "Double Hung Window",
            FamilyTemplate::SlidingWindow => "Sliding Window",
            FamilyTemplate::RoundWindow => "Round Window",
            FamilyTemplate::Table => "Table",
            FamilyTemplate::Chair => "Chair",
            FamilyTemplate::Sofa => "Sofa",
            FamilyTemplate::Bed => "Bed",
            FamilyTemplate::Desk => "Desk",
            FamilyTemplate::Wardrobe => "Wardrobe",
            FamilyTemplate::KitchenCabinet => "Base Cabinet",
            FamilyTemplate::Toilet => "Toilet",
            FamilyTemplate::Sink => "Sink",
            FamilyTemplate::Bathtub => "Bathtub",
            FamilyTemplate::Shower => "Shower Tray",
            FamilyTemplate::Refrigerator => "Refrigerator",
            FamilyTemplate::RectColumn => "Rectangular Column",
            FamilyTemplate::RoundColumn => "Round Column",
            FamilyTemplate::SteelColumn => "Steel Column (I-section)",
            FamilyTemplate::RectBeam => "Concrete Beam",
            FamilyTemplate::SteelBeam => "Steel Beam (I-section)",
            FamilyTemplate::Footing => "Isolated Footing",
            FamilyTemplate::Box => "Box",
            FamilyTemplate::Custom => "Generic Model (custom)",
        }
    }
    pub fn category(self) -> Category {
        use FamilyTemplate::*;
        match self {
            SingleDoor | DoubleDoor | SlidingDoor | BifoldDoor | GarageDoor | GlazedDoor => Category::Doors,
            FixedWindow | CasementWindow | AwningWindow | DoubleHungWindow | SlidingWindow | RoundWindow => Category::Windows,
            Table | Chair | Sofa | Bed | Desk | Wardrobe => Category::Furniture,
            KitchenCabinet => Category::Casework,
            Toilet | Sink | Bathtub | Shower => Category::PlumbingFixtures,
            Refrigerator => Category::SpecialtyEquipment,
            RectColumn | RoundColumn => Category::Columns,
            SteelColumn => Category::StructuralColumns,
            RectBeam | SteelBeam => Category::StructuralFraming,
            Footing => Category::StructuralFoundations,
            Box | Custom => Category::GenericModels,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum ParamKind {
    #[default]
    Length,
    Number,
    Integer,
    Angle,
    Area,
    Volume,
    Text,
    YesNo,
    Material,
    Currency,
}

impl ParamKind {
    pub const USER: [ParamKind; 8] = [
        ParamKind::Length,
        ParamKind::Number,
        ParamKind::Integer,
        ParamKind::Angle,
        ParamKind::Text,
        ParamKind::YesNo,
        ParamKind::Material,
        ParamKind::Currency,
    ];
    pub fn label(self) -> &'static str {
        match self {
            ParamKind::Length => "Length",
            ParamKind::Number => "Number",
            ParamKind::Integer => "Integer",
            ParamKind::Angle => "Angle",
            ParamKind::Area => "Area",
            ParamKind::Volume => "Volume",
            ParamKind::Text => "Text",
            ParamKind::YesNo => "Yes/No",
            ParamKind::Material => "Material",
            ParamKind::Currency => "Currency",
        }
    }
    pub fn is_numeric(self) -> bool {
        !matches!(self, ParamKind::Text | ParamKind::Material)
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct FamilyParameter {
    pub name: String,
    pub kind: ParamKind,
    pub instance: bool,
    /// When non-empty the value is computed and cannot be typed in.
    #[serde(default)]
    pub formula: String,
    pub group: String,
    /// Required by the template's geometry; cannot be deleted or renamed.
    #[serde(default)]
    pub built_in: bool,
    pub default: String,
    #[serde(default)]
    pub reporting: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FamilyType {
    pub id: Id,
    pub name: String,
    #[serde(default)]
    pub values: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Family {
    pub id: Id,
    pub name: String,
    pub category: Category,
    pub template: FamilyTemplate,
    pub params: Vec<FamilyParameter>,
    pub types: Vec<FamilyType>,
    /// Geometry definition for `FamilyTemplate::Custom` families.
    #[serde(default)]
    pub definition: Option<crate::family_def::FamilyDef>,
}

impl Family {
    pub fn param(&self, name: &str) -> Option<&FamilyParameter> {
        self.params.iter().find(|p| p.name.eq_ignore_ascii_case(name))
    }
    pub fn is_hosted(&self) -> bool {
        matches!(self.category, Category::Doors | Category::Windows)
    }
    pub fn is_column(&self) -> bool {
        matches!(self.category, Category::Columns | Category::StructuralColumns)
    }
    pub fn is_framing(&self) -> bool {
        self.category == Category::StructuralFraming
    }
}

// ---------------------------------------------------------------- views

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum ElevationDir {
    North,
    South,
    East,
    West,
}

impl ElevationDir {
    pub const ALL: [ElevationDir; 4] = [ElevationDir::North, ElevationDir::South, ElevationDir::East, ElevationDir::West];
    pub fn label(self) -> &'static str {
        match self {
            ElevationDir::North => "North",
            ElevationDir::South => "South",
            ElevationDir::East => "East",
            ElevationDir::West => "West",
        }
    }
    /// Direction the viewer looks in (looking at the north facade means looking south).
    pub fn look(self) -> DVec3 {
        match self {
            ElevationDir::North => DVec3::new(0.0, -1.0, 0.0),
            ElevationDir::South => DVec3::new(0.0, 1.0, 0.0),
            ElevationDir::East => DVec3::new(-1.0, 0.0, 0.0),
            ElevationDir::West => DVec3::new(1.0, 0.0, 0.0),
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum SheetSize {
    A0,
    #[default]
    A1,
    A2,
    A3,
    A4,
    ArchD,
    ArchE1,
    ArchE,
    AnsiB,
    Letter,
}

impl SheetSize {
    pub const ALL: [SheetSize; 10] = [
        SheetSize::A0,
        SheetSize::A1,
        SheetSize::A2,
        SheetSize::A3,
        SheetSize::A4,
        SheetSize::ArchD,
        SheetSize::ArchE1,
        SheetSize::ArchE,
        SheetSize::AnsiB,
        SheetSize::Letter,
    ];
    pub fn label(self) -> &'static str {
        match self {
            SheetSize::A0 => "A0",
            SheetSize::A1 => "A1",
            SheetSize::A2 => "A2",
            SheetSize::A3 => "A3",
            SheetSize::A4 => "A4",
            SheetSize::ArchD => "ARCH D (36x24)",
            SheetSize::ArchE1 => "ARCH E1 (42x30)",
            SheetSize::ArchE => "ARCH E (48x36)",
            SheetSize::AnsiB => "ANSI B (17x11)",
            SheetSize::Letter => "Letter (11x8.5)",
        }
    }
    /// Landscape paper size in millimetres.
    pub fn paper(self) -> (f64, f64) {
        let inch = 25.4;
        match self {
            SheetSize::A0 => (1189.0, 841.0),
            SheetSize::A1 => (841.0, 594.0),
            SheetSize::A2 => (594.0, 420.0),
            SheetSize::A3 => (420.0, 297.0),
            SheetSize::A4 => (297.0, 210.0),
            SheetSize::ArchD => (36.0 * inch, 24.0 * inch),
            SheetSize::ArchE1 => (42.0 * inch, 30.0 * inch),
            SheetSize::ArchE => (48.0 * inch, 36.0 * inch),
            SheetSize::AnsiB => (17.0 * inch, 11.0 * inch),
            SheetSize::Letter => (11.0 * inch, 8.5 * inch),
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Viewport {
    pub view: Id,
    /// Centre on the sheet in paper millimetres from the bottom-left corner.
    pub cx: f64,
    pub cy: f64,
    /// Detail number shown in the view title.
    #[serde(default)]
    pub detail_number: String,
    #[serde(default = "yes")]
    pub show_title: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Sheet {
    pub number: String,
    pub size: SheetSize,
    pub drawn_by: String,
    pub checked_by: String,
    pub issue_date: String,
    pub viewports: Vec<Viewport>,
    /// Revisions shown in the title block's revision schedule.
    #[serde(default)]
    pub revisions: Vec<Id>,
    #[serde(default)]
    pub designed_by: String,
    #[serde(default)]
    pub approved_by: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum FilterOp {
    Equals,
    NotEquals,
    Greater,
    Less,
    Contains,
    BeginsWith,
}

impl FilterOp {
    pub const ALL: [FilterOp; 6] =
        [FilterOp::Equals, FilterOp::NotEquals, FilterOp::Greater, FilterOp::Less, FilterOp::Contains, FilterOp::BeginsWith];
    pub fn label(self) -> &'static str {
        match self {
            FilterOp::Equals => "equals",
            FilterOp::NotEquals => "does not equal",
            FilterOp::Greater => "is greater than",
            FilterOp::Less => "is less than",
            FilterOp::Contains => "contains",
            FilterOp::BeginsWith => "begins with",
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScheduleFilter {
    pub field: String,
    pub op: FilterOp,
    pub value: String,
}

/// Calculated value field: `name = formula` over other fields.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct CalculatedField {
    pub name: String,
    pub formula: String,
    pub kind: ParamKind,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ScheduleDef {
    pub category: Category,
    pub fields: Vec<String>,
    #[serde(default)]
    pub sort_by: Vec<String>,
    #[serde(default)]
    pub descending: bool,
    /// When false, rows with equal sort-field values collapse (Revit "Itemize every instance").
    #[serde(default = "yes")]
    pub itemize: bool,
    #[serde(default = "yes")]
    pub grand_total: bool,
    /// Numeric fields summed in grouped rows and the grand total.
    #[serde(default)]
    pub total_fields: Vec<String>,
    #[serde(default)]
    pub filters: Vec<ScheduleFilter>,
    #[serde(default)]
    pub calculated: Vec<CalculatedField>,
    /// Material takeoff: one row per (element, material).
    #[serde(default)]
    pub material_takeoff: bool,
    /// Group headers/footers for the first sort field.
    #[serde(default)]
    pub group_headers: bool,
    /// Sheet list instead of an element schedule.
    #[serde(default)]
    pub sheet_list: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum DetailLevel {
    Coarse,
    #[default]
    Medium,
    Fine,
}

impl DetailLevel {
    pub const ALL: [DetailLevel; 3] = [DetailLevel::Coarse, DetailLevel::Medium, DetailLevel::Fine];
    pub fn label(self) -> &'static str {
        match self {
            DetailLevel::Coarse => "Coarse",
            DetailLevel::Medium => "Medium",
            DetailLevel::Fine => "Fine",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum VisualStyle {
    Wireframe,
    #[default]
    HiddenLine,
    Shaded,
    ConsistentColors,
    Realistic,
}

impl VisualStyle {
    pub const ALL: [VisualStyle; 5] =
        [VisualStyle::Wireframe, VisualStyle::HiddenLine, VisualStyle::Shaded, VisualStyle::ConsistentColors, VisualStyle::Realistic];
    pub fn label(self) -> &'static str {
        match self {
            VisualStyle::Wireframe => "Wireframe",
            VisualStyle::HiddenLine => "Hidden Line",
            VisualStyle::Shaded => "Shaded",
            VisualStyle::ConsistentColors => "Consistent Colors",
            VisualStyle::Realistic => "Realistic",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum PhaseFilter {
    #[default]
    ShowAll,
    ShowComplete,
    ShowNew,
    ShowPreviousAndNew,
    ShowDemoAndNew,
    ShowPrevious,
    None,
}

impl PhaseFilter {
    pub const ALL: [PhaseFilter; 7] = [
        PhaseFilter::ShowAll,
        PhaseFilter::ShowComplete,
        PhaseFilter::ShowNew,
        PhaseFilter::ShowPreviousAndNew,
        PhaseFilter::ShowDemoAndNew,
        PhaseFilter::ShowPrevious,
        PhaseFilter::None,
    ];
    pub fn label(self) -> &'static str {
        match self {
            PhaseFilter::ShowAll => "Show All",
            PhaseFilter::ShowComplete => "Show Complete",
            PhaseFilter::ShowNew => "Show New",
            PhaseFilter::ShowPreviousAndNew => "Show Previous + New",
            PhaseFilter::ShowDemoAndNew => "Show Previous + Demo",
            PhaseFilter::ShowPrevious => "Show Previous Phase",
            PhaseFilter::None => "None",
        }
    }
}

/// Floor plan view range (offsets from the associated level).
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct ViewRange {
    pub top: f64,
    pub cut: f64,
    pub bottom: f64,
    pub depth: f64,
}

impl Default for ViewRange {
    fn default() -> Self {
        ViewRange { top: 2300.0, cut: 1200.0, bottom: 0.0, depth: 0.0 }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct GraphicOverride {
    pub category: Option<Category>,
    pub element: Option<Id>,
    pub line_color: Option<[u8; 3]>,
    pub line_weight: Option<f32>,
    pub fill_color: Option<[u8; 3]>,
    #[serde(default)]
    pub halftone: bool,
    /// Surface transparency 0-100.
    #[serde(default)]
    pub transparency: u8,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum ViewKind {
    FloorPlan { level: Id, cut_height: f64, room_colors: bool },
    ThreeD { eye: DVec3, target: DVec3, perspective: bool },
    Elevation { dir: ElevationDir },
    Schedule(ScheduleDef),
    Sheet(Sheet),
    CeilingPlan { level: Id },
    /// A section: line `start`→`end`, looking to the right of it, far clip `depth`.
    Section { start: DVec2, end: DVec2, depth: f64, z_min: f64, z_max: f64 },
    Drafting,
    Legend,
    AreaPlan { level: Id, scheme: Id },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct View {
    pub id: Id,
    pub name: String,
    /// Scale denominator (100 = 1:100).
    pub scale: f64,
    /// Visibility/Graphics: categories hidden in this view.
    #[serde(default)]
    pub hidden: Vec<Category>,
    pub kind: ViewKind,
    #[serde(default)]
    pub detail: DetailLevel,
    #[serde(default)]
    pub style: VisualStyle,
    #[serde(default)]
    pub view_range: ViewRange,
    /// Crop region in model coordinates (plan) or view coordinates (sections/elevations).
    #[serde(default)]
    pub crop: Option<(DVec2, DVec2)>,
    #[serde(default)]
    pub crop_active: bool,
    #[serde(default)]
    pub crop_visible: bool,
    #[serde(default)]
    pub phase: Option<Id>,
    #[serde(default)]
    pub phase_filter: PhaseFilter,
    /// View template applied to this view.
    #[serde(default)]
    pub template: Option<Id>,
    /// This view is a view template (not shown in the browser's view list).
    #[serde(default)]
    pub is_template: bool,
    /// Elements hidden in this view (Hide in View > Elements).
    #[serde(default)]
    pub hidden_elements: Vec<Id>,
    #[serde(default)]
    pub overrides: Vec<GraphicOverride>,
    #[serde(default)]
    pub shadows: bool,
    #[serde(default)]
    pub section_box: Option<(DVec3, DVec3)>,
    /// Parent view for callouts and dependent views.
    #[serde(default)]
    pub parent: Option<Id>,
    /// Underlay level shown halftone in plans.
    #[serde(default)]
    pub underlay: Option<Id>,
    /// Which option of each option set this view shows (default = primary).
    #[serde(default)]
    pub options: BTreeMap<Id, Id>,
    #[serde(default)]
    pub title_on_sheet: String,
    /// Elevation views: far clip offset and an optional custom marker (origin, look direction).
    #[serde(default)]
    pub marker: Option<(DVec2, DVec2)>,
}

impl View {
    pub fn new(id: Id, name: impl Into<String>, scale: f64, kind: ViewKind) -> View {
        let style = match kind {
            ViewKind::ThreeD { .. } => VisualStyle::Shaded,
            ViewKind::Elevation { .. } | ViewKind::Section { .. } => VisualStyle::HiddenLine,
            _ => VisualStyle::HiddenLine,
        };
        View {
            id,
            name: name.into(),
            scale,
            hidden: Vec::new(),
            kind,
            detail: DetailLevel::Medium,
            style,
            view_range: ViewRange::default(),
            crop: None,
            crop_active: false,
            crop_visible: false,
            phase: None,
            phase_filter: PhaseFilter::ShowAll,
            template: None,
            is_template: false,
            hidden_elements: Vec::new(),
            overrides: Vec::new(),
            shadows: false,
            section_box: None,
            parent: None,
            underlay: None,
            options: BTreeMap::new(),
            title_on_sheet: String::new(),
            marker: None,
        }
    }

    pub fn shows(&self, c: Category) -> bool {
        !self.hidden.contains(&c)
    }

    pub fn shows_element(&self, e: &Element) -> bool {
        self.shows(e.category()) && !self.hidden_elements.contains(&e.id) && e.view.is_none_or(|v| v == self.id)
    }

    pub fn type_label(&self) -> &'static str {
        match self.kind {
            ViewKind::FloorPlan { .. } => "Floor Plan",
            ViewKind::ThreeD { .. } => "3D View",
            ViewKind::Elevation { .. } => "Elevation",
            ViewKind::Schedule(_) => "Schedule",
            ViewKind::Sheet(_) => "Sheet",
            ViewKind::CeilingPlan { .. } => "Ceiling Plan",
            ViewKind::Section { .. } => "Section",
            ViewKind::Drafting => "Drafting View",
            ViewKind::Legend => "Legend",
            ViewKind::AreaPlan { .. } => "Area Plan",
        }
    }

    /// Schedules and legends may appear on many sheets; other views on one.
    pub fn single_placement(&self) -> bool {
        !matches!(self.kind, ViewKind::Schedule(_) | ViewKind::Legend)
    }

    pub fn is_graphical(&self) -> bool {
        !matches!(self.kind, ViewKind::Schedule(_) | ViewKind::Sheet(_))
    }

    /// Plan-like views drawn top down (floor, ceiling and area plans).
    pub fn plan_level(&self) -> Option<Id> {
        match self.kind {
            ViewKind::FloorPlan { level, .. } | ViewKind::CeilingPlan { level } | ViewKind::AreaPlan { level, .. } => Some(level),
            _ => None,
        }
    }

    /// Views drawn with the 2D plan engine (plans and 2D-only views).
    pub fn is_planar_2d(&self) -> bool {
        matches!(self.kind, ViewKind::FloorPlan { .. } | ViewKind::CeilingPlan { .. } | ViewKind::AreaPlan { .. } | ViewKind::Drafting | ViewKind::Legend)
    }

    pub fn override_for(&self, e: &Element) -> Option<&GraphicOverride> {
        self.overrides
            .iter()
            .find(|o| o.element == Some(e.id))
            .or_else(|| self.overrides.iter().find(|o| o.element.is_none() && o.category == Some(e.category())))
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ProjectInfo {
    pub name: String,
    pub number: String,
    pub client: String,
    pub address: String,
    pub author: String,
    pub status: String,
    #[serde(default)]
    pub organization: String,
    #[serde(default)]
    pub issue_date: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Phase {
    pub id: Id,
    pub name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DesignOption {
    pub id: Id,
    pub name: String,
    pub primary: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OptionSet {
    pub id: Id,
    pub name: String,
    pub options: Vec<DesignOption>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AreaScheme {
    pub id: Id,
    pub name: String,
}

/// A group definition: member elements stored relative to the group origin.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GroupType {
    pub id: Id,
    pub name: String,
    pub members: Vec<Element>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Revision {
    pub id: Id,
    pub sequence: u32,
    pub date: String,
    pub description: String,
    pub issued_to: String,
    pub issued_by: String,
    pub issued: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DimensionStyle {
    pub id: Id,
    pub name: String,
    /// Text height in paper mm.
    pub text_size: f64,
    /// Tick: true = diagonal tick, false = arrow.
    pub tick: bool,
    /// Witness line gap to element in paper mm.
    pub gap: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TextType {
    pub id: Id,
    pub name: String,
    pub size: f64,
    pub bold: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SunSettings {
    /// Degrees; azimuth measured clockwise from north.
    pub azimuth: f64,
    pub altitude: f64,
    pub latitude: f64,
    pub longitude: f64,
    pub date: String,
    pub time: String,
}

impl Default for SunSettings {
    fn default() -> Self {
        SunSettings { azimuth: 135.0, altitude: 35.0, latitude: 51.5, longitude: 0.0, date: "06-21".into(), time: "15:00".into() }
    }
}

// ---------------------------------------------------------------- project

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Project {
    pub format: u32,
    pub next_id: Id,
    pub info: ProjectInfo,
    pub materials: Vec<Material>,
    pub types: Vec<SystemType>,
    pub families: Vec<Family>,
    pub elements: Vec<Element>,
    pub views: Vec<View>,
    #[serde(default)]
    pub units: Units,
    #[serde(default)]
    pub phases: Vec<Phase>,
    #[serde(default)]
    pub option_sets: Vec<OptionSet>,
    #[serde(default)]
    pub area_schemes: Vec<AreaScheme>,
    #[serde(default)]
    pub group_types: Vec<GroupType>,
    #[serde(default)]
    pub revisions: Vec<Revision>,
    #[serde(default)]
    pub dim_styles: Vec<DimensionStyle>,
    #[serde(default)]
    pub text_types: Vec<TextType>,
    #[serde(default)]
    pub sun: SunSettings,
    /// Angle (degrees) from project north to true north.
    #[serde(default)]
    pub true_north: f64,
    /// Manage > Object Styles: project-wide line overrides per category.
    #[serde(default)]
    pub object_styles: BTreeMap<Category, ObjectStyle>,
}

/// Line graphics of a category (Object Styles). None keeps the built-in default.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ObjectStyle {
    /// Projection line weight in paper millimetres.
    #[serde(default)]
    pub projection_weight: Option<f32>,
    /// Cut line weight in paper millimetres.
    #[serde(default)]
    pub cut_weight: Option<f32>,
    #[serde(default)]
    pub color: Option<[u8; 3]>,
    /// 0 solid, 1 dashed, 2 dash-dot, 3 dotted.
    #[serde(default)]
    pub pattern: Option<u8>,
}

impl Project {
    pub fn empty() -> Project {
        Project {
            format: 2,
            next_id: 1,
            info: ProjectInfo::default(),
            materials: Vec::new(),
            types: Vec::new(),
            families: Vec::new(),
            elements: Vec::new(),
            views: Vec::new(),
            units: Units::metric(),
            phases: Vec::new(),
            option_sets: Vec::new(),
            area_schemes: Vec::new(),
            group_types: Vec::new(),
            revisions: Vec::new(),
            dim_styles: Vec::new(),
            text_types: Vec::new(),
            sun: SunSettings::default(),
            true_north: 0.0,
            object_styles: BTreeMap::new(),
        }
    }

    pub fn new_id(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    pub fn element(&self, id: Id) -> Option<&Element> {
        self.elements.iter().find(|e| e.id == id)
    }

    pub fn element_mut(&mut self, id: Id) -> Option<&mut Element> {
        self.elements.iter_mut().find(|e| e.id == id)
    }

    pub fn wall(&self, id: Id) -> Option<&Wall> {
        self.element(id).and_then(Element::as_wall)
    }

    pub fn walls(&self) -> impl Iterator<Item = (&Element, &Wall)> {
        self.elements.iter().filter_map(|e| e.as_wall().map(|w| (e, w)))
    }

    pub fn instances(&self) -> impl Iterator<Item = (&Element, &FamilyInstance)> {
        self.elements.iter().filter_map(|e| e.as_instance().map(|i| (e, i)))
    }

    pub fn hosted_by(&self, wall: Id) -> impl Iterator<Item = (&Element, &FamilyInstance)> {
        self.instances().filter(move |(_, i)| i.host == Some(wall))
    }

    /// Levels sorted by elevation.
    pub fn levels(&self) -> Vec<(Id, &Level)> {
        let mut v: Vec<(Id, &Level)> = self.elements.iter().filter_map(|e| e.as_level().map(|l| (e.id, l))).collect();
        v.sort_by(|a, b| a.1.elevation.total_cmp(&b.1.elevation));
        v
    }

    pub fn level(&self, id: Id) -> Option<&Level> {
        self.element(id).and_then(Element::as_level)
    }

    pub fn level_elevation(&self, id: Id) -> f64 {
        self.level(id).map(|l| l.elevation).unwrap_or(0.0)
    }

    pub fn level_name(&self, id: Id) -> String {
        self.level(id).map(|l| l.name.clone()).unwrap_or_else(|| "<none>".into())
    }

    pub fn level_above(&self, id: Id) -> Option<(Id, &Level)> {
        let e = self.level_elevation(id);
        self.levels().into_iter().find(|(_, l)| l.elevation > e + 1e-6)
    }

    pub fn sys_type(&self, id: Id) -> Option<&SystemType> {
        self.types.iter().find(|t| t.id == id)
    }

    pub fn sys_type_mut(&mut self, id: Id) -> Option<&mut SystemType> {
        self.types.iter_mut().find(|t| t.id == id)
    }

    pub fn types_of(&self, c: Category) -> impl Iterator<Item = &SystemType> {
        self.types.iter().filter(move |t| t.category == c)
    }

    pub fn family(&self, id: Id) -> Option<&Family> {
        self.families.iter().find(|f| f.id == id)
    }

    pub fn family_mut(&mut self, id: Id) -> Option<&mut Family> {
        self.families.iter_mut().find(|f| f.id == id)
    }

    /// Finds a family type by id and returns it with its family.
    pub fn family_type(&self, type_id: Id) -> Option<(&Family, &FamilyType)> {
        self.families.iter().find_map(|f| f.types.iter().find(|t| t.id == type_id).map(|t| (f, t)))
    }

    pub fn material(&self, name: &str) -> Option<&Material> {
        self.materials.iter().find(|m| m.name == name)
    }

    pub fn view(&self, id: Id) -> Option<&View> {
        self.views.iter().find(|v| v.id == id)
    }

    pub fn view_mut(&mut self, id: Id) -> Option<&mut View> {
        self.views.iter_mut().find(|v| v.id == id)
    }

    /// Sheet a view is placed on.
    pub fn sheet_containing(&self, view: Id) -> Option<&View> {
        self.views.iter().find(|v| matches!(&v.kind, ViewKind::Sheet(s) if s.viewports.iter().any(|vp| vp.view == view)))
    }

    /// Type id of any typed element.
    pub fn type_of(&self, e: &Element) -> Option<Id> {
        match &e.kind {
            ElementKind::Wall(w) => Some(w.type_id),
            ElementKind::Floor(f) => Some(f.type_id),
            ElementKind::Roof(r) => Some(r.type_id),
            ElementKind::Instance(i) => Some(i.type_id),
            ElementKind::Ceiling(c) => Some(c.type_id),
            ElementKind::Stair(s) => Some(s.type_id),
            ElementKind::Railing(r) => Some(r.type_id),
            ElementKind::WallFoundation(f) => Some(f.type_id),
            ElementKind::GroupInstance(g) => Some(g.type_id),
            _ => None,
        }
    }

    /// Display name of an element type for any element ("Family: Type").
    pub fn type_name_of(&self, e: &Element) -> String {
        match &e.kind {
            ElementKind::Instance(i) => self.family_type(i.type_id).map(|(_, t)| t.name.clone()).unwrap_or_default(),
            ElementKind::GroupInstance(g) => self.group_types.iter().find(|t| t.id == g.type_id).map(|t| t.name.clone()).unwrap_or_default(),
            _ => self.type_of(e).and_then(|t| self.sys_type(t)).map(|t| t.name.clone()).unwrap_or_default(),
        }
    }

    pub fn family_name_of(&self, e: &Element) -> String {
        match &e.kind {
            ElementKind::Instance(i) => self.family(i.family_id).map(|f| f.name.clone()).unwrap_or_default(),
            ElementKind::Room(_) => "Room".into(),
            ElementKind::Level(_) => "Level".into(),
            ElementKind::Grid(_) => "Grid".into(),
            ElementKind::GroupInstance(_) => "Model Group".into(),
            _ => match self.type_of(e).and_then(|t| self.sys_type(t)) {
                Some(t) => t.family_name().into(),
                None => e.category().singular().into(),
            },
        }
    }

    pub fn display_name(&self, e: &Element) -> String {
        match &e.kind {
            ElementKind::Level(l) => l.name.clone(),
            ElementKind::Grid(g) => format!("Grid {}", g.name),
            ElementKind::Room(r) => format!("{} {}", r.name, r.number),
            ElementKind::Area(a) => format!("{} {}", a.name, a.number),
            ElementKind::RefPlane(r) => format!("Reference Plane {}", r.name),
            _ if self.type_of(e).is_none() => e.category().singular().to_string(),
            _ => format!("{}: {}", self.family_name_of(e), self.type_name_of(e)),
        }
    }

    pub fn phase_index(&self, id: Option<Id>) -> usize {
        match id {
            None => 0,
            Some(id) => self.phases.iter().position(|p| p.id == id).unwrap_or(0),
        }
    }

    /// Is an element part of the model visible in `view` given design options?
    pub fn option_visible(&self, view: &View, e: &Element) -> bool {
        let Some(opt) = e.design_option else { return true };
        for set in &self.option_sets {
            if set.options.iter().any(|o| o.id == opt) {
                let shown = view.options.get(&set.id).copied().or_else(|| set.options.iter().find(|o| o.primary).map(|o| o.id));
                return shown == Some(opt);
            }
        }
        true
    }
}

/// An open project with Revit-style transactions and undo/redo.
pub struct Document {
    pub data: Project,
    undo: Vec<(String, Project)>,
    redo: Vec<(String, Project)>,
    pub path: Option<std::path::PathBuf>,
    pub dirty: bool,
    /// Increments on every change; views use it to invalidate caches.
    pub revision: u64,
}

const MAX_UNDO: usize = 100;

impl Document {
    pub fn new(data: Project) -> Document {
        Document { data, undo: Vec::new(), redo: Vec::new(), path: None, dirty: false, revision: 1 }
    }

    /// Runs a named change. If `f` returns an error the model is rolled back.
    /// Constraints (locked/EQ dimensions, attached walls, hosted elements) are re-applied after `f`.
    pub fn transact<T>(&mut self, name: &str, f: impl FnOnce(&mut Project) -> Result<T, String>) -> Result<T, String> {
        let snapshot = self.data.clone();
        let result = f(&mut self.data).and_then(|v| crate::constraints::apply(&mut self.data, &snapshot).map(|_| v));
        match result {
            Ok(v) => {
                self.undo.push((name.to_string(), snapshot));
                if self.undo.len() > MAX_UNDO {
                    self.undo.remove(0);
                }
                self.redo.clear();
                self.dirty = true;
                self.revision += 1;
                Ok(v)
            }
            Err(e) => {
                self.data = snapshot;
                Err(e)
            }
        }
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }
    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }
    pub fn undo_name(&self) -> Option<&str> {
        self.undo.last().map(|u| u.0.as_str())
    }
    pub fn redo_name(&self) -> Option<&str> {
        self.redo.last().map(|u| u.0.as_str())
    }

    pub fn undo(&mut self) {
        if let Some((name, snap)) = self.undo.pop() {
            let current = std::mem::replace(&mut self.data, snap);
            self.redo.push((name, current));
            self.dirty = true;
            self.revision += 1;
        }
    }

    pub fn redo(&mut self) {
        if let Some((name, snap)) = self.redo.pop() {
            let current = std::mem::replace(&mut self.data, snap);
            self.undo.push((name, current));
            self.dirty = true;
            self.revision += 1;
        }
    }

    /// Number of undo steps (dialogs use it to group or discard their changes).
    pub fn undo_depth(&self) -> usize {
        self.undo.len()
    }

    /// Discards every change made after `depth` (a dialog's Cancel); nothing is left to redo.
    pub fn rollback_to(&mut self, depth: usize) {
        while self.undo.len() > depth {
            self.undo();
        }
        self.redo.clear();
    }

    /// Merges the changes made after `depth` into one undo step named `name` (a dialog's OK).
    pub fn squash_since(&mut self, depth: usize, name: &str) {
        if self.undo.len() > depth + 1 {
            let first = self.undo[depth].1.clone();
            self.undo.truncate(depth);
            self.undo.push((name.to_string(), first));
        } else if self.undo.len() == depth + 1 {
            self.undo[depth].0 = name.to_string();
        }
    }

    /// Records a change that should not be undoable (e.g. camera moves).
    pub fn touch(&mut self) {
        self.revision += 1;
    }
}
