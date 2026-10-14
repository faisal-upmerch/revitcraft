//! Project templates (metric and imperial): materials, system types, family library, levels,
//! views, schedules, phases, area schemes and annotation styles.

use crate::geom::DVec3;
use crate::library;
use crate::model::*;
use crate::units::{UnitSystem, Units};
use std::collections::BTreeMap;

fn mat(name: &str, rgb: [u8; 3], opacity: f64, class: &str, cut: FillPattern) -> Material {
    Material { name: name.into(), color: rgb, opacity, class: class.into(), cut_pattern: cut, shininess: if class == "Metal" || class == "Glass" { 0.8 } else { 0.1 } }
}

pub fn materials() -> Vec<Material> {
    use FillPattern::*;
    vec![
        mat("Default", [200, 200, 200], 1.0, "Generic", Diagonal),
        mat("Concrete", [172, 172, 166], 1.0, "Concrete", Concrete),
        mat("Concrete Masonry Units", [184, 180, 170], 1.0, "Masonry", CrossHatch),
        mat("Brick", [168, 84, 62], 1.0, "Masonry", Brick),
        mat("Insulation", [236, 214, 120], 1.0, "Insulation", Insulation),
        mat("Plasterboard", [242, 240, 234], 1.0, "Finish", Solid),
        mat("Stud Layer", [214, 204, 184], 1.0, "Generic", Diagonal),
        mat("Timber Flooring", [178, 128, 82], 1.0, "Wood", Diagonal),
        mat("Wood", [150, 105, 66], 1.0, "Wood", Diagonal),
        mat("Wood - Painted White", [246, 246, 240], 1.0, "Paint", Diagonal),
        mat("Glass", [150, 200, 230], 0.35, "Glass", Solid),
        mat("Aluminum", [192, 194, 198], 1.0, "Metal", Solid),
        mat("Steel", [122, 127, 132], 1.0, "Metal", CrossHatch),
        mat("Steel - Stainless", [210, 212, 215], 1.0, "Metal", Solid),
        mat("Roof Tiles", [142, 62, 46], 1.0, "Ceramic", Diagonal),
        mat("Metal Roofing", [70, 78, 90], 1.0, "Metal", Solid),
        mat("Fabric", [96, 110, 140], 1.0, "Textile", Solid),
        mat("Porcelain", [250, 250, 250], 1.0, "Ceramic", Solid),
        mat("Stone", [120, 116, 110], 1.0, "Stone", Diagonal),
        mat("Acoustic Tile", [236, 236, 232], 1.0, "Finish", CrossHatch),
        mat("Gravel", [150, 145, 135], 1.0, "Earth", Concrete),
        mat("Grass", [96, 150, 72], 1.0, "Earth", Solid),
        mat("Site - Earth", [176, 160, 132], 1.0, "Earth", Concrete),
        mat("Foliage", [92, 140, 70], 1.0, "Earth", Solid),
        mat("Paint - White", [248, 248, 248], 1.0, "Paint", Solid),
        mat("Default Mass", [196, 206, 222], 0.45, "Generic", Solid),
    ]
}

fn layer(function: LayerFunction, material: &str, thickness: f64, core: bool) -> Layer {
    Layer { function, material: material.into(), thickness, core }
}

#[allow(clippy::too_many_arguments)]
fn sys(p: &mut Project, category: Category, name: &str, function: WallFunction, cost: f64, layers: Vec<Layer>, props: &[(&str, f64)], texts: &[(&str, &str)]) -> Id {
    let id = p.new_id();
    p.types.push(SystemType {
        id,
        category,
        name: name.into(),
        cost,
        function,
        layers,
        props: props.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
        texts: texts.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
        ..Default::default()
    });
    id
}

/// Parameters of a template (re-exported for the family editor).
pub fn template_params(t: FamilyTemplate) -> Vec<FamilyParameter> {
    library::template_params(t)
}

/// Creates a family with the given types; each type is (name, [(param, value)]).
pub fn add_family(p: &mut Project, name: &str, template: FamilyTemplate, types: &[(&str, &[(&str, &str)])]) -> Id {
    let id = p.new_id();
    let mut family = Family {
        id,
        name: name.into(),
        category: template.category(),
        template,
        params: library::template_params(template),
        types: Vec::new(),
        definition: (template == FamilyTemplate::Custom).then(crate::family_def::generic_template),
    };
    for (tname, values) in types {
        let tid = p.new_id();
        let map: BTreeMap<String, String> = values.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        family.types.push(FamilyType { id: tid, name: tname.to_string(), values: map });
    }
    p.families.push(family);
    id
}

