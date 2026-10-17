//! Schedule views: the schedule laid out as on a sheet (title, inserted header rows, header
//! groups, column headings and the body) under a row of column letters, like the reference
//! schedule view. Cells select (Shift extends along a row), header texts edit on double-click,
//! instance values edit in place, and a frozen header stays in view while scrolling.

use crate::app::App;
use crate::style;
use eframe::egui::{self, Color32, Rect, Sense, Stroke, pos2, vec2};
use rc_core::model::*;
use rc_core::schedule::{CellKey, GridRowKind, RowKind};

/// Screen pixels per paper millimetre.
const PX_PER_MM: f32 = 3.5;
const LETTER_H: f32 = 20.0;

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

/// The selected cells of a schedule view.
pub fn selected_cells(app: &App, view: Id) -> Vec<CellKey> {
    app.sched_cells.as_ref().filter(|(v, _)| *v == view).map(|(_, c)| c.clone()).unwrap_or_default()
}

/// The fields (columns) of the selected heading or body cells, left to right.
pub fn selected_fields(app: &App, view: Id) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for c in selected_cells(app, view) {
        if let CellKey::Header(f) | CellKey::Body(_, f) = c {
            if !out.contains(&f) {
                out.push(f);
            }
        }
    }
    out
}

/// Text of a header cell as it is edited (the title edits the view's name).
fn cell_text(view: &View, def: &ScheduleDef, key: &CellKey) -> Option<String> {
    match key {
        CellKey::Title => Some(view.name.clone()),
        CellKey::Extra(r, c) => def.header_rows.get(*r).map(|h| h.cells.get(*c).cloned().unwrap_or_default()),
        CellKey::Group(g) => def.groups.get(*g).map(|g| g.text.clone()),
        CellKey::Header(f) => Some({
            let h = def.format(f).heading;
            if h.is_empty() { f.clone() } else { h }
        }),
        _ => None,
    }
}

