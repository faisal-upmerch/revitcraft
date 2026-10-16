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
        if crate::style::check(ui, &mut on, "").changed() {
            *c = if on { Some([200, 0, 0]) } else { None };
        }
        if let Some(col) = c.as_mut() {
            ui.color_edit_button_srgb(col);
        }
    });
}

/// One table cell of fixed width with right and bottom grid lines.
fn cell<R>(ui: &mut egui::Ui, w: f32, add: impl FnOnce(&mut egui::Ui) -> R) -> R {
    let (r, _) = ui.allocate_exact_size(vec2(w, 19.0), egui::Sense::hover());
    let line = egui::Stroke::new(1.0, egui::Color32::from_gray(210));
    ui.painter().line_segment([r.right_top(), r.right_bottom()], line);
    ui.painter().line_segment([r.left_bottom(), r.right_bottom()], line);
    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(r.shrink2(vec2(3.0, 0.0))).layout(egui::Layout::left_to_right(egui::Align::Center)));
    add(&mut child)
}

/// A colour swatch cell: blank when not overridden, the colour when set; click to edit,
/// right-click to clear.
fn swatch(ui: &mut egui::Ui, c: &mut Option<[u8; 3]>) {
    match c {
        Some(col) => {
            ui.color_edit_button_srgb(col).context_menu(|ui| {
                if ui.button("Clear Override").clicked() {
                    *c = None;
                    ui.close();
                }
            });
        }
        None => {
            // Blank until the cell is hovered, like the reference table.
            let hot = ui.rect_contains_pointer(ui.max_rect());
            let text = if hot { "Override..." } else { "" };
            if ui.add_sized(ui.available_size(), egui::Button::new(egui::RichText::new(text).size(11.5)).frame(false)).clicked() {
                *c = Some([200, 0, 0]);
            }
        }
    }
}

/// Windows-style tab strip.
fn tabs(ui: &mut egui::Ui, tab: &mut u8, names: &[&str]) {
    ui.horizontal(|ui| {
        ui.spacing_mut().item_spacing.x = 0.0;
        for (k, n) in names.iter().enumerate() {
            let w = ui.painter().layout_no_wrap(n.to_string(), style::font(12.0), egui::Color32::BLACK).size().x + 16.0;
            let (r, resp) = ui.allocate_exact_size(vec2(w, 22.0), egui::Sense::click());
            let on = *tab == k as u8;
            let p = ui.painter();
            p.rect_filled(r, 0.0, if on { style::field() } else if resp.hovered() { style::hover() } else { egui::Color32::from_rgb(236, 236, 236) });
            let st = egui::Stroke::new(1.0, egui::Color32::from_gray(190));
            p.line_segment([r.left_bottom(), r.left_top()], st);
            p.line_segment([r.left_top(), r.right_top()], st);
            p.line_segment([r.right_top(), r.right_bottom()], st);
            if !on {
                p.line_segment([r.left_bottom(), r.right_bottom()], st);
            }
            p.text(r.center(), egui::Align2::CENTER_CENTER, *n, style::font(12.0), style::text());
            if resp.clicked() {
                *tab = k as u8;
            }
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
    let mut footer = super::Footer::None;
    super::session_begin(app, "vg");
    window(&format!("Visibility/Graphic Overrides for {}: {}", v.type_label(), v.name)).open(&mut open).default_size(vec2(720.0, 560.0)).show(ctx, |ui| {
        let tab_id = egui::Id::new("vg-tab");
        let mut tab: u8 = ui.memory(|m| m.data.get_temp(tab_id)).unwrap_or(0);
        tabs(ui, &mut tab, &["Model Categories", "Annotation Categories", "Imported Categories", "Filters"]);
        ui.memory_mut(|m| m.data.insert_temp(tab_id, tab));
        if tab == 3 {
            let all = app.doc.data.filters.clone();
            if filters_tab(ui, &all, &mut v) {
                app.dialogs.filters = Some(v.overrides.iter().find_map(|o| o.filter).or(all.first().map(|f| f.id)));
            }
            footer = super::footer(ui, app, "vg", "Visibility/Graphics");
            return;
        }
        let cats: Vec<Category> = match tab {
            0 => Category::MODEL.to_vec(),
            1 => Category::ANNOTATION.iter().copied().filter(|c| *c != Category::ImportedCad).collect(),
            _ => vec![Category::ImportedCad],
        };
        ui.add_space(6.0);
        let what = match tab {
            0 => "model",
            1 => "annotation",
            _ => "import",
        };
        let mut show_all = !cats.iter().all(|c| v.hidden.contains(c));
        ui.horizontal(|ui| {
            if crate::style::check(ui, &mut show_all, format!("Show {what} categories in this view")).changed() {
                for c in &cats {
                    v.hidden.retain(|x| x != c);
                    if !show_all {
                        v.hidden.push(*c);
                    }
                }
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(egui::RichText::new("If a category is unchecked, it will not be visible.").size(11.5));
            });
        });
        ui.add_space(4.0);
        // Two-tier header: Visibility | Projection/Surface (Lines, Patterns, Transparency) | Halftone.
        let widths = [210.0, 110.0, 110.0, 100.0, 70.0];
        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(170))).show(ui, |ui| {
            let total: f32 = widths.iter().sum();
            let (hr, _) = ui.allocate_exact_size(vec2(total, 36.0), egui::Sense::hover());
            let p = ui.painter();
            p.rect_filled(hr, 0.0, egui::Color32::from_rgb(246, 246, 246));
            let line = egui::Stroke::new(1.0, egui::Color32::from_gray(200));
            let mut x = hr.left();
            let xs: Vec<f32> = widths.iter().map(|w| {
                let x0 = x;
                x += w;
                x0
            }).collect();
            let mid = hr.top() + 17.0;
            p.text(egui::pos2(xs[0] + widths[0] / 2.0, hr.center().y), egui::Align2::CENTER_CENTER, "Visibility", style::font(12.0), style::text());
            p.text(egui::pos2(xs[1] + (widths[1] + widths[2] + widths[3]) / 2.0, hr.top() + 9.0), egui::Align2::CENTER_CENTER, "Projection/Surface", style::font(12.0), style::text());
            p.line_segment([egui::pos2(xs[1], mid), egui::pos2(xs[4], mid)], line);
            for (k, label) in [(1, "Lines"), (2, "Patterns"), (3, "Transparency")] {
                p.text(egui::pos2(xs[k] + widths[k] / 2.0, mid + 9.0), egui::Align2::CENTER_CENTER, label, style::font(12.0), style::text());
            }
            p.text(egui::pos2(xs[4] + widths[4] / 2.0, hr.center().y), egui::Align2::CENTER_CENTER, "Halftone", style::font(12.0), style::text());
            for (k, x) in xs.iter().enumerate().skip(1) {
                let top = if k == 2 || k == 3 { mid } else { hr.top() };
                p.line_segment([egui::pos2(*x, top), egui::pos2(*x, hr.bottom())], line);
            }
            p.line_segment([hr.left_bottom(), hr.right_bottom()], line);
            egui::ScrollArea::vertical().max_height(ui.ctx().content_rect().height() * 0.5).auto_shrink([true, true]).show(ui, |ui| {
                ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                for c in cats {
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                        let mut vis = !v.hidden.contains(&c);
                        let changed = cell(ui, widths[0], |ui| crate::style::check(ui, &mut vis, c.label()).changed());
                        if changed {
                            if vis {
                                v.hidden.retain(|x| *x != c);
                            } else {
                                v.hidden.push(c);
                            }
                        }
                        let idx = v.overrides.iter().position(|o| o.element.is_none() && o.category == Some(c));
                        let mut o = idx.map(|i| v.overrides[i].clone()).unwrap_or(GraphicOverride { category: Some(c), ..Default::default() });
                        cell(ui, widths[1], |ui| {
                            swatch(ui, &mut o.line_color);
                            if o.line_color.is_some() || o.line_weight.is_some() {
                                let mut w = o.line_weight.unwrap_or(0.0);
                                ui.add(egui::DragValue::new(&mut w).range(0.0..=2.0).speed(0.01).max_decimals(2));
                                o.line_weight = (w > 0.0).then_some(w);
                            }
                        });
                        cell(ui, widths[2], |ui| swatch(ui, &mut o.fill_color));
                        cell(ui, widths[3], |ui| {
                            if o.transparency > 0 || ui.rect_contains_pointer(ui.max_rect()) {
                                let mut t = o.transparency as f64;
                                ui.add(egui::DragValue::new(&mut t).range(0.0..=100.0).suffix(" %"));
                                o.transparency = t as u8;
                            }
                        });
                        cell(ui, widths[4], |ui| {
                            crate::style::check(ui, &mut o.halftone, "");
                        });
                        let empty = o.line_color.is_none() && o.line_weight.is_none() && o.fill_color.is_none() && o.transparency == 0 && !o.halftone;
                        match (idx, empty) {
                            (Some(i), true) => {
                                v.overrides.remove(i);
                            }
                            (Some(i), false) => v.overrides[i] = o,
                            (None, false) => v.overrides.push(o),
                            _ => {}
                        }
                    });
                }
            });
        });
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            let cats: Vec<Category> = match tab {
                0 => Category::MODEL.to_vec(),
                1 => Category::ANNOTATION.iter().copied().filter(|c| *c != Category::ImportedCad).collect(),
                _ => vec![Category::ImportedCad],
            };
            if super::dlg_button(ui, "All", false, true) {
                v.hidden.retain(|c| !cats.contains(c));
            }
            if super::dlg_button(ui, "None", false, true) {
                for c in &cats {
                    if !v.hidden.contains(c) {
                        v.hidden.push(*c);
                    }
                }
            }
            if super::dlg_button(ui, "Invert", false, true) {
                for c in &cats {
                    if v.hidden.contains(c) {
                        v.hidden.retain(|x| x != c);
                    } else {
                        v.hidden.push(*c);
                    }
                }
            }
            ui.add_space(16.0);
            if super::dlg_button(ui, "Object Styles...", false, true) {
                app.dialogs.object_styles = true;
            }
        });
        footer = super::footer(ui, app, "vg", "Visibility/Graphics");
    });
    if footer == super::Footer::None && open {
        update_view(app, vid, "Visibility/Graphics", v);
    }
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        super::session_cancel(app, "vg");
    }
    if !open {
        app.dialogs.vg = None;
    }
}