fn add_catalog_family(p: &mut Project, name: &str, template: FamilyTemplate, types: Vec<(String, Vec<(&'static str, String)>)>) {
    let id = p.new_id();
    let mut family = Family { id, name: name.into(), category: template.category(), template, params: library::template_params(template), types: vec![], definition: None };
    for (tname, values) in types {
        let tid = p.new_id();
        family.types.push(FamilyType { id: tid, name: tname, values: values.into_iter().map(|(k, v)| (k.to_string(), v)).collect() });
    }
    p.families.push(family);
}

pub fn add_level(p: &mut Project, name: &str, elevation: f64, with_plan: bool) -> Id {
    let id = p.new_id();
    p.elements.push(Element::new(id, ElementKind::Level(Level { name: name.into(), elevation, building_story: true })));
    if with_plan {
        let vid = p.new_id();
        let mut v = View::new(vid, name, 100.0, ViewKind::FloorPlan { level: id, cut_height: 1200.0, room_colors: false });
        v.phase = p.phases.last().map(|ph| ph.id);
        p.views.push(v);
        let cid = p.new_id();
        let mut c = View::new(cid, name, 100.0, ViewKind::CeilingPlan { level: id });
        c.phase = p.phases.last().map(|ph| ph.id);
        c.view_range = ViewRange { top: 3000.0, cut: 2300.0, bottom: 0.0, depth: 0.0 };
        p.views.push(c);
    }
    id
}

fn schedule(p: &mut Project, name: &str, category: Category, fields: &[&str], sort: &[&str], totals: &[&str]) {
    let id = p.new_id();
    p.views.push(View::new(
        id,
        name,
        100.0,
        ViewKind::Schedule(ScheduleDef {
            category,
            fields: fields.iter().map(|s| s.to_string()).collect(),
            sort_by: sort.iter().map(|s| s.to_string()).collect(),
            itemize: true,
            grand_total: true,
            total_fields: totals.iter().map(|s| s.to_string()).collect(),
            ..Default::default()
        }),
    ));
}

/// A new project from the metric or imperial template.
pub fn new_project(system: UnitSystem) -> Project {
    use LayerFunction::*;
    let imp = system == UnitSystem::Imperial;
    let inch = 25.4;
    let mut p = Project::empty();
    p.units = if imp { Units::imperial() } else { Units::metric() };
    p.info = ProjectInfo { name: "Project Name".into(), number: "0001".into(), client: "Owner".into(), status: "Project Status".into(), ..Default::default() };
    p.materials = materials();
    for name in ["Existing", "New Construction"] {
        let id = p.new_id();
        p.phases.push(Phase { id, name: name.into() });
    }
    for name in ["Gross Building", "Rentable"] {
        let id = p.new_id();
        p.area_schemes.push(AreaScheme { id, name: name.into() });
    }
    let ds = p.new_id();
    p.dim_styles.push(DimensionStyle { id: ds, name: if imp { "Linear - 3/32\" Arial".into() } else { "Linear - 2.5mm Arial".into() }, text_size: 2.5, tick: true, gap: 1.5 });
    for (name, size, bold) in [("2.5mm Arial", 2.5, false), ("3.5mm Arial", 3.5, false), ("5mm Arial Bold", 5.0, true)] {
        let id = p.new_id();
        p.text_types.push(TextType { id, name: name.into(), size, bold });
    }

    // Wall types (exterior → interior).
    let t = |mm: f64, ins: f64| if imp { ins * inch } else { mm };
    let n_gen = if imp { "Generic - 8\"" } else { "Generic - 200mm" };
    sys(&mut p, Category::Walls, n_gen, WallFunction::Exterior, 120.0, vec![layer(Structure, "Default", t(200.0, 8.0), true)], &[], &[]);
    let brick = sys(
        &mut p,
        Category::Walls,
        "Exterior - Brick on Block",
        WallFunction::Exterior,
        260.0,
        vec![
            layer(Finish1, "Brick", t(100.0, 3.625), false),
            layer(ThermalAir, "Insulation", t(50.0, 2.0), false),
            layer(Structure, "Concrete Masonry Units", t(190.0, 7.625), true),
            layer(Finish2, "Plasterboard", t(13.0, 0.5), false),
        ],
        &[],
        &[],
    );
    sys(
        &mut p,
        Category::Walls,
        if imp { "Interior - 4 7/8\" Partition" } else { "Interior - 100mm Partition" },
        WallFunction::Interior,
        70.0,
        vec![layer(Finish1, "Plasterboard", t(13.0, 0.625), false), layer(Structure, "Stud Layer", t(75.0, 3.625), true), layer(Finish2, "Plasterboard", t(13.0, 0.625), false)],
        &[],
        &[],
    );
    let conc = sys(&mut p, Category::Walls, if imp { "Generic - 12\"" } else { "Generic - 300mm" }, WallFunction::Exterior, 180.0, vec![layer(Structure, "Concrete", t(300.0, 12.0), true)], &[], &[]);
    let found = sys(&mut p, Category::Walls, if imp { "Foundation - 12\" Concrete" } else { "Foundation - 300mm Concrete" }, WallFunction::Foundation, 160.0, vec![layer(Structure, "Concrete", t(300.0, 12.0), true)], &[], &[]);
    let cw_id = p.new_id();
    p.types.push(SystemType {
        id: cw_id,
        category: Category::Walls,
        name: "Storefront".into(),
        cost: 520.0,
        wall_kind: WallKind::Curtain,
        props: [("Vertical Spacing", t(1500.0, 60.0)), ("Horizontal Spacing", 0.0), ("Mullion Width", t(50.0, 2.0)), ("Mullion Depth", t(150.0, 6.0))].iter().map(|(k, v)| (k.to_string(), *v)).collect(),
        texts: [("Mullion Material", "Aluminum"), ("Panel Material", "Glass"), ("Solid Panel Material", "Aluminum")].iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
        ..Default::default()
    });
    let cw2 = p.new_id();
    p.types.push(SystemType {
        id: cw2,
        category: Category::Walls,
        name: "Curtain Wall - Grid".into(),
        cost: 640.0,
        wall_kind: WallKind::Curtain,
        props: [("Vertical Spacing", t(1200.0, 48.0)), ("Horizontal Spacing", t(1500.0, 60.0)), ("Mullion Width", t(60.0, 2.5)), ("Mullion Depth", t(180.0, 7.0))].iter().map(|(k, v)| (k.to_string(), *v)).collect(),
        texts: [("Mullion Material", "Aluminum"), ("Panel Material", "Glass"), ("Solid Panel Material", "Aluminum")].iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
        ..Default::default()
    });
    let stk = p.new_id();
    p.types.push(SystemType {
        id: stk,
        category: Category::Walls,
        name: "Stacked - Concrete Base, Brick Above".into(),
        cost: 300.0,
        wall_kind: WallKind::Stacked,
        layers: vec![layer(Structure, "Concrete", t(353.0, 14.0), true)],
        stack: vec![(conc, t(900.0, 36.0)), (brick, 0.0)],
        ..Default::default()
    });
    let _ = found;

    // Floors, roofs, ceilings (top → bottom).
    sys(&mut p, Category::Floors, if imp { "Generic 12\"" } else { "Generic 300mm" }, WallFunction::Exterior, 90.0, vec![layer(Structure, "Concrete", t(300.0, 12.0), true)], &[], &[]);
    sys(&mut p, Category::Floors, if imp { "Wood Finish on 10\" Concrete" } else { "Timber on Concrete 250mm" }, WallFunction::Exterior, 140.0, vec![layer(Finish1, "Timber Flooring", t(20.0, 0.75), false), layer(Structure, "Concrete", t(230.0, 9.25), true)], &[], &[]);
    sys(&mut p, Category::Floors, if imp { "Foundation Slab - 12\"" } else { "Foundation Slab 300mm" }, WallFunction::Foundation, 110.0, vec![layer(Structure, "Concrete", t(300.0, 12.0), true)], &[], &[]);
    sys(&mut p, Category::Roofs, "Tiled Roof 250mm", WallFunction::Exterior, 160.0, vec![layer(Finish1, "Roof Tiles", t(30.0, 1.0), false), layer(ThermalAir, "Insulation", t(150.0, 6.0), false), layer(Structure, "Wood", t(70.0, 3.0), true)], &[], &[]);
    sys(&mut p, Category::Roofs, if imp { "Generic - 12\"" } else { "Generic - 300mm" }, WallFunction::Exterior, 120.0, vec![layer(Structure, "Concrete", t(300.0, 12.0), true)], &[], &[]);
    sys(&mut p, Category::Roofs, "Standing Seam Metal", WallFunction::Exterior, 210.0, vec![layer(Finish1, "Metal Roofing", t(20.0, 1.0), false), layer(ThermalAir, "Insulation", t(150.0, 6.0), false), layer(Structure, "Wood", t(50.0, 2.0), true)], &[], &[]);
    sys(&mut p, Category::Ceilings, "600 x 600mm Grid", WallFunction::Interior, 45.0, vec![layer(Finish1, "Acoustic Tile", t(20.0, 0.75), false)], &[], &[]);
    sys(&mut p, Category::Ceilings, "Plasterboard Ceiling", WallFunction::Interior, 35.0, vec![layer(Finish1, "Plasterboard", t(13.0, 0.5), false)], &[], &[]);
    sys(
        &mut p,
        Category::Stairs,
        if imp { "7\" max riser 11\" tread" } else { "Monolithic Concrete" },
        WallFunction::Interior,
        2500.0,
        vec![],
        &[("Maximum Riser Height", t(180.0, 7.0)), ("Minimum Tread Depth", t(280.0, 11.0)), ("Minimum Run Width", t(1000.0, 36.0)), ("Structural Depth", t(150.0, 6.0)), ("Landing Thickness", t(200.0, 8.0))],
        &[("Material", "Concrete")],
    );
    sys(
        &mut p,
        Category::Railings,
        if imp { "Handrail - Pipe 42\"" } else { "Handrail - 1000mm" },
        WallFunction::Interior,
        180.0,
        vec![],
        &[("Height", t(1000.0, 42.0)), ("Baluster Spacing", t(120.0, 4.0)), ("Rail Width", t(50.0, 2.0)), ("Baluster Size", t(20.0, 0.75))],
        &[("Material", "Steel")],
    );
    sys(&mut p, Category::StructuralFoundations, "Bearing Footing - 600 x 300", WallFunction::Foundation, 140.0, vec![layer(Structure, "Concrete", 300.0, true)], &[("Width", t(600.0, 24.0)), ("Foundation Thickness", t(300.0, 12.0))], &[]);

    for (name, template, types) in library::catalog(system) {
        add_catalog_family(&mut p, name, template, types);
    }
    add_family(&mut p, "Generic Model (parametric)", FamilyTemplate::Custom, &[("Default", &[])]);

    if imp {
        add_level(&mut p, "Level 1", 0.0, true);
        add_level(&mut p, "Level 2", 10.0 * 304.8, true);
    } else {
        add_level(&mut p, "Level 1", 0.0, true);
        add_level(&mut p, "Level 2", 3000.0, true);
    }

    let id = p.new_id();
    // The default 3D view: orthographic, looking from the front-right-top corner, hidden line.
    let target = DVec3::new(0.0, 0.0, 1500.0);
    let mut v3 = View::new(id, "{3D}", 100.0, ViewKind::ThreeD { eye: target + DVec3::new(15000.0, -15000.0, 15000.0), target, perspective: false });
    v3.style = VisualStyle::HiddenLine;
    v3.phase = p.phases.last().map(|ph| ph.id);
    p.views.push(v3);
    for dir in ElevationDir::ALL {
        let id = p.new_id();
        let mut v = View::new(id, dir.label(), 100.0, ViewKind::Elevation { dir });
        v.phase = p.phases.last().map(|ph| ph.id);
        p.views.push(v);
    }
    // Site plan view template.
    let tid = p.new_id();
    let mut tmpl = View::new(tid, "Architectural Plan", 100.0, ViewKind::FloorPlan { level: 0, cut_height: 1200.0, room_colors: false });
    tmpl.is_template = true;
    tmpl.detail = DetailLevel::Medium;
    p.views.push(tmpl);
    let tid = p.new_id();
    let mut tmpl = View::new(tid, "Structural Framing Plan", 100.0, ViewKind::FloorPlan { level: 0, cut_height: 1200.0, room_colors: false });
    tmpl.is_template = true;
    tmpl.hidden = vec![Category::Furniture, Category::Casework, Category::PlumbingFixtures, Category::Rooms, Category::Doors, Category::Windows];
    p.views.push(tmpl);

    schedule(&mut p, "Door Schedule", Category::Doors, &["Mark", "Family and Type", "Width", "Height", "Level", "Fire Rating", "Cost", "Comments"], &["Mark"], &["Cost"]);
    schedule(&mut p, "Window Schedule", Category::Windows, &["Mark", "Family and Type", "Width", "Height", "Sill Height", "Level", "Cost"], &["Mark"], &["Cost"]);
    schedule(&mut p, "Room Schedule", Category::Rooms, &["Number", "Name", "Level", "Area", "Perimeter", "Floor Finish"], &["Number"], &["Area"]);
    // Views open at Coarse detail like the reference template (view templates keep theirs).
    for v in p.views.iter_mut().filter(|v| !v.is_template) {
        v.detail = DetailLevel::Coarse;
    }
    if imp {
        // Imperial views start at 1/8" = 1'-0".
        for v in p.views.iter_mut().filter(|v| v.scale == 100.0) {
            v.scale = 96.0;
        }
    }
    schedule(&mut p, "Wall Schedule", Category::Walls, &["Family and Type", "Base Constraint", "Length", "Area", "Volume"], &["Family and Type"], &["Length", "Area", "Volume"]);
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn templates_build() {
        for sys in [UnitSystem::Metric, UnitSystem::Imperial] {
            let p = new_project(sys);
            assert_eq!(p.levels().len(), 2);
            assert!(p.families.len() >= 30);
            for f in &p.families {
                for t in &f.types {
                    let mesh = crate::build3d::family_type_preview(f, t);
                    assert!(!mesh.is_empty(), "{} / {} has no geometry", f.name, t.name);
                }
            }
        }
    }
}
