//! Manage-tab and application settings dialogs.

use super::window;
use crate::app::App;
use crate::commands::Cmd;
use crate::style;
use eframe::egui::{self, vec2};
use rc_core::model::*;
use rc_core::units::{AreaUnit, LengthUnit, UnitSystem, VolumeUnit};

pub fn show(app: &mut App, ctx: &egui::Context) {
    options(app, ctx);
    materials(app, ctx);
    object_styles(app, ctx);
    snaps(app, ctx);
    project_info(app, ctx);
    units(app, ctx);
    purge(app, ctx);
    phases(app, ctx);
    design_options(app, ctx);
    sun(app, ctx);
    links(app, ctx);
    shortcuts(app, ctx);
}

fn options(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.options {
        return;
    }
    let mut open = true;
    window("Options").open(&mut open).default_width(420.0).show(ctx, |ui| {
        ui.heading("General");
        ui.horizontal(|ui| {
            ui.label("Save reminder interval:");
            let label = |m: u32| if m == 0 { "No reminders".to_string() } else if m < 60 { format!("{m} minutes") } else { format!("{} hours", m / 60) };
            egui::ComboBox::from_id_salt("opt-reminder").selected_text(label(app.settings.save_reminder_minutes)).show_ui(ui, |ui| {
                for m in [15, 30, 60, 120, 240, 0] {
                    ui.selectable_value(&mut app.settings.save_reminder_minutes, m, label(m));
                }
            });
        });
        ui.horizontal(|ui| {
            ui.label("Username:");
            ui.text_edit_singleline(&mut app.settings.user);
        });
        ui.add_space(6.0);
        ui.heading("User Interface");
        ui.horizontal(|ui| {
            ui.label("Theme:");
            ui.selectable_value(&mut app.settings.dark, false, "Light");
            ui.selectable_value(&mut app.settings.dark, true, "Dark");
        });
        ui.checkbox(&mut app.settings.tooltips, "Show tooltips");
        if ui.button("Keyboard Shortcuts: Customize...").clicked() {
            app.dialogs.shortcuts = Some(String::new());
        }
        ui.add_space(6.0);
        ui.heading("Graphics");
        ui.horizontal(|ui| {
            ui.label("Background:");
            ui.selectable_value(&mut app.settings.black_canvas, false, "White");
            ui.selectable_value(&mut app.settings.black_canvas, true, "Black");
        });
        ui.add_space(6.0);
        ui.heading("Selection");
        ui.checkbox(&mut app.settings.drag_on_selection, "Drag elements on selection");
        ui.checkbox(&mut app.settings.select_pinned, "Select pinned elements");
    });
    if !open {
        app.dialogs.options = false;
        app.settings_dirty = true;
    }
}

fn material_preview(ui: &mut egui::Ui, m: &Material) {
    let (r, _) = ui.allocate_exact_size(vec2(120.0, 120.0), egui::Sense::hover());
    let p = ui.painter();
    p.rect_filled(r, 4.0, egui::Color32::from_rgb(235, 238, 242));
    let c = r.center();
    let rad = 46.0f32;
    // Shaded sphere: concentric rings brightened towards the light.
    for k in (0..24).rev() {
        let t = k as f32 / 24.0;
        let lit = 0.45 + 0.55 * (1.0 - t).powf(0.7);
        let col = egui::Color32::from_rgb((m.color[0] as f32 * lit).min(255.0) as u8, (m.color[1] as f32 * lit).min(255.0) as u8, (m.color[2] as f32 * lit).min(255.0) as u8);
        let off = egui::vec2(-12.0, -12.0) * (1.0 - t);
        p.circle_filled(c + off, rad * t.max(0.06) + 0.01 + (1.0 - t) * 0.0, col);
    }
    if m.shininess > 0.05 {
        p.circle_filled(c + egui::vec2(-16.0, -18.0), 4.0 + 8.0 * m.shininess as f32, egui::Color32::from_rgba_unmultiplied(255, 255, 255, (90.0 + 150.0 * m.shininess) as u8));
    }
    if m.opacity < 0.99 {
        p.text(r.right_bottom() - vec2(6.0, 6.0), egui::Align2::RIGHT_BOTTOM, format!("{:.0}% transparent", (1.0 - m.opacity) * 100.0), egui::FontId::proportional(10.0), style::text_dim());
    }
}

