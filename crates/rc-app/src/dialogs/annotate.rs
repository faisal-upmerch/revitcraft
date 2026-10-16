//! Annotate dialogs: Beam Annotations and Check Spelling.

use super::{dlg_button, window};
use crate::app::App;
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::model::*;
use std::collections::{HashMap, HashSet};

pub fn show(app: &mut App, ctx: &egui::Context) {
    beam_annotations(app, ctx);
    check_spelling(app, ctx);
}

// ---------------------------------------------------------------- Beam Annotations

/// What goes at each place of a beam: 0 none, 1 structural framing tag, 2 spot elevation.
/// Places: above start, middle, end; below start, middle, end.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct BeamSlots {
    pub level: [u8; 6],
    pub sloped: [u8; 6],
}

pub struct BeamAnnoState {
    pub selected_only: bool,
    pub include_links: bool,
    pub remove: bool,
    pub tab: usize,
    pub slots: BeamSlots,
    /// The place whose annotation type is being picked, and the choice so far.
    pub picking: Option<(usize, u8)>,
    /// Placement Settings: the horizontal end offset being entered.
    pub settings: Option<String>,
    pub end_offset: f64,
}

impl BeamAnnoState {
    pub fn new(app: &App) -> BeamAnnoState {
        let any_selected = app.selection.iter().any(|id| is_beam(app.el(*id)));
        BeamAnnoState { selected_only: any_selected, include_links: false, remove: false, tab: 0, slots: app.dialogs.beam_slots, picking: None, settings: None, end_offset: app.dialogs.beam_end_offset }
    }
}

fn is_beam(e: Option<&Element>) -> bool {
    matches!(e.map(|e| &e.kind), Some(ElementKind::Instance(i)) if i.category == Category::StructuralFraming && i.end.is_some())
}

fn slot_label(kind: u8, place: usize) -> String {
    match kind {
        1 => "Structural Framing Tag : Standard".into(),
        2 => "Beam Elevation (Project)".into(),
        _ => ["<Start>", "<Middle>", "<End>"][place % 3].into(),
    }
}