/// The Filters tab of Visibility/Graphics: filters applied to the view with their visibility
/// and graphic overrides. Returns true when Edit/New... was clicked.
fn filters_tab(ui: &mut egui::Ui, all: &[ViewFilter], v: &mut View) -> bool {
    let sel_id = egui::Id::new("vg-filter-sel");
    let mut sel: Option<Id> = ui.memory(|m| m.data.get_temp::<Option<Id>>(sel_id)).flatten();
    let mut edit = false;
    ui.add_space(6.0);
    let widths = [190.0, 70.0, 110.0, 110.0, 100.0, 70.0];
    let total: f32 = widths.iter().sum();
    egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(170))).show(ui, |ui| {
        let (hr, _) = ui.allocate_exact_size(vec2(total, 36.0), egui::Sense::hover());
        let p = ui.painter();
        p.rect_filled(hr, 0.0, egui::Color32::from_rgb(246, 246, 246));
        let line = egui::Stroke::new(1.0, egui::Color32::from_gray(200));
        let mut xs = vec![hr.left()];
        for w in widths {
            xs.push(xs.last().unwrap() + w);
        }
        let mid = hr.top() + 17.0;
        p.text(egui::pos2(xs[0] + widths[0] / 2.0, hr.center().y), egui::Align2::CENTER_CENTER, "Name", style::font(12.0), style::text());
        p.text(egui::pos2(xs[1] + widths[1] / 2.0, hr.center().y), egui::Align2::CENTER_CENTER, "Visibility", style::font(12.0), style::text());
        p.text(egui::pos2((xs[2] + xs[5]) / 2.0, hr.top() + 9.0), egui::Align2::CENTER_CENTER, "Projection/Surface", style::font(12.0), style::text());
        p.line_segment([egui::pos2(xs[2], mid), egui::pos2(xs[5], mid)], line);
        for (k, label) in [(2, "Lines"), (3, "Patterns"), (4, "Transparency")] {
            p.text(egui::pos2(xs[k] + widths[k] / 2.0, mid + 9.0), egui::Align2::CENTER_CENTER, label, style::font(12.0), style::text());
        }
        p.text(egui::pos2(xs[5] + widths[5] / 2.0, hr.center().y), egui::Align2::CENTER_CENTER, "Halftone", style::font(12.0), style::text());
        for (k, x) in xs.iter().enumerate().skip(1).take(5) {
            let top = if k == 3 || k == 4 { mid } else { hr.top() };
            p.line_segment([egui::pos2(*x, top), egui::pos2(*x, hr.bottom())], line);
        }
        p.line_segment([hr.left_bottom(), hr.right_bottom()], line);
        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
        let rows: Vec<usize> = (0..v.overrides.len()).filter(|k| v.overrides[*k].filter.is_some()).collect();
        if rows.is_empty() {
            let (r, _) = ui.allocate_exact_size(vec2(total, 60.0), egui::Sense::hover());
            ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, "No filters applied. Click Add to apply a filter to this view.", style::font(12.0), style::text_dim());
        }
        for k in rows {
            let fid = v.overrides[k].filter.unwrap();
            let name = all.iter().find(|f| f.id == fid).map(|f| f.name.clone()).unwrap_or_else(|| "(deleted)".into());
            let o = &mut v.overrides[k];
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                let on = sel == Some(fid);
                if cell(ui, widths[0], |ui| ui.add(egui::Button::selectable(on, name).frame(false))).clicked() {
                    sel = Some(fid);
                }
                let mut vis = !o.hidden;
                cell(ui, widths[1], |ui| {
                    ui.add_space(22.0);
                    if crate::style::check(ui, &mut vis, "").changed() {
                        o.hidden = !vis;
                    }
                });
                cell(ui, widths[2], |ui| {
                    swatch(ui, &mut o.line_color);
                    if o.line_color.is_some() || o.line_weight.is_some() {
                        let mut w = o.line_weight.unwrap_or(0.0);
                        ui.add(egui::DragValue::new(&mut w).range(0.0..=2.0).speed(0.01).max_decimals(2));
                        o.line_weight = (w > 0.0).then_some(w);
                    }
                });
                cell(ui, widths[3], |ui| swatch(ui, &mut o.fill_color));
                cell(ui, widths[4], |ui| {
                    if o.transparency > 0 || ui.rect_contains_pointer(ui.max_rect()) {
                        let mut t = o.transparency as f64;
                        ui.add(egui::DragValue::new(&mut t).range(0.0..=100.0).suffix(" %"));
                        o.transparency = t as u8;
                    }
                });
                cell(ui, widths[5], |ui| {
                    ui.add_space(22.0);
                    crate::style::check(ui, &mut o.halftone, "");
                });
            });
        }
    });
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        let unused: Vec<&ViewFilter> = all.iter().filter(|f| !v.overrides.iter().any(|o| o.filter == Some(f.id))).collect();
        ui.add_enabled_ui(!unused.is_empty(), |ui| {
            ui.menu_button("Add", |ui| {
                for f in &unused {
                    if ui.button(&f.name).clicked() {
                        v.overrides.push(GraphicOverride { filter: Some(f.id), ..Default::default() });
                        sel = Some(f.id);
                        ui.close();
                    }
                }
            });
        });
        let idx = sel.and_then(|s| v.overrides.iter().position(|o| o.filter == Some(s)));
        if super::dlg_button(ui, "Remove", false, idx.is_some()) {
            v.overrides.remove(idx.unwrap());
            sel = None;
        }
        // Filter order sets priority: the first matching filter wins.
        let filter_rows: Vec<usize> = (0..v.overrides.len()).filter(|k| v.overrides[*k].filter.is_some()).collect();
        let pos = idx.and_then(|i| filter_rows.iter().position(|r| *r == i));
        if super::dlg_button(ui, "Up", false, pos.is_some_and(|p| p > 0)) {
            let p = pos.unwrap();
            v.overrides.swap(filter_rows[p], filter_rows[p - 1]);
        }
        if super::dlg_button(ui, "Down", false, pos.is_some_and(|p| p + 1 < filter_rows.len())) {
            let p = pos.unwrap();
            v.overrides.swap(filter_rows[p], filter_rows[p + 1]);
        }
        ui.add_space(16.0);
        if super::dlg_button(ui, "Edit/New...", false, true) {
            edit = true;
        }
    });
    if all.is_empty() {
        ui.label(egui::RichText::new("This project has no filters yet. Use Edit/New... to create one.").size(11.5).color(style::text_dim()));
    }
    ui.memory_mut(|m| m.data.insert_temp(sel_id, sel));
    edit
}

