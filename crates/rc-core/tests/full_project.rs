//! End-to-end: a whole project built through the public API the way a user works, then every
//! view drawn, every schedule built, saved and reloaded, and exported to IFC, DXF and PDF.

use rc_core::geom::{DVec2, DVec3};
use rc_core::model::*;
use rc_core::{analysis, annotation, edit, io, params, schedule, section, sheet};

fn v(x: f64, y: f64) -> DVec2 {
    DVec2::new(x, y)
}

fn count(p: &Project, c: Category) -> usize {
    p.elements.iter().filter(|e| e.category() == c && e.view.is_none() && e.group.is_none()).count()
}

#[test]
fn full_project_workflow() {
    let mut doc = Document::new(rc_core::sample::sample_house());
    let l1 = doc.data.levels()[0].0;
    let l2 = doc.data.levels()[1].0;
    let plan = doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { level, .. } if level == l1)).unwrap().id;

    // --- Modelling: a level, a wing with doors and windows, structure, stairs.
    let (wing_walls, l3) = doc
        .transact("wing", |p| {
            let l3 = edit::add_level(p, "Level 3", 6000.0)?;
            let ext = p.types_of(Category::Walls).find(|t| t.name == "Exterior - Brick on Block").unwrap().id;
            let pts = [v(12000.0, 8000.0), v(18000.0, 8000.0), v(18000.0, 0.0), v(12000.0, 0.0)];
            let mut walls = Vec::new();
            for k in 0..3 {
                walls.push(edit::add_wall(p, l1, ext, pts[k], pts[k + 1], 3000.0)?);
            }
            Ok((walls, l3))
        })
        .unwrap();
    doc.transact("openings", |p| {
        let door = p.families.iter().find(|f| f.category == Category::Doors).unwrap().types[0].id;
        let win = p.families.iter().find(|f| f.category == Category::Windows).unwrap().types[0].id;
        edit::place_hosted(p, door, wing_walls[1], 4000.0, false)?;
        edit::place_hosted(p, win, wing_walls[0], 3000.0, false)?;
        // Two openings cannot overlap.
        assert!(edit::place_hosted(p, win, wing_walls[0], 3000.0, false).is_err());
        Ok(())
    })
    .unwrap();
    doc.transact("structure", |p| {
        let grids: Vec<Id> = p.elements.iter().filter(|e| matches!(e.kind, ElementKind::Grid(_))).map(|e| e.id).collect();
        let col = p.families.iter().find(|f| f.category == Category::StructuralColumns).unwrap().types[0].id;
        let cols = edit::columns_at_grids(p, col, l1, &grids)?;
        assert!(!cols.is_empty() || grids.len() < 2);
        let beam = p.families.iter().find(|f| f.category == Category::StructuralFraming).unwrap().types[0].id;
        edit::add_beam(p, beam, l2, v(0.0, 0.0), v(7000.0, 0.0))?;
        let stair = p.types_of(Category::Stairs).next().unwrap().id;
        let rail = p.types_of(Category::Railings).next().map(|t| t.id);
        edit::add_stair(p, l1, stair, vec![StairRun { start: v(13000.0, 1000.0), end: v(13000.0, 6000.0), width: 1100.0 }], rail)?;
        let ceiling = p.types_of(Category::Ceilings).next().unwrap().id;
        edit::add_ceiling(p, l1, ceiling, vec![v(200.0, 200.0), v(6800.0, 200.0), v(6800.0, 7800.0), v(200.0, 7800.0)], 2600.0)?;
        Ok(())
    })
    .unwrap();
    assert_eq!(count(&doc.data, Category::Walls), 9);
    let base = rc_core::sample::sample_house();
    assert_eq!(count(&doc.data, Category::Stairs), count(&base, Category::Stairs) + 1);
    assert_eq!(count(&doc.data, Category::Ceilings), count(&base, Category::Ceilings) + 1);
    assert_eq!(doc.data.levels().len(), 3);
    let _ = l3;

    // --- Rooms are bounded by the walls; areas are measured to the wall faces.
    let room = doc.transact("room", |p| edit::add_room(p, l1, v(15000.0, 4000.0))).unwrap();
    let ElementKind::Room(r) = &doc.data.element(room).unwrap().kind else { panic!() };
    let _ = r;
    let a = match params::get(&doc.data, doc.data.element(room).unwrap(), "Area") {
        Some(params::Value::Num(x)) => x,
        _ => 0.0,
    };
    assert!(a > 30.0e6 && a < 48.0e6, "wing room area {a}");

    // --- Annotation: dimension, tags, text, keynote, spot elevation, detail items.
    doc.transact("annotate", |p| {
        let (w0, w1) = (wing_walls[0], wing_walls[2]);
        edit::add_dimension(p, plan, vec![DimRef { element: Some(w0), part: RefPart::WallCenter, point: v(15000.0, 8000.0) }, DimRef { element: Some(w1), part: RefPart::WallCenter, point: v(15000.0, 0.0) }], DVec2::Y, v(19000.0, 4000.0))?;
        let n = edit::tag_all(p, plan, &[Category::Doors, Category::Windows, Category::Rooms])?;
        assert_eq!(n, 3, "only the new door, window and room are untagged");
        edit::add_text(p, plan, v(15000.0, -2000.0), "NEW WING", 2.5)?;
        params::set(p, wing_walls[0], "Keynote", "04 21 13.A1")?;
        let t = edit::add_tag(p, plan, wing_walls[0], v(15000.0, 9000.0), true)?;
        if let Some(ElementKind::Tag(t)) = p.element_mut(t).map(|e| &mut e.kind) {
            t.parameter = "Keynote".into();
        }
        edit::add_insulation(p, plan, v(12000.0, 9500.0), v(18000.0, 9500.0), 75.0)?;
        edit::add_repeating_detail(p, plan, v(19000.0, 0.0), v(19000.0, 2000.0), "Brick")?;
        Ok(())
    })
    .unwrap();
    let dims: Vec<f64> = doc.data.elements.iter().filter_map(|e| match &e.kind {
        ElementKind::Dimension(d) if e.view == Some(plan) => annotation::segments(&doc.data, d).first().copied(),
        _ => None,
    }).collect();
    assert!(dims.iter().any(|d| (d - 8000.0).abs() < 1e-6), "{dims:?}");

    // --- Project parameter, view filter, global parameter.
    doc.transact("params", |p| {
        p.project_params.push(ProjectParameter { name: "Fire Rating".into(), kind: ParamKind::Text, group: "Identity Data".into(), instance: true, categories: vec![Category::Doors], guid: String::new() });
        let d = p.elements.iter().find(|e| e.category() == Category::Doors).unwrap().id;
        params::set(p, d, "Fire Rating", "60 min")?;
        let fid = p.new_id();
        p.filters.push(ViewFilter { id: fid, name: "Rated doors".into(), categories: vec![Category::Doors], rules: vec![FilterRule { param: "Fire Rating".into(), op: FilterOp::HasValue, value: String::new() }], any: false });
        p.view_mut(plan).unwrap().overrides.push(GraphicOverride { filter: Some(fid), line_color: Some([255, 0, 0]), ..Default::default() });
        p.global_params.push(GlobalParameter { name: "Wing Height".into(), kind: ParamKind::Length, value: 3500.0, ..Default::default() });
        params::set(p, wing_walls[1], "Top Constraint", "Unconnected")?;
        p.element_mut(wing_walls[1]).unwrap().global_links.insert("Unconnected Height".into(), "Wing Height".into());
        Ok(())
    })
    .unwrap();
    assert!((doc.data.wall(wing_walls[1]).unwrap().unconnected_height - 3500.0).abs() < 1e-6);
    let rated = doc.data.elements.iter().filter(|e| e.category() == Category::Doors).filter(|e| params::effective_override(&doc.data, doc.data.view(plan).unwrap(), e).is_some()).count();
    assert_eq!(rated, 1);

    // --- Groups and paint.
    doc.transact("groups", |p| {
        let tables: Vec<Id> = p.elements.iter().filter(|e| e.category() == Category::Furniture).map(|e| e.id).take(1).collect();
        let g = edit::create_group(p, &tables, "Dining")?;
        let ty = match &p.element(g).unwrap().kind {
            ElementKind::GroupInstance(gi) => gi.type_id,
            _ => unreachable!(),
        };
        edit::place_group(p, ty, v(15000.0, 4000.0), l1)?;
        edit::paint_face(p, wing_walls[0], DVec3::Y, DVec3::new(15000.0, 8000.0, 1000.0), "Paint - White")
            .or_else(|_| edit::paint_face(p, wing_walls[0], -DVec3::Y, DVec3::new(15000.0, 8000.0, 1000.0), "Paint - White"))
            .ok();
        Ok(())
    })
    .unwrap();
    assert_eq!(doc.data.group_types.iter().filter(|g| g.name == "Dining").count(), 1);

    // --- Views and sheets.
    let (section_v, sheet_v, sched_v, threed) = doc
        .transact("views", |p| {
            let s = edit::new_section(p, v(-2000.0, 4000.0), v(20000.0, 4000.0), 12000.0)?;
            let sh = edit::new_sheet(p, SheetSize::A1);
            let sc = edit::new_schedule(p, Category::Doors);
            let t = edit::new_3d_view(p);
            let dup = edit::duplicate_view(p, plan, true)?;
            edit::place_on_sheet(p, sh, dup, 250.0, 350.0)?;
            edit::place_on_sheet(p, sh, s, 250.0, 120.0)?;
            edit::place_on_sheet(p, sh, sc, 600.0, 400.0)?;
            edit::place_on_sheet(p, sh, t, 600.0, 200.0)?;
            // A general note and a revision cloud drawn on the sheet itself.
            edit::add_text(p, sh, v(60.0, 60.0), "GENERAL NOTES", 3.5)?;
            Ok((s, sh, sc, t))
        })
        .unwrap();
    let _ = threed;
    let fp = analysis::wall_footprints(&doc.data);
    let p = &doc.data;

    // Every view draws; plans and sections contain the wing.
    for view in p.views.iter().filter(|v| !v.is_template) {
        match &view.kind {
            ViewKind::Schedule(def) => {
                let t = schedule::build(p, def);
                assert!(!t.columns.is_empty(), "{}", view.name);
            }
            ViewKind::Sheet(_) => {
                assert!(!sheet::layout(p, view, &fp).is_empty(), "{}", view.name);
            }
            ViewKind::ThreeD { .. } => {}
            _ => {
                let d = sheet::view_drawing(p, view, &fp).unwrap_or_else(|| panic!("no drawing for {}", view.name));
                assert!(!d.prims.is_empty() || matches!(view.kind, ViewKind::Legend | ViewKind::Drafting), "{} is empty", view.name);
            }
        }
    }
    let sec = section::drawing(p, p.view(section_v).unwrap(), &fp);
    assert!(sec.prims.iter().any(|(id, _)| wing_walls.contains(&id.unwrap_or(0))));
    let ViewKind::Schedule(def) = &p.view(sched_v).unwrap().kind else { panic!() };
    let doors = schedule::build(p, def);
    assert_eq!(doors.rows.iter().filter(|r| r.kind == schedule::RowKind::Item).count(), count(p, Category::Doors));

    let layout = sheet::layout(p, p.view(sheet_v).unwrap(), &fp);
    assert!(layout.iter().any(|q| matches!(q, sheet::SheetPrim::Text { text, .. } if text == "GENERAL NOTES")), "sheet note missing from the layout");

    // --- Save and reload: identical project.
    let json = io::to_json(p);
    let back = io::from_json(&json).unwrap();
    assert_eq!(io::to_json(&back), json);

    // --- IFC round trip keeps the building elements.
    let ifc = rc_core::ifc::export(p, "full.ifc", "2026-10-15T00:00:00");
    let imported = rc_core::ifc::import(&ifc).unwrap().project;
    for c in [Category::Walls, Category::Doors, Category::Windows, Category::Floors, Category::Roofs] {
        assert_eq!(count(&imported, c), count(p, c), "IFC round trip changed {} count", c.label());
    }

    // --- DXF and PDF.
    let dxf = rc_core::dxf::export_view(p, p.view(plan).unwrap(), &fp).unwrap();
    assert!(dxf.contains("ENTITIES") && dxf.len() > 10_000);
    let dxf_sheet = rc_core::dxf::export_sheet(p, p.view(sheet_v).unwrap(), &fp);
    assert!(dxf_sheet.contains("ENTITIES"));
    let page = sheet::to_pdf_page(p, p.view(sheet_v).unwrap(), &fp, &mut |_, _, _| None);
    let pdf = rc_core::pdf::write(vec![page], "Full");
    assert!(pdf.starts_with(b"%PDF"));

    // --- Undo everything back to the sample, then redo it all.
    let depth = doc.undo_depth();
    let elements = doc.data.elements.len();
    while doc.can_undo() {
        doc.undo();
    }
    assert_eq!(doc.data.elements.len(), rc_core::sample::sample_house().elements.len());
    for _ in 0..depth {
        doc.redo();
    }
    assert_eq!(doc.data.elements.len(), elements);
}
