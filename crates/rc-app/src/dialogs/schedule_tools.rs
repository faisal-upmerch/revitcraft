//! Modify Schedule/Quantities tools: what each is enabled for, what it does, and their dialogs
//! (Format, Combine Parameters, Resize Column/Row, Edit Font, Edit Borders, Color, Split & Place).

use super::{dlg_button, window};
use crate::app::App;
use crate::commands::Cmd;
use crate::schedule_ui::{selected_cells, selected_fields};
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::model::*;
use rc_core::schedule::CellKey;
use rc_core::units::LengthUnit;

pub enum SchedTool {
    /// Format: (view, field, working format; None = project settings).
    Format(Id, String, Option<UnitFormat>),
    Combine(CombineState),
    /// Resize Column (fields) or Resize Row (a title or header row cell): (view, target, text).
    Resize(Id, ResizeTarget, String),
    /// Edit Font: (view, style keys, font).
    Font(Id, Vec<String>, FontSpec),
    /// Edit Borders: (view, style keys left to right, line weight, edits to apply).
    Borders(Id, Vec<String>, u8, Vec<BorderEdit>),
    /// Shading: (view, style keys, colour).
    Shading(Id, Vec<String>, [u8; 3]),
    /// Split & Place: (view, sheet index, segments).
    Split(Id, usize, u32),
}

/// A border change in Edit Borders, applied on OK.
#[derive(Clone, Copy, PartialEq)]
pub enum BorderEdit {
    None,
    Outside(u8),
    Inside(u8),
    /// One outer edge of the selection: 0 top, 1 right, 2 bottom, 3 left.
    Edge(usize, u8),
}

pub enum ResizeTarget {
    Columns(Vec<String>),
    Title,
    Row(usize),
}

pub struct CombineState {
    pub view: Id,
    pub name: String,
    pub parts: Vec<CombinedPart>,
    pub avail_sel: Option<String>,
    pub part_sel: Option<usize>,
}

fn schedule_view(app: &App) -> Option<View> {
    app.active_view().filter(|v| matches!(v.kind, ViewKind::Schedule(_))).cloned()
}

fn def_of(v: &View) -> Option<&ScheduleDef> {
    match &v.kind {
        ViewKind::Schedule(d) => Some(d),
        _ => None,
    }
}

/// Changes the active schedule's view in one undo step.
fn modify(app: &mut App, name: &str, f: impl FnOnce(&mut View)) {
    let Some(v) = schedule_view(app) else { return };
    let mut nv = v.clone();
    f(&mut nv);
    let vid = v.id;
    if format!("{nv:?}") != format!("{v:?}") {
        app.run(name, |p| {
            if let Some(x) = p.view_mut(vid) {
                *x = nv;
            }
            Ok(())
        });
    }
}

fn numeric_field(p: &Project, def: &ScheduleDef, field: &str) -> Option<ParamKind> {
    rc_core::schedule::available_fields(p, def).into_iter().find(|f| f.name == field).and_then(|f| match f.kind {
        rc_core::params::PKind::Value(k) if k.is_numeric() => Some(k),
        _ => None,
    })
}

/// Style keys of the selected cells.
fn style_keys(app: &App, view: Id) -> Vec<String> {
    let mut out: Vec<String> = selected_cells(app, view).iter().filter_map(|c| c.style_key()).collect();
    out.dedup();
    out
}

/// Whether a schedule tool can run now (None for other commands).
pub fn enabled(app: &App, cmd: Cmd) -> Option<bool> {
    use Cmd::*;
    let is_sched = matches!(
        cmd,
        SchedFormatUnit | SchedCalculated | SchedCombine | SchedColInsert | SchedColDelete | SchedColResize | SchedColHide | SchedColUnhide | SchedRowInsert | SchedRowInsertAbove | SchedRowInsertBelow | SchedRowInsertData | SchedRowDelete | SchedRowResize | SchedMerge | SchedInsertImage | SchedClearCell | SchedGroup | SchedUngroup | SchedFreeze | SchedShading | SchedBorders | SchedReset | SchedFont | SchedAlignLeft | SchedAlignCenter | SchedAlignRight | SchedAlignVertical | SchedAlignTop | SchedAlignMiddle | SchedAlignBottom | SchedSplit
    );
    if !is_sched {
        return None;
    }
    let Some(v) = schedule_view(app) else { return Some(false) };
    let def = def_of(&v)?;
    let cells = selected_cells(app, v.id);
    let fields = selected_fields(app, v.id);
    let first = cells.first();
    let title_or_extra = matches!(first, Some(CellKey::Title | CellKey::Extra(..)));
    Some(match cmd {
        SchedCalculated | SchedCombine | SchedColInsert | SchedFreeze => true,
        SchedColUnhide => def.formats.values().any(|f| f.hidden),
        SchedFormatUnit => fields.len() == 1 && numeric_field(&app.doc.data, def, &fields[0]).is_some(),
        SchedColDelete | SchedColHide | SchedColResize => !fields.is_empty(),
        SchedRowInsert | SchedRowInsertBelow => title_or_extra,
        SchedRowInsertAbove => matches!(first, Some(CellKey::Extra(..))),
        SchedRowDelete => cells.iter().any(|c| matches!(c, CellKey::Extra(..))) || (def.key.is_some() && cells.iter().any(|c| matches!(c, CellKey::Body(..)))),
        SchedRowResize => title_or_extra,
        SchedMerge => {
            let extra: Vec<&CellKey> = cells.iter().filter(|c| matches!(c, CellKey::Extra(..))).collect();
            match extra.first() {
                Some(CellKey::Extra(r, c)) => extra.len() >= 2 || def.header_rows.get(*r).is_some_and(|h| h.merges.iter().any(|(a, _)| a == c)),
                _ => false,
            }
        }
        SchedInsertImage => title_or_extra,
        SchedClearCell => cells.iter().any(|c| matches!(c, CellKey::Title | CellKey::Extra(..) | CellKey::Group(_))),
        SchedGroup => cells.iter().filter(|c| matches!(c, CellKey::Header(_))).count() >= 2,
        SchedUngroup => cells.iter().any(|c| matches!(c, CellKey::Group(_))),
        SchedShading | SchedBorders | SchedReset | SchedFont | SchedAlignLeft | SchedAlignCenter | SchedAlignRight | SchedAlignVertical | SchedAlignTop | SchedAlignMiddle | SchedAlignBottom => cells.iter().any(|c| c.style_key().is_some()),
        SchedSplit => app.doc.data.views.iter().any(|x| matches!(x.kind, ViewKind::Sheet(_))) && app.cache.grids.get(&v.id).is_none_or(|g| g.table.rows.len() >= 2),
        // Data rows belong to key schedules, as in the reference app.
        SchedRowInsertData => def.key.is_some(),
        _ => false,
    })
}