fn view_range(app: &mut App, ctx: &egui::Context) {
    let Some(vid) = app.dialogs.view_range else { return };
    let Some(mut v) = app.doc.data.view(vid).cloned() else {
        app.dialogs.view_range = None;
        return;
    };
    let mut open = true;
    let units = app.doc.data.units.clone();
    let mut footer = super::Footer::None;
    super::session_begin(app, "view-range");
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
        footer = super::footer(ui, app, "view-range", "View Range");
    });
    if footer == super::Footer::None && open {
        if v.view_range.bottom <= v.view_range.cut && v.view_range.cut <= v.view_range.top {
            update_view(app, vid, "View Range", v);
        }
    }
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        super::session_cancel(app, "view-range");
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
            if crate::style::check(ui, &mut on, &l.name).changed() {
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

/// New Schedule: the category (searchable), the name, building components or keys, and the phase.
#[derive(Clone, Default)]
struct NewSchedState {
    search: String,
    category: Option<Category>,
    name: String,
    name_edited: bool,
    phase: usize,
}

fn new_schedule(app: &mut App, ctx: &egui::Context) {
    let Some(takeoff) = app.dialogs.new_schedule else { return };
    let key = egui::Id::new(("new-schedule", takeoff));
    let mut st: NewSchedState = ctx.data(|m| m.get_temp(key)).unwrap_or_else(|| NewSchedState { phase: app.doc.data.phases.len().saturating_sub(1), ..Default::default() });
    let suffix = if takeoff { "Material Takeoff" } else { "Schedule" };
    let mut cats: Vec<Category> = Category::SCHEDULABLE.to_vec();
    cats.sort_by_key(|c| c.label());
    if st.category.is_none() {
        st.category = cats.first().copied();
    }
    if !st.name_edited {
        st.name = st.category.map(|c| format!("{} {suffix}", c.singular())).unwrap_or_default();
    }
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window(if takeoff { "New Material Takeoff" } else { "New Schedule" }).open(&mut open).resizable(false).default_width(560.0).show(ctx, |ui| {
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(260.0);
                ui.horizontal(|ui| {
                    ui.label("Filter list:");
                    egui::ComboBox::from_id_salt("sched-disc").selected_text("Architecture, Structure").width(170.0).show_ui(ui, |ui| {
                        let mut on = true;
                        crate::style::check(ui, &mut on, "Architecture");
                        crate::style::check(ui, &mut on, "Structure");
                    });
                });
                ui.add_space(4.0);
                ui.label("Category:");
                ui.add(egui::TextEdit::singleline(&mut st.search).hint_text("Search").desired_width(254.0));
                egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                    ui.set_min_size(vec2(250.0, 300.0));
                    egui::ScrollArea::vertical().max_height(300.0).auto_shrink([false, false]).show(ui, |ui| {
                        ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                            ui.add_enabled(false, egui::Button::selectable(false, "<Multi-Category>"));
                            for c in &cats {
                                if !st.search.is_empty() && !c.label().to_lowercase().contains(&st.search.to_lowercase()) {
                                    continue;
                                }
                                let r = ui.selectable_label(st.category == Some(*c), c.label());
                                if r.clicked() {
                                    st.category = Some(*c);
                                }
                                if r.double_clicked() {
                                    ok = true;
                                }
                            }
                        });
                    });
                });
            });
            ui.add_space(12.0);
            ui.vertical(|ui| {
                ui.add_space(26.0);
                ui.label("Name:");
                if ui.add(egui::TextEdit::singleline(&mut st.name).desired_width(250.0)).changed() {
                    st.name_edited = true;
                }
                ui.add_space(10.0);
                let _ = ui.radio(true, "Schedule building components");
                ui.add_enabled_ui(false, |ui| {
                    let _ = ui.radio(false, "Schedule keys");
                    ui.horizontal(|ui| {
                        ui.add_space(20.0);
                        ui.label("Key name:");
                        let mut k = String::new();
                        ui.add(egui::TextEdit::singleline(&mut k).desired_width(160.0));
                    });
                });
                ui.add_space(10.0);
                ui.label("Phase:");
                let phases: Vec<String> = app.doc.data.phases.iter().map(|p| p.name.clone()).collect();
                egui::ComboBox::from_id_salt("sched-phase").selected_text(phases.get(st.phase).cloned().unwrap_or_default()).width(250.0).show_ui(ui, |ui| {
                    for (k, name) in phases.iter().enumerate() {
                        ui.selectable_value(&mut st.phase, k, name);
                    }
                });
            });
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            cancel = super::dlg_button(ui, "Cancel", false, true);
            if super::dlg_button(ui, "OK", true, st.category.is_some() && !st.name.trim().is_empty()) {
                ok = true;
            }
        });
    });
    if ok {
        let Some(c) = st.category else { return };
        let name = st.name.trim().to_string();
        if app.doc.data.views.iter().any(|v| v.name == name) {
            app.error("The name is already in use.");
            ok = false;
        } else {
            let phase = app.doc.data.phases.get(st.phase).map(|p| p.id);
            if !takeoff {
                // As in the reference app, the schedule exists once Schedule Properties is OK'd.
                let def = ScheduleDef { category: c, itemize: true, grand_total: false, ..Default::default() };
                app.dialogs.new_schedule_pending = Some((def, name.clone(), phase));
                app.dialogs.schedule_props = Some((0, 0));
                app.dialogs.new_schedule = None;
                ctx.data_mut(|m| m.remove::<NewSchedState>(key));
                return;
            }
            let made = app.run("New Schedule", |p| {
                let id = if takeoff { edit::new_material_takeoff(p, c) } else { edit::new_schedule(p, c) };
                if let Some(v) = p.view_mut(id) {
                    v.name = name.clone();
                    v.phase = phase.or(v.phase);
                    // The fields are picked next, in Schedule Properties.
                    if let ViewKind::Schedule(d) = &mut v.kind {
                        if !takeoff {
                            d.fields.clear();
                        }
                    }
                }
                Ok(id)
            });
            if let Some(id) = made {
                app.open_view(id);
                app.dialogs.schedule_props = Some((id, 0));
            }
        }
    }
    if ok || cancel || !open {
        app.dialogs.new_schedule = None;
        ctx.data_mut(|m| m.remove::<NewSchedState>(key));
    } else {
        ctx.data_mut(|m| m.insert_temp(key, st));
    }
}

