//! Command execution: every ribbon button, shortcut and menu item lands here.

use crate::app::{App, Clipboard, TempHide};
use crate::commands::Cmd;
use crate::dialogs::{self, Pending};
use crate::snap::{Override, SnapKind};
use crate::tools::{DrawMode, Seg, Sketch, SketchKind, Tool, ToolKind};
use crate::{canvas, canvas_tools};
use rc_core::geom::{self, DVec2};
use rc_core::model::*;
use rc_core::{edit, io};
use std::collections::HashSet;

/// Is a command available right now (greys out ribbon buttons)?
pub fn enabled(app: &App, cmd: Cmd) -> bool {
    use Cmd::*;
    let view = app.active_view();
    let plan = view.is_some_and(|v| v.plan_level().is_some());
    let graphical_2d = view.is_some_and(|v| v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. }));
    let sel = !app.selection.is_empty();
    let sel_el = |f: &dyn Fn(&Element) -> bool| app.selection.iter().any(|id| app.el(*id).is_some_and(f));
    let in_sketch = app.sketch.is_some();
    match cmd {
        Undo => app.doc.can_undo() || in_sketch,
        Redo => app.doc.can_redo(),
        Door | Window | Component | Column | StructColumn | Beam | IsolatedFoundation | WallFoundation | Room | RoomSeparator | RoomTag | Grid | RefPlane
        | ModelLine | Ceiling | Floor | FloorStructural | RoofFootprint | Railing | Stair | Shaft | WallOpening | CurtainGrid | Section | Callout | ElevationView
        | PlaceGroup | Wall | WallStructural | AutoCeiling | SketchCeiling => !in_sketch && app.group_edit.as_ref().is_none_or(|_| true),
        Area | AreaBoundary | AreaTag => view.is_some_and(|v| matches!(v.kind, ViewKind::AreaPlan { .. })) && !in_sketch,
        RoofExtrusion => view.is_some_and(|v| matches!(v.kind, ViewKind::Section { .. } | ViewKind::Elevation { .. })) && !in_sketch,
        Level => !plan && graphical_2d,
        DimAligned | DimLinear | DimAngular | DimRadial | DimDiameter | DimArcLength | SpotElevation | DetailLine | FilledRegion | MaskingRegion | RevisionCloud
        | Text | TagByCategory | TagAll | Symbol | SpotCoordinate | SpotSlope => graphical_2d && !in_sketch,
        SaveSelection => sel,
        Insulation | DetailComponent | MultiCategoryTag | MaterialTag => graphical_2d && !in_sketch,
        ScopeBox => plan && !in_sketch,
        JoinGeometry | UnjoinGeometry => !in_sketch && view.is_some_and(|v| v.is_graphical()),
        ShowHiddenLines | RemoveHiddenLines => graphical_2d && !in_sketch,
        SwitchWindows => !app.open_tabs().is_empty(),
        LoadSelection | EditSelection => !app.doc.data.selection_sets.is_empty(),
        SelectJoined => sel_el(&|e| matches!(e.kind, ElementKind::Wall(_))),
        ExportCsv => view.is_some_and(|v| matches!(v.kind, ViewKind::Schedule(_))),
        PlaceView => view.is_some_and(|v| matches!(v.kind, ViewKind::Sheet(_))),
        TypeProperties => true,
        Paste | PasteSameLevel => app.clipboard.is_some(),
        Cut | CopyClip | Delete | MatchType | Pin | Unpin | Move | Copy | Rotate | MirrorPick | MirrorDraw | Array | Scale | HideElements | HideCategory
        | OverrideElements | CreateSimilar | SelectAllVisible | SelectAllProject | TempHideElement | TempIsolateElement | TempHideCategory | TempIsolateCategory
        | Demolish | CreateGroup | IdsOfSelection => sel,
        EditBoundary => app.selection.len() == 1 && sel_el(&|e| matches!(&e.kind, ElementKind::Floor(_) | ElementKind::Ceiling(_) | ElementKind::Region(_)) || matches!(&e.kind, ElementKind::Roof(r) if r.kind == RoofKind::Footprint)),
        AttachTop | AttachBase | Detach | FlipWall | WallJoinToggle => sel_el(&|e| matches!(e.kind, ElementKind::Wall(_))),
        EditGroup | Ungroup => app.selection.len() == 1 && sel_el(&|e| matches!(e.kind, ElementKind::GroupInstance(_))),
        FinishGroup | CancelGroup => app.group_edit.is_some(),
        EditFamily => app.selection.len() == 1 && sel_el(&|e| matches!(e.kind, ElementKind::Instance(_))),
        PickNewHost | FlipFacing | FlipHand => sel_el(&|e| matches!(&e.kind, ElementKind::Instance(i) if i.host.is_some())),
        GoToView => app.selection.iter().any(|id| app.doc.data.view(*id).is_some()),
        FinishSketch | CancelSketch => in_sketch,
        TempReset => app.active.and_then(|a| app.temp_hide.get(&a)).is_some_and(|t| t.is_active()),
        UnhideElements => sel && app.active.is_some_and(|a| app.reveal_hidden.contains(&a)),
        ToggleSectionBox => view.is_some_and(|v| matches!(v.kind, ViewKind::ThreeD { .. })),
        ViewRange => plan,
        DuplicateView | DuplicateWithDetailing | TemplateFromView | VisibilityGraphics | ZoomFit | ZoomRegion | ZoomOut => view.is_some(),
        PrevPanZoom => app.active.is_some_and(|v| canvas::can_step(app, v, true)),
        ScheduleFields | ScheduleFilter | ScheduleSorting => app.active_view().is_some_and(|v| matches!(v.kind, ViewKind::Schedule(_))),
        HighlightInModel => !app.selection.is_empty(),
        NextPanZoom => app.active.is_some_and(|v| canvas::can_step(app, v, false)),
        _ => true,
    }
}