fn beam_annotations(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.beam_annotations.take() else { return };
    let any_selected = app.selection.iter().any(|id| is_beam(app.el(*id)));
    let (mut open, mut ok, mut cancel) = (true, false, false);
    window("Beam Annotations").open(&mut open).resizable(false).default_width(660.0).show(ctx, |ui| {
        ui.label("Use this tool to place beam annotations, tags and spot elevations, on the beams in your current plan view.");
        ui.add_space(4.0);
        ui.label("Beam annotations can be placed at the ends and mid-points of level and sloped beams.  They can also be placed on either side of the beam.");
        ui.add_space(4.0);
        ui.label("Select the annotation type and location.  A schematic preview is given below.");
        ui.add_space(6.0);
        group(ui, "Placement", |ui| {
            ui.radio_value(&mut st.selected_only, false, "All beams in current plan view");
            ui.add_enabled_ui(any_selected, |ui| {
                ui.radio_value(&mut st.selected_only, true, "All selected beams in current plan view");
            });
            ui.checkbox(&mut st.include_links, "Include beams from links");
            ui.horizontal(|ui| {
                ui.checkbox(&mut st.remove, "Remove existing beam tags and spot elevations");
            });
            ui.horizontal(|ui| {
                let (r, _) = ui.allocate_exact_size(vec2(16.0, 16.0), egui::Sense::hover());
                ui.painter().circle_filled(r.center(), 7.0, style::SELECT);
                ui.painter().text(r.center(), egui::Align2::CENTER_CENTER, "i", style::bold(11.0), egui::Color32::WHITE);
                ui.label("Beams that have existing host file annotations will not be reannotated.");
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.add_sized(vec2(96.0, 22.0), egui::Button::new("Settings...")).clicked() {
                        st.settings = Some(app.doc.data.units.length(st.end_offset));
                    }
                });
            });
        });
        ui.add_space(6.0);
        group(ui, "Annotation location and type", |ui| {
            ui.horizontal(|ui| {
                ui.selectable_value(&mut st.tab, 0, "Level beams in plan");
                ui.selectable_value(&mut st.tab, 1, "Sloped beams in plan");
            });
            egui::Frame::new().fill(egui::Color32::WHITE).inner_margin(12.0).show(ui, |ui| {
                ui.set_width(ui.available_width());
                let slots = if st.tab == 0 { st.slots.level } else { st.slots.sloped };
                let row = |ui: &mut egui::Ui, from: usize, picking: &mut Option<(usize, u8)>| {
                    ui.horizontal(|ui| {
                        for k in from..from + 3 {
                            let mut text = slot_label(slots[k], k);
                            let color = if slots[k] == 0 { style::text_dim() } else { style::text() };
                            ui.add_enabled(false, egui::TextEdit::singleline(&mut text).desired_width(150.0).text_color(color));
                            if ui.small_button("...").clicked() {
                                *picking = Some((k, slots[k]));
                            }
                            if k < from + 2 {
                                ui.add_space(30.0);
                            }
                        }
                    });
                };
                row(ui, 0, &mut st.picking);
                // The schematic beam: a timber-coloured bar with its dashed centre line.
                let (r, _) = ui.allocate_exact_size(vec2(ui.available_width().min(560.0), 62.0), egui::Sense::hover());
                let r = egui::Rect::from_min_size(r.min + vec2(0.0, 2.0), vec2(r.width() - 4.0, 52.0));
                let p = ui.painter();
                p.rect_filled(r.translate(vec2(4.0, 4.0)), 0.0, egui::Color32::from_gray(225));
                p.rect(r, 0.0, egui::Color32::from_rgb(222, 165, 125), egui::Stroke::new(2.0, egui::Color32::from_rgb(150, 90, 60)), egui::StrokeKind::Inside);
                let y = r.center().y;
                let mut x = r.left() + 10.0;
                while x < r.right() - 20.0 {
                    p.line_segment([egui::pos2(x, y), egui::pos2(x + 16.0, y)], egui::Stroke::new(1.0, egui::Color32::from_rgb(150, 90, 60)));
                    x += 26.0;
                }
                row(ui, 3, &mut st.picking);
            });
        });
        ui.add_space(8.0);
        ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
            ui.spacing_mut().item_spacing.x = 8.0;
            cancel = dlg_button(ui, "Cancel", false, true);
            ok = dlg_button(ui, "OK", true, true);
        });
    });
    // Select Annotation Type.
    if let Some((place, mut choice)) = st.picking.take() {
        let (mut done, mut quit) = (false, false);
        window("Select Annotation Type").resizable(false).default_width(260.0).show(ctx, |ui| {
            group(ui, "Select Element to Place", |ui| {
                ui.radio_value(&mut choice, 0, "None");
                ui.radio_value(&mut choice, 1, "Structural Framing Tag");
                ui.radio_value(&mut choice, 2, "Spot Elevation");
            });
            ui.add_space(4.0);
            match choice {
                1 => group(ui, "Structural Framing Tag", |ui| {
                    ui.label("Type:");
                    egui::ComboBox::from_id_salt("beam-tag-type").width(220.0).selected_text("Structural Framing Tag : Standard").show_ui(ui, |ui| {
                        let _ = ui.selectable_label(true, "Structural Framing Tag : Standard");
                    });
                }),
                2 => group(ui, "Spot Elevation", |ui| {
                    ui.label("Type:");
                    egui::ComboBox::from_id_salt("beam-spot-type").width(220.0).selected_text("Beam Elevation (Project)").show_ui(ui, |ui| {
                        let _ = ui.selectable_label(true, "Beam Elevation (Project)");
                    });
                    ui.label("Display Elevation:");
                    egui::ComboBox::from_id_salt("beam-spot-display").width(220.0).selected_text("Actual (Selected) Elevation").show_ui(ui, |ui| {
                        let _ = ui.selectable_label(true, "Actual (Selected) Elevation");
                    });
                }),
                _ => {}
            }
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                quit = dlg_button(ui, "Cancel", false, true);
                done = dlg_button(ui, "OK", true, true);
            });
        });
        if done {
            if st.tab == 0 {
                st.slots.level[place] = choice;
            } else {
                st.slots.sloped[place] = choice;
            }
        } else if !quit {
            st.picking = Some((place, choice));
        }
    }
    // Placement Settings.
    if let Some(mut text) = st.settings.take() {
        let (mut done, mut quit) = (false, false);
        window("Placement Settings").resizable(false).default_width(340.0).show(ctx, |ui| {
            ui.label("Spot elevations and beam tags are placed with respect to the text's bounding box in those elements.");
            ui.label("Offsets from beam geometry or symbology can be adjusted here.");
            ui.add_space(6.0);
            ui.horizontal(|ui| {
                ui.label("Horizontal End Offset:");
                ui.add(egui::TextEdit::singleline(&mut text).desired_width(120.0));
            });
            ui.label("Vertical Offset:");
            let _ = ui.radio(true, "Default Offset");
            ui.add_space(8.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.spacing_mut().item_spacing.x = 8.0;
                quit = dlg_button(ui, "Cancel", false, true);
                done = dlg_button(ui, "OK", true, true);
            });
        });
        if done {
            match app.doc.data.units.parse(&text, ParamKind::Length) {
                Some(v) if v >= 0.0 => st.end_offset = v,
                _ => {
                    app.error("Enter a length for the offset.");
                    st.settings = Some(text);
                }
            }
        } else if !quit {
            st.settings = Some(text);
        }
    }
    if ok {
        let Some(view) = app.active_view().filter(|v| v.plan_level().is_some()).map(|v| v.id) else {
            app.error("Beam annotations are placed in plan views.");
            return;
        };
        let p = &app.doc.data;
        let v = p.view(view).unwrap().clone();
        let beams: Vec<Id> = if st.selected_only {
            app.selection.iter().copied().filter(|id| is_beam(app.el(*id))).collect()
        } else {
            p.elements.iter().filter(|e| is_beam(Some(e)) && rc_core::plan::in_plan(p, &v, e)).map(|e| e.id).collect()
        };
        let (slots, remove, off) = (st.slots, st.remove, st.end_offset);
        app.dialogs.beam_slots = slots;
        app.dialogs.beam_end_offset = off;
        if let Some(n) = app.run("Beam Annotations", |p| rc_core::edit::annotate_beams(p, view, &beams, slots.level, slots.sloped, remove, off)) {
            app.info(format!("{n} beam annotation(s) placed."));
        }
    }
    if !(ok || cancel || !open) {
        app.dialogs.beam_annotations = Some(st);
    }
}

