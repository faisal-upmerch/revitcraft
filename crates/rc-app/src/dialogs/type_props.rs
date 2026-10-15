//! Type Properties (with Edit Assembly for compound walls, floors, roofs and ceilings).

use super::window;
use crate::app::App;
use crate::properties::types_for;
use crate::style;
use eframe::egui::{self, Color32, Rect, Sense, Stroke, vec2};
use rc_core::edit;
use rc_core::model::*;

pub fn show(app: &mut App, ctx: &egui::Context) {
    let Some(tid) = app.dialogs.type_props else { return };
    let p = app.snapshot();
    let cat = p.sys_type(tid).map(|t| t.category).or_else(|| p.family_type(tid).map(|(f, _)| f.category));
    let Some(cat) = cat else {
        app.dialogs.type_props = None;
        return;
    };
    let mut open = true;
    let mut switch_to: Option<Id> = None;
    let mut duplicate = false;
    let mut rename = false;
    let mut load = false;
    let mut footer = super::Footer::None;
    super::session_begin(app, "type-props");
    window("Type Properties").open(&mut open).default_size(vec2(440.0, 560.0)).show(ctx, |ui| {
        let list = types_for(&p, cat);
        let (fam, ty) = list.iter().find(|x| x.0 == tid).map(|x| (x.1.clone(), x.2.clone())).unwrap_or_default();
        egui::Grid::new("tp-head").num_columns(3).spacing(vec2(10.0, 6.0)).show(ui, |ui| {
            ui.label("Family:");
            egui::ComboBox::from_id_salt("tp-fam").selected_text(&fam).width(230.0).show_ui(ui, |ui| {
                let mut fams: Vec<&String> = list.iter().map(|x| &x.1).collect();
                fams.dedup();
                for f in fams {
                    if ui.selectable_label(*f == fam, f).clicked() {
                        switch_to = list.iter().find(|x| &x.1 == f).map(|x| x.0);
                    }
                }
            });
            if super::dlg_button(ui, "Load...", false, true) {
                load = true;
            }
            ui.end_row();
            ui.label("Type:");
            egui::ComboBox::from_id_salt("tp-type").selected_text(&ty).width(230.0).show_ui(ui, |ui| {
                for (id, f, t) in &list {
                    if *f == fam && ui.selectable_label(*id == tid, t).clicked() {
                        switch_to = Some(*id);
                    }
                }
            });
            if super::dlg_button(ui, "Duplicate...", false, true) {
                duplicate = true;
            }
            ui.end_row();
            ui.label("");
            ui.label("");
            if super::dlg_button(ui, "Rename...", false, true) {
                rename = true;
            }
            ui.end_row();
        });
        ui.add_space(6.0);
        ui.label("Type Parameters");
        // Parameter | Value table on a white field with grid lines, like the reference dialog.
        egui::Frame::new().fill(style::field()).stroke(egui::Stroke::new(1.0, egui::Color32::from_gray(170))).show(ui, |ui| {
            if !ui.is_sizing_pass() {
                ui.set_width(ui.available_width());
            }
            super::table_header(ui, &["Parameter", "Value"]);
            egui::ScrollArea::vertical().max_height(ui.ctx().content_rect().height() * 0.55).id_salt("tp-scroll").auto_shrink([false, true]).show(ui, |ui| {
                let v = ui.visuals_mut();
                v.widgets.inactive.bg_stroke = egui::Stroke::NONE;
                v.widgets.inactive.weak_bg_fill = egui::Color32::TRANSPARENT;
                v.widgets.inactive.bg_fill = egui::Color32::TRANSPARENT;
                if p.sys_type(tid).is_some() {
                    system_type(app, ui, tid);
                } else {
                    family_type(app, ui, tid);
                }
            });
        });
        footer = super::footer(ui, app, "type-props", "Type Properties");
    });
    if footer != super::Footer::None {
        open = false;
    } else if !open {
        // The close cross cancels, like Cancel.
        super::session_cancel(app, "type-props");
    }
    if load {
        crate::actions::exec(app, crate::commands::Cmd::LoadFamily);
    }
    if duplicate {
        let base = p.sys_type(tid).map(|t| t.name.clone()).or_else(|| p.family_type(tid).map(|(_, t)| t.name.clone())).unwrap_or_default();
        let name = edit::unique_name(types_for(&p, cat).into_iter().map(|x| x.2), &format!("{base} 2"));
        let is_sys = p.sys_type(tid).is_some();
        if let Some(n) = app.run("Duplicate Type", |pr| if is_sys { edit::duplicate_system_type(pr, tid, &name) } else { edit::duplicate_family_type(pr, tid, &name) }) {
            switch_to = Some(n);
            app.dialogs.rename_type = Some((n, name));
        }
    }
    if rename {
        let name = p.sys_type(tid).map(|t| t.name.clone()).or_else(|| p.family_type(tid).map(|(_, t)| t.name.clone())).unwrap_or_default();
        app.dialogs.rename_type = Some((tid, name));
    }
    if let Some(t) = switch_to {
        app.dialogs.type_props = Some(t);
    }
    if !open {
        app.dialogs.type_props = None;
        app.dialogs.type_props_assembly = false;
    }
    assembly(app, ctx);
}

