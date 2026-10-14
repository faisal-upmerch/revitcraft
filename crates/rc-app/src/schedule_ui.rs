//! Schedule views: a live table of elements laid out like the reference schedule view
//! (column letters, title row, headers, gridded cells); instance values edit in place.

use crate::app::App;
use crate::style;
use eframe::egui::{self, Color32, Rect, Sense, Stroke, pos2, vec2};
use rc_core::model::*;
use rc_core::schedule::RowKind;

const ROW_H: f32 = 21.0;

fn letters(k: usize) -> String {
    let mut k = k;
    let mut s = String::new();
    loop {
        s.insert(0, (b'A' + (k % 26) as u8) as char);
        if k < 26 {
            break;
        }
        k = k / 26 - 1;
    }
    s
}

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let ViewKind::Schedule(def) = &view.kind else { return };
    let Some(table) = app.table(view_id) else { return };
    let editable: Vec<bool> = table.columns.iter().map(|c| !c.def.read_only && !def.sheet_list && !def.keynote_legend && !def.material_takeoff).collect();
    let font = style::font(12.0);
    // Column widths from the content.
    let widths: Vec<f32> = (0..table.columns.len())
        .map(|ci| {
            let mut w = ui.painter().layout_no_wrap(table.columns[ci].def.name.clone(), font.clone(), Color32::BLACK).size().x;
            for r in &table.rows {
                if let Some(c) = r.cells.get(ci) {
                    w = w.max(ui.painter().layout_no_wrap(c.clone(), font.clone(), Color32::BLACK).size().x);
                }
            }
            (w + 14.0).clamp(70.0, 360.0)
        })
        .collect();
    let total_w: f32 = widths.iter().sum::<f32>().max(200.0);
    let mut edits: Vec<(Id, String, String)> = Vec::new();
    let mut select_rows: Option<Vec<Id>> = None;
    let grid = Stroke::new(1.0, Color32::from_gray(200));
    egui::Frame::new().fill(style::canvas(app.settings.black_canvas)).show(ui, |ui| {
        ui.set_min_size(ui.available_size());
        egui::ScrollArea::both().auto_shrink([false, false]).show(ui, |ui| {
            let origin = ui.cursor().min + vec2(10.0, 10.0);
            let rows_n = table.rows.len();
            let height = ROW_H * (3 + rows_n) as f32 + 20.0;
            ui.allocate_exact_size(vec2(total_w + 20.0, height), Sense::hover());
            let p = ui.painter().clone();
            let xs: Vec<f32> = widths
                .iter()
                .scan(origin.x, |x, w| {
                    let x0 = *x;
                    *x += w;
                    Some(x0)
                })
                .collect();
            // Column letters.
            let lr = Rect::from_min_size(origin, vec2(total_w, ROW_H));
            p.rect_filled(lr, 0.0, Color32::from_rgb(236, 236, 236));
            for (k, x) in xs.iter().enumerate() {
                let cell = Rect::from_min_size(pos2(*x, origin.y), vec2(widths[k], ROW_H));
                p.text(cell.center(), egui::Align2::CENTER_CENTER, letters(k), style::font(11.5), Color32::from_gray(90));
                p.rect_stroke(cell, 0.0, grid, egui::StrokeKind::Inside);
            }
            // Title row.
            let tr = Rect::from_min_size(origin + vec2(0.0, ROW_H), vec2(total_w, ROW_H));
            p.rect_stroke(tr, 0.0, grid, egui::StrokeKind::Inside);
            p.text(tr.center(), egui::Align2::CENTER_CENTER, format!("<{}>", view.name), style::font(12.5), style::text());
            // Headers.
            for (k, x) in xs.iter().enumerate() {
                let cell = Rect::from_min_size(pos2(*x, origin.y + ROW_H * 2.0), vec2(widths[k], ROW_H));
                p.rect_stroke(cell, 0.0, grid, egui::StrokeKind::Inside);
                p.text(cell.center(), egui::Align2::CENTER_CENTER, &table.columns[k].def.name, font.clone(), style::text());
            }
            // Body.
            for (ri, row) in table.rows.iter().enumerate() {
                let y = origin.y + ROW_H * (3 + ri) as f32;
                let rr = Rect::from_min_size(pos2(origin.x, y), vec2(total_w, ROW_H));
                let selected = !row.ids.is_empty() && row.ids.iter().all(|id| app.selection.contains(id));
                if selected {
                    p.rect_filled(rr, 0.0, Color32::from_rgb(204, 228, 247));
                }
                let strong = matches!(row.kind, RowKind::Total | RowKind::Header | RowKind::Group);
                for (ci, cell) in row.cells.iter().enumerate() {
                    let Some(x) = xs.get(ci) else { continue };
                    let cr = Rect::from_min_size(pos2(*x, y), vec2(widths[ci], ROW_H));
                    p.rect_stroke(cr, 0.0, grid, egui::StrokeKind::Inside);
                    if row.kind == RowKind::Item && row.ids.len() == 1 && editable.get(ci).copied().unwrap_or(false) {
                        let key = egui::Id::new(("sched-cell", view_id, row.ids[0], ci));
                        let mut text: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| cell.clone());
                        let r = ui.put(cr.shrink2(vec2(4.0, 2.0)), egui::TextEdit::singleline(&mut text).frame(egui::Frame::NONE).font(font.clone()));
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
                        let f = if strong { style::bold(12.0) } else { font.clone() };
                        p.text(cr.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER, cell, f, style::text());
                        let resp = ui.interact(cr, egui::Id::new(("sched-sel", view_id, ri, ci)), Sense::click());
                        if resp.clicked() {
                            select_rows = Some(row.ids.clone());
                        }
                    }
                }
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
}
