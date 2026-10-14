//! Tools, draw modes, sketch mode and the sticky options shown in the Options Bar.

use rc_core::geom::{self, Arc2, DVec2};
use rc_core::model::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DrawMode {
    Line,
    Rect,
    PolyIn,
    PolyCirc,
    Circle,
    Arc3,
    ArcCenter,
    ArcTangent,
    Fillet,
    PickLines,
    PickWalls,
}

impl DrawMode {
    pub fn is_pick(self) -> bool {
        matches!(self, DrawMode::PickLines | DrawMode::PickWalls | DrawMode::Fillet)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolKind {
    Select,
    Wall,
    Door,
    Window,
    Component,
    Column,
    StructColumn,
    Beam,
    IsolatedFooting,
    WallFoundation,
    CeilingAuto,
    Room,
    Area,
    RoomTag,
    AreaTag,
    Grid,
    Level,
    RefPlane,
    ModelLine,
    DetailLine,
    RoomSeparator,
    AreaBoundary,
    /// Boundary segments of the active sketch.
    SketchLine,
    Text,
    Dimension(DimKind),
    Symbol,
    Tag,
    Section,
    Callout,
    ElevationMarker,
    CurtainGrid,
    WallOpening,
    PlaceGroup,
    Align,
    Offset,
    MirrorPick,
    MirrorDraw,
    Move,
    Copy,
    Rotate,
    TrimCorner,
    TrimSingle,
    TrimMulti,
    Split,
    SplitGap,
    Array,
    Scale,
    MatchType,
    Measure,
    ZoomRegion,
    AttachTop,
    AttachBase,
    PickHost,
    Paste,
    TopoPoints,
    ColorLegend,
    ScopeBox,
    Insulation,
    DetailComponent,
    JoinGeometry,
    UnjoinGeometry,
    ShowHiddenLines,
    RemoveHiddenLines,
    PlaceDetailGroup,
}

impl ToolKind {
    pub fn name(self) -> &'static str {
        match self {
            ToolKind::Select => "Modify",
            ToolKind::Wall => "Wall",
            ToolKind::Door => "Door",
            ToolKind::Window => "Window",
            ToolKind::Component => "Component",
            ToolKind::Column => "Column",
            ToolKind::StructColumn => "Structural Column",
            ToolKind::Beam => "Beam",
            ToolKind::IsolatedFooting => "Isolated Foundation",
            ToolKind::WallFoundation => "Wall Foundation",
            ToolKind::CeilingAuto => "Automatic Ceiling",
            ToolKind::Room => "Room",
            ToolKind::Area => "Area",
            ToolKind::RoomTag => "Room Tag",
            ToolKind::AreaTag => "Area Tag",
            ToolKind::Grid => "Grid",
            ToolKind::Level => "Level",
            ToolKind::RefPlane => "Reference Plane",
            ToolKind::ModelLine => "Lines",
            ToolKind::DetailLine => "Detail Lines",
            ToolKind::RoomSeparator => "Room Separation",
            ToolKind::AreaBoundary => "Area Boundary",
            ToolKind::SketchLine => "Boundary Line",
            ToolKind::Text => "Text",
            ToolKind::Dimension(k) => match k {
                DimKind::Aligned => "Aligned Dimension",
                DimKind::Linear => "Linear Dimension",
                DimKind::Angular => "Angular Dimension",
                DimKind::Radial => "Radial Dimension",
                DimKind::Diameter => "Diameter Dimension",
                DimKind::ArcLength => "Arc Length Dimension",
                DimKind::SpotElevation => "Spot Elevation",
                DimKind::SpotCoordinate => "Spot Coordinate",
                DimKind::SpotSlope => "Spot Slope",
            },
            ToolKind::Symbol => "Symbol",
            ToolKind::Tag => "Tag",
            ToolKind::Section => "Section",
            ToolKind::Callout => "Callout",
            ToolKind::ElevationMarker => "Elevation",
            ToolKind::CurtainGrid => "Curtain Grid",
            ToolKind::WallOpening => "Wall Opening",
            ToolKind::PlaceGroup => "Model Group",
            ToolKind::Align => "Align",
            ToolKind::Offset => "Offset",
            ToolKind::MirrorPick => "Mirror - Pick Axis",
            ToolKind::MirrorDraw => "Mirror - Draw Axis",
            ToolKind::Move => "Move",
            ToolKind::Copy => "Copy",
            ToolKind::Rotate => "Rotate",
            ToolKind::TrimCorner => "Trim/Extend to Corner",
            ToolKind::TrimSingle => "Trim/Extend Single Element",
            ToolKind::TrimMulti => "Trim/Extend Multiple Elements",
            ToolKind::Split => "Split Element",
            ToolKind::SplitGap => "Split with Gap",
            ToolKind::Array => "Array",
            ToolKind::Scale => "Scale",
            ToolKind::MatchType => "Match Type Properties",
            ToolKind::Measure => "Measure",
            ToolKind::ZoomRegion => "Zoom in Region",
            ToolKind::AttachTop => "Attach Top",
            ToolKind::AttachBase => "Attach Base",
            ToolKind::PickHost => "Pick New Host",
            ToolKind::Paste => "Paste",
            ToolKind::TopoPoints => "Modify Sub Elements",
            ToolKind::ColorLegend => "Color Fill Legend",
            ToolKind::ScopeBox => "Scope Box",
            ToolKind::Insulation => "Insulation",
            ToolKind::DetailComponent => "Detail Component",
            ToolKind::JoinGeometry => "Join Geometry",
            ToolKind::UnjoinGeometry => "Unjoin Geometry",
            ToolKind::ShowHiddenLines => "Show Hidden Lines",
            ToolKind::RemoveHiddenLines => "Remove Hidden Lines",
            ToolKind::PlaceDetailGroup => "Detail Group",
        }
    }

    /// Tools that draw curves and so use the draw-mode gallery.
    pub fn uses_draw_modes(self) -> bool {
        matches!(
            self,
            ToolKind::Wall
                | ToolKind::Beam
                | ToolKind::Grid
                | ToolKind::RefPlane
                | ToolKind::ModelLine
                | ToolKind::DetailLine
                | ToolKind::RoomSeparator
                | ToolKind::AreaBoundary
                | ToolKind::SketchLine
        )
    }

    /// Tools that work on the current selection.
    pub fn needs_selection(self) -> bool {
        matches!(
            self,
            ToolKind::Move | ToolKind::Copy | ToolKind::Rotate | ToolKind::MirrorPick | ToolKind::MirrorDraw | ToolKind::Array | ToolKind::Scale | ToolKind::AttachTop | ToolKind::AttachBase | ToolKind::PickHost
        )
    }

    /// Tools that place model elements on a level (need a plan view).
    pub fn needs_plan(self) -> bool {
        matches!(
            self,
            ToolKind::Wall
                | ToolKind::Door
                | ToolKind::Window
                | ToolKind::Component
                | ToolKind::Column
                | ToolKind::StructColumn
                | ToolKind::Beam
                | ToolKind::IsolatedFooting
                | ToolKind::WallFoundation
                | ToolKind::CeilingAuto
                | ToolKind::TopoPoints
                | ToolKind::ColorLegend
                | ToolKind::ScopeBox
                | ToolKind::Room
                | ToolKind::Area
                | ToolKind::RoomTag
                | ToolKind::AreaTag
                | ToolKind::Grid
                | ToolKind::RefPlane
                | ToolKind::ModelLine
                | ToolKind::RoomSeparator
                | ToolKind::AreaBoundary
                | ToolKind::Section
                | ToolKind::Callout
                | ToolKind::ElevationMarker
                | ToolKind::WallOpening
                | ToolKind::PlaceGroup
                | ToolKind::CurtainGrid
        )
    }
}

/// One sketch segment: a line or an arc through a mid point.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Seg {
    Line(DVec2, DVec2),
    Arc(DVec2, DVec2, DVec2),
}