/// Writes an edited header text back into the view.
fn set_cell_text(v: &mut View, key: &CellKey, text: String) {
    if let CellKey::Title = key {
        if !text.trim().is_empty() {
            v.name = text.trim().to_string();
        }
        return;
    }
    let ViewKind::Schedule(def) = &mut v.kind else { return };
    match key {
        CellKey::Extra(r, c) => {
            if let Some(h) = def.header_rows.get_mut(*r) {
                if h.cells.len() <= *c {
                    h.cells.resize(*c + 1, String::new());
                }
                h.cells[*c] = text;
            }
        }
        CellKey::Group(g) => {
            if let Some(g) = def.groups.get_mut(*g) {
                g.text = text;
            }
        }
        CellKey::Header(f) => {
            let mut fm = def.format(f);
            fm.heading = if text == *f { String::new() } else { text };
            if fm == FieldFormat::default() {
                def.formats.remove(f);
            } else {
                def.formats.insert(f.clone(), fm);
            }
        }
        _ => {}
    }
}

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    let ViewKind::Schedule(def) = &view.kind else { return };
    let Some(grid) = app.grid(view_id) else { return };
    let table = &grid.table;
    let key_schedule = def.key.is_some();
    let editable: Vec<bool> = table.columns.iter().map(|c| key_schedule || (!c.def.read_only && !def.sheet_list && !def.keynote_legend && !def.material_takeoff)).collect();
    let mut key_edits: Vec<(usize, String, String)> = Vec::new();
    let widths: Vec<f32> = grid.widths.iter().map(|w| *w as f32 * PX_PER_MM).collect();
    let total_w: f32 = widths.iter().sum::<f32>().max(200.0);
    let sel = selected_cells(app, view_id);
    let edit_key = egui::Id::new(("sched-edit", view_id));
    let focus_key = egui::Id::new(("sched-edit-focused", view_id));
    let mut editing: Option<(CellKey, String)> = ui.memory(|m| m.data.get_temp(edit_key));
    // Focus goes to the edit box once, when editing starts.
    let mut focused: bool = ui.memory(|m| m.data.get_temp(focus_key)).unwrap_or(false);
    if let Some((v, key)) = app.sched_edit_request.take() {
        if v == view_id {
            editing = cell_text(&view, def, &key).map(|t| (key, t));
            focused = false;
        }
    }
    let mut commit: Option<(CellKey, String)> = None;
    let mut cell_edits: Vec<(Id, String, String)> = Vec::new();
    let mut click: Option<(CellKey, bool, Vec<Id>)> = None;
    let mut dbl: Option<CellKey> = None;
    let shift = ui.input(|i| i.modifiers.shift);
    let grid_line = Color32::from_gray(205);
    egui::Frame::new().fill(style::canvas(app.settings.black_canvas)).show(ui, |ui| {
        ui.set_min_size(ui.available_size());
        egui::ScrollArea::both().auto_shrink([false, false]).show(ui, |ui| {
            let origin = ui.cursor().min + vec2(10.0, 10.0);
            let rows_h: f32 = grid.rows.iter().map(|r| r.height as f32 * PX_PER_MM).sum();
            ui.allocate_exact_size(vec2(total_w + 20.0, LETTER_H + rows_h + 20.0), Sense::hover());
            let clip_top = ui.clip_rect().top();
            let p = ui.painter().clone();
            let xs: Vec<f32> = widths
                .iter()
                .scan(origin.x, |x, w| {
                    let x0 = *x;
                    *x += w;
                    Some(x0)
                })
                .collect();
            // Rows top to bottom; with Freeze Header the heading rows are drawn last, pinned
            // to the top of the view.
            let freeze = def.look.freeze_header;
            let mut y_of = Vec::new();
            let mut y = origin.y + LETTER_H;
            for r in &grid.rows {
                y_of.push(y);
                y += r.height as f32 * PX_PER_MM;
            }
            let head_h: f32 = LETTER_H + grid.rows[..grid.head_rows].iter().map(|r| r.height as f32 * PX_PER_MM).sum::<f32>();
            let shift_head = if freeze { (clip_top - origin.y).max(0.0) } else { 0.0 };
            let order: Vec<usize> = (grid.head_rows..grid.rows.len()).chain(0..grid.head_rows).collect();
            for ri in order {
                let row = &grid.rows[ri];
                let in_head = ri < grid.head_rows;
                let y = y_of[ri] + if in_head { shift_head } else { 0.0 };
                let h = row.height as f32 * PX_PER_MM;
                if in_head && freeze && ri == 0 {
                    // Mask the body scrolled under the frozen header.
                    p.rect_filled(Rect::from_min_size(pos2(origin.x - 10.0, origin.y + shift_head), vec2(total_w + 20.0, head_h)), 0.0, style::canvas(app.settings.black_canvas));
                }
                let rr = Rect::from_min_size(pos2(origin.x, y), vec2(total_w, h));
                let body = matches!(row.kind, GridRowKind::Body(_));
                if body && def.look.stripe_rows && row.table_row.is_some_and(|t| t % 2 == 1) {
                    p.rect_filled(rr, 0.0, Color32::from_rgb(240, 244, 250));
                }
                let row_selected = body && !row.ids.is_empty() && row.ids.iter().all(|id| app.selection.contains(id));
                if row_selected {
                    p.rect_filled(rr, 0.0, Color32::from_rgb(222, 236, 250));
                }
                let mut ci = 0;
                for c in &row.cells {
                    let x = xs.get(ci).copied().unwrap_or(origin.x);
                    let w: f32 = widths[ci.min(widths.len().saturating_sub(1))..(ci + c.span).min(widths.len())].iter().sum();
                    if c.covered {
                        ci += c.span;
                        continue;
                    }
                    let h: f32 = grid.rows[ri..(ri + c.rowspan).min(grid.rows.len())].iter().map(|r| r.height as f32 * PX_PER_MM).sum::<f32>().max(h);
                    let cr = Rect::from_min_size(pos2(x, y), vec2(w.max(1.0), h));
                    if let Some(s) = c.shading {
                        p.rect_filled(cr, 0.0, Color32::from_rgb(s[0], s[1], s[2]));
                    }
                    if c.key != CellKey::Blank && sel.contains(&c.key) {
                        p.rect_filled(cr, 0.0, Color32::from_rgb(204, 228, 247));
                    }
                    // Edges one by one: top, right, bottom, left.
                    let stroke = |wt: u8| match wt {
                        0 => Stroke::NONE,
                        1 => Stroke::new(1.0, grid_line),
                        2 => Stroke::new(1.5, Color32::from_gray(90)),
                        _ => Stroke::new(2.5, Color32::from_gray(40)),
                    };
                    let cs = cr.shrink(0.5);
                    for (k, (e0, e1)) in [(cs.left_top(), cs.right_top()), (cs.right_top(), cs.right_bottom()), (cs.right_bottom(), cs.left_bottom()), (cs.left_bottom(), cs.left_top())].iter().enumerate() {
                        let st = stroke(c.edges[k]);
                        if st.width > 0.0 {
                            p.line_segment([*e0, *e1], st);
                        }
                    }
                    if let Some(t) = c.image.and_then(crate::images::texture) {
                        p.image(t, cr.shrink(2.0), Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                    }
                    let font_px = (c.size as f32 * 4.8).clamp(8.0, 60.0);
                    let font = if c.bold { style::bold(font_px) } else { style::font(font_px) };
                    let color = Color32::from_rgb(c.color[0], c.color[1], c.color[2]);
                    let is_editing = editing.as_ref().is_some_and(|(k, _)| *k == c.key);
                    let field = match &c.key {
                        CellKey::Body(_, f) => Some(f.clone()),
                        _ => None,
                    };
                    let col_editable = field.as_ref().and_then(|f| table.columns.iter().position(|col| col.def.name == *f)).is_some_and(|k| editable.get(k).copied().unwrap_or(false));
                    if is_editing {
                        if let Some((_, text)) = editing.as_mut() {
                            let r = ui.put(cr.shrink2(vec2(3.0, 1.0)), egui::TextEdit::singleline(text).font(font.clone()));
                            if !focused {
                                r.request_focus();
                                focused = true;
                            }
                            if r.lost_focus() {
                                commit = Some((c.key.clone(), text.clone()));
                            }
                        }
                    } else if row.kind == GridRowKind::Body(RowKind::Item) && row.ids.len() == 1 && col_editable {
                        let key = egui::Id::new(("sched-cell", view_id, row.ids[0], ci));
                        let mut text: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| c.text.clone());
                        let r = ui.put(cr.shrink2(vec2(4.0, 2.0)), egui::TextEdit::singleline(&mut text).frame(egui::Frame::NONE).font(font.clone()).text_color(color));
                        if r.has_focus() {
                            ui.memory_mut(|m| m.data.insert_temp(key, text.clone()));
                        }
                        if r.gained_focus() {
                            click = Some((c.key.clone(), false, row.ids.clone()));
                        }
                        if r.lost_focus() {
                            ui.memory_mut(|m| m.data.remove::<String>(key));
                            if text != c.text {
                                match (key_schedule, row.table_row) {
                                    (true, Some(tr)) => key_edits.push((tr, field.clone().unwrap_or_default(), text)),
                                    _ => cell_edits.push((row.ids[0], field.clone().unwrap_or_default(), text)),
                                }
                            }
                        }
                    } else {
                        if !c.text.is_empty() {
                            let (at, align) = match (c.halign, c.valign) {
                                (1, 0) => (cr.center_top() + vec2(0.0, 2.0), egui::Align2::CENTER_TOP),
                                (2, 0) => (cr.right_top() + vec2(-4.0, 2.0), egui::Align2::RIGHT_TOP),
                                (_, 0) => (cr.left_top() + vec2(4.0, 2.0), egui::Align2::LEFT_TOP),
                                (1, 2) => (cr.center_bottom() - vec2(0.0, 2.0), egui::Align2::CENTER_BOTTOM),
                                (2, 2) => (cr.right_bottom() - vec2(4.0, 2.0), egui::Align2::RIGHT_BOTTOM),
                                (_, 2) => (cr.left_bottom() + vec2(4.0, -2.0), egui::Align2::LEFT_BOTTOM),
                                (1, _) => (cr.center(), egui::Align2::CENTER_CENTER),
                                (2, _) => (cr.right_center() - vec2(4.0, 0.0), egui::Align2::RIGHT_CENTER),
                                _ => (cr.left_center() + vec2(4.0, 0.0), egui::Align2::LEFT_CENTER),
                            };
                            // Italic text goes through a layout job (the painter has no italics).
                            let tr = if c.italic {
                                let mut job = egui::text::LayoutJob::default();
                                job.append(&c.text, 0.0, egui::TextFormat { font_id: font.clone(), color, italics: true, ..Default::default() });
                                let galley = p.layout_job(job);
                                let rect = align.anchor_size(at, galley.size());
                                p.galley(rect.min, galley, color);
                                rect
                            } else {
                                p.text(at, align, &c.text, font.clone(), color)
                            };
                            if c.underline {
                                p.line_segment([tr.left_bottom(), tr.right_bottom()], Stroke::new(1.0, color));
                            }
                        }
                        let resp = ui.interact(cr, egui::Id::new(("sched-sel", view_id, ri, ci)), Sense::click());
                        // Spacer cells (blank row, beside groups) cannot be selected.
                        if resp.clicked() && c.key != CellKey::Blank {
                            click = Some((c.key.clone(), shift, if body { row.ids.clone() } else { vec![] }));
                        }
                        if resp.double_clicked() {
                            dbl = Some(c.key.clone());
                        }
                    }
                    ci += c.span;
                }
            }
            // Column letters above everything.
            let ly = origin.y + shift_head;
            p.rect_filled(Rect::from_min_size(pos2(origin.x, ly), vec2(total_w, LETTER_H)), 0.0, Color32::from_rgb(236, 236, 236));
            let picked = selected_fields(app, view_id);
            for (k, x) in xs.iter().enumerate() {
                let cell = Rect::from_min_size(pos2(*x, ly), vec2(widths[k], LETTER_H));
                if table.columns.get(k).is_some_and(|c| picked.contains(&c.def.name)) {
                    p.rect_filled(cell, 0.0, Color32::from_rgb(204, 228, 247));
                }
                p.text(cell.center(), egui::Align2::CENTER_CENTER, letters(k), style::font(11.5), Color32::from_gray(90));
                p.rect_stroke(cell, 0.0, Stroke::new(1.0, grid_line), egui::StrokeKind::Inside);
            }
        });
    });
    // Editing ends on Enter or a click elsewhere; Escape cancels.
    if ui.input(|i| i.key_pressed(egui::Key::Escape)) {
        editing = None;
        commit = None;
    }
    if let Some((key, text)) = commit.take() {
        editing = None;
        let mut nv = view.clone();
        set_cell_text(&mut nv, &key, text);
        if format!("{nv:?}") != format!("{view:?}") {
            app.run("Edit Schedule Text", |p| {
                if let Some(x) = p.view_mut(view_id) {
                    *x = nv;
                }
                Ok(())
            });
        }
    }
    if let Some(key) = dbl {
        editing = cell_text(&view, def, &key).map(|t| (key, t));
        focused = false;
    }
    ui.memory_mut(|m| m.data.insert_temp(focus_key, focused && editing.is_some()));
    match &editing {
        Some(e) => ui.memory_mut(|m| {
            m.data.insert_temp(edit_key, e.clone());
        }),
        None => ui.memory_mut(|m| m.data.remove::<(CellKey, String)>(edit_key)),
    }
    if let Some((key, extend, ids)) = click {
        // Shift extends the selection along the same row (headings, header rows, body row).
        let same_row = |a: &CellKey, b: &CellKey| match (a, b) {
            (CellKey::Header(_), CellKey::Header(_)) => true,
            (CellKey::Extra(r1, _), CellKey::Extra(r2, _)) => r1 == r2,
            (CellKey::Body(r1, _), CellKey::Body(r2, _)) => r1 == r2,
            _ => false,
        };
        let cells = match sel.first() {
            Some(anchor) if extend && same_row(anchor, &key) => {
                let row = grid.rows.iter().find(|r| r.cells.iter().any(|c| c.key == key));
                match row {
                    Some(row) => {
                        let (ia, ib) = (row.cells.iter().position(|c| c.key == *anchor).unwrap_or(0), row.cells.iter().position(|c| c.key == key).unwrap_or(0));
                        let (lo, hi) = (ia.min(ib), ia.max(ib));
                        let mut v: Vec<CellKey> = row.cells[lo..=hi].iter().map(|c| c.key.clone()).collect();
                        // The anchor stays first.
                        if let Some(k) = v.iter().position(|c| c == anchor) {
                            let a = v.remove(k);
                            v.insert(0, a);
                        }
                        v
                    }
                    None => vec![key.clone()],
                }
            }
            _ => vec![key.clone()],
        };
        app.sched_cells = Some((view_id, cells));
        if !ids.is_empty() {
            app.select(ids);
        }
    }
    if !key_edits.is_empty() {
        let mut nv = view.clone();
        if let ViewKind::Schedule(d) = &mut nv.kind {
            if let Some(k) = &mut d.key {
                for (r, f, v) in &key_edits {
                    if let Some(row) = k.rows.get_mut(*r) {
                        row.insert(f.clone(), v.clone());
                    }
                }
            }
        }
        app.run("Edit Schedule", |p| {
            if let Some(x) = p.view_mut(view_id) {
                *x = nv;
            }
            Ok(())
        });
    }
    if !cell_edits.is_empty() {
        app.run("Edit Schedule", |pr| {
            for (id, name, v) in &cell_edits {
                rc_core::params::set(pr, *id, name, v)?;
            }
            Ok(())
        });
    }
}