fn materials(app: &mut App, ctx: &egui::Context) {
    let Some(sel) = app.dialogs.materials.clone() else { return };
    let mut open = true;
    let mut sel = sel.or_else(|| app.doc.data.materials.first().map(|m| m.name.clone()));
    let mut change: Option<Material> = None;
    let mut create: Option<String> = None;
    let mut delete: Option<String> = None;
    window("Material Browser").open(&mut open).default_size(vec2(640.0, 460.0)).show(ctx, |ui| {
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.set_width(220.0);
                let key = egui::Id::new("mat-search");
                let mut search: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_default();
                ui.add(egui::TextEdit::singleline(&mut search).hint_text("Search").desired_width(210.0));
                ui.memory_mut(|m| m.data.insert_temp(key, search.clone()));
                egui::ScrollArea::vertical().max_height(340.0).id_salt("mat-list").show(ui, |ui| {
                    for m in &app.doc.data.materials {
                        if !search.is_empty() && !m.name.to_lowercase().contains(&search.to_lowercase()) {
                            continue;
                        }
                        ui.horizontal(|ui| {
                            let (r, _) = ui.allocate_exact_size(vec2(14.0, 14.0), egui::Sense::hover());
                            ui.painter().rect_filled(r, 2.0, egui::Color32::from_rgb(m.color[0], m.color[1], m.color[2]));
                            if ui.selectable_label(sel.as_deref() == Some(m.name.as_str()), &m.name).clicked() {
                                sel = Some(m.name.clone());
                            }
                        });
                    }
                });
                ui.horizontal(|ui| {
                    if ui.button("New").clicked() {
                        create = Some(String::new());
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Duplicate")).clicked() {
                        create = sel.clone();
                    }
                    if ui.add_enabled(sel.is_some(), egui::Button::new("Delete")).clicked() {
                        delete = sel.clone();
                    }
                });
            });
            ui.separator();
            ui.vertical(|ui| {
                let Some(m) = sel.as_ref().and_then(|n| app.doc.data.material(n)).cloned() else {
                    ui.label("Select a material.");
                    return;
                };
                let mut mm = m.clone();
                material_preview(ui, &m);
                egui::Grid::new("mat-props").num_columns(2).spacing(vec2(8.0, 4.0)).show(ui, |ui| {
                    ui.label(egui::RichText::new("Identity").strong());
                    ui.end_row();
                    ui.label("Name");
                    let key = egui::Id::new(("mat-name", &m.name));
                    let mut name: String = ui.memory(|me| me.data.get_temp(key)).unwrap_or_else(|| m.name.clone());
                    let r = ui.text_edit_singleline(&mut name);
                    if r.has_focus() {
                        ui.memory_mut(|me| me.data.insert_temp(key, name.clone()));
                    }
                    if r.lost_focus() {
                        ui.memory_mut(|me| me.data.remove::<String>(key));
                        mm.name = name;
                    }
                    ui.end_row();
                    ui.label("Class");
                    ui.text_edit_singleline(&mut mm.class);
                    ui.end_row();
                    ui.label(egui::RichText::new("Graphics").strong());
                    ui.end_row();
                    ui.label("Shading color");
                    ui.color_edit_button_srgb(&mut mm.color);
                    ui.end_row();
                    ui.label("Transparency");
                    let mut tr = (1.0 - mm.opacity) * 100.0;
                    ui.add(egui::Slider::new(&mut tr, 0.0..=100.0).suffix(" %"));
                    mm.opacity = 1.0 - tr / 100.0;
                    ui.end_row();
                    ui.label("Cut pattern");
                    egui::ComboBox::from_id_salt("mat-cut").selected_text(mm.cut_pattern.label()).show_ui(ui, |ui| {
                        for f in FillPattern::ALL {
                            ui.selectable_value(&mut mm.cut_pattern, f, f.label());
                        }
                    });
                    ui.end_row();
                    ui.label(egui::RichText::new("Appearance").strong());
                    ui.end_row();
                    ui.label("Glossiness");
                    ui.add(egui::Slider::new(&mut mm.shininess, 0.0..=1.0));
                    ui.end_row();
                });
                if format!("{mm:?}") != format!("{m:?}") {
                    change = Some(mm);
                }
            });
        });
    });
    if let Some(mm) = change {
        let old = sel.clone().unwrap_or_default();
        let new_name = mm.name.clone();
        if app
            .run("Edit Material", |p| {
                if new_name != old && p.material(&new_name).is_some() {
                    return Err(format!("A material named '{new_name}' already exists."));
                }
                if let Some(m) = p.materials.iter_mut().find(|m| m.name == old) {
                    *m = mm;
                }
                if new_name != old {
                    // Keep references working.
                    for t in &mut p.types {
                        for l in &mut t.layers {
                            if l.material == old {
                                l.material = new_name.clone();
                            }
                        }
                        for v in t.texts.values_mut() {
                            if *v == old {
                                *v = new_name.clone();
                            }
                        }
                    }
                    for f in &mut p.families {
                        for t in &mut f.types {
                            for v in t.values.values_mut() {
                                if *v == old {
                                    *v = new_name.clone();
                                }
                            }
                        }
                    }
                }
                Ok(())
            })
            .is_some()
        {
            sel = Some(new_name);
        }
    }
    if let Some(base) = create {
        let src = app.doc.data.material(&base).cloned();
        let name = rc_core::edit::unique_name(app.doc.data.materials.iter().map(|m| m.name.clone()), if base.is_empty() { "New Material" } else { &base });
        let n2 = name.clone();
        app.run("New Material", |p| {
            let mut m = src.unwrap_or(Material { name: String::new(), color: [200, 200, 200], opacity: 1.0, ..Default::default() });
            m.name = n2;
            p.materials.push(m);
            Ok(())
        });
        sel = Some(name);
    }
    if let Some(d) = delete {
        let used = app.doc.data.types.iter().any(|t| t.layers.iter().any(|l| l.material == d) || t.texts.values().any(|v| *v == d));
        if used {
            app.error(format!("'{d}' is used by types and cannot be deleted."));
        } else {
            app.run("Delete Material", |p| {
                p.materials.retain(|m| m.name != d);
                Ok(())
            });
            sel = None;
        }
    }
    app.dialogs.materials = if open { Some(sel) } else { None };
}