/// Runs a schedule tool; false for other commands.
pub fn exec(app: &mut App, cmd: Cmd) -> bool {
    use Cmd::*;
    if !matches!(enabled(app, cmd), Some(_)) {
        return false;
    }
    let Some(v) = schedule_view(app) else { return true };
    let vid = v.id;
    let Some(def) = def_of(&v).cloned() else { return true };
    let cells = selected_cells(app, vid);
    let fields = selected_fields(app, vid);
    match cmd {
        SchedCalculated => {
            app.dialogs.sched_calc_pending = true;
            app.dialogs.schedule_props = Some((vid, 0));
        }
        SchedColInsert => app.dialogs.schedule_props = Some((vid, 0)),
        SchedFormatUnit => {
            if let Some(f) = fields.first() {
                app.dialogs.sched_tool = Some(SchedTool::Format(vid, f.clone(), def.format(f).units));
            }
        }
        SchedCombine => app.dialogs.sched_tool = Some(SchedTool::Combine(CombineState { view: vid, name: String::new(), parts: Vec::new(), avail_sel: None, part_sel: None })),
        SchedColDelete => {
            modify(app, "Delete Column", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    d.fields.retain(|x| !fields.contains(x));
                    for f in &fields {
                        d.formats.remove(f);
                    }
                }
            });
            app.sched_cells = None;
        }
        SchedColHide => {
            modify(app, "Hide Column", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    for f in &fields {
                        d.formats.entry(f.clone()).or_default().hidden = true;
                    }
                }
            });
            app.sched_cells = None;
        }
        SchedColUnhide => modify(app, "Unhide All Columns", |v| {
            if let ViewKind::Schedule(d) = &mut v.kind {
                for fm in d.formats.values_mut() {
                    fm.hidden = false;
                }
            }
        }),
        SchedColResize => {
            let w = fields.first().and_then(|f| def.format(f).width).or_else(|| {
                let g = app.cache.grids.get(&vid)?;
                let k = g.table.columns.iter().position(|c| fields.first() == Some(&c.def.name))?;
                g.widths.get(k).copied()
            });
            app.dialogs.sched_tool = Some(SchedTool::Resize(vid, ResizeTarget::Columns(fields), paper_text(app, w.unwrap_or(25.0))));
        }
        SchedRowInsert | SchedRowInsertAbove | SchedRowInsertBelow => {
            let at = match (cells.first(), cmd) {
                (Some(CellKey::Extra(r, _)), SchedRowInsertAbove) => *r,
                (Some(CellKey::Extra(r, _)), _) => r + 1,
                _ => 0,
            };
            modify(app, "Insert Row", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    let n = d.fields.len();
                    d.header_rows.insert(at.min(d.header_rows.len()), HeaderRow { cells: vec![String::new(); n], ..Default::default() });
                }
            });
            app.sched_cells = Some((vid, vec![CellKey::Extra(at, 0)]));
        }
        SchedRowInsertData => {
            modify(app, "Insert Data Row", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    if let Some(k) = &mut d.key {
                        // Keys number on from the highest so far.
                        let next = k.rows.iter().filter_map(|r| r.get("Key Name").and_then(|x| x.parse::<u32>().ok())).max().unwrap_or(0) + 1;
                        let mut row = std::collections::BTreeMap::new();
                        row.insert("Key Name".to_string(), next.to_string());
                        k.rows.push(row);
                    }
                }
            });
        }
        SchedRowDelete if def.key.is_some() && !cells.iter().any(|c| matches!(c, CellKey::Extra(..))) => {
            let mut rows: Vec<usize> = cells.iter().filter_map(|c| if let CellKey::Body(r, _) = c { Some(*r) } else { None }).collect();
            rows.sort();
            rows.dedup();
            modify(app, "Delete Row", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    if let Some(k) = &mut d.key {
                        for r in rows.iter().rev() {
                            if *r < k.rows.len() {
                                k.rows.remove(*r);
                            }
                        }
                    }
                }
            });
            app.sched_cells = None;
        }
        SchedRowDelete => {
            let mut rows: Vec<usize> = cells.iter().filter_map(|c| if let CellKey::Extra(r, _) = c { Some(*r) } else { None }).collect();
            rows.sort();
            rows.dedup();
            modify(app, "Delete Row", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    for r in rows.iter().rev() {
                        if *r < d.header_rows.len() {
                            d.header_rows.remove(*r);
                        }
                    }
                }
            });
            app.sched_cells = None;
        }
        SchedRowResize => {
            let (target, h) = match cells.first() {
                Some(CellKey::Extra(r, _)) => (ResizeTarget::Row(*r), def.header_rows.get(*r).and_then(|h| h.height).unwrap_or(rc_core::schedule::ROW_MM)),
                _ => (ResizeTarget::Title, def.title_height.unwrap_or(rc_core::schedule::ROW_MM + 1.0)),
            };
            app.dialogs.sched_tool = Some(SchedTool::Resize(vid, target, paper_text(app, h)));
        }
        SchedMerge => {
            let extra: Vec<(usize, usize)> = cells.iter().filter_map(|c| if let CellKey::Extra(r, c) = c { Some((*r, *c)) } else { None }).collect();
            if let Some(&(r, _)) = extra.first() {
                let lo = extra.iter().map(|x| x.1).min().unwrap_or(0);
                let hi = extra.iter().map(|x| x.1).max().unwrap_or(0);
                modify(app, "Merge Unmerge", |v| {
                    if let ViewKind::Schedule(d) = &mut v.kind {
                        if let Some(h) = d.header_rows.get_mut(r) {
                            if extra.len() == 1 {
                                // A merged cell splits back into its columns.
                                h.merges.retain(|(a, _)| *a != lo);
                            } else {
                                h.merges.retain(|(a, b)| *b < lo || *a > hi);
                                h.merges.push((lo, hi));
                                // The merged cell keeps the first non-empty text.
                                let text = (lo..=hi).filter_map(|c| h.cells.get(c)).find(|t| !t.is_empty()).cloned().unwrap_or_default();
                                for c in lo..=hi {
                                    if let Some(t) = h.cells.get_mut(c) {
                                        *t = if c == lo { text.clone() } else { String::new() };
                                    }
                                }
                            }
                        }
                    }
                });
                app.sched_cells = Some((vid, vec![CellKey::Extra(r, lo)]));
            }
        }
        SchedInsertImage => {
            let Some(target) = cells.first().cloned() else { return true };
            if let Some(path) = crate::files::FileDialog::new().add_filter("Image Files", &["bmp", "jpg", "jpeg", "png"]).pick_file() {
                match crate::images::load_file(&path, 0) {
                    Ok(asset) => {
                        app.run("Insert Image", |p| {
                            let id = p.new_id();
                            p.images.push(ImageAsset { id, ..asset });
                            if let Some(ViewKind::Schedule(d)) = p.view_mut(vid).map(|v| &mut v.kind) {
                                match target {
                                    CellKey::Title => d.title_image = Some(id),
                                    CellKey::Extra(r, c) => {
                                        if let Some(h) = d.header_rows.get_mut(r) {
                                            h.images.insert(c, id);
                                        }
                                    }
                                    _ => {}
                                }
                            }
                            Ok(())
                        });
                    }
                    Err(e) => app.error(e),
                }
            }
        }
        SchedClearCell => modify(app, "Clear Cell", |v| {
            if let ViewKind::Schedule(d) = &mut v.kind {
                for c in &cells {
                    match c {
                        CellKey::Title => d.title_image = None,
                        CellKey::Extra(r, col) => {
                            if let Some(h) = d.header_rows.get_mut(*r) {
                                if let Some(t) = h.cells.get_mut(*col) {
                                    t.clear();
                                }
                                h.images.remove(col);
                            }
                        }
                        CellKey::Group(g) => {
                            if let Some(g) = d.groups.get_mut(*g) {
                                g.text.clear();
                            }
                        }
                        _ => {}
                    }
                }
            }
        }),
        SchedGroup => {
            let heads: Vec<String> = cells.iter().filter_map(|c| if let CellKey::Header(f) = c { Some(f.clone()) } else { None }).collect();
            let order: Vec<String> = def.fields.iter().filter(|f| heads.contains(f)).cloned().collect();
            if let (Some(first), Some(last)) = (order.first().cloned(), order.last().cloned()) {
                let idx = def.groups.len();
                modify(app, "Group", |v| {
                    if let ViewKind::Schedule(d) = &mut v.kind {
                        d.groups.push(HeaderGroup { first, last, text: String::new() });
                    }
                });
                // Type the group's heading next, as in the reference app.
                app.sched_cells = Some((vid, vec![CellKey::Group(idx)]));
                app.sched_edit_request = Some((vid, CellKey::Group(idx)));
            }
        }
        SchedUngroup => {
            let mut gs: Vec<usize> = cells.iter().filter_map(|c| if let CellKey::Group(g) = c { Some(*g) } else { None }).collect();
            gs.sort();
            modify(app, "Ungroup", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    for g in gs.iter().rev() {
                        if *g < d.groups.len() {
                            d.groups.remove(*g);
                        }
                    }
                }
            });
            app.sched_cells = None;
        }
        SchedFreeze => modify(app, "Freeze Header", |v| {
            if let ViewKind::Schedule(d) = &mut v.kind {
                d.look.freeze_header = !d.look.freeze_header;
            }
        }),
        SchedShading => {
            let keys = style_keys(app, vid);
            let c = keys.first().and_then(|k| def.styles.get(k)).and_then(|s| s.shading).unwrap_or([255, 255, 255]);
            app.dialogs.sched_tool = Some(SchedTool::Shading(vid, keys, c));
        }
        SchedBorders => {
            let keys = style_keys(app, vid);
            let w = keys.first().and_then(|k| def.styles.get(k)).and_then(|s| s.border).unwrap_or(1);
            app.dialogs.sched_tool = Some(SchedTool::Borders(vid, keys, w, Vec::new()));
        }
        SchedFont => {
            let keys = style_keys(app, vid);
            let f = keys.first().and_then(|k| def.styles.get(k)).and_then(|s| s.font.clone()).unwrap_or_else(|| FontSpec {
                bold: matches!(cells.first(), Some(CellKey::Title | CellKey::Header(_) | CellKey::Group(_))),
                size: if matches!(cells.first(), Some(CellKey::Title)) { 3.0 } else { 2.5 },
                ..Default::default()
            });
            app.dialogs.sched_tool = Some(SchedTool::Font(vid, keys, f));
        }
        SchedReset => {
            let keys = style_keys(app, vid);
            modify(app, "Reset", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    for k in &keys {
                        d.styles.remove(k);
                    }
                }
            });
        }
        SchedAlignLeft | SchedAlignCenter | SchedAlignRight | SchedAlignVertical | SchedAlignTop | SchedAlignMiddle | SchedAlignBottom => {
            let keys = style_keys(app, vid);
            let (h, va) = match cmd {
                SchedAlignLeft => (Some(0u8), None),
                SchedAlignCenter => (Some(1), None),
                SchedAlignRight => (Some(2), None),
                SchedAlignTop => (None, Some(0u8)),
                SchedAlignBottom => (None, Some(2)),
                _ => (None, Some(1)),
            };
            modify(app, "Align", |v| {
                if let ViewKind::Schedule(d) = &mut v.kind {
                    for k in &keys {
                        // A column's body alignment is its Formatting alignment.
                        if let (Some(a), Some(field)) = (h, k.strip_prefix("b:")) {
                            d.formats.entry(field.to_string()).or_default().align = a;
                        }
                        let st = d.styles.entry(k.clone()).or_default();
                        if let Some(a) = h {
                            st.halign = if k.starts_with("b:") { None } else { Some(a) };
                        }
                        if let Some(a) = va {
                            st.valign = Some(a);
                        }
                        if *st == CellStyle::default() {
                            d.styles.remove(k);
                        }
                    }
                }
            });
        }
        SchedSplit => app.dialogs.sched_tool = Some(SchedTool::Split(vid, 0, 2)),
        _ => {}
    }
    true
}

