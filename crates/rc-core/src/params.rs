//! Element parameters: what the Properties palette shows and schedules list as fields.

use crate::analysis;
use crate::annotation;
use crate::build3d;
use crate::family_params::Resolver;
use crate::geom::{self, DVec2};
use crate::model::*;
use crate::units;

#[derive(Clone, Debug, PartialEq)]
pub enum PKind {
    Value(ParamKind),
    /// A level picked by name.
    Level,
    /// One of a fixed list of strings.
    Choice(Vec<String>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParamDef {
    pub name: String,
    pub group: String,
    pub kind: PKind,
    pub read_only: bool,
    /// Belongs to the element's type: shown under "Edit Type", and editing it affects all instances.
    pub type_param: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Num(f64),
    Text(String),
}

impl Value {
    pub fn as_num(&self) -> Option<f64> {
        match self {
            Value::Num(v) => Some(*v),
            Value::Text(_) => None,
        }
    }
}

fn def(name: &str, group: &str, kind: PKind, read_only: bool, type_param: bool) -> ParamDef {
    ParamDef { name: name.into(), group: group.into(), kind, read_only, type_param }
}
fn v(k: ParamKind) -> PKind {
    PKind::Value(k)
}

const CONSTRAINTS: &str = "Constraints";
const DIMENSIONS: &str = "Dimensions";
const IDENTITY: &str = "Identity Data";
const CONSTRUCTION: &str = "Construction";
const STRUCTURAL: &str = "Structural";
const PHASING: &str = "Phasing";
const GRAPHICS: &str = "Graphics";
const TEXT: &str = "Text";
const OTHER: &str = "Other";
const MATERIALS: &str = "Materials and Finishes";

fn type_identity(d: &mut Vec<ParamDef>) {
    d.push(def("Family", IDENTITY, v(ParamKind::Text), true, true));
    d.push(def("Type", IDENTITY, v(ParamKind::Text), true, true));
    d.push(def("Family and Type", IDENTITY, v(ParamKind::Text), true, true));
}

fn system_type_params(d: &mut Vec<ParamDef>) {
    d.push(def("Type Mark", IDENTITY, v(ParamKind::Text), false, true));
    d.push(def("Description", IDENTITY, v(ParamKind::Text), false, true));
    d.push(def("Cost", IDENTITY, v(ParamKind::Currency), false, true));
}

fn mark_comments(d: &mut Vec<ParamDef>) {
    d.push(def("Mark", IDENTITY, v(ParamKind::Text), false, false));
    d.push(def("Comments", IDENTITY, v(ParamKind::Text), false, false));
}

fn phasing(p: &Project, d: &mut Vec<ParamDef>) {
    if p.phases.is_empty() {
        return;
    }
    let names: Vec<String> = p.phases.iter().map(|ph| ph.name.clone()).collect();
    d.push(def("Phase Created", PHASING, PKind::Choice(names.clone()), false, false));
    let mut demo = vec!["None".to_string()];
    demo.extend(names);
    d.push(def("Phase Demolished", PHASING, PKind::Choice(demo), false, false));
}

fn top_choices(p: &Project) -> PKind {
    let mut c = vec!["Unconnected".to_string()];
    c.extend(p.levels().iter().map(|(_, l)| l.name.clone()));
    PKind::Choice(c)
}

fn choice<T: Copy>(all: &[T], label: fn(T) -> &'static str) -> PKind {
    PKind::Choice(all.iter().map(|x| label(*x).to_string()).collect())
}

/// All parameters of an element (instance and type).
pub fn element_params(p: &Project, e: &Element) -> Vec<ParamDef> {
    use ParamKind::*;
    let mut d = Vec::new();
    match &e.kind {
        ElementKind::Level(_) => {
            d.push(def("Name", IDENTITY, v(Text), false, false));
            d.push(def("Elevation", CONSTRAINTS, v(Length), false, false));
            d.push(def("Building Story", OTHER, v(YesNo), false, false));
        }
        ElementKind::Grid(_) => {
            d.push(def("Name", IDENTITY, v(Text), false, false));
            d.push(def("Bubble at Start", GRAPHICS, v(YesNo), false, false));
            d.push(def("Bubble at End", GRAPHICS, v(YesNo), false, false));
        }
        ElementKind::RefPlane(_) => d.push(def("Name", IDENTITY, v(Text), false, false)),
        ElementKind::Wall(w) => {
            type_identity(&mut d);
            d.push(def("Location Line", CONSTRAINTS, choice(&LocationLine::ALL, LocationLine::label), false, false));
            d.push(def("Base Constraint", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Top Constraint", CONSTRAINTS, top_choices(p), false, false));
            d.push(def("Top Offset", CONSTRAINTS, v(Length), w.top_level.is_none(), false));
            d.push(def("Unconnected Height", CONSTRAINTS, v(Length), w.top_level.is_some(), false));
            d.push(def("Top is Attached", CONSTRAINTS, v(YesNo), true, false));
            d.push(def("Room Bounding", CONSTRAINTS, v(YesNo), false, false));
            d.push(def("Structural", STRUCTURAL, v(YesNo), false, false));
            d.push(def("Length", DIMENSIONS, v(Length), w.arc_mid.is_some(), false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Volume", DIMENSIONS, v(Volume), true, false));
            d.push(def("Width", CONSTRUCTION, v(Length), true, true));
            d.push(def("Function", CONSTRUCTION, v(Text), true, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Floor(_) => {
            type_identity(&mut d);
            d.push(def("Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Height Offset From Level", CONSTRAINTS, v(Length), false, false));
            d.push(def("Room Bounding", CONSTRAINTS, v(YesNo), true, false));
            d.push(def("Structural", STRUCTURAL, v(YesNo), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Perimeter", DIMENSIONS, v(Length), true, false));
            d.push(def("Volume", DIMENSIONS, v(Volume), true, false));
            d.push(def("Thickness", DIMENSIONS, v(Length), true, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Roof(_) => {
            type_identity(&mut d);
            d.push(def("Base Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset From Level", CONSTRAINTS, v(Length), false, false));
            d.push(def("Roof Shape", CONSTRUCTION, choice(&RoofShape::ALL, RoofShape::label), false, false));
            d.push(def("Slope", CONSTRUCTION, v(Angle), false, false));
            d.push(def("Overhang", CONSTRUCTION, v(Length), false, false));
            d.push(def("Fascia", CONSTRUCTION, v(YesNo), false, false));
            d.push(def("Gutter", CONSTRUCTION, v(YesNo), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Thickness", DIMENSIONS, v(Length), true, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Ceiling(_) => {
            type_identity(&mut d);
            d.push(def("Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Height Offset From Level", CONSTRAINTS, v(Length), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Perimeter", DIMENSIONS, v(Length), true, false));
            d.push(def("Thickness", DIMENSIONS, v(Length), true, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Stair(_) => {
            type_identity(&mut d);
            d.push(def("Base Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Top Level", CONSTRAINTS, top_choices(p), false, false));
            d.push(def("Top Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Desired Stair Height", CONSTRAINTS, v(Length), true, false));
            d.push(def("Desired Number of Risers", DIMENSIONS, v(Integer), false, false));
            d.push(def("Actual Number of Risers", DIMENSIONS, v(Integer), true, false));
            d.push(def("Actual Riser Height", DIMENSIONS, v(Length), true, false));
            d.push(def("Actual Tread Depth", DIMENSIONS, v(Length), true, false));
            d.push(def("Maximum Riser Height", CONSTRUCTION, v(Length), false, true));
            d.push(def("Minimum Tread Depth", CONSTRUCTION, v(Length), false, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Railing(_) => {
            type_identity(&mut d);
            d.push(def("Base Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Length", DIMENSIONS, v(Length), true, false));
            d.push(def("Railing Height", CONSTRUCTION, v(Length), false, true));
            d.push(def("Baluster Spacing", CONSTRUCTION, v(Length), false, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Mass(_) => {
            d.push(def("Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Height", DIMENSIONS, v(Length), false, false));
            d.push(def("Gross Floor Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Gross Surface Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Gross Volume", DIMENSIONS, v(Volume), true, false));
            d.push(def("Name", IDENTITY, v(Text), false, false));
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Toposolid(_) => {
            d.push(def("Level", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Height Offset From Level", CONSTRAINTS, v(Length), false, false));
            d.push(def("Thickness", DIMENSIONS, v(Length), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Volume", DIMENSIONS, v(Volume), true, false));
            d.push(def("Material", MATERIALS, v(Material), false, false));
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::PropertyLine(_) => {
            d.push(def("Name", IDENTITY, v(Text), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Perimeter", DIMENSIONS, v(Length), true, false));
        }
        ElementKind::ColorLegend(_) => {}
        ElementKind::Shaft(s) => {
            d.push(def("Base Constraint", CONSTRAINTS, PKind::Level, false, false));
            d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Top Constraint", CONSTRAINTS, top_choices(p), false, false));
            d.push(def("Top Offset", CONSTRAINTS, v(Length), s.top_level.is_none(), false));
            d.push(def("Unconnected Height", CONSTRAINTS, v(Length), s.top_level.is_some(), false));
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::WallFoundation(_) => {
            type_identity(&mut d);
            d.push(def("Length", DIMENSIONS, v(Length), true, false));
            d.push(def("Width", DIMENSIONS, v(Length), false, true));
            d.push(def("Foundation Thickness", DIMENSIONS, v(Length), false, true));
            system_type_params(&mut d);
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Room(_) => {
            d.push(def("Number", IDENTITY, v(Text), false, false));
            d.push(def("Name", IDENTITY, v(Text), false, false));
            d.push(def("Level", CONSTRAINTS, PKind::Level, true, false));
            d.push(def("Limit Offset", CONSTRAINTS, v(Length), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Perimeter", DIMENSIONS, v(Length), true, false));
            d.push(def("Volume", DIMENSIONS, v(Volume), true, false));
            d.push(def("Department", IDENTITY, v(Text), false, false));
            d.push(def("Occupancy", IDENTITY, v(Text), false, false));
            d.push(def("Floor Finish", IDENTITY, v(Text), false, false));
            d.push(def("Wall Finish", IDENTITY, v(Text), false, false));
            d.push(def("Ceiling Finish", IDENTITY, v(Text), false, false));
            d.push(def("Comments", IDENTITY, v(Text), false, false));
            phasing(p, &mut d);
        }
        ElementKind::Area(_) => {
            d.push(def("Number", IDENTITY, v(Text), false, false));
            d.push(def("Name", IDENTITY, v(Text), false, false));
            d.push(def("Area Type", IDENTITY, v(Text), false, false));
            d.push(def("Level", CONSTRAINTS, PKind::Level, true, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Perimeter", DIMENSIONS, v(Length), true, false));
            d.push(def("Comments", IDENTITY, v(Text), false, false));
        }
        ElementKind::Instance(i) => {
            type_identity(&mut d);
            let fam = p.family(i.family_id);
            let hosted = i.host.is_some();
            let column = fam.is_some_and(|f| f.is_column());
            let framing = fam.is_some_and(|f| f.is_framing());
            if framing {
                d.push(def("Reference Level", CONSTRAINTS, PKind::Level, false, false));
                d.push(def("Start Level Offset", CONSTRAINTS, v(Length), false, false));
                d.push(def("End Level Offset", CONSTRAINTS, v(Length), false, false));
                d.push(def("Length", DIMENSIONS, v(Length), true, false));
            } else if column {
                d.push(def("Base Level", CONSTRAINTS, PKind::Level, false, false));
                d.push(def("Base Offset", CONSTRAINTS, v(Length), false, false));
                d.push(def("Top Level", CONSTRAINTS, top_choices(p), false, false));
                d.push(def("Top Offset", CONSTRAINTS, v(Length), i.top_level.is_none(), false));
                d.push(def("Moves With Grids", CONSTRAINTS, v(YesNo), false, false));
                d.push(def("Rotation", CONSTRAINTS, v(Angle), false, false));
            } else {
                d.push(def("Level", CONSTRAINTS, PKind::Level, hosted, false));
            }
            if hosted {
                d.push(def("Host", CONSTRAINTS, v(Text), true, false));
                d.push(def("Sill Height", CONSTRAINTS, v(Length), false, false));
                d.push(def("Head Height", CONSTRAINTS, v(Length), true, false));
                d.push(def("Flip Facing", CONSTRUCTION, v(YesNo), false, false));
                d.push(def("Flip Hand", CONSTRUCTION, v(YesNo), false, false));
            } else if !column && !framing {
                d.push(def("Offset from Level", CONSTRAINTS, v(Length), false, false));
                d.push(def("Rotation", CONSTRAINTS, v(Angle), false, false));
            }
            if let Some(f) = fam {
                for fp in &f.params {
                    let type_only = fp.name.eq_ignore_ascii_case("Default Sill Height") || !fp.instance;
                    d.push(def(&fp.name, &fp.group, v(fp.kind), !fp.formula.is_empty() || fp.reporting, type_only));
                }
            }
            mark_comments(&mut d);
            phasing(p, &mut d);
        }
        ElementKind::Line(_) => {
            d.push(def("Line Style", GRAPHICS, choice(&LineStyle::ALL, LineStyle::label), false, false));
            d.push(def("Length", DIMENSIONS, v(Length), true, false));
            d.push(def("Comments", IDENTITY, v(Text), false, false));
        }
        ElementKind::RoomSeparation(_) | ElementKind::AreaBoundary(_) => {
            d.push(def("Length", DIMENSIONS, v(Length), true, false));
            d.push(def("Comments", IDENTITY, v(Text), false, false));
        }
        ElementKind::Dimension(_) => {
            d.push(def("Value", DIMENSIONS, v(Length), true, false));
            d.push(def("EQ", GRAPHICS, v(YesNo), false, false));
            d.push(def("Prefix", TEXT, v(Text), false, false));
            d.push(def("Suffix", TEXT, v(Text), false, false));
            d.push(def("Text Override", TEXT, v(Text), false, false));
            d.push(def("Label", OTHER, v(Text), false, false));
        }
        ElementKind::Tag(_) => {
            d.push(def("Leader Line", GRAPHICS, v(YesNo), false, false));
            d.push(def("Tag Parameter", GRAPHICS, PKind::Choice(["Mark", "Type Mark", "Name", "Number", "Family and Type", "Area", "Comments"].iter().map(|s| s.to_string()).collect()), false, false));
            d.push(def("Tagged Element", IDENTITY, v(Text), true, false));
        }
        ElementKind::Text(_) => {
            d.push(def("Text", TEXT, v(Text), false, false));
            d.push(def("Text Size", TEXT, v(Number), false, false));
            d.push(def("Bold", TEXT, v(YesNo), false, false));
            d.push(def("Rotation", GRAPHICS, v(Angle), false, false));
        }
        ElementKind::Region(_) => {
            d.push(def("Fill Pattern", GRAPHICS, choice(&FillPattern::ALL, FillPattern::label), false, false));
            d.push(def("Colour", GRAPHICS, v(Text), false, false));
            d.push(def("Area", DIMENSIONS, v(Area), true, false));
            d.push(def("Comments", IDENTITY, v(Text), false, false));
        }
        ElementKind::Symbol(_) => {
            d.push(def("Rotation", GRAPHICS, v(Angle), false, false));
            d.push(def("Value", TEXT, v(Text), false, false));
        }
        ElementKind::GroupInstance(_) => {
            type_identity(&mut d);
            d.push(def("Reference Level", CONSTRAINTS, PKind::Level, true, false));
            d.push(def("Rotation", CONSTRAINTS, v(Angle), true, false));
        }
        ElementKind::Cad(_) => {
            d.push(def("Name", IDENTITY, v(Text), true, false));
            d.push(def("Halftone", GRAPHICS, v(YesNo), false, false));
        }
    }
    d
}

/// Fields available for a schedule of the given category ("Count" is always available).
pub fn category_fields(p: &Project, c: Category) -> Vec<ParamDef> {
    let mut out: Vec<ParamDef> = Vec::new();
    let mut add = |defs: Vec<ParamDef>| {
        for d in defs {
            if !out.iter().any(|o| o.name == d.name) {
                out.push(d);
            }
        }
    };
    let proto = prototype(p, c);
    for e in proto.iter().chain(p.elements.iter().filter(|e| e.category() == c)) {
        add(element_params(p, e));
    }
    out.push(def("Count", IDENTITY, v(ParamKind::Integer), true, false));
    out
}

fn prototype(p: &Project, c: Category) -> Vec<Element> {
    let lvl = p.levels().first().map(|l| l.0).unwrap_or(0);
    let k = match c {
        Category::Walls => Some(ElementKind::Wall(Wall { base_level: lvl, end: DVec2::X, ..Default::default() })),
        Category::Floors => Some(ElementKind::Floor(Floor { level: lvl, ..Default::default() })),
        Category::Roofs => Some(ElementKind::Roof(Roof { level: lvl, ..Default::default() })),
        Category::Ceilings => Some(ElementKind::Ceiling(Ceiling { level: lvl, ..Default::default() })),
        Category::Stairs => Some(ElementKind::Stair(Stair { base_level: lvl, ..Default::default() })),
        Category::Railings => Some(ElementKind::Railing(Railing { level: lvl, ..Default::default() })),
        Category::Rooms => Some(ElementKind::Room(Room { level: lvl, ..Default::default() })),
        Category::Areas => Some(ElementKind::Area(Area { name: String::new(), number: String::new(), level: lvl, scheme: 0, location: DVec2::ZERO, area_type: String::new() })),
        _ => None,
    };
    if let Some(k) = k {
        return vec![Element::new(0, k)];
    }
    p.families
        .iter()
        .filter(|f| f.category == c)
        .filter_map(|f| f.types.first().map(|t| (f, t)))
        .map(|(f, t)| {
            Element::new(
                0,
                ElementKind::Instance(FamilyInstance {
                    family_id: f.id,
                    type_id: t.id,
                    category: c,
                    level: lvl,
                    host: f.is_hosted().then_some(0),
                    end: f.is_framing().then_some(DVec2::X),
                    ..Default::default()
                }),
            )
        })
        .collect()
}

fn text(s: impl Into<String>) -> Option<Value> {
    Some(Value::Text(s.into()))
}
fn num(x: f64) -> Option<Value> {
    Some(Value::Num(x))
}
fn yn(b: bool) -> Option<Value> {
    num(if b { 1.0 } else { 0.0 })
}

fn phase_name(p: &Project, id: Option<Id>, none: &str) -> String {
    match id {
        Some(id) => p.phases.iter().find(|ph| ph.id == id).map(|ph| ph.name.clone()).unwrap_or_default(),
        None if none.is_empty() => p.phases.first().map(|ph| ph.name.clone()).unwrap_or_default(),
        None => none.to_string(),
    }
}

fn top_name(p: &Project, l: Option<Id>) -> String {
    match l {
        Some(l) => p.level_name(l),
        None => "Unconnected".into(),
    }
}

/// Reads a parameter value.
pub fn get(p: &Project, e: &Element, name: &str) -> Option<Value> {
    match name {
        "Mark" if !matches!(e.kind, ElementKind::Room(_) | ElementKind::Area(_)) => return text(e.mark.clone()),
        "Comments" => return text(e.comments.clone()),
        "Family" => return text(p.family_name_of(e)),
        "Type" => return text(p.type_name_of(e)),
        "Family and Type" => return text(format!("{}: {}", p.family_name_of(e), p.type_name_of(e))),
        "Count" => return num(1.0),
        "Phase Created" => return text(phase_name(p, e.phase_created, "")),
        "Phase Demolished" => return text(phase_name(p, e.phase_demolished, "None")),
        _ => {}
    }
    let sys_common = |t: Option<&SystemType>, name: &str| -> Option<Value> {
        let t = t?;
        match name {
            "Type Mark" => text(t.type_mark.clone()),
            "Description" => text(t.description.clone()),
            "Cost" => num(t.cost),
            "Width" | "Thickness" => num(t.thickness()),
            "Function" => text(t.function.label()),
            other => t.props.get(other).map(|v| Value::Num(*v)).or_else(|| t.texts.get(other).map(|s| Value::Text(s.clone()))),
        }
    };
    let st = p.type_of(e).and_then(|t| p.sys_type(t));
    match &e.kind {
        ElementKind::Level(l) => match name {
            "Name" => text(l.name.clone()),
            "Elevation" => num(l.elevation),
            "Building Story" => yn(l.building_story),
            _ => None,
        },
        ElementKind::Grid(g) => match name {
            "Name" => text(g.name.clone()),
            "Bubble at Start" => yn(g.bubble_start),
            "Bubble at End" => yn(g.bubble_end),
            _ => None,
        },
        ElementKind::RefPlane(r) => (name == "Name").then(|| Value::Text(r.name.clone())),
        ElementKind::Wall(w) => match name {
            "Location Line" => text(w.location_line.label()),
            "Base Constraint" => text(p.level_name(w.base_level)),
            "Base Offset" => num(w.base_offset),
            "Top Constraint" => text(top_name(p, w.top_level)),
            "Top Offset" => num(w.top_offset),
            "Unconnected Height" => num(analysis::wall_height(p, w)),
            "Top is Attached" => yn(w.attach_top.is_some()),
            "Room Bounding" => yn(w.room_bounding),
            "Structural" => yn(w.structural),
            "Length" => num(w.length()),
            "Area" => num(analysis::wall_net_area(p, e.id, w)),
            "Volume" => num(analysis::wall_net_area(p, e.id, w) * analysis::wall_thickness(p, w)),
            _ => sys_common(st, name),
        },
        ElementKind::Floor(f) => match name {
            "Level" => text(p.level_name(f.level)),
            "Height Offset From Level" => num(f.height_offset),
            "Room Bounding" => yn(true),
            "Structural" => yn(f.structural),
            "Area" => num(analysis::floor_area(f)),
            "Perimeter" => num(geom::perimeter(&f.boundary)),
            "Volume" => num(analysis::floor_area(f) * analysis::floor_thickness(p, f)),
            _ => sys_common(st, name),
        },
        ElementKind::Roof(r) => match name {
            "Base Level" => text(p.level_name(r.level)),
            "Base Offset From Level" => num(r.base_offset),
            "Roof Shape" => text(r.shape.label()),
            "Slope" => num(r.slope_deg),
            "Overhang" => num(r.overhang),
            "Fascia" => yn(r.fascia),
            "Gutter" => yn(r.gutter),
            "Area" => num(analysis::roof_area(r)),
            _ => sys_common(st, name),
        },
        ElementKind::Ceiling(c) => match name {
            "Level" => text(p.level_name(c.level)),
            "Height Offset From Level" => num(c.height_offset),
            "Area" => num(geom::area(&c.boundary)),
            "Perimeter" => num(geom::perimeter(&c.boundary)),
            _ => sys_common(st, name),
        },
        ElementKind::Stair(s) => {
            let (n, rh, tread, rise) = analysis::stair_numbers(p, s);
            match name {
                "Base Level" => text(p.level_name(s.base_level)),
                "Base Offset" => num(s.base_offset),
                "Top Level" => text(top_name(p, s.top_level)),
                "Top Offset" => num(s.top_offset),
                "Desired Stair Height" => num(rise),
                "Desired Number of Risers" => num(n as f64),
                "Actual Number of Risers" => num(n as f64),
                "Actual Riser Height" => num(rh),
                "Actual Tread Depth" => {
                    let lay = build3d::stair_layout(p, s);
                    let g = lay.runs.first().map(|(r, k, ..)| r.start.distance(r.end) / (*k).max(1) as f64).unwrap_or(tread);
                    num(g)
                }
                _ => sys_common(st, name),
            }
        }
        ElementKind::Railing(r) => match name {
            "Base Level" => text(p.level_name(r.level)),
            "Base Offset" => num(r.base_offset),
            "Length" => num(r.path.windows(2).map(|w| w[0].distance(w[1])).sum()),
            "Railing Height" => st.map(|t| Value::Num(t.prop("Height", 1000.0))),
            _ => sys_common(st, name),
        },
        ElementKind::Mass(m) => match name {
            "Level" => text(p.level_name(m.level)),
            "Base Offset" => num(m.base_offset),
            "Height" => num(m.height),
            "Gross Floor Area" => {
                // Floor area at every level that cuts the mass.
                let z0 = p.level_elevation(m.level) + m.base_offset;
                let n = p.levels().iter().filter(|(_, l)| l.elevation >= z0 - 1.0 && l.elevation < z0 + m.height - 1.0).count();
                num(geom::area(&m.boundary).abs() * n as f64)
            }
            "Gross Surface Area" => num(geom::area(&m.boundary).abs() * 2.0 + geom::perimeter(&m.boundary) * m.height),
            "Gross Volume" => num(geom::area(&m.boundary).abs() * m.height),
            "Name" => text(m.name.clone()),
            _ => None,
        },
        ElementKind::Toposolid(t) => match name {
            "Level" => text(p.level_name(t.level)),
            "Height Offset From Level" => num(t.heights.iter().cloned().chain(t.points.iter().map(|q| q.1)).fold(f64::MAX, f64::min).min(1e12)),
            "Thickness" => num(t.thickness),
            "Area" => num(geom::area(&t.boundary).abs()),
            "Volume" => {
                // Prisms under each surface triangle down to the flat bottom.
                let tris = analysis::topo_triangles(p, t);
                let bottom = tris.iter().flat_map(|tr| tr.iter().map(|q| q.z)).fold(f64::MAX, f64::min) - t.thickness;
                let v: f64 = tris
                    .iter()
                    .map(|[a, b, c]| {
                        let area = geom::cross2(b.truncate() - a.truncate(), c.truncate() - a.truncate()).abs() / 2.0;
                        area * ((a.z + b.z + c.z) / 3.0 - bottom)
                    })
                    .sum();
                num(v)
            }
            "Material" => text(t.material.clone()),
            _ => None,
        },
        ElementKind::PropertyLine(l) => match name {
            "Name" => text(l.name.clone()),
            "Area" => num(geom::area(&l.boundary).abs()),
            "Perimeter" => num(geom::perimeter(&l.boundary)),
            _ => None,
        },
        ElementKind::ColorLegend(_) => None,
        ElementKind::Shaft(s) => match name {
            "Base Constraint" => text(p.level_name(s.base_level)),
            "Base Offset" => num(s.base_offset),
            "Top Constraint" => text(top_name(p, s.top_level)),
            "Top Offset" => num(s.top_offset),
            "Unconnected Height" => num(s.unconnected_height),
            _ => None,
        },
        ElementKind::WallFoundation(f) => match name {
            "Length" => p.wall(f.wall).map(|w| Value::Num(w.length())),
            _ => sys_common(st, name),
        },
        ElementKind::Room(r) => {
            let boundary = || analysis::room_boundary(p, r);
            match name {
                "Number" => text(r.number.clone()),
                "Name" => text(r.name.clone()),
                "Level" => text(p.level_name(r.level)),
                "Limit Offset" => num(r.upper_offset),
                "Area" => num(boundary().map(|b| b.area()).unwrap_or(0.0)),
                "Perimeter" => num(boundary().map(|b| b.perimeter()).unwrap_or(0.0)),
                "Volume" => num(boundary().map(|b| b.area() * r.upper_offset).unwrap_or(0.0)),
                "Department" => text(r.department.clone()),
                "Occupancy" => text(r.occupancy.clone()),
                "Floor Finish" => text(r.floor_finish.clone()),
                "Wall Finish" => text(r.wall_finish.clone()),
                "Ceiling Finish" => text(r.ceiling_finish.clone()),
                _ => None,
            }
        }
        ElementKind::Area(a) => {
            let b = || analysis::area_boundary(p, a);
            match name {
                "Number" => text(a.number.clone()),
                "Name" => text(a.name.clone()),
                "Area Type" => text(a.area_type.clone()),
                "Level" => text(p.level_name(a.level)),
                "Area" => num(b().map(|b| geom::area(&b.centerline)).unwrap_or(0.0)),
                "Perimeter" => num(b().map(|b| geom::perimeter(&b.centerline)).unwrap_or(0.0)),
                _ => None,
            }
        }
        ElementKind::Instance(i) => match name {
            "Level" | "Base Level" | "Reference Level" => text(p.level_name(i.level)),
            "Host" => text(i.host.and_then(|h| p.element(h)).map(|h| format!("{} [{}]", p.display_name(h), h.id)).unwrap_or_default()),
            "Sill Height" | "Offset from Level" | "Base Offset" | "Start Level Offset" => num(i.elevation),
            "End Level Offset" => num(i.end_elevation),
            "Head Height" => num(i.elevation + analysis::opening_size(p, i).1),
            "Flip Facing" => yn(i.flip_facing),
            "Flip Hand" => yn(i.flip_hand),
            "Rotation" => num(i.rotation_deg),
            "Top Level" => text(top_name(p, i.top_level)),
            "Top Offset" => num(i.top_offset),
            "Moves With Grids" => yn(i.moves_with_grids),
            "Length" if i.end.is_some() => num(i.location.distance(i.end.unwrap())),
            _ => {
                let r = Resolver::for_instance(p, i)?;
                let fp = r.family().param(name)?;
                if fp.kind.is_numeric() {
                    r.number(&fp.name).ok().map(Value::Num)
                } else {
                    text(r.raw(fp).to_string())
                }
            }
        },
        ElementKind::Line(l) => match name {
            "Line Style" => text(l.style.label()),
            "Length" => num(crate::plan::line_points(l).windows(2).map(|w| w[0].distance(w[1])).sum()),
            _ => None,
        },
        ElementKind::RoomSeparation(s) | ElementKind::AreaBoundary(s) => (name == "Length").then(|| Value::Num(s.start.distance(s.end))),
        ElementKind::Dimension(dm) => match name {
            "Value" => num(annotation::segments(p, dm).iter().sum()),
            "EQ" => yn(dm.equal),
            "Prefix" => text(dm.prefix.clone()),
            "Suffix" => text(dm.suffix.clone()),
            "Text Override" => text(dm.text_override.clone()),
            "Label" => text(dm.label.clone()),
            _ => None,
        },
        ElementKind::Tag(t) => match name {
            "Leader Line" => yn(t.leader),
            "Tag Parameter" => text(if t.parameter.is_empty() { p.element(t.host).map(|h| annotation::default_tag_parameter(h.category()).to_string()).unwrap_or_default() } else { t.parameter.clone() }),
            "Tagged Element" => text(p.element(t.host).map(|h| p.display_name(h)).unwrap_or_default()),
            _ => None,
        },
        ElementKind::Text(t) => match name {
            "Text" => text(t.text.clone()),
            "Text Size" => num(t.size),
            "Bold" => yn(t.bold),
            "Rotation" => num(t.rotation_deg),
            _ => None,
        },
        ElementKind::Region(r) => match name {
            "Fill Pattern" => text(r.pattern.label()),
            "Colour" => text(format!("#{:02X}{:02X}{:02X}", r.color[0], r.color[1], r.color[2])),
            "Area" => num(geom::area(&r.boundary) - r.holes.iter().map(|h| geom::area(h)).sum::<f64>()),
            _ => None,
        },
        ElementKind::Symbol(s) => match name {
            "Rotation" => num(s.rotation_deg),
            "Value" => text(s.value.clone()),
            _ => None,
        },
        ElementKind::GroupInstance(g) => match name {
            "Reference Level" => text(p.level_name(g.level)),
            "Rotation" => num(g.rotation_deg),
            _ => None,
        },
        ElementKind::Cad(c) => match name {
            "Name" => text(c.name.clone()),
            "Halftone" => yn(c.halftone),
            _ => None,
        },
    }
}

/// Formats a parameter value for display in project units.
pub fn display(p: &Project, e: &Element, d: &ParamDef) -> String {
    match get(p, e, &d.name) {
        None => String::new(),
        Some(Value::Text(s)) => s,
        Some(Value::Num(x)) => match &d.kind {
            PKind::Value(k) => p.units.format(x, *k),
            _ => p.units.format(x, ParamKind::Number),
        },
    }
}

pub fn parse(p: &Project, d: &ParamDef, input: &str) -> Result<Value, String> {
    match &d.kind {
        PKind::Value(k) if k.is_numeric() => {
            let parsed = if *k == ParamKind::YesNo { units::parse_input(input, *k) } else { p.units.parse(input, *k) };
            parsed.map(Value::Num).ok_or_else(|| format!("'{input}' is not a valid {}.", k.label().to_lowercase()))
        }
        PKind::Choice(options) => options
            .iter()
            .find(|o| o.eq_ignore_ascii_case(input.trim()))
            .map(|o| Value::Text(o.clone()))
            .ok_or_else(|| format!("'{input}' is not one of: {}.", options.join(", "))),
        _ => Ok(Value::Text(input.to_string())),
    }
}

fn level_by_name(p: &Project, name: &str) -> Result<Id, String> {
    p.levels().iter().find(|(_, l)| l.name == name).map(|(id, _)| *id).ok_or_else(|| format!("No level named '{name}'."))
}

fn phase_by_name(p: &Project, name: &str) -> Option<Id> {
    p.phases.iter().find(|ph| ph.name == name).map(|ph| ph.id)
}

/// Writes a parameter from user input. Must be called inside a transaction.
pub fn set(p: &mut Project, id: Id, name: &str, input: &str) -> Result<(), String> {
    let e = p.element(id).ok_or("Element not found.")?.clone();
    if e.pinned && !matches!(name, "Comments" | "Mark") {
        return Err("The element is pinned. Unpin it to change it.".into());
    }
    let d = element_params(p, &e).into_iter().find(|d| d.name == name).ok_or_else(|| format!("No parameter '{name}'."))?;
    if d.read_only {
        return Err(format!("'{name}' is read-only."));
    }
    let value = parse(p, &d, input)?;
    let n = || value.as_num().unwrap_or(0.0);
    let t = || match &value {
        Value::Text(s) => s.clone(),
        Value::Num(x) => units::to_stored(*x),
    };
    let positive = |x: f64, what: &str| if x > 0.0 { Ok(x) } else { Err(format!("{what} must be greater than zero.")) };

    match name {
        "Phase Created" => {
            let ph = phase_by_name(p, &t());
            let el = p.element_mut(id).unwrap();
            el.phase_created = ph;
            if let (Some(c), Some(dm)) = (el.phase_created, el.phase_demolished) {
                let (ci, di) = (p.phase_index(Some(c)), p.phase_index(Some(dm)));
                if di < ci {
                    return Err("An element cannot be demolished before it is created.".into());
                }
            }
            return Ok(());
        }
        "Phase Demolished" => {
            let ph = if t() == "None" { None } else { phase_by_name(p, &t()) };
            if let Some(dm) = ph {
                if p.phase_index(Some(dm)) < p.phase_index(e.phase_created) {
                    return Err("An element cannot be demolished before it is created.".into());
                }
            }
            p.element_mut(id).unwrap().phase_demolished = ph;
            return Ok(());
        }
        _ => {}
    }

    // Type parameters of system families.
    if d.type_param {
        if let Some(tid) = p.type_of(&e).filter(|t| p.sys_type(*t).is_some()) {
            let st = p.sys_type_mut(tid).unwrap();
            match name {
                "Type Mark" => st.type_mark = t(),
                "Description" => st.description = t(),
                "Cost" => st.cost = n(),
                "Railing Height" => {
                    st.props.insert("Height".into(), positive(n(), "Height")?);
                }
                other if st.props.contains_key(other) || matches!(other, "Maximum Riser Height" | "Minimum Tread Depth" | "Baluster Spacing" | "Width" | "Foundation Thickness") => {
                    st.props.insert(other.into(), positive(n(), other)?);
                }
                _ => return Err(format!("'{name}' is read-only.")),
            }
            return Ok(());
        }
    }

    let level_id = if matches!(d.kind, PKind::Level) { Some(level_by_name(p, &t())?) } else { None };
    let top_choice = if matches!(name, "Top Constraint" | "Top Level") {
        Some(if t() == "Unconnected" { None } else { Some(level_by_name(p, &t())?) })
    } else {
        None
    };
    let el = p.element_mut(id).unwrap();
    match name {
        "Mark" if !matches!(el.kind, ElementKind::Room(_) | ElementKind::Area(_)) => {
            el.mark = t();
            return Ok(());
        }
        "Comments" => {
            el.comments = t();
            return Ok(());
        }
        _ => {}
    }
    match &mut el.kind {
        ElementKind::Level(l) => match name {
            "Name" => {
                let new = t();
                if new.trim().is_empty() {
                    return Err("Level name cannot be empty.".into());
                }
                l.name = new;
            }
            "Elevation" => l.elevation = n(),
            "Building Story" => l.building_story = n() != 0.0,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Grid(g) => match name {
            "Name" => g.name = t(),
            "Bubble at Start" => g.bubble_start = n() != 0.0,
            "Bubble at End" => g.bubble_end = n() != 0.0,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::RefPlane(r) => r.name = t(),
        ElementKind::Wall(w) => match name {
            "Location Line" => w.location_line = *LocationLine::ALL.iter().find(|l| l.label() == t()).unwrap(),
            "Base Constraint" => w.base_level = level_id.unwrap(),
            "Base Offset" => w.base_offset = n(),
            "Top Constraint" => {
                w.top_level = top_choice.unwrap();
                w.attach_top = None;
            }
            "Top Offset" => w.top_offset = n(),
            "Unconnected Height" => w.unconnected_height = positive(n(), "Height")?,
            "Room Bounding" => w.room_bounding = n() != 0.0,
            "Structural" => w.structural = n() != 0.0,
            "Length" => {
                let len = positive(n(), "Length")?;
                w.end = w.start + w.direction() * len;
            }
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Floor(f) => match name {
            "Level" => f.level = level_id.unwrap(),
            "Height Offset From Level" => f.height_offset = n(),
            "Structural" => f.structural = n() != 0.0,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Roof(r) => match name {
            "Base Level" => r.level = level_id.unwrap(),
            "Base Offset From Level" => r.base_offset = n(),
            "Roof Shape" => {
                r.shape = *RoofShape::ALL.iter().find(|s| s.label() == t()).unwrap();
                r.edge_slopes.clear();
            }
            "Slope" => {
                let s = n();
                if !(0.0..=80.0).contains(&s) {
                    return Err("Slope must be between 0° and 80°.".into());
                }
                r.slope_deg = s;
            }
            "Overhang" => {
                if n() < 0.0 {
                    return Err("Overhang cannot be negative.".into());
                }
                r.overhang = n();
            }
            "Fascia" => r.fascia = n() != 0.0,
            "Gutter" => r.gutter = n() != 0.0,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Ceiling(c) => match name {
            "Level" => c.level = level_id.unwrap(),
            "Height Offset From Level" => c.height_offset = n(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Stair(s) => match name {
            "Base Level" => s.base_level = level_id.unwrap(),
            "Base Offset" => s.base_offset = n(),
            "Top Level" => s.top_level = top_choice.unwrap(),
            "Top Offset" => s.top_offset = n(),
            "Desired Number of Risers" => {
                let r = n().round();
                if !(2.0..=200.0).contains(&r) {
                    return Err("The number of risers must be between 2 and 200.".into());
                }
                s.desired_risers = r as u32;
            }
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Railing(r) => match name {
            "Base Level" => r.level = level_id.unwrap(),
            "Base Offset" => r.base_offset = n(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Shaft(s) => match name {
            "Base Constraint" => s.base_level = level_id.unwrap(),
            "Base Offset" => s.base_offset = n(),
            "Top Constraint" => s.top_level = top_choice.unwrap(),
            "Top Offset" => s.top_offset = n(),
            "Unconnected Height" => s.unconnected_height = positive(n(), "Height")?,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Mass(m) => match name {
            "Level" => m.level = level_id.unwrap(),
            "Base Offset" => m.base_offset = n(),
            "Height" => m.height = positive(n(), "Height")?,
            "Name" => m.name = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Toposolid(ts) => match name {
            "Level" => ts.level = level_id.unwrap(),
            "Height Offset From Level" => {
                let lo = ts.heights.iter().cloned().chain(ts.points.iter().map(|q| q.1)).fold(f64::MAX, f64::min);
                let lo = if lo == f64::MAX { 0.0 } else { lo };
                let dz = n() - lo;
                for h in ts.heights.iter_mut() {
                    *h += dz;
                }
                for q in ts.points.iter_mut() {
                    q.1 += dz;
                }
            }
            "Thickness" => ts.thickness = positive(n(), "Thickness")?,
            "Material" => ts.material = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::PropertyLine(l) => match name {
            "Name" => l.name = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Room(r) => match name {
            "Number" => r.number = t(),
            "Name" => r.name = t(),
            "Limit Offset" => r.upper_offset = positive(n(), "Limit offset")?,
            "Department" => r.department = t(),
            "Occupancy" => r.occupancy = t(),
            "Floor Finish" => r.floor_finish = t(),
            "Wall Finish" => r.wall_finish = t(),
            "Ceiling Finish" => r.ceiling_finish = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Area(a) => match name {
            "Number" => a.number = t(),
            "Name" => a.name = t(),
            "Area Type" => a.area_type = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Instance(i) => match name {
            "Level" | "Base Level" | "Reference Level" => i.level = level_id.unwrap(),
            "Sill Height" | "Offset from Level" | "Base Offset" | "Start Level Offset" => i.elevation = n(),
            "End Level Offset" => i.end_elevation = n(),
            "Flip Facing" => i.flip_facing = n() != 0.0,
            "Flip Hand" => i.flip_hand = n() != 0.0,
            "Rotation" => i.rotation_deg = n().rem_euclid(360.0),
            "Top Level" => i.top_level = top_choice.unwrap(),
            "Top Offset" => i.top_offset = n(),
            "Moves With Grids" => i.moves_with_grids = n() != 0.0,
            _ => {
                let (family_id, type_id) = (i.family_id, i.type_id);
                if d.type_param {
                    let fam = p.family_mut(family_id).ok_or("Family not found.")?;
                    let ft = fam.types.iter_mut().find(|ft| ft.id == type_id).ok_or("Type not found.")?;
                    ft.values.insert(name.to_string(), t());
                } else {
                    i.values.insert(name.to_string(), t());
                }
            }
        },
        ElementKind::Line(l) => match name {
            "Line Style" => l.style = *LineStyle::ALL.iter().find(|s| s.label() == t()).unwrap(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Dimension(dm) => match name {
            "EQ" => dm.equal = n() != 0.0,
            "Prefix" => dm.prefix = t(),
            "Suffix" => dm.suffix = t(),
            "Text Override" => dm.text_override = t(),
            "Label" => dm.label = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Tag(tg) => match name {
            "Leader Line" => tg.leader = n() != 0.0,
            "Tag Parameter" => tg.parameter = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Text(tn) => match name {
            "Text" => tn.text = t(),
            "Text Size" => tn.size = positive(n(), "Text size")?,
            "Bold" => tn.bold = n() != 0.0,
            "Rotation" => tn.rotation_deg = n(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Region(r) => match name {
            "Fill Pattern" => r.pattern = *FillPattern::ALL.iter().find(|s| s.label() == t()).unwrap(),
            "Colour" => {
                let s = t();
                let h = s.trim().trim_start_matches('#');
                let c = (h.len() == 6).then(|| u32::from_str_radix(h, 16).ok()).flatten().ok_or("Colour must look like #RRGGBB.")?;
                r.color = [(c >> 16) as u8, (c >> 8) as u8, c as u8];
            }
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Symbol(s) => match name {
            "Rotation" => s.rotation_deg = n(),
            "Value" => s.value = t(),
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        ElementKind::Cad(c) => match name {
            "Halftone" => c.halftone = n() != 0.0,
            _ => return Err(format!("'{name}' cannot be set.")),
        },
        _ => return Err(format!("'{name}' cannot be set.")),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{defaults, edit};

    #[test]
    fn wall_parameters_round_trip() {
        let mut p = defaults::new_project(units::UnitSystem::Metric);
        let lvl = p.levels()[0].0;
        let ty = p.types_of(Category::Walls).next().unwrap().id;
        let id = edit::add_wall(&mut p, lvl, ty, geom::DVec2::ZERO, geom::DVec2::new(4000.0, 0.0), 3000.0).unwrap();
        assert!(set(&mut p, id, "Unconnected Height", "2.5 m").is_err());
        set(&mut p, id, "Top Constraint", "Unconnected").unwrap();
        set(&mut p, id, "Unconnected Height", "2.5 m").unwrap();
        let e = p.element(id).unwrap();
        assert_eq!(get(&p, e, "Unconnected Height"), Some(Value::Num(2500.0)));
        assert_eq!(get(&p, e, "Area"), Some(Value::Num(4000.0 * 2500.0)));
        set(&mut p, id, "Top Constraint", "Level 2").unwrap();
        let e = p.element(id).unwrap();
        assert_eq!(get(&p, e, "Unconnected Height"), Some(Value::Num(3000.0)));
        assert!(set(&mut p, id, "Area", "5").is_err());
        assert!(set(&mut p, id, "Base Offset", "abc").is_err());
        set(&mut p, id, "Phase Created", "Existing").unwrap();
        set(&mut p, id, "Phase Demolished", "New Construction").unwrap();
        assert!(set(&mut p, id, "Phase Created", "New Construction").is_ok());
    }

    #[test]
    fn imperial_input() {
        let mut p = defaults::new_project(units::UnitSystem::Imperial);
        let lvl = p.levels()[0].0;
        let ty = p.types_of(Category::Walls).next().unwrap().id;
        let id = edit::add_wall(&mut p, lvl, ty, geom::DVec2::ZERO, geom::DVec2::new(4000.0, 0.0), 3048.0).unwrap();
        set(&mut p, id, "Base Offset", "1' 6\"").unwrap();
        let e = p.element(id).unwrap();
        assert!((get(&p, e, "Base Offset").unwrap().as_num().unwrap() - 457.2).abs() < 1e-9);
        let d = element_params(&p, e).into_iter().find(|d| d.name == "Base Offset").unwrap();
        assert_eq!(display(&p, e, &d), "1' - 6\"");
    }
}