fn object_styles(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.object_styles {
        return;
    }
    let mut open = true;
    let mut styles = app.doc.data.object_styles.clone();
    let mut footer = super::Footer::None;
    super::session_begin(app, "object-styles");
    window("Object Styles").open(&mut open).default_size(vec2(620.0, 480.0)).show(ctx, |ui| {
        let tab_id = egui::Id::new("os-tab");
        let mut tab: u8 = ui.memory(|m| m.data.get_temp(tab_id)).unwrap_or(0);
        ui.horizontal(|ui| {
            ui.selectable_value(&mut tab, 0, "Model Objects");
            ui.selectable_value(&mut tab, 1, "Annotation Objects");
        });
        ui.memory_mut(|m| m.data.insert_temp(tab_id, tab));
        let cats: Vec<Category> = if tab == 0 { Category::MODEL.to_vec() } else { Category::ANNOTATION.to_vec() };
        egui::ScrollArea::vertical().max_height(380.0).show(ui, |ui| {
            egui::Grid::new("os-grid").num_columns(5).striped(true).spacing(vec2(10.0, 4.0)).show(ui, |ui| {
                for h in ["Category", "Projection", "Cut", "Line Color", "Line Pattern"] {
                    ui.label(egui::RichText::new(h).strong());
                }
                ui.end_row();
                for c in cats {
                    let mut s = styles.get(&c).copied().unwrap_or_default();
                    ui.label(c.label());
                    weight_combo(ui, ("os-p", c), &mut s.projection_weight);
                    weight_combo(ui, ("os-c", c), &mut s.cut_weight);
                    let mut on = s.color.is_some();
                    ui.horizontal(|ui| {
                        if ui.checkbox(&mut on, "").changed() {
                            s.color = if on { Some([0, 0, 0]) } else { None };
                        }
                        if let Some(col) = s.color.as_mut() {
                            ui.color_edit_button_srgb(col);
                        } else {
                            ui.label(egui::RichText::new("Default").color(style::text_dim()));
                        }
                    });
                    let pat_label = |p: Option<u8>| match p {
                        None => "Default",
                        Some(0) => "Solid",
                        Some(1) => "Dash",
                        Some(2) => "Dash dot",
                        _ => "Dot",
                    };
                    egui::ComboBox::from_id_salt(("os-pat", c)).selected_text(pat_label(s.pattern)).width(90.0).show_ui(ui, |ui| {
                        for p in [None, Some(0), Some(1), Some(2), Some(3)] {
                            ui.selectable_value(&mut s.pattern, p, pat_label(p));
                        }
                    });
                    ui.end_row();
                    if s == ObjectStyle::default() {
                        styles.remove(&c);
                    } else {
                        styles.insert(c, s);
                    }
                }
            });
        });
        footer = super::footer(ui, app, "object-styles", "Object Styles");
    });
    if footer == super::Footer::None && open {
        if styles != app.doc.data.object_styles {
            app.run("Object Styles", |p| {
                p.object_styles = styles;
                Ok(())
            });
        }
    }
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        super::session_cancel(app, "object-styles");
    }
    if !open {
        app.dialogs.object_styles = false;
    }
}

pub(super) fn weight_combo(ui: &mut egui::Ui, id: impl std::hash::Hash + std::fmt::Debug, w: &mut Option<f32>) {
    // Pen numbers 1-8 like most BIM tools, mapped to paper widths.
    const PENS: [f32; 8] = [0.1, 0.13, 0.18, 0.25, 0.35, 0.5, 0.7, 1.0];
    let label = |w: Option<f32>| match w {
        None => "Default".to_string(),
        Some(x) => PENS.iter().position(|p| (p - x).abs() < 1e-4).map(|i| format!("{} ({x} mm)", i + 1)).unwrap_or(format!("{x} mm")),
    };
    egui::ComboBox::from_id_salt(id).selected_text(label(*w)).width(100.0).show_ui(ui, |ui| {
        ui.selectable_value(w, None, "Default");
        for p in PENS {
            ui.selectable_value(w, Some(p), label(Some(p)));
        }
    });
}