fn label(ui: &mut egui::Ui, s: &str) {
    crate::properties::prop_label(ui, s, false);
}

fn system_type(app: &mut App, ui: &mut egui::Ui, tid: Id) {
    let Some(t) = app.doc.data.sys_type(tid).cloned() else { return };
    let mut nt = t.clone();
    let units = app.doc.data.units.clone();
    let has_layers = matches!(t.category, Category::Walls | Category::Floors | Category::Roofs | Category::Ceilings) && t.wall_kind != WallKind::Curtain && t.wall_kind != WallKind::Stacked;
    style::header(ui, "Construction");
    crate::properties::prop_grid(ui, "tp-construction").show(ui, |ui| {
        if has_layers {
            label(ui, "Structure");
            if crate::properties::edit_button(ui).clicked() {
                app.dialogs.type_props_assembly = true;
            }
            ui.end_row();
            label(ui, "Thickness");
            ui.label(units.length(t.thickness()));
            ui.end_row();
        }
        if t.category == Category::Walls {
            label(ui, "Function");
            egui::ComboBox::from_id_salt("tp-func").selected_text(nt.function.label()).icon(crate::properties::chevron).show_ui(ui, |ui| {
                for f in WallFunction::ALL {
                    ui.selectable_value(&mut nt.function, f, f.label());
                }
            });
            ui.end_row();
        }
        if t.wall_kind == WallKind::Stacked {
            label(ui, "Structure (bottom → top)");
            ui.vertical(|ui| {
                for (k, (wt, h)) in nt.stack.iter_mut().enumerate() {
                    ui.horizontal(|ui| {
                        let name = app.doc.data.sys_type(*wt).map(|x| x.name.clone()).unwrap_or_default();
                        egui::ComboBox::from_id_salt(("stack", k)).selected_text(name).width(170.0).icon(crate::properties::chevron).show_ui(ui, |ui| {
                            for b in app.doc.data.types_of(Category::Walls).filter(|b| b.wall_kind == WallKind::Basic) {
                                ui.selectable_value(wt, b.id, &b.name);
                            }
                        });
                        let mut s = if *h == 0.0 { "Variable".to_string() } else { units.length(*h) };
                        if ui.add(egui::TextEdit::singleline(&mut s).desired_width(80.0)).lost_focus() {
                            *h = units.parse(&s, ParamKind::Length).unwrap_or(0.0);
                        }
                    });
                }
            });
            ui.end_row();
        }
        // Kind-specific numeric properties (curtain spacing, stair risers, railing height...).
        for (k, v) in nt.props.iter_mut() {
            label(ui, k);
            let length_like = !matches!(k.as_str(), "Slope" | "Angle" | "Count" | "Panels");
            let key = egui::Id::new(("tp-prop", tid, k.clone()));
            let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| if length_like { units.length(*v) } else { format!("{v}") });
            let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(140.0));
            if r.has_focus() {
                ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
            }
            if r.lost_focus() {
                ui.memory_mut(|m| m.data.remove::<String>(key));
                let parsed = if length_like { units.parse(&s, ParamKind::Length) } else { s.trim().parse::<f64>().ok() };
                if let Some(x) = parsed {
                    *v = x;
                }
            }
            ui.end_row();
        }
        for (k, v) in nt.texts.iter_mut() {
            label(ui, k);
            if k.contains("Material") {
                egui::ComboBox::from_id_salt(("tp-text", k.clone())).selected_text(v.clone()).icon(crate::properties::chevron).show_ui(ui, |ui| {
                    for m in &app.doc.data.materials {
                        ui.selectable_value(v, m.name.clone(), &m.name);
                    }
                });
            } else {
                ui.text_edit_singleline(v);
            }
            ui.end_row();
        }
    });
    style::header(ui, "Identity Data");
    crate::properties::prop_grid(ui, "tp-identity").show(ui, |ui| {
        label(ui, "Type Mark");
        ui.text_edit_singleline(&mut nt.type_mark);
        ui.end_row();
        label(ui, "Description");
        ui.text_edit_singleline(&mut nt.description);
        ui.end_row();
        label(ui, "Cost");
        ui.add(egui::DragValue::new(&mut nt.cost).speed(1.0).prefix(format!("{} ", units.currency)));
        ui.end_row();
    });
    if format!("{nt:?}") != format!("{t:?}") {
        app.run("Type Properties", |p| {
            if let Some(x) = p.sys_type_mut(tid) {
                *x = nt;
            }
            Ok(())
        });
    }
}

