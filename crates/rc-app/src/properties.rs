//! Properties palette: Type Selector, instance parameters of the selection, or the active
//! view's properties when nothing is selected.

use crate::app::App;
use crate::icons::{self, Icon};
use crate::style;
use crate::tools::{SketchKind, ToolKind};
use eframe::egui::{self, Rect, Sense, vec2};
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
        ToolKind::IsolatedFooting => (Category::StructuralFoundations, o.footing_type),
        ToolKind::WallFoundation => (Category::StructuralFoundations, o.foundation_type),
        ToolKind::Component => (app.doc.data.family_type(o.component_type).map(|(f, _)| f.category)?, o.component_type),
        ToolKind::SketchLine | ToolKind::Select if app.sketch.is_some() => match app.sketch.as_ref()?.kind {
            SketchKind::Floor { .. } | SketchKind::EditFloor(_) => (Category::Floors, o.floor_type),
            SketchKind::Ceiling | SketchKind::EditCeiling(_) => (Category::Ceilings, o.ceiling_type),
            SketchKind::Roof | SketchKind::RoofExtrusion | SketchKind::EditRoof(_) => (Category::Roofs, o.roof_type),
            SketchKind::Stair => (Category::Stairs, o.stair_type),
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
        Category::Railings => o.railing_type = t,
        _ => o.component_type = t,
    }
}

fn type_selector(app: &mut App, ui: &mut egui::Ui) {
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
        egui::Frame::new().inner_margin(egui::Margin::symmetric(8, 8)).show(ui, |ui| {
            ui.horizontal(|ui| {
                let (r, _) = ui.allocate_exact_size(vec2(36.0, 36.0), Sense::hover());
                icons::paint(ui.painter(), r, if app.selection.is_empty() { Icon::FloorPlan } else { Icon::Properties }, true);
                ui.label(egui::RichText::new(label).size(13.0).strong());
            });
        });
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
        Category::Railings => Icon::Railing,
        Category::Columns => Icon::Column,
        Category::StructuralColumns => Icon::StructColumn,
        Category::StructuralFraming => Icon::Beam,
        Category::StructuralFoundations => Icon::IsolatedFoundation,
        Category::Groups => Icon::PlaceGroup,
        _ => Icon::Component,
    };
    let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 52.0), Sense::click());
    let painter = ui.painter();
    painter.rect_filled(rect.shrink(4.0), 2.0, if resp.hovered() { style::hover() } else { style::field() });
    painter.rect_stroke(rect.shrink(4.0), 2.0, egui::Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
    icons::paint(painter, Rect::from_min_size(rect.min + vec2(10.0, 9.0), vec2(34.0, 34.0)), icon, true);
    painter.text(rect.min + vec2(52.0, 12.0), egui::Align2::LEFT_TOP, &fam, egui::FontId::proportional(12.5), style::text());
    painter.text(rect.min + vec2(52.0, 28.0), egui::Align2::LEFT_TOP, &ty, egui::FontId::proportional(12.0), style::text_dim());
    let c = rect.right_center() - vec2(16.0, 0.0);
    painter.add(egui::Shape::convex_polygon(vec![c + vec2(-4.0, -2.0), c + vec2(4.0, -2.0), c + vec2(0.0, 3.0)], style::text_dim(), egui::Stroke::NONE));
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

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    style::palette_title(ui, "Properties");
    type_selector(app, ui);
    ui.add_space(2.0);
    // Instance filter row + Edit Type.
    ui.horizontal(|ui| {
        ui.add_space(6.0);
        let label = filter_label(app);
        ui.label(egui::RichText::new(label).strong());
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.add_space(6.0);
            let t = selector_target(app).and_then(|(_, t)| t);
            if ui.add_enabled(t.is_some(), egui::Button::new("Edit Type")).clicked() {
                app.dialogs.type_props = t;
            }
        });
    });
    ui.separator();
    egui::ScrollArea::vertical().auto_shrink([false, false]).id_salt("props-scroll").show(ui, |ui| {
        ui.spacing_mut().indent = 6.0;
        egui::Frame::new().inner_margin(egui::Margin { left: 6, right: 4, top: 0, bottom: 0 }).show(ui, |ui| props_body(app, ui));
    });
}