impl Seg {
    pub fn start(&self) -> DVec2 {
        match self {
            Seg::Line(a, _) | Seg::Arc(a, _, _) => *a,
        }
    }
    pub fn end(&self) -> DVec2 {
        match self {
            Seg::Line(_, b) | Seg::Arc(_, _, b) => *b,
        }
    }
    pub fn reversed(&self) -> Seg {
        match *self {
            Seg::Line(a, b) => Seg::Line(b, a),
            Seg::Arc(a, m, b) => Seg::Arc(b, m, a),
        }
    }
    pub fn arc(&self) -> Option<Arc2> {
        match *self {
            Seg::Arc(a, m, b) => Arc2::through(a, m, b),
            _ => None,
        }
    }
    /// Polyline approximation (including both ends).
    pub fn points(&self) -> Vec<DVec2> {
        match self {
            Seg::Line(a, b) => vec![*a, *b],
            Seg::Arc(a, m, b) => match Arc2::through(*a, *m, *b) {
                Some(arc) => arc.tessellate(300.0),
                None => vec![*a, *b],
            },
        }
    }
    /// Direction of travel at the end.
    pub fn end_tangent(&self) -> DVec2 {
        match self {
            Seg::Line(a, b) => (*b - *a).normalize_or_zero(),
            Seg::Arc(a, m, b) => Arc2::through(*a, *m, *b).map(|x| x.tangent(1.0)).unwrap_or((*b - *a).normalize_or_zero()),
        }
    }
    pub fn distance_to(&self, q: DVec2) -> f64 {
        let pts = self.points();
        pts.windows(2).map(|w| geom::distance_to_segment(w[0], w[1], q)).fold(f64::MAX, f64::min)
    }
    pub fn translated(&self, d: DVec2) -> Seg {
        match *self {
            Seg::Line(a, b) => Seg::Line(a + d, b + d),
            Seg::Arc(a, m, b) => Seg::Arc(a + d, m + d, b + d),
        }
    }
    /// Offsets the segment to its left (positive) or right (negative).
    pub fn offset(&self, dist: f64) -> Seg {
        if dist.abs() < 1e-9 {
            return *self;
        }
        match *self {
            Seg::Line(a, b) => {
                let n = geom::perp((b - a).normalize_or_zero()) * dist;
                Seg::Line(a + n, b + n)
            }
            Seg::Arc(a, m, b) => match Arc2::through(a, m, b) {
                Some(arc) => {
                    // Left of travel is towards the centre for CCW arcs.
                    let s = if arc.sweep >= 0.0 { -1.0 } else { 1.0 };
                    let r = arc.radius + s * dist;
                    let f = |q: DVec2| arc.center + (q - arc.center).normalize_or_zero() * r;
                    Seg::Arc(f(a), f(m), f(b))
                }
                None => Seg::Line(a, b).offset(dist),
            },
        }
    }
}