/// Working state of Schedule Properties: the definition being edited and list selections.
#[derive(Clone)]
struct SchedPropsState {
    def: ScheduleDef,
    search: String,
    avail_sel: Option<String>,
    field_sel: Option<usize>,
    format_sel: usize,
    /// Calculated Value: (name, kind index, formula) while its dialog is open.
    calc: Option<(String, usize, String)>,
}

const CALC_KINDS: [(&str, ParamKind); 6] = [("Number", ParamKind::Number), ("Integer", ParamKind::Integer), ("Length", ParamKind::Length), ("Area", ParamKind::Area), ("Volume", ParamKind::Volume), ("Currency", ParamKind::Currency)];
const FOOTER_MODES: [&str; 4] = ["Title, count, and totals", "Title and totals", "Count and totals", "Totals only"];

/// A bordered list box of fixed size.
fn list_frame<R>(ui: &mut egui::Ui, salt: &str, size: egui::Vec2, add: impl FnOnce(&mut egui::Ui) -> R) -> R {
    egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
        ui.set_min_size(size);
        ui.set_max_width(size.x);
        egui::ScrollArea::vertical().id_salt(salt).max_height(size.y).auto_shrink([false, false]).show(ui, |ui| {
            ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), add).inner
        }).inner
    }).inner
}

fn field_combo(ui: &mut egui::Ui, salt: impl std::hash::Hash + std::fmt::Debug, value: &mut String, fields: &[String], width: f32) {
    let shown = if value.is_empty() { "(none)".to_string() } else { value.clone() };
    egui::ComboBox::from_id_salt(salt).selected_text(shown).width(width).show_ui(ui, |ui| {
        if ui.selectable_label(value.is_empty(), "(none)").clicked() {
            value.clear();
        }
        for f in fields {
            if ui.selectable_label(value == f, f).clicked() {
                *value = f.clone();
            }
        }
    });
}