fn paper_text(app: &App, mm: f64) -> String {
    // Paper sizes read in inches in imperial projects, millimetres otherwise.
    if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { format!("{:.4}\"", mm / 25.4) } else { format!("{mm:.1} mm") }
}

fn parse_paper(app: &App, text: &str) -> Option<f64> {
    let t = text.trim();
    let num = |s: &str| s.trim().parse::<f64>().ok();
    if let Some(x) = t.strip_suffix('"') {
        return num(x).map(|v| v * 25.4);
    }
    if let Some(x) = t.strip_suffix("mm") {
        return num(x);
    }
    let v = num(t)?;
    Some(if app.doc.data.units.system == rc_core::units::UnitSystem::Imperial { v * 25.4 } else { v })
}

/// The Format dialog's body: project settings or the column's own units.
pub fn format_ui(ui: &mut egui::Ui, uf: &mut Option<UnitFormat>, kind: ParamKind, project: &rc_core::units::Units) {
    let mut use_project = uf.is_none();
    if crate::style::check(ui, &mut use_project, "Use project settings").changed() {
        *uf = if use_project { None } else { Some(UnitFormat { length: Some(project.length), decimals: project.length_decimals, symbol: false, suppress_zeros: false, plus: false, grouping: false }) };
    }
    let mut cur = uf.clone().unwrap_or(UnitFormat { length: Some(project.length), decimals: if kind == ParamKind::Length { project.length_decimals } else { project.area_decimals }, symbol: false, suppress_zeros: false, plus: false, grouping: false });
    ui.add_enabled_ui(!use_project, |ui| {
        egui::Grid::new("fmt-units").num_columns(2).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
            ui.label("Units:");
            if kind == ParamKind::Length {
                let unit = cur.length.unwrap_or(project.length);
                egui::ComboBox::from_id_salt("fmt-unit").selected_text(unit.label()).width(200.0).show_ui(ui, |ui| {
                    for u in LengthUnit::ALL {
                        if ui.selectable_label(unit == u, u.label()).clicked() {
                            cur.length = Some(u);
                        }
                    }
                });
            } else {
                ui.label(match kind {
                    ParamKind::Area => project.area(0.0).split_whitespace().last().unwrap_or("").to_string(),
                    ParamKind::Volume => project.volume(0.0).split_whitespace().last().unwrap_or("").to_string(),
                    _ => "General".into(),
                });
            }
            ui.end_row();
            ui.label("Rounding:");
            let label = |d: u8| if d == 0 { "0 decimal places".to_string() } else { format!("{d} decimal place{}", if d == 1 { "" } else { "s" }) };
            egui::ComboBox::from_id_salt("fmt-round").selected_text(label(cur.decimals)).width(200.0).show_ui(ui, |ui| {
                for d in 0..=6u8 {
                    ui.selectable_value(&mut cur.decimals, d, label(d));
                }
            });
            ui.end_row();
            ui.label("Unit symbol:");
            crate::style::check(ui, &mut cur.symbol, "Show");
            ui.end_row();
        });
        crate::style::check(ui, &mut cur.suppress_zeros, "Suppress trailing 0's");
        crate::style::check(ui, &mut cur.plus, "Show + for positive values");
        crate::style::check(ui, &mut cur.grouping, "Use digit grouping");
    });
    if !use_project {
        *uf = Some(cur);
    }
}