fn group(ui: &mut egui::Ui, title: &str, add: impl FnOnce(&mut egui::Ui)) {
    egui::Frame::new().stroke(egui::Stroke::new(1.0, style::border())).inner_margin(8.0).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.label(title);
        add(ui);
    });
}

// ---------------------------------------------------------------- Check Spelling

#[derive(Default)]
pub struct SpellState {
    /// The text notes to check: the selected ones, or all in the view.
    items: Vec<Id>,
    item: usize,
    /// Where checking continues in the current note (bytes).
    from: usize,
    /// The word found: its byte range in the current note.
    cur: Option<(usize, usize)>,
    change_to: String,
    suggestions: Vec<String>,
    ignore_all: HashSet<String>,
    change_all: HashMap<String, String>,
    done: bool,
}

impl SpellState {
    pub fn new(app: &App) -> SpellState {
        let is_text = |e: &Element| matches!(e.kind, ElementKind::Text(_));
        let mut items: Vec<Id> = app.selection.iter().copied().filter(|id| app.el(*id).is_some_and(is_text)).collect();
        if items.is_empty() {
            let view = app.active;
            items = app.doc.data.elements.iter().filter(|e| e.view.is_some() && e.view == view && is_text(e)).map(|e| e.id).collect();
        }
        SpellState { items, ..Default::default() }
    }
}

fn note_text(app: &App, id: Id) -> Option<String> {
    match app.el(id).map(|e| &e.kind) {
        Some(ElementKind::Text(t)) => Some(t.text.clone()),
        _ => None,
    }
}

fn replace(app: &mut App, id: Id, s: usize, e: usize, with: &str) {
    let with = with.to_string();
    app.run("Check Spelling", |p| {
        if let Some(ElementKind::Text(t)) = p.element_mut(id).map(|x| &mut x.kind) {
            if e <= t.text.len() && t.text.is_char_boundary(s) && t.text.is_char_boundary(e) {
                t.text.replace_range(s..e, &with);
            }
        }
        Ok(())
    });
}

/// Moves on to the next misspelt word (changing those under Change All on the way).
fn advance(app: &mut App, st: &mut SpellState) {
    st.cur = None;
    'items: while st.item < st.items.len() {
        let id = st.items[st.item];
        let Some(text) = note_text(app, id) else {
            st.item += 1;
            st.from = 0;
            continue;
        };
        for (s, e) in crate::spelling::check(&text) {
            if s < st.from {
                continue;
            }
            let word = text[s..e].to_string();
            if st.ignore_all.contains(&word.to_lowercase()) {
                continue;
            }
            if let Some(to) = st.change_all.get(&word).cloned() {
                replace(app, id, s, e, &to);
                st.from = s + to.len();
                continue 'items;
            }
            st.suggestions = crate::spelling::suggest(&word);
            st.change_to = st.suggestions.first().cloned().unwrap_or_else(|| word.clone());
            st.cur = Some((s, e));
            return;
        }
        st.item += 1;
        st.from = 0;
    }
    st.done = true;
}