fn schedule_props(app: &mut App, ctx: &egui::Context) {
    let Some((vid, mut tab)) = app.dialogs.schedule_props else { return };
    let pending = if vid == 0 { app.dialogs.new_schedule_pending.clone() } else { None };
    let v = match &pending {
        Some((def, name, phase)) => {
            let mut v = View::new(0, name.clone(), 100.0, ViewKind::Schedule(def.clone()));
            v.phase = *phase;
            v
        }
        None => match app.doc.data.view(vid).cloned() {
            Some(v) => v,
            None => {
                app.dialogs.schedule_props = None;
                return;
            }
        },
    };
    let ViewKind::Schedule(orig) = v.kind.clone() else { return };
    let key = egui::Id::new(("sched-props", vid));
    let mut st: SchedPropsState = ctx.data(|m| m.get_temp(key)).unwrap_or(SchedPropsState { def: orig.clone(), search: String::new(), avail_sel: None, field_sel: None, format_sel: 0, calc: None });
    let available = rc_core::schedule::available_fields(&app.doc.data, &st.def);
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Schedule Properties").open(&mut open).resizable(false).default_width(640.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            for (k, name) in ["Fields", "Filter", "Sorting/Grouping", "Formatting", "Appearance"].iter().enumerate() {
                ui.selectable_value(&mut tab, k, *name);
            }
        });
        ui.separator();
        let def = &mut st.def;
        ui.allocate_ui(vec2(620.0, 400.0), |ui| {
            ui.set_min_size(vec2(620.0, 400.0));
            match tab {
                0 => {
                    ui.horizontal(|ui| {
                        ui.label("Select available fields from:");
                        egui::ComboBox::from_id_salt("sched-from").selected_text(def.category.label()).width(200.0).show_ui(ui, |ui| {
                            let _ = ui.selectable_label(true, def.category.label());
                        });
                    });
                    ui.add_space(4.0);
                    ui.horizontal(|ui| {
                        ui.label("Parameter Name Search:");
                        ui.add(egui::TextEdit::singleline(&mut st.search).desired_width(330.0));
                    });
                    ui.add_space(4.0);
                    let search = st.search.to_lowercase();
                    let shown: Vec<&rc_core::params::ParamDef> = available.iter().filter(|f| !def.fields.contains(&f.name) && (search.is_empty() || f.name.to_lowercase().contains(&search))).collect();
                    ui.horizontal_top(|ui| {
                        ui.vertical(|ui| {
                            ui.horizontal(|ui| {
                                ui.set_width(250.0);
                                ui.label("Available fields:");
                                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| ui.label(format!("{} items", shown.len())));
                            });
                            let mut add: Option<String> = None;
                            list_frame(ui, "sched-avail", vec2(250.0, 280.0), |ui| {
                                for f in &shown {
                                    let r = ui.selectable_label(st.avail_sel.as_deref() == Some(&f.name), &f.name);
                                    if r.clicked() {
                                        st.avail_sel = Some(f.name.clone());
                                    }
                                    if r.double_clicked() {
                                        add = Some(f.name.clone());
                                    }
                                }
                            });
                            ui.horizontal(|ui| {
                                if ui.button("fx").on_hover_text("Add calculated parameter").clicked() {
                                    st.calc = Some((String::new(), 0, String::new()));
                                }
                            });
                            if let Some(f) = add {
                                def.fields.push(f);
                                st.avail_sel = None;
                            }
                        });
                        ui.vertical(|ui| {
                            ui.add_space(130.0);
                            let can_add = st.avail_sel.as_ref().is_some_and(|f| !def.fields.contains(f));
                            if ui.add_enabled(can_add, egui::Button::new("  ➡  ")).on_hover_text("Add parameter(s)").clicked() {
                                if let Some(f) = st.avail_sel.take() {
                                    def.fields.push(f);
                                    st.field_sel = Some(def.fields.len() - 1);
                                }
                            }
                            ui.add_space(6.0);
                            if ui.add_enabled(st.field_sel.is_some_and(|k| k < def.fields.len()), egui::Button::new("  ⬅  ")).on_hover_text("Remove parameter(s)").clicked() {
                                if let Some(k) = st.field_sel.take() {
                                    let f = def.fields.remove(k);
                                    def.calculated.retain(|c| c.name != f);
                                }
                            }
                        });
                        ui.vertical(|ui| {
                            ui.label("Scheduled fields (in order):");
                            let mut remove: Option<usize> = None;
                            ui.add_space(2.0);
                            list_frame(ui, "sched-fields", vec2(250.0, 280.0), |ui| {
                                for (k, f) in def.fields.iter().enumerate() {
                                    let r = ui.selectable_label(st.field_sel == Some(k), f);
                                    if r.clicked() {
                                        st.field_sel = Some(k);
                                    }
                                    if r.double_clicked() {
                                        remove = Some(k);
                                    }
                                }
                            });
                            if let Some(k) = remove {
                                def.fields.remove(k);
                                st.field_sel = None;
                            }
                            ui.horizontal(|ui| {
                                let sel = st.field_sel.filter(|k| *k < def.fields.len());
                                if ui.add_enabled(sel.is_some_and(|k| k > 0), egui::Button::new("Move Up")).clicked() {
                                    let k = sel.unwrap();
                                    def.fields.swap(k, k - 1);
                                    st.field_sel = Some(k - 1);
                                }
                                if ui.add_enabled(sel.is_some_and(|k| k + 1 < def.fields.len()), egui::Button::new("Move Down")).clicked() {
                                    let k = sel.unwrap();
                                    def.fields.swap(k, k + 1);
                                    st.field_sel = Some(k + 1);
                                }
                            });
                        });
                    });
                    ui.add_space(4.0);
                    let mut links = false;
                    ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut links, "Include elements in links"));
                    let _ = &search;
                }
                1 => {
                    // Filter by / And: up to eight rules; "(none)" ends the list.
                    let names: Vec<String> = available.iter().map(|f| f.name.clone()).collect();
                    let rows = 8;
                    let mut remove: Option<usize> = None;
                    egui::Grid::new("sched-filter").num_columns(4).spacing(vec2(8.0, 8.0)).show(ui, |ui| {
                        for k in 0..rows {
                            ui.label(if k == 0 { "Filter by:" } else { "And:" });
                            let enabled = k <= def.filters.len();
                            ui.add_enabled_ui(enabled, |ui| {
                                let mut field = def.filters.get(k).map(|f| f.field.clone()).unwrap_or_default();
                                field_combo(ui, ("sf", k), &mut field, &names, 180.0);
                                match (def.filters.get_mut(k), field.is_empty()) {
                                    (Some(_), true) => remove = Some(k),
                                    (Some(f), false) => f.field = field,
                                    (None, false) => def.filters.push(ScheduleFilter { field, op: FilterOp::Equals, value: String::new() }),
                                    (None, true) => {}
                                }
                            });
                            if let Some(f) = def.filters.get_mut(k) {
                                egui::ComboBox::from_id_salt(("so", k)).selected_text(f.op.label()).width(150.0).show_ui(ui, |ui| {
                                    for o in FilterOp::ALL {
                                        ui.selectable_value(&mut f.op, o, o.label());
                                    }
                                });
                                ui.add(egui::TextEdit::singleline(&mut f.value).desired_width(170.0));
                            } else {
                                ui.add_enabled_ui(false, |ui| {
                                    egui::ComboBox::from_id_salt(("so-off", k)).selected_text("").width(150.0).show_ui(ui, |_| {});
                                });
                                let mut blank = String::new();
                                ui.add_enabled(false, egui::TextEdit::singleline(&mut blank).desired_width(170.0));
                            }
                            ui.end_row();
                        }
                    });
                    if let Some(k) = remove {
                        def.filters.truncate(k);
                    }
                    ui.add_space(6.0);
                    let mut by_sheet = false;
                    ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut by_sheet, "Filter by sheet"));
                }
                2 => {
                    // Sort by / Then by: four levels with direction, header, footer and blank line.
                    let names = def.fields.clone();
                    for k in 0..4 {
                        let enabled = k <= def.sort_by.len();
                        ui.add_enabled_ui(enabled, |ui| {
                            ui.horizontal(|ui| {
                                ui.add_sized(vec2(56.0, 18.0), egui::Label::new(if k == 0 { "Sort by:" } else { "Then by:" }));
                                let mut field = def.sort_by.get(k).cloned().unwrap_or_default();
                                field_combo(ui, ("sort", k), &mut field, &names, 200.0);
                                if field.is_empty() {
                                    if k < def.sort_by.len() {
                                        def.sort_by.truncate(k);
                                        def.levels.truncate(k);
                                    }
                                } else if k < def.sort_by.len() {
                                    def.sort_by[k] = field;
                                } else {
                                    def.sort_by.push(field);
                                }
                                while def.levels.len() < def.sort_by.len() {
                                    let n = def.levels.len();
                                    def.levels.push(def.level(n));
                                }
                                let active = k < def.sort_by.len();
                                let mut lv = def.levels.get(k).cloned().unwrap_or_default();
                                ui.add_enabled_ui(active, |ui| {
                                    ui.radio_value(&mut lv.descending, false, "Ascending");
                                    ui.radio_value(&mut lv.descending, true, "Descending");
                                });
                                if let Some(l) = def.levels.get_mut(k) {
                                    *l = lv;
                                }
                            });
                            let active = k < def.sort_by.len();
                            let mut lv = def.levels.get(k).cloned().unwrap_or_default();
                            ui.add_enabled_ui(active, |ui| {
                                ui.horizontal(|ui| {
                                    ui.add_space(62.0);
                                    crate::style::check(ui, &mut lv.header, "Header");
                                    crate::style::check(ui, &mut lv.footer, "Footer:");
                                    ui.add_enabled_ui(lv.footer, |ui| {
                                        egui::ComboBox::from_id_salt(("foot", k)).selected_text(FOOTER_MODES[lv.footer_mode.min(3) as usize]).width(170.0).show_ui(ui, |ui| {
                                            for (m, label) in FOOTER_MODES.iter().enumerate() {
                                                ui.selectable_value(&mut lv.footer_mode, m as u8, *label);
                                            }
                                        });
                                    });
                                    crate::style::check(ui, &mut lv.blank_line, "Blank line");
                                });
                            });
                            if let Some(l) = def.levels.get_mut(k) {
                                *l = lv;
                            }
                        });
                        ui.add_space(6.0);
                    }
                    if let Some(l0) = def.levels.first() {
                        def.descending = l0.descending;
                        def.group_headers = l0.header && l0.footer;
                    }
                    ui.separator();
                    ui.horizontal(|ui| {
                        crate::style::check(ui, &mut def.grand_total, "Grand totals:");
                        ui.add_enabled_ui(def.grand_total, |ui| {
                            egui::ComboBox::from_id_salt("grand").selected_text(FOOTER_MODES[def.grand_mode.min(3) as usize]).width(170.0).show_ui(ui, |ui| {
                                for (m, label) in FOOTER_MODES.iter().enumerate() {
                                    ui.selectable_value(&mut def.grand_mode, m as u8, *label);
                                }
                            });
                        });
                    });
                    ui.horizontal(|ui| {
                        ui.add_space(22.0);
                        ui.label("Custom grand total title:");
                        if def.grand_title.is_empty() {
                            def.grand_title = "Grand total".into();
                        }
                        ui.add_enabled(def.grand_total, egui::TextEdit::singleline(&mut def.grand_title).desired_width(200.0));
                    });
                    crate::style::check(ui, &mut def.itemize, "Itemize every instance");
                }
                3 => {
                    // Formatting: per-field heading, alignment, hidden and totals.
                    ui.horizontal_top(|ui| {
                        ui.vertical(|ui| {
                            ui.label("Fields:");
                            list_frame(ui, "sched-fmt", vec2(220.0, 340.0), |ui| {
                                for (k, f) in def.fields.iter().enumerate() {
                                    if ui.selectable_label(st.format_sel == k, f).clicked() {
                                        st.format_sel = k;
                                    }
                                }
                            });
                        });
                        ui.add_space(10.0);
                        let Some(name) = def.fields.get(st.format_sel).cloned() else { return };
                        let mut fm = def.format(&name);
                        if fm.heading.is_empty() {
                            fm.heading = name.clone();
                        }
                        ui.vertical(|ui| {
                            egui::Grid::new("sched-fmt-grid").num_columns(2).spacing(vec2(10.0, 8.0)).show(ui, |ui| {
                                ui.label("Heading:");
                                ui.add(egui::TextEdit::singleline(&mut fm.heading).desired_width(240.0));
                                ui.end_row();
                                ui.label("Heading orientation:");
                                egui::ComboBox::from_id_salt("fmt-orient").selected_text("Horizontal").width(150.0).show_ui(ui, |ui| {
                                    let _ = ui.selectable_label(true, "Horizontal");
                                });
                                ui.end_row();
                                ui.label("Alignment:");
                                egui::ComboBox::from_id_salt("fmt-align").selected_text(["Left", "Center", "Right"][fm.align.min(2) as usize]).width(150.0).show_ui(ui, |ui| {
                                    for (k, a) in ["Left", "Center", "Right"].iter().enumerate() {
                                        ui.selectable_value(&mut fm.align, k as u8, *a);
                                    }
                                });
                                ui.end_row();
                            });
                            ui.add_space(6.0);
                            egui::Grid::new("sched-fmt-grid2").num_columns(2).spacing(vec2(10.0, 8.0)).show(ui, |ui| {
                                ui.label("Field formatting:");
                                ui.add_enabled(false, egui::Button::new("Field Format...").min_size(vec2(150.0, 22.0)));
                                ui.end_row();
                                ui.label("Conditional formatting:");
                                ui.add_enabled(false, egui::Button::new("Conditional Format...").min_size(vec2(150.0, 22.0)));
                                ui.end_row();
                                ui.label("Show conditional format on\nsheets:");
                                let mut on = true;
                                ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut on, ""));
                                ui.end_row();
                                ui.label("Hidden field:");
                                crate::style::check(ui, &mut fm.hidden, "");
                                ui.end_row();
                            });
                            ui.add_space(10.0);
                            let numeric = available.iter().find(|f| f.name == name).is_some_and(|f| matches!(f.kind, rc_core::params::PKind::Value(k) if k.is_numeric()));
                            let mut totals = def.total_fields.contains(&name);
                            ui.add_enabled_ui(numeric, |ui| {
                                egui::ComboBox::from_id_salt("fmt-totals").selected_text(if totals { "Calculate totals" } else { "No calculation" }).width(160.0).show_ui(ui, |ui| {
                                    ui.selectable_value(&mut totals, false, "No calculation");
                                    ui.selectable_value(&mut totals, true, "Calculate totals");
                                });
                            });
                            ui.add_space(4.0);
                            ui.label("Multiple values indication");
                            let _ = ui.radio(true, "Use project settings");
                            ui.add_enabled_ui(false, |ui| {
                                let _ = ui.radio(false, "Display as <varies>");
                                let _ = ui.radio(false, "Display custom text:");
                            });
                            if totals && !def.total_fields.contains(&name) {
                                def.total_fields.push(name.clone());
                            } else if !totals {
                                def.total_fields.retain(|f| *f != name);
                            }
                        });
                        if fm.heading == name {
                            fm.heading.clear();
                        }
                        if fm == FieldFormat::default() {
                            def.formats.remove(&name);
                        } else {
                            def.formats.insert(name, fm);
                        }
                    });
                }
                _ => {
                    // Appearance: graphics and text.
                    let look = &mut def.look;
                    ui.label(egui::RichText::new("Graphics").strong());
                    egui::Grid::new("sched-look").num_columns(2).spacing(vec2(12.0, 8.0)).show(ui, |ui| {
                        ui.label("Build schedule:");
                        ui.horizontal(|ui| {
                            let _ = ui.radio(true, "Top-down");
                            ui.add_enabled_ui(false, |ui| {
                                let _ = ui.radio(false, "Bottom-up");
                            });
                        });
                        ui.end_row();
                        ui.label("Grid lines:");
                        ui.horizontal(|ui| {
                            crate::style::check(ui, &mut look.grid_lines, "");
                            egui::ComboBox::from_id_salt("look-grid").selected_text("<Thin Lines>").width(140.0).show_ui(ui, |ui| {
                                let _ = ui.selectable_label(true, "<Thin Lines>");
                            });
                            let mut g = false;
                            ui.add_enabled_ui(false, |ui| crate::style::check(ui, &mut g, "Grid in headers/footers/spacers"));
                        });
                        ui.end_row();
                        ui.label("Outline:");
                        ui.horizontal(|ui| {
                            crate::style::check(ui, &mut look.outline, "");
                            ui.add_enabled_ui(look.outline, |ui| {
                                egui::ComboBox::from_id_salt("look-outline").selected_text("<Thin Lines>").width(140.0).show_ui(ui, |ui| {
                                    let _ = ui.selectable_label(true, "<Thin Lines>");
                                });
                            });
                        });
                        ui.end_row();
                        ui.label("Height:");
                        ui.horizontal(|ui| {
                            ui.add_enabled_ui(false, |ui| {
                                egui::ComboBox::from_id_salt("look-height").selected_text("Variable").width(140.0).show_ui(ui, |_| {});
                            });
                            crate::style::check(ui, &mut look.blank_row, "Blank row before data");
                        });
                        ui.end_row();
                        ui.label("Stripe Rows:");
                        ui.horizontal(|ui| {
                            crate::style::check(ui, &mut look.stripe_rows, "");
                            egui::ComboBox::from_id_salt("look-stripe").selected_text("First Row Stripe Color").width(160.0).show_ui(ui, |ui| {
                                let _ = ui.selectable_label(true, "First Row Stripe Color");
                            });
                            let (r, _) = ui.allocate_exact_size(vec2(20.0, 18.0), egui::Sense::hover());
                            ui.painter().rect(r, 0.0, egui::Color32::from_rgb(240, 244, 250), egui::Stroke::new(1.0, style::border()), egui::StrokeKind::Inside);
                        });
                        ui.end_row();
                        ui.label("");
                        let mut on_sheets = true;
                        ui.add_enabled_ui(look.stripe_rows, |ui| crate::style::check(ui, &mut on_sheets, "Show Stripe Rows on Sheets"));
                        ui.end_row();
                    });
                    ui.add_space(8.0);
                    ui.label(egui::RichText::new("Text").strong());
                    egui::Grid::new("sched-text").num_columns(2).spacing(vec2(12.0, 8.0)).show(ui, |ui| {
                        ui.label("");
                        crate::style::check(ui, &mut look.show_title, "Show Title");
                        ui.end_row();
                        ui.label("");
                        crate::style::check(ui, &mut look.show_headers, "Show Headers");
                        ui.end_row();
                        for (k, label) in ["Title text:", "Header text:", "Body text:"].iter().enumerate() {
                            ui.label(*label);
                            egui::ComboBox::from_id_salt(("look-text", k)).selected_text("Schedule Default").width(160.0).show_ui(ui, |ui| {
                                let _ = ui.selectable_label(true, "Schedule Default");
                            });
                            ui.end_row();
                        }
                    });
                }
            }
        });
        ui.add_space(6.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            cancel = super::dlg_button(ui, "Cancel", false, true);
            ok = super::dlg_button(ui, "OK", true, true);
        });
    });
    // Calculated Value.
    if let Some((mut name, mut kind, mut formula)) = st.calc.take() {
        let (mut done, mut quit) = (false, false);
        window("Calculated Value").resizable(false).default_width(340.0).show(ctx, |ui| {
            egui::Grid::new("calc-grid").num_columns(2).spacing(vec2(10.0, 8.0)).show(ui, |ui| {
                ui.label("Name:");
                ui.add(egui::TextEdit::singleline(&mut name).desired_width(220.0));
                ui.end_row();
                ui.label("");
                ui.horizontal(|ui| {
                    let _ = ui.radio(true, "Formula");
                    ui.add_enabled_ui(false, |ui| {
                        let _ = ui.radio(false, "Percentage");
                    });
                });
                ui.end_row();
                ui.label("Discipline:");
                egui::ComboBox::from_id_salt("calc-disc").selected_text("Common").width(160.0).show_ui(ui, |ui| {
                    let _ = ui.selectable_label(true, "Common");
                });
                ui.end_row();
                ui.label("Type:");
                egui::ComboBox::from_id_salt("calc-kind").selected_text(CALC_KINDS[kind].0).width(160.0).show_ui(ui, |ui| {
                    for (k, (label, _)) in CALC_KINDS.iter().enumerate() {
                        ui.selectable_value(&mut kind, k, *label);
                    }
                });
                ui.end_row();
                ui.label("Formula:");
                ui.add(egui::TextEdit::singleline(&mut formula).desired_width(220.0));
                ui.end_row();
            });
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                quit = super::dlg_button(ui, "Cancel", false, true);
                done = super::dlg_button(ui, "OK", true, !name.trim().is_empty() && !formula.trim().is_empty());
            });
        });
        if done {
            let name = name.trim().to_string();
            if st.def.fields.contains(&name) || available.iter().any(|f| f.name == name) {
                app.error("The name is already in use.");
                st.calc = Some((name, kind, formula));
            } else {
                st.def.calculated.push(CalculatedField { name: name.clone(), formula: formula.trim().to_string(), kind: CALC_KINDS[kind].1 });
                st.def.fields.push(name);
            }
        } else if !quit {
            st.calc = Some((name, kind, formula));
        }
    }
    if ok && pending.is_some() {
        let (def, name, phase) = (st.def.clone(), v.name.clone(), v.phase);
        let made = app.run("New Schedule", |p| {
            let id = edit::new_schedule(p, def.category);
            if let Some(nv) = p.view_mut(id) {
                nv.name = name.clone();
                nv.phase = phase.or(nv.phase);
                nv.kind = ViewKind::Schedule(def.clone());
            }
            Ok(id)
        });
        if let Some(id) = made {
            app.open_view(id);
        }
    } else if ok {
        let mut nv = v.clone();
        nv.kind = ViewKind::Schedule(st.def.clone());
        update_view(app, vid, "Schedule Properties", nv);
    }
    if ok || cancel || !open {
        app.dialogs.schedule_props = None;
        app.dialogs.new_schedule_pending = None;
        ctx.data_mut(|m| m.remove::<SchedPropsState>(key));
    } else {
        app.dialogs.schedule_props = Some((vid, tab));
        ctx.data_mut(|m| m.insert_temp(key, st));
    }
}