/// What a sketch creates when finished.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SketchKind {
    Floor { structural: bool },
    Ceiling,
    Roof,
    RoofExtrusion,
    Region { masking: bool },
    Shaft,
    Railing,
    Stair,
    RevisionCloud,
    Mass,
    Toposolid,
    PropertyLine,
    EditFloor(Id),
    EditCeiling(Id),
    EditRoof(Id),
    EditRegion(Id),
}

impl SketchKind {
    pub fn title(self) -> &'static str {
        match self {
            SketchKind::Floor { .. } | SketchKind::EditFloor(_) => "Create Floor Boundary",
            SketchKind::Ceiling | SketchKind::EditCeiling(_) => "Create Ceiling Boundary",
            SketchKind::Roof | SketchKind::EditRoof(_) => "Create Roof Footprint",
            SketchKind::RoofExtrusion => "Create Extrusion Roof Profile",
            SketchKind::Region { .. } | SketchKind::EditRegion(_) => "Create Filled Region Boundary",
            SketchKind::Shaft => "Create Shaft Opening Sketch",
            SketchKind::Railing => "Create Railing Path",
            SketchKind::Stair => "Create Stair",
            SketchKind::RevisionCloud => "Create Revision Cloud Sketch",
            SketchKind::Mass => "Create Mass",
            SketchKind::Toposolid => "Create Toposolid Boundary",
            SketchKind::PropertyLine => "Create Property Line Sketch",
        }
    }
    pub fn is_roof(self) -> bool {
        matches!(self, SketchKind::Roof | SketchKind::EditRoof(_))
    }
}

#[derive(Clone, Debug)]
pub struct Sketch {
    pub kind: SketchKind,
    pub segs: Vec<Seg>,
    /// Roofs: does each segment define a slope.
    pub slopes: Vec<bool>,
    pub view: Id,
    pub level: Id,
    pub selected: Vec<usize>,
    /// Stairs: run width.
    pub width: f64,
}

impl Sketch {
    pub fn new(kind: SketchKind, view: Id, level: Id) -> Sketch {
        Sketch { kind, segs: Vec::new(), slopes: Vec::new(), view, level, selected: Vec::new(), width: 1200.0 }
    }

    pub fn push(&mut self, s: Seg, slope: bool) {
        self.segs.push(s);
        self.slopes.push(slope);
    }

