//! Properties palette: Type Selector, instance parameters of the selection, or the active
//! view's properties when nothing is selected.

use crate::app::App;
use crate::icons::{self, Icon};
use crate::style;
use crate::tools::{SketchKind, ToolKind};
use eframe::egui::{self, Rect, Sense, pos2, vec2};
use rc_core::model::*;
use rc_core::params::{self, PKind, ParamDef};
use std::collections::BTreeMap;

/// Types that can be chosen for a category: (id, family name, type name).
pub fn types_for(p: &Project, cat: Category) -> Vec<(Id, String, String)> {
    let mut v: Vec<(Id, String, String)> = p.types_of(cat).map(|t| (t.id, t.family_name().to_string(), t.name.clone())).collect();
    for f in p.families.iter().filter(|f| f.category == cat) {
        for t in &f.types {
            v.push((t.id, f.name.clone(), t.name.clone()));
        }
    }
    v
}

/// The category and current type the Type Selector shows.
fn selector_target(app: &App) -> Option<(Category, Option<Id>)> {
    if !app.selection.is_empty() {
        let p = &app.doc.data;
        let es: Vec<&Element> = app.selection.iter().filter_map(|id| app.el(*id)).collect();
        let cat = es.first()?.category();
        if !es.iter().all(|e| e.category() == cat) {
            return None;
        }
        let t0 = p.type_of(es[0]);
        let same = es.iter().all(|e| p.type_of(e) == t0);
        return t0.map(|_| (cat, if same { t0 } else { None }));
    }
    let o = &app.opts;
    let (cat, t) = match app.tool.kind {
        ToolKind::Wall => (Category::Walls, o.wall_type),
        ToolKind::Door => (Category::Doors, o.door_type),
        ToolKind::Window => (Category::Windows, o.window_type),
        ToolKind::Column => (Category::Columns, o.column_type),
        ToolKind::StructColumn => (Category::StructuralColumns, o.struct_column_type),
        ToolKind::Beam => (Category::StructuralFraming, o.beam_type),
        ToolKind::CeilingAuto => (Category::Ceilings, o.ceiling_type),
        ToolKind::IsolatedFooting => (Category::StructuralFoundations, o.footing_type),
        ToolKind::WallFoundation => (Category::StructuralFoundations, o.foundation_type),
        ToolKind::Component => (app.doc.data.family_type(o.component_type).map(|(f, _)| f.category)?, o.component_type),
        ToolKind::SketchLine | ToolKind::Select if app.sketch.is_some() => match app.sketch.as_ref()?.kind {
            SketchKind::Floor { .. } | SketchKind::EditFloor(_) => (Category::Floors, o.floor_type),
            SketchKind::Ceiling | SketchKind::EditCeiling(_) => (Category::Ceilings, o.ceiling_type),
            SketchKind::Roof | SketchKind::RoofExtrusion | SketchKind::EditRoof(_) => (Category::Roofs, o.roof_type),
            SketchKind::Stair => (Category::Stairs, o.stair_type),
            SketchKind::Ramp => (Category::Ramps, o.ramp_type),
            SketchKind::Railing => (Category::Railings, o.railing_type),
            _ => return None,
        },
        _ => return None,
    };
    Some((cat, Some(t)))
}

fn set_tool_type(app: &mut App, cat: Category, t: Id) {
    let o = &mut app.opts;
    match cat {
        Category::Walls => o.wall_type = t,
        Category::Doors => o.door_type = t,
        Category::Windows => o.window_type = t,
        Category::Columns => o.column_type = t,
        Category::StructuralColumns => o.struct_column_type = t,
        Category::StructuralFraming => o.beam_type = t,
        Category::StructuralFoundations => {
            if app.doc.data.sys_type(t).is_some() {
                o.foundation_type = t
            } else {
                o.footing_type = t
            }
        }
        Category::Floors => o.floor_type = t,
        Category::Ceilings => o.ceiling_type = t,
        Category::Roofs => o.roof_type = t,
        Category::Stairs => o.stair_type = t,
        Category::Ramps => o.ramp_type = t,
        Category::Railings => o.railing_type = t,
        _ => o.component_type = t,
    }
}

fn type_selector(app: &mut App, ui: &mut egui::Ui) {
    if app.tool.kind == ToolKind::RoomTag || (app.tool.kind == ToolKind::Room && app.opts.room_tag) {
        // The Room tool shows the tag it places, as in the reference app.
        selector_box(ui, Icon::RoomTag, "Room Tag", "", true);
        return;
    }
    let Some((cat, current)) = selector_target(app) else {
        // No type: a plain header naming what is shown.
        let label = if app.selection.is_empty() {
            app.active_view().map(|v| v.type_label().to_string()).unwrap_or_else(|| "Project".into())
        } else if app.selection.iter().any(|id| app.doc.data.view(*id).is_some()) {
            "Views".to_string()
        } else {
            let mut c: Vec<Category> = app.selection.iter().filter_map(|id| app.el(*id).map(|e| e.category())).collect();
            c.sort();
            c.dedup();
            if c.len() == 1 { c[0].label().to_string() } else { "Multiple Categories Selected".into() }
        };
        let icon = if app.selection.is_empty() {
            match app.active_view().map(|v| &v.kind) {
                Some(ViewKind::ThreeD { .. }) => Icon::View3D,
                Some(ViewKind::Elevation { .. }) => Icon::Elevation,
                Some(ViewKind::Section { .. }) => Icon::Section,
                Some(ViewKind::CeilingPlan { .. }) => Icon::CeilingPlan,
                Some(ViewKind::Sheet(_)) => Icon::Sheet,
                Some(ViewKind::Schedule(_)) => Icon::Schedule,
                _ => Icon::FloorPlan,
            }
        } else {
            Icon::Properties
        };
        selector_box(ui, icon, &label, "", false);
        return;
    };
    let p = &app.doc.data;
    let list = types_for(p, cat);
    let (fam, ty) = match current.and_then(|t| list.iter().find(|x| x.0 == t)) {
        Some(x) => (x.1.clone(), x.2.clone()),
        None => (cat.singular().to_string(), "<varies>".to_string()),
    };
    let icon = match cat {
        Category::Walls => Icon::Wall,
        Category::Doors => Icon::Door,
        Category::Windows => Icon::Window,
        Category::Floors => Icon::Floor,
        Category::Roofs => Icon::RoofFootprint,
        Category::Ceilings => Icon::Ceiling,
        Category::Stairs => Icon::Stair,
        Category::Ramps => Icon::Ramp,
        Category::Railings => Icon::Railing,
        Category::Columns => Icon::Column,
        Category::StructuralColumns => Icon::StructColumn,
        Category::StructuralFraming => Icon::Beam,
        Category::StructuralFoundations => Icon::IsolatedFoundation,
        Category::Groups => Icon::PlaceGroup,
        _ => Icon::Component,
    };
    let resp = selector_box(ui, icon, &fam, &ty, true);
    let rect = resp.rect;
    let search_id = egui::Id::new("type-selector-search");
    let mut chosen: Option<Id> = None;
    egui::Popup::menu(&resp).close_behavior(egui::PopupCloseBehavior::CloseOnClickOutside).show(|ui| {
        ui.set_min_width(rect.width() - 10.0);
        let mut search: String = ui.memory(|m| m.data.get_temp(search_id)).unwrap_or_default();
        ui.add(egui::TextEdit::singleline(&mut search).hint_text("Search").desired_width(f32::INFINITY));
        ui.memory_mut(|m| m.data.insert_temp(search_id, search.clone()));
        egui::ScrollArea::vertical().max_height(360.0).show(ui, |ui| {
            let mut by_family: BTreeMap<String, Vec<(Id, String)>> = BTreeMap::new();
            for (id, f, t) in &list {
                if search.is_empty() || t.to_lowercase().contains(&search.to_lowercase()) || f.to_lowercase().contains(&search.to_lowercase()) {
                    by_family.entry(f.clone()).or_default().push((*id, t.clone()));
                }
            }
            for (f, ts) in by_family {
                ui.label(egui::RichText::new(f).strong().color(style::text_dim()));
                for (id, t) in ts {
                    if ui.selectable_label(Some(id) == current, format!("    {t}")).clicked() {
                        chosen = Some(id);
                        ui.close();
                    }
                }
            }
        });
    });
    if let Some(t) = chosen {
        if app.selection.is_empty() {
            set_tool_type(app, cat, t);
        } else {
            let ids = app.selection.clone();
            app.run("Change Type", |p| rc_core::edit::change_type(p, &ids, t));
        }
    }
}

