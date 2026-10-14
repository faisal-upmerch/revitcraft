//! Project Parameters, view Filters, Line Styles, saved selections and Find/Replace.

use super::{Footer, dlg_button, footer, session_begin, session_cancel, window};
use crate::app::App;
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::model::*;
use rc_core::params;
use rc_core::plan::{self, Dash};

pub fn show(app: &mut App, ctx: &egui::Context) {
    project_params(app, ctx);
    param_edit(app, ctx);
    filters(app, ctx);
    line_styles(app, ctx);
    save_selection(app, ctx);
    selection_sets(app, ctx);
    find_replace(app, ctx);
}

/// Properties groups a project parameter can be listed under.
const GROUPS: [&str; 10] = [
    "Constraints",
    "Construction",
    "Dimensions",
    "Graphics",
    "Identity Data",
    "Materials and Finishes",
    "Other",
    "Phasing",
    "Structural",
    "Text",
];

/// A titled group box (thin border, title above).
fn group<R>(ui: &mut egui::Ui, title: &str, add: impl FnOnce(&mut egui::Ui) -> R) -> R {
    ui.label(egui::RichText::new(title).size(12.0));
    egui::Frame::new()
        .stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(200)))
        .inner_margin(egui::Margin::same(8))
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            add(ui)
        })
        .inner
}

/// A left-aligned list row with the selection highlight.
fn list_row(ui: &mut egui::Ui, width: f32, selected: bool, text: impl Into<String>) -> egui::Response {
    let (r, resp) = ui.allocate_exact_size(vec2(width, 19.0), egui::Sense::click());
    if selected {
        ui.painter().rect_filled(r, 0.0, style::accent_light());
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 0.0, style::hover());
    }
    ui.painter().text(r.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, text.into(), style::font(12.0), style::text());
    resp
}

/// A white list box with a border.
fn list_box<R>(ui: &mut egui::Ui, salt: &str, size: egui::Vec2, add: impl FnOnce(&mut egui::Ui) -> R) -> R {
    egui::Frame::new()
        .fill(style::field())
        .stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(170)))
        .inner_margin(egui::Margin::same(2))
        .show(ui, |ui| {
            ui.set_min_size(size);
            ui.set_max_width(size.x);
            egui::ScrollArea::vertical().id_salt(salt).max_height(size.y).auto_shrink([false, false]).show(ui, add).inner
        })
        .inner
}

// ---------------------------------------------------------------- project parameters

fn project_params(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.project_params {
        return;
    }
    let mut open = true;
    let mut out = Footer::None;
    session_begin(app, "project-params");
    let sel_id = egui::Id::new("pp-sel");
    let list = app.doc.data.project_params.clone();
    window("Project Parameters").open(&mut open).resizable(false).show(ctx, |ui| {
        let mut sel: Option<usize> = ui.memory(|m| m.data.get_temp::<Option<usize>>(sel_id)).flatten().filter(|k| *k < list.len());
        ui.label("Parameters available to elements in this project:");
        ui.add_space(2.0);
        ui.horizontal_top(|ui| {
            list_box(ui, "lb0", vec2(270.0, 250.0), |ui| {
                for (k, q) in list.iter().enumerate() {
                    let r = list_row(ui, 262.0, sel == Some(k), q.name.clone());
                    if r.clicked() {
                        sel = Some(k);
                    }
                    if r.double_clicked() {
                        app.dialogs.param_edit = Some((Some(k), q.clone()));
                    }
                }
            });
            ui.vertical(|ui| {
                ui.spacing_mut().item_spacing.y = 6.0;
                if dlg_button(ui, "Add...", false, true) {
                    app.dialogs.param_edit = Some((None, ProjectParameter { kind: ParamKind::Text, group: "Identity Data".into(), instance: true, ..Default::default() }));
                }
                if dlg_button(ui, "Modify...", false, sel.is_some()) {
                    let k = sel.unwrap();
                    app.dialogs.param_edit = Some((Some(k), list[k].clone()));
                }
                if dlg_button(ui, "Remove", false, sel.is_some()) {
                    let k = sel.unwrap();
                    app.run("Remove Project Parameter", |p| {
                        let q = p.project_params.remove(k);
                        for e in p.elements.iter_mut() {
                            e.params.remove(&q.name);
                        }
                        for t in p.types.iter_mut() {
                            t.texts.remove(&q.name);
                        }
                        for f in p.families.iter_mut() {
                            if f.params.iter().any(|fp| fp.name == q.name) {
                                continue;
                            }
                            for ft in f.types.iter_mut() {
                                ft.values.remove(&q.name);
                            }
                        }
                        Ok(())
                    });
                    sel = None;
                }
            });
        });
        ui.memory_mut(|m| m.data.insert_temp(sel_id, sel));
        out = footer(ui, app, "project-params", "Project Parameters");
    });
    if out != Footer::None {
        open = false;
    } else if !open {
        session_cancel(app, "project-params");
    }
    if !open {
        app.dialogs.project_params = false;
        app.dialogs.param_edit = None;
    }
}