pub fn exec(app: &mut App, cmd: Cmd) {
    if !enabled(app, cmd) {
        let why = match cmd {
            Cmd::Level => "Levels are created in sections and elevations. Open one first.",
            Cmd::Area | Cmd::AreaBoundary | Cmd::AreaTag => "Open an area plan to use area tools (View > Plan Views > Area Plan).",
            Cmd::RoofExtrusion => "Extrusion roofs are sketched in a section or elevation view.",
            Cmd::Paste | Cmd::PasteSameLevel => "The clipboard is empty.",
            _ if app.sketch.is_some() => "Finish or cancel the sketch first.",
            _ if !matches!(cmd, Cmd::Undo | Cmd::Redo) && app.selection.is_empty() => "Select elements first.",
            _ => "",
        };
        if !why.is_empty() {
            app.error(why);
        }
        return;
    }
    // Remember repeatable commands (Enter / right-click Repeat).
    if is_tool_cmd(cmd) {
        app.last_cmd = Some(cmd);
        app.recent_cmds.retain(|c| *c != cmd);
        app.recent_cmds.push(cmd);
        if app.recent_cmds.len() > 10 {
            app.recent_cmds.remove(0);
        }
    }
    use Cmd::*;
    match cmd {
        // ---------------- file
        New => {
            if app.confirm_discard(Pending::New) {
                app.dialogs.new_project = true;
            }
        }
        Open => {
            if app.confirm_discard(Pending::Open) {
                app.open_dialog();
            }
        }
        Save => {
            app.save();
        }
        SaveAs => {
            app.save_as();
        }
        OpenSample => {
            if app.confirm_discard(Pending::Sample) {
                app.open_sample();
            }
        }
        ImportIfc => {
            if app.confirm_discard(Pending::ImportIfc) {
                if let Some(path) = rfd::FileDialog::new().add_filter("IFC", &["ifc"]).pick_file() {
                    app.import_ifc_path(&path);
                }
            }
        }
        ExportIfc => export_ifc(app),
        ExportDxf => app.dialogs.export = Some(dialogs::ExportKind::Dxf),
        ExportPdf => app.dialogs.export = Some(dialogs::ExportKind::Pdf),
        ExportImage => app.dialogs.export = Some(dialogs::ExportKind::Image),
        ExportCsv => export_csv(app),
        Options => app.dialogs.options = true,
        Exit => app.dialogs.exit = true,
        Undo => app.undo(),
        Redo => app.redo(),

        // ---------------- architecture / structure
        Modify => {
            app.tool = Tool::select();
            app.typed.clear();
            app.interact.drag = None;
        }
        Wall | WallStructural => {
            app.opts.wall_structural = cmd == WallStructural;
            start_drawing(app, ToolKind::Wall);
        }
        Door => app.set_tool(ToolKind::Door),
        Window => app.set_tool(ToolKind::Window),
        Component => {
            if app.doc.data.family_type(app.opts.component_type).is_none() {
                app.error("There are no component families loaded. Use Insert > Load Family.");
                return;
            }
            app.set_tool(ToolKind::Component);
        }
        Column => app.set_tool(ToolKind::Column),
        StructColumn => app.set_tool(ToolKind::StructColumn),
        Beam => start_drawing(app, ToolKind::Beam),
        IsolatedFoundation => app.set_tool(ToolKind::IsolatedFooting),
        WallFoundation => {
            // With walls selected, add foundations to all of them at once.
            let walls: Vec<Id> = app.selection.iter().copied().filter(|id| app.doc.data.wall(*id).is_some()).collect();
            if walls.is_empty() {
                app.set_tool(ToolKind::WallFoundation);
            } else {
                let ft = app.opts.foundation_type;
                app.run("Wall Foundation", |p| {
                    for w in &walls {
                        edit::add_wall_foundation(p, *w, ft)?;
                    }
                    Ok(())
                });
            }
        }
        Floor | FloorStructural => start_sketch(app, SketchKind::Floor { structural: cmd == FloorStructural }, DrawMode::PickWalls),
        Ceiling | AutoCeiling => app.set_tool(ToolKind::CeilingAuto),
        SketchCeiling => start_sketch(app, SketchKind::Ceiling, DrawMode::PickWalls),
        RoofFootprint => start_sketch(app, SketchKind::Roof, DrawMode::PickWalls),
        RoofExtrusion => start_sketch(app, SketchKind::RoofExtrusion, DrawMode::Line),
        Shaft => start_sketch(app, SketchKind::Shaft, DrawMode::Rect),
        InPlaceMass => {
            app.show_mass = true;
            start_sketch(app, SketchKind::Mass, DrawMode::Rect)
        }
        Toposolid => start_sketch(app, SketchKind::Toposolid, DrawMode::Line),
        PropertyLine => start_sketch(app, SketchKind::PropertyLine, DrawMode::Line),
        ShowMass => app.show_mass = !app.show_mass,
        SiteComponent | ParkingComponent => {
            let cats: &[Category] = if cmd == ParkingComponent { &[Category::Parking] } else { &[Category::Planting, Category::Site] };
            // The last used site type, else the first planting, else any site family.
            let cur = app.opts.component_type;
            let fams = &app.doc.data.families;
            let t = fams
                .iter()
                .find(|f| cats.contains(&f.category) && f.types.iter().any(|t| t.id == cur))
                .map(|_| cur)
                .or_else(|| cats.iter().find_map(|c| fams.iter().filter(|f| f.category == *c).find_map(|f| f.types.first()).map(|t| t.id)));
            match t {
                Some(t) => {
                    app.opts.component_type = t;
                    app.set_tool(ToolKind::Component);
                }
                None => app.error("No site families are loaded. Use Load Family to load one."),
            }
        }
        WallByFace | CurtainSystemByFace | FloorByFace | RoofByFace => {
            let masses: Vec<Id> = app.selection.iter().copied().filter(|id| app.el(*id).is_some_and(|e| matches!(e.kind, ElementKind::Mass(_)))).collect();
            if masses.is_empty() {
                app.error("Select a mass first, then choose a Model by Face tool.");
                return;
            }
            let p = &app.doc.data;
            let (what, ty) = match cmd {
                WallByFace => (edit::ByFace::Walls, app.opts.wall_type),
                CurtainSystemByFace => (
                    edit::ByFace::CurtainSystem,
                    p.types_of(Category::Walls).find(|t| t.wall_kind == WallKind::Curtain).map(|t| t.id).unwrap_or(app.opts.wall_type),
                ),
                FloorByFace => (edit::ByFace::Floors, app.opts.floor_type),
                _ => (edit::ByFace::Roof, app.opts.roof_type),
            };
            if let Some(made) = app.run(cmd.info().label, |p| {
                let mut all = Vec::new();
                for m in &masses {
                    all.extend(edit::model_by_face(p, *m, what, ty)?);
                }
                Ok(all)
            }) {
                app.select(made);
            }
        }
        ModifySubElements => app.set_tool(ToolKind::TopoPoints),
        ColorFillLegend => app.set_tool(ToolKind::ColorLegend),
        Railing => start_sketch(app, SketchKind::Railing, DrawMode::Line),
        Stair => start_sketch(app, SketchKind::Stair, DrawMode::Line),
        FilledRegion => start_sketch(app, SketchKind::Region { masking: false }, DrawMode::Rect),
        MaskingRegion => start_sketch(app, SketchKind::Region { masking: true }, DrawMode::Rect),
        RevisionCloud => start_sketch(app, SketchKind::RevisionCloud, DrawMode::Rect),
        CurtainGrid => app.set_tool(ToolKind::CurtainGrid),
        ModelLine => start_drawing(app, ToolKind::ModelLine),
        DetailLine => start_drawing(app, ToolKind::DetailLine),
        PlaceGroup => {
            if app.doc.data.group_types.is_empty() {
                app.error("The project has no groups. Select elements and use Create Group first.");
                return;
            }
            app.set_tool(ToolKind::PlaceGroup);
        }
        CreateGroup => app.dialogs.create_group = Some(next_group_name(app)),
        Room => app.set_tool(ToolKind::Room),
        RoomSeparator => start_drawing(app, ToolKind::RoomSeparator),
        RoomTag => app.set_tool(ToolKind::RoomTag),
        Area => app.set_tool(ToolKind::Area),
        AreaBoundary => start_drawing(app, ToolKind::AreaBoundary),
        AreaTag => app.set_tool(ToolKind::AreaTag),
        WallOpening => app.set_tool(ToolKind::WallOpening),
        Level => app.set_tool(ToolKind::Level),
        Grid => start_drawing(app, ToolKind::Grid),
        RefPlane => start_drawing(app, ToolKind::RefPlane),

        // ---------------- insert
        LinkCad | ImportCad => {
            if let Some(path) = rfd::FileDialog::new().add_filter("DXF drawing", &["dxf"]).pick_file() {
                link_cad_path(app, &path);
            }
        }
        LoadFamily => {
            if let Some(path) = rfd::FileDialog::new().add_filter("RevitCraft Family", &[io::FAMILY_EXTENSION]).pick_file() {
                load_family_path(app, &path);
            }
        }

        // ---------------- annotate
        DimAligned => app.set_tool(ToolKind::Dimension(DimKind::Aligned)),
        DimLinear => app.set_tool(ToolKind::Dimension(DimKind::Linear)),
        DimAngular => app.set_tool(ToolKind::Dimension(DimKind::Angular)),
        DimRadial => app.set_tool(ToolKind::Dimension(DimKind::Radial)),
        DimDiameter => app.set_tool(ToolKind::Dimension(DimKind::Diameter)),
        DimArcLength => app.set_tool(ToolKind::Dimension(DimKind::ArcLength)),
        SpotElevation => app.set_tool(ToolKind::Dimension(DimKind::SpotElevation)),
        SpotCoordinate => app.set_tool(ToolKind::Dimension(DimKind::SpotCoordinate)),
        SpotSlope => app.set_tool(ToolKind::Dimension(DimKind::SpotSlope)),
        FindReplace => app.dialogs.find_replace = Some(Default::default()),
        Text => app.set_tool(ToolKind::Text),
        TagByCategory => {
            app.opts.tag_mode = 0;
            app.set_tool(ToolKind::Tag);
        }
        MultiCategoryTag => {
            app.opts.tag_mode = 1;
            app.set_tool(ToolKind::Tag);
        }
        MaterialTag => {
            app.opts.tag_mode = 2;
            app.set_tool(ToolKind::Tag);
        }
        ScopeBox => app.set_tool(ToolKind::ScopeBox),
        JoinGeometry => app.set_tool(ToolKind::JoinGeometry),
        UnjoinGeometry => app.set_tool(ToolKind::UnjoinGeometry),
        ShowHiddenLines => app.set_tool(ToolKind::ShowHiddenLines),
        RemoveHiddenLines => app.set_tool(ToolKind::RemoveHiddenLines),
        SwitchWindows => app.cycle_views(),
        CanvasTheme => {
            app.settings.black_canvas = !app.settings.black_canvas;
            app.scenes.clear();
        }
        Insulation => app.set_tool(ToolKind::Insulation),
        DetailComponent => app.set_tool(ToolKind::DetailComponent),
        TagAll => app.dialogs.tag_all = true,
        Symbol => app.set_tool(ToolKind::Symbol),

        // ---------------- view
        ViewTemplates => app.dialogs.view_templates = true,
        TemplateFromView => {
            if let Some(v) = app.active {
                let name = format!("{} Template", app.doc.data.view(v).map(|v| v.name.clone()).unwrap_or_default());
                if app.run("Create View Template", |p| edit::template_from_view(p, v, &name)).is_some() {
                    app.info(format!("Created view template '{name}'."));
                }
            }
        }
        VisibilityGraphics => app.dialogs.vg = app.active,
        ThinLines => app.thin_lines = !app.thin_lines,
        Default3D => {
            let existing = app.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::ThreeD { .. }) && v.name == "{3D}").map(|v| v.id);
            let id = match existing {
                Some(id) => Some(id),
                None => app.run("Default 3D View", |p| {
                    let id = edit::new_3d_view(p);
                    if let Some(v) = p.view_mut(id) {
                        v.name = "{3D}".into();
                    }
                    Ok(id)
                }),
            };
            if let Some(id) = id {
                app.open_view(id);
            }
        }
        Section => app.set_tool(ToolKind::Section),
        Callout => app.set_tool(ToolKind::Callout),
        NewFloorPlan => app.dialogs.new_plan = Some(dialogs::PlanKind::Floor),
        NewCeilingPlan => app.dialogs.new_plan = Some(dialogs::PlanKind::Ceiling),
        NewAreaPlan => app.dialogs.new_plan = Some(dialogs::PlanKind::Area),
        ElevationView => app.set_tool(ToolKind::ElevationMarker),
        DraftingView => {
            let n = app.doc.data.views.iter().filter(|v| matches!(v.kind, ViewKind::Drafting)).count() + 1;
            if let Some(id) = app.run("Drafting View", |p| Ok(edit::new_drafting_view(p, &format!("Drafting {n}"), 20.0))) {
                app.open_view(id);
            }
        }
        DuplicateView | DuplicateWithDetailing => {
            if let Some(v) = app.active {
                let with = cmd == DuplicateWithDetailing;
                if let Some(id) = app.run("Duplicate View", |p| edit::duplicate_view(p, v, with)) {
                    app.open_view(id);
                }
            }
        }
        Legend => {
            let n = app.doc.data.views.iter().filter(|v| matches!(v.kind, ViewKind::Legend)).count() + 1;
            if let Some(id) = app.run("Legend", |p| Ok(edit::new_legend(p, &format!("Legend {n}")))) {
                app.open_view(id);
            }
        }
        Schedule => app.dialogs.new_schedule = Some(false),
        MaterialTakeoff => app.dialogs.new_schedule = Some(true),
        SheetList => {
            if let Some(id) = app.run("Sheet List", |p| Ok(edit::new_sheet_list(p))) {
                app.open_view(id);
            }
        }
        NewSheet => app.dialogs.new_sheet = true,
        PlaceView => app.dialogs.place_view = app.active,
        Revisions => app.dialogs.revisions = true,
        CloseInactive => {
            let keep = app.active;
            for t in app.open_tabs() {
                if Some(t) != keep {
                    app.close_view(t);
                }
            }
        }
        TabViews => {
            let tabs = app.open_tabs();
            app.dock = Some(egui_dock::DockState::new(tabs));
            if let Some(a) = app.active {
                app.open_view(a);
            }
        }
        TileViews => tile_views(app),
        ToggleProperties => app.settings.show_properties = !app.settings.show_properties,
        ToggleBrowser => app.settings.show_browser = !app.settings.show_browser,
        ToggleStatusBar => app.settings.show_status = !app.settings.show_status,
        ToggleOptionsBar => app.settings.show_options_bar = !app.settings.show_options_bar,
        ToggleViewCube => app.settings.show_viewcube = !app.settings.show_viewcube,
        ToggleNavBar => app.settings.show_navbar = !app.settings.show_navbar,

        // ---------------- manage
        Materials => app.dialogs.materials = Some(None),
        ObjectStyles => app.dialogs.object_styles = true,
        Snaps => app.dialogs.snaps = true,
        ProjectInfo => app.dialogs.project_info = true,
        ProjectUnits => app.dialogs.units = true,
        Purge => app.dialogs.purge = Some(Default::default()),
        Phases => app.dialogs.phases = true,
        DesignOptions => app.dialogs.design_options = true,
        Sun => app.dialogs.sun = true,
        ManageLinks => app.dialogs.links = true,
        IdsOfSelection => {
            let ids: Vec<String> = app.selection.iter().map(|i| i.to_string()).collect();
            app.dialogs.message = Some(("IDs of Selection".into(), ids.join("; ")));
        }
        SelectById => app.dialogs.select_by_id = Some(String::new()),
        ProjectParameters => app.dialogs.project_params = true,
        GlobalParameters => app.dialogs.global_params = true,
        ViewFilters => app.dialogs.filters = Some(app.doc.data.filters.first().map(|f| f.id)),
        LineStyles => app.dialogs.line_styles = true,
        SaveSelection => {
            let n = app.doc.data.selection_sets.len() + 1;
            app.dialogs.save_selection = Some(format!("Selection {n}"));
        }
        LoadSelection => app.dialogs.selection_sets = Some(false),
        EditSelection => app.dialogs.selection_sets = Some(true),
        SelectJoined => select_joined(app),
        Warnings => app.dialogs.warnings = true,
        KeyboardShortcuts => app.dialogs.shortcuts = Some(String::new()),
        Home => app.dialogs.home = !app.dialogs.home,
        ViewRange => app.dialogs.view_range = app.active,

        // ---------------- modify
        TypeProperties => {
            let t = type_for_properties(app);
            match t {
                Some(t) => app.dialogs.type_props = Some(t),
                None => app.error("Select an element that has a type, or start a placement tool."),
            }
        }
        Paste => {
            let mut t = Tool::new(ToolKind::Paste);
            t.ids = app.selection.clone();
            app.tool = t;
        }
        PasteSameLevel => paste_at(app, DVec2::ZERO, app.active_level()),
        Cut => {
            copy_to_clipboard(app);
            exec(app, Delete);
        }
        CopyClip => {
            copy_to_clipboard(app);
            app.info(format!("Copied {} element(s) to the clipboard.", app.selection.len()));
        }
        MatchType => app.set_tool(ToolKind::MatchType),
        Demolish => {
            let ids = app.selection.clone();
            let phase = app.active_view().and_then(|v| v.phase).or_else(|| app.doc.data.phases.last().map(|p| p.id));
            app.run("Demolish", |p| {
                for id in &ids {
                    if let Some(e) = p.element_mut(*id) {
                        e.phase_demolished = phase;
                    }
                }
                Ok(())
            });
        }
        Align => app.set_tool(ToolKind::Align),
        Offset => app.set_tool(ToolKind::Offset),
        MirrorPick => app.set_tool(ToolKind::MirrorPick),
        MirrorDraw => app.set_tool(ToolKind::MirrorDraw),
        Move => app.set_tool(ToolKind::Move),
        Copy => app.set_tool(ToolKind::Copy),
        Rotate => app.set_tool(ToolKind::Rotate),
        TrimCorner => app.set_tool(ToolKind::TrimCorner),
        TrimSingle => app.set_tool(ToolKind::TrimSingle),
        TrimMulti => app.set_tool(ToolKind::TrimMulti),
        Split => app.set_tool(ToolKind::Split),
        SplitGap => app.set_tool(ToolKind::SplitGap),
        Array => app.set_tool(ToolKind::Array),
        Scale => app.set_tool(ToolKind::Scale),
        Measure => app.set_tool(ToolKind::Measure),
        Pin | Unpin => {
            let ids = app.selection.clone();
            let pin = cmd == Pin;
            app.run(if pin { "Pin" } else { "Unpin" }, |p| {
                edit::set_pinned(p, &ids, pin);
                Ok(())
            });
        }
        Delete => delete_selection(app),
        HideElements | HideCategory => {
            let Some(v) = app.active else { return };
            let ids = app.selection.clone();
            let cats: Vec<Category> = ids.iter().filter_map(|id| app.el(*id).map(|e| e.category())).collect();
            app.run(if cmd == HideElements { "Hide Elements" } else { "Hide Category" }, |p| {
                let view = p.view_mut(v).ok_or("No view.")?;
                if cmd == HideElements {
                    for id in &ids {
                        if !view.hidden_elements.contains(id) {
                            view.hidden_elements.push(*id);
                        }
                    }
                } else {
                    for c in &cats {
                        if !view.hidden.contains(c) {
                            view.hidden.push(*c);
                        }
                    }
                }
                Ok(())
            });
            app.select(vec![]);
        }
        UnhideElements => {
            let Some(v) = app.active else { return };
            let ids = app.selection.clone();
            app.run("Unhide in View", |p| {
                if let Some(view) = p.view_mut(v) {
                    view.hidden_elements.retain(|id| !ids.contains(id));
                }
                Ok(())
            });
        }
        OverrideElements => app.dialogs.override_graphics = app.active,
        CreateSimilar => create_similar(app),
        SelectAllVisible | SelectAllProject => select_all_instances(app, cmd == SelectAllVisible),

        // ---------------- contextual
        EditBoundary => edit_boundary(app),
        AttachTop => app.set_tool(ToolKind::AttachTop),
        AttachBase => app.set_tool(ToolKind::AttachBase),
        Detach => {
            let ids = app.selection.clone();
            app.run("Detach Top/Base", |p| {
                edit::detach_walls(p, &ids);
                Ok(())
            });
        }
        EditGroup => {
            let id = app.selection[0];
            app.group_edit = Some((id, app.doc.data.clone()));
            app.select(vec![]);
        }
        Ungroup => {
            let id = app.selection[0];
            if app.run("Ungroup", |p| edit::ungroup(p, id)).is_some() {
                app.select(vec![]);
            }
        }
        FinishGroup => {
            if let Some((id, _)) = app.group_edit.take() {
                app.run("Finish Group Edit", |p| edit::finish_group_edit(p, id));
                app.select(vec![id]);
            }
        }
        CancelGroup => {
            if let Some((id, snapshot)) = app.group_edit.take() {
                app.run("Cancel Group Edit", |p| {
                    *p = snapshot;
                    Ok(())
                });
                app.select(vec![id]);
            }
        }
        EditFamily => {
            let fam = app.selection.first().and_then(|id| app.el(*id)).and_then(|e| e.as_instance()).map(|i| i.family_id);
            if let Some(f) = fam {
                crate::family_editor::open(app, f);
            }
        }
        NewFamily => app.dialogs.new_family = true,
        PickNewHost => app.set_tool(ToolKind::PickHost),
        GoToView => {
            if let Some(v) = app.selection.iter().copied().find(|id| app.doc.data.view(*id).is_some()) {
                app.open_view(v);
            }
        }
        FinishSketch => finish_sketch(app),
        CancelSketch => {
            app.sketch = None;
            app.tool = Tool::select();
        }
        DrawLine | DrawRect | DrawPolyIn | DrawPolyCirc | DrawCircle | DrawArc3 | DrawArcCenter | DrawArcTangent | DrawFillet | PickLines | PickWalls => {
            let mode = match cmd {
                DrawLine => DrawMode::Line,
                DrawRect => DrawMode::Rect,
                DrawPolyIn => DrawMode::PolyIn,
                DrawPolyCirc => DrawMode::PolyCirc,
                DrawCircle => DrawMode::Circle,
                DrawArc3 => DrawMode::Arc3,
                DrawArcCenter => DrawMode::ArcCenter,
                DrawArcTangent => DrawMode::ArcTangent,
                DrawFillet => DrawMode::Fillet,
                PickLines => DrawMode::PickLines,
                _ => DrawMode::PickWalls,
            };
            app.opts.draw_mode = mode;
            if app.sketch.is_some() && app.tool.kind != ToolKind::SketchLine {
                app.tool = Tool::new(ToolKind::SketchLine);
            }
            app.tool.reset();
        }
        FlipFacing | FlipHand => {
            let ids = app.selection.clone();
            app.run(if cmd == FlipFacing { "Flip Facing" } else { "Flip Hand" }, |p| {
                for id in &ids {
                    if let Some(i) = p.element_mut(*id).and_then(Element::as_instance_mut) {
                        if cmd == FlipFacing {
                            i.flip_facing = !i.flip_facing;
                        } else {
                            i.flip_hand = !i.flip_hand;
                        }
                    }
                }
                Ok(())
            });
        }
        FlipWall => {
            let ids = app.selection.clone();
            app.run("Flip Wall", |p| {
                for id in &ids {
                    if p.wall(*id).is_some() {
                        edit::flip_wall(p, *id)?;
                    }
                }
                Ok(())
            });
        }
        WallJoinToggle => {
            let ids = app.selection.clone();
            app.run("Allow/Disallow Join", |p| {
                for id in &ids {
                    if let Some(w) = p.element(*id).and_then(Element::as_wall).cloned() {
                        let allow = !(w.join_start && w.join_end);
                        edit::set_wall_join(p, *id, true, allow)?;
                        edit::set_wall_join(p, *id, false, allow)?;
                    }
                }
                Ok(())
            });
        }

        // ---------------- view control
        ZoomFit => {
            if let Some(a) = app.active {
                if app.doc.data.view(a).is_some_and(|v| matches!(v.kind, ViewKind::ThreeD { .. })) {
                    crate::view3d::frame_all(app, a);
                } else if let Some(c) = app.cams.get_mut(&a) {
                    c.fitted = false;
                }
            }
        }
        ZoomRegion => app.set_tool(ToolKind::ZoomRegion),
        ZoomOut => {
            if let Some(c) = app.active.and_then(|a| app.cams.get_mut(&a)) {
                c.zoom /= 2.0;
            }
        }
        ScheduleFields | ScheduleFilter | ScheduleSorting => {
            if let Some(v) = app.active {
                let tab = match cmd {
                    ScheduleFields => 0,
                    ScheduleFilter => 1,
                    _ => 2,
                };
                app.dialogs.schedule_props = Some((v, tab));
            }
        }
        HighlightInModel => {
            let sel = app.selection.clone();
            if let Some(plan) = app.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. }) && !v.is_template).map(|v| v.id) {
                app.open_view(plan);
                app.select(sel);
            }
        }
        PrevPanZoom | NextPanZoom => {
            if let Some(v) = app.active {
                canvas::history_step(app, v, cmd == PrevPanZoom);
            }
        }
        TempHideElement | TempIsolateElement | TempHideCategory | TempIsolateCategory => {
            let Some(v) = app.active else { return };
            let ids: HashSet<Id> = app.selection.iter().copied().collect();
            let cats: HashSet<Category> = ids.iter().filter_map(|id| app.el(*id).map(|e| e.category())).collect();
            let t = app.temp_hide.entry(v).or_default();
            match cmd {
                TempHideElement => t.hidden_elements.extend(ids),
                TempIsolateElement => t.isolate_elements = Some(ids),
                TempHideCategory => t.hidden_categories.extend(cats),
                _ => t.isolate_categories = Some(cats),
            }
            app.select(vec![]);
            app.scenes.remove(&v);
        }
        TempReset => {
            if let Some(v) = app.active {
                app.temp_hide.insert(v, TempHide::default());
                app.scenes.remove(&v);
            }
        }
        RevealHidden => {
            if let Some(v) = app.active {
                if !app.reveal_hidden.remove(&v) {
                    app.reveal_hidden.insert(v);
                }
                app.scenes.remove(&v);
            }
        }
        StyleWireframe | StyleHidden | StyleShaded | StyleConsistent | StyleRealistic => {
            let style = match cmd {
                StyleWireframe => VisualStyle::Wireframe,
                StyleHidden => VisualStyle::HiddenLine,
                StyleShaded => VisualStyle::Shaded,
                StyleConsistent => VisualStyle::ConsistentColors,
                _ => VisualStyle::Realistic,
            };
            set_view(app, "Visual Style", move |v| v.style = style);
        }
        ToggleShadows => set_view(app, "Shadows", |v| v.shadows = !v.shadows),
        ToggleCrop => {
            let bounds = app.active.map(|a| app.drawing(a)).and_then(|d| d.bounds());
            set_view(app, "Crop View", move |v| {
                v.crop_active = !v.crop_active;
                if v.crop.is_none() {
                    v.crop = bounds.map(|(a, b)| (a - DVec2::splat(1000.0), b + DVec2::splat(1000.0)));
                }
            });
        }
        ToggleCropShow => {
            let bounds = app.active.map(|a| app.drawing(a)).and_then(|d| d.bounds());
            set_view(app, "Show Crop Region", move |v| {
                v.crop_visible = !v.crop_visible;
                if v.crop.is_none() {
                    v.crop = bounds.map(|(a, b)| (a - DVec2::splat(1000.0), b + DVec2::splat(1000.0)));
                }
            });
        }
        ToggleSectionBox => {
            let b = app.model_bounds();
            set_view(app, "Section Box", move |v| {
                v.section_box = match v.section_box {
                    Some(_) => None,
                    None => b.map(|(mn, mx)| (mn - rc_core::geom::DVec3::splat(500.0), mx + rc_core::geom::DVec3::splat(500.0))),
                };
            });
        }
        DetailCoarse => set_view(app, "Detail Level", |v| v.detail = DetailLevel::Coarse),
        DetailMedium => set_view(app, "Detail Level", |v| v.detail = DetailLevel::Medium),
        DetailFine => set_view(app, "Detail Level", |v| v.detail = DetailLevel::Fine),

        // ---------------- snaps
        SnapEndpoint => app.snap_override = Some(Override::Only(SnapKind::Endpoint)),
        SnapMidpoint => app.snap_override = Some(Override::Only(SnapKind::Midpoint)),
        SnapNearest => app.snap_override = Some(Override::Only(SnapKind::Nearest)),
        SnapIntersection => app.snap_override = Some(Override::Only(SnapKind::Intersection)),
        SnapCenter => app.snap_override = Some(Override::Only(SnapKind::Center)),
        SnapPerpendicular => app.snap_override = Some(Override::Only(SnapKind::Perpendicular)),
        SnapTangent => app.snap_override = Some(Override::Only(SnapKind::Tangent)),
        SnapQuadrant => app.snap_override = Some(Override::Only(SnapKind::Quadrant)),
        SnapOff => app.snap_override = Some(Override::Off),
        SnapClose => close_sketch_chain(app),
    }
}

