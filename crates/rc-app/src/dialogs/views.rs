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
                        crate::style::check(ui, &mut def.itemize, "Itemize every instance");
                        crate::style::check(ui, &mut def.grand_total, "Grand totals");
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
                crate::style::check(ui, &mut def.group_headers, "Header and footer (group by the sort field)");
                ui.label("Totals for:");
                for f in def.fields.clone() {
                    let mut on = def.total_fields.contains(&f);
                    if crate::style::check(ui, &mut on, &f).changed() {
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