fn param_edit(app: &mut App, ctx: &egui::Context) {
    let Some((idx, mut q)) = app.dialogs.param_edit.clone() else { return };
    let mut open = true;
    let mut ok = false;
    let mut cancel = false;
    let filter_id = egui::Id::new("pp-cat-filter");
    window("Parameter Properties").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(300.0);
                group(ui, "Parameter Type", |ui| {
                    let _ = ui.radio(true, "Project parameter");
                    ui.label(egui::RichText::new("(Can appear in schedules but not in tags)").size(11.0).color(style::text_dim()));
                    ui.add_enabled(false, egui::RadioButton::new(false, "Shared parameter"));
                });
                ui.add_space(6.0);
                group(ui, "Parameter Data", |ui| {
                    egui::Grid::new("pp-data").num_columns(2).spacing(vec2(8.0, 6.0)).show(ui, |ui| {
                        ui.label("Name:");
                        ui.add(egui::TextEdit::singleline(&mut q.name).desired_width(180.0));
                        ui.end_row();
                        ui.label("Type of Parameter:");
                        egui::ComboBox::from_id_salt("pp-kind").selected_text(q.kind.label()).width(180.0).show_ui(ui, |ui| {
                            for k in ParamKind::USER {
                                ui.selectable_value(&mut q.kind, k, k.label());
                            }
                        });
                        ui.end_row();
                        ui.label("Group parameter under:");
                        egui::ComboBox::from_id_salt("pp-group").selected_text(q.group.as_str()).width(180.0).show_ui(ui, |ui| {
                            for g in GROUPS {
                                ui.selectable_value(&mut q.group, g.to_string(), g);
                            }
                        });
                        ui.end_row();
                    });
                    ui.add_space(4.0);
                    ui.horizontal(|ui| {
                        if ui.radio(!q.instance, "Type").clicked() {
                            q.instance = false;
                        }
                        if ui.radio(q.instance, "Instance").clicked() {
                            q.instance = true;
                        }
                    });
                });
            });
            ui.add_space(10.0);
            ui.vertical(|ui| {
                ui.set_width(260.0);
                ui.label("Categories");
                let mut filter: String = ui.memory(|m| m.data.get_temp(filter_id)).unwrap_or_default();
                ui.horizontal(|ui| {
                    ui.label("Filter list:");
                    ui.add(egui::TextEdit::singleline(&mut filter).desired_width(170.0).hint_text("Type to filter"));
                });
                ui.memory_mut(|m| m.data.insert_temp(filter_id, filter.clone()));
                let shown: Vec<Category> = Category::MODEL.iter().copied().filter(|c| filter.is_empty() || c.label().to_lowercase().contains(&filter.to_lowercase())).collect();
                list_box(ui, "lb1", vec2(250.0, 250.0), |ui| {
                    for c in &shown {
                        let mut on = q.categories.contains(c);
                        if ui.checkbox(&mut on, c.label()).changed() {
                            if on {
                                q.categories.push(*c);
                            } else {
                                q.categories.retain(|x| x != c);
                            }
                        }
                    }
                });
                ui.horizontal(|ui| {
                    if dlg_button(ui, "Check All", false, true) {
                        for c in &shown {
                            if !q.categories.contains(c) {
                                q.categories.push(*c);
                            }
                        }
                    }
                    if dlg_button(ui, "Check None", false, true) {
                        q.categories.retain(|c| !shown.contains(c));
                    }
                });
            });
        });
        ui.add_space(8.0);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        q.name = q.name.trim().to_string();
        let p = &app.doc.data;
        let old = idx.map(|k| p.project_params[k].name.clone());
        let clash = q.categories.iter().any(|c| {
            params::category_fields(p, *c).iter().any(|d| d.name == q.name && p.project_param(*c, &d.name).is_none())
        });
        let err = if q.name.is_empty() {
            Some("Enter a parameter name.")
        } else if q.categories.is_empty() {
            Some("Select at least one category.")
        } else if p.project_params.iter().enumerate().any(|(k, x)| x.name == q.name && Some(k) != idx) {
            Some("A project parameter with this name already exists.")
        } else if clash {
            Some("A built-in parameter of one of these categories already has this name.")
        } else {
            None
        };
        if let Some(e) = err {
            app.error(e);
        } else {
            let q2 = q.clone();
            app.run("Project Parameter", |p| {
                match idx {
                    Some(k) => {
                        if let Some(old) = old.filter(|o| *o != q2.name) {
                            for e in p.elements.iter_mut() {
                                if let Some(v) = e.params.remove(&old) {
                                    e.params.insert(q2.name.clone(), v);
                                }
                            }
                            for t in p.types.iter_mut() {
                                if let Some(v) = t.texts.remove(&old) {
                                    t.texts.insert(q2.name.clone(), v);
                                }
                            }
                        }
                        p.project_params[k] = q2;
                    }
                    None => p.project_params.push(q2),
                }
                Ok(())
            });
            app.dialogs.param_edit = None;
        }
        return;
    }
    app.dialogs.param_edit = if open && !cancel { Some((idx, q)) } else { None };
}