/// New Sheet: the title block and the placeholder sheet ("New").
fn new_sheet(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.new_sheet {
        return;
    }
    let key = egui::Id::new("new-sheet");
    let mut sel: usize = ctx.data(|m| m.get_temp(key)).unwrap_or_else(|| {
        // The template's usual title block: A1 metric, ARCH E1 imperial.
        let want = if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { SheetSize::ArchE1 } else { SheetSize::A1 };
        SheetSize::ALL.iter().position(|s| *s == want).unwrap_or(0)
    });
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("New Sheet").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
        ui.label("Select titleblocks:");
        ui.horizontal_top(|ui| {
            egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                ui.set_min_size(vec2(300.0, 130.0));
                egui::ScrollArea::vertical().id_salt("tb").max_height(130.0).auto_shrink([false, false]).show(ui, |ui| {
                    ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                        for (k, s) in SheetSize::ALL.iter().enumerate() {
                            let r = ui.selectable_label(sel == k, s.label());
                            if r.clicked() {
                                sel = k;
                            }
                            if r.double_clicked() {
                                ok = true;
                            }
                        }
                        let none = SheetSize::ALL.len();
                        let r = ui.selectable_label(sel == none, "None");
                        if r.clicked() {
                            sel = none;
                        }
                        if r.double_clicked() {
                            ok = true;
                        }
                    });
                });
            });
            ui.add_enabled(false, egui::Button::new("Load...").min_size(vec2(70.0, 22.0)));
        });
        ui.add_space(8.0);
        ui.label("Select placeholder sheets:");
        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
            ui.set_min_size(vec2(300.0, 90.0));
            ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                let _ = ui.selectable_label(true, "New");
            });
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            cancel = super::dlg_button(ui, "Cancel", false, true);
            if super::dlg_button(ui, "OK", true, true) {
                ok = true;
            }
        });
    });
    if ok {
        let none = sel >= SheetSize::ALL.len();
        let s = SheetSize::ALL[sel.min(SheetSize::ALL.len() - 1)];
        if let Some(id) = app.run("New Sheet", |p| {
            let id = edit::new_sheet(p, s);
            if let Some(ViewKind::Sheet(sh)) = p.view_mut(id).map(|v| &mut v.kind) {
                sh.no_title_block = none;
            }
            Ok(id)
        }) {
            app.open_view(id);
        }
    }
    if ok || cancel || !open {
        app.dialogs.new_sheet = false;
        ctx.data_mut(|m| m.remove::<usize>(key));
    } else {
        ctx.data_mut(|m| m.insert_temp(key, sel));
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
                crate::style::check(ui, &mut r.issued, "");
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
            crate::style::check(ui, &mut o.halftone, "");
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