fn snaps(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.snaps {
        return;
    }
    let mut open = true;
    window("Snaps").open(&mut open).resizable(false).show(ctx, |ui| {
        let s = &mut app.settings.snaps;
        ui.checkbox(&mut s.enabled, "Snaps On");
        ui.add_enabled_ui(s.enabled, |ui| {
            ui.group(|ui| {
                ui.label(egui::RichText::new("Dimension Snaps").strong());
                ui.checkbox(&mut s.length_increments, "Length dimension snap increments (adapt to zoom)");
                ui.checkbox(&mut s.angle_increments, "Angular dimension snap increments (adapt to zoom)");
            });
            ui.group(|ui| {
                ui.label(egui::RichText::new("Object Snaps").strong());
                egui::Grid::new("snap-grid").num_columns(3).show(ui, |ui| {
                    ui.checkbox(&mut s.endpoints, "Endpoints (SE)");
                    ui.checkbox(&mut s.midpoints, "Midpoints (SM)");
                    ui.checkbox(&mut s.nearest, "Nearest (SN)");
                    ui.end_row();
                    ui.checkbox(&mut s.intersections, "Intersections (SI)");
                    ui.checkbox(&mut s.centers, "Centers (SC)");
                    ui.checkbox(&mut s.perpendicular, "Perpendicular (SP)");
                    ui.end_row();
                    ui.checkbox(&mut s.tangents, "Tangents (ST)");
                    ui.checkbox(&mut s.quadrants, "Quadrants (SQ)");
                    ui.checkbox(&mut s.remote, "Alignment & extensions");
                    ui.end_row();
                });
            });
            if ui.button("Check All").clicked() {
                *s = crate::snap::SnapSettings::default();
            }
        });
        ui.label(egui::RichText::new("Temporary overrides while drawing: SE, SM, SN, SI, SC, SP, ST, SQ, SO (off), SZ (close).").color(style::text_dim()));
    });
    if !open {
        app.dialogs.snaps = false;
        app.settings_dirty = true;
    }
}

fn project_info(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.project_info {
        return;
    }
    let mut open = true;
    let mut info = app.doc.data.info.clone();
    let mut footer = super::Footer::None;
    super::session_begin(app, "project-info");
    window("Project Information").open(&mut open).default_width(420.0).show(ctx, |ui| {
        egui::Grid::new("pi").num_columns(2).striped(true).spacing(vec2(8.0, 4.0)).show(ui, |ui| {
            for (label, f) in [
                ("Organization Name", &mut info.organization),
                ("Author", &mut info.author),
                ("Project Issue Date", &mut info.issue_date),
                ("Project Status", &mut info.status),
                ("Client Name", &mut info.client),
                ("Project Address", &mut info.address),
                ("Project Name", &mut info.name),
                ("Project Number", &mut info.number),
            ] {
                ui.label(label);
                ui.add(egui::TextEdit::singleline(f).desired_width(260.0));
                ui.end_row();
            }
        });
        footer = super::footer(ui, app, "project-info", "Project Information");
    });
    if footer == super::Footer::None && open {
        if format!("{info:?}") != format!("{:?}", app.doc.data.info) {
            app.run("Project Information", |p| {
                p.info = info;
                Ok(())
            });
        }
    }
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        super::session_cancel(app, "project-info");
    }
    if !open {
        app.dialogs.project_info = false;
    }
}