// ---------------------------------------------------------------- view filters

/// Parameter names common to all the given categories (for filter rules).
fn common_params(p: &Project, cats: &[Category]) -> Vec<String> {
    let mut out: Option<Vec<String>> = None;
    for c in cats {
        let names: Vec<String> = params::category_fields(p, *c).into_iter().map(|d| d.name).filter(|n| n != "Count").collect();
        out = Some(match out {
            None => names,
            Some(prev) => prev.into_iter().filter(|n| names.contains(n)).collect(),
        });
    }
    out.unwrap_or_default()
}

fn filters(app: &mut App, ctx: &egui::Context) {
    let Some(mut sel) = app.dialogs.filters else { return };
    let mut open = true;
    let mut out = Footer::None;
    session_begin(app, "filters");
    let mut list = app.doc.data.filters.clone();
    if sel.is_none_or(|id| !list.iter().any(|f| f.id == id)) {
        sel = list.first().map(|f| f.id);
    }
    let rename_id = egui::Id::new("filters-rename");
    let hide_id = egui::Id::new("filters-hide-unchecked");
    window("Filters").open(&mut open).resizable(false).show(ctx, |ui| {
        let mut renaming: Option<String> = ui.memory(|m| m.data.get_temp(rename_id));
        ui.horizontal_top(|ui| {
            // Filter list.
            ui.vertical(|ui| {
                ui.set_width(210.0);
                ui.label("Filters");
                list_box(ui, "lb2", vec2(206.0, 330.0), |ui| {
                    ui.label(egui::RichText::new("Rule-based Filters").strong().size(11.5));
                    for f in list.iter_mut() {
                        let on = sel == Some(f.id);
                        if on && renaming.is_some() {
                            let buf = renaming.as_mut().unwrap();
                            let r = ui.add(egui::TextEdit::singleline(buf).desired_width(190.0));
                            r.request_focus();
                            if ui.input(|i| i.key_pressed(egui::Key::Enter)) || r.lost_focus() {
                                let name = buf.trim().to_string();
                                if !name.is_empty() {
                                    f.name = name;
                                }
                                renaming = None;
                            }
                        } else if list_row(ui, 200.0, on, format!("   {}", f.name)).clicked() {
                            sel = Some(f.id);
                            renaming = None;
                        }
                    }
                });
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 4.0;
                    if ui.small_button("New").on_hover_text("New filter").clicked() {
                        let n = (1..).find(|k| !list.iter().any(|f| f.name == format!("Filter {k}"))).unwrap();
                        let name = format!("Filter {n}");
                        if let Some(id) = app.run("New Filter", |p| {
                            let id = p.new_id();
                            p.filters.push(ViewFilter { id, name: name.clone(), ..Default::default() });
                            Ok(id)
                        }) {
                            list = app.doc.data.filters.clone();
                            sel = Some(id);
                            renaming = Some(name);
                        }
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Duplicate").small()).clicked() {
                        if let Some(src) = list.iter().find(|f| Some(f.id) == sel).cloned() {
                            if let Some(id) = app.run("Duplicate Filter", |p| {
                                let id = p.new_id();
                                p.filters = list.clone();
                                p.filters.push(ViewFilter { id, name: format!("{} (1)", src.name), ..src });
                                Ok(id)
                            }) {
                                list = app.doc.data.filters.clone();
                                sel = Some(id);
                            }
                        }
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Rename").small()).clicked() {
                        renaming = list.iter().find(|f| Some(f.id) == sel).map(|f| f.name.clone());
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Delete").small()).clicked() {
                        list.retain(|f| Some(f.id) != sel);
                        sel = list.first().map(|f| f.id);
                        renaming = None;
                    }
                });
            });
            ui.add_space(8.0);
            let Some(fi) = list.iter().position(|f| Some(f.id) == sel) else {
                ui.label(egui::RichText::new("Click New to create a filter.").color(style::text_dim()));
                return;
            };
            // Categories.
            ui.vertical(|ui| {
                ui.set_width(250.0);
                ui.label("Categories");
                ui.label(egui::RichText::new("Select one or more categories to be included in the filter. Parameters common to these categories will be available for defining filter rules.").size(11.0).color(style::text_dim()));
                let mut hide: bool = ui.memory(|m| m.data.get_temp(hide_id)).unwrap_or(false);
                ui.checkbox(&mut hide, "Hide un-checked categories");
                ui.memory_mut(|m| m.data.insert_temp(hide_id, hide));
                let f = &mut list[fi];
                list_box(ui, "lb3", vec2(246.0, 236.0), |ui| {
                    for c in Category::MODEL {
                        let mut on = f.categories.contains(&c);
                        if hide && !on {
                            continue;
                        }
                        if ui.checkbox(&mut on, c.label()).changed() {
                            if on {
                                f.categories.push(c);
                            } else {
                                f.categories.retain(|x| *x != c);
                            }
                        }
                    }
                });
                ui.horizontal(|ui| {
                    if dlg_button(ui, "Check All", false, true) {
                        f.categories = Category::MODEL.to_vec();
                    }
                    if dlg_button(ui, "Check None", false, true) {
                        f.categories.clear();
                    }
                });
            });
            ui.add_space(8.0);
            // Rules.
            let available = common_params(&app.doc.data, &list[fi].categories);
            let f = &mut list[fi];
            ui.vertical(|ui| {
                ui.set_width(420.0);
                ui.label("Filter Rules");
                egui::Frame::new().stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(200))).inner_margin(egui::Margin::same(8)).show(ui, |ui| {
                    ui.set_min_size(vec2(404.0, 300.0));
                    if f.categories.is_empty() {
                        ui.label(egui::RichText::new("Select categories to define rules.").color(style::text_dim()));
                        return;
                    }
                    let label = |any: bool| if any { "OR (Any rule must be true)" } else { "AND (All rules must be true)" };
                    egui::ComboBox::from_id_salt("filter-andor").selected_text(label(f.any)).width(220.0).show_ui(ui, |ui| {
                        ui.selectable_value(&mut f.any, false, label(false));
                        ui.selectable_value(&mut f.any, true, label(true));
                    });
                    ui.add_space(4.0);
                    let mut remove = None;
                    for (k, r) in f.rules.iter_mut().enumerate() {
                        ui.horizontal(|ui| {
                            ui.add_space(14.0);
                            egui::ComboBox::from_id_salt(("filter-param", k)).selected_text(r.param.as_str()).width(130.0).show_ui(ui, |ui| {
                                for n in &available {
                                    ui.selectable_value(&mut r.param, n.clone(), n);
                                }
                            });
                            egui::ComboBox::from_id_salt(("filter-op", k)).selected_text(r.op.label()).width(120.0).show_ui(ui, |ui| {
                                for o in FilterOp::ALL {
                                    ui.selectable_value(&mut r.op, o, o.label());
                                }
                            });
                            ui.add_enabled(!r.op.unary(), egui::TextEdit::singleline(&mut r.value).desired_width(80.0));
                            if ui.small_button("Ã—").on_hover_text("Delete rule").clicked() {
                                remove = Some(k);
                            }
                        });
                    }
                    if let Some(k) = remove {
                        f.rules.remove(k);
                    }
                    ui.add_space(4.0);
                    if ui.button("Add Rule").clicked() {
                        f.rules.push(FilterRule { param: available.first().cloned().unwrap_or_default(), op: FilterOp::Equals, value: String::new() });
                    }
                });
            });
        });
        ui.memory_mut(|m| match &renaming {
            Some(r) => {
 m.data.insert_temp(rename_id, r.clone());
 }
            None => m.data.remove::<String>(rename_id),
        });
        out = footer(ui, app, "filters", "Filters");
    });
    if out == Footer::None && open && list != app.doc.data.filters {
        app.run("Filters", |p| {
            p.filters = list;
            // Views drop the rows of deleted filters.
            let ids: Vec<Id> = p.filters.iter().map(|f| f.id).collect();
            for v in p.views.iter_mut() {
                v.overrides.retain(|o| o.filter.is_none_or(|f| ids.contains(&f)));
            }
            Ok(())
        });
    }
    if out != Footer::None {
        open = false;
    } else if !open {
        session_cancel(app, "filters");
    }
    app.dialogs.filters = if open { Some(sel) } else { None };
}