fn family_type(app: &mut App, ui: &mut egui::Ui, tid: Id) {
    let Some((f, t)) = app.doc.data.family_type(tid).map(|(f, t)| (f.clone(), t.clone())) else { return };
    let r = rc_core::family_params::Resolver::for_type(&f, &t);
    let mut groups: Vec<(String, Vec<FamilyParameter>)> = Vec::new();
    for prm in f.params.iter().filter(|x| !x.instance) {
        match groups.iter_mut().find(|g| g.0 == prm.group) {
            Some(g) => g.1.push(prm.clone()),
            None => groups.push((prm.group.clone(), vec![prm.clone()])),
        }
    }
    let mut edits: Vec<(String, String)> = Vec::new();
    for (g, prms) in groups {
        style::header(ui, &g);
        crate::properties::prop_grid(ui, ("tp-fam", &g)).num_columns(3).show(ui, |ui| {
            for prm in prms {
                label(ui, &prm.name);
                let shown = r.display(&prm);
                if !prm.formula.is_empty() || prm.reporting {
                    ui.label(egui::RichText::new(shown).color(style::text_dim()));
                    ui.label(egui::RichText::new(format!("= {}", prm.formula)).color(style::text_dim()).italics());
                } else if prm.kind == ParamKind::YesNo {
                    let mut b = r.yes_no(&prm.name, false);
                    if crate::style::check(ui, &mut b, "").changed() {
                        edits.push((prm.name.clone(), if b { "Yes".into() } else { "No".into() }));
                    }
                    ui.label("");
                } else if prm.kind == ParamKind::Material {
                    let cur = r.text(&prm.name, "");
                    let mut v = cur.clone();
                    egui::ComboBox::from_id_salt(("tp-mat", &prm.name)).selected_text(&v).icon(crate::properties::chevron).show_ui(ui, |ui| {
                        for m in &app.doc.data.materials {
                            ui.selectable_value(&mut v, m.name.clone(), &m.name);
                        }
                    });
                    if v != cur {
                        edits.push((prm.name.clone(), v));
                    }
                    ui.label("");
                } else {
                    let key = egui::Id::new(("tp-fv", tid, prm.name.clone()));
                    let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| shown.clone());
                    let resp = ui.add(egui::TextEdit::singleline(&mut s).desired_width(140.0));
                    if resp.has_focus() {
                        ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
                    }
                    if resp.lost_focus() {
                        ui.memory_mut(|m| m.data.remove::<String>(key));
                        if s != shown {
                            edits.push((prm.name.clone(), s));
                        }
                    }
                    ui.label("");
                }
                ui.end_row();
            }
        });
    }
    if !edits.is_empty() {
        app.run("Type Properties", |p| {
            for (n, v) in &edits {
                edit::set_family_type_value(p, tid, n, v)?;
            }
            Ok(())
        });
    }
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        if ui.button("Edit Family...").clicked() {
            crate::family_editor::open(app, f.id);
        }
        ui.label(egui::RichText::new(format!("Template: {}", f.template.label())).color(style::text_dim()));
    });
}