fn units(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.units {
        return;
    }
    let mut open = true;
    let mut u = app.doc.data.units.clone();
    let mut footer = super::Footer::None;
    super::session_begin(app, "units");
    window("Project Units").open(&mut open).default_width(440.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("System:");
            if ui.selectable_label(u.system == UnitSystem::Metric, "Metric").clicked() {
                let mut m = rc_core::units::Units::metric();
                m.currency = u.currency.clone();
                u = m;
            }
            if ui.selectable_label(u.system == UnitSystem::Imperial, "Imperial").clicked() {
                let mut m = rc_core::units::Units::imperial();
                m.currency = u.currency.clone();
                u = m;
            }
        });
        egui::Grid::new("units").num_columns(3).striped(true).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
            ui.label(egui::RichText::new("Unit").strong());
            ui.label(egui::RichText::new("Format").strong());
            ui.label(egui::RichText::new("Example").strong());
            ui.end_row();
            ui.label("Length");
            ui.horizontal(|ui| {
                egui::ComboBox::from_id_salt("u-len").selected_text(u.length.label()).show_ui(ui, |ui| {
                    for l in LengthUnit::ALL {
                        ui.selectable_value(&mut u.length, l, l.label());
                    }
                });
                ui.label("Rounding:");
                let mut d = u.length_decimals as f64;
                ui.add(egui::DragValue::new(&mut d).range(0.0..=6.0).speed(0.1));
                u.length_decimals = d as u8;
                if matches!(u.length, LengthUnit::FeetFractionalInches | LengthUnit::FractionalInches) {
                    ui.label("1/");
                    egui::ComboBox::from_id_salt("u-frac").selected_text(u.fraction.to_string()).width(50.0).show_ui(ui, |ui| {
                        for f in [2, 4, 8, 16, 32, 64, 128, 256] {
                            ui.selectable_value(&mut u.fraction, f, f.to_string());
                        }
                    });
                }
            });
            ui.label(u.length(12345.678));
            ui.end_row();
            ui.label("Area");
            ui.horizontal(|ui| {
                egui::ComboBox::from_id_salt("u-area").selected_text(match u.area {
                    AreaUnit::SquareMeters => "Square meters",
                    AreaUnit::SquareFeet => "Square feet",
                }).show_ui(ui, |ui| {
                    ui.selectable_value(&mut u.area, AreaUnit::SquareMeters, "Square meters");
                    ui.selectable_value(&mut u.area, AreaUnit::SquareFeet, "Square feet");
                });
                ui.label("Rounding:");
                let mut d = u.area_decimals as f64;
                ui.add(egui::DragValue::new(&mut d).range(0.0..=6.0).speed(0.1));
                u.area_decimals = d as u8;
            });
            ui.label(u.area(23.456e6));
            ui.end_row();
            ui.label("Volume");
            egui::ComboBox::from_id_salt("u-vol").selected_text(match u.volume {
                VolumeUnit::CubicMeters => "Cubic meters",
                VolumeUnit::CubicFeet => "Cubic feet",
            }).show_ui(ui, |ui| {
                ui.selectable_value(&mut u.volume, VolumeUnit::CubicMeters, "Cubic meters");
                ui.selectable_value(&mut u.volume, VolumeUnit::CubicFeet, "Cubic feet");
            });
            ui.label(u.volume(12.5e9));
            ui.end_row();
            ui.label("Angle");
            ui.horizontal(|ui| {
                ui.label("Degrees, rounding:");
                let mut d = u.angle_decimals as f64;
                ui.add(egui::DragValue::new(&mut d).range(0.0..=6.0).speed(0.1));
                u.angle_decimals = d as u8;
            });
            ui.label(u.format(37.5, ParamKind::Angle));
            ui.end_row();
            ui.label("Currency");
            ui.add(egui::TextEdit::singleline(&mut u.currency).desired_width(60.0));
            ui.label(u.format(1234.5, ParamKind::Currency));
            ui.end_row();
        });
        footer = super::footer(ui, app, "units", "Project Units");
    });
    if footer == super::Footer::None && open {
        if format!("{u:?}") != format!("{:?}", app.doc.data.units) {
            app.run("Project Units", |p| {
                p.units = u;
                Ok(())
            });
        }
    }
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        super::session_cancel(app, "units");
    }
    if !open {
        app.dialogs.units = false;
    }
}

/// Everything Purge Unused can remove: (key, label).
fn purgeable(p: &Project) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for f in &p.families {
        if !p.instances().any(|(_, i)| i.family_id == f.id) {
            out.push((format!("F{}", f.id), format!("Family: {} ({})", f.name, f.category.label())));
        } else {
            for t in &f.types {
                if !p.instances().any(|(_, i)| i.type_id == t.id) && f.types.len() > 1 {
                    out.push((format!("T{}", t.id), format!("Type: {} : {}", f.name, t.name)));
                }
            }
        }
    }
    for t in &p.types {
        if !rc_core::edit::type_in_use(p, t.id) && p.types_of(t.category).count() > 1 {
            out.push((format!("T{}", t.id), format!("Type: {} : {}", t.family_name(), t.name)));
        }
    }
    for g in &p.group_types {
        if !p.elements.iter().any(|e| matches!(&e.kind, ElementKind::GroupInstance(gi) if gi.type_id == g.id)) {
            out.push((format!("G{}", g.id), format!("Group: {}", g.name)));
        }
    }
    let used: std::collections::HashSet<String> = p
        .types
        .iter()
        .flat_map(|t| t.layers.iter().map(|l| l.material.clone()).chain(t.texts.values().cloned()))
        .chain(p.families.iter().flat_map(|f| f.types.iter().flat_map(|t| t.values.values().cloned()).chain(f.params.iter().map(|x| x.default.clone()))))
        .collect();
    for m in &p.materials {
        if !used.contains(&m.name) && !matches!(m.name.as_str(), "Default" | "Glass") {
            out.push((format!("M{}", m.name), format!("Material: {}", m.name)));
        }
    }
    out
}