/// The Type Selector box: a thumbnail on the left, family and type on two lines and the
/// drop-down arrow on the right.
fn selector_box(ui: &mut egui::Ui, icon: Icon, line1: &str, line2: &str, dropdown: bool) -> egui::Response {
    let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 58.0), if dropdown { Sense::click() } else { Sense::hover() });
    let painter = ui.painter();
    if dropdown && resp.hovered() {
        painter.rect_filled(rect.shrink(1.0), 0.0, style::hover());
    }
    let thumb = Rect::from_min_size(rect.min + vec2(3.0, 3.0), vec2(54.0, 52.0));
    painter.rect_filled(thumb, 0.0, style::field());
    painter.rect_stroke(thumb, 0.0, egui::Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    icons::paint(painter, Rect::from_center_size(thumb.center(), vec2(32.0, 32.0)), icon, true);
    let tx = thumb.right() + 6.0;
    if line2.is_empty() {
        painter.text(pos2(tx, rect.center().y), egui::Align2::LEFT_CENTER, line1, style::font(12.0), style::text());
    } else {
        painter.text(pos2(tx, rect.center().y - 1.0), egui::Align2::LEFT_BOTTOM, line1, style::font(12.0), style::text());
        painter.text(pos2(tx, rect.center().y + 1.0), egui::Align2::LEFT_TOP, line2, style::font(12.0), style::text());
    }
    if dropdown {
        let c = rect.right_center() - vec2(10.0, 0.0);
        painter.add(egui::Shape::convex_polygon(vec![c + vec2(-3.5, -1.5), c + vec2(3.5, -1.5), c + vec2(0.0, 2.0)], style::text_dim(), egui::Stroke::NONE));
    }
    resp
}

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    if style::palette_title(ui, "Properties") {
        app.settings.show_properties = false;
    }
    type_selector(app, ui);
    // Instance filter row + Edit Type.
    let (row, _) = ui.allocate_exact_size(vec2(ui.available_width(), 20.0), Sense::hover());
    {
        let label = filter_label(app);
        let p = ui.painter();
        p.text(row.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, label, style::font(12.0), style::text());
        p.line_segment([row.left_bottom(), row.right_bottom()], egui::Stroke::new(1.0, style::border()));
    }
    let t = selector_target(app).and_then(|(_, t)| t);
    let edit = Rect::from_min_max(pos2(row.right() - 72.0, row.top() + 1.0), pos2(row.right() - 2.0, row.bottom() - 1.0));
    let resp = ui.interact(edit, egui::Id::new("props-edit-type"), if t.is_some() { Sense::click() } else { Sense::hover() });
    if t.is_some() && resp.hovered() {
        ui.painter().rect_filled(edit, 0.0, style::hover());
        ui.painter().rect_stroke(edit, 0.0, egui::Stroke::new(1.0, style::hover_stroke()), egui::StrokeKind::Inside);
    }
    icons::paint(ui.painter(), Rect::from_min_size(edit.min + vec2(3.0, 3.0), vec2(13.0, 13.0)), Icon::TypeProperties, t.is_some());
    ui.painter().text(edit.left_center() + vec2(19.0, 0.0), egui::Align2::LEFT_CENTER, "Edit Type", style::font(12.0), if t.is_some() { style::text() } else { style::text_dim() });
    if resp.clicked() {
        app.dialogs.type_props = t;
    }
    // Parameters, then the Apply footer.
    let footer_h = 26.0;
    let body_h = (ui.available_height() - footer_h).max(40.0);
    egui::ScrollArea::vertical().auto_shrink([false, false]).max_height(body_h).id_salt("props-scroll").show(ui, |ui| {
        ui.spacing_mut().indent = 6.0;
        ui.spacing_mut().interact_size.y = 18.0;
        let v = ui.visuals_mut();
        v.widgets.inactive.bg_stroke = egui::Stroke::NONE;
        v.widgets.inactive.weak_bg_fill = egui::Color32::TRANSPARENT;
        v.widgets.inactive.bg_fill = egui::Color32::TRANSPARENT;
        props_body(app, ui);
    });
    let (foot, _) = ui.allocate_exact_size(vec2(ui.available_width(), footer_h), Sense::hover());
    ui.painter().line_segment([foot.left_top(), foot.right_top()], egui::Stroke::new(1.0, style::border()));
    ui.painter().text(foot.left_center() + vec2(6.0, 0.0), egui::Align2::LEFT_CENTER, "Properties help", style::font(12.0), style::ACCENT);
    let apply = Rect::from_min_max(pos2(foot.right() - 66.0, foot.top() + 3.0), pos2(foot.right() - 4.0, foot.bottom() - 3.0));
    let editing = ui.ctx().memory(|m| m.focused().is_some());
    let resp = ui.interact(apply, egui::Id::new("props-apply"), Sense::click());
    ui.painter().rect_filled(apply, 0.0, if editing && resp.hovered() { style::hover() } else { egui::Color32::from_rgb(236, 237, 238) });
    ui.painter().rect_stroke(apply, 0.0, egui::Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    ui.painter().text(apply.center(), egui::Align2::CENTER_CENTER, "Apply", style::font(12.0), if editing { style::text() } else { style::text_dim() });
    if resp.clicked() {
        // Values commit when the edited field loses focus.
        ui.ctx().memory_mut(|m| m.stop_text_input());
    }
}

fn props_body(app: &mut App, ui: &mut egui::Ui) {
    {
        let sel = app.selection.clone();
        if sel.is_empty() && new_element_properties(app, ui) {
            return;
        }
        if sel.is_empty() {
            match app.active {
                Some(v) => view_properties(app, ui, v),
                None => {
                    ui.label("No view is open.");
                }
            }
            return;
        }
        if sel.len() == 1 && app.doc.data.view(sel[0]).is_some() {
            view_properties(app, ui, sel[0]);
            return;
        }
        element_properties(app, ui, &sel);
    }
}

/// "New Walls" etc. while a placement tool runs, like the reference palette.
fn new_label(app: &App) -> Option<&'static str> {
    if !app.selection.is_empty() {
        return None;
    }
    Some(match app.tool.kind {
        ToolKind::Wall => "New Walls",
        ToolKind::Door => "New Doors",
        ToolKind::Window => "New Windows",
        ToolKind::Column => "New Columns",
        ToolKind::StructColumn => "New Structural Columns",
        ToolKind::Component => "New Components",
        ToolKind::Beam => "New Structural Framing",
        ToolKind::Room => "New Rooms",
        ToolKind::RoomSeparator => "New <Room Separation>",
        ToolKind::RoomTag => "Room Tags (1)",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| matches!(s.kind, SketchKind::Floor { .. })) => "Floors",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Roof) => "Roofs",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Ceiling) => "Ceilings",
        ToolKind::CeilingAuto => "Ceilings (1)",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Stair) => "Stair",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Ramp) => "Ramps",
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Railing) => "Railings",
        _ => return None,
    })
}

