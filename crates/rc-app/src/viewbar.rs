//! The View Control Bar at the bottom of each view window.

use crate::actions;
use crate::app::App;
use crate::commands::Cmd;
use crate::icons::{self, Icon};
use crate::style;
use eframe::egui::{self, Sense, Stroke, vec2};
use rc_core::model::*;
use rc_core::units::UnitSystem;

pub const METRIC_SCALES: [f64; 15] = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0, 1250.0, 2000.0, 5000.0];
pub const IMPERIAL_SCALES: [(f64, &str); 18] = [
    (1.0, "12\" = 1'-0\""),
    (2.0, "6\" = 1'-0\""),
    (4.0, "3\" = 1'-0\""),
    (8.0, "1 1/2\" = 1'-0\""),
    (12.0, "1\" = 1'-0\""),
    (16.0, "3/4\" = 1'-0\""),
    (24.0, "1/2\" = 1'-0\""),
    (32.0, "3/8\" = 1'-0\""),
    (48.0, "1/4\" = 1'-0\""),
    (64.0, "3/16\" = 1'-0\""),
    (96.0, "1/8\" = 1'-0\""),
    (120.0, "1\" = 10'-0\""),
    (192.0, "1/16\" = 1'-0\""),
    (240.0, "1\" = 20'-0\""),
    (384.0, "3/32\" = 1'-0\""),
    (480.0, "1\" = 40'-0\""),
    (600.0, "1\" = 50'-0\""),
    (1200.0, "1\" = 100'-0\""),
];

pub fn scale_label(app: &App, s: f64) -> String {
    if app.doc.data.units.system == UnitSystem::Imperial {
        if let Some((_, l)) = IMPERIAL_SCALES.iter().find(|(v, _)| (*v - s).abs() < 1e-6) {
            return l.to_string();
        }
    }
    format!("1 : {}", s.round())
}

fn icon_btn(ui: &mut egui::Ui, icon: Icon, on: bool, tip: &str) -> egui::Response {
    let (r, resp) = ui.allocate_exact_size(vec2(22.0, 20.0), Sense::click());
    if on {
        ui.painter().rect_filled(r, 2.0, style::accent_light());
        ui.painter().rect_stroke(r, 2.0, Stroke::new(1.0, style::ACCENT), egui::StrokeKind::Inside);
    } else if resp.hovered() {
        ui.painter().rect_filled(r, 2.0, style::hover());
    }
    icons::paint(ui.painter(), r.shrink(2.5), icon, true);
    resp.on_hover_text(tip)
}