    /// Orders the segments into closed loops (outer first by area). Errors name the problem
    /// like the sketch-mode warnings do.
    pub fn loops(&self) -> Result<Vec<(Vec<DVec2>, Vec<bool>)>, String> {
        if self.segs.is_empty() {
            return Err("The sketch is empty. Draw a closed boundary.".into());
        }
        let tol = 1.0;
        let mut used = vec![false; self.segs.len()];
        let mut loops = Vec::new();
        while let Some(first) = used.iter().position(|u| !u) {
            used[first] = true;
            let mut chain = vec![(self.segs[first], self.slopes.get(first).copied().unwrap_or(true))];
            loop {
                let end = chain.last().unwrap().0.end();
                if end.distance(chain[0].0.start()) <= tol && chain.len() >= 2 {
                    break;
                }
                let next = (0..self.segs.len()).find(|k| !used[*k] && (self.segs[*k].start().distance(end) <= tol || self.segs[*k].end().distance(end) <= tol));
                match next {
                    Some(k) => {
                        used[k] = true;
                        let s = if self.segs[k].start().distance(end) <= tol { self.segs[k] } else { self.segs[k].reversed() };
                        chain.push((s, self.slopes.get(k).copied().unwrap_or(true)));
                    }
                    None => return Err("The boundary lines must form closed loops. Lines that do not connect at their ends are highlighted.".into()),
                }
            }
            // Polygon with one slope flag per polygon edge.
            let mut pts = Vec::new();
            let mut flags = Vec::new();
            for (s, f) in &chain {
                let p = s.points();
                for q in &p[..p.len() - 1] {
                    pts.push(*q);
                    flags.push(*f);
                }
            }
            if pts.len() < 3 {
                return Err("A boundary loop needs at least three sides.".into());
            }
            loops.push((pts, flags));
        }
        // Self intersection check (non-adjacent edges).
        for (pts, _) in &loops {
            let n = pts.len();
            for i in 0..n {
                for j in i + 2..n {
                    if i == 0 && j == n - 1 {
                        continue;
                    }
                    if let Some((t, u)) = geom::segment_intersection(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]) {
                        if t > 1e-6 && t < 1.0 - 1e-6 && u > 1e-6 && u < 1.0 - 1e-6 {
                            return Err("The boundary lines intersect each other. Loops must not cross.".into());
                        }
                    }
                }
            }
        }
        loops.sort_by(|a, b| geom::area(&b.0).total_cmp(&geom::area(&a.0)));
        Ok(loops)
    }

    /// Open chain (railing paths): segments joined end to end in drawing order.
    pub fn chain(&self) -> Result<Vec<DVec2>, String> {
        if self.segs.is_empty() {
            return Err("The sketch is empty.".into());
        }
        let mut pts = self.segs[0].points();
        for s in &self.segs[1..] {
            let p = s.points();
            if p[0].distance(*pts.last().unwrap()) > 1.0 {
                return Err("The path must be one continuous chain of connected lines.".into());
            }
            pts.extend_from_slice(&p[1..]);
        }
        Ok(pts)
    }
}

/// The active tool and the points/elements picked so far.
#[derive(Clone, Debug)]
pub struct Tool {
    pub kind: ToolKind,
    pub pts: Vec<DVec2>,
    pub picked: Vec<Id>,
    pub refs: Vec<DimRef>,
    /// Elements the modify tool operates on (snapshot of the selection when it started).
    pub ids: Vec<Id>,
    /// End tangent of the previous drawn segment (tangent arcs, chains).
    pub tangent: Option<(DVec2, DVec2)>,
}