/// Instance parameters of the element about to be placed (edits go to the tool options).
fn new_element_properties(app: &mut App, ui: &mut egui::Ui) -> bool {
    if new_label(app).is_none() {
        return false;
    }
    let units = app.doc.data.units.clone();
    let level = app.active_level();
    let level_name = level.map(|l| app.doc.data.level_name(l)).unwrap_or_default();
    let len_row = |ui: &mut egui::Ui, key: &str, v: &mut f64| {
        let id = egui::Id::new(("new-prop", key.to_string()));
        let mut s: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| units.length(*v));
        let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(ui.available_width() - 4.0));
        if r.has_focus() {
            ui.memory_mut(|m| m.data.insert_temp(id, s.clone()));
        }
        if r.lost_focus() {
            ui.memory_mut(|m| m.data.remove::<String>(id));
            if let Some(x) = units.parse(&s, ParamKind::Length) {
                *v = x;
            }
        }
    };
    let ro = |ui: &mut egui::Ui, s: &str| {
        ui.label(egui::RichText::new(s).color(style::text_dim()));
    };
    let mut o = app.opts.clone();
    match app.tool.kind {
        ToolKind::Wall => {
            let open = group_open(ui, "Constraints");
            if style::group_header_ui(ui, "Constraints", open).clicked() {
                set_group_open(ui, "Constraints", !open);
            }
            if open {
                prop_grid(ui, "new-wall").show(ui, |ui| {
                    prop_label(ui, "Location Line", false);
                    egui::ComboBox::from_id_salt("nw-ll").selected_text(o.location_line.label()).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                        for l in LocationLine::ALL {
                            ui.selectable_value(&mut o.location_line, l, l.label());
                        }
                    });
                    ui.end_row();
                    prop_label(ui, "Base Constraint", true);
                    ro(ui, &level_name);
                    ui.end_row();
                    prop_label(ui, "Base Offset", false);
                    len_row(ui, "base", &mut o.wall_base_offset);
                    ui.end_row();
                    prop_label(ui, "Base is Attached", true);
                    ro(ui, "");
                    ui.end_row();
                    prop_label(ui, "Top Constraint", false);
                    let top_label = |t: Option<Id>| t.map(|t| format!("Up to level: {}", app.doc.data.level_name(t))).unwrap_or_else(|| "Unconnected".into());
                    egui::ComboBox::from_id_salt("nw-top").selected_text(top_label(o.wall_top)).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                        ui.selectable_value(&mut o.wall_top, None, "Unconnected");
                        for (lid, _) in app.doc.data.levels() {
                            ui.selectable_value(&mut o.wall_top, Some(lid), top_label(Some(lid)));
                        }
                    });
                    ui.end_row();
                    prop_label(ui, "Unconnected Height", o.wall_top.is_some());
                    if o.wall_top.is_none() {
                        len_row(ui, "height", &mut o.wall_height);
                    } else {
                        ro(ui, &units.length(o.wall_height));
                    }
                    ui.end_row();
                    prop_label(ui, "Top Offset", o.wall_top.is_none());
                    if o.wall_top.is_some() {
                        len_row(ui, "top", &mut o.wall_top_offset);
                    } else {
                        ro(ui, &units.length(0.0));
                    }
                    ui.end_row();
                    prop_label(ui, "Room Bounding", false);
                    crate::style::check(ui, &mut o.wall_room_bounding, "");
                    ui.end_row();
                });
            }
            let open = group_open(ui, "Structural");
            if style::group_header_ui(ui, "Structural", open).clicked() {
                set_group_open(ui, "Structural", !open);
            }
            if open {
                prop_grid(ui, "new-wall-s").show(ui, |ui| {
                    prop_label(ui, "Structural", false);
                    crate::style::check(ui, &mut o.wall_structural, "");
                    ui.end_row();
                });
            }
        }
        ToolKind::Door | ToolKind::Window => {
            let is_window = app.tool.kind == ToolKind::Window;
            let t = if is_window { o.window_type } else { o.door_type };
            let default_sill = app
                .doc
                .data
                .family_type(t)
                .map(|(f, ft)| rc_core::family_params::Resolver::for_type(f, ft).num("Default Sill Height", if is_window { 900.0 } else { 0.0 }))
                .unwrap_or(0.0);
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-opening").show(ui, |ui| {
                prop_label(ui, "Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Sill Height", !is_window);
                if is_window {
                    let mut s = o.window_sill.unwrap_or(default_sill);
                    len_row(ui, "sill", &mut s);
                    if (s - default_sill).abs() > 1e-6 || o.window_sill.is_some() {
                        o.window_sill = Some(s);
                    }
                } else {
                    ro(ui, &units.length(0.0));
                }
                ui.end_row();
            });
        }
        ToolKind::StructColumn => {
            // A new structural column's instance parameters.
            let mat = app.doc.data.family_type(o.struct_column_type).map(|(f, t)| rc_core::family_params::Resolver::for_type(f, t)).map(|r| r.text("Structural Material", &r.text("Material", ""))).unwrap_or_default();
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-scol").show(ui, |ui| {
                prop_label(ui, "Moves With Grids", false);
                style::check(ui, &mut o.column_moves_grids, "");
                ui.end_row();
            });
            style::group_header_ui(ui, "Materials and Finishes", true);
            prop_grid(ui, "new-scol-m").show(ui, |ui| {
                prop_label(ui, "Structural Material", true);
                ro(ui, &mat);
                ui.end_row();
            });
            style::group_header_ui(ui, "Structural", true);
            prop_grid(ui, "new-scol-s").show(ui, |ui| {
                for (n, v) in [("Top Connection", "None"), ("Base Connection", "None")] {
                    prop_label(ui, n, true);
                    ro(ui, v);
                    ui.end_row();
                }
            });
        }
        ToolKind::Component => {
            // A new component's instance parameters (free instances host on the level).
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-comp").show(ui, |ui| {
                prop_label(ui, "Level", false);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Host", true);
                ro(ui, &format!("Level : {level_name}"));
                ui.end_row();
                prop_label(ui, "Offset from Host", false);
                len_row(ui, "comp-off", &mut o.component_offset);
                ui.end_row();
                prop_label(ui, "Moves With Nearby Elements", false);
                crate::style::check(ui, &mut o.component_moves_nearby, "");
                ui.end_row();
            });
            style::group_header_ui(ui, "Identity Data", true);
            prop_grid(ui, "new-comp-id").show(ui, |ui| {
                prop_label(ui, "Image", true);
                ro(ui, "");
                ui.end_row();
                prop_label(ui, "Comments", false);
                ui.add(egui::TextEdit::singleline(&mut o.place_comments).desired_width(ui.available_width() - 4.0));
                ui.end_row();
                prop_label(ui, "Mark", false);
                ui.add(egui::TextEdit::singleline(&mut o.place_mark).desired_width(ui.available_width() - 4.0));
                ui.end_row();
            });
        }
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| matches!(s.kind, SketchKind::Floor { .. })) => {
            // A new floor's instance parameters while its boundary is sketched.
            let mut structural = matches!(app.sketch.as_ref().map(|s| &s.kind), Some(SketchKind::Floor { structural: true }));
            let thick = app.doc.data.sys_type(o.floor_type).map(|t| t.thickness()).unwrap_or(0.0);
            let top = level.map(|l| app.doc.data.level_elevation(l)).unwrap_or(0.0) + o.floor_offset;
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-floor").show(ui, |ui| {
                prop_label(ui, "Level", false);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Height Offset From Level", false);
                len_row(ui, "floor-off", &mut o.floor_offset);
                ui.end_row();
                prop_label(ui, "Room Bounding", false);
                crate::style::check(ui, &mut o.floor_room_bounding, "");
                ui.end_row();
                prop_label(ui, "Related to Mass", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                ui.end_row();
            });
            style::group_header_ui(ui, "Structural", true);
            prop_grid(ui, "new-floor-s").show(ui, |ui| {
                prop_label(ui, "Structural", false);
                crate::style::check(ui, &mut structural, "");
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-floor-d").show(ui, |ui| {
                for (name, value) in [("Slope", String::new()), ("Perimeter", String::new()), ("Area", String::new()), ("Volume", String::new()), ("Elevation at Top", units.length(top)), ("Elevation at Bottom", units.length(top - thick)), ("Thickness", units.length(thick))] {
                    prop_label(ui, name, true);
                    ro(ui, &value);
                    ui.end_row();
                }
            });
            if let Some(SketchKind::Floor { structural: s }) = app.sketch.as_mut().map(|s| &mut s.kind) {
                *s = structural;
            }
        }
        ToolKind::CeilingAuto | ToolKind::SketchLine | ToolKind::Select if app.tool.kind == ToolKind::CeilingAuto || app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Ceiling) => {
            // A new ceiling's instance parameters (Automatic Ceiling or a ceiling sketch).
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-ceil").show(ui, |ui| {
                prop_label(ui, "Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Height Offset From Level", false);
                len_row(ui, "ceil-off", &mut o.ceiling_offset);
                ui.end_row();
                prop_label(ui, "Room Bounding", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, ""));
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-ceil-d").show(ui, |ui| {
                for (name, value) in [("Slope", String::new()), ("Perimeter", String::new()), ("Area", String::new()), ("Volume", units.volume(0.0))] {
                    prop_label(ui, name, true);
                    ro(ui, &value);
                    ui.end_row();
                }
            });
            style::group_header_ui(ui, "Identity Data", true);
            prop_grid(ui, "new-ceil-id").show(ui, |ui| {
                prop_label(ui, "Image", true);
                ro(ui, "");
                ui.end_row();
                prop_label(ui, "Comments", false);
                ui.add(egui::TextEdit::singleline(&mut o.place_comments).desired_width(ui.available_width() - 4.0));
                ui.end_row();
                prop_label(ui, "Mark", false);
                ui.add(egui::TextEdit::singleline(&mut o.place_mark).desired_width(ui.available_width() - 4.0));
                ui.end_row();
            });
            let phase = app.doc.data.phases.last().map(|p| p.name.clone()).unwrap_or_default();
            style::group_header_ui(ui, "Phasing", true);
            prop_grid(ui, "new-ceil-ph").show(ui, |ui| {
                prop_label(ui, "Phase Created", true);
                ro(ui, &phase);
                ui.end_row();
                prop_label(ui, "Phase Demolished", true);
                ro(ui, "None");
                ui.end_row();
            });
        }
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Stair) => {
            // A new stair's instance parameters while its runs are drawn.
            let (n, made, rh, tread) = crate::canvas_tools::sketch_stair_numbers(app).unwrap_or((0, 0, 0.0, 0.0));
            let base_level = app.sketch.as_ref().map(|s| s.level).unwrap_or_default();
            let p = &app.doc.data;
            let base_z = p.level_elevation(base_level) + o.stair_base_offset;
            let top_z = o.stair_top.map(|t| p.level_elevation(t) + o.stair_top_offset);
            let levels: Vec<(Id, String)> = p.levels().iter().map(|(id, l)| (*id, l.name.clone())).collect();
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-stair").show(ui, |ui| {
                prop_label(ui, "Base Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Base Offset", false);
                len_row(ui, "stair-base", &mut o.stair_base_offset);
                ui.end_row();
                prop_label(ui, "Top Level", false);
                let name = o.stair_top.and_then(|t| levels.iter().find(|l| l.0 == t).map(|l| l.1.clone())).unwrap_or_else(|| "None".into());
                egui::ComboBox::from_id_salt("ns-top").selected_text(name).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut o.stair_top, None, "None");
                    for (id, n) in &levels {
                        ui.selectable_value(&mut o.stair_top, Some(*id), n);
                    }
                });
                ui.end_row();
                prop_label(ui, "Top Offset", o.stair_top.is_none());
                len_row(ui, "stair-top", &mut o.stair_top_offset);
                ui.end_row();
                prop_label(ui, "Desired Stair Height", true);
                ro(ui, &top_z.map(|t| units.length(t - base_z)).unwrap_or_default());
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-stair-d").show(ui, |ui| {
                prop_label(ui, "Desired Number of Risers", false);
                let mut s = n.to_string();
                let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(ui.available_width() - 4.0));
                if r.changed() {
                    if let Ok(v) = s.trim().parse::<u32>() {
                        o.stair_risers = v.clamp(2, 200);
                    }
                }
                ui.end_row();
                for (name, value) in [("Actual Number of Risers", made.to_string()), ("Actual Riser Height", units.length(rh)), ("Actual Tread Depth", units.length(tread)), ("Tread/Riser Start Number", "1".to_string())] {
                    prop_label(ui, name, true);
                    ro(ui, &value);
                    ui.end_row();
                }
            });
        }
        ToolKind::RoomSeparator => {
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-rs").show(ui, |ui| {
                prop_label(ui, "Moves With Nearby Elements", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                ui.end_row();
            });
            style::group_header_ui(ui, "Graphics", true);
            prop_grid(ui, "new-rs-g").show(ui, |ui| {
                prop_label(ui, "Detail Line", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                ui.end_row();
            });
        }
        ToolKind::RoomTag => {
            style::group_header_ui(ui, "Graphics", true);
            prop_grid(ui, "new-rt").show(ui, |ui| {
                prop_label(ui, "Leader Line", false);
                crate::style::check(ui, &mut o.tag_leader, "");
                ui.end_row();
                prop_label(ui, "Orientation", false);
                egui::ComboBox::from_id_salt("nrt-or").selected_text(if o.tag_horizontal { "Horizontal" } else { "Vertical" }).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut o.tag_horizontal, true, "Horizontal");
                    ui.selectable_value(&mut o.tag_horizontal, false, "Vertical");
                });
                ui.end_row();
                prop_label(ui, "Angle", true);
                ro(ui, &units.format(if o.tag_horizontal { 0.0 } else { 90.0 }, ParamKind::Angle));
                ui.end_row();
            });
        }
        ToolKind::Room => {
            // A new room's instance parameters.
            let p = &app.doc.data;
            let levels: Vec<(Id, String)> = p.levels().iter().map(|(id, l)| (*id, l.name.clone())).collect();
            let base = level.unwrap_or_default();
            let top = p.level_elevation(o.room_upper_level.unwrap_or(base)) + o.room_upper;
            let height = (top - p.level_elevation(base) - o.room_base_offset).max(0.0);
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-room").show(ui, |ui| {
                prop_label(ui, "Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Upper Limit", false);
                let cur = o.room_upper_level.unwrap_or(base);
                let mut pick = cur;
                let name = levels.iter().find(|l| l.0 == cur).map(|l| l.1.clone()).unwrap_or_default();
                egui::ComboBox::from_id_salt("nroom-ul").selected_text(name).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                    for (id, n) in &levels {
                        ui.selectable_value(&mut pick, *id, n);
                    }
                });
                if pick != cur {
                    o.room_upper_level = Some(pick).filter(|l| *l != base);
                }
                ui.end_row();
                prop_label(ui, "Limit Offset", false);
                len_row(ui, "room-lim", &mut o.room_upper);
                ui.end_row();
                prop_label(ui, "Base Offset", false);
                len_row(ui, "room-base", &mut o.room_base_offset);
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-room-d").show(ui, |ui| {
                for (name, value) in [("Area", "Not Enclosed".to_string()), ("Perimeter", "Not Enclosed".to_string()), ("Unbounded Height", units.length(height)), ("Volume", "Not Enclosed".to_string()), ("Computation Height", units.length(0.0))] {
                    prop_label(ui, name, true);
                    ro(ui, &value);
                    ui.end_row();
                }
            });
        }
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Ramp) => {
            // A new ramp's instance parameters while its runs are drawn.
            let levels: Vec<(Id, String)> = app.doc.data.levels().iter().map(|(id, l)| (*id, l.name.clone())).collect();
            let r = &mut o.ramp;
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-ramp").show(ui, |ui| {
                prop_label(ui, "Base Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Base Offset", false);
                len_row(ui, "ramp-base", &mut r.base_offset);
                ui.end_row();
                prop_label(ui, "Top Level", false);
                let name = r.top_level.and_then(|t| levels.iter().find(|l| l.0 == t).map(|l| l.1.clone())).unwrap_or_else(|| "None".into());
                egui::ComboBox::from_id_salt("nr-top").selected_text(name).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut r.top_level, None, "None");
                    for (id, n) in &levels {
                        ui.selectable_value(&mut r.top_level, Some(*id), n);
                    }
                });
                ui.end_row();
                prop_label(ui, "Top Offset", false);
                len_row(ui, "ramp-top", &mut r.top_offset);
                ui.end_row();
                prop_label(ui, "Multistory Top Level", true);
                ro(ui, "None");
                ui.end_row();
            });
            style::group_header_ui(ui, "Graphics", true);
            prop_grid(ui, "new-ramp-g").show(ui, |ui| {
                prop_label(ui, "Up text", false);
                ui.add(egui::TextEdit::singleline(&mut r.up_text).desired_width(ui.available_width() - 4.0));
                ui.end_row();
                prop_label(ui, "Down text", false);
                ui.add(egui::TextEdit::singleline(&mut r.down_text).desired_width(ui.available_width() - 4.0));
                ui.end_row();
                prop_label(ui, "Up label", false);
                crate::style::check(ui, &mut r.up_label, "");
                ui.end_row();
                prop_label(ui, "Down label", false);
                crate::style::check(ui, &mut r.down_label, "");
                ui.end_row();
                prop_label(ui, "Show Up arrow in all views", false);
                crate::style::check(ui, &mut r.up_arrow_all_views, "");
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-ramp-d").show(ui, |ui| {
                prop_label(ui, "Width", false);
                len_row(ui, "ramp-w", &mut o.ramp_width);
                ui.end_row();
            });
        }
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Railing) => {
            // A new railing's instance parameters while its path is sketched.
            let len: f64 = app.sketch.as_ref().map(|s| s.segs.iter().map(|g| g.points().windows(2).map(|w| w[0].distance(w[1])).sum::<f64>()).sum()).unwrap_or(0.0);
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-rail").show(ui, |ui| {
                prop_label(ui, "Base Level", true);
                ro(ui, &level_name);
                ui.end_row();
                prop_label(ui, "Base Offset", false);
                len_row(ui, "rail-base", &mut o.railing_base_offset);
                ui.end_row();
                prop_label(ui, "Offset from Path", true);
                ro(ui, &units.length(0.0));
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-rail-d").show(ui, |ui| {
                prop_label(ui, "Length", true);
                ro(ui, &units.length(len));
                ui.end_row();
            });
        }
        ToolKind::SketchLine | ToolKind::Select if app.sketch.as_ref().is_some_and(|s| s.kind == SketchKind::Roof) => {
            // A new footprint roof's instance parameters while its footprint is sketched.
            let mut base = app.sketch.as_ref().map(|s| s.level).unwrap_or_default();
            let thick = app.doc.data.sys_type(o.roof_type).map(|t| t.thickness()).unwrap_or(0.0);
            let levels: Vec<(Id, String)> = app.doc.data.levels().iter().map(|(id, l)| (*id, l.name.clone())).collect();
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-roof").show(ui, |ui| {
                prop_label(ui, "Base Level", false);
                let name = levels.iter().find(|l| l.0 == base).map(|l| l.1.clone()).unwrap_or_default();
                egui::ComboBox::from_id_salt("nr-base").selected_text(name).width(ui.available_width() - 4.0).icon(chevron).show_ui(ui, |ui| {
                    for (id, n) in &levels {
                        ui.selectable_value(&mut base, *id, n);
                    }
                });
                ui.end_row();
                prop_label(ui, "Room Bounding", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut true, ""));
                ui.end_row();
                prop_label(ui, "Related to Mass", true);
                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut false, ""));
                ui.end_row();
                prop_label(ui, "Base Offset From Level", false);
                len_row(ui, "roof-base", &mut o.roof_base_offset);
                ui.end_row();
                prop_label(ui, "Cutoff Level", true);
                ro(ui, "None");
                ui.end_row();
                prop_label(ui, "Cutoff Offset", true);
                ro(ui, &units.length(0.0));
                ui.end_row();
            });
            style::group_header_ui(ui, "Construction", true);
            prop_grid(ui, "new-roof-c").show(ui, |ui| {
                prop_label(ui, "Rafter Cut", true);
                ro(ui, "Plumb Cut");
                ui.end_row();
                prop_label(ui, "Fascia Depth", true);
                ro(ui, "");
                ui.end_row();
                prop_label(ui, "Maximum Ridge Height", true);
                ro(ui, "");
                ui.end_row();
            });
            style::group_header_ui(ui, "Dimensions", true);
            prop_grid(ui, "new-roof-d").show(ui, |ui| {
                prop_label(ui, "Slope", false);
                let id = egui::Id::new("new-prop-roof-slope");
                let mut s: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| units.slope(o.roof_slope));
                let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(ui.available_width() - 4.0));
                if r.has_focus() {
                    ui.memory_mut(|m| m.data.insert_temp(id, s.clone()));
                }
                if r.lost_focus() {
                    ui.memory_mut(|m| m.data.remove::<String>(id));
                    if let Some(x) = units.parse_slope(&s).filter(|x| (0.0..=80.0).contains(x)) {
                        o.roof_slope = x;
                    }
                }
                ui.end_row();
                for (name, value) in [("Thickness", units.length(thick)), ("Volume", String::new()), ("Area", String::new())] {
                    prop_label(ui, name, true);
                    ro(ui, &value);
                    ui.end_row();
                }
            });
            if let Some(sk) = app.sketch.as_mut() {
                sk.level = base;
            }
        }
        _ => {
            style::group_header_ui(ui, "Constraints", true);
            prop_grid(ui, "new-other").show(ui, |ui| {
                prop_label(ui, "Level", true);
                ro(ui, &level_name);
                ui.end_row();
            });
        }
    }
    app.opts = o;
    true
}