/// Edit Assembly: the layer table of a compound type with a section preview.
fn assembly(app: &mut App, ctx: &egui::Context) {
    if !app.dialogs.type_props_assembly {
        return;
    }
    let Some(tid) = app.dialogs.type_props else { return };
    let Some(t) = app.doc.data.sys_type(tid).cloned() else {
        app.dialogs.type_props_assembly = false;
        return;
    };
    let mut layers = t.layers.clone();
    let units = app.doc.data.units.clone();
    let mut open = true;
    let mats: Vec<(String, [u8; 3])> = app.doc.data.materials.iter().map(|m| (m.name.clone(), m.color)).collect();
    let selected_key = egui::Id::new("asm-sel");
    window("Edit Assembly").default_pos(ctx.content_rect().center() + vec2(80.0, 60.0)).open(&mut open).default_size(vec2(720.0, 460.0)).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label(format!("Family: {}", t.family_name()));
            ui.separator();
            ui.label(format!("Type: {}", t.name));
            ui.separator();
            ui.label(format!("Total thickness: {}", units.length(layers.iter().map(|l| l.thickness).sum())));
        });
        let mut sel: usize = ui.memory(|m| m.data.get_temp(selected_key)).unwrap_or(0);
        ui.horizontal_top(|ui| {
            ui.vertical(|ui| {
                ui.label(egui::RichText::new(if t.category == Category::Walls { "Layers (EXTERIOR SIDE at top)" } else { "Layers (TOP at top)" }).strong());
                egui::Grid::new("asm").num_columns(5).striped(true).spacing(vec2(6.0, 3.0)).show(ui, |ui| {
                    for h in ["", "Function", "Material", "Thickness", "Core"] {
                        ui.label(egui::RichText::new(h).strong());
                    }
                    ui.end_row();
                    for (k, l) in layers.iter_mut().enumerate() {
                        if ui.selectable_label(sel == k, format!("{}", k + 1)).clicked() {
                            sel = k;
                        }
                        egui::ComboBox::from_id_salt(("asm-f", k)).selected_text(l.function.label()).width(140.0).icon(crate::properties::chevron).show_ui(ui, |ui| {
                            for f in LayerFunction::ALL {
                                ui.selectable_value(&mut l.function, f, f.label());
                            }
                        });
                        egui::ComboBox::from_id_salt(("asm-m", k)).selected_text(&l.material).width(170.0).icon(crate::properties::chevron).show_ui(ui, |ui| {
                            for (m, _) in &mats {
                                ui.selectable_value(&mut l.material, m.clone(), m);
                            }
                        });
                        let key = egui::Id::new(("asm-t", tid, k));
                        let mut s: String = ui.memory(|m| m.data.get_temp(key)).unwrap_or_else(|| units.length(l.thickness));
                        let r = ui.add(egui::TextEdit::singleline(&mut s).desired_width(80.0));
                        if r.has_focus() {
                            ui.memory_mut(|m| m.data.insert_temp(key, s.clone()));
                        }
                        if r.lost_focus() {
                            ui.memory_mut(|m| m.data.remove::<String>(key));
                            if let Some(v) = units.parse(&s, ParamKind::Length) {
                                l.thickness = v.max(0.0);
                            }
                        }
                        crate::style::check(ui, &mut l.core, "");
                        ui.end_row();
                    }
                });
                ui.horizontal(|ui| {
                    if ui.button("Insert").clicked() {
                        let at = (sel + 1).min(layers.len());
                        layers.insert(at, Layer { function: LayerFunction::Finish2, material: "Default".into(), thickness: 10.0, core: false });
                        sel = at;
                    }
                    if ui.add_enabled(layers.len() > 1, egui::Button::new("Delete")).clicked() && sel < layers.len() {
                        layers.remove(sel);
                        sel = sel.saturating_sub(1);
                    }
                    if ui.add_enabled(sel > 0, egui::Button::new("Up")).clicked() {
                        layers.swap(sel, sel - 1);
                        sel -= 1;
                    }
                    if ui.add_enabled(sel + 1 < layers.len(), egui::Button::new("Down")).clicked() {
                        layers.swap(sel, sel + 1);
                        sel += 1;
                    }
                });
            });
            ui.separator();
            // Section preview.
            ui.vertical(|ui| {
                ui.label(egui::RichText::new("Preview").strong());
                let (r, _) = ui.allocate_exact_size(vec2(180.0, 300.0), Sense::hover());
                let p = ui.painter();
                p.rect_filled(r, 0.0, Color32::WHITE);
                let total: f64 = layers.iter().map(|l| l.thickness).sum::<f64>().max(1.0);
                let mut y = r.top() + 20.0;
                let h_avail = r.height() - 40.0;
                for (k, l) in layers.iter().enumerate() {
                    let h = (l.thickness / total) as f32 * h_avail;
                    let col = mats.iter().find(|m| m.0 == l.material).map(|m| m.1).unwrap_or([200, 200, 200]);
                    let band = Rect::from_min_size(egui::pos2(r.left() + 20.0, y), vec2(r.width() - 40.0, h.max(1.0)));
                    p.rect_filled(band, 0.0, Color32::from_rgb(col[0], col[1], col[2]));
                    // Simple hatch to read like a section.
                    let mut x = band.left() - band.height();
                    while x < band.right() {
                        let a = egui::pos2(x.max(band.left()), band.bottom() - (x.max(band.left()) - x));
                        let b = egui::pos2((x + band.height()).min(band.right()), band.top() + ((x + band.height()) - (x + band.height()).min(band.right())));
                        if a.x < b.x {
                            p.line_segment([a, b], Stroke::new(0.6, Color32::from_rgba_unmultiplied(0, 0, 0, 60)));
                        }
                        x += 8.0;
                    }
                    p.rect_stroke(band, 0.0, Stroke::new(if k == sel { 2.0 } else { 0.8 }, if k == sel { style::SELECT } else { Color32::BLACK }), egui::StrokeKind::Middle);
                    if l.core {
                        p.line_segment([band.left_top() - vec2(10.0, 0.0), band.left_bottom() - vec2(10.0, 0.0)], Stroke::new(2.0, Color32::from_rgb(40, 140, 60)));
                    }
                    y += h;
                }
                p.text(r.center_top() + vec2(0.0, 8.0), egui::Align2::CENTER_CENTER, if t.category == Category::Walls { "Exterior" } else { "Top" }, egui::FontId::proportional(10.0), Color32::DARK_GRAY);
                p.text(r.center_bottom() - vec2(0.0, 8.0), egui::Align2::CENTER_CENTER, if t.category == Category::Walls { "Interior" } else { "Bottom" }, egui::FontId::proportional(10.0), Color32::DARK_GRAY);
            });
        });
        ui.memory_mut(|m| m.data.insert_temp(selected_key, sel));
        ui.label(egui::RichText::new("Green bars mark the core. Changes apply to every instance of this type.").color(style::text_dim()));
    });
    if format!("{layers:?}") != format!("{:?}", t.layers) {
        if layers.iter().map(|l| l.thickness).sum::<f64>() <= 0.0 {
            app.error("The assembly must have a thickness.");
        } else {
            app.run("Edit Assembly", |p| {
                if let Some(x) = p.sys_type_mut(tid) {
                    x.layers = layers;
                }
                Ok(())
            });
        }
    }
    if !open {
        app.dialogs.type_props_assembly = false;
    }
}