// ---------------------------------------------------------------- line styles

const PENS: [f32; 8] = [0.1, 0.13, 0.18, 0.25, 0.35, 0.5, 0.7, 1.0];

fn pen_label(w: f32) -> String {
    match PENS.iter().position(|p| (p - w).abs() < 1e-4) {
        Some(i) => format!("{}", i + 1),
        None => format!("{w} mm"),
    }
}

fn pattern_label(p: u8) -> &'static str {
    match p {
        1 => "Dash",
        2 => "Dash dot",
        3 => "Dot",
        _ => "Solid",
    }
}

fn def_of(p: &Project, s: LineStyle) -> LineStyleDef {
    if let LineStyle::Custom(k) = s {
        if let Some(d) = p.line_styles.get(k as usize) {
            return d.clone();
        }
    }
    if let Some(d) = p.builtin_line_styles.get(s.label()) {
        return d.clone();
    }
    let st = plan::builtin_line_stroke(s);
    let pattern = match st.dash {
        Dash::Solid => 0,
        Dash::Dashed => 1,
        Dash::DashDot => 2,
        Dash::Dotted => 3,
    };
    LineStyleDef { name: s.label().to_string(), weight: st.width, color: st.color, pattern }
}

fn line_styles(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.line_styles {
        return;
    }
    let mut open = true;
    let mut out = Footer::None;
    session_begin(app, "line-styles");
    let p0 = app.doc.data.clone();
    let mut customs = p0.line_styles.clone();
    let mut builtins = p0.builtin_line_styles.clone();
    let sel_id = egui::Id::new("ls-sel");
    let search_id = egui::Id::new("ls-search");
    let exp_id = egui::Id::new("ls-expanded");
    let new_id = egui::Id::new("ls-new");
    let mut delete: Option<u16> = None;
    window("Line Styles").open(&mut open).resizable(false).show(ctx, |ui| {
        let mut sel: Option<String> = ui.memory(|m| m.data.get_temp(sel_id));
        let mut search: String = ui.memory(|m| m.data.get_temp(search_id)).unwrap_or_default();
        let mut expanded: bool = ui.memory(|m| m.data.get_temp(exp_id)).unwrap_or(true);
        let mut new_name: Option<String> = ui.memory(|m| m.data.get_temp(new_id));
        ui.horizontal(|ui| {
            ui.label("Category name search:");
            ui.add(egui::TextEdit::singleline(&mut search).desired_width(160.0));
        });
        ui.add_space(4.0);
        let widths = [210.0, 110.0, 130.0, 120.0];
        let total: f32 = widths.iter().sum();
        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(170))).show(ui, |ui| {
            ui.set_width(total);
            {
                let (r, _) = ui.allocate_exact_size(vec2(total, 21.0), egui::Sense::hover());
                let p = ui.painter();
                p.rect_filled(r, 0.0, egui::Color32::from_rgb(246, 246, 246));
                p.line_segment([r.left_bottom(), r.right_bottom()], egui::Stroke::new(1.0, egui::Color32::from_gray(190)));
                let mut x = r.left();
                for (k, h) in ["Category", "Line Weight", "Line Color", "Line Pattern"].iter().enumerate() {
                    p.text(egui::pos2(x + widths[k] / 2.0, r.center().y), egui::Align2::CENTER_CENTER, *h, style::font(12.0), style::text());
                    x += widths[k];
                    if k < 3 {
                        p.line_segment([egui::pos2(x, r.top()), egui::pos2(x, r.bottom())], egui::Stroke::new(1.0, egui::Color32::from_gray(200)));
                    }
                }
            }
            egui::ScrollArea::vertical().max_height(300.0).auto_shrink([false, true]).show(ui, |ui| {
                ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                    let (r, resp) = ui.allocate_exact_size(vec2(total, 20.0), egui::Sense::click());
                    ui.painter().text(r.left_center() + vec2(6.0, 0.0), egui::Align2::LEFT_CENTER, if expanded { "âŠŸ  Lines" } else { "âŠž  Lines" }, style::font(12.0), style::text());
                    if resp.clicked() {
                        expanded = !expanded;
                    }
                });
                if !expanded {
                    return;
                }
                let mut rows: Vec<LineStyle> = p0.all_line_styles();
                rows.sort_by_key(|s| match s {
                    LineStyle::Custom(k) => customs.get(*k as usize).map(|d| d.name.to_lowercase()).unwrap_or_default(),
                    other => other.label().trim_start_matches('<').to_lowercase(),
                });
                for s in rows {
                    let mut d = match s {
                        LineStyle::Custom(k) => customs[k as usize].clone(),
                        other => builtins.get(other.label()).cloned().unwrap_or_else(|| def_of(&p0, other)),
                    };
                    if !search.is_empty() && !d.name.to_lowercase().contains(&search.to_lowercase()) {
                        continue;
                    }
                    let before = d.clone();
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                        let on = sel.as_deref() == Some(d.name.as_str());
                        let (r, resp) = ui.allocate_exact_size(vec2(widths[0], 20.0), egui::Sense::click());
                        if on {
                            ui.painter().rect_filled(r, 0.0, style::accent_light());
                        }
                        ui.painter().text(r.left_center() + vec2(26.0, 0.0), egui::Align2::LEFT_CENTER, &d.name, style::font(12.0), style::text());
                        if resp.clicked() {
                            sel = Some(d.name.clone());
                        }
                        let cell = |ui: &mut egui::Ui, w: f32, add: &mut dyn FnMut(&mut egui::Ui)| {
                            let (r, _) = ui.allocate_exact_size(vec2(w, 20.0), egui::Sense::hover());
                            ui.painter().line_segment([r.left_top(), r.left_bottom()], egui::Stroke::new(1.0, egui::Color32::from_gray(215)));
                            let mut child = ui.new_child(egui::UiBuilder::new().max_rect(r.shrink2(vec2(4.0, 1.0))).layout(egui::Layout::left_to_right(egui::Align::Center)));
                            add(&mut child);
                        };
                        cell(ui, widths[1], &mut |ui| {
                            egui::ComboBox::from_id_salt(("ls-w", d.name.clone())).selected_text(pen_label(d.weight)).width(90.0).show_ui(ui, |ui| {
                                for p in PENS {
                                    ui.selectable_value(&mut d.weight, p, format!("{} ({p} mm)", pen_label(p)));
                                }
                            });
                        });
                        cell(ui, widths[2], &mut |ui| {
                            ui.color_edit_button_srgb(&mut d.color);
                            ui.label(egui::RichText::new(format!(" RGB {:03}-{:03}-{:03}", d.color[0], d.color[1], d.color[2])).size(11.0));
                        });
                        cell(ui, widths[3], &mut |ui| {
                            egui::ComboBox::from_id_salt(("ls-p", d.name.clone())).selected_text(pattern_label(d.pattern)).width(100.0).show_ui(ui, |ui| {
                                for k in 0..4u8 {
                                    ui.selectable_value(&mut d.pattern, k, pattern_label(k));
                                }
                            });
                        });
                    });
                    if d != before {
                        match s {
                            LineStyle::Custom(k) => customs[k as usize] = d,
                            other => {
                                builtins.insert(other.label().to_string(), d);
                            }
                        }
                    }
                }
            });
        });
        ui.add_space(6.0);
        let sel_custom = sel.as_ref().and_then(|n| customs.iter().position(|d| &d.name == n));
        let old_id = egui::Id::new("ls-old");
        let mut rename_old: Option<String> = ui.memory(|m| m.data.get_temp(old_id));
        group(ui, "Modify Subcategories", |ui| {
            ui.horizontal(|ui| {
                if dlg_button(ui, "New", false, new_name.is_none()) {
                    new_name = Some(String::new());
                    rename_old = None;
                }
                if dlg_button(ui, "Delete", false, sel_custom.is_some()) {
                    delete = sel_custom.map(|k| k as u16);
                    sel = None;
                }
                if dlg_button(ui, "Rename", false, sel_custom.is_some()) {
                    new_name = sel.clone();
                    rename_old = sel.clone();
                }
            });
            let mut done = false;
            let mut cancelled = false;
            if let Some(text) = new_name.as_mut() {
                ui.add_space(4.0);
                ui.horizontal(|ui| {
                    ui.label(if rename_old.is_some() { "New name:" } else { "Name (subcategory of Lines):" });
                    let r = ui.add(egui::TextEdit::singleline(text).desired_width(160.0));
                    if ui.button("OK").clicked() || (r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter))) {
                        done = true;
                    }
                    if ui.button("Cancel").clicked() {
                        cancelled = true;
                    }
                });
            }
            if cancelled {
                done = false;
                rename_old = None;
                new_name = None;
            }
            if done {
                let name = new_name.clone().unwrap_or_default().trim().to_string();
                let taken = rename_old.as_deref() != Some(name.as_str())
                    && (p0.all_line_styles().iter().any(|s| p0.line_style_name(*s) == name) || customs.iter().any(|d| d.name == name));
                if name.is_empty() || taken {
                    app.error("Enter a name that is not used by another line style.");
                } else {
                    match rename_old.take() {
                        Some(old) => {
                            if let Some(d) = customs.iter_mut().find(|d| d.name == old) {
                                d.name = name.clone();
                            }
                        }
                        None => customs.push(LineStyleDef { name: name.clone(), weight: 0.13, color: [0, 0, 0], pattern: 0 }),
                    }
                    sel = Some(name);
                    new_name = None;
                }
            }
        });
        ui.memory_mut(|m| match &rename_old {
            Some(o) => {
                m.data.insert_temp(old_id, o.clone());
            }
            None => m.data.remove::<String>(old_id),
        });
        ui.memory_mut(|m| {
            match &sel {
                Some(s) => {
 m.data.insert_temp(sel_id, s.clone());
 }
                None => m.data.remove::<String>(sel_id),
            }
            m.data.insert_temp(search_id, search.clone());
            m.data.insert_temp(exp_id, expanded);
            match &new_name {
                Some(s) => {
 m.data.insert_temp(new_id, s.clone());
 }
                None => m.data.remove::<String>(new_id),
            }
        });
        out = footer(ui, app, "line-styles", "Line Styles");
    });
    if out == Footer::None && open {
        if let Some(k) = delete {
            app.run("Delete Line Style", |p| {
                p.line_styles.remove(k as usize);
                let fix = |s: &mut LineStyle| {
                    if let LineStyle::Custom(j) = *s {
                        if j == k {
                            *s = LineStyle::Thin;
                        } else if j > k {
                            *s = LineStyle::Custom(j - 1);
                        }
                    }
                };
                for e in p.elements.iter_mut() {
                    match &mut e.kind {
                        ElementKind::Line(l) => fix(&mut l.style),
                        ElementKind::Region(r) => fix(&mut r.boundary_style),
                        _ => {}
                    }
                }
                Ok(())
            });
        } else if customs != app.doc.data.line_styles || builtins != app.doc.data.builtin_line_styles {
            app.run("Line Styles", |p| {
                p.line_styles = customs;
                p.builtin_line_styles = builtins;
                Ok(())
            });
        }
    }
    if out != Footer::None {
        open = false;
    } else if !open {
        session_cancel(app, "line-styles");
    }
    if !open {
        app.dialogs.line_styles = false;
    }
}

