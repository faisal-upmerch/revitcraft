//! Status bar: prompts, the active design option and the selection controls.

use crate::app::App;
use crate::icons::{self, Icon};
use crate::style;
use eframe::egui::{self, Rect, Sense, Stroke, vec2};

fn toggle_icon(ui: &mut egui::Ui, icon: Icon, on: &mut bool, tip: &str) -> bool {
    let (r, resp) = ui.allocate_exact_size(vec2(20.0, 20.0), Sense::click());
    if *on {
        ui.painter().rect_filled(r, 2.0, style::accent_light());
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 2.0, style::hover());
    }
    icons::paint(ui.painter(), r.shrink(2.0), icon, true);
    if !*on {
        ui.painter().line_segment([r.left_bottom() + vec2(3.0, -3.0), r.right_top() + vec2(-3.0, 3.0)], Stroke::new(1.5, style::ERROR));
    }
    let clicked = resp.clicked();
    resp.on_hover_text(tip);
    if clicked {
        *on = !*on;
    }
    clicked
}

pub fn show(app: &mut App, ui: &mut egui::Ui) {
    ui.horizontal_centered(|ui| {
        let prompt = if app.family_editor.is_some() {
            crate::family_editor::status_text(app)
        } else if app.interact.prompt.is_empty() {
            crate::canvas_tools::prompt(app)
        } else {
            app.interact.prompt.clone()
        };
        let prompt = if prompt.is_empty() { "Ready".to_string() } else { prompt };
        ui.add(egui::Label::new(egui::RichText::new(prompt).color(style::text())).truncate());
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            // Filter with count.
            let (r, resp) = ui.allocate_exact_size(vec2(54.0, 20.0), Sense::click());
            if resp.hovered() {
                ui.painter().rect_filled(r, 2.0, style::hover());
            }
            icons::paint(ui.painter(), Rect::from_min_size(r.min + vec2(2.0, 2.0), vec2(16.0, 16.0)), Icon::Filter, true);
            ui.painter().text(r.left_center() + vec2(22.0, 0.0), egui::Align2::LEFT_CENTER, format!(":{}", app.selection.len()), egui::FontId::proportional(12.0), style::text());
            if resp.clicked() && !app.selection.is_empty() {
                app.dialogs.filter = true;
            }
            resp.on_hover_text("Filter the selection by category");
            ui.add_space(6.0);
            let s = &mut app.settings;
            let mut changed = false;
            changed |= toggle_icon(ui, Icon::DragOnSelect, &mut s.drag_on_selection, "Drag elements on selection");
            changed |= toggle_icon(ui, Icon::SelectByFace, &mut s.select_by_face, "Select elements by face");
            changed |= toggle_icon(ui, Icon::SelectPinned, &mut s.select_pinned, "Select pinned elements");
            changed |= toggle_icon(ui, Icon::SelectUnderlay, &mut s.select_underlay, "Select underlay elements");
            changed |= toggle_icon(ui, Icon::SelectLinks, &mut s.select_links, "Select links");
            if changed {
                app.settings_dirty = true;
            }
            ui.separator();
            // Design option being edited.
            let p = &app.doc.data;
            if !p.option_sets.is_empty() {
                let label = app
                    .active_option
                    .and_then(|o| p.option_sets.iter().find_map(|s| s.options.iter().find(|x| x.id == o).map(|x| format!("{} : {}", s.name, x.name))))
                    .unwrap_or_else(|| "Main Model".into());
                let mut active = app.active_option;
                egui::ComboBox::from_id_salt("design-option").selected_text(label).width(170.0).show_ui(ui, |ui| {
                    ui.selectable_value(&mut active, None, "Main Model");
                    for set in &p.option_sets {
                        for o in &set.options {
                            ui.selectable_value(&mut active, Some(o.id), format!("{} : {}{}", set.name, o.name, if o.primary { " (primary)" } else { "" }));
                        }
                    }
                });
                if active != app.active_option {
                    app.active_option = active;
                }
                ui.label(egui::RichText::new("Design Option:").color(style::text_dim()));
                ui.separator();
            }
            if p.option_sets.is_empty() {
                ui.add_space(8.0);
                ui.label(egui::RichText::new("Main Model").color(style::text_dim()));
                let (r, _) = ui.allocate_exact_size(vec2(18.0, 18.0), Sense::hover());
                icons::paint(ui.painter(), r.shrink(1.0), Icon::DesignOptions, true);
            }
        });
    });
}
