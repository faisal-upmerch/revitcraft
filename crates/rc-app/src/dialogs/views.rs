//! View dialogs: Visibility/Graphics, View Range, templates, plans, schedules, sheets.

use super::{PlanKind, window};
use crate::app::App;
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::edit;
use rc_core::model::*;

pub fn show(app: &mut App, ctx: &egui::Context) {
    vg(app, ctx);
    view_range(app, ctx);
    templates(app, ctx);
    new_plan(app, ctx);
    new_schedule(app, ctx);
    schedule_props(app, ctx);
    new_sheet(app, ctx);
    place_view(app, ctx);
    revisions(app, ctx);
    override_graphics(app, ctx);
}

fn update_view(app: &mut App, vid: Id, name: &str, v: View) {
    if let Some(cur) = app.doc.data.view(vid) {
        if format!("{cur:?}") != format!("{v:?}") {
            app.run(name, |p| {
                if let Some(x) = p.view_mut(vid) {
                    *x = v;
                }
                Ok(())
            });
        }
    }
}

fn color_override(ui: &mut egui::Ui, c: &mut Option<[u8; 3]>) {
    let mut on = c.is_some();
    ui.horizontal(|ui| {
        if ui.checkbox(&mut on, "").changed() {
            *c = if on { Some([200, 0, 0]) } else { None };
        }
        if let Some(col) = c.as_mut() {
            ui.color_edit_button_srgb(col);
        }
    });
}

fn vg(app: &mut App, ctx: &egui::Context) {
    let Some(vid) = app.dialogs.vg else { return };
    let Some(mut v) = app.doc.data.view(vid).cloned() else {
        app.dialogs.vg = None;
        return;
    };
    let mut open = true;
    window(&format!("Visibility/Graphic Overrides for {}: {}", v.type_label(), v.name)).open(&mut open).default_size(vec2(720.0, 520.0)).show(ctx, |ui| {
        let tab_id = egui::Id::new("vg-tab");
        let mut tab: u8 = ui.memory(|m| m.data.get_temp(tab_id)).unwrap_or(0);
        ui.horizontal(|ui| {
            ui.selectable_value(&mut tab, 0, "Model Categories");
            ui.selectable_value(&mut tab, 1, "Annotation Categories");
            ui.selectable_value(&mut tab, 2, "Imported Categories");
        });
        ui.memory_mut(|m| m.data.insert_temp(tab_id, tab));
        let cats: Vec<Category> = match tab {
            0 => Category::MODEL.to_vec(),
            1 => Category::ANNOTATION.iter().copied().filter(|c| *c != Category::ImportedCad).collect(),
            _ => vec![Category::ImportedCad],
        };
        ui.horizontal(|ui| {
            if ui.button("All").clicked() {
                v.hidden.retain(|c| !cats.contains(c));
            }
            if ui.button("None").clicked() {
                for c in &cats {
                    if !v.hidden.contains(c) {
                        v.hidden.push(*c);
                    }
                }
            }
        });
        egui::ScrollArea::vertical().max_height(400.0).show(ui, |ui| {
            egui::Grid::new("vg-grid").num_columns(6).striped(true).spacing(vec2(10.0, 3.0)).show(ui, |ui| {
                for h in ["Visibility", "Lines (color)", "Line weight", "Surface (color)", "Transparency", "Halftone"] {
                    ui.label(egui::RichText::new(h).strong());
                }
                ui.end_row();
                for c in cats {
                    let mut vis = !v.hidden.contains(&c);
                    if ui.checkbox(&mut vis, c.label()).changed() {
                        if vis {
                            v.hidden.retain(|x| *x != c);
                        } else {
                            v.hidden.push(c);
                        }
                    }
                    let idx = v.overrides.iter().position(|o| o.element.is_none() && o.category == Some(c));
                    let mut o = idx.map(|i| v.overrides[i].clone()).unwrap_or(GraphicOverride { category: Some(c), ..Default::default() });
                    color_override(ui, &mut o.line_color);
                    let mut w = o.line_weight.unwrap_or(0.0);
                    ui.add(egui::DragValue::new(&mut w).range(0.0..=2.0).speed(0.01).suffix(" mm"));
                    o.line_weight = (w > 0.0).then_some(w);
                    color_override(ui, &mut o.fill_color);
                    let mut t = o.transparency as f64;
                    ui.add(egui::DragValue::new(&mut t).range(0.0..=100.0).suffix(" %"));
                    o.transparency = t as u8;
                    ui.checkbox(&mut o.halftone, "");
                    ui.end_row();
                    let empty = o.line_color.is_none() && o.line_weight.is_none() && o.fill_color.is_none() && o.transparency == 0 && !o.halftone;
                    match (idx, empty) {
                        (Some(i), true) => {
                            v.overrides.remove(i);
                        }
                        (Some(i), false) => v.overrides[i] = o,
                        (None, false) => v.overrides.push(o),
                        _ => {}
                    }
                }
            });
        });
        ui.label(egui::RichText::new("Changes apply immediately (one undo step per change).").color(style::text_dim()));
    });
    update_view(app, vid, "Visibility/Graphics", v);
    if !open {
        app.dialogs.vg = None;
    }
}