fn is_tool_cmd(c: Cmd) -> bool {
    use Cmd::*;
    matches!(
        c,
        Wall | WallStructural | Door | Window | Component | Column | StructColumn | RoofFootprint | RoofExtrusion | Ceiling | Floor | FloorStructural | CurtainGrid
            | Railing | Stair | ModelLine | PlaceGroup | Room | RoomSeparator | RoomTag | Area | AreaBoundary | AreaTag | Shaft | WallOpening | Level | Grid | RefPlane
            | Beam | WallFoundation | IsolatedFoundation | DimAligned | DimLinear | DimAngular | DimRadial | DimDiameter | DimArcLength | SpotElevation | SpotCoordinate | SpotSlope | DetailLine | ScopeBox | Insulation | DetailComponent | MultiCategoryTag | MaterialTag | JoinGeometry | UnjoinGeometry | ShowHiddenLines | RemoveHiddenLines
            | FilledRegion | MaskingRegion | RevisionCloud | Text | TagByCategory | Symbol | Section | Callout | ElevationView | Align | Offset | MirrorPick
            | MirrorDraw | Move | Copy | Rotate | TrimCorner | Split | SplitGap | Array | Scale | TrimSingle | TrimMulti | MatchType | Measure
    )
}

fn set_view(app: &mut App, name: &str, f: impl FnOnce(&mut View)) {
    let Some(v) = app.active else { return };
    app.run(name, |p| {
        f(p.view_mut(v).ok_or("No active view.")?);
        Ok(())
    });
}

