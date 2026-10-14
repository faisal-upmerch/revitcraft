//! A small sample house used by "Open Sample Project" and tests.

use crate::defaults;
use crate::edit;
use crate::geom::DVec2;
use crate::model::*;

fn v(x: f64, y: f64) -> DVec2 {
    DVec2::new(x, y)
}

pub fn sample_house() -> Project {
    let mut p = defaults::new_project(crate::units::UnitSystem::Metric);
    p.info.name = "Sample House".into();
    p.info.number = "2026-001".into();
    p.info.client = "RevitCraft".into();
    let l1 = p.levels()[0].0;
    let l2 = p.levels()[1].0;
    let ext = p.types_of(Category::Walls).find(|t| t.name == "Exterior - Brick on Block").unwrap().id;
    let int = p.types_of(Category::Walls).find(|t| t.name == "Interior - 100mm Partition").unwrap().id;

    // Exterior walls drawn clockwise so the brick faces outwards.
    let outline = [v(0.0, 8000.0), v(12000.0, 8000.0), v(12000.0, 0.0), v(0.0, 0.0)];
    let mut ext_walls = Vec::new();
    for k in 0..4 {
        ext_walls.push(edit::add_wall(&mut p, l1, ext, outline[k], outline[(k + 1) % 4], 3000.0).unwrap());
    }
    // Interior partitions.
    let w1 = edit::add_wall(&mut p, l1, int, v(7000.0, 0.0), v(7000.0, 8000.0), 3000.0).unwrap();
    let w2 = edit::add_wall(&mut p, l1, int, v(7000.0, 4500.0), v(12000.0, 4500.0), 3000.0).unwrap();

    let fam_type = |p: &Project, fam: &str, ty: &str| -> Id {
        p.families.iter().find(|f| f.name == fam).unwrap().types.iter().find(|t| t.name == ty).unwrap().id
    };
    let door = fam_type(&p, "Single-Flush", "900 x 2100");
    let door_int = fam_type(&p, "Single-Flush", "800 x 2100");
    let double = fam_type(&p, "Double-Flush", "1600 x 2100");
    let window = fam_type(&p, "Casement 2 Lite", "1200 x 1200");
    let wide = fam_type(&p, "Fixed", "1800 x 1500");

    // Walls run: [0] north (W→E), [1] east (N→S), [2] south (E→W), [3] west (S→N).
    let marks = [
        edit::place_hosted(&mut p, double, ext_walls[2], 9000.0, true).unwrap(),
        edit::place_hosted(&mut p, door, ext_walls[0], 9500.0, true).unwrap(),
        edit::place_hosted(&mut p, door_int, w1, 2000.0, false).unwrap(),
        edit::place_hosted(&mut p, door_int, w2, 2500.0, true).unwrap(),
    ];
    for (k, id) in marks.iter().enumerate() {
        p.element_mut(*id).unwrap().mark = format!("D{:02}", k + 1);
    }
    let windows = [
        edit::place_hosted(&mut p, wide, ext_walls[2], 3000.0, false).unwrap(),
        edit::place_hosted(&mut p, window, ext_walls[3], 4000.0, false).unwrap(),
        edit::place_hosted(&mut p, wide, ext_walls[0], 3500.0, false).unwrap(),
        edit::place_hosted(&mut p, window, ext_walls[1], 2000.0, false).unwrap(),
        edit::place_hosted(&mut p, window, ext_walls[1], 6200.0, false).unwrap(),
    ];
    for (k, id) in windows.iter().enumerate() {
        p.element_mut(*id).unwrap().mark = format!("W{:02}", k + 1);
    }

    // Ground slab and a hipped roof on Level 2.
    let slab = p.types_of(Category::Floors).find(|t| t.name.starts_with("Timber")).unwrap().id;
    edit::add_floor(&mut p, l1, slab, vec![v(-176.5, -176.5), v(12176.5, -176.5), v(12176.5, 8176.5), v(-176.5, 8176.5)]).unwrap();
    let roof = p.types_of(Category::Roofs).next().unwrap().id;
    edit::add_roof(&mut p, l2, roof, vec![v(-176.5, -176.5), v(12176.5, -176.5), v(12176.5, 8176.5), v(-176.5, 8176.5)], RoofShape::Hip, 0.0).unwrap();

    // Rooms.
    for (pt, name, finish) in [(v(3500.0, 4000.0), "Living", "Timber"), (v(9500.0, 6200.0), "Bedroom", "Carpet"), (v(9500.0, 2200.0), "Kitchen", "Tiles")] {
        let id = edit::add_room(&mut p, l1, pt).unwrap();
        if let Some(Element { kind: ElementKind::Room(r), .. }) = p.element_mut(id) {
            r.name = name.into();
            r.floor_finish = finish.into();
        }
    }

    // Furniture.
    let table = fam_type(&p, "Table-Dining", "1600 x 800");
    edit::place_free(&mut p, table, l1, v(3500.0, 4500.0), 0.0).unwrap();
    edit::place_free(&mut p, table, l1, v(9500.0, 2000.0), 90.0).unwrap();

    // The sample's plans show the room colour fill and wall layers.
    for v in p.views.iter_mut() {
        v.detail = DetailLevel::Medium;
        if let ViewKind::FloorPlan { room_colors, .. } = &mut v.kind {
            *room_colors = true;
        }
    }

    // Grids.
    for (a, b) in [(v(0.0, -2500.0), v(0.0, 10500.0)), (v(7000.0, -2500.0), v(7000.0, 10500.0)), (v(12000.0, -2500.0), v(12000.0, 10500.0))] {
        let g = edit::add_grid(&mut p, a, b).unwrap();
        if let Some(ElementKind::Grid(g)) = p.element_mut(g).map(|e| &mut e.kind) {
            g.bubble_start = true;
        }
    }
    for (a, b) in [(v(-2500.0, 0.0), v(14500.0, 0.0)), (v(-2500.0, 8000.0), v(14500.0, 8000.0))] {
        let g = edit::add_grid(&mut p, a, b).unwrap();
        if let Some(ElementKind::Grid(g)) = p.element_mut(g).map(|e| &mut e.kind) {
            g.bubble_start = true;
        }
    }

    // Ceiling in the living room, attach exterior walls to the roof, and add footings.
    let ceil = p.types_of(Category::Ceilings).next().unwrap().id;
    if let Some(b) = crate::analysis::find_enclosure(&p, l1, v(3500.0, 4000.0)) {
        edit::add_ceiling(&mut p, l1, ceil, b.interior, 2700.0).unwrap();
    }
    let roof_id = p.elements.iter().find(|e| matches!(e.kind, ElementKind::Roof(_))).map(|e| e.id).unwrap();
    let _ = roof_id;
    let footing = p.types_of(Category::StructuralFoundations).next().unwrap().id;
    for w in &ext_walls {
        edit::add_wall_foundation(&mut p, *w, footing).unwrap();
    }

    // Plan annotation: door tags, an overall dimension and a north arrow.
    let plan_view = p.views.iter().find(|x| matches!(x.kind, ViewKind::FloorPlan { level, .. } if level == l1)).unwrap().id;
    edit::tag_all(&mut p, plan_view, &[Category::Doors, Category::Windows, Category::Rooms]).unwrap();
    edit::add_dimension(
        &mut p,
        plan_view,
        vec![
            DimRef { element: Some(ext_walls[3]), part: RefPart::WallExterior, point: v(0.0, 4000.0) },
            DimRef { element: Some(w1), part: RefPart::WallCenter, point: v(7000.0, 4000.0) },
            DimRef { element: Some(ext_walls[1]), part: RefPart::WallExterior, point: v(12000.0, 4000.0) },
        ],
        DVec2::X,
        v(0.0, -1800.0),
    )
    .unwrap();
    edit::add_symbol(&mut p, plan_view, SymbolKind::NorthArrow, v(15500.0, 9000.0));

    // A building section through the living room and kitchen.
    edit::new_section(&mut p, v(-1500.0, 3000.0), v(13500.0, 3000.0), 12000.0).unwrap();

    // A sheet with the ground floor plan, the 3D view and the door schedule.
    let sheet = edit::new_sheet(&mut p, SheetSize::A1);
    p.view_mut(sheet).unwrap().name = "Ground Floor".into();
    let plan = p.views.iter().find(|x| matches!(x.kind, ViewKind::FloorPlan { level, .. } if level == l1)).unwrap().id;
    let view3d = p.views.iter().find(|x| matches!(x.kind, ViewKind::ThreeD { .. })).unwrap().id;
    if let Some(View { kind: ViewKind::ThreeD { eye, target, .. }, .. }) = p.view_mut(view3d) {
        *eye = crate::geom::DVec3::new(-9000.0, -15000.0, 12000.0);
        *target = crate::geom::DVec3::new(6000.0, 4000.0, 1800.0);
    }
    let doors = p.views.iter().find(|x| x.name == "Door Schedule").unwrap().id;
    edit::place_on_sheet(&mut p, sheet, plan, 230.0, 360.0).unwrap();
    edit::place_on_sheet(&mut p, sheet, view3d, 560.0, 420.0).unwrap();
    edit::place_on_sheet(&mut p, sheet, doors, 560.0, 220.0).unwrap();
    p
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{analysis, build3d, ifc, plan, schedule, sheet};

    #[test]
    fn sample_house_is_consistent() {
        let p = sample_house();
        let rooms: Vec<f64> = p
            .elements
            .iter()
            .filter_map(|e| e.as_room())
            .map(|r| analysis::room_boundary(&p, r).expect("enclosed").area())
            .collect();
        assert_eq!(rooms.len(), 3);
        assert!(rooms.iter().all(|a| *a > 10e6));
        let fp = analysis::wall_footprints(&p);
        let tris: usize = p.elements.iter().map(|e| build3d::element_mesh(&p, e, &fp).by_material.values().map(|m| m.triangle_count()).sum::<usize>()).sum();
        assert!(tris > 500, "{tris}");
        let plan_view = p.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. })).unwrap();
        assert!(plan::floor_plan(&p, plan_view, &fp).prims.len() > 20);
        let doors = p.views.iter().find(|v| v.name == "Door Schedule").unwrap();
        if let ViewKind::Schedule(d) = &doors.kind {
            assert_eq!(schedule::build(&p, d).rows.len(), 5);
        }
        let sheet_view = p.views.iter().find(|v| matches!(v.kind, ViewKind::Sheet(_))).unwrap();
        let page = sheet::to_pdf_page(&p, sheet_view, &fp, &mut |_, w, h| Some(crate::pdf::Image { width: w, height: h, rgb: vec![200; (w * h * 3) as usize] }));
        assert!(!crate::pdf::write(vec![page], "t").is_empty());
        let r = ifc::import(&ifc::export(&p, "s.ifc", "now")).unwrap();
        assert!(r.warnings.is_empty(), "{:?}", r.warnings);
        // Every exchanged model category comes back with the same count (annotation, reference
        // and view-specific elements are not part of the IFC exchange).
        let exchanged = |e: &Element| {
            e.is_model()
                && !matches!(
                    e.kind,
                    ElementKind::RefPlane(_)
                        | ElementKind::Line(_)
                        | ElementKind::RoomSeparation(_)
                        | ElementKind::AreaBoundary(_)
                        | ElementKind::Area(_)
                        | ElementKind::Shaft(_)
                        | ElementKind::GroupInstance(_)
                        | ElementKind::Cad(_)
                )
        };
        let counts = |q: &Project| {
            let mut m = std::collections::BTreeMap::new();
            for e in q.elements.iter().filter(|e| exchanged(e)) {
                *m.entry(format!("{:?}", e.category())).or_insert(0) += 1;
            }
            m
        };
        assert_eq!(counts(&r.project), counts(&p));
    }
}