fn view_range(app: &mut App, ctx: &egui::Context) {
    let Some(vid) = app.dialogs.view_range else { return };
    let Some(mut v) = app.doc.data.view(vid).cloned() else {
        app.dialogs.view_range = None;
        return;
    };
    let mut open = true;
    let units = app.doc.data.units.clone();
    window("View Range").open(&mut open).resizable(false).show(ctx, |ui| {
        let level = v.plan_level().map(|l| app.doc.data.level_name(l)).unwrap_or_default();
        ui.label(egui::RichText::new("Primary Range").strong());
        egui::Grid::new("vr").num_columns(3).spacing(vec2(10.0, 4.0)).show(ui, |ui| {
            for (label, val) in [("Top:", &mut v.view_range.top), ("Cut plane:", &mut v.view_range.cut), ("Bottom:", &mut v.view_range.bottom)] {
                ui.label(label);
                ui.label(format!("Associated Level ({level})"));
                let mut s = units.length(*val);
                if ui.add(egui::TextEdit::singleline(&mut s).desired_width(90.0)).lost_focus() {
                    if let Some(x) = units.parse(&s, ParamKind::Length) {
                        *val = x;
                    }
                }
                ui.end_row();
            }
            ui.label(egui::RichText::new("View Depth").strong());
            ui.end_row();
            ui.label("Level:");
            ui.label(format!("Associated Level ({level})"));
            let mut s = units.length(v.view_range.depth);
            if ui.add(egui::TextEdit::singleline(&mut s).desired_width(90.0)).lost_focus() {
                if let Some(x) = units.parse(&s, ParamKind::Length) {
                    v.view_range.depth = x;
                }
            }
            ui.end_row();
        });
        if v.view_range.cut > v.view_range.top || v.view_range.bottom > v.view_range.cut {
            ui.colored_label(style::ERROR, "The cut plane must lie between the bottom and the top.");
        }
    });
    if v.view_range.bottom <= v.view_range.cut && v.view_range.cut <= v.view_range.top {
        update_view(app, vid, "View Range", v);
    }
    if !open {
        app.dialogs.view_range = None;
    }
}

fn templates(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.view_templates {
        return;
    }
    let mut open = true;
    let mut apply: Option<Id> = None;
    let mut delete: Option<Id> = None;
    let mut create = false;
    window("View Templates").open(&mut open).default_size(vec2(520.0, 380.0)).show(ctx, |ui| {
        let key = egui::Id::new("vt-sel");
        let mut sel: Option<Id> = ui.memory(|m| m.data.get_temp(key));
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(200.0);
                ui.label(egui::RichText::new("Names:").strong());
                for t in app.doc.data.views.iter().filter(|t| t.is_template) {
                    if ui.selectable_label(sel == Some(t.id), &t.name).clicked() {
                        sel = Some(t.id);
                    }
                }
                ui.horizontal(|ui| {
                    if ui.button("From Active View").clicked() {
                        create = true;
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Delete")).clicked() {
                        delete = sel;
                    }
                });
            });
            ui.separator();
            ui.vertical(|ui| {
                if let Some(t) = sel.and_then(|s| app.doc.data.view(s)) {
                    egui::Grid::new("vt-props").num_columns(2).striped(true).show(ui, |ui| {
                        ui.label("View Scale");
                        ui.label(format!("1 : {}", t.scale));
                        ui.end_row();
                        ui.label("Detail Level");
                        ui.label(t.detail.label());
                        ui.end_row();
                        ui.label("Visual Style");
                        ui.label(t.style.label());
                        ui.end_row();
                        ui.label("Hidden categories");
                        ui.label(t.hidden.len().to_string());
                        ui.end_row();
                        ui.label("Overrides");
                        ui.label(t.overrides.len().to_string());
                        ui.end_row();
                        ui.label("Phase Filter");
                        ui.label(t.phase_filter.label());
                        ui.end_row();
                    });
                    if ui.button("Apply to Active View").clicked() {
                        apply = Some(t.id);
                    }
                } else {
                    ui.label("Select a template.");
                }
            });
        });
        ui.memory_mut(|m| match sel {
            Some(s) => {
                m.data.insert_temp(key, s);
            }
            None => {
                m.data.remove::<Id>(key);
            }
        });
    });
    if create {
        crate::actions::exec(app, crate::commands::Cmd::TemplateFromView);
    }
    if let (Some(t), Some(v)) = (apply, app.active) {
        app.run("Apply View Template", |p| edit::apply_template(p, v, t));
    }
    if let Some(t) = delete {
        app.run("Delete View Template", |p| edit::delete_view(p, t));
    }
    if !open {
        app.dialogs.view_templates = false;
    }
}