fn filter_label(app: &App) -> String {
    if let Some(l) = new_label(app) {
        return l.to_string();
    }
    if app.selection.is_empty() {
        return app.active_view().map(|v| format!("{}: {}", v.type_label(), v.name)).unwrap_or_default();
    }
    let mut counts: BTreeMap<&'static str, usize> = BTreeMap::new();
    for id in &app.selection {
        if let Some(e) = app.el(*id) {
            *counts.entry(e.category().label()).or_default() += 1;
        } else if app.doc.data.view(*id).is_some() {
            *counts.entry("Views").or_default() += 1;
        }
    }
    if counts.len() == 1 {
        let (k, n) = counts.into_iter().next().unwrap();
        format!("{k} ({n})")
    } else {
        format!("Common ({})", app.selection.len())
    }
}

/// Collapsible state per group.
fn group_open(ui: &egui::Ui, name: &str) -> bool {
    ui.memory(|m| m.data.get_temp::<bool>(egui::Id::new(("prop-group", name)))).unwrap_or(true)
}

fn set_group_open(ui: &egui::Ui, name: &str, open: bool) {
    ui.memory_mut(|m| m.data.insert_temp(egui::Id::new(("prop-group", name)), open));
}

fn element_properties(app: &mut App, ui: &mut egui::Ui, sel: &[Id]) {
    let p = app.snapshot();
    let elems: Vec<&Element> = sel.iter().filter_map(|id| p.element(*id)).collect();
    if elems.is_empty() {
        return;
    }
    // Parameters common to all selected elements (instance parameters only).
    let first = params::element_params(&p, elems[0]);
    let common: Vec<ParamDef> = first.into_iter().filter(|d| !d.type_param).filter(|d| elems.iter().skip(1).all(|e| params::element_params(&p, e).iter().any(|x| x.name == d.name))).collect();
    let mut groups: Vec<(String, Vec<ParamDef>)> = Vec::new();
    for d in common {
        match groups.iter_mut().find(|g| g.0 == d.group) {
            Some(g) => g.1.push(d),
            None => groups.push((d.group.clone(), vec![d])),
        }
    }
    let mut edits: Vec<(String, String)> = Vec::new();
    let mut link: Option<(String, Option<String>)> = None;
    for (g, defs) in groups {
        let open = group_open(ui, &g);
        if style::group_header_ui(ui, &g, open).clicked() {
            set_group_open(ui, &g, !open);
        }
        if !open {
            continue;
        }
        prop_grid(ui, ("props", &g)).show(ui, |ui| {
            for d in defs {
                let values: Vec<String> = elems.iter().map(|e| params::display(&p, e, &d)).collect();
                let same = values.iter().all(|v| *v == values[0]);
                let shown = if same { values[0].clone() } else { String::new() };
                prop_label(ui, &d.name, d.read_only);
                // Parameters that can be associated with a global parameter of the same type.
                let globals: Vec<String> = match &d.kind {
                    PKind::Value(k) if !d.read_only && elems.len() == 1 => p.global_params.iter().filter(|g| g.kind == *k).map(|g| g.name.clone()).collect(),
                    _ => vec![],
                };
                let linked = if elems.len() == 1 { elems[0].global_links.get(&d.name).cloned() } else { None };
                if globals.is_empty() && linked.is_none() {
                    if let Some(v) = value_editor(ui, app, &d, &shown, ("elem", sel.first().copied().unwrap_or(0), d.name.clone())) {
                        edits.push((d.name.clone(), v));
                    }
                } else {
                    let avail = ui.available_width();
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing.x = 2.0;
                        let w = (avail - 22.0).max(40.0);
                        ui.allocate_ui(vec2(w, 20.0), |ui| {
                            ui.set_width(w);
                            if linked.is_some() {
                                ui.add(egui::Label::new(egui::RichText::new(&shown).color(style::text_dim())).truncate());
                            } else if let Some(v) = value_editor(ui, app, &d, &shown, ("elem", sel.first().copied().unwrap_or(0), d.name.clone())) {
                                edits.push((d.name.clone(), v));
                            }
                        });
                        let tip = match &linked {
                            Some(g) => format!("Associated with global parameter: {g}"),
                            None => "Associate Global Parameter".to_string(),
                        };
                        let b = ui.add(egui::Button::new(egui::RichText::new(if linked.is_some() { "=" } else { "⊞" }).size(11.0)).min_size(vec2(18.0, 18.0)).selected(linked.is_some())).on_hover_text(tip);
                        egui::Popup::menu(&b).show(|ui| {
                            ui.label(egui::RichText::new("Associate Global Parameter").strong());
                            if ui.selectable_label(linked.is_none(), "<None>").clicked() {
                                link = Some((d.name.clone(), None));
                            }
                            for g in &globals {
                                if ui.selectable_label(linked.as_deref() == Some(g.as_str()), g).clicked() {
                                    link = Some((d.name.clone(), Some(g.clone())));
                                }
                            }
                        });
                    });
                }
                ui.end_row();
            }
        });
    }
    if let Some((param, g)) = link {
        let id = sel[0];
        app.run("Associate Global Parameter", |p| {
            let e = p.element_mut(id).ok_or("Element not found.")?;
            match g {
                Some(g) => {
                    e.global_links.insert(param, g);
                }
                None => {
                    e.global_links.remove(&param);
                }
            }
            Ok(())
        });
    }
    if !edits.is_empty() {
        let ids: Vec<Id> = sel.to_vec();
        app.run("Modify Parameters", |p| {
            for (name, v) in &edits {
                for id in &ids {
                    params::set(p, *id, name, v)?;
                }
            }
            Ok(())
        });
    }
}