fn check_spelling(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.spelling.take() else { return };
    if st.cur.is_none() && !st.done {
        advance(app, &mut st);
    }
    if st.done {
        let mut close = false;
        window("RevitCraft").resizable(false).default_width(280.0).show(ctx, |ui| {
            ui.label(egui::RichText::new("Spell check is complete.").color(style::SELECT).size(14.0));
            ui.add_space(10.0);
            ui.allocate_ui_with_layout(vec2(ui.available_width(), 26.0), egui::Layout::right_to_left(egui::Align::Center), |ui| {
                close = dlg_button(ui, "Close", true, true);
            });
        });
        if !close {
            app.dialogs.spelling = Some(st);
        }
        return;
    }
    let Some((s, e)) = st.cur else { return };
    let id = st.items[st.item];
    let text = note_text(app, id).unwrap_or_default();
    if e > text.len() {
        st.cur = None;
        app.dialogs.spelling = Some(st);
        return;
    }
    let word = text[s..e].to_string();
    let mut action = "";
    let mut open = true;
    window("Check Spelling").open(&mut open).resizable(false).default_width(380.0).show(ctx, |ui| {
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(270.0);
                ui.label("Context");
                egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(4.0).show(ui, |ui| {
                    ui.set_min_size(vec2(262.0, 60.0));
                    let mut job = egui::text::LayoutJob::default();
                    let font = egui::FontId::proportional(12.0);
                    job.append(&text[..s], 0.0, egui::TextFormat { font_id: font.clone(), color: style::text(), ..Default::default() });
                    job.append(&word, 0.0, egui::TextFormat { font_id: style::bold(12.0), color: style::text(), ..Default::default() });
                    job.append(&text[e..], 0.0, egui::TextFormat { font_id: font, color: style::text(), ..Default::default() });
                    job.wrap.max_width = 256.0;
                    ui.label(job);
                });
                ui.label("Not in Dictionary:");
                let mut w = word.clone();
                ui.add_enabled(false, egui::TextEdit::singleline(&mut w).desired_width(266.0));
                ui.label("Change to:");
                ui.add(egui::TextEdit::singleline(&mut st.change_to).desired_width(266.0));
                egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, style::border())).inner_margin(2.0).show(ui, |ui| {
                    ui.set_min_size(vec2(264.0, 70.0));
                    egui::ScrollArea::vertical().max_height(70.0).show(ui, |ui| {
                        ui.with_layout(egui::Layout::top_down_justified(egui::Align::Min), |ui| {
                            for sug in st.suggestions.clone() {
                                if ui.selectable_label(st.change_to == sug, &sug).clicked() {
                                    st.change_to = sug;
                                }
                            }
                        });
                    });
                });
            });
            ui.vertical(|ui| {
                ui.add_space(14.0);
                let b = |ui: &mut egui::Ui, label: &str, enabled: bool| ui.add_enabled(enabled, egui::Button::new(label).min_size(vec2(84.0, 22.0))).clicked();
                for (label, key) in [("Ignore", "ignore"), ("Ignore All", "ignore_all"), ("Add", "add"), ("Change", "change"), ("Change All", "change_all")] {
                    if b(ui, label, true) {
                        action = key;
                    }
                }
                ui.add_space(50.0);
                b(ui, "Undo", false);
                if b(ui, "Close", true) {
                    action = "close";
                }
            });
        });
    });
    if !open {
        action = "close";
    }
    match action {
        "close" => return,
        "ignore" => st.from = e,
        "ignore_all" => {
            st.ignore_all.insert(word.to_lowercase());
            st.from = e;
        }
        "add" => {
            crate::spelling::add_word(&word);
            st.from = e;
        }
        "change" | "change_all" => {
            let to = st.change_to.clone();
            if action == "change_all" {
                st.change_all.insert(word.clone(), to.clone());
            }
            replace(app, id, s, e, &to);
            st.from = s + to.len();
        }
        _ => {
            app.dialogs.spelling = Some(st);
            return;
        }
    }
    advance(app, &mut st);
    app.dialogs.spelling = Some(st);
}