fn new_plan(app: &mut App, ctx: &egui::Context) {
    let Some(kind) = app.dialogs.new_plan else { return };
    let mut open = true;
    let mut ok = false;
    let title = match kind {
        PlanKind::Floor => "New Floor Plan",
        PlanKind::Ceiling => "New RCP",
        PlanKind::Area => "New Area Plan",
    };
    let key = egui::Id::new("area-scheme");
    window(title).open(&mut open).resizable(false).show(ctx, |ui| {
        if kind == PlanKind::Area {
            let mut scheme: Id = ui.memory(|m| m.data.get_temp(key)).unwrap_or(app.doc.data.area_schemes.first().map(|s| s.id).unwrap_or(0));
            ui.horizontal(|ui| {
                ui.label("Type:");
                let name = app.doc.data.area_schemes.iter().find(|s| s.id == scheme).map(|s| s.name.clone()).unwrap_or_default();
                egui::ComboBox::from_id_salt("scheme").selected_text(name).show_ui(ui, |ui| {
                    for s in &app.doc.data.area_schemes {
                        ui.selectable_value(&mut scheme, s.id, &s.name);
                    }
                });
            });
            ui.memory_mut(|m| m.data.insert_temp(key, scheme));
        }
        ui.label("Levels:");
        for (id, l) in app.doc.data.levels() {
            let mut on = app.dialogs.new_plan_sel.contains(&id);
            if ui.checkbox(&mut on, &l.name).changed() {
                if on {
                    app.dialogs.new_plan_sel.insert(id);
                } else {
                    app.dialogs.new_plan_sel.remove(&id);
                }
            }
        }
        if ui.button("OK").clicked() {
            ok = true;
        }
    });
    if ok {
        let levels: Vec<Id> = app.dialogs.new_plan_sel.iter().copied().collect();
        let scheme: Id = ctx.memory(|m| m.data.get_temp(key)).unwrap_or(app.doc.data.area_schemes.first().map(|s| s.id).unwrap_or(0));
        let created = app.run(title, |p| {
            let mut out = Vec::new();
            for l in &levels {
                out.push(match kind {
                    PlanKind::Floor => edit::new_floor_plan(p, *l)?,
                    PlanKind::Area => edit::new_area_plan(p, *l, scheme)?,
                    PlanKind::Ceiling => {
                        let id = p.new_id();
                        let name = edit::unique_name(p.views.iter().map(|v| v.name.clone()), &p.level_name(*l));
                        let scale = p.views.iter().find(|v| v.plan_level().is_some()).map(|v| v.scale).unwrap_or(100.0);
                        p.views.push(View::new(id, name, scale, ViewKind::CeilingPlan { level: *l }));
                        id
                    }
                });
            }
            Ok(out)
        });
        if let Some(v) = created.and_then(|v| v.last().copied()) {
            app.open_view(v);
        }
    }
    if !open || ok {
        app.dialogs.new_plan = None;
        app.dialogs.new_plan_sel.clear();
    }
}