fn props_body(app: &mut App, ui: &mut egui::Ui) {
    {
        let sel = app.selection.clone();
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

fn filter_label(app: &App) -> String {
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
    let p = app.doc.data.clone();
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
    for (g, defs) in groups {
        let open = group_open(ui, &g);
        if style::group_header_ui(ui, &g, open).clicked() {
            set_group_open(ui, &g, !open);
        }
        if !open {
            continue;
        }
        egui::Grid::new(("props", &g)).num_columns(2).striped(true).min_col_width(ui.available_width() * 0.45).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            for d in defs {
                let values: Vec<String> = elems.iter().map(|e| params::display(&p, e, &d)).collect();
                let same = values.iter().all(|v| *v == values[0]);
                let shown = if same { values[0].clone() } else { String::new() };
                ui.label(egui::RichText::new(&d.name).size(12.0));
                if let Some(v) = value_editor(ui, app, &d, &shown, ("elem", sel.first().copied().unwrap_or(0), d.name.clone())) {
                    edits.push((d.name.clone(), v));
                }
                ui.end_row();
            }
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
            if ui.checkbox(&mut b, "").changed() {
                return Some(if b { "Yes".into() } else { "No".into() });
            }
            None
        }
        PKind::Level => {
            let mut out = None;
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).show_ui(ui, |ui| {
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
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).show_ui(ui, |ui| {
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
            egui::ComboBox::from_id_salt(egui::Id::new(&key)).selected_text(shown).width(width - 8.0).show_ui(ui, |ui| {
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
    ui.label(egui::RichText::new(s).size(12.0));
}

fn view_properties(app: &mut App, ui: &mut egui::Ui, vid: Id) {
    let Some(v) = app.doc.data.view(vid).cloned() else { return };
    let mut changed = v.clone();
    let p = app.doc.data.clone();
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
        egui::Grid::new("view-graphics").num_columns(2).striped(true).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            if v.is_graphical() {
                row_label(ui, "View Scale");
                let mut s = changed.scale;
                ui.add(egui::DragValue::new(&mut s).range(1.0..=10000.0).prefix("1 : ").speed(1.0));
                changed.scale = s;
                ui.end_row();
                row_label(ui, "Detail Level");
                egui::ComboBox::from_id_salt("vp-detail").selected_text(changed.detail.label()).show_ui(ui, |ui| {
                    for d in DetailLevel::ALL {
                        ui.selectable_value(&mut changed.detail, d, d.label());
                    }
                });
                ui.end_row();
                row_label(ui, "Visibility/Graphics Overrides");
                if ui.button("Edit...").clicked() {
                    open_vg = true;
                }
                ui.end_row();
                row_label(ui, "Visual Style");
                egui::ComboBox::from_id_salt("vp-style").selected_text(changed.style.label()).show_ui(ui, |ui| {
                    for s in VisualStyle::ALL {
                        ui.selectable_value(&mut changed.style, s, s.label());
                    }
                });
                ui.end_row();
                row_label(ui, "Shadows");
                ui.checkbox(&mut changed.shadows, "");
                ui.end_row();
            }
            if let ViewKind::FloorPlan { room_colors, .. } = &mut changed.kind {
                row_label(ui, "Color Scheme (rooms)");
                ui.checkbox(room_colors, "");
                ui.end_row();
            }
            if v.plan_level().is_some() {
                row_label(ui, "Underlay");
                let label = changed.underlay.map(|l| p.level_name(l)).unwrap_or_else(|| "None".into());
                egui::ComboBox::from_id_salt("vp-underlay").selected_text(label).show_ui(ui, |ui| {
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
        egui::Grid::new("view-extents").num_columns(2).striped(true).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            if !matches!(v.kind, ViewKind::ThreeD { .. }) {
                row_label(ui, "Crop View");
                ui.checkbox(&mut changed.crop_active, "");
                ui.end_row();
                row_label(ui, "Crop Region Visible");
                ui.checkbox(&mut changed.crop_visible, "");
                ui.end_row();
            }
            if v.plan_level().is_some() {
                row_label(ui, "View Range");
                if ui.button("Edit...").clicked() {
                    open_range = true;
                }
                ui.end_row();
                row_label(ui, "Associated Level");
                ui.label(p.level_name(v.plan_level().unwrap()));
                ui.end_row();
            }
            if let ViewKind::ThreeD { .. } = v.kind {
                row_label(ui, "Section Box");
                let mut on = changed.section_box.is_some();
                if ui.checkbox(&mut on, "").changed() {
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
        egui::Grid::new("view-identity").num_columns(2).striped(true).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            row_label(ui, "View Template");
            let tname = changed.template.and_then(|t| p.view(t)).map(|t| t.name.clone()).unwrap_or_else(|| "<None>".into());
            egui::ComboBox::from_id_salt("vp-template").selected_text(tname).show_ui(ui, |ui| {
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
                egui::ComboBox::from_id_salt("sheet-size").selected_text(s.size.label()).show_ui(ui, |ui| {
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
        egui::Grid::new("view-phasing").num_columns(2).striped(true).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            row_label(ui, "Phase Filter");
            egui::ComboBox::from_id_salt("vp-pf").selected_text(changed.phase_filter.label()).show_ui(ui, |ui| {
                for f in PhaseFilter::ALL {
                    ui.selectable_value(&mut changed.phase_filter, f, f.label());
                }
            });
            ui.end_row();
            row_label(ui, "Phase");
            let pname = changed.phase.and_then(|ph| p.phases.iter().find(|x| x.id == ph)).map(|x| x.name.clone()).unwrap_or_else(|| p.phases.last().map(|x| x.name.clone()).unwrap_or_default());
            egui::ComboBox::from_id_salt("vp-phase").selected_text(pname).show_ui(ui, |ui| {
                for ph in &p.phases {
                    ui.selectable_value(&mut changed.phase, Some(ph.id), &ph.name);
                }
            });
            ui.end_row();
        });
    }
    if v.is_graphical() && !p.option_sets.is_empty() && section(ui, "Design Options") {
        egui::Grid::new("view-options").num_columns(2).striped(true).spacing(vec2(6.0, 2.0)).show(ui, |ui| {
            for set in &p.option_sets {
                row_label(ui, &set.name);
                let cur = changed.options.get(&set.id).copied();
                let label = cur.and_then(|o| set.options.iter().find(|x| x.id == o)).map(|x| x.name.clone()).unwrap_or_else(|| "Automatic (primary)".into());
                let mut sel = cur;
                egui::ComboBox::from_id_salt(("vp-opt", set.id)).selected_text(label).show_ui(ui, |ui| {
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