fn purge(app: &mut App, ctx: &egui::Context) {
    let Some(mut st) = app.dialogs.purge.clone() else { return };
    let items = purgeable(&app.doc.data);
    if !st.init {
        st.checked = items.iter().map(|i| i.0.clone()).collect();
        st.init = true;
    }
    let mut open = true;
    let mut go = false;
    window("Purge Unused").open(&mut open).default_size(vec2(460.0, 420.0)).show(ctx, |ui| {
        if items.is_empty() {
            ui.label("Nothing to purge: every family, type, group and material is in use.");
            return;
        }
        ui.label("Select the unused items to remove:");
        egui::ScrollArea::vertical().max_height(300.0).show(ui, |ui| {
            for (k, label) in &items {
                let mut on = st.checked.contains(k);
                if ui.checkbox(&mut on, label).changed() {
                    if on {
                        st.checked.insert(k.clone());
                    } else {
                        st.checked.remove(k);
                    }
                }
            }
        });
        ui.horizontal(|ui| {
            if ui.button("Check All").clicked() {
                st.checked = items.iter().map(|i| i.0.clone()).collect();
            }
            if ui.button("Check None").clicked() {
                st.checked.clear();
            }
            if ui.button("OK").clicked() {
                go = true;
            }
        });
    });
    if go {
        let keys = st.checked.clone();
        if let Some(n) = app.run("Purge Unused", |p| {
            let mut n = 0;
            for k in &keys {
                let (tag, rest) = k.split_at(1);
                match tag {
                    "F" => {
                        if let Ok(id) = rest.parse() {
                            rc_core::edit::delete_family(p, id)?;
                            n += 1;
                        }
                    }
                    "T" => {
                        if let Ok(id) = rest.parse() {
                            if rc_core::edit::delete_type(p, id).is_ok() {
                                n += 1;
                            }
                        }
                    }
                    "G" => {
                        if let Ok(id) = rest.parse::<Id>() {
                            p.group_types.retain(|g| g.id != id);
                            n += 1;
                        }
                    }
                    _ => {
                        p.materials.retain(|m| m.name != rest);
                        n += 1;
                    }
                }
            }
            Ok(n)
        }) {
            app.info(format!("Purged {n} item(s)."));
        }
        app.dialogs.purge = None;
        return;
    }
    app.dialogs.purge = if open { Some(st) } else { None };
}

fn phases(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.phases {
        return;
    }
    let mut open = true;
    let mut phases = app.doc.data.phases.clone();
    let mut add_after: Option<usize> = None;
    let mut remove: Option<usize> = None;
    window("Phasing").open(&mut open).default_width(460.0).show(ctx, |ui| {
        ui.label(egui::RichText::new("Project Phases").strong());
        ui.label(egui::RichText::new("PAST (earliest first) → FUTURE").color(style::text_dim()));
        egui::Grid::new("phases").num_columns(3).striped(true).show(ui, |ui| {
            for (k, ph) in phases.iter_mut().enumerate() {
                ui.label(format!("{}", k + 1));
                ui.text_edit_singleline(&mut ph.name);
                ui.horizontal(|ui| {
                    if ui.small_button("Insert After").clicked() {
                        add_after = Some(k);
                    }
                    if ui.small_button("Delete").clicked() {
                        remove = Some(k);
                    }
                });
                ui.end_row();
            }
        });
        ui.add_space(6.0);
        ui.label(egui::RichText::new("Phase Filters: Show All, Show Complete, Show New, Show Previous + New, Show Previous + Demo, Show Previous Phase (set per view in Properties).").color(style::text_dim()));
    });
    let mut changed = format!("{phases:?}") != format!("{:?}", app.doc.data.phases);
    if let Some(k) = add_after {
        let n = phases.len() + 1;
        let name = format!("Phase {n}");
        app.run("Add Phase", |p| {
            p.phases = phases.clone();
            let id = p.new_id();
            p.phases.insert(k + 1, Phase { id, name });
            Ok(())
        });
        changed = false;
    }
    if let Some(k) = remove {
        if phases.len() <= 1 {
            app.error("A project needs at least one phase.");
        } else {
            let pid = phases[k].id;
            app.run("Delete Phase", |p| {
                if p.elements.iter().any(|e| e.phase_created == Some(pid) || e.phase_demolished == Some(pid)) {
                    return Err("Elements are created or demolished in this phase.".into());
                }
                p.phases.retain(|x| x.id != pid);
                Ok(())
            });
        }
        changed = false;
    }
    if changed {
        app.run("Rename Phase", |p| {
            p.phases = phases;
            Ok(())
        });
    }
    if !open {
        app.dialogs.phases = false;
    }
}