fn new_schedule(app: &mut App, ctx: &egui::Context) {
    let Some(takeoff) = app.dialogs.new_schedule else { return };
    let mut open = true;
    let mut chosen: Option<Category> = None;
    window(if takeoff { "New Material Takeoff" } else { "New Schedule" }).open(&mut open).default_width(320.0).show(ctx, |ui| {
        ui.label("Category:");
        egui::ScrollArea::vertical().max_height(320.0).show(ui, |ui| {
            for c in Category::SCHEDULABLE {
                if ui.selectable_label(false, c.label()).clicked() {
                    chosen = Some(c);
                }
            }
        });
    });
    if let Some(c) = chosen {
        if let Some(id) = app.run("New Schedule", |p| Ok(if takeoff { edit::new_material_takeoff(p, c) } else { edit::new_schedule(p, c) })) {
            app.open_view(id);
            app.dialogs.schedule_props = Some((id, 0));
        }
    }
    if !open || chosen.is_some() {
        app.dialogs.new_schedule = None;
    }
}

fn schedule_props(app: &mut App, ctx: &egui::Context) {
    let Some((vid, mut tab)) = app.dialogs.schedule_props else { return };
    let Some(v) = app.doc.data.view(vid).cloned() else {
        app.dialogs.schedule_props = None;
        return;
    };
    let ViewKind::Schedule(mut def) = v.kind.clone() else { return };
    let mut open = true;
    let available = rc_core::schedule::available_fields(&app.doc.data, &def);
    window("Schedule Properties").open(&mut open).default_size(vec2(620.0, 460.0)).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.selectable_value(&mut tab, 0, "Fields");
            ui.selectable_value(&mut tab, 1, "Filter");
            ui.selectable_value(&mut tab, 2, "Sorting/Grouping");
        });
        ui.separator();
        match tab {
            0 => {
                ui.horizontal_top(|ui| {
                    ui.vertical(|ui| {
                        ui.set_width(250.0);
                        ui.label(egui::RichText::new("Available fields:").strong());
                        egui::ScrollArea::vertical().id_salt("avail").max_height(320.0).show(ui, |ui| {
                            for f in &available {
                                if def.fields.contains(&f.name) {
                                    continue;
                                }
                                if ui.selectable_label(false, format!("+  {}", f.name)).clicked() {
                                    def.fields.push(f.name.clone());
                                }
                            }
                        });
                    });
                    ui.separator();
                    ui.vertical(|ui| {
                        ui.label(egui::RichText::new("Scheduled fields (in order):").strong());
                        let mut action: Option<(usize, i32)> = None;
                        egui::ScrollArea::vertical().id_salt("sched").max_height(300.0).show(ui, |ui| {
                            for (k, f) in def.fields.iter().enumerate() {
                                ui.horizontal(|ui| {
                                    ui.label(f);
                                    if ui.small_button("▲").clicked() {
                                        action = Some((k, -1));
                                    }
                                    if ui.small_button("▼").clicked() {
                                        action = Some((k, 1));
                                    }
                                    if ui.small_button("Remove").clicked() {
                                        action = Some((k, 0));
                                    }
                                });
                            }
                        });
                        match action {
                            Some((k, 0)) => {
                                def.fields.remove(k);
                            }
                            Some((k, d)) => {
                                let j = (k as i32 + d).clamp(0, def.fields.len() as i32 - 1) as usize;
                                def.fields.swap(k, j);
                            }
                            None => {}
                        }
                        ui.separator();
                        ui.label(egui::RichText::new("Calculated value").strong());
                        let key = egui::Id::new(("calc", vid));
                        let mut st: (String, String) = ui.memory(|m| m.data.get_temp(key)).unwrap_or_default();
                        ui.horizontal(|ui| {
                            ui.label("Name:");
                            ui.add(egui::TextEdit::singleline(&mut st.0).desired_width(100.0));
                            ui.label("Formula:");
                            ui.add(egui::TextEdit::singleline(&mut st.1).desired_width(140.0));
                            if ui.button("Add").clicked() && !st.0.is_empty() && !st.1.is_empty() {
                                def.calculated.push(CalculatedField { name: st.0.clone(), formula: st.1.clone(), kind: ParamKind::Number });
                                def.fields.push(st.0.clone());
                                st = Default::default();
                            }
                        });
                        ui.memory_mut(|m| m.data.insert_temp(key, st));
                        ui.checkbox(&mut def.itemize, "Itemize every instance");
                        ui.checkbox(&mut def.grand_total, "Grand totals");
                    });
                });
            }
            1 => {
                let mut remove: Option<usize> = None;
                for (k, f) in def.filters.iter_mut().enumerate() {
                    ui.horizontal(|ui| {
                        egui::ComboBox::from_id_salt(("ff", k)).selected_text(&f.field).width(150.0).show_ui(ui, |ui| {
                            for a in &available {
                                ui.selectable_value(&mut f.field, a.name.clone(), &a.name);
                            }
                        });
                        egui::ComboBox::from_id_salt(("fo", k)).selected_text(f.op.label()).width(120.0).show_ui(ui, |ui| {
                            for o in FilterOp::ALL {
                                ui.selectable_value(&mut f.op, o, o.label());
                            }
                        });
                        ui.add(egui::TextEdit::singleline(&mut f.value).desired_width(120.0));
                        if ui.small_button("Remove").clicked() {
                            remove = Some(k);
                        }
                    });
                }
                if let Some(k) = remove {
                    def.filters.remove(k);
                }
                if ui.button("Add Filter").clicked() {
                    def.filters.push(ScheduleFilter { field: available.first().map(|f| f.name.clone()).unwrap_or_default(), op: FilterOp::Equals, value: String::new() });
                }
            }
            _ => {
                ui.horizontal(|ui| {
                    ui.label("Sort by:");
                    let cur = def.sort_by.first().cloned().unwrap_or_else(|| "(none)".into());
                    egui::ComboBox::from_id_salt("sort").selected_text(cur).width(180.0).show_ui(ui, |ui| {
                        if ui.selectable_label(def.sort_by.is_empty(), "(none)").clicked() {
                            def.sort_by.clear();
                        }
                        for f in def.fields.clone() {
                            if ui.selectable_label(def.sort_by.first() == Some(&f), &f).clicked() {
                                def.sort_by = vec![f];
                            }
                        }
                    });
                    ui.radio_value(&mut def.descending, false, "Ascending");
                    ui.radio_value(&mut def.descending, true, "Descending");
                });
                ui.checkbox(&mut def.group_headers, "Header and footer (group by the sort field)");
                ui.label("Totals for:");
                for f in def.fields.clone() {
                    let mut on = def.total_fields.contains(&f);
                    if ui.checkbox(&mut on, &f).changed() {
                        if on {
                            def.total_fields.push(f);
                        } else {
                            def.total_fields.retain(|x| *x != f);
                        }
                    }
                }
            }
        }
    });
    let mut nv = v.clone();
    nv.kind = ViewKind::Schedule(def);
    update_view(app, vid, "Schedule Properties", nv);
    app.dialogs.schedule_props = if open { Some((vid, tab)) } else { None };
}