/// Starts a curve-drawing tool, keeping the draw mode when it applies.
fn start_drawing(app: &mut App, kind: ToolKind) {
    if !canvas_tools::modes_for(kind).contains(&app.opts.draw_mode) || app.opts.draw_mode == DrawMode::PickWalls {
        app.opts.draw_mode = DrawMode::Line;
    }
    app.set_tool(kind);
}

fn start_sketch(app: &mut App, kind: SketchKind, mode: DrawMode) {
    let view_ok = match kind {
        SketchKind::RoofExtrusion => app.active_view().is_some_and(|v| matches!(v.kind, ViewKind::Section { .. } | ViewKind::Elevation { .. })),
        SketchKind::Region { .. } | SketchKind::RevisionCloud => app.active_view().is_some_and(|v| v.is_graphical() && !matches!(v.kind, ViewKind::ThreeD { .. })),
        _ => app.active_level().is_some(),
    };
    if !view_ok {
        if matches!(kind, SketchKind::RoofExtrusion | SketchKind::Region { .. } | SketchKind::RevisionCloud) {
            app.error("Open a suitable view for this sketch (a section or elevation for extrusion roofs; any 2D view for regions).");
            return;
        }
        let plan = app.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. }) && !v.is_template).map(|v| v.id);
        match plan {
            Some(id) => app.open_view(id),
            None => {
                app.error("Open a plan view first.");
                return;
            }
        }
    }
    let Some(view) = app.active else { return };
    let level = app.active_level().unwrap_or_else(|| app.doc.data.levels().first().map(|l| l.0).unwrap_or(0));
    let mut sk = Sketch::new(kind, view, level);
    sk.width = app.opts.stair_width;
    app.sketch = Some(sk);
    app.opts.draw_mode = mode;
    app.tool = Tool::new(ToolKind::SketchLine);
    app.select(vec![]);
}