// ---------------------------------------------------------------- saved selections

fn save_selection(app: &mut App, ctx: &egui::Context) {
    let Some(mut name) = app.dialogs.save_selection.clone() else { return };
    let mut open = true;
    let mut ok = false;
    let mut cancel = false;
    window("Save Selection").open(&mut open).resizable(false).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Name:");
            let r = ui.add(egui::TextEdit::singleline(&mut name).desired_width(220.0));
            if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                ok = true;
            }
        });
        ui.add_space(8.0);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Cancel", false, true) {
                cancel = true;
            }
            if dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        let name = name.trim().to_string();
        if name.is_empty() {
            app.error("Enter a name for the selection.");
            return;
        }
        let ids = app.selection.clone();
        app.run("Save Selection", |p| {
            p.selection_sets.retain(|s| s.name != name);
            p.selection_sets.push(SelectionSet { name, ids });
            Ok(())
        });
        app.dialogs.save_selection = None;
        return;
    }
    app.dialogs.save_selection = if open && !cancel { Some(name) } else { None };
}

fn selection_sets(app: &mut App, ctx: &egui::Context) {
    let Some(edit) = app.dialogs.selection_sets else { return };
    let mut open = true;
    let mut close = false;
    let sel_id = egui::Id::new("selsets-sel");
    let ren_id = egui::Id::new("selsets-rename");
    let sets = app.doc.data.selection_sets.clone();
    window(if edit { "Edit Filters" } else { "Retrieve Filters" }).open(&mut open).resizable(false).show(ctx, |ui| {
        let mut sel: Option<usize> = ui.memory(|m| m.data.get_temp::<Option<usize>>(sel_id)).flatten().filter(|k| *k < sets.len());
        let mut renaming: Option<String> = ui.memory(|m| m.data.get_temp(ren_id));
        ui.label("Saved selections:");
        ui.horizontal_top(|ui| {
            list_box(ui, "lb4", vec2(240.0, 200.0), |ui| {
                for (k, s) in sets.iter().enumerate() {
                    if sel == Some(k) && renaming.is_some() {
                        let buf = renaming.as_mut().unwrap();
                        let r = ui.add(egui::TextEdit::singleline(buf).desired_width(220.0));
                        r.request_focus();
                        if ui.input(|i| i.key_pressed(egui::Key::Enter)) || r.lost_focus() {
                            let name = buf.trim().to_string();
                            if !name.is_empty() {
                                app.run("Rename Selection", |p| {
                                    p.selection_sets[k].name = name;
                                    Ok(())
                                });
                            }
                            renaming = None;
                        }
                        continue;
                    }
                    let r = list_row(ui, 232.0, sel == Some(k), format!("{}  ({})", s.name, s.ids.len()));
                    if r.clicked() {
                        sel = Some(k);
                    }
                    if r.double_clicked() && !edit {
                        sel = Some(k);
                        close = true;
                    }
                }
            });
            if edit {
                ui.vertical(|ui| {
                    ui.spacing_mut().item_spacing.y = 6.0;
                    if dlg_button(ui, "Rename", false, sel.is_some()) {
                        renaming = sel.map(|k| sets[k].name.clone());
                    }
                    if dlg_button(ui, "Delete", false, sel.is_some()) {
                        let k = sel.unwrap();
                        app.run("Delete Selection", |p| {
                            p.selection_sets.remove(k);
                            Ok(())
                        });
                        sel = None;
                    }
                    if dlg_button(ui, "Select", false, sel.is_some()) {
                        let ids: Vec<Id> = sets[sel.unwrap()].ids.iter().copied().filter(|id| app.doc.data.element(*id).is_some()).collect();
                        app.select(ids);
                    }
                });
            }
        });
        ui.add_space(8.0);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if edit {
                if dlg_button(ui, "Close", true, true) {
                    close = true;
                }
            } else {
                if dlg_button(ui, "Cancel", false, true) {
                    sel = None;
                    close = true;
                }
                if dlg_button(ui, "OK", true, sel.is_some()) {
                    close = true;
                }
            }
        });
        if close && !edit {
            if let Some(k) = sel {
                let ids: Vec<Id> = sets[k].ids.iter().copied().filter(|id| app.doc.data.element(*id).is_some()).collect();
                app.select(ids);
            }
        }
        ui.memory_mut(|m| {
            m.data.insert_temp(sel_id, sel);
            match &renaming {
                Some(r) => {
 m.data.insert_temp(ren_id, r.clone());
 }
                None => m.data.remove::<String>(ren_id),
            }
        });
    });
    if close || !open {
        app.dialogs.selection_sets = None;
    }
}