impl Tool {
    pub fn new(kind: ToolKind) -> Tool {
        Tool { kind, pts: Vec::new(), picked: Vec::new(), refs: Vec::new(), ids: Vec::new(), tangent: None }
    }
    pub fn select() -> Tool {
        Tool::new(ToolKind::Select)
    }
    pub fn is_select(&self) -> bool {
        self.kind == ToolKind::Select
    }
    /// Has the tool started an operation that Esc should cancel first?
    pub fn in_progress(&self) -> bool {
        !self.pts.is_empty() || !self.picked.is_empty() || !self.refs.is_empty()
    }
    pub fn reset(&mut self) {
        self.pts.clear();
        self.picked.clear();
        self.refs.clear();
        self.tangent = None;
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WallRefPref {
    Centers,
    Faces,
    CoreCenters,
    CoreFaces,
}

impl WallRefPref {
    pub const ALL: [WallRefPref; 4] = [WallRefPref::Centers, WallRefPref::Faces, WallRefPref::CoreCenters, WallRefPref::CoreFaces];
    pub fn label(self) -> &'static str {
        match self {
            WallRefPref::Centers => "Wall centerlines",
            WallRefPref::Faces => "Wall faces",
            WallRefPref::CoreCenters => "Center of core",
            WallRefPref::CoreFaces => "Faces of core",
        }
    }
}

/// Sticky tool options (the Options Bar remembers them between uses).
#[derive(Clone, Debug)]
pub struct ToolOptions {
    pub wall_type: Id,
    pub floor_type: Id,
    pub roof_type: Id,
    pub ceiling_type: Id,
    pub stair_type: Id,
    pub railing_type: Id,
    pub foundation_type: Id,
    pub door_type: Id,
    pub window_type: Id,
    pub component_type: Id,
    pub column_type: Id,
    pub struct_column_type: Id,
    pub beam_type: Id,
    pub footing_type: Id,
    pub group_type: Id,
    pub draw_mode: DrawMode,
    pub poly_sides: u32,
    /// Wall top: None = Unconnected (uses `wall_height`).
    pub wall_top: Option<Id>,
    pub wall_depth: bool,
    pub wall_height: f64,
    /// New walls: base and top offsets, room bounding (Properties palette while placing).
    pub wall_base_offset: f64,
    pub wall_top_offset: f64,
    pub wall_room_bounding: bool,
    /// New windows: sill height override (None = the type's default).
    pub window_sill: Option<f64>,
    pub location_line: LocationLine,
    pub chain: bool,
    pub offset: f64,
    pub radius: f64,
    pub tag_on_placement: bool,
    pub rotation: f64,
    pub column_top: Option<Id>,
    pub column_height: f64,
    pub defines_slope: bool,
    pub overhang: f64,
    pub roof_slope: f64,
    pub make_plan: bool,
    pub constrain: bool,
    pub copy_multiple: bool,
    pub rotate_copy: bool,
    pub mirror_copy: bool,
    pub array_radial: bool,
    pub array_count: u32,
    pub array_last: bool,
    pub scale_factor: f64,
    pub offset_dist: f64,
    pub offset_copy: bool,
    /// Offset by two clicked points instead of a typed distance.
    pub offset_graphical: bool,
    pub align_multiple: bool,
    pub align_prefer: WallRefPref,
    pub split_gap: f64,
    pub tag_leader: bool,
    pub tag_horizontal: bool,
    /// Tag tool variant: 0 by category, 1 multi-category, 2 material.
    pub tag_mode: u8,
    pub insulation_width: f64,
    /// Join Geometry: join more elements to the first pick.
    pub join_multiple: bool,
    /// Index into `DETAIL_COMPONENTS`.
    pub detail_component: usize,
    pub dim_prefer: WallRefPref,
    pub text_size: f64,
    pub text_bold: bool,
    pub line_style: LineStyle,
    pub fill_pattern: FillPattern,
    pub fill_color: [u8; 3],
    pub symbol_kind: SymbolKind,
    pub stair_width: f64,
    pub room_tag: bool,
    pub room_upper: f64,
    pub mass_height: f64,
    pub topo_height: f64,
    pub topo_thickness: f64,
    /// Modify Sub Elements: elevation given to clicked toposolid points.
    pub topo_point_height: f64,
    pub section_depth: f64,
    pub opening_height: f64,
    pub opening_sill: f64,
    pub wall_structural: bool,
    /// Doors/windows: Space flips the facing while placing.
    pub place_flip: bool,
}

impl ToolOptions {
    pub fn for_project(p: &Project) -> ToolOptions {
        let first_sys = |c: Category| p.types_of(c).next().map(|t| t.id).unwrap_or(0);
        let first_fam = |c: Category| p.families.iter().filter(|f| f.category == c).find_map(|f| f.types.get(f.types.len() / 2)).map(|t| t.id).unwrap_or(0);
        let wall = p.types_of(Category::Walls).find(|t| t.wall_kind == WallKind::Basic && t.function == WallFunction::Exterior).map(|t| t.id).unwrap_or(first_sys(Category::Walls));
        let imperial = p.units.system == rc_core::units::UnitSystem::Imperial;
        let comp = p.families.iter().filter(|f| matches!(f.category, Category::Furniture | Category::Casework | Category::PlumbingFixtures | Category::SpecialtyEquipment | Category::GenericModels)).find_map(|f| f.types.first()).map(|t| t.id).unwrap_or(0);
        ToolOptions {
            wall_type: wall,
            floor_type: first_sys(Category::Floors),
            roof_type: first_sys(Category::Roofs),
            ceiling_type: first_sys(Category::Ceilings),
            stair_type: first_sys(Category::Stairs),
            railing_type: first_sys(Category::Railings),
            foundation_type: first_sys(Category::StructuralFoundations),
            door_type: first_fam(Category::Doors),
            window_type: first_fam(Category::Windows),
            component_type: comp,
            column_type: first_fam(Category::Columns),
            struct_column_type: first_fam(Category::StructuralColumns),
            beam_type: first_fam(Category::StructuralFraming),
            footing_type: first_fam(Category::StructuralFoundations),
            group_type: p.group_types.first().map(|g| g.id).unwrap_or(0),
            draw_mode: DrawMode::Line,
            poly_sides: 6,
            wall_top: None,
            wall_depth: false,
            // The Wall tool starts Unconnected at 20'-0" (8000 mm in metric), as in the reference app.
            wall_height: if imperial { 6096.0 } else { 8000.0 },
            wall_base_offset: 0.0,
            wall_top_offset: 0.0,
            wall_room_bounding: true,
            window_sill: None,
            location_line: LocationLine::WallCenterline,
            chain: true,
            offset: 0.0,
            radius: if imperial { 1828.8 } else { 2000.0 },
            tag_on_placement: false,
            rotation: 0.0,
            column_top: None,
            column_height: if imperial { 3048.0 } else { 3000.0 },
            defines_slope: true,
            overhang: if imperial { 609.6 } else { 600.0 },
            roof_slope: 30.0,
            make_plan: true,
            constrain: false,
            copy_multiple: false,
            rotate_copy: false,
            mirror_copy: true,
            array_radial: false,
            array_count: 3,
            array_last: false,
            scale_factor: 2.0,
            offset_dist: if imperial { 304.8 } else { 1000.0 },
            offset_copy: true,
            offset_graphical: false,
            align_multiple: false,
            align_prefer: WallRefPref::Faces,
            split_gap: if imperial { 25.4 } else { 25.0 },
            tag_leader: false,
            tag_horizontal: true,
            tag_mode: 0,
            insulation_width: if imperial { 76.2 } else { 75.0 },
            join_multiple: false,
            detail_component: 0,
            dim_prefer: WallRefPref::Centers,
            text_size: 2.5,
            text_bold: false,
            line_style: LineStyle::Medium,
            fill_pattern: FillPattern::Diagonal,
            fill_color: [0, 0, 0],
            symbol_kind: SymbolKind::NorthArrow,
            stair_width: if imperial { 1066.8 } else { 1200.0 },
            room_tag: true,
            room_upper: if imperial { 2438.4 } else { 2500.0 },
            mass_height: if imperial { 9144.0 } else { 10000.0 },
            topo_height: 0.0,
            topo_thickness: if imperial { 3048.0 } else { 3000.0 },
            topo_point_height: 0.0,
            section_depth: 15000.0,
            opening_height: 2100.0,
            opening_sill: 0.0,
            wall_structural: false,
            place_flip: false,
        }
    }