fn design_options(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.design_options {
        return;
    }
    let mut open = true;
    let mut action: Option<Box<dyn FnOnce(&mut Project) -> Result<(), String>>> = None;
    let mut edit_option: Option<Option<Id>> = None;
    window("Design Options").open(&mut open).default_width(520.0).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Editing:");
            let p = &app.doc.data;
            let label = app.active_option.and_then(|o| p.option_sets.iter().find_map(|s| s.options.iter().find(|x| x.id == o).map(|x| format!("{} : {}", s.name, x.name)))).unwrap_or_else(|| "Main Model".into());
            ui.label(egui::RichText::new(label).strong());
            if app.active_option.is_some() && ui.button("Finish Editing").clicked() {
                edit_option = Some(None);
            }
        });
        ui.separator();
        let p = app.snapshot();
        for set in &p.option_sets {
            ui.group(|ui| {
                ui.horizontal(|ui| {
                    ui.label(egui::RichText::new(&set.name).strong());
                    let sid = set.id;
                    if ui.small_button("New Option").clicked() {
                        let n = set.options.len() + 1;
                        action = Some(Box::new(move |p| rc_core::edit::add_option(p, sid, &format!("Option {n}")).map(|_| ())));
                    }
                    if ui.small_button("Delete Set").clicked() {
                        action = Some(Box::new(move |p| {
                            let opts: Vec<Id> = p.option_sets.iter().find(|s| s.id == sid).map(|s| s.options.iter().map(|o| o.id).collect()).unwrap_or_default();
                            p.elements.retain(|e| !e.design_option.is_some_and(|o| opts.contains(&o)));
                            p.option_sets.retain(|s| s.id != sid);
                            Ok(())
                        }));
                    }
                });
                for o in &set.options {
                    ui.horizontal(|ui| {
                        ui.label(format!("{}{}", o.name, if o.primary { " (primary)" } else { "" }));
                        let oid = o.id;
                        if ui.small_button("Edit Selected").clicked() {
                            edit_option = Some(Some(oid));
                        }
                        if !o.primary && ui.small_button("Make Primary").clicked() {
                            action = Some(Box::new(move |p| rc_core::edit::make_primary(p, oid)));
                        }
                        if ui.small_button("Add Selection").clicked() {
                            let ids = app.selection.clone();
                            action = Some(Box::new(move |p| {
                                rc_core::edit::set_design_option(p, &ids, Some(oid));
                                Ok(())
                            }));
                        }
                    });
                }
            });
        }
        if ui.button("New Option Set").clicked() {
            let n = p.option_sets.len() + 1;
            action = Some(Box::new(move |p| {
                let s = rc_core::edit::add_option_set(p, &format!("Option Set {n}"));
                let _ = s;
                Ok(())
            }));
        }
        ui.label(egui::RichText::new("Elements created while an option is being edited belong to it. Views show primary options unless their properties choose otherwise.").color(style::text_dim()));
    });
    if let Some(a) = action {
        app.run("Design Options", a);
    }
    if let Some(e) = edit_option {
        app.active_option = e;
    }
    if !open {
        app.dialogs.design_options = false;
    }
}

fn sun(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.sun {
        return;
    }
    let mut open = true;
    let mut s = app.doc.data.sun.clone();
    let mut tn = app.doc.data.true_north;
    window("Sun Settings").open(&mut open).resizable(false).show(ctx, |ui| {
        egui::Grid::new("sun").num_columns(2).spacing(vec2(8.0, 4.0)).show(ui, |ui| {
            ui.label("Azimuth");
            ui.add(egui::Slider::new(&mut s.azimuth, 0.0..=360.0).suffix("°"));
            ui.end_row();
            ui.label("Altitude");
            ui.add(egui::Slider::new(&mut s.altitude, 1.0..=89.0).suffix("°"));
            ui.end_row();
            ui.label("Latitude");
            ui.add(egui::DragValue::new(&mut s.latitude).range(-90.0..=90.0).speed(0.1));
            ui.end_row();
            ui.label("Longitude");
            ui.add(egui::DragValue::new(&mut s.longitude).range(-180.0..=180.0).speed(0.1));
            ui.end_row();
            ui.label("Date (MM-DD)");
            ui.text_edit_singleline(&mut s.date);
            ui.end_row();
            ui.label("Time (HH:MM)");
            ui.text_edit_singleline(&mut s.time);
            ui.end_row();
            ui.label("Angle to True North");
            ui.add(egui::DragValue::new(&mut tn).range(-180.0..=180.0).speed(0.5).suffix("°"));
            ui.end_row();
        });
        if ui.button("Compute azimuth/altitude from date, time and latitude").clicked() {
            if let Some((az, alt)) = solar_position(&s) {
                s.azimuth = az;
                s.altitude = alt.max(1.0);
            }
        }
        ui.label(egui::RichText::new("Turn shadows on in a view with the View Control Bar.").color(style::text_dim()));
    });
    if format!("{s:?}") != format!("{:?}", app.doc.data.sun) || tn != app.doc.data.true_north {
        app.run("Sun Settings", |p| {
            p.sun = s;
            p.true_north = tn;
            Ok(())
        });
        app.scenes.clear();
    }
    if !open {
        app.dialogs.sun = false;
    }
}