fn edit_boundary(app: &mut App) {
    let Some(id) = app.selection.first().copied() else { return };
    let Some(e) = app.el(id).cloned() else { return };
    let view = app.active.unwrap_or(0);
    let (kind, rings, slopes, level): (SketchKind, Vec<Vec<DVec2>>, Vec<bool>, Id) = match &e.kind {
        ElementKind::Floor(f) => (SketchKind::EditFloor(id), std::iter::once(f.boundary.clone()).chain(f.holes.iter().cloned()).collect(), vec![], f.level),
        ElementKind::Ceiling(c) => (SketchKind::EditCeiling(id), std::iter::once(c.boundary.clone()).chain(c.holes.iter().cloned()).collect(), vec![], c.level),
        ElementKind::Roof(r) => (SketchKind::EditRoof(id), vec![r.footprint.clone()], rc_core::analysis::roof_edge_slopes(r), r.level),
        ElementKind::Region(r) => (SketchKind::EditRegion(id), std::iter::once(r.boundary.clone()).chain(r.holes.iter().cloned()).collect(), vec![], view),
        _ => return,
    };
    let mut sk = Sketch::new(kind, view, level);
    for ring in &rings {
        let n = ring.len();
        for k in 0..n {
            let flag = if rings.len() == 1 { slopes.get(k).copied().unwrap_or(true) } else { true };
            sk.push(Seg::Line(ring[k], ring[(k + 1) % n]), flag);
        }
    }
    app.sketch = Some(sk);
    app.opts.draw_mode = DrawMode::Line;
    app.tool = Tool::select();
    app.select(vec![]);
}

/// Closes the current chain of sketch lines back to its first point (SZ).
fn close_sketch_chain(app: &mut App) {
    let Some(sk) = app.sketch.as_mut() else { return };
    let Some(last) = sk.segs.last().copied() else { return };
    let mut start = last.start();
    for s in sk.segs.iter().rev().skip(1) {
        if s.end().distance(start) < 1.0 {
            start = s.start();
        } else {
            break;
        }
    }
    if start.distance(last.end()) > 1.0 {
        let flag = app.opts.defines_slope;
        sk.push(Seg::Line(last.end(), start), flag);
    }
    app.tool.reset();
}