pub fn show(app: &mut App, ui: &mut egui::Ui, view_id: Id) {
    let Some(view) = app.doc.data.view(view_id).cloned() else { return };
    egui::Panel::bottom(egui::Id::new(("viewbar", view_id)))
        .exact_size(24.0)
        .frame(egui::Frame::new().fill(style::chrome()).inner_margin(egui::Margin::symmetric(4, 1)).stroke(Stroke::new(1.0, style::border())))
        .show(ui, |ui| {
            ui.horizontal_centered(|ui| {
                ui.spacing_mut().item_spacing.x = 2.0;
                let is3d = matches!(view.kind, ViewKind::ThreeD { .. });
                // Make clicks here also activate the view.
                let activate = |app: &mut App| {
                    if app.active != Some(view_id) {
                        app.activate(view_id);
                    }
                };
                // Scale.
                if !is3d || !matches!(view.kind, ViewKind::ThreeD { perspective: true, .. }) {
                    let resp = ui.add(egui::Button::new(egui::RichText::new(scale_label(app, view.scale)).size(11.0)).frame(false));
                    egui::Popup::menu(&resp).show(|ui| {
                        let imperial = app.doc.data.units.system == UnitSystem::Imperial;
                        let list: Vec<(f64, String)> = if imperial {
                            IMPERIAL_SCALES.iter().map(|(v, l)| (*v, l.to_string())).collect()
                        } else {
                            METRIC_SCALES.iter().map(|v| (*v, format!("1 : {v}"))).collect()
                        };
                        for (v, l) in list {
                            if ui.selectable_label((view.scale - v).abs() < 1e-6, l).clicked() {
                                activate(app);
                                app.run("View Scale", |p| {
                                    if let Some(vv) = p.view_mut(view_id) {
                                        vv.scale = v;
                                    }
                                    Ok(())
                                });
                            }
                        }
                    });
                    resp.on_hover_text("View scale");
                    ui.separator();
                }
                // Detail level.
                let resp = icon_btn(ui, Icon::DetailLevel, false, &format!("Detail Level: {}", view.detail.label()));
                egui::Popup::menu(&resp).show(|ui| {
                    for (d, c) in [(DetailLevel::Coarse, Cmd::DetailCoarse), (DetailLevel::Medium, Cmd::DetailMedium), (DetailLevel::Fine, Cmd::DetailFine)] {
                        if ui.selectable_label(view.detail == d, d.label()).clicked() {
                            activate(app);
                            actions::exec(app, c);
                        }
                    }
                });
                // Visual style.
                let style_icon = match view.style {
                    VisualStyle::Wireframe => Icon::Wireframe,
                    VisualStyle::HiddenLine => Icon::HiddenLine,
                    VisualStyle::Shaded => Icon::Shaded,
                    VisualStyle::ConsistentColors => Icon::Consistent,
                    VisualStyle::Realistic => Icon::Realistic,
                };
                let resp = icon_btn(ui, style_icon, false, &format!("Visual Style: {}", view.style.label()));
                egui::Popup::menu(&resp).show(|ui| {
                    for (s, c) in [
                        (VisualStyle::Wireframe, Cmd::StyleWireframe),
                        (VisualStyle::HiddenLine, Cmd::StyleHidden),
                        (VisualStyle::Shaded, Cmd::StyleShaded),
                        (VisualStyle::ConsistentColors, Cmd::StyleConsistent),
                        (VisualStyle::Realistic, Cmd::StyleRealistic),
                    ] {
                        if ui.selectable_label(view.style == s, s.label()).clicked() {
                            activate(app);
                            actions::exec(app, c);
                        }
                    }
                });
                if icon_btn(ui, Icon::Shadows, view.shadows, if view.shadows { "Shadows On" } else { "Shadows Off" }).clicked() {
                    activate(app);
                    actions::exec(app, Cmd::ToggleShadows);
                }
                if is3d {
                    let persp = matches!(view.kind, ViewKind::ThreeD { perspective: true, .. });
                    if icon_btn(ui, Icon::Camera, persp, if persp { "Perspective (click for orthographic)" } else { "Orthographic (click for perspective)" }).clicked() {
                        activate(app);
                        app.run("Toggle Perspective", |p| {
                            if let Some(v) = p.view_mut(view_id) {
                                if let ViewKind::ThreeD { perspective, .. } = &mut v.kind {
                                    *perspective = !*perspective;
                                }
                            }
                            Ok(())
                        });
                    }
                    if icon_btn(ui, Icon::SectionBox, view.section_box.is_some(), "Section Box").clicked() {
                        activate(app);
                        actions::exec(app, Cmd::ToggleSectionBox);
                    }
                } else {
                    if icon_btn(ui, Icon::Crop, view.crop_active, if view.crop_active { "Crop View (on)" } else { "Do Not Crop View" }).clicked() {
                        activate(app);
                        actions::exec(app, Cmd::ToggleCrop);
                    }
                    if icon_btn(ui, Icon::CropShow, view.crop_visible, if view.crop_visible { "Hide Crop Region" } else { "Show Crop Region" }).clicked() {
                        activate(app);
                        actions::exec(app, Cmd::ToggleCropShow);
                    }
                }
                ui.separator();
                let temp_on = app.temp_hide.get(&view_id).is_some_and(|t| t.is_active());
                let resp = icon_btn(ui, Icon::TempHide, temp_on, "Temporary Hide/Isolate");
                egui::Popup::menu(&resp).show(|ui| {
                    for c in [Cmd::TempIsolateCategory, Cmd::TempHideCategory, Cmd::TempIsolateElement, Cmd::TempHideElement, Cmd::TempReset] {
                        let enabled = actions::enabled(app, c);
                        if ui.add_enabled(enabled, egui::Button::new(c.info().label).frame(false)).clicked() {
                            activate(app);
                            actions::exec(app, c);
                        }
                    }
                });
                let rev = app.reveal_hidden.contains(&view_id);
                if icon_btn(ui, Icon::RevealHidden, rev, "Reveal Hidden Elements").clicked() {
                    activate(app);
                    actions::exec(app, Cmd::RevealHidden);
                }
                if !is3d {
                    ui.separator();
                    ui.label(egui::RichText::new(format!("{} — {}", view.type_label(), view.name)).size(11.0).color(style::text_dim()));
                }
            });
        });
}