fn new_sheet(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.new_sheet {
        return;
    }
    let mut open = true;
    let mut chosen: Option<SheetSize> = None;
    window("New Sheet").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.label("Select title block:");
        for s in SheetSize::ALL {
            if ui.selectable_label(false, format!("Title Block {}", s.label())).clicked() {
                chosen = Some(s);
            }
        }
    });
    if let Some(s) = chosen {
        if let Some(id) = app.run("New Sheet", |p| Ok(edit::new_sheet(p, s))) {
            app.open_view(id);
        }
    }
    if !open || chosen.is_some() {
        app.dialogs.new_sheet = false;
    }
}

fn place_view(app: &mut App, ctx: &egui::Context) {
    let Some(sheet) = app.dialogs.place_view else { return };
    let mut open = true;
    let mut chosen: Option<Id> = None;
    window("Views").open(&mut open).default_width(320.0).show(ctx, |ui| {
        ui.label("Select a view to place on the sheet:");
        egui::ScrollArea::vertical().max_height(360.0).show(ui, |ui| {
            for v in app.doc.data.views.iter().filter(|v| !v.is_template && !matches!(v.kind, ViewKind::Sheet(_))) {
                let placed = v.single_placement() && app.doc.data.sheet_containing(v.id).is_some();
                if ui.add_enabled(!placed, egui::Button::new(format!("{}: {}", v.type_label(), v.name)).frame(false)).clicked() {
                    chosen = Some(v.id);
                }
            }
        });
    });
    if let Some(v) = chosen {
        let (cx, cy) = match app.doc.data.view(sheet).map(|s| &s.kind) {
            Some(ViewKind::Sheet(s)) => {
                let (w, h) = s.size.paper();
                (w * 0.4, h * 0.55)
            }
            _ => (200.0, 150.0),
        };
        app.run("Place View", |p| edit::place_on_sheet(p, sheet, v, cx, cy));
    }
    if !open || chosen.is_some() {
        app.dialogs.place_view = None;
    }
}