/// Finish Edit Mode (green check): validates the sketch and creates or updates the element.
pub fn finish_sketch(app: &mut App) {
    let Some(sk) = app.sketch.clone() else { return };
    let o = app.opts.clone();
    let level = sk.level;
    let vid = sk.view;
    let result: Result<Option<Id>, String> = (|| {
        match sk.kind {
            SketchKind::Railing => {
                let path = sk.chain()?;
                Ok(app.run("Create Railing", |p| edit::add_railing(p, level, o.railing_type, path)))
            }
            SketchKind::Stair => {
                let runs: Vec<StairRun> = sk
                    .segs
                    .iter()
                    .filter_map(|s| match s {
                        Seg::Line(a, b) => Some(StairRun { start: *a, end: *b, width: o.stair_width }),
                        _ => None,
                    })
                    .collect();
                if runs.is_empty() {
                    return Err("Sketch at least one straight run (click its start and end).".into());
                }
                let rt = Some(o.railing_type).filter(|t| app.doc.data.sys_type(*t).is_some());
                Ok(app.run("Create Stair", |p| edit::add_stair(p, level, o.stair_type, runs, rt)))
            }
            SketchKind::RoofExtrusion => {
                let prof = sk.chain()?;
                let Some(frame) = app.frame_of(vid) else { return Err("This view cannot host an extrusion roof.".into()) };
                let bounds = app.model_bounds();
                let look = frame.look.truncate().normalize_or_zero();
                let o2 = frame.origin.truncate();
                let (d0, d1) = match bounds {
                    Some((mn, mx)) => {
                        let cs = [DVec2::new(mn.x, mn.y), DVec2::new(mx.x, mn.y), DVec2::new(mx.x, mx.y), DVec2::new(mn.x, mx.y)];
                        let ds: Vec<f64> = cs.iter().map(|c| (*c - o2).dot(look)).collect();
                        (ds.iter().cloned().fold(f64::MAX, f64::min), ds.iter().cloned().fold(f64::MIN, f64::max))
                    }
                    None => (0.0, 10000.0),
                };
                let zmin = prof.iter().map(|q| q.y).fold(f64::MAX, f64::min);
                let lv = app.doc.data.levels().iter().rev().find(|(_, l)| l.elevation <= zmin + 1.0).map(|(id, _)| *id).or_else(|| app.doc.data.levels().first().map(|l| l.0));
                let Some(lv) = lv else { return Err("The project has no levels.".into()) };
                let base = app.doc.data.level_elevation(lv);
                let profile: Vec<DVec2> = prof.iter().map(|q| DVec2::new(q.x, q.y - base)).collect();
                let (start, end) = (o2 + look * d0, o2 + look * d1);
                Ok(app.run("Create Extrusion Roof", |p| edit::add_extrusion_roof(p, lv, o.roof_type, start, end, profile)))
            }
            _ => {
                let loops = sk.loops()?;
                let outer = loops[0].0.clone();
                let holes: Vec<Vec<DVec2>> = loops[1..].iter().map(|l| l.0.clone()).collect();
                for h in &holes {
                    if !h.iter().all(|q| geom::contains(&outer, *q)) {
                        return Err("Every inner loop must be inside the outer boundary.".into());
                    }
                }
                let flags = loops[0].1.clone();
                let imperial = app.doc.data.units.system == rc_core::units::UnitSystem::Imperial;
                Ok(match sk.kind {
                    SketchKind::Floor { structural } => app.run("Create Floor", |p| {
                        let id = edit::add_floor(p, level, o.floor_type, outer)?;
                        if let Some(ElementKind::Floor(f)) = p.element_mut(id).map(|e| &mut e.kind) {
                            f.holes = holes;
                            f.structural = structural;
                        }
                        Ok(id)
                    }),
                    SketchKind::Ceiling => app.run("Create Ceiling", |p| {
                        let h = if imperial { 2438.4 } else { 2600.0 };
                        let id = edit::add_ceiling(p, level, o.ceiling_type, outer, h)?;
                        if let Some(ElementKind::Ceiling(c)) = p.element_mut(id).map(|e| &mut e.kind) {
                            c.holes = holes;
                        }
                        Ok(id)
                    }),
                    SketchKind::Roof => {
                        let poly = outer.clone();
                        app.run("Create Roof", |p| {
                            let id = edit::add_roof(p, level, o.roof_type, outer, RoofShape::Hip, 0.0)?;
                            if let Some(ElementKind::Roof(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                                r.overhang = 0.0;
                                r.slope_deg = o.roof_slope;
                                r.edge_slopes = match_edge_flags(&r.footprint, &poly, &flags);
                                r.shape = shape_from_flags(&r.edge_slopes);
                            }
                            Ok(id)
                        })
                    }
                    SketchKind::Shaft => app.run("Create Shaft", |p| edit::add_shaft(p, level, outer)),
                    SketchKind::Mass => app.run("Create Mass", |p| edit::add_mass(p, level, outer, o.mass_height)),
                    SketchKind::Toposolid => app.run("Create Toposolid", |p| edit::add_toposolid(p, level, outer, o.topo_height, o.topo_thickness)),
                    SketchKind::PropertyLine => app.run("Create Property Line", |p| edit::add_property_line(p, level, outer)),
                    SketchKind::Region { masking } => app.run(if masking { "Masking Region" } else { "Filled Region" }, |p| {
                        let id = edit::add_region(p, vid, outer, if masking { FillPattern::Masking } else { o.fill_pattern })?;
                        if let Some(ElementKind::Region(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                            r.holes = holes;
                            if masking {
                                r.color = [255, 255, 255];
                            } else {
                                r.color = o.fill_color;
                            }
                        }
                        Ok(id)
                    }),
                    SketchKind::RevisionCloud => {
                        let rev = app.doc.data.revisions.last().map(|r| r.id.to_string()).unwrap_or_default();
                        app.run("Revision Cloud", |p| {
                            let c = geom::centroid(&outer);
                            let id = edit::add_symbol(p, vid, SymbolKind::Revision, c);
                            if let Some(ElementKind::Symbol(s)) = p.element_mut(id).map(|e| &mut e.kind) {
                                s.points = outer;
                                s.value = rev;
                            }
                            Ok(id)
                        })
                    }
                    SketchKind::EditFloor(id) => app.run("Edit Boundary", |p| {
                        if let Some(ElementKind::Floor(f)) = p.element_mut(id).map(|e| &mut e.kind) {
                            f.boundary = geom::ensure_ccw(&outer);
                            f.holes = holes;
                        }
                        Ok(id)
                    }),
                    SketchKind::EditCeiling(id) => app.run("Edit Boundary", |p| {
                        if let Some(ElementKind::Ceiling(c)) = p.element_mut(id).map(|e| &mut e.kind) {
                            c.boundary = geom::ensure_ccw(&outer);
                            c.holes = holes;
                        }
                        Ok(id)
                    }),
                    SketchKind::EditRoof(id) => {
                        let poly = outer.clone();
                        app.run("Edit Footprint", |p| {
                            if let Some(ElementKind::Roof(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                                r.footprint = geom::clean(&outer, 1.0);
                                r.edge_slopes = match_edge_flags(&r.footprint, &poly, &flags);
                                r.shape = shape_from_flags(&r.edge_slopes);
                            }
                            Ok(id)
                        })
                    }
                    SketchKind::EditRegion(id) => app.run("Edit Boundary", |p| {
                        if let Some(ElementKind::Region(r)) = p.element_mut(id).map(|e| &mut e.kind) {
                            r.boundary = outer;
                            r.holes = holes;
                        }
                        Ok(id)
                    }),
                    _ => None,
                })
            }
        }
    })();
    match result {
        Ok(Some(id)) => {
            app.sketch = None;
            app.tool = Tool::select();
            app.select(vec![id]);
        }
        Ok(None) => {}
        Err(e) => {
            app.error(e);
        }
    }
}

/// Slope flags for a roof footprint's edges, matched to the sketched polygon's edges.
fn match_edge_flags(footprint: &[DVec2], sketch: &[DVec2], flags: &[bool]) -> Vec<bool> {
    let n = footprint.len();
    let m = sketch.len();
    (0..n)
        .map(|k| {
            let (a, b) = (footprint[k], footprint[(k + 1) % n]);
            let mid = (a + b) / 2.0;
            (0..m)
                .map(|j| (geom::distance_to_segment(sketch[j], sketch[(j + 1) % m], mid), j))
                .min_by(|x, y| x.0.total_cmp(&y.0))
                .map(|(_, j)| flags.get(j).copied().unwrap_or(true))
                .unwrap_or(true)
        })
        .collect()
}

fn shape_from_flags(f: &[bool]) -> RoofShape {
    if f.iter().all(|x| *x) {
        RoofShape::Hip
    } else if f.iter().any(|x| *x) {
        RoofShape::Gable
    } else {
        RoofShape::Flat
    }
}

fn tile_views(app: &mut App) {
    let tabs = app.open_tabs();
    if tabs.is_empty() {
        return;
    }
    let mut dock = egui_dock::DockState::new(vec![tabs[0]]);
    let n = tabs.len();
    let cols = (n as f64).sqrt().ceil() as usize;
    let rows = n.div_ceil(cols);
    // Build columns by splitting right, then split each column down.
    let mut col_nodes = vec![egui_dock::NodeIndex::root()];
    for c in 1..cols {
        let idx = c * rows;
        if idx >= n {
            break;
        }
        let last = *col_nodes.last().unwrap();
        let frac = 1.0 - 1.0 / (cols - c + 1) as f32;
        let [_, new] = dock.main_surface_mut().split_right(last, frac, vec![tabs[idx]]);
        col_nodes.push(new);
    }
    for (c, node) in col_nodes.iter().enumerate() {
        let mut cur = *node;
        for r in 1..rows {
            let idx = c * rows + r;
            if idx >= n {
                break;
            }
            let frac = 1.0 - 1.0 / (rows - r + 1) as f32;
            let [_, new] = dock.main_surface_mut().split_below(cur, frac, vec![tabs[idx]]);
            cur = new;
        }
    }
    app.dock = Some(dock);
    for t in &tabs {
        app.cams.entry(*t).and_modify(|c| c.fitted = false);
    }
}

pub fn delete_selection(app: &mut App) {
    if let Some(sk) = app.sketch.as_mut() {
        let mut sel = sk.selected.clone();
        sel.sort_unstable_by(|a, b| b.cmp(a));
        for k in sel {
            if k < sk.segs.len() {
                sk.segs.remove(k);
                sk.slopes.remove(k);
            }
        }
        sk.selected.clear();
        return;
    }
    let ids = app.selection.clone();
    if ids.is_empty() {
        return;
    }
    // On a sheet, Delete removes the selected viewports (the views stay in the project).
    if let Some(sheet) = app.active.filter(|a| matches!(app.doc.data.view(*a).map(|v| &v.kind), Some(ViewKind::Sheet(_)))) {
        let on_sheet: Vec<Id> = match app.doc.data.view(sheet).map(|v| &v.kind) {
            Some(ViewKind::Sheet(s)) => ids.iter().copied().filter(|id| s.viewports.iter().any(|vp| vp.view == *id)).collect(),
            _ => vec![],
        };
        if !on_sheet.is_empty() {
            app.run("Remove Viewport", |p| {
                if let Some(ViewKind::Sheet(s)) = p.view_mut(sheet).map(|v| &mut v.kind) {
                    s.viewports.retain(|vp| !on_sheet.contains(&vp.view));
                }
                Ok(())
            });
            app.select(vec![]);
            return;
        }
    }
    // Views (section/elevation markers) delete their view.
    let views: Vec<Id> = ids.iter().copied().filter(|id| app.doc.data.view(*id).is_some() && Some(*id) != app.active).collect();
    let elems: Vec<Id> = ids.iter().copied().filter(|id| app.el(*id).is_some()).collect();
    let pinned = elems.iter().filter(|id| app.el(**id).is_some_and(|e| e.pinned)).count();
    if pinned > 0 {
        app.error("Pinned elements cannot be deleted. Unpin them first (UP).");
        return;
    }
    let r = app.run("Delete", |p| {
        let mut n = 0;
        if !elems.is_empty() {
            n += edit::delete_elements(p, &elems)?;
        }
        for v in &views {
            edit::delete_view(p, *v)?;
            n += 1;
        }
        Ok(n)
    });
    if let Some(n) = r {
        app.select(vec![]);
        app.info(format!("Deleted {n} element{}.", if n == 1 { "" } else { "s" }));
    }
}

pub fn select_all_in_view(app: &mut App) {
    let Some(v) = app.active_view().cloned() else { return };
    let d = app.drawing(v.id);
    let mut ids: Vec<Id> = Vec::new();
    for (id, _) in &d.prims {
        if let Some(id) = id {
            if let Some(s) = canvas::selectable_id(app, &v, *id) {
                if !ids.contains(&s) && s != v.id {
                    ids.push(s);
                }
            }
        }
    }
    app.select(ids);
}

/// Adds walls joined at the ends of the selected walls (L, T and straight joins).
fn select_joined(app: &mut App) {
    let p = &app.doc.data;
    let mut out: Vec<Id> = app.selection.clone();
    let touches = |a: &Wall, b: &Wall| {
        let on = |q: DVec2, w: &Wall| geom::distance_to_segment(w.start, w.end, q) < 1.0;
        on(a.start, b) || on(a.end, b) || on(b.start, a) || on(b.end, a)
    };
    for id in &app.selection {
        let Some(w) = p.wall(*id) else { continue };
        for (e, other) in p.walls() {
            if e.id != *id && !out.contains(&e.id) && touches(w, other) {
                out.push(e.id);
            }
        }
    }
    app.select(out);
}

fn select_all_instances(app: &mut App, visible_only: bool) {
    let types: HashSet<Id> = app.selection.iter().filter_map(|id| app.el(*id)).filter_map(|e| app.doc.data.type_of(e)).collect();
    if types.is_empty() {
        app.error("The selection has no types.");
        return;
    }
    let visible: Option<HashSet<Id>> = if visible_only {
        app.active.map(|a| app.drawing(a).prims.iter().filter_map(|(id, _)| *id).collect())
    } else {
        None
    };
    let ids: Vec<Id> = app
        .doc
        .data
        .elements
        .iter()
        .filter(|e| app.doc.data.type_of(e).is_some_and(|t| types.contains(&t)))
        .filter(|e| visible.as_ref().is_none_or(|v| v.contains(&e.id)))
        .map(|e| e.id)
        .collect();
    app.info(format!("Selected {} instance(s).", ids.len()));
    app.select(ids);
}

fn type_for_properties(app: &App) -> Option<Id> {
    if let Some(e) = app.selection.first().and_then(|id| app.el(*id)) {
        return app.doc.data.type_of(e);
    }
    let o = &app.opts;
    Some(match app.tool.kind {
        ToolKind::Wall => o.wall_type,
        ToolKind::Door => o.door_type,
        ToolKind::Window => o.window_type,
        ToolKind::Component => o.component_type,
        ToolKind::Column => o.column_type,
        ToolKind::StructColumn => o.struct_column_type,
        ToolKind::Beam => o.beam_type,
        ToolKind::IsolatedFooting => o.footing_type,
        ToolKind::WallFoundation => o.foundation_type,
        ToolKind::SketchLine => match app.sketch.as_ref().map(|s| s.kind) {
            Some(SketchKind::Floor { .. }) => o.floor_type,
            Some(SketchKind::Ceiling) => o.ceiling_type,
            Some(SketchKind::Roof) | Some(SketchKind::RoofExtrusion) => o.roof_type,
            Some(SketchKind::Stair) => o.stair_type,
            Some(SketchKind::Railing) => o.railing_type,
            _ => return None,
        },
        _ => return None,
    })
}

fn create_similar(app: &mut App) {
    let Some(e) = app.selection.first().and_then(|id| app.el(*id)).cloned() else { return };
    let t = app.doc.data.type_of(&e);
    match &e.kind {
        ElementKind::Wall(_) => {
            if let Some(t) = t {
                app.opts.wall_type = t;
            }
            exec(app, Cmd::Wall);
        }
        ElementKind::Instance(i) => {
            let cat = i.category;
            match cat {
                Category::Doors => {
                    app.opts.door_type = i.type_id;
                    exec(app, Cmd::Door);
                }
                Category::Windows => {
                    app.opts.window_type = i.type_id;
                    exec(app, Cmd::Window);
                }
                Category::Columns => {
                    app.opts.column_type = i.type_id;
                    exec(app, Cmd::Column);
                }
                Category::StructuralColumns => {
                    app.opts.struct_column_type = i.type_id;
                    exec(app, Cmd::StructColumn);
                }
                Category::StructuralFraming => {
                    app.opts.beam_type = i.type_id;
                    exec(app, Cmd::Beam);
                }
                Category::StructuralFoundations => {
                    app.opts.footing_type = i.type_id;
                    exec(app, Cmd::IsolatedFoundation);
                }
                _ => {
                    app.opts.component_type = i.type_id;
                    exec(app, Cmd::Component);
                }
            }
        }
        ElementKind::Floor(f) => {
            app.opts.floor_type = f.type_id;
            exec(app, Cmd::Floor);
        }
        ElementKind::Ceiling(c) => {
            app.opts.ceiling_type = c.type_id;
            exec(app, Cmd::Ceiling);
        }
        ElementKind::Roof(r) => {
            app.opts.roof_type = r.type_id;
            exec(app, Cmd::RoofFootprint);
        }
        ElementKind::Stair(s) => {
            app.opts.stair_type = s.type_id;
            exec(app, Cmd::Stair);
        }
        ElementKind::Railing(r) => {
            app.opts.railing_type = r.type_id;
            exec(app, Cmd::Railing);
        }
        ElementKind::Grid(_) => exec(app, Cmd::Grid),
        ElementKind::Level(_) => exec(app, Cmd::Level),
        ElementKind::RefPlane(_) => exec(app, Cmd::RefPlane),
        ElementKind::Room(_) => exec(app, Cmd::Room),
        ElementKind::Line(l) => {
            app.opts.line_style = l.style;
            exec(app, if e.view.is_some() { Cmd::DetailLine } else { Cmd::ModelLine });
        }
        ElementKind::Text(t) => {
            app.opts.text_size = t.size;
            exec(app, Cmd::Text);
        }
        ElementKind::Dimension(_) => exec(app, Cmd::DimAligned),
        ElementKind::Tag(_) => exec(app, Cmd::TagByCategory),
        ElementKind::GroupInstance(g) => {
            app.opts.group_type = g.type_id;
            exec(app, Cmd::PlaceGroup);
        }
        _ => app.error("Create Similar is not available for this element."),
    }
}

fn next_group_name(app: &App) -> String {
    edit::unique_name(app.doc.data.group_types.iter().map(|g| g.name.clone()), "Group 1")
}

// ---------------------------------------------------------------- clipboard

fn copy_to_clipboard(app: &mut App) {
    let p = &app.doc.data;
    let mut ids: HashSet<Id> = app.selection.iter().copied().collect();
    // Hosted elements travel with their hosts; group members with their groups.
    for e in &p.elements {
        if let ElementKind::Instance(i) = &e.kind {
            if i.host.is_some_and(|h| ids.contains(&h)) {
                ids.insert(e.id);
            }
        }
        if e.group.is_some_and(|g| ids.contains(&g)) {
            ids.insert(e.id);
        }
    }
    let elements: Vec<Element> = p.elements.iter().filter(|e| ids.contains(&e.id)).cloned().collect();
    if elements.is_empty() {
        return;
    }
    let fp = app.footprints();
    let pts: Vec<DVec2> = elements.iter().flat_map(|e| rc_core::plan::element_outline(p, e, &fp).into_iter().flatten()).collect();
    let base = if pts.is_empty() { DVec2::ZERO } else { geom::bounds(pts).0 };
    app.clipboard = Some(Clipboard { elements, base, level: app.active_level() });
}

/// Pastes the clipboard moved by `delta`, onto `level` when given.
pub fn paste_at(app: &mut App, delta: DVec2, level: Option<Id>) {
    let Some(cb) = app.clipboard.clone() else { return };
    let target_view = app.active;
    let created = app.run("Paste", |p| {
        let mut map = std::collections::HashMap::new();
        for e in &cb.elements {
            let id = p.new_id();
            map.insert(e.id, id);
        }
        let mut out = Vec::new();
        let level_shift = |l: Id, p: &Project| -> Id {
            match (cb.level, level) {
                (Some(src), Some(dst)) if l == src => dst,
                _ => {
                    let _ = p;
                    l
                }
            }
        };
        for e in &cb.elements {
            let mut c = e.clone();
            c.id = map[&e.id];
            c.uid = uuid_like(c.id);
            c.pinned = false;
            c.group = e.group.and_then(|g| map.get(&g).copied());
            if c.view.is_some() {
                c.view = target_view;
            }
            match &mut c.kind {
                ElementKind::Instance(i) => {
                    i.level = level_shift(i.level, p);
                    if let Some(h) = i.host {
                        i.host = map.get(&h).copied().or(Some(h));
                    }
                }
                ElementKind::Wall(w) => {
                    w.base_level = level_shift(w.base_level, p);
                    if let (Some(t), Some(src), Some(dst)) = (w.top_level, cb.level, level) {
                        if src != dst {
                            let rel = p.level_elevation(t) - p.level_elevation(src);
                            w.top_level = p.levels().into_iter().find(|(_, l)| (l.elevation - (p.level_elevation(dst) + rel)).abs() < 1.0).map(|l| l.0);
                            if w.top_level.is_none() {
                                w.unconnected_height = rc_core::analysis::wall_height(p, w);
                            }
                        }
                    }
                }
                ElementKind::Floor(f) => f.level = level_shift(f.level, p),
                ElementKind::Roof(r) => r.level = level_shift(r.level, p),
                ElementKind::Ceiling(cc) => cc.level = level_shift(cc.level, p),
                ElementKind::Room(r) => {
                    r.level = level_shift(r.level, p);
                    r.number = edit::next_room_number(p);
                }
                ElementKind::Tag(t) => {
                    if let Some(h) = map.get(&t.host) {
                        t.host = *h;
                    }
                }
                ElementKind::WallFoundation(f) => {
                    if let Some(h) = map.get(&f.wall) {
                        f.wall = *h;
                    }
                }
                _ => {}
            }
            p.elements.push(c);
            out.push(map[&e.id]);
        }
        // Move the free copies (hosted ones follow their hosts).
        let movable: Vec<Id> = out.iter().copied().filter(|id| !p.element(*id).is_some_and(|e| matches!(&e.kind, ElementKind::Instance(i) if i.host.is_some()))).collect();
        edit::move_elements(p, &movable, delta);
        Ok(out)
    });
    if let Some(ids) = created {
        let top: Vec<Id> = ids.iter().copied().filter(|id| app.doc.data.element(*id).is_some_and(|e| e.group.is_none())).collect();
        app.select(top);
    }
}

fn uuid_like(id: Id) -> String {
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let a = (t as u64) ^ ((id as u64) << 32) ^ 0x9E37_79B9_7F4A_7C15;
    let b = a.rotate_left(17).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    format!("{:08x}-{:04x}-4{:03x}-a{:03x}-{:012x}", (a >> 32) as u32, (a >> 16) as u16, (b >> 52) & 0xfff, (b >> 40) & 0xfff, b & 0xffff_ffff_ffff)
}

// ---------------------------------------------------------------- files

pub fn load_family_path(app: &mut App, path: &std::path::Path) {
    match io::load_family(path) {
        Ok(ff) => {
            let name = ff.family.name.clone();
            let mats = ff.materials.clone();
            let fam = ff.family;
            if let Some(id) = app.run("Load Family", |p| {
                for m in mats {
                    if p.material(&m.name).is_none() {
                        p.materials.push(m);
                    }
                }
                Ok(edit::load_family(p, fam))
            }) {
                app.info(format!("Loaded family '{name}'."));
                if let Some(t) = app.doc.data.family(id).and_then(|f| f.types.first()).map(|t| t.id) {
                    app.opts.component_type = t;
                }
            }
        }
        Err(e) => app.error(e),
    }
}

pub fn link_cad_path(app: &mut App, path: &std::path::Path) {
    let text = match std::fs::read(path) {
        Ok(b) => String::from_utf8_lossy(&b).to_string(),
        Err(e) => {
            app.error(format!("Could not read {}: {e}", path.display()));
            return;
        }
    };
    let name = path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "Drawing.dxf".into());
    match rc_core::dxf::import(&text, &name) {
        Ok(mut cad) => {
            let Some(view) = app.active else {
                app.error("Open the view to link the drawing into.");
                return;
            };
            cad.level = app.active_level();
            let n = cad.polylines.len();
            let plan = app.active_level().is_some();
            if let Some(id) = app.run("Link CAD", |p| {
                let id = p.new_id();
                let mut e = Element::new(id, ElementKind::Cad(cad));
                if !plan {
                    e.view = Some(view);
                } else {
                    e.view = Some(view);
                }
                p.elements.push(e);
                Ok(id)
            }) {
                app.select(vec![id]);
                app.info(format!("Linked {name}: {n} curves."));
                if let Some(c) = app.cams.get_mut(&view) {
                    c.fitted = false;
                }
            }
        }
        Err(e) => app.error(format!("DXF import failed: {e}")),
    }
}

fn export_ifc(app: &mut App) {
    let Some(path) = rfd::FileDialog::new().add_filter("IFC", &["ifc"]).set_file_name("Project1.ifc").save_file() else { return };
    let name = path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
    let text = rc_core::ifc::export(&app.doc.data, &name, &crate::app::timestamp());
    match std::fs::write(&path, text) {
        Ok(()) => app.info(format!("Exported {}", path.display())),
        Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
    }
}

fn export_csv(app: &mut App) {
    let Some(v) = app.active_view().cloned() else { return };
    let Some(path) = rfd::FileDialog::new().add_filter("CSV", &["csv"]).set_file_name(format!("{}.csv", v.name)).save_file() else { return };
    let Some(table) = app.table(v.id) else { return };
    match std::fs::write(&path, rc_core::schedule::to_csv(&v.name, &table)) {
        Ok(()) => app.info(format!("Exported {}", path.display())),
        Err(e) => app.error(format!("Could not write {}: {e}", path.display())),
    }
}