// ---------------------------------------------------------------- find / replace

#[derive(Clone, Debug, Default)]
pub struct FindReplace {
    pub find: String,
    pub replace: String,
    pub match_case: bool,
    pub whole_word: bool,
    /// 0 entire project, 1 current view, 2 current selection.
    pub scope: u8,
    pub results: Vec<Id>,
}

fn find_in(text: &str, f: &FindReplace) -> Vec<(usize, usize)> {
    if f.find.is_empty() {
        return vec![];
    }
    let (hay, needle) = if f.match_case { (text.to_string(), f.find.clone()) } else { (text.to_lowercase(), f.find.to_lowercase()) };
    let mut out = Vec::new();
    let mut start = 0;
    while let Some(i) = hay[start..].find(&needle) {
        let a = start + i;
        let b = a + needle.len();
        let word = |c: Option<char>| c.is_some_and(|c| c.is_alphanumeric() || c == '_');
        if !f.whole_word || (!word(hay[..a].chars().last()) && !word(hay[b..].chars().next())) {
            out.push((a, b));
        }
        start = b.max(a + 1);
        if start >= hay.len() {
            break;
        }
    }
    out
}

fn replace_in(text: &str, f: &FindReplace) -> String {
    let hits = find_in(text, f);
    let mut s = String::new();
    let mut last = 0;
    for (a, b) in hits {
        s.push_str(&text[last..a]);
        s.push_str(&f.replace);
        last = b;
    }
    s.push_str(&text[last..]);
    s
}