fn revisions(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.revisions {
        return;
    }
    let mut open = true;
    let mut revs = app.doc.data.revisions.clone();
    let mut add = false;
    window("Sheet Issues/Revisions").open(&mut open).default_size(vec2(680.0, 300.0)).show(ctx, |ui| {
        egui::Grid::new("revs").num_columns(6).striped(true).spacing(vec2(8.0, 3.0)).show(ui, |ui| {
            for h in ["Seq.", "Date", "Description", "Issued To", "Issued By", "Issued"] {
                ui.label(egui::RichText::new(h).strong());
            }
            ui.end_row();
            for r in revs.iter_mut() {
                ui.label(r.sequence.to_string());
                ui.add(egui::TextEdit::singleline(&mut r.date).desired_width(90.0));
                ui.add(egui::TextEdit::singleline(&mut r.description).desired_width(200.0));
                ui.add(egui::TextEdit::singleline(&mut r.issued_to).desired_width(90.0));
                ui.add(egui::TextEdit::singleline(&mut r.issued_by).desired_width(90.0));
                ui.checkbox(&mut r.issued, "");
                ui.end_row();
            }
        });
        if ui.button("Add").clicked() {
            add = true;
        }
    });
    if add {
        app.run("Add Revision", |p| Ok(edit::add_revision(p, "Revision")));
    } else if format!("{revs:?}") != format!("{:?}", app.doc.data.revisions) {
        app.run("Revisions", |p| {
            p.revisions = revs;
            Ok(())
        });
    }
    if !open {
        app.dialogs.revisions = false;
    }
}

fn override_graphics(app: &mut App, ctx: &egui::Context) {
    let Some(vid) = app.dialogs.override_graphics else { return };
    let Some(mut v) = app.doc.data.view(vid).cloned() else {
        app.dialogs.override_graphics = None;
        return;
    };
    let ids = app.selection.clone();
    let mut open = true;
    let mut ok = false;
    let first = ids.first().and_then(|id| v.overrides.iter().find(|o| o.element == Some(*id)).cloned()).unwrap_or_default();
    let key = egui::Id::new(("ovr", vid));
    let mut o: GraphicOverride = ctx.memory(|m| m.data.get_temp(key)).unwrap_or(first);
    window("View-Specific Element Graphics").open(&mut open).resizable(false).show(ctx, |ui| {
        egui::Grid::new("ovr-grid").num_columns(2).spacing(vec2(8.0, 4.0)).show(ui, |ui| {
            ui.label("Projection lines color");
            color_override(ui, &mut o.line_color);
            ui.end_row();
            ui.label("Line weight");
            let mut w = o.line_weight.unwrap_or(0.0);
            ui.add(egui::DragValue::new(&mut w).range(0.0..=2.0).speed(0.01).suffix(" mm"));
            o.line_weight = (w > 0.0).then_some(w);
            ui.end_row();
            ui.label("Surface color");
            color_override(ui, &mut o.fill_color);
            ui.end_row();
            ui.label("Halftone");
            ui.checkbox(&mut o.halftone, "");
            ui.end_row();
            ui.label("Transparency");
            let mut t = o.transparency as f64;
            ui.add(egui::Slider::new(&mut t, 0.0..=100.0).suffix(" %"));
            o.transparency = t as u8;
            ui.end_row();
        });
        ui.horizontal(|ui| {
            if ui.button("OK").clicked() {
                ok = true;
            }
            if ui.button("Reset").clicked() {
                o = GraphicOverride::default();
            }
        });
    });
    ctx.memory_mut(|m| m.data.insert_temp(key, o.clone()));
    if ok {
        for id in &ids {
            v.overrides.retain(|x| x.element != Some(*id));
            let empty = o.line_color.is_none() && o.line_weight.is_none() && o.fill_color.is_none() && o.transparency == 0 && !o.halftone;
            if !empty {
                v.overrides.push(GraphicOverride { element: Some(*id), category: None, ..o.clone() });
            }
        }
        update_view(app, vid, "Override Graphics", v);
    }
    if ok || !open {
        app.dialogs.override_graphics = None;
        ctx.memory_mut(|m| m.data.remove::<GraphicOverride>(key));
    }
}