fn ok_cancel(ui: &mut egui::Ui, ok_enabled: bool) -> (bool, bool) {
    let (mut ok, mut cancel) = (false, false);
    ui.add_space(8.0);
    ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
        ui.spacing_mut().item_spacing.x = 8.0;
        cancel = dlg_button(ui, "Cancel", false, true);
        ok = dlg_button(ui, "OK", true, ok_enabled);
    });
    (ok, cancel)
}

fn set_styles(app: &mut App, vid: Id, name: &str, keys: &[String], f: impl Fn(&mut CellStyle)) {
    let keys = keys.to_vec();
    let _ = vid;
    modify(app, name, |v| {
        if let ViewKind::Schedule(d) = &mut v.kind {
            for k in &keys {
                let st = d.styles.entry(k.clone()).or_default();
                f(st);
            }
        }
    });
}

pub fn show(app: &mut App, ctx: &egui::Context) {
    let Some(tool) = app.dialogs.sched_tool.take() else { return };
    let keep: bool;
    let mut open = true;
    let next = match tool {
        SchedTool::Format(vid, field, mut uf) => {
            let kind = app.doc.data.view(vid).and_then(def_of).and_then(|d| numeric_field(&app.doc.data, d, &field)).unwrap_or(ParamKind::Number);
            let units = app.doc.data.units.clone();
            let (mut ok, mut cancel) = (false, false);
            window("Format").open(&mut open).resizable(false).default_width(300.0).show(ctx, |ui| {
                format_ui(ui, &mut uf, kind, &units);
                (ok, cancel) = ok_cancel(ui, true);
            });
            if ok {
                let f = field.clone();
                let u = uf.clone();
                modify(app, "Format Unit", |v| {
                    if let ViewKind::Schedule(d) = &mut v.kind {
                        d.formats.entry(f).or_default().units = u;
                    }
                });
            }
            keep = !(ok || cancel);
            SchedTool::Format(vid, field, uf)
        }
        SchedTool::Combine(mut st) => {
            let def = app.doc.data.view(st.view).and_then(def_of).cloned().unwrap_or_default();
            let available: Vec<String> = rc_core::schedule::available_fields(&app.doc.data, &def).into_iter().map(|f| f.name).filter(|n| !def.combined.iter().any(|c| c.name == *n)).collect();
            let (mut ok, mut cancel) = (false, false);
            window("Combine Parameters").open(&mut open).resizable(false).default_width(560.0).show(ctx, |ui| {
                ui.label("Select two or more parameters to combine their values.  The values for combined parameters are read-only in schedules.");
                ui.add_space(4.0);
                ui.horizontal_top(|ui| {
                    ui.vertical(|ui| {
                        ui.set_width(170.0);
                        ui.label("Parameter Type:");
                        egui::ComboBox::from_id_salt("comb-type").selected_text(def.category.label()).width(160.0).show_ui(ui, |ui| {
                            let _ = ui.selectable_label(true, def.category.label());
                        });
                        ui.add_space(4.0);
                        ui.label("Schedule Parameters:");
                        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                            ui.set_min_size(vec2(160.0, 220.0));
                            egui::ScrollArea::vertical().max_height(220.0).auto_shrink([false, false]).show(ui, |ui| {
                                ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                                    for f in &available {
                                        let r = ui.selectable_label(st.avail_sel.as_ref() == Some(f), f);
                                        if r.clicked() {
                                            st.avail_sel = Some(f.clone());
                                        }
                                        if r.double_clicked() {
                                            st.parts.push(CombinedPart { field: f.clone(), separator: "/".into(), ..Default::default() });
                                        }
                                    }
                                });
                            });
                        });
                    });
                    ui.vertical(|ui| {
                        ui.add_space(100.0);
                        if ui.add_enabled(st.avail_sel.is_some(), egui::Button::new(" ➡ ")).clicked() {
                            if let Some(f) = st.avail_sel.clone() {
                                st.parts.push(CombinedPart { field: f, separator: "/".into(), ..Default::default() });
                            }
                        }
                        if ui.add_enabled(st.part_sel.is_some(), egui::Button::new(" ⬅ ")).clicked() {
                            if let Some(k) = st.part_sel.take() {
                                if k < st.parts.len() {
                                    st.parts.remove(k);
                                }
                            }
                        }
                    });
                    ui.vertical(|ui| {
                        ui.label("Combined Parameter Name:");
                        ui.add(egui::TextEdit::singleline(&mut st.name).desired_width(330.0));
                        ui.add_space(4.0);
                        ui.label("Combined Parameter:");
                        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                            ui.set_min_size(vec2(330.0, 150.0));
                            egui::Grid::new("comb-parts").num_columns(5).striped(true).spacing(vec2(6.0, 4.0)).show(ui, |ui| {
                                for h in ["Name", "Prefix", "Sample Value", "Suffix", "Separator"] {
                                    ui.label(egui::RichText::new(h).strong());
                                }
                                ui.end_row();
                                for (k, part) in st.parts.iter_mut().enumerate() {
                                    if ui.selectable_label(st.part_sel == Some(k), &part.field).clicked() {
                                        st.part_sel = Some(k);
                                    }
                                    ui.add(egui::TextEdit::singleline(&mut part.prefix).desired_width(44.0));
                                    ui.label("<value>");
                                    ui.add(egui::TextEdit::singleline(&mut part.suffix).desired_width(44.0));
                                    ui.add(egui::TextEdit::singleline(&mut part.separator).desired_width(44.0));
                                    ui.end_row();
                                }
                            });
                        });
                        ui.horizontal(|ui| {
                            let sel = st.part_sel.filter(|k| *k < st.parts.len());
                            if ui.add_enabled(sel.is_some_and(|k| k > 0), egui::Button::new("Move Up")).clicked() {
                                let k = sel.unwrap();
                                st.parts.swap(k, k - 1);
                                st.part_sel = Some(k - 1);
                            }
                            if ui.add_enabled(sel.is_some_and(|k| k + 1 < st.parts.len()), egui::Button::new("Move Down")).clicked() {
                                let k = sel.unwrap();
                                st.parts.swap(k, k + 1);
                                st.part_sel = Some(k + 1);
                            }
                        });
                        let preview: String = st.parts.iter().enumerate().map(|(k, p)| format!("{}<{}>{}{}", p.prefix, p.field, p.suffix, if k + 1 < st.parts.len() { p.separator.as_str() } else { "" })).collect();
                        ui.label(format!("Preview of value: {preview}"));
                    });
                });
                (ok, cancel) = ok_cancel(ui, st.parts.len() >= 2 && !st.name.trim().is_empty());
            });
            if ok {
                let name = st.name.trim().to_string();
                if def.fields.contains(&name) || available.contains(&name) {
                    app.error("The name is already in use.");
                    ok = false;
                } else {
                    let parts = st.parts.clone();
                    modify(app, "Combine Parameters", |v| {
                        if let ViewKind::Schedule(d) = &mut v.kind {
                            d.combined.push(CombinedField { name: name.clone(), parts });
                            d.fields.push(name);
                        }
                    });
                }
            }
            keep = !(ok || cancel);
            SchedTool::Combine(st)
        }
        SchedTool::Resize(vid, target, mut text) => {
            let title = if matches!(target, ResizeTarget::Columns(_)) { "Resize Column" } else { "Resize Row" };
            let (mut ok, mut cancel) = (false, false);
            window(title).open(&mut open).resizable(false).default_width(260.0).show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label("Size:");
                    ui.add(egui::TextEdit::singleline(&mut text).desired_width(160.0));
                });
                (ok, cancel) = ok_cancel(ui, true);
            });
            if ok {
                match parse_paper(app, &text).filter(|v| *v > 1.0) {
                    Some(mm) => {
                        let t = match &target {
                            ResizeTarget::Columns(f) => ResizeTarget::Columns(f.clone()),
                            ResizeTarget::Title => ResizeTarget::Title,
                            ResizeTarget::Row(r) => ResizeTarget::Row(*r),
                        };
                        modify(app, title, |v| {
                            if let ViewKind::Schedule(d) = &mut v.kind {
                                match t {
                                    ResizeTarget::Columns(fields) => {
                                        for f in fields {
                                            d.formats.entry(f).or_default().width = Some(mm);
                                        }
                                    }
                                    ResizeTarget::Title => d.title_height = Some(mm),
                                    ResizeTarget::Row(r) => {
                                        if let Some(h) = d.header_rows.get_mut(r) {
                                            h.height = Some(mm);
                                        }
                                    }
                                }
                            }
                        });
                    }
                    None => {
                        app.error("Enter a size, such as 25 mm or 1\".");
                        ok = false;
                    }
                }
            }
            keep = !(ok || cancel);
            SchedTool::Resize(vid, target, text)
        }
        SchedTool::Font(vid, keys, mut f) => {
            let (mut ok, mut cancel) = (false, false);
            window("Edit Font").open(&mut open).resizable(false).default_width(260.0).show(ctx, |ui| {
                ui.label("Font:");
                egui::ComboBox::from_id_salt("font-family").selected_text(f.family.clone()).width(220.0).show_ui(ui, |ui| {
                    for fam in ["Arial", "Arial Narrow", "Calibri", "Segoe UI", "Tahoma", "Times New Roman", "Trebuchet MS", "Verdana"] {
                        if ui.selectable_label(f.family == fam, fam).clicked() {
                            f.family = fam.into();
                        }
                    }
                });
                ui.add_space(4.0);
                ui.label("Font size:");
                let mut size = paper_text(app, f.size);
                if ui.add(egui::TextEdit::singleline(&mut size).desired_width(100.0)).changed() {
                    if let Some(v) = parse_paper(app, &size).filter(|v| *v > 0.5) {
                        f.size = v;
                    }
                }
                ui.add_space(4.0);
                ui.label("Font style:");
                crate::style::check(ui, &mut f.bold, "Bold");
                crate::style::check(ui, &mut f.italic, "Italic");
                crate::style::check(ui, &mut f.underline, "Underline");
                ui.add_space(4.0);
                ui.label("Font color:");
                ui.color_edit_button_srgb(&mut f.color);
                (ok, cancel) = ok_cancel(ui, true);
            });
            if ok {
                let font = f.clone();
                set_styles(app, vid, "Edit Font", &keys, |st| st.font = Some(font.clone()));
            }
            keep = !(ok || cancel);
            SchedTool::Font(vid, keys, f)
        }
        SchedTool::Borders(vid, keys, mut w, mut edits) => {
            let (mut ok, mut cancel) = (false, false);
            window("Edit Borders").open(&mut open).resizable(false).default_width(420.0).show(ctx, |ui| {
                ui.horizontal_top(|ui| {
                    ui.vertical(|ui| {
                        ui.label("Line style:");
                        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                            ui.set_min_size(vec2(160.0, 150.0));
                            ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                                for (k, name) in [(0u8, "<Invisible lines>"), (1, "<Thin Lines>"), (2, "<Medium Lines>"), (3, "<Wide Lines>")] {
                                    ui.selectable_value(&mut w, k, name);
                                }
                            });
                        });
                    });
                    ui.add_space(10.0);
                    ui.vertical(|ui| {
                        ui.label("Cell border:");
                        ui.horizontal(|ui| {
                            if ui.button("None").clicked() {
                                edits.push(BorderEdit::None);
                            }
                            if ui.button("Outside").clicked() {
                                edits.push(BorderEdit::Outside(w));
                            }
                            if ui.add_enabled(keys.len() > 1, egui::Button::new("Inside")).clicked() {
                                edits.push(BorderEdit::Inside(w));
                            }
                        });
                        // A sample of the selection's outer edges, with a button per edge.
                        let mut sample = [1u8; 4];
                        for e in &edits {
                            match e {
                                BorderEdit::None => sample = [0; 4],
                                BorderEdit::Outside(x) => sample = [*x; 4],
                                BorderEdit::Edge(k, x) => sample[*k] = *x,
                                BorderEdit::Inside(_) => {}
                            }
                        }
                        ui.horizontal(|ui| {
                            ui.vertical(|ui| {
                                if ui.small_button("Top").clicked() {
                                    edits.push(BorderEdit::Edge(0, w));
                                }
                                ui.add_space(50.0);
                                if ui.small_button("Bottom").clicked() {
                                    edits.push(BorderEdit::Edge(2, w));
                                }
                            });
                            let (r, _) = ui.allocate_exact_size(vec2(180.0, 100.0), egui::Sense::hover());
                            let pt = ui.painter();
                            pt.rect_filled(r, 0.0, egui::Color32::WHITE);
                            let c = r.shrink(10.0);
                            for (k, (a, b)) in [(c.left_top(), c.right_top()), (c.right_top(), c.right_bottom()), (c.right_bottom(), c.left_bottom()), (c.left_bottom(), c.left_top())].iter().enumerate() {
                                let wdt = [0.0, 1.0, 2.0, 3.0][sample[k].min(3) as usize];
                                if wdt > 0.0 {
                                    pt.line_segment([*a, *b], egui::Stroke::new(wdt, egui::Color32::BLACK));
                                }
                            }
                            pt.text(r.center(), egui::Align2::CENTER_CENTER, "Text", style::font(11.0), egui::Color32::BLACK);
                        });
                        ui.horizontal(|ui| {
                            ui.add_space(40.0);
                            if ui.small_button("Left").clicked() {
                                edits.push(BorderEdit::Edge(3, w));
                            }
                            ui.add_space(110.0);
                            if ui.small_button("Right").clicked() {
                                edits.push(BorderEdit::Edge(1, w));
                            }
                        });
                    });
                });
                ui.add_space(4.0);
                ui.label("Apply the selected line style by clicking the cell border buttons.");
                (ok, cancel) = ok_cancel(ui, true);
            });
            if ok {
                // Apply each change to the selected cells, left to right.
                let all = edits.clone();
                let n = keys.len();
                let ks = keys.clone();
                modify(app, "Edit Borders", |v| {
                    if let ViewKind::Schedule(d) = &mut v.kind {
                        for (i, k) in ks.iter().enumerate() {
                            let st = d.styles.entry(k.clone()).or_default();
                            let mut e = st.edges.unwrap_or([st.border.unwrap_or(1); 4]);
                            for ed in &all {
                                match *ed {
                                    BorderEdit::None => e = [0; 4],
                                    BorderEdit::Outside(x) => {
                                        e[0] = x;
                                        e[2] = x;
                                        if i == 0 {
                                            e[3] = x;
                                        }
                                        if i + 1 == n {
                                            e[1] = x;
                                        }
                                    }
                                    BorderEdit::Inside(x) => {
                                        if i > 0 {
                                            e[3] = x;
                                        }
                                        if i + 1 < n {
                                            e[1] = x;
                                        }
                                    }
                                    BorderEdit::Edge(k2, x) => {
                                        let outer = match k2 {
                                            1 => i + 1 == n,
                                            3 => i == 0,
                                            _ => true,
                                        };
                                        if outer {
                                            e[k2] = x;
                                        }
                                    }
                                }
                            }
                            st.edges = Some(e);
                        }
                    }
                });
            }
            keep = !(ok || cancel);
            SchedTool::Borders(vid, keys, w, edits)
        }
        SchedTool::Shading(vid, keys, mut c) => {
            let (mut ok, mut cancel) = (false, false);
            window("Color").open(&mut open).resizable(false).default_width(300.0).show(ctx, |ui| {
                // Basic colours (the standard 48), then the full picker.
                const BASIC: [u32; 48] = [
                    0xFF8080, 0xFFFF80, 0x80FF80, 0x00FF80, 0x80FFFF, 0x0080FF, 0xFF80C0, 0xFF80FF, 0xFF0000, 0xFFFF00, 0x80FF00, 0x00FF40, 0x00FFFF, 0x0080C0, 0x8080C0, 0xFF00FF,
                    0x804040, 0xFF8040, 0x00FF00, 0x008080, 0x004080, 0x8080FF, 0x800040, 0xFF0080, 0x800000, 0xFF8000, 0x008000, 0x008040, 0x0000FF, 0x0000A0, 0x800080, 0x8000FF,
                    0x400000, 0x804000, 0x004000, 0x004040, 0x000080, 0x000040, 0x400040, 0x400080, 0x000000, 0x808000, 0x808040, 0x808080, 0x408080, 0xC0C0C0, 0x400040, 0xFFFFFF,
                ];
                ui.label("Basic colors:");
                egui::Grid::new("basic-colors").spacing(vec2(4.0, 4.0)).show(ui, |ui| {
                    for (k, hex) in BASIC.iter().enumerate() {
                        let rgb = [(hex >> 16) as u8, (hex >> 8) as u8, *hex as u8];
                        let (r, resp) = ui.allocate_exact_size(vec2(20.0, 16.0), egui::Sense::click());
                        ui.painter().rect_filled(r, 0.0, egui::Color32::from_rgb(rgb[0], rgb[1], rgb[2]));
                        let st = if rgb == c { egui::Stroke::new(2.0, egui::Color32::BLACK) } else { egui::Stroke::new(1.0, egui::Color32::GRAY) };
                        ui.painter().rect_stroke(r, 0.0, st, egui::StrokeKind::Inside);
                        if resp.clicked() {
                            c = rgb;
                        }
                        if k % 8 == 7 {
                            ui.end_row();
                        }
                    }
                });
                ui.add_space(6.0);
                let mut col = egui::Color32::from_rgb(c[0], c[1], c[2]);
                egui::widgets::color_picker::color_picker_color32(ui, &mut col, egui::widgets::color_picker::Alpha::Opaque);
                c = [col.r(), col.g(), col.b()];
                ui.label(format!("Red: {}   Green: {}   Blue: {}", c[0], c[1], c[2]));
                (ok, cancel) = ok_cancel(ui, true);
            });
            if ok {
                let col = if c == [255, 255, 255] { None } else { Some(c) };
                set_styles(app, vid, "Shading", &keys, |st| st.shading = col);
            }
            keep = !(ok || cancel);
            SchedTool::Shading(vid, keys, c)
        }
        SchedTool::Split(vid, mut sheet, mut segs) => {
            let sheets: Vec<(Id, String)> = app.doc.data.views.iter().filter_map(|v| match &v.kind {
                ViewKind::Sheet(s) => Some((v.id, format!("{} - {}", s.number, v.name))),
                _ => None,
            }).collect();
            let rows = app.grid(vid).map(|g| g.table.rows.len()).unwrap_or(0);
            let (mut ok, mut cancel) = (false, false);
            window("Split Schedule and Place").open(&mut open).resizable(false).default_width(320.0).show(ctx, |ui| {
                ui.label("Place on sheet:");
                egui::ComboBox::from_id_salt("split-sheet").selected_text(sheets.get(sheet).map(|s| s.1.clone()).unwrap_or_default()).width(280.0).show_ui(ui, |ui| {
                    for (k, s) in sheets.iter().enumerate() {
                        ui.selectable_value(&mut sheet, k, &s.1);
                    }
                });
                ui.add_space(6.0);
                ui.horizontal(|ui| {
                    ui.label("Number of segments:");
                    ui.add(egui::DragValue::new(&mut segs).range(2..=(rows.max(2) as u32).min(20)));
                });
                ui.label(format!("{rows} rows, split into segments of equal height."));
                (ok, cancel) = ok_cancel(ui, !sheets.is_empty());
            });
            if ok {
                if let Some((sid, _)) = sheets.get(sheet).cloned() {
                    let n = segs.max(1) as usize;
                    let per = rows.div_ceil(n).max(1);
                    let made = app.run("Split & Place", |p| {
                        let size = match p.view(sid).map(|v| &v.kind) {
                            Some(ViewKind::Sheet(s)) => s.size.paper(),
                            _ => return Err("Sheet not found.".into()),
                        };
                        let def = match p.view(vid).map(|v| &v.kind) {
                            Some(ViewKind::Schedule(d)) => d.clone(),
                            _ => return Err("Schedule not found.".into()),
                        };
                        let name = p.view(vid).map(|v| v.name.clone()).unwrap_or_default();
                        // Segments side by side from the sheet's top left.
                        let mut x = 30.0;
                        let mut vps = Vec::new();
                        for k in 0..n {
                            let (a, b) = ((k * per) as u32, (((k + 1) * per).min(rows) - 1) as u32);
                            if (a as usize) >= rows {
                                break;
                            }
                            let g = rc_core::schedule::layout(p, &def, &name, Some((a, b)));
                            let w: f64 = g.widths.iter().sum::<f64>().max(40.0);
                            let h: f64 = g.rows.iter().map(|r| r.height).sum();
                            vps.push(Viewport { view: vid, cx: x + w / 2.0, cy: size.1 - 30.0 - h / 2.0, detail_number: String::new(), show_title: false, segment: Some((a, b)) });
                            x += w + 10.0;
                        }
                        if let Some(ViewKind::Sheet(s)) = p.view_mut(sid).map(|v| &mut v.kind) {
                            s.viewports.retain(|vp| vp.view != vid);
                            s.viewports.extend(vps);
                        }
                        Ok(sid)
                    });
                    if let Some(sid) = made {
                        app.open_view(sid);
                    }
                }
            }
            keep = !(ok || cancel);
            SchedTool::Split(vid, sheet, segs)
        }
    };
    if keep && open {
        app.dialogs.sched_tool = Some(next);
    }
}