/// An editor for one parameter. Returns the new input text when committed.
fn value_editor(ui: &mut egui::Ui, app: &App, d: &ParamDef, shown: &str, key: (&str, Id, String)) -> Option<String> {
    let p = &app.doc.data;
    let width = ui.available_width().max(80.0);
    if d.read_only {
        ui.add(egui::Label::new(egui::RichText::new(shown).color(style::text_dim())).truncate());
        return None;
    }
    match &d.kind {
        PKind::Value(ParamKind::YesNo) => {
            let mut b = matches!(shown, "Yes" | "yes" | "1" | "true");
            if crate::style::check(ui, &mut b, "").changed() {
                return Some(if b { "Yes".into() } else { "No".into() });
            }
            None
        }
        PKind::Level => {
            let mut out = None;
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).icon(chevron).show_ui(ui, |ui| {
                for (_, l) in p.levels() {
                    if ui.selectable_label(l.name == shown, &l.name).clicked() {
                        out = Some(l.name.clone());
                    }
                }
            });
            out
        }
        PKind::Choice(options) => {
            let mut out = None;
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).icon(chevron).show_ui(ui, |ui| {
                for o in options {
                    if ui.selectable_label(o == shown, o).clicked() {
                        out = Some(o.clone());
                    }
                }
            });
            out
        }
        PKind::Value(ParamKind::Material) => {
            let mut out = None;
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).icon(chevron).show_ui(ui, |ui| {
                for m in &p.materials {
                    if ui.selectable_label(m.name == shown, &m.name).clicked() {
                        out = Some(m.name.clone());
                    }
                }
            });
            out
        }
        _ => {
            let id = egui::Id::new(("prop-edit", &key));
            let mut text: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| shown.to_string());
            let r = ui.add(egui::TextEdit::singleline(&mut text).desired_width(width - 8.0));
            if r.has_focus() {
                ui.memory_mut(|m| m.data.insert_temp(id, text.clone()));
            }
            if r.lost_focus() {
                ui.memory_mut(|m| m.data.remove::<String>(id));
                if text != shown {
                    return Some(text);
                }
            }
            None
        }
    }
}