fn find_replace(app: &mut App, ctx: &egui::Context) {
    let Some(mut f) = app.dialogs.find_replace.clone() else { return };
    let mut open = true;
    let mut find_all = false;
    let mut replace_all = false;
    window("Find/Replace").open(&mut open).resizable(false).show(ctx, |ui| {
        egui::Grid::new("fr-grid").num_columns(2).spacing(vec2(8.0, 6.0)).show(ui, |ui| {
            ui.label("Find:");
            let r = ui.add(egui::TextEdit::singleline(&mut f.find).desired_width(280.0));
            if r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                find_all = true;
            }
            ui.end_row();
            ui.label("Replace with:");
            ui.add(egui::TextEdit::singleline(&mut f.replace).desired_width(280.0));
            ui.end_row();
        });
        ui.add_space(4.0);
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(170.0);
                group(ui, "Options", |ui| {
                    ui.checkbox(&mut f.match_case, "Match case");
                    ui.checkbox(&mut f.whole_word, "Match whole word only");
                });
            });
            ui.vertical(|ui| {
                ui.set_width(170.0);
                group(ui, "Scope", |ui| {
                    for (k, l) in [(2u8, "Current selection"), (1, "Current view"), (0, "Entire project")] {
                        if ui.radio(f.scope == k, l).clicked() {
                            f.scope = k;
                        }
                    }
                });
            });
        });
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            if dlg_button(ui, "Find All", true, !f.find.is_empty()) {
                find_all = true;
            }
            if dlg_button(ui, "Replace All", false, !f.find.is_empty()) {
                replace_all = true;
            }
        });
        ui.add_space(6.0);
        ui.label(egui::RichText::new(format!("Results: {}", f.results.len())).size(11.5));
        list_box(ui, "lb5", vec2(400.0, 160.0), |ui| {
            for id in f.results.clone() {
                let Some(e) = app.doc.data.element(id) else { continue };
                let ElementKind::Text(t) = &e.kind else { continue };
                let view = e.view.map(|v| app.view_title(v)).unwrap_or_default();
                let line = format!("{view}:  {}", t.text.replace('\n', " "));
                if list_row(ui, 392.0, app.selection.contains(&id), line).clicked() {
                    if let Some(v) = e.view {
                        app.open_view(v);
                    }
                    app.select(vec![id]);
                }
            }
        });
    });
    if find_all || replace_all {
        let p = &app.doc.data;
        let in_scope = |e: &Element| match f.scope {
            1 => e.view == app.active,
            2 => app.selection.contains(&e.id),
            _ => true,
        };
        f.results = p
            .elements
            .iter()
            .filter(|e| in_scope(e))
            .filter(|e| matches!(&e.kind, ElementKind::Text(t) if !find_in(&t.text, &f).is_empty()))
            .map(|e| e.id)
            .collect();
        if replace_all && !f.results.is_empty() {
            let ids = f.results.clone();
            let fr = f.clone();
            let n = ids.len();
            app.run("Replace All", |p| {
                for id in &ids {
                    if let Some(ElementKind::Text(t)) = p.element_mut(*id).map(|e| &mut e.kind) {
                        t.text = replace_in(&t.text, &fr);
                    }
                }
                Ok(())
            });
            app.info(format!("Replaced text in {n} text note(s)."));
            f.results.clear();
        } else if f.results.is_empty() {
            app.info("No matches found.");
        }
    }
    app.dialogs.find_replace = if open { Some(f) } else { None };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_and_replace_respects_case_and_words() {
        let mut f = FindReplace { find: "door".into(), replace: "DOOR".into(), ..Default::default() };
        assert_eq!(replace_in("Door and doorway", &f), "DOOR and DOORway");
        f.whole_word = true;
        assert_eq!(replace_in("Door and doorway", &f), "DOOR and doorway");
        f.match_case = true;
        assert_eq!(replace_in("Door and door", &f), "Door and DOOR");
    }
}