/// Simple solar position (NOAA-style approximation) in degrees: (azimuth from north, altitude).
fn solar_position(s: &SunSettings) -> Option<(f64, f64)> {
    let (m, d) = s.date.split_once('-')?;
    let (hh, mm) = s.time.split_once(':')?;
    let (m, d, hh, mm): (u32, u32, f64, f64) = (m.trim().parse().ok()?, d.trim().parse().ok()?, hh.trim().parse().ok()?, mm.trim().parse().ok()?);
    let days = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    let n = days.get(m.saturating_sub(1) as usize)? + d;
    let decl = 23.44f64.to_radians() * ((360.0 / 365.0 * (n as f64 - 81.0)).to_radians()).sin();
    let solar_time = hh + mm / 60.0 + s.longitude / 15.0 - (s.longitude / 15.0).round();
    let hour_angle = ((solar_time - 12.0) * 15.0).to_radians();
    let lat = s.latitude.to_radians();
    let alt = (lat.sin() * decl.sin() + lat.cos() * decl.cos() * hour_angle.cos()).asin();
    let az = (decl.sin() - alt.sin() * lat.sin()) / (alt.cos() * lat.cos());
    let mut az = az.clamp(-1.0, 1.0).acos().to_degrees();
    if hour_angle > 0.0 {
        az = 360.0 - az;
    }
    Some((az, alt.to_degrees()))
}

fn links(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.links {
        return;
    }
    let mut open = true;
    let mut remove: Option<Id> = None;
    window("Manage Links").open(&mut open).default_width(460.0).show(ctx, |ui| {
        let cads: Vec<(Id, String, usize, Option<Id>)> = app.doc.data.elements.iter().filter_map(|e| match &e.kind {
            ElementKind::Cad(c) => Some((e.id, c.name.clone(), c.polylines.len(), e.view)),
            _ => None,
        }).collect();
        if cads.is_empty() {
            ui.label("No CAD drawings are linked. Use Insert > Link CAD.");
        }
        egui::Grid::new("links").num_columns(4).striped(true).show(ui, |ui| {
            for h in ["Link Name", "Curves", "View", ""] {
                ui.label(egui::RichText::new(h).strong());
            }
            ui.end_row();
            for (id, name, n, v) in cads {
                ui.label(name);
                ui.label(n.to_string());
                ui.label(v.and_then(|v| app.doc.data.view(v)).map(|v| v.name.clone()).unwrap_or_else(|| "All".into()));
                if ui.button("Remove").clicked() {
                    remove = Some(id);
                }
                ui.end_row();
            }
        });
    });
    if let Some(id) = remove {
        app.run("Remove Link", |p| rc_core::edit::delete_elements(p, &[id]).map(|_| ()));
    }
    if !open {
        app.dialogs.links = false;
    }
}

fn shortcuts(app: &mut App, ctx: &egui::Context) {
    let Some(mut search) = app.dialogs.shortcuts.clone() else { return };
    let mut open = true;
    window("Keyboard Shortcuts").open(&mut open).default_size(vec2(560.0, 520.0)).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("Search:");
            ui.text_edit_singleline(&mut search);
        });
        ui.label(egui::RichText::new("Type one or more key sequences separated by commas (for example: WA or WA,W1).").color(style::text_dim()));
        egui::ScrollArea::vertical().max_height(420.0).show(ui, |ui| {
            egui::Grid::new("ks").num_columns(3).striped(true).spacing(vec2(10.0, 3.0)).show(ui, |ui| {
                ui.label(egui::RichText::new("Command").strong());
                ui.label(egui::RichText::new("Shortcuts").strong());
                ui.label("");
                ui.end_row();
                for c in Cmd::ALL {
                    let info = c.info();
                    if !search.is_empty() && !info.label.to_lowercase().contains(&search.to_lowercase()) {
                        continue;
                    }
                    ui.label(info.label.replace('\n', " "));
                    let mut keys = app.settings.shortcuts.keys(*c);
                    if ui.add(egui::TextEdit::singleline(&mut keys).desired_width(90.0)).changed() {
                        app.settings.shortcuts.custom.insert(c.key_name(), keys.to_uppercase());
                        app.settings_dirty = true;
                    }
                    if app.settings.shortcuts.custom.contains_key(&c.key_name()) {
                        if ui.small_button("Reset").clicked() {
                            app.settings.shortcuts.custom.remove(&c.key_name());
                        }
                    } else {
                        ui.label("");
                    }
                    ui.end_row();
                }
            });
        });
    });
    app.dialogs.shortcuts = if open { Some(search) } else { None };
}