fn row_label(ui: &mut egui::Ui, s: &str) {
    prop_label(ui, s, false);
}

/// The thin drop-down chevron of property cells (instead of a heavy triangle).
pub fn chevron(ui: &egui::Ui, rect: Rect, _visuals: &egui::style::WidgetVisuals, open: bool) {
    let c = rect.center();
    let st = egui::Stroke::new(1.0, if open { style::text() } else { style::text_dim() });
    ui.painter().line_segment([c + vec2(-3.5, -1.5), c + vec2(0.0, 2.0)], st);
    ui.painter().line_segment([c + vec2(0.0, 2.0), c + vec2(3.5, -1.5)], st);
}

/// A two-column property grid with thin grid lines (drawn by `prop_label`).
pub fn prop_grid(ui: &egui::Ui, id: impl std::hash::Hash + std::fmt::Debug) -> egui::Grid {
    egui::Grid::new(id).num_columns(2).striped(false).spacing(vec2(0.0, 0.0)).min_col_width(label_width(ui)).min_row_height(20.0)
}

fn label_width(ui: &egui::Ui) -> f32 {
    (ui.clip_rect().width() * 0.46).floor().clamp(80.0, 200.0)
}

/// The label cell of a property row; also draws the row's grid lines.
pub fn prop_label(ui: &mut egui::Ui, s: &str, dim: bool) {
    let w = label_width(ui);
    let (r, resp) = ui.allocate_exact_size(vec2(w, 20.0), Sense::hover());
    let clip = ui.clip_rect();
    let p = ui.painter();
    let line = egui::Stroke::new(1.0, style::grid_line());
    p.line_segment([egui::pos2(clip.left(), r.bottom() - 0.5), egui::pos2(clip.right(), r.bottom() - 0.5)], line);
    p.line_segment([egui::pos2(r.right() - 0.5, r.top()), egui::pos2(r.right() - 0.5, r.bottom())], line);
    let galley = p.layout_no_wrap(s.to_string(), style::font(12.0), if dim { style::text_dim() } else { style::text() });
    let truncated = galley.size().x > w - 10.0;
    p.with_clip_rect(r.shrink2(vec2(1.0, 0.0))).galley(egui::pos2(r.left() + 6.0, r.center().y - galley.size().y / 2.0), galley, style::text());
    if truncated {
        resp.on_hover_text(s);
    }
}

