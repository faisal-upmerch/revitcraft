//! Schedule views: a live table of elements; instance values can be edited in place.

use crate::app::App;
use crate::style;
use eframe::egui::{self, Sense, Stroke, vec2};
use egui_extras::{Column, TableBuilder};
use rc_core::model::*;
use rc_core::schedule::RowKind;

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let ViewKind::Schedule(def) = &view.kind else { return };
    let Some(table) = app.table(view_id) else { return };
    egui::Frame::new().fill(style::chrome()).inner_margin(egui::Margin::symmetric(8, 4)).show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.label(egui::RichText::new(format!("<{}>", view.name)).strong().size(14.0));
            ui.separator();
            if ui.button("Fields...").clicked() {
                app.dialogs.schedule_props = Some((view_id, 0));
            }
            if ui.button("Filter...").clicked() {
                app.dialogs.schedule_props = Some((view_id, 1));
            }
            if ui.button("Sorting/Grouping...").clicked() {
                app.dialogs.schedule_props = Some((view_id, 2));
            }
            ui.separator();
            if ui.button("Export CSV").clicked() {
                app.activate(view_id);
                crate::actions::exec(app, crate::commands::Cmd::ExportCsv);
            }
            if ui.button("Highlight in Model").on_hover_text("Selects the elements of the chosen rows").clicked() && !app.selection.is_empty() {
                if let Some(plan) = app.doc.data.views.iter().find(|v| matches!(v.kind, ViewKind::FloorPlan { .. }) && !v.is_template).map(|v| v.id) {
                    let sel = app.selection.clone();
                    app.open_view(plan);
                    app.select(sel);
                }
            }
            ui.label(egui::RichText::new(format!("{} rows", table.rows.iter().filter(|r| r.kind == RowKind::Item).count())).color(style::text_dim()));
        });
    });
    let editable: Vec<bool> = table.columns.iter().map(|c| !c.def.read_only && !def.sheet_list && !def.material_takeoff).collect();
    let n = table.columns.len().max(1);
    let p = app.doc.data.clone();
    let mut edits: Vec<(Id, String, String)> = Vec::new();
    let mut select_rows: Option<Vec<Id>> = None;
    egui::Frame::new().fill(style::field()).inner_margin(egui::Margin::same(6)).show(ui, |ui| {
        let tb = TableBuilder::new(ui).striped(true).resizable(true).cell_layout(egui::Layout::left_to_right(egui::Align::Center)).columns(Column::auto().at_least(90.0).clip(true), n).min_scrolled_height(0.0);
        tb.header(24.0, |mut header| {
            for c in &table.columns {
                header.col(|ui| {
                    ui.label(egui::RichText::new(&c.def.name).strong());
                });
            }
        })
        .body(|mut body| {
            for (ri, row) in table.rows.iter().enumerate() {
                let selected = !row.ids.is_empty() && row.ids.iter().all(|id| app.selection.contains(id));
                body.row(22.0, |mut tr| {
                    tr.set_selected(selected);
                    for (ci, cell) in row.cells.iter().enumerate() {
                        tr.col(|ui| {
                            let strong = matches!(row.kind, RowKind::Total | RowKind::Header | RowKind::Group);
                            if row.kind == RowKind::Item && row.ids.len() == 1 && editable.get(ci).copied().unwrap_or(false) {
                                let key = egui::Id::new(("sched-cell", view_id, row.ids[0], ci));
                                let mut text: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| cell.clone());
                                let r = ui.add(egui::TextEdit::singleline(&mut text).frame(egui::Frame::NONE).desired_width(f32::INFINITY));
                                if r.has_focus() {
                                    ui.memory_mut(|m| m.data.insert_temp(key, text.clone()));
                                }
                                if r.gained_focus() {
                                    select_rows = Some(row.ids.clone());
                                }
                                if r.lost_focus() {
                                    ui.memory_mut(|m| m.data.remove::<String>(key));
                                    if text != *cell {
                                        edits.push((row.ids[0], table.columns[ci].def.name.clone(), text));
                                    }
                                }
                            } else {
                                let rt = egui::RichText::new(cell);
                                let resp = ui.add(egui::Label::new(if strong { rt.strong() } else { rt }).sense(Sense::click()));
                                if resp.clicked() {
                                    select_rows = Some(row.ids.clone());
                                }
                            }
                        });
                    }
                    let _ = ri;
                });
            }
        });
    });
    if let Some(ids) = select_rows {
        app.select(ids);
    }
    if !edits.is_empty() {
        app.run("Edit Schedule", |pr| {
            for (id, name, v) in &edits {
                rc_core::params::set(pr, *id, name, v)?;
            }
            Ok(())
        });
    }
    let _ = (p, vec2(0.0, 0.0), Stroke::NONE);
}