    /// Re-validates remembered types after undo, imports or deletes.
    pub fn validate(&mut self, p: &Project) {
        let fresh = ToolOptions::for_project(p);
        let sys = |id: &mut Id, f: Id| {
            if p.sys_type(*id).is_none() {
                *id = f;
            }
        };
        sys(&mut self.wall_type, fresh.wall_type);
        sys(&mut self.floor_type, fresh.floor_type);
        sys(&mut self.roof_type, fresh.roof_type);
        sys(&mut self.ceiling_type, fresh.ceiling_type);
        sys(&mut self.stair_type, fresh.stair_type);
        sys(&mut self.railing_type, fresh.railing_type);
        sys(&mut self.foundation_type, fresh.foundation_type);
        let fam = |id: &mut Id, f: Id| {
            if p.family_type(*id).is_none() {
                *id = f;
            }
        };
        fam(&mut self.door_type, fresh.door_type);
        fam(&mut self.window_type, fresh.window_type);
        fam(&mut self.component_type, fresh.component_type);
        fam(&mut self.column_type, fresh.column_type);
        fam(&mut self.struct_column_type, fresh.struct_column_type);
        fam(&mut self.beam_type, fresh.beam_type);
        fam(&mut self.footing_type, fresh.footing_type);
        if !p.group_types.iter().any(|g| g.id == self.group_type) {
            self.group_type = fresh.group_type;
        }
        if self.wall_top.is_some_and(|l| p.level(l).is_none()) {
            self.wall_top = None;
        }
        if self.column_top.is_some_and(|l| p.level(l).is_none()) {
            self.column_top = None;
        }
    }
}

/// Converts clicks in a draw mode into segments. Returns the finished segments once enough
/// points are collected; `pts` keeps the points of the shape in progress.
pub fn draw_step(mode: DrawMode, pts: &mut Vec<DVec2>, click: DVec2, sides: u32, tangent: Option<(DVec2, DVec2)>, chain: bool) -> Option<Vec<Seg>> {
    match mode {
        DrawMode::Line => {
            if pts.is_empty() {
                pts.push(click);
                return None;
            }
            let a = pts[0];
            if a.distance(click) < 1.0 {
                return None;
            }
            pts.clear();
            if chain {
                pts.push(click);
            }
            Some(vec![Seg::Line(a, click)])
        }
        DrawMode::Rect => {
            if pts.is_empty() {
                pts.push(click);
                return None;
            }
            let a = pts[0];
            pts.clear();
            if (a.x - click.x).abs() < 1.0 || (a.y - click.y).abs() < 1.0 {
                return None;
            }
            let c = [a, DVec2::new(click.x, a.y), click, DVec2::new(a.x, click.y)];
            Some((0..4).map(|k| Seg::Line(c[k], c[(k + 1) % 4])).collect())
        }
        DrawMode::PolyIn | DrawMode::PolyCirc => {
            if pts.is_empty() {
                pts.push(click);
                return None;
            }
            let c = pts[0];
            pts.clear();
            let v = polygon_vertices(c, click, sides, mode == DrawMode::PolyCirc);
            if v.is_empty() {
                return None;
            }
            let n = v.len();
            Some((0..n).map(|k| Seg::Line(v[k], v[(k + 1) % n])).collect())
        }
        DrawMode::Circle => {
            if pts.is_empty() {
                pts.push(click);
                return None;
            }
            let c = pts[0];
            pts.clear();
            let r = c.distance(click);
            if r < 1.0 {
                return None;
            }
            let p = |a: f64| c + DVec2::new(a.cos(), a.sin()) * r;
            use std::f64::consts::PI;
            Some(vec![Seg::Arc(p(0.0), p(PI / 2.0), p(PI)), Seg::Arc(p(PI), p(1.5 * PI), p(0.0))])
        }
        DrawMode::Arc3 => {
            if pts.len() < 2 {
                if pts.last().is_none_or(|l| l.distance(click) > 1.0) {
                    pts.push(click);
                }
                return None;
            }
            let (a, b) = (pts[0], pts[1]);
            pts.clear();
            if chain {
                pts.push(b);
            }
            Arc2::through(a, click, b).map(|arc| vec![Seg::Arc(a, arc.mid(), b)]).or(Some(vec![Seg::Line(a, b)]))
        }
        DrawMode::ArcCenter => {
            if pts.len() < 2 {
                pts.push(click);
                return None;
            }
            let (c, s) = (pts[0], pts[1]);
            pts.clear();
            let r = c.distance(s);
            let e = c + (click - c).normalize_or_zero() * r;
            let arc = Arc2::from_center(c, s, e, true);
            Some(vec![Seg::Arc(s, arc.mid(), e)])
        }
        DrawMode::ArcTangent => {
            let Some((start, dir)) = tangent.or_else(|| pts.first().map(|p| (*p, DVec2::ZERO))) else {
                pts.push(click);
                return None;
            };
            if dir == DVec2::ZERO {
                // No previous segment: behave like a line start.
                pts.clear();
                pts.push(start);
                return draw_step(DrawMode::Line, pts, click, sides, None, chain);
            }
            pts.clear();
            tangent_arc(start, dir, click).map(|s| vec![s])
        }
        DrawMode::Fillet | DrawMode::PickLines | DrawMode::PickWalls => None,
    }
}

/// Vertices of a regular polygon centred at `c` with a vertex (inscribed) or edge midpoint
/// (circumscribed) towards `toward`.
pub fn polygon_vertices(c: DVec2, toward: DVec2, sides: u32, circumscribed: bool) -> Vec<DVec2> {
    let n = sides.clamp(3, 64) as usize;
    let r0 = c.distance(toward);
    if r0 < 1.0 {
        return vec![];
    }
    let a0 = (toward - c).y.atan2((toward - c).x);
    let step = std::f64::consts::TAU / n as f64;
    let (r, start) = if circumscribed { (r0 / (step / 2.0).cos(), a0 + step / 2.0) } else { (r0, a0) };
    (0..n).map(|k| c + DVec2::new((start + step * k as f64).cos(), (start + step * k as f64).sin()) * r).collect()
}

/// Arc starting at `start` with tangent `dir` ending at `end`.
pub fn tangent_arc(start: DVec2, dir: DVec2, end: DVec2) -> Option<Seg> {
    let chord = end - start;
    if chord.length() < 1.0 {
        return None;
    }
    let n = geom::perp(dir);
    let denom = 2.0 * chord.dot(n);
    if denom.abs() < 1e-9 {
        return Some(Seg::Line(start, end));
    }
    let r = chord.dot(chord) / denom;
    let center = start + n * r;
    let ccw = r > 0.0;
    let arc = Arc2::from_center(center, start, end, ccw);
    Some(Seg::Arc(start, arc.mid(), end))
}

/// Preview of the shape in progress for the current cursor point.
pub fn preview(mode: DrawMode, pts: &[DVec2], cursor: DVec2, sides: u32, tangent: Option<(DVec2, DVec2)>) -> Vec<Seg> {
    let mut tmp = pts.to_vec();
    match mode {
        DrawMode::Arc3 if pts.len() == 1 => vec![Seg::Line(pts[0], cursor)],
        DrawMode::ArcCenter if pts.len() == 1 => vec![Seg::Line(pts[0], cursor)],
        DrawMode::ArcTangent if tangent.is_none() && pts.is_empty() => vec![],
        _ if mode.is_pick() => vec![],
        _ if pts.is_empty() && mode != DrawMode::ArcTangent => vec![],
        _ => draw_step(mode, &mut tmp, cursor, sides, tangent, false).unwrap_or_default(),
    }
}

/// Fillet between two lines: trims them back and returns (new end of a, new end of b, arc).
pub fn fillet(a: (DVec2, DVec2), b: (DVec2, DVec2), radius: f64) -> Option<(DVec2, DVec2, Seg)> {
    let da = (a.1 - a.0).normalize_or_zero();
    let db = (b.1 - b.0).normalize_or_zero();
    let corner = geom::line_intersection(a.0, da, b.0, db)?;
    // Directions away from the corner along each line (towards the kept part).
    let ua = if a.0.distance(corner) > a.1.distance(corner) { (a.0 - corner).normalize_or_zero() } else { (a.1 - corner).normalize_or_zero() };
    let ub = if b.0.distance(corner) > b.1.distance(corner) { (b.0 - corner).normalize_or_zero() } else { (b.1 - corner).normalize_or_zero() };
    let half = ua.dot(ub).clamp(-1.0, 1.0).acos() / 2.0;
    if half < 1e-3 || half > std::f64::consts::FRAC_PI_2 - 1e-3 {
        return None;
    }
    let t = radius / half.tan();
    let pa = corner + ua * t;
    let pb = corner + ub * t;
    let bis = (ua + ub).normalize_or_zero();
    let center = corner + bis * (radius / half.sin());
    let mid = center + (corner - center).normalize_or_zero() * radius;
    Some((pa, pb, Seg::Arc(pa, mid, pb)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rectangle_and_polygon_modes() {
        let mut pts = vec![];
        assert!(draw_step(DrawMode::Rect, &mut pts, DVec2::ZERO, 6, None, false).is_none());
        let segs = draw_step(DrawMode::Rect, &mut pts, DVec2::new(4000.0, 3000.0), 6, None, false).unwrap();
        assert_eq!(segs.len(), 4);
        let mut s = Sketch::new(SketchKind::Floor { structural: false }, 1, 1);
        for g in segs {
            s.push(g, true);
        }
        let loops = s.loops().unwrap();
        assert!((geom::area(&loops[0].0) - 12e6).abs() < 1.0);
        let v = polygon_vertices(DVec2::ZERO, DVec2::new(1000.0, 0.0), 4, true);
        assert!((v[0].length() - 1000.0 * 2f64.sqrt()).abs() < 1e-6);
    }

    #[test]
    fn open_sketch_reports_error_and_fillet_trims() {
        let mut s = Sketch::new(SketchKind::Floor { structural: false }, 1, 1);
        s.push(Seg::Line(DVec2::ZERO, DVec2::new(1000.0, 0.0)), true);
        s.push(Seg::Line(DVec2::new(1000.0, 0.0), DVec2::new(1000.0, 1000.0)), true);
        assert!(s.loops().is_err());
        let (pa, pb, arc) = fillet((DVec2::new(-5000.0, 0.0), DVec2::ZERO), (DVec2::ZERO, DVec2::new(0.0, 5000.0)), 1000.0).unwrap();
        assert!((pa - DVec2::new(-1000.0, 0.0)).length() < 1e-6);
        assert!((pb - DVec2::new(0.0, 1000.0)).length() < 1e-6);
        assert!((arc.arc().unwrap().radius - 1000.0).abs() < 1e-6);
    }

    #[test]
    fn tangent_arc_continues_direction() {
        let s = tangent_arc(DVec2::ZERO, DVec2::X, DVec2::new(1000.0, 1000.0)).unwrap();
        let arc = s.arc().unwrap();
        assert!((arc.tangent(0.0) - DVec2::X).length() < 1e-6);
        assert!((arc.radius - 1000.0).abs() < 1e-6);
    }
}