/// The grey "Edit..." button that fills a value cell.
pub fn edit_button(ui: &mut egui::Ui) -> egui::Response {
    let w = ui.available_width().max(60.0) - 2.0;
    let (r, resp) = ui.allocate_exact_size(vec2(w, 19.0), Sense::click());
    let fill = if resp.hovered() { style::hover() } else { egui::Color32::from_rgb(236, 237, 238) };
    ui.painter().rect_filled(r.shrink(1.0), 0.0, fill);
    ui.painter().rect_stroke(r.shrink(1.0), 0.0, egui::Stroke::new(1.0, style::grid_line()), egui::StrokeKind::Inside);
    ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, "Edit...", style::font(12.0), style::text());
    resp
}

fn view_properties(app: &mut App, ui: &mut egui::Ui, vid: Id) {
    let Some(v) = app.doc.data.view(vid).cloned() else { return };
    let mut changed = v.clone();
    let p = app.snapshot();
    let mut open_vg = false;
    let mut open_range = false;
    let section = |ui: &mut egui::Ui, name: &str| -> bool {
        let open = group_open(ui, name);
        if style::group_header_ui(ui, name, open).clicked() {
            set_group_open(ui, name, !open);
        }
        open
    };
    if section(ui, "Graphics") {
        prop_grid(ui, "view-graphics").show(ui, |ui| {
            if v.is_graphical() {
                row_label(ui, "View Scale");
                let imperial = app.doc.data.units.system == rc_core::units::UnitSystem::Imperial;
                let list: Vec<(f64, String)> = if imperial {
                    crate::viewbar::IMPERIAL_SCALES.iter().map(|(v, l)| (*v, l.to_string())).collect()
                } else {
                    crate::viewbar::METRIC_SCALES.iter().map(|v| (*v, format!("1 : {v}"))).collect()
                };
                let w = ui.available_width() - 4.0;
                egui::ComboBox::from_id_salt("vp-scale").selected_text(crate::viewbar::scale_label(app, changed.scale)).width(w).icon(chevron).show_ui(ui, |ui| {
                    for (v, l) in list {
                        ui.selectable_value(&mut changed.scale, v, l);
                    }
                });
                ui.end_row();
                prop_label(ui, "Scale Value    1:", true);
                ui.label(egui::RichText::new(format!("{}", changed.scale.round())).color(style::text_dim()));
                ui.end_row();
                row_label(ui, "Detail Level");
                egui::ComboBox::from_id_salt("vp-detail").selected_text(changed.detail.label()).icon(chevron).show_ui(ui, |ui| {
                    for d in DetailLevel::ALL {
                        ui.selectable_value(&mut changed.detail, d, d.label());
                    }
                });
                ui.end_row();
                row_label(ui, "Visibility/Graphics Overrides");
                if edit_button(ui).clicked() {
                    open_vg = true;
                }
                ui.end_row();
                row_label(ui, "Visual Style");
                egui::ComboBox::from_id_salt("vp-style").selected_text(changed.style.label()).icon(chevron).show_ui(ui, |ui| {
                    for s in VisualStyle::ALL {
                        ui.selectable_value(&mut changed.style, s, s.label());
                    }
                });
                ui.end_row();
                row_label(ui, "Shadows");
                crate::style::check(ui, &mut changed.shadows, "");
                ui.end_row();
            }
            if let ViewKind::FloorPlan { room_colors, .. } = &mut changed.kind {
                row_label(ui, "Color Scheme (rooms)");
                crate::style::check(ui, room_colors, "");
                ui.end_row();
            }
            if v.plan_level().is_some() {
                row_label(ui, "Underlay");
                let label = changed.underlay.map(|l| p.level_name(l)).unwrap_or_else(|| "None".into());
                egui::ComboBox::from_id_salt("vp-underlay").selected_text(label).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut changed.underlay, None, "None");
                    for (id, l) in p.levels() {
                        ui.selectable_value(&mut changed.underlay, Some(id), &l.name);
                    }
                });
                ui.end_row();
            }
        });
    }
    if v.is_graphical() && section(ui, "Extents") {
        prop_grid(ui, "view-extents").show(ui, |ui| {
            if !matches!(v.kind, ViewKind::ThreeD { .. }) {
                row_label(ui, "Crop View");
                crate::style::check(ui, &mut changed.crop_active, "");
                ui.end_row();
                row_label(ui, "Crop Region Visible");
                crate::style::check(ui, &mut changed.crop_visible, "");
                ui.end_row();
            }
            if v.plan_level().is_some() {
                row_label(ui, "View Range");
                if edit_button(ui).clicked() {
                    open_range = true;
                }
                ui.end_row();
                row_label(ui, "Associated Level");
                ui.label(p.level_name(v.plan_level().unwrap()));
                ui.end_row();
                row_label(ui, "Scope Box");
                let boxes: Vec<(Id, String)> = p
                    .elements
                    .iter()
                    .filter_map(|e| match &e.kind {
                        ElementKind::ScopeBox(s) => Some((e.id, s.name.clone())),
                        _ => None,
                    })
                    .collect();
                let label = changed.scope_box.and_then(|id| boxes.iter().find(|b| b.0 == id)).map(|b| b.1.clone()).unwrap_or_else(|| "None".into());
                egui::ComboBox::from_id_salt("vp-scope-box").selected_text(label).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut changed.scope_box, None, "None");
                    for (id, name) in &boxes {
                        ui.selectable_value(&mut changed.scope_box, Some(*id), name);
                    }
                });
                ui.end_row();
            }
            if let ViewKind::ThreeD { .. } = v.kind {
                row_label(ui, "Section Box");
                let mut on = changed.section_box.is_some();
                if crate::style::check(ui, &mut on, "").changed() {
                    changed.section_box = None;
                    if on {
                        let fp = app.footprints();
                        changed.section_box = rc_core::sheet::model_bounds(&p, &fp).map(|(a, b)| (a - rc_core::geom::DVec3::splat(500.0), b + rc_core::geom::DVec3::splat(500.0)));
                    }
                }
                ui.end_row();
            }
            if let ViewKind::Section { depth, .. } = &mut changed.kind {
                row_label(ui, "Far Clip Offset");
                ui.add(egui::DragValue::new(depth).range(100.0..=1e6).speed(50.0));
                ui.end_row();
            }
        });
    }
    if section(ui, "Identity Data") {
        prop_grid(ui, "view-identity").show(ui, |ui| {
            row_label(ui, "View Template");
            let tname = changed.template.and_then(|t| p.view(t)).map(|t| t.name.clone()).unwrap_or_else(|| "<None>".into());
            egui::ComboBox::from_id_salt("vp-template").selected_text(tname).icon(chevron).show_ui(ui, |ui| {
                ui.selectable_value(&mut changed.template, None, "<None>");
                for t in p.views.iter().filter(|t| t.is_template) {
                    ui.selectable_value(&mut changed.template, Some(t.id), &t.name);
                }
            });
            ui.end_row();
            row_label(ui, "View Name");
            let id = egui::Id::new(("view-name", vid));
            let mut name: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| changed.name.clone());
            let r = ui.text_edit_singleline(&mut name);
            if r.has_focus() {
                ui.memory_mut(|m| m.data.insert_temp(id, name.clone()));
            }
            if r.lost_focus() {
                ui.memory_mut(|m| m.data.remove::<String>(id));
                changed.name = name;
            }
            ui.end_row();
            if let ViewKind::Sheet(s) = &mut changed.kind {
                for (label, field) in [("Sheet Number", &mut s.number), ("Drawn By", &mut s.drawn_by), ("Checked By", &mut s.checked_by), ("Designed By", &mut s.designed_by), ("Approved By", &mut s.approved_by), ("Sheet Issue Date", &mut s.issue_date)] {
                    row_label(ui, label);
                    let id = egui::Id::new(("sheet-field", vid, label));
                    let mut t: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| field.clone());
                    let r = ui.text_edit_singleline(&mut t);
                    if r.has_focus() {
                        ui.memory_mut(|m| m.data.insert_temp(id, t.clone()));
                    }
                    if r.lost_focus() {
                        ui.memory_mut(|m| m.data.remove::<String>(id));
                        *field = t;
                    }
                    ui.end_row();
                }
                row_label(ui, "Sheet Size");
                egui::ComboBox::from_id_salt("sheet-size").selected_text(s.size.label()).icon(chevron).show_ui(ui, |ui| {
                    for sz in SheetSize::ALL {
                        ui.selectable_value(&mut s.size, sz, sz.label());
                    }
                });
                ui.end_row();
            } else if v.is_graphical() {
                row_label(ui, "Title on Sheet");
                let id = egui::Id::new(("view-title", vid));
                let mut t: String = ui.memory(|m| m.data.get_temp(id)).unwrap_or_else(|| changed.title_on_sheet.clone());
                let r = ui.text_edit_singleline(&mut t);
                if r.has_focus() {
                    ui.memory_mut(|m| m.data.insert_temp(id, t.clone()));
                }
                if r.lost_focus() {
                    ui.memory_mut(|m| m.data.remove::<String>(id));
                    changed.title_on_sheet = t;
                }
                ui.end_row();
                row_label(ui, "Sheet Number");
                let sheet = p.sheet_containing(vid).map(|s| match &s.kind {
                    ViewKind::Sheet(sh) => sh.number.clone(),
                    _ => String::new(),
                });
                ui.label(egui::RichText::new(sheet.unwrap_or_else(|| "---".into())).color(style::text_dim()));
                ui.end_row();
            }
        });
    }
    if v.is_graphical() && section(ui, "Phasing") {
        prop_grid(ui, "view-phasing").show(ui, |ui| {
            row_label(ui, "Phase Filter");
            egui::ComboBox::from_id_salt("vp-pf").selected_text(changed.phase_filter.label()).icon(chevron).show_ui(ui, |ui| {
                for f in PhaseFilter::ALL {
                    ui.selectable_value(&mut changed.phase_filter, f, f.label());
                }
            });
            ui.end_row();
            row_label(ui, "Phase");
            let pname = changed.phase.and_then(|ph| p.phases.iter().find(|x| x.id == ph)).map(|x| x.name.clone()).unwrap_or_else(|| p.phases.last().map(|x| x.name.clone()).unwrap_or_default());
            egui::ComboBox::from_id_salt("vp-phase").selected_text(pname).icon(chevron).show_ui(ui, |ui| {
                for ph in &p.phases {
                    ui.selectable_value(&mut changed.phase, Some(ph.id), &ph.name);
                }
            });
            ui.end_row();
        });
    }
    if v.is_graphical() && !p.option_sets.is_empty() && section(ui, "Design Options") {
        prop_grid(ui, "view-options").show(ui, |ui| {
            for set in &p.option_sets {
                row_label(ui, &set.name);
                let cur = changed.options.get(&set.id).copied();
                let label = cur.and_then(|o| set.options.iter().find(|x| x.id == o)).map(|x| x.name.clone()).unwrap_or_else(|| "Automatic (primary)".into());
                let mut sel = cur;
                egui::ComboBox::from_id_salt(("vp-opt", set.id)).selected_text(label).icon(chevron).show_ui(ui, |ui| {
                    ui.selectable_value(&mut sel, None, "Automatic (primary)");
                    for o in &set.options {
                        ui.selectable_value(&mut sel, Some(o.id), &o.name);
                    }
                });
                if sel != cur {
                    match sel {
                        Some(o) => {
                            changed.options.insert(set.id, o);
                        }
                        None => {
                            changed.options.remove(&set.id);
                        }
                    }
                }
                ui.end_row();
            }
        });
    }
    if let ViewKind::Schedule(_) = v.kind {
        let mut which: Option<usize> = None;
        if section(ui, "Other") {
            prop_grid(ui, "view-sched").show(ui, |ui| {
                for (k, label) in ["Fields", "Filter", "Sorting/Grouping"].iter().enumerate() {
                    row_label(ui, label);
                    if edit_button(ui).clicked() {
                        which = Some(k);
                    }
                    ui.end_row();
                }
            });
        }
        if let Some(k) = which {
            app.dialogs.schedule_props = Some((vid, k));
        }
    }
    if open_vg {
        app.dialogs.vg = Some(vid);
    }
    if open_range {
        app.dialogs.view_range = Some(vid);
    }
    if format!("{changed:?}") != format!("{v:?}") {
        app.run("View Properties", |p| {
            if let Some(view) = p.view_mut(vid) {
                *view = changed;
            }
            Ok(())
        });
    }
}
